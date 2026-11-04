import 'connection_manager.dart';

/// Where the effective Projects root came from.
enum ProjectsRootSource {
  /// The dashboard reported a `locked_root`. A hosted/container dashboard can
  /// only write inside that root, so it is the Projects root — and it outranks
  /// any local preference, which is why the UI shows it read-only.
  locked,

  /// The user configured a root for this connection and the dashboard is not
  /// locked.
  configured,

  /// Nothing configured: the server's conventional `<home>/Projects`, which is
  /// exactly what the app used before this setting existed.
  serverDefault,

  /// The dashboard could not be read, so no root is known. Callers degrade
  /// (stay folderless, show "unavailable") rather than guess a path.
  unavailable,
}

/// The resolved Projects root plus everything the UI needs to explain it.
class ProjectsRootResolution {
  /// The absolute root to use, or `null` when [source] is
  /// [ProjectsRootSource.unavailable].
  final String? path;
  final ProjectsRootSource source;

  /// The dashboard's `locked_root`, when it reported one.
  final String? lockedRoot;

  /// The conventional `<home>/Projects` for this server, when its browse home
  /// is known. Shown as the placeholder/reset target in the editor.
  final String? serverDefault;

  /// Why the dashboard read failed, when it did.
  final Object? error;

  const ProjectsRootResolution({
    required this.path,
    required this.source,
    this.lockedRoot,
    this.serverDefault,
    this.error,
  });

  bool get isLocked => source == ProjectsRootSource.locked;
}

/// Resolves which server-side directory new Project folders live under.
///
/// The precedence is fixed and deliberate:
///
///  1. the dashboard's `locked_root` (a server lock always wins),
///  2. the per-connection [configuredRoot] the user opted into,
///  3. the server's conventional `<home>/Projects`.
///
/// Only one existing server interface is used: `GET /api/files`, the same
/// managed-files route the folder provisioner already probes with. Its
/// `locked_root` and `path` fields are the only facts consulted.
class ProjectsRootResolver {
  final DashboardClient dashboard;

  /// A validated absolute path, or `null` to keep the server default.
  final String? configuredRoot;

  /// Read the current saved preference for every operation. A retained
  /// workspace must not keep the value captured before the editor was opened.
  final String? Function()? readConfiguredRoot;

  const ProjectsRootResolver({
    required this.dashboard,
    this.configuredRoot,
    this.readConfiguredRoot,
  });

  Future<ProjectsRootResolution> resolve() async {
    final Map<String, dynamic> res;
    try {
      res = await dashboard.apiGet('files');
    } catch (error) {
      // No readable dashboard means no root; the caller degrades instead of
      // inventing one. A configured preference is NOT used here: without the
      // dashboard answer we cannot know whether the server is locked, and a
      // local preference must never outrank a lock we failed to read.
      return ProjectsRootResolution(
        path: null,
        source: ProjectsRootSource.unavailable,
        error: error,
      );
    }
    final locked = res['locked_root'];
    final home = res['path'];
    final serverDefault = home is String && home.trim().isNotEmpty
        ? '${trimTrailingSlash(home.trim())}/Projects'
        : null;
    if (locked is String && locked.trim().isNotEmpty) {
      final lockedRoot = trimTrailingSlash(locked.trim());
      return ProjectsRootResolution(
        path: lockedRoot,
        source: ProjectsRootSource.locked,
        lockedRoot: lockedRoot,
        serverDefault: serverDefault,
      );
    }
    final configured =
        (readConfiguredRoot == null ? configuredRoot : readConfiguredRoot!())
            ?.trim();
    if (configured != null && configured.isNotEmpty) {
      return ProjectsRootResolution(
        path: trimTrailingSlash(configured),
        source: ProjectsRootSource.configured,
        serverDefault: serverDefault,
      );
    }
    if (serverDefault != null) {
      return ProjectsRootResolution(
        path: serverDefault,
        source: ProjectsRootSource.serverDefault,
        serverDefault: serverDefault,
      );
    }
    return const ProjectsRootResolution(
      path: null,
      source: ProjectsRootSource.unavailable,
    );
  }

  /// Drops trailing `/` (and `\`) separators without emptying a bare root.
  static String trimTrailingSlash(String path) {
    var end = path.length;
    while (end > 1 && (path[end - 1] == '/' || path[end - 1] == r'\')) {
      end--;
    }
    return path.substring(0, end);
  }
}
