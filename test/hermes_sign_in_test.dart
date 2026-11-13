import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/hermes_sign_in.dart';
import 'package:hermes_android/core/services/lan_discovery_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => HermesSignInVault.resetForTesting(MemorySignInSecretStore()));

  group('GatewayUrl', () {
    test('adds http:// and trims slashes, query and fragment', () {
      final url = GatewayUrl.parse(' 192.168.1.20:9119/// ');
      expect(url.value, 'http://192.168.1.20:9119');
      expect(url.canonical, 'http://192.168.1.20:9119');
      expect(url.webSocketUrl, 'ws://192.168.1.20:9119/api/ws');
      expect(url.resolve('/api/status'), 'http://192.168.1.20:9119/api/status');
    });

    test('keeps a path prefix and gives https an explicit port', () {
      final url = GatewayUrl.parse('https://hermes.example.ts.net/hermes/?x=1');
      expect(url.value, 'https://hermes.example.ts.net/hermes');
      expect(url.canonical, 'https://hermes.example.ts.net:443/hermes');
      expect(url.webSocketUrl, 'wss://hermes.example.ts.net/hermes/api/ws');
      expect(url.display, 'hermes.example.ts.net/hermes');
    });

    test('rejects empty, foreign-scheme and host-less addresses', () {
      expect(
        () => GatewayUrl.parse(''),
        throwsA(isA<InvalidGatewayUrlException>()),
      );
      expect(
        () => GatewayUrl.parse('ftp://example.com'),
        throwsA(
          isA<InvalidGatewayUrlException>().having(
            (e) => e.problem,
            'problem',
            GatewayUrlProblem.scheme,
          ),
        ),
      );
      expect(GatewayUrl.tryParse('http://'), isNull);
    });

    test('flags plain http to a public host as exposed', () {
      expect(GatewayUrl.parse('http://203.0.113.9:9119').isExposed, isTrue);
      expect(GatewayUrl.parse('https://203.0.113.9').isExposed, isFalse);
      expect(GatewayUrl.parse('http://192.168.1.4:9119').isExposed, isFalse);
      expect(GatewayUrl.parse('http://100.64.0.1:9119').isExposed, isFalse);
      expect(GatewayUrl.parse('http://box.local:9119').isExposed, isFalse);
    });
  });

  test('isPrivateHost covers LAN, CGNAT/Tailscale and loopback', () {
    for (final host in [
      '10.0.0.2',
      '172.16.4.1',
      '192.168.0.10',
      '100.100.1.1',
      '127.0.0.1',
      'localhost',
      'server.lan',
      'box.tail1234.ts.net',
    ]) {
      expect(isPrivateHost(host), isTrue, reason: host);
    }
    for (final host in ['8.8.8.8', '172.32.0.1', 'example.com']) {
      expect(isPrivateHost(host), isFalse, reason: host);
    }
  });

  test('GatewayStatus reads auth providers, flows and profiles', () {
    final status = GatewayStatus.fromJson({
      'version': '0.9.0',
      'gateway_running': true,
      'auth_required': true,
      'auth_providers': [
        {'name': 'basic'},
      ],
      'auth_flows': ['cookie', 'native_pkce'],
      'profiles': ['default', 'sol'],
    });
    expect(status.supportsPasswordLogin, isTrue);
    expect(status.supportsNativeSignIn, isTrue);
    expect(status.canSignIn, isTrue);
    expect(status.signInSummary, 'Password or browser');
    expect(status.profiles, ['default', 'sol']);
    final open = GatewayStatus.fromJson({
      'version': '1',
      'auth_required': false,
    });
    expect(open.canSignIn, isTrue);
    expect(open.signInSummary, 'Not required');
  });

  test(
    'PKCE S256 challenge is base64url(sha256(verifier)) without padding',
    () {
      expect(
        pkceChallengeFor('dBjftJeZ4CVP-mJ92K3jSLiT0e3uqLXgTlLsZoZd7vo'),
        'yBx5J-7uRCuJdAOhx9MQiIr1B1e49eV6Tb-7sNxPLe0',
      );
    },
  );

  group('GatewayProbe', () {
    test('reports a reachable dashboard with its status', () async {
      final probe = GatewayProbe(
        client: MockClient((request) async {
          expect(request.url.path, '/api/status');
          return http.Response(
            jsonEncode({
              'version': '0.9.0',
              'gateway_running': true,
              'auth_required': true,
              'auth_providers': ['basic'],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final result = await probe.probe(GatewayUrl.parse('10.0.0.5:9119'));
      expect(result, isA<ProbeReachable>());
      expect((result as ProbeReachable).status.version, '0.9.0');
    });

    test('tells the API server apart from the dashboard', () async {
      final probe = GatewayProbe(
        client: MockClient(
          (_) async => http.Response(
            '{"status":"ok"}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      final result = await probe.probe(GatewayUrl.parse('10.0.0.5:8642'));
      expect(result, isA<ProbeNotHermes>());
    });

    test('sends a saved Cloudflare Access token', () async {
      await HermesSignInVault.instance.setAccessToken(
        'hermes.example.com',
        const AccessToken('id.access', 'secret'),
      );
      late Map<String, String> headers;
      final probe = GatewayProbe(
        client: MockClient((request) async {
          headers = request.headers;
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://team.cloudflareaccess.com/cdn-cgi/access/login',
            },
          );
        }),
      );
      final result = await probe.probe(
        GatewayUrl.parse('https://hermes.example.com'),
      );
      expect(headers['CF-Access-Client-Id'], 'id.access');
      expect(headers['CF-Access-Client-Secret'], 'secret');
      expect(result, isA<ProbeAccessBlocked>());
      expect((result as ProbeAccessBlocked).tokenSent, isTrue);
    });
  });

  group('HermesSignIn.passwordSignIn', () {
    test('posts the basic provider credentials', () async {
      late Map<String, dynamic> body;
      final signIn = HermesSignIn(
        client: MockClient((request) async {
          expect(request.url.path, '/auth/password-login');
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );
      final result = await signIn.passwordSignIn(
        GatewayUrl.parse('10.0.0.5:9119'),
        username: 'sam',
        password: 'pw',
      );
      expect(result, isA<SignInOk>());
      expect(body, {'provider': 'basic', 'username': 'sam', 'password': 'pw'});
    });

    test('maps 401 and 429', () async {
      for (final (code, type) in [
        (401, SignInInvalidCredentials),
        (429, SignInRateLimited),
      ]) {
        final result =
            await HermesSignIn(
              client: MockClient((_) async => http.Response('', code)),
            ).passwordSignIn(
              GatewayUrl.parse('10.0.0.5:9119'),
              username: 'u',
              password: 'p',
            );
        expect(result.runtimeType, type);
      }
    });
  });

  group('HermesSignInVault', () {
    test('finds a browser session by either spelling of the address', () async {
      final vault = HermesSignInVault.instance;
      await vault.setSession(
        'https://hermes.example.com/hermes',
        const NativeSession(
          accessToken: 'at',
          refreshToken: 'rt',
          expiresAt: 0,
          provider: 'oidc',
        ),
      );
      expect(
        vault.sessionFor('https://hermes.example.com:443/hermes')?.accessToken,
        'at',
      );
      expect(
        vault
            .sessionForRequest(
              Uri.parse('https://hermes.example.com/hermes/api/sessions'),
            )
            ?.accessToken,
        'at',
      );
      expect(
        vault.sessionForRequest(Uri.parse('https://hermes.example.com/other')),
        isNull,
      );
    });

    test('refresh replaces the tokens and persists them', () async {
      final store = MemorySignInSecretStore();
      HermesSignInVault.resetForTesting(store);
      final vault = HermesSignInVault.instance;
      const base = 'http://10.0.0.5:9119';
      await vault.setSession(
        base,
        const NativeSession(
          accessToken: 'old',
          refreshToken: 'rt',
          expiresAt: 0,
          provider: 'oidc',
        ),
      );
      final client = MockClient((request) async {
        expect(request.url.path, '/auth/native/refresh');
        expect(jsonDecode(request.body), {
          'refresh_token': 'rt',
          'provider': 'oidc',
        });
        return http.Response(
          jsonEncode({
            'access_token': 'new',
            'refresh_token': 'rt2',
            'expires_at': 9999999999,
            'provider': 'oidc',
          }),
          200,
        );
      });
      final next = await vault.refresh(
        base,
        client: client,
        expiredAccessToken: 'old',
      );
      expect(next?.accessToken, 'new');
      expect(vault.sessionFor(base)?.refreshToken, 'rt2');
      expect(store.values.values.join(), contains('rt2'));
    });
  });

  test('LAN discovery recognises a dashboard status body', () {
    expect(
      LanDiscoveryService.looksLikeDashboard(
        jsonEncode({'version': '0.9.0', 'auth_required': false}),
      ),
      isTrue,
    );
    expect(LanDiscoveryService.looksLikeDashboard('{"status":"ok"}'), isFalse);
    expect(LanDiscoveryService.looksLikeDashboard('<html>'), isFalse);
  });
}
