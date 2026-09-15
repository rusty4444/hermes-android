/// Client for the gateway's `filing.*` correction-aware Projects filing RPC.
///
/// Mirrors [ProjectsGatewayClient]'s compatibility discipline: the surface is
/// discovered by calling, never assumed. A gateway without the filing family
/// answers unknown-method and this client reports [FilingUnsupportedException]
/// once, then short-circuits — the More-pane entry stays disabled with its
/// reason instead of re-probing or erroring.
library;

import 'capability_registry.dart';
import 'projects_gateway_client.dart' show GatewayRpcCall;
import 'ws_client.dart' show JsonRpcError;

/// The gateway has no `filing.*` surface (or it was proven missing).
class FilingUnsupportedException implements Exception {
  final String method;
  final String message;

  const FilingUnsupportedException(this.method, this.message);

  @override
  String toString() => 'FilingUnsupportedException($method): $message';
}

/// One deterministic filing suggestion from `filing.suggest`.
class FilingSuggestion {
  final String sessionId;
  final String title;
  final String cwd;
  final String projectId;
  final String projectName;

  /// `contract_rule` (the user's own standing rule) or `cwd_match`
  /// (the session's working directory is owned by the project).
  final String reason;
  final double confidence;

  const FilingSuggestion({
    required this.sessionId,
    required this.title,
    required this.cwd,
    required this.projectId,
    required this.projectName,
    required this.reason,
    required this.confidence,
  });

  bool get isUserRule => reason == 'contract_rule';

  static FilingSuggestion? fromJson(Map<String, dynamic> json) {
    final sessionId = json['session_id'];
    final projectId = json['project_id'];
    if (sessionId is! String || sessionId.isEmpty) return null;
    if (projectId is! String || projectId.isEmpty) return null;
    return FilingSuggestion(
      sessionId: sessionId,
      title: json['title'] is String ? json['title'] as String : '',
      cwd: json['cwd'] is String ? json['cwd'] as String : '',
      projectId: projectId,
      projectName:
          json['project_name'] is String ? json['project_name'] as String : '',
      reason: json['reason'] is String ? json['reason'] as String : '',
      confidence: json['confidence'] is num
          ? (json['confidence'] as num).toDouble()
          : 0,
    );
  }
}

/// The filing contract's answer about this gateway.
class FilingStatus {
  /// True when the gateway has the contract library installed and reachable.
  final bool available;

  /// True when the `project-filing` gateway hook that records natural-language
  /// corrections is installed alongside it.
  final bool hookInstalled;
  final String contractPath;
  final int rules;
  final int exclusions;
  final int auditEntries;

  const FilingStatus({
    required this.available,
    required this.hookInstalled,
    required this.contractPath,
    required this.rules,
    required this.exclusions,
    required this.auditEntries,
  });

  static FilingStatus fromJson(Map<String, dynamic> json) => FilingStatus(
        available: json['available'] == true,
        hookInstalled: json['hook_installed'] == true,
        contractPath:
            json['contract_path'] is String ? json['contract_path'] as String : '',
        rules: json['rules'] is int ? json['rules'] as int : 0,
        exclusions: json['exclusions'] is int ? json['exclusions'] as int : 0,
        auditEntries:
            json['audit_entries'] is int ? json['audit_entries'] as int : 0,
      );
}

/// The contract's policy lists with the recent audit trail.
class FilingPolicy {
  final List<Map<String, dynamic>> rules;
  final List<Map<String, dynamic>> exclusions;
  final List<Map<String, dynamic>> audit;

  const FilingPolicy({
    required this.rules,
    required this.exclusions,
    required this.audit,
  });

  static FilingPolicy fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(Object? value) => value is List
        ? value
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : const [];
    return FilingPolicy(
      rules: rows(json['rules']),
      exclusions: rows(json['exclusions']),
      audit: rows(json['audit']),
    );
  }
}

/// RPC client over the shared Desktop Gateway transport.
class FilingGatewayClient {
  static const _unknownMethodCode = -32601;

  final GatewayRpcCall _call;
  final CapabilityRegistry? capabilities;
  bool? _supported;

  FilingGatewayClient(this._call, {this.capabilities});

  /// Whether this gateway serves `filing.*` (probed by the first call).
  Future<bool> isSupported() async {
    final known = _supported;
    if (known != null) return known;
    try {
      final filingStatus = await status();
      _supported = filingStatus.available;
      return filingStatus.available;
    } on FilingUnsupportedException {
      return false;
    }
  }

  /// The last known support verdict without contacting the gateway.
  bool? get cachedSupport => _supported;

  Future<FilingStatus> status() async {
    final result = await _request('filing.status', const {});
    return FilingStatus.fromJson(result);
  }

  Future<FilingPolicy> policy() async {
    final result = await _request('filing.rules', const {});
    return FilingPolicy.fromJson(result);
  }

  Future<List<FilingSuggestion>> suggest() async {
    final result = await _request('filing.suggest', const {});
    final rows = result['suggestions'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => FilingSuggestion.fromJson(Map<String, dynamic>.from(e)))
        .whereType<FilingSuggestion>()
        .toList();
  }

  /// Accept a suggestion: records the rule and mirrors it into projects.db.
  Future<String> apply({required String path, required String project}) async {
    final result = await _request('filing.apply', {
      'path': path,
      'project': project,
      'source': 'android:accept',
    });
    final note = result['note'];
    return note is String && note.isNotEmpty ? note : 'applied';
  }

  /// Reject a suggestion: records an exclusion (and unfiles retroactively).
  Future<String> reject({
    required String path,
    String? project,
  }) async {
    final params = <String, dynamic>{
      'path': path,
      'source': 'android:reject',
    };
    if (project != null && project.trim().isNotEmpty) {
      params['project'] = project.trim();
    }
    final result = await _request('filing.reject', params);
    final note = result['note'];
    return note is String && note.isNotEmpty ? note : 'recorded';
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final capabilities = this.capabilities;
    if (capabilities != null && capabilities.isUnsupported(method)) {
      throw FilingUnsupportedException(
        method,
        'This gateway does not support $method',
      );
    }
    final Map<String, dynamic> response;
    try {
      response = await _call(method, params);
    } catch (error) {
      capabilities?.recordFailure(method, error);
      rethrow;
    }
    final error = response['error'];
    if (error != null) {
      final rpcError = error is Map
          ? JsonRpcError.fromGateway(
              method,
              error,
              fallbackMessage: 'Gateway filing call failed',
            )
          : JsonRpcError(method, 'Gateway filing call failed');
      capabilities?.recordFailure(method, rpcError);
      if (_isUnknownMethod(rpcError)) {
        throw FilingUnsupportedException(method, rpcError.message);
      }
      // A real filing error proves the family exists.
      _supported = true;
      throw rpcError;
    }
    _supported = true;
    capabilities?.recordSuccess(method);
    final result = response['result'];
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

  static bool _isUnknownMethod(JsonRpcError error) {
    if (error.code == _unknownMethodCode) return true;
    final message = error.message.toLowerCase();
    return message.contains('unknown method') ||
        message.contains('method not found');
  }
}
