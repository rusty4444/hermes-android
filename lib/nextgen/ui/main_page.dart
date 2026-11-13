// The NextGen main screen: the sidebar drawer beside one open chat.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/session.dart';
import '../../core/services/turn_notification_service.dart';
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = NgScope.of(context);
    final sessions = _sessions;
    if (sessions == null) {
      _sessions = NgSessionsModel(scope);
      unawaited(_sessions!.refresh());
      final last = NextGenPreferences.lastSession(
        scope.prefs,
        scope.connection.id,
      );
      _openId(last, '', initial: true);
    } else {
      sessions.scope = scope;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
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
        unawaited(_sessions?.refresh());
      },
      onTurnFinished: () => _turnFinished(chat),
    );
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

  void _turnFinished(NgChatController chat) {
    unawaited(_sessions?.refresh());
    if (_foreground) return;
    final reply = chat.items.whereType<NgAssistantItem>().lastOrNull;
    final text = reply?.text.trim() ?? '';
    unawaited(
      TurnNotificationService.shared.showTurnCompleted(
        title: chat.title.isEmpty ? 'Hermes replied' : chat.title,
        turnSummary: text.isEmpty
            ? 'The turn finished.'
            : text.length > 180
            ? '${text.substring(0, 180)}…'
            : text,
        turnId: '${chat.storedId}-${DateTime.now().millisecondsSinceEpoch}',
        sessionId: chat.storedId,
        connectionId: NgScope.of(context).connection.id,
      ),
    );
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat?.dispose();
    _sessions?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    return Scaffold(
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
              onNewChat: _newChat,
            ),
    );
  }
}
