import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

/// Case-insensitive request header lookup — package:http normalises header
/// names when sending, so tests should not assume a particular casing.
String? _header(http.BaseRequest request, String name) {
  final lower = name.toLowerCase();
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}

void main() {
  group('SavedConnection', () {
    test('normalizes bare HTTP gateway hosts with fallback port', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        '192.168.1.50',
        8642,
      );

      expect(normalized.host, '192.168.1.50');
      expect(normalized.port, 8642);
      expect(normalized.useHttps, isFalse);
    });

    test('normalizes HTTPS URLs without an explicit port to 443', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        'https://hermes.example.com',
        8642,
      );

      expect(normalized.host, 'hermes.example.com');
      expect(normalized.port, 443);
      expect(normalized.useHttps, isTrue);
    });

    test('normalizes HTTPS URLs with a custom fallback port', () {
      final normalized = SavedConnection.normalizeHostAndPort(
        'https://hermes.example.com',
        8443,
      );

      expect(normalized.host, 'hermes.example.com');
      expect(normalized.port, 8443);
      expect(normalized.useHttps, isTrue);
    });

    test('serializes HTTPS flag and remains backward compatible', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Remote',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
      );

      expect(SavedConnection.fromMap(conn.toMap()).useHttps, isTrue);
      expect(
        SavedConnection.fromMap({
          'id': '2',
          'label': 'Old',
          'host': '192.168.1.50',
          'port': 8642,
          'api_key': 'key',
        }).useHttps,
        isFalse,
      );
    });

    test('uses dashboard port 9119 for local gateway connections', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Home',
        host: '192.168.1.50',
        port: 8642,
        apiKey: 'key',
      );

      expect(conn.dashboardPort, 9119);
      expect(
        DashboardClient(host: conn.host, port: conn.dashboardPort).baseUrl,
        'http://192.168.1.50:9119',
      );
    });

    test('uses the HTTPS proxy port for dashboard calls over HTTPS', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Remote',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
      );

      expect(conn.dashboardPort, 443);
      expect(
        DashboardClient(
          host: conn.host,
          port: conn.dashboardPort,
          useHttps: conn.useHttps,
        ).baseUrl,
        'https://hermes.example.com:443',
      );
    });

    test('explicit dashboard port override wins over topology default', () {
      final local = SavedConnection(
        id: '1',
        label: 'Home',
        host: '192.168.1.50',
        port: 8642,
        apiKey: 'key',
        dashboardPortOverride: 30433,
      );
      expect(local.dashboardPort, 30433);

      final https = SavedConnection(
        id: '2',
        label: 'Remote',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
        dashboardPortOverride: 8443,
      );
      expect(https.dashboardPort, 8443);
    });

    test(
      'round-trips dashboard port and credentials through toMap/fromMap',
      () {
        final conn = SavedConnection(
          id: '1',
          label: 'Home',
          host: '192.168.1.50',
          port: 8642,
          apiKey: 'key',
          dashboardPortOverride: 30433,
          dashboardUsername: 'misha',
          dashboardPassword: 'secret',
        );

        final restored = SavedConnection.fromMap(conn.toMap());
        expect(restored.dashboardPortOverride, 30433);
        expect(restored.dashboardUsername, 'misha');
        expect(restored.dashboardPassword, 'secret');
        expect(restored.dashboardPort, 30433);
      },
    );

    test('fromMap is backward compatible with maps lacking dashboard keys', () {
      final restored = SavedConnection.fromMap({
        'id': '2',
        'label': 'Old',
        'host': '192.168.1.50',
        'port': 8642,
        'api_key': 'key',
      });
      expect(restored.dashboardPortOverride, isNull);
      expect(restored.dashboardUsername, isNull);
      expect(restored.dashboardPassword, isNull);
      expect(restored.dashboardPort, 9119);
    });

    test('fromMap normalises blank credentials to null', () {
      final restored = SavedConnection.fromMap({
        'id': '3',
        'label': 'Blank',
        'host': '192.168.1.50',
        'port': 8642,
        'api_key': 'key',
        'dashboard_username': '   ',
        'dashboard_password': '',
      });
      expect(restored.dashboardUsername, isNull);
      expect(restored.dashboardPassword, isNull);
    });

    test('copyWith preserves unset fields and clears via flags', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Home',
        host: '192.168.1.50',
        port: 8642,
        apiKey: 'key',
        gatewayPrefix: '/profile/peter',
        dashboardPrefix: '/dashboard',
        dashboardProxied: true,
        dashboardPortOverride: 30433,
        dashboardUsername: 'misha',
        dashboardPassword: 'secret',
      );

      final keyOnly = conn.copyWith(apiKey: 'new-key');
      expect(keyOnly.apiKey, 'new-key');
      expect(keyOnly.gatewayPrefix, '/profile/peter');
      expect(keyOnly.dashboardPrefix, '/dashboard');
      expect(keyOnly.dashboardProxied, isTrue);
      expect(keyOnly.dashboardPortOverride, 30433);
      expect(keyOnly.dashboardUsername, 'misha');
      expect(keyOnly.dashboardPassword, 'secret');

      final cleared = conn.copyWith(
        clearGatewayPrefix: true,
        clearDashboardPrefix: true,
        clearDashboardPort: true,
        clearDashboardUsername: true,
        clearDashboardPassword: true,
      );
      expect(cleared.gatewayPrefix, isNull);
      expect(cleared.dashboardPrefix, isNull);
      expect(cleared.dashboardProxied, isTrue);
      expect(cleared.dashboardPortOverride, isNull);
      expect(cleared.dashboardUsername, isNull);
      expect(cleared.dashboardPassword, isNull);
      // Identity and unrelated fields are retained.
      expect(cleared.id, '1');
      expect(cleared.apiKey, 'key');
    });
  });

  group('ApiClient', () {
    test('healthCheck verifies an authenticated endpoint', () async {
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'valid-key',
        httpClient: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer valid-key');
          if (request.url.path == '/health') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/sessions') {
            return http.Response('{"object":"list","data":[]}', 200);
          }
          return http.Response('not found', 404);
        }),
      );

      expect(await client.healthCheck(), isTrue);
      client.close();
    });

    test('healthCheck rejects invalid API keys', () async {
      final client = ApiClient(
        baseUrl: 'http://hermes.local:8642',
        apiKey: 'bad-key',
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('{}', 200);
          }
          if (request.url.path == '/api/sessions') {
            return http.Response('unauthorized', 401);
          }
          return http.Response('not found', 404);
        }),
      );

      expect(await client.healthCheck(), isFalse);
      client.close();
    });
  });

  group('GatewayChatClient', () {
    test('appends latest user message to existing history exactly once', () {
      final messages = GatewayChatClient.buildChatCompletionMessages(
        message: 'new question',
        history: [
          {'role': 'user', 'content': 'old question'},
          {'role': 'assistant', 'content': 'old answer'},
        ],
      );

      expect(messages, [
        {'role': 'user', 'content': 'old question'},
        {'role': 'assistant', 'content': 'old answer'},
        {'role': 'user', 'content': 'new question'},
      ]);
    });

    test(
      'does not duplicate latest user message already present in history',
      () {
        final messages = GatewayChatClient.buildChatCompletionMessages(
          message: 'new question',
          history: [
            {'role': 'user', 'content': 'old question'},
            {'role': 'assistant', 'content': 'old answer'},
            {'role': 'user', 'content': 'new question'},
          ],
        );

        expect(
          messages.where((m) => m['content'] == 'new question'),
          hasLength(1),
        );
        expect(messages.last, {'role': 'user', 'content': 'new question'});
      },
    );

    test('parses normal chat completion SSE token frames', () {
      final token = GatewayChatClient.parseSseFrame(
        'data: {"choices":[{"delta":{"content":"hello"}}]}',
      );

      expect(token, 'hello');
    });

    test('parses Hermes tool progress SSE frames via callback', () {
      Map<String, dynamic>? progress;
      final token = GatewayChatClient.parseSseFrame(
        'event: hermes.tool.progress\n'
        'data: {"tool":"read_file","toolCallId":"call_1","status":"running"}',
        onToolProgress: (p) => progress = p,
      );

      expect(token, isNull);
      expect(progress, isNotNull);
      expect(progress!['tool'], 'read_file');
      expect(progress!['toolCallId'], 'call_1');
      expect(progress!['status'], 'running');
    });
  });

  group('DashboardClient', () {
    test('wraps cron job updates for dashboard endpoint', () {
      final updates = {'name': 'Daily', 'no_agent': true};

      expect(DashboardClient.buildCronUpdateBody(updates), {
        'updates': updates,
      });
    });

    test(
      'logs in and authenticates /api calls with the session cookie',
      () async {
        var loginCalls = 0;
        final client = DashboardClient(
          host: 'hermes.local',
          port: 30433,
          username: 'misha',
          password: 'secret',
          httpClient: MockClient((request) async {
            if (request.url.path == '/auth/password-login') {
              loginCalls++;
              expect(request.method, 'POST');
              expect(jsonDecode(request.body), {
                'provider': 'basic',
                'username': 'misha',
                'password': 'secret',
              });
              return http.Response(
                '{"ok":true}',
                200,
                headers: {
                  'set-cookie':
                      'hermes_session_at=TOK123; Path=/; HttpOnly; SameSite=Lax',
                },
              );
            }
            if (request.url.path == '/api/model/info') {
              // Cookie auth, not the insecure token header.
              expect(_header(request, 'cookie'), 'hermes_session_at=TOK123');
              expect(_header(request, 'x-hermes-session-token'), isNull);
              return http.Response('{"model":"hermes-agent"}', 200);
            }
            return http.Response('not found', 404);
          }),
        );

        final info = await client.getModelInfo();
        expect(info['model'], 'hermes-agent');

        // A second call reuses the cached cookie (no re-login).
        await client.getModelInfo();
        expect(loginCalls, 1);
        client.close();
      },
    );

    test('falls back to homepage token scrape when no credentials', () async {
      final client = DashboardClient(
        host: 'hermes.local',
        port: 9119,
        httpClient: MockClient((request) async {
          if (request.url.path == '/') {
            return http.Response(
              '<script>window.__HERMES_SESSION_TOKEN__="SPA_TOK";</script>',
              200,
            );
          }
          if (request.url.path == '/api/model/info') {
            expect(_header(request, 'x-hermes-session-token'), 'SPA_TOK');
            expect(_header(request, 'cookie'), isNull);
            return http.Response('{"model":"hermes-agent"}', 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final info = await client.getModelInfo();
      expect(info['model'], 'hermes-agent');
      client.close();
    });

    test('re-authenticates once on a 401 from an /api call', () async {
      var apiCalls = 0;
      var loginCalls = 0;
      final client = DashboardClient(
        host: 'hermes.local',
        port: 30433,
        username: 'misha',
        password: 'secret',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            loginCalls++;
            final cookie = 'hermes_session_at=TOK$loginCalls';
            return http.Response(
              '{"ok":true}',
              200,
              headers: {'set-cookie': '$cookie; Path=/'},
            );
          }
          if (request.url.path == '/api/model/info') {
            apiCalls++;
            // First attempt: stale cookie → 401. Retry: succeeds.
            if (apiCalls == 1) return http.Response('unauthorized', 401);
            expect(_header(request, 'cookie'), 'hermes_session_at=TOK2');
            return http.Response('{"model":"hermes-agent"}', 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final info = await client.getModelInfo();
      expect(info['model'], 'hermes-agent');
      expect(apiCalls, 2);
      expect(loginCalls, 2);
      client.close();
    });

    test('surfaces invalid dashboard credentials', () async {
      final client = DashboardClient(
        host: 'hermes.local',
        port: 30433,
        username: 'misha',
        password: 'wrong',
        httpClient: MockClient((request) async {
          if (request.url.path == '/auth/password-login') {
            return http.Response('{"detail":"Invalid credentials"}', 401);
          }
          return http.Response('not found', 404);
        }),
      );

      expect(client.getModelInfo(), throwsA(isA<Exception>()));
      client.close();
    });
  });

  group('ConnectionManager', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('saveConnection persists dashboard port and credentials', () async {
      final prefs = await SharedPreferences.getInstance();
      final mgr = ConnectionManager(prefs);
      mgr.saveConnection(
        'Home',
        '192.168.1.50',
        8642,
        'key',
        dashboardPort: 30433,
        dashboardUsername: 'misha',
        dashboardPassword: 'secret',
      );

      final conn = mgr.getConnections().single;
      expect(conn.dashboardPortOverride, 30433);
      expect(conn.dashboardUsername, 'misha');
      expect(conn.dashboardPassword, 'secret');
    });

    test('updateDashboardAuth sets then clears fields', () async {
      final prefs = await SharedPreferences.getInstance();
      final mgr = ConnectionManager(prefs);
      mgr.saveConnection('Home', '192.168.1.50', 8642, 'key');
      final id = mgr.getConnections().single.id;

      mgr.updateDashboardAuth(
        id,
        gatewayPrefix: '/profile/peter',
        dashboardPrefix: '/dashboard',
        dashboardProxied: true,
        dashboardPort: 30433,
        username: 'misha',
        password: 'secret',
      );
      var conn = mgr.getConnections().single;
      expect(conn.gatewayPrefix, '/profile/peter');
      expect(conn.dashboardPrefix, '/dashboard');
      expect(conn.dashboardProxied, isTrue);
      expect(conn.dashboardPortOverride, 30433);
      expect(conn.dashboardUsername, 'misha');
      expect(conn.dashboardPassword, 'secret');

      // Blank values clear the corresponding fields.
      mgr.updateDashboardAuth(
        id,
        gatewayPrefix: '',
        dashboardPrefix: '',
        dashboardProxied: false,
        username: '',
        password: '',
      );
      conn = mgr.getConnections().single;
      expect(conn.gatewayPrefix, isNull);
      expect(conn.dashboardPrefix, isNull);
      expect(conn.dashboardProxied, isFalse);
      expect(conn.dashboardPortOverride, isNull);
      expect(conn.dashboardUsername, isNull);
      expect(conn.dashboardPassword, isNull);
    });

    test('updateApiKey preserves dashboard credentials', () async {
      final prefs = await SharedPreferences.getInstance();
      final mgr = ConnectionManager(prefs);
      mgr.saveConnection(
        'Home',
        '192.168.1.50',
        8642,
        'key',
        dashboardPort: 30433,
        dashboardUsername: 'misha',
        dashboardPassword: 'secret',
      );
      final id = mgr.getConnections().single.id;

      mgr.updateApiKey(id, 'new-key');
      final conn = mgr.getConnections().single;
      expect(conn.apiKey, 'new-key');
      expect(conn.dashboardPortOverride, 30433);
      expect(conn.dashboardUsername, 'misha');
      expect(conn.dashboardPassword, 'secret');
    });
  });

  group('Path prefix support', () {
    test('joinBaseUrl without prefix returns baseUrl unchanged', () {
      expect(
        SavedConnection.joinBaseUrl('https://hermes.example.com:443', ''),
        'https://hermes.example.com:443',
      );
    });

    test('joinBaseUrl appends prefix between base and API path', () {
      expect(
        SavedConnection.joinBaseUrl(
          'https://hermes.example.com:443',
          '/profile/peter',
        ),
        'https://hermes.example.com:443/profile/peter',
      );
    });

    test('ApiClient pathPrefix is prepended to baseUrl', () {
      final client = ApiClient(
        baseUrl: 'https://hermes.example.com:443',
        apiKey: 'key',
        pathPrefix: '/profile/peter',
      );
      expect(client.baseUrl, 'https://hermes.example.com:443/profile/peter');
      client.close();
    });

    test('DashboardClient uses pathPrefix', () {
      final client = DashboardClient(
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        pathPrefix: '/dashboard',
      );
      expect(client.baseUrl, 'https://hermes.example.com:443/dashboard');
      client.close();
    });

    test('DashboardClient proxied sends no auth headers', () async {
      final client = DashboardClient(
        host: 'hermes.example.com',
        port: 443,
        useHttps: true,
        pathPrefix: '/dashboard',
        proxied: true,
        httpClient: MockClient((request) async {
          expect(
            request.headers.containsKey('x-hermes-session-token'),
            isFalse,
          );
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response('{"data": {}}', 200);
        }),
      );
      await client.apiGet('model/info');
      client.close();
    });

    test(
      'DashboardClient proxied ignores credentials, sends clean headers',
      () async {
        final client = DashboardClient(
          host: 'hermes.example.com',
          port: 443,
          useHttps: true,
          pathPrefix: '/dashboard',
          proxied: true,
          username: 'user',
          password: 'pass',
          httpClient: MockClient((request) async {
            expect(
              request.headers.containsKey('x-hermes-session-token'),
              isFalse,
            );
            expect(request.headers.containsKey('cookie'), isFalse);
            return http.Response('{"data": {}}', 200);
          }),
        );
        await client.apiGet('model/info');
        client.close();
      },
    );

    test('SavedConnection serializes gateway and dashboard prefixes', () {
      final conn = SavedConnection(
        id: '1',
        label: 'Proxy',
        host: 'hermes.example.com',
        port: 443,
        apiKey: 'key',
        useHttps: true,
        gatewayPrefix: '/profile/peter',
        dashboardPrefix: '/dashboard',
        dashboardProxied: true,
      );
      final map = conn.toMap();
      expect(map['gateway_prefix'], '/profile/peter');
      expect(map['dashboard_prefix'], '/dashboard');
      expect(map['dashboard_proxied'], true);
    });
  });
}
