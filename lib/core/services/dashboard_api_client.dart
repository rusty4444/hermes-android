// The classic app's [ApiClient] surface served entirely by the dashboard.
//
// A single-login connection has no API-server key: everything the classic
// screens used to read from the API server on 8642 (session list, transcript,
// rename / pin / archive / delete, models, health) is answered by the same
// dashboard routes Hermes Desktop and Kyllene use
// (hermes_cli/web_routers/sessions.py), authenticated with the one sign-in.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'connection_manager.dart';
import 'hermes_sign_in.dart';

/// Thrown for API-server-only operations a dashboard can't perform.
class DashboardUnsupportedException implements Exception {
  final String operation;
  const DashboardUnsupportedException(this.operation);

  @override
  String toString() =>
      '$operation is not available on a single sign-in connection.';
}

/// A gateway refusal, with the gateway's own words when it gave any.
class DashboardRequestException implements Exception {
  final int statusCode;
  final String message;
  const DashboardRequestException(this.statusCode, this.message);

  @override
  String toString() => message;
}

/// Reads the human message out of a dashboard error body.
String dashboardErrorMessage(http.Response res) {
  try {
    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final detail =
          decoded['detail'] ?? decoded['error'] ?? decoded['message'];
      if (detail is String && detail.trim().isNotEmpty) return detail.trim();
      if (detail is Map) {
        final inner = detail['message'] ?? detail['detail'] ?? detail['code'];
        if (inner is String && inner.trim().isNotEmpty) return inner.trim();
      }
    }
  } catch (_) {
    // Not JSON: fall through to the status.
  }
  return 'HTTP ${res.statusCode}';
}

Map<String, dynamic> _decodeMap(http.Response res) {
  final body = res.body.trim();
  if (body.isEmpty) return <String, dynamic>{};
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) return decoded;
  return {'data': decoded};
}

/// Stored-session writes the way the dashboard takes them: the row's
/// mutation snapshot is read first and named in the write, so the gateway
/// applies it once and only over the row as read. Older gateways lack the
/// snapshot route (a 404 "Not Found" / "No such API endpoint", or a non-JSON
/// reply) and get the write without identity. A write that lost a race is
/// re-read and sent once more, unless it carries a title.
class DashboardSessionWrites {
  DashboardSessionWrites(this._dashboard, {this._profile});

  final DashboardClient _dashboard;
  final String? _profile;
  static const _uuid = Uuid();

  Map<String, String>? get _profileQuery =>
      _profile == null ? null : {'profile': _profile};

  Future<({String requestId, int revision, int? generation})?> _identity(
    String sessionId,
  ) async {
    final res = await _dashboard.apiRequest(
      'GET',
      'sessions/${Uri.encodeComponent(sessionId)}/mutation-snapshot',
      queryParameters: _profileQuery,
    );
    final isJson = (res.headers['content-type'] ?? '').contains('json');
    if (res.statusCode == 404) {
      final message = dashboardErrorMessage(res);
      if (!isJson ||
          message == 'Not Found' ||
          message.startsWith('No such API endpoint')) {
        return null;
      }
      throw SessionNotFoundException(sessionId);
    }
    if (!isJson) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DashboardRequestException(
        res.statusCode,
        dashboardErrorMessage(res),
      );
    }
    final snapshot = _decodeMap(res);
    if (snapshot['exists'] == false) throw SessionNotFoundException(sessionId);
    final revision = snapshot['runtime_revision'];
    final generation = snapshot['runtime_generation'];
    return (
      requestId: _uuid.v4(),
      revision: revision is int ? revision : 0,
      generation: generation is int ? generation : null,
    );
  }

  static bool _lostRace(http.Response res) {
    if (res.statusCode != 409) return false;
    final body = res.body;
    return body.contains('revision_conflict') ||
        body.contains('stale_generation');
  }

  /// `PATCH /api/sessions/{id}` with any of title / archived / pinned /
  /// unread.
  Future<Map<String, dynamic>> patch(
    String sessionId,
    Map<String, dynamic> fields,
  ) async {
    final attempts = fields.containsKey('title') ? 1 : 2;
    http.Response? last;
    for (var i = 0; i < attempts; i++) {
      final identity = await _identity(sessionId);
      final res = await _dashboard.apiRequest(
        'PATCH',
        'sessions/${Uri.encodeComponent(sessionId)}',
        body: {
          ...fields,
          'profile': ?_profile,
          if (identity != null) ...{
            'request_id': identity.requestId,
            'expected_revision': identity.revision,
            'expected_generation': ?identity.generation,
          },
        },
      );
      last = res;
      if (res.statusCode >= 200 && res.statusCode < 300) return _decodeMap(res);
      if (res.statusCode == 404) throw SessionNotFoundException(sessionId);
      if (identity == null || !_lostRace(res)) break;
    }
    throw DashboardRequestException(
      last!.statusCode,
      _inWords(dashboardErrorMessage(last)),
    );
  }

  /// `DELETE /api/sessions/{id}`; an already-deleted session succeeds.
  Future<void> delete(String sessionId) async {
    for (var i = 0; i < 2; i++) {
      final ({String requestId, int revision, int? generation})? identity;
      try {
        identity = await _identity(sessionId);
      } on SessionNotFoundException {
        return;
      }
      final res = await _dashboard.apiRequest(
        'DELETE',
        'sessions/${Uri.encodeComponent(sessionId)}',
        queryParameters: {
          ...?_profileQuery,
          if (identity != null) ...{
            'request_id': identity.requestId,
            'expected_revision': '${identity.revision}',
            if (identity.generation != null)
              'expected_generation': '${identity.generation}',
          },
        },
      );
      if (res.statusCode == 404) return;
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      if (identity == null || !_lostRace(res)) {
        throw DashboardRequestException(
          res.statusCode,
          _inWords(dashboardErrorMessage(res)),
        );
      }
    }
  }

  static String _inWords(String message) => switch (message) {
    'session_busy' =>
      'The chat is busy with a turn right now. Try again when it finishes.',
    'revision_conflict' ||
    'stale_generation' => 'The chat changed on another device. Try again.',
    _ => message,
  };
}

/// The classic [ApiClient] backed by the dashboard. Built by
/// [ApiClient.forConnection] for single-login connections.
class DashboardApiClient extends ApiClient {
  DashboardApiClient._(this.dashboard, this._profile, http.Client? httpClient)
    : _writes = DashboardSessionWrites(dashboard, profile: _profile),
      super(baseUrl: dashboard.baseUrl, apiKey: '', httpClient: httpClient);

  /// Shares an existing [DashboardClient] (and its sign-in) with this client.
  DashboardApiClient.withDashboard(DashboardClient dashboard, {String? profile})
    : this._(dashboard, profile, null);

  factory DashboardApiClient.fromConnection(
    SavedConnection connection, {
    http.Client? httpClient,
  }) {
    final profile = connection.gatewayProfile?.trim();
    return DashboardApiClient._(
      DashboardClient.fromConnection(connection, httpClient: httpClient),
      profile == null || profile.isEmpty ? null : profile,
      httpClient,
    );
  }

  final DashboardClient dashboard;
  final String? _profile;
  final DashboardSessionWrites _writes;

  Map<String, String> get _profileQuery => {'profile': ?_profile};

  Future<Map<String, dynamic>> _getMap(
    String endpoint, {
    Map<String, String>? query,
    Duration timeout = ApiClient.requestTimeout,
  }) async {
    final res = await dashboard.apiRequest(
      'GET',
      endpoint,
      queryParameters: {..._profileQuery, ...?query},
      timeout: timeout,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DashboardRequestException(
        res.statusCode,
        dashboardErrorMessage(res),
      );
    }
    return _decodeMap(res);
  }

  @override
  Future<SessionListPage> getSessionsPage({
    int limit = 50,
    int offset = 0,
    String? title,
    Duration timeout = ApiClient.requestTimeout,
  }) async {
    if (title != null && title.trim().isNotEmpty) {
      final found = await _getMap(
        'sessions/search',
        query: {'q': title.trim(), 'limit': '${limit.clamp(1, 100)}'},
        timeout: timeout,
      );
      final rows = (found['results'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Session.fromJson)
          .toList();
      return SessionListPage(sessions: rows, hasMore: false);
    }
    final pageSize = limit.clamp(1, 100);
    final data = await _getMap(
      'sessions',
      query: {
        'limit': '$pageSize',
        'offset': '$offset',
        'order': 'recent',
        'archived': 'exclude',
      },
      timeout: timeout,
    );
    final rows = (data['sessions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Session.fromJson)
        .toList();
    final total = data['total'];
    return SessionListPage(
      sessions: rows,
      hasMore: total is int
          ? offset + rows.length < total
          : rows.length >= pageSize,
    );
  }

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final res = await dashboard.apiRequest(
      'GET',
      'sessions/${Uri.encodeComponent(sessionId)}',
      queryParameters: _profileQuery,
    );
    if (res.statusCode == 404) throw SessionNotFoundException(sessionId);
    if (res.statusCode != 200) {
      throw DashboardRequestException(
        res.statusCode,
        dashboardErrorMessage(res),
      );
    }
    final data = _decodeMap(res);
    final nested = data['session'];
    final row = nested is Map ? Map<String, dynamic>.from(nested) : data;
    row['archived'] = row['archived'] == true || row['archived'] == 1;
    if (row.containsKey('pinned')) {
      row['pinned'] = row['pinned'] == true || row['pinned'] == 1;
    }
    return row;
  }

  @override
  Future<String> renameSession({
    required String sessionId,
    required String title,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be blank');
    }
    await _writes.patch(sessionId, {'title': trimmed});
    final saved = await getSession(sessionId);
    return (saved['title'] as String?)?.trim().isNotEmpty == true
        ? saved['title'] as String
        : trimmed;
  }

  @override
  Future<bool> setSessionArchived({
    required String sessionId,
    required bool archived,
    bool clearPin = false,
  }) async {
    await _writes.patch(sessionId, {
      'archived': archived,
      if (archived && clearPin) 'pinned': false,
    });
    final confirmed = await getSession(sessionId);
    if (confirmed['archived'] != archived) {
      throw const FormatException('Gateway archive read-back did not match');
    }
    return archived;
  }

  @override
  Future<bool> setSessionPinned({
    required String sessionId,
    required bool pinned,
  }) async {
    await _writes.patch(sessionId, {'pinned': pinned});
    final confirmed = await getSession(sessionId);
    if (confirmed.containsKey('pinned') && confirmed['pinned'] != pinned) {
      throw const FormatException('Gateway pin read-back did not match');
    }
    return pinned;
  }

  /// Sets the gateway's shared read state (`PATCH {unread}`), which Hermes
  /// Desktop and Kyllene read too.
  Future<void> setSessionUnread(String sessionId, {required bool unread}) =>
      _writes.patch(sessionId, {'unread': unread});

  /// The raw body of a transcript page, for callers that decode it off the
  /// UI thread (NextGen). Same query as [getMessages].
  Future<Uint8List> getMessagesBytes(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
  }) async {
    final res = await dashboard.apiRequest(
      'GET',
      'sessions/${Uri.encodeComponent(sessionId)}/messages',
      queryParameters: {
        ..._profileQuery,
        if (limit != null) 'limit': '${limit.clamp(0, 500)}',
        if (offset != 0) 'offset': '$offset',
        if (latest || limit == null) 'order': 'latest',
      },
      timeout: ApiClient.requestTimeout,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw DashboardRequestException(
        res.statusCode,
        dashboardErrorMessage(res),
      );
    }
    return res.bodyBytes;
  }

  @override
  Future<List<Map<String, dynamic>>> getMessages(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
  }) async {
    final data = await _getMap(
      'sessions/${Uri.encodeComponent(sessionId)}/messages',
      query: {
        if (limit != null) 'limit': '${limit.clamp(0, 500)}',
        if (offset != 0) 'offset': '$offset',
        if (latest || limit == null) 'order': 'latest',
      },
    );
    final list = data['messages'] ?? data['data'];
    return (list is List ? list : const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  @override
  Future<void> deleteSession(String sessionId) => _writes.delete(sessionId);

  @override
  Future<List<String>> getModels() async {
    try {
      final options = await dashboard.getModelOptions();
      final ids = <String>{};
      void collect(Object? value) {
        if (value is List) {
          for (final item in value) {
            if (item is String) ids.add(item);
            if (item is Map) {
              final id = item['id'] ?? item['model'] ?? item['name'];
              if (id is String) ids.add(id);
              collect(item['models']);
            }
          }
        }
      }

      collect(options['models']);
      collect(options['providers']);
      return ids.isEmpty ? ['hermes-agent'] : ids.toList();
    } catch (_) {
      return ['hermes-agent'];
    }
  }

  @override
  Future<ApiHealthCheckResult> checkHealth() async {
    final status = Uri.parse('${dashboard.baseUrl}/api/status');
    try {
      final probe = await GatewayProbe().probe(
        GatewayUrl.parse(dashboard.baseUrl),
      );
      if (probe is! ProbeReachable) {
        return ApiHealthCheckResult.httpFailure(status, 503);
      }
      final sessions = Uri.parse('${dashboard.baseUrl}/api/sessions');
      final res = await dashboard.apiRequest(
        'GET',
        'sessions',
        queryParameters: {..._profileQuery, 'limit': '1'},
        timeout: const Duration(seconds: 8),
      );
      if (res.statusCode != 200) {
        return ApiHealthCheckResult.httpFailure(sessions, res.statusCode);
      }
      return ApiHealthCheckResult.success(sessions);
    } catch (_) {
      return ApiHealthCheckResult.networkFailure(status);
    }
  }

  static String _dashboardEndpoint(String endpoint) {
    var path = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    if (path.startsWith('v1/')) {
      throw DashboardUnsupportedException('The API-server route /$path');
    }
    if (path.startsWith('api/')) path = path.substring(4);
    return path;
  }

  @override
  Future<Map<String, dynamic>> apiGet(String endpoint) {
    final parsed = Uri.parse(_dashboardEndpoint(endpoint));
    return dashboard.apiGet(
      parsed.path,
      queryParameters: parsed.queryParameters.isEmpty
          ? null
          : parsed.queryParameters,
    );
  }

  @override
  Future<List<dynamic>> apiGetList(String endpoint) {
    final parsed = Uri.parse(_dashboardEndpoint(endpoint));
    return dashboard.apiGetList(
      parsed.path,
      queryParameters: parsed.queryParameters.isEmpty
          ? null
          : parsed.queryParameters,
    );
  }

  @override
  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
  }) => dashboard.apiPost(_dashboardEndpoint(endpoint), body: body);

  @override
  Future<void> apiDelete(String endpoint) =>
      dashboard.apiDelete(_dashboardEndpoint(endpoint));

  @override
  Future<void> respondToRunApproval({
    required String runId,
    required String choice,
    String? requestId,
    Object? executionGeneration,
    bool canonicalControl = false,
    bool Function()? isCurrent,
  }) async {
    throw const DashboardUnsupportedException('A REST run approval');
  }

  @override
  Future<Map<String, dynamic>> getModelInfo() => dashboard.getModelInfo();

  @override
  Future<Map<String, dynamic>> getModelOptions() => dashboard.getModelOptions();

  @override
  Future<Map<String, dynamic>> setSessionModel({
    required String sessionId,
    required String provider,
    required String model,
    bool createSessionIfMissing = false,
  }) async {
    // A dashboard chat switches its model on the live session (`config.set`
    // over /api/ws); there is no REST lock to write.
    throw const DashboardUnsupportedException('A REST model lock');
  }

  @override
  Future<List<Map<String, dynamic>>> getSkills() => dashboard.getSkills();

  @override
  Future<Map<String, dynamic>> setModel(
    String scope,
    String provider,
    String model,
  ) => dashboard.setModel(scope, provider, model);

  @override
  void close() {
    dashboard.close();
    super.close();
  }
}
