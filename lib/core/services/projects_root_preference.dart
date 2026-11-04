import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection.dart';

/// Why a typed Projects-root path was refused.
///
/// The app never probes or creates the directory — there is no server
/// interface for "does this path exist and may I write there?" that is
/// cheaper than the provisioner's own probe — so validation is purely
/// syntactic and deliberately conservative.
enum ProjectsRootIssue {
  /// Nothing (or only whitespace) was typed.
  empty,

  /// The path does not start at the POSIX filesystem root. A relative path
  /// would be resolved against whatever cwd the server happens to use, which
  /// is exactly the ambiguity this setting exists to remove.
  notAbsolute,

  /// The path carries `.`/`..` segments or control characters, so the folder
  /// it names depends on resolution rules the app cannot see.
  unsafeSegments,
}

/// Result of validating a user-typed Projects root.
class ProjectsRootValidation {
  /// The normalized absolute path when [issue] is null.
  final String? path;
  final ProjectsRootIssue? issue;

  const ProjectsRootValidation.valid(String this.path) : issue = null;
  const ProjectsRootValidation.invalid(ProjectsRootIssue this.issue)
    : path = null;

  bool get isValid => issue == null;
}

/// Per-connection persistence for the server-side Projects root.
///
/// Stored per saved connection, never globally: one gateway may keep its
/// Projects under `~/.hermes/projects` while another uses `~/Projects`, and a
/// locked (hosted/container) dashboard has no choice at all. A connection with
/// nothing stored reads back `null`, which every caller treats as "keep the
/// server's conventional default" — so upgrading changes no behaviour until
/// the user opts in.
///
/// Corrupt or foreign values are dropped on read rather than repaired: a
/// relative path that somehow reached storage (a hand-edited preferences file,
/// a restored backup from an older build) must not silently become the root
/// that new Project folders are created under.
class ProjectsRootPreference {
  static const _prefix = 'projects_root';

  final SharedPreferences _preferences;

  ProjectsRootPreference(this._preferences);

  static Future<ProjectsRootPreference> open() async =>
      ProjectsRootPreference(await SharedPreferences.getInstance());

  /// The configured root for [connectionIdentity], or `null` when the user has
  /// not set one (or the stored value no longer validates).
  String? read({required String connectionIdentity}) {
    final String? stored;
    try {
      stored = _preferences.getString(_key(connectionIdentity));
    } catch (_) {
      // A preferences backend that cannot answer is indistinguishable from
      // "nothing configured" for this setting, and throwing here would break
      // the Projects pane over an opt-in preference.
      return null;
    }
    if (stored == null) return null;
    final validation = validate(stored);
    return validation.isValid ? validation.path : null;
  }

  /// Stores [path] for [connectionIdentity] after validating it.
  ///
  /// Returns the validation so the caller can show the reason; nothing is
  /// written when the path is rejected.
  Future<ProjectsRootValidation> save({
    required String connectionIdentity,
    required String path,
  }) async {
    final validation = validate(path);
    if (!validation.isValid) return validation;
    await _preferences.setString(_key(connectionIdentity), validation.path!);
    return validation;
  }

  /// Drops the override so [connectionIdentity] falls back to the server's
  /// conventional `<home>/Projects`.
  Future<void> clear({required String connectionIdentity}) async {
    await _preferences.remove(_key(connectionIdentity));
  }

  /// Validates and normalizes a user-typed root path.
  ///
  /// Accepts only absolute POSIX paths: duplicate and trailing slashes are
  /// collapsed, everything else is refused with a reason.
  static ProjectsRootValidation validate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const ProjectsRootValidation.invalid(ProjectsRootIssue.empty);
    }
    if (!trimmed.startsWith('/')) {
      return const ProjectsRootValidation.invalid(
        ProjectsRootIssue.notAbsolute,
      );
    }
    // Control characters (NUL included) and backslashes make the path mean
    // different things to different layers; refuse rather than guess.
    if (RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(trimmed)) {
      return const ProjectsRootValidation.invalid(
        ProjectsRootIssue.unsafeSegments,
      );
    }
    final segments = trimmed
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    for (final segment in segments) {
      if (segment == '.' || segment == '..') {
        return const ProjectsRootValidation.invalid(
          ProjectsRootIssue.unsafeSegments,
        );
      }
    }
    if (segments.isEmpty) {
      // `/` (or `///`) is absolute and canonical, but using the filesystem
      // root as the Projects root would scatter project folders across the
      // whole host. Treat it as unsafe rather than accept it.
      return const ProjectsRootValidation.invalid(
        ProjectsRootIssue.unsafeSegments,
      );
    }
    return ProjectsRootValidation.valid('/${segments.join('/')}');
  }

  /// The storage identity for [connection].
  ///
  /// Saved connections are independent even when they target the same host
  /// (for example different gateway profiles).
  static String identityOf(SavedConnection connection) => connection.id;

  /// Namespaces keys by connection so identical hosts across profiles cannot
  /// collide, without writing gateway URLs into preference key names.
  static String _key(String connectionIdentity) =>
      '$_prefix.${Uri.encodeComponent(connectionIdentity)}.path';
}
