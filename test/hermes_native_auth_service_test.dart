import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/hermes_native_auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'a state-bound OAuth error terminates without redeeming a code',
    () async {
      final service = HermesNativeAuthService(
        dashboardBaseUri: Uri.parse('https://dashboard.example'),
        trustedOrigin: Uri.parse('https://dashboard.example'),
        httpClientFactory: () =>
            MockClient((_) async => throw StateError('Must not redeem')),
        launchBrowser: (uri) async {
          expect(
            await _callback(Uri.parse(uri.queryParameters['redirect_uri']!), {
              'state': uri.queryParameters['state']!,
              'error': 'access_denied',
              'error_description': 'access-secret',
            }),
            200,
          );
          return true;
        },
      );
      addTearDown(service.dispose);
      await expectLater(
        service.authorize().timeout(const Duration(seconds: 1)),
        _failure(HermesNativeAuthFailure.callback),
      );
    },
  );

  test('refresh rotates tokens using the Hermes JSON contract', () async {
    final service = _service((request) async {
      if (request.url.path.endsWith('/refresh')) {
        expect(request.followRedirects, isFalse);
        expect(jsonDecode(request.body), {
          'refresh_token': 'refresh-secret',
          'provider': 'authentik',
        });
        return http.Response(
          jsonEncode({
            ..._payload(),
            'access_token': 'rotated',
            'refresh_token': 'rotated-refresh',
          }),
          200,
        );
      }
      return http.Response(jsonEncode(_payload()), 200);
    });
    addTearDown(service.dispose);
    final initial = await service.authorize();
    final rotated = await service.refresh(initial);
    expect(rotated.accessToken, 'rotated');
    expect(rotated.refreshToken, 'rotated-refresh');
  });

  test(
    'refresh refuses credentials from another dashboard and reports expired sessions',
    () async {
      var calls = 0;
      final service = _service((request) async {
        calls++;
        return request.url.path.endsWith('/refresh')
            ? http.Response('{"error":"session_expired"}', 401)
            : http.Response(jsonEncode(_payload()), 200);
      });
      addTearDown(service.dispose);
      final initial = await service.authorize();
      final foreign = HermesNativeCredentials(
        dashboardBaseUri: Uri.parse('https://evil.example'),
        accessToken: initial.accessToken,
        refreshToken: initial.refreshToken,
        provider: initial.provider,
        userId: initial.userId,
        expiresAt: initial.expiresAt,
      );
      await expectLater(
        service.refresh(foreign),
        _failure(HermesNativeAuthFailure.originMismatch),
      );
      expect(calls, 1);
      await expectLater(
        service.refresh(initial),
        _failure(HermesNativeAuthFailure.sessionExpired),
      );
    },
  );

  test(
    'rejects non-HTTPS or non-exact trusted dashboard origins before launching',
    () {
      for (final base in [
        'http://dashboard.example',
        'https://evil.example',
        'https://dashboard.example.evil.example',
        'https://dashboard.example:444',
        'https://user:password@dashboard.example',
        'https://dashboard.example/?token=secret',
        'https://dashboard.example/#secret',
        'https://dashboard.example/a%2fb',
        'https://dashboard.example/a%5cb',
      ]) {
        expect(
          () => HermesNativeAuthService(
            dashboardBaseUri: Uri.parse(base),
            trustedOrigin: Uri.parse('https://dashboard.example'),
            launchBrowser: (_) async => throw StateError('Must not launch'),
          ),
          throwsArgumentError,
          reason: base,
        );
      }
      expect(
        () => HermesNativeAuthService(
          dashboardBaseUri: Uri.parse('https://dashboard.example'),
          trustedOrigin: Uri.parse('https://dashboard.example/not-an-origin'),
          launchBrowser: (_) async => true,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'untrusted, malformed and duplicate callbacks cannot consume the login',
    () async {
      var exchanges = 0;
      final service = HermesNativeAuthService(
        dashboardBaseUri: Uri.parse('https://dashboard.example'),
        trustedOrigin: Uri.parse('https://dashboard.example'),
        httpClientFactory: () => MockClient((_) async {
          exchanges++;
          return http.Response(jsonEncode(_payload()), 200);
        }),
        launchBrowser: (uri) async {
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          final state = uri.queryParameters['state']!;
          expect(
            await _callback(redirect, {'state': 'forged', 'code': 'bad'}),
            400,
          );
          expect(
            await _callback(redirect.replace(path: '/wrong'), {
              'state': state,
              'code': 'bad',
            }),
            404,
          );
          expect(
            await _callback(redirect, {
              'state': state,
              'code': 'bad',
            }, method: 'POST'),
            405,
          );
          expect(
            await _callback(redirect, {
              'state': [state, state],
              'code': 'bad',
            }),
            400,
          );
          expect(
            await _callback(redirect, {
              'state': state,
              'code': ['bad', 'bad'],
            }),
            400,
          );
          expect(await _callback(redirect, {'state': state}), 400);
          expect(
            await _callback(redirect, {
              'state': state,
              'code': 'bad',
              'error': 'denied',
            }),
            400,
          );
          expect(
            await _callback(redirect, {
              'state': state,
              'code': 'bad',
            }, hostHeader: 'evil.example'),
            400,
          );
          expect(
            await _callback(redirect, {'state': state, 'code': 'valid'}),
            200,
          );
          expect(
            await _callback(redirect, {'state': state, 'code': 'replay'}),
            409,
          );
          return true;
        },
      );
      addTearDown(service.dispose);
      expect((await service.authorize()).provider, 'authentik');
      expect(exchanges, 1);
    },
  );

  test(
    'browser launch failure is bounded, sanitized and releases the login lease',
    () async {
      var released = 0;
      var acquired = false;
      final service = HermesNativeAuthService(
        dashboardBaseUri: Uri.parse('https://dashboard.example'),
        trustedOrigin: Uri.parse('https://dashboard.example'),
        acquireLoginLease: () async {
          acquired = true;
          return () async {
            released++;
          };
        },
        launchBrowser: (_) async {
          expect(acquired, isTrue);
          return false;
        },
      );
      addTearDown(service.dispose);
      await expectLater(
        service.authorize().timeout(const Duration(seconds: 1)),
        _failure(HermesNativeAuthFailure.browserLaunch),
      );
      expect(released, 1);
    },
  );

  test(
    'timeout closes loopback and releases the Android login lease',
    () async {
      final launched = Completer<Uri>();
      var released = 0;
      final service = HermesNativeAuthService(
        dashboardBaseUri: Uri.parse('https://dashboard.example'),
        trustedOrigin: Uri.parse('https://dashboard.example'),
        authorizationTimeout: const Duration(milliseconds: 100),
        acquireLoginLease: () async => () async {
          released++;
        },
        launchBrowser: (uri) async {
          launched.complete(uri);
          return true;
        },
      );
      addTearDown(service.dispose);
      final result = expectLater(
        service.authorize().timeout(const Duration(seconds: 1)),
        _failure(HermesNativeAuthFailure.timeout),
      );
      final uri = await launched.future;
      await result;
      expect(released, 1);
      await expectLater(
        _callback(Uri.parse(uri.queryParameters['redirect_uri']!), {}),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test(
    'cancel rejects concurrent login, closes listener and allows a new attempt',
    () async {
      final launched = Completer<Uri>();
      var launches = 0;
      var released = 0;
      final service = HermesNativeAuthService(
        dashboardBaseUri: Uri.parse('https://dashboard.example'),
        trustedOrigin: Uri.parse('https://dashboard.example'),
        acquireLoginLease: () async => () async {
          released++;
        },
        launchBrowser: (uri) async {
          launches++;
          if (!launched.isCompleted) launched.complete(uri);
          return true;
        },
      );
      final pending = expectLater(
        service.authorize(),
        _failure(HermesNativeAuthFailure.cancelled),
      );
      final uri = await launched.future;
      await expectLater(
        service.authorize(),
        _failure(HermesNativeAuthFailure.busy),
      );
      await service.cancel();
      await pending;
      expect(released, 1);
      await expectLater(
        _callback(Uri.parse(uri.queryParameters['redirect_uri']!), {}),
        throwsA(isA<SocketException>()),
      );
      final next = expectLater(
        service.authorize(),
        _failure(HermesNativeAuthFailure.cancelled),
      );
      while (launches < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      await service.dispose();
      await next;
      expect(released, 2);
      await expectLater(
        service.authorize(),
        _failure(HermesNativeAuthFailure.disposed),
      );
    },
  );

  test(
    'token exchange rejects redirects, HTTP errors and malformed bearer JSON without leaking secrets',
    () async {
      final responses = <(http.Response, HermesNativeAuthFailure)>[
        (
          http.Response(
            'access-secret',
            302,
            headers: {'location': 'https://evil.example/'},
          ),
          HermesNativeAuthFailure.http,
        ),
        (
          http.Response('{"detail":"refresh-secret"}', 400),
          HermesNativeAuthFailure.http,
        ),
        (http.Response('access-secret', 503), HermesNativeAuthFailure.http),
        (
          http.Response('not-json access-secret', 200),
          HermesNativeAuthFailure.invalidResponse,
        ),
        (http.Response('[]', 200), HermesNativeAuthFailure.invalidResponse),
        (
          http.Response(
            jsonEncode({..._payload(), 'token_type': 'Cookie'}),
            200,
          ),
          HermesNativeAuthFailure.invalidResponse,
        ),
        (
          http.Response(jsonEncode({..._payload(), 'access_token': ''}), 200),
          HermesNativeAuthFailure.invalidResponse,
        ),
        (
          http.Response(
            jsonEncode({
              ..._payload(),
              'access_token': 'secret\r\nInjected: yes',
            }),
            200,
          ),
          HermesNativeAuthFailure.invalidResponse,
        ),
        (
          http.Response(
            jsonEncode({..._payload(), 'expires_at': '2000000000'}),
            200,
          ),
          HermesNativeAuthFailure.invalidResponse,
        ),
        (
          http.Response(
            jsonEncode({..._payload(), 'refresh_token': null}),
            200,
          ),
          HermesNativeAuthFailure.invalidResponse,
        ),
        (
          http.Response(
            jsonEncode({..._payload(), 'provider': 'another'}),
            200,
          ),
          HermesNativeAuthFailure.invalidResponse,
        ),
        (
          http.Response('x' * 140000, 200),
          HermesNativeAuthFailure.invalidResponse,
        ),
      ];
      for (final (response, failure) in responses) {
        final service = _service((_) async => response);
        addTearDown(service.dispose);
        try {
          await service.authorize(provider: 'authentik');
          fail('Expected ${failure.name}');
        } on HermesNativeAuthException catch (e) {
          expect(e.failure, failure);
          expect(e.toString(), isNot(contains('secret')));
        }
      }
    },
  );

  test(
    'token transport failures and stalled HTTP are bounded and sanitized',
    () async {
      final service = _service(
        (_) async => throw const SocketException('access-secret'),
      );
      addTearDown(service.dispose);
      await expectLater(
        service.authorize(),
        _failure(HermesNativeAuthFailure.transport),
      );
      final stalled = _service(
        (_) => Completer<http.Response>().future,
        requestTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(stalled.dispose);
      await expectLater(
        stalled.authorize().timeout(const Duration(seconds: 1)),
        _failure(HermesNativeAuthFailure.timeout),
      );
    },
  );

  test(
    'native login uses loopback, S256 and the Hermes JSON bearer contract',
    () async {
      final requests = <http.Request>[];
      late Uri launched;
      final service = HermesNativeAuthService(
        dashboardBaseUri: Uri.parse('https://dashboard.example/hermes'),
        trustedOrigin: Uri.parse('https://dashboard.example'),
        httpClientFactory: () => MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(_payload()), 200);
        }),
        launchBrowser: (uri) async {
          launched = uri;
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          expect(redirect.scheme, 'http');
          expect(redirect.host, '127.0.0.1');
          expect(redirect.port, greaterThan(0));
          final response = await _callback(redirect, {
            'state': uri.queryParameters['state']!,
            'code': 'one-time-code',
          });
          expect(response, HttpStatus.ok);
          return true;
        },
      );
      addTearDown(service.dispose);

      final credentials = await service.authorize(provider: 'authentik');

      expect(launched.origin, 'https://dashboard.example');
      expect(launched.path, '/hermes/auth/native/authorize');
      expect(launched.queryParameters['provider'], 'authentik');
      expect(launched.queryParameters['code_challenge_method'], 'S256');
      expect(
        launched.queryParameters['state'],
        matches(RegExp(r'^[A-Za-z0-9_-]{43}$')),
      );
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://dashboard.example/hermes/auth/native/token',
      );
      expect(request.followRedirects, isFalse);
      expect(request.headers['content-type'], contains('application/json'));
      expect(request.headers.containsKey('cookie'), isFalse);
      expect(request.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, unorderedEquals(['code', 'code_verifier']));
      expect(body['code'], 'one-time-code');
      expect(
        body['code_verifier'],
        matches(RegExp(r'^[A-Za-z0-9_-]{43,128}$')),
      );
      final challenge = base64Url
          .encode(
            sha256.convert(ascii.encode(body['code_verifier'] as String)).bytes,
          )
          .replaceAll('=', '');
      expect(launched.queryParameters['code_challenge'], challenge);
      expect(
        launched.queryParameters.values,
        isNot(contains(body['code_verifier'])),
      );
      expect(credentials.accessToken, 'access-secret');
      expect(credentials.refreshToken, 'refresh-secret');
      expect(credentials.provider, 'authentik');
      expect(credentials.userId, 'user-1');
      expect(
        credentials.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(2000000000000, isUtc: true),
      );
      expect(
        credentials.dashboardBaseUri.toString(),
        'https://dashboard.example/hermes',
      );
    },
  );
}

HermesNativeAuthService _service(
  Future<http.Response> Function(http.Request) handler, {
  Duration requestTimeout = const Duration(seconds: 30),
}) => HermesNativeAuthService(
  dashboardBaseUri: Uri.parse('https://dashboard.example'),
  trustedOrigin: Uri.parse('https://dashboard.example'),
  requestTimeout: requestTimeout,
  httpClientFactory: () => MockClient(handler),
  launchBrowser: (uri) async {
    await _callback(Uri.parse(uri.queryParameters['redirect_uri']!), {
      'state': uri.queryParameters['state']!,
      'code': 'one-time-code',
    });
    return true;
  },
);

Matcher _failure(HermesNativeAuthFailure failure) => throwsA(
  isA<HermesNativeAuthException>().having((e) => e.failure, 'failure', failure),
);

Map<String, dynamic> _payload() => {
  'access_token': 'access-secret',
  'refresh_token': 'refresh-secret',
  'token_type': 'Bearer',
  'expires_at': 2000000000,
  'provider': 'authentik',
  'user_id': 'user-1',
};

Future<int> _callback(
  Uri redirect,
  Map<String, dynamic> parameters, {
  String method = 'GET',
  String? hostHeader,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      redirect.replace(queryParameters: parameters),
    );
    if (hostHeader != null) {
      request.headers.set(HttpHeaders.hostHeader, hostHeader);
    }
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}
