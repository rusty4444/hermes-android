/// Client for the gateway's `organization.*` RPC: batch pin/archive with undo.
///
/// Same discovery discipline as [FilingGatewayClient]: the surface is proven
/// by calling, and an unknown-method gateway degrades the feature instead of
/// erroring. Every batch the server applies is recorded server-side with the
/// previous state of each session, so [undo] can reverse a whole batch even
/// after the app restarted.
library;

import 'capability_registry.dart';
import 'projects_gateway_client.dart' show GatewayRpcCall;
import 'ws_client.dart' show JsonRpcError;

/// The gateway has no `organization.*` surface (or it was proven missing).
class OrganizationUnsupportedException implements Exception {
  final String method;
  final String message;

  const OrganizationUnsupportedException(this.method, this.message);

  @override
  String toString() =>
      'OrganizationUnsupportedException($method): $message';
}

/// Outcome of one batch mutation.
class OrganizationBatchResult {
  final String batchId;
  final List<String> applied;
  final List<Map<String, dynamic>> failed;

  const OrganizationBatchResult({
    required this.batchId,
    required this.applied,
    required this.failed,
  });

  bool get partial => failed.isNotEmpty;

  static OrganizationBatchResult fromJson(Map<String, dynamic> json) {
    final rows = json['failed'];
    return OrganizationBatchResult(
      batchId: json['batch_id'] is String ? json['batch_id'] as String : '',
      applied: json['applied'] is List
          ? (json['applied'] as List).whereType<String>().toList()
          : const [],
      failed: rows is List
          ? rows
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [],
    );
  }
}

/// One recorded batch in the undo history.
class OrganizationBatchEntry {
  final String id;
  final double ts;
  final String action; // "pinned" | "archived"
  final int value;
  final int count;
  final bool undone;

  const OrganizationBatchEntry({
    required this.id,
    required this.ts,
    required this.action,
    required this.value,
    required this.count,
    required this.undone,
  });

  String get label => switch (action) {
        'pinned' => value == 1 ? 'Pinned' : 'Unpinned',
        'archived' => value == 1 ? 'Archived' : 'Restored',
        _ => action,
      };

  static OrganizationBatchEntry? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return OrganizationBatchEntry(
      id: id,
      ts: json['ts'] is num ? (json['ts'] as num).toDouble() : 0,
      action: json['action'] is String ? json['action'] as String : '',
      value: json['value'] is int ? json['value'] as int : 0,
      count: json['count'] is int ? json['count'] as int : 0,
      undone: json['undone'] == true,
    );
  }
}

/// RPC client over the shared Desktop Gateway transport.
class OrganizationGatewayClient {
  static const _unknownMethodCode = -32601;

  final GatewayRpcCall _call;
  final CapabilityRegistry? capabilities;
  bool? _supported;

  OrganizationGatewayClient(this._call, {this.capabilities});

  /// Whether this gateway serves `organization.*` (probed by the first call).
  Future<bool> isSupported() async {
    final known = _supported;
    if (known != null) return known;
    try {
      await history();
      return true;
    } on OrganizationUnsupportedException {
      return false;
    }
  }

  /// The last known support verdict without contacting the gateway.
  bool? get cachedSupport => _supported;

  Future<OrganizationBatchResult> pin(
    List<String> sessionIds, {
    required bool pinned,
  }) async {
    final result = await _request('organization.pin', {
      'session_ids': sessionIds,
      'pinned': pinned,
    });
    return OrganizationBatchResult.fromJson(result);
  }

  Future<OrganizationBatchResult> archive(
    List<String> sessionIds, {
    required bool archived,
  }) async {
    final result = await _request('organization.archive', {
      'session_ids': sessionIds,
      'archived': archived,
    });
    return OrganizationBatchResult.fromJson(result);
  }

  Future<List<OrganizationBatchEntry>> history() async {
    final result = await _request('organization.history', const {});
    final rows = result['batches'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) =>
            OrganizationBatchEntry.fromJson(Map<String, dynamic>.from(e)))
        .whereType<OrganizationBatchEntry>()
        .toList();
  }

  /// Reverse one batch by id, or the newest not-yet-undone when null.
  Future<OrganizationBatchResult> undo({String? batchId}) async {
    final params = <String, dynamic>{};
    if (batchId != null && batchId.trim().isNotEmpty) {
      params['batch_id'] = batchId.trim();
    }
    final result = await _request('organization.undo', params);
    return OrganizationBatchResult.fromJson(result);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final capabilities = this.capabilities;
    if (capabilities != null && capabilities.isUnsupported(method)) {
      throw OrganizationUnsupportedException(
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
              fallbackMessage: 'Gateway organization call failed',
            )
          : JsonRpcError(method, 'Gateway organization call failed');
      capabilities?.recordFailure(method, rpcError);
      if (_isUnknownMethod(rpcError)) {
        throw OrganizationUnsupportedException(method, rpcError.message);
      }
      // A real organization error proves the family exists.
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
