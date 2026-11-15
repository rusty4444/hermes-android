// Single sign-in for a Hermes dashboard ("remote gateway").
//
// One address and one sign-in reach everything: the dashboard's REST routes
// (sessions, cron, config, skills, analytics…) and its `/api/ws` JSON-RPC chat
// socket. There is no separate API-server key and no second dashboard login.
//
// Adapted from the way Kyllene (MIT, github.com/Giton22/kyllene) connects:
//   * the public `GET /api/status` probe discovers the version, whether a
//     sign-in is needed, which providers/flows the gateway offers and its
//     profiles (hermes_cli/web_routers/status.py `_auth_gate_status`),
//   * a password sign-in uses `POST /auth/password-login` (session cookie),
//   * a browser sign-in uses RFC 8252 + PKCE through a loopback redirect
//     (`/auth/native/authorize`, `/auth/native/token`, `/auth/native/refresh`)
//     and authenticates with `Authorization: Bearer`,
//   * gateways behind Cloudflare Access get a per-host service token.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/client_certificate.dart';
import 'tls_client_factory.dart';

/// Why an address isn't usable.
enum GatewayUrlProblem { required, scheme, invalid, noHost }

class InvalidGatewayUrlException implements Exception {
  final GatewayUrlProblem problem;
  final String detail;
  const InvalidGatewayUrlException(this.problem, [this.detail = '']);

  @override
  String toString() => switch (problem) {
    GatewayUrlProblem.required => 'Enter the address of your Hermes dashboard.',
    GatewayUrlProblem.scheme =>
      'The address must start with http:// or https:// (got $detail).',
    GatewayUrlProblem.invalid => 'That address is not valid.',
    GatewayUrlProblem.noHost => 'The address has no host name.',
  };
}

/// The normalised base URL of a Hermes dashboard, e.g.
/// `http://100.64.0.1:9119` or `https://hermes.example.ts.net/hermes`.
///
/// Scheme-less `host:port` gets `http://`, only http/https are accepted,
/// query/fragment are dropped and trailing slashes are trimmed.
@immutable
class GatewayUrl {
  final String value;
  const GatewayUrl._(this.value);

  Uri get uri => Uri.parse(value);
  String get host => uri.host;
  bool get isHttps => uri.scheme == 'https';

  /// The explicit port, or the scheme default.
  int get port => uri.hasPort ? uri.port : (isHttps ? 443 : 80);

  /// Path prefix (no trailing slash), '' at the root.
  String get pathPrefix {
    final path = uri.path;
    return path == '/' ? '' : path;
  }

  /// `scheme://host:port/prefix` with an explicit port. The form
  /// [DashboardClient] uses for its base URL, so credentials can be found by
  /// either spelling of the same gateway.
  String get canonical =>
      '${Uri(scheme: uri.scheme, host: host)}:$port$pathPrefix';

  /// `ws(s)://host[:port][/prefix]/api/ws`.
  String get webSocketUrl {
    final scheme = isHttps ? 'wss' : 'ws';
    return '$scheme://${uri.authority}$pathPrefix/api/ws';
  }

  /// Address without the scheme, for lists.
  String get display => value.replaceFirst(RegExp(r'^https?://'), '');

  /// Plain http to a host that isn't on a private network: the password,
  /// session cookie and every message cross the internet readable.
  bool get isExposed => !isHttps && !isPrivateHost(host);

  String resolve(String path) =>
      '$value/${path.startsWith('/') ? path.substring(1) : path}';

  static final _scheme = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);

  static GatewayUrl parse(String raw) {
    var input = raw.trim();
    if (input.isEmpty) {
      throw const InvalidGatewayUrlException(GatewayUrlProblem.required);
    }
    if (!_scheme.hasMatch(input)) input = 'http://$input';
    final scheme = input.substring(0, input.indexOf('://')).toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw InvalidGatewayUrlException(GatewayUrlProblem.scheme, '$scheme://');
    }
    final Uri uri;
    try {
      uri = Uri.parse(input);
    } on FormatException catch (e) {
      throw InvalidGatewayUrlException(GatewayUrlProblem.invalid, e.message);
    }
    if (uri.host.trim().isEmpty) {
      throw const InvalidGatewayUrlException(GatewayUrlProblem.noHost);
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final normalised = Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
    return GatewayUrl._(normalised);
  }

  static GatewayUrl? tryParse(String raw) {
    try {
      return parse(raw);
    } on InvalidGatewayUrlException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is GatewayUrl && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Canonical key (`scheme://host:port/prefix`) for any spelling of a base URL.
String canonicalGatewayKey(String baseUrl) =>
    GatewayUrl.tryParse(baseUrl)?.canonical ?? baseUrl;

/// Loopback, LAN and Tailscale (100.64.0.0/10, MagicDNS `.ts.net`) hosts,
/// and local-only names.
bool isPrivateHost(String host) {
  var name = host.toLowerCase().trim();
  if (name.startsWith('[')) name = name.substring(1);
  if (name.endsWith(']')) name = name.substring(0, name.length - 1);
  while (name.endsWith('.')) {
    name = name.substring(0, name.length - 1);
  }
  const suffixes = [
    '.ts.net',
    '.local',
    '.lan',
    '.home.arpa',
    '.internal',
    '.localhost',
  ];
  if (name == 'localhost' ||
      suffixes.any(name.endsWith) ||
      (!name.contains('.') && !name.contains(':'))) {
    return true;
  }
  if (name.contains(':')) {
    return name == '::1' ||
        name.startsWith('fc') ||
        name.startsWith('fd') ||
        name.startsWith('fe80');
  }
  final octets = name.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.any((o) => o == null)) return false;
  final a = octets[0]!, b = octets[1]!;
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b <= 127) ||
      (a == 169 && b == 254);
}

/// The subset of the public `GET /api/status` probe the app reads.
@immutable
class GatewayStatus {
  final String? version;
  final String? releaseDate;
  final bool gatewayRunning;
  final String? gatewayState;
  final int activeAgents;
  final int activeSessions;
  final bool authRequired;
  final List<String> authProviders;
  final List<String> authFlows;
  final List<String> profiles;
  final String? overall;

  const GatewayStatus({
    this.version,
    this.releaseDate,
    this.gatewayRunning = false,
    this.gatewayState,
    this.activeAgents = 0,
    this.activeSessions = 0,
    this.authRequired = false,
    this.authProviders = const [],
    this.authFlows = const [],
    this.profiles = const [],
    this.overall,
  });

  factory GatewayStatus.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? value
              .map(
                (e) => e is Map
                    ? (e['name'] ?? e['id'])?.toString()
                    : e?.toString(),
              )
              .whereType<String>()
              .where((e) => e.isNotEmpty)
              .toList()
        : const [];
    int count(Object? value) => value is int
        ? value
        : value is List
        ? value.length
        : int.tryParse('$value') ?? 0;
    return GatewayStatus(
      version: json['version']?.toString(),
      releaseDate: json['release_date']?.toString(),
      gatewayRunning: json['gateway_running'] == true,
      gatewayState: json['gateway_state']?.toString(),
      activeAgents: count(json['active_agents']),
      activeSessions: count(json['active_sessions']),
      authRequired: json['auth_required'] == true,
      authProviders: strings(json['auth_providers']),
      authFlows: strings(json['auth_flows']),
      profiles: strings(json['profiles']),
      overall: json['overall']?.toString(),
    );
  }

  /// The bundled username/password provider is registered.
  bool get supportsPasswordLogin => authProviders.contains('basic');

  /// RFC 8252 native PKCE sign-in is advertised.
  bool get supportsNativeSignIn => authFlows.contains('native_pkce');

  /// A gated dashboard needs a password provider or browser sign-in.
  bool get canSignIn =>
      !authRequired || supportsPasswordLogin || supportsNativeSignIn;

  /// How the user signs in, in words.
  String get signInSummary {
    if (!authRequired) return 'Not required';
    if (supportsPasswordLogin && supportsNativeSignIn) {
      return 'Password or browser';
    }
    if (supportsPasswordLogin) return 'Password';
    if (supportsNativeSignIn) return 'Browser';
    return 'Unsupported';
  }
}

/// What the probe found at an address.
sealed class ProbeResult {
  final GatewayUrl url;
  const ProbeResult(this.url);
}

/// A Hermes dashboard answered `/api/status`.
class ProbeReachable extends ProbeResult {
  final GatewayStatus status;
  const ProbeReachable(super.url, this.status);
}

/// Something answered, but not like a Hermes dashboard.
class ProbeNotHermes extends ProbeResult {
  final int? httpStatus;
  const ProbeNotHermes(super.url, this.httpStatus);
}

/// Cloudflare Access stopped the request before it reached Hermes.
class ProbeAccessBlocked extends ProbeResult {
  final int httpStatus;
  final bool tokenSent;
  const ProbeAccessBlocked(super.url, this.httpStatus, this.tokenSent);
}

/// Nothing answered (DNS, refused, timeout, TLS…).
class ProbeUnreachable extends ProbeResult {
  final String reason;
  const ProbeUnreachable(super.url, this.reason);
}

/// The server wants a client certificate.
class ProbeClientCertRequired extends ProbeResult {
  final String reason;
  const ProbeClientCertRequired(super.url, this.reason);
}

/// A Cloudflare Access service token for gateways behind Access.
@immutable
class AccessToken {
  final String clientId;
  final String clientSecret;
  const AccessToken(this.clientId, this.clientSecret);

  Map<String, String> toJson() => {
    'client_id': clientId,
    'client_secret': clientSecret,
  };

  static AccessToken? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['client_id'], secret = json['client_secret'];
    if (id is! String || secret is! String) return null;
    return AccessToken(id, secret);
  }
}

const cfAccessClientIdHeader = 'CF-Access-Client-Id';
const cfAccessClientSecretHeader = 'CF-Access-Client-Secret';

/// Bearer tokens from a browser sign-in. [expiresAt] is Unix seconds.
@immutable
class NativeSession {
  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String? provider;
  final String? userId;

  const NativeSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAt = 0,
    this.provider,
    this.userId,
  });

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt,
    'provider': ?provider,
    'user_id': ?userId,
  };

  static NativeSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final access = json['access_token'], refresh = json['refresh_token'];
    if (access is! String || access.isEmpty) return null;
    return NativeSession(
      accessToken: access,
      refreshToken: refresh is String ? refresh : '',
      expiresAt: switch (json['expires_at']) {
        final int v => v,
        final num v => v.toInt(),
        _ => 0,
      },
      provider: json['provider']?.toString(),
      userId: json['user_id']?.toString(),
    );
  }
}

/// Minimal secure key/value store, so tests can swap the platform keystore.
abstract interface class SignInSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _PlatformSignInSecretStore implements SignInSecretStore {
  static const _options = AndroidOptions(
    resetOnError: false,
    migrateWithBackup: true,
    storageNamespace: 'hermes_android_sign_in',
  );
  final _storage = const FlutterSecureStorage(aOptions: _options);

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory store used when the platform keystore isn't available (tests).
class MemorySignInSecretStore implements SignInSecretStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// The browser sign-in tokens and Cloudflare Access service tokens, kept in
/// the platform secure store and mirrored in memory so every HTTP client and
/// WebSocket in the app (classic and NextGen) can authenticate synchronously.
class HermesSignInVault extends ChangeNotifier {
  HermesSignInVault._(this._store);

  static HermesSignInVault instance = HermesSignInVault._(
    _PlatformSignInSecretStore(),
  );

  /// Replace the backing store (tests).
  @visibleForTesting
  static void resetForTesting([SignInSecretStore? store]) {
    instance = HermesSignInVault._(store ?? MemorySignInSecretStore());
    instance._loaded = true;
  }

  static const _tokensKey = 'native_tokens.v1';
  static const _accessKey = 'cf_access_tokens.v1';

  final SignInSecretStore _store;
  final Map<String, NativeSession> _tokens = {};
  final Map<String, AccessToken> _access = {};
  final Map<String, Future<NativeSession?>> _refreshing = {};
  final Map<String, DateTime> _refreshFailedAt = {};
  bool _loaded = false;
  Future<void>? _loading;

  /// Loads persisted tokens once. Safe to call repeatedly.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        final tokens = await _store.read(_tokensKey);
        if (tokens != null) {
          final decoded = jsonDecode(tokens);
          if (decoded is Map) {
            for (final e in decoded.entries) {
              final session = NativeSession.fromJson(e.value);
              if (session != null) _tokens[e.key.toString()] = session;
            }
          }
        }
        final access = await _store.read(_accessKey);
        if (access != null) {
          final decoded = jsonDecode(access);
          if (decoded is Map) {
            for (final e in decoded.entries) {
              final token = AccessToken.fromJson(e.value);
              if (token != null) _access[e.key.toString()] = token;
            }
          }
        }
      } catch (_) {
        // A damaged entry signs the user out of browser sessions; it never
        // blocks startup.
      }
      _loaded = true;
      notifyListeners();
    }();
  }

  Future<void> _persistTokens() => _tokens.isEmpty
      ? _store.delete(_tokensKey)
      : _store.write(
          _tokensKey,
          jsonEncode(_tokens.map((k, v) => MapEntry(k, v.toJson()))),
        );

  Future<void> _persistAccess() => _access.isEmpty
      ? _store.delete(_accessKey)
      : _store.write(
          _accessKey,
          jsonEncode(_access.map((k, v) => MapEntry(k, v.toJson()))),
        );

  /// Bearer tokens for the gateway whose base URL is [baseUrl], if any.
  NativeSession? sessionFor(String baseUrl) =>
      _tokens[canonicalGatewayKey(baseUrl)];

  /// Tokens for the gateway a request to [requestUrl] goes to: the longest
  /// base-URL prefix on the same host and port wins.
  NativeSession? sessionForRequest(Uri requestUrl) {
    final port = requestUrl.hasPort
        ? requestUrl.port
        : (requestUrl.scheme == 'https' || requestUrl.scheme == 'wss')
        ? 443
        : 80;
    final authority = '${requestUrl.host.toLowerCase()}:$port';
    String? best;
    for (final key in _tokens.keys) {
      final base = Uri.tryParse(key);
      if (base == null) continue;
      final basePort = base.hasPort
          ? base.port
          : (base.scheme == 'https' ? 443 : 80);
      if ('${base.host.toLowerCase()}:$basePort' != authority) continue;
      final prefix = base.path == '/' ? '' : base.path;
      if (prefix.isNotEmpty &&
          requestUrl.path != prefix &&
          !requestUrl.path.startsWith('$prefix/')) {
        continue;
      }
      if (best == null || key.length > best.length) best = key;
    }
    return best == null ? null : _tokens[best];
  }

  Future<void> setSession(String baseUrl, NativeSession? session) async {
    final key = canonicalGatewayKey(baseUrl);
    if (session == null) {
      if (_tokens.remove(key) == null) return;
    } else {
      _tokens[key] = session;
    }
    await _persistTokens();
    notifyListeners();
  }

  AccessToken? accessTokenFor(String host) => _access[_hostKey(host)];

  Future<void> setAccessToken(String host, AccessToken? token) async {
    final key = _hostKey(host);
    if (token == null) {
      if (_access.remove(key) == null) return;
    } else {
      _access[key] = token;
    }
    await _persistAccess();
    notifyListeners();
  }

  static String _hostKey(String host) {
    var name = host.toLowerCase().trim();
    if (name.startsWith('[')) name = name.substring(1);
    if (name.endsWith(']')) name = name.substring(0, name.length - 1);
    while (name.endsWith('.')) {
      name = name.substring(0, name.length - 1);
    }
    return name;
  }

  /// The Cloudflare Access headers for [uri]. Only over TLS: the secret must
  /// never cross a network in plain text.
  Map<String, String> accessHeadersFor(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'wss') return const {};
    final token = accessTokenFor(uri.host);
    if (token == null) return const {};
    return {
      cfAccessClientIdHeader: token.clientId,
      cfAccessClientSecretHeader: token.clientSecret,
    };
  }

  /// Refreshes the bearer tokens of [baseUrl] once; concurrent callers share
  /// the refresh so a burst of 401s cannot replay a rotated refresh token.
  ///
  /// Returns the new session, or null when the gateway rejected the refresh
  /// (the tokens are then forgotten and the user must sign in again).
  /// Throws [SocketException] when the gateway couldn't refresh right now.
  Future<NativeSession?> refresh(
    String baseUrl, {
    http.Client? client,
    String? expiredAccessToken,
  }) {
    final key = canonicalGatewayKey(baseUrl);
    final inFlight = _refreshing[key];
    if (inFlight != null) return inFlight;
    final current = _tokens[key];
    if (current == null) return Future.value(null);
    if (expiredAccessToken != null &&
        current.accessToken != expiredAccessToken) {
      // Another caller already refreshed while this one waited.
      return Future.value(current);
    }
    final failed = _refreshFailedAt[current.accessToken];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(seconds: 30)) {
      return Future.error(
        const SocketException(
          "The gateway couldn't renew the sign-in right now.",
        ),
      );
    }
    final future = () async {
      final owned = client ?? http.Client();
      try {
        final response = await owned
            .post(
              Uri.parse('$key/auth/native/refresh'),
              headers: {
                'Content-Type': 'application/json',
                ...accessHeadersFor(Uri.parse(key)),
              },
              body: jsonEncode({
                'refresh_token': current.refreshToken,
                'provider': current.provider ?? '',
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final next = NativeSession.fromJson(jsonDecode(response.body));
          if (next == null) throw const FormatException('No tokens returned');
          _refreshFailedAt.remove(current.accessToken);
          await setSession(key, next);
          return next;
        }
        if (response.statusCode == 401 || response.statusCode == 400) {
          await setSession(key, null);
          return null;
        }
        _refreshFailedAt[current.accessToken] = DateTime.now();
        throw const SocketException(
          "The gateway couldn't renew the sign-in: its sign-in provider is unreachable.",
        );
      } on SocketException {
        _refreshFailedAt[current.accessToken] = DateTime.now();
        rethrow;
      } on TimeoutException {
        _refreshFailedAt[current.accessToken] = DateTime.now();
        throw const SocketException('Timed out renewing the sign-in.');
      } finally {
        if (client == null) owned.close();
      }
    }();
    _refreshing[key] = future;
    future.whenComplete(() => _refreshing.remove(key)).ignore();
    return future;
  }
}

/// Builds the HTTP client used for probes and sign-in, honouring a client
/// certificate when the connection has one.
http.Client signInHttpClient(ClientCertificateConfig? certificate) =>
    const TlsClientFactory().createRestClient(certificate);

/// Public liveness probe used by "Test connection" before any sign-in.
class GatewayProbe {
  GatewayProbe({this._client, this.timeout = const Duration(seconds: 15)});

  final http.Client? _client;
  final Duration timeout;

  Future<ProbeResult> probe(
    GatewayUrl url, {
    ClientCertificateConfig? certificate,
  }) async {
    final client = _client ?? signInHttpClient(certificate);
    try {
      final uri = Uri.parse(url.resolve('api/status'));
      final accessHeaders = HermesSignInVault.instance.accessHeadersFor(uri);
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({'Accept': 'application/json', ...accessHeaders});
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      final code = response.statusCode;
      final contentType = response.headers['content-type'] ?? '';
      final isJson = contentType.contains('json');
      final tokenSent = accessHeaders.isNotEmpty;
      final location = response.headers['location'];
      final server = response.headers['server'];
      final cloudflareRefused =
          code == 403 && !isJson && (server?.toLowerCase() == 'cloudflare');
      if (_isAccessLoginRedirect(code, location) ||
          (cloudflareRefused && tokenSent)) {
        return ProbeAccessBlocked(url, code, tokenSent);
      }
      if (!isJson && _isClientCertReply(code, response.body)) {
        return ProbeClientCertRequired(url, 'HTTP $code');
      }
      if (cloudflareRefused) return ProbeAccessBlocked(url, code, false);
      if (code < 200 || code >= 300 || !isJson) {
        return ProbeNotHermes(url, code);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return ProbeNotHermes(url, code);
      final status = GatewayStatus.fromJson(decoded);
      if (status.version == null) return ProbeNotHermes(url, code);
      return ProbeReachable(url, status);
    } on FormatException {
      return ProbeNotHermes(url, null);
    } on TimeoutException {
      return ProbeUnreachable(
        url,
        'Timed out. Check the address, VPN or Tailscale connection.',
      );
    } on HandshakeException catch (e) {
      if (_isClientCertDemand(e)) {
        return ProbeClientCertRequired(url, e.message);
      }
      return ProbeUnreachable(url, 'TLS handshake failed: ${e.message}');
    } catch (e) {
      return ProbeUnreachable(url, _describe(e));
    } finally {
      if (_client == null) client.close();
    }
  }

  static bool _isAccessLoginRedirect(int code, String? location) {
    if (code < 300 || code > 399 || location == null) return false;
    final host = Uri.tryParse(location)?.host.toLowerCase() ?? '';
    return host.endsWith('.cloudflareaccess.com') ||
        location.contains('/cdn-cgi/access/');
  }

  static bool _isClientCertReply(int code, String body) {
    if (code == 495 || code == 496) return true;
    if (code != 400) return false;
    final text = body.length > 2048
        ? body.substring(0, 2048).toLowerCase()
        : body.toLowerCase();
    return text.contains('no required ssl certificate was sent') ||
        text.contains('the ssl certificate error');
  }

  static bool _isClientCertDemand(HandshakeException e) {
    final text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    return const [
      'certificate_required',
      'bad_certificate',
      'certificate_unknown',
      'unknown_ca',
    ].any(text.contains);
  }
}

String _describe(Object error) {
  if (error is SocketException) {
    return error.osError?.message.isNotEmpty == true
        ? error.osError!.message
        : error.message;
  }
  if (error is HttpException) return error.message;
  return error.toString();
}

/// The outcome of a sign-in attempt.
sealed class SignInResult {
  const SignInResult();
}

class SignInOk extends SignInResult {
  final String? user;
  const SignInOk([this.user]);
}

class SignInInvalidCredentials extends SignInResult {
  const SignInInvalidCredentials();
}

class SignInRateLimited extends SignInResult {
  const SignInRateLimited();
}

class SignInFailed extends SignInResult {
  final String message;
  const SignInFailed(this.message);
}

/// Who the stored sign-in belongs to (`GET /api/auth/me`).
@immutable
class AuthUser {
  final String? userId;
  final String? email;
  final String? displayName;
  final String? provider;
  const AuthUser({this.userId, this.email, this.displayName, this.provider});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    userId: json['user_id']?.toString(),
    email: json['email']?.toString(),
    displayName: json['display_name']?.toString(),
    provider: json['provider']?.toString(),
  );

  String get label => displayName ?? email ?? userId ?? 'Signed in';
}

/// Sign-in calls against a dashboard (hermes_cli/dashboard_auth/routes.py).
class HermesSignIn {
  HermesSignIn({this._client});

  final http.Client? _client;

  Future<T> _with<T>(
    ClientCertificateConfig? certificate,
    Future<T> Function(http.Client) body,
  ) async {
    final client = _client ?? signInHttpClient(certificate);
    try {
      return await body(client);
    } finally {
      if (_client == null) client.close();
    }
  }

  Map<String, String> _headers(Uri uri, {bool json = false}) => {
    if (json) 'Content-Type': 'application/json',
    'Accept': 'application/json',
    ...HermesSignInVault.instance.accessHeadersFor(uri),
  };

  /// `POST /auth/password-login` with the `basic` provider. The password is
  /// verified here, then kept in the connection's secure credentials so the
  /// app can re-establish the session cookie later without asking again.
  Future<SignInResult> passwordSignIn(
    GatewayUrl url, {
    required String username,
    required String password,
    String provider = 'basic',
    ClientCertificateConfig? certificate,
  }) => _with(certificate, (client) async {
    final uri = Uri.parse(url.resolve('auth/password-login'));
    try {
      final res = await client
          .post(
            uri,
            headers: _headers(uri, json: true),
            body: jsonEncode({
              'provider': provider,
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 401 || res.statusCode == 403) {
        return const SignInInvalidCredentials();
      }
      if (res.statusCode == 429) return const SignInRateLimited();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return SignInFailed('The gateway answered HTTP ${res.statusCode}.');
      }
      // Any previous browser sign-in would win over the cookie; forget it.
      await HermesSignInVault.instance.setSession(url.canonical, null);
      return SignInOk(username);
    } on TimeoutException {
      return const SignInFailed('The gateway took too long to answer.');
    } catch (e) {
      return SignInFailed(_describe(e));
    }
  });

  /// RFC 8252 browser sign-in: listens on the phone's loopback, opens the
  /// gateway's `/auth/native/authorize` page in the system browser, waits for
  /// the one-time code and redeems it with the PKCE verifier.
  Future<SignInResult> browserSignIn(
    GatewayUrl url, {
    required Future<bool> Function(Uri) openBrowser,
    String? provider,
    ClientCertificateConfig? certificate,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      return SignInFailed(
        "Couldn't get ready for the browser to come back: ${_describe(e)}",
      );
    }
    try {
      final verifier = _randomToken(32);
      final challenge = _base64Url(sha256.convert(utf8.encode(verifier)).bytes);
      final state = _randomToken(16);
      final redirectUri = 'http://127.0.0.1:${server.port}/callback';
      final authorize = Uri.parse(url.resolve('auth/native/authorize')).replace(
        queryParameters: {
          if (provider != null && provider.isNotEmpty) 'provider': provider,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'redirect_uri': redirectUri,
          'state': state,
        },
      );
      final code = Completer<String>();
      final subscription = server.listen((request) async {
        final query = request.uri.queryParameters;
        final matches =
            request.uri.path == '/callback' &&
            query['state'] == state &&
            (query['code']?.isNotEmpty ?? false);
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(
            matches
                ? _callbackPage('Signed in', 'You can go back to Hermes now.')
                : _callbackPage(
                    'Waiting for sign-in',
                    'This page is not part of the current sign-in.',
                  ),
          );
        await request.response.close();
        if (matches && !code.isCompleted) code.complete(query['code']!);
      });
      try {
        final opened = await openBrowser(authorize);
        if (!opened) {
          return const SignInFailed("Couldn't open the browser to sign in.");
        }
        final String received;
        try {
          received = await code.future.timeout(timeout);
        } on TimeoutException {
          return const SignInFailed('The sign-in took too long. Try again.');
        }
        return await _with(certificate, (client) async {
          final uri = Uri.parse(url.resolve('auth/native/token'));
          final res = await client
              .post(
                uri,
                headers: _headers(uri, json: true),
                body: jsonEncode({'code': received, 'code_verifier': verifier}),
              )
              .timeout(const Duration(seconds: 20));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            return SignInFailed(
              'The gateway refused the sign-in (HTTP ${res.statusCode}).',
            );
          }
          final session = NativeSession.fromJson(jsonDecode(res.body));
          if (session == null) {
            return const SignInFailed(
              'The gateway returned no sign-in tokens.',
            );
          }
          await HermesSignInVault.instance.setSession(url.canonical, session);
          return SignInOk(session.userId);
        });
      } finally {
        await subscription.cancel();
      }
    } catch (e) {
      return SignInFailed(_describe(e));
    } finally {
      await server.close(force: true);
    }
  }

  /// `GET /api/auth/me` with whatever credentials the caller supplies.
  Future<AuthUser?> me(
    GatewayUrl url, {
    required Map<String, String> authHeaders,
    ClientCertificateConfig? certificate,
  }) => _with(certificate, (client) async {
    final uri = Uri.parse(url.resolve('api/auth/me'));
    final res = await client
        .get(uri, headers: {..._headers(uri), ...authHeaders})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? AuthUser.fromJson(decoded) : null;
  });

  /// Best-effort server-side sign-out, then forget the local tokens.
  Future<void> signOut(
    GatewayUrl url, {
    Map<String, String> authHeaders = const {},
    ClientCertificateConfig? certificate,
  }) async {
    try {
      await _with(certificate, (client) async {
        final uri = Uri.parse(url.resolve('auth/logout'));
        await client
            .post(uri, headers: {..._headers(uri), ...authHeaders})
            .timeout(const Duration(seconds: 10));
      });
    } catch (_) {
      // Offline sign-out still clears the local session.
    }
    await HermesSignInVault.instance.setSession(url.canonical, null);
  }
}

String _callbackPage(String title, String body) =>
    '<!doctype html><html><head><meta name="viewport" '
    'content="width=device-width,initial-scale=1"><title>$title</title>'
    '<style>body{font-family:system-ui,sans-serif;background:rgb(10,10,12);'
    'color:rgb(244,244,246);display:flex;align-items:center;justify-content:center;'
    'height:100vh;margin:0}main{text-align:center;padding:24px}'
    'h1{font-size:22px;margin:0 0 8px}p{color:rgb(138,138,148)}</style></head>'
    '<body><main><h1>$title</h1><p>$body</p></main></body></html>';

final _random = Random.secure();

String _randomToken(int bytes) =>
    _base64Url(List<int>.generate(bytes, (_) => _random.nextInt(256)));

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// RFC 7636 helpers, exposed for tests.
@visibleForTesting
String pkceChallengeFor(String verifier) =>
    _base64Url(sha256.convert(utf8.encode(verifier)).bytes);
