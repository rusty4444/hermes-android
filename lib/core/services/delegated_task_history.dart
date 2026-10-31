import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/background_report.dart';
import '../models/gateway_insight.dart';
import '../utils/android_prompt_context.dart';
import 'connection_manager.dart';
import 'desktop_gateway_client.dart';
import 'tls_client_factory.dart';

enum TaskHistoryProblem {
  invalidReference,
  authRequired,
  authRejected,
  incompatible,
  identityUnproven,
  partialCompression,
  partialAncestors,
  missingReference,
  missingRowIdentity,
  notReady,
  refreshFailed,
}

class TaskHistoryUnavailable implements Exception {
  const TaskHistoryUnavailable(this.reason);
  final TaskHistoryProblem reason;
  @override
  String toString() => 'TaskHistoryUnavailable(${reason.name})';
}

class TaskHistoryReadFailure implements Exception {
  const TaskHistoryReadFailure(this.reason);
  final TaskHistoryProblem reason;
}

class TaskHistoryPage {
  const TaskHistoryPage({
    required this.rows,
    required this.sessionId,
    required this.offset,
    required this.lineage,
    this.limitation,
  });
  final List<Map<String, dynamic>> rows;
  final String sessionId;
  final int offset;

  /// Verified compression path, newest segment first and task root last.
  final List<String> lineage;
  final TaskHistoryProblem? limitation;
  bool get partial => limitation != null;
}

abstract interface class TaskHistorySource {
  Future<TaskHistoryPage> fetch(
    String childId,
    int offset, {
    String? latestChildId,
    String? currentSessionId,
  });
  void close();
}

/// Dashboard raw history only: no socket, runtime session or API-server fallback.
class DashboardTaskHistory implements TaskHistorySource {
  DashboardTaskHistory({
    required this.dashboard,
    this.profile,
    this.authAvailable = true,
  });
  final DashboardClient dashboard;
  final String? profile;
  final bool authAvailable;

  factory DashboardTaskHistory.fromConnection(
    SavedConnection connection, {
    http.Client? httpClient,
  }) {
    final base = Uri.parse(
      DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
    );
    final local = const {'localhost', '127.0.0.1', '::1'}.contains(base.host);
    return DashboardTaskHistory(
      dashboard: DashboardClient(
        host: base.host,
        port: base.port,
        useHttps: base.scheme == 'https',
        pathPrefix: base.path == '/' ? '' : base.path,
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
        httpClient: _TaskHistoryHttpClient(
          httpClient ??
              const TlsClientFactory().createRestClient(
                connection.clientCertificate,
              ),
        ),
      ),
      profile: connection.gatewayProfile,
      authAvailable:
          connection.dashboardProxied ||
          local ||
          (connection.dashboardUsername?.isNotEmpty == true &&
              connection.dashboardPassword?.isNotEmpty == true),
    );
  }

  @override
  Future<TaskHistoryPage> fetch(
    String childId,
    int offset, {
    String? latestChildId,
    String? currentSessionId,
  }) async {
    if ([childId, latestChildId, currentSessionId].whereType<String>().any(
          (id) => GatewaySubagentActivity.opaqueId(id) == null,
        ) ||
        offset < 0) {
      throw const TaskHistoryUnavailable(TaskHistoryProblem.invalidReference);
    }
    if (!authAvailable) {
      throw const TaskHistoryUnavailable(TaskHistoryProblem.authRequired);
    }
    try {
      // Per-read cache/budget, never a global session-store scan. References
      // from live events and messages are candidates, not authority.
      final details = <String, Map<String, dynamic>>{};
      var reads = 0;
      Future<Map<String, dynamic>> detail(
        String id, {
        bool fresh = false,
      }) async {
        if (!fresh && details.containsKey(id)) return details[id]!;
        if (++reads > 100) {
          throw const TaskHistoryUnavailable(
            TaskHistoryProblem.identityUnproven,
          );
        }
        final row = await _exactDetail(id);
        final owner = details[childId]?['profile'];
        if (owner != null && row['profile'] != owner) {
          throw const TaskHistoryUnavailable(
            TaskHistoryProblem.identityUnproven,
          );
        }
        return details[id] = row;
      }

      await detail(childId); // Prefix resolution must never become identity.
      var lineage = <String>[childId];
      for (final candidate in [currentSessionId, latestChildId]) {
        if (candidate == null || lineage.contains(candidate)) continue;
        final path = await _proveCompressionLineage(childId, candidate, detail);
        // Descendants of one compressed root can still be unrelated forks.
        // Only advance on the verified branch, never choose by time.
        if (!path.contains(lineage.first)) {
          throw const TaskHistoryUnavailable(
            TaskHistoryProblem.identityUnproven,
          );
        }
        lineage = path;
      }
      var pageOffset =
          currentSessionId != null && lineage.first != currentSessionId
          ? 0
          : offset;
      var data = await _messages(lineage.first, pageOffset);
      var path = await _proveCompressionLineage(
        childId,
        data['session_id'],
        detail,
      );
      if (!path.contains(lineage.first)) {
        throw const TaskHistoryUnavailable(TaskHistoryProblem.identityUnproven);
      }
      // OFFSET belongs to one canonical segment. Rotation found by messages
      // restarts at the head before any rows are published.
      if (pageOffset != 0 &&
          path.first != (currentSessionId ?? lineage.first)) {
        pageOffset = 0;
        lineage = path;
        data = await _messages(lineage.first, 0);
        path = await _proveCompressionLineage(
          childId,
          data['session_id'],
          detail,
        );
        if (!path.contains(lineage.first)) {
          throw const TaskHistoryUnavailable(
            TaskHistoryProblem.identityUnproven,
          );
        }
      }
      final messages = data['messages'];
      final pagination = data['pagination'];
      if (messages is! List ||
          messages.length > 50 ||
          messages.any((row) => row is! Map<String, dynamic>) ||
          pagination is! Map ||
          pagination['limit'] != 50 ||
          pagination['offset'] != pageOffset ||
          pagination['order'] != 'latest' ||
          pagination['returned'] != messages.length ||
          (profile?.isNotEmpty == true && data['profile'] != profile) ||
          (details[childId]?['profile'] != null &&
              data['profile'] != details[childId]!['profile'])) {
        throw const TaskHistoryUnavailable(TaskHistoryProblem.incompatible);
      }
      final tip = await detail(path.first, fresh: true);
      final missingAncestors =
          tip['end_reason'] != 'compression' &&
          tip['source'] == 'tool' &&
          (path.length > 1 || await _hasCompressionParent(tip, detail));
      return TaskHistoryPage(
        rows: messages.cast<Map<String, dynamic>>(),
        sessionId: path.first,
        offset: pageOffset,
        lineage: path,
        // Stock resume/latest-descendant exclude inherited delegation markers
        // and tool sources. The original may be only a partial snapshot.
        limitation: tip['end_reason'] == 'compression'
            ? TaskHistoryProblem.partialCompression
            // Stock tool-source messages omit ancestors even at a verified
            // tip. A short page proves only this segment is exhausted.
            : missingAncestors
            ? TaskHistoryProblem.partialAncestors
            : null,
      );
    } on DashboardHttpException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        throw const TaskHistoryUnavailable(TaskHistoryProblem.authRejected);
      }
      if (error.statusCode == 404) {
        throw const TaskHistoryReadFailure(TaskHistoryProblem.notReady);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _messages(String id, int offset) =>
      dashboard.apiGet(
        'sessions/${Uri.encodeComponent(id)}/messages',
        queryParameters: {
          if (profile?.isNotEmpty == true) 'profile': profile!,
          'limit': '50',
          'offset': '$offset',
          'order': 'latest',
          'inline_images': 'false',
          'include_compacted': 'true',
        },
      );

  Future<Map<String, dynamic>> _exactDetail(String id) async {
    final detail = await dashboard.apiGet(
      'sessions/${Uri.encodeComponent(id)}',
      queryParameters: {if (profile?.isNotEmpty == true) 'profile': profile!},
    );
    if (detail['id'] != id ||
        (profile?.isNotEmpty == true && detail['profile'] != profile)) {
      throw const TaskHistoryUnavailable(TaskHistoryProblem.identityUnproven);
    }
    return detail;
  }

  Future<List<String>> _proveCompressionLineage(
    String original,
    Object? canonical,
    Future<Map<String, dynamic>> Function(String id) detail,
  ) async {
    var current = GatewaySubagentActivity.opaqueId(canonical);
    final path = <String>[];
    for (var hop = 0; hop < 32 && current != null; hop++) {
      if (path.contains(current)) break;
      path.add(current);
      if (current == original) return path;
      final child = await detail(current);
      final parentId = GatewaySubagentActivity.opaqueId(
        child['parent_session_id'],
      );
      if (parentId == null) break;
      final parent = await detail(parentId);
      if (!_isCompressionEdge(child, parent)) break;
      current = parentId;
    }
    throw const TaskHistoryUnavailable(TaskHistoryProblem.identityUnproven);
  }

  /// The advertised reference can already be the tip, making its verified
  /// task path a singleton. One proven compression edge is enough to disclose
  /// missing ancestors; never fetch ancestor messages or scan for siblings.
  Future<bool> _hasCompressionParent(
    Map<String, dynamic> tip,
    Future<Map<String, dynamic>> Function(String id) detail,
  ) async {
    final parentId = GatewaySubagentActivity.opaqueId(tip['parent_session_id']);
    if (parentId == null || parentId == tip['id']) return false;
    final config = decodeTaskJson(tip['model_config']);
    // A newly delegated/branched/reset task is not its parent's compression
    // continuation, even when that parent chat subsequently compressed.
    if (config is Map && _forkMarkers.any((key) => config[key] == parentId)) {
      return false;
    }
    return _isCompressionEdge(tip, await detail(parentId));
  }

  static const _forkMarkers = [
    '_delegate_from',
    '_branched_from',
    '_reset_from',
  ];

  bool _isCompressionEdge(
    Map<String, dynamic> child,
    Map<String, dynamic> parent,
  ) {
    final parentId = parent['id'];
    final ended = parent['ended_at'];
    final started = child['started_at'];
    final parentStarted = parent['started_at'];
    // Publication inserts the child just BEFORE stamping parent closure.
    if (parent['end_reason'] != 'compression' ||
        ended is! num ||
        started is! num ||
        parentStarted is! num ||
        !ended.isFinite ||
        !started.isFinite ||
        !parentStarted.isFinite ||
        ended < parentStarted ||
        started < parentStarted ||
        child['source'] is! String ||
        child['source'] != parent['source'] ||
        !child.containsKey('model_config') ||
        !parent.containsKey('model_config')) {
      return false;
    }
    final config = decodeTaskJson(child['model_config']);
    final parentConfig = decodeTaskJson(parent['model_config']);
    if ((config != null && config is! Map) ||
        (parentConfig != null && parentConfig is! Map)) {
      return false;
    }
    // Inherited grandparent markers are valid only when copied unchanged.
    return !_forkMarkers.any((key) {
      final marker = config is Map ? config[key] : null;
      final inherited = parentConfig is Map ? parentConfig[key] : null;
      return marker == parentId || marker != inherited;
    });
  }

  @override
  void close() => dashboard.close();
}

/// An auth request can finish after the viewer closes. Reject the follow-up
/// GET before it reaches the delegate, even with clients whose close is a no-op.
class _TaskHistoryHttpClient extends http.BaseClient {
  _TaskHistoryHttpClient(this._delegate);
  final http.Client _delegate;
  bool _closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw StateError('Task history viewer is closed');
    }
    final response = await _delegate.send(request);
    if (request.url.path.endsWith('/auth/password-login') &&
        (response.statusCode == 401 || response.statusCode == 403)) {
      await response.stream.drain<void>();
      throw const TaskHistoryUnavailable(TaskHistoryProblem.authRejected);
    }
    return response;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _delegate.close();
  }
}

Object? decodeTaskJson(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } on FormatException {
    return value;
  }
}

String _pretty(Object? value) =>
    value is String ? value : const JsonEncoder.withIndent('  ').convert(value);

/// Read only explicitly exposed textual fields; encrypted/opaque reasoning is
/// deliberately not stringified. Sidecars can be JSON strings or native lists.
List<String> _reasoningText(Object? raw) {
  final value = decodeTaskJson(raw);
  if (value is String) return value.trim().isEmpty ? [] : [value];
  if (value is List) return value.expand(_reasoningText).toList();
  if (value is Map) {
    if (const {
      'reasoning.encrypted',
      'redacted_thinking',
    }.contains(value['type'])) {
      return [];
    }
    for (final key in ['text', 'thinking', 'summary', 'content']) {
      if (value[key] != null) return _reasoningText(value[key]);
    }
  }
  return [];
}

// Server-projected text is already decoded: JSON-looking prose stays prose.
List<String> _projectedText(Object? raw) => [
  if (raw is String) raw,
  if (raw is List) ...raw.whereType<String>(),
].where((text) => text.trim().isNotEmpty).toList();

String _prose(Object? raw) {
  // Prose that happens to be JSON is still prose, not an encoded sidecar.
  final value = raw;
  if (value is String) return value;
  if (value is List) {
    return value
        .map((part) {
          if (part is String) return part;
          if (part is Map &&
              const {
                'text',
                'output_text',
                'input_text',
              }.contains(part['type'])) {
            return part['text'] as String? ?? '';
          }
          return '';
        })
        .where((text) => text.isNotEmpty)
        .join('\n');
  }
  // A literal JSON result is still actual result content.
  return raw is String ? raw : '';
}

class TaskToolCall {
  const TaskToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String? id;
  final String name;
  final String? arguments;
}

List<TaskToolCall> _calls(Object? raw) {
  final list = decodeTaskJson(raw);
  if (list is! List) return [];
  return [
    for (final call in list.whereType<Map>())
      if (call['function'] is Map)
        TaskToolCall(
          id: call['id'] is String ? call['id'] as String : null,
          name: (call['function'] as Map)['name'] as String? ?? 'tool',
          arguments: (call['function'] as Map)['arguments'] == null
              ? null
              : _pretty((call['function'] as Map)['arguments']),
        ),
  ];
}

class TaskTranscriptRow {
  const TaskTranscriptRow({
    required this.id,
    required this.role,
    required this.text,
    required this.reasoning,
    required this.reasoningKeys,
    required this.calls,
    this.toolId,
    this.toolName,
    this.backgroundReport,
  });
  final int id;
  final String role;
  final String text;
  final List<String> reasoning;
  final List<String> reasoningKeys;
  final List<TaskToolCall> calls;
  final String? toolId;
  final String? toolName;
  final BackgroundReport? backgroundReport;
}

int? taskRowId(Map<String, dynamic> row) {
  final id = row['id'];
  if (id is int) return id;
  if (id is String) return int.tryParse(id);
  return null;
}

List<TaskTranscriptRow> parseTaskTranscript(List<Map<String, dynamic>> rows) {
  final ordered = rows.where((row) => taskRowId(row) != null).toList()
    ..sort((a, b) => taskRowId(a)!.compareTo(taskRowId(b)!));
  final names = <String, String>{};
  for (final row in ordered) {
    for (final call in _calls(row['tool_calls'])) {
      if (call.id != null) names[call.id!] = call.name;
    }
  }
  final transcript = <TaskTranscriptRow>[];
  for (final row in ordered) {
    final metadata = row['display_metadata'];
    if (row['display_kind'] == 'hidden' ||
        (metadata is Map && metadata['model_only'] == true) ||
        (row['role'] == 'user' &&
            row.containsKey('display_content') &&
            (row['display_content'] == null || row['display_content'] == '')) ||
        !const {
          'user',
          'assistant',
          'agent',
          'tool',
          'system',
        }.contains(row['role'])) {
      continue;
    }
    final reasoning = <MapEntry<String, String>>[
      for (final field
          in row.containsKey('display_reasoning')
              ? ['display_reasoning']
              : [
                  'reasoning',
                  'reasoning_content',
                  'reasoning_details',
                  'codex_reasoning_items',
                ])
        for (final (index, text)
            in (field == 'display_reasoning'
                    ? _projectedText(row[field])
                    : _reasoningText(row[field]))
                .indexed)
          MapEntry('$field:$index', text),
    ];
    transcript.add(
      TaskTranscriptRow(
        id: taskRowId(row)!,
        role: row['role'] == 'agent' ? 'assistant' : row['role'] as String,
        backgroundReport: BackgroundReport.fromMessage(row),
        text: row['role'] == 'tool'
            ? (row['content'] == null ? '' : _pretty(row['content']))
            : [
                ..._projectedText(row['display_commentary']),
                _prose(
                  AndroidPromptContext.displayContent(
                    row,
                    row.containsKey('display_content')
                        ? row['display_content']
                        : row['content'],
                  ),
                ),
              ].where((text) => text.isNotEmpty).join('\n\n'),
        reasoning: reasoning.map((entry) => entry.value).toList(),
        reasoningKeys: reasoning.map((entry) => entry.key).toList(),
        calls: _calls(row['tool_calls']),
        toolId: row['tool_call_id'] is String
            ? row['tool_call_id'] as String
            : null,
        toolName:
            names[row['tool_call_id']] ??
            (row['name'] is String ? row['name'] as String : null) ??
            (row['tool_name'] is String ? row['tool_name'] as String : null) ??
            'tool',
      ),
    );
  }
  return transcript;
}

/// Recover only delegate_task's known top-level result/results schema. Never
/// recurse into arbitrary tool output or accept a generic session_id as a child.
List<GatewaySubagentActivity> recoverDelegatedTasks(
  List<Map<String, dynamic>> rows,
) {
  final delegates = <String, Map>{};
  for (final row in rows) {
    final calls = decodeTaskJson(row['tool_calls']);
    if (calls is! List) continue;
    for (final call in calls.whereType<Map>()) {
      final function = call['function'];
      if (function is Map &&
          function['name'] == 'delegate_task' &&
          call['id'] is String) {
        final args = decodeTaskJson(function['arguments']);
        delegates[call['id'] as String] = args is Map ? args : {};
      }
    }
  }
  final recovered = <GatewaySubagentActivity>[];
  for (final row in rows) {
    if (row['role'] != 'tool') continue;
    final callId = row['tool_call_id'];
    if (callId is! String ||
        (!delegates.containsKey(callId) &&
            row['name'] != 'delegate_task' &&
            row['tool_name'] != 'delegate_task')) {
      continue;
    }
    final result = decodeTaskJson(row['content']);
    final args = delegates[callId];
    if (_isControlAcknowledgement(args) || _isControlAcknowledgement(result)) {
      continue;
    }
    final entries = _delegationEntries(result);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry is! Map || _isControlAcknowledgement(entry)) continue;
      final taskArgs = args?['tasks'];
      final arg = taskArgs is List && i < taskArgs.length && taskArgs[i] is Map
          ? taskArgs[i] as Map
          : args;
      recovered.add(
        GatewaySubagentActivity.fromGatewayEvent(
          const {
                'completed',
                'failed',
                'error',
                'interrupted',
                'cancelled',
              }.contains(entry['status'])
              ? 'subagent.complete'
              : 'subagent.start',
          {
            ...Map<String, dynamic>.from(entry),
            'subagent_id':
                GatewaySubagentActivity.opaqueId(entry['subagent_id']) ??
                'stored-tool:$callId:$i',
            'goal': entry['goal'] ?? arg?['goal'],
            'task_index': i,
          },
        )!,
      );
    }
  }
  return recovered;
}

bool _isControlAcknowledgement(Object? value) =>
    value is Map &&
    ((value['action'] != null && value['action'] != 'spawn') ||
        const {'queued', 'interrupt_requested'}.contains(value['status']) ||
        value.containsKey('subagents'));

List<dynamic> _delegationEntries(Object? result) {
  if (result is! Map) return [];
  if (result['results'] is List) return result['results'] as List;
  // Actual background dispatch carries runtime ids/goals, not durable child
  // refs. Preserve each task; opening it explains the missing-reference limit.
  if (result['status'] == 'dispatched' && result['goals'] is List) {
    final goals = result['goals'] as List;
    final ids = result['subagent_ids'];
    return [
      for (var i = 0; i < goals.length; i++)
        {
          ...result,
          'goal': goals[i],
          if (ids is List && i < ids.length) 'subagent_id': ids[i],
        },
    ];
  }
  return [result];
}
