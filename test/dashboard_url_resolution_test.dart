import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStore implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _RealHttpOverrides extends HttpOverrides {}

SavedConnection selected({
  String? url,
  int? dashboardPort,
  String? dashboardPrefix,
  bool authoritative = false,
}) => SavedConnection(
  id: 'url-resolution',
  label: 'URL resolution',
  host: 'agent.example.com',
  port: 443,
  useHttps: true,
  apiKey: 'synthetic-api-only',
  desktopGatewayUrl: url,
  dashboardUrlAuthoritative: authoritative,
  dashboardPortOverride: dashboardPort,
  dashboardPrefix: dashboardPrefix,
  dashboardUsername: 'synthetic-user',
  dashboardPassword: 'synthetic-password',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final url in [
    'ftp://agent.example.com/collect',
    'https://user:password@agent.example.com/collect',
    'https://[invalid',
  ]) {
    test(
      'invalid explicit URL is rejected rather than using legacy credentials: $url',
      () {
        final connection = selected(url: url, dashboardPort: 8443);
        var requests = 0;
        expect(
          () => DashboardClient.fromConnection(
            connection,
            httpClient: MockClient((_) async {
              requests++;
              return http.Response('{}', 200);
            }),
          ),
          throwsArgumentError,
        );
        expect(requests, 0);
      },
    );
  }

  test(
    'HEAD serialized same-host URLs never relocate legacy credentials',
    () async {
      for (final url in [
        'https://agent.example.com:9443/other',
        'http://agent.example.com/collect',
        'https://AGENT.example.com:9999/other',
      ]) {
        // These keys model persisted HEAD-era records, with no authority flag.
        final connection = SavedConnection.fromMap({
          'id': 'existing',
          'label': 'Existing',
          'host': 'agent.example.com',
          'port': 443,
          'use_https': true,
          'desktop_gateway_url': url,
          'dashboard_username': 'synthetic-user',
          'dashboard_password': 'synthetic-password',
          'gateway_profile': 'existing-profile',
        });
        final requests = <http.Request>[];
        final client = DashboardClient.fromConnection(
          connection,
          httpClient: MockClient((request) async {
            requests.add(request);
            return http.Response(
              '{}',
              200,
              headers: {
                'set-cookie': 'hermes_session_at=synthetic-cookie; Path=/',
              },
            );
          }),
        );
        addTearDown(client.close);
        expect(client.baseUrl, 'https://agent.example.com:443');
        await client.apiGet('status');
        expect(requests, isNotEmpty);
        for (final request in requests) {
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'agent.example.com');
          expect(request.url.port, 443);
          expect(request.url.path, isNot(contains('other')));
          expect(request.url.path, isNot(contains('collect')));
        }
        expect(requests.first.body, contains('synthetic-password'));
        expect(connection.gatewayProfile, 'existing-profile');
        final reloaded = SavedConnection.fromMap(connection.toMap());
        expect(
          DesktopGatewayClient.normalizedGatewayBaseUrl(reloaded),
          'https://agent.example.com:443',
        );
      }
    },
  );

  test(
    'saved native session remains bound to HEAD destination and profile',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: _MemoryStore(),
      );
      final connection = SavedConnection.fromMap({
        'id': 'existing-native-url',
        'label': 'Existing native',
        'host': 'agent.example.com',
        'port': 443,
        'use_https': true,
        'desktop_gateway_url': 'http://agent.example.com:9443/collect',
        'gateway_profile': 'existing-profile',
      });
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'synthetic-native-token',
        refreshToken: 'synthetic-refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
        userId: 'synthetic-user',
      );
      final restored = manager.getConnections().single;
      final requests = <http.Request>[];
      final client = DashboardClient.fromConnection(
        restored,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await client.apiGet('status');
      expect(requests, hasLength(1));
      expect(
        requests.single.url.toString(),
        'https://agent.example.com/api/status',
      );
      expect(
        requests.single.headers['authorization'],
        'Bearer synthetic-native-token',
      );
      expect(restored.gatewayProfile, 'existing-profile');
      final relocated = restored.copyWith(dashboardUrlAuthoritative: true);
      final deniedRequests = <http.Request>[];
      final denied = DashboardClient.fromConnection(
        relocated,
        httpClient: MockClient((request) async {
          deniedRequests.add(request);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(denied.close);
      await expectLater(denied.apiGet('status'), throwsA(anything));
      expect(deniedRequests, isEmpty);
    },
  );

  test('explicit URL authority survives metadata serialization', () {
    final connection = SavedConnection(
      id: 'opt-in',
      label: 'Explicit',
      host: 'agent.example.com',
      port: 443,
      apiKey: 'synthetic-api-only',
      useHttps: true,
      desktopGatewayUrl: 'http://agent.example.com:9443/exact',
      dashboardUrlAuthoritative: true,
      dashboardPortOverride: 8443,
      dashboardPrefix: '/stale',
      gatewayProfile: 'bound-profile',
    );
    final map = connection.toMap();
    expect(map['dashboard_url_authoritative'], isTrue);
    final restored = SavedConnection.fromMap(map);
    expect(restored.dashboardUrlAuthoritative, isTrue);
    expect(restored.gatewayProfile, 'bound-profile');
    expect(
      DesktopGatewayClient.normalizedGatewayBaseUrl(restored),
      'http://agent.example.com:9443/exact',
    );
  });

  test(
    'copy preserves opt-in, supports explicit downgrade and clears inheritance',
    () {
      final original = SavedConnection.fromMap({
        'id': 'copy',
        'label': 'Copy',
        'host': 'agent.example.com',
        'port': 443,
        'use_https': true,
        'desktop_gateway_url': 'http://agent.example.com:9443/exact',
        'dashboard_url_authoritative': true,
      });
      expect(
        original.copyWith(label: 'Renamed').dashboardUrlAuthoritative,
        isTrue,
      );
      final downgraded = original.copyWith(dashboardUrlAuthoritative: false);
      expect(downgraded.dashboardUrlAuthoritative, isFalse);
      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(downgraded),
        'https://agent.example.com:443',
      );
      final changed = original.copyWith(
        desktopGatewayUrl: 'http://agent.example.com:9555/new',
      );
      expect(
        SavedConnection.fromMap(changed.toMap()).dashboardUrlAuthoritative,
        isTrue,
      );
      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(changed),
        'http://agent.example.com:9555/new',
      );
      final cleared = original.copyWith(clearDesktopGatewayUrl: true);
      expect(cleared.desktopGatewayUrl, isNull);
      expect(cleared.dashboardUrlAuthoritative, isFalse);
      expect(
        cleared
            .copyWith(desktopGatewayUrl: 'http://agent.example.com:9555/new')
            .dashboardUrlAuthoritative,
        isFalse,
      );
    },
  );

  final cases = <(String?, int?, String?, String)>[
    (
      'https://agent.example.com:9443',
      null,
      null,
      'https://agent.example.com:9443',
    ),
    (
      'https://agent.example.com/dashboard/',
      null,
      null,
      'https://agent.example.com:443/dashboard',
    ),
    ('http://agent.example.com', null, null, 'http://agent.example.com:80'),
    (
      'agent.example.com:9443/dashboard',
      null,
      null,
      'https://agent.example.com:9443/dashboard',
    ),
    (
      'https://AGENT.example.com:9999/old',
      8443,
      '/legacy/',
      'https://agent.example.com:8443/legacy',
    ),
    (
      'http://agent.example.com:9999/old',
      8443,
      null,
      'https://agent.example.com:8443',
    ),
    (
      'http://agent.example.com:9999/old',
      null,
      '/legacy',
      'https://agent.example.com:443/legacy',
    ),
    (
      'https://dashboard.example.com:9443/new',
      8443,
      '/legacy',
      'https://dashboard.example.com:9443/new',
    ),
    (null, 8443, '/legacy/', 'https://agent.example.com:8443/legacy'),
    ('   ', null, null, 'https://agent.example.com:443'),
  ];
  for (final (url, port, prefix, expected) in cases) {
    test('endpoint precedence: $url / $port / $prefix', () {
      final connection = selected(
        url: url,
        dashboardPort: port,
        dashboardPrefix: prefix,
        authoritative: port == null && prefix == null,
      );
      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
        expected,
      );
      final client = DashboardClient.fromConnection(
        connection,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(client.close);
      expect(client.baseUrl, expected);
    });
  }

  test(
    'real same-host transport keeps login and cookie off API port and redirects',
    () async {
      final approved = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final unapproved = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var unapprovedRequests = 0;
      final paths = <String>[];
      unapproved.listen((request) async {
        unapprovedRequests++;
        await request.drain<void>();
        request.response.write('{}');
        await request.response.close();
      });
      approved.listen((request) async {
        paths.add(request.uri.path);
        expect(request.headers.value('authorization'), isNull);
        expect(request.headers.value('x-hermes-session-token'), isNull);
        final body = await utf8.decoder.bind(request).join();
        if (request.uri.path == '/dashboard/auth/password-login') {
          expect(body, contains('synthetic-password'));
          expect(request.headers.value('cookie'), isNull);
          request.response.headers.add(
            'set-cookie',
            'hermes_session_at=synthetic-cookie; Path=/',
          );
        } else {
          expect(
            request.headers.value('cookie'),
            'hermes_session_at=synthetic-cookie',
          );
          request.response.statusCode = 307;
          request.response.headers.set(
            'location',
            'http://127.0.0.1:${unapproved.port}/collect',
          );
        }
        request.response.write('{}');
        await request.response.close();
      });
      final connection = SavedConnection(
        id: 'real-url-resolution',
        label: 'Loopback',
        host: '127.0.0.1',
        port: unapproved.port,
        apiKey: 'synthetic-api-only',
        desktopGatewayUrl: 'http://127.0.0.1:${approved.port}/dashboard',
        dashboardUrlAuthoritative: true,
        dashboardUsername: 'synthetic-user',
        dashboardPassword: 'synthetic-password',
      );
      final client = HttpOverrides.runWithHttpOverrides(
        () => DashboardClient.fromConnection(connection),
        _RealHttpOverrides(),
      );
      addTearDown(() async {
        client.close();
        await approved.close(force: true);
        await unapproved.close(force: true);
      });
      await expectLater(
        client.apiGet('status'),
        throwsA(isA<DashboardHttpException>()),
      );
      expect(paths, [
        '/dashboard/auth/password-login',
        '/dashboard/api/status',
      ]);
      expect(unapprovedRequests, 0);
    },
  );

  test(
    'same-host explicit URL supplies port, path and scheme without legacy settings',
    () {
      final connection = selected(
        url: 'http://agent.example.com:9443/dashboard/?ignored=1#fragment',
        authoritative: true,
      );
      expect(
        DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
        'http://agent.example.com:9443/dashboard',
      );
      final client = DashboardClient.fromConnection(
        connection,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(client.close);
      expect(client.baseUrl, 'http://agent.example.com:9443/dashboard');
    },
  );
}
