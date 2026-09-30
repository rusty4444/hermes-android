// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/connection.dart';
import '../models/session.dart';

// Re-export for convenience
export '../models/connection.dart';
export '../models/session.dart';

/// Injectable secret storage boundary used by [ConnectionManager].
///
/// The production implementation is backed by Android Keystore through
/// `flutter_secure_storage`; tests use a deterministic in-memory fake.
abstract interface class CredentialStore {
  String? readCached(String key);

  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureCredentialStore implements CredentialStore {
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateWithBackup: true,
    storageNamespace: 'hermes_android_connections',
  );

  final FlutterSecureStorage _storage;
  final Map<String, String> _cache = <String, String>{};

  FlutterSecureCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage(aOptions: _androidOptions);

  @override
  String? readCached(String key) => _cache[key];

  @override
  Future<String?> read(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
    _cache.remove(key);
  }
}

class CredentialStorageException implements Exception {
  final String message;

  const CredentialStorageException(this.message);

  @override
  String toString() => message;
}

class _ConnectionCredentials {
  final String apiKey;
  final String? dashboardPassword;

  const _ConnectionCredentials({
    required this.apiKey,
    required this.dashboardPassword,
  });

  bool get isEmpty => apiKey.isEmpty && dashboardPassword == null;

  String encode() => jsonEncode(<String, String>{
    if (apiKey.isNotEmpty) 'api_key': apiKey,
    'dashboard_password': ?dashboardPassword,
  });

  static _ConnectionCredentials decode(String encoded) {
    try {
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      final apiKey = map['api_key'];
      final dashboardPassword = map['dashboard_password'];
      if (apiKey != null && apiKey is! String ||
          dashboardPassword != null && dashboardPassword is! String) {
        throw const FormatException();
      }
      final password = (dashboardPassword as String?)?.trim();
      return _ConnectionCredentials(
        apiKey: (apiKey as String?) ?? '',
        dashboardPassword: password == null || password.isEmpty
            ? null
            : password,
      );
    } catch (_) {
      throw const CredentialStorageException(
        'Stored connection credentials could not be read safely.',
      );
    }
  }

  static _ConnectionCredentials fromConnection(SavedConnection connection) {
    final password = connection.dashboardPassword?.trim();
    return _ConnectionCredentials(
      apiKey: connection.apiKey,
      dashboardPassword: password == null || password.isEmpty ? null : password,
    );
  }
}

/// Manages non-secret connection metadata in SharedPreferences and credentials
/// in a platform secure store.
class ConnectionManager {
  static const String _key = 'saved_connections';
  static const String _credentialKeyPrefix = 'connection_credentials_v1.';
  static const Uuid _uuid = Uuid();
  static final CredentialStore _sharedCredentialStore =
      FlutterSecureCredentialStore();

  final SharedPreferences prefs;
  final CredentialStore _credentialStore;

  ConnectionManager(this.prefs, {CredentialStore? credentialStore})
    : _credentialStore = credentialStore ?? _sharedCredentialStore;

  static Future<ConnectionManager> create(
    SharedPreferences prefs, {
    CredentialStore? credentialStore,
  }) async {
    final manager = ConnectionManager(prefs, credentialStore: credentialStore);
    await manager.initialize();
    return manager;
  }

  /// Migrates legacy plaintext credentials before the first UI is rendered.
  ///
  /// Every legacy credential bundle is written and read back first. The
  /// SharedPreferences list is sanitized only after all read-backs match, so a
  /// partial secure-store failure leaves every legacy profile retryable.
  Future<void> initialize() async {
    final maps = _readConnectionMaps();
    final connections = _connectionsFromMaps(maps);
    final hasLegacyFields = maps.any(
      (map) =>
          map.containsKey('api_key') || map.containsKey('dashboard_password'),
    );

    try {
      for (final connection in connections) {
        final credentials = _ConnectionCredentials.fromConnection(connection);
        if (!credentials.isEmpty) {
          await _writeAndVerifyCredentials(connection.id, credentials);
        }
      }

      for (final connection in connections) {
        final encoded = await _credentialStore.read(
          _credentialKey(connection.id),
        );
        if (encoded != null) {
          _ConnectionCredentials.decode(encoded);
        }
      }

      if (hasLegacyFields) {
        await _saveAll(connections);
      }
    } on CredentialStorageException {
      rethrow;
    } catch (_) {
      throw const CredentialStorageException(
        'Connection credentials could not be migrated safely.',
      );
    }
  }

  List<SavedConnection> getConnections() {
    return _connectionsFromMaps(
      _readConnectionMaps(),
    ).map(_hydrateFromCachedCredentials).toList();
  }

  /// Returns every saved connection with its secrets read back from the secure
  /// store, rather than from the in-memory cache used by [getConnections].
  ///
  /// Config export needs this: a freshly launched app has an empty credential
  /// cache, so [getConnections] alone would hand back connections with blank
  /// API keys and silently produce a useless backup.
  Future<List<SavedConnection>> loadConnectionsWithSecrets() async {
    final connections = _connectionsFromMaps(_readConnectionMaps());
    final hydrated = <SavedConnection>[];
    for (final connection in connections) {
      final encoded = await _credentialStore.read(
        _credentialKey(connection.id),
      );
      if (encoded == null) {
        hydrated.add(connection);
        continue;
      }
      final credentials = _ConnectionCredentials.decode(encoded);
      hydrated.add(
        connection.copyWith(
          apiKey: credentials.apiKey,
          dashboardPassword: credentials.dashboardPassword,
          clearDashboardPassword: credentials.dashboardPassword == null,
        ),
      );
    }
    return hydrated;
  }

  /// Writes a whole set of connections at once, preserving their ids.
  ///
  /// Every credential bundle is written and verified before the metadata list
  /// is committed, matching the fail-closed contract of the single-connection
  /// paths. When [replaceExisting] is true, connections absent from [incoming]
  /// are removed along with their credentials.
  Future<void> importConnections(
    List<SavedConnection> incoming, {
    required bool replaceExisting,
  }) async {
    final current = _connectionsFromMaps(_readConnectionMaps());

    final ordered = List<SavedConnection>.of(incoming);

    final List<SavedConnection> next;
    final removed = <SavedConnection>[];
    if (replaceExisting) {
      final keep = ordered.map((connection) => connection.id).toSet();
      removed.addAll(
        current.where((connection) => !keep.contains(connection.id)),
      );
      next = ordered;
    } else {
      final incomingIds = ordered.map((connection) => connection.id).toSet();
      next = <SavedConnection>[
        ...ordered,
        ...current.where((connection) => !incomingIds.contains(connection.id)),
      ];
    }

    for (final connection in ordered) {
      await _writeAndVerifyCredentials(
        connection.id,
        _ConnectionCredentials.fromConnection(connection),
      );
    }
    for (final connection in removed) {
      await _writeAndVerifyCredentials(
        connection.id,
        const _ConnectionCredentials(apiKey: '', dashboardPassword: null),
      );
    }

    await _saveAll(next);
  }

  Future<void> saveConnection(
    String label,
    String host,
    int? port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied = false,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
    String? gatewayProfile,
  }) async {
    final normalized = SavedConnection.normalizeHostAndPort(host, port);
    final profile = gatewayProfile?.trim();
    final conn = SavedConnection(
      id: _uuid.v4(),
      label: label,
      host: normalized.host,
      port: normalized.port,
      apiKey: apiKey,
      useHttps: normalized.useHttps,
      gatewayPrefix: gatewayPrefix,
      dashboardPrefix: dashboardPrefix,
      dashboardProxied: dashboardProxied,
      desktopGatewayUrl: desktopGatewayUrl?.trim(),
      dashboardPortOverride: dashboardPort,
      dashboardUsername: dashboardUsername,
      dashboardPassword: dashboardPassword,
      gatewayProfile: profile == null || profile.isEmpty ? null : profile,
    );
    final current = getConnections();
    current.insert(0, conn);
    await _commitCredentialAndMetadata(
      connectionId: conn.id,
      previousCredentials: const _ConnectionCredentials(
        apiKey: '',
        dashboardPassword: null,
      ),
      nextCredentials: _ConnectionCredentials.fromConnection(conn),
      connections: current,
    );
  }

  /// Updates all editable fields on an existing connection while preserving its
  /// id and list position. Empty optional strings clear their saved values.
  Future<void> updateConnection(
    String connId,
    String label,
    String host,
    int? port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied = false,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
    String? gatewayProfile,
  }) async {
    final current = getConnections();
    final idx = current.indexWhere((c) => c.id == connId);
    if (idx < 0) return;

    final previousCredentials = _ConnectionCredentials.fromConnection(
      current[idx],
    );

    final normalized = SavedConnection.normalizeHostAndPort(host, port);
    final gateway = gatewayPrefix?.trim();
    final dashboard = dashboardPrefix?.trim();
    final dashUser = dashboardUsername?.trim();
    final dashPass = dashboardPassword?.trim();
    final desktopGateway = desktopGatewayUrl?.trim();
    final profile = gatewayProfile?.trim();

    current[idx] = current[idx].copyWith(
      label: label,
      host: normalized.host,
      port: normalized.port,
      apiKey: apiKey,
      useHttps: normalized.useHttps,
      gatewayPrefix: gateway == null || gateway.isEmpty ? null : gateway,
      clearGatewayPrefix: gateway != null && gateway.isEmpty,
      dashboardPrefix: dashboard == null || dashboard.isEmpty
          ? null
          : dashboard,
      clearDashboardPrefix: dashboard != null && dashboard.isEmpty,
      dashboardProxied: dashboardProxied,
      desktopGatewayUrl: desktopGateway == null || desktopGateway.isEmpty
          ? null
          : desktopGateway,
      clearDesktopGatewayUrl: desktopGateway != null && desktopGateway.isEmpty,
      dashboardPortOverride: dashboardPort,
      clearDashboardPort: dashboardPort == null,
      dashboardUsername: dashUser == null || dashUser.isEmpty ? null : dashUser,
      clearDashboardUsername: dashUser != null && dashUser.isEmpty,
      dashboardPassword: dashPass == null || dashPass.isEmpty ? null : dashPass,
      clearDashboardPassword: dashPass != null && dashPass.isEmpty,
      gatewayProfile: profile == null || profile.isEmpty ? null : profile,
      clearGatewayProfile: profile != null && profile.isEmpty,
    );
    await _commitCredentialAndMetadata(
      connectionId: connId,
      previousCredentials: previousCredentials,
      nextCredentials: _ConnectionCredentials.fromConnection(current[idx]),
      connections: current,
    );
  }

  /// Updates the dashboard port + basic-auth credentials on an existing
  /// connection. Empty strings clear the corresponding field.
  Future<void> updateDashboardAuth(
    String connId, {
    int? dashboardPort,
    required String username,
    required String password,
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool? dashboardProxied,
  }) async {
    final current = getConnections();
    final idx = current.indexWhere((c) => c.id == connId);
    if (idx < 0) return;
    final previousCredentials = _ConnectionCredentials.fromConnection(
      current[idx],
    );
    final u = username.trim();
    final p = password.trim();
    final gateway = gatewayPrefix?.trim();
    final dashboard = dashboardPrefix?.trim();
    current[idx] = current[idx].copyWith(
      gatewayPrefix: gateway == null || gateway.isEmpty ? null : gateway,
      clearGatewayPrefix: gateway != null && gateway.isEmpty,
      dashboardPrefix: dashboard == null || dashboard.isEmpty
          ? null
          : dashboard,
      clearDashboardPrefix: dashboard != null && dashboard.isEmpty,
      dashboardProxied: dashboardProxied,
      dashboardPortOverride: dashboardPort,
      clearDashboardPort: dashboardPort == null,
      dashboardUsername: u.isEmpty ? null : u,
      clearDashboardUsername: u.isEmpty,
      dashboardPassword: p.isEmpty ? null : p,
      clearDashboardPassword: p.isEmpty,
    );
    await _commitCredentialAndMetadata(
      connectionId: connId,
      previousCredentials: previousCredentials,
      nextCredentials: _ConnectionCredentials.fromConnection(current[idx]),
      connections: current,
    );
  }

  Future<void> updateApiKey(String connId, String apiKey) async {
    final current = getConnections();
    final idx = current.indexWhere((c) => c.id == connId);
    if (idx < 0) return;
    final previousCredentials = _ConnectionCredentials.fromConnection(
      current[idx],
    );
    current[idx] = current[idx].copyWith(apiKey: apiKey);
    await _commitCredentialAndMetadata(
      connectionId: connId,
      previousCredentials: previousCredentials,
      nextCredentials: _ConnectionCredentials.fromConnection(current[idx]),
      connections: current,
    );
  }

  Future<void> deleteConnection(String id) async {
    final current = getConnections();
    final index = current.indexWhere((connection) => connection.id == id);
    if (index < 0) return;
    final previousCredentials = _ConnectionCredentials.fromConnection(
      current[index],
    );
    current.removeWhere((c) => c.id == id);
    await _commitCredentialAndMetadata(
      connectionId: id,
      previousCredentials: previousCredentials,
      nextCredentials: const _ConnectionCredentials(
        apiKey: '',
        dashboardPassword: null,
      ),
      connections: current,
    );
  }

  List<Map<String, dynamic>> _readConnectionMaps() {
    try {
      final jsonList = prefs.getStringList(_key) ?? const <String>[];
      return jsonList
          .map((json) => jsonDecode(json) as Map<String, dynamic>)
          .toList();
    } catch (_) {
      throw const CredentialStorageException(
        'Saved connection metadata could not be read safely.',
      );
    }
  }

  List<SavedConnection> _connectionsFromMaps(List<Map<String, dynamic>> maps) {
    try {
      return maps.map(SavedConnection.fromMap).toList();
    } catch (_) {
      throw const CredentialStorageException(
        'Saved connection metadata could not be read safely.',
      );
    }
  }

  SavedConnection _hydrateFromCachedCredentials(SavedConnection connection) {
    final encoded = _credentialStore.readCached(_credentialKey(connection.id));
    if (encoded == null) return connection;
    final credentials = _ConnectionCredentials.decode(encoded);
    return connection.copyWith(
      apiKey: credentials.apiKey,
      dashboardPassword: credentials.dashboardPassword,
      clearDashboardPassword: credentials.dashboardPassword == null,
    );
  }

  Future<void> _commitCredentialAndMetadata({
    required String connectionId,
    required _ConnectionCredentials previousCredentials,
    required _ConnectionCredentials nextCredentials,
    required List<SavedConnection> connections,
  }) async {
    try {
      await _writeAndVerifyCredentials(connectionId, nextCredentials);
      await _saveAll(connections);
    } catch (_) {
      try {
        await _writeAndVerifyCredentials(connectionId, previousCredentials);
      } catch (_) {
        // The caller still receives a generic fail-closed error. Never attach
        // platform errors because they may include sensitive storage details.
      }
      throw const CredentialStorageException(
        'Connection credentials could not be saved safely.',
      );
    }
  }

  Future<void> _writeAndVerifyCredentials(
    String connectionId,
    _ConnectionCredentials credentials,
  ) async {
    final key = _credentialKey(connectionId);
    if (credentials.isEmpty) {
      await _credentialStore.delete(key);
      final readBack = await _credentialStore.read(key);
      if (readBack != null) {
        throw const CredentialStorageException(
          'Connection credentials could not be cleared safely.',
        );
      }
      return;
    }

    final encoded = credentials.encode();
    await _credentialStore.write(key, encoded);
    final readBack = await _credentialStore.read(key);
    if (readBack != encoded) {
      throw const CredentialStorageException(
        'Connection credentials could not be verified safely.',
      );
    }
  }

  Future<void> _saveAll(List<SavedConnection> list) async {
    try {
      final saved = await prefs.setStringList(
        _key,
        list.map((connection) => jsonEncode(connection.toMap())).toList(),
      );
      if (!saved) {
        throw const CredentialStorageException(
          'Connection metadata could not be saved safely.',
        );
      }
    } on CredentialStorageException {
      rethrow;
    } catch (_) {
      throw const CredentialStorageException(
        'Connection metadata could not be saved safely.',
      );
    }
  }

  static String _credentialKey(String connectionId) {
    final encodedId = base64Url
        .encode(utf8.encode(connectionId))
        .replaceAll('=', '');
    return '$_credentialKeyPrefix$encodedId';
  }
}

class ApiHealthCheckResult {
  final bool isHealthy;
  final Uri endpoint;
  final int? statusCode;

  const ApiHealthCheckResult._({
    required this.isHealthy,
    required this.endpoint,
    this.statusCode,
  });

  const ApiHealthCheckResult.success(Uri endpoint)
    : this._(isHealthy: true, endpoint: endpoint);

  const ApiHealthCheckResult.httpFailure(Uri endpoint, int statusCode)
    : this._(isHealthy: false, endpoint: endpoint, statusCode: statusCode);

  const ApiHealthCheckResult.networkFailure(Uri endpoint)
    : this._(isHealthy: false, endpoint: endpoint);

  String userMessage({required bool apiKeyProvided}) {
    if (isHealthy) return '';
    if (statusCode == 401 || statusCode == 403) {
      return apiKeyProvided
          ? 'API key was rejected by $endpoint (HTTP $statusCode).'
          : 'Server requires an API key. Enter your API_SERVER_KEY.';
    }
    if (statusCode == 404) {
      return 'Gateway endpoint $endpoint returned HTTP 404. Check the Gateway '
          'path prefix and reverse-proxy routes.';
    }
    if (statusCode case final code?) {
      return 'Gateway endpoint $endpoint returned HTTP $code.';
    }
    return 'Cannot reach Gateway endpoint $endpoint.';
  }
}

/// One page of the gateway's session list with its paging signal.
class SessionListPage {
  final List<Session> sessions;
  final bool hasMore;

  const SessionListPage({required this.sessions, required this.hasMore});
}

/// HTTP client for the Hermes Gateway API Server (port 8642).
///
/// Uses Bearer token auth. Same pattern as hermes-desktop.
class ApiClient {
  final http.Client _http;
  final String baseUrl;
  final String _apiKey;

  /// How long a single request may take before the UI may surface an error.
  ///
  /// A gateway on a dead keep-alive socket can otherwise hang forever while
  /// the server already answered or closed the connection; every read path
  /// uses this bound so the user always gets a loadable error state.
  static const Duration requestTimeout = Duration(seconds: 20);

  // Keep the public parameter name `apiKey` while storing it privately.
  ApiClient({
    required String baseUrl,
    required String apiKey,
    String pathPrefix = '',
    http.Client? httpClient,
  }) : _apiKey = apiKey,
       baseUrl = SavedConnection.joinBaseUrl(baseUrl, pathPrefix),
       _http = httpClient ?? _freshClient();

  /// Builds a client that does not pool keep-alive sockets.
  ///
  /// dart:io's pooled connections go stale silently (the server closed an
  /// idle connection; the client only notices on the *next* request, which
  /// then hangs). Home/tablet/LAN gateways are cheap to reconnect to, so a
  /// fresh TCP connection per request is a fair price for never wedging the
  /// session list on a stale socket.
  static http.Client _freshClient() {
    final io = HttpClient()..idleTimeout = Duration.zero;
    return IOClient(io);
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
  };

  // ── Session listing ──────────────────────────────────────────────────

  /// One page of the gateway session list plus the server's paging signal.
  ///
  /// The gateway api_server caps `limit` at 200 and reports `has_more` from
  /// its recency window, so a client that never pages only ever sees the
  /// most recent page — which silently truncated the Unassigned bucket
  /// (sessions outside the first page never reached the device).
  Future<SessionListPage> getSessionsPage({
    int limit = 50,
    int offset = 0,
    Duration timeout = requestTimeout,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/sessions',
    ).replace(queryParameters: {'limit': '$limit', 'offset': '$offset'});
    final res = await _http.get(uri, headers: _headers).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return SessionListPage(
      sessions: list
          .whereType<Map<String, dynamic>>()
          .map((s) => Session.fromJson(s))
          .toList(),
      hasMore: data['has_more'] == true,
    );
  }

  Future<List<Session>> getSessions({Duration timeout = requestTimeout}) async {
    final page = await getSessionsPage(timeout: timeout);
    return page.sessions;
  }

  // ── Messages ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final res = await _http
        .get(
          Uri.parse('$baseUrl/api/sessions/$sessionId/messages'),
          headers: _headers,
        )
        .timeout(requestTimeout);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> deleteSession(String sessionId) async {
    final encodedId = Uri.encodeComponent(sessionId);
    final res = await _http
        .delete(
          Uri.parse('$baseUrl/api/sessions/$encodedId'),
          headers: _headers,
        )
        .timeout(requestTimeout);
    // Treat a stale local row as already synced: the remote no longer has it,
    // so the UI can safely remove it from history.
    if (res.statusCode == 404) return;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  // ── Models ───────────────────────────────────────────────────────────

  Future<List<String>> getModels() async {
    final res = await _http
        .get(Uri.parse('$baseUrl/v1/models'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode != 200) {
      return ['hermes-agent'];
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => (m['id'] as String?) ?? 'hermes-agent')
        .toList();
  }

  // ── Health check ─────────────────────────────────────────────────────

  Future<ApiHealthCheckResult> checkHealth() async {
    final healthEndpoint = Uri.parse('$baseUrl/health');
    var activeEndpoint = healthEndpoint;
    try {
      final health = await _http
          .get(healthEndpoint, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (health.statusCode != 200) {
        return ApiHealthCheckResult.httpFailure(
          healthEndpoint,
          health.statusCode,
        );
      }

      // /health may be intentionally public on some deployments. Confirm that
      // the saved API key can also reach an authenticated endpoint before the
      // add/update connection dialogs accept it as valid.
      final sessionsEndpoint = Uri.parse('$baseUrl/api/sessions');
      activeEndpoint = sessionsEndpoint;
      final sessions = await _http
          .get(sessionsEndpoint, headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (sessions.statusCode != 200) {
        return ApiHealthCheckResult.httpFailure(
          sessionsEndpoint,
          sessions.statusCode,
        );
      }
      return ApiHealthCheckResult.success(sessionsEndpoint);
    } catch (_) {
      return ApiHealthCheckResult.networkFailure(activeEndpoint);
    }
  }

  Future<bool> healthCheck() async => (await checkHealth()).isHealthy;

  // ── Generic HTTP helpers (for Dashboard API compatibility) ────────────

  Future<Map<String, dynamic>> apiGet(String endpoint) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/$endpoint'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> apiGetList(String endpoint) async {
    final res = await _http
        .get(Uri.parse('$baseUrl/$endpoint'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final res = await _http
        .post(
          Uri.parse('$baseUrl/$endpoint'),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(requestTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> apiDelete(String endpoint) async {
    final res = await _http
        .delete(Uri.parse('$baseUrl/$endpoint'), headers: _headers)
        .timeout(requestTimeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  // ── Dashboard-compatible helpers (port 9119 endpoints, may not work on API server) ──

  Future<Map<String, dynamic>> getModelInfo() => apiGet('api/model/info');
  Future<Map<String, dynamic>> getModelOptions() => apiGet('api/model/options');
  Future<List<Map<String, dynamic>>> getSkills() async {
    final data = await apiGetList('api/skills');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> setModel(
    String scope,
    String provider,
    String model,
  ) => apiPost(
    'api/model/set',
    body: {'scope': scope, 'provider': provider, 'model': model},
  );

  void close() => _http.close();
}

typedef ToolProgressCallback = void Function(Map<String, dynamic> progress);

/// SSE streaming chat client for the Gateway API Server.
class GatewayChatClient {
  final ApiClient _api;
  final String _baseUrl;

  /// Per-call stream state: each sendMessageStreaming call owns a
  /// _LiveStream, and the client keeps only the current one, which
  /// cancelActiveMessage targets. (Previously three shared fields let a
  /// second send overwrite the first's slot and let cancel-then-resend
  /// reset the cancelled flag before the cancelled stream's onDone
  /// check ran — so a cancelled turn reported success and the orphaned
  /// subscription kept pushing tokens into stale callbacks.)
  _LiveStream? _liveStream;

  GatewayChatClient(this._api) : _baseUrl = _api.baseUrl;

  /// Generate a client-side session ID: `mob-<timestamp>-<uuid>`.
  static String generateSessionId() {
    return 'mob-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4()}';
  }

  /// Build OpenAI chat-completions messages, preserving prior history and
  /// ensuring the newly typed user message is present exactly once at the end.
  static List<Map<String, dynamic>> buildChatCompletionMessages({
    required String message,
    List<Map<String, dynamic>>? history,
    String? imageDataUrl,
  }) {
    final messages = <Map<String, dynamic>>[];
    if (history != null && history.isNotEmpty) {
      for (final msg in history) {
        final role = (msg['role'] == 'agent' || msg['role'] == 'assistant')
            ? 'assistant'
            : 'user';
        final content = msg['content'];
        if (content == null || (content is String && content.isEmpty)) {
          continue;
        }
        messages.add({'role': role, 'content': content});
      }
    }

    final latest = message.trim();
    final latestContent = imageDataUrl == null
        ? latest
        : <Map<String, dynamic>>[
            if (latest.isNotEmpty) {'type': 'text', 'text': latest},
            {
              'type': 'image_url',
              'image_url': {'url': imageDataUrl},
            },
          ];
    final alreadyLast =
        imageDataUrl == null &&
        messages.isNotEmpty &&
        messages.last['role'] == 'user' &&
        messages.last['content'] == latest;
    if ((latest.isNotEmpty || imageDataUrl != null) && !alreadyLast) {
      messages.add({'role': 'user', 'content': latestContent});
    }
    return messages;
  }

  /// Parse one SSE frame. Returns streamed text token, or null for non-token
  /// frames. Hermes tool progress frames are delivered via [onToolProgress].
  static String? parseSseFrame(
    String frame, {
    ToolProgressCallback? onToolProgress,
  }) {
    String eventType = '';
    final dataLines = <String>[];

    for (final rawLine in frame.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty || line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    if (dataLines.isEmpty) return null;
    final data = dataLines.join('\n').trim();
    if (data.isEmpty || data == '[DONE]') return null;

    try {
      final parsed = jsonDecode(data);
      if (eventType == 'hermes.tool.progress') {
        if (parsed is Map<String, dynamic>) onToolProgress?.call(parsed);
        return null;
      }

      if (parsed is Map<String, dynamic>) {
        final choices = parsed['choices'] as List?;
        if (choices != null && choices.isNotEmpty && choices.first is Map) {
          final first = choices.first as Map;
          final delta = first['delta'];
          if (delta is Map) {
            final content = delta['content'];
            if (content != null && content.toString().isNotEmpty) {
              return content.toString();
            }
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Send a message and stream the assistant response token-by-token.
  Future<void> sendMessageStreaming({
    required String message,
    required String sessionId,
    String? model,
    List<Map<String, dynamic>>? history,
    String? imageDataUrl,
    required void Function(String token) onToken,
    ToolProgressCallback? onToolProgress,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    final messages = buildChatCompletionMessages(
      message: message,
      history: history,
      imageDataUrl: imageDataUrl,
    );

    final body = {
      'model': model ?? 'hermes-agent',
      'messages': messages,
      'stream': true,
    };

    final headers = {..._api._headers, 'X-Hermes-Session-Id': sessionId};
    final stream = _LiveStream();
    final previous = _liveStream;
    // A second concurrent send supersedes the first: cancel the old one
    // with its OWN state so its callbacks are muted rather than silently
    // drained into the new call's flags.
    if (previous != null) {
      previous.cancelled = true;
      if (!previous.cancellation.isCompleted) {
        previous.cancellation.complete();
      }
      final sub = previous.subscription;
      if (sub != null) {
        unawaited(sub.cancel());
      }
      if (!previous.completion.isCompleted) previous.completion.complete();
    }
    _liveStream = stream;
    final completion = stream.completion;

    try {
      final request = http.AbortableRequest(
        'POST',
        Uri.parse('$_baseUrl/v1/chat/completions'),
        abortTrigger: stream.cancellation.future,
      );
      request.headers.addAll(headers);
      request.body = jsonEncode(body);

      final responseFuture = _api._http.send(request);
      final response = await Future.any<http.StreamedResponse?>([
        responseFuture.then<http.StreamedResponse?>((value) => value),
        stream.cancellation.future.then<http.StreamedResponse?>((_) => null),
      ]);
      if (response == null) {
        // AbortableRequest is honoured by package:http's production clients.
        // The race above is also a safe fallback for an injected/custom client
        // that ignores it: settle this send now, then discard any late body
        // without invoking user callbacks or closing the shared ApiClient.
        unawaited(
          responseFuture.then<void>((lateResponse) {
            final subscription = lateResponse.stream.listen((_) {});
            unawaited(subscription.cancel());
          }, onError: (Object _, StackTrace _) {}),
        );
        return;
      }

      if (stream.cancelled || !identical(_liveStream, stream)) {
        final subscription = response.stream.listen((_) {});
        await subscription.cancel();
        return;
      }

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        String errorMsg;
        try {
          final err = jsonDecode(errorBody);
          errorMsg =
              err['error']?['message'] ??
              err['message'] ??
              'HTTP ${response.statusCode}';
        } catch (_) {
          errorMsg = 'HTTP ${response.statusCode}';
        }
        onError(errorMsg);
        return;
      }

      String buffer = '';
      stream.subscription = response.stream
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              // A superseded or cancelled stream must never deliver tokens
              // into these callbacks: the UI has moved on (or already
              // reported the cancellation).
              if (stream.cancelled || !identical(_liveStream, stream)) return;
              buffer += chunk;
              // SSE frames end on a blank line: LF-only or CRLF-only per
              // the spec. A CRLF-emitting proxy would otherwise never
              // match and the stream would look frozen until the end.
              var boundary = RegExp(r'\r?\n\r?\n').firstMatch(buffer);
              while (boundary != null) {
                final frame = buffer.substring(0, boundary.start);
                buffer = buffer.substring(boundary.end);

                final token = parseSseFrame(
                  frame,
                  onToolProgress: onToolProgress,
                );
                if (token != null && token.isNotEmpty) onToken(token);
                boundary = RegExp(r'\r?\n\r?\n').firstMatch(buffer);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!completion.isCompleted) {
                completion.completeError(error, stackTrace);
              }
            },
            onDone: () {
              if (!completion.isCompleted) completion.complete();
            },
            cancelOnError: true,
          );
      await completion.future;

      // Per-call flag: a newer send cannot reset this call's cancelled
      // state, so a cancelled turn never reports onDone.
      if (!stream.cancelled) onDone();
    } catch (e) {
      if (!stream.cancelled) onError(e.toString());
    } finally {
      // Every exit path settles this send, not just the ones that reach the
      // SSE subscription. A `send()` that fails before the response headers, an
      // abort that races the response, a non-200 reply, or an exception thrown
      // while reading one never touch `completion`, yet such a send IS settled
      // — the socket is finished with. Leaving the completer pending stranded a
      // detached caller (screen disposal hands the stream to a closer that
      // awaits exactly this) on the 30-minute backstop, holding the HTTP client
      // open for a request that was already over.
      if (!completion.isCompleted) completion.complete();
      if (identical(_liveStream, stream)) {
        _liveStream = null;
      }
    }
  }

  /// Whether a send currently owns the live SSE stream.
  bool get isStreaming => _liveStream != null;

  /// Completes once the live stream settles: done, error, cancellation, or any
  /// other exit from the send — including the failures that never open a body
  /// stream (a rejected `send()`, a non-200 reply).
  ///
  /// Lets a caller that is going away hand the connection to a detached owner.
  /// Closing the HTTP client while a turn streams aborts the request, and the
  /// API server treats that client disconnect as an agent interrupt — the turn
  /// and its tool work die server-side. A failed stream still counts as settled:
  /// the caller's only need is for the socket to be finished with.
  Future<void> whenStreamSettles() async {
    final stream = _liveStream;
    if (stream == null) return;
    try {
      await stream.completion.future;
    } catch (_) {
      // Settled with an error is settled.
    }
  }

  /// Cancels the current SSE response. The Hermes API server treats the
  /// resulting client disconnect as an agent interrupt.
  Future<bool> cancelActiveMessage() async {
    final stream = _liveStream;
    if (stream == null) return false;

    stream.cancelled = true;
    if (!stream.cancellation.isCompleted) stream.cancellation.complete();
    final subscription = stream.subscription;
    if (subscription != null) {
      await subscription.cancel();
    }
    if (!stream.completion.isCompleted) stream.completion.complete();
    return true;
  }

  void abort() {
    final stream = _liveStream;
    if (stream != null) {
      stream.cancelled = true;
      if (!stream.cancellation.isCompleted) stream.cancellation.complete();
      final sub = stream.subscription;
      if (sub != null) {
        unawaited(sub.cancel());
      }
      if (!stream.completion.isCompleted) stream.completion.complete();
      _liveStream = null;
    }
    // NOTE: deliberately does NOT close the shared ApiClient's HTTP
    // client — the same ApiClient instance feeds the session list and
    // health checks, and closing it killed every later HTTP call on it.
  }
}

/// Per-call SSE stream state owned by one sendMessageStreaming call.
class _LiveStream {
  final Completer<void> completion = Completer<void>();
  final Completer<void> cancellation = Completer<void>();
  StreamSubscription<String>? subscription;
  bool cancelled = false;
}

/// A non-200 answer from a dashboard API call, carrying the status code so
/// callers can distinguish authoritative outcomes (404 = the resource is
/// definitively absent) from unknowable ones (403/5xx/timeout = existence
/// cannot be determined). Callers that must never act on a guess — like
/// the project folder provisioner — branch on this instead of string-
/// matching a bare Exception.
class DashboardHttpException implements Exception {
  final int statusCode;
  const DashboardHttpException(this.statusCode);

  @override
  String toString() => 'HTTP $statusCode';
}

/// Client for the Hermes Dashboard REST API.
///
/// Three auth modes, picked by proxy configuration and supplied credentials:
///
///  * **Proxied dashboard** — when [proxied] is true, upstream infrastructure
///    injects auth and the app sends clean JSON requests with no dashboard
///    session token or cookie.
///  * **Password (gated) dashboard** — when [username] and [password] are set,
///    performs the `/auth/password-login` flow (provider `basic`) and
///    authenticates subsequent `/api/` calls with the returned
///    `hermes_session_at` session cookie. This is what hermes-desktop does and
///    is required when the dashboard runs with basic-auth.
///  * **Insecure (open) dashboard** — when no credentials are given, falls back
///    to scraping the ephemeral SPA session token from the homepage. Only works
///    on a dashboard started with `--insecure`.
///
/// Used for Dashboard-only features: cron, memory, skills, settings.
class DashboardClient {
  final http.Client _http;
  final String _baseUrl;
  final bool _proxied;
  final String? _username;
  final String? _password;
  final String? _apiKey;
  final String? _gatewayProfile;
  String? _token;
  String? _cookie;
  int _authGeneration = 0;
  // In-flight auth requests, shared so concurrent /api calls trigger a single
  // login / token fetch instead of a thundering herd (the dashboard
  // rate-limits password logins).
  Future<String>? _cookieInFlight;
  Future<String>? _tokenInFlight;

  String get baseUrl => _baseUrl;

  bool get _usesApiKeyAuth => _apiKey?.isNotEmpty ?? false;

  /// Password login is a fallback only: the gateway API key works as a Bearer
  /// token on the dashboard routes the app uses (verified server-side), so it
  /// takes priority and avoids the rate-limited password-login round trip.
  bool get _usesPasswordAuth =>
      !_usesApiKeyAuth &&
      (_username?.isNotEmpty ?? false) &&
      (_password?.isNotEmpty ?? false);

  DashboardClient({
    required String host,
    int port = 9119,
    bool useHttps = false,
    String pathPrefix = '',
    bool proxied = false,
    String? username,
    String? password,
    String? apiKey,
    String? gatewayProfile,
    http.Client? httpClient,
  }) : _proxied = proxied,
       _username = username,
       _password = password,
       _apiKey = apiKey,
       _gatewayProfile = gatewayProfile?.trim().isEmpty == true
           ? null
           : gatewayProfile?.trim(),
       _baseUrl = SavedConnection.joinBaseUrl(
         '${useHttps ? 'https' : 'http'}://$host:$port',
         pathPrefix,
       ),
       _http = httpClient ?? http.Client();

  /// Clears cached auth only when the failed request used the current auth
  /// generation. Concurrent stale 401s therefore cannot invalidate a newer
  /// replacement login started by the first failure.
  void _resetAuth({int? ifGeneration}) {
    if (ifGeneration != null && ifGeneration != _authGeneration) return;
    _authGeneration++;
    _token = null;
    _cookie = null;
    _cookieInFlight = null;
    _tokenInFlight = null;
  }

  /// Returns the session cookie, reusing a cached value or an in-flight login.
  Future<String> _getCookie() {
    final cached = _cookie;
    if (cached != null) return Future.value(cached);
    final inFlight = _cookieInFlight;
    if (inFlight != null) return inFlight;
    final generation = _authGeneration;
    final future = _login();
    _cookieInFlight = future;
    // Cache only if this login still belongs to the active generation. A stale
    // login completing after a 401 reset must not overwrite its replacement.
    future
        .then((cookie) {
          if (_authGeneration == generation &&
              identical(_cookieInFlight, future)) {
            _cookie = cookie;
          }
        })
        .whenComplete(() {
          if (identical(_cookieInFlight, future)) _cookieInFlight = null;
        })
        .ignore();
    return future;
  }

  /// Logs in against the `basic` password provider and caches the session
  /// cookie. Throws on failure (bad credentials → 401, etc.).
  Future<String> _login() async {
    final res = await _http
        .post(
          Uri.parse('$_baseUrl/auth/password-login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'provider': 'basic',
            'username': _username,
            'password': _password,
          }),
        )
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401) {
      throw Exception('Dashboard login failed: invalid username or password');
    }
    if (res.statusCode != 200) {
      throw Exception('Dashboard login failed: HTTP ${res.statusCode}');
    }
    final setCookie = res.headers['set-cookie'] ?? '';
    // The `http` package folds multiple Set-Cookie headers into one
    // comma-joined string; cookie expiry dates also contain commas, so match
    // the access-token cookie by name and take its value up to the first
    // delimiter. Handles the bare name plus the __Host-/__Secure- prefixes
    // Hermes uses on HTTPS binds.
    final match = RegExp(
      r'((?:__Host-|__Secure-)?hermes_session_at)=([^;,\s]+)',
    ).firstMatch(setCookie);
    if (match == null) {
      throw Exception('Dashboard login succeeded but no session cookie found');
    }
    return '${match.group(1)}=${match.group(2)}';
  }

  /// Returns the SPA session token, reusing a cached value or an in-flight fetch.
  Future<String> _getToken() {
    final cached = _token;
    if (cached != null) return Future.value(cached);
    final inFlight = _tokenInFlight;
    if (inFlight != null) return inFlight;
    final generation = _authGeneration;
    final future = _fetchToken();
    _tokenInFlight = future;
    future
        .then((token) {
          if (_authGeneration == generation &&
              identical(_tokenInFlight, future)) {
            _token = token;
          }
        })
        .whenComplete(() {
          if (identical(_tokenInFlight, future)) _tokenInFlight = null;
        })
        .ignore();
    return future;
  }

  Future<String> _fetchToken() async {
    final res = await _http
        .get(Uri.parse('$_baseUrl/'))
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode != 200) throw Exception('Dashboard not reachable');
    final match = RegExp(
      r'window\.__HERMES_SESSION_TOKEN__="([^"]+)";',
    ).firstMatch(res.body);
    if (match == null) throw Exception('Session token not found');
    return match.group(1)!;
  }

  Future<Map<String, String>> _authHeaders() async {
    // "Dashboard behind proxy" means upstream infrastructure injects auth, so
    // the app normally sends clean requests. But if the user actually stored
    // credentials, sending them is strictly better than sending nothing: a real
    // proxy ignores or overwrites the header, while a misconfigured proxied
    // flag (no proxy in front, plain LAN dashboard) would otherwise 401 on
    // every dashboard route.
    if (_proxied && !_usesApiKeyAuth && !_usesPasswordAuth) {
      return {'Content-Type': 'application/json'};
    }
    if (_usesApiKeyAuth) {
      return {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };
    }
    if (_usesPasswordAuth) {
      return {'Cookie': await _getCookie(), 'Content-Type': 'application/json'};
    }
    return {
      'X-Hermes-Session-Token': await _getToken(),
      'Content-Type': 'application/json',
    };
  }

  /// Resolves the dashboard auth headers for a caller that issues its own
  /// requests against [baseUrl].
  ///
  /// Exposed so collaborators such as the session search client can reuse this
  /// client's cached cookie/token and its single-flight login, instead of
  /// re-implementing the auth ladder and triggering a second password login.
  Future<Map<String, String>> authHeaders() => _authHeaders();

  /// Mints the short-lived, single-use WebSocket ticket required by a secured
  /// Hermes Desktop gateway. The HTTP API cookie stays in this client; only the
  /// ticket is passed to the WebSocket URL.
  Future<String> mintWebSocketTicket({bool retried = false}) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final res = await _http
        .post(Uri.parse('$_baseUrl/api/auth/ws-ticket'), headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return mintWebSocketTicket(retried: true);
    }
    if (res.statusCode != 200) {
      throw Exception(
        'Could not mint Desktop gateway WebSocket ticket: HTTP ${res.statusCode}',
      );
    }
    final data = _decodeMapResponse(res);
    final ticket = data['ticket'] as String?;
    if (ticket == null || ticket.isEmpty) {
      throw Exception('Desktop gateway returned no WebSocket ticket');
    }
    return ticket;
  }

  Map<String, dynamic> _decodeMapResponse(http.Response res) {
    final trimmed = res.body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> apiGet(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .get(uri, headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiGet(endpoint, queryParameters: queryParameters, retried: true);
    }
    if (res.statusCode != 200) throw DashboardHttpException(res.statusCode);
    return _decodeMapResponse(res);
  }

  Future<http.Response> apiGetBytes(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .get(uri, headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiGetBytes(
        endpoint,
        queryParameters: queryParameters,
        retried: true,
      );
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return res;
  }

  Future<List<dynamic>> apiGetList(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .get(uri, headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiGetList(
        endpoint,
        queryParameters: queryParameters,
        retried: true,
      );
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final decoded = jsonDecode(res.body);
    if (decoded is List<dynamic>) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List<dynamic>) {
      return decoded['data'] as List<dynamic>;
    }
    throw Exception('Expected list response');
  }

  /// Lists server-archived sessions from the dashboard's session router.
  ///
  /// The gateway api_server that serves the chat transport ignores the
  /// `archived` query param entirely (live-verified: its list never
  /// contains archived rows), so the Chats browser's Archived chip reads
  /// them from the dashboard instead — the same `archived=only` router the
  /// dashboard's own Archived view uses, and the only stock Hermes surface
  /// that enumerates archived sessions. Requires dashboard credentials on
  /// the connection; callers degrade honestly when this throws.
  ///
  /// Pages to completion: the router caps each page at 100 rows and
  /// reports the full match count in `total`, so a single request would
  /// silently truncate anyone with more than one page of archived chats.
  /// [gatewayProfile] scopes the read to the connection's Hermes profile
  /// (the router opens that profile's session DB); omitting it would list
  /// the dashboard process's own default profile instead — the wrong
  /// store on a multiplexed gateway.
  ///
  /// Termination is by offset/no-progress, never by comparing the
  /// accumulated row count against `total`: the same pinned back-fill
  /// semantics as the live list can repeat rows across pages, and an
  /// inflated `all.length >= total` would stop before every offset
  /// window has been read, truncating the archive. Rows are deduplicated
  /// by session id so repeats never surface twice. [maxPages] is the
  /// explicit safety cap: if it is reached while the list was not
  /// exhausted the read throws rather than silently returning a partial
  /// archive — callers degrade honestly on the error instead of showing
  /// a truncated list as complete.
  Future<List<Session>> getArchivedSessions({
    int pageSize = 100,
    int maxPages = 20,
    String? gatewayProfile,
  }) async {
    final all = <Session>[];
    final seenIds = <String>{};
    var offset = 0;
    var exhausted = false;
    int? total;
    // Fallback pin-bound bookkeeping for a router that omits `total`
    // (see the loop comment): max pins on any page bounds the pin set, and
    // k consecutive zero-new windows consume k*pageSize disjoint pins.
    var pinBound = 0;
    var zeroNewPages = 0;
    for (var page = 0; page < maxPages; page++) {
      final data = await apiGet(
        'sessions',
        queryParameters: {
          'archived': 'only',
          'order': 'recent',
          'limit': '$pageSize',
          'offset': '$offset',
          if (gatewayProfile != null && gatewayProfile.isNotEmpty)
            'profile': gatewayProfile,
        },
      );
      // The dashboard router reports the filtered row count alongside the
      // page (`total = session_count(same scope)`), so the LIMIT/OFFSET
      // windows together cover exactly `total` rows — pins inside the
      // window are part of that count, back-filled pins are repeats of
      // rows already counted. Advancing until the offset covers `total`
      // cannot confuse a pin-only window (zero new ids, rows still ahead)
      // with the end of the archive.
      final reportedTotal = data['total'];
      if (reportedTotal is int && reportedTotal >= 0) total = reportedTotal;
      final list = data['sessions'] as List? ?? [];
      final rows = list
          .whereType<Map<String, dynamic>>()
          .map((s) => Session.fromJson(s))
          .toList();
      var newRows = 0;
      for (final row in rows) {
        if (seenIds.add(row.id)) {
          all.add(row);
          newRows++;
        }
      }
      offset += pageSize;
      if (total != null) {
        if (offset >= total) {
          exhausted = true;
          break;
        }
        continue;
      }
      // No `total` (non-standard router): fall back to the client-side
      // proof — a single zero-new page is NOT exhaustion when pins exist
      // (a later all-pin window repeats seen ids while unseen rows
      // remain); k consecutive zero-new windows past the pin bound are.
      final pinsOnPage = rows.where((row) => row.pinned).length;
      if (pinsOnPage > pinBound) pinBound = pinsOnPage;
      if (rows.isEmpty || newRows == 0) {
        zeroNewPages++;
        final required = pinBound == 0 ? 1 : pinBound ~/ pageSize + 1;
        if (zeroNewPages >= required) {
          exhausted = true;
          break;
        }
      } else {
        zeroNewPages = 0;
      }
    }
    if (!exhausted) {
      throw StateError(
        'Archived session list exceeded the $maxPages-page cap without '
        'reaching its end; refusing to present a possibly truncated '
        'archive as complete.',
      );
    }
    return all;
  }

  Map<String, String>? _cronQuery([Map<String, String>? parameters]) {
    final profile = _gatewayProfile;
    if (profile == null) return parameters;
    return {...?parameters, 'profile': profile};
  }

  Future<List<Map<String, dynamic>>> getCronJobs() async {
    final data = await apiGetList('cron/jobs', queryParameters: _cronQuery());
    return data.whereType<Map<String, dynamic>>().toList();
  }

  /// Run sessions produced by one cron job, newest first.
  ///
  /// Mirrors the desktop's `getCronJobRuns` (apps/desktop/src/api/cron.ts):
  /// runs are ordinary sessions with id `cron_{job_id}_{timestamp}` and
  /// `source='cron'`, enumerated by the dashboard's bounded id-range scan.
  /// This is the desktop-parity home for cron output: the chat list excludes
  /// machine-source rows, so per-job runs are browsed here instead.
  Future<List<Session>> getCronJobRuns(String jobId, {int limit = 20}) async {
    final data = await apiGet(
      'cron/jobs/${Uri.encodeComponent(jobId)}/runs',
      queryParameters: _cronQuery({'limit': '$limit'}),
    );
    final list = data['runs'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((s) => Session.fromJson(s))
        .toList();
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .post(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiPost(
        endpoint,
        body: body,
        queryParameters: queryParameters,
        retried: true,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decodeMapResponse(res);
  }

  Future<void> apiDelete(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool retried = false,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .delete(uri, headers: headers)
        .timeout(ApiClient.requestTimeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiDelete(
        endpoint,
        queryParameters: queryParameters,
        retried: true,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> apiPut(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool retried = false,
    Duration timeout = ApiClient.requestTimeout,
  }) async {
    final authGeneration = _authGeneration;
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$_baseUrl/api/$endpoint',
    ).replace(queryParameters: queryParameters);
    final res = await _http
        .put(
          uri,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(timeout);
    if (res.statusCode == 401 && !retried) {
      _resetAuth(ifGeneration: authGeneration);
      return apiPut(
        endpoint,
        body: body,
        queryParameters: queryParameters,
        retried: true,
        timeout: timeout,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decodeMapResponse(res);
  }

  Future<Map<String, dynamic>> getModelInfo() => apiGet('model/info');
  Future<Map<String, dynamic>> getModelOptions() => apiGet('model/options');
  Future<List<Map<String, dynamic>>> getSkills() async {
    final data = await apiGetList('skills');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> setModel(
    String scope,
    String provider,
    String model,
  ) => apiPost(
    'model/set',
    body: {'scope': scope, 'provider': provider, 'model': model},
  );

  // ── Cron job management ──────────────────────────────────────────────

  Future<Map<String, dynamic>> createJob({
    required String prompt,
    required String schedule,
    String name = '',
    String deliver = 'local',
  }) => apiPost(
    'cron/jobs',
    queryParameters: _cronQuery(),
    body: {
      'prompt': prompt,
      'schedule': schedule,
      'name': name,
      'deliver': deliver,
    },
  );

  static Map<String, dynamic> buildCronUpdateBody(
    Map<String, dynamic> updates,
  ) => {'updates': updates};

  Future<Map<String, dynamic>> updateJob(
    String jobId,
    Map<String, dynamic> updates, {
    Duration timeout = ApiClient.requestTimeout,
  }) => apiPut(
    'cron/jobs/${Uri.encodeComponent(jobId)}',
    queryParameters: _cronQuery(),
    body: buildCronUpdateBody(updates),
    timeout: timeout,
  );

  Future<Map<String, dynamic>> setJobPaused(
    String jobId, {
    required bool paused,
  }) => apiPost(
    'cron/jobs/${Uri.encodeComponent(jobId)}/${paused ? 'pause' : 'resume'}',
    queryParameters: _cronQuery(),
  );

  Future<Map<String, dynamic>> triggerJob(String jobId) => apiPost(
    'cron/jobs/${Uri.encodeComponent(jobId)}/trigger',
    queryParameters: _cronQuery(),
  );

  Future<void> deleteJob(String jobId) => apiDelete(
    'cron/jobs/${Uri.encodeComponent(jobId)}',
    queryParameters: _cronQuery(),
  );

  void close() => _http.close();
}
