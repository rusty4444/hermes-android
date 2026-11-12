import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Must open a system browser, e.g. url_launcher's LaunchMode.externalApplication.
/// Never supply a WebView or in-app browser implementation.
typedef HermesBrowserLauncher = Future<bool> Function(Uri uri);

/// Acquire a bounded Android foreground-service lease before browser launch;
/// return an idempotent async release callback. This library has no Android
/// platform wiring: without a lease Android may freeze the loopback listener
/// while the browser is foreground. A Dart timer cannot prevent process freeze.
/// The platform service must not restart after process death (login is in memory).
/// Acquisition and release must themselves be bounded by the platform adapter.
typedef HermesLoginLease = Future<Future<void> Function()> Function();

enum HermesNativeAuthFailure {
  timeout,
  cancelled,
  busy,
  disposed,
  browserLaunch,
  callback,
  transport,
  http,
  invalidResponse,
  originMismatch,
  sessionExpired,
}

class HermesNativeAuthException implements Exception {
  final HermesNativeAuthFailure failure;
  final int? statusCode;
  const HermesNativeAuthException(this.failure, {this.statusCode});
  @override
  String toString() =>
      'Hermes native authentication failed: ${failure.name}${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

class HermesNativeCredentials {
  final Uri dashboardBaseUri;
  final String accessToken;
  final String refreshToken;
  final String provider;
  final String userId;
  final DateTime expiresAt;

  const HermesNativeCredentials({
    required this.dashboardBaseUri,
    required this.accessToken,
    required this.refreshToken,
    required this.provider,
    required this.userId,
    required this.expiresAt,
  });
}

/// Hermes dashboard broker flow, not a direct OIDC client of Authentik.
///
/// Wire contract verified against dashboard_auth/routes.py and native_flow.py:
/// authorize GET carries S256/state/loopback redirect (no client_id); token POST
/// JSON has code/code_verifier; refresh POST JSON has refresh_token/provider.
/// Both return access_token, refresh_token, token_type=Bearer, expires_at in
/// Unix seconds, provider and user_id. Cookies and upstream ID tokens are not
/// credentials for this flow. Callers own secure storage and bearer attachment.
///
/// The trusted origin must come from explicit user/operator configuration, not
/// discovery redirects. Factory clients must be fresh, credential-free, preserve
/// normal TLS validation and honor followRedirects=false; the service closes each
/// client. One authorization/refresh is allowed at a time. Secrets are never
/// logged; exceptions intentionally omit response bodies and underlying errors.
class HermesNativeAuthService {
  final Uri dashboardBaseUri;
  final Uri trustedOrigin;
  final HermesBrowserLauncher _launchBrowser;
  final http.Client Function() _httpClientFactory;
  final Duration authorizationTimeout;
  final Duration requestTimeout;
  final HermesLoginLease? _acquireLoginLease;
  _NativeOperation? _active;
  bool _disposed = false;

  HermesNativeAuthService({
    required this.dashboardBaseUri,
    required this.trustedOrigin,
    required this._launchBrowser,
    http.Client Function()? httpClientFactory,
    this.authorizationTimeout = const Duration(minutes: 5),
    this.requestTimeout = const Duration(seconds: 30),
    this._acquireLoginLease,
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new {
    bool safe(Uri uri) =>
        uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        !RegExp(r'[%\\\x00-\x20\x7f]').hasMatch(uri.authority) &&
        !RegExp(r'%2f|%5c|%00|%0[ad]', caseSensitive: false).hasMatch(uri.path);
    if (!safe(dashboardBaseUri) ||
        !safe(trustedOrigin) ||
        (trustedOrigin.path.isNotEmpty && trustedOrigin.path != '/') ||
        dashboardBaseUri.origin != trustedOrigin.origin) {
      throw ArgumentError(
        'A dashboard URL and matching explicitly trusted HTTPS origin are required.',
      );
    }
  }

  Future<HermesNativeCredentials> authorize({String? provider}) async {
    final operation = _begin(authorizationTimeout);
    HttpServer? server;
    StreamSubscription<HttpRequest>? subscription;
    try {
      final random = Random.secure();
      String secret() => base64Url
          .encode(List<int>.generate(32, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final state = secret();
      final verifier = secret();
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      server = await operation.wait(
        HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false).then((
          bound,
        ) {
          if (operation.finished) {
            unawaited(bound.close(force: true));
          }
          return bound;
        }),
      );
      final boundServer = server!;
      final redirect = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: boundServer.port,
        path: '/oauth/callback',
      );
      final code = Completer<String>();
      subscription = boundServer.listen((request) async {
        final params = request.uri.queryParametersAll;
        String? single(String key) {
          final values = params[key];
          return values != null &&
                  values.length == 1 &&
                  values.single.isNotEmpty
              ? values.single
              : null;
        }

        var status = HttpStatus.badRequest;
        if (request.uri.path != redirect.path) {
          status = HttpStatus.notFound;
        } else if (request.method != 'GET') {
          status = HttpStatus.methodNotAllowed;
        } else if (request.headers.value(HttpHeaders.hostHeader) !=
                redirect.authority ||
            request.requestedUri.origin != redirect.origin ||
            single('state') != state ||
            (params.containsKey('code') == params.containsKey('error')) ||
            (params.containsKey('code') && single('code') == null) ||
            (params.containsKey('error') && single('error') == null)) {
          status = HttpStatus.badRequest;
        } else if (code.isCompleted) {
          status = HttpStatus.conflict;
        } else {
          status = HttpStatus.ok;
          // A value sentinel avoids an unhandled error before launcher returns.
          code.complete(params.containsKey('error') ? '' : single('code')!);
        }
        request.response.statusCode = status;
        request.response.headers
          ..contentType = ContentType.text
          ..set(HttpHeaders.cacheControlHeader, 'no-store')
          ..set('Referrer-Policy', 'no-referrer')
          ..set(
            'Content-Security-Policy',
            "default-src 'none'; frame-ancestors 'none'",
          );
        request.response.write(
          status == HttpStatus.ok
              ? 'Sign-in received. You can return to the app.'
              : 'Invalid sign-in callback.',
        );
        await request.response.close();
      });
      if (_acquireLoginLease != null) {
        await operation.wait(
          _acquireLoginLease().then((release) async {
            if (operation.finished) {
              await release();
            } else {
              operation.releaseLease = release;
            }
          }),
        );
      }
      final authorizeUri = _endpoint('authorize').replace(
        queryParameters: {
          'provider': ?provider,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'redirect_uri': redirect.toString(),
          'state': state,
        },
      );
      final bool launched;
      try {
        launched = await operation.wait(_launchBrowser(authorizeUri));
      } on HermesNativeAuthException {
        rethrow;
      } catch (_) {
        throw const HermesNativeAuthException(
          HermesNativeAuthFailure.browserLaunch,
        );
      }
      if (!launched) {
        throw const HermesNativeAuthException(
          HermesNativeAuthFailure.browserLaunch,
        );
      }
      final gatewayCode = await operation.wait(code.future);
      if (gatewayCode.isEmpty) {
        throw const HermesNativeAuthException(HermesNativeAuthFailure.callback);
      }
      return await _post(operation, 'token', {
        'code': gatewayCode,
        'code_verifier': verifier,
      }, expectedProvider: provider);
    } on HermesNativeAuthException {
      rethrow;
    } catch (_) {
      throw const HermesNativeAuthException(HermesNativeAuthFailure.transport);
    } finally {
      operation.finish();
      await server?.close(force: true);
      await subscription?.cancel();
      await operation.release();
      _active = null;
      operation.done.complete();
    }
  }

  Future<HermesNativeCredentials> _post(
    _NativeOperation operation,
    String action,
    Map<String, String> payload, {
    String? expectedProvider,
  }) async {
    final client = _httpClientFactory();
    try {
      final request = http.Request('POST', _endpoint(action))
        ..followRedirects = false
        ..headers['content-type'] = 'application/json'
        ..headers['accept'] = 'application/json'
        ..headers['cache-control'] = 'no-store'
        ..body = jsonEncode(payload);
      Future<HermesNativeCredentials> exchange() async {
        final response = await operation.wait(client.send(request));
        if (response.statusCode != 200) {
          throw HermesNativeAuthException(
            action == 'refresh' && response.statusCode == 401
                ? HermesNativeAuthFailure.sessionExpired
                : HermesNativeAuthFailure.http,
            statusCode: response.statusCode,
          );
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 131072) {
            throw const HermesNativeAuthException(
              HermesNativeAuthFailure.invalidResponse,
            );
          }
          bytes.addAll(chunk);
        }
        return _credentials(bytes, expectedProvider: expectedProvider);
      }

      return await operation.wait(
        exchange().timeout(
          requestTimeout,
          onTimeout: () {
            throw const HermesNativeAuthException(
              HermesNativeAuthFailure.timeout,
            );
          },
        ),
      );
    } on HermesNativeAuthException {
      rethrow;
    } catch (_) {
      throw const HermesNativeAuthException(HermesNativeAuthFailure.transport);
    } finally {
      client.close();
    }
  }

  HermesNativeCredentials _credentials(
    List<int> bytes, {
    String? expectedProvider,
  }) {
    try {
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      String field(String key, {bool allowEmpty = false}) {
        final value = body[key];
        if (value is! String ||
            (!allowEmpty && value.isEmpty) ||
            RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
          throw const FormatException();
        }
        return value;
      }

      if (body['token_type'] != 'Bearer' ||
          body['expires_at'] is! int ||
          (body['expires_at'] as int) <= 0) {
        throw const FormatException();
      }
      final provider = field('provider');
      if (expectedProvider != null &&
          expectedProvider.isNotEmpty &&
          provider != expectedProvider) {
        throw const FormatException();
      }
      return HermesNativeCredentials(
        dashboardBaseUri: dashboardBaseUri,
        accessToken: field('access_token'),
        refreshToken: field('refresh_token', allowEmpty: true),
        provider: provider,
        userId: field('user_id'),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          (body['expires_at'] as int) * 1000,
          isUtc: true,
        ),
      );
    } catch (_) {
      throw const HermesNativeAuthException(
        HermesNativeAuthFailure.invalidResponse,
      );
    }
  }

  Uri _endpoint(String action) => dashboardBaseUri.replace(
    path:
        '${dashboardBaseUri.path.replaceFirst(RegExp(r'/+$'), '')}/auth/native/$action',
  );

  _NativeOperation _begin(Duration timeout) {
    if (_disposed) {
      throw const HermesNativeAuthException(HermesNativeAuthFailure.disposed);
    }
    if (_active != null) {
      throw const HermesNativeAuthException(HermesNativeAuthFailure.busy);
    }
    return _active = _NativeOperation(timeout);
  }

  Future<HermesNativeCredentials> refresh(
    HermesNativeCredentials credentials,
  ) async {
    if (credentials.dashboardBaseUri != dashboardBaseUri) {
      throw const HermesNativeAuthException(
        HermesNativeAuthFailure.originMismatch,
      );
    }
    if (credentials.refreshToken.isEmpty) {
      throw const HermesNativeAuthException(
        HermesNativeAuthFailure.sessionExpired,
      );
    }
    final operation = _begin(requestTimeout);
    try {
      return await _post(operation, 'refresh', {
        'refresh_token': credentials.refreshToken,
        'provider': credentials.provider,
      }, expectedProvider: credentials.provider);
    } finally {
      operation.finish();
      _active = null;
      operation.done.complete();
    }
  }

  Future<void> cancel() async {
    final active = _active;
    if (active == null) return;
    active.abort(HermesNativeAuthFailure.cancelled);
    await active.done.future;
  }

  Future<void> dispose() async {
    _disposed = true;
    await cancel();
  }
}

class _NativeOperation {
  final _abort = Completer<HermesNativeAuthFailure>();
  final done = Completer<void>();
  late final Timer _timer;
  bool finished = false;
  Future<void> Function()? releaseLease;

  _NativeOperation(Duration timeout) {
    _timer = Timer(timeout, () => abort(HermesNativeAuthFailure.timeout));
  }

  void abort(HermesNativeAuthFailure failure) {
    if (!_abort.isCompleted && !finished) _abort.complete(failure);
  }

  Future<T> wait<T>(Future<T> future) => Future.any([
    future,
    _abort.future.then<T>(
      (failure) => throw HermesNativeAuthException(failure),
    ),
  ]);

  void finish() {
    finished = true;
    _timer.cancel();
  }

  Future<void> release() async {
    try {
      await releaseLease?.call();
    } catch (_) {
      /* Cleanup must not expose native secrets. */
    }
  }
}
