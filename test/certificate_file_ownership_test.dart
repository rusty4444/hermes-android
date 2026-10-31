import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/tls_client_factory.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/main.dart';
// Existing plugin seams; filesystem and certificate-enforcing HTTPS are real.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/mtls_fixture.dart';

const _sensitiveMarker = 'synthetic-provider-detail-not-for-ui';
const _pushChannel = MethodChannel(
  'com.hermesagent.hermes_android/mobile_push',
);
const _secureError = 'The connection could not be stored securely.';

class _WriteGate {
  final entered = Completer<void>();
  final release = Completer<void>();

  void open() {
    if (!release.isCompleted) release.complete();
  }
}

class _Secrets implements CredentialStore {
  final values = <String, String>{};
  _WriteGate? nextWrite;

  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    final gate = nextWrite;
    nextWrite = null;
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

enum _MetadataFault {
  none,
  lostAck,
  rollbackOutage,
  rollbackAndReadOutage,
  baselineReadOutage,
}

class _PhysicalPreferences extends InMemorySharedPreferencesStore {
  _PhysicalPreferences() : super.empty();
  _MetadataFault fault = _MetadataFault.none;
  int metadataAttempts = 0;
  bool failReads = false;

  void arm(_MetadataFault value) {
    fault = value;
    metadataAttempts = 0;
    failReads = value == _MetadataFault.baselineReadOutage;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (failReads) throw StateError(_sensitiveMarker);
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != 'flutter.saved_connections' ||
        fault == _MetadataFault.none ||
        fault == _MetadataFault.baselineReadOutage) {
      return super.setValue(type, key, value);
    }
    metadataAttempts++;
    if (metadataAttempts == 1) {
      await super.setValue(
        type,
        key,
        value,
      ); // Physical commit before ACK loss.
      if (fault == _MetadataFault.rollbackAndReadOutage) failReads = true;
      throw StateError(_sensitiveMarker);
    }
    if (fault == _MetadataFault.rollbackOutage ||
        fault == _MetadataFault.rollbackAndReadOutage) {
      throw StateError(_sensitiveMarker); // Rollback does not reach storage.
    }
    return super.setValue(type, key, value);
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.support);
  final Directory support;
  @override
  Future<String?> getApplicationSupportPath() async => support.path;
}

class _Picker extends FilePicker {
  final files = <PlatformFile>[];
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (allowMultiple) {
      final picked = List<PlatformFile>.of(files);
      files.clear();
      return FilePickerResult(picked);
    }
    return FilePickerResult([files.removeAt(0)]);
  }
}

class _ObservedCertificates extends ClientCertificateService {
  _ObservedCertificates(Directory support)
    : super(supportDirectory: () async => support);
  final restored = Completer<ClientCertificateConfig>();
  int collections = 0;

  @override
  Future<ClientCertificateConfig> restore({
    required String certificatePem,
    required String privateKeyPem,
    required String label,
    String? password,
  }) async {
    final config = await super.restore(
      certificatePem: certificatePem,
      privateKeyPem: privateKeyPem,
      label: label,
      password: password,
    );
    restored.complete(config);
    return config;
  }

  @override
  Future<void> deleteUnreferenced(Iterable<String> references) async {
    collections++;
    await super.deleteUnreferenced(references);
  }
}

class _NativeMutations {
  final begins = <String>[];
  final ends = <String>[];
  final active = <String>{};
  bool loseNextEndAck = false;
  _WriteGate? endGate;

  Future<Object?> call(MethodCall call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final token = args['mutation'] as String;
    if (call.method == 'beginConnectionChange') {
      begins.add(token);
      active.add(token);
    } else if (call.method == 'endConnectionChange') {
      ends.add(token);
      active.remove(token); // Physical native END, before its response.
      final gate = endGate;
      endGate = null;
      if (gate != null) {
        gate.entered.complete();
        await gate.release.future;
      }
      if (loseNextEndAck) {
        loseNextEndAck = false;
        throw PlatformException(code: _sensitiveMarker);
      }
    } else {
      throw StateError('Unexpected native method: ${call.method}');
    }
    return null;
  }
}

SavedConnection _account(String id, {int port = 443}) => SavedConnection(
  id: id,
  label: id,
  host: '127.0.0.1',
  port: port,
  useHttps: true,
  apiKey: 'synthetic-api',
);

Future<ClientCertificateConfig> _identity(
  ClientCertificateService certificates, {
  String label = 'original',
}) async => certificates.commit(
  await certificates.importPemPair(
    certificateBytes: await File(
      loopbackIdentity.certificatePemPath,
    ).readAsBytes(),
    privateKeyBytes: await File(
      loopbackIdentity.privateKeyPemPath,
    ).readAsBytes(),
    label: label,
  ),
);

Future<ConfigBackup> _backup(SavedConnection account) async => ConfigBackup(
  createdAt: DateTime.utc(2026),
  appVersion: 'certificate-ownership-test',
  connections: [account],
  preferences: {},
  clientCertificates: {
    account.id: ClientCertificateBackup(
      label: 'incoming',
      certificatePem: await File(
        loopbackIdentity.certificatePemPath,
      ).readAsString(),
      privateKeyPem: await File(
        loopbackIdentity.privateKeyPemPath,
      ).readAsString(),
    ),
  },
);

Future<MutualTlsFixture> _server() async {
  final fixture = MutualTlsFixture();
  await fixture.start((request) async {
    expect(request.headers.value('authorization'), 'Bearer synthetic-api');
    fixture.json(request, {'status': 'ok', 'data': [], 'has_more': false});
    await request.response.close();
  });
  return fixture;
}

Future<void> _expectFreshTls(
  ClientCertificateConfig identity,
  MutualTlsFixture fixture,
) async {
  expect(File(identity.certificatePemPath).existsSync(), isTrue);
  expect(File(identity.privateKeyPemPath).existsSync(), isTrue);
  final before = fixture.requests.length;
  await withLoopbackTrust(() async {
    final client = ApiClient(
      baseUrl: fixture.origin,
      apiKey: 'synthetic-api',
      clientCertificate: identity,
    );
    try {
      expect((await client.checkHealth()).isHealthy, isTrue);
    } finally {
      client.close();
    }
  });
  expect(fixture.requests.length, before + 2);
  expect(fixture.anonymousRequests, 0);
}

Future<List<Directory>> _permanentDirectories(Directory support) async {
  final root = Directory('${support.path}/client-certs');
  if (!root.existsSync()) return [];
  return (await root.list().toList())
      .whereType<Directory>()
      .where((directory) => !directory.path.endsWith('.staging'))
      .toList();
}

/// Joins the route's actual release callback, not merely a sibling collector
/// which can finish before that callback has even entered the saved-list queue.
class _EditorManager extends ConnectionManager {
  _EditorManager(
    super.prefs, {
    required super.credentialStore,
    required super.certificateFiles,
  }) : super(nativePushSupported: true);

  final _editorCleanup = Completer<void>();
  Future<void> get editorCleanup => _editorCleanup.future;

  @override
  Future<void> cleanupUnreferencedCertificates() async {
    await super.cleanupUnreferencedCertificates();
    if (!_editorCleanup.isCompleted) _editorCleanup.complete();
  }
}

class _Editor {
  _Editor(this.tester);
  final WidgetTester tester;
  late Directory support;
  late SharedPreferences prefs;
  late _PhysicalPreferences platform;
  late ClientCertificateService certificates;
  late _EditorManager manager;
  late SavedConnection account;
  late MutualTlsFixture fixture;
  final secrets = _Secrets();
  final native = _NativeMutations();
  final controller = GatewayTurnApplicationController();

  Future<void> open() async {
    support = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('certificate-editor-'),
    ))!;
    final oldPaths = PathProviderPlatform.instance;
    final oldPicker = FilePicker.platform;
    PathProviderPlatform.instance = _Paths(support);
    final picker = _Picker();
    FilePicker.platform = picker;
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      FilePicker.platform = oldPicker;
    });
    addTearDown(() async {
      if (support.existsSync()) await support.delete(recursive: true);
    });
    fixture = (await tester.runAsync(_server))!;
    addTearDown(fixture.close);
    addTearDown(controller.close);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    platform = _PhysicalPreferences();
    final oldPlatform = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() => SharedPreferencesStorePlatform.instance = oldPlatform);
    certificates = ClientCertificateService(
      supportDirectory: () async => support,
    );
    final seed = ConnectionManager(
      prefs,
      credentialStore: secrets,
      certificateFiles: certificates,
      nativePushSupported: false,
    );
    account = _account('editor-account', port: fixture.server.port);
    await seed.importConnections([account], replaceExisting: false);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pushChannel, native.call);
    manager = (await tester.runAsync(
      () async => _EditorManager(
        prefs,
        credentialStore: secrets,
        certificateFiles: certificates,
      ),
    ))!;
    addTearDown(() async {
      await manager.finishPendingMobilePushChanges();
      messenger.setMockMethodCallHandler(_pushChannel, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          connManager: manager,
          turnApplicationController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Connection'));
    await tester.pumpAndSettle();
    tester
        .widget<SwitchListTile>(
          find.byKey(const Key('connection_client_certificate_toggle')),
        )
        .onChanged!(true);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (final path in [
        loopbackIdentity.certificatePemPath,
        loopbackIdentity.privateKeyPemPath,
      ]) {
        final bytes = await File(path).readAsBytes();
        picker.files.add(
          PlatformFile(
            name: path.split('/').last,
            size: bytes.length,
            bytes: bytes,
          ),
        );
      }
    });
    // The single picker takes every queued file in one multi-pick: the lone
    // certificate stages first, then the key pairs with it.
    final dynamic callback = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('connection_client_certificate_pick')),
        )
        .onPressed;
    await tester.runAsync(() async => await callback());
    await tester.pumpAndSettle();
    expect(find.textContaining('Loaded:'), findsOneWidget);
  }

  Future<void> save() async {
    final dynamic callback = tester
        .widget<FilledButton>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed;
    await withLoopbackTrust(() async => await callback());
  }

  Future<void> disposeAndCollect() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => manager.editorCleanup);
    // Retain the independent collector check, after the route's own callback
    // is joined. Otherwise its late I/O can retain a dead fake-async zone and
    // poison the next editor's shared saved-list transaction.
    await tester.runAsync(manager.cleanupUnreferencedCertificates);
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker.platform = _Picker();

  for (final fault in _MetadataFault.values) {
    testWidgets('real editor physical metadata/rollback fault: $fault', (
      tester,
    ) async {
      final editor = _Editor(tester);
      await editor.open();
      editor.platform.arm(fault);
      await tester.runAsync(editor.save);
      await tester.pumpAndSettle();
      if (fault == _MetadataFault.none) {
        expect(find.byType(AlertDialog), findsNothing);
      } else {
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text(_secureError), findsOneWidget);
        expect(find.textContaining(_sensitiveMarker), findsNothing);
      }
      // Dismiss during an outage as well: unknown physical references must not
      // be treated as a cached rollback, including when the widget is gone.
      await editor.disposeAndCollect();
      final committed =
          fault == _MetadataFault.none ||
          fault == _MetadataFault.rollbackOutage ||
          fault == _MetadataFault.rollbackAndReadOutage;
      await tester.runAsync(() async {
        final directories = await _permanentDirectories(editor.support);
        expect(
          directories,
          hasLength(
            committed || fault == _MetadataFault.baselineReadOutage ? 1 : 0,
          ),
          reason:
              'unknown references retain files; proven rollback collects them',
        );
        editor.platform.failReads = false;
        editor.platform.fault = _MetadataFault.none;
        await editor.prefs.reload();
        final restarted = ConnectionManager(
          editor.prefs,
          credentialStore: editor.secrets,
          certificateFiles: editor.certificates,
          nativePushSupported: false,
        );
        final saved = (await restarted.loadConnectionsWithSecrets()).single;
        if (committed) {
          await _expectFreshTls(saved.clientCertificate!, editor.fixture);
        } else {
          expect(saved.clientCertificate, isNull);
        }
        // Unknown-only leftovers are collected once a fresh list proves them
        // unreferenced; native/storage errors are not converted to success.
        await restarted.cleanupUnreferencedCertificates();
        expect(
          await _permanentDirectories(editor.support),
          hasLength(committed ? 1 : 0),
        );
      });
      expect(editor.native.active, isEmpty);
      expect(ConnectionMutationBarrier.isPending(editor.account.id), isFalse);
      await tester.runAsync(editor.fixture.close);
      await editor.controller.close();
    });
  }

  testWidgets(
    'real editor retains identity through lost and held native END, replays exact token before successor',
    (tester) async {
      final editor = _Editor(tester);
      await editor.open();
      await tester.runAsync(() async {
        final gate = _WriteGate();
        addTearDown(gate.open);
        editor.native.endGate = gate;
        editor.native.loseNextEndAck = true;
        final saving = editor.save();
        await gate.entered.future;
        final directory = (await _permanentDirectories(editor.support)).single;
        expect(File('${directory.path}/private-key.pem').existsSync(), isTrue);
        expect(editor.native.active, isEmpty);
        expect(ConnectionMutationBarrier.isPending(editor.account.id), isTrue);
        final sibling = ConnectionManager(
          editor.prefs,
          credentialStore: editor.secrets,
          certificateFiles: editor.certificates,
          nativePushSupported: true,
        );
        final successor = sibling.updateApiKey(
          editor.account.id,
          'synthetic-api',
        );
        expect(editor.native.begins, hasLength(1));
        gate.open();
        await saving;
        await successor;
        expect(editor.native.ends, [
          editor.native.begins.first,
          editor.native.begins.first,
          editor.native.begins.last,
        ]);
        expect(editor.native.begins, hasLength(2));
        final saved = (await sibling.loadConnectionsWithSecrets()).single;
        await _expectFreshTls(saved.clientCertificate!, editor.fixture);
      });
      await tester.pumpAndSettle();
      expect(find.text(_secureError), findsOneWidget);
      expect(find.textContaining(_sensitiveMarker), findsNothing);
      await editor.disposeAndCollect();
      await tester.runAsync(() async {
        final saved =
            (await editor.manager.loadConnectionsWithSecrets()).single;
        await _expectFreshTls(saved.clientCertificate!, editor.fixture);
      });
      await tester.runAsync(editor.fixture.close);
      await editor.controller.close();
    },
  );

  testWidgets(
    'real editor staging and queued permanent identity survive unrelated removal GC',
    (tester) async {
      final editor = _Editor(tester);
      await editor.open();
      await tester.runAsync(() async {
        final unrelated = _account(
          'unrelated',
        ).copyWith(clientCertificate: await _identity(editor.certificates));
        final sibling = ConnectionManager(
          editor.prefs,
          credentialStore: editor.secrets,
          certificateFiles: editor.certificates,
          nativePushSupported: false,
        );
        await sibling.importConnections([unrelated], replaceExisting: false);
        // The import's GC also visits .staging while the real editor is open.
        final staging = Directory(
          '${editor.support.path}/client-certs/.staging',
        );
        expect(await staging.list().length, 1);
        final gate = _WriteGate();
        addTearDown(gate.open);
        editor.secrets.nextWrite = gate;
        final removal = sibling.updateConnection(
          unrelated.id,
          unrelated.label,
          'https://${unrelated.host}',
          unrelated.port,
          unrelated.apiKey,
          clearClientCertificate: true,
        );
        await gate.entered.future;
        // Observe actual commit/rename before the editor queues its manager save.
        final materialized = Completer<void>();
        final subscription = Directory('${editor.support.path}/client-certs')
            .watch()
            .listen((_) {
              if (_permanentCountSync(editor.support) == 2 &&
                  !materialized.isCompleted) {
                materialized.complete();
              }
            });
        try {
          final saving = editor.save();
          await materialized.future;
          expect(
            editor.native.begins,
            isEmpty,
            reason: 'editor manager is still queued',
          );
          gate.open();
          await removal;
          await saving;
        } finally {
          gate.open();
          await subscription.cancel();
        }
        final saved = (await editor.manager.loadConnectionsWithSecrets())
            .singleWhere((c) => c.id == editor.account.id);
        await _expectFreshTls(saved.clientCertificate!, editor.fixture);
        expect(
          File(unrelated.clientCertificate!.privateKeyPemPath).existsSync(),
          isFalse,
        );
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await editor.disposeAndCollect();
      await tester.runAsync(editor.fixture.close);
      await editor.controller.close();
    },
  );

  testWidgets(
    'cancelled real editor releases staged files without changing metadata',
    (tester) async {
      final editor = _Editor(tester);
      await editor.open();
      await editor.disposeAndCollect();
      await tester.runAsync(() async {
        expect(await _permanentDirectories(editor.support), isEmpty);
        final staging = Directory(
          '${editor.support.path}/client-certs/.staging',
        );
        expect(await staging.list().toList(), isEmpty);
        final saved =
            (await editor.manager.loadConnectionsWithSecrets()).single;
        expect(saved.clientCertificate, isNull);
      });
      expect(editor.native.begins, isEmpty);
      await tester.runAsync(editor.fixture.close);
      await editor.controller.close();
    },
  );

  testWidgets(
    'disposing real editor joins physically completed held END before releasing files',
    (tester) async {
      final editor = _Editor(tester);
      await editor.open();
      late _WriteGate gate;
      late Future<void> saving;
      await tester.runAsync(() async {
        gate = _WriteGate();
        addTearDown(gate.open);
        editor.native.endGate = gate;
        editor.native.loseNextEndAck = true;
        saving = editor.save();
        await gate.entered.future;
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        // This collector deliberately has no saved references. The admitted
        // save, not the disposed widget, must still own the materialized pair.
        await editor.certificates.deleteUnreferenced([]);
        expect(await _permanentDirectories(editor.support), hasLength(1));
        gate.open();
        await saving;
        await editor.manager.finishPendingMobilePushChanges();
        await editor.manager.editorCleanup;
        await editor.manager.cleanupUnreferencedCertificates();
        final saved =
            (await editor.manager.loadConnectionsWithSecrets()).single;
        await _expectFreshTls(saved.clientCertificate!, editor.fixture);
      });
      expect(editor.native.ends, [
        editor.native.begins.single,
        editor.native.begins.single,
      ]);
      expect(editor.native.active, isEmpty);
      expect(ConnectionMutationBarrier.isPending(editor.account.id), isFalse);
      await tester.runAsync(editor.fixture.close);
      await editor.controller.close();
    },
  );

  for (final sameId in [false, true]) {
    for (final rotate in [false, true]) {
      for (final overlap in [false, true]) {
        test(
          'public import sameId=$sameId rotation=$rotate queued=$overlap survives GC and fresh TLS',
          () async {
            final support = await Directory.systemTemp.createTemp(
              'certificate-import-',
            );
            addTearDown(() => support.delete(recursive: true));
            final collector = ClientCertificateService(
              supportDirectory: () async => support,
            );
            final importingFiles = _ObservedCertificates(support);
            SharedPreferences.setMockInitialValues({});
            final prefs = await SharedPreferences.getInstance();
            final secrets = _Secrets();
            ConnectionManager manager(ClientCertificateService files) =>
                ConnectionManager(
                  prefs,
                  credentialStore: secrets,
                  certificateFiles: files,
                  nativePushSupported: false,
                );
            final a = manager(collector);
            final b = manager(importingFiles);
            final fixture = await _server();
            addTearDown(fixture.close);
            final original = await _identity(collector);
            final account = _account(
              'account-a',
              port: fixture.server.port,
            ).copyWith(clientCertificate: original);
            await a.importConnections([account], replaceExisting: false);
            final replacement = rotate
                ? await _identity(collector, label: 'rotation')
                : null;
            final gate = _WriteGate();
            addTearDown(gate.open);
            if (overlap) secrets.nextWrite = gate;
            final removal = a.updateConnection(
              account.id,
              account.label,
              'https://${account.host}',
              account.port,
              account.apiKey,
              clientCertificate: replacement,
              clearClientCertificate: !rotate,
            );
            if (overlap) {
              await gate.entered.future;
            } else {
              await removal;
            }
            final incoming = _account(
              sameId ? account.id : 'account-b',
              port: fixture.server.port,
            );
            final service = ConfigBackupService(
              connectionManager: b,
              preferences: prefs,
              certificates: importingFiles,
            );
            final importing = service.import(
              await _backup(incoming),
              mode: ConfigImportMode.merge,
            );
            final materialized = await importingFiles.restored.future;
            expect(File(materialized.privateKeyPemPath).existsSync(), isTrue);
            if (overlap) {
              expect(ConnectionMutationBarrier.isPending(incoming.id), isTrue);
            }
            gate.open();
            await removal;
            await importing;
            await prefs.reload();
            final restarted = manager(collector);
            final saved = (await restarted.loadConnectionsWithSecrets())
                .singleWhere((c) => c.id == incoming.id);
            expect(saved.clientCertificate, materialized);
            await _expectFreshTls(saved.clientCertificate!, fixture);
            expect(File(original.privateKeyPemPath).existsSync(), isFalse);
            if (replacement != null) {
              expect(File(replacement.privateKeyPemPath).existsSync(), !sameId);
            }
            // Releasing an import lease does not exempt its files from later GC.
            await restarted.deleteConnection(incoming.id);
            expect(File(materialized.privateKeyPemPath).existsSync(), isFalse);
            expect(ConnectionMutationBarrier.isPending(incoming.id), isFalse);
          },
        );
      }
    }
  }

  test(
    'public backup import retains committed files and reports sanitized lost native END ACK',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'certificate-import-end-',
      );
      addTearDown(() => support.delete(recursive: true));
      final files = _ObservedCertificates(support);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secrets = _Secrets();
      final fixture = await _server();
      addTearDown(fixture.close);
      final account = _account('native-import', port: fixture.server.port);
      final seed = ConnectionManager(
        prefs,
        credentialStore: secrets,
        certificateFiles: files,
        nativePushSupported: false,
      );
      await seed.importConnections([account], replaceExisting: false);
      final native = _NativeMutations()..loseNextEndAck = true;
      final gate = _WriteGate();
      addTearDown(gate.open);
      native.endGate = gate;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_pushChannel, native.call);
      final manager = ConnectionManager(
        prefs,
        credentialStore: secrets,
        certificateFiles: files,
        nativePushSupported: true,
      );
      addTearDown(() async {
        await manager.finishPendingMobilePushChanges();
        messenger.setMockMethodCallHandler(_pushChannel, null);
      });
      final service = ConfigBackupService(
        connectionManager: manager,
        preferences: prefs,
        certificates: files,
      );
      final importing = service.import(
        await _backup(account),
        mode: ConfigImportMode.merge,
      );
      final failure = expectLater(
        importing,
        throwsA(
          isA<ConfigBackupException>().having(
            (error) => error.message,
            'sanitized native failure',
            'Native push account change could not be completed safely. Retry the connection change.',
          ),
        ),
      );
      final identity = await files.restored.future;
      await gate.entered.future;
      await files.deleteUnreferenced([]);
      expect(File(identity.privateKeyPemPath).existsSync(), isTrue);
      expect(ConnectionMutationBarrier.isPending(account.id), isTrue);
      gate.open();
      await failure;
      await manager.finishPendingMobilePushChanges();
      expect(native.ends, [native.begins.single, native.begins.single]);
      await prefs.reload();
      final saved = (await seed.loadConnectionsWithSecrets()).single;
      expect(saved.clientCertificate, identity);
      await _expectFreshTls(saved.clientCertificate!, fixture);
      expect(native.active, isEmpty);
      expect(ConnectionMutationBarrier.isPending(account.id), isFalse);
    },
  );

  test(
    'replaced identity releases are bounded and do not release another file owner',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'certificate-replaced-',
      );
      addTearDown(() => support.delete(recursive: true));
      final files = ClientCertificateService(
        supportDirectory: () async => support,
      );
      final first = ClientCertificateFileLease();
      final second = ClientCertificateFileLease();
      final identity = await first.run(() => _identity(files));
      expect(await second.run(() => files.commit(identity)), identity);
      first.releaseIdentity(identity);
      first.releaseIdentity(identity);
      await files.deleteUnreferenced([]);
      expect(File(identity.privateKeyPemPath).existsSync(), isTrue);
      await second.close();
      await files.deleteUnreferenced([]);
      expect(File(identity.privateKeyPemPath).existsSync(), isFalse);
      await first.close();
    },
  );

  test(
    'file leases join admitted work, are idempotent, and collect only abandoned identities',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'certificate-leases-',
      );
      addTearDown(() => support.delete(recursive: true));
      final files = ClientCertificateService(
        supportDirectory: () async => support,
      );
      final sibling = ClientCertificateService(
        supportDirectory: () async => support,
      );
      final abandoned = await _identity(files, label: 'abandoned');
      final first = ClientCertificateFileLease();
      final second = ClientCertificateFileLease();
      final gate = _WriteGate();
      addTearDown(gate.open);
      late ClientCertificateConfig staged;
      final work = first.run(() async {
        staged = await files.importPemPair(
          certificateBytes: await File(
            loopbackIdentity.certificatePemPath,
          ).readAsBytes(),
          privateKeyBytes: await File(
            loopbackIdentity.privateKeyPemPath,
          ).readAsBytes(),
          label: 'live stage',
        );
        gate.entered.complete();
        await gate.release.future;
        return second.run(() => files.commit(staged));
      });
      await gate.entered.future;
      var closed = false;
      final closing = first.close().then((_) => closed = true);
      await sibling.deleteUnreferenced([]);
      expect(closed, isFalse);
      expect(File(staged.privateKeyPemPath).existsSync(), isTrue);
      expect(File(abandoned.privateKeyPemPath).existsSync(), isFalse);
      gate.open();
      final permanent = await work;
      await closing;
      await first.close();
      await sibling.deleteUnreferenced([]);
      expect(File(permanent.privateKeyPemPath).existsSync(), isTrue);
      await second.close();
      await second.close();
      await sibling.deleteUnreferenced([]);
      expect(File(permanent.privateKeyPemPath).existsSync(), isFalse);
      await expectLater(first.run(() async {}), throwsStateError);
      expect(
        () => const TlsClientFactory().createRestClient(permanent),
        throwsA(anything),
      );
    },
  );
}

int _permanentCountSync(Directory support) =>
    Directory('${support.path}/client-certs')
        .listSync()
        .whereType<Directory>()
        .where((d) => !d.path.endsWith('.staging'))
        .length;
