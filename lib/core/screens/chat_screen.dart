// Chat screen with real-time streaming via REST API.
// Uses REST endpoints: POST /api/sessions/{id}/chat and
// GET /api/sessions/{id}/messages.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import '../controllers/voice_composer_controller.dart';
import '../services/connection_manager.dart';
import '../services/attachment_draft_service.dart';
import '../services/chat_model_override_store.dart';
import '../services/desktop_gateway_client.dart';
import '../services/gateway_turn_application_controller.dart';
import '../services/gateway_turn_coordinator.dart';
import '../services/gateway_turn_recovery.dart';
import '../services/gateway_turn_ui_projection.dart';
import '../services/turn_notification_service.dart';
import '../services/voice_composer_adapter.dart';
import '../services/ws_client.dart';
import '../models/attachment_draft.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_approval.dart';
import '../models/gateway_clarify.dart';
import '../models/gateway_insight.dart';
import '../models/gateway_sensitive_prompt.dart';
import '../models/gateway_turn_contract.dart';
import '../utils/chat_history_scroll.dart';
import '../utils/message_content.dart';
import '../utils/responsive.dart';
import '../widgets/gateway_activity_card.dart';
import '../widgets/attachment_draft_tile.dart';
import '../widgets/chat_end_affordance.dart';
import '../widgets/gateway_approval_dialog.dart';
import '../widgets/gateway_clarify_dialog.dart';
import '../widgets/gateway_insight_card.dart';
import '../widgets/gateway_sensitive_prompt_dialog.dart';
import '../widgets/voice_composer_controls.dart';

/// These colors remain identical in light and dark themes. Their 8.15:1
/// contrast ratio keeps normal user-message text above WCAG AA.
const hermesUserMessageBubbleBackground = Color(0xFFD4AF37);
const hermesUserMessageForeground = Color(0xFF1C1B1F);

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

const _reasoningEffortLabels = <String, String>{
  'none': 'Off (no thinking)',
  'minimal': 'Minimal',
  'low': 'Low',
  'medium': 'Medium',
  'high': 'High',
  'xhigh': 'Extra High',
  'max': 'Max',
  'ultra': 'Ultra',
};

class _GatewayReasoningDisplay {
  final String text;
  final bool initiallyExpanded;

  const _GatewayReasoningDisplay(this.text, this.initiallyExpanded);
}

enum _ResponseTransport { none, rest, desktop }

const _legacyTransportNotice =
    'Background recovery unavailable — legacy transport';

@visibleForTesting
typedef TestRemotePromptSubmit =
    Future<void> Function({
      required String sessionId,
      required String text,
      required StreamCallback onEvent,
    });

@visibleForTesting
typedef TestRemoteAttachmentUpload =
    Future<AttachmentUploadReceipt> Function({
      required AttachmentDraft draft,
      required String dataUrl,
    });

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
  final TestRemoteAttachmentUpload? testRemoteAttachmentUpload;

  @visibleForTesting
  final List<AttachmentDraft> testInitialAttachmentDrafts;

  @visibleForTesting
  final VoiceComposerAdapter? testVoiceComposerAdapter;

  const ChatScreen({
    required this.connection,
    required this.session,
    this.turnApplicationController,
    this.testTurnApplicationSession,
    this.testApiClient,
    this.testAttachmentDraftService,
    this.testRemotePromptSubmit,
    this.testRemoteAttachmentUpload,
    this.testInitialAttachmentDrafts = const [],
    this.testVoiceComposerAdapter,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _messages = [];
  final List<GatewayToolActivity> _toolActivities = [];
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
  DesktopConnectionState _desktopConnectionState =
      DesktopConnectionState.disconnected;
  bool _appInBackground = false;

  // Chat sending state
  final _textController = TextEditingController();
  final _imagePicker = ImagePicker();
  final List<AttachmentDraft> _attachmentDrafts = [];
  String? _sessionModel;
  String? _sessionProvider;
  String? _sessionReasoningEffort;
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
  bool _legacyResumeSyncPending = false;
  bool _legacyResumeSyncInFlight = false;
  int _responseGeneration = 0;
  bool _approvalDialogOpen = false;
  final List<_PendingSensitivePrompt> _sensitivePromptQueue = [];
  final Set<String> _expiredSensitivePromptIds = {};
  _PendingSensitivePrompt? _activeSensitivePrompt;
  bool _sensitivePromptRouteOpen = false;
  final List<_PendingClarifyPrompt> _clarifyPromptQueue = [];
  _PendingClarifyPrompt? _activeClarifyPrompt;

  // Voice input / spoken replies
  final FlutterTts _flutterTts = FlutterTts();
  late final VoiceComposerController _voiceComposer;
  bool _voiceReplyEnabled = true;
  bool _awaitingVoiceReply = false;
  String? _voiceStatus;
  String? _sttLocaleId;

  // Verbose mode
  bool _verboseMode = false;

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
    _turnNotifications = TurnNotificationService();
    unawaited(_turnNotifications.ensureInitialized());
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
    _attachmentDrafts.addAll(widget.testInitialAttachmentDrafts);
    _gatewayNotices = List<GatewayNotice>.from(
      _savedGatewayNotices[_gatewayNoticeIdentity] ?? const [],
    );
    _chatModelStore = ChatModelOverrideStore.open();
    _sessionModelRestore = _restoreSessionModelOverride();
    if (widget.connection.desktopGatewayUrl?.trim().isNotEmpty == true) {
      try {
        _desktopGateway = DesktopGatewayClient.fromConnection(
          widget.connection,
        );
        _desktopGateway!.setAsyncEventListener(_handleDesktopAsyncEvent);
        _desktopGateway!.setConnectionListener((state) {
          if (mounted) setState(() => _desktopConnectionState = state);
        });
        unawaited(_ensureDesktopSession());
      } on ArgumentError {
        // The regular mobile chat remains usable; selection surfaces the
        // actionable configuration error when Desktop attachments are needed.
        _desktopGateway = null;
      }
    }
    _turnApplicationSession =
        widget.testTurnApplicationSession ??
        (_desktopGateway != null
            ? widget.turnApplicationController?.sessionFor(widget.connection)
            : null);
    _turnApplicationSession?.onTurnSettled = _onTurnSettled;
    unawaited(_initializeChat());
    _loadVerboseMode();
    _initVoice();
    _recoverLostImage();
    _scrollController.addListener(_onScroll);
  }

  String get _chatModelConnectionIdentity =>
      '${widget.connection.baseUrl}|'
      '${widget.connection.gatewayPrefix ?? ''}|'
      '${widget.connection.desktopGatewayUrl ?? ''}';

  String get _gatewayNoticeIdentity =>
      '$_chatModelConnectionIdentity|${widget.session.id}';

  Future<void> _restoreSessionModelOverride() async {
    final store = await _chatModelStore;
    final override = store.read(
      connectionIdentity: _chatModelConnectionIdentity,
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    _client.close();
    unawaited(
      _attachmentDraftService.removeAll(
        List<AttachmentDraft>.from(_attachmentDrafts),
      ),
    );
    _desktopGateway?.setAsyncEventListener(null);
    _desktopGateway?.close();
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _appInBackground = true;
      if (_legacyTransportFallback && (_sending || _streaming)) {
        _legacyResumeSyncPending = true;
      }
    } else if (state == AppLifecycleState.resumed) {
      _appInBackground = false;
      unawaited(_turnNotifications.cancelAll());
      if (_desktopGateway != null) unawaited(_ensureDesktopSession());
      if (_turnApplicationSession != null && !_legacyTransportFallback) {
        unawaited(_recoverPendingTurn());
      }
      _scheduleLegacyResumeSyncIfIdle();
    }
  }

  void _scheduleLegacyResumeSyncIfIdle() {
    if (!mounted ||
        !_legacyTransportFallback ||
        !_legacyResumeSyncPending ||
        _legacyResumeSyncInFlight ||
        _appInBackground ||
        _sending ||
        _streaming) {
      return;
    }
    _legacyResumeSyncPending = false;
    unawaited(_resyncLegacyMessages());
  }

  Future<void> _resyncLegacyMessages() async {
    _legacyResumeSyncInFlight = true;
    try {
      final messages = await _client.getMessages(widget.session.id);
      if (!mounted) return;
      _extractToolMessages(messages);
      setState(() {
        _messages = messages;
        _error = null;
      });
      _scheduleInitialEndAlignment();
    } catch (_) {
      // Keep the usable local chat when a resume-time refresh is transiently
      // unavailable. A later legacy turn can schedule another refresh.
    } finally {
      _legacyResumeSyncInFlight = false;
      _scheduleLegacyResumeSyncIfIdle();
    }
  }

  Future<void> _initializeChat() async {
    await _fetchMessages();
    if (!mounted) return;
    await _recoverPendingTurn(allowLegacyFallback: true);
  }

  Future<void> _ensureDesktopSession() async {
    final gateway = _desktopGateway;
    if (gateway == null) return;
    try {
      await gateway.ensureSession(widget.session.id);
    } catch (_) {
      // The composer remains available. The next send retries with a fresh
      // single-use ticket and surfaces an actionable error if it still fails.
    }
  }

  void _editAndResend(String text) {
    _textController
      ..text = text
      ..selection = TextSelection.collapsed(offset: text.length);
    FocusScope.of(context).nextFocus();
  }

  Future<void> _retryPrompt(String text) async {
    if (_sending || _streaming || text.trim().isEmpty) return;
    _editAndResend(text);
    await _sendMessage();
  }

  Future<void> _exportConversation() async {
    final buffer = StringBuffer('# ${widget.session.title}\n\n');
    for (final message in _messages) {
      final role = message['role']?.toString();
      if (role != 'user' && role != 'assistant') continue;
      final content = stripToolResultText(
        messageContentToText(message['content']),
      ).trim();
      if (content.isEmpty) continue;
      buffer
        ..writeln(role == 'user' ? '## You' : '## Hermes')
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
      setState(() => _voiceStatus = 'Voice setup failed: $e');
    }
  }

  Future<void> _startVoiceInput() async {
    if (_streaming || _sending || _loading) return;
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
                'Speech recognition is unavailable',
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
          const SnackBar(
            content: Text('Reading response aloud'),
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
          const SnackBar(
            content: Text('Read aloud is unavailable on this device'),
            duration: Duration(seconds: 3),
          ),
        );
    }
  }

  void _onTurnSettled(GatewayTurnRecoveryState state) {
    if (!mounted || !_appInBackground) return;
    final turnId = state.turnId ?? state.clientTurnId;
    final summary = state.isTerminal && !state.isFailClosed
        ? 'Response ready'
        : 'Turn completed';
    unawaited(
      _turnNotifications.showTurnCompleted(
        turnSummary: '${widget.session.title}: $summary',
        turnId: turnId,
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

  Future<void> _fetchMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final messages = await _client.getMessages(widget.session.id);
      if (!mounted) return;
      _extractToolMessages(messages);
      setState(() {
        _messages = messages;
        _loading = false;
      });
      _scheduleInitialEndAlignment();
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      if (errStr.contains('404') || errStr.contains('not found')) {
        setState(() {
          _messages = [];
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

  Future<void> _recoverPendingTurn({bool allowLegacyFallback = false}) async {
    final turnSession = _turnApplicationSession;
    if (turnSession == null || _recoveringTurn || _legacyTransportFallback) {
      return;
    }
    _recoveringTurn = true;
    if (mounted && !_streaming) {
      setState(() {
        _sending = true;
        _gatewayTurnStatus = const GatewayTurnStatus(
          kind: 'recovery',
          text: 'Recovering Hermes…',
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
      if (allowLegacyFallback &&
          error is GatewayTurnCoordinatorException &&
          error.failure ==
              GatewayTurnCoordinatorFailure.unsupportedCapability) {
        setState(() {
          _legacyTransportFallback = true;
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
          text: 'Hermes recovery is unavailable: $error',
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
            ? const GatewayTurnStatus(
                kind: 'recovery_failed',
                text: 'Hermes stopped recovery safely. No prompt was resent.',
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
      GatewayRecoveryTurnStatus.waitingInput => 'Hermes is waiting for input…',
      GatewayRecoveryTurnStatus.running => 'Hermes is responding…',
      _ => 'Recovering Hermes…',
    };
  }

  void _extractToolMessages(List<Map<String, dynamic>> messages) {
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
        GatewayToolActivity(
          toolId: toolCallId.isEmpty ? null : toolCallId,
          name: toolName,
          phase: GatewayToolActivityPhase.completed,
        ),
      );
    }
  }

  Future<void> _showAttachmentPicker() async {
    if (_loading || _streaming || _sending) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                _desktopGateway == null ? 'Choose image' : 'Choose images',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickGalleryImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCameraImage();
              },
            ),
            if (_desktopGateway != null)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Choose files'),
                subtitle: const Text(
                  'Documents, archives, audio, video, or data',
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
      _showAttachmentError('Unable to prepare this image. Try another one.');
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
      _showAttachmentError('Unable to prepare this image. Try another one.');
    }
  }

  Future<void> _recoverLostImage() async {
    final response = await _imagePicker.retrieveLostData();
    if (response.isEmpty) return;

    final files = response.files;
    if (files == null || files.isEmpty) {
      _showAttachmentError('Image selection was interrupted. Try again.');
      return;
    }

    await _preparePickedImages(_desktopGateway == null ? [files.first] : files);
  }

  Future<void> _preparePickedImages(List<XFile> images) async {
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
        errors.add('Unable to prepare ${image.name}.');
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
        'Configure a valid Desktop Gateway URL before attaching files.',
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
        _showAttachmentError(
          'You can attach up to $maxRemoteAttachmentDrafts items.',
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
          '${files.length - prepared.length} file(s) skipped: limit, size, unreadable, or sensitive filename.',
        );
      }
    } catch (_) {
      _showAttachmentError('Unable to prepare this file. Try another one.');
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
    if (desktopGateway == null || _sending || _streaming) return;
    setState(() {
      _sending = true;
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'upload',
        text: 'Retrying ${draft.name}…',
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
          const SnackBar(
            content: Text(
              'File attached; document catalog registration is pending.',
            ),
          ),
        );
      }
    } catch (error) {
      _showAttachmentError(
        'Retry failed for ${draft.name}. The draft and prompt were kept.',
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
    final desktopGateway = _desktopGateway;
    if (desktopGateway == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configure Desktop Gateway URL and Dashboard credentials to choose a chat model.',
          ),
        ),
      );
      return;
    }

    setState(() => _loadingModelOptions = true);
    try {
      final results = await Future.wait([
        desktopGateway.getModelInfo(),
        desktopGateway.getModelOptions(),
      ]);
      if (!mounted) return;
      final modelInfo = results[0];
      final choices = _parseModelChoices(results[1]);
      if (choices.isEmpty) {
        throw StateError(
          'The active profile did not return any selectable models.',
        );
      }

      var currentEffort =
          _sessionReasoningEffort ??
          WsClient.normalizeReasoningEffort(modelInfo['reasoning_effort']);
      try {
        currentEffort = await desktopGateway.getSessionReasoning(
          widget.session.id,
        );
      } catch (_) {
        // Older gateways may not expose session-scoped config.get. The model
        // selector remains usable with the profile/default effort.
      }
      if (!mounted) return;

      var selectedChoice = choices.firstWhere(
        (choice) =>
            choice.model == (_sessionModel ?? widget.session.model) &&
            (_sessionProvider == null || choice.provider == _sessionProvider),
        orElse: () => choices.first,
      );
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
                    title: const Text('Model and thinking for this chat'),
                    subtitle: Text(
                      'Profile default: ${modelInfo['model'] ?? 'unknown'}'
                      '${modelInfo['provider'] == null ? '' : ' • ${modelInfo['provider']}'}',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Thinking effort',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedEffort,
                          items: _reasoningEffortLabels.entries
                              .map(
                                (entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
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
                            choice.model == selectedChoice.model &&
                            choice.provider == selectedChoice.provider;
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
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            _ModelSelection(
                              choice: selectedChoice,
                              reasoningEffort: selectedEffort,
                            ),
                          ),
                          child: const Text('Apply to this chat'),
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
      if (selection != null && mounted) {
        await _setSessionModel(selection);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load models for this profile: $error'),
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

  Future<void> _setSessionModel(_ModelSelection selection) async {
    final desktopGateway = _desktopGateway;
    if (desktopGateway == null || _changingModel) return;
    final choice = selection.choice;
    setState(() => _changingModel = true);
    try {
      await desktopGateway.setSessionModel(
        sessionId: widget.session.id,
        provider: choice.provider,
        model: choice.model,
      );
      await desktopGateway.setSessionReasoning(
        sessionId: widget.session.id,
        effort: selection.reasoningEffort,
      );
      final store = await _chatModelStore;
      await store.save(
        connectionIdentity: _chatModelConnectionIdentity,
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
            '${choice.model} • ${_reasoningEffortLabels[selection.reasoningEffort]} '
            'now apply only to this chat.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model was not changed: $error')));
    } finally {
      if (mounted) setState(() => _changingModel = false);
    }
  }

  /// Send message via SSE streaming (Gateway API Server).
  Future<void> _sendMessage({bool speakResponse = false}) async {
    if (_voiceComposer.listening) return;
    final text = _textController.text.trim();
    final attachments = List<AttachmentDraft>.from(_attachmentDrafts);
    if (text.isEmpty && attachments.isEmpty) return;
    if (_sending || _streaming) return;
    await _sessionModelRestore;
    if (!mounted) return;

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
        _showAttachmentError(
          'Unable to read the selected image. The selection was kept.',
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

    _textController.text = '';
    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;
    final responseGeneration = ++_responseGeneration;
    _activeResponseTransport = _ResponseTransport.rest;

    // The server returns oldest-to-newest history. Preserve that order; the
    // gateway client appends the current prompt exactly once.
    final history = buildRestChatHistory(_messages);
    _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());

    setState(() {
      _sending = true;
      _streaming = true;
      _gatewayTurnStatus = const GatewayTurnStatus(
        kind: 'starting',
        text: 'Starting Hermes…',
      );
      _messages.add({'role': 'user', 'content': localContent});
      // Insert a placeholder streaming message
      _messages.add({'role': 'assistant', 'content': ''});
    });

    _scheduleStreamingFollow();

    // Accumulate tokens into the streaming placeholder
    await _gateway.sendMessageStreaming(
      message: text,
      sessionId: widget.session.id,
      history: history,
      imageDataUrl: imageDataUrl,
      onToken: (token) {
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
        if (!mounted || responseGeneration != _responseGeneration) return;
        _upsertToolProgress(progress);
      },
      onDone: () async {
        if (!mounted || responseGeneration != _responseGeneration) return;
        // Refresh messages to get the final server-side state
        try {
          final messages = await _client.getMessages(widget.session.id);
          if (!mounted || responseGeneration != _responseGeneration) return;
          _extractToolMessages(messages);
          if (pendingImage != null) {
            await _attachmentDraftService.removeCachedFile(pendingImage);
          }
          if (!mounted || responseGeneration != _responseGeneration) return;
          setState(() {
            _messages = messages;
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
        } catch (e) {
          if (!mounted || responseGeneration != _responseGeneration) return;
          _scrollCoordinator.cancelStreaming();
          setState(() {
            _streaming = false;
            _sending = false;
            _gatewayTurnStatus = null;
            _activeResponseTransport = _ResponseTransport.none;
          });
        }
      },
      onError: (error) {
        if (!mounted || responseGeneration != _responseGeneration) return;
        // Remove the placeholder assistant message
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.removeLast();
          }
        });
        _handleSendError(error, removePendingUserMessage: true);
      },
    );
  }

  Future<void> _sendDesktopGatewayMessage({
    required String text,
    required List<AttachmentDraft> attachments,
    required bool speakResponse,
  }) async {
    final desktopGateway = _desktopGateway;
    final testRemotePromptSubmit = widget.testRemotePromptSubmit;
    if (desktopGateway == null && testRemotePromptSubmit == null) {
      _showAttachmentError(
        'Desktop Gateway is not configured for this connection.',
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
    _activeResponseTransport = _ResponseTransport.desktop;
    var turnAdded = false;

    setState(() {
      _sending = true;
      _gatewayTurnStatus = const GatewayTurnStatus(
        kind: 'upload',
        text: 'Preparing attachments…',
      );
    });

    try {
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
                text:
                    'Uploading ${index + 1}/${attachments.length}: ${draft.name}',
              );
            }
          });
        },
        submitPrompt: (refTexts) async {
          if (!mounted || responseGeneration != _responseGeneration) return;
          if (attachments.any((draft) => draft.atlasIntakeAccepted == false)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'File attached; document catalog registration is pending.',
                ),
              ),
            );
          }
          final prompt = [
            text,
            refTexts.join('\n'),
          ].where((part) => part.trim().isNotEmpty).join('\n\n');
          final attachmentLabels = attachments
              .map((attachment) => '[Attached file: ${attachment.name}]')
              .join('\n');
          final localContent = [
            text,
            attachmentLabels,
          ].where((part) => part.trim().isNotEmpty).join('\n\n');
          _textController.clear();
          _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());
          setState(() {
            _streaming = true;
            _gatewayTurnStatus = const GatewayTurnStatus(
              kind: 'starting',
              text: 'Starting Hermes…',
            );
            _attachmentDrafts.clear();
            _messages.add({'role': 'user', 'content': localContent});
            _messages.add({'role': 'assistant', 'content': ''});
            turnAdded = true;
          });
          _scheduleStreamingFollow();
          void onEvent(StreamEvent event) {
            _handleDesktopGatewayEvent(event, responseGeneration);
          }

          if (testRemotePromptSubmit != null) {
            await testRemotePromptSubmit(
              sessionId: widget.session.id,
              text: prompt,
              onEvent: onEvent,
            );
          } else {
            await desktopGateway!.submitPrompt(
              sessionId: widget.session.id,
              text: prompt,
              onEvent: onEvent,
            );
          }
        },
      );
      if (!mounted || responseGeneration != _responseGeneration) return;
      setState(() {
        _streaming = false;
        _sending = false;
        _gatewayTurnStatus = null;
        _activeResponseTransport = _ResponseTransport.none;
      });
      _scheduleLegacyResumeSyncIfIdle();
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
      if (turnAdded) {
        setState(() {
          if (_messages.isNotEmpty &&
              _messages.last['role'] == 'assistant' &&
              (_messages.last['content']?.toString().isEmpty ?? true)) {
            _messages.removeLast();
          }
          if (_messages.isNotEmpty && _messages.last['role'] == 'user') {
            _messages.removeLast();
          }
          _textController.text = text;
          _attachmentDrafts
            ..clear()
            ..addAll(attachments);
        });
      }
      _handleSendError(error);
    }
  }

  Future<void> _sendRecoverableGatewayMessage({
    required String text,
    required List<AttachmentDraft> attachments,
    required bool speakResponse,
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
      unawaited(_attachmentDraftService.removeAll(attachments));
    }

    void onState(GatewayTurnRecoveryState state) {
      releaseAcceptedAttachmentCache(state);
      if (!mounted || responseGeneration != _responseGeneration) return;
      _applyGatewayTurnState(state);
    }

    setState(() {
      _sending = true;
      _gatewayTurnStatus = const GatewayTurnStatus(
        kind: 'upload',
        text: 'Preparing attachments…',
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
            text: 'Uploading ${index + 1}/${attachments.length}: ${draft.name}',
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
      return;
    }

    final attachmentLabels = attachments
        .map((attachment) => '[Attached file: ${attachment.name}]')
        .join('\n');
    final localContent = [
      text,
      attachmentLabels,
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    _textController.clear();
    _scrollCoordinator.beginStreaming(isNearEnd: _isNearEnd());
    setState(() {
      _streaming = true;
      _gatewayTurnStatus = const GatewayTurnStatus(
        kind: 'starting',
        text: 'Starting Hermes…',
      );
      _attachmentDrafts.clear();
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
          _textController.text = text;
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
        return;
      }
      setState(() {
        _gatewayTurnStatus = const GatewayTurnStatus(
          kind: 'recovery',
          text: 'Delivery is uncertain; recovering without resending…',
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
    if (event.type == 'sudo.request' || event.type == 'secret.request') {
      _queueSensitivePrompt(event, responseGeneration);
      return;
    }
    if (event.type == 'sudo.expire' || event.type == 'secret.expire') {
      _expireSensitivePrompt(event);
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
          _messages.add({'role': 'assistant', 'content': ''});
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
      if (completeText.isNotEmpty) {
        setState(() {
          final assistant = _lastAssistantMessage();
          if (assistant != null) {
            final current = assistant['content']?.toString() ?? '';
            if (current.isEmpty) _registerMaterializedAssistantMessage();
            assistant['content'] = completeText;
          }
        });
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

  Map<String, dynamic>? _lastAssistantMessage() {
    for (var index = _messages.length - 1; index >= 0; index--) {
      if (_messages[index]['role'] == 'assistant') return _messages[index];
    }
    return null;
  }

  void _handleDesktopAsyncEvent(String mobileSessionId, StreamEvent event) {
    if (!mounted || mobileSessionId != widget.session.id) return;
    if (event.type == 'notification.show') {
      final notification = GatewayNotification.fromEventData(event.data);
      if (notification == null) return;
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
    setState(() {
      _gatewayNotices.add(notice);
      if (_gatewayNotices.length > 20) _gatewayNotices.removeAt(0);
      _savedGatewayNotices[_gatewayNoticeIdentity] = List.unmodifiable(
        _gatewayNotices,
      );
    });
    _scheduleStreamingFollow();
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
          text: 'Delegated task: ${update.goal}',
        );
      }
    });
    _scheduleStreamingFollow();
  }

  void _showGatewayApproval(
    Map<String, dynamic> eventData,
    int responseGeneration,
  ) {
    if (_approvalDialogOpen) return;
    final request = GatewayApprovalRequest.fromEventData(eventData);
    _approvalDialogOpen = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || responseGeneration != _responseGeneration) {
        _approvalDialogOpen = false;
        return;
      }
      final desktopGateway = _desktopGateway;
      if (desktopGateway == null) {
        _approvalDialogOpen = false;
        return;
      }

      final responded = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => GatewayApprovalDialog(
          request: request,
          onRespond: (choice) => desktopGateway.respondToApproval(
            sessionId: widget.session.id,
            choice: choice.wireValue,
          ),
        ),
      );
      _approvalDialogOpen = false;
      _drainClarifyPromptQueue();
      _drainSensitivePromptQueue();

      // System Back is treated as a denial. This prevents a dismissed mobile
      // dialog from leaving the gateway turn blocked indefinitely.
      if (responded != true &&
          mounted &&
          responseGeneration == _responseGeneration) {
        try {
          await desktopGateway.respondToApproval(
            sessionId: widget.session.id,
            choice: GatewayApprovalChoice.deny.wireValue,
          );
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not deny the command: $error'),
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
            GatewaySensitivePromptKind.sudo => desktopGateway.respondToSudo(
              requestId: pending.request.requestId,
              password: value,
            ),
            GatewaySensitivePromptKind.secret => desktopGateway.respondToSecret(
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
              await desktopGateway.respondToSudo(
                requestId: pending.request.requestId,
                password: '',
              );
              break;
            case GatewaySensitivePromptKind.secret:
              await desktopGateway.respondToSecret(
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

  void _queueClarifyPrompt(
    Map<String, dynamic> eventData,
    int responseGeneration,
  ) {
    final request = GatewayClarifyRequest.fromEventData(eventData);
    if (request == null) return;
    final duplicate =
        _activeClarifyPrompt?.request.requestId == request.requestId ||
        _clarifyPromptQueue.any(
          (pending) => pending.request.requestId == request.requestId,
        );
    if (duplicate) return;

    _clarifyPromptQueue.add(_PendingClarifyPrompt(request, responseGeneration));
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          pending.responseGeneration != _responseGeneration ||
          _activeClarifyPrompt?.request.requestId !=
              pending.request.requestId) {
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

      final responded = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => GatewayClarifyDialog(
          request: pending.request,
          onRespond: (answer) => desktopGateway.respondToClarify(
            requestId: pending.request.requestId,
            answer: answer,
          ),
        ),
      );
      if (_activeClarifyPrompt?.request.requestId ==
          pending.request.requestId) {
        _activeClarifyPrompt = null;
      }

      // System Back or a barrier dismiss maps to the official empty answer,
      // matching Hermes Desktop's Skip behavior.
      if (responded != true &&
          mounted &&
          pending.responseGeneration == _responseGeneration) {
        try {
          await desktopGateway.respondToClarify(
            requestId: pending.request.requestId,
            answer: '',
          );
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not skip the Hermes question.'),
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
      final interrupted = switch (transport) {
        _ResponseTransport.rest => await _gateway.cancelActiveMessage(),
        _ResponseTransport.desktop =>
          _turnApplicationSession != null && activeClientTurnId != null
              ? (await _turnApplicationSession!.interrupt(
                      localSessionId: widget.session.id,
                      clientTurnId: activeClientTurnId,
                    )).status?.isTerminal ==
                    true
              : await _desktopGateway?.interruptPrompt(
                      sessionId: widget.session.id,
                    ) ??
                    false,
        _ResponseTransport.none => false,
      };
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            interrupted
                ? 'Response stopped.'
                : 'Response closed locally; no active gateway turn was found.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Response closed locally; gateway stop failed: $error'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
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
          content: Text('Send failed: $e'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
    _scheduleLegacyResumeSyncIfIdle();
  }

  void _upsertToolProgress(
    Map<String, dynamic> progress, {
    String eventType = 'tool.start',
  }) {
    final update = GatewayToolActivity.fromGatewayEvent(eventType, progress);
    if (update == null) return;
    setState(() {
      var idx = update.toolId == null
          ? -1
          : _toolActivities.indexWhere(
              (activity) => activity.toolId == update.toolId,
            );
      if (idx < 0) {
        idx = _toolActivities.lastIndexWhere(
          (activity) =>
              !activity.isTerminal &&
              activity.name.toLowerCase() == update.name.toLowerCase(),
        );
      }
      if (idx >= 0) {
        _toolActivities[idx] = _toolActivities[idx].merge(update);
      } else {
        _toolActivities.add(update);
      }
      _gatewayTurnStatus = GatewayTurnStatus(
        kind: 'tool',
        text: update.isTerminal
            ? '${update.displayName}: ${update.statusLabel.toLowerCase()}'
            : 'Using ${update.displayName}…',
      );
    });

    _scheduleStreamingFollow();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _desktopGateway == null
                        ? (_loading
                              ? Colors.orange
                              : _error == null
                              ? Colors.green
                              : Theme.of(context).colorScheme.error)
                        : switch (_desktopConnectionState) {
                            DesktopConnectionState.connected => Colors.green,
                            DesktopConnectionState.connecting ||
                            DesktopConnectionState.reconnecting =>
                              Colors.orange,
                            DesktopConnectionState.disconnected => Theme.of(
                              context,
                            ).colorScheme.error,
                          },
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${widget.connection.label} • ${_desktopGateway == null ? (_loading
                              ? 'connecting'
                              : _error == null
                              ? 'connected'
                              : 'offline') : _desktopConnectionState.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_streaming)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Responding…', style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Chat actions',
              onSelected: (action) {
                if (action == 'refresh') _fetchMessages();
                if (action == 'export') _exportConversation();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('Refresh'),
                  ),
                ),
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.ios_share_outlined),
                    title: Text('Export / share'),
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
                    _legacyTransportNotice,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
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
              _buildInputBar(),
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
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      key: const Key('chat-input-bar'),
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
            if (_gatewayTurnStatus != null && (_sending || _streaming))
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(4, 2, 4, 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.8),
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
                  label: 'Choose chat model',
                  value: _sessionModel ?? widget.session.model,
                  button: true,
                  enabled:
                      !(_sending ||
                          _streaming ||
                          _loadingModelOptions ||
                          _changingModel),
                  excludeSemantics: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: TextButton.icon(
                      onPressed:
                          (_sending ||
                              _streaming ||
                              _loadingModelOptions ||
                              _changingModel)
                          ? null
                          : _showModelSelector,
                      icon: _loadingModelOptions || _changingModel
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.tune, size: 18),
                      label: Text(
                        '${_sessionModel ?? widget.session.model} • '
                        '${_sessionModelOverride ? 'this chat' : 'profile default'}',
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Semantics(
                  label: 'Attachment drafts',
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.32,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _attachmentDrafts.length,
                      itemBuilder: (context, index) => AttachmentDraftTile(
                        draft: _attachmentDrafts[index],
                        index: index,
                        total: _attachmentDrafts.length,
                        busy: _sending,
                        onMovePrevious: () =>
                            _moveAttachment(_attachmentDrafts[index], -1),
                        onMoveNext: () =>
                            _moveAttachment(_attachmentDrafts[index], 1),
                        onRetry: () =>
                            _retryAttachment(_attachmentDrafts[index]),
                        onRemove: () =>
                            _removeAttachment(_attachmentDrafts[index]),
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
            Row(
              children: [
                Semantics(
                  label: 'Add attachment',
                  button: true,
                  enabled: !_loading && !_streaming && !_sending,
                  excludeSemantics: true,
                  child: IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: (!_loading && !_streaming && !_sending)
                        ? _showAttachmentPicker
                        : null,
                    tooltip: 'Attach image or file',
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
                Expanded(
                  child: Semantics(
                    label: 'Message',
                    textField: true,
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
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
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.send,
                      enabled: !_loading && !_streaming,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_voiceComposer.listening)
                  VoiceComposerStartButton(
                    enabled: !_loading && !_streaming && !_sending,
                    onPressed: _startVoiceInput,
                  ),
                Semantics(
                  label: 'Spoken replies',
                  value: _voiceReplyEnabled ? 'On' : 'Off',
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
                        ? 'Spoken replies on'
                        : 'Spoken replies off',
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Semantics(
                  label: _streaming ? 'Stop response' : 'Send message',
                  button: true,
                  enabled:
                      _streaming ||
                      (!_loading && !_sending && !_voiceComposer.listening),
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
                              tooltip: 'Stop response',
                              constraints: const BoxConstraints.tightFor(
                                width: 48,
                                height: 48,
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.send, size: 20),
                              onPressed:
                                  _loading ||
                                      _sending ||
                                      _voiceComposer.listening
                                  ? null
                                  : _sendMessage,
                              tooltip: 'Send',
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Failed to load messages',
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
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Build display list: consecutive tool messages grouped into cards,
    // interleaved with user/assistant bubbles.
    final toolQueue = List<GatewayToolActivity>.from(_toolActivities);
    final displayMessages = <dynamic>[];
    final currentGroup = <GatewayToolActivity>[];
    String? lastUserPrompt;

    for (final msg in _messages) {
      final role = (msg['role'] as String?) ?? 'assistant';
      if (isToolResultMessage(msg)) {
        if (toolQueue.isNotEmpty) {
          currentGroup.add(toolQueue.removeAt(0));
        }
        continue;
      }
      if (role != 'user' && role != 'assistant') continue;
      final content = stripToolResultText(messageContentToText(msg['content']));
      final reasoning = msg['_gateway_reasoning']?.toString() ?? '';
      if (content.isEmpty && reasoning.trim().isEmpty) continue;

      if (currentGroup.isNotEmpty) {
        displayMessages.add(currentGroup.toList());
        currentGroup.clear();
      }
      if (role == 'assistant' && reasoning.trim().isNotEmpty) {
        displayMessages.add(
          _GatewayReasoningDisplay(
            reasoning,
            _verboseMode || msg['_gateway_reasoning_verbose'] == true,
          ),
        );
      }
      if (content.isNotEmpty) {
        if (role == 'user') lastUserPrompt = content;
        displayMessages.add({
          ...msg,
          '_display_content': content,
          if (role == 'assistant' && lastUserPrompt != null)
            '_retry_prompt': lastUserPrompt,
        });
      }
    }
    if (currentGroup.isNotEmpty) {
      displayMessages.add(currentGroup.toList());
    }

    // Tools from SSE events that arrived during streaming but haven't been
    // matched to server messages yet — show them as a card.
    if (toolQueue.isNotEmpty) {
      displayMessages.add(toolQueue.toList());
    }
    if (_subagentActivities.isNotEmpty) {
      displayMessages.add(
        List<GatewaySubagentActivity>.from(_subagentActivities),
      );
    }
    displayMessages.addAll(_gatewayNotices);

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        _syncEndAffordance(notification.metrics, clearUnreadAtEnd: false);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 4),
          itemCount: displayMessages.length,
          itemBuilder: (context, index) {
            final item = displayMessages[index];

            if (item is List<GatewayToolActivity>) {
              return GatewayActivityCard(
                activities: item,
                verbose: _verboseMode,
              );
            }
            if (item is List<GatewaySubagentActivity>) {
              return GatewaySubagentCard(activities: item);
            }
            if (item is _GatewayReasoningDisplay) {
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
              metadata: msg,
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
  final Map<String, dynamic> metadata;
  final Future<void> Function()? onReadAloud;
  final VoidCallback? onEdit;
  final Future<void> Function()? onRetry;

  const MessageBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.verbose = false,
    this.metadata = const {},
    this.onReadAloud,
    this.onEdit,
    this.onRetry,
  });

  Future<void> _copyMessage(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Message copied'),
          duration: Duration(seconds: 2),
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

    final bubble = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 80,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? userBubbleColor : assistantBubbleColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
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
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          // Message content
          MarkdownBody(
            data: content,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: (isUser
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: hermesUserMessageForeground,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: assistantTextColor,
                    )),
              code: TextStyle(
                backgroundColor: (isUser ? Colors.white : Colors.black)
                    .withValues(alpha: 0.12),
                fontFamily: 'monospace',
                color: isUser ? hermesUserMessageForeground : null,
              ),
              a: TextStyle(
                color: isUser
                    ? hermesUserMessageForeground
                    : theme.colorScheme.primary,
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
                  : theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              strong: isUser
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: hermesUserMessageForeground,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Wrap(
              spacing: 0,
              runSpacing: 0,
              children: [
                Semantics(
                  label: 'Copy message',
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 19),
                    tooltip: 'Copy message',
                    onPressed: () => _copyMessage(context),
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
                if (onReadAloud != null)
                  Semantics(
                    label: 'Read aloud',
                    button: true,
                    excludeSemantics: true,
                    child: IconButton(
                      icon: const Icon(Icons.volume_up_outlined, size: 20),
                      tooltip: 'Read aloud',
                      onPressed: onReadAloud,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ),
                if (onEdit != null)
                  Semantics(
                    label: 'Edit and resend',
                    button: true,
                    excludeSemantics: true,
                    child: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit and resend',
                      onPressed: onEdit,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ),
                if (onRetry != null)
                  Semantics(
                    label: 'Regenerate response',
                    button: true,
                    excludeSemantics: true,
                    child: IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Regenerate from the preceding prompt',
                      onPressed: onRetry,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bubble],
    );
  }
}
