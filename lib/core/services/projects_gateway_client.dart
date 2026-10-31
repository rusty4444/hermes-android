import '../models/hermes_project.dart';
import '../models/project_sessions_tree.dart';
import '../models/projects_tree_overview.dart';
import 'capability_registry.dart';
import 'ws_client.dart';

/// Sends one JSON-RPC method call and returns the raw envelope.
///
/// Kept as a function type so the Projects client can sit on top of any
/// transport (the live [WsClient], a recovery socket, or a test double)
/// without owning connection state.
typedef GatewayRpcCall =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

/// Thrown when the connected Hermes Gateway predates the `projects.*` RPC.
///
/// This is a compatibility signal, not a failure: the caller should fall back
/// to local-only organization rather than showing an error.
class ProjectsUnsupportedException implements Exception {
  final String method;
  final String message;

  const ProjectsUnsupportedException(this.method, this.message);

  @override
  String toString() => 'ProjectsUnsupportedException($method): $message';
}

/// Read/write access to the server-owned Hermes Projects.
///
/// Every call goes through the gateway, so Projects created here are the same
/// records Hermes Desktop and the CLI see. Unknown-method errors are converted
/// into [ProjectsUnsupportedException] and remembered, so an old gateway is
/// probed at most once instead of on every screen build.
class ProjectsGatewayClient {
  static const _unknownMethodCode = -32601;

  /// The method whose presence defines the whole `projects.*` family.
  ///
  /// Support is decided by this one call only. A gateway may ship
  /// `projects.list` and predate a newer sibling such as
  /// `projects.project_sessions`; letting that sibling flip the family verdict
  /// would drop the entire Projects pane into local-only compatibility mode,
  /// and the verdict is cached, so nothing would ever re-probe to undo it.
  static const _probeMethod = 'projects.list';

  final GatewayRpcCall _call;

  /// Optional shared registry, so one probe here informs the whole app.
  ///
  /// Public because it is plain collaborator state: callers pass the gateway's
  /// registry in, and reading it back is useful for diagnostics.
  final CapabilityRegistry? capabilities;
  bool? _supported;

  ProjectsGatewayClient(this._call, {this.capabilities});

  /// Whether the gateway exposes `projects.*`.
  ///
  /// Only a definitive answer is cached: transport failures rethrow and leave
  /// the verdict unknown so a later reconnect can still discover support.
  Future<bool> isSupported() async {
    final known = _supported;
    if (known != null) return known;
    try {
      await list();
      return true;
    } on ProjectsUnsupportedException {
      return false;
    }
  }

  /// The last known support verdict without contacting the gateway.
  bool? get cachedSupport => _supported;

  Future<ProjectsSnapshot> list() async {
    final result = await _request('projects.list', const {});
    return ProjectsSnapshot.fromJson(result);
  }

  Future<HermesProject> get(String id) async {
    final result = await _request('projects.get', {'id': _requireId(id)});
    return _requireProject('projects.get', result);
  }

  /// Every project with its repo/lane structure, counts, and preview chats.
  ///
  /// The cheap overview tier: lanes carry no session rows, so entering the
  /// Projects pane costs one call regardless of how many chats exist. The
  /// hydrated rows for a single project come from [projectSessions].
  ///
  /// [previewLimit] and [sessionLimit] are only sent when given, so the
  /// server's own defaults stay authoritative instead of being frozen into
  /// the app by an echoed copy.
  Future<ProjectsTreeOverview> tree({
    int? previewLimit,
    int? sessionLimit,
  }) async {
    final params = <String, dynamic>{};
    if (previewLimit != null) params['preview_limit'] = previewLimit;
    if (sessionLimit != null) params['session_limit'] = sessionLimit;
    final result = await _request('projects.tree', params);
    return ProjectsTreeOverview.fromJson(result);
  }

  /// The hydrated contents of one project: repos, lanes, and their chats.
  ///
  /// Returns `null` when the gateway knows no such project, or when the
  /// profile has no projects database at all. That is an empty result rather
  /// than a failure: the caller shows "no chats yet", never an error screen.
  Future<ProjectSessionsTree?> projectSessions(
    String id, {
    int? sessionLimit,
  }) async {
    final params = <String, dynamic>{'project_id': _requireId(id)};
    if (sessionLimit != null) params['session_limit'] = sessionLimit;
    final result = await _request('projects.project_sessions', params);
    final project = result['project'];
    if (project is! Map) return null;
    return ProjectSessionsTree.fromJson(Map<String, dynamic>.from(project));
  }

  Future<HermesProject> create({
    required String name,
    String? slug,
    String? description,
    String? primaryPath,
    List<String> folders = const [],
    bool use = false,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A project name is required');
    }
    final params = <String, dynamic>{'name': trimmedName};
    if (slug != null && slug.trim().isNotEmpty) params['slug'] = slug.trim();
    if (description != null && description.trim().isNotEmpty) {
      params['description'] = description.trim();
    }
    if (primaryPath != null && primaryPath.trim().isNotEmpty) {
      params['primary_path'] = primaryPath.trim();
    }
    if (folders.isNotEmpty) params['folders'] = folders;
    if (use) params['use'] = true;

    final result = await _request('projects.create', params);
    return _requireProject('projects.create', result);
  }

  Future<HermesProject> rename({
    required String id,
    required String name,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'A project name is required');
    }
    final result = await _request('projects.update', {
      'id': _requireId(id),
      'name': trimmedName,
    });
    return _requireProject('projects.update', result);
  }

  /// Archives a project, or restores it when [restore] is true.
  ///
  /// Archiving is deliberately preferred over deletion in the mobile flows:
  /// it is reversible and never destroys server-side history.
  Future<ProjectsSnapshot> archive(String id, {bool restore = false}) async {
    final params = <String, dynamic>{'id': _requireId(id)};
    if (restore) params['restore'] = true;
    final result = await _request('projects.archive', params);
    return ProjectsSnapshot.fromJson(result);
  }

  /// Adds a folder to an existing project and returns the updated record.
  ///
  /// The gateway normalizes the path and, with [isPrimary], repoints the
  /// project's `primary_path`. An older gateway lacking this sibling raises
  /// [ProjectsUnsupportedException] without disowning the `projects.*`
  /// family (only `projects.list` decides that).
  Future<HermesProject> addFolder({
    required String id,
    required String path,
    String? label,
    bool isPrimary = false,
  }) async {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'A folder path is required');
    }
    final params = <String, dynamic>{
      'id': _requireId(id),
      'path': trimmedPath,
    };
    if (label != null && label.trim().isNotEmpty) params['label'] = label.trim();
    if (isPrimary) params['is_primary'] = true;
    final result = await _request('projects.add_folder', params);
    return _requireProject('projects.add_folder', result);
  }

  Future<ProjectsSnapshot> delete(String id) async {
    final result = await _request('projects.delete', {'id': _requireId(id)});
    return ProjectsSnapshot.fromJson(result);
  }

  /// Re-homes a stored session's workspace to [cwd] via `session.workspace.move`.
  ///
  /// This is how Hermes Desktop moves a chat between Projects: the gateway
  /// derives project membership from the session's cwd (`project_for_path`),
  /// so rewriting the cwd IS the move. Works on every gateway that serves
  /// sessions, including stock ones without any explicit assignment RPC.
  /// [sessionKey] must be the gateway's stored session key, not a local id.
  Future<void> moveSessionWorkspace({
    required String sessionKey,
    required String cwd,
  }) async {
    final key = sessionKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(
        sessionKey,
        'sessionKey',
        'A stored session key is required',
      );
    }
    final folder = cwd.trim();
    if (folder.isEmpty) {
      throw ArgumentError.value(cwd, 'cwd', 'A working directory is required');
    }
    await _request('session.workspace.move', {
      'session_key': key,
      'cwd': folder,
    });
  }

  /// Selects [id] as the gateway's active project, or clears it when null.
  Future<String?> setActive(String? id) async {
    final params = <String, dynamic>{};
    if (id != null && id.trim().isNotEmpty) params['id'] = id.trim();
    final result = await _request('projects.set_active', params);
    final activeId = result['active_id'];
    return activeId is String && activeId.trim().isNotEmpty
        ? activeId.trim()
        : null;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final capabilities = this.capabilities;
    // A gateway already proven to lack this method is not probed again.
    if (capabilities != null && capabilities.isUnsupported(method)) {
      if (method == _probeMethod) _supported = false;
      throw ProjectsUnsupportedException(
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
              fallbackMessage: 'Gateway projects call failed',
            )
          : JsonRpcError(method, 'Gateway projects call failed');
      capabilities?.recordFailure(method, rpcError);
      if (_isUnknownMethod(rpcError)) {
        // Only the probe method can disown the family; a missing sibling
        // leaves the earlier verdict — and the rest of the pane — intact.
        if (method == _probeMethod) _supported = false;
        throw ProjectsUnsupportedException(method, rpcError.message);
      }
      // A real projects error still proves the RPC family exists.
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

  static String _requireId(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(id, 'id', 'A project id is required');
    }
    return trimmed;
  }

  static HermesProject _requireProject(
    String method,
    Map<String, dynamic> result,
  ) {
    final project = result['project'];
    if (project is! Map) {
      throw JsonRpcError(method, 'Gateway returned no project record');
    }
    return HermesProject.fromJson(Map<String, dynamic>.from(project));
  }
}
