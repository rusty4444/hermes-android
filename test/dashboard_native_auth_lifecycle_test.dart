import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_native_auth_store.dart';
import 'package:hermes_android/core/services/memory_repository.dart';
import 'package:hermes_android/core/services/session_search_client.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NativeMemoryCredentials implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class NativeRealHttpOverrides extends HttpOverrides {}

SavedConnection selected({String id = 'oidc-one'}) => SavedConnection(
  id: id,
  label: 'Native',
  host: 'api.example.test',
  port: 443,
  useHttps: true,
  apiKey: 'api-server-only',
  desktopGatewayUrl: 'https://dashboard.example.test:9443/proxy',
  gatewayProfile: 'research',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'secure native sign-in authenticates REST and WS ticket, never exports',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secure = NativeMemoryCredentials();
      final manager = ConnectionManager(prefs, credentialStore: secure);
      final connection = selected();
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'native-id-or-access',
        refreshToken: 'native-refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
        userId: 'test-subject',
      );
      final requests = <http.Request>[];
      final dashboard = DashboardClient.fromConnection(
        connection,
        nativeAuthStore: manager.dashboardNativeAuth,
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/ws-ticket')) {
            return http.Response('{"ticket":"single-use"}', 200);
          }
          return http.Response('{}', 200);
        }),
      );
      addTearDown(dashboard.close);
      expect(dashboard.providerOAuthUnavailableReason, isNull);
      await dashboard.apiGet('status');
      expect(await dashboard.mintWebSocketTicket(), 'single-use');
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.headers['authorization'], 'Bearer native-id-or-access');
        expect(request.headers['cookie'], isNull);
        expect(request.headers['x-hermes-session-token'], isNull);
        expect(request.followRedirects, isFalse);
        expect(request.url.host, 'dashboard.example.test');
        expect(request.url.path, startsWith('/proxy/api/'));
      }
      final preferences = jsonEncode(prefs.getStringList('saved_connections'));
      final exported = jsonEncode(
        (await manager.loadConnectionsWithSecrets())
            .map((c) => c.toMap())
            .toList(),
      );
      for (final serialized in [preferences, exported]) {
        expect(serialized, isNot(contains('native-id-or-access')));
        expect(serialized, isNot(contains('native-refresh')));
      }
      expect(
        secure.values.values.any((v) => v.contains('native-refresh')),
        isTrue,
      );
    },
  );

  test('concurrent REST and ticket 401s rotate once across clients', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final manager = ConnectionManager(
      prefs,
      credentialStore: NativeMemoryCredentials(),
    );
    final connection = selected(id: 'single-flight');
    await manager.importConnections([connection], replaceExisting: true);
    await manager.saveDashboardNativeTokens(
      connection,
      accessToken: 'old-token',
      refreshToken: 'old-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      provider: 'oidc',
    );
    var refreshes = 0;
    final initialCalls = Completer<void>();
    var oldCalls = 0;
    final transport = MockClient((request) async {
      expect(request.followRedirects, isFalse);
      if (request.url.path.endsWith('/auth/native/refresh')) {
        refreshes++;
        expect(jsonDecode(request.body), {
          'refresh_token': 'old-refresh',
          'provider': 'oidc',
        });
        return http.Response(
          jsonEncode({
            'access_token': 'new-token',
            'refresh_token': 'rotated-refresh',
            'expires_at':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch /
                1000,
            'provider': 'oidc',
            'user_id': 'subject',
            'token_type': 'Bearer',
          }),
          200,
        );
      }
      if (request.headers['authorization'] == 'Bearer old-token') {
        if (++oldCalls == 2) initialCalls.complete();
        await initialCalls.future;
        return http.Response('{}', 401);
      }
      expect(request.headers['authorization'], 'Bearer new-token');
      return http.Response('{"ticket":"fresh-ticket"}', 200);
    });
    final one = DashboardClient.fromConnection(
      connection,
      httpClient: transport,
    );
    final two = DashboardClient.fromConnection(
      connection,
      httpClient: transport,
    );
    addTearDown(one.close);
    addTearDown(two.close);
    await Future.wait([one.apiGet('status'), two.mintWebSocketTicket()]);
    expect(refreshes, 1);
  });

  test(
    'direct-constructor memory consumer uses connection native credentials',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: NativeMemoryCredentials(),
      );
      final connection = selected(id: 'memory-consumer');
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'memory-native',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
      );
      var calls = 0;
      final memory = MemoryRepository.fromConnection(
        connection,
        httpClient: MockClient((request) async {
          calls++;
          expect(request.url.path, '/proxy/api/learning/graph');
          expect(request.headers['authorization'], 'Bearer memory-native');
          expect(request.url.queryParameters['profile'], 'research');
          return http.Response('{"memory":[],"nodes":[],"edges":[]}', 200);
        }),
      );
      addTearDown(memory.close);
      await memory.loadFacts();
      expect(calls, 1);
    },
  );

  test(
    'removed connections delete native secrets and fence delayed refresh',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secure = NativeMemoryCredentials();
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: secure,
      );
      final connection = selected(id: 'removed-during-refresh');
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'expired-token',
        refreshToken: 'removed-refresh',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        provider: 'oidc',
      );
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final client = DashboardClient.fromConnection(
        connection,
        httpClient: MockClient((request) async {
          expect(request.url.path, '/proxy/auth/native/refresh');
          started.complete();
          return response.future;
        }),
      );
      addTearDown(client.close);
      final read = client.apiGet('status');
      final rejected = expectLater(read, throwsA(anything));
      await started.future;
      await manager.deleteConnection(connection.id);
      expect(
        secure.values.values.any((v) => v.contains('removed-refresh')),
        isFalse,
      );
      response.complete(
        http.Response(
          jsonEncode({
            'access_token': 'late-token',
            'refresh_token': 'late-refresh',
            'expires_at':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch /
                1000,
            'provider': 'oidc',
          }),
          200,
        ),
      );
      await rejected;
      expect(
        secure.values.values.any((v) => v.contains('late-refresh')),
        isFalse,
      );
    },
  );

  test(
    'terminal refresh rejection stays signed out without insecure fallback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final secure = NativeMemoryCredentials();
      final prefs = await SharedPreferences.getInstance();
      final manager = ConnectionManager(prefs, credentialStore: secure);
      final connection = selected(id: 'terminal-rejection');
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'expired',
        refreshToken: 'rejected-refresh',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        provider: 'oidc',
      );
      final paths = <String>[];
      final transport = MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/refresh')) {
          return http.Response('secret-provider-error', 401);
        }
        return http.Response(
          'window.__HERMES_SESSION_TOKEN__="should-not-fallback";',
          200,
        );
      });
      final first = DashboardClient.fromConnection(
        connection,
        httpClient: transport,
      );
      addTearDown(first.close);
      await expectLater(
        first.apiGet('status'),
        throwsA(isA<DashboardNativeAuthException>()),
      );
      // A fresh client also must not downgrade after the refresh token was cleared.
      final second = DashboardClient.fromConnection(
        connection,
        httpClient: transport,
      );
      addTearDown(second.close);
      await expectLater(
        second.apiGet('status'),
        throwsA(isA<DashboardNativeAuthException>()),
      );
      expect(paths, ['/proxy/auth/native/refresh']);
      expect(
        secure.values.values.any((v) => v.contains('rejected-refresh')),
        isFalse,
      );
    },
  );

  test(
    'expired native session survives a transient refresh error and app reinitialization',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secure = NativeMemoryCredentials();
      final manager = ConnectionManager(prefs, credentialStore: secure);
      final connection = selected(id: 'transient-refresh');
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'expired',
        refreshToken: 'keep-refresh',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        provider: 'oidc',
      );
      expect(
        await manager.dashboardNativeAuthStatus(connection),
        DashboardNativeSessionStatus.expired,
      );
      var attempts = 0;
      final client = DashboardClient.fromConnection(
        connection,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            if (++attempts == 1) return http.Response('provider-secret', 503);
            return http.Response(
              jsonEncode({
                'access_token': 'renewed',
                'refresh_token': 'renewed-refresh',
                'expires_at':
                    DateTime.now()
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch /
                    1000,
                'provider': 'oidc',
              }),
              200,
            );
          }
          expect(request.headers['authorization'], 'Bearer renewed');
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.apiGet('status'),
        throwsA(isA<DashboardNativeAuthException>()),
      );
      expect(
        secure.values.values.any((v) => v.contains('keep-refresh')),
        isTrue,
      );
      await ConnectionManager(prefs, credentialStore: secure).initialize();
      await client.apiGet('status');
      expect(attempts, 2);
      expect(
        await manager.dashboardNativeAuthStatus(connection),
        DashboardNativeSessionStatus.signedIn,
      );
    },
  );

  test(
    'origin and profile replacement never reuse a token or accept an old login',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: NativeMemoryCredentials(),
      );
      final connection = selected(id: 'replaced-binding');
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'old-origin-token',
        refreshToken: 'old-origin-refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
      );
      var calls = 0;
      final client = DashboardClient.fromConnection(
        connection,
        httpClient: MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.close);
      await manager.importConnections([
        connection.copyWith(gatewayProfile: 'other'),
      ], replaceExisting: true);
      await expectLater(
        client.apiGet('status'),
        throwsA(isA<DashboardNativeAuthException>()),
      );
      await expectLater(
        manager.saveDashboardNativeTokens(
          connection,
          accessToken: 'stale-login',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          provider: 'oidc',
        ),
        throwsA(isA<DashboardNativeAuthException>()),
      );
      expect(calls, 0);
    },
  );

  test('a replacement sign-in wins over a delayed refresh result', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = NativeMemoryCredentials();
    final manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: secure,
    );
    final connection = selected(id: 'new-signin-wins');
    await manager.importConnections([connection], replaceExisting: true);
    await manager.saveDashboardNativeTokens(
      connection,
      accessToken: 'expired',
      refreshToken: 'old-refresh',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      provider: 'oidc',
    );
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final client = DashboardClient.fromConnection(
      connection,
      httpClient: MockClient((request) async {
        started.complete();
        return response.future;
      }),
    );
    addTearDown(client.close);
    final rejected = expectLater(
      client.apiGet('status'),
      throwsA(isA<DashboardNativeAuthException>()),
    );
    await started.future;
    await manager.saveDashboardNativeTokens(
      connection,
      accessToken: 'new-login',
      refreshToken: 'new-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      provider: 'oidc',
    );
    response.complete(
      http.Response(
        jsonEncode({
          'access_token': 'stale-rotation',
          'refresh_token': 'stale-refresh',
          'expires_at':
              DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch /
              1000,
          'provider': 'oidc',
        }),
        200,
      ),
    );
    await rejected;
    expect(secure.values.values.any((v) => v.contains('new-refresh')), isTrue);
    expect(
      secure.values.values.any((v) => v.contains('stale-refresh')),
      isFalse,
    );
  });

  test(
    'session search carrying native headers never follows redirects',
    () async {
      var calls = 0;
      final search = SessionSearchClient(
        baseUrl: 'https://dashboard.example.test/proxy',
        headers: () async => {'Authorization': 'Bearer search-token'},
        httpClient: MockClient((request) async {
          calls++;
          expect(request.followRedirects, isFalse);
          return http.Response('{"results":[]}', 200);
        }),
      );
      addTearDown(search.close);
      await search.search('native');
      expect(calls, 1);
    },
  );

  test(
    'a ticket completing after connection removal cannot open a socket',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: NativeMemoryCredentials(),
      );
      final connection = selected(id: 'stale-ticket');
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'ticket-access',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
      );
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final client = DashboardClient.fromConnection(
        connection,
        httpClient: MockClient((request) async {
          started.complete();
          return response.future;
        }),
      );
      addTearDown(client.close);
      final rejected = expectLater(
        client.mintWebSocketTicket(),
        throwsA(isA<DashboardNativeAuthException>()),
      );
      await started.future;
      await manager.deleteConnection(connection.id);
      response.complete(http.Response('{"ticket":"stale-ticket"}', 200));
      await rejected;
    },
  );

  test(
    'native dashboard enables chat authority predicates without an override',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: NativeMemoryCredentials(),
      );
      final connection = selected(
        id: 'chat-auth',
      ).copyWith(clearDesktopGatewayUrl: true);
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'chat-native',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
      );
      expect(DesktopGatewayClient.endpointDigestFor(connection), isNotNull);
      expect(
        shouldExplainApiOnlyPermissionDenial(connection, 'permission_denied'),
        isFalse,
      );
    },
  );

  test(
    'real redirect servers cannot receive dashboard bearer or refresh credentials',
    () async {
      final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var leakedRequests = 0;
      var sourceRequests = 0;
      final targetSub = target.listen((request) async {
        leakedRequests++;
        await request.drain<void>();
        request.response.write('{}');
        await request.response.close();
      });
      final sourceSub = origin.listen((request) async {
        sourceRequests++;
        await request.drain<void>();
        request.response.statusCode = 307;
        request.response.headers.set(
          'location',
          'http://127.0.0.1:${target.port}/collect',
        );
        await request.response.close();
      });
      addTearDown(() async {
        await sourceSub.cancel();
        await targetSub.cancel();
        await origin.close(force: true);
        await target.close(force: true);
      });
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: NativeMemoryCredentials(),
      );
      final connection = SavedConnection(
        id: 'redirect-wire',
        label: 'Loopback',
        host: '127.0.0.1',
        port: origin.port,
        apiKey: '',
        dashboardPortOverride: origin.port,
        dashboardPrefix: '/proxy',
      );
      await manager.importConnections([connection], replaceExisting: true);
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'wire-bearer',
        refreshToken: 'wire-refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        provider: 'oidc',
      );
      final client = HttpOverrides.runWithHttpOverrides(
        () => DashboardClient.fromConnection(connection),
        NativeRealHttpOverrides(),
      );
      addTearDown(client.close);
      for (final operation in <Future<dynamic> Function()>[
        () => client.apiGet('status'),
        () => client.apiGetList('list'),
        () => client.apiGetBytes('file'),
        () => client.apiGetBytes('bounded', maxBytes: 16),
        () => client.apiPost('write', body: {'a': 1}),
        () => client.apiPut('write', body: {'a': 1}),
        () => client.apiDelete('write'),
        () => client.mintWebSocketTicket(),
      ]) {
        await expectLater(operation(), throwsA(anything));
      }
      await manager.saveDashboardNativeTokens(
        connection,
        accessToken: 'expired',
        refreshToken: 'wire-refresh',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        provider: 'oidc',
      );
      // Account replacement intentionally revokes existing HTTP/socket owners.
      final renewedClient = HttpOverrides.runWithHttpOverrides(
        () => DashboardClient.fromConnection(connection),
        NativeRealHttpOverrides(),
      );
      addTearDown(renewedClient.close);
      await expectLater(
        renewedClient.apiGet('status'),
        throwsA(isA<DashboardNativeAuthException>()),
      );
      expect(sourceRequests, 9);
      expect(leakedRequests, 0);
    },
  );

  test('dashboard-backed session search refreshes an unexpected 401', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: NativeMemoryCredentials(),
    );
    final connection = selected(id: 'search-refresh');
    await manager.importConnections([connection], replaceExisting: true);
    await manager.saveDashboardNativeTokens(
      connection,
      accessToken: 'search-old',
      refreshToken: 'search-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      provider: 'oidc',
    );
    var refreshes = 0;
    final dashboard = DashboardClient.fromConnection(
      connection,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshes++;
          return http.Response(
            jsonEncode({
              'access_token': 'search-new',
              'refresh_token': 'rotated',
              'expires_at':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch /
                  1000,
              'provider': 'oidc',
            }),
            200,
          );
        }
        if (request.headers['authorization'] == 'Bearer search-old') {
          return http.Response('{}', 401);
        }
        return http.Response('{"results":[]}', 200);
      }),
    );
    addTearDown(dashboard.close);
    final search = SessionSearchClient(
      baseUrl: dashboard.baseUrl,
      headers: dashboard.authHeaders,
      dashboardClient: dashboard,
    );
    addTearDown(search.close);
    expect(await search.search('native'), isEmpty);
    expect(refreshes, 1);
  });

  test('an uncertain authenticated write is never retried', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: NativeMemoryCredentials(),
    );
    final connection = selected(id: 'uncertain-write');
    await manager.importConnections([connection], replaceExisting: true);
    await manager.saveDashboardNativeTokens(
      connection,
      accessToken: 'write-access',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      provider: 'oidc',
    );
    var calls = 0;
    final client = DashboardClient.fromConnection(
      connection,
      httpClient: MockClient((request) async {
        calls++;
        throw http.ClientException('connection ended after dispatch');
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.apiPost('config', body: {'a': 1}),
      throwsA(anything),
    );
    expect(calls, 1);
  });

  test('a ticket completing after sign-out is fenced', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: NativeMemoryCredentials(),
    );
    final connection = selected(id: 'signedout-ticket');
    await manager.importConnections([connection], replaceExisting: true);
    await manager.saveDashboardNativeTokens(
      connection,
      accessToken: 'ticket-access',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      provider: 'oidc',
    );
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final client = DashboardClient.fromConnection(
      connection,
      httpClient: MockClient((request) async {
        started.complete();
        return response.future;
      }),
    );
    addTearDown(client.close);
    final rejected = expectLater(
      client.mintWebSocketTicket(),
      throwsA(isA<DashboardNativeAuthException>()),
    );
    await started.future;
    await manager.clearDashboardNativeTokens(connection.id);
    response.complete(http.Response('{"ticket":"signedout-ticket"}', 200));
    await rejected;
  });

  test(
    'native credentials refuse remote cleartext dashboard transport',
    () async {
      SharedPreferences.setMockInitialValues({});
      final manager = ConnectionManager(
        await SharedPreferences.getInstance(),
        credentialStore: NativeMemoryCredentials(),
      );
      final connection = SavedConnection(
        id: 'no-cleartext',
        label: 'Remote',
        host: 'remote.example.test',
        port: 8642,
        apiKey: '',
      );
      await manager.importConnections([connection], replaceExisting: true);
      await expectLater(
        manager.saveDashboardNativeTokens(
          connection,
          accessToken: 'must-not-store',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          provider: 'oidc',
        ),
        throwsA(anything),
      );
    },
  );
}
