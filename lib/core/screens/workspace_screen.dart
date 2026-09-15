/// The Hermes workspace: the navigation shell bound to one saved connection.
///
/// This is the entry point of the new information architecture — Home,
/// Projects, Activity, More — wired to real server-owned Projects. It is
/// additive: the existing session-list flow is untouched, so the app keeps
/// working while the remaining destinations are built out.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/attachment_draft.dart';
import '../models/hermes_project.dart';
import '../services/android_share_intent_service.dart';
import '../services/attachment_draft_service.dart';
import '../services/chat_space_store.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';
import '../services/gateway_turn_application_controller.dart';
import '../services/gateway_turn_journal.dart';
import '../services/projects_gateway_client.dart';
import '../services/projects_repository.dart';
import '../services/quick_chat_store.dart';
import '../services/remote_files_client.dart';
import '../services/shared_attachment_preparer.dart';
import '../theme/hermes_theme.dart';
import '../utils/activity_feed.dart';
import '../utils/home_turn_signals.dart';
import '../utils/new_chat_options.dart';
import '../widgets/activity_pane.dart';
import '../widgets/hermes_components.dart';
import '../widgets/hermes_shell.dart';
import '../widgets/home_pane.dart';
import '../widgets/more_pane.dart';
import '../widgets/new_chat_sheet.dart';
import '../widgets/project_detail_screen.dart';
import '../widgets/projects_pane.dart';
import 'chat_screen.dart';
import 'files_screen.dart';
import 'cron_screen.dart';
import 'filing_screen.dart';
import 'memory_screen.dart';
import 'settings_screen.dart';
import 'skills_screen.dart';
import '../widgets/share_text_review_sheet.dart';
import 'workspace_sessions_screen.dart';

/// Builds the Projects repository for a connection. Injectable for tests.
typedef ProjectsRepositoryFactory =
    ProjectsRepository Function(SavedConnection connection);

/// Opens the authenticated Hermes dashboard for a URL. Injectable for tests so
/// the fallback can be asserted without launching a real browser.
typedef DashboardLauncher = Future<void> Function(String url);

/// Builds the screen a Home row opens. Injectable so the navigation contract
/// can be asserted without constructing a live chat transport.
typedef WorkspaceSessionScreenBuilder = Widget Function(Session session);

/// Builds the native remote Files destination. Injectable for navigation tests.
typedef WorkspaceFilesScreenBuilder =
    Widget Function(SavedConnection connection);

/// Reads the attention/running signals Home ranks by. Injectable so the
/// ranking can be asserted without a real recovery journal.
typedef WorkspaceTurnSignalsLoader =
    Future<HomeTurnSignals> Function(SavedConnection connection);

/// Reads the Activity timeline. Injectable so the destination can be asserted
/// without a real recovery journal.
///
/// Receives the session titles the screen has cached, because the turn
/// journal deliberately stores no prose: the titles are an input to the feed,
/// not something it can discover.
typedef WorkspaceActivityFeedLoader =
    Future<ActivityFeed> Function(
      SavedConnection connection,
      Map<String, String> sessionTitles,
    );

/// Identifies Home's global New button, so a test asserts the affordance
/// itself rather than an icon that another widget could also draw.
const Key kWorkspaceNewChatButtonKey = Key('workspace-new-chat');

/// Generates the id a new chat is created under. Injectable so a test can pin
/// it; the app uses the same generator the session list already uses.
typedef NewChatSessionIdFactory = String Function();
typedef SharedAttachmentPreparer =
    Future<List<AttachmentDraft>> Function(List<AndroidSharedFile> files);

/// The chat screen a Home row opens by default.
///
/// Exposed so a test can assert what actually ships rather than only the
/// injected stand-in. [turnApplicationController] is threaded through
/// deliberately: it owns durable turn recovery above the Navigator, so a chat
/// opened from Home must resume exactly like one opened from the session list.
Widget buildWorkspaceChatScreen({
  required SavedConnection connection,
  required Session session,
  String? projectName,
  String? projectWorkingDirectory,
  String? initialComposerText,
  List<AttachmentDraft> initialAttachmentDrafts = const [],
  GatewayTurnApplicationController? turnApplicationController,
}) {
  return ChatScreen(
    connection: connection,
    session: session,
    projectName: projectName,
    projectWorkingDirectory: projectWorkingDirectory,
    initialComposerText: initialComposerText,
    initialAttachmentDrafts: initialAttachmentDrafts,
    turnApplicationController: turnApplicationController,
  );
}

class WorkspaceScreen extends StatefulWidget {
  final SavedConnection connection;

  /// Overrides repository construction. When provided, the caller keeps
  /// ownership of the repository lifecycle and this screen will not close it.
  final ProjectsRepositoryFactory? repositoryFactory;

  /// Called when the user opens a project.
  final ValueChanged<String>? onOpenProject;

  /// Called when the user opens a chat from the Home digest. When null, this
  /// screen pushes the chat itself, so the shell is never a dead end.
  final ValueChanged<Session>? onOpenSession;

  /// Owns durable turn recovery above this screen's lifetime. Passed to every
  /// chat opened from Home so a turn survives leaving the chat.
  final GatewayTurnApplicationController? turnApplicationController;

  /// Overrides how Home reads the sessions it ranks. Injectable for tests so
  /// the digest can be asserted without a live gateway.
  final HomeSessionsLoader? sessionsLoader;

  /// Overrides the screen a Home row opens.
  final WorkspaceSessionScreenBuilder? sessionScreenBuilder;

  /// Overrides the native Files screen.
  final WorkspaceFilesScreenBuilder? filesScreenBuilder;

  /// Overrides how Home reads its attention and running signals.
  final WorkspaceTurnSignalsLoader? turnSignalsLoader;

  /// Overrides how Activity reads its timeline.
  final WorkspaceActivityFeedLoader? activityFeedLoader;

  /// Called when the user starts a chat from Home's New button. When null,
  /// this screen opens the chat itself, so New is never an inert affordance.
  final ValueChanged<NewChatDraft>? onNewChat;

  /// Overrides the id a new chat is created under.
  final NewChatSessionIdFactory? newChatSessionIdFactory;

  /// Text received through Android's share sheet. Kept for callers that only
  /// support the original text-only contract.
  final String? initialSharedText;

  /// Text and files received through Android's ACTION_SEND contract.
  final AndroidSharePayload? initialSharedPayload;

  /// Opens a fresh Quick Chat immediately, as requested by an Android launcher
  /// shortcut. The value is consumed by the caller before this screen opens.
  final bool initialQuickChat;

  /// Converts native-cached shared files into validated composer drafts.
  final SharedAttachmentPreparer? sharedAttachmentPreparer;

  /// Overrides how the Hermes dashboard fallback is opened.
  final DashboardLauncher? onOpenDashboard;

  const WorkspaceScreen({
    required this.connection,
    this.repositoryFactory,
    this.onOpenProject,
    this.onOpenSession,
    this.turnApplicationController,
    this.sessionsLoader,
    this.sessionScreenBuilder,
    this.filesScreenBuilder,
    this.turnSignalsLoader,
    this.activityFeedLoader,
    this.onNewChat,
    this.newChatSessionIdFactory,
    this.initialSharedText,
    this.initialSharedPayload,
    this.initialQuickChat = false,
    this.sharedAttachmentPreparer,
    this.onOpenDashboard,
    super.key,
  });

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  ProjectsRepository? _repository;
  DesktopGatewayClient? _ownedGateway;

  /// Proven answer for the gateway's `filing.*` correction-aware contract.
  /// Null until probed; false keeps the More entry disabled with its reason.
  bool? _filingAvailable;
  ChatSpaceStore? _spaceStore;
  QuickChatStore? _quickChats;
  ApiClient? _sessionsApi;
  bool _ownsRepository = false;
  bool _initialized = false;
  late final Future<void> _initialization;

  /// Quick chats past their retention deadline, recomputed on every session
  /// read. Held here rather than derived inside [HomePane] so the store is
  /// touched once per refresh instead of once per build.
  Set<String> _archivedQuickChats = const {};

  /// Reaches the live Home pane so it can be refreshed after a chat closes.
  final _homeKey = GlobalKey<HomePaneState>();

  /// Reaches the live Activity pane for the same reason.
  final _activityKey = GlobalKey<ActivityPaneState>();

  /// Reaches the action-only Activity view opened from Home.
  final _inboxKey = GlobalKey<ActivityPaneState>();

  /// The destination currently on screen. The New button is a Home
  /// affordance: over Projects or More it would be ambiguous what it creates.
  HermesDestination _destination = HermesDestination.home;

  /// The last known attention/running signals. Home ranks with these; an
  /// empty value simply means everything falls back to `Continue working`.
  HomeTurnSignals _turnSignals = HomeTurnSignals.empty;

  /// How much work Activity reports as blocked, for the shell badge. Held
  /// separately from the feed so the badge survives a destination switch that
  /// disposes the pane.
  int _activityBlockedCount = 0;

  /// Blocked plus failed turns shown by the Home Inbox action.
  int _inboxActionCount = 0;

  /// Session id to title, from the last successful session read.
  ///
  /// The turn journal deliberately stores no prose, so Activity has no titles
  /// of its own. Reusing what Home already fetched costs no extra request and
  /// no new gateway contract; a turn whose chat is absent simply stays
  /// untitled rather than being dropped or given a fabricated name.
  Map<String, String> _sessionTitles = const {};

  /// Best-effort Project labels learned from the latest projects.tree read,
  /// used to carry context into chats opened from the global Chats browser.
  Map<String, String> _chatProjectLabels = const {};

  /// Draft session ids of Project chats this workspace started, mapped to the
  /// Project they were committed to. When `session.open` first binds such a
  /// draft to a durable stored id, the binding is re-written under the stored
  /// id so the server-owned Project actually shows the chat.
  final Map<String, String> _projectChatBindings = {};
  bool _projectReconcileInstalled = false;

  /// Read lazily so a connection that never opens Home never touches secure
  /// storage, and so tests that inject a loader never construct one at all.
  GatewayTurnJournal? _journal;

  /// Home reads the same REST session list the session list screen uses; the
  /// injected loader wins so tests never touch a transport.
  late final HomeSessionsLoader _loadSessions =
      widget.sessionsLoader ?? _loadSessionsFromGateway;

  late final WorkspaceTurnSignalsLoader _loadTurnSignals =
      widget.turnSignalsLoader ?? _loadTurnSignalsFromJournal;

  Future<List<Session>> _loadSessionsFromGateway() {
    final connection = widget.connection;
    final api = _sessionsApi ??= ApiClient(
      baseUrl: connection.baseUrl,
      apiKey: connection.apiKey,
      pathPrefix: connection.gatewayPrefix ?? '',
    );
    return api.getSessions();
  }

  /// Derives Home's signals from the durable turn recovery journal.
  ///
  /// The journal is the only store that already survives process death and
  /// knows what a chat was doing, so no new gateway contract is required and
  /// legacy REST connections keep working — they simply have no scope, and
  /// [readHomeTurnSignals] then reports nothing.
  Future<HomeTurnSignals> _loadTurnSignalsFromJournal(
    SavedConnection connection,
  ) {
    final endpointDigest = endpointDigestForConnection(connection);
    if (endpointDigest == null) {
      return Future.value(HomeTurnSignals.empty);
    }
    return readHomeTurnSignals(
      journal: _journal ??= GatewayTurnJournal(),
      connectionId: connection.id,
      endpointDigest: endpointDigest,
    );
  }

  /// Reads the sessions, and refreshes the signals alongside them.
  ///
  /// The signal read is deliberately *not* awaited before the sessions are
  /// returned: it hits secure storage, and holding the whole screen on a
  /// skeleton until the journal answers would trade a working Home for a
  /// slightly better-ranked one. The ranking simply improves a frame later.
  ///
  /// Both are refreshed together so returning from a chat picks up both —
  /// `HomePaneState.refresh` only knows how to re-read sessions, and a digest
  /// ranked with stale signals is worse than one ranked with none.
  Future<List<Session>> _loadHome() {
    unawaited(_refreshTurnSignals());
    return _loadSessions().then((sessions) {
      // Cache the titles for Activity. Done here rather than in a second
      // request: the journal knows what ran, the session list knows what it
      // was called, and only one of the two costs a round trip.
      _cacheSessionTitles(sessions);
      // Which quick chats have aged out. Recomputed from the session list
      // rather than on a timer, so the retention rule is applied whenever
      // Home is read and never fires while the app is closed.
      unawaited(_refreshQuickChats(sessions));
      // The Activity badge is the only signal of blocked work visible while
      // the user is on another destination, so it cannot wait for the pane
      // to be mounted for the first time.
      unawaited(_refreshActivityBadge());
      return sessions;
    });
  }

  /// Opens the Quick chat lifecycle store for this connection.
  ///
  /// Lazy so a connection that never starts a Quick chat never touches
  /// SharedPreferences for one.
  Future<QuickChatStore> _quickChatStore() async {
    final existing = _quickChats;
    if (existing != null) return existing;
    final preferences = await SharedPreferences.getInstance();
    return _quickChats ??= QuickChatStore(
      preferences,
      connectionId: widget.connection.id,
    );
  }

  /// Recomputes which quick chats have passed their 72 h deadline.
  ///
  /// Also prunes records for chats the gateway no longer lists, so the store
  /// cannot grow without bound. A failure costs the archive rule for this
  /// refresh — never the session list itself.
  Future<void> _refreshQuickChats(List<Session> sessions) async {
    Set<String> archived;
    try {
      final store = await _quickChatStore();
      final now = DateTime.now();
      await store.prune({for (final session in sessions) session.id}, now: now);
      archived = (await store.load()).archivedAt(now);
    } catch (_) {
      archived = const {};
    }
    if (!mounted) return;
    if (archived.length == _archivedQuickChats.length &&
        archived.every(_archivedQuickChats.contains)) {
      return;
    }
    setState(() => _archivedQuickChats = Set.unmodifiable(archived));
  }

  /// Reads the timeline purely to keep the shell badge honest.
  ///
  /// Failures are swallowed: an unreadable journal costs a badge, and must
  /// never surface as an error on a destination the user is not looking at.
  Future<void> _refreshActivityBadge() async {
    try {
      await _loadActivity();
    } catch (_) {
      if (!mounted || (_activityBlockedCount == 0 && _inboxActionCount == 0)) {
        return;
      }
      setState(() {
        _activityBlockedCount = 0;
        _inboxActionCount = 0;
      });
    }
  }

  void _cacheSessionTitles(List<Session> sessions) {
    final titles = <String, String>{};
    for (final session in sessions) {
      final title = session.title.trim();
      if (title.isEmpty) continue;
      titles[session.id] = title;
    }
    _sessionTitles = Map.unmodifiable(titles);
  }

  /// Reads the Activity timeline from the durable turn journal.
  ///
  /// Same store, same scope, and same degradation rule as Home's signals: a
  /// connection with no Desktop Gateway has no journal scope and reports an
  /// empty timeline instead of an error, so a legacy REST connection keeps
  /// working.
  Future<ActivityFeed> _loadActivityFeedFromJournal(
    SavedConnection connection,
    Map<String, String> sessionTitles,
  ) async {
    final endpointDigest = endpointDigestForConnection(connection);
    if (endpointDigest == null) {
      return const ActivityFeed(groups: [], blockedCount: 0, runningCount: 0);
    }
    return readActivityFeed(
      journal: _journal ??= GatewayTurnJournal(),
      connectionId: connection.id,
      endpointDigest: endpointDigest,
      sessionTitles: sessionTitles,
    );
  }

  /// Reads the feed and keeps the shell badge in step with it.
  Future<ActivityFeed> _loadActivity() async {
    final loader = widget.activityFeedLoader ?? _loadActivityFeedFromJournal;
    // Titles may not be cached yet when Activity is the first destination the
    // user opens; read the sessions once so rows are not all untitled. A
    // failed read degrades a row's title, never the timeline itself.
    if (_sessionTitles.isEmpty) {
      try {
        _cacheSessionTitles(await _loadSessions());
      } catch (_) {}
    }
    final feed = await loader(widget.connection, _sessionTitles);
    final inboxCount = feed.groups
        .where(
          (group) =>
              group.kind == ActivityGroupKind.needsYou ||
              group.kind == ActivityGroupKind.failed,
        )
        .fold<int>(0, (count, group) => count + group.totalCount);
    if (mounted &&
        (feed.blockedCount != _activityBlockedCount ||
            inboxCount != _inboxActionCount)) {
      // Deferred: the pane calls this from its own build-triggered load, and
      // setState during that frame would rebuild the shell mid-layout.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _activityBlockedCount = feed.blockedCount;
          _inboxActionCount = inboxCount;
        });
      });
    }
    return feed;
  }

  Future<void> _refreshTurnSignals() async {
    HomeTurnSignals signals;
    try {
      signals = await _loadTurnSignals(widget.connection);
    } catch (_) {
      // A journal that cannot be read degrades the ranking, never the screen.
      signals = HomeTurnSignals.empty;
    }
    if (!mounted) return;
    setState(() => _turnSignals = signals);
  }

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
    final legacyText = widget.initialSharedText?.trim();
    final sharedPayload =
        widget.initialSharedPayload ??
        (legacyText == null || legacyText.isEmpty
            ? null
            : AndroidSharePayload(text: legacyText));
    if (sharedPayload != null && !sharedPayload.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startSharedChat(sharedPayload));
      });
    } else if (widget.initialQuickChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startQuickChat());
      });
    }
  }

  Future<void> _startQuickChat() async {
    await _initialization;
    if (!mounted) return;
    final draft = buildNewChatDraft(
      mode: NewChatMode.quickChat,
      sessionId:
          (widget.newChatSessionIdFactory ??
                  GatewayChatClient.generateSessionId)
              .call(),
      now: DateTime.now(),
    );
    final expiresAt = draft.expiresAt;
    if (expiresAt != null) {
      try {
        await (await _quickChatStore()).record(
          draft.session.id,
          expiresAt: expiresAt,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    await _finishNewChat(draft);
  }

  Future<void> _startSharedChat(AndroidSharePayload payload) async {
    await _initialization;
    if (!mounted) return;

    final text = payload.text ?? '';
    final projectsView = await _projectsForNewChat();
    if (!mounted) return;
    final activeProjects = projectsView.projects
        .where((project) => !project.archived)
        .toList();
    final decision = await showModalBottomSheet<ShareTextDecision>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ShareTextReviewSheet(
        sharedText: text,
        sharedFiles: payload.files,
        projectChatEnabled: activeProjects.isNotEmpty,
      ),
    );
    if (decision == null || !mounted) return;

    HermesProject? project;
    if (decision.mode == NewChatMode.projectChat) {
      project = activeProjects.length == 1
          ? activeProjects.single
          : await showModalBottomSheet<HermesProject>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ProjectPickerSheet(projects: activeProjects),
            );
      if (project == null || !mounted) return;
    }

    List<AttachmentDraft> attachments;
    try {
      attachments = payload.files.isEmpty
          ? const []
          : await (widget.sharedAttachmentPreparer ??
                    (files) => prepareAndroidSharedFiles(files))
                .call(payload.files);
    } on AttachmentDraftException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t prepare the shared files.')),
      );
      return;
    }
    if (!mounted) return;

    final draft = buildNewChatDraft(
      mode: decision.mode,
      sessionId:
          (widget.newChatSessionIdFactory ??
                  GatewayChatClient.generateSessionId)
              .call(),
      now: DateTime.now(),
      project: project,
    );
    final expiresAt = draft.expiresAt;
    if (draft.isQuick && expiresAt != null) {
      try {
        final store = await _quickChatStore();
        await store.record(draft.session.id, expiresAt: expiresAt);
      } catch (_) {}
    }
    if (!mounted) return;
    await _finishNewChat(
      draft,
      initialComposerText: buildSharedPrompt(
        decision.action,
        text,
        hasAttachments: attachments.isNotEmpty,
      ),
      initialAttachmentDrafts: attachments,
    );
  }

  @override
  void dispose() {
    // Only tear down what this screen created; an injected repository stays
    // owned by whoever supplied it.
    if (_ownsRepository) {
      unawaited(_repository?.close());
      _ownedGateway?.close();
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    final factory = widget.repositoryFactory;
    // The legacy local Spaces store is read-only here: it exists so the
    // migration preview can show what still lives on the phone.
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final spaceStore = ChatSpaceStore(
      preferences,
      connectionId: widget.connection.id,
    );

    if (factory != null) {
      final repository = factory(widget.connection);
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _spaceStore = spaceStore;
        _ownsRepository = false;
        _initialized = true;
      });
      return;
    }

    // Projects live on the Desktop Gateway JSON-RPC transport; a legacy REST
    // connection simply has nowhere to ask.
    final gatewayUrl = widget.connection.desktopGatewayUrl?.trim() ?? '';
    if (gatewayUrl.isEmpty) {
      if (mounted) setState(() => _initialized = true);
      return;
    }

    try {
      final gateway = DesktopGatewayClient.fromConnection(widget.connection);
      if (!mounted) {
        gateway.close();
        return;
      }
      setState(() {
        _ownedGateway = gateway;
        _repository = ProjectsRepository(
          client: gateway.projects,
          preferences: preferences,
          connectionId: widget.connection.id,
        );
        _spaceStore = spaceStore;
        _ownsRepository = true;
        _initialized = true;
      });
    } catch (_) {
      // A malformed gateway URL is a configuration problem, not a crash: fall
      // through to the same explanation a legacy connection gets.
      if (mounted) setState(() => _initialized = true);
    }
  }

  Widget _pane(BuildContext context, HermesDestination destination) {
    switch (destination) {
      case HermesDestination.chats:
        return WorkspaceSessionsScreen(
          title: 'Chats',
          view: WorkspaceSessionView.all,
          embedded: true,
          load: _loadWorkspaceSessionsData,
          onOpenSession: (session) => unawaited(
            _openSession(session, projectName: _chatProjectLabels[session.id]),
          ),
        );
      case HermesDestination.projects:
        final repository = _repository;
        if (!_initialized) {
          return const Padding(
            padding: EdgeInsets.only(top: HermesSpacing.lg),
            child: LoadingSkeleton(rows: 4),
          );
        }
        if (repository == null) {
          return const ErrorState.unsupported(
            title: 'Projects unavailable',
            message:
                'Projects need a Desktop Gateway connection. Add the Desktop '
                'Gateway URL to this connection to organize chats across '
                'your devices.',
          );
        }
        return ProjectsPane(
          repository: repository,
          onProjectSelected: (projectId) => _openProject(repository, projectId),
          spaceStore: _spaceStore,
        );
      case HermesDestination.home:
        return HomePane(
          key: _homeKey,
          loadSessions: _loadHome,
          attention: _turnSignals.attention,
          running: _turnSignals.running,
          archived: _archivedQuickChats,
          onOpenSession: _openSession,
        );
      case HermesDestination.activity:
        return ActivityPane(
          key: _activityKey,
          loadFeed: _loadActivity,
          onOpenItem: _openActivityItem,
        );
      case HermesDestination.more:
        // Probe filing lazily, on first open of the pane: the entry must
        // reflect the server's real answer, and an unprobed gateway is not
        // evidence either way.
        if (_filingAvailable == null) unawaited(_probeFiling());
        return MorePane(
          sections: buildMoreSections(
            dashboardReachable: _dashboardReachable,
            filingAvailable: _filingAvailable == true,
          ),
          onSelect: _openMoreEntry,
        );
    }
  }

  /// The dashboard only exists when the connection names a host to reach it
  /// on. Without one, every dashboard-backed entry is disabled *with a reason*
  /// rather than hidden, per the roadmap's capability-discovery rule.
  bool get _dashboardReachable => widget.connection.host.trim().isNotEmpty;

  /// The dashboard origin, which is not the gateway chat origin: it has its
  /// own port and optional path prefix.
  String get _dashboardUrl {
    final connection = widget.connection;
    final scheme = connection.useHttps ? 'https' : 'http';
    return SavedConnection.joinBaseUrl(
      '$scheme://${connection.host}:${connection.dashboardPort}',
      connection.dashboardPrefix ?? '',
    );
  }

  Future<void> _openDashboard() async {
    final launcher = widget.onOpenDashboard;
    if (launcher != null) {
      await launcher(_dashboardUrl);
      return;
    }
    final uri = Uri.tryParse(_dashboardUrl);
    if (uri == null) return;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the Hermes dashboard.')),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Opens a chat from the Home digest.
  ///
  /// A host that supplied [WorkspaceScreen.onOpenSession] owns navigation, so
  /// this screen must not also push a route underneath it. Otherwise it opens
  /// the chat itself and re-reads Home on return, because the reason a chat
  /// was blocked usually stops being true while the user is inside it.
  Future<void> _openSession(
    Session session, {
    String? projectName,
    String? projectWorkingDirectory,
    String? initialComposerText,
    List<AttachmentDraft> initialAttachmentDrafts = const [],
  }) async {
    final report = widget.onOpenSession;
    if (report != null) {
      report(session);
      return;
    }

    final builder = widget.sessionScreenBuilder;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            builder?.call(session) ??
            buildWorkspaceChatScreen(
              connection: widget.connection,
              session: session,
              projectName: projectName,
              projectWorkingDirectory: projectWorkingDirectory,
              initialComposerText: initialComposerText,
              initialAttachmentDrafts: initialAttachmentDrafts,
              turnApplicationController: widget.turnApplicationController,
            ),
      ),
    );
    if (!mounted) return;
    unawaited(_homeKey.currentState?.refresh() ?? Future<void>.value());
  }

  /// Opens one project's detail screen.
  ///
  /// A host that supplied [WorkspaceScreen.onOpenProject] owns navigation, so
  /// this screen must not also push a route underneath it — the same rule
  /// [_openSession] follows. Otherwise it opens the project itself, because a
  /// project card that does nothing is a dead end in the shell.
  Future<void> _openProject(
    ProjectsRepository repository,
    String projectId,
  ) async {
    final report = widget.onOpenProject;
    if (report != null) {
      report(projectId);
      return;
    }

    // The name is read from the list we already hold, so the screen opens with
    // the real title instead of "Untitled" until the drill-in lands.
    final known = repository.current.projects
        .where((project) => project.id == projectId)
        .firstOrNull;

    final project =
        known ?? HermesProject(id: projectId, slug: projectId, name: 'Project');

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProjectDetailScreen(
          projectId: projectId,
          projectName: project.name,
          loadSessions: ({required bool refresh}) =>
              repository.projectSessions(projectId, refresh: refresh),
          onOpenSession: (session) => _openSession(session,
              projectName: project.name,
              projectWorkingDirectory: project.workingDirectory),
          onNewChat: () => unawaited(_startProjectChat(project)),
          projects: repository.current.projects,
          onMoveSession: (session, targetProjectId) =>
              repository.assignSession(session.id, targetProjectId),
          onRenameProject: (name) => repository.rename(projectId, name),
          onArchiveProject: () => repository.archive(projectId),
          onDeleteProject: () => repository.delete(projectId),
        ),
      ),
    );
  }

  /// Opens the Home action Inbox. It deliberately reuses the Activity feed but
  /// filters out informational Running/Completed rows, so this route contains
  /// only work that can change what the user does next.
  void _openInbox() {
    _push(
      Scaffold(
        appBar: AppBar(title: const Text('Inbox')),
        body: ActivityPane(
          key: _inboxKey,
          loadFeed: _loadActivity,
          onOpenItem: _openActivityItem,
          actionableOnly: true,
        ),
      ),
    );
  }

  /// Opens the chat an Activity row belongs to.
  ///
  /// The journal outlives a deleted session, so a row can name a chat the
  /// gateway no longer has. Pushing a chat screen for it would open a surface
  /// that can never load, so an unknown session is a deliberate no-op rather
  /// than a broken navigation.
  Future<void> _openActivityItem(ActivityItem item) async {
    final session = _sessionForActivity(item);
    if (session == null) return;
    await _openSession(session);
    if (!mounted) return;
    unawaited(_activityKey.currentState?.refresh() ?? Future<void>.value());
    unawaited(_inboxKey.currentState?.refresh() ?? Future<void>.value());
  }

  /// The live session an Activity row points at, or `null` when the chat is
  /// no longer known.
  Session? _sessionForActivity(ActivityItem item) {
    final title = _sessionTitles[item.sessionId];
    if (title == null) return null;
    return Session(
      id: item.sessionId,
      title: title,
      model: '',
      source: '',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: item.updatedAt.millisecondsSinceEpoch / 1000.0,
    );
  }

  /// The Projects state the New sheet reasons about.
  ///
  /// A connection with no Desktop Gateway has nowhere to host projects, which
  /// is the same situation for the user as a gateway that predates them: the
  /// mode is offered, disabled, with a reason.
  Future<ProjectsView> _projectsForNewChat() async {
    final repository = _repository;
    if (repository == null) {
      return const ProjectsView(support: ProjectsSupport.unsupported);
    }
    // Home may be the first screen the user ever opens, in which case nothing
    // has probed the gateway yet. Probe now rather than claiming `unknown`.
    if (repository.current.support == ProjectsSupport.unknown) {
      return repository.refresh();
    }
    return repository.current;
  }

  /// Starts directly inside a Project without asking the user to choose the
  /// mode or Project again. The same commit-before-open path is reused.
  Future<void> _startProjectChat(HermesProject project) async {
    final draft = buildNewChatDraft(
      mode: NewChatMode.projectChat,
      sessionId:
          (widget.newChatSessionIdFactory ??
                  GatewayChatClient.generateSessionId)
              .call(),
      now: DateTime.now(),
      project: project,
    );
    await _finishNewChat(draft);
  }

  /// Runs Home's global New affordance.
  ///
  /// Every product rule it depends on lives in `new_chat_options.dart`; this
  /// method only sequences the two questions (which mode, then which project)
  /// and opens the result.
  Future<void> _startNewChat() async {
    final view = await _projectsForNewChat();
    if (!mounted) return;

    final mode = await showModalBottomSheet<NewChatMode>(
      context: context,
      builder: (_) => NewChatSheet(options: buildNewChatOptionsFor(view)),
    );
    if (mode == null || !mounted) return;

    HermesProject? project;
    if (mode == NewChatMode.projectChat) {
      final projects = view.projects
          .where((candidate) => !candidate.archived)
          .toList();
      if (projects.isEmpty) return;
      // A single project carries no decision, so do not charge a tap for it.
      project = projects.length == 1
          ? projects.single
          : await showModalBottomSheet<HermesProject>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ProjectPickerSheet(projects: projects),
            );
      if (project == null || !mounted) return;
    }

    final draft = buildNewChatDraft(
      mode: mode,
      sessionId:
          (widget.newChatSessionIdFactory ??
                  GatewayChatClient.generateSessionId)
              .call(),
      now: DateTime.now(),
      project: project,
    );

    // Start the retention clock now, before the chat opens. Recorded even
    // when a host owns navigation: the lifecycle belongs to the chat, not to
    // whoever displays it. A failure costs the archive rule for this chat,
    // never the chat itself.
    final expiresAt = draft.expiresAt;
    if (draft.isQuick && expiresAt != null) {
      try {
        final store = await _quickChatStore();
        await store.record(draft.session.id, expiresAt: expiresAt);
      } catch (_) {}
      if (!mounted) return;
    }

    await _finishNewChat(draft);
  }

  /// Commits a drafted Project chat before exposing it to navigation.
  ///
  /// `projects.assign_session` is idempotent, so Retry can safely reuse the
  /// same session id. A failed write never opens an Unassigned chat under the
  /// guise of the Project the user chose.
  Future<void> _finishNewChat(
    NewChatDraft draft, {
    String? initialComposerText,
    List<AttachmentDraft> initialAttachmentDrafts = const [],
  }) async {
    final projectId = draft.projectId;
    if (projectId != null) {
      // Remember the intent so the stored-id reconciliation below can re-write
      // the assignment once this draft gains its durable server id.
      _projectChatBindings[draft.session.id] = projectId;
      _installProjectAssignmentReconcile();
      try {
        final repository = _repository;
        if (repository == null) {
          throw StateError('Projects are unavailable for this connection');
        }
        await repository.assignSession(draft.session.id, projectId);
      } on ProjectsUnsupportedException {
        // Stock Hermes hosts the `projects.*` family but predates
        // `projects.assign_session`. Do not block the chat: open it with the
        // project's working directory as the session cwd instead — the
        // gateway derives project membership from cwd (`project_for_path`),
        // so the chat still lands inside the project.
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'This gateway can\u2019t file chats into projects directly \u2014 '
              'opened in the project\u2019s folder instead.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Couldn’t create Project chat'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => unawaited(
                _finishNewChat(
                  draft,
                  initialComposerText: initialComposerText,
                  initialAttachmentDrafts: initialAttachmentDrafts,
                ),
              ),
            ),
          ),
        );
        return;
      }
      if (!mounted) return;
    }

    final report = widget.onNewChat;
    if (report != null) {
      report(draft);
      return;
    }
    await _openSession(
      draft.session,
      projectName: draft.projectName,
      projectWorkingDirectory: draft.projectWorkingDirectory,
      initialComposerText: initialComposerText,
      initialAttachmentDrafts: initialAttachmentDrafts,
    );
  }

  /// Re-writes a Project chat's assignment under its durable stored id.
  ///
  /// The commit-before-open write uses the draft id (`mob-...`) because the
  /// stored id only exists once `session.open` runs. The Gateway binds the two
  /// ids; this workspace subscribes once and, on the first binding, writes the
  /// authoritative row the server-owned Project tree can resolve.
  void _installProjectAssignmentReconcile() {
    if (_projectReconcileInstalled) return;
    final controller = widget.turnApplicationController;
    if (controller == null) return;
    _projectReconcileInstalled = true;
    controller
        .sessionFor(widget.connection)
        .onSessionBound = (localSessionId, storedSessionId) {
      final projectId = _projectChatBindings.remove(localSessionId);
      if (projectId == null) return;
      unawaited(_reconcileProjectAssignment(storedSessionId, projectId));
    };
  }

  Future<void> _reconcileProjectAssignment(
    String storedSessionId,
    String projectId,
  ) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.assignSession(storedSessionId, projectId);
    } catch (_) {
      // Best-effort: the commit-before-open write already recorded the user's
      // choice under the draft id, so the intent is never lost — this only
      // makes the chat visible inside the Project one refresh sooner.
      debugPrint('Could not reconcile Project assignment for $storedSessionId');
    }
  }

  Future<WorkspaceSessionsData> _loadWorkspaceSessionsData() async {
    final sessions = await _loadSessions();
    _cacheSessionTitles(sessions);

    Set<String> claimed = const {};
    Map<String, String> projectLabels = const {};
    final repository = _repository;
    if (repository != null) {
      try {
        // The session list is the primary surface and must never wait on the
        // Projects transport: a wedged Desktop Gateway (unreachable host,
        // slow connect) would otherwise hide every conversation behind an
        // infinite skeleton. Bounded, best-effort, additive metadata only.
        final overview = await repository
            .overview(refresh: true)
            .timeout(const Duration(seconds: 8));
        claimed = overview.scopedSessionIds.toSet();
        // Best-effort session → project label, from the server's own preview
        // rows. A conversation the overview does not name stays honest as
        // "Unassigned" in the Chats row.
        projectLabels = {
          for (final project in overview.projects)
            for (final preview in project.previewSessions)
              preview.id: project.label,
        };
      } catch (_) {
        // A gateway without projects.tree still gets All chats and Search.
      }
    }

    Set<String> archived = const {};
    try {
      final store = await _quickChatStore();
      archived = (await store.load()).archivedAt(DateTime.now());
    } catch (_) {
      // Quick-chat metadata is additive; session access must survive its loss.
    }

    _chatProjectLabels = Map.unmodifiable(projectLabels);
    return WorkspaceSessionsData(
      sessions: sessions,
      claimedSessionIds: Set.unmodifiable(claimed),
      archivedQuickChatIds: Set.unmodifiable(archived),
      projectLabels: _chatProjectLabels,
    );
  }

  void _openWorkspaceSessionView(WorkspaceSessionView view) {
    final title = switch (view) {
      WorkspaceSessionView.all => 'All chats',
      WorkspaceSessionView.unassigned => 'Unassigned chats',
      WorkspaceSessionView.archivedQuick => 'Archived quick chats',
      WorkspaceSessionView.search => 'Search',
    };
    _push(
      WorkspaceSessionsScreen(
        title: title,
        view: view,
        load: _loadWorkspaceSessionsData,
        onOpenSession: (session) => unawaited(_openSession(session)),
        onPromote: view == WorkspaceSessionView.archivedQuick
            ? _promoteQuickChat
            : null,
      ),
    );
  }

  Future<void> _promoteQuickChat(Session session) async {
    final repository = _repository;
    if (repository == null) {
      throw StateError('Projects are unavailable for this connection');
    }
    var view = repository.current;
    if (view.support == ProjectsSupport.unknown) {
      view = await repository.refresh();
    }
    final projects = view.projects
        .where((project) => !project.archived)
        .toList(growable: false);
    if (projects.isEmpty) {
      throw StateError('Create a Project before promoting this chat');
    }

    if (!mounted) throw const QuickChatPromotionCancelled();
    final project = projects.length == 1
        ? projects.single
        : await showModalBottomSheet<HermesProject>(
            context: context,
            isScrollControlled: true,
            builder: (_) => ProjectPickerSheet(projects: projects),
          );
    if (project == null) throw const QuickChatPromotionCancelled();

    await repository.assignSession(session.id, project.id);
    await (await _quickChatStore()).promote(session.id);
    if (mounted) {
      setState(() {
        _archivedQuickChats = {
          for (final id in _archivedQuickChats)
            if (id != session.id) id,
        };
      });
    }
  }

  Future<void> _openFiles() async {
    final builder = widget.filesScreenBuilder;
    if (builder != null) {
      _push(builder(widget.connection));
      return;
    }
    final files = RemoteFilesClient.fromConnection(widget.connection);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FilesScreen(files: files)),
      );
    } finally {
      files.close();
    }
  }

  /// Probes `filing.status` once so the More pane can gate AI-assisted
  /// filing on the server's real capability. Best-effort: any failure —
  /// unsupported family, transport blink, missing contract library —
  /// resolves to false, which keeps the entry honestly disabled rather
  /// than optimistically open.
  Future<void> _probeFiling() async {
    var gateway = _ownedGateway;
    var ownsProbeOnly = false;
    if (gateway == null) {
      final gatewayUrl = widget.connection.desktopGatewayUrl?.trim() ?? '';
      if (gatewayUrl.isEmpty) return;
      try {
        gateway = DesktopGatewayClient.fromConnection(widget.connection);
        ownsProbeOnly = true;
      } catch (_) {
        return;
      }
    }
    try {
      final status = await gateway.filing.status();
      if (mounted) setState(() => _filingAvailable = status.available);
    } catch (_) {
      if (mounted) setState(() => _filingAvailable = false);
    } finally {
      if (ownsProbeOnly) gateway.close();
    }
  }

  void _openMoreEntry(MoreEntry entry) {
    final connection = widget.connection;
    switch (entry.id) {
      case 'unassigned':
        _openWorkspaceSessionView(WorkspaceSessionView.unassigned);
      case 'archived-quick':
        _openWorkspaceSessionView(WorkspaceSessionView.archivedQuick);
      case 'files':
        unawaited(_openFiles());
      case 'ai-filing':
        _push(FilingScreen(connection: connection));
      case 'cron':
        _push(CronScreen(connection: connection));
      case 'skills':
        _push(SkillsScreen(connection: connection));
      case 'memory':
        _push(MemoryScreen(connection: connection));
      case 'settings':
        _push(SettingsScreen(connection: connection));
      case 'dashboard':
        unawaited(_openDashboard());
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        title: Text(widget.connection.label),
        centerTitle: false,
        actions: [
          if (_destination == HermesDestination.home) ...[
            IconButton(
              tooltip: _inboxActionCount == 0
                  ? 'Open inbox'
                  : 'Open inbox ($_inboxActionCount)',
              onPressed: _openInbox,
              icon: Badge(
                isLabelVisible: _inboxActionCount > 0,
                label: Text('$_inboxActionCount'),
                child: const Icon(Icons.inbox_outlined),
              ),
            ),
            IconButton(
              tooltip: 'Search all chats',
              onPressed: () =>
                  _openWorkspaceSessionView(WorkspaceSessionView.search),
              icon: const Icon(Icons.search),
            ),
          ],
        ],
      ),
      body: HermesShell(
        initialDestination: HermesDestination.home,
        // The badge is the only attention signal visible from another
        // destination, so blocked work has to raise it even while the user is
        // in Projects or More.
        badges: {
          HermesDestination.home: _turnSignals.attention.length,
          HermesDestination.activity: _activityBlockedCount,
        },
        onDestinationChanged: (destination) =>
            setState(() => _destination = destination),
        // The FAB belongs to the shell, not to this Scaffold: above the shell
        // it would float over the bottom bar and swallow taps on More.
        floatingActionButton:
            _destination == HermesDestination.home ||
                _destination == HermesDestination.chats
            ? FloatingActionButton.extended(
                key: kWorkspaceNewChatButtonKey,
                onPressed: () => unawaited(_startNewChat()),
                icon: const Icon(Icons.add),
                label: const Text('New'),
              )
            : null,
        builder: _pane,
      ),
    );
  }
}
