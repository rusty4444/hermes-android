import 'dart:async';

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/local_chat_pin_store.dart';
import '../services/session_archive_ledger.dart';
import '../theme/hermes_theme.dart';
import '../utils/relative_time.dart';
import '../utils/session_sources.dart';
import '../widgets/chat_attention_section.dart';
import '../widgets/hermes_components.dart';
import '../widgets/hermes_shell.dart';
import '../widgets/session_name_dialog.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

export '../utils/session_sources.dart';

const kWorkspaceSessionSearchKey = Key('workspace-session-search');

enum WorkspaceSessionView { all, unassigned, archivedQuick, search }

/// Source separation applies before search, pins, date groups, and filters.
enum WorkspaceSessionKind {
  chats,
  crons;

  bool includes(Session session) => switch (this) {
    WorkspaceSessionKind.chats => !isMachineSession(session),
    WorkspaceSessionKind.crons => isCronSession(session),
  };
}

/// The chip filters the Chats browser offers (decision #4 of the final UI
/// spec): every conversation, recent activity, unassigned, and archived.
enum WorkspaceChatsFilter {
  all,
  recent,
  unassigned,
  archived;

  String label(AppLocalizations l10n) {
    return switch (this) {
      WorkspaceChatsFilter.all => l10n.filter_all,
      WorkspaceChatsFilter.recent => l10n.filter_recent,
      WorkspaceChatsFilter.unassigned => l10n.unassigned,
      WorkspaceChatsFilter.archived => l10n.archived,
    };
  }
}

/// How recently a conversation was last active, for date group headers.
enum ChatDateBucket {
  today,
  yesterday,
  thisWeek,
  earlier;

  String label(AppLocalizations l10n) {
    return switch (this) {
      ChatDateBucket.today => l10n.date_today,
      ChatDateBucket.yesterday => l10n.date_yesterday,
      ChatDateBucket.thisWeek => l10n.this_week,
      ChatDateBucket.earlier => l10n.date_earlier,
    };
  }
}

/// How long "Recent" means in the Chats browser.
const Duration kRecentChatsWindow = Duration(days: 7);

/// Assigns a conversation to its date bucket, by calendar day.
ChatDateBucket chatDateBucket(DateTime now, double lastActiveSeconds) {
  final activity = DateTime.fromMillisecondsSinceEpoch(
    (lastActiveSeconds * 1000).round(),
  );
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(activity.year, activity.month, activity.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return ChatDateBucket.today;
  if (diff == 1) return ChatDateBucket.yesterday;
  if (diff < 7) return ChatDateBucket.thisWeek;
  return ChatDateBucket.earlier;
}

/// Filters and sorts the Chats browser list for one chip filter.
///
/// Sorting is always by most recent activity, so a conversation moving up in
/// the list is the honest signal that it changed. [now] is injectable so the
/// "Recent" window and date buckets are deterministic in tests.
List<Session> filterChats({
  required List<Session> sessions,
  required WorkspaceChatsFilter filter,
  WorkspaceSessionKind kind = WorkspaceSessionKind.chats,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
  DateTime? now,
  bool projectsKnown = true,
}) {
  final current = now ?? DateTime.now();
  final normalized = query.trim().toLowerCase();
  final recentCutoff =
      current.subtract(kRecentChatsWindow).millisecondsSinceEpoch / 1000.0;

  final filtered = [
    for (final session in sessions)
      if (!session.isUntitledCronShell &&
          kind.includes(session) &&
          switch (filter) {
            WorkspaceChatsFilter.all => !session.archived,
            WorkspaceChatsFilter.recent =>
              !session.archived && session.lastActive >= recentCutoff,
            WorkspaceChatsFilter.unassigned =>
              // When the claim map is unknown (projects.tree timed out),
              // every chat would pass as 'unassigned' — a lie that turns
              // the whole archive into filing noise. Show none instead;
              // the UI surfaces the read failure.
              projectsKnown &&
                  !session.archived &&
                  !claimedSessionIds.contains(session.id),
            WorkspaceChatsFilter.archived =>
              session.archived || archivedQuickChatIds.contains(session.id),
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
  return filtered;
}

/// Groups conversations into date buckets, newest bucket first.
List<MapEntry<ChatDateBucket, List<Session>>> groupChatsByDate(
  DateTime now,
  List<Session> sessions,
) {
  final buckets = <ChatDateBucket, List<Session>>{
    for (final bucket in ChatDateBucket.values) bucket: <Session>[],
  };
  for (final session in sessions) {
    buckets[chatDateBucket(now, session.lastActive)]!.add(session);
  }
  return [
    for (final bucket in ChatDateBucket.values)
      if (buckets[bucket]!.isNotEmpty)
        MapEntry(bucket, List.unmodifiable(buckets[bucket]!)),
  ];
}

class WorkspaceSessionsData {
  final List<Session> sessions;

  /// False while the active-history read is pending or failed.
  final bool sessionsKnown;

  /// A provisional list while a complete scan or additive metadata loads.
  final bool isPartial;
  final bool archivedIsPartial;
  final bool projectsLoading;
  final Object? sessionsError;
  final Object? archiveError;
  final Set<String> claimedSessionIds;
  final Set<String> archivedQuickChatIds;

  /// Server-archived sessions, fetched from the dashboard's
  /// `archived=only` router. The gateway chat transport never returns
  /// archived rows, so without this the Archived chip only ever showed
  /// quick-chat expiries. May contain only the pages read before a failure;
  /// [archivesKnown] distinguishes that from a confirmed complete archive.
  final List<Session> archivedSessions;

  /// False while the archive read is pending, or when it failed. An empty
  /// archive is not authoritative until this is true.
  final bool archivesKnown;

  /// Best-effort session id → project label mapping.
  ///
  /// Built from the server `projects.tree` preview rows; a conversation whose
  /// project is unknown stays honest as "Unassigned" in the UI.
  final Map<String, String> projectLabels;

  /// Whether the claim map above actually reflects the server. False when
  /// `projects.tree` timed out or failed: an empty `claimedSessionIds` then
  /// means "unknown", not "nothing is filed", and the Unassigned chip must
  /// say so instead of presenting the whole archive as unfiled noise.
  final bool projectsKnown;

  const WorkspaceSessionsData({
    this.sessions = const [],
    bool? sessionsKnown,
    this.isPartial = false,
    this.archivedIsPartial = false,
    this.projectsLoading = false,
    this.sessionsError,
    this.archiveError,
    this.claimedSessionIds = const {},
    this.archivedQuickChatIds = const {},
    this.archivedSessions = const [],
    bool? archivesKnown,
    this.projectLabels = const {},
    this.projectsKnown = true,
  }) : sessionsKnown = sessionsKnown ?? (!isPartial && sessionsError == null),
       archivesKnown =
           archivesKnown ?? (!archivedIsPartial && archiveError == null);

  WorkspaceSessionsData withArchives({
    required List<Session> rows,
    bool loading = false,
    Object? error,
  }) => WorkspaceSessionsData(
    sessions: sessions,
    sessionsKnown: sessionsKnown,
    archivesKnown: !loading && error == null,
    isPartial: isPartial,
    sessionsError: sessionsError,
    archivedSessions: rows,
    archivedIsPartial: loading,
    archiveError: error,
    claimedSessionIds: claimedSessionIds,
    archivedQuickChatIds: archivedQuickChatIds,
    projectLabels: projectLabels,
    projectsKnown: projectsKnown,
    projectsLoading: projectsLoading,
  );

  /// Active refresh also owns Project/Quick metadata, but never server archives.
  WorkspaceSessionsData withActive(WorkspaceSessionsData active) =>
      WorkspaceSessionsData(
        sessions: active.sessions,
        sessionsKnown: active.sessionsKnown,
        archivesKnown: archivesKnown,
        isPartial: active.isPartial,
        sessionsError: active.sessionsError,
        archivedSessions: archivedSessions,
        archivedIsPartial: archivedIsPartial,
        archiveError: archiveError,
        claimedSessionIds: active.claimedSessionIds,
        archivedQuickChatIds: active.archivedQuickChatIds,
        projectLabels: active.projectLabels,
        projectsKnown: active.projectsKnown,
        projectsLoading: active.projectsLoading,
      );

  WorkspaceSessionsData copyWith({
    List<Session>? sessions,
    List<Session>? archivedSessions,
    Set<String>? claimedSessionIds,
    Set<String>? archivedQuickChatIds,
    Map<String, String>? projectLabels,
  }) => WorkspaceSessionsData(
    sessions: sessions ?? this.sessions,
    sessionsKnown: sessionsKnown,
    archivesKnown: archivesKnown,
    archivedSessions: archivedSessions ?? this.archivedSessions,
    claimedSessionIds: claimedSessionIds ?? this.claimedSessionIds,
    archivedQuickChatIds: archivedQuickChatIds ?? this.archivedQuickChatIds,
    projectLabels: projectLabels ?? this.projectLabels,
    isPartial: isPartial,
    archivedIsPartial: archivedIsPartial,
    projectsLoading: projectsLoading,
    sessionsError: sessionsError,
    archiveError: archiveError,
    projectsKnown: projectsKnown,
  );
}

/// Reconcile only mutations newer than a snapshot's physical request epoch.
WorkspaceSessionsData applySessionArchiveChanges(
  WorkspaceSessionsData data,
  SessionArchiveLedger ledger,
  int observedRevision, {
  int? archivedObservedRevision,
}) {
  final archiveRevision = archivedObservedRevision ?? observedRevision;
  // Each complete authority replaces itself; the sibling's carried rows keep
  // their own mutation epoch, not the aggregate request's earlier authority.
  final active = ledger
      .apply(data.sessions, observedRevision)
      .where((row) => !row.archived)
      .toList();
  final archived = ledger
      .apply(data.archivedSessions, archiveRevision)
      .where((row) => row.archived)
      .toList();
  void reconcile(List<Session> target, int revision, bool archiveTarget) {
    for (final change in ledger.changesSince(revision)) {
      final row = ledger
          .apply(
            [...data.sessions, ...data.archivedSessions],
            revision,
            includeMissing: true,
          )
          .firstWhere(
            (row) => ledger.sameConversation(row, change.session),
            orElse: () => change.session,
          )
          .withArchived(change.archived);
      target.removeWhere((old) => ledger.sameConversation(old, row));
      if (change.archived == archiveTarget) target.add(row);
    }
  }

  reconcile(active, observedRevision, false);
  reconcile(archived, archiveRevision, true);
  final restored = <String>{
    for (final change in ledger.changesSince(observedRevision))
      if (!change.archived) ...[
        change.session.id,
        ?change.session.lineageRootId,
      ],
  };
  return WorkspaceSessionsData(
    sessions: active,
    archivedSessions: archived,
    sessionsKnown: data.sessionsKnown,
    archivesKnown: data.archivesKnown,
    isPartial: data.isPartial,
    claimedSessionIds: data.claimedSessionIds,
    archivedQuickChatIds: data.archivedQuickChatIds.difference(restored),
    projectLabels: data.projectLabels,
    projectsKnown: data.projectsKnown,
    archivedIsPartial: data.archivedIsPartial,
    projectsLoading: data.projectsLoading,
    sessionsError: data.sessionsError,
    archiveError: data.archiveError,
  );
}

typedef WorkspaceSessionArchiver =
    Future<bool> Function(Session session, bool archived);

typedef WorkspaceSessionsLoader = Future<WorkspaceSessionsData> Function();
typedef WorkspaceArchivesLoader =
    Future<List<Session>> Function(
      void Function(List<Session> rows) onProgress,
    );
typedef WorkspaceSessionsProgressiveLoader =
    Future<WorkspaceSessionsData> Function(
      void Function(WorkspaceSessionsData data) onProgress,
    );

/// Emits cumulative provisional snapshots and returns the final snapshot.
/// The screen ignores emissions after this future settles or it is disposed.
typedef WorkspaceProgressiveSessionsLoader =
    Future<WorkspaceSessionsData> Function(
      void Function(WorkspaceSessionsData) onProgress,
    );

/// Saves a title remotely and returns the authoritative saved title.
/// Failures throw without changing the visible conversation.
typedef WorkspaceSessionRenamer =
    Future<String> Function(Session session, String title);

/// Moves a session and returns the destination Project label. Returning the
/// label lets the row update ownership and presentation in one state change,
/// without waiting for a second projects.tree request.
typedef WorkspaceSessionPromoter = Future<String> Function(Session session);

class QuickChatPromotionCancelled implements Exception {
  const QuickChatPromotionCancelled();
}

List<Session> filterWorkspaceSessions({
  required List<Session> sessions,
  required WorkspaceSessionView view,
  WorkspaceSessionKind kind = WorkspaceSessionKind.chats,
  Set<String> claimedSessionIds = const {},
  Set<String> archivedQuickChatIds = const {},
  String query = '',
  bool projectsKnown = true,
}) {
  final normalized = query.trim().toLowerCase();
  return [
    for (final session in sessions)
      if (!session.isUntitledCronShell &&
          kind.includes(session) &&
          switch (view) {
            // Same contract as filterChats' unassigned chip: an unknown
            // claim map (projects.tree timed out) must not render every
            // chat as unfiled, and machine-source runs (cron/kanban/
            // oneshot) carry no human filing intent — they live in the
            // Cron screen's run drill-down, never in the Unassigned
            // bucket.
            WorkspaceSessionView.unassigned =>
              projectsKnown &&
                  !session.archived &&
                  !claimedSessionIds.contains(session.id),
            WorkspaceSessionView.archivedQuick => archivedQuickChatIds.contains(
              session.id,
            ),
            // Machine sessions stay out of every human-facing list, the
            // archived view included — an archived cron run is still
            // cron noise. Quick-chat archives are human rows and stay.
            WorkspaceSessionView.all ||
            WorkspaceSessionView.search => !session.archived,
          } &&
          (normalized.isEmpty ||
              session.title.toLowerCase().contains(normalized) ||
              session.preview.toLowerCase().contains(normalized) ||
              session.id.toLowerCase().contains(normalized) ||
              session.model.toLowerCase().contains(normalized)))
        session,
  ];
}

class WorkspaceSessionsScreen extends StatefulWidget {
  final String title;
  final WorkspaceSessionView view;
  final WorkspaceSessionKind kind;
  final WorkspaceSessionsLoader load;
  final WorkspaceSessionsProgressiveLoader? loadProgressively;

  /// Refreshes active history and its metadata independently of server archives.
  final WorkspaceSessionsProgressiveLoader? reloadActive;

  /// Retries the archive authority without waiting for unrelated active scans.
  final WorkspaceArchivesLoader? reloadArchives;
  final WorkspaceSessionsData? initialData;
  final ValueChanged<Session> onOpenSession;
  final WorkspaceSessionPromoter? onPromote;
  final WorkspaceSessionRenamer? onRename;
  final WorkspaceSessionArchiver? onArchive;
  final LocalChatPinStore? pinStore;
  final bool embedded;
  final Map<String, String> attention;
  final Set<String> running;
  final VoidCallback? onOpenActivity;

  /// Clock injection for deterministic filter/date tests. When null the
  /// screen uses `DateTime.now()`.
  final DateTime? now;

  /// Periodic silent refresh for the running/idle chips. Null (the default,
  /// used by tests that drive loads explicitly) disables the timer; the
  /// production surfaces pass a modest interval.
  final Duration? refreshInterval;

  const WorkspaceSessionsScreen({
    required this.title,
    required this.view,
    this.kind = WorkspaceSessionKind.chats,
    required this.load,
    this.loadProgressively,
    this.reloadActive,
    this.reloadArchives,
    this.initialData,
    required this.onOpenSession,
    this.onPromote,
    this.onRename,
    this.onArchive,
    this.pinStore,
    this.embedded = false,
    this.attention = const {},
    this.running = const {},
    this.onOpenActivity,
    this.now,
    this.refreshInterval,
    super.key,
  });

  @override
  WorkspaceSessionsScreenState createState() => WorkspaceSessionsScreenState();
}

class WorkspaceSessionsScreenState extends State<WorkspaceSessionsScreen>
    with WidgetsBindingObserver {
  WorkspaceSessionsData? _data;
  bool _activeFullyLoaded = false;
  bool _archivesFullyLoaded = false;
  Object? _error;
  String _query = '';
  final Set<String> _promoting = {};
  int _projectRevision = 0;
  final _movedProjects = <String, ({int revision, String label})>{};
  final Set<String> _renameDialogs = {};
  final Set<String> _renaming = {};
  final Set<String> _archiving = {};
  final _archiveChanges = SessionArchiveLedger();

  /// Only reads started before a successful rename need their title patched.
  /// Keep the rest of each response, including unrelated rows and metadata.
  int _titleRevision = 0;
  int _activeTitleRevision = 0;
  int _archiveTitleRevision = 0;
  int _activeProjectRevision = 0;
  int _activeArchiveRevision = 0;
  int _archivedArchiveRevision = 0;
  final _savedTitles = <String, ({int revision, String title})>{};
  final Set<String> _pinChanges = {};
  List<String> _pinnedIds = const [];

  /// Periodic silent refresh so running/idle chips stay honest while the
  /// list is actually visible (not behind a pushed chat, another shell tab,
  /// or a backgrounded app).
  Timer? _refreshTimer;
  bool _visible = true;

  /// Ticks share the current read; explicit refreshes queue one fresh read
  /// after it so a return from chat cannot lose a rename behind an old load.
  Future<void>? _loadInFlight;
  Future<void>? _queuedRefresh;
  int _loadGeneration = 0;
  bool _hasLoaderData = false;
  WorkspaceSessionsData? _retainedData;
  Future<void>? _activeReadInFlight;
  Future<void>? _queuedActiveRefresh;
  int _activeReadRevision = 0;
  Future<void>? _archiveReadInFlight;
  Future<void>? _queuedArchiveRefresh;
  int _archiveReadRevision = 0;

  /// The active chip filter in the embedded Chats browser.
  WorkspaceChatsFilter _filter = WorkspaceChatsFilter.all;

  /// Injectable clock for deterministic tests.
  DateTime get _now => widget.now ?? DateTime.now();

  /// Whether the current surface is an Unassigned one (standalone view or
  /// the embedded chip browser with the Unassigned chip active).
  bool get _isUnassignedSurface =>
      widget.view == WorkspaceSessionView.unassigned ||
      (widget.embedded && _filter == WorkspaceChatsFilter.unassigned);

  bool get _isArchivedSurface =>
      widget.view == WorkspaceSessionView.archivedQuick ||
      (widget.embedded && _filter == WorkspaceChatsFilter.archived);

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    _activeFullyLoaded = _data != null && !_data!.isPartial;
    _archivesFullyLoaded = _data != null && !_data!.archivedIsPartial;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPins());
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant WorkspaceSessionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The default Chats pane can mount before the root hydrates preferences.
    if (oldWidget.pinStore != widget.pinStore) {
      _pinnedIds = const [];
      unawaited(_refreshPins());
    }
    // Home can deliver its first five (or more human rows from the first
    // background page) after Chats has already mounted. Never replace a
    // completed metadata read with provisional data from a parent rebuild.
    if (!_hasLoaderData &&
        (_data == null || _data!.isPartial) &&
        widget.initialData != null &&
        !identical(oldWidget.initialData, widget.initialData)) {
      _data = _withProjectMoves(
        _withSessionTitles(widget.initialData!, {
          for (final entry in _savedTitles.entries)
            entry.key: entry.value.title,
        }),
        {
          for (final entry in _movedProjects.entries)
            entry.key: entry.value.label,
        },
      );
      if (!_data!.isPartial) _activeFullyLoaded = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRefreshTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncRefreshTimer();
  }

  /// True when this pane is on screen: the route is current (no chat pushed
  /// over it), the shell tab is selected, and the app is foregrounded.
  bool _computeVisible() {
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (!HermesPaneVisibility.of(context)) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  /// Starts the periodic refresh only while visible: hidden panes must not
  /// hit the gateway, and the pull-to-refresh keeps working regardless.
  void _syncRefreshTimer() {
    final visible = _computeVisible();
    if (visible == _visible && _refreshTimer != null) return;
    final becameVisible = visible && !_visible;
    _visible = visible;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    if (becameVisible) unawaited(_refreshPins());
    final interval = widget.refreshInterval;
    if (interval == null || !visible) return;
    _refreshTimer = Timer.periodic(interval, (_) {
      if (_visible) unawaited(_load());
    });
  }

  Future<void> _refreshPins() async {
    final store = widget.pinStore;
    if (store == null) return;
    try {
      final pins = await store.load();
      if (mounted && identical(store, widget.pinStore)) {
        setState(() => _pinnedIds = pins);
      }
    } catch (_) {
      // A failed pin read must not hide conversations on a visible pane.
    }
  }

  @override
  void dispose() {
    ++_loadGeneration;
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Completes after a read started at or after this refresh request.
  Future<void> refresh() {
    if (!mounted) return Future<void>.value();
    if (widget.embedded &&
        _filter == WorkspaceChatsFilter.archived &&
        widget.reloadArchives != null) {
      final pending = _archiveReadInFlight;
      if (pending == null) return _loadArchives();
      return _queuedArchiveRefresh ??= pending.then<void>((_) {
        _queuedArchiveRefresh = null;
        return _loadArchives();
      });
    }
    if (widget.reloadActive != null) return _refreshActive();
    final pending = _loadInFlight;
    if (pending == null) return _load();
    return _queuedRefresh ??= pending.then<void>((_) {
      _queuedRefresh = null;
      return _load();
    });
  }

  Future<void> _refreshActive() {
    // Batch requests before physical start; a later gesture owns a trailing read.
    return _queuedActiveRefresh ??=
        (_activeReadInFlight ?? Future<void>.value()).then<void>((_) {
          _queuedActiveRefresh = null;
          return _loadActive();
        });
  }

  bool _requiresQuickHistory(WorkspaceSessionsData data) {
    if (data.sessionsKnown) return false;
    final resolved = <String>{
      for (final row in [...data.sessions, ...data.archivedSessions]) ...[
        row.id,
        ?row.lineageRootId,
      ],
    };
    return data.archivedQuickChatIds.difference(resolved).isNotEmpty;
  }

  Future<void> _retryScope() {
    final data = _data;
    if (_isArchivedSurface &&
        data != null &&
        data.archivesKnown &&
        data.archiveError == null &&
        _requiresQuickHistory(data) &&
        widget.reloadActive != null) {
      // Server archives are already complete: only active history can resolve
      // the expired device-local identities behind this failure notice.
      return _refreshActive();
    }
    return refresh();
  }

  Future<void> _load() {
    if (!mounted) return Future<void>.value();
    // Passive ticks must not compete with a selected authority's refresh.
    final scoped = _activeReadInFlight ?? _archiveReadInFlight;
    if (scoped != null) return scoped;
    return _loadInFlight ??= _loadOnce().whenComplete(() {
      _loadInFlight = null;
    });
  }

  Future<void> _loadActive() {
    if (!mounted) return Future<void>.value();
    return _activeReadInFlight ??= _loadActiveOnce().whenComplete(() {
      _activeReadInFlight = null;
    });
  }

  Future<void> _loadActiveOnce() async {
    final revision = ++_activeReadRevision;
    final titleRevision = _titleRevision;
    final projectRevision = _projectRevision;
    final mutationRevision = _archiveChanges.revision;
    var acceptingProgress = true;
    void apply(WorkspaceSessionsData data) {
      if (!mounted || revision != _activeReadRevision) return;
      _applyData(
        (_data ?? const WorkspaceSessionsData()).withActive(data),
        titleRevision: titleRevision,
        archiveTitleRevision: _archiveTitleRevision,
        archiveRevision: mutationRevision,
        archivedArchiveRevision: _archivedArchiveRevision,
        projectRevision: projectRevision,
      );
    }

    final previous = _data ?? const WorkspaceSessionsData();
    apply(
      WorkspaceSessionsData(
        sessions: previous.sessions,
        isPartial: true,
        claimedSessionIds: previous.claimedSessionIds,
        archivedQuickChatIds: previous.archivedQuickChatIds,
        projectLabels: previous.projectLabels,
        projectsKnown: previous.projectsKnown,
        projectsLoading: previous.projectsLoading,
      ),
    );
    try {
      final data = await widget.reloadActive!((data) {
        if (acceptingProgress) apply(data);
      });
      acceptingProgress = false;
      apply(data);
      await _refreshPins();
    } catch (error) {
      acceptingProgress = false;
      final current = _data ?? previous;
      apply(
        WorkspaceSessionsData(
          sessions: current.sessions,
          sessionsError: error,
          claimedSessionIds: current.claimedSessionIds,
          archivedQuickChatIds: current.archivedQuickChatIds,
          projectLabels: current.projectLabels,
          projectsKnown: current.projectsKnown,
          projectsLoading: current.projectsLoading,
        ),
      );
    }
  }

  Future<void> _loadArchives() =>
      _archiveReadInFlight ??= _loadArchivesOnce().whenComplete(() {
        _archiveReadInFlight = null;
      });

  Future<void> _loadArchivesOnce() async {
    if (!mounted || _data == null) return;
    final revision = ++_archiveReadRevision;
    final mutationRevision = _archiveChanges.revision;
    final titleRevision = _titleRevision;
    var acceptingProgress = true;
    void apply(List<Session> rows, {bool loading = false, Object? error}) {
      if (!mounted || revision != _archiveReadRevision) return;
      final previous = _data!;
      final seen = rows.map((row) => row.id).toSet();
      final retained = loading || error != null
          ? [
              ...rows,
              ...previous.archivedSessions.where(
                (row) => !seen.contains(row.id),
              ),
            ]
          : rows;
      setState(() {
        final incoming = applySessionArchiveChanges(
          previous.withArchives(rows: retained, loading: loading, error: error),
          _archiveChanges,
          _activeArchiveRevision,
          archivedObservedRevision: mutationRevision,
        );
        _data = _withReadTitles(
          incoming,
          activeRevision: _activeTitleRevision,
          archiveRevision: titleRevision,
        );
        _archiveTitleRevision = _titleRevision;
        _archivedArchiveRevision = _archiveChanges.revision;
        _error = null;
        if (!loading && error == null) _archivesFullyLoaded = true;
      });
    }

    apply(_data!.archivedSessions, loading: true);
    try {
      final rows = await widget.reloadArchives!((rows) {
        if (acceptingProgress) apply(rows, loading: true);
      });
      acceptingProgress = false;
      apply(rows);
    } catch (error) {
      acceptingProgress = false;
      apply(const [], error: error);
    }
  }

  Future<void> _loadOnce() async {
    final generation = ++_loadGeneration;
    final titleRevision = _titleRevision;
    final projectRevision = _projectRevision;
    final activeRevision = _activeReadRevision;
    final archiveRevision = _archiveReadRevision;
    final mutationRevision = _archiveChanges.revision;
    var acceptingProgress = true;
    void apply(WorkspaceSessionsData data) {
      if (!mounted || generation != _loadGeneration) return;
      // An older aggregate load cannot undo a newer archive-only retry.
      if (archiveRevision != _archiveReadRevision && _data != null) {
        data = data.withArchives(
          rows: _data!.archivedSessions,
          loading: _data!.archivedIsPartial,
          error: _data!.archiveError,
        );
      }
      if (activeRevision != _activeReadRevision && _data != null) {
        data = data.withActive(_data!);
      }
      _applyData(
        data,
        titleRevision: activeRevision != _activeReadRevision
            ? _activeTitleRevision
            : titleRevision,
        archiveTitleRevision: archiveRevision != _archiveReadRevision
            ? _archiveTitleRevision
            : titleRevision,
        archiveRevision: activeRevision != _activeReadRevision
            ? _activeArchiveRevision
            : mutationRevision,
        archivedArchiveRevision: archiveRevision != _archiveReadRevision
            ? _archivedArchiveRevision
            : mutationRevision,
        projectRevision: activeRevision != _activeReadRevision
            ? _activeProjectRevision
            : projectRevision,
      );
    }

    try {
      final progressive = widget.loadProgressively;
      final data = await (progressive == null
          ? widget.load()
          : progressive((data) {
              if (acceptingProgress) apply(data);
            }));
      acceptingProgress = false;
      if (!mounted) return;
      apply(data);
      await _refreshPins();
    } catch (error) {
      acceptingProgress = false;
      debugPrint('[workspace-sessions] load failed: $error');
      if (mounted &&
          activeRevision == _activeReadRevision &&
          archiveRevision == _archiveReadRevision) {
        setState(() => _error = error);
      }
    }
  }

  void _applyData(
    WorkspaceSessionsData data, {
    required int titleRevision,
    int? archiveTitleRevision,
    required int archiveRevision,
    int? archivedArchiveRevision,
    required int projectRevision,
  }) {
    if (!mounted) return;
    _hasLoaderData = true;
    data = applySessionArchiveChanges(
      data,
      _archiveChanges,
      archiveRevision,
      archivedObservedRevision: archivedArchiveRevision,
    );
    if (!data.isPartial && data.sessionsError == null) {
      _activeFullyLoaded = true;
    }
    if (!data.archivedIsPartial && data.archiveError == null) {
      _archivesFullyLoaded = true;
    }
    // A partial refresh must not erase already visible older/blocked work.
    // A completed authority replaces only its own collection.
    final previous = _data;
    List<Session> retained(List<Session> old, List<Session> fresh) {
      final freshIds = fresh.map((row) => row.id).toSet();
      return [...fresh, ...old.where((row) => !freshIds.contains(row.id))];
    }

    if (previous != null) {
      data = data.copyWith(
        sessions:
            !data.sessionsKnown || data.isPartial || data.sessionsError != null
            ? retained(previous.sessions, data.sessions)
            : data.sessions,
        archivedSessions:
            !data.archivesKnown ||
                data.archivedIsPartial ||
                data.archiveError != null
            ? retained(previous.archivedSessions, data.archivedSessions)
            : data.archivedSessions,
      );
    }
    setState(() {
      _data = _withProjectMoves(
        _withReadTitles(
          data,
          activeRevision: titleRevision,
          archiveRevision: archiveTitleRevision ?? titleRevision,
        ),
        {
          for (final entry in _movedProjects.entries)
            if (entry.value.revision > projectRevision)
              entry.key: entry.value.label,
        },
      );
      _activeTitleRevision = _titleRevision;
      _archiveTitleRevision = _titleRevision;
      _activeProjectRevision = _projectRevision;
      _activeArchiveRevision = _archiveChanges.revision;
      _archivedArchiveRevision = _archiveChanges.revision;
      if (data.projectsKnown && !data.projectsLoading && data.sessionsKnown) {
        _retainedData = _data;
      }
      _error = null;
    });
  }

  WorkspaceSessionsData _withReadTitles(
    WorkspaceSessionsData data, {
    required int activeRevision,
    required int archiveRevision,
  }) {
    List<Session> patch(List<Session> rows, int revision) => [
      for (final row in rows)
        if (_savedTitles[row.id] case final saved?
            when saved.revision > revision)
          row.withTitle(saved.title)
        else
          row,
    ];
    return data.copyWith(
      sessions: patch(data.sessions, activeRevision),
      archivedSessions: patch(data.archivedSessions, archiveRevision),
    );
  }

  void reconcileTitle(Session session, String title) {
    if (!mounted) return;
    setState(() {
      _savedTitles[session.id] = (revision: ++_titleRevision, title: title);
      if (_data case final data?) {
        _data = _withSessionTitles(data, {session.id: title});
      }
    });
  }

  WorkspaceSessionsData _withSessionTitles(
    WorkspaceSessionsData data,
    Map<String, String> titles,
  ) {
    if (titles.isEmpty) return data;
    Session renamed(Session session) {
      final title = titles[session.id];
      return title == null ? session : session.withTitle(title);
    }

    return data.copyWith(
      sessions: data.sessions.map(renamed).toList(),
      archivedSessions: data.archivedSessions.map(renamed).toList(),
    );
  }

  Session? _currentSession(String id) {
    final data = _data;
    if (data == null) return null;
    // Match the browser's union: the archived copy wins if both are present.
    for (final session in [...data.archivedSessions, ...data.sessions]) {
      if (session.id == id) return session;
    }
    return null;
  }

  Future<void> _rename(Session session) async {
    final rename = widget.onRename;
    if (rename == null ||
        _archiving.contains(session.id) ||
        _promoting.contains(session.id) ||
        !_renameDialogs.add(session.id)) {
      return;
    }
    try {
      // PopupMenuButton reports its selection before the popup route has
      // finished teardown. Do not autofocus a dialog during that transition.
      await Future<void>.delayed(kThemeAnimationDuration);
      if (!mounted) return;
      final current = _currentSession(session.id);
      if (current == null) return;
      final result = await showSessionNameDialog(
        context: context,
        title: context.l10n.rename_chat,
        initialValue: current.title,
        actionLabel: context.l10n.rename,
      );
      if (!mounted) return;
      final title = result?.trim();
      final latest = _currentSession(session.id);
      if (title == null ||
          title.isEmpty ||
          latest == null ||
          title == latest.title) {
        return;
      }
      setState(() => _renaming.add(session.id));
      final savedTitle = await rename(latest, title);
      if (!mounted) return;
      setState(() {
        _savedTitles[session.id] = (
          revision: ++_titleRevision,
          title: savedTitle,
        );
        final data = _data;
        if (data != null) {
          _data = _withSessionTitles(data, {session.id: savedTitle});
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.could_not_rename_chat(error.toString())),
        ),
      );
    } finally {
      _renameDialogs.remove(session.id);
      if (mounted) setState(() => _renaming.remove(session.id));
    }
  }

  /// Patch only the metadata owned by successful moves, never session rows.
  /// Old responses still contribute new chats, previews, titles and pins.
  WorkspaceSessionsData _withProjectMoves(
    WorkspaceSessionsData data,
    Map<String, String> moves,
  ) {
    if (moves.isEmpty) return data;
    return data.copyWith(
      claimedSessionIds: {...data.claimedSessionIds, ...moves.keys},
      archivedQuickChatIds: data.archivedQuickChatIds.difference(
        moves.keys.toSet(),
      ),
      projectLabels: {...data.projectLabels, ...moves},
    );
  }

  Future<void> _promote(Session session, {bool fromMenu = false}) async {
    final promote = widget.onPromote;
    if (promote == null ||
        !mounted ||
        _archiving.contains(session.id) ||
        _renameDialogs.contains(session.id) ||
        _promoting.contains(session.id)) {
      return;
    }
    setState(() => _promoting.add(session.id));
    try {
      // Own the flight before popup teardown, including the destination picker.
      if (fromMenu) await Future<void>.delayed(kThemeAnimationDuration);
      if (!mounted) return;
      final current = _currentSession(session.id);
      if (current == null) return;
      final projectLabel = await promote(current);
      if (!mounted) return;
      setState(() {
        _movedProjects[session.id] = (
          revision: ++_projectRevision,
          label: projectLabel,
        );
        final data = _data;
        if (data != null) {
          _data = _withProjectMoves(data, {session.id: projectLabel});
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.moved_to(projectLabel))),
      );
    } catch (error) {
      if (!mounted || error is QuickChatPromotionCancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          persist: false,
          content: Text('${context.l10n.couldn_t_move_conversation}: $error'),
          action: SnackBarAction(
            label: context.l10n.retry,
            onPressed: () => unawaited(_promote(session)),
          ),
        ),
      );
    } finally {
      _promoting.remove(session.id);
      if (mounted) setState(() {});
    }
  }

  void reconcileArchive(Session session, bool archived) {
    if (!mounted) return;
    final before = _archiveChanges.revision;
    _archiveChanges.record(session, archived);
    setState(() {
      if (_data case final data?) {
        _data = applySessionArchiveChanges(data, _archiveChanges, before);
      }
      if (_retainedData case final data?) {
        _retainedData = applySessionArchiveChanges(
          data,
          _archiveChanges,
          before,
        );
      }
    });
  }

  Future<void> _setArchived(Session session, bool archived) async {
    final archive = widget.onArchive;
    if (archive == null ||
        !mounted ||
        _renameDialogs.contains(session.id) ||
        _promoting.contains(session.id) ||
        !_archiving.add(session.id)) {
      return;
    }
    setState(() {});
    try {
      await Future<void>.delayed(kThemeAnimationDuration);
      if (!mounted) return;
      final current = _currentSession(session.id);
      if (current == null) return;
      final confirmed = await archive(current, archived);
      if (confirmed != archived) {
        throw StateError('Archive state was not confirmed');
      }
      if (!mounted) return;
      setState(() {
        final previousRevision = _archiveChanges.revision;
        _archiveChanges.record(current, archived);
        if (_data case final data?) {
          _data = applySessionArchiveChanges(
            data,
            _archiveChanges,
            previousRevision,
          );
        }
        if (_retainedData case final retained?) {
          _retainedData = applySessionArchiveChanges(
            retained,
            _archiveChanges,
            previousRevision,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            archived
                ? context.l10n.chat_archived
                : context.l10n.chat_unarchived,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          persist: false,
          content: Text(context.l10n.could_not_update_chat_archive(error)),
          action: SnackBarAction(
            label: context.l10n.retry,
            onPressed: () => unawaited(_setArchived(session, archived)),
          ),
        ),
      );
    } finally {
      _archiving.remove(session.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _togglePin(Session session) async {
    final store = widget.pinStore;
    if (store == null || !_pinChanges.add(session.id)) return;
    try {
      final pinnedId = localPinIdForSession(session, _pinnedIds);
      final pins = await store.setPinned(
        pinnedId ?? session.id,
        pinned: pinnedId == null,
      );
      if (mounted) setState(() => _pinnedIds = pins);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.could_not_save_chat_pin)),
      );
    } finally {
      _pinChanges.remove(session.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final body = data == null
        ? _error == null
              ? const Padding(
                  padding: EdgeInsets.only(top: HermesSpacing.lg),
                  child: LoadingSkeleton(rows: 5),
                )
              : ErrorState(
                  title: context.l10n.could_not_load_conversations,
                  message: context.l10n.check_the_connection_and_try_again,
                  onRetry: _load,
                )
        : _buildLoaded(data);
    if (widget.embedded) {
      return Material(color: Colors.transparent, child: body);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: body,
    );
  }

  Widget _buildLoaded(WorkspaceSessionsData data) {
    final archiveScope = _isArchivedSurface;
    final unresolvedQuick = archiveScope && _requiresQuickHistory(data);
    final scopeLoading = archiveScope
        ? data.archivedIsPartial ||
              (widget.view == WorkspaceSessionView.archivedQuick &&
                  data.isPartial) ||
              (unresolvedQuick && data.isPartial)
        : data.isPartial || (_isUnassignedSurface && data.projectsLoading);
    final scopeError =
        _error ??
        (archiveScope ? data.archiveError : data.sessionsError) ??
        (archiveScope && !data.archivesKnown && !data.archivedIsPartial
            ? StateError('Archived history unavailable')
            : null) ??
        (unresolvedQuick && !data.isPartial
            ? data.sessionsError ?? StateError('Quick Chat history unavailable')
            : null) ??
        (_isUnassignedSurface && !data.projectsKnown && !data.projectsLoading
            ? StateError('Project ownership unavailable')
            : null);
    // The embedded browser filters over the union of the gateway's active
    // list and the dashboard's archived list: the Archived chip needs the
    // archived rows, and every other chip explicitly excludes
    // `session.archived`, so the union cannot leak them into All/Recent/
    // Unassigned. The two lists come from different backends at
    // different instants, so dedupe by id — the archived copy wins for
    // a session archived between the two fetches.
    final unionSessions = _archiveChanges.apply([
      ...data.sessions,
      ...data.archivedSessions,
    ], _archiveChanges.revision);
    final retainedClaims = _retainedData;
    final reuseClaims =
        _isUnassignedSurface &&
        !data.projectsKnown &&
        (retainedClaims?.projectsKnown ?? false);
    final retainedIds = reuseClaims
        ? retainedClaims!.sessions.map((session) => session.id).toSet()
        : const <String>{};
    List<Session> classified(List<Session> rows) => reuseClaims
        ? rows.where((s) => retainedIds.contains(s.id)).toList()
        : rows;
    final filteredSessions = widget.embedded
        ? filterChats(
            sessions: classified(unionSessions),
            filter: _filter,
            kind: widget.kind,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
            now: _now,
            projectsKnown: data.projectsKnown || reuseClaims,
          )
        : filterWorkspaceSessions(
            sessions: classified(unionSessions),
            view: widget.view,
            kind: widget.kind,
            claimedSessionIds: data.claimedSessionIds,
            archivedQuickChatIds: data.archivedQuickChatIds,
            query: _query,
            projectsKnown: data.projectsKnown || reuseClaims,
          );

    final previouslyLoaded =
        archiveScope && widget.view != WorkspaceSessionView.archivedQuick
        ? _archivesFullyLoaded
        : _activeFullyLoaded;
    final sessions = scopeLoading && !previouslyLoaded
        ? filteredSessions.take(5).toList()
        : filteredSessions;
    final ordered = orderLocalPinnedChats(sessions, _pinnedIds);
    final pinnedSessions = ordered
        .where((session) => localPinIdForSession(session, _pinnedIds) != null)
        .toList();
    final unpinnedSessions = ordered
        .where((session) => localPinIdForSession(session, _pinnedIds) == null)
        .toList();
    final groups = widget.embedded
        ? groupChatsByDate(_now, unpinnedSessions)
        : [
            MapEntry(
              ChatDateBucket.today,
              List<Session>.unmodifiable(unpinnedSessions),
            ),
          ];

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          HermesSpacing.md,
          HermesSpacing.lg,
          HermesSpacing.xl,
        ),
        children: [
          if (widget.embedded &&
              widget.kind == WorkspaceSessionKind.chats &&
              _filter == WorkspaceChatsFilter.all &&
              _query.isEmpty)
            ChatAttentionSection(
              sessions: unionSessions.where(widget.kind.includes).toList(),
              attention: widget.attention,
              running: widget.running,
              onOpenSession: widget.onOpenSession,
              onOpenActivity: widget.onOpenActivity,
            ),
          if (scopeLoading || scopeError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: HermesSpacing.md),
              child: scopeError == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.loading),
                        const LinearProgressIndicator(),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.could_not_load_conversations,
                          ),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_retryScope()),
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    ),
            ),
          TextField(
            key: kWorkspaceSessionSearchKey,
            autofocus: widget.view == WorkspaceSessionView.search,
            decoration: InputDecoration(
              hintText: widget.kind == WorkspaceSessionKind.crons
                  ? context.l10n.search_cron_conversations
                  : context.l10n.search_conversations,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.l10n.clear_search,
                      onPressed: () => setState(() => _query = ''),
                      icon: const Icon(Icons.clear),
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          if (widget.embedded) ...[
            const SizedBox(height: HermesSpacing.md),
            _buildChips(),
          ],
          const SizedBox(height: HermesSpacing.lg),
          if (sessions.isEmpty && !scopeLoading && scopeError == null)
            EmptyState(
              icon: _emptyIcon,
              title: _query.isEmpty
                  ? context.l10n.nothing_here
                  : context.l10n.no_matches,
              message: _emptyMessage,
            ),
          if (sessions.isNotEmpty) ...[
            if (pinnedSessions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: HermesSpacing.xs,
                  bottom: HermesSpacing.sm,
                ),
                child: Text(
                  context.l10n.pinned_on_this_device,
                  style: HermesTokens.of(context).typography.section,
                ),
              ),
              for (final session in pinnedSessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: HermesSpacing.sm),
                  child: _buildSessionRow(session, data),
                ),
            ],
            for (final group in groups)
              if (group.value.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: HermesSpacing.xs,
                    bottom: HermesSpacing.sm,
                  ),
                  child: Text(
                    widget.embedded
                        ? group.key.label(context.l10n)
                        : widget.title,
                    style: HermesTokens.of(context).typography.section,
                  ),
                ),
                for (final session in group.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: HermesSpacing.sm),
                    child: _buildSessionRow(session, data),
                  ),
              ],
          ],
        ],
      ),
    );
  }

  Widget _buildChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in WorkspaceChatsFilter.values)
            if (widget.kind != WorkspaceSessionKind.crons ||
                filter != WorkspaceChatsFilter.unassigned)
              Padding(
                padding: const EdgeInsets.only(right: HermesSpacing.sm),
                child: ChoiceChip(
                  label: Text(filter.label(context.l10n)),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() {
                    _filter = filter;
                  }),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Session session, WorkspaceSessionsData data) {
    final tokens = HermesTokens.of(context);
    final projectLabel = data.projectLabels[session.id];
    final locallyPinned = localPinIdForSession(session, _pinnedIds) != null;
    final isArchived =
        session.archived || data.archivedQuickChatIds.contains(session.id);
    final archiveBusy = _archiving.contains(session.id);
    final mutating =
        archiveBusy ||
        _renameDialogs.contains(session.id) ||
        _promoting.contains(session.id);
    // The move-to-project affordance serves the Archived-Quick view
    // (promote a lapsed quick chat) and any Unassigned surface — the
    // standalone view or the embedded chip browser with the Unassigned
    // chip active. Both call the same repository move.
    final showPromote =
        (widget.view == WorkspaceSessionView.archivedQuick ||
            _isUnassignedSurface) &&
        widget.onPromote != null;
    return HermesCard(
      onTap: () => widget.onOpenSession(session),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            locallyPinned
                ? Icons.push_pin
                : session.pinned
                ? Icons.push_pin_outlined
                : Icons.chat_bubble_outline,
            size: 20,
            color: locallyPinned || session.pinned
                ? tokens.accent
                : tokens.muted,
          ),
          const SizedBox(width: HermesSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title.isEmpty
                      ? context.l10n.untitled_chat
                      : session.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (session.preview.isNotEmpty)
                  Text(
                    session.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.muted),
                  ),
                const SizedBox(height: HermesSpacing.xs),
                Wrap(
                  spacing: HermesSpacing.sm,
                  runSpacing: HermesSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(
                      status: session.isActive
                          ? HermesStatus.running
                          : HermesStatus.completed,
                      label: session.isActive
                          ? context.l10n.status_running
                          : context.l10n.status_done,
                    ),
                    if (projectLabel != null)
                      _MetaChip(
                        label: projectLabel,
                        icon: Icons.folder_outlined,
                      )
                    else if (data.projectsKnown &&
                        widget.kind == WorkspaceSessionKind.chats)
                      _MetaChip(
                        label: context.l10n.unassigned,
                        icon: Icons.inbox_outlined,
                      ),
                    Text(
                      _relativeTime(_now, session.lastActive),
                      style: tokens.typography.label.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showPromote)
            _promoting.contains(session.id)
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: _isUnassignedSurface
                        ? context.l10n.move_to_project
                        : context.l10n.promote_to_project,
                    onPressed: mutating
                        ? null
                        : () => unawaited(_promote(session)),
                    icon: const Icon(Icons.drive_file_move_outline),
                  ),
          if (archiveBusy ||
              _renaming.contains(session.id) ||
              (!showPromote && _promoting.contains(session.id)))
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (widget.pinStore != null ||
              widget.onRename != null ||
              widget.onPromote != null ||
              widget.onArchive != null)
            PopupMenuButton<String>(
              tooltip: context.l10n.chat_actions,
              onSelected: (action) {
                switch (action) {
                  case 'archive':
                    unawaited(_setArchived(session, !isArchived));
                  case 'rename':
                    unawaited(_rename(session));
                  case 'pin':
                    unawaited(_togglePin(session));
                  case 'move':
                    unawaited(_promote(session, fromMenu: true));
                }
              },
              itemBuilder: (_) => [
                if (widget.onArchive != null)
                  PopupMenuItem(
                    value: 'archive',
                    enabled: !mutating,
                    child: Text(
                      isArchived
                          ? context.l10n.unarchive_chat
                          : context.l10n.archive_chat,
                    ),
                  ),
                if (widget.onRename != null)
                  PopupMenuItem(
                    value: 'rename',
                    enabled: !mutating,
                    child: Text(context.l10n.rename),
                  ),
                if (widget.onPromote != null && !isMachineSession(session))
                  PopupMenuItem(
                    value: 'move',
                    enabled: !mutating,
                    child: Text(context.l10n.move_to_project),
                  ),
                if (widget.pinStore != null)
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(
                      locallyPinned
                          ? context.l10n.unpin_on_this_device
                          : context.l10n.pin_on_this_device,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  IconData get _emptyIcon {
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned => Icons.inbox_outlined,
        WorkspaceChatsFilter.archived => Icons.archive_outlined,
        WorkspaceChatsFilter.recent => Icons.history_outlined,
        WorkspaceChatsFilter.all => Icons.search_off,
      };
    }
    return widget.view == WorkspaceSessionView.unassigned
        ? Icons.inbox_outlined
        : Icons.search_off;
  }

  String get _emptyMessage {
    if (widget.kind == WorkspaceSessionKind.crons &&
        _filter == WorkspaceChatsFilter.all &&
        _query.isEmpty) {
      return context.l10n.cron_conversations_empty;
    }
    if (widget.embedded) {
      return switch (_filter) {
        WorkspaceChatsFilter.unassigned =>
          context.l10n.every_conversation_is_already_assigned_to_a_project,
        WorkspaceChatsFilter.archived =>
          context.l10n.archived_conversations_appear_here,
        WorkspaceChatsFilter.recent =>
          context.l10n.nothing_changed_in_the_last_seven_days,
        WorkspaceChatsFilter.all =>
          context.l10n.no_conversation_matches_this_view,
      };
    }
    return switch (widget.view) {
      WorkspaceSessionView.unassigned =>
        context.l10n.every_conversation_is_already_assigned_to_a_project,
      WorkspaceSessionView.archivedQuick =>
        context.l10n.quick_chats_appear_here_after_their_retention_period,
      WorkspaceSessionView.all || WorkspaceSessionView.search =>
        context.l10n.no_conversation_matches_this_view,
    };
  }

  /// Compact relative time: "now", "5m", "2h", "3d", else a date.
  String _relativeTime(DateTime now, double lastActiveSeconds) =>
      formatRelativeTime(now, lastActiveSeconds);
}

/// A small neutral label under a conversation row (project, unassigned).
class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MetaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Semantics(
      label: label,
      container: true,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: HermesSpacing.sm,
            vertical: HermesSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.raised,
            borderRadius: BorderRadius.circular(HermesRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: tokens.muted),
              const SizedBox(width: 4),
              Text(label, style: tokens.typography.label),
            ],
          ),
        ),
      ),
    );
  }
}
