/// Offline-aware access to the server-owned Hermes Projects.
///
/// Sits between the UI and [ProjectsGatewayClient]:
///
/// - the gateway stays the source of truth;
/// - the last good listing is cached per connection so the app opens with
///   content instead of a spinner, clearly marked as stale;
/// - mutations apply optimistically and roll back on failure;
/// - an older gateway degrades to a labelled compatibility mode rather than
///   an error screen;
/// - local Spaces can be *previewed* against server Projects without writing
///   anything, which is the safe first half of the migration.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/hermes_project.dart';
import '../models/project_sessions_tree.dart';
import '../models/projects_tree_overview.dart';
import '../models/session.dart';
import 'chat_space_store.dart';
import 'project_folder_provisioner.dart';
import 'projects_gateway_client.dart';

/// Whether this gateway offers the native `projects.*` family.
enum ProjectsSupport {
  /// Not probed yet.
  unknown,

  /// The gateway answers `projects.*`.
  native,

  /// The gateway predates Projects; local grouping remains the only option.
  unsupported,
}

/// An immutable snapshot the UI can render directly.
class ProjectsView {
  final List<HermesProject> projects;
  final List<HermesProject> archived;
  final String? activeId;
  final ProjectsSupport support;

  /// True when these projects came from the cache rather than a live read.
  final bool isStale;

  /// The failure that forced the fallback to cache, if any.
  final Object? error;

  const ProjectsView({
    this.projects = const [],
    this.archived = const [],
    this.activeId,
    this.support = ProjectsSupport.unknown,
    this.isStale = false,
    this.error,
  });

  static const empty = ProjectsView();

  bool get isEmpty => projects.isEmpty && archived.isEmpty;

  HermesProject? get activeProject {
    for (final project in projects) {
      if (project.id == activeId) return project;
    }
    return null;
  }

  ProjectsView copyWith({
    List<HermesProject>? projects,
    List<HermesProject>? archived,
    String? activeId,
    bool clearActiveId = false,
    ProjectsSupport? support,
    bool? isStale,
    Object? error,
    bool clearError = false,
  }) {
    return ProjectsView(
      projects: projects ?? this.projects,
      archived: archived ?? this.archived,
      activeId: clearActiveId ? null : (activeId ?? this.activeId),
      support: support ?? this.support,
      isStale: isStale ?? this.isStale,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// One local Space matched (or not) against the server Projects.
class SpaceMigrationEntry {
  final ChatSpace space;

  /// The server Project this Space maps onto, or null when it must be created.
  final HermesProject? matchedProject;

  /// How many local chats are assigned to this Space.
  final int sessionCount;

  const SpaceMigrationEntry({
    required this.space,
    required this.matchedProject,
    required this.sessionCount,
  });

  bool get needsCreation => matchedProject == null;
}

/// What a completed migration actually did.
class SpaceMigrationResult {
  /// Spaces turned into new server Projects.
  final int createdProjects;

  /// Spaces the server already carried under the same (normalized) name.
  final int alreadyLinked;

  /// Chats now owned by their server Project.
  final int linkedSessions;

  /// Chats whose assignment failed or whose gateway predates the binding RPC.
  final int unlinkedSessions;

  /// Space or `space/session` → the error that stopped it.
  final Map<String, Object> failures;

  const SpaceMigrationResult({
    required this.createdProjects,
    required this.alreadyLinked,
    required this.linkedSessions,
    required this.unlinkedSessions,
    required this.failures,
  });

  /// Complete means every Project exists and every assigned chat moved.
  bool get isComplete => failures.isEmpty && unlinkedSessions == 0;
}

/// A read-only description of what a Spaces migration *would* do.
class SpaceMigrationPlan {
  final List<SpaceMigrationEntry> entries;

  const SpaceMigrationPlan(this.entries);

  bool get isEmpty => entries.isEmpty;

  int get projectsToCreate =>
      entries.where((entry) => entry.needsCreation).length;

  int get sessionsToLink =>
      entries.fold(0, (total, entry) => total + entry.sessionCount);
}

/// One project's chats, as an immutable snapshot the UI can render directly.
///
/// Deliberately separate from [ProjectsView]: opening a project must never be
/// able to disturb the Projects list. A gateway that serves `projects.list`
/// but predates `projects.project_sessions` reports [ProjectsSupport
/// .unsupported] *here* while the pane behind it keeps working.
class ProjectSessionsView {
  final String projectId;

  /// The server's own project → repo → lane grouping, when it answered one.
  final ProjectSessionsTree? tree;

  /// Every chat in the project, flattened in server order.
  final List<Session> sessions;

  final ProjectsSupport support;

  /// True when these chats came from an earlier read that a failure has since
  /// left unrefreshed.
  final bool isStale;

  /// The failure that prevented a live read, if any.
  final Object? error;

  const ProjectSessionsView({
    required this.projectId,
    this.tree,
    this.sessions = const [],
    this.support = ProjectsSupport.unknown,
    this.isStale = false,
    this.error,
  });

  bool get isEmpty => sessions.isEmpty;
}

class _OptimisticProjectsMutation {
  final ProjectsView baseline;
  final String? projectId;
  final bool changesActiveId;

  const _OptimisticProjectsMutation({
    required this.baseline,
    this.projectId,
    this.changesActiveId = false,
  });
}

/// Repository over the gateway Projects family.
class ProjectsRepository {
  final ProjectsGatewayClient client;
  final SharedPreferences preferences;
  final String connectionId;

  /// Optional folder auto-provisioner for name-only creates.
  ///
  /// When set, a Project created without any folder gets a provisioned
  /// directory bound as its primary — the phone cannot pick folders the
  /// way Desktop does, and a folderless Project cannot hold chats on
  /// gateways without direct assignment. The provisioner chooses a fresh,
  /// unguessable candidate and returns it only after verifying its independent
  /// marker is uncontested. This provides practical collision resistance
  /// without treating the host's non-atomic mkdir as proof of creation.
  final ProjectFolderProvisioner? folderProvisioner;

  final _controller = StreamController<ProjectsView>.broadcast();
  ProjectsView _current = ProjectsView.empty;
  int _pendingCreateSequence = 0;
  int _stateRevision = 0;
  int _refreshGeneration = 0;
  bool _closed = false;

  /// Cache writes are serialized across repository instances as well as
  /// within one instance. A workspace disposed during a slow write must not
  /// overwrite a newer repository for the same connection.
  static final Map<String, Future<void>> _cacheWriteTails = {};

  /// Destructive/list-wide mutations are serialized so a later optimistic
  /// operation never captures an earlier operation's unconfirmed state as its
  /// rollback baseline. Creates stay concurrent and reconcile by placeholder.
  Future<void> _mutationTail = Future<void>.value();
  _OptimisticProjectsMutation? _optimisticMutation;

  /// Last good drill-in per project, so re-entering one opens with content.
  final _sessionsCache = <String, ProjectSessionsView>{};

  /// In-flight drill-in reads, so two opens racing each other share one call.
  final _sessionsInFlight = <String, Future<ProjectSessionsView>>{};
  int _sessionPlacementRevision = 0;

  /// Set once the gateway proves it predates `projects.project_sessions`.
  bool _sessionsUnsupported = false;

  ProjectsTreeOverview? _overviewCache;
  int _overviewCacheGeneration = 0;
  int _overviewGeneration = 0;
  bool _overviewUnsupported = false;

  ProjectsRepository({
    required this.client,
    required this.preferences,
    required this.connectionId,
    this.folderProvisioner,
  });

  /// Emits after every state change, including optimistic ones.
  Stream<ProjectsView> get changes => _controller.stream;

  ProjectsView get current => _current;

  String get _cacheKey => 'projects_cache_v1_$connectionId';

  /// Reads the cached listing without touching the network.
  ///
  /// Always marked stale: the app may show it instantly, but must not present
  /// it as confirmed server state.
  Future<ProjectsView> loadCached() async {
    final cached = _readCache();
    _emit(cached);
    return cached;
  }

  /// Refreshes from the gateway, falling back to cache on transport failure.
  Future<ProjectsView> refresh() async {
    final requestStart = _current;
    final requestRevision = _stateRevision;
    final generation = ++_refreshGeneration;
    try {
      final snapshot = await client.list();
      if (_closed ||
          generation != _refreshGeneration ||
          requestRevision != _stateRevision) {
        return _current;
      }
      final view = _reconcileSnapshot(snapshot, requestStart: requestStart);
      _emit(view);
      await _queueCacheWrite(view);
      return view;
    } on ProjectsUnsupportedException {
      if (_closed ||
          generation != _refreshGeneration ||
          requestRevision != _stateRevision) {
        return _current;
      }
      // Not a failure: this gateway simply has no Projects. Keep the surface
      // calm and let the caller offer local grouping instead.
      return _emit(const ProjectsView(support: ProjectsSupport.unsupported));
    } catch (error) {
      if (_closed ||
          generation != _refreshGeneration ||
          requestRevision != _stateRevision) {
        return _current;
      }
      // Disk is only a bootstrap fallback. Once this repository has usable
      // state, replacing it with an older cache can undo a confirmed mutation
      // whose write is still queued behind another repository instance.
      final fallback =
          requestStart.support != ProjectsSupport.unknown ||
              !requestStart.isEmpty ||
              requestStart.activeId != null
          ? requestStart
          : _readCache();
      return _emit(
        fallback.copyWith(
          support: _current.support == ProjectsSupport.unknown
              ? fallback.support
              : _current.support,
          isStale: true,
          error: error,
        ),
      );
    }
  }

  /// Reads the server's cheap all-Project tree used for card counts and Inbox.
  ///
  /// Older gateways may support `projects.list` without this sibling method;
  /// that degrades only the extra metadata, never the Projects list itself.
  /// A successful result, even an empty one, confirms membership. Unsupported,
  /// failed, closed or superseded reads without a newer accepted snapshot
  /// throw instead: unknown membership must never classify every chat as unfiled.
  Future<ProjectsTreeOverview> overview({bool refresh = false}) async {
    if (_closed) throw StateError('Projects repository is closed');
    if (_current.support == ProjectsSupport.unsupported ||
        _overviewUnsupported) {
      throw const ProjectsUnsupportedException(
        'projects.tree',
        'This Hermes gateway does not support project membership metadata',
      );
    }
    final cached = _overviewCache;
    if (!refresh && cached != null) return cached;
    final generation = ++_overviewGeneration;
    final placementRevision = _sessionPlacementRevision;
    try {
      final overview = await client.tree();
      // A later refresh can complete first. Never let an older tree replace
      // the shared counts/placement cache or leak back to a waiting caller.
      if (_closed) throw StateError('Projects repository is closed');
      if (generation != _overviewGeneration) {
        final newer = _newerOverview(generation);
        if (newer != null) return newer;
        if (placementRevision != _sessionPlacementRevision) {
          return this.overview(refresh: true);
        }
        throw StateError('Project membership read was superseded');
      }
      _overviewCache = overview;
      _overviewCacheGeneration = generation;
      return overview;
    } on ProjectsUnsupportedException {
      if (!_closed && generation == _overviewGeneration) {
        _overviewUnsupported = true;
        _overviewCache = null;
      }
      final newer = _newerOverview(generation);
      if (newer != null) return newer;
      rethrow;
    } catch (_) {
      // Stale errors have no more authority than stale successes. Only a
      // snapshot accepted after this request began can replace its result;
      // the older cached tree is not proof of current membership.
      final newer = _newerOverview(generation);
      if (newer != null) return newer;
      rethrow;
    }
  }

  ProjectsTreeOverview? _newerOverview(int generation) =>
      !_closed && _overviewCacheGeneration > generation ? _overviewCache : null;

  Future<HermesProject> create(String name, {bool select = false}) => select
      ? _serializeMutation(() => _create(name, select: true))
      : _create(name, select: false);

  Future<HermesProject> _create(String name, {required bool select}) async {
    _requireSupported();
    final trimmed = name.trim();
    final pendingSequence = _pendingCreateSequence++;
    final placeholder = HermesProject(
      id: 'pending:${DateTime.now().microsecondsSinceEpoch}:$pendingSequence',
      slug: trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '-'),
      name: trimmed,
    );
    _emit(
      _current.copyWith(
        projects: [..._current.projects, placeholder],
        clearError: true,
      ),
    );

    late HermesProject created;
    try {
      created = await client.create(name: trimmed, use: select);
      if (created.folders.isEmpty && folderProvisioner != null) {
        // Name-only create: bind the fresh, unguessable candidate only after
        // the provisioner verifies its independent marker is uncontested.
        // A provisioning or bind failure must not undo the create — the
        // Project exists and stays folderless (honest, and the user can
        // add a folder later); only the auto-home is lost.
        final folder = await folderProvisioner!.provision(created.slug);
        if (folder != null) {
          try {
            created = await client.addFolder(
              id: created.id,
              path: folder,
              label: created.name,
              isPrimary: true,
            );
          } catch (_) {}
        }
      }
    } catch (_) {
      // Remove only this request's placeholder. Rolling back to the snapshot
      // captured at request start would erase sibling creates that completed
      // while this request was in flight.
      _emit(
        _current.copyWith(
          projects: [
            for (final project in _current.projects)
              if (project.id != placeholder.id) project,
          ],
        ),
      );
      rethrow;
    }

    // Reconcile against the latest state, not the snapshot captured when the
    // request started. Another create may have completed while this one was in
    // flight; replacing only our own placeholder preserves that server record
    // and any still-pending siblings. If a refresh already surfaced [created],
    // replace it in place instead of duplicating it.
    final projects = <HermesProject>[];
    var createdAlreadyPresent = false;
    for (final project in _current.projects) {
      if (project.id == placeholder.id) continue;
      if (project.id == created.id) {
        projects.add(created);
        createdAlreadyPresent = true;
      } else {
        projects.add(project);
      }
    }
    if (!createdAlreadyPresent) projects.add(created);

    final view = _current.copyWith(
      projects: projects,
      activeId: select ? created.id : null,
      clearError: true,
    );
    _emit(view);
    await _queueCacheWrite(view);
    return created;
  }

  Future<HermesProject> rename(String id, String name) =>
      _serializeMutation(() => _rename(id, name));

  Future<HermesProject> _rename(String id, String name) async {
    _requireSupported();
    final previous = _current;
    _optimisticMutation = _OptimisticProjectsMutation(
      baseline: previous,
      projectId: id,
    );
    final trimmed = name.trim();
    _emit(
      previous.copyWith(
        projects: _renamed(previous.projects, id, trimmed),
        archived: _renamed(previous.archived, id, trimmed),
      ),
    );

    try {
      final updated = await client.rename(id: id, name: trimmed);
      final latest = _current;
      final view = latest.copyWith(
        projects: _replaced(latest.projects, id, updated),
        archived: _replaced(latest.archived, id, updated),
        clearError: true,
      );
      _emit(view);
      _optimisticMutation = null;
      await _queueCacheWrite(view);
      return updated;
    } catch (_) {
      if (_optimisticMutation == null) rethrow;
      // Roll back only this target if our optimistic name is still visible.
      // A sibling create or a newer mutation must remain untouched.
      final original = _projectIn(previous, id);
      final latest = _current;
      if (original != null && _projectIn(latest, id)?.name == trimmed) {
        _emit(
          latest.copyWith(
            projects: _replaced(latest.projects, id, original),
            archived: _replaced(latest.archived, id, original),
          ),
        );
      }
      final rollback = _current;
      _optimisticMutation = null;
      await _queueCacheWrite(rollback);
      rethrow;
    }
  }

  /// Archives a project (reversible), or restores it when [restore] is true.
  Future<void> archive(String id, {bool restore = false}) =>
      _serializeMutation(() => _archive(id, restore: restore));

  Future<void> _archive(String id, {required bool restore}) async {
    _requireSupported();
    final previous = _current;
    _optimisticMutation = _OptimisticProjectsMutation(
      baseline: previous,
      projectId: id,
    );
    _emit(_locallyArchived(previous, id, restore: restore));

    try {
      final snapshot = await client.archive(id, restore: restore);
      final view = _reconcileSnapshot(
        snapshot,
        requestStart: previous,
        authoritativeIds: {id},
      );
      _emit(view);
      _optimisticMutation = null;
      await _queueCacheWrite(view);
    } catch (_) {
      if (_optimisticMutation == null) rethrow;
      final rollback = _restoreProject(_current, previous, id);
      _emit(rollback);
      _optimisticMutation = null;
      await _queueCacheWrite(rollback);
      rethrow;
    }
  }

  /// Hard-deletes one Project while preserving its conversations.
  ///
  /// The Gateway cascades only Project metadata and assignment rows; chat
  /// sessions remain stored and therefore fall back to Unassigned. The list is
  /// updated optimistically and fully restored if the server rejects the write.
  Future<void> delete(String id) => _serializeMutation(() => _delete(id));

  Future<void> _delete(String id) async {
    _requireSupported();
    final previous = _current;
    _optimisticMutation = _OptimisticProjectsMutation(
      baseline: previous,
      projectId: id,
      changesActiveId: previous.activeId == id,
    );
    final optimistic = previous.copyWith(
      projects: [
        for (final project in previous.projects)
          if (project.id != id) project,
      ],
      archived: [
        for (final project in previous.archived)
          if (project.id != id) project,
      ],
      clearActiveId: previous.activeId == id,
      clearError: true,
    );
    _emit(optimistic);

    try {
      final snapshot = await client.delete(id);
      final view = _reconcileSnapshot(
        snapshot,
        requestStart: previous,
        authoritativeIds: {id},
      );
      _sessionsCache.remove(id);
      _emit(view);
      _optimisticMutation = null;
      await _queueCacheWrite(view);
    } catch (_) {
      if (_optimisticMutation == null) rethrow;
      final rollback = _restoreProject(
        _current,
        previous,
        id,
        restoreActiveId: true,
      );
      _emit(rollback);
      _optimisticMutation = null;
      await _queueCacheWrite(rollback);
      rethrow;
    }
  }

  /// Moves one chat into [projectId] by re-homing its workspace.
  ///
  /// Stock-gateway-only path: the chat's cwd is re-pointed at the target
  /// project's folder via `session.workspace.move` — the one RPC stock
  /// Hermes ships for this, and how the desktop files chats (membership
  /// is derived from cwd). `projects.assign_session` is deliberately
  /// NOT attempted: it never shipped upstream, so trying it first only
  /// adds a doomed round-trip and a capability assumption.
  ///
  /// [storedSessionKey] is the gateway's stored key for the chat (falls
  /// back to [sessionId] when the binding is unknown). Returns a reason
  /// string when the move is impossible (un-file on a cwd-derived model,
  /// or a target Project with no folder to re-home into); throws only on
  /// a real gateway failure so the caller can offer a retry.
  Future<String?> moveSessionToProject(
    String sessionId,
    String? projectId, {
    String? storedSessionKey,
  }) async {
    _requireSupported();
    if (projectId == null) {
      // There is no stock RPC to un-file a chat: its project is wherever
      // its cwd points. Say so instead of failing with a generic error.
      return 'This gateway files chats by working folder and cannot move a '
          'chat back to Unassigned.';
    }
    final target = _findProject(projectId);
    final folder = target?.workingDirectory?.trim() ?? '';
    if (target == null || folder.isEmpty) {
      return 'That Project has no folder to move the chat into. Add a '
          'folder to it first.';
    }
    await client.moveSessionWorkspace(
      sessionKey: (storedSessionKey?.trim().isNotEmpty ?? false)
          ? storedSessionKey!.trim()
          : sessionId,
      cwd: folder,
    );
    // A move changes source and destination, potentially including auto-folder
    // nodes. Fence pending reads as well as clearing the cached trees.
    _sessionPlacementRevision++;
    _sessionsCache.clear();
    _sessionsInFlight.clear();
    _overviewGeneration++;
    _overviewCache = null;
    return null;
  }

  HermesProject? _findProject(String id) {
    for (final project in _current.projects) {
      if (project.id == id) return project;
    }
    for (final project in _current.archived) {
      if (project.id == id) return project;
    }
    return null;
  }

  static HermesProject? _projectIn(ProjectsView view, String id) {
    for (final project in view.projects) {
      if (project.id == id) return project;
    }
    for (final project in view.archived) {
      if (project.id == id) return project;
    }
    return null;
  }

  static List<HermesProject> _replaced(
    List<HermesProject> projects,
    String id,
    HermesProject replacement,
  ) => [
    for (final project in projects)
      if (project.id == id) replacement else project,
  ];

  /// Applies an authoritative server snapshot without erasing state produced
  /// by another mutation that completed while this request was in flight.
  ProjectsView _reconcileSnapshot(
    ProjectsSnapshot snapshot, {
    required ProjectsView requestStart,
    Set<String> authoritativeIds = const {},
  }) {
    final latest = _current;
    final active = List<HermesProject>.from(snapshot.active);
    final archived = List<HermesProject>.from(snapshot.archived);
    final startById = {
      for (final project in [
        ...requestStart.projects,
        ...requestStart.archived,
      ])
        project.id: project,
    };
    final startArchivedIds = {
      for (final project in requestStart.archived) project.id,
    };
    final latestIds = {
      for (final project in [...latest.projects, ...latest.archived])
        project.id,
    };

    void remove(String id) {
      active.removeWhere((project) => project.id == id);
      archived.removeWhere((project) => project.id == id);
    }

    void preserve(HermesProject project, {required bool isArchived}) {
      remove(project.id);
      (isArchived ? archived : active).add(project);
    }

    for (final project in latest.projects) {
      if (authoritativeIds.contains(project.id)) continue;
      final atStart = startById[project.id];
      final changedWhileInFlight =
          atStart != null &&
          (!_sameProject(atStart, project) ||
              startArchivedIds.contains(project.id));
      if (project.id.startsWith('pending:') ||
          atStart == null ||
          changedWhileInFlight) {
        preserve(project, isArchived: false);
      }
    }
    for (final project in latest.archived) {
      if (authoritativeIds.contains(project.id)) continue;
      final atStart = startById[project.id];
      final changedWhileInFlight =
          atStart != null &&
          (!_sameProject(atStart, project) ||
              !startArchivedIds.contains(project.id));
      if (project.id.startsWith('pending:') ||
          atStart == null ||
          changedWhileInFlight) {
        preserve(project, isArchived: true);
      }
    }
    // A refresh can begin after an optimistic mutation has already changed
    // [_current]. In that case requestStart contains the optimistic value too,
    // so the ordinary before/after comparison cannot identify it. Keep the
    // overlay visible until its serialized server write settles.
    final optimistic = _optimisticMutation;
    final optimisticId = optimistic?.projectId;
    if (optimisticId != null && !authoritativeIds.contains(optimisticId)) {
      final project = _projectIn(latest, optimisticId);
      if (project == null) {
        remove(optimisticId);
      } else {
        preserve(
          project,
          isArchived: latest.archived.any((item) => item.id == optimisticId),
        );
      }
    }
    // Preserve a concurrent deletion of any project other than the target
    // owned by this response.
    for (final id in startById.keys) {
      if (!authoritativeIds.contains(id) && !latestIds.contains(id)) remove(id);
    }

    final activeChangedWhileInFlight =
        optimistic?.changesActiveId == true ||
        latest.activeId != requestStart.activeId;
    final activeId = activeChangedWhileInFlight
        ? latest.activeId
        : snapshot.activeId;
    return latest.copyWith(
      projects: active,
      archived: archived,
      activeId: activeId,
      clearActiveId: activeId == null,
      support: ProjectsSupport.native,
      isStale: false,
      clearError: true,
    );
  }

  static ProjectsView _restoreProject(
    ProjectsView latest,
    ProjectsView previous,
    String id, {
    bool restoreActiveId = false,
  }) {
    final projects = [
      for (final project in latest.projects)
        if (project.id != id) project,
    ];
    final archived = [
      for (final project in latest.archived)
        if (project.id != id) project,
    ];
    final previousProjectIndex = previous.projects.indexWhere(
      (project) => project.id == id,
    );
    final previousArchivedIndex = previous.archived.indexWhere(
      (project) => project.id == id,
    );
    if (previousProjectIndex >= 0) {
      projects.insert(
        previousProjectIndex.clamp(0, projects.length),
        previous.projects[previousProjectIndex],
      );
    } else if (previousArchivedIndex >= 0) {
      archived.insert(
        previousArchivedIndex.clamp(0, archived.length),
        previous.archived[previousArchivedIndex],
      );
    }
    final activeId = restoreActiveId ? previous.activeId : latest.activeId;
    return latest.copyWith(
      projects: projects,
      archived: archived,
      activeId: activeId,
      clearActiveId: activeId == null,
    );
  }

  static bool _sameProject(HermesProject left, HermesProject right) =>
      jsonEncode(_projectToJson(left)) == jsonEncode(_projectToJson(right));

  Future<T> _serializeMutation<T>(Future<T> Function() mutation) {
    final next = _mutationTail.then((_) => mutation());
    _mutationTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  ProjectsView _confirmedCacheView(ProjectsView view) {
    final optimistic = _optimisticMutation;
    if (optimistic == null) return view;
    var confirmed = view;
    final projectId = optimistic.projectId;
    if (projectId != null) {
      confirmed = _restoreProject(confirmed, optimistic.baseline, projectId);
    }
    if (optimistic.changesActiveId) {
      confirmed = confirmed.copyWith(
        activeId: optimistic.baseline.activeId,
        clearActiveId: optimistic.baseline.activeId == null,
      );
    }
    return confirmed;
  }

  Future<void> setActive(String? id) =>
      _serializeMutation(() => _setActive(id));

  Future<void> _setActive(String? id) async {
    _requireSupported();
    final previous = _current;
    _optimisticMutation = _OptimisticProjectsMutation(
      baseline: previous,
      changesActiveId: true,
    );
    _emit(previous.copyWith(activeId: id, clearActiveId: id == null));

    try {
      final activeId = await client.setActive(id);
      final view = _current.copyWith(
        activeId: activeId,
        clearActiveId: activeId == null,
        clearError: true,
      );
      _emit(view);
      _optimisticMutation = null;
      await _queueCacheWrite(view);
    } catch (_) {
      if (_optimisticMutation == null) rethrow;
      final latest = _current;
      var rollback = latest;
      if (latest.activeId == id) {
        rollback = latest.copyWith(
          activeId: previous.activeId,
          clearActiveId: previous.activeId == null,
        );
        _emit(rollback);
      }
      _optimisticMutation = null;
      await _queueCacheWrite(rollback);
      rethrow;
    }
  }

  /// Describes how local Spaces map onto server Projects.
  ///
  /// Purely read-only: nothing is created, linked, or deleted. The user sees
  /// this plan before any migration runs, and the local store stays intact
  /// until the server read-back confirms every assignment.
  SpaceMigrationPlan planMigration(ChatSpaceState state) {
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    // Active projects only: matching a Space to an ARCHIVED project would
    // report 'already linked' while landing the chats in a bucket the
    // user cannot see in the active list. An archived name is treated as
    // free — the migration creates/uses the active project instead.
    final byName = <String, HermesProject>{
      for (final project in _current.projects) normalize(project.name): project,
    };

    final counts = <String, int>{};
    for (final spaceId in state.assignments.values) {
      counts[spaceId] = (counts[spaceId] ?? 0) + 1;
    }

    return SpaceMigrationPlan([
      for (final space in state.spaces)
        SpaceMigrationEntry(
          space: space,
          matchedProject: byName[normalize(space.name)],
          sessionCount: counts[space.id] ?? 0,
        ),
    ]);
  }

  /// Executes the plan described by [planMigration].
  ///
  /// Gated behind step 7 of Phase 0 (real Gateway smoke test on a device),
  /// which passed once the preview rendered correctly against a live gateway.
  ///
  /// Three properties this must keep:
  ///
  /// * **Idempotent.** Matching is by normalized name, so a second run creates
  ///   nothing. A user who taps twice must not end up with duplicate projects.
  /// * **Non-destructive.** The local Spaces store is never cleared. It is the
  ///   only record of the user's grouping until the server can hold chat →
  ///   project links, and a partial migration that wiped it would lose data
  ///   that cannot be reconstructed.
  /// * **Honest.** A failure part-way keeps what already succeeded and reports
  ///   the rest in [SpaceMigrationResult.failures] rather than throwing away
  ///   the successful writes or claiming a clean run.
  Future<SpaceMigrationResult> migrateSpaces(ChatSpaceState state) async {
    // A legacy gateway must fail loudly: silently no-opping would let the UI
    // report a migration that never happened.
    _requireSupported();

    final plan = planMigration(state);
    var created = 0;
    var matched = 0;
    var linkedSessions = 0;
    var unlinkedSessions = 0;
    final failures = <String, Object>{};

    for (final entry in plan.entries) {
      HermesProject target;
      if (entry.matchedProject case final existing?) {
        target = existing;
        matched++;
      } else {
        try {
          // `use: false` — migrating is bookkeeping, not navigation. Stealing
          // the active project would move the user somewhere they didn't ask
          // to go.
          target = await create(entry.space.name, select: false);
          created++;
        } catch (error) {
          failures[entry.space.name] = error;
          unlinkedSessions += entry.sessionCount;
          continue;
        }
      }

      final sessionIds = state.assignments.entries
          .where((assignment) => assignment.value == entry.space.id)
          .map((assignment) => assignment.key);
      for (final sessionId in sessionIds) {
        // Stock path: re-home the chat's cwd to the target Project's folder
        // (`session.workspace.move`) — the gateway derives membership from
        // cwd, so the move IS the assignment. No `projects.assign_session`
        // round-trip: that RPC never shipped upstream.
        final folder = target.workingDirectory?.trim() ?? '';
        if (folder.isEmpty) {
          unlinkedSessions++;
          failures['${entry.space.name}/$sessionId'] = StateError(
            'Project ${entry.space.name} has no folder to re-home chats into.',
          );
          continue;
        }
        try {
          await client.moveSessionWorkspace(sessionKey: sessionId, cwd: folder);
          linkedSessions++;
        } catch (error) {
          unlinkedSessions++;
          failures['${entry.space.name}/$sessionId'] = error;
        }
      }
    }

    return SpaceMigrationResult(
      createdProjects: created,
      alreadyLinked: matched,
      linkedSessions: linkedSessions,
      unlinkedSessions: unlinkedSessions,
      failures: failures,
    );
  }

  /// The chats inside one project, as the server groups them.
  ///
  /// Cached per project: re-entering a project shows the previous contents
  /// immediately and costs no request unless [refresh] is set. A failure never
  /// discards chats already read — losing the list because the socket blinked
  /// is worse than showing it behind an offline notice.
  Future<ProjectSessionsView> projectSessions(
    String id, {
    bool refresh = false,
  }) async {
    final cached = _sessionsCache[id];
    if (!refresh && cached != null) return cached;

    // A gateway already proven to lack the family, or the drill-in method
    // itself, is never probed again: the answer cannot change without a
    // reconnect, and every wasted round trip is a slower project screen.
    if (_current.support == ProjectsSupport.unsupported ||
        _sessionsUnsupported) {
      return ProjectSessionsView(
        projectId: id,
        support: ProjectsSupport.unsupported,
        sessions: cached?.sessions ?? const [],
        tree: cached?.tree,
      );
    }

    final inFlight = _sessionsInFlight[id];
    if (inFlight != null) return inFlight;

    final request = _readProjectSessions(id, cached, _sessionPlacementRevision);
    _sessionsInFlight[id] = request;
    try {
      return await request;
    } finally {
      if (identical(_sessionsInFlight[id], request)) {
        _sessionsInFlight.remove(id);
      }
    }
  }

  Future<ProjectSessionsView> _readProjectSessions(
    String id,
    ProjectSessionsView? cached,
    int placementRevision,
  ) async {
    try {
      final tree = await client.projectSessions(id);
      if (!_closed && placementRevision != _sessionPlacementRevision) {
        return projectSessions(id, refresh: true);
      }
      final view = ProjectSessionsView(
        projectId: id,
        tree: tree,
        sessions: _sessionsOf(tree),
        support: ProjectsSupport.native,
      );
      if (!_closed) _sessionsCache[id] = view;
      return view;
    } on ProjectsUnsupportedException {
      if (!_closed && placementRevision != _sessionPlacementRevision) {
        return projectSessions(id, refresh: true);
      }
      // Only this call is missing. The Projects list stays exactly as it is:
      // flipping the whole pane into compatibility mode would hide server
      // projects the gateway serves perfectly well.
      _sessionsUnsupported = true;
      return ProjectSessionsView(
        projectId: id,
        support: ProjectsSupport.unsupported,
        sessions: cached?.sessions ?? const [],
        tree: cached?.tree,
      );
    } catch (error) {
      if (!_closed && placementRevision != _sessionPlacementRevision) {
        return projectSessions(id, refresh: true);
      }
      return ProjectSessionsView(
        projectId: id,
        tree: cached?.tree,
        sessions: cached?.sessions ?? const [],
        support: _current.support,
        isStale: cached != null,
        error: error,
      );
    }
  }

  /// The chats to render for [tree].
  ///
  /// Lane grouping is preferred because it is what the server ranked, but a
  /// project whose chats carry no repo/cwd produces no lanes at all while the
  /// server still lists them in `previewSessions`. Showing "no chats yet" then
  /// would be a lie the user cannot resolve from the phone.
  static List<Session> _sessionsOf(ProjectSessionsTree? tree) {
    if (tree == null) return const [];
    final grouped = tree.allSessions;
    return grouped.isNotEmpty ? grouped : tree.previewSessions;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _refreshGeneration++;
    _stateRevision++;
    final pendingCacheWrite = _cacheWriteTails[_cacheKey];
    if (pendingCacheWrite != null) await pendingCacheWrite;
    await _controller.close();
  }

  void _requireSupported() {
    if (_current.support == ProjectsSupport.unsupported) {
      throw const ProjectsUnsupportedException(
        'projects',
        'This Hermes gateway does not support server-side projects',
      );
    }
  }

  static List<HermesProject> _renamed(
    List<HermesProject> projects,
    String id,
    String name,
  ) {
    return [
      for (final project in projects)
        if (project.id == id)
          HermesProject(
            id: project.id,
            slug: project.slug,
            name: name.trim(),
            description: project.description,
            icon: project.icon,
            color: project.color,
            boardSlug: project.boardSlug,
            primaryPath: project.primaryPath,
            archived: project.archived,
            createdAt: project.createdAt,
            folders: project.folders,
          )
        else
          project,
    ];
  }

  static ProjectsView _locallyArchived(
    ProjectsView view,
    String id, {
    required bool restore,
  }) {
    if (restore) {
      final restored = view.archived.where((p) => p.id == id).toList();
      return view.copyWith(
        projects: [...view.projects, ...restored],
        archived: view.archived.where((p) => p.id != id).toList(),
      );
    }
    final removed = view.projects.where((p) => p.id == id).toList();
    return view.copyWith(
      projects: view.projects.where((p) => p.id != id).toList(),
      archived: [...view.archived, ...removed],
    );
  }

  ProjectsView _emit(ProjectsView view) {
    if (_closed) return _current;
    _current = view;
    _stateRevision++;
    if (!_controller.isClosed) _controller.add(view);
    return view;
  }

  ProjectsView _readCache() {
    final raw = preferences.getString(_cacheKey);
    if (raw == null || raw.isEmpty) {
      return const ProjectsView(isStale: true);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ProjectsView(isStale: true);
      final map = Map<String, dynamic>.from(decoded);
      final snapshot = ProjectsSnapshot.fromJson({
        'projects': map['projects'],
        'active_id': map['active_id'],
      });
      return ProjectsView(
        projects: snapshot.active,
        archived: snapshot.archived,
        activeId: snapshot.activeId,
        support: ProjectsSupport.native,
        isStale: true,
      );
    } catch (_) {
      // A corrupt cache must never block the app; drop it silently.
      return const ProjectsView(isStale: true);
    }
  }

  Future<void> _writeCache(ProjectsView view) async {
    final payload = jsonEncode({
      'projects': [
        for (final project in [...view.projects, ...view.archived])
          if (!project.id.startsWith('pending:')) _projectToJson(project),
      ],
      'active_id': view.activeId,
    });
    await preferences.setString(_cacheKey, payload);
  }

  Future<void> _queueCacheWrite(ProjectsView view) {
    if (_closed) return Future<void>.value();
    // Snapshot the confirmed projection now. By the time an earlier queued
    // write completes, the optimistic operation may already have settled.
    final confirmed = _confirmedCacheView(view);
    final key = _cacheKey;
    final previous = _cacheWriteTails[key] ?? Future<void>.value();
    final write = previous.then((_) => _writeCache(confirmed));
    final tail = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _cacheWriteTails[key] = tail;
    tail.whenComplete(() {
      if (identical(_cacheWriteTails[key], tail)) _cacheWriteTails.remove(key);
    }).ignore();
    return write;
  }

  static Map<String, dynamic> _projectToJson(HermesProject project) => {
    'id': project.id,
    'slug': project.slug,
    'name': project.name,
    'description': project.description,
    'icon': project.icon,
    'color': project.color,
    'board_slug': project.boardSlug,
    'primary_path': project.primaryPath,
    'archived': project.archived,
    'created_at': project.createdAt,
    'folders': [
      for (final folder in project.folders)
        {
          'path': folder.path,
          'label': folder.label,
          'is_primary': folder.isPrimary,
          'added_at': folder.addedAt,
        },
    ],
  };
}
