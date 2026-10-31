/// The overview shape returned by the Gateway `projects.tree` RPC.
///
/// This is the companion tier to `projects.project_sessions`: the drill-in
/// hydrates one project's lanes with every chat row, while the overview
/// describes *all* projects with their structure and counts but with lane rows
/// emptied (`hydrate=False` in `tui_gateway/project_tree.py`). A Projects pane
/// therefore pays for one cheap call on entry and one hydrated call only when
/// the user actually enters a project.
///
/// Two things live here that `projects.list` cannot answer, because that call
/// returns projects-database records and knows nothing about chats:
///
/// - the repo/lane structure and chat counts behind each project card;
/// - [ProjectsTreeOverview.scopedSessionIds], the flat set of chats already
///   claimed by some project. Subtracting it from a flat session list is how
///   Hermes Desktop avoids listing the same chat twice, and Android must use
///   the same server-computed set rather than recomputing membership on device.
///
/// Parsing rules that matter, all pinned by `test/projects_tree_overview_test.dart`:
///
/// - counts come from the server and are never derived from the (empty) lanes,
///   or every card would read zero chats;
/// - one malformed project node is dropped rather than thrown, since taking
///   down the whole pane is a far worse failure than one missing card;
/// - project rows carry a fixed `is_active: false` placeholder (not a
///   liveness signal — see `_project_tree_row` in the gateway's
///   `methods_projects`), so it is ignored and liveness falls back to the
///   recency window;
/// - server order is preserved verbatim across all three tiers (Home, explicit,
///   auto), so Android cannot rank projects differently from Desktop;
/// - an `active_id` naming no listed project is ignored, matching
///   `ProjectsSnapshot`.
library;

import 'project_sessions_tree.dart';
import 'session.dart';

/// One project as the overview describes it: structure and counts, no rows.
///
/// Reuses [ProjectRepo] / [ProjectLane] from the drill-in on purpose. Both
/// tiers are emitted by the same server builder, so a second Android shape
/// could only drift from it.
class ProjectOverviewNode {
  final String id;
  final String label;
  final String? path;
  final String? color;
  final String? icon;

  /// True for a repo Hermes discovered rather than one the user created.
  ///
  /// Auto projects have no projects-database record, so they cannot be
  /// renamed, archived or deleted — offering those actions would only produce
  /// a server error the user cannot act on.
  final bool isAuto;

  /// True for the synthetic `Home` bucket holding every unclaimed chat.
  final bool isNoProject;

  /// Chats the server counted for this project.
  final int sessionCount;

  /// Most recent activity across the project, in seconds since the epoch.
  final double lastActive;

  /// Tokens summed by the server over the same chats [sessionCount] counts.
  final int totalTokens;

  /// Spend summed by the server over the same chats [sessionCount] counts.
  final double totalCostUsd;

  final List<ProjectRepo> repos;

  /// The few most recent chats, as ranked by the server.
  ///
  /// The only place the overview carries real Session rows, so a card that
  /// shows recent activity depends entirely on this list.
  final List<Session> previewSessions;

  /// Every chat id this project claims — not just the preview window.
  ///
  /// The server emits this on every node even when `hydrate=False`
  /// (`sessionIds` in `tui_gateway/project_tree.py::_project_node`), so
  /// placement never depends on whether a chat made the preview cut. This
  /// is the ONLY wire source of per-chat ownership: there is no
  /// top-level placement map on `projects.tree`.
  final List<String> sessionIds;

  const ProjectOverviewNode({
    required this.id,
    required this.label,
    this.path,
    this.color,
    this.icon,
    this.isAuto = false,
    this.isNoProject = false,
    this.sessionCount = 0,
    this.lastActive = 0,
    this.totalTokens = 0,
    this.totalCostUsd = 0,
    this.repos = const [],
    this.previewSessions = const [],
    this.sessionIds = const [],
  });

  factory ProjectOverviewNode.fromJson(Map<String, dynamic> json) {
    final id = _trimmedString(json['id']);
    if (id == null) {
      throw const FormatException('A project overview node requires an id');
    }
    final rawRepos = json['repos'];
    return ProjectOverviewNode(
      id: id,
      label: _trimmedString(json['label']) ?? id,
      path: _trimmedString(json['path']),
      color: _trimmedString(json['color']),
      icon: _trimmedString(json['icon']),
      isAuto: json['isAuto'] == true,
      isNoProject: json['isNoProject'] == true,
      sessionCount: _asInt(json['sessionCount']) ?? 0,
      lastActive: _asDouble(json['lastActive']) ?? 0,
      totalTokens: _asInt(json['totalTokens']) ?? 0,
      totalCostUsd: _asDouble(json['totalCostUsd']) ?? 0,
      repos: rawRepos is List
          ? rawRepos
                .whereType<Map>()
                .map(
                  (repo) =>
                      ProjectRepo.fromJson(Map<String, dynamic>.from(repo)),
                )
                .toList(growable: false)
          : const <ProjectRepo>[],
      previewSessions: _sessions(json['previewSessions']),
      sessionIds: _scopedIds(json['sessionIds']),
    );
  }

  /// Whether this project can be renamed, archived or deleted server-side.
  bool get isUserOwned => !isAuto && !isNoProject;
}

/// The full `projects.tree` payload: every project, the active one, and the
/// chats already claimed by any of them.
class ProjectsTreeOverview {
  final List<ProjectOverviewNode> projects;

  /// The gateway's active project, or `null` when nothing is selected or the
  /// reported id no longer resolves to a listed project.
  final String? activeId;

  /// Ids of chats some project already claims, in server order.
  final List<String> scopedSessionIds;

  /// Full placement map: chat id -> owning project id (`__no_project__` for
  /// the Home bucket), derived from every node's [ProjectOverviewNode
  /// .sessionIds]. Unlike [ProjectOverviewNode.previewSessions] — a top-N
  /// window — this names the owner of EVERY claimed chat, so a row label
  /// never depends on whether the chat made the preview cut.
  late final Map<String, String> sessionProjects = Map.unmodifiable({
    for (final project in projects)
      for (final id in project.sessionIds) id: project.id,
  });

  final Set<String> _scoped;

  ProjectsTreeOverview({
    this.projects = const [],
    this.activeId,
    this.scopedSessionIds = const [],
  }) : _scoped = Set.unmodifiable(scopedSessionIds);

  static final empty = ProjectsTreeOverview();

  factory ProjectsTreeOverview.fromJson(Map<String, dynamic> json) {
    final rawProjects = json['projects'];
    final projects = <ProjectOverviewNode>[];
    if (rawProjects is List) {
      for (final entry in rawProjects.whereType<Map>()) {
        try {
          projects.add(
            ProjectOverviewNode.fromJson(Map<String, dynamic>.from(entry)),
          );
        } on FormatException {
          // A node with no id could only ever be a dead card. Drop it rather
          // than let one bad row blank every other project.
          continue;
        }
      }
    }

    final rawActiveId = _trimmedString(json['active_id']);
    final activeId = projects.any((project) => project.id == rawActiveId)
        ? rawActiveId
        : null;

    return ProjectsTreeOverview(
      projects: List.unmodifiable(projects),
      activeId: activeId,
      scopedSessionIds: _scopedIds(json['scoped_session_ids']),
    );
  }

  /// The label of the project that owns [sessionId], or null when no project
  /// claims it (or the owning node is the Home bucket, which is not a filing).
  String? ownerLabelOf(String sessionId) {
    final ownerId = sessionProjects[sessionId];
    if (ownerId == null || ownerId == noProjectId) return null;
    for (final project in projects) {
      if (project.id == ownerId) return project.label;
    }
    return null;
  }

  /// The Home bucket id the backend's tree uses for unfiled chats.
  static const String noProjectId = '__no_project__';

  /// Projects the user created, so the ones that accept server-side edits.
  List<ProjectOverviewNode> get userProjects =>
      projects.where((project) => project.isUserOwned).toList(growable: false);

  ProjectOverviewNode? get activeProject {
    final id = activeId;
    if (id == null) return null;
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  /// Whether some project already claims [sessionId].
  bool claimsSession(String sessionId) => _scoped.contains(sessionId);

  bool get isEmpty => projects.isEmpty;
}

/// Cleans the claimed-chat ids without reordering them.
///
/// A blank entry would match nothing and a duplicate would hide a chat twice;
/// server order is kept because nothing on device may re-rank it.
List<String> _scopedIds(Object? raw) {
  if (raw is! List) return const [];
  final seen = <String>{};
  final ids = <String>[];
  for (final entry in raw) {
    final id = _trimmedString(entry);
    if (id != null && seen.add(id)) ids.add(id);
  }
  return List.unmodifiable(ids);
}

/// Decodes a list of session rows, skipping any row that carries no id.
List<Session> _sessions(Object? raw) {
  if (raw is! List) return const [];
  final sessions = <Session>[];
  for (final entry in raw.whereType<Map>()) {
    final row = Map<String, dynamic>.from(entry);
    if (_trimmedString(row['id']) == null) continue;
    // `is_active` on project rows is a fixed placeholder, never a liveness
    // signal — ignore it so the recency window decides.
    sessions.add(Session.fromJson(row, ignoreIsActive: true));
  }
  return List.unmodifiable(sessions);
}

String? _trimmedString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}
