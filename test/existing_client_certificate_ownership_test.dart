import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/main.dart';
// Existing platform seams; certificate files and verified HTTPS are real.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mtls_fixture.dart';

class _Secrets implements CredentialStore {
  final values = <String, String>{};

  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
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

Future<ClientCertificateConfig> _identity(
  ClientCertificateService files,
  String label,
) async => files.commit(
  await files.importPemPair(
    certificateBytes: await File(
      loopbackIdentity.certificatePemPath,
    ).readAsBytes(),
    privateKeyBytes: await File(
      loopbackIdentity.privateKeyPemPath,
    ).readAsBytes(),
    label: label,
  ),
);

void _expectFiles(ClientCertificateConfig identity, bool exist) {
  expect(File(identity.certificatePemPath).existsSync(), exist);
  expect(File(identity.privateKeyPemPath).existsSync(), exist);
}

class _ExistingEditor {
  _ExistingEditor(this.tester);

  final WidgetTester tester;
  final secrets = _Secrets();
  final controller = GatewayTurnApplicationController();
  final picker = _Picker();
  late final Completer<void> validationEntered;
  late final Completer<void> validationRelease;
  late Directory support;
  late SharedPreferences prefs;
  late MutualTlsFixture server;
  late ClientCertificateService files;
  late ConnectionManager manager;
  late SavedConnection account;
  late ClientCertificateConfig original;
  bool rejectFirstValidation = false;
  bool _firstSessions = true;

  ConnectionManager sibling({bool separateFiles = true}) => ConnectionManager(
    prefs,
    credentialStore: secrets,
    certificateFiles: separateFiles
        ? ClientCertificateService(supportDirectory: () async => support)
        : files,
    nativePushSupported: false,
  );

  Future<void> open({bool nativePushSupported = false}) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final oldPaths = PathProviderPlatform.instance;
    final oldPicker = FilePicker.platform;
    addTearDown(() async {
      releaseValidation();
      PathProviderPlatform.instance = oldPaths;
      FilePicker.platform = oldPicker;
      await server.close();
      await controller.close();
      if (support.existsSync()) await support.delete(recursive: true);
    });
    await tester.runAsync(() async {
      // A held real-network future must be created in the real async zone too.
      validationEntered = Completer<void>();
      validationRelease = Completer<void>();
      support = await Directory.systemTemp.createTemp('existing-certificate-');
      PathProviderPlatform.instance = _Paths(support);
      FilePicker.platform = picker;
      files = ClientCertificateService(supportDirectory: () async => support);
      original = await _identity(files, 'existing X');
      server = MutualTlsFixture();
      await server.start((request) async {
        expect(request.headers.value('authorization'), 'Bearer synthetic-api');
        expect(request.uri.path, anyOf('/health', '/api/sessions'));
        if (request.uri.path == '/api/sessions' && _firstSessions) {
          _firstSessions = false;
          validationEntered.complete();
          await validationRelease.future;
          if (rejectFirstValidation) {
            request.response.statusCode = HttpStatus.unauthorized;
          }
        }
        server.json(request, {'status': 'ok', 'data': [], 'has_more': false});
        await request.response.close();
      });
      account = SavedConnection(
        id: 'existing-account',
        label: 'Existing account',
        host: '127.0.0.1',
        port: server.server.port,
        apiKey: 'synthetic-api',
        useHttps: true,
        clientCertificate: original,
      );
      manager = sibling(separateFiles: false);
      await manager.importConnections([account], replaceExisting: false);
      if (nativePushSupported) {
        manager = ConnectionManager(
          prefs,
          credentialStore: secrets,
          certificateFiles: files,
          nativePushSupported: true,
        );
      }
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
    expect(find.textContaining('existing X'), findsOneWidget);
  }

  void releaseValidation() {
    if (!validationRelease.isCompleted) validationRelease.complete();
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

  Future<void> changeIdentity(
    ConnectionManager other,
    ClientCertificateConfig? replacement,
  ) => other.updateConnection(
    account.id,
    account.label,
    'https://${account.host}',
    account.port,
    account.apiKey,
    clientCertificate: replacement,
    clearClientCertificate: replacement == null,
  );

  Future<SavedConnection> reload() async {
    await prefs.reload();
    return (await sibling().loadConnectionsWithSecrets()).single;
  }

  Future<void> expectFreshTls(ClientCertificateConfig identity) async {
    _expectFiles(identity, true);
    final before = server.requests.length;
    await withLoopbackTrust(() async {
      final client = ApiClient(
        baseUrl: server.origin,
        apiKey: 'synthetic-api',
        clientCertificate: identity,
      );
      try {
        expect((await client.checkHealth()).isHealthy, isTrue);
      } finally {
        client.close();
      }
    });
    expect(server.requests.length, before + 2);
    expect(server.anonymousRequests, 0);
  }

  Future<void> disposeAndCollect() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(manager.cleanupUnreferencedCertificates);
    await tester.pumpAndSettle();
  }

  Future<void> pickReplacement() async {
    final dynamic remove = tester
        .widget<TextButton>(
          find.byKey(const Key('connection_client_certificate_remove')),
        )
        .onPressed;
    await tester.runAsync(() async => remove());
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
            name: 'replacement-${path.split('/').last}',
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
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker.platform = _Picker();

  for (final separateFiles in [false, true]) {
    for (final rotate in [false, true]) {
      testWidgets(
        'existing editor X survives authenticated validation with rotation=$rotate separateFiles=$separateFiles',
        (tester) async {
          final editor = _ExistingEditor(tester);
          await editor.open();
          await tester.runAsync(() async {
            final saving = editor.save();
            await editor.validationEntered.future;
            expect(editor.server.requests.map((r) => r.uri.path), [
              '/health',
              '/api/sessions',
            ]);
            final other = editor.sibling(separateFiles: separateFiles);
            final replacement = rotate
                ? await _identity(editor.files, 'replacement Y')
                : null;
            try {
              await editor.changeIdentity(other, replacement);
              final changed = await editor.reload();
              expect(changed.clientCertificate, replacement);
              if (replacement != null) {
                await editor.expectFreshTls(replacement);
              }
              _expectFiles(editor.original, true);
            } finally {
              editor.releaseValidation();
            }
            await saving;
            final saved = await editor.reload();
            expect(saved.clientCertificate, editor.original);
            await editor.expectFreshTls(saved.clientCertificate!);
            if (replacement != null) _expectFiles(replacement, false);
          });
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          await editor.disposeAndCollect();
          await tester.runAsync(() async {
            await editor.manager.deleteConnection(editor.account.id);
            _expectFiles(editor.original, false);
            expect(await editor.manager.loadConnectionsWithSecrets(), isEmpty);
            await editor.server.close();
          });
          await editor.controller.close();
        },
      );
    }
  }

  testWidgets(
    'existing selection is released by cancellation before any Save',
    (tester) async {
      final editor = _ExistingEditor(tester);
      await editor.open();
      await tester.runAsync(() async {
        await editor.changeIdentity(editor.sibling(), null);
        _expectFiles(editor.original, true);
      });
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await editor.disposeAndCollect();
      await tester.runAsync(() async {
        _expectFiles(editor.original, false);
        expect((await editor.reload()).clientCertificate, isNull);
        await editor.server.close();
      });
      await editor.controller.close();
    },
  );

  testWidgets('disposal joins held validation before releasing existing X', (
    tester,
  ) async {
    final editor = _ExistingEditor(tester);
    await editor.open();
    late Future<void> saving;
    await tester.runAsync(() async {
      saving = editor.save();
      await editor.validationEntered.future;
      await editor.changeIdentity(editor.sibling(), null);
      _expectFiles(editor.original, true);
    });
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await editor.manager.cleanupUnreferencedCertificates();
      _expectFiles(editor.original, true);
      editor.releaseValidation();
      await saving;
      await editor.manager.cleanupUnreferencedCertificates();
      _expectFiles(editor.original, false);
      expect((await editor.reload()).clientCertificate, isNull);
      await editor.server.close();
    });
    await tester.pumpAndSettle();
    await editor.controller.close();
  });

  testWidgets(
    'failed validation retains existing X through rotation and retry',
    (tester) async {
      final editor = _ExistingEditor(tester)..rejectFirstValidation = true;
      await editor.open();
      await tester.runAsync(() async {
        final saving = editor.save();
        await editor.validationEntered.future;
        try {
          final replacement = await _identity(editor.files, 'replacement Y');
          await editor.changeIdentity(editor.sibling(), replacement);
          expect((await editor.reload()).clientCertificate, replacement);
        } finally {
          editor.releaseValidation();
        }
        await saving;
        _expectFiles(editor.original, true);
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      editor.rejectFirstValidation = false;
      await tester.runAsync(editor.save);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await editor.disposeAndCollect();
      await tester.runAsync(() async {
        final saved = await editor.reload();
        expect(saved.clientCertificate, editor.original);
        await editor.expectFreshTls(saved.clientCertificate!);
        await editor.manager.deleteConnection(editor.account.id);
        _expectFiles(editor.original, false);
        await editor.server.close();
      });
      await editor.controller.close();
    },
  );

  testWidgets(
    'replacing existing X releases it while the unvalidated stage stays leased',
    (tester) async {
      final editor = _ExistingEditor(tester);
      await editor.open();
      await editor.pickReplacement();
      await tester.runAsync(() async {
        await editor.changeIdentity(editor.sibling(), null);
        _expectFiles(editor.original, false);
        final staged = (await Directory(
          '${editor.support.path}/client-certs/.staging',
        ).list().toList()).single;
        expect(File('${staged.path}/private-key.pem').existsSync(), isTrue);
        final saving = editor.save();
        await editor.validationEntered.future;
        // Retaining existing X must not prematurely commit its replacement.
        expect(Directory(staged.path).existsSync(), isTrue);
        editor.releaseValidation();
        await saving;
        final saved = await editor.reload();
        expect(saved.clientCertificate, isNot(editor.original));
        expect(saved.clientCertificate!.directoryPath, isNot(staged.path));
        expect(Directory(staged.path).existsSync(), isFalse);
        await editor.expectFreshTls(saved.clientCertificate!);
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await editor.disposeAndCollect();
      await tester.runAsync(() async {
        final saved = await editor.reload();
        await editor.manager.deleteConnection(editor.account.id);
        _expectFiles(saved.clientCertificate!, false);
        await editor.server.close();
      });
      await editor.controller.close();
    },
  );

  testWidgets(
    'existing X survives disposal during held lost END ACK and exact-token retry',
    (tester) async {
      const channel = MethodChannel(
        'com.hermesagent.hermes_android/mobile_push',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final begins = <String>[];
      final ends = <String>[];
      late Completer<void> endEntered;
      late Completer<void> endRelease;
      var loseEndAck = true;
      await tester.runAsync(() async {
        endEntered = Completer<void>();
        endRelease = Completer<void>();
      });
      messenger.setMockMethodCallHandler(channel, (call) async {
        final token = (call.arguments as Map)['mutation'] as String;
        if (call.method == 'beginConnectionChange') {
          begins.add(token);
        } else if (call.method == 'endConnectionChange') {
          ends.add(token);
          if (loseEndAck) {
            loseEndAck = false;
            endEntered.complete();
            await endRelease.future;
            throw PlatformException(code: 'synthetic lost END acknowledgement');
          }
        } else {
          throw StateError('Unexpected native method: ${call.method}');
        }
        return null;
      });
      final editor = _ExistingEditor(tester);
      await editor.open(nativePushSupported: true);
      addTearDown(() async {
        if (!endRelease.isCompleted) endRelease.complete();
        await editor.manager.finishPendingMobilePushChanges();
        messenger.setMockMethodCallHandler(channel, null);
      });
      late Future<void> saving;
      await tester.runAsync(() async {
        saving = editor.save();
        await editor.validationEntered.future;
        try {
          final replacement = await _identity(editor.files, 'replacement Y');
          await editor.changeIdentity(editor.sibling(), replacement);
        } finally {
          editor.releaseValidation();
        }
        await endEntered.future;
        expect(ConnectionMutationBarrier.isPending(editor.account.id), isTrue);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        // Even a collector with no references must respect the disposed
        // editor's admitted save until its physical END acknowledgement settles.
        await editor.files.deleteUnreferenced([]);
        _expectFiles(editor.original, true);
        endRelease.complete();
        await saving;
        final successor = ConnectionManager(
          editor.prefs,
          credentialStore: editor.secrets,
          certificateFiles: editor.files,
          nativePushSupported: true,
        );
        await successor.updateApiKey(editor.account.id, 'synthetic-api');
        expect(begins, hasLength(2));
        expect(ends, [begins.first, begins.first, begins.last]);
        expect(ConnectionMutationBarrier.isPending(editor.account.id), isFalse);
        final saved = await editor.reload();
        expect(saved.clientCertificate, editor.original);
        await editor.expectFreshTls(saved.clientCertificate!);
        await editor.sibling().deleteConnection(editor.account.id);
        _expectFiles(editor.original, false);
        await editor.server.close();
      });
      await tester.pumpAndSettle();
      await editor.controller.close();
    },
  );

  test(
    'existing path retention is bounded, shared and close joins admitted work',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'existing-path-lease-',
      );
      addTearDown(() => support.delete(recursive: true));
      final files = ClientCertificateService(
        supportDirectory: () async => support,
      );
      final identity = await _identity(files, 'existing');
      final first = ClientCertificateFileLease();
      final second = ClientCertificateFileLease();
      first.retainIdentity(identity);
      first.retainIdentity(identity);
      second.retainIdentity(identity);
      first.releaseIdentity(identity);
      first.releaseIdentity(identity);
      await first.close();
      await files.deleteUnreferenced([]);
      _expectFiles(identity, true);
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final work = second.run(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var closed = false;
      final closing = second.close().then((_) => closed = true);
      expect(() => second.retainIdentity(identity), throwsStateError);
      await files.deleteUnreferenced([]);
      expect(closed, isFalse);
      _expectFiles(identity, true);
      release.complete();
      await work;
      await closing;
      await second.close();
      await files.deleteUnreferenced([]);
      _expectFiles(identity, false);
      expect(() => second.retainIdentity(identity), throwsStateError);
    },
  );
}
