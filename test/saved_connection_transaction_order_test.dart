import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'independent_push_quality_edit_race_test.dart' as race;
import 'mobile_push_service_test.dart' as fixture;

class _CachedSecrets implements CredentialStore {
  _CachedSecrets(this.values);
  final Map<String, String> values;
  final cache = <String, String>{};
  race.WriteGate? nextWrite;
  @override
  String? readCached(String key) => cache[key];
  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    final gate = nextWrite;
    nextWrite = null;
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
      if (gate.fail) throw StateError('test-owned secure write failure');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    cache.remove(key);
  }
}

class _Preferences extends InMemorySharedPreferencesStore {
  _Preferences(super.data) : super.withData();
  race.WriteGate? nextRead;
  bool failNextWrite = false;
  @override
  Future<Map<String, Object>> getAll() async {
    final gate = nextRead;
    nextRead = null;
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
      if (gate.fail) throw StateError('provider-detail-must-not-escape');
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.saved_connections' && failNextWrite) {
      failNextWrite = false;
      // The platform persisted it but the acknowledgement was lost.
      await super.setValue(valueType, key, value);
      throw StateError('provider-detail-must-not-escape');
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Fixture f;
  late race.GatedSecrets secrets;
  late ConnectionManager first;
  late ConnectionManager second;
  late SavedConnection a;
  final transcript = <Map<String, dynamic>>[];
  var scenario = '';
  var sequence = 0;

  setUp(() async {
    transcript.clear();
    sequence = 0;
    scenario = 'credential ordering';
    notificationPrefs.value = NotificationPrefs.defaults;
    f = fixture.Fixture();
    await f.setup();
    secrets = race.GatedSecrets();
    first = ConnectionManager(
      f.manager.prefs,
      credentialStore: secrets,
      nativePushSupported: true,
    );
    second = ConnectionManager(
      first.prefs,
      credentialStore: secrets,
      nativePushSupported: true,
    );
    await first.importConnections([f.connection], replaceExisting: true);
    a = first.getConnections().single;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final previousHandler = messenger.allMessagesHandler;
    messenger.allMessagesHandler = (channel, handler, message) async {
      final observing = channel == MobilePushService.channelName;
      final call = observing
          ? const StandardMethodCodec().decodeMethodCall(message!)
          : null;
      final index = ++sequence;
      if (call != null) {
        transcript.add({
          'sequence': index,
          'phase': 'call',
          'method': call.method,
          'arguments': call.arguments,
          'saved': first.prefs.getStringList('saved_connections'),
        });
      }
      final reply = await (previousHandler != null
          ? previousHandler(channel, handler, message)
          : handler != null
          ? handler(message)
          : messenger.delegate.send(channel, message));
      if (call != null) {
        transcript.add({
          'sequence': index,
          'phase': 'reply',
          'method': call.method,
          'native_fixture': f.clone(f.native),
        });
      }
      return reply;
    };
    addTearDown(() async {
      messenger.allMessagesHandler = previousHandler;
      final output = Platform.environment['PUSH_TRANSACTION_TRANSCRIPT'];
      if (output != null) {
        await File(output).writeAsString(
          '${jsonEncode({'scenario': scenario, 'seam': 'Test-owned native/HTTP fixture; exact production MethodChannel transcript, not sealed-store evidence', 'messages': transcript})}\n',
          mode: FileMode.append,
          flush: true,
        );
      }
    });
    await f.service.initialize(second);
    f.methods.clear();
  });
  tearDown(() => f.close());

  _Preferences usePreferences() {
    final previous = SharedPreferencesStorePlatform.instance;
    final store = _Preferences({
      for (final key in first.prefs.getKeys())
        'flutter.$key': first.prefs.get(key)!,
    });
    SharedPreferencesStorePlatform.instance = store;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    return store;
  }

  for (final operation in ['update', 'merge import', 'replacement import']) {
    test('$operation cannot erase C created by a second manager', () async {
      scenario = '$operation queued-create C';
      final gate = race.WriteGate();
      secrets.gates.add(gate);
      final editing = operation == 'update'
          ? first.updateApiKey(a.id, 'updated-a-key')
          : first.importConnections([
              a.copyWith(apiKey: 'updated-a-key'),
            ], replaceExisting: operation == 'replacement import');
      await gate.entered.future;
      final creating = second.saveConnection(
        'C',
        a.host,
        a.port,
        'independent-c-key',
        dashboardPrefix: a.dashboardPrefix,
        dashboardUsername: a.dashboardUsername,
        dashboardPassword: a.dashboardPassword,
        gatewayProfile: 'independent-c-profile',
      );
      var created = false;
      final creation = creating.then((_) => created = true);
      // Drain all runnable callbacks while A's physical credential write stays
      // held. A serialized implementation queues C; a rebasing implementation
      // may finish it, but must then preserve it or revoke before removal.
      await Future<void>.delayed(Duration.zero);
      SavedConnection? c;
      if (created) {
        c = second.getConnections().singleWhere((c) => c.id != a.id);
        await f.service.enable(c, 'test.distributor', ['durable-session']);
        f.native.addAll({
          'endpoint': 'https://distributor.invalid/c',
          'keys': {'p256dh': 'fixture', 'auth': 'fixture'},
        });
        f.challenge();
        await f.changed();
        expect(f.native['active'], isTrue);
      }
      gate.release.complete();
      await editing;
      await creation;
      c ??= second.getConnections().singleWhere((c) => c.id != a.id);
      final savedIds = first.getConnections().map((c) => c.id).toSet();
      if (!savedIds.contains(c.id)) {
        expect(
          f.native['active'],
          isFalse,
          reason: 'An actually removed C must be natively revoked',
        );
        expect(
          f.native['revocations'],
          contains(containsPair('connection', c.id)),
        );
      } else {
        final saved = await first.loadConnectionsWithSecrets();
        expect(
          saved.singleWhere((row) => row.id == c!.id).apiKey,
          'independent-c-key',
        );
        if (f.native['active'] != true) {
          await f.service.enable(c, 'test.distributor', ['durable-session']);
          f.native.addAll({
            'endpoint': 'https://distributor.invalid/c',
            'keys': {'p256dh': 'fixture', 'auth': 'fixture'},
          });
          f.challenge();
          await f.changed();
        }
        expect(f.native['active'], isTrue);
        expect(f.native['connection'], c.id);
      }
      // No refresh/replacement controller can repair an orphaned sealed state.
      f.restart(); // Dispose without initializing/refreshing a replacement.
      expect(
        f.native['active'] != true || savedIds.contains(f.native['connection']),
        isTrue,
      );
      expect(
        first.getConnections().singleWhere((c) => c.id == a.id).apiKey,
        'updated-a-key',
      );
    });
  }

  test(
    'replacement owns current removal set and revokes active C before writes',
    () async {
      scenario = 'replacement removes active C';
      await second.saveConnection(
        'C',
        a.host,
        a.port,
        'independent-c-key',
        dashboardPrefix: a.dashboardPrefix,
        dashboardUsername: a.dashboardUsername,
        dashboardPassword: a.dashboardPassword,
        gatewayProfile: 'independent-c-profile',
      );
      final c = second.getConnections().first;
      await f.service.enable(c, 'test.distributor', ['durable-session']);
      f.native.addAll({
        'endpoint': 'https://distributor.invalid/c',
        'keys': {'p256dh': 'fixture', 'auth': 'fixture'},
      });
      f.challenge();
      await f.changed();
      expect(f.native['active'], isTrue);
      final gate = race.WriteGate();
      secrets.gates.add(gate);
      final replacing = first.importConnections([a], replaceExisting: true);
      await gate.entered.future;
      try {
        expect(f.native['active'], isFalse);
        expect(f.connectionChanges.values.single, {a.id, c.id});
        expect(first.getConnections().map((c) => c.id), contains(c.id));
      } finally {
        gate.release.complete();
        await replacing;
      }
      f.restart(); // No initialization/refresh repairs the native snapshot.
      expect(first.getConnections().map((c) => c.id), [a.id]);
      expect(f.native['active'], isFalse);
      expect(
        f.native['revocations'],
        contains(containsPair('connection', c.id)),
      );
      expect(jsonEncode(secrets.values), isNot(contains('independent-c-key')));
    },
  );

  test(
    'queued partial edits read fresh credentials, never another manager cache',
    () async {
      final gate = race.WriteGate();
      secrets.gates.add(gate);
      final editing = first.updateApiKey(a.id, 'new-a-api-key');
      await gate.entered.future;
      final auth = second.updateDashboardAuth(
        a.id,
        username: 'fixture-user',
        password: 'new-dashboard-password',
      );
      gate.release.complete();
      await Future.wait([editing, auth]);
      final saved = (await second.loadConnectionsWithSecrets()).single;
      expect(saved.apiKey, 'new-a-api-key');
      expect(saved.dashboardPassword, 'new-dashboard-password');
    },
  );

  for (final operation in ['add', 'remove']) {
    test('held $operation cannot overwrite another manager create', () async {
      final gate = race.WriteGate();
      secrets.gates.add(gate);
      final changing = operation == 'add'
          ? first.saveConnection('B', a.host, a.port, 'independent-b-key')
          : first.deleteConnection(a.id);
      await gate.entered.future;
      final creating = second.saveConnection(
        'C',
        a.host,
        a.port,
        'independent-c-key',
      );
      await Future<void>.delayed(Duration.zero);
      gate.release.complete();
      await changing;
      await creating;
      await first.prefs.reload();
      final saved = await first.loadConnectionsWithSecrets();
      expect(
        saved.singleWhere((c) => c.label == 'C').apiKey,
        'independent-c-key',
      );
      if (operation == 'add') {
        expect(saved.map((c) => c.id), contains(a.id));
        expect(
          saved.singleWhere((c) => c.label == 'B').apiKey,
          'independent-b-key',
        );
      } else {
        expect(saved.map((c) => c.id), isNot(contains(a.id)));
        expect(saved, hasLength(1));
        expect(jsonEncode(secrets.values), isNot(contains(a.apiKey)));
      }
    });
  }

  test(
    'queued replacement discovers C added since invocation and revokes it',
    () async {
      scenario = 'queued replacement discovers active C';
      final store = usePreferences();
      final write = race.WriteGate();
      secrets.gates.add(write);
      final editing = first.updateApiKey(a.id, 'updated-a-key');
      await write.entered.future;
      final creating = second.saveConnection(
        'C',
        a.host,
        a.port,
        'independent-c-key',
        dashboardPrefix: a.dashboardPrefix,
        dashboardUsername: a.dashboardUsername,
        dashboardPassword: a.dashboardPassword,
        gatewayProfile: 'independent-c-profile',
      );
      final reload = race.WriteGate();
      f.afterCommand = (method, _) async {
        if (method == 'endConnectionChange' &&
            first.getConnections().any((c) => c.label == 'C')) {
          store.nextRead = reload;
          f.afterCommand = null;
        }
      };
      // C is not in this invocation's snapshot. Discover it from the owned
      // current list rather than silently removing it with an obsolete ID set.
      final replacing = first.importConnections([a], replaceExisting: true);
      write.release.complete();
      await editing;
      await creating;
      await reload.entered.future;
      try {
        final c = second.getConnections().first;
        await f.service.enable(c, 'test.distributor', ['durable-session']);
        f.native.addAll({
          'endpoint': 'https://distributor.invalid/c',
          'keys': {'p256dh': 'fixture', 'auth': 'fixture'},
        });
        f.challenge();
        await f.changed();
        expect(f.native['active'], isTrue);
        expect(f.native['connection'], c.id);
      } finally {
        reload.release.complete();
        await replacing;
      }
      f.restart();
      expect(first.getConnections().map((c) => c.id), [a.id]);
      expect(f.native['active'], isFalse);
      final begin = transcript
          .where(
            (e) =>
                e['phase'] == 'call' && e['method'] == 'beginConnectionChange',
          )
          .last;
      expect((begin['arguments'] as Map)['connections'], hasLength(2));
    },
  );

  test(
    'failed metadata commit rolls back before queued unrelated create',
    () async {
      final store = usePreferences();
      final gate = race.WriteGate();
      secrets.gates.add(gate);
      final editing = first.updateConnection(
        a.id,
        'Rejected',
        'changed.invalid',
        a.port,
        'rejected-key',
      );
      final failed = expectLater(
        editing,
        throwsA(isA<CredentialStorageException>()),
      );
      await gate.entered.future;
      final creating = second.saveConnection(
        'C',
        a.host,
        a.port,
        'independent-c-key',
      );
      store.failNextWrite = true;
      gate.release.complete();
      await failed;
      await creating;
      await first.prefs.reload();
      final saved = await first.loadConnectionsWithSecrets();
      expect(saved.singleWhere((c) => c.id == a.id).host, a.host);
      expect(saved.singleWhere((c) => c.id == a.id).apiKey, a.apiKey);
      expect(
        saved.singleWhere((c) => c.label == 'C').apiKey,
        'independent-c-key',
      );
      expect(f.connectionChanges, isEmpty);
    },
  );

  test(
    'failed prerequisite reload releases queued owner with a safe error',
    () async {
      final store = usePreferences();
      final gate = race.WriteGate()..fail = true;
      store.nextRead = gate;
      final editing = first.updateApiKey(a.id, 'rejected-key');
      final failed = expectLater(
        editing,
        throwsA(
          isA<CredentialStorageException>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('provider-detail')),
          ),
        ),
      );
      await gate.entered.future;
      final auth = second.updateDashboardAuth(
        a.id,
        username: 'fixture-user',
        password: 'new-dashboard-password',
      );
      gate.release.complete();
      await failed;
      await auth;
      final saved = (await second.loadConnectionsWithSecrets()).single;
      expect(saved.apiKey, a.apiKey);
      expect(saved.dashboardPassword, 'new-dashboard-password');
      expect(f.connectionChanges, isEmpty);
    },
  );

  for (final fail in [false, true]) {
    test(
      'independent credential caches rebase after queued edit failure=$fail',
      () async {
        final firstStore = _CachedSecrets(secrets.values);
        final secondStore = _CachedSecrets(secrets.values);
        final writer = ConnectionManager(
          first.prefs,
          credentialStore: firstStore,
        );
        final stale = ConnectionManager(
          first.prefs,
          credentialStore: secondStore,
        );
        await writer.initialize();
        await stale.initialize();
        final gate = race.WriteGate()..fail = fail;
        firstStore.nextWrite = gate;
        final editing = writer.updateApiKey(a.id, 'new-a-api-key');
        final settled = fail
            ? expectLater(editing, throwsA(isA<CredentialStorageException>()))
            : editing;
        await gate.entered.future;
        final auth = stale.updateDashboardAuth(
          a.id,
          username: 'fixture-user',
          password: 'new-dashboard-password',
        );
        expect(stale.getConnections().single.apiKey, a.apiKey);
        gate.release.complete();
        await settled;
        await auth;
        final saved = (await stale.loadConnectionsWithSecrets()).single;
        expect(saved.apiKey, fail ? a.apiKey : 'new-a-api-key');
        expect(saved.dashboardPassword, 'new-dashboard-password');
      },
    );
  }
}
