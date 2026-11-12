import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_native_auth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dashboard_native_auth_security_test.dart' show MemoryStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ConnectionManager manager;
  late SharedPreferences prefs;
  late MemoryStore secrets;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secrets = MemoryStore();
    manager = ConnectionManager(
      prefs,
      credentialStore: secrets,
      nativePushSupported: false,
    );
  });

  test(
    'update authority rebinds native identity, preserves omission, and clears safely',
    () async {
      final original = await manager.saveConnection(
        'Original',
        'https://agent.example',
        443,
        'api',
        desktopGatewayUrl: 'https://agent.example:9443/new',
        dashboardPort: 8443,
        dashboardPrefix: '/old',
        dashboardUsername: 'legacy-user',
        dashboardPassword: 'legacy-pass',
        gatewayProfile: 'research',
      );
      await manager.saveDashboardNativeTokens(
        original,
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
      );
      await manager.updateConnection(
        original.id,
        'Explicit',
        'https://agent.example',
        443,
        'api',
        dashboardPort: 8443,
        dashboardUrlAuthoritative: true,
      );
      var saved = (await manager.loadConnectionsWithSecrets()).single;
      expect(saved.id, original.id);
      expect(saved.dashboardUrlAuthoritative, isTrue);
      expect(saved.dashboardPassword, original.dashboardPassword);
      expect(
        DashboardNativeAuthStore.baseUrlFor(saved),
        'https://agent.example:9443/new',
      );
      expect(
        await manager.dashboardNativeAuthStatus(saved),
        DashboardNativeSessionStatus.signedOut,
      );
      final marker = secrets.values.entries.singleWhere(
        (e) => e.key.startsWith('dashboard_native_auth_v1.'),
      );
      expect(jsonDecode(marker.value), {
        'base_url': 'https://agent.example:9443/new',
        'profile': 'research',
        'signed_out': true,
      });
      await manager.updateConnection(
        original.id,
        'Rename',
        'https://agent.example',
        443,
        'api',
        dashboardPort: 8443,
      );
      saved = manager.getConnections().single;
      expect(saved.dashboardUrlAuthoritative, isTrue);
      expect(secrets.values[marker.key], marker.value);
      await manager.updateConnection(
        original.id,
        'Downgrade',
        'https://agent.example',
        443,
        'api',
        dashboardPort: 8443,
        dashboardUrlAuthoritative: false,
      );
      saved = manager.getConnections().single;
      expect(saved.dashboardUrlAuthoritative, isFalse);
      expect(
        await manager.dashboardNativeAuthStatus(saved),
        DashboardNativeSessionStatus.signedOut,
      );
      await manager.updateConnection(
        original.id,
        'Explicit',
        'https://agent.example',
        443,
        'api',
        dashboardPort: 8443,
        dashboardUrlAuthoritative: true,
      );
      await manager.updateConnection(
        original.id,
        'Clear',
        'https://agent.example',
        443,
        'api',
        dashboardPort: 8443,
        desktopGatewayUrl: '',
      );
      saved = manager.getConnections().single;
      expect(saved.dashboardUrlAuthoritative, isFalse);
      expect(saved.desktopGatewayUrl, isNull);
      expect(
        await manager.dashboardNativeAuthStatus(saved),
        DashboardNativeSessionStatus.signedOut,
      );
    },
  );

  test(
    'authority-only edit with unchanged resolved endpoint preserves native tokens',
    () async {
      final original = await manager.saveConnection(
        'Original',
        'https://agent.example',
        443,
        'api',
        desktopGatewayUrl: 'https://agent.example:8443/old',
        dashboardPort: 8443,
        dashboardPrefix: '/old',
      );
      await manager.saveDashboardNativeTokens(
        original,
        accessToken: 'access',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
      );
      final before = Map<String, String>.of(secrets.values);
      await manager.updateConnection(
        original.id,
        original.label,
        'https://agent.example',
        443,
        'api',
        dashboardPort: 8443,
        dashboardUrlAuthoritative: true,
      );
      final saved = manager.getConnections().single;
      expect(saved.dashboardUrlAuthoritative, isTrue);
      expect(
        await manager.dashboardNativeAuthStatus(saved),
        DashboardNativeSessionStatus.signedIn,
      );
      expect(secrets.values, before);
    },
  );

  test(
    'failed authority save retains metadata and credentials without legacy fallback',
    () async {
      final original = await manager.saveConnection(
        'Original',
        'https://agent.example',
        443,
        'api',
        desktopGatewayUrl: 'https://agent.example:9443/new',
        dashboardPort: 8443,
        dashboardPrefix: '/old',
        dashboardUsername: 'legacy-user',
        dashboardPassword: 'legacy-pass',
        requireDashboardNativeSignIn: true,
      );
      final metadata = prefs.getStringList('saved_connections');
      secrets.failWrites = true;
      await expectLater(
        manager.updateConnection(
          original.id,
          'Changed',
          'https://agent.example',
          443,
          'new-api',
          dashboardPort: 8443,
          dashboardPassword: 'new-pass',
          dashboardUrlAuthoritative: true,
        ),
        throwsA(isA<CredentialStorageException>()),
      );
      expect(prefs.getStringList('saved_connections'), metadata);
      final saved = (await manager.loadConnectionsWithSecrets()).single;
      expect(saved.toMap(), original.toMap());
      expect(saved.dashboardPassword, original.dashboardPassword);
      expect(saved.apiKey, original.apiKey);
      expect(
        await manager.dashboardNativeAuthStatus(saved),
        DashboardNativeSessionStatus.signedOut,
      );
      var calls = 0;
      final client = DashboardClient.fromConnection(
        saved,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await expectLater(client.apiGet('status'), throwsA(anything));
      expect(calls, 0);
    },
  );

  test(
    'save authority is independent from native sign-in and defaults false',
    () async {
      final legacy = await manager.saveConnection(
        'Legacy',
        'https://agent.example',
        443,
        '',
        desktopGatewayUrl: 'https://agent.example:9443/new',
        dashboardPort: 8443,
        dashboardPrefix: '/old',
        requireDashboardNativeSignIn: true,
      );
      expect(legacy.dashboardUrlAuthoritative, isFalse);
      expect(
        DashboardNativeAuthStore.baseUrlFor(legacy),
        'https://agent.example:8443/old',
      );
      final explicit = await manager.saveConnection(
        'Explicit',
        'https://agent.example',
        443,
        '',
        desktopGatewayUrl: 'https://agent.example:9443/new',
        dashboardPort: 8443,
        dashboardPrefix: '/old',
        dashboardUrlAuthoritative: true,
      );
      expect(explicit.dashboardUrlAuthoritative, isTrue);
      expect(
        DashboardNativeAuthStore.baseUrlFor(explicit),
        'https://agent.example:9443/new',
      );
      expect(
        await manager.dashboardNativeAuthStatus(explicit),
        DashboardNativeSessionStatus.notConfigured,
      );
      expect(
        (await manager.loadConnectionsWithSecrets()).first.toMap(),
        explicit.toMap(),
      );
      final rows = prefs
          .getStringList('saved_connections')!
          .map((s) => jsonDecode(s) as Map)
          .toList();
      expect(rows.first['dashboard_url_authoritative'], true);
    },
  );
}
