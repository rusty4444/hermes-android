import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'independent_push_quality_edit_race_test.dart'
    show GatedSecrets, WriteGate;
import 'mobile_push_service_test.dart' as fixture;

/// Separate secure-store wrappers sharing physical values, NOT their caches.
class CachedSecrets implements CredentialStore {
  CachedSecrets(this.backing);
  final GatedSecrets backing;
  final cache = <String, String>{};
  @override
  String? readCached(String key) => cache[key];
  @override
  Future<String?> read(String key) async {
    final value = await backing.read(key);
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) => backing.write(key, value);
  @override
  Future<void> delete(String key) => backing.delete(key);
}

class FailingMetadata extends InMemorySharedPreferencesStore {
  FailingMetadata(super.data, {required this.afterEffect}) : super.withData();
  final bool afterEffect;
  bool failed = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.saved_connections' && !failed) {
      failed = true;
      if (afterEffect) await super.setValue(valueType, key, value);
      throw StateError('test-owned physical metadata failure / lost ACK');
    }
    return super.setValue(valueType, key, value);
  }
}

// Original independent failing schedule is archived with its actual red run.
// Physical-list serialization forbids its old intermediate completion: C now
// waits for owned import/edit A, then saves/consents without being overwritten.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Fixture f;
  late GatedSecrets secrets;
  late ConnectionManager manager;
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
    // Hydrate this manager's independent secure-store seam with the actual
    // fixture credentials, so post-failure consent uses password-cookie auth.
    await manager.importConnections([f.connection], replaceExisting: false);
    await f.service.initialize(manager);
  });
  tearDown(() => f.close());

  ConnectionManager sibling({CredentialStore? store}) => ConnectionManager(
    manager.prefs,
    credentialStore: store ?? secrets,
    nativePushSupported: true,
  );

  Future<void> expectRestartedIds(Iterable<String> ids) async {
    final reopened = sibling();
    await reopened.initialize();
    expect(reopened.getConnections().map((c) => c.id), ids);
  }

  Future<SavedConnection> createAndActivateC() async {
    final sibling = ConnectionManager(
      manager.prefs,
      credentialStore: secrets,
      nativePushSupported: true,
    );
    await sibling.saveConnection(
      'Concurrent C',
      'https://fixture.invalid',
      443,
      'new-c-api-key',
      dashboardPrefix: '/dash',
      dashboardUsername: 'fixture-user',
      dashboardPassword: 'fixture-password',
      gatewayProfile: 'new-c-profile',
    );
    final c = sibling.getConnections().first;
    await f.service.enable(c, 'test.distributor', ['durable-session']);
    f.native.addAll({
      'endpoint': 'https://distributor.invalid/test',
      'keys': {'p256dh': 'test-fixture-only', 'auth': 'test-fixture-only'},
    });
    f.challenge();
    await f.service.refresh();
    expect(f.native['active'], isTrue);
    expect(f.native['binding'], MobilePushService.binding(c));
    return c;
  }

  test(
    'lost BEGIN acknowledgement after native effect aborts all credential writes',
    () async {
      final a = manager.getConnections().single;
      final before = Map<String, String>.of(secrets.values);
      var dropped = false;
      f.afterCommand = (method, args) async {
        if (method == 'beginConnectionChange' && !dropped) {
          dropped = true;
          throw StateError('fixture lost reply AFTER native BEGIN effect');
        }
      };
      await expectLater(
        manager.updateApiKey(a.id, 'never-written'),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(secrets.values, before);
      expect(f.connectionChanges, isEmpty);
      f.afterCommand = null;
      await f.service.enable(
        manager.getConnections().single,
        'test.distributor',
        ['durable-session'],
      );
      expect(f.native['enabled'], isTrue);
    },
  );

  test(
    'terminal END replay after physical ACK loss cannot release a still-live sibling',
    () async {
      final a = manager.getConnections().single;
      final one = WriteGate(), two = WriteGate();
      secrets.gates.addAll([one, two]);
      var lost = false;
      f.afterCommand = (method, args) async {
        if (method == 'endConnectionChange' && !lost) {
          lost = true;
          throw StateError('fixture lost reply AFTER native END effect');
        }
      };
      final first = manager.updateApiKey(a.id, 'first-key');
      final firstFailed = expectLater(
        first,
        throwsA(isA<CredentialStorageException>()),
      );
      await one.entered.future;
      final second = manager.updateApiKey(a.id, 'second-key');
      one.release.complete();
      await firstFailed;
      await two.entered.future;
      expect(f.connectionChanges, hasLength(1));
      final replacement = ConnectionManager(
        manager.prefs,
        credentialStore: secrets,
        nativePushSupported: true,
      );
      await replacement.finishPendingMobilePushChanges();
      await replacement.finishPendingMobilePushChanges();
      expect(f.connectionChanges, hasLength(1));
      f.requests.clear();
      await f.service.enable(
        manager.getConnections().single,
        'test.distributor',
        ['durable-session'],
      );
      expect(f.requests, isEmpty);
      two.release.complete();
      await second;
      expect(f.connectionChanges, isEmpty);
      await f.service.enable(
        manager.getConnections().single,
        'test.distributor',
        ['durable-session'],
      );
      expect(f.native['enabled'], isTrue);
    },
  );

  for (final operation in [
    'key',
    'full edit',
    'dashboard',
    'remove',
    'merge',
  ]) {
    test(
      'preexisting active C survives unrelated $operation and cold cache',
      () async {
        final a = manager.getConnections().single;
        final cold = sibling(store: CachedSecrets(secrets));
        final c = await createAndActivateC();
        // Reattach the controller to the cold wrapper. Its absent C cache must
        // not be interpreted as a changed binding and revoke valid C authority.
        await f.service.initialize(cold);
        await f.changed();
        expect(f.native['active'], isTrue);
        final gate = WriteGate();
        secrets.gates.add(gate);
        final changing = switch (operation) {
          'key' => cold.updateApiKey(a.id, 'new-a-key'),
          'full edit' => cold.updateConnection(
            a.id,
            'Edited',
            a.host,
            a.port,
            'new-a-key',
            gatewayProfile: 'changed-A',
          ),
          'dashboard' => cold.updateDashboardAuth(
            a.id,
            username: 'new-user',
            password: 'new-password',
          ),
          'remove' => cold.deleteConnection(a.id),
          _ => cold.importConnections([
            a.copyWith(label: 'Imported'),
          ], replaceExisting: false),
        };
        await gate.entered.future;
        expect(f.connectionChanges.values.single, {a.id});
        await f.changed();
        expect(f.native['active'], isTrue);
        gate.release.complete();
        await changing;
        await f.changed();
        expect(f.native['active'], isTrue);
        expect(
          cold.getConnections().singleWhere((x) => x.id == c.id).apiKey,
          c.apiKey,
        );
        final savedC = (await cold.loadConnectionsWithSecrets()).singleWhere(
          (x) => x.id == c.id,
        );
        expect(MobilePushService.binding(savedC), MobilePushService.binding(c));
        expect(f.native['binding'], MobilePushService.binding(c));
        f.restart();
        expect(f.native['active'], isTrue);
        await expectRestartedIds(
          operation == 'remove'
              ? [c.id]
              : operation == 'merge'
              ? [a.id, c.id]
              : [c.id, a.id],
        );
      },
    );
  }

  test(
    'replace discovers and revokes active C saved after manager creation',
    () async {
      final a = manager.getConnections().single;
      final staleOwner = sibling(store: CachedSecrets(secrets));
      final c = await createAndActivateC();
      final gate = WriteGate();
      secrets.gates.add(gate);
      final replacing = staleOwner.importConnections([
        a,
      ], replaceExisting: true);
      await gate.entered.future;
      expect(f.connectionChanges.values.single, {a.id, c.id});
      expect(f.native['enabled'], isFalse);
      expect(f.native['revocations'], hasLength(1));
      await f.service.enable(c, 'test.distributor', ['durable-session']);
      expect(f.native['enabled'], isFalse);
      gate.release.complete();
      await replacing;
      await expectRestartedIds([a.id]);
      f.restart();
      expect(f.native['enabled'], isFalse);
    },
  );

  test(
    'queued same-ID partial update reads current credentials, including clears',
    () async {
      final a = manager.getConnections().single;
      final stale = sibling(store: CachedSecrets(secrets));
      await stale.initialize();
      final one = WriteGate(), two = WriteGate();
      secrets.gates.addAll([one, two]);
      final first = manager.updateApiKey(a.id, 'latest-api');
      await one.entered.future;
      final second = stale.updateDashboardAuth(
        a.id,
        username: '',
        password: '',
      );
      one.release.complete();
      await first;
      await two.entered.future;
      two.release.complete();
      await second;
      final live = (await manager.loadConnectionsWithSecrets()).single;
      expect(live.apiKey, 'latest-api');
      expect(live.dashboardPassword, isNull);
      await stale.updateApiKey(a.id, '');
      expect(
        (await manager.loadConnectionsWithSecrets()).single.apiKey,
        isEmpty,
      );
      expect(secrets.values, isEmpty);
    },
  );

  test(
    'queued edit cannot resurrect a connection deleted by prior owner',
    () async {
      final a = manager.getConnections().single;
      final gate = WriteGate();
      secrets.gates.add(gate);
      final deleting = manager.deleteConnection(a.id);
      await gate.entered.future;
      final editing = sibling().updateApiKey(a.id, 'must-not-return');
      gate.release.complete();
      await deleting;
      await editing;
      expect(secrets.values, isEmpty);
      await expectRestartedIds([]);
    },
  );

  for (final afterEffect in [false, true]) {
    test(
      'metadata failure afterEffect=$afterEffect rolls back before next owner snapshots',
      () async {
        final a = manager.getConnections().single;
        final before = Map<String, String>.of(secrets.values);
        final previousStore = SharedPreferencesStorePlatform.instance;
        SharedPreferencesStorePlatform.instance = FailingMetadata({
          for (final key in manager.prefs.getKeys())
            'flutter.$key': manager.prefs.get(key)!,
        }, afterEffect: afterEffect);
        addTearDown(
          () => SharedPreferencesStorePlatform.instance = previousStore,
        );
        final failing = manager.updateConnection(
          a.id,
          'Not committed',
          a.host,
          a.port,
          'rejected-key',
        );
        final failed = expectLater(
          failing,
          throwsA(isA<CredentialStorageException>()),
        );
        final savingC = createAndActivateC();
        await failed;
        final c = await savingC;
        expect(
          manager.getConnections().singleWhere((x) => x.id == a.id).label,
          a.label,
        );
        expect(
          (await manager.loadConnectionsWithSecrets())
              .singleWhere((x) => x.id == a.id)
              .apiKey,
          a.apiKey,
        );
        for (final entry in before.entries) {
          expect(secrets.values[entry.key], entry.value);
        }
        expect(f.native['active'], isTrue);
        await expectRestartedIds([c.id, a.id]);
      },
    );
  }

  test(
    'import rollback holds ownership until all old credentials restored',
    () async {
      final a = manager.getConnections().single;
      final c = await createAndActivateC();
      final before = Map<String, String>.of(secrets.values);
      final write = WriteGate(),
          failure = WriteGate()..fail = true,
          rollback = WriteGate();
      secrets.gates.addAll([write, failure, rollback]);
      final importing = manager.importConnections([
        a.copyWith(apiKey: 'rejected'),
      ], replaceExisting: true);
      final failed = expectLater(
        importing,
        throwsA(isA<CredentialStorageException>()),
      );
      await write.entered.future;
      write.release.complete();
      await failure.entered.future;
      final editing = sibling(
        store: CachedSecrets(secrets),
      ).updateApiKey(a.id, 'after-rollback');
      failure.release.complete();
      await rollback.entered.future;
      expect(f.connectionChanges, hasLength(1));
      expect(f.native['enabled'], isFalse);
      rollback.release.complete();
      await failed;
      await editing;
      final reopened = await sibling().loadConnectionsWithSecrets();
      expect(reopened.map((x) => x.id), [c.id, a.id]);
      expect(reopened.singleWhere((x) => x.id == c.id).apiKey, c.apiKey);
      expect(
        reopened.singleWhere((x) => x.id == a.id).apiKey,
        'after-rollback',
      );
      expect(
        secrets.values.values,
        contains(before.values.firstWhere((v) => v.contains('new-c-api-key'))),
      );
      f.restart();
      expect(f.native['enabled'], isFalse);
    },
  );

  test(
    'migration owns the list through sanitization before queued create',
    () async {
      final a = manager.getConnections().single;
      await manager.prefs.setStringList('saved_connections', [
        jsonEncode({
          ...a.toMap(),
          'api_key': a.apiKey,
          'dashboard_password': a.dashboardPassword,
        }),
      ]);
      final gate = WriteGate();
      secrets.gates.add(gate);
      final migrating = sibling().initialize();
      await gate.entered.future;
      final saving = createAndActivateC();
      gate.release.complete();
      await migrating;
      final c = await saving;
      await expectRestartedIds([c.id, a.id]);
      expect(
        manager.prefs.getStringList('saved_connections')!.join(),
        isNot(contains('api_key')),
      );
    },
  );

  for (final corrupt in ['valid', 'json', 'type']) {
    test(
      'reset corrupt=$corrupt revokes native C before clearing list; later create survives',
      () async {
        final c = await createAndActivateC();
        if (corrupt == 'json') {
          await manager.prefs.setStringList('saved_connections', [
            'invalid-json',
          ]);
        } else if (corrupt == 'type') {
          await manager.prefs.setString('saved_connections', 'invalid-type');
        }
        final reset = manager.resetConnections();
        final saving = sibling().saveConnection(
          'After reset',
          'new.invalid',
          443,
          'new-key',
        );
        await reset;
        expect(f.native['enabled'], isFalse);
        expect((f.native['revocations'] as List).single['connection'], c.id);
        await saving;
        final connections = await sibling().loadConnectionsWithSecrets();
        expect(connections.single.label, 'After reset');
        expect(connections.single.apiKey, 'new-key');
      },
    );
  }

  test('export waits for credential and metadata settlement', () async {
    final a = manager.getConnections().single;
    final gate = WriteGate();
    secrets.gates.add(gate);
    final editing = manager.updateApiKey(a.id, 'settled-key');
    await gate.entered.future;
    var exported = false;
    final exporting = sibling().loadConnectionsWithSecrets().then((list) {
      exported = true;
      return list;
    });
    await f.changed();
    expect(exported, isFalse);
    gate.release.complete();
    await editing;
    expect((await exporting).single.apiKey, 'settled-key');
  });

  test(
    'store/profile caches are not shared merely because metadata is shared',
    () async {
      final separate = CachedSecrets(GatedSecrets());
      final isolated = sibling(store: separate);
      await isolated.initialize();
      expect(isolated.getConnections().single.apiKey, isEmpty);
      expect(separate.cache, isEmpty);
      expect(manager.getConnections().single.apiKey, isNotEmpty);
    },
  );

  for (final zone in [1, 2]) {
    testWidgets('completed list tail releases widget-test zone $zone', (
      tester,
    ) async {
      final a = manager.getConnections().single;
      await manager.updateApiKey(a.id, 'zone-$zone');
      expect(
        (await sibling().loadConnectionsWithSecrets()).single.apiKey,
        'zone-$zone',
      );
    });
  }

  for (final replacing in [true, false]) {
    test(
      'queued C survives held ${replacing ? 'replace import' : 'unrelated account edit'} without unrelated revocation',
      () async {
        final a = manager.getConnections().single;
        final gate = WriteGate();
        secrets.gates.add(gate);
        final changing = replacing
            ? manager.importConnections([a], replaceExisting: true)
            : manager.updateApiKey(a.id, 'changed-a-key');
        await gate.entered.future;
        var cFinished = false;
        final savingC = createAndActivateC().then((c) {
          cFinished = true;
          return c;
        });
        await f.changed();
        expect(cFinished, isFalse);
        gate.release.complete();
        await changing;
        final c = await savingC;
        await f.changed();
        expect(manager.getConnections().any((x) => x.id == c.id), isTrue);
        expect(manager.getConnections().first.apiKey, 'new-c-api-key');
        expect(f.native['active'], isTrue);
        f.restart();
        expect(f.native['connection'], c.id);
        expect(f.connectionChanges, isEmpty);
        expect(
          f.native['enabled'],
          isTrue,
          reason:
              'C remains saved; its valid native authority must not be revoked to conceal a stale overwrite',
        );
      },
    );
  }
}
