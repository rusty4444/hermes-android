import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'mobile_push_service_test.dart' as fixture;

class WriteGate {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool fail = false;
}

class GatedSecrets extends fixture.MemorySecrets {
  final gates = <WriteGate>[];
  Future<void> wait() async {
    if (gates.isEmpty) return;
    final gate = gates.removeAt(0);
    gate.entered.complete();
    await gate.release.future;
    if (gate.fail) throw StateError('test-owned write failure');
  }

  @override
  Future<void> write(String key, String value) async {
    await wait();
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await wait();
    await super.delete(key);
  }
}

class HeldMetadata extends InMemorySharedPreferencesStore {
  HeldMetadata(super.data) : super.withData();
  final gate = WriteGate();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.saved_connections') {
      gate.entered.complete();
      await gate.release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

/// Original independent red probe retained with its now-forbidden intermediates
/// changed: releasing old capabilities during a secure write must NOT issue
/// permission/enable/PUT/confirm. Before the fix, old authority survived disposal.
/// Only Android detection is injected now: production BEGIN/END IPC and the full
/// transaction execute. Kotlin pairs this fake with the real bridge/store/receive.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Fixture f;
  late GatedSecrets secrets;
  late ConnectionManager manager;
  late SavedConnection original;

  Future<void> edit() => manager.updateConnection(
    original.id,
    original.label,
    'https://fixture.invalid',
    443,
    'new-api-key',
    dashboardPrefix: '/dash',
    dashboardUsername: 'fixture-user',
    dashboardPassword: 'fixture-password',
    gatewayProfile: 'new-profile',
  );
  Future<void> enable(SavedConnection c) =>
      f.service.enable(c, 'test.distributor', ['durable-session']);
  http.Response capabilities() => http.Response(
    jsonEncode({
      'schema': 1,
      'registration_fence': 1,
      'enabled': true,
      'transports': ['webpush'],
      'vapid_public_key': base64Url
          .encode([4, ...List<int>.filled(64, 1)])
          .replaceAll('=', ''),
    }),
    200,
  );
  void seed({bool active = false, bool endpoint = true}) {
    f.seed(active: active);
    f.native.addAll({
      'connection': original.id,
      'binding': MobilePushService.binding(original),
    });
    if (!endpoint) f.native.remove('endpoint');
  }

  void expectOff() {
    expect(f.native['enabled'], isFalse);
    expect(f.native['active'] == true, isFalse);
  }

  setUp(() async {
    notificationPrefs.value = NotificationPrefs.defaults;
    f = fixture.Fixture();
    await f.setup();
    secrets = GatedSecrets();
    manager = ConnectionManager(
      f.manager.prefs,
      credentialStore: secrets,
      nativePushSupported: true,
    );
    await manager.saveConnection(
      'Race',
      'https://fixture.invalid',
      443,
      'gateway-test-key',
      dashboardPrefix: '/dash',
      dashboardUsername: 'fixture-user',
      dashboardPassword: 'fixture-password',
      gatewayProfile: 'old-profile',
    );
    original = manager.getConnections().first;
    f.methods.clear();
  });
  tearDown(() => f.close());

  test(
    'initially off: old capabilities cannot enable during held account write',
    () async {
      await f.service.initialize(manager);
      final capEntered = Completer<void>();
      final caps = Completer<http.Response>();
      f.onCapabilities = (_) {
        capEntered.complete();
        return caps.future;
      };
      final enabling = enable(original);
      await capEntered.future;
      final gate = WriteGate();
      secrets.gates.add(gate);
      final editing = edit();
      await gate.entered.future;
      expect(manager.getConnections().first.gatewayProfile, 'old-profile');
      expect(f.methods, contains('beginConnectionChange'));
      caps.complete(capabilities());
      await enabling;
      await f.changed();
      expectOff();
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
      expect(f.requests.where((r) => r.method == 'PUT'), isEmpty);
      gate.release.complete();
      await editing;
      expect(manager.getConnections().first.gatewayProfile, 'new-profile');
      f.restart(); // no foreground reconciliation repairs the result
      expectOff();
      expect(f.connectionChanges, isEmpty);
    },
  );

  test(
    'new starts blocked across BEGIN reply, credential write and END reply',
    () async {
      await f.service.initialize(manager);
      final begin = WriteGate(), end = WriteGate(), write = WriteGate();
      secrets.gates.add(write);
      f.afterCommand = (method, _) async {
        final gate = method == 'beginConnectionChange'
            ? begin
            : method == 'endConnectionChange'
            ? end
            : null;
        if (gate != null) {
          gate.entered.complete();
          await gate.release.future;
        }
      };
      final editing = edit();
      // Try before BEGIN can even be acknowledged: Dart must mark ownership
      // synchronously, rather than waiting for native or a secure-store write.
      await enable(original);
      await begin.entered.future;
      await enable(original);
      expect(f.requests, isEmpty);
      begin.release.complete();
      await write.entered.future;
      await enable(original);
      write.release.complete();
      await end.entered.future;
      await enable(manager.getConnections().first);
      expect(f.requests, isEmpty);
      end.release.complete();
      await editing;
      f.afterCommand = null;
      await enable(manager.getConnections().first);
      expect(f.native['enabled'], isTrue);
      expect(
        f.native['binding'],
        MobilePushService.binding(manager.getConnections().first),
      );
      expect(
        f.requests
            .singleWhere((r) => r.url.path.endsWith('/capabilities'))
            .url
            .queryParameters['profile'],
        'new-profile',
      );
    },
  );

  test(
    'metadata persistence await stays gated across separate manager instances',
    () async {
      final reader = ConnectionManager(
        manager.prefs,
        credentialStore: secrets,
        nativePushSupported: true,
      );
      await f.service.initialize(reader);
      final previousStore = SharedPreferencesStorePlatform.instance;
      final store = HeldMetadata({
        for (final key in manager.prefs.getKeys())
          'flutter.$key': manager.prefs.get(key)!,
      });
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousStore,
      );
      final editing = edit();
      await store.gate.entered.future;
      // SharedPreferences already exposes optimistic metadata B here, but has
      // not durably acknowledged it. Neither old A nor that B may gain consent.
      await enable(original);
      await enable(reader.getConnections().first);
      expect(f.requests, isEmpty);
      expectOff();
      store.gate.release.complete();
      await editing;
      await enable(reader.getConnections().first);
      expect(f.native['enabled'], isTrue);
    },
  );

  test(
    'lost END is retryable by fresh consent from a replacement manager',
    () async {
      await f.service.initialize(manager);
      f.failCommand = 'endConnectionChange';
      await expectLater(edit(), throwsA(isA<CredentialStorageException>()));
      expectOff();
      expect(f.connectionChanges, hasLength(1));
      expect(manager.getConnections().first.gatewayProfile, 'new-profile');
      // A replacement manager can finish only terminal leases from the outbox.
      final replacement = ConnectionManager(
        manager.prefs,
        credentialStore: secrets,
        nativePushSupported: true,
      );
      f.restart();
      await f.service.initialize(replacement);
      await enable(replacement.getConnections().first);
      expect(f.connectionChanges, isEmpty);
      expect(f.native['enabled'], isTrue);
    },
  );

  test('failed native BEGIN cannot write credentials or metadata', () async {
    await f.service.initialize(manager);
    final before = Map<String, String>.of(secrets.values);
    f.failCommand = 'beginConnectionChange';
    await expectLater(edit(), throwsA(isA<CredentialStorageException>()));
    expect(secrets.values, before);
    expect(manager.getConnections().first.gatewayProfile, 'old-profile');
    expect(f.connectionChanges, isEmpty);
    await enable(original);
    expect(f.native['enabled'], isTrue);
  });

  test(
    'overlapping transactions retain the gate until every owner settles',
    () async {
      await f.service.initialize(manager);
      final first = WriteGate(), second = WriteGate();
      secrets.gates.addAll([first, second]);
      final one = manager.updateApiKey(original.id, 'first-key');
      await first.entered.future;
      final two = manager.updateDashboardAuth(
        original.id,
        username: 'fixture-user',
        password: 'fixture-password',
      );
      // Whole-list ownership queues the sibling before snapshot capture.
      // Its synchronous per-ID lease must still block consent between owners.
      await enable(manager.getConnections().first);
      expect(second.entered.isCompleted, isFalse);
      expect(f.requests, isEmpty);
      first.release.complete();
      await one;
      await second.entered.future;
      expect(f.connectionChanges, hasLength(1));
      await enable(manager.getConnections().first);
      expect(f.requests, isEmpty);
      second.release.complete();
      await two;
      await enable(manager.getConnections().first);
      expect(f.native['enabled'], isTrue);
      expect(f.connectionChanges, isEmpty);
    },
  );

  test(
    'failed multi-ID import releases leases but never revives old authority',
    () async {
      seed(active: true);
      await f.service.initialize(manager);
      final other = manager.getConnections().singleWhere(
        (c) => c.id != original.id,
      );
      final gate = WriteGate()..fail = true;
      secrets.gates.add(gate);
      final importing = manager.importConnections([
        other.copyWith(gatewayProfile: 'imported'),
        original,
      ], replaceExisting: false);
      final failed = expectLater(
        importing,
        throwsA(isA<CredentialStorageException>()),
      );
      await gate.entered.future;
      expectOff();
      await enable(original);
      gate.release.complete();
      await failed;
      expect(f.connectionChanges, isEmpty);
      expectOff();
      await enable(manager.getConnections().first);
      expect(f.native['enabled'], isTrue);
    },
  );

  for (final phase in ['active', 'endpoint', 'PUT', 'confirm']) {
    test(
      '$phase authority revoked before held write; late replies powerless',
      () async {
        seed(active: phase == 'active', endpoint: phase != 'endpoint');
        final entered = Completer<void>();
        final response = Completer<http.Response>();
        final pending = f.pending();
        if (phase == 'PUT') {
          f.onPut = (_) {
            entered.complete();
            return response.future;
          };
        }
        if (phase == 'confirm') {
          f.challenge();
          f.onConfirm = (_) {
            entered.complete();
            return response.future;
          };
        }
        final initialization = f.service.initialize(manager);
        if (phase == 'PUT' || phase == 'confirm') {
          await entered.future;
        } else {
          await initialization;
        }
        final gate = WriteGate();
        secrets.gates.add(gate);
        final editing = edit();
        await gate.entered.future;
        expectOff();
        expect(f.native['keys'], isNull);
        expect(f.native['challenges'], isNull);
        expect(f.native['revocations'], hasLength(1));
        if (phase == 'PUT' || phase == 'confirm') {
          response.complete(
            phase == 'PUT'
                ? pending
                : http.Response('{"status":"active","generation":7}', 200),
          );
          await initialization;
        }
        await f.changed();
        expect(f.methods, isNot(contains('activate')));
        await enable(original);
        expectOff();
        gate.release.complete();
        await editing;
        f.restart();
        expectOff();
        expect(f.native['revocations'], hasLength(1));
        expect(f.requests.where((r) => r.method == 'DELETE'), isEmpty);
      },
    );
  }

  test(
    'gate spans failed write and rollback; old pending start cannot revive unchanged metadata',
    () async {
      await f.service.initialize(manager);
      final capEntered = Completer<void>();
      final caps = Completer<http.Response>();
      f.onCapabilities = (_) {
        capEntered.complete();
        return caps.future;
      };
      final enabling = enable(original);
      await capEntered.future;
      final write = WriteGate()..fail = true;
      final rollback = WriteGate();
      secrets.gates.addAll([write, rollback]);
      final editing = edit();
      final failed = expectLater(
        editing,
        throwsA(isA<CredentialStorageException>()),
      );
      await write.entered.future;
      write.release.complete();
      await rollback.entered.future;
      await enable(original);
      expectOff();
      rollback.release.complete();
      await failed;
      expect(
        MobilePushService.binding(manager.getConnections().first),
        MobilePushService.binding(original),
      );
      caps.complete(capabilities());
      await enabling;
      expect(f.methods, isNot(contains('enable')));
      f.onCapabilities = null;
      await enable(manager.getConnections().first);
      expect(f.native['enabled'], isTrue);
      expect(f.connectionChanges, isEmpty);
    },
  );

  for (final replace in [false, true]) {
    test(
      'import replace=$replace gates all affected IDs before first write',
      () async {
        final other = f.manager.getConnections().singleWhere(
          (c) => c.id != original.id,
        );
        seed(active: true);
        await f.service.initialize(manager);
        final gate = WriteGate();
        secrets.gates.add(gate);
        final incoming = [
          other.copyWith(gatewayProfile: 'imported'),
          if (!replace) original.copyWith(gatewayProfile: 'imported'),
        ];
        final importing = manager.importConnections(
          incoming,
          replaceExisting: replace,
        );
        await gate.entered.future;
        expectOff();
        expect(f.connectionChanges.values.single, {other.id, original.id});
        await enable(original);
        await enable(other);
        expect(f.methods, isNot(contains('enable')));
        gate.release.complete();
        await importing;
        expect(f.connectionChanges, isEmpty);
        expectOff();
        expect(
          manager.getConnections().any((c) => c.id == original.id),
          !replace,
        );
      },
    );
  }

  test(
    'remove gates credential deletion and leaves authority off after return',
    () async {
      seed(active: true);
      await f.service.initialize(manager);
      final gate = WriteGate();
      secrets.gates.add(gate);
      final deleting = manager.deleteConnection(original.id);
      await gate.entered.future;
      await enable(original);
      expectOff();
      gate.release.complete();
      await deleting;
      expect(manager.getConnections().any((c) => c.id == original.id), isFalse);
      f.restart();
      expectOff();
    },
  );

  test(
    'unrelated edit does not invalidate pending opt-in or active binding',
    () async {
      await f.service.initialize(manager);
      final capEntered = Completer<void>();
      final caps = Completer<http.Response>();
      f.onCapabilities = (_) {
        capEntered.complete();
        return caps.future;
      };
      final enabling = enable(original);
      await capEntered.future;
      final other = manager.getConnections().singleWhere(
        (c) => c.id != original.id,
      );
      final gate = WriteGate();
      secrets.gates.add(gate);
      final editing = manager.updateApiKey(other.id, 'other-new-key');
      await gate.entered.future;
      caps.complete(capabilities());
      await enabling;
      expect(f.native['enabled'], isTrue);
      gate.release.complete();
      await editing;
      expect(f.native['enabled'], isTrue);
      expect(f.native['connection'], original.id);
    },
  );

  test(
    'old enable IPC reply after fresh B enable cannot restore A authority',
    () async {
      await f.service.initialize(manager);
      final oldReply = WriteGate();
      f.afterCommand = (method, _) async {
        if (method == 'enable') {
          oldReply.entered.complete();
          await oldReply.release.future;
        }
      };
      final enabling = enable(original);
      await oldReply.entered.future;
      await edit();
      expectOff();
      f.afterCommand = null;
      final changed = manager.getConnections().first;
      await enable(changed);
      final fresh = f.clone(f.native);
      oldReply.release.complete();
      await enabling;
      expect(f.native, fresh);
      expect(f.service.connectionId, changed.id);
      expect(f.native['binding'], MobilePushService.binding(changed));
    },
  );
}
