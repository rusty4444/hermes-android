// Chat screen with real-time streaming via REST API.
// Uses REST endpoints: POST /api/sessions/{id}/chat and
// GET /api/sessions/{id}/messages.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import '../widgets/session_name_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/voice_composer_controller.dart';
import '../controllers/delegated_task_controller.dart';
import '../services/delegated_task_history.dart';
import '../widgets/delegated_task_timeline.dart';
import '../widgets/delegated_task_labels.dart';
import '../services/connection_manager.dart';
import '../services/attachment_draft_service.dart';
import '../services/chat_presentation_state.dart';
import '../services/chat_model_override_store.dart';
import '../services/chat_density_preference.dart';
import '../services/chat_history_window.dart';
import '../services/desktop_gateway_client.dart';
import '../services/gateway_turn_application_controller.dart';
import '../services/normal_gateway_application_session.dart';
import '../services/gateway_turn_coordinator.dart';
import '../services/gateway_turn_recovery.dart';
import '../services/gateway_turn_ui_projection.dart';
import '../services/remote_files_client.dart';
import '../services/turn_notification_service.dart';
import '../services/notification_approval_authority.dart';
import '../services/notification_prefs.dart';
import '../services/voice_composer_adapter.dart';
import '../services/ws_client.dart';
import '../utils/media_tags.dart';
import '../utils/delivered_files.dart';
import '../utils/generated_media.dart';
import '../models/attachment_draft.dart';
import '../models/background_report.dart';
import '../models/chat_timeline.dart';
import '../models/received_scope_outcome.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_approval.dart';
import '../models/gateway_clarify.dart';
import '../models/gateway_insight.dart';
import '../models/gateway_sensitive_prompt.dart';
import '../models/gateway_turn_contract.dart';
import '../models/projects_tree_overview.dart';
import '../services/tool_activity_group_pins.dart';
import '../utils/chat_display_items.dart';
import '../utils/chat_received_recovery_projection.dart';
import '../utils/chat_conversation_projection.dart';
import '../models/chat_message_time.dart';
import '../utils/rest_chat_reply_retention.dart';
import '../utils/android_prompt_context.dart';
import '../utils/chat_history_scroll.dart';
import '../utils/message_content.dart';
import '../utils/responsive.dart';
import '../utils/turn_recovery_fallback.dart';
import '../theme/hermes_theme.dart';
import 'files_screen.dart';
import '../widgets/background_report_card.dart';
import '../widgets/gateway_activity_card.dart';
import '../widgets/chat_context_header.dart';
import '../widgets/chat_activity_bar.dart';
import '../widgets/markdown_code_block.dart';
import '../widgets/markdown_link_handler.dart';
import '../widgets/attachment_draft_tile.dart';
import '../widgets/chat_end_affordance.dart';
import '../widgets/received_recovery_inspector.dart';
import '../widgets/gateway_approval_dialog.dart';
import '../widgets/gateway_clarify_dialog.dart';
import '../widgets/gateway_insight_card.dart';
import '../widgets/gateway_sensitive_prompt_dialog.dart';
import '../widgets/hermes_components.dart';
import '../widgets/media_artifact_card.dart';
import '../widgets/voice_composer_controls.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

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

/// Route identity and resource ownership around one physical history flight.
/// Offset paging captures a fence without allocating latest-read authority.
class _ChatHistoryRead {
  const _ChatHistoryRead({
    required this.owner,
    required this.account,
    required this.localSessionId,
    required this.authority,
    required this.sessionId,
    required this.routeSessionId,
    required this.responseGeneration,
    required this.observation,
    required this.windowRevision,
  });
  final NormalGatewayChatOwner? owner;
  final Object account;
  final String localSessionId;
  final NormalGatewayHistoryRead? authority;
  final String sessionId;
  final String routeSessionId;
  final int responseGeneration;
  final int observation;
  final int windowRevision;
}

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
  DesktopConnectionState currentState = DesktopConnectionState.disconnected;
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

  /// Publishes a server-confirmed stored-session change to the owning list.
  final Future<void> Function(String sessionId, bool archived)?
  onArchiveChanged;

  /// Lets a longer-lived list own PATCH, read-back and reconciliation even
  /// when this route is popped before the request completes.
  final Future<bool> Function(String sessionId, bool archived)? sessionArchiver;

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
  final NormalGatewayResume? testNormalResume;

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

  @visibleForTesting
  final TaskHistorySource Function()? testTaskHistorySource;

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
    this.testNormalResume,
    this.testServerFilePicker,
    this.testRemoteAttachmentUpload,
    this.testInitialAttachmentDrafts = const [],
    this.testComposerDraftReader,
    this.testVoiceComposerAdapter,
    this.testTurnNotifications,
    this.testDesktopConnectionHook,
    this.testDesktopAsyncEventHook,
    this.testProjectOverviewLoader,
    this.testDesktopSessionEnsured,
    this.testLegacyProjectSessionEnsure,
    this.testStoredSessionKey,
    this.testMediaFilesClient,
    this.testTaskHistorySource,
    this.onArchiveChanged,
    this.sessionArchiver,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _messages = [];
  ChatTimeline _timeline = const ChatTimeline();
  RestChatReplyRetention? _restReplyRetention;
  bool _hasSuccessfulHistoryRead = false;
  late final ChatPresentationRegistry _presentationRegistry;
  late final ChatPresentationState _presentation;
  late final ComposerDraftWriter _draftWriter;
  late final GatewayTurnApplicationController _viewController;
  String _lastComposerText = '';
  bool _restoringComposer = false;
  // Keep manual expansion through streaming rebuilds/lazy-list eviction, but
  // only for this route's visit. Leaving/reopening must start collapsed again.
  late ChatPresentationRegistry _reasoningRegistry;
  late ChatPresentationState _reasoningPresentation;
  late ToolActivityGroupPins _reasoningExpansionPins;
  // Bounded, visit-local choices only; no bodies or cross-source correlation.
  Map<Object, bool> _backgroundReportExpansions = {};
  Map<Object, bool> _detailExpansions = {};
  bool? _delegationExpanded;
  final ChatHistoryWindow _historyWindow = ChatHistoryWindow();
  bool _loadingOlder = false;
  int _historyReadIssued = 0;
  int _historyReadAccepted = 0;
  int _historyWindowRevision = 0;
  _ChatHistoryRead? _loadingHistoryRead;
  _ChatHistoryRead? _olderHistoryRead;
  _ChatHistoryRead? _deferredHistoryRead;
  final List<GatewayToolActivity> _toolActivities = [];

  /// Expansion choices for tool-activity cards, keyed by group id so they
  /// survive reordering/eviction within this State's visit, never a real exit.
  late final ToolActivityGroupPins _toolActivityPins;
  final List<GatewaySubagentActivity> _subagentActivities = [];
  DelegatedTaskController? _openTaskController;
  int _automaticScrollGeneration = 0;
  final Map<String, GatewayNotification> _gatewayNotifications = {};
  final Map<String, Timer> _notificationTimers = {};
  late final List<GatewayNotice> _gatewayNotices;
  bool _loading = true;
  late String _sessionTitle;
  bool _renaming = false;
  late bool _sessionArchived;
  bool _archiving = false;
  int _archiveRevision = 0;
  int _archiveReadGeneration = 0;
  String? _archiveStateSessionId;
  String? _archiveReadSessionId;
  String? _error;
  late final ApiClient _client;
  late final GatewayChatClient _gateway;
  late final AttachmentDraftService _attachmentDraftService;
  late final AttachmentDraftSendCoordinator _attachmentSendCoordinator;
  late final Future<ChatModelOverrideStore> _chatModelStore;
  late final Future<void> _sessionModelRestore;
  DesktopGatewayClient? _desktopGateway;
  GatewayTurnApplicationController? _localTurnController;
  NormalGatewayApplicationSession? _normalSession;
  bool _normalSessionReady = false;
  NormalGatewayChatOwner? _normalChat;
  NormalGatewayChatSnapshot? _normalSnapshot;
  // Presentation only: no saved/received correspondence or owner retirement.
  final Set<String> _retainedRecoveryOutcomeIds = {};
  final Set<String> _historyObservedRecoveryOutcomeIds = {};
  bool _receivedRecoverySheetOpen = false;
  late final Map<String, String> _notificationApprovalOrigin;
  Object? _normalSubscription;
  Object? _normalReservation;
  String? _normalTurnId;
  String? _hiddenActivityTurnId;
  final Set<String> _normalInputSeen = {};
  final Set<String> _normalMaterializedIds = {};
  final Set<StreamEvent> _normalAuxiliarySeen = {};
  final Set<StreamEvent> _normalInputUpdatesSeen = {};
  final Set<String> _normalPendingRequestIds = {};
  final Map<String, String> _normalPendingRequestMethods = {};
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
  int _clearedComposerRevision = 0;

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
  bool _preparingSend = false;
  bool _midTurnSendInFlight = false;
  GatewayTurnStatus? _gatewayTurnStatus;
  String? _terminalTurnNotice;
  _ResponseTransport _activeResponseTransport = _ResponseTransport.none;
  String? _activeClientTurnId;
  // Stop can arrive after submit admission but before the coordinator's first
  // persisted callback supplies its client-turn identity. Keep that intent on
  // the v2 route rather than falling back to a legacy session interrupt.
  Completer<void>? _recoverableSubmissionState;
  bool _recoveringTurn = false;
  bool _legacyTransportFallback = false;
  bool _stockGatewayFallback = false;

  /// View-only admission gate; all reconnect work belongs to the app owner.
  bool get _pendingReattachResync => _normalChat?.snapshot.reconciling ?? false;

  /// Backstop for [releaseClientAfterStreamSettles] on the dispose path: a
  /// stream that never settles must not hold this screen's HTTP client open
  /// for the life of the process.
  static const _detachedStreamCloseDeadline = Duration(minutes: 30);

  /// Fences route-owned preparation and the existing REST/v2 UI callbacks.
  /// Stock turn and recovery generations live exclusively on the app owner.
  int _responseGeneration = 0;
  bool _deferredHistoryRefreshPending = false;
  bool _deferredHistoryRefreshing = false;
  String? _persistedHistoryContextRequested;
  Object? _persistedHistoryContextFlight;
  bool _stopResponseInFlight = false;
  bool _approvalDialogOpen = false;
  bool _approvalRouteOpen = false;
  Route<bool>? _approvalPromptRoute;
  String? _activeApprovalServerRequestId;
  final Set<String> _cancelledInteractiveRequestIds = {};
  final List<_PendingSensitivePrompt> _sensitivePromptQueue = [];
  final Set<String> _expiredSensitivePromptIds = {};
  _PendingSensitivePrompt? _activeSensitivePrompt;
  bool _sensitivePromptRouteOpen = false;
  Route<GatewaySensitivePromptDialogResult>? _sensitivePromptRoute;
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
  bool _openingHistoryChromePending = true;
  bool _openingScrollInterrupted = false;
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
    _notificationApprovalOrigin = NotificationApprovalAuthority.origin(
      widget.connection,
    );
    _sessionTitle = widget.session.title;
    _sessionArchived = widget.session.archived;
    WidgetsBinding.instance.addObserver(this);
    _projectName = _normalisedProjectName(widget.projectName);
    _viewController =
        widget.turnApplicationController ??
        (widget.testRemotePromptSubmit != null
            ? (_localTurnController ??= GatewayTurnApplicationController())
            : GatewayTurnApplicationController.standalone);
    _presentationRegistry = _viewController.presentationFor(widget.connection);
    _presentation = _presentationRegistry.chatFor(widget.session.id);
    _reasoningRegistry = _presentationRegistry;
    _reasoningPresentation = _presentation;
    _reasoningExpansionPins = _reasoningPresentation.openReasoningVisit();
    _toolActivityPins = _presentation.openToolVisit();
    _draftWriter = _presentation.openWriter(
      onBindingChanged: () {
        if (mounted && widget.initialComposerText == null) {
          unawaited(_restoreComposerDraft());
        }
      },
    );
    _textController.addListener(_onComposerChanged);
    if (widget.initialComposerText case final shared?) {
      _textController.text = shared;
      _textController.selection = TextSelection.collapsed(
        offset: shared.length,
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
          clientCertificate: widget.connection.clientCertificate,
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
        _attachNormalSession();
        _desktopGateway = _normalSession!.client;
      } on ArgumentError {
        // The regular mobile chat remains usable; selection surfaces the
        // actionable configuration error when Desktop attachments are needed.
        _desktopGateway = null;
      }
    }
    // Test seam: with no real gateway, hand the same handler to the test
    // hook so it can simulate reconnect transitions.
    if (widget.testRemotePromptSubmit != null && _normalSession == null) {
      _attachNormalSession();
    }
    if (widget.initialComposerText == null) unawaited(_restoreComposerDraft());
    widget.testDesktopConnectionHook?.handler = (state) {
      widget.testDesktopConnectionHook?.currentState = state;
      _normalSession?.connectionChanged(state);
      if (_normalSession == null) _onDesktopConnectionChanged(state);
    };
    widget.testDesktopAsyncEventHook?.handler = (event) {
      if (_normalSession != null &&
          (_turnApplicationSession == null || _legacyTransportFallback)) {
        _normalSession!.receiveEvent(widget.session.id, event);
      } else {
        _handleDesktopAsyncEvent(widget.session.id, event);
      }
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
    unawaited(_refreshArchiveState());
    unawaited(_initializeChat());
    _loadVerboseMode();
    _loadChatDensity();
    chatDensitySelection.addListener(_onChatDensityChanged);
    _initVoice();
    _recoverLostImage();
    _scrollController.addListener(_onScroll);
    if (_desktopGateway != null) unawaited(_ensureDesktopSession());
  }

  void _attachNormalSession() {
    final controller = _viewController;
    final testClient = widget.testApiClient;
    _normalSession = controller.normalSessionFor(
      widget.connection,
      submit: widget.testRemotePromptSubmit,
      resume: widget.testNormalResume,
      history: testClient == null
          ? null
          : (id) => testClient.getMessages(
              id,
              limit: ChatHistoryWindow.pageSize,
              latest: true,
            ),
      notifications: _turnNotifications,
    );
    _normalChat = _normalSession!.chatFor(
      widget.session.id,
      storedSessionId: widget.session.isLocalDraft
          ? null
          : _normalSession!.findChat(widget.session.id)?.storedSessionId ??
                widget.testStoredSessionKey?.call(widget.session.id) ??
                widget.session.id,
      title: _sessionTitle,
      lineageRootId: widget.session.lineageRootId,
      workingDirectory: widget.projectWorkingDirectory,
    );
    if (_textController.text.isNotEmpty || widget.initialComposerText != null) {
      _normalChat!.invalidateDraftRecovery();
    }
    _normalSubscription = _normalChat!.subscribe(_applyNormalSnapshot);
    final session = _normalSession!;
    unawaited(
      session.ready.then(
        (_) {
          if (!mounted || !identical(_normalSession, session)) return;
          setState(() => _normalSessionReady = true);
        },
        onError: (Object _, StackTrace _) {
          // Failed receipt hydration cannot prove that the chat is idle.
        },
      ),
    );
  }

  void _applyNormalSnapshot(
    NormalGatewayChatSnapshot snapshot, {
    bool hydrateHistory = true,
    bool followStream = true,
  }) {
    if (!mounted) return;
    final rejectedDraft = snapshot.rejectedDraft;
    if (rejectedDraft != null &&
        widget.initialComposerText == null &&
        _composerRevision == _clearedComposerRevision) {
      _restoreComposerAfterRejectedSend(rejectedDraft);
    }
    _normalInputUpdatesSeen.retainAll(snapshot.inputUpdates);
    final updatedInputIds = <String>{};
    for (final event in snapshot.inputUpdates) {
      if (_normalInputUpdatesSeen.add(event)) {
        final id = (event.data['id'] ?? event.data['request_id'])?.toString();
        if (id != null) updatedInputIds.add(id);
        _handleDesktopGatewayEvent(event, _responseGeneration);
      }
    }
    _normalInputSeen.retainAll(
      snapshot.pendingInput.map(
        (event) => '${event.type}:${jsonEncode(event.data)}',
      ),
    );
    _normalAuxiliarySeen.retainAll(snapshot.auxiliaryEvents);
    for (final event in snapshot.auxiliaryEvents) {
      if (_normalAuxiliarySeen.add(event)) {
        _handleDesktopAsyncEvent(widget.session.id, event);
      }
    }
    _normalSnapshot =
        snapshot; // read-only owner projection, not a route buffer
    _retainedRecoveryOutcomeIds.retainAll(
      snapshot.receivedOutcomes.map((outcome) => outcome.id),
    );
    _historyObservedRecoveryOutcomeIds.retainAll(
      snapshot.receivedOutcomes.map((outcome) => outcome.id),
    );
    final justDetached =
        _desktopConnectionState == DesktopConnectionState.connected &&
        snapshot.connectionState != DesktopConnectionState.connected &&
        snapshot.wireEmitted &&
        snapshot.hasActiveTurn;
    if (justDetached &&
        _normalTurnId != null &&
        ModalRoute.of(context)?.isCurrent == true) {
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
    final newTurn = snapshot.turnId != _normalTurnId;
    if (newTurn) {
      _normalTurnId = snapshot.turnId;
      _responseGeneration++;
      _normalInputSeen.clear();
      _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());
    }
    final bindingChanged =
        snapshot.storedSessionId != null &&
        _storedSessionId != snapshot.storedSessionId;
    _storedSessionId = snapshot.storedSessionId;
    if (bindingChanged) {
      unawaited(_refreshProjectName());
      unawaited(_refreshArchiveState());
    }
    final pendingIds = snapshot.pendingInput
        .map(
          (event) =>
              (event.data['server_request_id'] ??
                      event.data['request_id'] ??
                      event.data['id'])
                  ?.toString(),
        )
        .whereType<String>()
        .toSet();
    for (final removed in _normalPendingRequestIds.difference(pendingIds)) {
      if (updatedInputIds.contains(removed)) continue;
      _handleDesktopGatewayEvent(
        StreamEvent(
          type: 'request.cancel',
          data: {
            'id': removed,
            'method': _normalPendingRequestMethods[removed],
          },
        ),
        _responseGeneration,
      );
    }
    _normalPendingRequestMethods.clear();
    for (final event in snapshot.pendingInput) {
      final id =
          (event.data['server_request_id'] ??
                  event.data['request_id'] ??
                  event.data['id'])
              ?.toString();
      if (id != null) {
        _normalPendingRequestMethods[id] = event.type.split('.').first;
      }
    }
    _normalPendingRequestIds
      ..clear()
      ..addAll(pendingIds);
    // Only this admission's received assistant scopes can create unread work.
    // Imported donors and saved rows are not new current output.
    final lastPrompt = snapshot.displayRows.lastIndexWhere(
      (row) => row['role'] == 'user',
    );
    final currentRows = snapshot.displayRows.skip(lastPrompt + 1).toList();
    _normalMaterializedIds.retainAll(
      snapshot.displayRows
          .map((row) => row['_normal_projection_id'])
          .whereType<String>(),
    );
    for (final row in snapshot.displayRows) {
      final id = row['_normal_projection_id']?.toString();
      if (id != null &&
          row['role'] == 'assistant' &&
          (row['content']?.toString().isNotEmpty ?? false) &&
          _normalMaterializedIds.add(id) &&
          snapshot.wireEmitted &&
          snapshot.turnId != null &&
          currentRows.contains(row)) {
        _registerMaterializedAssistantMessage();
      }
    }
    setState(() {
      _desktopConnectionState = snapshot.connectionState;
      if (snapshot.turnId != null || snapshot.displayRows.isNotEmpty) {
        _loading = false;
      }
      _sending = snapshot.hasActiveTurn && !snapshot.reconciling;
      _streaming =
          snapshot.hasActiveTurn &&
          !snapshot.reconciling &&
          snapshot.phase != NormalGatewayTurnPhase.preparing;
      _activeResponseTransport = snapshot.hasActiveTurn
          ? _ResponseTransport.desktop
          : _ResponseTransport.none;
      _gatewayTurnStatus = snapshot.reconciling
          ? const GatewayTurnStatus(
              kind: 'recovery',
              text: 'Recovering without resending',
            )
          : snapshot.status;
      if (hydrateHistory) {
        // Finish synchronous owner fan-out before merging into the retained
        // window: another subscriber can accept a newer snapshot reentrantly.
        // An idle owner provides rows only; physical route pages still own the
        // paging cursor, including during a held older/latest request.
        final owner = _normalChat;
        scheduleMicrotask(() {
          if (!mounted ||
              !identical(owner, _normalChat) ||
              !identical(_normalSnapshot, snapshot) ||
              _windowContainsLatest(_ownerHistoryForPresentation(snapshot))) {
            return;
          }
          setState(() {
            if (!_windowContainsLatest(snapshot.historyRows)) {
              if (snapshot.turnId == null) {
                _historyWindow.mergeObservedRows(snapshot.historyRows);
                _historyWindowRevision++;
                _extractToolMessages(_historyWindow.rows);
              } else {
                _acceptRecentMessages(snapshot.historyRows);
              }
            }
            if (snapshot.historyPresentationRows.isNotEmpty) {
              // A sibling can confirm a long turn while this route's own
              // context read is held. Publish its canonical replacement here,
              // without granting retained rows latest/read or cursor authority.
              _historyWindow.mergeObservedRows(
                _ownerHistoryForPresentation(snapshot),
              );
              _historyWindowRevision++;
              _extractToolMessages(_historyWindow.rows);
            }
            _messages = _restHistoryForPresentation();
          });
        });
      }
      if (!hydrateHistory &&
          snapshot.historyPresentationRows.isNotEmpty &&
          !_windowContainsLatest(_ownerHistoryForPresentation(snapshot))) {
        // Physical readers already applied their cursor-owning batch, but it
        // can predate an alias's retained per-row veto. This synchronous path
        // supersedes the queued owner callback; apply its presentation union
        // too, without lending that union paging or latest-read authority.
        _historyWindow.mergeObservedRows(
          _ownerHistoryForPresentation(snapshot),
        );
        _historyWindowRevision++;
        _extractToolMessages(_historyWindow.rows);
      }
      _messages = _restHistoryForPresentation();
      // Hydrated child roots and owner runtime IDs may differ. Preserve the
      // stable task anchor and forward all progress/final updates to the modal.
      for (final update in snapshot.subagents) {
        _mergeSubagentActivity(update);
      }
      // App-owned runs use stable projection ids, so copying snapshot rows or
      // replacing a route cannot discard receipt chronology.
      _timeline = snapshot.timeline;
    });
    _queuePersistedHistoryContext(snapshot);
    if (followStream) {
      if (snapshot.hasActiveTurn) {
        _scheduleStreamingFollow();
      } else {
        _scheduleScrollTarget(_scrollCoordinator.endStreaming());
      }
    }
    if (snapshot.phase == NormalGatewayTurnPhase.failed ||
        snapshot.phase == NormalGatewayTurnPhase.reconciledUnknown) {
      _awaitingVoiceReply = false;
    }
    if (snapshot.phase == NormalGatewayTurnPhase.completed &&
        _awaitingVoiceReply) {
      final rows = currentRows;
      for (final row in rows.reversed) {
        if (row['role'] == 'user') break;
        final text = row['content']?.toString() ?? '';
        if (const {'assistant', 'agent'}.contains(row['role']) &&
            row['_gateway_interim'] != true &&
            text.isNotEmpty) {
          _awaitingVoiceReply = false;
          unawaited(_speakAssistantText(text).catchError((Object _) {}));
          break;
        }
      }
      _awaitingVoiceReply = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final currentInputs =
          _normalChat?.snapshot.pendingInput ?? const <StreamEvent>[];
      for (final event in snapshot.pendingInput) {
        if (!currentInputs.contains(event)) continue;
        final key = '${event.type}:${jsonEncode(event.data)}';
        if (_normalInputSeen.add(key)) {
          _handleDesktopGatewayEvent(event, _responseGeneration);
        }
      }
    });
  }

  void _queuePersistedHistoryContext(NormalGatewayChatSnapshot snapshot) {
    final owner = _normalChat;
    if (owner == null ||
        snapshot.hasActiveTurn ||
        _loading ||
        _sending ||
        _streaming ||
        _stopResponseInFlight ||
        _pendingReattachResync ||
        _persistedHistoryContextFlight != null) {
      return;
    }
    final key = owner.persistedTurnContextKey(snapshot.historyRows);
    if (key == null || key == _persistedHistoryContextRequested) return;
    // One automatic bounded scan per receipt set. Incomplete/failed context
    // consumes its attempt only if that read remains valid. A new turn can
    // invalidate a held scan without permanently suppressing its fresh retry.
    _persistedHistoryContextRequested = key;
    final flight = Object();
    _persistedHistoryContextFlight = flight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(owner, _normalChat)) {
        _finishPersistedHistoryContext(flight, invalidated: true);
        return;
      }
      if (_sending ||
          _streaming ||
          _stopResponseInFlight ||
          _pendingReattachResync ||
          owner.persistedTurnContextKey(owner.snapshot.historyRows) != key) {
        _finishPersistedHistoryContext(flight, invalidated: true);
        return;
      }
      unawaited(_fetchMessages(persistedContextFlight: flight));
    });
  }

  void _finishPersistedHistoryContext(
    Object flight, {
    bool invalidated = false,
  }) {
    if (!identical(_persistedHistoryContextFlight, flight)) return;
    _persistedHistoryContextFlight = null;
    if (invalidated) _persistedHistoryContextRequested = null;
    // This also covers a new turn which already settled while the old page
    // was held. An accepted failure keeps its key, so it cannot retry-spin.
    final snapshot = _normalChat?.snapshot;
    if (mounted && snapshot != null) _queuePersistedHistoryContext(snapshot);
  }

  bool _sameHistoryRows(
    List<Map<String, dynamic>>? a,
    List<Map<String, dynamic>> b,
  ) =>
      a != null &&
      a.length == b.length &&
      Iterable<int>.generate(b.length).every((i) => mapEquals(a[i], b[i]));

  bool _windowContainsLatest(List<Map<String, dynamic>> latest) {
    int? id(Map<String, dynamic> row) =>
        int.tryParse(row['id']?.toString() ?? '');
    final retained = {
      for (final row in _historyWindow.rows)
        if (id(row) != null) id(row): row,
    };
    return latest
            .where((row) => id(row) != null)
            .every(
              (row) =>
                  retained[id(row)] != null &&
                  mapEquals(retained[id(row)], row),
            ) &&
        _sameHistoryRows(
          _historyWindow.rows.where((row) => id(row) == null).toList(),
          latest.where((row) => id(row) == null).toList(),
        );
  }

  List<Map<String, dynamic>> _ownerHistoryForPresentation(
    NormalGatewayChatSnapshot snapshot,
  ) {
    if (snapshot.historyPresentationRows.isEmpty) return snapshot.historyRows;
    // The owner preserves per-row observation order through alias handoff.
    // Its retained presentation may contain a newer veto than the winning
    // owner's admission-only latest snapshot. Never overwrite that value.
    final projection = ChatHistoryWindow()
      ..mergeObservedRows(snapshot.historyRows)
      ..mergeObservedRows(snapshot.historyPresentationRows);
    return projection.rows;
  }

  String get _connectionIdentity =>
      '${widget.connection.baseUrl}|'
      '${widget.connection.gatewayPrefix ?? ''}|'
      '${widget.connection.desktopGatewayUrl ?? ''}';

  String get _gatewayNoticeIdentity =>
      '$_connectionIdentity|${widget.session.id}';

  void _onComposerChanged() {
    _composerRevision += 1;
    _normalChat?.invalidateDraftRecovery();
    final text = _textController.text;
    if (!_restoringComposer && text != _lastComposerText) {
      _draftWriter.edit(text);
    }
    _lastComposerText = text;
  }

  Future<void> _restoreComposerDraft() async {
    final revision = _composerRevision;
    await _normalSession?.ready;
    if (!mounted || !_draftWriter.isCurrent) return;
    final draft = await _draftWriter.read(
      reader: widget.testComposerDraftReader,
    );
    if (!mounted ||
        !_draftWriter.isCurrent ||
        draft == null ||
        _composerRevision != revision ||
        _textController.text.isNotEmpty) {
      return;
    }
    _setRestoredComposer(draft);
  }

  void _setRestoredComposer(String text) {
    _restoringComposer = true;
    try {
      _textController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _restoringComposer = false;
    }
  }

  bool get _usesNormalInputOwner =>
      _normalSession != null &&
      (_turnApplicationSession == null || _legacyTransportFallback);

  String get _normalLocalSessionKey =>
      _normalChat?.localSessionId ?? widget.session.id;

  String get _storedSessionKey =>
      _normalChat?.storedSessionId ??
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
    if (!mounted) return;
    _normalChat?.bindStoredSession(storedSessionId);
    _presentationRegistry.bind(localSessionId, storedSessionId);
    setState(() => _storedSessionId = storedSessionId);
    unawaited(_refreshProjectName());
    unawaited(_refreshArchiveState());
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
    if (!mounted) return;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute establishes a dependency on visibility. A lower duplicate
    // route becoming current must replay pending input even if the server is
    // blocked waiting for that answer and sends no further stream frames.
    final current = ModalRoute.of(context)?.isCurrent == true;
    if (current && _normalChat != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          _applyNormalSnapshot(_normalChat!.snapshot, followStream: false);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final registry = (widget.turnApplicationController ?? _viewController)
        .presentationFor(widget.connection);
    if (!identical(registry, _reasoningRegistry) ||
        !identical(
          registry.chatFor(oldWidget.session.id),
          registry.chatFor(widget.session.id),
        )) {
      _reasoningPresentation.closeReasoningVisit(_reasoningExpansionPins);
      _reasoningRegistry = registry;
      _reasoningPresentation = registry.chatFor(widget.session.id);
      _reasoningExpansionPins = _reasoningPresentation.openReasoningVisit();
      _backgroundReportExpansions = {};
      _detailExpansions = {};
      _delegationExpanded = null;
      _retainedRecoveryOutcomeIds.clear();
      _historyObservedRecoveryOutcomeIds.clear();
    }
  }

  @override
  void dispose() {
    final pendingSubmission = _recoverableSubmissionState;
    if (pendingSubmission != null && !pendingSubmission.isCompleted) {
      pendingSubmission.complete();
    }
    final normalChat = _normalChat;
    final reservation = _normalReservation;
    final subscription = _normalSubscription;
    if (subscription != null) normalChat?.unsubscribe(subscription);
    if (reservation != null) normalChat?.cancelPreparation(reservation);
    _openTaskController?.dispose();
    _openTaskController = null;
    WidgetsBinding.instance.removeObserver(this);
    chatDensitySelection.removeListener(_onChatDensityChanged);
    _projectNameRefreshGeneration += 1;
    _archiveReadGeneration += 1;
    pendingNotificationApprovals.removeListener(
      _consumePendingNotificationApproval,
    );
    widget.testDesktopConnectionHook?.handler = null;
    widget.testDesktopAsyncEventHook?.handler = null;
    _savedGatewayNotices[_gatewayNoticeIdentity] = List.unmodifiable(
      _gatewayNotices,
    );
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
    // Route disposal only unsubscribes; it never closes the app-owned socket.

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
    _presentation.closeToolVisit(_toolActivityPins);
    _reasoningPresentation.closeReasoningVisit(_reasoningExpansionPins);
    final draftSaved = _draftWriter.close();
    unawaited(draftSaved.then((_) => _localTurnController?.close()));
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
      _normalSession?.setLifecycle(background: true);
      // Persist the draft on the way out: a process kill must not lose it.
      unawaited(_draftWriter.flush());
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      if (_normalChat?.snapshot.reconciling == true) {
        widget.testDesktopSessionEnsured?.call();
      }
      _normalSession?.setLifecycle(background: false);
      if (_normalChat?.snapshot.turnId != null) return;
      if (_desktopGateway != null) unawaited(_ensureDesktopSession());
      if (_turnApplicationSession != null) unawaited(_recoverPendingTurn());
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
    final changed = _desktopConnectionState != state;
    setState(() => _desktopConnectionState = state);
    if (changed && state == DesktopConnectionState.connected) {
      unawaited(_refreshProjectName());
      _consumePendingNotificationApproval();
    }
  }

  Future<void> _ensureDesktopSession() async {
    if (_normalChat?.snapshot.hasActiveTurn == true) {
      _normalChat!.requestRecovery();
      return;
    }
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
        _normalLocalSessionKey,
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
    if (_archiving ||
        _sending ||
        _streaming ||
        _pendingReattachResync ||
        text.trim().isEmpty) {
      return;
    }
    _editAndResend(text);
    await _sendMessage();
  }

  bool get _canRename =>
      !_renaming &&
      !_archiving &&
      !_sending &&
      !_streaming &&
      !_pendingReattachResync &&
      (!widget.session.isLocalDraft ||
          _storedSessionId != null ||
          _storedSessionKey != widget.session.id ||
          _messages.isNotEmpty);

  String get _archiveSessionId => _storedSessionId ?? _storedSessionKey;

  bool get _hasStoredArchiveTarget =>
      !widget.session.isLocalDraft ||
      _storedSessionId != null ||
      _storedSessionKey != widget.session.id ||
      _archiveStateSessionId == _archiveSessionId;

  bool get _canArchive =>
      _hasStoredArchiveTarget &&
      (_normalSession == null || _normalSessionReady) &&
      !_archiving &&
      !_renaming &&
      !_preparingSend &&
      !_sending &&
      !_streaming &&
      !_recoveringTurn &&
      !_pendingReattachResync;

  /// Navigation metadata can precede a canonical binding or an edit on another
  /// device. Read exact stored metadata once per identity/open, without ever
  /// resuming/creating a chat. A pre-write read cannot undo a confirmed save.
  Future<void> _refreshArchiveState() async {
    if (!mounted || _archiving) return;
    final sessionId = _archiveSessionId;
    if (_archiveReadSessionId == sessionId) return;
    if (!_hasStoredArchiveTarget && _messages.isEmpty) return;
    _archiveReadSessionId = sessionId;
    final generation = ++_archiveReadGeneration;
    final revision = _archiveRevision;
    try {
      final saved = await _client.getSession(sessionId);
      if (!mounted ||
          generation != _archiveReadGeneration ||
          revision != _archiveRevision ||
          sessionId != _archiveSessionId) {
        return;
      }
      if (saved['id'] != sessionId || saved['archived'] is! bool) return;
      setState(() {
        _sessionArchived = saved['archived'] as bool;
        _archiveStateSessionId = sessionId;
      });
    } catch (_) {
      // Older gateways may lack metadata. Keep navigation-time state; the
      // mutation still requires an independently verified server read-back.
    }
  }

  Future<void> _setSessionArchived(
    bool archived, {
    String? expectedSessionId,
  }) async {
    if (!mounted || !_canArchive) return;
    final sessionId = _archiveSessionId;
    if (expectedSessionId != null && expectedSessionId != sessionId) return;
    setState(() => _archiving = true);
    // Invalidate pending metadata before the first await, including failures.
    _archiveReadGeneration++;
    try {
      final archiver = widget.sessionArchiver;
      final saved = await (archiver != null
          ? archiver(sessionId, archived)
          : _client.setSessionArchived(
              sessionId: sessionId,
              archived: archived,
            ));
      if (!mounted || sessionId != _archiveSessionId) return;
      setState(() {
        _sessionArchived = saved;
        _archiveStateSessionId = sessionId;
        _archiveReadSessionId = sessionId;
        _archiveRevision++;
      });
      // The owner may need to clear a device-local expiry before Unarchive
      // becomes visible. Do not announce success ahead of that reconciliation.
      await widget.onArchiveChanged?.call(sessionId, saved);
      if (!mounted || sessionId != _archiveSessionId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? context.l10n.chat_archived : context.l10n.chat_unarchived,
          ),
        ),
      );
    } catch (error) {
      if (!mounted || sessionId != _archiveSessionId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.could_not_update_chat_archive(error)),
          action: SnackBarAction(
            label: context.l10n.retry,
            onPressed: () => unawaited(
              _setSessionArchived(archived, expectedSessionId: sessionId),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }

  Future<void> _renameSession() async {
    if (!_canRename) return;
    setState(() => _renaming = true);
    try {
      // Let the popup route finish closing before presenting another route.
      await Future<void>.delayed(kThemeAnimationDuration);
      if (!mounted) return;
      final title = await showSessionNameDialog(
        context: context,
        title: context.l10n.rename_chat,
        initialValue: _sessionTitle,
        actionLabel: context.l10n.rename,
      );
      if (!mounted || title == null || title == _sessionTitle.trim()) return;
      final savedTitle = await _client.renameSession(
        sessionId: _storedSessionId ?? _storedSessionKey,
        title: title,
      );
      if (mounted) {
        _normalChat?.title = savedTitle;
        setState(() => _sessionTitle = savedTitle);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.could_not_rename_chat(error))),
      );
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  Future<void> _showReceivedOutputDetails() async {
    // Let the chat-actions popup close before presenting another route.
    await Future<void>.delayed(kThemeAnimationDuration);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.l10n.received_output_heading),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.received_output_explanation),
            const SizedBox(height: 12),
            Text(context.l10n.received_output_lifetime),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _exportConversation() async {
    final buffer = StringBuffer('# $_sessionTitle\n\n');
    if (_normalChat != null) {
      for (final section in _normalDisplaySections(verbose: true)) {
        if (section.source == ChatDisplaySource.auxiliary) continue;
        final received = section.source == ChatDisplaySource.received;
        buffer.writeln(
          '## ${received ? context.l10n.received_output_heading : context.l10n.saved_history_heading}\n',
        );
        if (received) {
          buffer.writeln('${context.l10n.received_output_explanation}\n');
          buffer.writeln('${context.l10n.received_output_lifetime}\n');
        }
        for (final item in section.items) {
          final fact = section.outcomes[chatDisplayItemIdentity(item)];
          if (fact != null) {
            buffer.writeln('${_receivedOutcomeLabel(fact.outcome)}\n');
          }
          if (item is Map<String, dynamic>) {
            _writeExportMessage(buffer, item, localPrompt: received);
          } else if (item is ChatReasoningItem) {
            buffer.writeln('${item.text}\n');
          } else if (item is ChatToolActivityGroup) {
            for (final tool in item.activities) {
              buffer.writeln('${tool.displayName}: ${tool.statusLabel}');
            }
            buffer.writeln();
          }
        }
      }
    } else {
      // Export the same public projection as the transcript on every transport.
      // Raw history can contain hidden/model-only rows and explicit empty
      // replacements; neither is permission to expose physical model content.
      for (final item in buildChatDisplayItems(messages: _messages)) {
        if (item is Map<String, dynamic>) _writeExportMessage(buffer, item);
      }
    }
    await SharePlus.instance.share(
      ShareParams(subject: _sessionTitle, text: buffer.toString().trim()),
    );
  }

  void _writeExportMessage(
    StringBuffer buffer,
    Map<String, dynamic> message, {
    bool localPrompt = false,
  }) {
    final role = message['role']?.toString();
    if (role != 'user' && role != 'assistant' && role != 'agent') return;
    if (!isPublicDeliveryMessage(message)) return;
    final content = stripToolResultText(
      messageContentToText(
        message.containsKey('_display_content')
            ? message['_display_content']
            : AndroidPromptContext.displayContent(
                message,
                publicDeliveryContent(message),
              ),
      ),
    ).trim();
    if (content.isEmpty) return;
    buffer
      ..writeln(
        role == 'user'
            ? (localPrompt
                  ? context.l10n.local_prompt_context
                  : context.l10n.you_heading)
            : context.l10n.hermes_heading,
      )
      ..writeln()
      ..writeln(content)
      ..writeln();
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
              turnSummary: '$_sessionTitle: $summary',
              turnId: turnId,
              sessionId: widget.session.id,
              connectionId: widget.connection.id,
            )
          : _turnNotifications.showTurnFailed(
              title: context.l10n.the_turn_failed,
              turnSummary: '$_sessionTitle: $summary',
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
    if (_normalSession != null && _normalChat?.snapshot.turnId != null) return;
    if (!_appInBackground || serverRequestId == null) return;
    final command = request.command.trim();
    final body = command.isEmpty
        ? request.description.trim()
        : (command.length > 140 ? '${command.substring(0, 140)}…' : command);
    unawaited(
      _turnNotifications.showKind(
        kind: HermesNotificationKind.approval,
        title: '${context.l10n.approval_needed} — $_sessionTitle',
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
          ..._notificationApprovalOrigin,
        }),
      ),
    );
  }

  /// Mirrors a clarify/sudo/secret prompt to a native notification while the
  /// app is in the background. The dialog itself stays queued for the return.
  void _notifyInputRequest({required String eventId, required String body}) {
    if (_normalSession != null && _normalChat?.snapshot.turnId != null) return;
    if (!_appInBackground) return;
    final trimmed = body.trim();
    unawaited(
      _turnNotifications.showKind(
        kind: HermesNotificationKind.input,
        title: '${context.l10n.input_needed} — $_sessionTitle',
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
    if (_normalSession != null &&
        (_turnApplicationSession == null || _legacyTransportFallback)) {
      return;
    }
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
    if (_normalSession != null &&
        (_turnApplicationSession == null || _legacyTransportFallback)) {
      return;
    }
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
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null) ||
        (notification is OverscrollNotification &&
            notification.dragDetails != null);
    if (isDirectUserScroll) {
      // A direct reader gesture cancels both opening and lazy-layout alignment.
      _openingScrollInterrupted = true;
      _initialEndFramesRemaining = 0;
      _automaticScrollGeneration++;
      _scrollCoordinator.updateFromUserScroll(
        isNearEnd: _isNearEnd(notification.metrics),
      );
    }
    return false;
  }

  void _applyScrollTarget(ChatScrollTarget target, {bool converge = true}) {
    if (_openTaskController != null ||
        _receivedRecoverySheetOpen ||
        !_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if ((_scrollController.position.pixels - maxExtent).abs() >
        _stableExtentTolerance) {
      _scrollController.jumpTo(maxExtent);
    }
    _syncEndAffordance(_scrollController.position);
    if (converge) _startEndLayoutAlignment();
  }

  void _goToEnd() {
    if (_canFocusSavedRecovery && _retainIdleRecoveryForPresentation()) {
      setState(() {});
      _scheduleScrollTarget(const ChatScrollTarget.end());
      return;
    }
    _applyScrollTarget(const ChatScrollTarget.end());
  }

  void _scheduleScrollTarget(ChatScrollTarget? target) {
    if (_openTaskController != null || _receivedRecoverySheetOpen) return;
    final generation = _automaticScrollGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canApplyAutomaticScroll(generation)) return;
      if (target != null) {
        _applyScrollTarget(target);
      } else if (_scrollController.hasClients) {
        _syncEndAffordance(_scrollController.position, clearUnreadAtEnd: false);
      }
    });
  }

  void _scheduleStreamingFollow() {
    if (_openTaskController != null ||
        _receivedRecoverySheetOpen ||
        _streamFollowScheduled) {
      return;
    }
    final generation = _automaticScrollGeneration;
    _streamFollowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _streamFollowScheduled = false;
      if (!_canApplyAutomaticScroll(generation)) return;
      final target = _scrollCoordinator.streamingContentChanged();
      if (target != null) {
        _applyScrollTarget(target);
      } else if (_scrollController.hasClients) {
        _syncEndAffordance(_scrollController.position, clearUnreadAtEnd: false);
      }
    });
  }

  bool _canApplyAutomaticScroll(int generation) =>
      mounted &&
      _openTaskController == null &&
      !_receivedRecoverySheetOpen &&
      generation == _automaticScrollGeneration;

  void _scheduleInitialEndAlignment() {
    if (_scrollCoordinator.consumeInitialEndAlignment() == null) {
      _scheduleScrollTarget(null);
      return;
    }
    _startEndLayoutAlignment();
  }

  // Collapsed details and independent source sections have different lazy row
  // estimates. Converge only an authorised end target, never an ordinary refresh.
  void _startEndLayoutAlignment() {
    _initialEndFramesRemaining = _initialEndFrameBudget;
    _initialEndStableFrames = 0;
    _initialEndLastExtent = null;
    _scheduleNextInitialEndFrame();
  }

  void _scheduleNextInitialEndFrame() {
    if (_openTaskController != null ||
        _receivedRecoverySheetOpen ||
        _initialEndFrameScheduled ||
        _initialEndFramesRemaining <= 0) {
      return;
    }
    final generation = _automaticScrollGeneration;
    _initialEndFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialEndFrameScheduled = false;
      if (!_canApplyAutomaticScroll(generation) ||
          _initialEndFramesRemaining <= 0) {
        return;
      }
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
      _applyScrollTarget(const ChatScrollTarget.end(), converge: false);
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
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // Value equality permits harmless SavedConnection rehydration, but fences
  // credential/profile/origin replacement even when a parent retains State.
  // This record is private in-memory authority, never logged or persisted.
  Object get _historyAccountKey {
    final c = widget.connection;
    return (
      c.id,
      c.host,
      c.port,
      c.useHttps,
      c.apiKey,
      c.gatewayPrefix,
      c.gatewayProfile,
      c.desktopGatewayUrl,
      c.dashboardUsername,
      c.dashboardPassword,
      c.dashboardPrefix,
      c.dashboardPort,
      c.dashboardProxied,
    );
  }

  _ChatHistoryRead _beginHistoryRead(String sessionId, {bool older = false}) {
    final owner = _normalChat;
    return _ChatHistoryRead(
      owner: owner,
      account: _historyAccountKey,
      localSessionId: widget.session.id,
      authority: older
          ? owner?.historyReadFence(sessionId)
          : owner?.beginHistoryRead(sessionId),
      sessionId: sessionId,
      routeSessionId: _storedSessionKey,
      responseGeneration: _responseGeneration,
      observation: older ? _historyReadAccepted : ++_historyReadIssued,
      windowRevision: _historyWindowRevision,
    );
  }

  bool _historyReadAttached(_ChatHistoryRead read) =>
      mounted &&
      read.account == _historyAccountKey &&
      read.localSessionId == widget.session.id &&
      identical(read.owner, _normalChat) &&
      read.routeSessionId == _storedSessionKey &&
      (read.authority?.isAttached ?? true);

  bool _canApplyHistoryRead(_ChatHistoryRead read) =>
      _historyReadAttached(read) &&
      read.responseGeneration == _responseGeneration &&
      read.observation >= _historyReadAccepted &&
      (read.authority?.isCurrent ?? true);

  bool _acceptHistoryRead(
    _ChatHistoryRead read,
    List<Map<String, dynamic>> latest, {
    List<Map<String, dynamic>>? confirmedRows,
  }) {
    if (!_canApplyHistoryRead(read)) return false;
    if (read.owner != null &&
        !read.owner!.observeHistory(
          latest,
          read: read.authority,
          confirmedRows: confirmedRows,
        )) {
      return false;
    }
    // Owner delivery invokes arbitrary subscribers synchronously. A new turn,
    // binding, close or newer successful read there invalidates this callback.
    if (!_canApplyHistoryRead(read)) return false;
    _historyReadAccepted = read.observation;
    _hasSuccessfulHistoryRead = true;
    final snapshot = _normalSnapshot;
    if (latest.isNotEmpty && snapshot != null && !snapshot.hasActiveTurn) {
      _historyObservedRecoveryOutcomeIds.addAll(
        snapshot.receivedOutcomes
            .where((fact) => fact.outcome == ReceivedLifecycleOutcome.unknown)
            .map((fact) => fact.id),
      );
    }
    return true;
  }

  void _finishHistoryLoading(_ChatHistoryRead read) {
    // Release only this loader's resource, even when its result was superseded.
    // It must never clear a newer route loader or publish stale error/status.
    if (!mounted || !identical(_loadingHistoryRead, read)) return;
    _loadingHistoryRead = null;
    if (_historyReadAttached(read) &&
        read.responseGeneration == _responseGeneration) {
      // The first read can replace a thin loader with a taller error banner
      // after retained history has already used its one-shot alignment. Keep
      // only an untouched, exactly-at-end opening anchored across that layout.
      final keepOpeningEnd =
          _openingHistoryChromePending &&
          !_openingScrollInterrupted &&
          _openTaskController == null &&
          _scrollCoordinator.initialEndAlignmentConsumed &&
          _scrollController.hasClients &&
          (_scrollController.position.maxScrollExtent -
                      _scrollController.position.pixels)
                  .abs() <=
              1;
      _openingHistoryChromePending = false;
      setState(() => _loading = false);
      if (keepOpeningEnd) _startEndLayoutAlignment();
    }
  }

  Future<void> _fetchMessages({
    String? sessionId,
    Object? persistedContextFlight,
    bool focusSavedHistory = false,
  }) async {
    if (_pendingReattachResync && sessionId == null) return;
    final read = _beginHistoryRead(
      sessionId ?? _normalChat?.storedSessionId ?? widget.session.id,
    );
    _loadingHistoryRead = read;
    final navigationGeneration = _automaticScrollGeneration;
    final mayFocusRecovery =
        focusSavedHistory ||
        (!_hasSuccessfulHistoryRead && !_openingScrollInterrupted);
    setState(() {
      _loading = true;
      _error = null;
    });
    List<Map<String, dynamic>>? latest;
    try {
      final batch = await _historyWindow.fetchRecent(
        (offset) async {
          final rows = await _client.getMessages(
            read.sessionId,
            limit: ChatHistoryWindow.pageSize,
            offset: offset,
            latest: true,
          );
          // Only offset zero carries latest authority. Additional cold pages
          // are context, never a new read-start sequence or admission snapshot.
          if (offset == 0) latest = rows;
          return rows;
        },
        shouldContinue: () => _canApplyHistoryRead(read),
        forceColdScan: !_hasSuccessfulHistoryRead,
        needsContext: (rows) =>
            read.owner?.persistedTurnContextKey(rows) != null,
      );
      if (!_historyReadAttached(read)) return;
      if (read.responseGeneration != _responseGeneration) {
        _deferHistoryRefresh();
        return;
      }
      // Context fetched by this read can confirm a long receipt; retained
      // rows from earlier paging cannot lend this request fresh authority.
      if (!_acceptHistoryRead(read, latest!, confirmedRows: batch.rows)) return;
      final wasFollowingEnd = _isNearEnd();
      _historyWindow.acceptRecent(batch);
      _historyWindowRevision++;

      final regroupedRecovery =
          mayFocusRecovery &&
          navigationGeneration == _automaticScrollGeneration &&
          _retainIdleRecoveryForPresentation();
      final messages = _restHistoryForPresentation();
      _extractToolMessages(
        _historyWindow.rows,
        replacePresentation: _restReplyRetention?.hasRetainedReply != true,
      );
      setState(() {
        _messages = messages;
        _error = null;
      });
      if (_normalChat != null) {
        _applyNormalSnapshot(_normalChat!.snapshot, hydrateHistory: false);
      }
      if (regroupedRecovery && wasFollowingEnd) {
        _scheduleScrollTarget(const ChatScrollTarget.end());
      }
    } catch (e) {
      if (!_historyReadAttached(read)) return;
      if (read.responseGeneration != _responseGeneration) {
        _deferHistoryRefresh();
        return;
      }
      if (!_canApplyHistoryRead(read)) return;
      final errStr = e.toString();
      if (errStr.contains('404') || errStr.contains('not found')) {
        if (_pendingReattachResync || _messages.isNotEmpty) return;
        setState(() => _messages = []);
        return;
      }
      setState(() => _error = errStr);
    } finally {
      _finishHistoryLoading(read);
      if (persistedContextFlight != null) {
        _finishPersistedHistoryContext(
          persistedContextFlight,
          invalidated: !_canApplyHistoryRead(read),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getRecentMessages(
    _ChatHistoryRead read,
  ) => _client.getMessages(
    read.sessionId,
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
    _historyWindowRevision++;
    _restReplyRetention?.reconcile(_historyWindow.rows);
    _extractToolMessages(
      _historyWindow.rows,
      replacePresentation: _restReplyRetention?.hasRetainedReply != true,
    );
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_historyWindow.hasOlder) return;
    final scrollGeneration = _automaticScrollGeneration;
    final offset = _historyWindow.olderOffset;
    final read = _beginHistoryRead(_storedSessionKey, older: true);
    _olderHistoryRead = read;
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    setState(() => _loadingOlder = true);
    try {
      final older = await _client.getMessages(
        read.sessionId,
        limit: ChatHistoryWindow.pageSize,
        offset: offset,
        latest: true,
      );
      if (!_canApplyHistoryRead(read) ||
          read.windowRevision != _historyWindowRevision ||
          offset != _historyWindow.olderOffset ||
          _sending ||
          _streaming) {
        return;
      }
      _historyWindow.acceptOlder(older);
      final acceptedRevision = ++_historyWindowRevision;
      _extractToolMessages(_historyWindow.rows, replacePresentation: false);
      setState(() => _messages = _restHistoryForPresentation());
      final normalSnapshot = _normalChat?.snapshot;
      if (normalSnapshot != null) {
        _applyNormalSnapshot(normalSnapshot, hydrateHistory: false);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_canApplyHistoryRead(read) ||
            acceptedRevision != _historyWindowRevision ||
            _sending ||
            _streaming ||
            !_canApplyAutomaticScroll(scrollGeneration) ||
            !_scrollController.hasClients) {
          return;
        }
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
      if (mounted && identical(_olderHistoryRead, read)) {
        _olderHistoryRead = null;
        setState(() => _loadingOlder = false);
      }
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
    final read = _beginHistoryRead(_storedSessionKey);
    _deferredHistoryRead = read;
    var retryAfterSettlement = false;
    try {
      final messages = await _getRecentMessages(read);
      if (!_historyReadAttached(read)) return;
      if (read.responseGeneration != _responseGeneration ||
          _sending ||
          _streaming ||
          _stopResponseInFlight ||
          _pendingReattachResync) {
        _deferredHistoryRefreshPending = true;
        retryAfterSettlement = true;
        return;
      }
      if (!_acceptHistoryRead(read, messages)) return;
      _acceptRecentMessages(messages);
      setState(() {
        _messages = _restHistoryForPresentation();
        _error = null;
      });
      final normalSnapshot = _normalChat?.snapshot;
      if (normalSnapshot != null) {
        _applyNormalSnapshot(normalSnapshot, hydrateHistory: false);
      }
    } catch (_) {
      // A stale failure cannot resurrect pending work after a newer success.
      if (_historyReadAttached(read) &&
          read.observation >= _historyReadAccepted &&
          !(read.authority?.isSuperseded ?? false)) {
        _deferredHistoryRefreshPending = true;
        retryAfterSettlement = read.responseGeneration != _responseGeneration;
      }
    } finally {
      if (identical(_deferredHistoryRead, read)) {
        _deferredHistoryRead = null;
        _deferredHistoryRefreshing = false;
      }
      if (retryAfterSettlement &&
          _historyReadAttached(read) &&
          !_sending &&
          !_streaming &&
          !_stopResponseInFlight &&
          !_pendingReattachResync) {
        unawaited(_refreshDeferredHistoryIfIdle());
      }
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
        ..['_chat_response_complete'] =
            projection.status == GatewayRecoveryTurnStatus.completed &&
            !projection.isFailClosed
        ..['_gateway_client_turn_id'] = projection.clientTurnId
        ..['_gateway_message_id'] = projection.messageId
        ..['_gateway_last_seq'] = projection.lastSeq
        ..['_gateway_pending_response'] = projection.isActive;
      if (projection.finalMessageRef != null) {
        message['_gateway_final_message_ref'] = projection.finalMessageRef;
      }
      // Only the application owner may supply a live receipt. Replayed events,
      // snapshots and route rebuilds deliberately do not manufacture one.
      if (projection.receivedAt != null) {
        ChatMessageTime.observe(
          message,
          source: ChatMessageTimeSource.received,
          at: projection.receivedAt,
        );
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
        _terminalTurnNotice = projection.isFailClosed
            ? context.l10n.hermes_stopped_recovery_safely_no_prompt_was_resent
            : projection.status == GatewayRecoveryTurnStatus.failed
            ? context.l10n.turn_failed
            : projection.status == GatewayRecoveryTurnStatus.interrupted
            ? context.l10n.response_stopped
            : null;
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
    final pendingSubmission = _recoverableSubmissionState;
    if (pendingSubmission != null && !pendingSubmission.isCompleted) {
      pendingSubmission.complete();
    }
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

  void _extractToolMessages(
    List<Map<String, dynamic>> messages, {
    bool replacePresentation = true,
  }) {
    final normal = _normalChat != null;
    final liveRuns = !normal && !replacePresentation
        ? _timeline.runs
        : const <ChatTimelineRun>[];
    if (!normal && replacePresentation) _timeline = _timeline.clear();
    for (final recovered in recoverDelegatedTasks(messages)) {
      // Real child references can reconnect a persisted row to live activity;
      // neither task goal nor task index is sufficient identity evidence.
      final index = _subagentActivities.indexWhere(
        (activity) => activity.matchesTask(recovered),
      );
      if (index < 0) {
        _subagentActivities.add(recovered);
      } else {
        _subagentActivities[index] = _subagentActivities[index].merge(
          recovered,
        );
        _openTaskController?.updateTask(_subagentActivities[index]);
      }
    }
    // Canonical task recovery may be older than an independently observed
    // child tip. Reapply that single owner's current metadata after hydration;
    // never clone its controller or let parent saved rows reset the viewer.
    if (normal) {
      for (final update
          in _normalSnapshot?.subagents ?? const <GatewaySubagentActivity>[]) {
        _mergeSubagentActivity(update);
      }
    }
    final observedByToolId = {
      for (final activity in [
        ..._toolActivities,
        if (normal) ...?_normalSnapshot?.tools,
      ])
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
    for (final run in liveRuns) {
      if (run.kind != ChatTimelineKind.tool) continue;
      final activity = run.activity!;
      final index = _toolActivities.indexWhere(
        (stored) =>
            stored.identity == activity.identity ||
            activity.toolId != null && stored.toolId == activity.toolId,
      );
      if (index < 0) {
        _toolActivities.add(activity);
      } else {
        _timeline = _timeline.tool(run.scope, _toolActivities[index]);
      }
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
      hermesStatusSnackBar(
        context,
        message: message,
        status: HermesStatus.failed,
      ),
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
      sessionId: _normalLocalSessionKey,
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
          sessionId: _normalLocalSessionKey,
          provider: choice.provider,
          model: choice.model,
        );
        if (!mounted || _pendingReattachResync) return;
        await desktopGateway.setSessionReasoning(
          sessionId: _normalLocalSessionKey,
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
  Future<void> _sendMessage({bool speakResponse = false}) async {
    if (_voiceComposer.listening ||
        _preparingSend ||
        _archiving ||
        _stopResponseInFlight ||
        _midTurnSendInFlight ||
        _normalChat?.snapshot.steering == true) {
      return;
    }
    final text = _textController.text.trim();
    if (_streaming) {
      if (text.isNotEmpty) {
        await _sendWhileWorking(text);
      } else if (_attachmentDrafts.isNotEmpty) {
        // Active-turn guidance is text-only. Do not silently drop an explicit
        // attachments-only Send, interrupt work, or consume the staged files.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.running_message_not_accepted)),
        );
      }
      return;
    }
    final attachments = List<AttachmentDraft>.from(_attachmentDrafts);
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
    final usesRemoteTransport =
        (_turnApplicationSession != null && !_legacyTransportFallback) ||
        _desktopGateway != null ||
        widget.testRemotePromptSubmit != null;
    try {
      if (usesRemoteTransport) {
        _attachmentDraftService.validateRemoteDrafts(attachments);
      } else {
        _attachmentDraftService.validateRestDrafts(attachments);
      }
    } on AttachmentDraftException catch (error) {
      _showAttachmentError(error.message);
      return;
    }

    // Own this submission before the first await. Only the captured prompt is
    // consumed; setup, uploads and stream callbacks must not clear newer text.
    if (_normalChat != null &&
        (_turnApplicationSession == null || _legacyTransportFallback)) {
      final reservation = _normalChat!.reserve();
      if (reservation == null) return;
      _normalReservation = reservation;
    }
    _preparingSend = true;
    setState(() => _sending = true);
    _clearComposerForSend(text);
    try {
      await _sessionModelRestore;
    } catch (error) {
      if (!mounted) return;
      _restoreComposerAfterRejectedSend(text);
      _handleSendError(error);
      final reservation = _normalReservation;
      if (reservation != null) _normalChat?.cancelPreparation(reservation);
      _normalReservation = null;
      return;
    } finally {
      _preparingSend = false;
    }
    if (!mounted) return;
    await _submitMessage(
      text: text,
      attachments: attachments,
      speakResponse: speakResponse,
    );
  }

  Future<void> _sendWhileWorking(String text) async {
    final normal = _normalChat;
    if (normal?.snapshot.hasActiveTurn == true) {
      if (!normal!.canSteer) return;
      final revision = _composerRevision;
      setState(() => _midTurnSendInFlight = true);
      try {
        final accepted = await normal.steer(text);
        if (!mounted) return;
        if (accepted) {
          // An acknowledgement consumes only the submitted edit. Typing,
          // clearing or changing route ownership while it waits wins.
          if (_draftWriter.isCurrent && revision == _composerRevision) {
            _setRestoredComposer('');
          }
          _commitComposerForSend();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted
                  ? context.l10n.message_queued_for_running_turn
                  : context.l10n.running_message_not_accepted,
            ),
          ),
        );
      } catch (error) {
        if (!mounted) return;
        final rejected =
            error is JsonRpcError &&
            const [-32601, 4001, 4002, 4010].contains(error.code);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              rejected
                  ? context.l10n.running_message_not_accepted
                  : context.l10n.running_message_delivery_unknown,
            ),
          ),
        );
      } finally {
        if (mounted) setState(() => _midTurnSendInFlight = false);
      }
      return;
    }

    // The OpenAI-compatible SSE transport has no steerable run handle.
    // Use the existing explicit Stop contract before sending a new prompt;
    // never start a second stream over the active response. The button names
    // this fallback "Stop and send" rather than claiming non-interruption.
    setState(() => _midTurnSendInFlight = true);
    var ownsHandoff = true;
    _clearComposerForSend(text);
    try {
      final stopped = await _stopResponse();
      if (!mounted) return;
      if (!stopped) {
        _restoreComposerAfterRejectedSend(text);
        return;
      }
      // _submitMessage synchronously takes ownership of the next stream.
      // Release this short handoff flight, not the lifetime of the new run.
      _midTurnSendInFlight = false;
      ownsHandoff = false;
      await _submitMessage(
        text: text,
        attachments: const [],
        speakResponse: false,
      );
    } finally {
      if (mounted && ownsHandoff) {
        setState(() => _midTurnSendInFlight = false);
      }
    }
  }

  Future<void> _submitMessage({
    required String text,
    required List<AttachmentDraft> attachments,
    required bool speakResponse,
  }) async {
    // A remote-gateway profile uses one transport for every prompt. Images and
    // arbitrary files are both attached with the official `file.attach` RPC.
    if (_turnApplicationSession != null && !_legacyTransportFallback) {
      await _sendRecoverableGatewayMessage(
        text: text,
        attachments: attachments,
        speakResponse: speakResponse,
      );
      return;
    }
    if (_desktopGateway != null || widget.testRemotePromptSubmit != null) {
      await _sendDesktopGatewayMessage(
        text: text,
        attachments: attachments,
        speakResponse: speakResponse,
      );
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
        _restoreComposerAfterRejectedSend(text);
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

    _commitComposerForSend();
    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;
    final responseGeneration = ++_responseGeneration;
    _activeResponseTransport = _ResponseTransport.rest;

    // The server returns oldest-to-newest history. Preserve that order; the
    // gateway client appends the current prompt exactly once.
    final history = buildRestChatHistory(_messages);
    final replyRetention = RestChatReplyRetention.admit(
      _messages,
      historyKnown: _hasSuccessfulHistoryRead,
    );
    _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());

    setState(() {
      _sending = true;
      _streaming = true;
      _terminalTurnNotice = null;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'starting',
        text: context.l10n.starting_hermes,
      );
      _messages.add({
        'role': 'user',
        'content': localContent,
        AndroidPromptContext.localUserTextKey: true,
        ChatMessageTime.observedAtKey: DateTime.now().millisecondsSinceEpoch,
        ChatMessageTime.sourceKey: 'sent',
        AndroidPromptContext.wireContentKey: GatewayChatClient.buildUserContent(
          message: text,
          imageDataUrl: imageDataUrl,
        ),
      });
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
        if (!mounted || responseGeneration != _responseGeneration) return;
        setState(() {
          _gatewayTurnStatus = null;
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            final assistant = _messages.last;
            final current = assistant['content'] as String;
            if (current.isEmpty && token.isNotEmpty) {
              _registerMaterializedAssistantMessage();
            }
            assistant['content'] = current + token;
            if (token.isNotEmpty) {
              ChatMessageTime.observe(
                assistant,
                source: ChatMessageTimeSource.received,
              );
            }
            _timeline = _timeline.appendText(assistant, token);
            _retainReceiptPresentation();
          }
        });
        _scheduleStreamingFollow();
      },
      onToolProgress: (progress) {
        if (!mounted || responseGeneration != _responseGeneration) return;
        _upsertToolProgress(
          progress,
          eventType: progress['status'] == 'running'
              ? 'tool.start'
              : 'tool.update',
        );
      },
      onReasoning: (text) => _handleDesktopGatewayEvent(
        StreamEvent(type: 'reasoning.delta', data: {'text': text}),
        responseGeneration,
      ),
      onStatus: (status) => _handleDesktopGatewayEvent(
        StreamEvent(type: 'status.update', data: status),
        responseGeneration,
      ),
      onDone: () async {
        if (!mounted || responseGeneration != _responseGeneration) return;
        // The SSE client requires an explicit successful protocol completion.
        final assistant = _lastAssistantMessage();
        setState(() {
          assistant?['_chat_response_complete'] = true;
          if (assistant != null) {
            ChatMessageTime.observe(
              assistant,
              source: ChatMessageTimeSource.received,
            );
          }
          assistant?['_gateway_pending_response'] = false;
          replyRetention.complete(_messages);
          _restReplyRetention = replyRetention;
          _sending = false;
          _streaming = false;
          _gatewayTurnStatus = null;
        });
        // Refresh messages to get the final server-side state. The token is
        // retained across both HTTP and attachment cleanup, including failure.
        final read = _beginHistoryRead(widget.session.id);
        try {
          final messages = await _getRecentMessages(read);
          if (!_canApplyHistoryRead(read)) return;
          if (pendingImage != null) {
            await _attachmentDraftService.removeCachedFile(pendingImage);
          }
          if (!_acceptHistoryRead(read, messages)) return;
          _acceptRecentMessages(messages);
          setState(() {
            _messages = _restHistoryForPresentation();
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
          if (!_canApplyHistoryRead(read)) return;
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
        } finally {
          // Completing this REST operation is independent of the freshness of
          // its history GET. If a newer success superseded that GET, release
          // only the still-owned stream latch, without touching its transcript,
          // error, status or scroll. Never strand Send behind a discarded read.
          if (_historyReadAttached(read) &&
              responseGeneration == _responseGeneration &&
              _activeResponseTransport == _ResponseTransport.rest) {
            setState(() {
              _streaming = false;
              _sending = false;
              _activeResponseTransport = _ResponseTransport.none;
            });
          }
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
        if (!hadContent) _restoreComposerAfterRejectedSend(text);
        _handleSendError(error, removePendingUserMessage: true);
      },
    );
  }

  Future<void> _sendDesktopGatewayMessage({
    required String text,
    required List<AttachmentDraft> attachments,
    required bool speakResponse,
  }) async {
    final chat = _normalChat;
    if (chat == null) return;
    final reservation = _normalReservation ?? chat.reserve();
    if (reservation == null) {
      _restoreComposerAfterRejectedSend(text);
      return;
    }
    _normalReservation = reservation;
    final desktopGateway = _desktopGateway;
    final responseGeneration = _responseGeneration;
    var handedOff = false;
    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;
    try {
      final projectCwd = widget.projectWorkingDirectory?.trim();
      if (widget.session.isLocalDraft && projectCwd?.isNotEmpty == true) {
        if (desktopGateway != null) {
          await desktopGateway.ensureSession(
            _normalLocalSessionKey,
            workingDirectory: projectCwd,
          );
        } else {
          await widget.testLegacyProjectSessionEnsure?.call(
            widget.session.id,
            projectCwd!,
          );
        }
      }
      if (!mounted || responseGeneration != _responseGeneration) return;
      if (desktopGateway != null) {
        await _applySessionModelOverride(desktopGateway);
      }
      if (!mounted || responseGeneration != _responseGeneration) return;
      await _attachmentSendCoordinator.uploadThenSubmit(
        drafts: attachments,
        upload: ({required draft, required dataUrl}) async {
          if (!mounted || responseGeneration != _responseGeneration) {
            throw StateError('Attachment preparation was cancelled.');
          }
          if (desktopGateway == null) {
            final upload = widget.testRemoteAttachmentUpload;
            if (upload == null) {
              throw StateError('Test remote transport does not upload files');
            }
            return upload(draft: draft, dataUrl: dataUrl);
          }
          return _uploadAttachmentDraft(desktopGateway, draft, dataUrl);
        },
        onChanged: (draft) {
          if (!mounted || responseGeneration != _responseGeneration) return;
          setState(() {
            _gatewayTurnStatus = GatewayTurnStatus(
              kind: 'upload',
              text: context.l10n.preparing_attachments,
            );
          });
        },
        submitPrompt: (refTexts) async {
          if (!mounted || responseGeneration != _responseGeneration) return;
          final prompt = [
            text,
            refTexts.join('\n'),
          ].where((part) => part.trim().isNotEmpty).join('\n\n');
          final labels = attachments
              .map((file) => '[${context.l10n.attached_file}: ${file.name}]')
              .join('\n');
          final localContent = [
            text,
            labels,
          ].where((part) => part.trim().isNotEmpty).join('\n\n');
          final testSubmit = widget.testRemotePromptSubmit;
          final knownStored =
              widget.testStoredSessionKey?.call(widget.session.id) ??
              _storedSessionId ??
              (widget.session.isLocalDraft && desktopGateway != null
                  ? null
                  : widget.session.id);
          _commitComposerForSend();
          _attachmentDrafts.clear();
          handedOff = true;
          _normalReservation = null;
          // All post-handoff callbacks and error/recovery handling live on the
          // app owner. This await's UI continuation is fenced on reattachment.
          await chat.submitPrepared(
            reservation: reservation,
            text: prompt,
            localContent: localContent,
            submit: testSubmit,
            knownStoredSessionId: knownStored,
            rawDraftText: text,
            canRestoreDraft: _composerRevision == _clearedComposerRevision,
            draftHandle: _draftWriter.draftHandle,
          );
        },
      );
      if (!mounted || responseGeneration != _responseGeneration) return;
    } catch (error) {
      if (!mounted || responseGeneration != _responseGeneration) return;
      // Only definitely pre-wire rejection restores this route's captured
      // revision. Post-wire errors are absorbed as unresolved by the owner.
      if (!chat.snapshot.wireEmitted) {
        _restoreComposerAfterRejectedSend(text);
        setState(() {
          _attachmentDrafts
            ..clear()
            ..addAll(attachments);
        });
        _handleSendError(error);
        unawaited(_refreshDeferredHistoryIfIdle());
      }
    } finally {
      if (!handedOff) chat.cancelPreparation(reservation);
      if (identical(_normalReservation, reservation)) _normalReservation = null;
    }
  }

  Future<void> _sendRecoverableGatewayMessage({
    required String text,
    required List<AttachmentDraft> attachments,
    required bool speakResponse,
  }) async {
    final turnSession = _turnApplicationSession;
    if (turnSession == null) return;
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
      _restoreComposerAfterRejectedSend(text);
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
    _commitComposerForSend();
    _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());
    final firstState = Completer<void>();
    _recoverableSubmissionState = firstState;
    setState(() {
      _streaming = true;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'starting',
        text: context.l10n.starting_hermes,
      );
      _attachmentDrafts.clear();
      _messages.add({
        'role': 'user',
        'content': localContent,
        AndroidPromptContext.localUserTextKey: true,
        ChatMessageTime.observedAtKey: DateTime.now().millisecondsSinceEpoch,
        ChatMessageTime.sourceKey: 'sent',
      });
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
          _restoreComposerAfterRejectedSend(text);
          for (final draft in attachments) {
            draft
              ..status = AttachmentDraftStatus.ready
              ..error = null;
          }
          _attachmentDrafts
            ..clear()
            ..addAll(attachments);
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
    } finally {
      // Definite rejection or failed recovery may produce no callback. Release
      // a queued Stop without inventing an identity or issuing a legacy RPC.
      if (!firstState.isCompleted) firstState.complete();
      if (identical(_recoverableSubmissionState, firstState)) {
        _recoverableSubmissionState = null;
      }
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
        _gatewayTurnStatus = const GatewayTurnStatus(
          kind: 'reasoning',
          text: '',
        );
        final assistant = _lastAssistantMessage();
        if (assistant == null) return;
        final current = assistant['_gateway_reasoning']?.toString() ?? '';
        assistant['_gateway_reasoning'] = reasoning.applyTo(current);
        _timeline = _timeline.reasoning(assistant, reasoning);
        _retainReceiptPresentation();
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
        _timeline = _timeline.appendText(assistant, token);
        _retainReceiptPresentation();
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
        _timeline = _timeline.textSnapshot(assistant, transition.sealedText);
        _retainReceiptPresentation();
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
        final pending = _lastAssistantMessage();
        final assistant = _completionAssistantMessage(
          event.data,
          event.data['text']?.toString() ?? completeText,
        );
        if (assistant != null) {
          assistant['_gateway_pending_response'] = false;
          assistant['_chat_response_complete'] = isSuccessfulResponseReceipt(
            event.data,
          );
          if (completeText.isNotEmpty) {
            final current = assistant['content']?.toString() ?? '';
            if (current.isEmpty) _registerMaterializedAssistantMessage();
            assistant['content'] = completeText;
            _timeline = _timeline.textSnapshot(
              assistant,
              completeText,
              preservePosition: !identical(assistant, pending),
            );
            _retainReceiptPresentation();
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
      _timeline = _timeline.reassignScope(
        pending,
        candidate,
        replaceReasoning: pending['_gateway_reasoning_replaces'] == true,
      );
      _messages.removeAt(pendingIndex);
      _retainReceiptPresentation();
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
    if (const {
      'message.complete',
      'turn.end',
      'turn.error',
      'error',
    }.contains(event.type)) {
      return;
    }
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

  GatewaySubagentActivity _mergeSubagentActivity(
    GatewaySubagentActivity update,
  ) {
    final index = _subagentActivities.indexWhere(
      (activity) => activity.matchesTask(update),
    );
    final merged = index < 0
        ? update
        : _subagentActivities[index].merge(update);
    if (index < 0) {
      _subagentActivities.add(merged);
    } else {
      _subagentActivities[index] = merged;
    }
    _openTaskController?.updateTask(merged);
    return merged;
  }

  void _upsertSubagent(String eventType, Map<String, dynamic> data) {
    final update = GatewaySubagentActivity.fromGatewayEvent(eventType, data);
    if (update == null || !mounted) return;
    setState(() {
      final merged = _mergeSubagentActivity(update);
      if ((_sending || _streaming) &&
          (!merged.isComplete || _gatewayTurnStatus?.kind == 'subagent')) {
        final active = _subagentActivities
            .where((task) => !task.isComplete)
            .lastOrNull;
        _gatewayTurnStatus = active == null
            ? null
            : GatewayTurnStatus(
                kind: 'subagent',
                text: delegatedTaskGoal(context.l10n, active),
              );
      }
    });
    if (_openTaskController == null) _scheduleStreamingFollow();
  }

  Future<void> _openDelegatedTask(GatewaySubagentActivity task) async {
    if (_openTaskController != null) return;
    final controller = DelegatedTaskController(
      task: task,
      history:
          widget.testTaskHistorySource?.call() ??
          DashboardTaskHistory.fromConnection(widget.connection),
    );
    _openTaskController = controller;
    _openingScrollInterrupted = true;
    // Fence queued callbacks too, without changing the parent's sticky follow
    // intent or deferring a jump until dismissal. Content keeps arriving.
    _automaticScrollGeneration++;
    _initialEndFramesRemaining = 0;
    try {
      // Freeze parent follow synchronously, then let its pending layout and
      // semantics flush before inserting the modal's separate semantics tree.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !identical(_openTaskController, controller)) return;
      await showDelegatedTaskTimeline(context, controller);
    } finally {
      controller.dispose();
      if (identical(_openTaskController, controller)) {
        _openTaskController = null;
      }
    }
  }

  Future<void> _respondToGatewayApproval(
    String choice, {
    String? requestId,
    bool Function()? isCurrent,
  }) async {
    final normal = _normalSession;
    final recovery = _turnApplicationSession;
    final gateway = _desktopGateway;
    final sessionId = widget.session.id;
    final localSessionId = _normalLocalSessionKey;
    void check() {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Approval authority was revoked.');
      }
    }

    check();
    if (requestId != null &&
        await normal?.tryRespondToApproval(
              sessionId: sessionId,
              requestId: requestId,
              choice: choice,
            ) ==
            true) {
      return;
    }
    check();
    final handled =
        await recovery?.tryRespondToApproval(
          sessionId: sessionId,
          choice: choice,
          requestId: requestId,
        ) ??
        false;
    if (handled) return;
    check();
    if (gateway == null) {
      throw StateError('The Desktop gateway session is no longer connected');
    }
    await gateway.respondToApproval(
      sessionId: localSessionId,
      choice: choice,
      serverRequestId: requestId,
    );
  }

  /// Answers approvals that notification actions left pending for this
  /// connection. Entries are removed only after the gateway confirms the
  /// answer: a cold start (no route-local session yet) or a throw keeps the
  /// tap pending for a later retry instead of losing it.
  void _consumePendingNotificationApproval() {
    prunePendingNotificationApprovals();
    final mine = [
      for (final approval in pendingNotificationApprovals.value)
        if (approval.connectionId == widget.connection.id &&
            approval.sessionId == widget.session.id &&
            approval.authority?.isCurrentFor(widget.connection) == true)
          approval,
    ];
    for (final approval in mine) {
      unawaited(_answerPendingNotificationApproval(approval));
    }
  }

  /// Approvals whose answer is in flight, so a notifier change cannot
  /// dispatch the same request twice.
  Future<void> _answerPendingNotificationApproval(
    PendingNotificationApproval approval,
  ) async {
    if (!claimNotificationApproval(approval)) return;
    final account = _historyAccountKey;
    final sessionId = widget.session.id;
    bool current() =>
        mounted &&
        account == _historyAccountKey &&
        sessionId == widget.session.id &&
        approval.authority?.isCurrentFor(widget.connection) == true &&
        pendingNotificationApprovals.value.any(
          (item) => identical(item, approval),
        );
    try {
      if (!await approval.authority!.validate() || !current()) return;
      // The normal approval path: route-local turn session first, then the
      // desktop gateway. A throw means the route-local gateway is not up
      // yet (cold start/reconnect) — keep the entry and retry later.
      await _respondToGatewayApproval(
        approval.choice,
        requestId: approval.requestId,
        isCurrent: current,
      );
      removePendingNotificationApproval(approval);
    } catch (_) {
      // Unresolved, not answered: keep the entry for a later retry.
    } finally {
      releaseNotificationApproval(approval);
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
    _normalSession?.forgetAnsweredInput(requestId);
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
    _normalSession?.forgetAnsweredInput(requestId);
  }

  bool _ownsGatewayApproval(String requestId) {
    if (_normalSession?.ownsApprovalRequest(
          sessionId: widget.session.id,
          requestId: requestId,
        ) ==
        true) {
      return true;
    }
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
      if (_usesNormalInputOwner &&
          mounted &&
          ModalRoute.of(context)?.isCurrent != true) {
        _normalInputSeen.clear();
        _approvalDialogOpen = false;
        _activeApprovalServerRequestId = null;
        return;
      }
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
      final approvalRoute = DialogRoute<bool>(
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
      _approvalPromptRoute = approvalRoute;
      final responded = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(approvalRoute);
      _approvalPromptRoute = null;
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
            hermesStatusSnackBar(
              context,
              message: context.l10n.could_not_deny_the_command(error),
              status: HermesStatus.failed,
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
      if (_usesNormalInputOwner &&
          mounted &&
          ModalRoute.of(context)?.isCurrent != true) {
        _normalInputSeen.clear();
        _activeSensitivePrompt = null;
        return;
      }
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
      final sensitiveRoute = DialogRoute<GatewaySensitivePromptDialogResult>(
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
      _sensitivePromptRoute = sensitiveRoute;
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(sensitiveRoute);
      _sensitivePromptRoute = null;
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
      final route = _sensitivePromptRoute;
      if (route != null && route.isActive) {
        route.navigator?.removeRoute(
          route,
          GatewaySensitivePromptDialogResult.expired,
        );
      }
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
        final route = _approvalPromptRoute;
        if (route != null && route.isActive) {
          route.navigator?.removeRoute(route, false);
        }
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
      if (_usesNormalInputOwner &&
          mounted &&
          ModalRoute.of(context)?.isCurrent != true) {
        _normalInputSeen.clear();
        _activeClarifyPrompt = null;
        return;
      }
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
            hermesStatusSnackBar(
              context,
              message: context.l10n.could_not_skip_the_hermes_question,
              status: HermesStatus.failed,
            ),
          );
        }
      }
      _drainSensitivePromptQueue();
      _drainClarifyPromptQueue();
    });
  }

  Future<bool> _stopRecoverableGatewayResponse() async {
    final turnSession = _turnApplicationSession!;
    final responseGeneration = _responseGeneration;
    final pendingSubmission = _recoverableSubmissionState;
    setState(() {
      _stopResponseInFlight = true;
      _awaitingVoiceReply = false;
    });
    try {
      if (_activeClientTurnId == null) await pendingSubmission?.future;
      if (!mounted || responseGeneration != _responseGeneration) return false;
      final clientTurnId = _activeClientTurnId;
      // A first terminal callback or definite pre-ACK rejection needs no
      // interrupt. Unknown admission must never borrow the legacy route.
      if (clientTurnId == null) return false;
      final state = await turnSession.interrupt(
        localSessionId: widget.session.id,
        clientTurnId: clientTurnId,
      );
      if (!mounted || responseGeneration != _responseGeneration) return false;
      // A real terminal may have arrived while interrupt was pending. Its
      // cleared identity wins over an older, nonterminal interrupt read-back.
      if (_activeClientTurnId == clientTurnId) _applyGatewayTurnState(state);
      final stopped = state.isTerminal && !state.isFailClosed && !_streaming;
      if (!stopped && _activeClientTurnId == clientTurnId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stop requested. Waiting for Hermes to finish.'),
          ),
        );
      }
      // Stop is an intent, not lifecycle settlement. A nonterminal reconcile
      // must keep the submit observer, scaffold and admission ownership alive;
      // in particular Stop and send cannot launch another prompt yet.
      return stopped;
    } catch (error) {
      if (mounted && responseGeneration == _responseGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not request stop: $error')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _stopResponseInFlight = false);
      unawaited(_refreshDeferredHistoryIfIdle());
    }
  }

  Future<bool> _stopResponse() async {
    if (!_streaming || _stopResponseInFlight) return false;
    if (_turnApplicationSession != null && !_legacyTransportFallback) {
      return _stopRecoverableGatewayResponse();
    }
    final normal = _normalChat;
    if (normal?.snapshot.hasActiveTurn == true) {
      final turn = normal!.turnId;
      setState(() {
        _stopResponseInFlight = true;
        _hiddenActivityTurnId = turn;
        _awaitingVoiceReply = false;
      });
      try {
        final requested = await normal.interrupt();
        if (!mounted || turn != normal.turnId) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              requested
                  ? 'Stop requested. Waiting for Hermes to finish.'
                  : 'The running turn could not be reached. Reconnecting without resending.',
            ),
          ),
        );
        return requested;
      } catch (error) {
        if (mounted && turn == normal.turnId) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not request stop: $error')),
          );
        }
      } finally {
        if (mounted) setState(() => _stopResponseInFlight = false);
      }
      return false;
    }

    final transport = _activeResponseTransport;
    // Capture the cancelled admission before its empty scaffold is removed.
    // Looking up the last assistant after cancellation can select an older
    // successful reply and incorrectly revoke its quiet-mode completion.
    final stoppedAssistant = _lastAssistantMessage();
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
      bool interrupted;
      switch (transport) {
        case _ResponseTransport.rest:
          interrupted = await _gateway.cancelActiveMessage();
        case _ResponseTransport.desktop:
          interrupted =
              await _desktopGateway?.interruptPrompt(
                sessionId: _normalLocalSessionKey,
              ) ??
              false;
        case _ResponseTransport.none:
          interrupted = false;
      }
      if (!mounted) return false;
      if (interrupted) {
        setState(() {
          stoppedAssistant?['_gateway_pending_response'] = false;
          stoppedAssistant?['_chat_response_complete'] = false;
        });
      }
      if (!mounted) return false;
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
      return interrupted;
    } catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        hermesStatusSnackBar(
          context,
          message: context.l10n.response_closed_locally_gateway_stop_failed(
            error,
          ),
          status: HermesStatus.failed,
          duration: const Duration(seconds: 6),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _stopResponseInFlight = false);
      unawaited(_refreshDeferredHistoryIfIdle());
    }
  }

  /// Clear the visible draft immediately but retain the unsent prompt through
  /// cancellable setup. Leaving during an upload must not silently lose it.
  void _clearComposerForSend(String text) {
    _setRestoredComposer('');
    _clearedComposerRevision = _composerRevision;
    _draftWriter.edit(text);
    unawaited(_draftWriter.save(text));
  }

  /// Preparation finished: hand off the prompt without touching newer typing.
  void _commitComposerForSend() {
    unawaited(_draftWriter.save(_textController.text));
  }

  /// Restore only the send's untouched draft. A newer edit (including typing
  /// and then deleting) belongs to the user, not this failed submission.
  void _restoreComposerAfterRejectedSend(String text) {
    if (text.trim().isEmpty) return;
    if (!_draftWriter.isCurrent) return;
    if (_composerRevision == _clearedComposerRevision) {
      _setRestoredComposer(text);
    }
    unawaited(_draftWriter.save(_textController.text));
  }

  void _handleSendError(Object e, {bool removePendingUserMessage = false}) {
    _scrollCoordinator.cancelStreaming();
    setState(() {
      _sending = false;
      _streaming = false;
      _gatewayTurnStatus = null;
      _activeResponseTransport = _ResponseTransport.none;
      _awaitingVoiceReply = false;
      _terminalTurnNotice = context.l10n.send_failed(e);
      if (removePendingUserMessage &&
          _messages.isNotEmpty &&
          _messages.last['role'] == 'user') {
        _messages.removeLast();
      }
    });

    // The persistent non-spinning bottom notice owns this failure. A transient
    // snackbar would duplicate it and disappear on route reattachment.
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
    if (update == null || _timeline.excludesTool(update)) return;
    setState(() {
      final idx = toolActivityUpdateIndex(_toolActivities, update, eventType);
      if (idx >= 0) {
        final previous = _toolActivities[idx];
        _toolActivities[idx] = previous.merge(update);
      } else {
        _toolActivities.add(update);
      }
      final activity = idx >= 0 ? _toolActivities[idx] : update;
      final toolId = activity.toolId;
      if (toolId != null) {
        _presentation.aliasTool(activity.identity, 'tool:$toolId');
      }
      final assistant = _lastAssistantMessage();
      if (assistant != null) {
        _timeline = _timeline.tool(assistant, activity);
        // A late completion of an evicted tool is not a new receipt/card.
        _toolActivities.removeWhere(
          (a) =>
              a.identity == update.identity &&
              !_timeline.runs.any((r) => r.activity?.identity == a.identity),
        );
        _retainReceiptPresentation();
      }
      if (!activity.isTerminal || _gatewayTurnStatus?.kind == 'tool') {
        _gatewayTurnStatus = GatewayTurnStatus.forRunningTool(
          _timeline
              .forScope(assistant ?? Object())
              .where((run) => run.activity != null)
              .map((run) => run.activity!),
        );
      }
    });

    _scheduleStreamingFollow();
  }

  /// Retention belongs to receipt ingestion, before any ListView projection.
  /// Do not change canonical/request accumulators to trim this view-only tail.
  void _retainReceiptPresentation() {
    _timeline = _timeline.retainScopes(
      _messages.map((row) => row['_normal_projection_id'] ?? row),
    );
    _toolActivities.removeWhere(_timeline.excludesTool);
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
          _sessionTitle.trim().isEmpty
              ? context.l10n.untitled_chat
              : _sessionTitle,
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
          if (_archiving)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox.square(
                  key: ValueKey('chat-archive-progress'),
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_streaming)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.l10n.responding,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: context.l10n.chat_actions,
              onOpened: () => unawaited(_refreshArchiveState()),
              onSelected: (action) {
                if (action == 'refresh' && !_pendingReattachResync) {
                  _fetchMessages(focusSavedHistory: true);
                }
                if (action == 'export') _exportConversation();
                if (action == 'received-output-info') {
                  unawaited(_showReceivedOutputDetails());
                }
                if (action == 'rename') unawaited(_renameSession());
                if (action == 'archive') unawaited(_setSessionArchived(true));
                if (action == 'unarchive') {
                  unawaited(_setSessionArchived(false));
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'rename',
                  enabled: _canRename,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text(context.l10n.rename),
                  ),
                ),
                PopupMenuItem(
                  value: _sessionArchived ? 'unarchive' : 'archive',
                  enabled: _canArchive,
                  child: ListTile(
                    leading: Icon(
                      _sessionArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    ),
                    title: Text(
                      _sessionArchived
                          ? context.l10n.unarchive_chat
                          : context.l10n.archive_chat,
                    ),
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
                if (_hasReceivedOutput)
                  PopupMenuItem(
                    value: 'received-output-info',
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text(context.l10n.received_output_details),
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
              if (_verboseMode)
                for (final notification in _gatewayNotifications.values)
                  _buildGatewayNotification(notification),
              if (_verboseMode && _legacyTransportFallback)
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
                            if (_endAffordanceController.isVisible ||
                                _canFocusSavedRecovery)
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: ChatEndAffordance(
                                  newMessageCount:
                                      _endAffordanceController.newMessageCount,
                                  onPressed: _goToEnd,
                                  label: _canFocusSavedRecovery
                                      ? context.l10n.saved_history_heading
                                      : null,
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
    final tokens = HermesTokens.of(context);
    final color = switch (notification.level) {
      GatewayNotificationLevel.success => tokens.success,
      GatewayNotificationLevel.warning => tokens.warning,
      GatewayNotificationLevel.error => tokens.danger,
      GatewayNotificationLevel.info => tokens.running,
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

  String? get _currentActivityText {
    final snapshot = _normalSnapshot;
    if (snapshot != null) {
      if (!snapshot.hasActiveTurn ||
          snapshot.responseFailure != null ||
          snapshot.turnId != null && snapshot.turnId == _hiddenActivityTurnId) {
        return null;
      }
      if (snapshot.pendingInput.isNotEmpty) {
        return context.l10n.hermes_is_waiting_for_input;
      }
    } else if (!_sending && !_streaming && !_pendingReattachResync) {
      return null;
    }
    final status = _gatewayTurnStatus;
    return switch (status?.kind) {
      'tool' => context.l10n.using(status!.text),
      'reasoning' => context.l10n.reasoning,
      'subagent' => context.l10n.delegated_task(status!.text),
      _ => status?.text ?? context.l10n.hermes_is_responding,
    };
  }

  String? get _terminalNoticeText {
    final snapshot = _normalSnapshot;
    if (snapshot?.responseFailure case final failure?) {
      return context.l10n.send_failed(failure);
    }
    if (snapshot?.hasActiveTurn == true) return null;
    if (snapshot?.phase == NormalGatewayTurnPhase.failed) {
      return context.l10n.send_failed(
        snapshot?.error ?? context.l10n.turn_failed,
      );
    }
    if (snapshot?.phase == NormalGatewayTurnPhase.reconciledUnknown) {
      return snapshot?.status?.text;
    }
    return _terminalTurnNotice;
  }

  Widget _buildInputBar({required double availableHeight}) {
    final sendEnabled =
        !_transcriptLoadBlocksComposer &&
        !_archiving &&
        !_preparingSend &&
        !_midTurnSendInFlight &&
        !_stopResponseInFlight &&
        !_pendingReattachResync &&
        !_voiceComposer.listening &&
        _normalChat?.snapshot.steering != true &&
        (_streaming
            ? (_normalChat?.snapshot.hasActiveTurn != true ||
                  _normalChat!.canSteer)
            : !_sending);
    final sendTooltip =
        _streaming && _normalChat?.snapshot.hasActiveTurn != true
        ? context.l10n.stop_and_send
        : context.l10n.send;
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
          BoxShadow(
            blurRadius: 4,
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
          ),
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
                    if (_currentActivityText case final activity?)
                      ChatActivityBar(text: activity)
                    else if (_terminalNoticeText case final notice?)
                      ChatActivityBar(text: notice, isTerminalNotice: true),
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
                      !_streaming &&
                      !_sending &&
                      !_pendingReattachResync,
                  excludeSemantics: true,
                  child: IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed:
                        (!_transcriptLoadBlocksComposer &&
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
                        textInputAction: TextInputAction.newline,
                        enabled: !_transcriptLoadBlocksComposer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_voiceComposer.listening && !_streaming)
                  VoiceComposerStartButton(
                    enabled:
                        !_transcriptLoadBlocksComposer &&
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
                if (_streaming) ...[
                  _buildComposerAction(
                    key: const Key('chat-stop-response'),
                    label: context.l10n.stop_response,
                    tooltip: context.l10n.stop_response,
                    icon: Icons.stop_rounded,
                    onPressed: _stopResponseInFlight ? null : _stopResponse,
                  ),
                  const SizedBox(width: 4),
                ],
                _buildComposerAction(
                  key: const Key('chat-send-message'),
                  label: sendTooltip == context.l10n.send
                      ? context.l10n.send_message
                      : sendTooltip,
                  tooltip: sendTooltip,
                  icon: Icons.send,
                  onPressed: sendEnabled ? _sendMessage : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerAction({
    required Key key,
    required String label,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final tokens = HermesTokens.of(context);
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            key: key,
            icon: Icon(icon, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: tokens.onAccentContainer,
            ),
            onPressed: onPressed,
            tooltip: tooltip,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _restHistoryForPresentation() =>
      _restReplyRetention?.reconcile(_historyWindow.rows) ??
      _historyWindow.rows;

  List<ChatDisplaySection> _normalDisplaySections({bool? verbose}) =>
      buildNormalChatDisplaySections(
        canonicalRows: _messages,
        receivedRows: _normalSnapshot?.displayRows ?? const [],
        canonicalTools: _toolActivities,
        receivedTools: _normalSnapshot?.tools ?? const [],
        receivedTimeline: _normalSnapshot?.timeline ?? const ChatTimeline(),
        receivedOutcomes: _normalSnapshot?.receivedOutcomes ?? const [],
        subagentActivities: _subagentActivities,
        notices: _gatewayNotices,
        verbose: verbose ?? _verboseMode,
        conversationOnly: !(verbose ?? _verboseMode),
      );

  bool get _canFocusSavedRecovery =>
      _normalSnapshot?.hasActiveTurn == false &&
      _normalSnapshot!.receivedOutcomes.any(
        (fact) =>
            fact.outcome == ReceivedLifecycleOutcome.unknown &&
            _historyObservedRecoveryOutcomeIds.contains(fact.id) &&
            !_retainedRecoveryOutcomeIds.contains(fact.id),
      );

  bool _retainIdleRecoveryForPresentation() {
    final snapshot = _normalSnapshot;
    if (snapshot == null || snapshot.hasActiveTurn) return false;
    final before = _retainedRecoveryOutcomeIds.length;
    _retainedRecoveryOutcomeIds.addAll(
      snapshot.receivedOutcomes
          .where(
            (fact) =>
                fact.outcome == ReceivedLifecycleOutcome.unknown &&
                _historyObservedRecoveryOutcomeIds.contains(fact.id),
          )
          .map((fact) => fact.id),
    );
    return _retainedRecoveryOutcomeIds.length != before;
  }

  ChatReceivedRecoveryProjection _normalRecoveryProjection() {
    ChatReceivedRecoveryProjection project(bool verbose) =>
        ChatReceivedRecoveryProjection.build(
          sections: _normalDisplaySections(verbose: verbose),
          timeline: _normalSnapshot?.timeline ?? const ChatTimeline(),
          outcomes: _normalSnapshot?.receivedOutcomes ?? const [],
          retainedOutcomeIds: _retainedRecoveryOutcomeIds,
        );
    return project(_verboseMode);
  }

  Future<void> _inspectRetainedRecovery(ChatDisplaySection section) async {
    if (_receivedRecoverySheetOpen) return;
    // Capture all rendering and media authority before opening another route.
    // The inspector never reads mutable ChatScreen state after construction.
    final connection = _normalSession?.connection ?? widget.connection;
    final sessionId = _storedSessionKey;
    final testFiles = widget.testMediaFilesClient;
    final verbose = _verboseMode;
    final density = _chatDensity;
    final sourceIdentity = (connection, sessionId, ChatDisplaySource.received);
    RemoteFilesDataSource filesClient() =>
        testFiles?.call(sessionId) ??
        RemoteFilesClient.fromConnection(
          connection,
          sessionId: sessionId,
          maxDownloadBytes: maxAttachmentDownloadBytes,
        );
    Widget buildMessage(
      Map<String, dynamic> message,
      bool expanded,
      ValueChanged<bool> onExpansionChanged,
    ) {
      final isUser = message['role'] == 'user';
      final content =
          (message['_display_content'] as String?) ??
          stripToolResultText(
            messageContentToText(
              AndroidPromptContext.displayContent(message, message['content']),
            ),
          );
      return MessageBubble(
        content: content,
        isUser: isUser,
        verbose: verbose,
        density: density,
        metadata: message,
        metadataExpanded: expanded,
        onMetadataExpansionChanged: onExpansionChanged,
        mediaReferencesFinal: message['_gateway_pending_response'] != true,
        mediaSourceIdentity: sourceIdentity,
        mediaFilesClient: isUser ? null : filesClient,
      );
    }

    _receivedRecoverySheetOpen = true;
    _automaticScrollGeneration++;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ReceivedRecoveryInspector(
          section: section,
          verbose: verbose,
          sourceIdentity: sourceIdentity,
          filesClient: filesClient,
          messageBuilder: buildMessage,
        ),
      );
    } finally {
      _receivedRecoverySheetOpen = false;
    }
  }

  Widget _buildSavedHistoryHeading() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Semantics(
        header: true,
        child: Text(
          context.l10n.saved_history_heading,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }

  String _receivedOutcomeLabel(ReceivedLifecycleOutcome outcome) =>
      switch (outcome) {
        ReceivedLifecycleOutcome.completed => context.l10n.turn_completed,
        ReceivedLifecycleOutcome.failed => context.l10n.turn_failed,
        ReceivedLifecycleOutcome.unknown =>
          context.l10n.received_outcome_unknown,
      };

  Widget _buildReceivedCell(
    dynamic item,
    Widget child,
    ReceivedScopeOutcome? fact,
  ) {
    final localPrompt = item is Map<String, dynamic> && item['role'] == 'user';
    final provenance = localPrompt
        ? context.l10n.local_prompt_context
        : context.l10n.received_output_badge;
    final label = fact == null
        ? provenance
        : '${_receivedOutcomeLabel(fact.outcome)} · $provenance';
    // Separate semantics node: do not merge away ExpansionTile/actions, or put
    // changing streamed content into a live-region announcement.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Semantics(
            container: true,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
        child,
      ],
    );
  }

  void _pinDetail(Object identity, bool expanded) {
    _detailExpansions.remove(identity);
    _detailExpansions[identity] = expanded;
    if (_detailExpansions.length > ToolActivityGroupPins.maxPins) {
      _detailExpansions.remove(_detailExpansions.keys.first);
    }
  }

  RemoteFilesDataSource _newMediaFilesClient() =>
      widget.testMediaFilesClient?.call(_storedSessionKey) ??
      RemoteFilesClient.fromConnection(
        widget.connection,
        sessionId: _storedSessionKey,
        maxDownloadBytes: maxAttachmentDownloadBytes,
      );

  Widget _buildDisplayItem(dynamic item, {ChatDisplaySource? source}) {
    if (item is ChatAttachmentItem) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: MediaArtifactCard(
          key: ValueKey((
            widget.connection,
            _storedSessionKey,
            source,
            item.id,
          )),
          ref: item.ref,
          filesClient: _newMediaFilesClient,
          sourceIdentity: (widget.connection, _storedSessionKey, source),
        ),
      );
    }
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
      return GatewaySubagentCard(
        key: ValueKey((_reasoningExpansionPins, 'delegation')),
        activities: item,
        pinnedExpansion: _delegationExpanded,
        onPinChanged: (expanded) => _delegationExpanded = expanded,
        onOpenTask: (task) => unawaited(_openDelegatedTask(task)),
      );
    }
    if (item is ChatReasoningItem) {
      // A same-State account/config replacement is a new preference scope.
      // Keep the public inner run key while dropping only that card's old
      // controller-local manual choice when its visit token changes.
      return KeyedSubtree(
        key: ValueKey((_reasoningExpansionPins, item.id)),
        child: GatewayReasoningCard(
          key: ValueKey<String>('reasoning-${item.id}'),
          id: item.id,
          pinnedExpansion: item.id == null
              ? null
              : _reasoningExpansionPins[item.id!],
          onPinChanged: (expanded) {
            if (item.id != null) {
              _reasoningExpansionPins.pin(item.id!, expanded);
            }
          },
          text: item.text,
          initiallyExpanded: item.initiallyExpanded,
        ),
      );
    }
    if (item is GatewayNotice) {
      final identity = (source, 'notice', item.identity);
      return GatewayNoticeCard(
        key: ValueKey((_detailExpansions, identity)),
        notice: item,
        initiallyExpanded: _detailExpansions[identity] ?? false,
        onExpansionChanged: (expanded) => _pinDetail(identity, expanded),
      );
    }

    final msg = item as Map<String, dynamic>;
    final report = BackgroundReport.fromMessage(msg);
    if (report != null) {
      final identity = (source, chatDisplayItemIdentity(msg));
      return BackgroundReportCard(
        key: ValueKey((_backgroundReportExpansions, identity)),
        report: report,
        initiallyExpanded: _backgroundReportExpansions[identity] ?? false,
        onExpansionChanged: (expanded) {
          _backgroundReportExpansions.remove(identity);
          _backgroundReportExpansions[identity] = expanded;
          if (_backgroundReportExpansions.length >
              ToolActivityGroupPins.maxPins) {
            _backgroundReportExpansions.remove(
              _backgroundReportExpansions.keys.first,
            );
          }
        },
      );
    }
    final role = (msg['role'] as String?) ?? 'assistant';
    final content =
        (msg['_display_content'] as String?) ??
        stripToolResultText(
          messageContentToText(
            AndroidPromptContext.displayContent(msg, msg['content']),
          ),
        );
    final isUser = role == 'user';

    return MessageBubble(
      key: msg['_timeline_id'] == null
          ? null
          : ValueKey<String>(msg['_timeline_id'] as String),
      content: content,
      isUser: isUser,
      verbose: _verboseMode,
      metadataExpanded:
          _detailExpansions[(source, chatDisplayItemIdentity(msg))] ?? false,
      onMetadataExpansionChanged: (expanded) =>
          _pinDetail((source, chatDisplayItemIdentity(msg)), expanded),
      density: _chatDensity,
      metadata: msg,
      mediaReferencesFinal: msg['_gateway_pending_response'] != true,
      mediaSourceIdentity: (widget.connection, _storedSessionKey, source),
      mediaFilesClient: isUser ? null : _newMediaFilesClient,
      onReadAloud: isUser
          ? null
          : () => _readAssistantText(content, announce: true),
      onEdit: isUser ? () => _editAndResend(content) : null,
      onRetry: isUser
          ? null
          : () => _retryPrompt(msg['_retry_prompt']?.toString() ?? ''),
    );
  }

  bool get _hasReceivedOutput =>
      _normalSnapshot?.displayRows.isNotEmpty == true ||
      _normalSnapshot?.timeline.runs.isNotEmpty == true ||
      _normalSnapshot?.tools.isNotEmpty == true;

  Widget _buildBody() {
    final hasReceived = _hasReceivedOutput;
    if (_loading && _messages.isEmpty && !hasReceived) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _messages.isEmpty && !hasReceived) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber,
                size: 48,
                color: HermesTokens.of(context).warning,
              ),
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

    final normal = _normalChat != null;
    final recovery = normal ? _normalRecoveryProjection() : null;
    final retained = recovery?.retained;
    final sections = normal ? recovery!.sections : const <ChatDisplaySection>[];
    final displayMessages = normal
        ? [for (final section in sections) ...section.items]
        : !_verboseMode
        ? buildConversationAttachmentItems(
            messages: _messages,
            toolActivities: _toolActivities,
            timeline: _timeline,
          )
        : buildChatDisplayItems(
            messages: _messages,
            toolActivities: _toolActivities,
            subagentActivities: _subagentActivities,
            notices: _gatewayNotices,
            verbose: _verboseMode,
            timeline: _timeline,
          );
    final cells = <({ChatDisplaySource? source, dynamic item, Key key})>[
      if (normal)
        for (final section in sections) ...[
          if (_verboseMode && section.source == ChatDisplaySource.canonical)
            (
              source: section.source,
              item: null,
              key: ValueKey((section.source, 'heading')),
            ),
          for (final item in section.items)
            (
              source: section.source,
              item: item,
              key: ValueKey((section.source, chatDisplayItemIdentity(item))),
            ),
        ]
      else
        for (var i = 0; i < displayMessages.length; i++)
          (source: null, item: displayMessages[i], key: ValueKey(i)),
    ];
    final receivedOutcomes = <Object, ReceivedScopeOutcome>{
      for (final section in sections)
        if (section.source == ChatDisplaySource.received) ...section.outcomes,
    };
    // Retained owner content can be visible while the first HTTP read is still
    // pending, rejected by an active turn, or unavailable. Align that first
    // actual transcript, not the eventual completion of a network request.
    if (displayMessages.isNotEmpty &&
        !_scrollCoordinator.initialEndAlignmentConsumed) {
      _scheduleInitialEndAlignment();
    }
    final cellIndices = <Key, int>{
      for (var i = 0; i < cells.length; i++)
        cells[i].key: i + (_historyWindow.hasOlder ? 1 : 0),
    };

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
          itemCount: cells.length + (_historyWindow.hasOlder ? 1 : 0),
          findChildIndexCallback: normal ? (key) => cellIndices[key] : null,
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
            final cell = cells[index - (_historyWindow.hasOlder ? 1 : 0)];
            if (cell.item == null) {
              return KeyedSubtree(
                key: cell.key,
                child: _buildSavedHistoryHeading(),
              );
            }
            final child = _buildDisplayItem(cell.item, source: cell.source);
            if (cell.source == null) return child;
            return KeyedSubtree(
              key: cell.key,
              child: _verboseMode && cell.source == ChatDisplaySource.received
                  ? _buildReceivedCell(
                      cell.item,
                      child,
                      receivedOutcomes[chatDisplayItemIdentity(cell.item)],
                    )
                  : child,
            );
          },
        ),
      ),
    );
    // Keep the Scrollable mounted when loading/error chrome changes; replacing
    // its parent would discard the opening alignment or the reader's position.
    return Column(
      children: [
        if (retained != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: OutlinedButton.icon(
              key: const Key('chat-retained-received-output'),
              onPressed: () => unawaited(_inspectRetainedRecovery(retained)),
              icon: const Icon(Icons.history),
              label: Text(context.l10n.received_output_badge),
            ),
          ),
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
      sessionId: _normalLocalSessionKey,
      provider: provider,
      model: model,
    );
    final effort = _sessionReasoningEffort;
    if (effort != null) {
      await desktopGateway.setSessionReasoning(
        sessionId: _normalLocalSessionKey,
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
  final bool metadataExpanded;
  final ValueChanged<bool>? onMetadataExpansionChanged;
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
  final Object? mediaSourceIdentity;

  const MessageBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.verbose = false,
    this.density = ChatDensity.comfortable,
    this.metadataExpanded = false,
    this.onMetadataExpansionChanged,
    this.metadata = const {},
    this.onReadAloud,
    this.onEdit,
    this.onRetry,
    this.mediaFilesClient,
    this.mediaSourceIdentity,
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
    // Capture the bubble's owner before crossing the modal boundary. The
    // dialog is not its descendant, and the bubble may later be deactivated.
    final previewOwner = InlineMediaPreviewScope.ownerOf(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        // The dialog renders on the dialog surface, not on a bubble: use the
        // prose colours with the dialog's own onSurface, not onAccent.
        final dialogTheme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(dialogContext.l10n.select_text),
          content: SingleChildScrollView(
            child: MarkdownBody(
              data: !isUser && mediaFilesClient != null
                  ? inlineDeliveredFilesAsLinks(
                      content,
                      isFinal: mediaReferencesFinal,
                    )
                  : content,
              selectable: true,
              sizedImageBuilder: (image) =>
                  Text(image.alt ?? image.title ?? ''),
              onTapLink: (_, href, _) => unawaited(
                _openLink(dialogContext, href, previewOwner: previewOwner),
              ),
              styleSheet: _messageStyleSheet(
                dialogTheme,
                HermesTokens.of(dialogContext),
                isUser: false,
                assistantTextColor: dialogTheme.colorScheme.onSurface,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(dialogContext.l10n.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openLink(
    BuildContext context,
    String? href, {
    InlineMediaPreviewOwner? previewOwner,
  }) async {
    final path = href == null ? null : deliveredFilePathFromHref(href);
    if (path == null) {
      await openMarkdownWebLink(context, href);
      return;
    }
    _openDeliveredLink(context, href, previewOwner: previewOwner);
  }

  MediaTagRef _deliveryRef(MediaTagRef ref) {
    final hints = metadata['_delivery_refs'];
    final hint = hints is Map<String, MediaTagRef> ? hints[ref.path] : null;
    if (ref.suggestedFilename != null || hint?.suggestedFilename == null) {
      return ref;
    }
    return MediaTagRef(
      path: ref.path,
      quoted: ref.quoted,
      suggestedFilename: hint!.suggestedFilename,
    );
  }

  void _openDeliveredLink(
    BuildContext context,
    String? href, {
    InlineMediaPreviewOwner? previewOwner,
  }) {
    final filesClient = !isUser ? mediaFilesClient : null;
    final path = href == null ? null : deliveredFilePathFromHref(href);
    if (filesClient == null || path == null || !context.mounted) return;
    final eligible = extractDeliveredFileRefs(
      content,
      isFinal: mediaReferencesFinal,
    ).any((ref) => ref.path == path);
    if (!eligible) return;
    unawaited(
      openMediaFilePreview(
        context: context,
        filesClient: filesClient,
        ref: _deliveryRef(MediaTagRef(path: path)),
        sourceIdentity: mediaSourceIdentity,
        owner: previewOwner,
      ).catchError((Object error) {
        debugPrint('media preview failed: $error');
      }),
    );
  }

  MarkdownStyleSheet _messageStyleSheet(
    ThemeData theme,
    HermesTokens tokens, {
    required bool isUser,
    required Color assistantTextColor,
  }) {
    final foreground = isUser ? tokens.onAccent : assistantTextColor;
    final body = theme.textTheme.bodyMedium?.copyWith(color: foreground);
    final rule = isUser ? tokens.onAccent : tokens.border;
    return MarkdownStyleSheet(
      p: body,
      code: tokens.typography.mono.copyWith(
        backgroundColor: tokens.accentContainer,
        color: tokens.onAccentContainer,
      ),
      a: TextStyle(
        color: isUser ? tokens.onAccent : tokens.accent,
        decoration: TextDecoration.underline,
        decorationColor: isUser ? tokens.onAccent : tokens.accent,
      ),
      h1: theme.textTheme.headlineSmall?.copyWith(color: foreground),
      h2: theme.textTheme.titleLarge?.copyWith(color: foreground),
      h3: theme.textTheme.titleMedium?.copyWith(color: foreground),
      h4: theme.textTheme.titleSmall?.copyWith(color: foreground),
      h5: body?.copyWith(fontWeight: FontWeight.bold),
      h6: body?.copyWith(fontWeight: FontWeight.bold),
      blockquote: body?.copyWith(fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: rule, width: 3)),
      ),
      em: body?.copyWith(fontStyle: FontStyle.italic),
      strong: body?.copyWith(fontWeight: FontWeight.bold),
      del: body?.copyWith(decoration: TextDecoration.lineThrough),
      listBullet: body,
      checkbox: body,
      tableHead: body?.copyWith(fontWeight: FontWeight.bold),
      tableBody: body,
      tableBorder: TableBorder.all(color: rule),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: rule)),
      ),
      codeblockDecoration: BoxDecoration(color: tokens.accentContainer),
    );
  }

  /// Splits assistant text on `MEDIA:` refs (when a files client is
  /// available) and renders each piece: prose through the markdown/code-block
  /// pipeline, standalone-line refs as download cards. Code fences are split
  /// out FIRST and stay verbatim — a `MEDIA:` example inside a code block is
  /// documentation, not a delivery. Mid-line refs stay in the prose as
  /// markdown links so they never fragment a list item or table row.
  List<Widget> _renderContent(
    BuildContext context,

    HermesTokens tokens,
    bool isUser,
    Color assistantTextColor,
  ) {
    final styleSheet = _messageStyleSheet(
      Theme.of(context),
      tokens,
      isUser: isUser,
      assistantTextColor: assistantTextColor,
    );
    final filesClient = !isUser ? mediaFilesClient : null;
    final mediaPaths = filesClient == null
        ? const <String>{}
        : {
            for (final ref in extractMediaTagRefs(
              content,
              isFinal: mediaReferencesFinal,
            ))
              ref.path,
          };
    final markdownRefs = <String, MediaTagRef>{};
    if (filesClient != null) {
      for (final ref in extractMarkdownFileRefs(
        content,
        isFinal: mediaReferencesFinal,
      )) {
        if (!mediaPaths.contains(ref.path)) {
          markdownRefs.putIfAbsent(ref.path, () => ref);
        }
      }
    }
    Widget prose(String text) => MarkdownBody(
      data: text,
      selectable: false,
      styleSheet: styleSheet,
      // Local images become lazy file cards below. Never let Markdown load a
      // host path from the phone or contact an arbitrary image URL on render.
      sizedImageBuilder: (image) => Text(image.alt ?? image.title ?? ''),
      onTapLink: (_, href, _) => unawaited(_openLink(context, href)),
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
              key: ValueKey((mediaSourceIdentity, path, occurrence)),
              ref: _deliveryRef(segment.media!),
              filesClient: filesClient,
              sourceIdentity: mediaSourceIdentity,
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
      if (filesClient != null)
        for (final ref in markdownRefs.values)
          MediaArtifactCard(
            key: ValueKey((mediaSourceIdentity, 'file-link', ref.path)),
            ref: _deliveryRef(ref),
            filesClient: filesClient,
            sourceIdentity: mediaSourceIdentity,
          ),
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
  Widget build(BuildContext context) => InlineMediaPreviewScope(
    filesClient: isUser ? null : mediaFilesClient,
    sourceIdentity: mediaSourceIdentity,
    references: isUser || mediaFilesClient == null
        ? const []
        : extractDeliveredFileRefs(
            content,
            isFinal: mediaReferencesFinal,
          ).map(_deliveryRef).toList(growable: false),
    builder: _buildBubble,
  );

  Widget _buildBubble(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = HermesTokens.of(context);
    final userBubbleColor = tokens.accent;
    final assistantBubbleColor = tokens.raised;
    final assistantTextColor = tokens.onSurface;
    final messageTime =
        (isUser || isCompletedChatResponse(metadata)) &&
            metadata['_message_time_continuation'] != true
        ? ChatMessageTime.fromRow(metadata)
        : null;
    final localTime = messageTime?.at.toLocal();
    final clockTime = localTime == null
        ? null
        : MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(localTime),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          );
    final fullTime = localTime == null
        ? null
        : '${MaterialLocalizations.of(context).formatFullDate(localTime)} · $clockTime';

    // Collect extra metadata for verbose mode
    final List<String> metaLines = [];
    if (verbose) {
      final role = (metadata['role'] as String?) ?? 'unknown';
      metaLines.add('role: $role');
      // Show any extra fields that aren't role/content
      for (final entry in metadata.entries) {
        if (entry.key == 'role' ||
            entry.key == 'content' ||
            entry.key == '_delivery_refs') {
          continue;
        }
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
                    color: isUser ? tokens.onAccent : tokens.muted,
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
                  color: isUser ? tokens.accentContainer : tokens.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: ExpansionTile(
                    key: const ValueKey('message-metadata'),
                    title: Text(context.l10n.message_metadata),
                    dense: true,
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: metadataExpanded,
                    onExpansionChanged: onMetadataExpansionChanged,
                    children: metaLines
                        .map(
                          (line) => Text(
                            line,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: isUser
                                  ? tokens.onAccentContainer
                                  : tokens.onSurface,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
            // Message content: assistant `MEDIA:` refs become file cards;
            // prose renders as markdown and fenced code blocks render with
            // language, copy, and wrap controls. User bubbles never parse
            // MEDIA: — the contract is assistant-side delivery, and quoted
            // tags in a prompt must stay verbatim.
            ..._renderContent(context, tokens, isUser, assistantTextColor),
            if (messageTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Tooltip(
                  message: switch (messageTime.source) {
                    ChatMessageTimeSource.recorded =>
                      context.l10n.message_time_recorded(fullTime!),
                    ChatMessageTimeSource.sent =>
                      context.l10n.message_time_sent(fullTime!),
                    ChatMessageTimeSource.received =>
                      context.l10n.message_time_received(fullTime!),
                  },
                  child: Text(
                    clockTime!,
                    key: const Key('message-timestamp'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isUser ? tokens.onAccent : tokens.muted,
                    ),
                  ),
                ),
              ),
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
