import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:shared_preferences_platform_interface/method_channel_shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'home_config_restore_test.dart' show pumpHome;
import 'mobile_push_service_test.dart' as fixture;

const _providerCode = 'fixture-keystore-read-unavailable';
const _providerMessage = 'synthetic platform details: do not surface';
const _providerDetails = 'SYNTHETIC-SENSITIVE-MARKER';
const _credentialReadMessage =
    'Connection credentials could not be read safely.';
const _metadataReadMessage =
    'Saved connection metadata could not be read safely.';

PlatformException _readFailure() => PlatformException(
  code: _providerCode,
  message: _providerMessage,
  details: _providerDetails,
);

Future<Object?> _captureFailure(Future<void> Function() action) async {
  try {
    await action();
    return null;
  } catch (error) {
    return error;
  }
}

void _expectSanitized(Object? error, String message) {
  expect(error, isA<CredentialStorageException>());
  expect(error.toString(), message);
  for (final payload in [_providerCode, _providerMessage, _providerDetails]) {
    expect(error.toString(), isNot(contains(payload)));
  }
}

/// The production secure-store and preference adapters execute their real
/// MethodChannel codecs. Only the physical providers/native push are fixtures;
/// this is not Android Keystore or installed-device acceptance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const prefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late fixture.Fixture f;
  late ConnectionManager manager;
  late Map<String, String> secrets;
  late Map<String, Object> metadata;
  late List<String> secureCalls;
  late List<String> prefsCalls;
  int? failSecureReadAt;
  int? failPrefsReadAt;
  var secureReads = 0;
  var prefsReads = 0;
  Completer<void>? faultEntered;
  Completer<void>? releaseFault;

  Map<String, Object> copyMetadata() =>
      Map<String, Object>.from(jsonDecode(jsonEncode(metadata)) as Map);

  Future<void> throwReadFailure() async {
    faultEntered?.complete();
    if (releaseFault != null) await releaseFault!.future;
    throw _readFailure();
  }

  void resetObservations() {
    secureReads = 0;
    prefsReads = 0;
    secureCalls.clear();
    prefsCalls.clear();
    f.methods.clear();
  }

  ConnectionManager sibling() => ConnectionManager(
    manager.prefs,
    credentialStore: FlutterSecureCredentialStore(),
    nativePushSupported: true,
  );

  Future<void> expectSuccessor(SavedConnection connection) async {
    final next = sibling();
    await next.updateApiKey(connection.id, 'successor-key');
    final saved = (await next.loadConnectionsWithSecrets()).singleWhere(
      (c) => c.id == connection.id,
    );
    expect(saved.apiKey, 'successor-key');
    expect(
      secrets.values.map((v) => jsonDecode(v)['api_key']),
      contains('successor-key'),
    );
    expect(ConnectionMutationBarrier.isPending(connection.id), isFalse);
    expect(f.connectionChanges, isEmpty);
  }

  Future<void> operate(String operation, SavedConnection a) async {
    await switch (operation) {
      'add' => manager.saveConnection('C', 'c.invalid', 443, 'c-key'),
      'full' => manager.updateConnection(
        a.id,
        'new',
        a.host,
        a.port,
        'new-key',
      ),
      'key' => manager.updateApiKey(a.id, 'new-key'),
      'dashboard' => manager.updateDashboardAuth(
        a.id,
        username: '',
        password: '',
      ),
      'delete' => manager.deleteConnection(a.id),
      'merge' => manager.importConnections([a], replaceExisting: false),
      'replace' => manager.importConnections([], replaceExisting: true),
      'initialize' => manager.initialize(),
      'export' => manager.loadConnectionsWithSecrets(),
      'reset' => manager.resetConnections(),
      _ => throw ArgumentError.value(operation),
    };
  }

  setUp(() async {
    notificationPrefs.value = NotificationPrefs.defaults;
    f = fixture.Fixture();
    await f.setup();
    final originalPrefsStore = SharedPreferencesStorePlatform.instance;
    addTearDown(
      () => SharedPreferencesStorePlatform.instance = originalPrefsStore,
    );
    secrets = {};
    metadata = {
      for (final key in f.manager.prefs.getKeys())
        'flutter.$key': f.manager.prefs.get(key)!,
    };
    secureCalls = [];
    prefsCalls = [];
    failSecureReadAt = null;
    failPrefsReadAt = null;
    faultEntered = null;
    releaseFault = null;
    secureReads = 0;
    prefsReads = 0;
    messenger.setMockMethodCallHandler(secureChannel, (call) async {
      secureCalls.add(call.method);
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final key = args['key'] as String;
      switch (call.method) {
        case 'write':
          secrets[key] = args['value'] as String;
          return null;
        case 'delete':
          secrets.remove(key);
          return null;
        case 'read':
          if (++secureReads == failSecureReadAt) await throwReadFailure();
          return secrets[key];
        default:
          throw StateError(call.method);
      }
    });
    messenger.setMockMethodCallHandler(prefsChannel, (call) async {
      prefsCalls.add(call.method);
      switch (call.method) {
        case 'getAll':
        case 'getAllWithParameters':
          if (++prefsReads == failPrefsReadAt) await throwReadFailure();
          return copyMetadata();
        case 'setStringList':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          metadata[args['key'] as String] = List<String>.from(
            args['value'] as List,
          );
          return true;
        case 'remove':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          metadata.remove(args['key']);
          return true;
        default:
          throw StateError(call.method);
      }
    });
    SharedPreferencesStorePlatform.instance =
        MethodChannelSharedPreferencesStore();
    manager = ConnectionManager(
      f.manager.prefs,
      credentialStore: FlutterSecureCredentialStore(),
      nativePushSupported: true,
    );
    await manager.importConnections([f.connection], replaceExisting: true);
    await f.service.initialize(manager);
    expect(manager.getConnections().single.apiKey, f.connection.apiKey);
    resetObservations();
  });

  tearDown(() {
    f.close();
    messenger.setMockMethodCallHandler(secureChannel, null);
    messenger.setMockMethodCallHandler(prefsChannel, null);
  });

  for (final operation in [
    'add',
    'full',
    'key',
    'dashboard',
    'delete',
    'merge',
    'replace',
    'export',
  ]) {
    test('fresh credential read failure is sanitized for $operation', () async {
      final a = manager.getConnections().single;
      final metadataBefore = copyMetadata();
      final secretsBefore = Map<String, String>.of(secrets);
      f.seed(active: true);
      failSecureReadAt = 1;

      final error = await _captureFailure(() => operate(operation, a));

      expect(metadata, metadataBefore);
      expect(
        manager.prefs.getStringList('saved_connections'),
        metadataBefore['flutter.saved_connections'],
      );
      expect(secrets, secretsBefore);
      expect(secureCalls, ['read']);
      expect(prefsCalls, ['getAll']);
      expect(f.methods, isEmpty);
      expect(f.native['active'], isTrue);
      expect(f.connectionChanges, isEmpty);
      expect(ConnectionMutationBarrier.isPending(a.id), isFalse);
      // A warm cached credential must not turn failed physical I/O into success.
      expect(manager.getConnections().single.apiKey, a.apiKey);
      await expectSuccessor(a);
      _expectSanitized(error, _credentialReadMessage);
    });
  }

  for (final operation in [
    'add',
    'full',
    'key',
    'dashboard',
    'delete',
    'merge',
    'replace',
    'initialize',
    'export',
    'reset',
  ]) {
    test(
      'fresh preference reload failure is sanitized for $operation',
      () async {
        final a = manager.getConnections().single;
        final metadataBefore = copyMetadata();
        final secretsBefore = Map<String, String>.of(secrets);
        failPrefsReadAt = 1;

        final error = await _captureFailure(() => operate(operation, a));

        expect(metadata, metadataBefore);
        expect(secrets, secretsBefore);
        expect(secureCalls, isEmpty);
        expect(prefsCalls, ['getAll']);
        expect(f.methods, isEmpty);
        expect(ConnectionMutationBarrier.isPending(a.id), isFalse);
        await expectSuccessor(a);
        _expectSanitized(error, _metadataReadMessage);
      },
    );
  }

  for (final replace in [false, true]) {
    test('import replace=$replace sanitizes its later prior-credential read '
        'after BEGIN and releases both leases without writes', () async {
      final a = manager.getConnections().single;
      final b = SavedConnection(
        id: 'fixture-second-account',
        label: 'B',
        host: 'b.invalid',
        port: 443,
        apiKey: 'b-fixture-key',
      );
      await manager.importConnections([a, b], replaceExisting: false);
      f.seed(active: true);
      resetObservations();
      final metadataBefore = copyMetadata();
      final secretsBefore = Map<String, String>.of(secrets);
      final nativeCalls = <Map<String, dynamic>>[];
      f.afterCommand = (method, args) async {
        nativeCalls.add({'method': method, ...args});
      };
      // Two hydration reads, then prior A succeeds and prior B fails. In
      // replace mode B is removed; in merge mode it is an incoming account.
      failSecureReadAt = 4;

      final error = await _captureFailure(
        () => manager.importConnections([
          a.copyWith(apiKey: 'never-written'),
          if (!replace) b.copyWith(apiKey: 'also-never-written'),
        ], replaceExisting: replace),
      );

      expect(metadata, metadataBefore);
      expect(secrets, secretsBefore);
      expect(secureCalls, List.filled(4, 'read'));
      expect(nativeCalls.map((c) => c['method']), [
        'beginConnectionChange',
        'endConnectionChange',
      ]);
      expect(nativeCalls.first['connections'], unorderedEquals([a.id, b.id]));
      expect(nativeCalls.last['mutation'], nativeCalls.first['mutation']);
      expect(nativeCalls.last['connections'], nativeCalls.first['connections']);
      expect(f.connectionChanges, isEmpty);
      for (final id in [a.id, b.id]) {
        expect(ConnectionMutationBarrier.isPending(id), isFalse);
      }
      expect(f.native['enabled'], isFalse);
      expect(f.native['active'], isFalse);
      expect((f.native['revocations'] as List).single['connection'], a.id);
      f.restart();
      expect(f.native['enabled'], isFalse);
      await expectSuccessor(a);
      expect(
        (await sibling().loadConnectionsWithSecrets()).last.apiKey,
        b.apiKey,
      );
      _expectSanitized(error, _credentialReadMessage);
    });
  }

  for (final source in ['credential', 'preference']) {
    test(
      'held $source failure releases owned reload and queued same-ID epoch',
      () async {
        final a = manager.getConnections().single;
        final epochBefore = ConnectionMutationBarrier.capture(a.id);
        final metadataBefore = copyMetadata();
        final secretsBefore = Map<String, String>.of(secrets);
        if (source == 'credential') {
          failSecureReadAt = 1;
        } else {
          failPrefsReadAt = 1;
        }
        faultEntered = Completer<void>();
        releaseFault = Completer<void>();
        final failed = _captureFailure(
          () => manager.updateApiKey(a.id, 'rejected'),
        );
        await faultEntered!.future;
        final next = sibling();
        final successor = next.updateApiKey(a.id, 'queued-successor-key');
        final queuedEpoch = ConnectionMutationBarrier.capture(a.id);
        expect(queuedEpoch, isNot(same(epochBefore)));
        expect(ConnectionMutationBarrier.isPending(a.id), isTrue);
        // An independent native callback drains pending microtasks without sleeps.
        await f.changed();
        expect(prefsReads, 1);
        expect(secureReads, source == 'credential' ? 1 : 0);
        expect(metadata, metadataBefore);
        expect(secrets, secretsBefore);
        expect(f.methods, isNot(contains('beginConnectionChange')));
        releaseFault!.complete();
        final error = await failed;
        await successor;

        expect(ConnectionMutationBarrier.isPending(a.id), isFalse);
        // The successor's active native lease advances its queued epoch again.
        expect(ConnectionMutationBarrier.isCurrent(a.id, queuedEpoch), isFalse);
        expect(
          ConnectionMutationBarrier.isCurrent(
            a.id,
            ConnectionMutationBarrier.capture(a.id),
          ),
          isTrue,
        );
        expect(f.connectionChanges, isEmpty);
        expect(
          f.methods.where((m) => m == 'beginConnectionChange'),
          hasLength(1),
        );
        expect(
          f.methods.where((m) => m == 'endConnectionChange'),
          hasLength(1),
        );
        expect(
          (await next.loadConnectionsWithSecrets()).single.apiKey,
          'queued-successor-key',
        );
        _expectSanitized(
          error,
          source == 'credential'
              ? _credentialReadMessage
              : _metadataReadMessage,
        );
      },
    );
  }

  for (final afterEffect in [false, true]) {
    test('import prior-read failure retains idempotent END retry '
        'afterEffect=$afterEffect', () async {
      final a = manager.getConnections().single;
      final metadataBefore = copyMetadata();
      final secretsBefore = Map<String, String>.of(secrets);
      final ends = <Map<String, dynamic>>[];
      f.seed(active: true);
      var lostAck = false;
      f.afterCommand = (method, args) async {
        if (method == 'endConnectionChange') {
          ends.add(Map.of(args));
          if (afterEffect && !lostAck) {
            lostAck = true;
            throw _readFailure();
          }
        }
      };
      if (!afterEffect) f.failCommand = 'endConnectionChange';
      failSecureReadAt = 2;
      final error = await _captureFailure(
        () => manager.importConnections([a], replaceExisting: true),
      );

      expect(metadata, metadataBefore);
      expect(secrets, secretsBefore);
      expect(secureCalls, ['read', 'read']);
      expect(f.native['enabled'], isFalse);
      expect(f.connectionChanges, hasLength(afterEffect ? 0 : 1));
      expect(ConnectionMutationBarrier.isPending(a.id), isFalse);
      final replacement = sibling();
      await replacement.finishPendingMobilePushChanges();
      await replacement.finishPendingMobilePushChanges();
      expect(f.connectionChanges, isEmpty);
      expect(ends, hasLength(afterEffect ? 2 : 1));
      expect(
        ends.every((args) => args['mutation'] == ends.first['mutation']),
        isTrue,
      );
      expect(f.methods.where((m) => m == 'endConnectionChange'), hasLength(2));
      await expectSuccessor(a);
      _expectSanitized(
        error,
        'Native push account change could not be completed safely. Retry the connection change.',
      );
    });
  }

  for (final source in ['credential', 'preference']) {
    testWidgets(
      'real Home Delete shows safe feedback after $source read fails',
      (tester) async {
        await pumpHome(tester, manager);
        final a = manager.getConnections().single;
        final metadataBefore = copyMetadata();
        final secretsBefore = Map<String, String>.of(secrets);
        resetObservations();
        if (source == 'credential') {
          failSecureReadAt = 1;
        } else {
          failPrefsReadAt = 1;
        }
        final callback = tester
            .widget<PopupMenuButton<String>>(
              find.byType(PopupMenuButton<String>),
            )
            .onSelected!;
        final uncaught = await _captureFailure(() async {
          // Await the exact production callback, not a mock catching consumer.
          await (callback as dynamic)('delete');
        });
        await tester.pumpAndSettle();
        final feedbackVisible = find
            .text('The connection could not be deleted safely.')
            .evaluate()
            .isNotEmpty;
        final visibleText = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join('\n');
        expect(metadata, metadataBefore);
        expect(secrets, secretsBefore);
        expect(ConnectionMutationBarrier.isPending(a.id), isFalse);
        await expectSuccessor(a);
        await tester.pumpWidget(const SizedBox.shrink());

        expect(uncaught, isNull);
        expect(tester.takeException(), isNull);
        expect(feedbackVisible, isTrue);
        for (final payload in [
          _providerCode,
          _providerMessage,
          _providerDetails,
        ]) {
          expect(visibleText, isNot(contains(payload)));
        }
      },
    );
  }
}
