import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/screens/cron_screen.dart';
import 'package:hermes_android/core/screens/nous_portal_screen.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/skills_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/mobile_push_api.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/session_search_preferences.dart';
import 'package:hermes_android/main.dart';
import 'package:hermes_android/core/services/session_search_client.dart';
import 'package:hermes_android/core/services/tls_client_factory.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_test_utils.dart';
import 'support/inert_turn_application_session.dart';

SavedConnection connection() => SavedConnection(
  id: 'separate-dashboard',
  label: 'Separate dashboard',
  host: 'agent-api.example.com',
  port: 443,
  apiKey: 'synthetic-api-only',
  useHttps: true,
  gatewayPrefix: '/api-proxy',
  dashboardPrefix: '/ignored',
  desktopGatewayUrl: 'https://agent.example.com:9443/dashboard/',
  dashboardUsername: 'synthetic-user',
  dashboardPassword: 'synthetic-password',
  gatewayProfile: 'research & development',
);

class RecordingTlsFactory extends TlsClientFactory {
  RecordingTlsFactory(this.client);
  final http.Client client;
  ClientCertificateConfig? certificate;
  @override
  http.Client createRestClient(ClientCertificateConfig? config) {
    certificate = config;
    return client;
  }
}

class MemoryCredentials implements CredentialStore {
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

// Keep the production request URLs/Host headers; only DNS/socket connection is
// replaced with loopback. No external service or real credentials are involved.
class LoopbackOverrides extends HttpOverrides {
  LoopbackOverrides(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (uri, proxyHost, proxyPort) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, port);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'session search consumer keeps API and dashboard subdomains separate',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final selected = connection().copyWith(dashboardProxied: true);
      final preferences = await SessionSearchPreferences.open();
      await preferences.saveMode(
        connectionIdentity:
            '${selected.baseUrl}|${selected.gatewayPrefix}|${selected.desktopGatewayUrl}',
        mode: SessionSearchMode.server,
      );
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/sessions/search')) {
          expect(request.url.host, 'agent.example.com');
          expect(request.url.port, 9443);
          expect(request.url.path, '/dashboard/api/sessions/search');
          expect(request.headers['authorization'], isNull);
          expect(request.headers['cookie'], isNull);
          return http.Response('{"results":[]}', 200);
        }
        expect(request.url.host, 'agent-api.example.com');
        expect(request.url.path, startsWith('/api-proxy/'));
        if (request.url.path.endsWith('/health')) {
          return http.Response('{}', 200);
        }
        expect(request.headers['authorization'], 'Bearer synthetic-api-only');
        return http.Response('{"data":[],"has_more":false}', 200);
      });
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(controller.close);
      await tester.pumpWidget(
        testAppWithL10n(
          SessionListScreen(
            connection: selected,
            turnApplicationController: controller,
            testHttpClient: transport,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchBar), 'needle');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        requests.where((r) => r.url.path.endsWith('/sessions/search')),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'distinct dashboard authority preserves login, profile, TLS and API split',
    () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/password-login')) {
          expect(jsonDecode(request.body), {
            'provider': 'basic',
            'username': 'synthetic-user',
            'password': 'synthetic-password',
          });
          return http.Response(
            '{}',
            200,
            headers: {
              'set-cookie':
                  '__Secure-hermes_session_at=synthetic-cookie; Secure; HttpOnly; Path=/',
            },
          );
        }
        if (request.url.path.endsWith('/api/auth/ws-ticket')) {
          return http.Response('{"ticket":"synthetic-ticket"}', 200);
        }
        if (request.url.path.endsWith('/skills') ||
            request.url.path.endsWith('/cron/jobs')) {
          return http.Response('[]', 200);
        }
        if (request.url.path.endsWith('/sessions/search')) {
          return http.Response('{"results":[]}', 200);
        }
        return http.Response('{}', 200);
      });
      const cert = ClientCertificateConfig(
        label: 'synthetic',
        certificatePemPath: 'not-loaded-by-recording-factory',
        privateKeyPemPath: 'not-loaded-by-recording-factory',
      );
      final selected = connection().copyWith(clientCertificate: cert);
      final tls = RecordingTlsFactory(transport);
      final dashboard = DashboardClient.fromConnection(
        selected,
        tlsClientFactory: tls,
      );
      addTearDown(dashboard.close);
      expect(tls.certificate, same(cert));
      expect(
        dashboard.baseUrl,
        DesktopGatewayClient.normalizedGatewayBaseUrl(selected),
      );
      await dashboard.getSkills();
      await dashboard.getCronJobs();
      await dashboard.getModelInfo();
      await dashboard.setModel('global', 'openai', 'test-model');
      await dashboard.getModelInfo();
      await dashboard.mintWebSocketTicket();
      await MobilePushApi(dashboard).events('19');
      final search = SessionSearchClient(
        baseUrl: dashboard.baseUrl,
        headers: dashboard.authHeaders,
        httpClient: transport,
      );
      await search.search('needle');
      expect(
        requests.where((r) => r.url.path.endsWith('/auth/password-login')),
        hasLength(1),
      );
      for (final request in requests) {
        expect(request.url.host, 'agent.example.com');
        expect(request.url.port, 9443);
        expect(request.url.scheme, 'https');
        expect(request.url.path, startsWith('/dashboard/'));
        expect(request.headers['authorization'], isNull);
        expect(request.headers['origin'], isNull);
        expect(request.headers['x-hermes-session-token'], isNull);
        if (request.url.path.contains('/api/')) {
          expect(
            request.headers['cookie'],
            '__Secure-hermes_session_at=synthetic-cookie',
          );
        }
        if (request.url.path.endsWith('/model/info') ||
            request.url.path.endsWith('/mobile-push/events')) {
          expect(
            request.url.queryParameters['profile'],
            'research & development',
          );
        }
        if (request.url.path.endsWith('/model/set')) {
          expect(jsonDecode(request.body)['profile'], 'research & development');
        }
      }
      final api = ApiClient(
        baseUrl: selected.baseUrl,
        apiKey: selected.apiKey,
        pathPrefix: selected.gatewayPrefix!,
        httpClient: MockClient((request) async {
          expect(request.url.host, 'agent-api.example.com');
          expect(request.url.path, '/api-proxy/v1/models');
          expect(request.headers['authorization'], 'Bearer synthetic-api-only');
          expect(request.headers['cookie'], isNull);
          return http.Response('{"data":[]}', 200);
        }),
      );
      addTearDown(api.close);
      await api.getModels();
    },
  );

  test(
    'proxy auth stays clean; existing same-host and LAN resolution is unchanged',
    () async {
      final selected = connection().copyWith(dashboardProxied: true);
      final dashboard = DashboardClient.fromConnection(
        selected,
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://agent.example.com:9443/dashboard/api/model/info?profile=research+%26+development',
          );
          expect(request.headers['cookie'], isNull);
          expect(request.headers['authorization'], isNull);
          expect(request.headers['x-hermes-session-token'], isNull);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(dashboard.close);
      await dashboard.getModelInfo();
      for (final override in <String?>[
        null,
        'https://agent-api.example.com:9999/old',
      ]) {
        final legacy = DashboardClient.fromConnection(
          connection().copyWith(
            desktopGatewayUrl: override,
            clearDesktopGatewayUrl: override == null,
            dashboardPortOverride: 8443,
            dashboardPrefix: '/legacy/',
          ),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        );
        expect(legacy.baseUrl, 'https://agent-api.example.com:8443/legacy');
        legacy.close();
      }
      final lan = DashboardClient.fromConnection(
        SavedConnection(
          id: 'lan',
          label: 'LAN',
          host: 'lan.test',
          port: 8642,
          apiKey: '',
        ),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(lan.baseUrl, 'http://lan.test:9119');
      lan.close();
    },
  );

  for (final screen in [
    'skills',
    'cron',
    'settings',
    'portal',
    'validation',
    'push',
  ]) {
    testWidgets(
      '$screen default consumer sends real HTTP to distinct dashboard host',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final requests = <String>[];
        final savedOverrides = HttpOverrides.current;
        late HttpServer server;
        await tester.runAsync(() async {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen((request) async {
            await request.drain<void>();
            requests.add(
              '${request.headers.value('host')} ${request.uri.path}',
            );
            expect(
              request.headers.value('authorization'),
              request.uri.path.contains('/api-proxy/')
                  ? 'Bearer synthetic-api-only'
                  : isNull,
            );
            expect(request.headers.value('cookie'), isNull);
            request.response.headers.contentType = ContentType.json;
            // Refuse after capturing validation authority: this test must not
            // persist a connection or invoke account/native mutation workflows.
            if (screen == 'validation' &&
                request.uri.path.endsWith('/model/info')) {
              expect(request.uri.queryParameters['profile'], 'secondary');
              request.response.statusCode = HttpStatus.notFound;
            }
            request.response.write(
              request.uri.path.endsWith('/skills') ||
                      request.uri.path.endsWith('/cron/jobs')
                  ? '[]'
                  : '{}',
            );
            await request.response.close();
          });
        });
        HttpOverrides.global = LoopbackOverrides(server.port);
        addTearDown(() async {
          HttpOverrides.global = savedOverrides;
          await server.close(force: true);
        });
        final selected = connection().copyWith(
          desktopGatewayUrl: 'http://agent.example.com/dashboard',
          dashboardProxied: true,
        );
        final Widget view = switch (screen) {
          'skills' => SkillsScreen(connection: selected),
          'cron' => CronScreen(connection: selected),
          'settings' => SettingsScreen(connection: selected),
          _ => NousPortalScreen(connection: selected),
        };
        if (screen == 'validation') {
          final prefs = await SharedPreferences.getInstance();
          final manager = ConnectionManager(
            prefs,
            credentialStore: MemoryCredentials(),
            nativePushSupported: false,
          );
          final turns = GatewayTurnApplicationController(
            sessionFactory: (_) => InertTurnApplicationSession(),
          );
          addTearDown(turns.close);
          await tester.pumpWidget(
            testAppWithL10n(
              HomeScreen(
                connManager: manager,
                turnApplicationController: turns,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Add Connection'));
          await tester.pumpAndSettle();
          Future<void> enter(String label, String value) async {
            final field = find.widgetWithText(TextField, label);
            await tester.ensureVisible(field);
            await tester.enterText(field, value);
          }

          await enter('Label', 'Separate dashboard');
          await enter('Host', 'http://agent-api.example.com');
          await enter('API Key', 'synthetic-api-only');
          await tester.ensureVisible(
            find.text('Custom proxy and dashboard details'),
          );
          await tester.tap(find.text('Custom proxy and dashboard details'));
          await tester.pumpAndSettle();
          await enter('Gateway path prefix', '/api-proxy');
          await enter(
            'Desktop Gateway URL (optional)',
            'http://agent.example.com/dashboard',
          );
          await enter('Hermes profile (optional)', 'secondary');
          await tester.ensureVisible(find.text('Dashboard behind proxy'));
          await tester.tap(find.text('Dashboard behind proxy'));
          await tester.ensureVisible(find.text('Connect'));
          await tester.tap(find.text('Connect'));
        } else if (screen == 'push') {
          SharedPreferences.setMockInitialValues({
            'saved_connections': [jsonEncode(selected.toMap())],
          });
          final prefs = await SharedPreferences.getInstance();
          final secrets = MemoryCredentials();
          final credentialId = base64Url
              .encode(utf8.encode(selected.id))
              .replaceAll('=', '');
          secrets.values['connection_credentials_v1.$credentialId'] =
              jsonEncode({
                'api_key': selected.apiKey,
                'dashboard_password': selected.dashboardPassword,
              });
          final manager = ConnectionManager(
            prefs,
            credentialStore: secrets,
            nativePushSupported: false,
          );
          const channel = MethodChannel('test.dashboard-origin.push');
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                channel,
                (call) async => <String, dynamic>{},
              );
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          final push = MobilePushService(channel: channel, supported: true);
          await tester.runAsync(() async {
            await push.initialize(manager).timeout(const Duration(seconds: 3));
            await push
                .checkAvailability(selected)
                .timeout(const Duration(seconds: 3));
          });
          push.dispose();
        } else if (screen == 'settings') {
          final prefs = await SharedPreferences.getInstance();
          await tester.pumpWidget(
            HermesApp(connManager: ConnectionManager(prefs)),
          );
          await tester.pumpAndSettle();
          unawaited(
            Navigator.of(
              tester.element(find.byType(HomeScreen)),
            ).push(MaterialPageRoute<void>(builder: (_) => view)),
          );
          await tester.pump();
        } else {
          await tester.pumpWidget(testAppWithL10n(view));
        }
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        if (screen == 'validation') await tester.pumpAndSettle();
        expect(requests, isNotEmpty);
        expect(
          requests.where((r) => !r.startsWith('agent-api.example.com')),
          everyElement(startsWith('agent.example.com /dashboard/api/')),
        );
        expect(
          requests.any(
            (r) => r.contains(switch (screen) {
              'skills' => '/skills',
              'cron' => '/cron/jobs',
              'settings' => '/model/info',
              'validation' => '/model/info',
              'push' => '/mobile-push/capabilities',
              _ => '/portal',
            }),
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
