import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/connection.dart';
import 'connection_manager.dart'
    show CredentialStore, CredentialStorageException;
import 'connection_mutation_barrier.dart';
import 'desktop_gateway_client.dart';

enum DashboardNativeSessionStatus {
  notConfigured,
  signedIn,
  expired,
  signedOut,
}

/// Never includes a provider error, response body, URL, or credential.
class DashboardNativeAuthException implements Exception {
  const DashboardNativeAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Opaque, one-attempt authority captured before launching a browser.
class DashboardNativeSignInAttempt {
  DashboardNativeSignInAttempt._(
    this._store,
    this._id,
    this._baseUrl,
    this._profile,
    this._epoch,
    this._generation,
  );
  final DashboardNativeAuthStore _store;
  final String _id;
  final String _baseUrl;
  final String? _profile;
  final Object? _epoch;
  final Object? _generation;
}

/// Native dashboard tokens are intentionally separate from exported connection
/// credentials. The issuing URL includes its reverse-proxy prefix.
class DashboardNativeAuthStore {
  DashboardNativeAuthStore({
    required CredentialStore credentialStore,
    required SavedConnection? Function(String id) connectionById,
    DateTime Function()? now,
  }) : _storage = credentialStore,
       // ignore: prefer_initializing_formals
       _connectionById = connectionById,
       _now = now ?? DateTime.now;

  final CredentialStore _storage;
  final SavedConnection? Function(String id) _connectionById;
  final DateTime Function() _now;
  final _versions = <String, Object>{};
  // Storage failure must not resurrect a locally revoked principal.
  final _signedOutIds = <String>{};
  final _tails = <String, Future<void>>{};
  final _flights = <(String, String, String?, Object?), Future<String?>>{};

  static String baseUrlFor(SavedConnection c) =>
      DesktopGatewayClient.normalizedGatewayBaseUrl(c);
  static String? profileFor(String? profile) =>
      profile?.trim().isEmpty == true ? null : profile?.trim();
  static String _key(String id) =>
      'dashboard_native_auth_v1.${sha256.convert(utf8.encode(id))}';

  static void _requireSafeTransport(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    if (uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                {'127.0.0.1', '::1', 'localhost'}.contains(uri.host)))) {
      throw const DashboardNativeAuthException(
        'Dashboard sign-in requires HTTPS.',
      );
    }
  }

  bool _matches(String id, String baseUrl, String? profile) {
    final c = _connectionById(id);
    return c != null &&
        baseUrlFor(c) == baseUrl &&
        profileFor(c.gatewayProfile) == profileFor(profile);
  }

  void checkBinding(String id, String baseUrl, String? profile, Object? epoch) {
    if (!ConnectionMutationBarrier.isCurrent(id, epoch) ||
        !_matches(id, baseUrl, profile)) {
      throw const DashboardNativeAuthException('Dashboard connection changed.');
    }
  }

  void Function() requestFence(String id) {
    final version = _versions[id];
    return () {
      if (!identical(_versions[id], version)) {
        throw const DashboardNativeAuthException('Dashboard sign-in changed.');
      }
    };
  }

  DashboardNativeSignInAttempt beginSignIn(SavedConnection connection) {
    final id = connection.id;
    final baseUrl = baseUrlFor(connection);
    final profile = profileFor(connection.gatewayProfile);
    final epoch = ConnectionMutationBarrier.capture(id);
    _requireSafeTransport(baseUrl);
    checkBinding(id, baseUrl, profile, epoch);
    final generation = Object();
    _versions[id] = generation;
    return DashboardNativeSignInAttempt._(
      this,
      id,
      baseUrl,
      profile,
      epoch,
      generation,
    );
  }

  void checkSignInAttempt(
    DashboardNativeSignInAttempt attempt,
    SavedConnection connection,
  ) {
    if (!identical(attempt._store, this) ||
        attempt._id != connection.id ||
        attempt._baseUrl != baseUrlFor(connection) ||
        attempt._profile != profileFor(connection.gatewayProfile) ||
        !identical(attempt._generation, _versions[connection.id])) {
      throw const DashboardNativeAuthException('Dashboard sign-in changed.');
    }
    checkBinding(
      attempt._id,
      attempt._baseUrl,
      attempt._profile,
      attempt._epoch,
    );
  }

  Future<T> _serial<T>(String id, Future<T> Function() action) {
    final previous = _tails[id];
    final done = Completer<void>();
    final tail = done.future;
    _tails[id] = tail;
    return (() async {
      try {
        if (previous != null) await previous;
        return await action();
      } finally {
        if (identical(_tails[id], tail)) _tails.remove(id);
        done.complete();
      }
    })();
  }

  Future<void> _write(String id, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(_key(id));
      } else {
        await _storage.write(_key(id), value);
      }
      if (await _storage.read(_key(id)) != value) {
        throw const FormatException();
      }
    } catch (_) {
      throw const CredentialStorageException(
        'Dashboard sign-in could not be stored safely.',
      );
    }
  }

  Future<Map<String, dynamic>?> _read(String id) async {
    try {
      final value = await _storage.read(_key(id));
      if (value == null) return null;
      final data = jsonDecode(value) as Map<String, dynamic>;
      if (data['base_url'] is! String) throw const FormatException();
      if (data['signed_out'] != true) _validate(data);
      return data;
    } catch (_) {
      throw const CredentialStorageException(
        'Dashboard sign-in could not be read safely.',
      );
    }
  }

  static void _validate(Map<String, dynamic> data) {
    final access = data['access_token'];
    final expiry = data['expires_at'];
    if (access is! String ||
        access.isEmpty ||
        RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(access) ||
        expiry is! num ||
        !expiry.isFinite ||
        expiry <= 0 ||
        data['provider'] is! String ||
        (data['refresh_token'] != null && data['refresh_token'] is! String) ||
        (data['user_id'] != null && data['user_id'] is! String)) {
      throw const DashboardNativeAuthException(
        'Invalid dashboard token response.',
      );
    }
  }

  Future<void> save(
    SavedConnection connection, {
    required String accessToken,
    String? refreshToken,
    required DateTime expiresAt,
    required String provider,
    String? userId,
  }) {
    final id = connection.id;
    final baseUrl = baseUrlFor(connection);
    _requireSafeTransport(baseUrl);
    final profile = profileFor(connection.gatewayProfile);
    final data = <String, dynamic>{
      'base_url': baseUrl,
      'profile': profile,
      'access_token': accessToken,
      'refresh_token': refreshToken ?? '',
      'expires_at': expiresAt.millisecondsSinceEpoch / 1000,
      'provider': provider,
      'user_id': userId ?? '',
    };
    _validate(data);
    final version = Object();
    _versions[id] = version;
    return _serial(id, () async {
      if (!identical(_versions[id], version) ||
          !_matches(id, baseUrl, profile)) {
        throw const DashboardNativeAuthException(
          'Dashboard connection changed.',
        );
      }
      await _write(id, jsonEncode(data));
      if (!identical(_versions[id], version)) {
        throw const DashboardNativeAuthException('Dashboard sign-in changed.');
      }
      _signedOutIds.remove(id);
    });
  }

  /// Invalidate synchronously, then serialize deletion behind any secure write.
  Future<void> clear(String id, {bool requireSignIn = false}) {
    _versions[id] = Object();
    if (requireSignIn) _signedOutIds.add(id);
    return _serial(id, () async {
      final connection = _connectionById(id);
      // Native-required mode does not depend on a previous token bundle.
      // Configuring native auth on an empty store must already fail closed.
      final previous = requireSignIn
          ? (connection == null
                ? await _read(id)
                : <String, dynamic>{
                    'base_url': baseUrlFor(connection),
                    'profile': profileFor(connection.gatewayProfile),
                  })
          : null;
      await _write(id, previous == null ? null : _signedOut(previous));
      if (!requireSignIn) _signedOutIds.remove(id);
    });
  }

  /// Persist revocation before touching legacy secrets or metadata. Do not
  /// decode the old bundle: even a corrupt native record forbids downgrade.
  /// The tombstone survives rollback/restart; only committed removal clears it.
  Future<void> prepareRemoval(String id) {
    _versions[id] = Object();
    return _serial(id, () async {
      final String? previous;
      try {
        previous = await _storage.read(_key(id));
      } catch (_) {
        throw const CredentialStorageException(
          'Dashboard sign-in could not be read safely.',
        );
      }
      if (previous == null) return;
      _signedOutIds.add(id);
      final connection = _connectionById(id);
      await _write(
        id,
        _signedOut({
          'base_url': connection == null ? '' : baseUrlFor(connection),
          'profile': connection == null
              ? null
              : profileFor(connection.gatewayProfile),
        }),
      );
    });
  }

  static String _signedOut(Map<String, dynamic> data) => jsonEncode({
    'base_url': data['base_url'],
    'profile': data['profile'],
    'signed_out': true,
  });

  /// Keep native-required mode independently of the secret/principal binding.
  /// Endpoint/profile edits revoke tokens, never authorize a legacy downgrade.
  Future<void> rebind(
    SavedConnection connection, {
    bool requireSignIn = false,
  }) {
    final id = connection.id;
    _versions[id] = Object();
    return _serial(id, () async {
      final previous = await _read(id);
      if (previous == null && !requireSignIn) return;
      final baseUrl = baseUrlFor(connection);
      final profile = profileFor(connection.gatewayProfile);
      if (previous?['base_url'] == baseUrl && previous?['profile'] == profile) {
        return;
      }
      _signedOutIds.add(id);
      await _write(id, _signedOut({'base_url': baseUrl, 'profile': profile}));
    });
  }

  Future<DashboardNativeSessionStatus> status(
    SavedConnection connection,
  ) async {
    final data = await _serial(connection.id, () => _read(connection.id));
    if (_signedOutIds.contains(connection.id)) {
      return DashboardNativeSessionStatus.signedOut;
    }
    if (data == null) {
      return DashboardNativeSessionStatus.notConfigured;
    }
    if (data['signed_out'] == true ||
        data['base_url'] != baseUrlFor(connection) ||
        data['profile'] != profileFor(connection.gatewayProfile)) {
      return DashboardNativeSessionStatus.signedOut;
    }
    return _now().millisecondsSinceEpoch / 1000 >=
            (data['expires_at'] as num) - 30
        ? DashboardNativeSessionStatus.expired
        : DashboardNativeSessionStatus.signedIn;
  }

  bool hasCachedSession(SavedConnection connection) {
    return hasCachedBinding(
      connection.id,
      baseUrlFor(connection),
      connection.gatewayProfile,
    );
  }

  bool hasCachedBinding(String id, String baseUrl, String? profile) {
    if (_signedOutIds.contains(id)) return true;
    try {
      final raw = _storage.readCached(_key(id));
      if (raw == null) return false;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // Presence means native-required even when an interrupted endpoint edit
      // left an old binding. Only an explicit mode switch may remove it.
      return data['base_url'] is String;
    } catch (_) {
      return false;
    }
  }

  Future<void> hydrate(String id) => _serial(id, () async {
    await _read(id);
  });

  Future<String?> accessToken({
    required String connectionId,
    required String baseUrl,
    required String? profile,
    required Object? epoch,
    required http.Client httpClient,
    String? rejectedToken,
  }) {
    checkBinding(connectionId, baseUrl, profile, epoch);
    final key = (
      connectionId,
      baseUrl,
      profileFor(profile),
      _versions[connectionId],
    );
    final flight = _flights[key];
    if (flight != null) return flight;
    final version = _versions[connectionId];
    final future = _accessToken(
      connectionId,
      baseUrl,
      profile,
      epoch,
      version,
      httpClient,
      rejectedToken,
    );
    _flights[key] = future;
    future.whenComplete(() {
      if (identical(_flights[key], future)) _flights.remove(key);
    }).ignore();
    return future;
  }

  Future<String?> _accessToken(
    String id,
    String baseUrl,
    String? profile,
    Object? epoch,
    Object? version,
    http.Client client,
    String? rejectedToken,
  ) async {
    void check() {
      checkBinding(id, baseUrl, profile, epoch);
      if (!identical(_versions[id], version)) {
        throw const DashboardNativeAuthException('Dashboard sign-in changed.');
      }
    }

    final data = await _serial(id, () => _read(id));
    check();
    if (_signedOutIds.contains(id)) {
      throw const DashboardNativeAuthException(
        'Dashboard sign-in expired. Sign in again.',
      );
    }
    if (data == null) return null;
    if (data['base_url'] != baseUrl || data['profile'] != profileFor(profile)) {
      throw const DashboardNativeAuthException(
        'Dashboard connection changed. Sign in again.',
      );
    }
    _requireSafeTransport(baseUrl);
    if (data['signed_out'] == true) {
      throw const DashboardNativeAuthException(
        'Dashboard sign-in expired. Sign in again.',
      );
    }
    final token = data['access_token'] as String;
    if (rejectedToken != token &&
        (_now().millisecondsSinceEpoch / 1000) <
            (data['expires_at'] as num) - 30) {
      return token;
    }
    final refresh = data['refresh_token'] as String? ?? '';
    if (refresh.isEmpty) {
      await _serial(id, () async {
        check();
        await _write(id, _signedOut(data));
      });
      throw const DashboardNativeAuthException(
        'Dashboard sign-in expired. Sign in again.',
      );
    }
    final http.Response response;
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/auth/native/refresh'))
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              'refresh_token': refresh,
              'provider': data['provider'],
            });
      response = await http.Response.fromStream(
        await client.send(request),
      ).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const DashboardNativeAuthException(
        'Dashboard sign-in renewal unavailable.',
      );
    }
    check();
    if (response.statusCode == 401) {
      await _serial(id, () async {
        check();
        await _write(id, _signedOut(data));
      });
      throw const DashboardNativeAuthException(
        'Dashboard sign-in expired. Sign in again.',
      );
    }
    if (response.statusCode != 200) {
      throw const DashboardNativeAuthException(
        'Dashboard sign-in renewal unavailable.',
      );
    }
    final Map<String, dynamic> rotated;
    try {
      rotated = jsonDecode(response.body) as Map<String, dynamic>;
      _validate(rotated);
    } catch (_) {
      throw const DashboardNativeAuthException(
        'Invalid dashboard token response.',
      );
    }
    rotated['base_url'] = baseUrl;
    rotated['profile'] = profileFor(profile);
    await _serial(id, () async {
      check();
      await _write(id, jsonEncode(rotated));
      check();
    });
    check();
    return rotated['access_token'] as String;
  }
}

/// Even same-origin redirects are rejected: a prefix can be an auth boundary.
class DashboardNoRedirectClient extends http.BaseClient {
  DashboardNoRedirectClient(this.inner, {this.checkBinding, this.captureFence});
  final http.Client inner;
  final void Function()? checkBinding;
  final void Function() Function()? captureFence;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final fence = captureFence?.call();
    void check() {
      checkBinding?.call();
      fence?.call();
    }

    check();
    request.followRedirects = false;
    final response = await inner.send(request);
    try {
      check();
    } catch (_) {
      await response.stream.listen((_) {}).cancel();
      rethrow;
    }
    // A direct transformer forwards pause/cancel to the source even before
    // its first event. An async* wrapper can leave an idle body unconsumed
    // when callers reject Content-Length and immediately cancel.
    final guarded = response.stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          try {
            check();
          } catch (error, stack) {
            sink.addError(error, stack);
            sink.close();
            return;
          }
          sink.add(chunk);
        },
        handleDone: (sink) {
          try {
            check();
          } catch (error, stack) {
            sink.addError(error, stack);
          } finally {
            sink.close();
          }
        },
      ),
    );

    return http.StreamedResponse(
      guarded,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => inner.close();
}
