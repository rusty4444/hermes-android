// The NextGen main screen: the sidebar drawer beside one open chat.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/session.dart';
import '../../core/services/notification_prefs.dart';
import '../../core/services/turn_notification_service.dart';
import '../data/nextgen_gateway.dart';
import '../data/chat_controller.dart';
import '../nextgen_preferences.dart';
import 'capabilities_page.dart';
import 'chat_view.dart';
import 'insights_page.dart';
import 'more_page.dart';
import 'nextgen_scope.dart';
import 'scheduled_page.dart';
import 'sessions_sidebar.dart';
import 'settings_page.dart';
import '../nextgen_l10n.dart';

class NgMainPage extends StatefulWidget {
  const NgMainPage({super.key});

  @override
  State<NgMainPage> createState() => _NgMainPageState();
}

class _NgMainPageState extends State<NgMainPage> with WidgetsBindingObserver {
  final _scaffold = GlobalKey<ScaffoldState>();
  NgSessionsModel? _sessions;
  NgChatController? _chat;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    nextGenOpenRequest.addListener(_onOpenRequest);
    nextGenNotificationAnswer.addListener(_onNotificationAnswer);
  }

  @override
  void dispose() {
    nextGenOpenRequest.removeListener(_onOpenRequest);
    nextGenNotificationAnswer.removeListener(_onNotificationAnswer);
    _requestSub?.cancel();
    _watchedGateway?.removeListener(_onGatewayChanged);
    _pendingAnswerTimeout?.cancel();
    _chat?.removeListener(_onChatChanged);
    nextGenTurnActive.value = false;
    WidgetsBinding.instance.removeObserver(this);
    _chat?.dispose();
    _sessions?.dispose();
    super.dispose();
  }

  /// The chat a notification tap asked for, when it belongs to this
  /// connection. Consumed so it opens once.
  String? _takeOpenRequest(String connectionId) {
    final request = nextGenOpenRequest.value;
    if (request == null || request.connectionId != connectionId) return null;
    nextGenOpenRequest.value = null;
    return request.sessionId;
  }

  void _onOpenRequest() {
    if (!mounted) return;
    final scope = NgScope.of(context);
    final id = _takeOpenRequest(scope.connection.id);
    if (id == null) return;
    _scaffold.currentState?.closeDrawer();
    if (id == _chat?.storedId) return;
    _openId(id, '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = NgScope.of(context);
    final sessions = _sessions;
    if (sessions == null) {
      _sessions = NgSessionsModel(scope);
      unawaited(_sessions!.refresh());
      final last =
          _takeOpenRequest(scope.connection.id) ??
          NextGenPreferences.lastSession(scope.prefs, scope.connection.id);
      _openId(last, '', initial: true);
      _listenForRequests(scope);
    } else {
      sessions.scope = scope;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    // In sight while resumed or only covered (the notification shade).
    _foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    final chat = _chat;
    if (!_foreground && wasForeground && chat != null) {
      // Out of sight: what arrives from now on is news when the user is back.
      _sessions?.markRead(chat.storedId, running: chat.running);
      _sessions?.currentId = null;
    }
    if (!_foreground && wasForeground) {
      // A question that came in while in sight still needs its notification
      // now that the app isn't.
      final scope = NgScope.of(context);
      for (final raw in scope.gateway.openRequests.values.toList()) {
        unawaited(_notifyRequest(scope, raw));
      }
    }
    if (_foreground && !wasForeground) {
      _cancelAttention();
      // Catch the open chat up on what the socket may have missed.
      chat?.resync();
    }
    if (_foreground) {
      _sessions?.currentId = chat?.storedId;
      final scope = NgScope.of(context);
      if (!scope.gateway.state.isConnected) scope.gateway.retry();
      unawaited(_sessions?.refresh());
    }
  }

  void _openId(String? id, String title, {bool initial = false}) {
    final scope = NgScope.of(context);
    final old = _chat;
    late final NgChatController chat;
    chat = NgChatController(
      scope.gateway,
      sessionId: id,
      title: title,
      onCreated: (stored) {
        unawaited(
          NextGenPreferences.setLastSession(
            scope.prefs,
            scope.connection.id,
            stored,
          ),
        );
        if (identical(_chat, chat)) _sessions?.currentId = stored;
        unawaited(_sessions?.refresh());
      },
      onTurnFinished: () => _turnFinished(chat),
    );
    // Leaving a chat counts as having seen it so far; one left mid-turn shows
    // unread when its reply lands.
    _sessions?.markRead(old?.storedId, running: old?.running ?? false);
    _sessions?.currentId = id;
    if (id != null) _sessions?.markRead(id);
    old?.removeListener(_onChatChanged);
    chat.addListener(_onChatChanged);
    _chatWasRunning = false;
    nextGenTurnActive.value = false;
    if (initial) {
      _chat = chat;
    } else {
      setState(() => _chat = chat);
    }
    old?.dispose();
    unawaited(chat.open());
    unawaited(
      NextGenPreferences.setLastSession(scope.prefs, scope.connection.id, id),
    );
  }

  // ── Notifications (Kyllene's ChatNotifier) ──────────────────────────
  //
  // Out of sight: a heads-up for every approval, question or secret the agent
  // waits on (approvals with Allow once / Deny buttons), and the open chat's
  // reply when its turn ends. Each comes down once answered, when a new turn
  // starts in that chat, or when the app is back in sight. While the open
  // chat's turn runs, the app root keeps the process up (foreground service)
  // so the socket survives the background.

  StreamSubscription<NgServerRequest>? _requestSub;
  NextGenGateway? _watchedGateway;

  /// Requests posted, by request id: what to cancel once each is gone.
  final Map<String, ({HermesNotificationKind kind, String? sessionId})>
  _postedRequests = {};

  /// Chats whose reply notification is up.
  final Set<String> _postedReplies = {};

  static const _replyTurnId = 'nextgen-reply';

  void _listenForRequests(NgScope scope) {
    _requestSub?.cancel();
    _requestSub = scope.gateway.serverRequests.listen(
      (raw) => unawaited(_notifyRequest(scope, raw)),
    );
    _watchedGateway?.removeListener(_onGatewayChanged);
    _watchedGateway = scope.gateway..addListener(_onGatewayChanged);
  }

  String? _storedFor(NgScope scope, String? runtime) => runtime == null
      ? _chat?.storedId
      : scope.gateway.storedIdFor(runtime) ?? runtime;

  Future<void> _notifyRequest(NgScope scope, NgServerRequest raw) async {
    if (_foreground || !mounted) return;
    if (_postedRequests.containsKey(raw.id)) return;
    final input = NgInputRequest.parse(raw);
    if (input == null) return;
    final stored = _storedFor(scope, raw.sessionId);
    final approval = input.kind == NgRequestKind.approval;
    final kind = approval
        ? HermesNotificationKind.approval
        : HermesNotificationKind.input;
    final posted = await TurnNotificationService.shared.showKind(
      kind: kind,
      title: input.title,
      body: input.body.isNotEmpty
          ? input.body
          : (input.command ?? ngL.ng_hermes_is_waiting_for_you),
      eventId: raw.id,
      sessionId: stored,
      connectionId: scope.connection.id,
      actions: approval
          ? [
              TurnNotificationAction(id: 'approve', label: ngL.ng_allow_once),
              TurnNotificationAction(id: 'reject', label: ngL.ng_deny),
            ]
          : const [],
      payload: jsonEncode({
        'connectionId': scope.connection.id,
        'sessionId': stored,
        'requestId': raw.id,
      }),
    );
    if (posted) _postedRequests[raw.id] = (kind: kind, sessionId: stored);
  }

  /// Requests answered here, elsewhere or withdrawn take their notification
  /// with them.
  void _onGatewayChanged() {
    final gateway = _watchedGateway;
    if (gateway == null || _postedRequests.isEmpty) return;
    for (final id in _postedRequests.keys.toList()) {
      if (!gateway.openRequests.containsKey(id)) _cancelRequest(id);
    }
    _answerPending();
  }

  void _cancelRequest(String id) {
    final posted = _postedRequests.remove(id);
    if (posted == null || !mounted) return;
    unawaited(
      TurnNotificationService.shared.cancelKind(
        kind: posted.kind,
        eventId: id,
        sessionId: posted.sessionId,
        connectionId: NgScope.of(context).connection.id,
      ),
    );
  }

  void _cancelReply(String storedId) {
    if (!_postedReplies.remove(storedId) || !mounted) return;
    unawaited(
      TurnNotificationService.shared.cancelTurnCompleted(
        _replyTurnId,
        sessionId: storedId,
        connectionId: NgScope.of(context).connection.id,
      ),
    );
  }

  /// Back in sight: what was posted is on screen now.
  void _cancelAttention() {
    for (final id in _postedRequests.keys.toList()) {
      _cancelRequest(id);
    }
    for (final id in _postedReplies.toList()) {
      _cancelReply(id);
    }
  }

  // An approval button pressed, answered on this socket once the request is
  // there (it is redelivered when the socket comes back).
  NgNotificationAnswer? _pendingAnswer;
  Timer? _pendingAnswerTimeout;

  void _onNotificationAnswer() {
    final answer = nextGenNotificationAnswer.value;
    if (answer == null || !mounted) return;
    if (answer.connectionId != NgScope.of(context).connection.id) return;
    nextGenNotificationAnswer.value = null;
    _pendingAnswer = answer;
    _pendingAnswerTimeout?.cancel();
    _pendingAnswerTimeout = Timer(
      const Duration(seconds: 30),
      () => _pendingAnswer = null,
    );
    _answerPending();
  }

  void _answerPending() {
    final answer = _pendingAnswer;
    final gateway = _watchedGateway;
    if (answer == null || gateway == null) return;
    final request = gateway.openRequests[answer.requestId];
    if (request == null) return;
    _pendingAnswer = null;
    _pendingAnswerTimeout?.cancel();
    request.raw.respond({'choice': answer.choice});
    gateway.forgetRequest(answer.requestId);
    _chat?.forgetRequest(answer.requestId);
    _cancelRequest(answer.requestId);
  }

  bool _chatWasRunning = false;

  void _onChatChanged() {
    final chat = _chat;
    if (chat == null) return;
    if (chat.running && !_chatWasRunning) {
      final stored = chat.storedId;
      if (stored != null) _cancelReply(stored);
    }
    _chatWasRunning = chat.running;
    nextGenTurnActive.value = chat.running;
  }

  void _turnFinished(NgChatController chat) {
    unawaited(_sessions?.refresh());
    if (!mounted) return;
    final label = chat.title.isEmpty ? ngL.ng_hermes_replied : chat.title;
    if (_foreground) {
      TurnNotificationService.recordAttempt(
        'reply',
        label,
        'skipped',
        'Ares was on screen',
      );
      return;
    }
    if (chat.lastTurnInterrupted) {
      TurnNotificationService.recordAttempt(
        'reply',
        label,
        'skipped',
        'the turn was stopped',
      );
      return;
    }
    final stored = chat.storedId;
    final reply = chat.items.whereType<NgAssistantItem>().lastOrNull;
    var text = reply?.text.trim() ?? '';
    final failed = chat.lastTurnFailed;
    if (failed && (chat.error?.isNotEmpty ?? false)) text = chat.error!;
    final title = chat.title.isEmpty ? ngL.ng_hermes_replied : chat.title;
    final body = text.isEmpty
        ? (failed ? ngL.ng_the_turn_failed : ngL.ng_the_turn_finished)
        : text.length > 180
        ? '${text.substring(0, 180)}…'
        : text;
    final connectionId = NgScope.of(context).connection.id;
    final notifications = TurnNotificationService.shared;
    unawaited(
      failed
          ? notifications.showTurnFailed(
              title: title,
              turnSummary: body,
              turnId: _replyTurnId,
              sessionId: stored,
              connectionId: connectionId,
            )
          : notifications.showTurnCompleted(
              title: title,
              turnSummary: body,
              turnId: _replyTurnId,
              sessionId: stored,
              connectionId: connectionId,
            ),
    );
    if (stored != null) _postedReplies.add(stored);
  }

  void _onBack(bool didPop) {
    if (didPop) return;
    final scaffold = _scaffold.currentState;
    if (scaffold == null) return;
    if (scaffold.isDrawerOpen) {
      unawaited(SystemNavigator.pop());
    } else {
      scaffold.openDrawer();
    }
  }

  void _open(Session s) {
    _scaffold.currentState?.closeDrawer();
    if (s.id == _chat?.storedId) return;
    _openId(s.id, ngSessionTitle(s));
  }

  void _newChat() {
    _scaffold.currentState?.closeDrawer();
    if (_chat?.isNew == true && _chat!.items.isEmpty) return;
    _openId(null, '');
  }

  void _go(NgDestination d) {
    _scaffold.currentState?.closeDrawer();
    final Widget page = switch (d) {
      NgDestination.scheduled => NgScheduledPage(onOpenSession: _open),
      NgDestination.insights => const NgInsightsPage(),
      NgDestination.capabilities => const NgCapabilitiesPage(),
      NgDestination.archived => NgArchivedPage(onOpenSession: _open),
      NgDestination.more => NgMorePage(onOpenSession: _open),
      NgDestination.settings => const NgSettingsPage(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    // Back opens the sidebar; back again with the sidebar open leaves the
    // app. Pushed pages (settings, scheduled...) still pop normally first.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
      child: Scaffold(
        key: _scaffold,
        drawerEdgeDragWidth: 48,
        onDrawerChanged: (open) {
          if (open) unawaited(_sessions?.refresh());
        },
        drawer: NgSessionsSidebar(
          model: _sessions!,
          currentSessionId: chat?.storedId,
          onOpen: _open,
          onNewChat: _newChat,
          onDestination: _go,
        ),
        body: chat == null
            ? const SizedBox.shrink()
            : NgChatView(
                key: ObjectKey(chat),
                chat: chat,
                onOpenSidebar: () => _scaffold.currentState?.openDrawer(),
                sessions: _sessions,
                onNewChat: _newChat,
              ),
      ),
    );
  }
}
