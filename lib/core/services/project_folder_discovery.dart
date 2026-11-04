import '../models/hermes_project.dart';
import 'connection_manager.dart';
import 'projects_root_resolver.dart';
import 'remote_files_client.dart';

/// Lists one server directory.
///
/// Narrowed to a function so discovery sits on top of the existing
/// [RemoteFilesClient.listDirectory] (`GET /api/fs/list`) without owning that
/// client's lifecycle — closing a [RemoteFilesClient] closes its dashboard,
/// and the dashboard here is shared with the live gateway.
typedef RemoteDirectoryLister =
    Future<List<RemoteFileEntry>> Function(String path);

/// Whether the connection could be asked for candidate folders at all.
enum ProjectFolderDiscoveryStatus {
  /// The root was resolved and the directory listed.
  ready,

  /// This connection cannot enumerate server folders: no readable dashboard,
  /// no `fs/list` route, or no permission. The UI must say so instead of
  /// showing an empty list, and falls back to typing a path by hand.
  unsupported,

  /// The listing call reached the server and failed for another reason.
  failed,
}

/// One directory under the Projects root, and whether Hermes already knows it.
class DiscoveredProjectFolder {
  final String name;
  final String path;

  /// True when some Project in `projects.list` already claims this path.
  final bool registered;

  /// The Project that claims [path], when [registered].
  final String? registeredProjectName;

  const DiscoveredProjectFolder({
    required this.name,
    required this.path,
    this.registered = false,
    this.registeredProjectName,
  });
}

/// The outcome of one discovery pass.
class ProjectFolderDiscoveryResult {
  final ProjectFolderDiscoveryStatus status;

  /// The root that was (or would have been) listed.
  final String? root;
  final ProjectsRootSource rootSource;

  /// Every directory found under [root], registered ones included, so the UI
  /// can show what is already claimed rather than silently hiding it.
  final List<DiscoveredProjectFolder> folders;
  final Object? error;

  const ProjectFolderDiscoveryResult({
    required this.status,
    this.root,
    this.rootSource = ProjectsRootSource.unavailable,
    this.folders = const [],
    this.error,
  });

  /// Folders no Project claims yet — the adoption candidates.
  List<DiscoveredProjectFolder> get unregistered =>
      folders.where((folder) => !folder.registered).toList(growable: false);
}

/// Finds server-side Project folders that `projects.list` does not know about.
///
/// This is the other half of issue #232: Hermes Projects are *records*, so a
/// directory created by the TUI (or by hand) under a different root never
/// appears in `projects.list` and therefore never appears in the app.
abstract class ProjectFolderDiscovery {
  const ProjectFolderDiscovery();

  /// Lists the effective Projects root and marks every entry already claimed
  /// by one of [registered].
  ///
  /// Never throws for a server that cannot answer: the refusal is reported as
  /// [ProjectFolderDiscoveryStatus.unsupported] or
  /// [ProjectFolderDiscoveryStatus.failed] so the UI can say which it is.
  Future<ProjectFolderDiscoveryResult> scan({
    required Iterable<HermesProject> registered,
  });
}

/// Discovery over the dashboard's managed-files routes.
///
/// Nothing scans a filesystem on the device; the only interfaces used are the
/// dashboard's existing `GET /api/fs/list` route, reached through
/// [RemoteFilesClient.listDirectory], plus `GET /api/files` for the root.
class DashboardProjectFolderDiscovery extends ProjectFolderDiscovery {
  final RemoteDirectoryLister listDirectory;
  final ProjectsRootResolver roots;

  const DashboardProjectFolderDiscovery({
    required this.listDirectory,
    required this.roots,
  });

  @override
  Future<ProjectFolderDiscoveryResult> scan({
    required Iterable<HermesProject> registered,
  }) async {
    final resolution = await roots.resolve();
    final root = resolution.path;
    if (root == null) {
      // No readable dashboard: honest "not supported on this connection"
      // rather than an empty candidate list.
      return ProjectFolderDiscoveryResult(
        status: ProjectFolderDiscoveryStatus.unsupported,
        rootSource: resolution.source,
        error: resolution.error,
      );
    }

    final claimed = <String>{};
    final claimedBy = <String, String>{};
    for (final project in registered) {
      for (final folder in project.folders) {
        final key = _normalize(folder.path);
        if (key == null) continue;
        claimed.add(key);
        claimedBy.putIfAbsent(key, () => project.name);
      }
      final primary = _normalize(project.primaryPath);
      if (primary != null) {
        claimed.add(primary);
        claimedBy.putIfAbsent(primary, () => project.name);
      }
    }

    final List<RemoteFileEntry> entries;
    try {
      entries = await listDirectory(root);
    } on DashboardHttpException catch (error) {
      // 404 here is the route, not the path: the stock `fs/list` answers 200
      // with an `error` field for an unreadable path, so an HTTP 404 means the
      // dashboard has no such route. 401/403 means we may not ask.
      final unsupported = const {
        401,
        403,
        404,
        405,
        501,
      }.contains(error.statusCode);
      return ProjectFolderDiscoveryResult(
        status: unsupported
            ? ProjectFolderDiscoveryStatus.unsupported
            : ProjectFolderDiscoveryStatus.failed,
        root: root,
        rootSource: resolution.source,
        error: error,
      );
    } catch (error) {
      return ProjectFolderDiscoveryResult(
        status: ProjectFolderDiscoveryStatus.failed,
        root: root,
        rootSource: resolution.source,
        error: error,
      );
    }

    final folders = <DiscoveredProjectFolder>[];
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      if (entry.name.isEmpty || entry.name.startsWith('.')) continue;
      final path = entry.path.trim().isEmpty
          ? '$root/${entry.name}'
          : entry.path.trim();
      final key = _normalize(path);
      final isClaimed = key != null && claimed.contains(key);
      folders.add(
        DiscoveredProjectFolder(
          name: entry.name,
          path: ProjectsRootResolver.trimTrailingSlash(path),
          registered: isClaimed,
          registeredProjectName: isClaimed ? claimedBy[key] : null,
        ),
      );
    }
    folders.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return ProjectFolderDiscoveryResult(
      status: ProjectFolderDiscoveryStatus.ready,
      root: root,
      rootSource: resolution.source,
      folders: folders,
    );
  }

  /// Compares paths without trailing-slash or case noise on the folder name.
  /// Deliberately not a symlink-aware comparison: the app cannot resolve
  /// server-side links, so two paths that name the same directory by different
  /// routes are treated as different, and the worst case is offering a folder
  /// that is already a Project under another path.
  static String? _normalize(String? path) {
    if (path == null) return null;
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    return ProjectsRootResolver.trimTrailingSlash(trimmed);
  }
}
