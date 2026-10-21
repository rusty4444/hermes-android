// Chat screen with real-time streaming via REST API.
// Uses REST endpoints: POST /api/sessions/{id}/chat and
// GET /api/sessions/{id}/messages.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/voice_composer_controller.dart';
import '../controllers/voice_recording_controller.dart';
import '../services/local_voice_recorder.dart';
import '../services/voice_transcription.dart';
import '../widgets/voice_recording_controls.dart';
import '../services/connection_manager.dart';
import '../services/attachment_draft_service.dart';
import '../services/composer_draft_store.dart';
import '../services/chat_model_override_store.dart';
import '../services/chat_density_preference.dart';
import '../services/chat_history_window.dart';
import '../services/desktop_gateway_client.dart';
import '../services/gateway_turn_application_controller.dart';
import '../services/gateway_turn_coordinator.dart';
import '../services/gateway_turn_recovery.dart';
import '../services/gateway_turn_ui_projection.dart';
import '../services/remote_files_client.dart';
import '../services/turn_notification_service.dart';
import '../services/notification_prefs.dart';
import '../services/voice_composer_adapter.dart';
import '../services/ws_client.dart';
import '../utils/media_tags.dart';
import '../models/attachment_draft.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_approval.dart';
import '../models/gateway_clarify.dart';
import '../models/gateway_insight.dart';
import '../models/gateway_sensitive_prompt.dart';
import '../models/gateway_turn_contract.dart';
import '../models/projects_tree_overview.dart';
import '../services/tool_activity_group_pins.dart';
import '../utils/chat_display_items.dart';
import '../utils/chat_history_scroll.dart';
import '../utils/message_content.dart';
import '../utils/responsive.dart';
import '../utils/turn_recovery_fallback.dart';
import 'files_screen.dart';
import '../widgets/gateway_activity_card.dart';
import '../widgets/chat_context_header.dart';
import '../widgets/markdown_code_block.dart';
import '../widgets/attachment_draft_tile.dart';
import '../widgets/chat_end_affordance.dart';
import '../widgets/gateway_approval_dialog.dart';
import '../widgets/gateway_clarify_dialog.dart';
import '../widgets/gateway_insight_card.dart';
import '../widgets/gateway_sensitive_prompt_dialog.dart';
import '../widgets/media_artifact_card.dart';
import '../widgets/voice_composer_controls.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// These colors remain identical in light and dark themes. Their 8.15:1
/// contrast ratio keeps normal user-message text above WCAG AA.
const hermesUserMessageBubbleBackground = Color(0xFFD4AF37);
const hermesUserMessageForeground = Color(0xFF1C1B1F);

/// Recovery v2 opens a new server session and cannot yet target an existing
/// Gateway session. Keep it confined to locally-created drafts; a session from
/// `GET /sessions` must submit through the legacy transport that accepts its
/// exact session id. A Project draft also uses legacy until `session.open`
/// supports `cwd`, since stock Hermes files it by the creation cwd.
@visibleForTesting
bool shouldUseRecoveryV2ForSession(
  Session session, {
  String? projectWorkingDirectory,
}) =>
    session.isLocalDraft &&
    (projectWorkingDirectory?.trim().isNotEmpty != true);

/// Avoid opening the same local draft once through the legacy client's
/// `session.create` path and again through recovery v2's `session.open` path.
/// If recovery v2 is explicitly unsupported, the local draft may safely fall
/// back to the legacy transport and establish its first server session there.
@visibleForTesting
bool shouldEstablishLegacyDesktopSession(
  Session session, {
  required bool legacyTransportFallback,
}) => !session.isLocalDraft || legacyTransportFallback;

class _ModelChoice {
  final String provider;
  final String model;

  const _ModelChoice({required this.provider, required this.model});
}

class _ModelSelection {
  final _ModelChoice choice;
  final String reasoningEffort;

  const _ModelSelection({required this.choice, required this.reasoningEffort});
}

const _reasoningEffortOptions = <String>[
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'max',
  'ultra',
];

String _reasoningEffortLabel(BuildContext context, String effort) {
  return switch (effort) {
    'none' => context.l10n.off_no_thinking,
    'minimal' => context.l10n.reasoning_minimal,
    'low' => context.l10n.reasoning_low,
    'medium' => context.l10n.reasoning_medium,
    'high' => context.l10n.reasoning_high,
    'xhigh' => context.l10n.extra_high,
    'max' => context.l10n.reasoning_max,
    'ultra' => context.l10n.reasoning_ultra,
    _ => effort,
  };
}

enum _ResponseTransport { none, rest, desktop }

@visibleForTesting
typedef TestRemotePromptSubmit =
    Future<void> Function({
      required String sessionId,
      required String text,
      required StreamCallback onEvent,
      required void Function() onSent,
    });

@visibleForTesting
typedef TestRemoteAttachmentUpload =
    Future<AttachmentUploadReceipt> Function({
      required AttachmentDraft draft,
      required String dataUrl,
    });

/// Loads the gateway's authoritative chat-to-Project placement in tests.
@visibleForTesting
typedef TestProjectOverviewLoader = Future<ProjectsTreeOverview> Function();

/// The result of looking up a chat in an authoritative Projects tree.
///
/// [known] distinguishes a chat explicitly filed under Home (known, with no
/// Project name) from a chat absent from a response that may have raced its
/// first server-side persistence (unknown). The latter must not erase a valid
/// navigation-time Project label.
@visibleForTesting
class ChatProjectHeaderResolution {
  final bool known;
  final String? projectName;

  const ChatProjectHeaderResolution._({
    required this.known,
    required this.projectName,
  });

  static const unknown = ChatProjectHeaderResolution._(
    known: false,
    projectName: null,
  );

  const ChatProjectHeaderResolution.known(this.projectName) : known = true;
}

/// Resolves the first canonical session id present in [overview].
///
/// Callers pass the gateway's stored id before any draft/mobile id. This makes
/// the durable record authoritative after `session.open` reconciliation while
/// still supporting existing sessions whose app id is already the stored id.
@visibleForTesting
ChatProjectHeaderResolution resolveChatProjectHeader(
  ProjectsTreeOverview overview,
  Iterable<String> sessionIds,
) {
  for (final rawId in sessionIds) {
    final id = rawId.trim();
    if (id.isEmpty) continue;
    final ownerId = overview.sessionProjects[id];
    if (ownerId == null) continue;
    if (ownerId == ProjectsTreeOverview.noProjectId) {
      return const ChatProjectHeaderResolution.known(null);
    }
    return ChatProjectHeaderResolution.known(overview.ownerLabelOf(id));
  }
  return ChatProjectHeaderResolution.unknown;
}

@visibleForTesting
typedef TestComposerDraftReader =
    Future<String?> Function({
      required String connectionId,
      required String sessionId,
    });

/// Mutable holder that lets a test reach the ChatScreen's Desktop
/// connection-state handler when no real gateway is configured. The screen
/// fills [handler] in `initState`; the test then calls it with the state
/// transitions a reconnecting `DesktopGatewayClient` would emit.
@visibleForTesting
class TestDesktopConnectionHook {
  void Function(DesktopConnectionState state)? handler;
}

/// Test seam for session-scoped terminal events that arrive after the
/// prompt.submit listener was detached by a socket close.
@visibleForTesting
class TestDesktopAsyncEventHook {
  void Function(StreamEvent event)? handler;
}

class _PendingSensitivePrompt {
  final GatewaySensitivePromptRequest request;
  final int responseGeneration;

  const _PendingSensitivePrompt(this.request, this.responseGeneration);
}

class _PendingClarifyPrompt {
  final GatewayClarifyRequest request;
  final int responseGeneration;

  const _PendingClarifyPrompt(this.request, this.responseGeneration);
}

class ChatScreen extends StatefulWidget {
  final SavedConnection connection;
  final Session session;

  /// The server-owned Project this chat was opened from, when known.
  /// `null` stays explicit as Unassigned in the sticky context header.
  final String? projectName;

  /// The owning Project's working directory on the gateway host. Forwarded as
  /// `cwd` when this chat's session is created, so a Project chat runs inside
  /// the project folder — stock Hermes derives project membership from the
  /// session cwd (`project_for_path`), so the cwd is the filing.
  final String? projectWorkingDirectory;

  /// Optional text supplied by Android's share sheet. It only prefills the
  /// composer; sending remains an explicit user action.
  final String? initialComposerText;

  /// Validated app-private files supplied by Android's share sheet.
  final List<AttachmentDraft> initialAttachmentDrafts;

  final GatewayTurnApplicationController? turnApplicationController;

  @visibleForTesting
  final GatewayTurnApplicationSession? testTurnApplicationSession;

  @visibleForTesting
  final ApiClient? testApiClient;

  @visibleForTesting
  final AttachmentDraftService? testAttachmentDraftService;

  @visibleForTesting
  final TestRemotePromptSubmit? testRemotePromptSubmit;

  @visibleForTesting
  final Future<String?> Function()? testServerFilePicker;

  @visibleForTesting
  final TestRemoteAttachmentUpload? testRemoteAttachmentUpload;

  @visibleForTesting
  final List<AttachmentDraft> testInitialAttachmentDrafts;

  @visibleForTesting
  final TestComposerDraftReader? testComposerDraftReader;

  @visibleForTesting
  final VoiceComposerAdapter? testVoiceComposerAdapter;

  @visibleForTesting
  final VoiceRecorder? testVoiceRecorder;

  @visibleForTesting
  final Future<String> Function(String)? testVoiceTranscription;

  /// Lets a test observe what the chat posts to Android when a turn settles,
  /// without touching the notification platform channel.
  @visibleForTesting
  final TurnNotificationService? testTurnNotifications;

  /// Passed by tests when no real Desktop gateway is configured: the
  /// screen attaches its connection-state handler to this hook in
  /// `initState`, so a test can drive drop-during-turn → reconnect →
  /// resync transitions without a live socket.
  @visibleForTesting
  final TestDesktopConnectionHook? testDesktopConnectionHook;

  @visibleForTesting
  final TestDesktopAsyncEventHook? testDesktopAsyncEventHook;

  /// Supplies an authoritative Projects tree without a real gateway.
  @visibleForTesting
  final TestProjectOverviewLoader? testProjectOverviewLoader;

  /// Invoked on every `_ensureDesktopSession()` call so a test can assert
  /// the reattach resync actually re-bound the session.
  @visibleForTesting
  final VoidCallback? testDesktopSessionEnsured;

  /// Observes the project-cwd binding before a legacy draft's first prompt.
  @visibleForTesting
  final Future<void> Function(String sessionId, String cwd)?
  testLegacyProjectSessionEnsure;

  /// Test seam mirroring `DesktopGatewayClient.storedSessionKeyFor`: maps
  /// the mobile session id to the gateway's stored DB key so a test can
  /// assert the reattach history refetch targets the stored identity.
  @visibleForTesting
  final String? Function(String mobileSessionId)? testStoredSessionKey;

  /// Lets widget tests observe the exact stored-session scope bound to an
  /// artifact tap without opening a real dashboard connection.
  @visibleForTesting
  final RemoteFilesDataSource Function(String storedSessionId)?
  testMediaFilesClient;

  const ChatScreen({
    required this.connection,
    required this.session,
    this.projectName,
    this.projectWorkingDirectory,
    this.initialComposerText,
    this.initialAttachmentDrafts = const [],
    this.turnApplicationController,
    this.testTurnApplicationSession,
    this.testApiClient,
    this.testAttachmentDraftService,
    this.testRemotePromptSubmit,
    this.testServerFilePicker,
    this.testRemoteAttachmentUpload,
    this.testInitialAttachmentDrafts = const [],
    this.testComposerDraftReader,
    this.testVoiceComposerAdapter,
    this.testVoiceRecorder,
    this.testVoiceTranscription,
    this.testTurnNotifications,
    this.testDesktopConnectionHook,
    this.testDesktopAsyncEventHook,
    this.testProjectOverviewLoader,
    this.testDesktopSessionEnsured,
    this.testLegacyProjectSessionEnsure,
    this.testStoredSessionKey,
    this.testMediaFilesClient,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _messages = [];
  final ChatHistoryWindow _historyWindow = ChatHistoryWindow();
  bool _loadingOlder = false;
  final List<GatewayToolActivity> _toolActivities = [];

  /// Expansion choices for tool-activity cards, keyed by group id so they
  /// survive the list reordering and row eviction that a streaming turn causes.
  final ToolActivityGroupPins _toolActivityPins = ToolActivityGroupPins();
  final List<GatewaySubagentActivity> _subagentActivities = [];
  final Map<String, GatewayNotification> _gatewayNotifications = {};
  final Map<String, Timer> _notificationTimers = {};
  late final List<GatewayNotice> _gatewayNotices;
  bool _loading = true;
  String? _error;
  late final ApiClient _client;
  late final GatewayChatClient _gateway;
  late final AttachmentDraftService _attachmentDraftService;
  late final AttachmentDraftSendCoordinator _attachmentSendCoordinator;
  late final Future<ChatModelOverrideStore> _chatModelStore;
  late final Future<void> _sessionModelRestore;
  DesktopGatewayClient? _desktopGateway;
  GatewayTurnApplicationSession? _turnApplicationSession;
  Object? _turnApplicationAsyncEventRegistration;
  Object? _turnApplicationSettledRegistration;
  Object? _turnApplicationBoundRegistration;
  DesktopConnectionState _desktopConnectionState =
      DesktopConnectionState.disconnected;
  bool _appInBackground = false;

  // Chat sending state
  final _textController = TextEditingController();
  int _composerRevision = 0;
  final _imagePicker = ImagePicker();
  final List<AttachmentDraft> _attachmentDrafts = [];
  String? _sessionModel;
  String? _sessionProvider;
  String? _sessionReasoningEffort;
  String? _projectName;
  String? _storedSessionId;
  int _projectNameRefreshGeneration = 0;
  bool _sessionModelOverride = false;
  bool _loadingModelOptions = false;
  bool _changingModel = false;
  bool _sending = false;
  bool _streaming = false;
  GatewayTurnStatus? _gatewayTurnStatus;
  _ResponseTransport _activeResponseTransport = _ResponseTransport.none;
  String? _activeClientTurnId;
  bool _recoveringTurn = false;
  bool _legacyTransportFallback = false;
  bool _stockGatewayFallback = false;
  bool _legacyHistoryResyncPending = false;
  bool _legacyHistoryResyncing = false;

  /// Set when a submitted legacy prompt loses its socket before completion.
  /// The server keeps the turn running detached, so authoritative history is
  /// polled until a terminal row beyond the pre-submit durable ID appears.
  bool _pendingReattachResync = false;
  bool _reattachResyncing = false;
  bool _reattachImmediateRetryRequested = false;
  bool _legacyDesktopPromptSubmitted = false;
  int _reattachGeneration = 0;
  int _reattachMessageIdWatermark = 0;
  int _reattachLegacyTerminalWatermark = 0;
  int _reattachRetryAttempt = 0;
  Timer? _reattachRetryTimer;
  static const _reattachRetryBaseDelay = Duration(milliseconds: 500);
  static const _reattachRetryMaxDelay = Duration(seconds: 30);

  /// Backstop for [releaseClientAfterStreamSettles] on the dispose path: a
  /// stream that never settles must not hold this screen's HTTP client open
  /// for the life of the process.
  static const _detachedStreamCloseDeadline = Duration(minutes: 30);

  /// Bumped every time authoritative history replaces [_messages]. The submit
  /// catch path compares it against the value captured at send time to tell
  /// whether a reattach resync already made the server history
  /// authoritative before it restores the composer.
  int _historyGeneration = 0;
  int _responseGeneration = 0;
  bool _deferredHistoryRefreshPending = false;
  bool _deferredHistoryRefreshing = false;
  bool _stopResponseInFlight = false;
  bool _approvalDialogOpen = false;
  bool _approvalRouteOpen = false;
  String? _activeApprovalServerRequestId;
  final Set<String> _cancelledInteractiveRequestIds = {};
  final List<_PendingSensitivePrompt> _sensitivePromptQueue = [];
  final Set<String> _expiredSensitivePromptIds = {};
  _PendingSensitivePrompt? _activeSensitivePrompt;
  bool _sensitivePromptRouteOpen = false;
  final List<_PendingClarifyPrompt> _clarifyPromptQueue = [];
  _PendingClarifyPrompt? _activeClarifyPrompt;
  bool _clarifyPromptRouteOpen = false;
  Route<bool>? _clarifyPromptRoute;
  bool _clarifyPromptClosing = false;

  /// Clarify prompts whose answer the user submitted from their own card.
  ///
  /// The batch transport locks one answer at a time and reports the remaining
  /// question ids while that answer is still in flight, so the reconcile sees
  /// the card's own question leave the pending set. Without this record it
  /// would close the card a second time, and that surplus pop takes the route
  /// underneath with it — the chat screen on the legacy transport, or the next
  /// question of the batch once its card is open — leaving the batch
  /// unanswerable until the chat is re-entered.
  final Set<String> _selfAnsweredClarifyIdentities = {};

  // Voice input / spoken replies
  final FlutterTts _flutterTts = FlutterTts();
  late final VoiceComposerController _voiceComposer;
  late final VoiceRecordingController _voiceRecording;
  DashboardClient? _voiceDashboard;
  bool _voiceReplyEnabled = true;
  bool _awaitingVoiceReply = false;
  String? _voiceStatus;
  String? _sttLocaleId;

  // Verbose mode
  bool _verboseMode = false;

  // Chat density (bubble geometry and sender labels)
  ChatDensity _chatDensity = chatDensitySelection.value;

  // Scroll management
  final _scrollController = ScrollController();
  final _scrollCoordinator = ChatScrollCoordinator();
  final _endAffordanceController = ChatEndAffordanceController();
  bool _streamFollowScheduled = false;
  bool _initialEndFrameScheduled = false;
  double? _initialEndLastExtent;
  int _initialEndStableFrames = 0;
  int _initialEndFramesRemaining = 0;
  static const _initialEndFrameBudget = 12;
  static const _requiredStableEndFrames = 2;
  static const _stableExtentTolerance = 0.5;
  static final Map<String, List<GatewayNotice>> _savedGatewayNotices = {};

  late final TurnNotificationService _turnNotifications;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _projectName = _normalisedProjectName(widget.projectName);
    _textController.addListener(_onComposerChanged);
    if (widget.initialComposerText case final shared?) {
      _textController.text = shared;
      _textController.selection = TextSelection.collapsed(
        offset: shared.length,
      );
    } else {
      // Restore this session's draft: leaving the chat must never lose it.
      final composerRevision = _composerRevision;
      final readDraft =
          widget.testComposerDraftReader ?? ComposerDraftStore.read;
      unawaited(
        readDraft(
          connectionId: widget.connection.id,
          sessionId: widget.session.id,
        ).then((draft) {
          if (!mounted || draft == null) return;
          // The user may have started typing while the read was in flight:
          // even if they cleared or sent that newer text, never resurrect the
          // older stored value just because the composer is empty again.
          if (_composerRevision != composerRevision ||
              _textController.text.isNotEmpty) {
            return;
          }
          _textController.text = draft;
          _textController.selection = TextSelection.collapsed(
            offset: draft.length,
          );
        }),
      );
    }
    _turnNotifications =
        widget.testTurnNotifications ?? TurnNotificationService.shared;
    unawaited(_turnNotifications.ensureInitialized());
    // A notification action that could not answer directly (the request is
    // owned by this screen's gateway, not the app-level controller) lands in
    // the shared store; consume it on mount and whenever it changes while
    // this chat is open — the already-mounted owner must observe it too.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _consumePendingNotificationApproval(),
    );
    pendingNotificationApprovals.addListener(
      _consumePendingNotificationApproval,
    );
    _client =
        widget.testApiClient ??
        ApiClient(
          baseUrl: widget.connection.baseUrl,
          apiKey: widget.connection.apiKey,
          pathPrefix: widget.connection.gatewayPrefix ?? '',
        );
    _gateway = GatewayChatClient(_client);
    _attachmentDraftService =
        widget.testAttachmentDraftService ?? AttachmentDraftService();
    _attachmentSendCoordinator = AttachmentDraftSendCoordinator(
      _attachmentDraftService,
    );
    _voiceComposer = VoiceComposerController(
      textController: _textController,
      adapter:
          widget.testVoiceComposerAdapter ?? SpeechToTextVoiceComposerAdapter(),
    )..addListener(_onVoiceComposerChanged);
    _voiceRecording = VoiceRecordingController(
      widget.testVoiceRecorder ??
          LocalVoiceRecorder('${widget.connection.id}:${widget.session.id}'),
    )..addListener(_onVoiceComposerChanged);
    unawaited(_voiceRecording.ready);

    _attachmentDrafts
      ..addAll(widget.initialAttachmentDrafts)
      ..addAll(widget.testInitialAttachmentDrafts);
    _gatewayNotices = List<GatewayNotice>.from(
      _savedGatewayNotices[_gatewayNoticeIdentity] ?? const [],
    );
    _chatModelStore = ChatModelOverrideStore.open();
    _sessionModelRestore = _restoreSessionModelOverride();
    final hasDashboardAuth =
        widget.connection.dashboardProxied ||
        (widget.connection.dashboardUsername?.trim().isNotEmpty == true &&
            widget.connection.dashboardPassword?.trim().isNotEmpty == true);
    if (widget.connection.desktopGatewayUrl?.trim().isNotEmpty == true ||
        hasDashboardAuth) {
      try {
        _desktopGateway = DesktopGatewayClient.fromConnection(
          widget.connection,
        );
        _desktopGateway!.setAsyncEventListener(_handleDesktopAsyncEvent);
        _desktopGateway!.setConnectionListener(_onDesktopConnectionChanged);
        _desktopGateway!.setSessionBoundListener(_onSessionBound);
        unawaited(_ensureDesktopSession());
      } on ArgumentError {
        // The regular mobile chat remains usable; selection surfaces the
        // actionable configuration error when Desktop attachments are needed.
        _desktopGateway = null;
      }
    }
    // Test seam: with no real gateway, hand the same handler to the test
    // hook so it can simulate reconnect transitions.
    widget.testDesktopConnectionHook?.handler = _onDesktopConnectionChanged;
    widget.testDesktopAsyncEventHook?.handler = (event) {
      _handleDesktopAsyncEvent(widget.session.id, event);
    };
    // The experimental recovery-v2 session.open contract carries no cwd.
    // Project drafts must use stock session.create(cwd), or the server files
    // them as unassigned even when their header names a Project.
    _turnApplicationSession =
        widget.testTurnApplicationSession ??
        (_desktopGateway != null &&
                shouldUseRecoveryV2ForSession(
                  widget.session,
                  projectWorkingDirectory: widget.projectWorkingDirectory,
                )
            ? widget.turnApplicationController?.sessionFor(widget.connection)
            : null);
    final turnApplicationSession = _turnApplicationSession;
    if (turnApplicationSession != null) {
      _turnApplicationAsyncEventRegistration = turnApplicationSession
          .setAsyncEventListener(widget.session.id, _handleDesktopAsyncEvent);
      _turnApplicationSettledRegistration = turnApplicationSession
          .setTurnSettledListener(widget.session.id, _onTurnSettled);
      _turnApplicationBoundRegistration = turnApplicationSession
          .setSessionBoundListener(widget.session.id, _onSessionBound);
    }
    unawaited(_refreshProjectName());
    unawaited(_initializeChat());
    _loadVerboseMode();
    _loadChatDensity();
    chatDensitySelection.addListener(_onChatDensityChanged);
    _initVoice();
    _recoverLostImage();
    _scrollController.addListener(_onScroll);
  }

  String get _connectionIdentity =>
      '${widget.connection.baseUrl}|'
      '${widget.connection.gatewayPrefix ?? ''}|'
      '${widget.connection.desktopGatewayUrl ?? ''}';

  String get _gatewayNoticeIdentity =>
      '$_connectionIdentity|${widget.session.id}';

  void _onComposerChanged() => _composerRevision += 1;

  String get _storedSessionKey =>
      _desktopGateway?.storedSessionKeyFor(widget.session.id) ??
      widget.testStoredSessionKey?.call(widget.session.id) ??
      widget.session.id;

  static String? _normalisedProjectName(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Refreshes the sticky header from the same server Projects tree used by
  /// the workspace. A response that does not yet contain a newly persisted
  /// chat is inconclusive and therefore keeps the navigation-time label.
  Future<void> _refreshProjectName() async {
    final loader = widget.testProjectOverviewLoader;
    final gateway = _desktopGateway;
    if (loader == null && gateway == null) return;

    final generation = ++_projectNameRefreshGeneration;
    try {
      final overview = await (loader?.call() ?? gateway!.projects.tree());
      if (!mounted || generation != _projectNameRefreshGeneration) return;
      final candidates = <String>[];
      void addCandidate(String? value) {
        final id = value?.trim() ?? '';
        if (id.isNotEmpty && !candidates.contains(id)) candidates.add(id);
      }

      // The stored id is the canonical identity once a draft has been bound.
      addCandidate(_storedSessionId);
      addCandidate(gateway?.storedSessionKeyFor(widget.session.id));
      addCandidate(widget.testStoredSessionKey?.call(widget.session.id));
      addCandidate(widget.session.id);

      final resolution = resolveChatProjectHeader(overview, candidates);
      if (!resolution.known || resolution.projectName == _projectName) return;
      setState(() => _projectName = resolution.projectName);
    } catch (_) {
      // Project metadata is additive. Chat and recovery remain usable when an
      // older gateway lacks projects.tree or the control socket is offline.
    }
  }

  void _onSessionBound(String localSessionId, String storedSessionId) {
    if (localSessionId != widget.session.id) return;
    _storedSessionId = storedSessionId;
    unawaited(_refreshProjectName());
  }

  Future<void> _restoreSessionModelOverride() async {
    final store = await _chatModelStore;
    final override = store.read(
      connectionIdentity: _connectionIdentity,
      sessionId: widget.session.id,
    );
    if (!mounted || override == null) return;
    setState(() {
      _sessionModel = override.model;
      _sessionProvider = override.provider;
      _sessionReasoningEffort = override.reasoningEffort;
      _sessionModelOverride = true;
    });
  }

  Future<void> _loadVerboseMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _verboseMode = prefs.getBool('verbose_mode') ?? false);
  }

  Future<void> _loadChatDensity() async {
    final prefs = await SharedPreferences.getInstance();
    final density = ChatDensityStore(prefs).read();
    if (!mounted || density == _chatDensity) return;
    setState(() => _chatDensity = density);
  }

  /// Settings can change the density while this chat is already mounted, so the
  /// selection is broadcast rather than read once per launch.
  void _onChatDensityChanged() {
    final density = chatDensitySelection.value;
    if (!mounted || density == _chatDensity) return;
    setState(() => _chatDensity = density);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chatDensitySelection.removeListener(_onChatDensityChanged);
    _projectNameRefreshGeneration += 1;
    pendingNotificationApprovals.removeListener(
      _consumePendingNotificationApproval,
    );
    _clearPendingReattachResync();
    widget.testDesktopConnectionHook?.handler = null;
    widget.testDesktopAsyncEventHook?.handler = null;
    _savedGatewayNotices[_gatewayNoticeIdentity] = List.unmodifiable(
      _gatewayNotices,
    );
    _voiceRecording
      ..removeListener(_onVoiceComposerChanged)
      ..dispose();
    _voiceDashboard?.close();
    _voiceComposer
      ..removeListener(_onVoiceComposerChanged)
      ..dispose();
    if (widget.testVoiceComposerAdapter == null) {
      _flutterTts.stop();
    }
    for (final timer in _notificationTimers.values) {
      timer.cancel();
    }
    _releaseClientAfterStreamSettles();
    unawaited(
      _attachmentDraftService.removeAll(
        List<AttachmentDraft>.from(_attachmentDrafts),
      ),
    );
    _desktopGateway?.setAsyncEventListener(null);
    _desktopGateway?.setSessionBoundListener(null);
    _desktopGateway?.close();
    final registration = _turnApplicationAsyncEventRegistration;
    if (registration != null) {
      _turnApplicationSession?.removeAsyncEventListener(
        widget.session.id,
        registration,
      );
    }
    final settledRegistration = _turnApplicationSettledRegistration;
    if (settledRegistration != null) {
      _turnApplicationSession?.removeTurnSettledListener(
        widget.session.id,
        settledRegistration,
      );
    }
    final boundRegistration = _turnApplicationBoundRegistration;
    if (boundRegistration != null) {
      _turnApplicationSession?.removeSessionBoundListener(
        widget.session.id,
        boundRegistration,
      );
    }
    unawaited(
      ComposerDraftStore.save(
        connectionId: widget.connection.id,
        sessionId: widget.session.id,
        text: _textController.text,
      ),
    );
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Closes this screen's HTTP client — but not while a turn is streaming.
  ///
  /// Closing the client aborts the in-flight SSE request, and the API server
  /// treats a client disconnect as an agent interrupt ("SSE client
  /// disconnected" → hard interrupt): the turn and every tool call it had made
  /// were destroyed server-side, so leaving the chat mid-turn came back as a
  /// bare `Operation interrupted.` with the work gone. Detach instead — the turn
  /// finishes on the server, where the transcript is persisted anyway, and the
  /// client closes as soon as the stream settles.
  void _releaseClientAfterStreamSettles() {
    final client = _client;
    final gateway = _gateway;
    if (!gateway.isStreaming) {
      client.close();
      return;
    }
    unawaited(
      gateway
          .whenStreamSettles()
          // Backstop: a stream that never settles must not hold the client
          // open for the life of the process.
          .timeout(_detachedStreamCloseDeadline, onTimeout: () {})
          .whenComplete(client.close),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _appInBackground = true;
      unawaited(_voiceRecording.background());
      // Persist the draft on the way out: a process kill must not lose it.
      unawaited(
        ComposerDraftStore.save(
          connectionId: widget.connection.id,
          sessionId: widget.session.id,
          text: _textController.text,
        ),
      );
      _pauseReattachRetry();
      if (_legacyTransportFallback && (_sending || _streaming)) {
        _legacyHistoryResyncPending = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      _voiceRecording.foreground();
      unawaited(_turnNotifications.cancelAll());
      if (_pendingReattachResync) {
        // The transport's autonomous loop is normally enough, but an app
        // resume is also an explicit recovery signal. Force the session path
        // to restart a socket immediately after any prolonged offline period;
        // the history retry itself remains gated on the connected callback.
        unawaited(_ensureDesktopSession());
        _requestImmediateReattachResync();
      } else if (_desktopGateway != null) {
        unawaited(_ensureDesktopSession());
      }
      if (_legacyTransportFallback) {
        unawaited(_resyncLegacyHistoryAfterResume());
      } else if (_turnApplicationSession != null) {
        unawaited(_recoverPendingTurn());
      }
    }
  }

  Future<void> _initializeChat() async {
    await _fetchMessages();
    if (!mounted) return;
    await _recoverPendingTurn(allowLegacyFallback: true);
  }

  /// Desktop gateway connection-state transitions.
  ///
  /// A deliberate connection switch or a dropped socket detaches the WS
  /// mid-turn. The gateway no longer cancels the running turn at the
  /// orphan-reap grace (activity-staleness gate); it completes detached
  /// and the client re-resumes the stored session on the fresh socket.
  /// Say so — the bare silence read as "your reply was lost" (issue
  /// #94196's `Operation interrupted.` UX) — and remember the drop so the
  /// eventual `connected` transition actually re-binds and refetches.
  void _onDesktopConnectionChanged(DesktopConnectionState state) {
    if (!mounted) return;
    final previousState = _desktopConnectionState;
    final connectionChanged = previousState != state;
    final lostSubmittedLegacyPrompt =
        previousState == DesktopConnectionState.connected &&
        _legacyDesktopPromptSubmitted &&
        (state == DesktopConnectionState.reconnecting ||
            state == DesktopConnectionState.disconnected);
    if (lostSubmittedLegacyPrompt) {
      final newlyPending = !_pendingReattachResync;
      _markPendingReattachResync();
      if (newlyPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context
                  .l10n
                  .connection_switched_the_running_reply_continues_on_the_server_and,
            ),
            persist: false,
          ),
        );
      }
    }
    if (state != DesktopConnectionState.connected) _pauseReattachRetry();
    setState(() => _desktopConnectionState = state);
    if (connectionChanged && state == DesktopConnectionState.connected) {
      unawaited(_refreshProjectName());
      _requestImmediateReattachResync();
      // A notification tap that landed before this route-local gateway was
      // ready stays pending; retry it now that the connection is back.
      _consumePendingNotificationApproval();
    }
  }

  Future<void> _ensureDesktopSession() async {
    if (!shouldEstablishLegacyDesktopSession(
      widget.session,
      legacyTransportFallback: _legacyTransportFallback,
    )) {
      return;
    }
    final gateway = _desktopGateway;
    widget.testDesktopSessionEnsured?.call();
    if (gateway == null) {
      unawaited(_refreshProjectName());
      return;
    }
    try {
      await gateway.ensureSession(
        widget.session.id,
        workingDirectory: widget.projectWorkingDirectory,
      );
    } catch (_) {
      // The composer remains available. The next send retries with a fresh
      // single-use ticket and surfaces an actionable error if it still fails.
      return;
    }
    unawaited(_refreshProjectName());
  }

  void _editAndResend(String text) {
    _textController
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
    FocusScope.of(context).nextFocus();
  }

  Future<void> _retryPrompt(String text) async {
    if (_sending ||
        _streaming ||
        _pendingReattachResync ||
        text.trim().isEmpty) {
      return;
    }
    _editAndResend(text);
    await _sendMessage();
  }

  Future<void> _exportConversation() async {
    final buffer = StringBuffer('# ${widget.session.title}\n\n');
    for (final message in _messages) {
      final role = message['role']?.toString();
      if (role != 'user' && role != 'assistant' && role != 'agent') continue;
      final content = stripToolResultText(
        messageContentToText(message['content']),
      ).trim();
      if (content.isEmpty) continue;
      buffer
        ..writeln(
          role == 'user'
              ? context.l10n.you_heading
              : context.l10n.hermes_heading,
        )
        ..writeln()
        ..writeln(content)
        ..writeln();
    }
    await SharePlus.instance.share(
      ShareParams(
        subject: widget.session.title,
        text: buffer.toString().trim(),
      ),
    );
  }

  Future<void> _initVoice({bool requestSpeechPermission = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceName = prefs.getString('voice_name');
      final voiceLocale = prefs.getString('voice_locale');

      if (widget.testVoiceComposerAdapter == null) {
        if (voiceName != null && voiceName.isNotEmpty) {
          if (voiceName == voiceLocale) {
            await _flutterTts.setLanguage(voiceName);
          } else {
            await _flutterTts.setVoice({
              'name': voiceName,
              'locale': voiceLocale ?? '',
            });
          }
          _sttLocaleId = voiceLocale?.replaceAll('-', '_');
        } else {
          _sttLocaleId = null;
        }
        await _flutterTts.setSpeechRate(0.48);
        await _flutterTts.setVolume(1.0);
        await _flutterTts.setPitch(1.0);
      } else {
        _sttLocaleId = voiceLocale?.replaceAll('-', '_');
      }

      await _voiceComposer.initialize(
        requestPermission: requestSpeechPermission,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _voiceStatus = context.l10n.voice_setup_failed(e));
    }
  }

  Future<void> _startVoiceInput() async {
    if (_streaming ||
        _sending ||
        _transcriptLoadBlocksComposer ||
        _pendingReattachResync) {
      return;
    }
    if (widget.testVoiceComposerAdapter == null) {
      await _flutterTts.stop();
    }
    if (!mounted) return;
    final started = await _voiceComposer.start(localeId: _sttLocaleId);
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _voiceComposer.status ??
                _voiceStatus ??
                context.l10n.speech_recognition_is_unavailable,
          ),
        ),
      );
    }
  }

  void _onVoiceComposerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _speakAssistantText(String text) async {
    if (!_voiceReplyEnabled) return;
    await _readAssistantText(text);
  }

  Future<void> _readAssistantText(String text, {bool announce = false}) async {
    final spokenText = text.trim();
    if (spokenText.isEmpty) return;
    if (announce && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(context.l10n.reading_response_aloud),
            duration: Duration(seconds: 2),
          ),
        );
    }
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(spokenText);
    } catch (_) {
      if (!announce || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.read_aloud_is_unavailable_on_this_device,
            ),
            duration: Duration(seconds: 3),
          ),
        );
    }
  }

  void _onTurnSettled(GatewayTurnRecoveryState state) {
    if (!mounted || !_appInBackground) return;
    final turnId = state.turnId ?? state.clientTurnId;
    final completed =
        !state.isFailClosed &&
        state.status == GatewayRecoveryTurnStatus.completed;
    final kind = completed
        ? HermesNotificationKind.turnDone
        : HermesNotificationKind.turnError;
    if (!notificationKindEnabled(kind)) return;
    final summary = completed
        ? context.l10n.response_ready
        : context.l10n.turn_failed;
    unawaited(
      completed
          ? _turnNotifications.showTurnCompleted(
              title: context.l10n.hermes_response_ready,
              turnSummary: '${widget.session.title}: $summary',
              turnId: turnId,
              sessionId: widget.session.id,
              connectionId: widget.connection.id,
            )
          : _turnNotifications.showTurnFailed(
              title: context.l10n.the_turn_failed,
              turnSummary: '${widget.session.title}: $summary',
              turnId: turnId,
              sessionId: widget.session.id,
              connectionId: widget.connection.id,
            ),
    );
  }

  /// Mirrors a blocking approval to a native notification (with approve/deny
  /// buttons) while the app is in the background — the one prompt class that
  /// must not wait for the user to come back on their own.
  void _notifyApprovalRequest(
    GatewayApprovalRequest request,
    String? serverRequestId,
  ) {
    if (!_appInBackground || serverRequestId == null) return;
    final command = request.command.trim();
    final body = command.isEmpty
        ? request.description.trim()
        : (command.length > 140 ? '${command.substring(0, 140)}…' : command);
    unawaited(
      _turnNotifications.showKind(
        kind: HermesNotificationKind.approval,
        title: '${context.l10n.approval_needed} — ${widget.session.title}',
        body: body,
        eventId: serverRequestId,
        sessionId: widget.session.id,
        connectionId: widget.connection.id,
        actions: [
          TurnNotificationAction(id: 'approve', label: context.l10n.approve),
          TurnNotificationAction(id: 'reject', label: context.l10n.deny),
        ],
        payload: jsonEncode({
          'sessionId': widget.session.id,
          'connectionId': widget.connection.id,
          'requestId': serverRequestId,
        }),
      ),
    );
  }

  /// Mirrors a clarify/sudo/secret prompt to a native notification while the
  /// app is in the background. The dialog itself stays queued for the return.
  void _notifyInputRequest({required String eventId, required String body}) {
    if (!_appInBackground) return;
    final trimmed = body.trim();
    unawaited(
      _turnNotifications.showKind(
        kind: HermesNotificationKind.input,
        title: '${context.l10n.input_needed} — ${widget.session.title}',
        body: trimmed.length > 140 ? '${trimmed.substring(0, 140)}…' : trimmed,
        eventId: eventId,
        sessionId: widget.session.id,
        connectionId: widget.connection.id,
        payload: jsonEncode({
          'sessionId': widget.session.id,
          'connectionId': widget.connection.id,
        }),
      ),
    );
  }

  /// Gateway notices mirror the desktop split: credit state changes are the
  /// only native notice class (credits.depleted / credits.restored); every
  /// other notice posts as a plugin notice while the app is away.
  void _notifyGatewayNotice(GatewayNotification notification) {
    if (!_appInBackground) return;
    final isCredits =
        notification.key == 'credits.depleted' ||
        notification.key == 'credits.restored';
    unawaited(
      _turnNotifications.showKind(
        kind: isCredits
            ? HermesNotificationKind.credits
            : HermesNotificationKind.plugin,
        title: isCredits
            ? context.l10n.credit_notifications
            : context.l10n.plugin_notifications,
        body: notification.text,
        eventId: notification.key,
        sessionId: widget.session.id,
        connectionId: widget.connection.id,
        payload: jsonEncode({
          'sessionId': widget.session.id,
          'connectionId': widget.connection.id,
        }),
      ),
    );
  }

  /// Background task completions and review summaries arrive as GatewayNotice
  /// insights; mirror them to a native notification while the app is away —
  /// completions as background work, reviews as gateway notices.
  void _notifyBackgroundNotice(GatewayNotice notice) {
    if (!_appInBackground) return;
    final isBackground = notice.kind == GatewayNoticeKind.background;
    unawaited(
      _turnNotifications.showKind(
        kind: isBackground
            ? HermesNotificationKind.backgroundDone
            : HermesNotificationKind.plugin,
        title: isBackground
            ? context.l10n.background_task_completed
            : context.l10n.plugin_notifications,
        body: notice.text,
        eventId: notice.identity,
        sessionId: widget.session.id,
        connectionId: widget.connection.id,
        payload: jsonEncode({
          'sessionId': widget.session.id,
          'connectionId': widget.connection.id,
        }),
      ),
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _syncEndAffordance(_scrollController.position);
  }

  bool _isNearEnd([ScrollMetrics? metrics]) {
    if (metrics == null && !_scrollController.hasClients) return true;
    final current = metrics ?? _scrollController.position;
    return _scrollCoordinator.isNearEnd(
      pixels: current.pixels,
      maxScrollExtent: current.maxScrollExtent,
    );
  }

  void _syncEndAffordance(
    ScrollMetrics metrics, {
    bool clearUnreadAtEnd = true,
  }) {
    final changed = _endAffordanceController.updatePosition(
      pixels: metrics.pixels,
      maxScrollExtent: metrics.maxScrollExtent,
      clearUnreadAtEnd: clearUnreadAtEnd,
    );
    if (changed && mounted) setState(() {});
  }

  void _registerMaterializedAssistantMessage() {
    _endAffordanceController.registerMaterializedMessage(
      willFollow: _scrollCoordinator.shouldFollowStreaming,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final isDirectUserScroll =
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null);
    if (isDirectUserScroll) {
      _scrollCoordinator.updateFromUserScroll(
        isNearEnd: _isNearEnd(notification.metrics),
      );
    }
    return false;
  }

  void _applyScrollTarget(ChatScrollTarget target) {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(maxExtent);
    _syncEndAffordance(_scrollController.position);
  }

  void _goToEnd() {
    _applyScrollTarget(const ChatScrollTarget.end());
  }

  void _scheduleScrollTarget(ChatScrollTarget? target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (target != null) {
        _applyScrollTarget(target);
      } else if (_scrollController.hasClients) {
        _syncEndAffordance(_scrollController.position, clearUnreadAtEnd: false);
      }
    });
  }

  void _scheduleStreamingFollow() {
    if (_streamFollowScheduled) return;
    _streamFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _streamFollowScheduled = false;
      if (!mounted) return;
      final target = _scrollCoordinator.streamingContentChanged();
      if (target != null) {
        _applyScrollTarget(target);
      } else if (_scrollController.hasClients) {
        _syncEndAffordance(_scrollController.position, clearUnreadAtEnd: false);
      }
    });
  }

  void _scheduleInitialEndAlignment() {
    if (_scrollCoordinator.consumeInitialEndAlignment() == null) {
      _scheduleScrollTarget(null);
      return;
    }
    _initialEndFramesRemaining = _initialEndFrameBudget;
    _initialEndStableFrames = 0;
    _initialEndLastExtent = null;
    _scheduleNextInitialEndFrame();
  }

  void _scheduleNextInitialEndFrame() {
    if (_initialEndFrameScheduled || _initialEndFramesRemaining <= 0) return;
    _initialEndFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialEndFrameScheduled = false;
      if (!mounted || _initialEndFramesRemaining <= 0) return;
      _initialEndFramesRemaining -= 1;

      if (!_scrollController.hasClients) {
        _scheduleNextInitialEndFrame();
        return;
      }

      final extent = _scrollController.position.maxScrollExtent;
      final previousExtent = _initialEndLastExtent;
      final extentIsStable =
          previousExtent != null &&
          (extent - previousExtent).abs() <= _stableExtentTolerance;
      _applyScrollTarget(const ChatScrollTarget.end());
      _initialEndStableFrames = extentIsStable
          ? _initialEndStableFrames + 1
          : 0;
      _initialEndLastExtent = extent;

      if (_initialEndStableFrames >= _requiredStableEndFrames ||
          _initialEndFramesRemaining <= 0) {
        return;
      }
      _scheduleNextInitialEndFrame();
    });
  }

  Future<void> _fetchMessages({String? sessionId}) async {
    if (_pendingReattachResync && sessionId == null) return;
    final responseGeneration = _responseGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final batch = await _historyWindow.fetchRecent(
        (offset) => _client.getMessages(
          sessionId ?? widget.session.id,
          limit: ChatHistoryWindow.pageSize,
          offset: offset,
          latest: true,
        ),
        shouldContinue: () =>
            mounted && responseGeneration == _responseGeneration,
      );
      if (!mounted) return;
      // A remote turn can start while history is still hydrating. Its local
      // optimistic messages and stream are newer than this response, so never
      // replace them with a stale transcript page.
      if (responseGeneration != _responseGeneration) {
        setState(() => _loading = false);
        _deferHistoryRefresh();
        return;
      }
      _historyWindow.acceptRecent(batch);
      final messages = _historyWindow.rows;
      _extractToolMessages(messages);
      final completedPendingReattach =
          _pendingReattachResync &&
          _hasTerminalAssistantAfterWatermark(messages);
      setState(() {
        _messages = messages;
        // Server history is now authoritative; a submit catch that starts
        // after this point must not clobber it with composer-restore.
        _historyGeneration++;
        _loading = false;
      });
      _scheduleInitialEndAlignment();
      if (completedPendingReattach) _clearPendingReattachResync();
    } catch (e) {
      if (!mounted) return;
      if (responseGeneration != _responseGeneration) {
        setState(() => _loading = false);
        _deferHistoryRefresh();
        return;
      }
      final errStr = e.toString();
      if (errStr.contains('404') || errStr.contains('not found')) {
        if (_pendingReattachResync) {
          setState(() => _loading = false);
          return;
        }
        if (_messages.isNotEmpty) {
          setState(() => _loading = false);
          return;
        }
        setState(() {
          _messages = [];
          _historyGeneration++;
          _loading = false;
        });
        _scheduleInitialEndAlignment();
        return;
      }
      setState(() {
        _error = errStr;
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _getRecentMessages(String sessionId) =>
      _client.getMessages(
        sessionId,
        limit: ChatHistoryWindow.pageSize,
        latest: true,
      );

  void _acceptRecentMessages(List<Map<String, dynamic>> recent) {
    _historyWindow.acceptRecent(
      ChatHistoryPageBatch(
        recent,
        recent.length,
        recent.length == ChatHistoryWindow.pageSize,
      ),
    );
    _extractToolMessages(_historyWindow.rows);
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_historyWindow.hasOlder) return;
    final responseGeneration = _responseGeneration;
    final offset = _historyWindow.olderOffset;
    final sessionId = _storedSessionKey;
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    setState(() => _loadingOlder = true);
    try {
      final older = await _client.getMessages(
        sessionId,
        limit: ChatHistoryWindow.pageSize,
        offset: offset,
        latest: true,
      );
      if (!mounted ||
          sessionId != _storedSessionKey ||
          responseGeneration != _responseGeneration ||
          _sending ||
          _streaming) {
        return;
      }
      _historyWindow.acceptOlder(older);
      _extractToolMessages(_historyWindow.rows);
      setState(() => _messages = _historyWindow.rows);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final delta = _scrollController.position.maxScrollExtent - oldExtent;
        _scrollController.jumpTo(
          (oldPixels + delta).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
      });
    } catch (_) {
      // Leave the control available for a retry without hiding loaded rows.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// A remote turn may start while the initial bounded transcript request is
  /// still in flight. Its stale response must not overwrite optimistic or
  /// streamed messages, but dropping it permanently would leave the existing
  /// transcript blank. Refresh once the turn is idle, using the authoritative
  /// post-turn page instead.
  void _deferHistoryRefresh() {
    _deferredHistoryRefreshPending = true;
    unawaited(_refreshDeferredHistoryIfIdle());
  }

  Future<void> _refreshDeferredHistoryIfIdle() async {
    if (!mounted ||
        !_deferredHistoryRefreshPending ||
        _deferredHistoryRefreshing ||
        _sending ||
        _streaming ||
        _stopResponseInFlight ||
        _pendingReattachResync) {
      return;
    }
    _deferredHistoryRefreshPending = false;
    _deferredHistoryRefreshing = true;
    final responseGeneration = _responseGeneration;
    var retryAfterSettlement = false;
    try {
      final messages = await _getRecentMessages(_storedSessionKey);
      if (!mounted) return;
      if (responseGeneration != _responseGeneration ||
          _sending ||
          _streaming ||
          _stopResponseInFlight ||
          _pendingReattachResync) {
        _deferredHistoryRefreshPending = true;
        retryAfterSettlement = true;
        return;
      }
      _acceptRecentMessages(messages);
      setState(() {
        _messages = _historyWindow.rows;
        _historyGeneration += 1;
        _error = null;
      });
      _scheduleInitialEndAlignment();
    } catch (_) {
      // Keep the refresh pending. A later terminal/rollback transition can
      // retry without turning background hydration into a composer blocker.
      _deferredHistoryRefreshPending = true;
    } finally {
      _deferredHistoryRefreshing = false;
      if (retryAfterSettlement &&
          mounted &&
          !_sending &&
          !_streaming &&
          !_stopResponseInFlight &&
          !_pendingReattachResync) {
        unawaited(_refreshDeferredHistoryIfIdle());
      }
    }
  }

  /// Reattach resync: the socket came back after a mid-turn drop. Re-bind
  /// the session on the fresh socket (single-flights with the client's own
  /// reconnect rebind) and refetch history so a reply that completed
  /// server-side while the socket was down lands in the transcript.
  ///
  /// Two production-ordering facts shape this:
  /// - WsClient rejects every pending RPC the instant the socket closes,
  ///   so the submit catch fires BEFORE the reconnect — the composer may
  ///   already be restored and the optimistic turn stripped by the time
  ///   this runs. The detached server turn may also still be settling, so
  ///   a single immediate fetch can read history that lacks the reply.
  ///   Retry with capped exponential backoff until authoritative terminal
  ///   evidence lands; there is no attempt-count deadline.
  /// - The watermark is NOT a list index, length, or assistant count: stock
  ///   `prompt.submit` persists the user row SYNCHRONOUSLY before the
  ///   model worker starts, so the first refetch after the optimistic turn
  ///   was stripped can grow by exactly one — the user row alone. Waiting
  ///   on length would then end the resync while the assistant reply is
  ///   still detached and in flight, with no listener or retry left to
  ///   ever surface it. The endpoint also returns a capped latest-history
  ///   window, whose length and role counts can remain constant as old rows
  ///   roll off. The authoritative signal is therefore a terminal assistant
  ///   row (role assistant/agent, no tool_calls) with a durable numeric row
  ///   ID beyond the highest ID present before the drop.
  /// - Retry timers pause while disconnected or backgrounded and resume
  ///   immediately on reconnect/resume. Delay is capped at 30 seconds, but
  ///   the recovery itself remains pending until terminal evidence arrives.
  /// - A newly created stock session lives in the DB under the gateway-
  ///   minted STORED key, not the mobile session id (the mobile id never
  ///   survives into gateway-side lookups). Fetching by `widget.session.id`
  ///   404s and would wipe the transcript, so the refetch targets
  ///   `storedSessionKeyFor()` after the rebind, falling back to the
  ///   mobile id only when no stored binding exists.
  /// - A 404 here NEVER clears the transcript: it means the stored row
  ///   isn't readable yet (turn still settling), not that the chat is
  ///   empty. Only a successful fetch replaces `_messages`.
  static int? _messageRowId(Map<String, dynamic> message) {
    final raw = message['id'];
    if (raw is int) return raw;
    if (raw is num && raw.isFinite && raw == raw.truncate()) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString() ?? '');
  }

  static int _highestMessageRowId(Iterable<Map<String, dynamic>> messages) {
    var highest = 0;
    for (final message in messages) {
      final id = _messageRowId(message);
      if (id != null && id > highest) highest = id;
    }
    return highest;
  }

  static bool _isTerminalAssistant(Map<String, dynamic> message) {
    final role = message['role'];
    if (role != 'assistant' && role != 'agent') return false;
    final toolCalls = message['tool_calls'];
    return toolCalls is! List || toolCalls.isEmpty;
  }

  static int _legacyTerminalCount(
    Iterable<Map<String, dynamic>> messages,
  ) => messages.where((message) {
    if (_messageRowId(message) != null || !_isTerminalAssistant(message)) {
      return false;
    }
    // Exclude the local optimistic assistant placeholder captured at detach.
    return message['content']?.toString().isNotEmpty ?? false;
  }).length;

  bool _hasTerminalAssistantAfterWatermark(
    Iterable<Map<String, dynamic>> messages,
  ) {
    var legacyTerminalCount = 0;
    for (final message in messages) {
      if (!_isTerminalAssistant(message)) continue;
      final id = _messageRowId(message);
      if (id != null) {
        if (id > _reattachMessageIdWatermark) return true;
      } else if (message['content']?.toString().isNotEmpty ?? false) {
        legacyTerminalCount += 1;
      }
    }
    // Conservative fallback for legacy gateways that omit durable row IDs.
    // It may retry longer under capped-window rollover, but never accepts an
    // old terminal row or a tool-call intermediate as fresh completion.
    return legacyTerminalCount > _reattachLegacyTerminalWatermark;
  }

  void _markPendingReattachResync() {
    if (_pendingReattachResync) return;
    _reattachRetryTimer?.cancel();
    _reattachRetryTimer = null;
    _pendingReattachResync = true;
    _reattachGeneration += 1;
    _reattachMessageIdWatermark = _highestMessageRowId(_messages);
    _reattachLegacyTerminalWatermark = _legacyTerminalCount(_messages);
    _reattachRetryAttempt = 0;
    _reattachImmediateRetryRequested = false;
  }

  void _pauseReattachRetry() {
    _reattachRetryTimer?.cancel();
    _reattachRetryTimer = null;
    _reattachImmediateRetryRequested = false;
  }

  void _clearPendingReattachResync() {
    _pauseReattachRetry();
    _pendingReattachResync = false;
    _legacyDesktopPromptSubmitted = false;
    _reattachMessageIdWatermark = 0;
    _reattachLegacyTerminalWatermark = 0;
    _reattachRetryAttempt = 0;
    _reattachGeneration += 1;
  }

  bool get _canRunReattachResync =>
      mounted &&
      _pendingReattachResync &&
      !_appInBackground &&
      _desktopConnectionState == DesktopConnectionState.connected;

  Duration _nextReattachRetryDelay() {
    var milliseconds = _reattachRetryBaseDelay.inMilliseconds;
    for (var i = 0; i < _reattachRetryAttempt; i += 1) {
      milliseconds *= 2;
      if (milliseconds >= _reattachRetryMaxDelay.inMilliseconds) {
        milliseconds = _reattachRetryMaxDelay.inMilliseconds;
        break;
      }
    }
    _reattachRetryAttempt += 1;
    return Duration(milliseconds: milliseconds);
  }

  void _scheduleReattachRetry(int generation) {
    if (!_canRunReattachResync || generation != _reattachGeneration) return;
    _reattachRetryTimer?.cancel();
    _reattachRetryTimer = Timer(_nextReattachRetryDelay(), () {
      _reattachRetryTimer = null;
      if (generation != _reattachGeneration) return;
      _requestImmediateReattachResync();
    });
  }

  void _requestImmediateReattachResync() {
    if (!_canRunReattachResync) return;
    _reattachRetryTimer?.cancel();
    _reattachRetryTimer = null;
    if (_reattachResyncing) {
      _reattachImmediateRetryRequested = true;
      return;
    }
    unawaited(_resyncAfterReattach(_reattachGeneration));
  }

  Future<void> _resyncAfterReattach(int generation) async {
    if (_reattachResyncing ||
        !_canRunReattachResync ||
        generation != _reattachGeneration) {
      return;
    }
    _reattachResyncing = true;
    _reattachImmediateRetryRequested = false;
    try {
      await _ensureDesktopSession();
      if (!_canRunReattachResync || generation != _reattachGeneration) return;
      final messages = await _getRecentMessages(_storedSessionKey);
      if (!_canRunReattachResync || generation != _reattachGeneration) return;
      final completed = _hasTerminalAssistantAfterWatermark(messages);
      _acceptRecentMessages(messages);
      setState(() {
        _messages = _historyWindow.rows;
        _historyGeneration += 1;
        _loading = false;
        _error = null;
      });
      _scheduleInitialEndAlignment();
      if (completed) _clearPendingReattachResync();
    } catch (_) {
      // A temporary 404 or transport failure is not an empty transcript and
      // not terminal turn evidence. Keep the current UI and retry later.
      if (mounted && generation == _reattachGeneration) {
        setState(() => _loading = false);
      }
    } finally {
      _reattachResyncing = false;
      if (_canRunReattachResync) {
        // A terminal event can clear generation A while its history request is
        // still in flight, then a later turn can create generation B. Hand the
        // single-flight slot directly to B instead of discarding its queued
        // reconnect request when A finally unwinds.
        if (generation != _reattachGeneration ||
            _reattachImmediateRetryRequested) {
          _reattachImmediateRetryRequested = false;
          _requestImmediateReattachResync();
        } else {
          _scheduleReattachRetry(generation);
        }
      }
    }
  }

  Future<void> _resyncLegacyHistoryAfterResume() async {
    if (!mounted ||
        !_legacyTransportFallback ||
        !_legacyHistoryResyncPending ||
        _appInBackground ||
        _legacyHistoryResyncing ||
        _loading ||
        _sending ||
        _streaming) {
      return;
    }

    _legacyHistoryResyncing = true;
    try {
      final messages = await _getRecentMessages(widget.session.id);
      if (!mounted || _appInBackground) return;
      _acceptRecentMessages(messages);
      setState(() {
        _messages = _historyWindow.rows;
        _legacyHistoryResyncPending = false;
      });
      _scheduleInitialEndAlignment();
    } catch (_) {
      // Keep the pending watermark so the next resume can retry. The composer
      // remains usable and the normal screen reload path still fetches history.
    } finally {
      _legacyHistoryResyncing = false;
    }
  }

  Future<void> _recoverPendingTurn({bool allowLegacyFallback = false}) async {
    final turnSession = _turnApplicationSession;
    if (turnSession == null || _recoveringTurn || _legacyTransportFallback) {
      return;
    }
    _recoveringTurn = true;
    if (mounted && !_streaming) {
      setState(() {
        _sending = true;
        _gatewayTurnStatus = GatewayTurnStatus(
          kind: 'recovery',
          text: context.l10n.recovering_hermes,
        );
      });
    }
    try {
      final states = await turnSession.recoverPending(
        widget.session.id,
        onState: _applyGatewayTurnState,
      );
      if (!mounted) return;
      for (final state in states) {
        _applyGatewayTurnState(state);
      }
      if (states.isEmpty && _activeClientTurnId == null) {
        setState(() {
          _sending = false;
          _gatewayTurnStatus = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      final fallback = classifyTurnRecoveryFailure(
        error,
        allowLegacyFallback: allowLegacyFallback,
      );
      if (fallback == TurnRecoveryFallback.legacyTransport) {
        setState(() {
          _legacyTransportFallback = true;
          _stockGatewayFallback = turnRecoveryFailureIsStockGateway(error);
          _sending = false;
          _streaming = false;
          _gatewayTurnStatus = null;
          _activeResponseTransport = _ResponseTransport.none;
        });
        return;
      }
      setState(() {
        _gatewayTurnStatus = GatewayTurnStatus(
          kind: 'recovery',
          text: context.l10n.hermes_recovery_is_unavailable(error),
        );
      });
    } finally {
      _recoveringTurn = false;
    }
  }

  void _applyGatewayTurnState(GatewayTurnRecoveryState state) {
    if (!mounted) return;
    final projection = GatewayTurnUiProjection.fromState(state);
    final messageIndex = _gatewayAssistantMessageIndex(projection);
    final shouldCreateMessage =
        messageIndex == null &&
        (projection.hasAssistantMaterial || projection.isActive);
    final previousText = messageIndex == null
        ? ''
        : _messages[messageIndex]['content']?.toString() ?? '';
    final nextText = projection.assistantText;
    final materialized = previousText.isEmpty && nextText.isNotEmpty;
    final speakTerminalResponse =
        projection.isTerminal &&
        !projection.isFailClosed &&
        _awaitingVoiceReply &&
        nextText.isNotEmpty;

    setState(() {
      final message = messageIndex == null
          ? <String, dynamic>{
              'role': 'assistant',
              'content': nextText,
              '_gateway_pending_response': projection.isActive,
            }
          : _messages[messageIndex];
      message
        ..['content'] = nextText
        ..['_gateway_client_turn_id'] = projection.clientTurnId
        ..['_gateway_message_id'] = projection.messageId
        ..['_gateway_last_seq'] = projection.lastSeq
        ..['_gateway_pending_response'] = projection.isActive;
      if (projection.finalMessageRef != null) {
        message['_gateway_final_message_ref'] = projection.finalMessageRef;
      }
      if (shouldCreateMessage) _messages.add(message);

      if (projection.isActive) {
        _activeClientTurnId = projection.clientTurnId;
        _activeResponseTransport = _ResponseTransport.desktop;
        _sending = true;
        _streaming = true;
        _gatewayTurnStatus = GatewayTurnStatus(
          kind: 'recovery',
          text: _gatewayRecoveryStatusText(projection.status),
        );
      } else if (_activeClientTurnId == null ||
          _activeClientTurnId == projection.clientTurnId) {
        _activeClientTurnId = null;
        _activeResponseTransport = _ResponseTransport.none;
        _sending = false;
        _streaming = false;
        _awaitingVoiceReply = false;
        _gatewayTurnStatus = projection.isFailClosed
            ? GatewayTurnStatus(
                kind: 'recovery_failed',
                text: context
                    .l10n
                    .hermes_stopped_recovery_safely_no_prompt_was_resent,
              )
            : null;
      }
    });
    if (materialized) _registerMaterializedAssistantMessage();
    if (speakTerminalResponse) unawaited(_speakAssistantText(nextText));
    if (projection.isActive) {
      _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());
      _scheduleStreamingFollow();
    } else {
      _scheduleScrollTarget(_scrollCoordinator.endStreaming());
      unawaited(_refreshDeferredHistoryIfIdle());
    }
  }

  int? _gatewayAssistantMessageIndex(GatewayTurnUiProjection projection) {
    for (var index = _messages.length - 1; index >= 0; index--) {
      final message = _messages[index];
      if (message['role'] != 'assistant') continue;
      if (message['_gateway_client_turn_id'] == projection.clientTurnId) {
        return index;
      }
      if (projection.messageId != null &&
          (message['_gateway_message_id'] == projection.messageId ||
              message['message_id'] == projection.messageId ||
              message['id'] == projection.messageId)) {
        return index;
      }
    }
    for (var index = _messages.length - 1; index >= 0; index--) {
      final message = _messages[index];
      if (message['role'] == 'assistant' &&
          message['_gateway_pending_response'] == true) {
        return index;
      }
    }
    if (projection.assistantText.isNotEmpty) {
      for (var index = _messages.length - 1; index >= 0; index--) {
        final message = _messages[index];
        if (message['role'] == 'assistant' &&
            message['content']?.toString() == projection.assistantText) {
          return index;
        }
      }
    }
    return null;
  }

  String _gatewayRecoveryStatusText(GatewayRecoveryTurnStatus? status) {
    return switch (status) {
      GatewayRecoveryTurnStatus.waitingInput =>
        context.l10n.hermes_is_waiting_for_input,
      GatewayRecoveryTurnStatus.running => context.l10n.hermes_is_responding,
      _ => context.l10n.recovering_hermes,
    };
  }

  void _extractToolMessages(List<Map<String, dynamic>> messages) {
    final observedByToolId = {
      for (final activity in _toolActivities)
        if (activity.toolId != null) activity.toolId!: activity,
    };
    _toolActivities.clear();
    for (final msg in messages) {
      if (!isToolResultMessage(msg)) continue;

      final name =
          (msg['name'] as String?) ??
          (msg['tool_name'] as String?) ??
          (msg['toolCallName'] as String?) ??
          '';
      final toolCallId = (msg['tool_call_id'] as String?) ?? '';
      final content = messageContentToText(msg['content']);

      String toolName = name.isNotEmpty ? name : '';
      if (toolName.isEmpty && content.isNotEmpty) {
        final match = RegExp(r'source="([^"]+)"').firstMatch(content);
        if (match != null) toolName = match.group(1)!;
      }
      if (toolName.isEmpty) toolName = 'tool';

      _toolActivities.add(
        GatewayToolActivity.fromStoredResult(
          toolId: toolCallId.isEmpty ? null : toolCallId,
          name: toolName,
          timestamp: msg['timestamp'],
          observedStart: observedByToolId[toolCallId]?.startedAt,
          observedLastActivity: observedByToolId[toolCallId]?.lastActivityAt,
        ),
      );
    }
  }

  Future<void> _showAttachmentPicker() async {
    if (_transcriptLoadBlocksComposer ||
        _streaming ||
        _sending ||
        _pendingReattachResync) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                _desktopGateway == null
                    ? context.l10n.choose_image
                    : context.l10n.choose_images,
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickGalleryImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(context.l10n.take_photo),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCameraImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(context.l10n.browse_server_files),
              subtitle: Text(context.l10n.insert_a_remote_file_reference),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_pickServerFile());
              },
            ),
            if (_desktopGateway != null)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(context.l10n.choose_files),
                subtitle: Text(
                  context.l10n.documents_archives_audio_video_or_data,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickFiles();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickServerFile() async {
    String? path;
    final testPicker = widget.testServerFilePicker;
    if (testPicker != null) {
      path = await testPicker();
    } else {
      final files = RemoteFilesClient.fromConnection(widget.connection);
      try {
        if (!mounted) return;
        path = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) => FilesScreen(
              files: files,
              onAddToChat: (selectedPath) =>
                  Navigator.of(context).pop(selectedPath),
            ),
          ),
        );
      } finally {
        files.close();
      }
    }
    if (!mounted || path == null || path.trim().isEmpty) return;
    final current = _textController.text.trimRight();
    final reference = '@file ${path.trim()} ';
    final next = current.isEmpty ? reference : '$current\n$reference';
    _textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _pickGalleryImages() async {
    try {
      final mode = _desktopGateway == null
          ? AttachmentDraftMode.rest
          : AttachmentDraftMode.remoteGateway;
      if (!allowsMultipleImageSelection(mode)) {
        final image = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 75,
          maxWidth: 1600,
          maxHeight: 1600,
        );
        if (image != null) await _preparePickedImages([image]);
        return;
      }
      final images = await _imagePicker.pickMultiImage(
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (images.isNotEmpty) await _preparePickedImages(images);
    } catch (_) {
      if (!mounted) return;
      _showAttachmentError(
        context.l10n.unable_to_prepare_this_image_try_another_one,
      );
    }
  }

  Future<void> _pickCameraImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 75,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (image != null) await _preparePickedImages([image]);
    } catch (_) {
      if (!mounted) return;
      _showAttachmentError(
        context.l10n.unable_to_prepare_this_image_try_another_one,
      );
    }
  }

  Future<void> _recoverLostImage() async {
    final response = await _imagePicker.retrieveLostData();
    if (response.isEmpty) return;

    final files = response.files;
    if (files == null || files.isEmpty) {
      if (!mounted) return;
      _showAttachmentError(
        context.l10n.image_selection_was_interrupted_try_again,
      );
      return;
    }

    await _preparePickedImages(_desktopGateway == null ? [files.first] : files);
  }

  Future<void> _preparePickedImages(List<XFile> images) async {
    final l10n = context.l10n;
    final isRemote = _desktopGateway != null;
    final prepared = <AttachmentDraft>[];
    final errors = <String>[];
    for (final image in images) {
      try {
        final draft = await _attachmentDraftService.prepareImage(
          sourcePath: image.path,
          displayName: image.name,
          existingDrafts: isRemote
              ? [..._attachmentDrafts, ...prepared]
              : const <AttachmentDraft>[],
          mode: isRemote
              ? AttachmentDraftMode.remoteGateway
              : AttachmentDraftMode.rest,
        );
        prepared.add(draft);
        if (!isRemote) break;
      } on AttachmentDraftException catch (error) {
        errors.add(error.message);
      } catch (_) {
        errors.add(l10n.unable_to_prepare(image.name));
      }
    }
    if (!mounted) {
      await _attachmentDraftService.removeAll(prepared);
      return;
    }
    if (prepared.isNotEmpty) {
      if (isRemote) {
        setState(() => _attachmentDrafts.addAll(prepared));
      } else {
        final replaced = List<AttachmentDraft>.from(_attachmentDrafts);
        setState(() {
          _attachmentDrafts
            ..clear()
            ..add(prepared.single);
        });
        unawaited(_attachmentDraftService.removeAll(replaced));
      }
    }
    if (errors.isNotEmpty) {
      _showAttachmentError(errors.first);
    }
  }

  Future<void> _pickFiles() async {
    if (_desktopGateway == null) {
      _showAttachmentError(
        context
            .l10n
            .configure_a_valid_desktop_gateway_url_before_attaching_files,
      );
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
      final files = result?.files ?? const [];
      if (files.isEmpty) return;
      final available = maxRemoteAttachmentDrafts - _attachmentDrafts.length;
      if (available <= 0) {
        if (!mounted) return;
        _showAttachmentError(
          context.l10n.you_can_attach_up_to_items(maxRemoteAttachmentDrafts),
        );
        return;
      }
      final prepared = <AttachmentDraft>[];
      var rejected = 0;
      for (final file in files.take(available)) {
        final path = file.path;
        if (path == null) {
          rejected++;
          continue;
        }
        try {
          prepared.add(
            await _attachmentDraftService.prepareGenericFile(
              sourcePath: path,
              displayName: file.name,
              existingDrafts: [..._attachmentDrafts, ...prepared],
            ),
          );
        } catch (_) {
          rejected++;
        }
      }
      if (!mounted) {
        await _attachmentDraftService.removeAll(prepared);
        return;
      }
      setState(() => _attachmentDrafts.addAll(prepared));
      if (files.length > available || rejected > 0) {
        _showAttachmentError(
          context.l10n.files_skipped(files.length - prepared.length),
        );
      }
    } catch (_) {
      _showAttachmentError(
        context.l10n.unable_to_prepare_this_file_try_another_one,
      );
    }
  }

  void _showAttachmentError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.orange),
    );
  }

  Future<void> _removeAttachment(AttachmentDraft draft) async {
    await _attachmentDraftService.removeCachedFile(draft);
    if (!mounted) return;
    setState(
      () => _attachmentDrafts.removeWhere((item) => item.id == draft.id),
    );
  }

  void _moveAttachment(AttachmentDraft draft, int offset) {
    final index = _attachmentDrafts.indexOf(draft);
    setState(() {
      _attachmentDraftService.moveDraft(
        _attachmentDrafts,
        fromIndex: index,
        offset: offset,
      );
    });
  }

  Future<AttachmentUploadReceipt> _uploadAttachmentDraft(
    DesktopGatewayClient desktopGateway,
    AttachmentDraft draft,
    String dataUrl,
  ) async {
    final attachment = await desktopGateway.attachFile(
      sessionId: widget.session.id,
      name: draft.name,
      dataUrl: dataUrl,
    );
    return AttachmentUploadReceipt(
      refText: attachment.refText,
      atlasIntakeAccepted: attachment.atlasIntakeAccepted,
    );
  }

  Future<void> _retryAttachment(AttachmentDraft draft) async {
    final desktopGateway = _desktopGateway;
    if (desktopGateway == null ||
        _sending ||
        _streaming ||
        _pendingReattachResync) {
      return;
    }
    setState(() {
      _sending = true;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'upload',
        text: context.l10n.retrying(draft.name),
      );
    });
    try {
      final receipt = await _attachmentSendCoordinator.retryFailed(
        draft: draft,
        upload: ({required draft, required dataUrl}) =>
            _uploadAttachmentDraft(desktopGateway, draft, dataUrl),
        onChanged: (_) {
          if (mounted) setState(() {});
        },
      );
      if (!mounted) return;
      if (receipt.atlasIntakeAccepted == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context
                  .l10n
                  .file_attached_document_catalog_registration_is_pending,
            ),
          ),
        );
      }
    } catch (error) {
      _showAttachmentError(
        context.l10n.retry_failed_for_the_draft_and_prompt_were_kept(
          draft.name,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _gatewayTurnStatus = null;
        });
      }
    }
  }

  Future<void> _showModelSelector() async {
    if (_pendingReattachResync || _loadingModelOptions) return;
    setState(() => _loadingModelOptions = true);
    try {
      await _sessionModelRestore;
      if (!mounted || _pendingReattachResync) return;
      final desktopGateway = _desktopGateway;

      // API-server-only connections deliberately stay on port 8642. The API
      // server exposes both the model inventory and the current session model;
      // no Dashboard client or :9119 transport is needed for the picker.
      late final Map<String, dynamic> sessionOrModelInfo;
      late final Map<String, dynamic> modelOptions;
      if (desktopGateway != null) {
        final results = await Future.wait([
          desktopGateway.getModelInfo(),
          desktopGateway.getModelOptions(),
        ]);
        sessionOrModelInfo = results[0];
        modelOptions = results[1];
      } else if (widget.session.isLocalDraft) {
        // A new chat deliberately has no server row until its first turn (or
        // until a selected model is persisted below), so an exact-session GET
        // would be a guaranteed 404. The API model inventory contains the
        // profile default needed to initialise the picker.
        sessionOrModelInfo = const {};
        modelOptions = await _client.getModelOptions();
      } else {
        final results = await Future.wait([
          _client.getSession(widget.session.id),
          _client.getModelOptions(),
        ]);
        sessionOrModelInfo = results[0];
        modelOptions = results[1];
      }
      if (!mounted || _pendingReattachResync) return;
      final modelInfo = desktopGateway != null
          ? sessionOrModelInfo
          : modelOptions;
      final choices = _parseModelChoices(modelOptions);
      if (choices.isEmpty) {
        throw StateError(
          'The active profile did not return any selectable models.',
        );
      }

      var currentEffort =
          _sessionReasoningEffort ??
          WsClient.normalizeReasoningEffort(modelInfo['reasoning_effort']);
      try {
        if (desktopGateway != null) {
          currentEffort = await desktopGateway.getSessionReasoning(
            widget.session.id,
          );
        }
      } catch (_) {
        // Older gateways may not expose session-scoped config.get. The model
        // selector remains usable with the profile/default effort.
      }
      if (!mounted || _pendingReattachResync) return;

      final apiSessionModel =
          desktopGateway == null && !widget.session.isLocalDraft
          ? sessionOrModelInfo['model']?.toString().trim()
          : null;
      final selectedModel = apiSessionModel?.isNotEmpty == true
          ? apiSessionModel!
          : (_sessionModel ??
                (widget.session.isLocalDraft
                    ? modelOptions['model']?.toString().trim()
                    : null) ??
                widget.session.model);
      final providerHint =
          _sessionProvider ??
          (widget.session.isLocalDraft
              ? modelOptions['provider']?.toString().trim()
              : desktopGateway != null
              ? modelInfo['provider']?.toString().trim()
              : null);
      var selectedChoice = _initialModelChoice(
        choices,
        selectedModel: selectedModel,
        provider: providerHint,
      );
      final providerChoiceRequired = selectedChoice == null;
      var selectedEffort = currentEffort;
      final selection = await showModalBottomSheet<_ModelSelection>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 640),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(context.l10n.model_and_thinking_for_this_chat),
                    subtitle: Text(
                      'Profile default: ${modelInfo['model'] ?? 'unknown'}'
                      '${modelInfo['provider'] == null ? '' : ' • ${modelInfo['provider']}'}',
                    ),
                  ),
                  if (providerChoiceRequired)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        'This model is available from multiple providers. Choose a provider to continue.',
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: context.l10n.thinking_effort,
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedEffort,
                          items: _reasoningEffortOptions
                              .map(
                                (effort) => DropdownMenuItem(
                                  value: effort,
                                  child: Text(
                                    _reasoningEffortLabel(context, effort),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => selectedEffort = value);
                          },
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, index) {
                        final choice = choices[index];
                        final selected =
                            choice.model == selectedChoice?.model &&
                            choice.provider == selectedChoice?.provider;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.smart_toy_outlined,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(choice.model),
                          subtitle: Text(choice.provider),
                          onTap: () =>
                              setSheetState(() => selectedChoice = choice),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: Text(context.l10n.cancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: selectedChoice == null
                              ? null
                              : () => Navigator.pop(
                                  sheetContext,
                                  _ModelSelection(
                                    choice: selectedChoice!,
                                    reasoningEffort: selectedEffort,
                                  ),
                                ),
                          child: Text(context.l10n.apply_to_this_chat),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (selection != null && mounted && !_pendingReattachResync) {
        await _setSessionModel(selection);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.could_not_load_models_for_this_profile(error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingModelOptions = false);
    }
  }

  List<_ModelChoice> _parseModelChoices(Map<String, dynamic> options) {
    final providers = options['providers'];
    if (providers is! List) return const [];
    final choices = <_ModelChoice>[];
    for (final rawProvider in providers) {
      if (rawProvider is! Map) continue;
      final provider =
          (rawProvider['slug'] ?? rawProvider['id'])?.toString().trim() ?? '';
      final models = rawProvider['models'];
      if (provider.isEmpty || models is! List) continue;
      for (final rawModel in models) {
        final model = rawModel is String
            ? rawModel.trim()
            : rawModel is Map
            ? (rawModel['id'] ?? rawModel['model'] ?? rawModel['name'])
                      ?.toString()
                      .trim() ??
                  ''
            : '';
        if (model.isNotEmpty) {
          choices.add(_ModelChoice(provider: provider, model: model));
        }
      }
    }
    return choices;
  }

  _ModelChoice? _initialModelChoice(
    List<_ModelChoice> choices, {
    required String selectedModel,
    String? provider,
  }) {
    final candidates = choices
        .where((choice) => choice.model == selectedModel)
        .toList(growable: false);
    final cleanProvider = provider?.trim() ?? '';
    if (cleanProvider.isNotEmpty) {
      for (final choice in candidates) {
        if (choice.provider == cleanProvider) return choice;
      }
    }
    if (candidates.length == 1) return candidates.single;
    if (candidates.length > 1) {
      // GET /api/sessions/{id} intentionally omits model_config, so an API
      // session whose model id exists under multiple providers has no
      // authoritative provider unless this client saved one. Never guess the
      // first provider: require an explicit tap before Apply is enabled.
      return null;
    }
    return choices.isEmpty ? null : choices.first;
  }

  Future<void> _setSessionModel(_ModelSelection selection) async {
    final desktopGateway = _desktopGateway;
    if (_changingModel || _pendingReattachResync) return;
    final choice = selection.choice;
    setState(() => _changingModel = true);
    try {
      if (desktopGateway != null) {
        await desktopGateway.setSessionModel(
          sessionId: widget.session.id,
          provider: choice.provider,
          model: choice.model,
        );
        if (!mounted || _pendingReattachResync) return;
        await desktopGateway.setSessionReasoning(
          sessionId: widget.session.id,
          effort: selection.reasoningEffort,
        );
      } else {
        // The API Server owns this session, so persist the same per-session
        // lock over :8642 instead of activating the Dashboard transport.
        // Reasoning effort remains a Desktop Gateway-only control.
        await _client.setSessionModel(
          sessionId: widget.session.id,
          provider: choice.provider,
          model: choice.model,
          createSessionIfMissing: widget.session.isLocalDraft,
        );
      }
      final store = await _chatModelStore;
      await store.save(
        connectionIdentity: _connectionIdentity,
        sessionId: widget.session.id,
        provider: choice.provider,
        model: choice.model,
        reasoningEffort: selection.reasoningEffort,
      );
      if (!mounted) return;
      setState(() {
        _sessionModel = choice.model;
        _sessionProvider = choice.provider;
        _sessionReasoningEffort = selection.reasoningEffort;
        _sessionModelOverride = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.model_scope_applied(
              _reasoningEffortLabel(context, selection.reasoningEffort),
              choice.model,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.model_was_not_changed(error))),
      );
    } finally {
      if (mounted) setState(() => _changingModel = false);
    }
  }

  /// Send message via SSE streaming (Gateway API Server).
  Future<void> _sendRecordedVoice() async {
    if (_sending ||
        _streaming ||
        _pendingReattachResync ||
        _voiceComposer.listening) {
      return;
    }
    await _voiceRecording.send(
      submit: (path, accepted) async {
        final transcribe = widget.testVoiceTranscription;
        final transcript = transcribe != null
            ? await transcribe(path)
            : await transcribeVoiceRecording(
                _voiceDashboard ??= DashboardClient(
                  host: widget.connection.host,
                  port: widget.connection.dashboardPort,
                  pathPrefix: widget.connection.dashboardPrefix ?? '',
                  proxied: widget.connection.dashboardProxied,
                  useHttps: widget.connection.useHttps,
                  username: widget.connection.dashboardUsername,
                  password: widget.connection.dashboardPassword,
                  gatewayProfile: widget.connection.gatewayProfile,
                ),
                path,
              );
        if (!mounted || transcript.trim().isEmpty) return;
        final receipt = Completer<void>();
        final sending = _sendMessage(
          textOverride: transcript.trim(),
          onAccepted: () {
            if (receipt.isCompleted) return;
            accepted();
            receipt.complete();
          },
        );
        // Free the voice UI after a proven receipt, while the ordinary chat
        // transport continues owning the response. No transport write is retried.
        await Future.any([sending, receipt.future]);
      },
    );
  }

  Future<void> _sendMessage({
    bool speakResponse = false,
    String? textOverride,
    VoidCallback? onAccepted,
  }) async {
    if (_voiceComposer.listening) return;
    if (textOverride == null &&
        (_voiceRecording.recording || _voiceRecording.busy)) {
      return;
    }
    final text = textOverride ?? _textController.text.trim();
    final attachments = textOverride == null
        ? List<AttachmentDraft>.from(_attachmentDrafts)
        : <AttachmentDraft>[];
    if (text.isEmpty && attachments.isEmpty) return;
    if (_sending || _streaming || _pendingReattachResync) return;
    if (_transcriptLoadBlocksComposer) return;
    if (_loading || _error != null) {
      // Remote transports own their session history server-side. Let a prompt
      // proceed independently of a slow or failed visible transcript request.
      setState(() {
        _loading = false;
        _error = null;
      });
    }
    await _sessionModelRestore;
    if (!mounted) return;

    // A remote-gateway profile uses one transport for every prompt. Images and
    // arbitrary files are both attached with the official `file.attach` RPC.
    if (_turnApplicationSession != null && !_legacyTransportFallback) {
      await _sendRecoverableGatewayMessage(
        text: text,
        attachments: attachments,
        speakResponse: speakResponse,
        preserveComposer: textOverride != null,
        onAccepted: onAccepted,
      );
      return;
    }
    if (_desktopGateway != null || widget.testRemotePromptSubmit != null) {
      await _sendDesktopGatewayMessage(
        text: text,
        attachments: attachments,
        speakResponse: speakResponse,
        preserveComposer: textOverride != null,
        onAccepted: onAccepted,
      );
      return;
    }

    try {
      _attachmentDraftService.validateRestDrafts(attachments);
    } on AttachmentDraftException catch (error) {
      _showAttachmentError(error.message);
      return;
    }
    final pendingImage = attachments.firstOrNull;
    String? imageDataUrl;
    if (pendingImage != null) {
      setState(() => _sending = true);
      try {
        imageDataUrl = await _attachmentDraftService.readDataUrl(pendingImage);
      } catch (_) {
        if (mounted) setState(() => _sending = false);
        if (!mounted) return;
        _showAttachmentError(
          context.l10n.unable_to_read_the_selected_image_the_selection_was_kept,
        );
        return;
      }
      if (!mounted) return;
    }

    final localContent = pendingImage == null
        ? text
        : <Map<String, dynamic>>[
            if (text.isNotEmpty) {'type': 'text', 'text': text},
            {
              'type': 'image_url',
              'image_url': {'url': imageDataUrl},
            },
          ];

    if (textOverride == null) _clearComposerForSend();
    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;
    final responseGeneration = ++_responseGeneration;
    _activeResponseTransport = _ResponseTransport.rest;

    // The server returns oldest-to-newest history. Preserve that order; the
    // gateway client appends the current prompt exactly once.
    final knownHistoryIds = _messages
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();
    final history = buildRestChatHistory(_messages);
    _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());

    setState(() {
      _sending = true;
      _streaming = true;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'starting',
        text: context.l10n.starting_hermes,
      );
      _messages.add({'role': 'user', 'content': localContent});
      // Insert a placeholder streaming message
      _messages.add({
        'role': 'assistant',
        'content': '',
        '_gateway_pending_response': true,
      });
    });

    _scheduleStreamingFollow();

    // Accumulate tokens into the streaming placeholder
    await _gateway.sendMessageStreaming(
      message: text,
      sessionId: widget.session.id,
      // The OpenAI-compatible endpoint does not consume the API session's
      // persisted Browser lock. Carry both ids on API-only turns so duplicate
      // model names cannot silently fall back to another provider. Desktop
      // Gateway keeps its existing model-only request behaviour.
      model: _sessionModelOverride ? _sessionModel : null,
      provider: _desktopGateway == null && _sessionModelOverride
          ? _sessionProvider
          : null,
      history: history,
      imageDataUrl: imageDataUrl,
      onToken: (token) {
        onAccepted?.call();
        if (!mounted || responseGeneration != _responseGeneration) return;
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            final assistant = _messages.last;
            final current = assistant['content'] as String;
            if (current.isEmpty && token.isNotEmpty) {
              _registerMaterializedAssistantMessage();
            }
            assistant['content'] = current + token;
          }
        });
        _scheduleStreamingFollow();
      },
      onToolProgress: (progress) {
        onAccepted?.call();
        if (!mounted || responseGeneration != _responseGeneration) return;
        _upsertToolProgress(progress);
      },
      onDone: () async {
        if (!mounted || responseGeneration != _responseGeneration) return;
        // Refresh messages to get the final server-side state
        try {
          final messages = await _getRecentMessages(widget.session.id);
          // An empty/error SSE body is not a receipt. Without output, require
          // a new durable user row before discarding the local recording.
          if (messages.any(
            (row) =>
                row['role'] == 'user' &&
                row['content'] == text &&
                row['id'] != null &&
                !knownHistoryIds.contains(row['id'].toString()),
          )) {
            onAccepted?.call();
          }

          if (!mounted || responseGeneration != _responseGeneration) return;
          if (pendingImage != null) {
            await _attachmentDraftService.removeCachedFile(pendingImage);
          }
          if (!mounted || responseGeneration != _responseGeneration) return;
          _acceptRecentMessages(messages);
          setState(() {
            _messages = _historyWindow.rows;
            if (pendingImage != null) {
              _attachmentDrafts.removeWhere(
                (draft) => draft.id == pendingImage.id,
              );
            }
            _streaming = false;
            _sending = false;
            _gatewayTurnStatus = null;
            _activeResponseTransport = _ResponseTransport.none;
          });
          _scheduleScrollTarget(_scrollCoordinator.endStreaming());
          if (_awaitingVoiceReply) {
            _awaitingVoiceReply = false;
            final assistant = messages.reversed.firstWhere(
              (message) => message['role'] == 'assistant',
              orElse: () => const <String, dynamic>{},
            );
            final assistantText = assistant['content']?.toString();
            if (assistantText != null) {
              await _speakAssistantText(assistantText);
            }
          }
        } catch (_) {
          if (!mounted || responseGeneration != _responseGeneration) return;
          _scrollCoordinator.cancelStreaming();
          setState(() {
            if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
              _messages.last['_gateway_pending_response'] = false;
            }
            _streaming = false;
            _sending = false;
            _gatewayTurnStatus = null;
            _activeResponseTransport = _ResponseTransport.none;
          });
          // The SSE response completed, so the server accepted the prompt.
          // A follow-up history read failing must not resurrect it as a draft.
          _deferHistoryRefresh();
        }
      },
      onError: (error) {
        if (!mounted || responseGeneration != _responseGeneration) return;
        // No streamed content means the request never reached the server
        // (connection failure, non-200): restore the draft so nothing typed
        // is lost. Content already flowing means the prompt was accepted.
        final hadContent =
            _messages.isNotEmpty &&
            _messages.last['role'] == 'assistant' &&
            (_messages.last['content']?.toString().isNotEmpty ?? false);
        // Remove the placeholder assistant message
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.removeLast();
          }
        });
        if (!hadContent && textOverride == null) {
          _restoreComposerAfterRejectedSend(text);
        }
        _handleSendError(error, removePendingUserMessage: true);
      },
    );
  }

  Future<void> _sendDesktopGatewayMessage({
    required String text,
    required List<AttachmentDraft> attachments,
    required bool speakResponse,
    bool preserveComposer = false,
    VoidCallback? onAccepted,
  }) async {
    final desktopGateway = _desktopGateway;
    final testRemotePromptSubmit = widget.testRemotePromptSubmit;
    if (desktopGateway == null && testRemotePromptSubmit == null) {
      _showAttachmentError(
        context.l10n.desktop_gateway_is_not_configured_for_this_connection,
      );
      return;
    }
    try {
      _attachmentDraftService.validateRemoteDrafts(attachments);
    } on AttachmentDraftException catch (error) {
      _showAttachmentError(error.message);
      return;
    }

    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;
    final responseGeneration = ++_responseGeneration;
    // History generation at send time: if a reattach resync replaces
    // _messages while this submit is in flight, the catch path below must
    // not clobber the fresh server history with composer-restore.
    final historyAtSend = _historyGeneration;
    _activeResponseTransport = _ResponseTransport.desktop;
    var turnAdded = false;
    var promptSubmitted = false;

    setState(() {
      _sending = true;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'upload',
        text: context.l10n.preparing_attachments,
      );
    });

    // Stock-gateway coverage: this transport carries every stock send and
    // every stored chat, and never enters the recovery-v2 coordinator —
    // register the turn app-wide so the keep-alive can bound itself to it.
    // Released in the finally at the end of this method, so every settle
    // and error path ends it exactly once.
    final turnController = widget.turnApplicationController;
    final legacyTurnToken = turnController?.beginLegacyTurn();
    try {
      // Local drafts skip the eager legacy bind while recovery-v2 capability
      // detection is pending. Once this send has selected the legacy path,
      // bind a Project draft *before* model overrides, file.attach or prompt
      // can create a default-cwd session. Stock Hermes derives membership
      // from the cwd supplied on session.create; a later ensure cannot move it.
      final projectCwd = widget.projectWorkingDirectory?.trim();
      if (widget.session.isLocalDraft &&
          projectCwd != null &&
          projectCwd.isNotEmpty) {
        if (desktopGateway != null) {
          await desktopGateway.ensureSession(
            widget.session.id,
            workingDirectory: projectCwd,
          );
        } else {
          await widget.testLegacyProjectSessionEnsure?.call(
            widget.session.id,
            projectCwd,
          );
        }
      }
      if (desktopGateway != null) {
        await _applySessionModelOverride(desktopGateway);
      }
      if (!mounted || responseGeneration != _responseGeneration) return;
      await _attachmentSendCoordinator.uploadThenSubmit(
        drafts: attachments,
        upload: ({required draft, required dataUrl}) async {
          if (desktopGateway == null) {
            final testUpload = widget.testRemoteAttachmentUpload;
            if (testUpload == null) {
              throw StateError('Test remote transport does not upload files');
            }
            return testUpload(draft: draft, dataUrl: dataUrl);
          }
          return _uploadAttachmentDraft(desktopGateway, draft, dataUrl);
        },
        onChanged: (draft) {
          if (!mounted || responseGeneration != _responseGeneration) return;
          setState(() {
            if (draft.status == AttachmentDraftStatus.uploading) {
              final index = attachments.indexOf(draft);
              _gatewayTurnStatus = GatewayTurnStatus(
                kind: 'upload',
                text: context.l10n.uploading(
                  index + 1,
                  draft.name,
                  attachments.length,
                ),
              );
            }
          });
        },
        submitPrompt: (refTexts) async {
          if (!mounted || responseGeneration != _responseGeneration) return;
          if (attachments.any((draft) => draft.atlasIntakeAccepted == false)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context
                      .l10n
                      .file_attached_document_catalog_registration_is_pending,
                ),
              ),
            );
          }
          final prompt = [
            text,
            refTexts.join('\n'),
          ].where((part) => part.trim().isNotEmpty).join('\n\n');
          final attachmentLabels = attachments
              .map(
                (attachment) =>
                    '[${context.l10n.attached_file}: ${attachment.name}]',
              )
              .join('\n');
          final localContent = [
            text,
            attachmentLabels,
          ].where((part) => part.trim().isNotEmpty).join('\n\n');
          if (!preserveComposer) _clearComposerForSend();
          _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());
          setState(() {
            _streaming = true;
            _gatewayTurnStatus = GatewayTurnStatus(
              kind: 'starting',
              text: context.l10n.starting_hermes,
            );
            if (!preserveComposer) _attachmentDrafts.clear();
            _messages.add({'role': 'user', 'content': localContent});
            _messages.add({
              'role': 'assistant',
              'content': '',
              '_gateway_pending_response': true,
            });
            turnAdded = true;
          });
          _scheduleStreamingFollow();
          void onEvent(StreamEvent event) {
            if (const {
              'message.delta',
              'message.interim',
              'message.complete',
              'tool.start',
              'tool.end',
            }.contains(event.type)) {
              onAccepted?.call();
            }
            _handleDesktopGatewayEvent(event, responseGeneration);
          }

          void markPromptSent() {
            promptSubmitted = true;
            if (mounted && responseGeneration == _responseGeneration) {
              _legacyDesktopPromptSubmitted = true;
            }
          }

          try {
            if (testRemotePromptSubmit != null) {
              await testRemotePromptSubmit(
                sessionId: widget.session.id,
                text: prompt,
                onEvent: onEvent,
                onSent: markPromptSent,
              );
            } else {
              await desktopGateway!.submitPrompt(
                sessionId: widget.session.id,
                text: prompt,
                onEvent: onEvent,
                onSent: markPromptSent,
              );
            }
          } finally {
            _legacyDesktopPromptSubmitted = false;
          }
        },
      );
      onAccepted?.call();
      if (!mounted || responseGeneration != _responseGeneration) return;
      setState(() {
        final assistant = _lastAssistantMessage();
        if (assistant != null) {
          assistant['_gateway_pending_response'] = false;
        }
        _streaming = false;
        _sending = false;
        _gatewayTurnStatus = null;
        _activeResponseTransport = _ResponseTransport.none;
      });
      unawaited(_refreshDeferredHistoryIfIdle());
      unawaited(_resyncLegacyHistoryAfterResume());
      _scheduleScrollTarget(_scrollCoordinator.endStreaming());
      if (_awaitingVoiceReply) {
        _awaitingVoiceReply = false;
        final assistantText = _messages.isNotEmpty
            ? _messages.last['content']?.toString()
            : null;
        if (assistantText != null && assistantText.isNotEmpty) {
          await _speakAssistantText(assistantText);
        }
      }
    } catch (error) {
      if (!mounted || responseGeneration != _responseGeneration) return;
      _scrollCoordinator.cancelStreaming();
      // A reattach resync replaced _messages while this submit was in
      // flight: the server history is now authoritative (it already
      // carries the user prompt and, if the detached turn finished, the
      // reply). Restoring the composer and stripping the local turn would
      // clobber it, so skip the restore and just surface the error state.
      final resyncLanded = _historyGeneration != historyAtSend;
      if (turnAdded && !resyncLanded && !promptSubmitted) {
        setState(() {
          if (_messages.isNotEmpty &&
              _messages.last['role'] == 'assistant' &&
              (_messages.last['content']?.toString().isEmpty ?? true)) {
            _messages.removeLast();
          }
          if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
            _messages.removeLast();
          }
          if (!preserveComposer) _restoreComposerAfterRejectedSend(text);
          if (!preserveComposer) {
            _attachmentDrafts
              ..clear()
              ..addAll(attachments);
          }
        });
      }
      _handleSendError(error);
      unawaited(_refreshDeferredHistoryIfIdle());
      unawaited(_resyncLegacyHistoryAfterResume());
    } finally {
      if (turnController != null && legacyTurnToken != null) {
        turnController.endLegacyTurn(legacyTurnToken);
      }
    }
  }

  Future<void> _sendRecoverableGatewayMessage({
    required String text,
    required List<AttachmentDraft> attachments,
    required bool speakResponse,
    bool preserveComposer = false,
    VoidCallback? onAccepted,
  }) async {
    final turnSession = _turnApplicationSession;
    if (turnSession == null) return;
    try {
      _attachmentDraftService.validateRemoteDrafts(attachments);
    } on AttachmentDraftException catch (error) {
      _showAttachmentError(error.message);
      return;
    }

    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;
    final responseGeneration = ++_responseGeneration;
    _activeResponseTransport = _ResponseTransport.desktop;
    final staged = <GatewayTurnAttachmentReceipt>[];
    var attachmentCacheReleased = false;

    void releaseAcceptedAttachmentCache(GatewayTurnRecoveryState state) {
      if (attachmentCacheReleased ||
          state.turnId == null ||
          state.ackUncertain) {
        return;
      }
      attachmentCacheReleased = true;
      onAccepted?.call();
      unawaited(_attachmentDraftService.removeAll(attachments));
    }

    void onState(GatewayTurnRecoveryState state) {
      releaseAcceptedAttachmentCache(state);
      if (!mounted || responseGeneration != _responseGeneration) return;
      _applyGatewayTurnState(state);
    }

    setState(() {
      _sending = true;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'upload',
        text: context.l10n.preparing_attachments,
      );
    });

    try {
      for (var index = 0; index < attachments.length; index++) {
        final draft = attachments[index];
        setState(() {
          draft
            ..status = AttachmentDraftStatus.uploading
            ..error = null;
          _gatewayTurnStatus = GatewayTurnStatus(
            kind: 'upload',
            text: context.l10n.uploading(
              index + 1,
              draft.name,
              attachments.length,
            ),
          );
        });
        final dataUrl = await _attachmentDraftService.readDataUrl(draft);
        final receipt = await turnSession.stageAttachment(
          localSessionId: widget.session.id,
          clientAttachmentId: draft.id,
          name: draft.name,
          dataUrl: dataUrl,
          byteLength: draft.byteLength,
          mediaType: draft.mediaType,
          kind: draft.isImage
              ? GatewayTurnAttachmentKind.image
              : GatewayTurnAttachmentKind.file,
        );
        staged.add(receipt);
        if (!mounted || responseGeneration != _responseGeneration) return;
        setState(() => draft.status = AttachmentDraftStatus.attached);
      }
    } catch (error) {
      if (staged.isNotEmpty) {
        try {
          await turnSession.detachAttachments(
            localSessionId: widget.session.id,
            attachments: staged,
          );
        } catch (_) {
          // Closing or quarantining the coordinator also invalidates receipts.
        }
      }
      if (!mounted || responseGeneration != _responseGeneration) return;
      for (final draft in attachments) {
        draft
          ..status = AttachmentDraftStatus.ready
          ..error = null;
      }
      _handleSendError(error);
      unawaited(_refreshDeferredHistoryIfIdle());
      return;
    }

    final attachmentLabels = attachments
        .map(
          (attachment) => '[${context.l10n.attached_file}: ${attachment.name}]',
        )
        .join('\n');
    final localContent = [
      text,
      attachmentLabels,
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    if (!preserveComposer) _clearComposerForSend();
    _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());
    setState(() {
      _streaming = true;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'starting',
        text: context.l10n.starting_hermes,
      );
      if (!preserveComposer) _attachmentDrafts.clear();
      _messages.add({'role': 'user', 'content': localContent});
      _messages.add({
        'role': 'assistant',
        'content': '',
        '_gateway_pending_response': true,
      });
    });
    _scheduleStreamingFollow();

    try {
      final state = await turnSession.submit(
        localSessionId: widget.session.id,
        text: text,
        attachments: staged,
        onState: onState,
      );
      releaseAcceptedAttachmentCache(state);
      if (!mounted || responseGeneration != _responseGeneration) return;
      _applyGatewayTurnState(state);
    } catch (error) {
      if (!mounted || responseGeneration != _responseGeneration) return;
      if (gatewayTurnSubmissionWasDefinitelyRejected(error)) {
        setState(() {
          if (_messages.isNotEmpty &&
              _messages.last['role'] == 'assistant' &&
              _messages.last['_gateway_pending_response'] == true) {
            _messages.removeLast();
          }
          if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
            _messages.removeLast();
          }
          if (!preserveComposer) _restoreComposerAfterRejectedSend(text);
          for (final draft in attachments) {
            draft
              ..status = AttachmentDraftStatus.ready
              ..error = null;
          }
          if (!preserveComposer) {
            _attachmentDrafts
              ..clear()
              ..addAll(attachments);
          }
        });
        _handleSendError(error);
        unawaited(_refreshDeferredHistoryIfIdle());
        return;
      }
      setState(() {
        _gatewayTurnStatus = GatewayTurnStatus(
          kind: 'recovery',
          text: context.l10n.delivery_is_uncertain_recovering_without_resending,
        );
      });
      await _recoverPendingTurn();
    }
  }

  void _handleDesktopGatewayEvent(StreamEvent event, int responseGeneration) {
    if (!mounted || responseGeneration != _responseGeneration) return;
    final reasoning = GatewayReasoningUpdate.fromGatewayEvent(
      event.type,
      event.data,
    );
    if (reasoning != null) {
      setState(() {
        _gatewayTurnStatus = null;
        final assistant = _lastAssistantMessage();
        if (assistant == null) return;
        final current = assistant['_gateway_reasoning']?.toString() ?? '';
        assistant['_gateway_reasoning'] = reasoning.applyTo(current);
        assistant['_gateway_reasoning_verbose'] = reasoning.verbose;
        assistant['_gateway_reasoning_replaces'] =
            assistant['_gateway_reasoning_replaces'] == true ||
            reasoning.mode == GatewayReasoningEventMode.replace;
      });
      _scheduleStreamingFollow();
      return;
    }
    final turnStatus = GatewayTurnStatus.fromGatewayEvent(
      event.type,
      event.data,
    );
    if (turnStatus != null) {
      setState(() => _gatewayTurnStatus = turnStatus);
      _scheduleStreamingFollow();
      return;
    }
    if (event.type == 'approval.request') {
      _showGatewayApproval(event.data, responseGeneration);
      return;
    }
    if (event.type == 'clarify.request') {
      _queueClarifyPrompt(event.data, responseGeneration);
      return;
    }
    if (event.type == 'clarify.remaining') {
      _reconcileClarifyPrompts(event);
      return;
    }
    if (event.type == 'sudo.request' || event.type == 'secret.request') {
      _queueSensitivePrompt(event, responseGeneration);
      return;
    }
    if (event.type == 'sudo.expire' || event.type == 'secret.expire') {
      _expireSensitivePrompt(event);
      return;
    }
    if (event.type == 'request.cancel') {
      _cancelGatewayServerRequest(event);
      return;
    }
    if (event.type == 'message.start') {
      _lastAssistantMessage()?.remove('_gateway_interim_boundary');
      return;
    }
    if (event.type == 'message.delta') {
      final token = event.data['text']?.toString() ?? '';
      if (token.isEmpty) return;
      setState(() {
        _gatewayTurnStatus = null;
        final assistant = _lastAssistantMessage();
        if (assistant == null) return;
        final current = assistant['content']?.toString() ?? '';
        if (current.isEmpty) _registerMaterializedAssistantMessage();
        assistant['content'] = '$current$token';
      });
      _scheduleStreamingFollow();
      return;
    }
    if (event.type == 'message.interim') {
      final interim = event.data['text']?.toString() ?? '';
      setState(() {
        _gatewayTurnStatus = null;
        final assistant = _lastAssistantMessage();
        if (assistant == null) return;
        final current = assistant['content']?.toString() ?? '';
        final transition = GatewayInterimTransition.resolve(
          currentText: current,
          interimText: interim,
          alreadyStreamed: event.data['already_streamed'] == true,
        );
        if (current.isEmpty && transition.sealedText.isNotEmpty) {
          _registerMaterializedAssistantMessage();
        }
        assistant['content'] = transition.sealedText;
        if (transition.startsNewMessage) {
          assistant['_gateway_interim'] = true;
          assistant['_gateway_pending_response'] = false;
          _messages.add({
            'role': 'assistant',
            'content': '',
            '_gateway_pending_response': true,
            '_gateway_interim_boundary': true,
          });
        }
      });
      _scheduleStreamingFollow();
      return;
    }
    if (event.type == 'message.complete') {
      final completeText =
          event.data['rendered']?.toString() ??
          event.data['text']?.toString() ??
          '';
      setState(() {
        final assistant = _completionAssistantMessage(
          event.data,
          event.data['text']?.toString() ?? completeText,
        );
        if (assistant != null) {
          assistant['_gateway_pending_response'] = false;
          if (completeText.isNotEmpty) {
            final current = assistant['content']?.toString() ?? '';
            if (current.isEmpty) _registerMaterializedAssistantMessage();
            assistant['content'] = completeText;
          }
        }
      });
      if (completeText.isNotEmpty) {
        _scheduleStreamingFollow();
      }
      return;
    }
    if (event.type.startsWith('tool.')) {
      _upsertToolProgress(event.data, eventType: event.type);
      return;
    }
    if (event.type.startsWith('subagent.')) {
      _upsertSubagent(event.type, event.data);
    }
  }

  Map<String, dynamic>? _completionAssistantMessage(
    Map<String, dynamic> data,
    String rawCompleteText,
  ) {
    final pendingIndex = _messages.lastIndexWhere(
      (message) => message['role'] == 'assistant',
    );
    if (pendingIndex < 0) return null;
    final pending = _messages[pendingIndex];
    if (pending['_gateway_pending_response'] != true ||
        (pending['content']?.toString() ?? '').isNotEmpty ||
        pending['_gateway_interim_boundary'] != true) {
      return pending;
    }
    // Flags describe the final response, but do not identify which interim
    // it settles. Only an exact raw-text match may consume a sealed interim.
    if (data['response_previewed'] != true &&
        data['response_transformed'] != true &&
        data['response_reused'] != true) {
      return pending;
    }
    if (rawCompleteText.isEmpty) return pending;

    // A completion settles a matching preview from this turn, not the empty
    // bubble prepared for a continuation or distinct interim commentary.
    for (var index = pendingIndex - 1; index >= 0; index--) {
      final candidate = _messages[index];
      if (candidate['role'] == 'user') break;
      if (candidate['role'] != 'assistant' ||
          candidate['_gateway_interim'] != true ||
          candidate['content'] != rawCompleteText) {
        continue;
      }
      final pendingReasoning = pending['_gateway_reasoning']?.toString() ?? '';
      if (pendingReasoning.isNotEmpty) {
        final currentReasoning =
            candidate['_gateway_reasoning']?.toString() ?? '';
        candidate['_gateway_reasoning'] = GatewayReasoningUpdate(
          text: pendingReasoning,
          mode: pending['_gateway_reasoning_replaces'] == true
              ? GatewayReasoningEventMode.replace
              : GatewayReasoningEventMode.append,
          verbose: pending['_gateway_reasoning_verbose'] == true,
        ).applyTo(currentReasoning);
        candidate['_gateway_reasoning_verbose'] =
            pending['_gateway_reasoning_verbose'] == true;
      }
      _messages.removeAt(pendingIndex);
      candidate.remove('_gateway_interim');
      return candidate;
    }
    return pending;
  }

  Map<String, dynamic>? _lastAssistantMessage() {
    for (var index = _messages.length - 1; index >= 0; index--) {
      if (_messages[index]['role'] == 'assistant') return _messages[index];
    }
    return null;
  }

  void _handleDesktopAsyncEvent(String mobileSessionId, StreamEvent event) {
    if (!mounted || mobileSessionId != widget.session.id) return;
    const interactiveTypes = {
      'approval.request',
      'clarify.request',
      'clarify.remaining',
      'sudo.request',
      'secret.request',
      'request.cancel',
    };
    if (interactiveTypes.contains(event.type)) {
      _handleDesktopGatewayEvent(event, _responseGeneration);
      return;
    }
    if (_handlePendingReattachTerminalEvent(event)) return;
    if (event.type == 'notification.show') {
      final notification = GatewayNotification.fromEventData(event.data);
      if (notification == null) return;
      _notifyGatewayNotice(notification);
      _notificationTimers.remove(notification.key)?.cancel();
      setState(() => _gatewayNotifications[notification.key] = notification);
      _scheduleStreamingFollow();
      if (notification.ttl case final ttl?) {
        _notificationTimers[notification.key] = Timer(ttl, () {
          if (!mounted) return;
          setState(() => _gatewayNotifications.remove(notification.key));
          _notificationTimers.remove(notification.key);
        });
      }
      return;
    }
    if (event.type == 'notification.clear') {
      final key = event.data['key']?.toString().trim();
      setState(() {
        if (key == null || key.isEmpty) {
          _gatewayNotifications.clear();
          for (final timer in _notificationTimers.values) {
            timer.cancel();
          }
          _notificationTimers.clear();
        } else {
          _gatewayNotifications.remove(key);
          _notificationTimers.remove(key)?.cancel();
        }
      });
      _scheduleStreamingFollow();
      return;
    }
    if (event.type.startsWith('subagent.')) {
      _upsertSubagent(event.type, event.data);
      return;
    }
    final notice = GatewayNotice.fromGatewayEvent(event.type, event.data);
    if (notice == null) return;
    if (_gatewayNotices.any((item) => item.identity == notice.identity)) return;
    _notifyBackgroundNotice(notice);
    setState(() {
      _gatewayNotices.add(notice);
      if (_gatewayNotices.length > 20) _gatewayNotices.removeAt(0);
      _savedGatewayNotices[_gatewayNoticeIdentity] = List.unmodifiable(
        _gatewayNotices,
      );
    });
    _scheduleStreamingFollow();
  }

  bool _handlePendingReattachTerminalEvent(StreamEvent event) {
    const terminalTypes = {
      'message.complete',
      'turn.end',
      'turn.error',
      'error',
    };
    if (!terminalTypes.contains(event.type)) return false;
    // Active turns receive terminal events through prompt.submit. The async
    // bridge intentionally duplicates only these frames so detached legacy
    // recovery can still observe them after reconnect.
    if (!_pendingReattachResync) return true;

    final status = event.data['status']?.toString().trim().toLowerCase();
    final rawError = event.data['error'] ?? event.data['message'];
    final error = rawError?.toString().trim() ?? '';
    const failureStatuses = {
      'error',
      'failed',
      'interrupted',
      'cancelled',
      'canceled',
    };
    final failed =
        event.type == 'error' ||
        event.type == 'turn.error' ||
        failureStatuses.contains(status);
    if (failed) {
      _clearPendingReattachResync();
      setState(() {
        _sending = false;
        _streaming = false;
        _gatewayTurnStatus = null;
      });
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error.isEmpty
                  ? context.l10n.the_detached_reply_failed
                  : context.l10n.the_detached_reply_failed_2(error),
            ),
            persist: false,
          ),
        );
      return true;
    }

    // A success event says history should now contain the durable terminal
    // row. Fetch immediately, but let the row-ID watermark remain the sole
    // completion authority in case persistence trails the event slightly.
    _requestImmediateReattachResync();
    return true;
  }

  void _upsertSubagent(String eventType, Map<String, dynamic> data) {
    final update = GatewaySubagentActivity.fromGatewayEvent(eventType, data);
    if (update == null || !mounted) return;
    setState(() {
      final index = _subagentActivities.indexWhere(
        (activity) => activity.id == update.id,
      );
      if (index < 0) {
        _subagentActivities.add(update);
      } else {
        _subagentActivities[index] = _subagentActivities[index].merge(update);
      }
      if (!update.isComplete) {
        _gatewayTurnStatus = GatewayTurnStatus(
          kind: 'subagent',
          text: context.l10n.delegated_task(update.goal),
        );
      }
    });
    _scheduleStreamingFollow();
  }

  Future<void> _respondToGatewayApproval(
    String choice, {
    String? requestId,
  }) async {
    final handled =
        await _turnApplicationSession?.tryRespondToApproval(
          sessionId: widget.session.id,
          choice: choice,
          requestId: requestId,
        ) ??
        false;
    if (handled) return;
    final gateway = _desktopGateway;
    if (gateway == null) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await gateway.respondToApproval(
      sessionId: widget.session.id,
      choice: choice,
      serverRequestId: requestId,
    );
  }

  /// Answers approvals that notification actions left pending for this
  /// connection. Entries are removed only after the gateway confirms the
  /// answer: a cold start (no route-local session yet) or a throw keeps the
  /// tap pending for a later retry instead of losing it.
  void _consumePendingNotificationApproval() {
    final mine = [
      for (final approval in pendingNotificationApprovals.value)
        if (approval.connectionId == widget.connection.id &&
            approval.sessionId == widget.session.id)
          approval,
    ];
    for (final approval in mine) {
      unawaited(_answerPendingNotificationApproval(approval));
    }
  }

  /// Approvals whose answer is in flight, so a notifier change cannot
  /// dispatch the same request twice.
  final Set<String> _answeringPendingApprovals = {};

  Future<void> _answerPendingNotificationApproval(
    PendingNotificationApproval approval,
  ) async {
    final key =
        '${approval.connectionId}|${approval.sessionId}|${approval.requestId}';
    if (_answeringPendingApprovals.contains(key)) return;
    _answeringPendingApprovals.add(key);
    try {
      // The normal approval path: route-local turn session first, then the
      // desktop gateway. A throw means the route-local gateway is not up
      // yet (cold start/reconnect) — keep the entry and retry later.
      await _respondToGatewayApproval(
        approval.choice,
        requestId: approval.requestId,
      );
      removePendingNotificationApproval(approval);
    } catch (_) {
      // Unresolved, not answered: keep the entry for a later retry.
    } finally {
      _answeringPendingApprovals.remove(key);
    }
  }

  /// Sends the answer the user submitted from a clarify card.
  ///
  /// Records the prompt as self-answered for the duration of the send so the
  /// remaining-questions reconcile does not close the card's route a second
  /// time (see [_selfAnsweredClarifyIdentities]).
  Future<void> _answerClarifyPrompt(
    GatewayClarifyRequest request,
    String answer,
  ) async {
    _selfAnsweredClarifyIdentities.add(request.identityKey);
    try {
      await _respondToGatewayClarify(
        requestId: request.requestId,
        questionId: request.questionId,
        answer: answer,
      );
    } catch (_) {
      // A failed send keeps the card open for a retry, so the reconcile may
      // own the route again.
      _selfAnsweredClarifyIdentities.remove(request.identityKey);
      rethrow;
    }
  }

  /// Whether the open clarify card still belongs to [request].
  ///
  /// A `request.cancel` arriving while `clarify.lock` is pending closes the
  /// card itself, and the drain can open the next question's card before the
  /// late answer (the gateway reports `status: expired`) resolves. A card may
  /// only close the route it still owns: popping otherwise takes whatever is
  /// on top — the chat screen, or the next question's card — with it.
  bool _ownsClarifyPromptRoute(GatewayClarifyRequest request) {
    return _clarifyPromptRouteOpen &&
        !_clarifyPromptClosing &&
        _activeClarifyPrompt?.request.identityKey == request.identityKey;
  }

  void _closeClarifyPromptRoute() {
    if (_clarifyPromptClosing) return;
    final route = _clarifyPromptRoute;
    if (route == null) {
      // showDialog pushed the route but its builder has not run yet.
      // Wait for its identity rather than popping an unrelated top route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _clarifyPromptRouteOpen && _clarifyPromptRoute != null) {
          _closeClarifyPromptRoute();
        }
      });
      return;
    }
    _clarifyPromptClosing = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (route.isCurrent) {
      navigator.pop(false);
    } else {
      // A newer approval may be above clarify. Expiring clarify must not
      // dismiss that independent request or send an unintended denial.
      navigator.removeRoute(route, false);
    }
  }

  Future<void> _respondToGatewayClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async {
    final handled =
        await _turnApplicationSession?.tryRespondToClarify(
          requestId: requestId,
          answer: answer,
          questionId: questionId,
        ) ??
        false;
    if (handled) return;
    final gateway = _desktopGateway;
    if (gateway == null) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await gateway.respondToClarify(
      requestId: requestId,
      answer: answer,
      questionId: questionId,
    );
  }

  Future<void> _respondToGatewaySudo({
    required String requestId,
    required String password,
  }) async {
    final handled =
        await _turnApplicationSession?.tryRespondToSudo(
          requestId: requestId,
          password: password,
        ) ??
        false;
    if (handled) return;
    final gateway = _desktopGateway;
    if (gateway == null) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await gateway.respondToSudo(requestId: requestId, password: password);
  }

  Future<void> _respondToGatewaySecret({
    required String requestId,
    required String value,
  }) async {
    final handled =
        await _turnApplicationSession?.tryRespondToSecret(
          requestId: requestId,
          value: value,
        ) ??
        false;
    if (handled) return;
    final gateway = _desktopGateway;
    if (gateway == null) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await gateway.respondToSecret(requestId: requestId, value: value);
  }

  bool _ownsGatewayApproval(String requestId) {
    final turnSession = _turnApplicationSession;
    if (turnSession != null &&
        turnSession.ownsApprovalRequest(
          sessionId: widget.session.id,
          requestId: requestId,
        )) {
      return true;
    }
    return _desktopGateway?.ownsApprovalRequest(
          widget.session.id,
          requestId: requestId,
        ) ??
        false;
  }

  void _showGatewayApproval(
    Map<String, dynamic> eventData,
    int responseGeneration,
  ) {
    if (_approvalDialogOpen) return;
    final request = GatewayApprovalRequest.fromEventData(eventData);
    final rawServerRequestId = eventData['server_request_id']
        ?.toString()
        .trim();
    final serverRequestId = rawServerRequestId?.isEmpty == true
        ? null
        : rawServerRequestId;
    _approvalDialogOpen = true;
    _activeApprovalServerRequestId = serverRequestId;
    _notifyApprovalRequest(request, serverRequestId);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final wasCancelledBeforeOpen =
          serverRequestId != null &&
          _cancelledInteractiveRequestIds.remove(serverRequestId);
      if (!mounted ||
          responseGeneration != _responseGeneration ||
          wasCancelledBeforeOpen) {
        _approvalDialogOpen = false;
        _activeApprovalServerRequestId = null;
        return;
      }
      if (serverRequestId != null && !_ownsGatewayApproval(serverRequestId)) {
        _approvalDialogOpen = false;
        _activeApprovalServerRequestId = null;
        return;
      }
      if (_desktopGateway == null && _turnApplicationSession == null) {
        _approvalDialogOpen = false;
        _activeApprovalServerRequestId = null;
        return;
      }

      _approvalRouteOpen = true;
      final responded = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => GatewayApprovalDialog(
          request: request,
          onRespond: (choice) => _respondToGatewayApproval(
            choice.wireValue,
            requestId: serverRequestId,
          ),
        ),
      );
      _approvalRouteOpen = false;
      _approvalDialogOpen = false;
      final wasCancelled =
          serverRequestId != null &&
          _cancelledInteractiveRequestIds.remove(serverRequestId);
      _activeApprovalServerRequestId = null;
      _drainClarifyPromptQueue();
      _drainSensitivePromptQueue();

      // System Back is treated as a denial. This prevents a dismissed mobile
      // dialog from leaving the gateway turn blocked indefinitely. A gateway
      // cancellation closes the same route but must not emit a late denial.
      if (responded != true &&
          !wasCancelled &&
          mounted &&
          responseGeneration == _responseGeneration) {
        try {
          await _respondToGatewayApproval(
            GatewayApprovalChoice.deny.wireValue,
            requestId: serverRequestId,
          );
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.could_not_deny_the_command(error)),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    });
  }

  void _queueSensitivePrompt(StreamEvent event, int responseGeneration) {
    final kind = event.type == 'sudo.request'
        ? GatewaySensitivePromptKind.sudo
        : GatewaySensitivePromptKind.secret;
    final request = GatewaySensitivePromptRequest.fromEventData(
      kind: kind,
      data: event.data,
      l10n: context.l10n,
    );
    if (request == null) return;
    final duplicate =
        _expiredSensitivePromptIds.contains(request.requestId) ||
        _activeSensitivePrompt?.request.requestId == request.requestId ||
        _sensitivePromptQueue.any(
          (pending) => pending.request.requestId == request.requestId,
        );
    if (duplicate) return;
    _sensitivePromptQueue.add(
      _PendingSensitivePrompt(request, responseGeneration),
    );
    _drainSensitivePromptQueue();
  }

  void _drainSensitivePromptQueue() {
    if (!mounted ||
        _approvalDialogOpen ||
        _activeClarifyPrompt != null ||
        _activeSensitivePrompt != null ||
        _sensitivePromptQueue.isEmpty) {
      return;
    }
    final pending = _sensitivePromptQueue.removeAt(0);
    _activeSensitivePrompt = pending;
    _notifyInputRequest(
      eventId: pending.request.requestId,
      body: pending.request.description.isNotEmpty
          ? pending.request.description
          : pending.request.title,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          pending.responseGeneration != _responseGeneration ||
          _expiredSensitivePromptIds.contains(pending.request.requestId) ||
          _activeSensitivePrompt?.request.requestId !=
              pending.request.requestId) {
        _expiredSensitivePromptIds.remove(pending.request.requestId);
        _activeSensitivePrompt = null;
        _drainSensitivePromptQueue();
        return;
      }
      final desktopGateway = _desktopGateway;
      if (desktopGateway == null) {
        _activeSensitivePrompt = null;
        _drainSensitivePromptQueue();
        return;
      }

      _sensitivePromptRouteOpen = true;
      final result = await showDialog<GatewaySensitivePromptDialogResult>(
        context: context,
        barrierDismissible: true,
        builder: (_) => GatewaySensitivePromptDialog(
          request: pending.request,
          onRespond: (value) => switch (pending.request.kind) {
            GatewaySensitivePromptKind.sudo => _respondToGatewaySudo(
              requestId: pending.request.requestId,
              password: value,
            ),
            GatewaySensitivePromptKind.secret => _respondToGatewaySecret(
              requestId: pending.request.requestId,
              value: value,
            ),
          },
        ),
      );
      _sensitivePromptRouteOpen = false;
      _expiredSensitivePromptIds.remove(pending.request.requestId);

      if (_activeSensitivePrompt?.request.requestId ==
          pending.request.requestId) {
        _activeSensitivePrompt = null;
      }
      if (result == null &&
          mounted &&
          pending.responseGeneration == _responseGeneration) {
        try {
          switch (pending.request.kind) {
            case GatewaySensitivePromptKind.sudo:
              await _respondToGatewaySudo(
                requestId: pending.request.requestId,
                password: '',
              );
              break;
            case GatewaySensitivePromptKind.secret:
              await _respondToGatewaySecret(
                requestId: pending.request.requestId,
                value: '',
              );
              break;
          }
        } catch (_) {
          // The request may have expired while the route was closing. Never
          // include a sensitive value in an error message or diagnostic.
        }
      }
      _drainClarifyPromptQueue();
      _drainSensitivePromptQueue();
    });
  }

  void _expireSensitivePrompt(StreamEvent event) {
    final requestId = event.data['request_id']?.toString().trim() ?? '';
    if (requestId.isEmpty) return;
    _expiredSensitivePromptIds.add(requestId);
    _sensitivePromptQueue.removeWhere(
      (pending) => pending.request.requestId == requestId,
    );
    if (_activeSensitivePrompt?.request.requestId == requestId &&
        _sensitivePromptRouteOpen) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).pop(GatewaySensitivePromptDialogResult.expired);
    } else if (_activeSensitivePrompt?.request.requestId != requestId) {
      _expiredSensitivePromptIds.remove(requestId);
    }
  }

  void _cancelGatewayServerRequest(StreamEvent event) {
    final requestId = event.data['id']?.toString().trim() ?? '';
    final method = event.data['method']?.toString().trim() ?? '';
    if (requestId.isEmpty) return;

    if (method == 'sudo' || method == 'secret') {
      _expireSensitivePrompt(
        StreamEvent(type: '$method.expire', data: {'request_id': requestId}),
      );
      return;
    }

    _cancelledInteractiveRequestIds.add(requestId);
    if (method == 'clarify') {
      _clarifyPromptQueue.removeWhere(
        (pending) => pending.request.requestId == requestId,
      );
      if (_activeClarifyPrompt?.request.requestId == requestId &&
          _clarifyPromptRouteOpen) {
        _closeClarifyPromptRoute();
      } else if (_activeClarifyPrompt?.request.requestId != requestId) {
        _cancelledInteractiveRequestIds.remove(requestId);
      }
      return;
    }

    if (method == 'approval') {
      if (_activeApprovalServerRequestId == requestId && _approvalRouteOpen) {
        Navigator.of(context, rootNavigator: true).pop(false);
      } else if (_activeApprovalServerRequestId != requestId) {
        _cancelledInteractiveRequestIds.remove(requestId);
      }
    }
  }

  void _reconcileClarifyPrompts(StreamEvent event) {
    final requestId = event.data['id']?.toString().trim() ?? '';
    final rawRemaining = event.data['remaining'];
    if (requestId.isEmpty || rawRemaining is! List) return;
    final remaining = rawRemaining.map((value) => value.toString()).toSet();
    _clarifyPromptQueue.removeWhere(
      (pending) =>
          pending.request.requestId == requestId &&
          !remaining.contains(pending.request.questionId),
    );
    final active = _activeClarifyPrompt;
    if (active?.request.requestId != requestId ||
        remaining.contains(active?.request.questionId)) {
      return;
    }
    // An answer the user sent from this card closes its own route once the
    // lock lands. The reconcile is for questions resolved elsewhere, so leave
    // the route alone here instead of popping it twice.
    if (_selfAnsweredClarifyIdentities.remove(active!.request.identityKey)) {
      return;
    }
    _cancelledInteractiveRequestIds.add(requestId);
    if (_clarifyPromptRouteOpen) {
      _closeClarifyPromptRoute();
    } else {
      _activeClarifyPrompt = null;
      _cancelledInteractiveRequestIds.remove(requestId);
      _drainClarifyPromptQueue();
    }
  }

  void _queueClarifyPrompt(
    Map<String, dynamic> eventData,
    int responseGeneration,
  ) {
    final requests = GatewayClarifyRequest.fromEventDataList(eventData);
    if (requests.isEmpty) return;
    for (final request in requests) {
      final duplicate =
          _activeClarifyPrompt?.request.identityKey == request.identityKey ||
          _clarifyPromptQueue.any(
            (pending) => pending.request.identityKey == request.identityKey,
          );
      if (duplicate) continue;
      _clarifyPromptQueue.add(
        _PendingClarifyPrompt(request, responseGeneration),
      );
    }
    _drainClarifyPromptQueue();
  }

  void _drainClarifyPromptQueue() {
    if (!mounted ||
        _approvalDialogOpen ||
        _activeSensitivePrompt != null ||
        _activeClarifyPrompt != null ||
        _clarifyPromptQueue.isEmpty) {
      return;
    }
    final pending = _clarifyPromptQueue.removeAt(0);
    _activeClarifyPrompt = pending;
    _notifyInputRequest(
      eventId: pending.request.identityKey,
      body: pending.request.question,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          pending.responseGeneration != _responseGeneration ||
          _cancelledInteractiveRequestIds.remove(pending.request.requestId) ||
          _activeClarifyPrompt?.request.identityKey !=
              pending.request.identityKey) {
        _activeClarifyPrompt = null;
        _drainSensitivePromptQueue();
        _drainClarifyPromptQueue();
        return;
      }
      final desktopGateway = _desktopGateway;
      if (desktopGateway == null) {
        _activeClarifyPrompt = null;
        _drainSensitivePromptQueue();
        _drainClarifyPromptQueue();
        return;
      }

      _clarifyPromptRouteOpen = true;
      final responded = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          _clarifyPromptRoute = ModalRoute.of<bool>(dialogContext);
          return GatewayClarifyDialog(
            request: pending.request,
            onRespond: (answer) =>
                _answerClarifyPrompt(pending.request, answer),
            canCloseRoute: () => _ownsClarifyPromptRoute(pending.request),
          );
        },
      );
      _clarifyPromptRouteOpen = false;
      _clarifyPromptRoute = null;
      _clarifyPromptClosing = false;
      _selfAnsweredClarifyIdentities.remove(pending.request.identityKey);
      final wasCancelled = _cancelledInteractiveRequestIds.remove(
        pending.request.requestId,
      );
      if (_activeClarifyPrompt?.request.identityKey ==
          pending.request.identityKey) {
        _activeClarifyPrompt = null;
      }

      // System Back or a barrier dismiss maps to the official empty answer,
      // matching Hermes Desktop's Skip behavior. Batch questions skip
      // per-question so the remaining questions can still be answered. A
      // gateway cancellation closes the same route without answering it.
      if (responded != true &&
          !wasCancelled &&
          mounted &&
          pending.responseGeneration == _responseGeneration) {
        try {
          await _respondToGatewayClarify(
            requestId: pending.request.requestId,
            questionId: pending.request.questionId,
            answer: '',
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.could_not_skip_the_hermes_question),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      _drainSensitivePromptQueue();
      _drainClarifyPromptQueue();
    });
  }

  Future<void> _stopResponse() async {
    if (!_streaming) return;

    final transport = _activeResponseTransport;
    final activeClientTurnId = _activeClientTurnId;
    _stopResponseInFlight = true;
    ++_responseGeneration;
    _scrollCoordinator.cancelStreaming();
    setState(() {
      _streaming = false;
      _sending = false;
      _gatewayTurnStatus = null;
      _awaitingVoiceReply = false;
      _activeResponseTransport = _ResponseTransport.none;
      _activeClientTurnId = null;
      if (_messages.isNotEmpty &&
          _messages.last['role'] == 'assistant' &&
          (_messages.last['content']?.toString().isEmpty ?? true)) {
        _messages.removeLast();
      }
    });

    try {
      GatewayTurnRecoveryState? interruptedTurnState;
      bool interrupted;
      switch (transport) {
        case _ResponseTransport.rest:
          interrupted = await _gateway.cancelActiveMessage();
        case _ResponseTransport.desktop:
          if (_turnApplicationSession != null && activeClientTurnId != null) {
            // Keep the authoritative terminal state from the interrupt so
            // the partial assistant message gets the real final content
            // + terminal markers instead of whatever streamed before the
            // stop. Previously only .status was read for the snackbar and
            // the state was discarded: navigating away before the next
            // resume left truncated text displayed as if complete.
            final state = await _turnApplicationSession!.interrupt(
              localSessionId: widget.session.id,
              clientTurnId: activeClientTurnId,
            );
            interruptedTurnState = state;
            interrupted = state.status?.isTerminal == true;
          } else {
            interrupted =
                await _desktopGateway?.interruptPrompt(
                  sessionId: widget.session.id,
                ) ??
                false;
          }
        case _ResponseTransport.none:
          interrupted = false;
      }
      if (!mounted) return;
      if (interruptedTurnState != null) {
        // Route through the shared apply path (idempotent): the terminal
        // state updates the message content/markers and clears the
        // pending-response flag exactly as a live terminal event would.
        _applyGatewayTurnState(interruptedTurnState);
      } else if (interrupted) {
        setState(() {
          final assistant = _lastAssistantMessage();
          if (assistant != null) {
            assistant['_gateway_pending_response'] = false;
          }
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            interrupted
                ? context.l10n.response_stopped
                : context
                      .l10n
                      .response_closed_locally_no_active_gateway_turn_was_found,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.response_closed_locally_gateway_stop_failed(error),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      _stopResponseInFlight = false;
      unawaited(_refreshDeferredHistoryIfIdle());
    }
  }

  /// Clears the composer and its stored draft at the same boundary, so a
  /// process kill right after sending cannot resurrect the sent prompt.
  void _clearComposerForSend() {
    _textController.clear();
    unawaited(
      ComposerDraftStore.save(
        connectionId: widget.connection.id,
        sessionId: widget.session.id,
        text: '',
      ),
    );
  }

  /// A definite send rejection: put the text back into the composer and the
  /// store so the user does not lose what they typed.
  void _restoreComposerAfterRejectedSend(String text) {
    if (text.trim().isEmpty) return;
    _textController.text = text;
    _textController.selection = TextSelection.collapsed(offset: text.length);
    unawaited(
      ComposerDraftStore.save(
        connectionId: widget.connection.id,
        sessionId: widget.session.id,
        text: text,
      ),
    );
  }

  void _handleSendError(Object e, {bool removePendingUserMessage = false}) {
    _scrollCoordinator.cancelStreaming();
    setState(() {
      _sending = false;
      _streaming = false;
      _gatewayTurnStatus = null;
      _activeResponseTransport = _ResponseTransport.none;
      _awaitingVoiceReply = false;
      if (removePendingUserMessage &&
          _messages.isNotEmpty &&
          _messages.last['role'] == 'user') {
        _messages.removeLast();
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.send_failed(e)),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  void _upsertToolProgress(
    Map<String, dynamic> progress, {
    String eventType = 'tool.start',
  }) {
    final update = GatewayToolActivity.fromGatewayEvent(
      eventType,
      progress,
      observedAt: DateTime.now(),
    );
    if (update == null) return;
    setState(() {
      var idx = update.toolId == null
          ? -1
          : _toolActivities.indexWhere(
              (activity) => activity.toolId == update.toolId,
            );
      if (idx < 0) {
        // A different gateway tool id is a different call, even when two
        // concurrent calls share the same tool name. Only id-less updates can
        // fall back to the most recent active call by name.
        idx = _toolActivities.lastIndexWhere(
          (activity) =>
              !activity.isTerminal &&
              (update.toolId == null || activity.toolId == null) &&
              activity.name.toLowerCase() == update.name.toLowerCase(),
        );
      }
      if (idx >= 0) {
        final previous = _toolActivities[idx];
        _toolActivities[idx] = previous.merge(update);
        if (previous.toolId == null && update.toolId != null) {
          _toolActivityPins.alias(previous.identity, 'tool:${update.toolId}');
        }
      } else {
        _toolActivities.add(update);
      }
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'tool',
        text: update.isTerminal
            ? '${update.displayName}: ${update.statusLabel.toLowerCase()}'
            : context.l10n.using(update.displayName),
      );
    });

    _scheduleStreamingFollow();
  }

  bool get _transcriptLoadBlocksComposer =>
      _loading &&
      _desktopGateway == null &&
      _turnApplicationSession == null &&
      widget.testRemotePromptSubmit == null;

  ChatConnectionStatus get _chatConnectionStatus {
    if (_desktopGateway == null) {
      if (_loading) return ChatConnectionStatus.connecting;
      return _error == null
          ? ChatConnectionStatus.connected
          : ChatConnectionStatus.offline;
    }
    return switch (_desktopConnectionState) {
      DesktopConnectionState.connected => ChatConnectionStatus.connected,
      DesktopConnectionState.connecting => ChatConnectionStatus.connecting,
      DesktopConnectionState.reconnecting => ChatConnectionStatus.reconnecting,
      DesktopConnectionState.disconnected => ChatConnectionStatus.offline,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          widget.session.title.trim().isEmpty
              ? context.l10n.untitled_chat
              : widget.session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ChatContextHeader(
            projectName: _projectName,
            model: _sessionModel ?? widget.session.model,
            reasoningEffort: _sessionReasoningEffort ?? 'default',
            connectionLabel: widget.connection.label,
            connectionStatus: _chatConnectionStatus,
          ),
        ),
        actions: [
          if (_streaming)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(context.l10n.responding, style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: context.l10n.chat_actions,
              onSelected: (action) {
                if (action == 'record-voice') {
                  unawaited(_voiceRecording.start());
                }
                if (action == 'refresh' && !_pendingReattachResync) {
                  _fetchMessages();
                }
                if (action == 'export') _exportConversation();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'record-voice',
                  enabled:
                      !_voiceComposer.listening &&
                      !_voiceRecording.busy &&
                      !_voiceRecording.recording &&
                      !_voiceRecording.hasDraft &&
                      !_pendingReattachResync,
                  child: ListTile(
                    leading: const Icon(Icons.mic),
                    title: Text(context.l10n.voice_recording_start),
                  ),
                ),
                PopupMenuItem(
                  value: 'refresh',
                  enabled: !_pendingReattachResync,
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text(context.l10n.refresh),
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.ios_share_outlined),
                    title: Text(context.l10n.export_share),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.isTablet(context) ? 800 : double.infinity,
          ),
          child: Column(
            children: [
              for (final notification in _gatewayNotifications.values)
                _buildGatewayNotification(notification),
              if (_legacyTransportFallback)
                Container(
                  key: const ValueKey('legacy-transport-notice'),
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    _stockGatewayFallback
                        ? context
                              .l10n
                              .this_server_doesn_t_offer_background_recovery_chats_run_live
                        : context
                              .l10n
                              .background_recovery_unavailable_legacy_transport,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, viewport) => Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(child: _buildBody()),
                            if (_endAffordanceController.isVisible)
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: ChatEndAffordance(
                                  newMessageCount:
                                      _endAffordanceController.newMessageCount,
                                  onPressed: _goToEnd,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildInputBar(availableHeight: viewport.maxHeight),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGatewayNotification(GatewayNotification notification) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (notification.level) {
      GatewayNotificationLevel.success => Colors.green,
      GatewayNotificationLevel.warning => Colors.orange,
      GatewayNotificationLevel.error => scheme.error,
      GatewayNotificationLevel.info => scheme.primary,
    };
    return MaterialBanner(
      backgroundColor: color.withValues(alpha: 0.12),
      leading: Icon(Icons.notifications_outlined, color: color),
      content: SelectionArea(child: Text(notification.text)),
      actions: [
        TextButton(
          onPressed: () {
            _notificationTimers.remove(notification.key)?.cancel();
            setState(() => _gatewayNotifications.remove(notification.key));
          },
          child: Text(context.l10n.dismiss),
        ),
      ],
    );
  }

  Widget _buildInputBar({required double availableHeight}) {
    const minimumControlsHeight = 56.0;
    final composerMaxHeight = availableHeight <= minimumControlsHeight
        ? availableHeight
        : (availableHeight * 0.85)
              .clamp(minimumControlsHeight, availableHeight)
              .toDouble();
    return Container(
      key: const Key('chat-input-bar'),
      // Leave some transcript visible when space permits. At very small
      // heights, the fixed controls take priority and extras scroll away.
      constraints: BoxConstraints(maxHeight: composerMaxHeight),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.1)),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_voiceRecording.recording ||
                        _voiceRecording.hasDraft ||
                        _voiceRecording.busy ||
                        _voiceRecording.error != null)
                      VoiceRecordingControls(
                        controller: _voiceRecording,
                        canSend:
                            !_sending &&
                            !_streaming &&
                            !_pendingReattachResync &&
                            !_voiceComposer.listening,
                        onSend: () => unawaited(_sendRecordedVoice()),
                      ),

                    if (_gatewayTurnStatus != null && (_sending || _streaming))
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _gatewayTurnStatus!.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                        child: Semantics(
                          label: context.l10n.choose_chat_model,
                          value: _sessionModel ?? widget.session.model,
                          button: true,
                          enabled:
                              !(_sending ||
                                  _streaming ||
                                  _pendingReattachResync ||
                                  _loadingModelOptions ||
                                  _changingModel),
                          excludeSemantics: true,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: TextButton.icon(
                              onPressed:
                                  (_sending ||
                                      _streaming ||
                                      _pendingReattachResync ||
                                      _loadingModelOptions ||
                                      _changingModel)
                                  ? null
                                  : _showModelSelector,
                              icon: _loadingModelOptions || _changingModel
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.tune, size: 18),
                              label: Text(
                                context.l10n.model_scope_label(
                                  _sessionModel ?? widget.session.model,
                                  _sessionModelOverride
                                      ? context.l10n.this_chat
                                      : context.l10n.profile_default,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_attachmentDrafts.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Semantics(
                          label: context.l10n.attachment_drafts,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              // Scaffold has already subtracted the keyboard and app bar.
                              maxHeight: availableHeight * 0.32,
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _attachmentDrafts.length,
                              itemBuilder: (context, index) =>
                                  AttachmentDraftTile(
                                    draft: _attachmentDrafts[index],
                                    index: index,
                                    total: _attachmentDrafts.length,
                                    busy: _sending,
                                    onMovePrevious: () => _moveAttachment(
                                      _attachmentDrafts[index],
                                      -1,
                                    ),
                                    onMoveNext: () => _moveAttachment(
                                      _attachmentDrafts[index],
                                      1,
                                    ),
                                    onRetry: () => _retryAttachment(
                                      _attachmentDrafts[index],
                                    ),
                                    onRemove: () => _removeAttachment(
                                      _attachmentDrafts[index],
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                    if (_voiceComposer.listening)
                      VoiceComposerIndicator(
                        controller: _voiceComposer,
                        onStop: () => unawaited(_voiceComposer.stop()),
                        onCancel: () => unawaited(_voiceComposer.cancel()),
                      ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Semantics(
                  label: context.l10n.add_attachment,
                  button: true,
                  enabled:
                      !_transcriptLoadBlocksComposer &&
                      !_voiceRecording.busy &&
                      !_voiceRecording.recording &&
                      !_streaming &&
                      !_sending &&
                      !_pendingReattachResync,
                  excludeSemantics: true,
                  child: IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed:
                        (!_transcriptLoadBlocksComposer &&
                            !_voiceRecording.busy &&
                            !_voiceRecording.recording &&
                            !_streaming &&
                            !_sending &&
                            !_pendingReattachResync)
                        ? _showAttachmentPicker
                        : null,
                    tooltip: context.l10n.attach_image_or_file,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    label: context.l10n.message,
                    textField: true,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (availableHeight * 0.30).clamp(48.0, 160.0),
                      ),
                      child: TextField(
                        key: const Key('chat-message-composer'),
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: context.l10n.message_hermes,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.send,
                        enabled:
                            !_transcriptLoadBlocksComposer &&
                            !_voiceRecording.busy &&
                            !_voiceRecording.recording &&
                            !_streaming &&
                            !_pendingReattachResync,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_voiceComposer.listening)
                  VoiceComposerStartButton(
                    enabled:
                        !_transcriptLoadBlocksComposer &&
                        !_voiceRecording.busy &&
                        !_voiceRecording.recording &&
                        !_streaming &&
                        !_sending &&
                        !_pendingReattachResync,
                    onPressed: _startVoiceInput,
                  ),
                Semantics(
                  label: context.l10n.spoken_replies,
                  value: _voiceReplyEnabled
                      ? context.l10n.on
                      : context.l10n.off,
                  toggled: _voiceReplyEnabled,
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    icon: Icon(
                      _voiceReplyEnabled ? Icons.volume_up : Icons.volume_off,
                    ),
                    onPressed: () {
                      setState(() => _voiceReplyEnabled = !_voiceReplyEnabled);
                      if (!_voiceReplyEnabled) {
                        _flutterTts.stop();
                      }
                    },
                    tooltip: _voiceReplyEnabled
                        ? context.l10n.spoken_replies_on
                        : context.l10n.spoken_replies_off,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: _streaming
                      ? context.l10n.stop_response
                      : context.l10n.send_message,
                  button: true,
                  enabled:
                      _streaming ||
                      (!_transcriptLoadBlocksComposer &&
                          !_voiceRecording.busy &&
                          !_voiceRecording.recording &&
                          !_sending &&
                          !_pendingReattachResync &&
                          !_voiceComposer.listening),
                  excludeSemantics: true,
                  child: SizedBox.square(
                    dimension: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: _streaming
                          ? IconButton(
                              icon: const Icon(Icons.stop_rounded, size: 20),
                              onPressed: _stopResponse,
                              tooltip: context.l10n.stop_response,
                              constraints: const BoxConstraints.tightFor(
                                width: 48,
                                height: 48,
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.send, size: 20),
                              onPressed:
                                  _transcriptLoadBlocksComposer ||
                                      _voiceRecording.busy ||
                                      _voiceRecording.recording ||
                                      _sending ||
                                      _pendingReattachResync ||
                                      _voiceComposer.listening
                                  ? null
                                  : _sendMessage,
                              tooltip: context.l10n.send,
                              constraints: const BoxConstraints.tightFor(
                                width: 48,
                                height: 48,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                context.l10n.failed_to_load_messages,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchMessages,
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    final displayMessages = buildChatDisplayItems(
      messages: _messages,
      toolActivities: _toolActivities,
      subagentActivities: _subagentActivities,
      notices: _gatewayNotices,
      verbose: _verboseMode,
    );

    // The stored row is the durable anchor once available. Carry a pin made
    // while this group was still streaming across the tool-id → row-id handoff.
    for (final group in displayMessages.whereType<ChatToolActivityGroup>()) {
      final toolId = group.activities.first.toolId;
      if (group.id.startsWith('message:') &&
          toolId != null &&
          toolId.isNotEmpty) {
        _toolActivityPins.alias('tool:$toolId', group.id);
      }
    }

    final list = NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _syncEndAffordance(notification.metrics, clearUnreadAtEnd: false);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.only(bottom: _chatDensity.listEndPadding),
          itemCount: displayMessages.length + (_historyWindow.hasOlder ? 1 : 0),
          itemBuilder: (context, index) {
            if (_historyWindow.hasOlder && index == 0) {
              return Center(
                child: TextButton(
                  key: const Key('chat-load-older'),
                  onPressed: _loadingOlder || _sending || _streaming
                      ? null
                      : _loadOlderMessages,
                  child: _loadingOlder
                      ? const CircularProgressIndicator()
                      : Text(context.l10n.load_more),
                ),
              );
            }
            final item =
                displayMessages[index - (_historyWindow.hasOlder ? 1 : 0)];

            if (item is ChatToolActivityGroup) {
              return GatewayActivityCard(
                key: ValueKey<String>('tool-activity-${item.id}'),
                activities: item.activities,
                verbose: _verboseMode,
                pinnedExpansion: _toolActivityPins[item.id],
                onPinChanged: (expanded) {
                  _toolActivityPins.pin(item.id, expanded);
                  final toolId = item.activities.first.toolId;
                  if (toolId != null && toolId.isNotEmpty) {
                    _toolActivityPins.alias(item.id, 'tool:$toolId');
                  }
                },
              );
            }
            if (item is List<GatewaySubagentActivity>) {
              return GatewaySubagentCard(activities: item);
            }
            if (item is ChatReasoningItem) {
              return GatewayReasoningCard(
                text: item.text,
                initiallyExpanded: item.initiallyExpanded,
              );
            }
            if (item is GatewayNotice) {
              return GatewayNoticeCard(notice: item);
            }

            final msg = item as Map<String, dynamic>;
            final role = (msg['role'] as String?) ?? 'assistant';
            final content =
                (msg['_display_content'] as String?) ??
                stripToolResultText(messageContentToText(msg['content']));
            final isUser = role == 'user';

            return MessageBubble(
              content: content,
              isUser: isUser,
              verbose: _verboseMode,
              density: _chatDensity,
              metadata: msg,
              mediaReferencesFinal: msg['_gateway_pending_response'] != true,
              mediaFilesClient: isUser
                  ? null
                  : () =>
                        widget.testMediaFilesClient?.call(_storedSessionKey) ??
                        RemoteFilesClient.fromConnection(
                          widget.connection,
                          sessionId: _storedSessionKey,
                        ),
              onReadAloud: isUser
                  ? null
                  : () => _readAssistantText(content, announce: true),
              onEdit: isUser ? () => _editAndResend(content) : null,
              onRetry: isUser
                  ? null
                  : () => _retryPrompt(msg['_retry_prompt']?.toString() ?? ''),
            );
          },
        ),
      ),
    );
    if (!_loading && _error == null) return list;
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          MaterialBanner(
            content: Text(context.l10n.failed_to_load_messages),
            actions: [
              TextButton(
                onPressed: () => unawaited(_fetchMessages()),
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        Expanded(child: list),
      ],
    );
  }

  Future<void> _applySessionModelOverride(
    DesktopGatewayClient desktopGateway,
  ) async {
    final provider = _sessionProvider;
    final model = _sessionModel;
    if (!_sessionModelOverride || provider == null || model == null) return;
    await desktopGateway.setSessionModel(
      sessionId: widget.session.id,
      provider: provider,
      model: model,
    );
    final effort = _sessionReasoningEffort;
    if (effort != null) {
      await desktopGateway.setSessionReasoning(
        sessionId: widget.session.id,
        effort: effort,
      );
    }
  }
}

class MessageBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool verbose;
  final ChatDensity density;
  final Map<String, dynamic> metadata;
  final Future<void> Function()? onReadAloud;
  final VoidCallback? onEdit;
  final Future<void> Function()? onRetry;
  final bool mediaReferencesFinal;

  /// Gateway files client factory for `MEDIA:` artifact cards. Assistant
  /// bubbles without it render `MEDIA:` tags as prose (e.g. transcript views
  /// with no session to resolve paths against — a same-path local file on
  /// the phone would be worse than a dead link).
  final RemoteFilesDataSource Function()? mediaFilesClient;

  const MessageBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.verbose = false,
    this.density = ChatDensity.comfortable,
    this.metadata = const {},
    this.onReadAloud,
    this.onEdit,
    this.onRetry,
    this.mediaFilesClient,
    this.mediaReferencesFinal = true,
  });

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.message_copied),
          duration: Duration(seconds: 2),
        ),
      );
  }

  /// Opens the message in a selection-enabled dialog so a single sentence can
  /// be copied without taking the whole message. The rendering matches the
  /// bubble; the text is selectable with the platform handles, which keeps the
  /// long-press actions on the bubble itself untouched.
  Future<void> _showSelectTextDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // The dialog renders on the dialog surface, not on a bubble: use the
        // prose colours with the dialog's own onSurface. The user-bubble
        // foreground is hardcoded for the gold bubble and would be unreadable
        // on the dark dialog surface in dark mode.
        final dialogTheme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(context.l10n.select_text),
          content: SingleChildScrollView(
            child: MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: _messageStyleSheet(
                dialogTheme,
                isUser: false,
                assistantTextColor: dialogTheme.colorScheme.onSurface,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(context.l10n.close),
            ),
          ],
        );
      },
    );
  }

  MarkdownStyleSheet _messageStyleSheet(
    ThemeData theme, {
    required bool isUser,
    required Color assistantTextColor,
  }) {
    return MarkdownStyleSheet(
      p: (isUser
          ? theme.textTheme.bodyMedium?.copyWith(
              color: hermesUserMessageForeground,
            )
          : theme.textTheme.bodyMedium?.copyWith(color: assistantTextColor)),
      code: TextStyle(
        backgroundColor: (isUser ? Colors.white : Colors.black).withValues(
          alpha: 0.12,
        ),
        fontFamily: 'monospace',
        color: isUser ? hermesUserMessageForeground : null,
      ),
      a: TextStyle(
        color: isUser ? hermesUserMessageForeground : theme.colorScheme.primary,
      ),
      h1: isUser
          ? theme.textTheme.headlineSmall?.copyWith(
              color: hermesUserMessageForeground,
            )
          : theme.textTheme.headlineSmall,
      h2: isUser
          ? theme.textTheme.titleLarge?.copyWith(
              color: hermesUserMessageForeground,
            )
          : theme.textTheme.titleLarge,
      h3: isUser
          ? theme.textTheme.titleMedium?.copyWith(
              color: hermesUserMessageForeground,
            )
          : theme.textTheme.titleMedium,
      blockquote: TextStyle(
        color: isUser ? hermesUserMessageForeground : Colors.grey,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isUser
                ? hermesUserMessageForeground.withValues(alpha: 0.65)
                : theme.colorScheme.primary,
            width: 3,
          ),
        ),
      ),
      em: isUser
          ? theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: hermesUserMessageForeground,
            )
          : theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
      strong: isUser
          ? theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: hermesUserMessageForeground,
            )
          : theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  /// Splits assistant text on `MEDIA:` refs (when a files client is
  /// available) and renders each piece: prose through the markdown/code-block
  /// pipeline, standalone-line refs as download cards. Code fences are split
  /// out FIRST and stay verbatim — a `MEDIA:` example inside a code block is
  /// documentation, not a delivery. Mid-line refs stay in the prose as
  /// markdown links so they never fragment a list item or table row.
  List<Widget> _renderContent(
    ThemeData theme,
    bool isUser,
    Color assistantTextColor,
  ) {
    final styleSheet = _messageStyleSheet(
      theme,
      isUser: isUser,
      assistantTextColor: assistantTextColor,
    );
    final filesClient = !isUser ? mediaFilesClient : null;
    Widget prose(String text) => MarkdownBody(
      data: text,
      selectable: false,
      styleSheet: styleSheet,
      onTapLink: filesClient == null
          ? null
          : (linkText, href, title) {
              final path = href == null
                  ? null
                  : mediaPathFromArtifactHref(href);
              if (path == null) return;
              unawaited(
                downloadAndShareMediaFile(
                  filesClient: filesClient,
                  ref: MediaTagRef(path: path),
                ).catchError((Object e) {
                  debugPrint('media link download failed: $e');
                }),
              );
            },
    );

    final parseMedia = filesClient != null;
    final blocks = splitMarkdownCodeBlocks(content);
    final mediaOccurrences = <String, int>{};

    List<Widget> renderProse(String text) {
      if (!parseMedia) return [prose(text)];
      final segments = splitMediaTags(text, isFinal: mediaReferencesFinal);
      if (!segments.any((s) => s.isMedia)) {
        return [
          prose(inlineMediaTagsAsLinks(text, isFinal: mediaReferencesFinal)),
        ];
      }
      final widgets = <Widget>[];
      for (final segment in segments) {
        if (segment.isMedia) {
          final path = segment.media!.path;
          final occurrence = mediaOccurrences.update(
            path,
            (value) => value + 1,
            ifAbsent: () => 0,
          );
          widgets.add(
            MediaArtifactCard(
              // The occurrence ordinal keeps repeated paths unique while
              // remaining stable as a streamed suffix grows.
              key: ValueKey((path, occurrence)),
              ref: segment.media!,
              filesClient: filesClient,
            ),
          );
        } else if (segment.text.trim().isNotEmpty) {
          // Inline refs (mid-line) become markdown links in place.
          widgets.add(
            prose(
              inlineMediaTagsAsLinks(
                segment.text,
                isFinal: mediaReferencesFinal,
              ),
            ),
          );
        }
      }
      return widgets;
    }

    return [
      for (final block in blocks)
        if (block is MarkdownCodeBlock)
          block
        else
          ...renderProse(block as String),
    ];
  }

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // The sheet scrolls: at large text scales four 48 dp tiles plus the
      // header exceed the default sheet height, and an action a user cannot
      // reach is worse than one that scrolls.
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  context.l10n.message_actions,
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
              ),
              _actionTile(
                sheetContext,
                label: context.l10n.copy_message,
                tooltip: context.l10n.copy_message,
                icon: Icons.copy_outlined,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_copyMessage(context));
                },
              ),
              _actionTile(
                sheetContext,
                label: context.l10n.select_text,
                tooltip: context.l10n.select_text,
                icon: Icons.select_all,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_showSelectTextDialog(context));
                },
              ),
              if (onReadAloud != null)
                _actionTile(
                  sheetContext,
                  label: context.l10n.read_aloud,
                  tooltip: context.l10n.read_aloud,
                  icon: Icons.volume_up_outlined,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(onReadAloud!());
                  },
                ),
              if (onEdit != null)
                _actionTile(
                  sheetContext,
                  label: context.l10n.edit_and_resend,
                  tooltip: context.l10n.edit_and_resend,
                  icon: Icons.edit_outlined,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onEdit!();
                  },
                ),
              if (onRetry != null)
                _actionTile(
                  sheetContext,
                  label: context.l10n.regenerate_response,
                  tooltip: context.l10n.regenerate_response,
                  icon: Icons.refresh,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(onRetry!());
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required String label,
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          minTileHeight: 48,
          onTap: onTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Bubble colors
    const userBubbleColor = hermesUserMessageBubbleBackground;
    final assistantBubbleColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFEAEAEA);
    final assistantTextColor = isDark ? Colors.white : Colors.black87;

    // Collect extra metadata for verbose mode
    final List<String> metaLines = [];
    if (verbose) {
      final role = (metadata['role'] as String?) ?? 'unknown';
      metaLines.add('role: $role');
      // Show any extra fields that aren't role/content
      for (final entry in metadata.entries) {
        if (entry.key == 'role' || entry.key == 'content') continue;
        final value = entry.value?.toString() ?? 'null';
        if (value.length > 80) {
          metaLines.add('${entry.key}: ${value.substring(0, 80)}…');
        } else {
          metaLines.add('${entry.key}: $value');
        }
      }
    }

    final bubble = GestureDetector(
      key: const Key('message-bubble'),
      onLongPress: () => _showActions(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: density.bubbleMargin,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - density.maxWidthInset,
        ),
        padding: density.bubblePadding,
        decoration: BoxDecoration(
          color: isUser ? userBubbleColor : assistantBubbleColor,
          borderRadius: BorderRadius.circular(density.bubbleRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Role header keeps user and assistant prose clearly separated.
            // Compact density drops it: alignment and colour already identify
            // the speaker, and the label costs a line per message.
            if (density.showsSenderLabel)
              Padding(
                padding: EdgeInsets.only(bottom: density.senderLabelGap),
                child: Text(
                  isUser ? 'You' : 'Hermes',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isUser
                        ? hermesUserMessageForeground.withValues(alpha: 0.75)
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            // Verbose metadata header
            if (metaLines.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isUser ? Colors.white : Colors.black).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: metaLines
                      .map(
                        (line) => Text(
                          line,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isUser
                                ? hermesUserMessageForeground
                                : (isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600]),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
            // Message content: assistant `MEDIA:` refs become file cards;
            // prose renders as markdown and fenced code blocks render with
            // language, copy, and wrap controls. User bubbles never parse
            // MEDIA: — the contract is assistant-side delivery, and quoted
            // tags in a prompt must stay verbatim.
            ..._renderContent(theme, isUser, assistantTextColor),
            SizedBox(height: density.bodyBottomGap),
          ],
        ),
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      // Compact drops the visible label, but the speaker is still information:
      // keep it for screen readers instead of removing it from the tree.
      child: density.showsSenderLabel
          ? bubble
          : Semantics(
              container: true,
              label: isUser ? 'You' : 'Hermes',
              child: bubble,
            ),
    );
  }
}
