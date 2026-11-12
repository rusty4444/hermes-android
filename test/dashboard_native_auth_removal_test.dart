import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Store implements CredentialStore {
  final values = <String, String>{};
  Future<void> Function(String)? beforeDelete;
  Future<void> Function(String, String)? beforeWrite;
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(key, value);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    await beforeDelete?.call(key);
    values.remove(key);
  }
}

class _Metadata extends InMemorySharedPreferencesStore {
  _Metadata() : super.withData({});
  String? failure;
  Future<bool>? inject() {
    final mode = failure;
    failure = null;
    return mode == null ? null : Future.value(mode == 'lying success');
  }

  @override
  Future<bool> remove(String key) =>
      (key == 'flutter.saved_connections' ? inject() : null) ??
      super.remove(key);
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    return (key == 'flutter.saved_connections' ? inject() : null) ??
        super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final operation in ['delete', 'import', 'reset']) {
    for (final fault in [
      'legacy delete',
      'lost ACK',
      'corrupt native',
      'metadata false',
      'metadata lying success',
      'final cleanup ACK',
      'success',
      'interrupted removal',
      'tombstone lost ACK',
      'tombstone unavailable',
      'signed in',
    ]) {
      test('$operation $fault cannot downgrade after restart', () async {
        SharedPreferences.setMockInitialValues({});
        final previousPlatform = SharedPreferencesStorePlatform.instance;
        addTearDown(
          () => SharedPreferencesStorePlatform.instance = previousPlatform,
        );
        final metadata = _Metadata();
        SharedPreferencesStorePlatform.instance = metadata;
        final prefs = await SharedPreferences.getInstance();
        final store = _Store();
        final manager = ConnectionManager(prefs, credentialStore: store);
        final c = SavedConnection(
          id: 'rollback-$operation',
          label: 'test',
          host: 'dashboard.example',
          port: 443,
          useHttps: true,
          apiKey: 'api',
          dashboardPortOverride: 443,
          dashboardUsername: 'legacy-admin',
          dashboardPassword: 'synthetic',
        );
        await manager.importConnections([c], replaceExisting: true);
        await manager.saveDashboardNativeTokens(
          c,
          accessToken: 'restricted',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          provider: 'oidc',
        );
        if (fault != 'signed in') {
          await manager.clearDashboardNativeTokens(c.id);
        }
        final nativeKey = store.values.keys.singleWhere(
          (k) => k.startsWith('dashboard_native_auth_v1.'),
        );
        if (fault == 'corrupt native') store.values[nativeKey] = 'corrupt-json';
        if (fault.startsWith('metadata ')) {
          metadata.failure = fault.substring(9);
        }
        var failed = false;
        store.beforeWrite = (key, value) async {
          if (key != nativeKey) return;
          if (fault == 'tombstone lost ACK') {
            store.values[key] = value;
            throw StateError('lost tombstone ACK');
          }
          if (fault == 'tombstone unavailable') {
            throw StateError('write unavailable');
          }
        };
        store.beforeDelete = (key) async {
          if (key == nativeKey && fault == 'final cleanup ACK') {
            store.values.remove(key);
            throw StateError('lost cleanup ACK');
          }
          if (!failed && key.startsWith('connection_credentials_v1.')) {
            expect(jsonDecode(store.values[nativeKey]!)['signed_out'], isTrue);
            expect(store.values[nativeKey], isNot(contains('restricted')));
            if (fault.startsWith('metadata ') ||
                fault == 'final cleanup ACK' ||
                fault == 'success') {
              return;
            }
            failed = true;
            if (fault == 'lost ACK') store.values.remove(key);
            throw StateError('legacy delete failure');
          }
        };
        if (fault == 'interrupted removal') {
          await manager.dashboardNativeAuth.prepareRemoval(c.id);
        } else {
          final removal = switch (operation) {
            'delete' => manager.deleteConnection(c.id),
            'import' => manager.importConnections([], replaceExisting: true),
            _ => manager.resetConnections(),
          };
          if (fault == 'success') {
            await removal;
          } else {
            await expectLater(
              removal,
              throwsA(isA<CredentialStorageException>()),
            );
          }
        }
        // A different store identity prevents reuse of the manager's shared state.
        final restartedStore = _Store()..values.addAll(store.values);
        final restarted = ConnectionManager(
          prefs,
          credentialStore: restartedStore,
        );
        if (fault == 'final cleanup ACK' || fault == 'success') {
          expect(await restarted.loadConnectionsWithSecrets(), isEmpty);
          expect(restartedStore.values, isEmpty);
          return;
        }
        await restarted.initialize();
        final restored = (await restarted.loadConnectionsWithSecrets()).single;
        expect(restored.dashboardPassword, 'synthetic');
        expect(
          await restarted.dashboardNativeAuthStatus(restored),
          DashboardNativeSessionStatus.signedOut,
        );
        final paths = <String>[];
        final client = DashboardClient.fromConnection(
          restored,
          nativeAuthStore: restarted.dashboardNativeAuth,
          httpClient: MockClient((r) async {
            paths.add(r.url.path);
            return http.Response(
              '{}',
              200,
              headers: {
                'set-cookie':
                    'hermes_session_at=legacy-admin-session; HttpOnly',
              },
            );
          }),
        );
        addTearDown(client.close);
        await expectLater(
          client.apiPost('config', body: {'value': 'forbidden'}),
          throwsA(anything),
        );
        expect(paths, isEmpty);
        store.beforeDelete = null;
        store.beforeWrite = null;
        await manager.resetConnections();
        expect(store.values, isEmpty);
        expect(prefs.containsKey('saved_connections'), isFalse);
      });
    }
  }
}
