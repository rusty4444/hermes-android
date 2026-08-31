// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
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

  Future<void> saveConnection(
    String label,
    String host,
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied = false,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
  }) async {
    final normalized = SavedConnection.normalizeHostAndPort(host, port);
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
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied = false,
    String? desktopGatewayUrl,
    int? dashboardPort,
    String? dashboardUsername,
    String? dashboardPassword,
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

/// HTTP client for the Hermes Gateway API Server (port 8642).
///
/// Uses Bearer token auth. Same pattern as hermes-desktop.
class ApiClient {
  final http.Client _http;
  final String baseUrl;
  final String _apiKey;

  // Keep the public parameter name `apiKey` while storing it privately.
  ApiClient({
    required String baseUrl,
    required String apiKey,
    String pathPrefix = '',
    http.Client? httpClient,
  }) : _apiKey = apiKey,
       baseUrl = SavedConnection.joinBaseUrl(baseUrl, pathPrefix),
       _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
  };

  // ── Session listing ──────────────────────────────────────────────────

  Future<List<Session>> getSessions() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/sessions'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((s) => Session.fromJson(s))
        .toList();
  }

  // ── Messages ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/sessions/$sessionId/messages'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> deleteSession(String sessionId) async {
    final encodedId = Uri.encodeComponent(sessionId);
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/sessions/$encodedId'),
      headers: _headers,
    );
    // Treat a stale local row as already synced: the remote no longer has it,
    // so the UI can safely remove it from history.
    if (res.statusCode == 404) return;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  // ── Models ───────────────────────────────────────────────────────────

  Future<List<String>> getModels() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/v1/models'),
      headers: _headers,
    );
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
    final res = await _http.get(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> apiGetList(String endpoint) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> apiDelete(String endpoint) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
    );
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
  StreamSubscription<String>? _activeStreamSubscription;
  Completer<void>? _activeStreamCompletion;
  bool _activeStreamCancelled = false;

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
    final completion = Completer<void>();
    _activeStreamCompletion = completion;
    _activeStreamCancelled = false;

    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_baseUrl/v1/chat/completions'),
      );
      request.headers.addAll(headers);
      request.body = jsonEncode(body);

      final response = await _api._http.send(request);

      if (_activeStreamCancelled ||
          !identical(_activeStreamCompletion, completion)) {
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
      _activeStreamSubscription = response.stream
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              if (_activeStreamCancelled) return;
              buffer += chunk;
              while (buffer.contains('\n\n')) {
                final eventEnd = buffer.indexOf('\n\n');
                final frame = buffer.substring(0, eventEnd);
                buffer = buffer.substring(eventEnd + 2);

                final token = parseSseFrame(
                  frame,
                  onToolProgress: onToolProgress,
                );
                if (token != null && token.isNotEmpty) onToken(token);
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

      if (!_activeStreamCancelled) onDone();
    } catch (e) {
      if (!_activeStreamCancelled) onError(e.toString());
    } finally {
      if (identical(_activeStreamCompletion, completion)) {
        _activeStreamSubscription = null;
        _activeStreamCompletion = null;
        _activeStreamCancelled = false;
      }
    }
  }

  /// Cancels the current SSE response. The Hermes API server treats the
  /// resulting client disconnect as an agent interrupt.
  Future<bool> cancelActiveMessage() async {
    final completion = _activeStreamCompletion;
    if (completion == null) return false;

    _activeStreamCancelled = true;
    final subscription = _activeStreamSubscription;
    if (subscription != null) {
      await subscription.cancel();
    }
    if (!completion.isCompleted) completion.complete();
    return true;
  }

  void abort() {
    _api.close();
  }
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
  String? _token;
  String? _cookie;
  // In-flight auth requests, shared so concurrent /api calls trigger a single
  // login / token fetch instead of a thundering herd (the dashboard
  // rate-limits password logins).
  Future<String>? _cookieInFlight;
  Future<String>? _tokenInFlight;

  String get baseUrl => _baseUrl;

  bool get _usesPasswordAuth =>
      (_username?.isNotEmpty ?? false) && (_password?.isNotEmpty ?? false);

  DashboardClient({
    required String host,
    int port = 9119,
    bool useHttps = false,
    String pathPrefix = '',
    bool proxied = false,
    String? username,
    String? password,
    http.Client? httpClient,
  }) : _proxied = proxied,
       _username = username,
       _password = password,
       _baseUrl = SavedConnection.joinBaseUrl(
         '${useHttps ? 'https' : 'http'}://$host:$port',
         pathPrefix,
       ),
       _http = httpClient ?? http.Client();

  /// Clears any cached auth state so the next request re-authenticates.
  void _resetAuth() {
    _token = null;
    _cookie = null;
    _cookieInFlight = null;
    _tokenInFlight = null;
  }

  /// Returns the session cookie, reusing a cached value or an in-flight login.
  Future<String> _getCookie() {
    final cached = _cookie;
    if (cached != null) return Future.value(cached);
    return _cookieInFlight ??= _login();
  }

  /// Logs in against the `basic` password provider and caches the session
  /// cookie. Throws on failure (bad credentials → 401, etc.).
  Future<String> _login() async {
    try {
      final res = await _http.post(
        Uri.parse('$_baseUrl/auth/password-login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'provider': 'basic',
          'username': _username,
          'password': _password,
        }),
      );
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
        throw Exception(
          'Dashboard login succeeded but no session cookie found',
        );
      }
      _cookie = '${match.group(1)}=${match.group(2)}';
      return _cookie!;
    } finally {
      _cookieInFlight = null;
    }
  }

  /// Returns the SPA session token, reusing a cached value or an in-flight fetch.
  Future<String> _getToken() {
    final cached = _token;
    if (cached != null) return Future.value(cached);
    return _tokenInFlight ??= _fetchToken();
  }

  Future<String> _fetchToken() async {
    try {
      final res = await _http.get(Uri.parse('$_baseUrl/'));
      if (res.statusCode != 200) throw Exception('Dashboard not reachable');
      final match = RegExp(
        r'window\.__HERMES_SESSION_TOKEN__="([^"]+)";',
      ).firstMatch(res.body);
      if (match == null) throw Exception('Session token not found');
      _token = match.group(1)!;
      return _token!;
    } finally {
      _tokenInFlight = null;
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    if (_proxied) return {'Content-Type': 'application/json'};
    if (_usesPasswordAuth) {
      return {'Cookie': await _getCookie(), 'Content-Type': 'application/json'};
    }
    return {
      'X-Hermes-Session-Token': await _getToken(),
      'Content-Type': 'application/json',
    };
  }

  /// Mints the short-lived, single-use WebSocket ticket required by a secured
  /// Hermes Desktop gateway. The HTTP API cookie stays in this client; only the
  /// ticket is passed to the WebSocket URL.
  Future<String> mintWebSocketTicket({bool retried = false}) async {
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/auth/ws-ticket'),
      headers: await _authHeaders(),
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
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
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiGet(endpoint, retried: true);
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return _decodeMapResponse(res);
  }

  Future<List<dynamic>> apiGetList(
    String endpoint, {
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiGetList(endpoint, retried: true);
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final decoded = jsonDecode(res.body);
    if (decoded is List<dynamic>) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List<dynamic>) {
      return decoded['data'] as List<dynamic>;
    }
    throw Exception('Expected list response');
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiPost(endpoint, body: body, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decodeMapResponse(res);
  }

  Future<void> apiDelete(String endpoint, {bool retried = false}) async {
    final headers = await _authHeaders();
    final res = await _http.delete(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiDelete(endpoint, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> apiPut(
    String endpoint, {
    Map<String, dynamic>? body,
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.put(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiPut(endpoint, body: body, retried: true);
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
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.put(
      Uri.parse('$_baseUrl/api/cron/jobs/$jobId'),
      headers: headers,
      body: jsonEncode(buildCronUpdateBody(updates)),
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return updateJob(jobId, updates, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void close() => _http.close();
}
