/// The drill-in shape returned by the Gateway `projects.project_sessions` RPC.
///
/// The Hermes gateway already owns the authoritative grouping of chats into
/// project → repo → lane (`tui_gateway/project_tree.py`), including which lane
/// is the trunk and how lanes are ordered. Android reads that grouping instead
/// of deriving its own, so the phone and Hermes Desktop can never disagree
/// about where a chat belongs.
///
/// Parsing rules that matter, all pinned by `test/project_sessions_tree_test.dart`:
///
/// - a repo the server seeded with **no** lanes is kept, because a brand-new
///   project is exactly that and dropping it renders an entered project blank;
/// - a sparse session row is rendered with defaults rather than crashing the
///   whole project view — but a row with no id is dropped, since it can never
///   be opened;
/// - project rows carry a fixed `is_active: false` placeholder (not a
///   liveness signal — see `_project_tree_row` in the gateway's
///   `methods_projects`), so it is ignored and liveness falls back to the
///   recency window;
/// - server order is preserved verbatim. Re-sorting on device would make
///   Android rank the same project differently from Desktop.
library;

import 'session.dart';

/// One branch/worktree lane inside a repo.
class ProjectLane {
  final String id;
  final String label;

  /// Working directory of the lane, when the server reported one.
  final String? path;

  /// Whether this is the repo's trunk lane. The server pins it first.
  final bool isMain;

  /// Whether this lane aggregates kanban-dispatched work.
  final bool isKanban;

  /// Chats in this lane, in the order the server ranked them.
  final List<Session> sessions;

  const ProjectLane({
    required this.id,
    required this.label,
    this.path,
    this.isMain = false,
    this.isKanban = false,
    this.sessions = const [],
  });

  factory ProjectLane.fromJson(Map<String, dynamic> json) {
    final id = _trimmedString(json['id']);
    if (id == null) {
      throw const FormatException('A project lane requires an id');
    }
    return ProjectLane(
      id: id,
      label: _trimmedString(json['label']) ?? id,
      path: _trimmedString(json['path']),
      isMain: json['isMain'] == true,
      isKanban: json['isKanban'] == true,
      sessions: _sessions(json['sessions']),
    );
  }
}

/// One repository inside a project, holding its lanes.
class ProjectRepo {
  final String id;
  final String label;
  final String? path;

  /// Chats the server counted for this repo.
  ///
  /// Falls back to the rows actually present when the server omitted the
  /// count, so a repo never reports zero chats while showing some.
  final int sessionCount;

  final List<ProjectLane> lanes;

  const ProjectRepo({
    required this.id,
    required this.label,
    required this.sessionCount,
    this.path,
    this.lanes = const [],
  });

  factory ProjectRepo.fromJson(Map<String, dynamic> json) {
    final id = _trimmedString(json['id']);
    if (id == null) {
      throw const FormatException('A project repo requires an id');
    }
    final rawLanes = json['groups'];
    final lanes = rawLanes is List
        ? rawLanes
              .whereType<Map>()
              .map(
                (lane) => ProjectLane.fromJson(Map<String, dynamic>.from(lane)),
              )
              .toList(growable: false)
        : const <ProjectLane>[];
    final reported = _asInt(json['sessionCount']);
    return ProjectRepo(
      id: id,
      label: _trimmedString(json['label']) ?? id,
      path: _trimmedString(json['path']),
      sessionCount:
          reported ??
          lanes.fold<int>(0, (total, lane) => total + lane.sessions.length),
      lanes: lanes,
    );
  }
}

/// The hydrated contents of one project: its repos, lanes, and chats.
class ProjectSessionsTree {
  final String id;
  final String label;
  final String? path;
  final String? color;
  final String? icon;

  /// Chats the server counted for this project.
  final int sessionCount;

  /// Most recent activity across the project, in seconds since the epoch.
  final double lastActive;

  final List<ProjectRepo> repos;

  /// The few most recent chats, as ranked by the server.
  final List<Session> previewSessions;

  const ProjectSessionsTree({
    required this.id,
    required this.label,
    this.path,
    this.color,
    this.icon,
    this.sessionCount = 0,
    this.lastActive = 0,
    this.repos = const [],
    this.previewSessions = const [],
  });

  factory ProjectSessionsTree.fromJson(Map<String, dynamic> json) {
    final id = _trimmedString(json['id']);
    if (id == null) {
      throw const FormatException('A project node requires an id');
    }
    final rawRepos = json['repos'];
    return ProjectSessionsTree(
      id: id,
      label: _trimmedString(json['label']) ?? id,
      path: _trimmedString(json['path']),
      color: _trimmedString(json['color']),
      icon: _trimmedString(json['icon']),
      sessionCount: _asInt(json['sessionCount']) ?? 0,
      lastActive: _asDouble(json['lastActive']) ?? 0,
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
    );
  }

  /// Every chat in the project, flattened in server order and de-duplicated.
  ///
  /// A chat can legitimately appear under more than one lane (a worktree and
  /// its trunk, for example); listing it twice would let the user open the
  /// same conversation from two rows that claim to be different work.
  List<Session> get allSessions {
    final seen = <String>{};
    final flattened = <Session>[];
    for (final repo in repos) {
      for (final lane in repo.lanes) {
        for (final session in lane.sessions) {
          if (seen.add(session.id)) flattened.add(session);
        }
      }
    }
    return List.unmodifiable(flattened);
  }

  /// Whether the project holds no chat at all — the designed empty state.
  bool get isEmpty => allSessions.isEmpty;
}

/// Decodes a list of session rows, skipping any row that carries no id.
///
/// An id-less row could never be opened, so rendering it would only produce a
/// dead tap target.
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
