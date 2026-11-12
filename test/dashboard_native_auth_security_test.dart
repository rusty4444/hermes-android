import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/hermes_native_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStore implements CredentialStore {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ConnectionManager> setup(
    SavedConnection c, {
    MemoryStore? store,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final m = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: store ?? MemoryStore(),
    );
    await m.importConnections([c], replaceExisting: true);
    return m;
  }

  SavedConnection connection(String id) => SavedConnection(
    id: id,
    label: 'audit',
    host: 'dashboard.example',
    port: 443,
    useHttps: true,
    apiKey: '',
    dashboardPortOverride: 443,
  );
  Future<void> save(ConnectionManager m, SavedConnection c, String token) =>
      m.saveDashboardNativeTokens(
        c,
        accessToken: token,
        refreshToken: 'refresh-$token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
        userId: token,
      );

  test(
    'SECURITY: native setup must persist a signed-out marker on an empty store',
    () async {
      final c = connection('audit-new-native');
      final m = await setup(c);
      await m.clearDashboardNativeTokens(c.id);
      final status = await m.dashboardNativeAuthStatus(c);
      final paths = <String>[];
      final client = DashboardClient.fromConnection(
        c,
        httpClient: MockClient((r) async {
          paths.add(r.url.path);
          return r.url.path == '/'
              ? http.Response(
                  'window.__HERMES_SESSION_TOKEN__="legacy-admin";',
                  200,
                )
              : http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      Object? error;
      try {
        await client.apiGet('status');
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(status, DashboardNativeSessionStatus.signedOut);
      expect(paths, isEmpty);
    },
  );

  test(
    'SECURITY: editing a signed-out native connection must not re-enable legacy auth',
    () async {
      final c = connection('audit-edit-signedout');
      final m = await setup(c);
      await save(m, c, 'alice');
      await m.clearDashboardNativeTokens(c.id);
      await m.updateConnection(
        c.id,
        'renamed',
        'https://${c.host}',
        443,
        '',
        dashboardPort: 443,
      );
      final updated = m.getConnections().single;
      // This is the follow-up attempted by the native-mode Save button.
      if (await m.dashboardNativeAuthStatus(updated) ==
          DashboardNativeSessionStatus.notConfigured) {
        await m.clearDashboardNativeTokens(updated.id);
      }
      final requests = <String>[];
      final client = DashboardClient.fromConnection(
        updated,
        httpClient: MockClient((r) async {
          requests.add('${r.url.path} ${r.headers}');
          return r.url.path == '/'
              ? http.Response(
                  'window.__HERMES_SESSION_TOKEN__="legacy-admin";',
                  200,
                )
              : http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      Object? error;
      try {
        await client.apiPost('config', body: {'setting': 'value'});
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(requests, isEmpty);
    },
  );

  test(
    'SECURITY: native logout must stop already authenticated WebSocket writes',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <WebSocket>[];
        final methods = <String>[];
        var tickets = 0;
        final sub = server.listen((request) async {
          if (request.uri.path == '/api/auth/ws-ticket') {
            tickets++;
            expect(request.headers.value('authorization'), 'Bearer alice');
            request.response.headers.contentType = ContentType.json;
            request.response.write('{"ticket":"alice-ticket"}');
            await request.response.close();
          } else if (WebSocketTransformer.isUpgradeRequest(request)) {
            final ws = await WebSocketTransformer.upgrade(request);
            sockets.add(ws);
            ws.listen((raw) {
              final f = jsonDecode(raw as String) as Map;
              if (f['method'] == null) return;
              methods.add(f['method'] as String);
              final result = f['method'] == 'session.resume'
                  ? {
                      'session_id': 'runtime-alice',
                      'running': false,
                      'status': 'idle',
                    }
                  : {'ok': true};
              ws.add(
                jsonEncode({'jsonrpc': '2.0', 'id': f['id'], 'result': result}),
              );
            });
          } else {
            request.response.statusCode = 404;
            await request.response.close();
          }
        });
        final c = SavedConnection(
          id: 'audit-live-socket',
          label: 'audit',
          host: '127.0.0.1',
          port: server.port,
          apiKey: '',
          dashboardPortOverride: server.port,
        );
        final m = await setup(c);
        await save(m, c, 'alice');
        final client = DesktopGatewayClient.fromConnection(c);
        try {
          await client.ensureSession('alice-session');
          await m.clearDashboardNativeTokens(c.id);
          Object? logoutError;
          try {
            await client.renameSession(
              sessionId: 'alice-session',
              title: 'after-logout',
            );
          } catch (e) {
            logoutError = e;
          }
          expect(methods, ['session.resume']);
          await save(m, c, 'bob');
          Object? switchError;
          try {
            await client.renameSession(
              sessionId: 'alice-session',
              title: 'after-bob-login',
            );
          } catch (e) {
            switchError = e;
          }
          expect(methods, ['session.resume']);
          expect(tickets, 1);
          expect(
            logoutError,
            isNotNull,
            reason: 'RPC must not be transmitted after sign-out',
          );
          expect(
            switchError,
            isNotNull,
            reason: 'Alice socket must not survive Bob login',
          );
        } finally {
          client.close();
          for (final ws in sockets) {
            await ws.close();
          }
          await sub.cancel();
          await server.close(force: true);
        }
      }, RealHttp());
    },
  );

  test(
    'SECURITY: native marker deletion permits a real legacy-cookie write',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = <String>[];
        final sub = server.listen((r) async {
          final body = await utf8.decoder.bind(r).join();
          received.add(
            '${r.method} ${r.uri.path} cookie=${r.headers.value('cookie')} body=$body',
          );
          r.response.headers.contentType = ContentType.json;
          if (r.uri.path == '/auth/password-login') {
            r.response.headers.set(
              'set-cookie',
              'hermes_session_at=legacy-admin-session; HttpOnly',
            );
          }
          r.response.write('{}');
          await r.response.close();
        });
        final c = SavedConnection(
          id: 'audit-wire-downgrade',
          label: 'audit',
          host: '127.0.0.1',
          port: server.port,
          apiKey: '',
          dashboardPortOverride: server.port,
          dashboardUsername: 'legacy-admin',
          dashboardPassword: 'synthetic-password',
        );
        final m = await setup(c);
        await save(m, c, 'oidc-restricted-user');
        await m.clearDashboardNativeTokens(c.id);
        // An API-key-only edit goes through the same unconditional native clear.
        await m.updateApiKey(c.id, 'replacement-api-key');
        final current = m.getConnections().single;
        final client = DashboardClient.fromConnection(current);
        try {
          Object? error;
          try {
            await client.apiPost(
              'config',
              body: {'setting': 'changed-after-logout'},
            );
          } catch (e) {
            error = e;
          }
          expect(error, isNotNull);
          expect(
            received,
            isEmpty,
            reason:
                'Native sign-out must not unlock saved legacy administrator credentials',
          );
        } finally {
          client.close();
          await sub.cancel();
          await server.close(force: true);
        }
      }, RealHttp());
    },
  );

  test('SECURITY: browser completion from before logout cannot commit', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final c = connection('browser-logout-race');
      final m = await setup(c);
      await save(m, c, 'alice');
      final attempt = m.beginDashboardNativeSignIn(c);
      final launched = Completer<Uri>();
      final browserReturned = Completer<void>();
      final service = HermesNativeAuthService(
        dashboardBaseUri: Uri.parse('https://dashboard.example:443'),
        trustedOrigin: Uri.parse('https://dashboard.example:443'),
        launchBrowser: (uri) async {
          launched.complete(uri);
          await browserReturned.future;
          return true;
        },
        httpClientFactory: () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'access_token': 'late-browser-token',
              'refresh_token': 'late-browser-refresh',
              'provider': 'oidc',
              'user_id': 'late-user',
              'token_type': 'Bearer',
              'expires_at':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
            200,
          ),
        ),
      );
      final authorizing = service.authorize();
      final uri = await launched.future;
      await m.clearDashboardNativeTokens(c.id);
      final callback = Uri.parse(uri.queryParameters['redirect_uri']!).replace(
        queryParameters: {
          'state': uri.queryParameters['state']!,
          'code': 'late-code',
        },
      );
      final httpClient = HttpClient();
      try {
        final response = await (await httpClient.getUrl(callback)).close();
        await response.drain<void>();
        browserReturned.complete();
        final result = await authorizing;
        Object? error;
        try {
          await m.saveDashboardNativeTokens(
            c,
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            expiresAt: result.expiresAt,
            provider: result.provider,
            userId: result.userId,
            signInAttempt: attempt,
          );
        } catch (e) {
          error = e;
        }
        expect(
          error,
          isNotNull,
          reason:
              'The sign-in generation belongs to browser launch, not save time',
        );
        expect(
          await m.dashboardNativeAuthStatus(c),
          DashboardNativeSessionStatus.signedOut,
        );
      } finally {
        httpClient.close(force: true);
        await service.dispose();
      }
    }, RealHttp());
  });

  test(
    'SECURITY: direct account replacement revokes the previous live owner',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <WebSocket>[];
        final methods = <String>[];
        final bearers = <String?>[];
        final sub = server.listen((r) async {
          if (WebSocketTransformer.isUpgradeRequest(r)) {
            final ws = await WebSocketTransformer.upgrade(r);
            sockets.add(ws);
            ws.listen((raw) {
              final frame = jsonDecode(raw as String) as Map;
              if (frame['method'] == null) return;
              methods.add(frame['method'] as String);
              ws.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': frame['id'],
                  'result': {
                    'session_id': 'runtime',
                    'running': false,
                    'status': 'idle',
                  },
                }),
              );
            });
          } else {
            bearers.add(r.headers.value('authorization'));
            r.response.write('{"ticket":"ticket-${bearers.length}"}');
            await r.response.close();
          }
        });
        final c = SavedConnection(
          id: 'direct-switch',
          label: 'Native',
          host: '127.0.0.1',
          port: server.port,
          apiKey: '',
          dashboardPortOverride: server.port,
        );
        final m = await setup(c);
        await save(m, c, 'alice');
        final old = DesktopGatewayClient.fromConnection(c);
        DesktopGatewayClient? fresh;
        try {
          await old.ensureSession('alice-session');
          await save(m, c, 'bob');
          Object? staleError;
          try {
            await old.renameSession(
              sessionId: 'alice-session',
              title: 'not-bob-consent',
            );
          } catch (e) {
            staleError = e;
          }
          expect(
            staleError,
            isNotNull,
            reason:
                'A successful Bob login must revoke Alice without an intermediate logout',
          );
          expect(methods, ['session.resume']);
          fresh = DesktopGatewayClient.fromConnection(c);
          await fresh.ensureSession('bob-session');
          expect(bearers, ['Bearer alice', 'Bearer bob']);
        } finally {
          old.close();
          fresh?.close();
          for (final ws in sockets) {
            await ws.close();
          }
          await sub.cancel();
          await server.close(force: true);
        }
      }, RealHttp());
    },
  );

  test(
    'SECURITY: sign-out must supersede an already queued token save',
    () async {
      final c = connection('audit-save-race');
      final m = await setup(c);
      await save(m, c, 'alice');
      final saving = save(m, c, 'late-login');
      final rejected = expectLater(saving, throwsA(anything));
      final signingOut = m.clearDashboardNativeTokens(c.id);
      await signingOut;
      await rejected;

      expect(
        await m.dashboardNativeAuthStatus(c),
        DashboardNativeSessionStatus.signedOut,
      );
    },
  );

  test(
    'SECURITY: first native configuration is committed without a legacy gap',
    () async {
      final c = connection('atomic-native-config');
      final m = await setup(c);
      await m.updateConnection(
        c.id,
        c.label,
        'https://${c.host}',
        443,
        '',
        dashboardPort: 443,
        requireDashboardNativeSignIn: true,
      );
      expect(
        await m.dashboardNativeAuthStatus(m.getConnections().single),
        DashboardNativeSessionStatus.signedOut,
      );
    },
  );

  test(
    'SECURITY: failed logout storage must not resurrect credentials in a fresh client',
    () async {
      final c = connection('failed-signout-storage');
      final store = MemoryStore();
      final m = await setup(c, store: store);
      await save(m, c, 'alice');
      store.failWrites = true;
      await expectLater(m.clearDashboardNativeTokens(c.id), throwsA(anything));
      var calls = 0;
      final client = DashboardClient.fromConnection(
        c,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      Object? error;
      try {
        await client.apiPost('config', body: {'value': 'after-failed-signout'});
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(calls, 0);
    },
  );
}
