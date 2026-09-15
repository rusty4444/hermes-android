/// Client for the gateway's `assets.*` server-authoritative asset index RPC.
///
/// Same compatibility discipline as [FilingGatewayClient]: the surface is
/// discovered by calling, never assumed. A gateway without the assets
/// family answers unknown-method and this client reports
/// [AssetsUnsupportedException] — the More-pane entry stays disabled with
/// its reason instead of hiding or erroring.
library;

import 'capability_registry.dart';
import 'projects_gateway_client.dart' show GatewayRpcCall;
import 'ws_client.dart' show JsonRpcError;

/// The gateway has no `assets.*` surface (or it was proven missing).
class AssetsUnsupportedException implements Exception {
  final String method;
  final String message;

  const AssetsUnsupportedException(this.method, this.message);

  @override
  String toString() => 'AssetsUnsupportedException($method): $message';
}

/// One indexed asset: a delivered MEDIA file, a user upload, or a
/// generated artifact.
class HermesAsset {
  final String id;

  /// `artifact` | `attachment` | `media`.
  final String kind;
  final String name;
  final String path;
  final String mimeType;
  final int sizeBytes;
  final double modifiedAt;
  final String sessionId;
  final String sessionTitle;
  final String? projectId;
  final String? projectName;

  const HermesAsset({
    required this.id,
    required this.kind,
    required this.name,
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.sessionId,
    required this.sessionTitle,
    this.projectId,
    this.projectName,
  });

  bool get isImage => mimeType.startsWith('image/');
  bool get isMedia =>
      mimeType.startsWith('video/') || mimeType.startsWith('audio/');

  static HermesAsset? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final path = json['path'];
    if (id is! String || id.isEmpty) return null;
    if (path is! String || path.isEmpty) return null;
    return HermesAsset(
      id: id,
      kind: json['kind'] is String ? json['kind'] as String : 'artifact',
      name: json['name'] is String ? json['name'] as String : '',
      path: path,
      mimeType: json['mime_type'] is String
          ? json['mime_type'] as String
          : 'application/octet-stream',
      sizeBytes: json['size_bytes'] is num ? (json['size_bytes'] as num).toInt() : 0,
      modifiedAt:
          json['modified_at'] is num ? (json['modified_at'] as num).toDouble() : 0,
      sessionId: json['session_id'] is String ? json['session_id'] as String : '',
      sessionTitle:
          json['session_title'] is String ? json['session_title'] as String : '',
      projectId: json['project_id'] is String ? json['project_id'] as String : null,
      projectName:
          json['project_name'] is String ? json['project_name'] as String : null,
    );
  }
}

/// The asset index's answer about this gateway.
class AssetsStatus {
  final bool available;
  final String attachmentsDir;
  final bool attachmentsPresent;

  const AssetsStatus({
    required this.available,
    required this.attachmentsDir,
    required this.attachmentsPresent,
  });

  static AssetsStatus fromJson(Map<String, dynamic> json) => AssetsStatus(
        available: json['available'] == true,
        attachmentsDir:
            json['attachments_dir'] is String ? json['attachments_dir'] as String : '',
        attachmentsPresent: json['attachments_present'] == true,
      );
}

/// RPC client over the shared Desktop Gateway transport.
class AssetsGatewayClient {
  static const _unknownMethodCode = -32601;

  final GatewayRpcCall _call;
  final CapabilityRegistry? capabilities;
  bool? _supported;

  AssetsGatewayClient(this._call, {this.capabilities});

  /// Whether this gateway serves `assets.*` (probed by the first call).
  Future<bool> isSupported() async {
    final known = _supported;
    if (known != null) return known;
    try {
      final assetsStatus = await status();
      _supported = assetsStatus.available;
      return assetsStatus.available;
    } on AssetsUnsupportedException {
      return false;
    }
  }

  /// The last known support verdict without contacting the gateway.
  bool? get cachedSupport => _supported;

  Future<AssetsStatus> status() async {
    final result = await _request('assets.status', const {});
    return AssetsStatus.fromJson(result);
  }

  Future<List<HermesAsset>> list({
    String? kind,
    String? projectId,
    String? sessionId,
  }) async {
    final params = <String, dynamic>{};
    if (kind != null && kind.isNotEmpty) params['kind'] = kind;
    if (projectId != null && projectId.isNotEmpty) params['project_id'] = projectId;
    if (sessionId != null && sessionId.isNotEmpty) params['session_id'] = sessionId;
    final result = await _request('assets.list', params);
    final rows = result['assets'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => HermesAsset.fromJson(Map<String, dynamic>.from(e)))
        .whereType<HermesAsset>()
        .toList();
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final capabilities = this.capabilities;
    if (capabilities != null && capabilities.isUnsupported(method)) {
      throw AssetsUnsupportedException(
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
              fallbackMessage: 'Gateway assets call failed',
            )
          : JsonRpcError(method, 'Gateway assets call failed');
      capabilities?.recordFailure(method, rpcError);
      if (_isUnknownMethod(rpcError)) {
        throw AssetsUnsupportedException(method, rpcError.message);
      }
      // A real assets error proves the family exists.
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
