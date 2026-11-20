import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_api_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/data/seen_chats.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:hermes_android/nextgen/ui/sessions_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _row(
  String id,
  double lastActive, {
  String source = 'desktop',
  bool unread = false,
  double? lastReadAt,
  String title = '',
  bool active = false,
}) => Session(
  id: id,
  title: title.isEmpty ? 'Chat $id' : title,
  model: 'm',
  source: source,
  messageCount: 2,
  isActive: active,
  preview: '',
  startedAt: 1000,
  lastActive: lastActive,
  unread: unread,
  lastReadAt: lastReadAt,
);

SavedConnection _conn() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
);

class _ControlledSessionsApi extends DashboardApiClient {
  _ControlledSessionsApi(super.dashboard) : super.withDashboard();

  final calls = <({int offset, String? title})>[];
  final _pages = <Completer<SessionListPage>>[];

  @override
  Future<SessionListPage> getSessionsPage({
    int limit = 50,
    int offset = 0,
    String? title,
    Duration timeout = ApiClient.requestTimeout,
  }) {
    calls.add((offset: offset, title: title));
    final page = Completer<SessionListPage>();
    _pages.add(page);
    return page.future;
  }

  void complete(int index, List<Session> sessions, {bool hasMore = false}) {
    _pages[index].complete(
      SessionListPage(sessions: sessions, hasMore: hasMore),
    );
  }
}

NgSessionsModel _model(
  NextGenGateway gateway,
  SharedPreferences prefs,
  SavedConnection connection,
) => NgSessionsModel(
  NgScope(
    connManager: ConnectionManager(prefs),
    gateway: gateway,
    connections: [connection],
    switchTo: (_) async {},
    addGateway: () async {},
    signOut: (_) async {},
    reload: () async {},
    signInAgain: () async {},
    child: const SizedBox(),
  ),
);

void main() {
  group('seen chats', () {
    test('activity after the last look here is unread', () {
      final seen = NgSeenChats(since: 2000, chats: {'a': 3000});
      expect(seen.isUnread(_row('a', 2999)), isFalse);
      expect(seen.isUnread(_row('a', 3000.5)), isFalse, reason: 'slack');
      expect(seen.isUnread(_row('a', 3100)), isTrue);
      // Never looked at: anything since tracking began is news.
      expect(seen.isUnread(_row('b', 1500)), isFalse);
      expect(seen.isUnread(_row('b', 2500)), isTrue);
    });

    test('the gateway watermark wins, unless a later look here', () {
      final seen = NgSeenChats(since: 0, chats: {'a': 5000});
      expect(seen.isUnread(_row('a', 4000, lastReadAt: 3000)), isFalse);
      expect(
        seen.isUnread(_row('b', 4000, lastReadAt: 3000, unread: true)),
        isTrue,
      );
      expect(seen.isUnread(_row('b', 2000, lastReadAt: 3000)), isFalse);
      // Zero is an explicit mark-unread elsewhere: a look here doesn't hide it.
      expect(
        seen.isUnread(_row('a', 4000, lastReadAt: 0, unread: true)),
        isTrue,
      );
    });

    test('messaging-platform chats need a flag or a turn left running', () {
      final seen = NgSeenChats(since: 0, chats: {'t': 100});
      expect(seen.isUnread(_row('t', 500, source: 'telegram')), isFalse);
      expect(seen.isUnread(_row('t', 500, source: 'cron')), isTrue);
      seen.leftRunning.add('t');
      expect(seen.isUnread(_row('t', 500, source: 'telegram')), isTrue);
    });

    test(
      'the store persists looks and marks, and a look clears a mark',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = NgSeenStore(prefs, 'c1');
        store.markLooked('a', 9e9);
        store.markUnread('b');
        final again = NgSeenStore(prefs, 'c1');
        expect(again.chats.chats['a'], 9e9);
        expect(again.chats.isUnread(_row('b', 1)), isTrue);
        again.markLooked('b', 9e9);
        expect(again.chats.isUnread(_row('b', 1)), isFalse);
        expect(NgSeenStore(prefs, 'other').chats.chats, isEmpty);
      },
    );

    test('rows parse the gateway read state', () {
      final s = Session.fromJson({
        'id': 'x',
        'unread': true,
        'last_read_at': 12.5,
        'started_at': 1,
      });
      expect(s.unread, isTrue);
      expect(s.lastReadAt, 12.5);
      expect(s.withTitle('t').lastReadAt, 12.5);
      expect(Session.fromJson({'id': 'y'}).lastReadAt, isNull);
    });
  });

  group('session list loading', () {
    test(
      'refresh bursts share one request and coalesce one trailing read',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final conn = _conn();
        final gateway = NextGenGateway(conn);
        final api = _ControlledSessionsApi(gateway.dashboard);
        gateway.api = api;
        final model = _model(gateway, prefs, conn);
        addTearDown(() {
          model.dispose();
          gateway.dispose();
        });

        final first = model.refresh();
        model.query = 'latest';
        final second = model.refresh();
        final third = model.refresh();
        await pumpEventQueue();
        expect(api.calls, hasLength(1));

        api.complete(0, [_row('old', 1000)]);
        await pumpEventQueue();
        expect(api.calls, hasLength(2));
        expect(api.calls[1].title, 'latest');

        api.complete(1, [_row('new', 2000)]);
        await Future.wait([first, second, third]);
        expect(model.sessions.map((s) => s.id), ['new']);
        expect(model.loading, isFalse);
      },
    );

    test('a refresh invalidates an older load-more response', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final conn = _conn();
      final gateway = NextGenGateway(conn);
      final api = _ControlledSessionsApi(gateway.dashboard);
      gateway.api = api;
      final model = _model(gateway, prefs, conn);
      addTearDown(() {
        model.dispose();
        gateway.dispose();
      });

      // Seed one full page through refresh so the raw server offset is set.
      final seeding = model.refresh();
      await pumpEventQueue();
      api.complete(0, [
        for (var i = 0; i < 60; i++) _row('c$i', 1000.0 + i),
      ], hasMore: true);
      await seeding;
      expect(model.sessions, hasLength(60));

      final paging = model.loadMore();
      await pumpEventQueue();
      expect(api.calls[1].offset, 60);
      final refreshing = model.refresh();
      await pumpEventQueue();
      expect(api.calls, hasLength(3));

      api.complete(2, [_row('fresh', 3000)]);
      await refreshing;
      api.complete(1, [_row('stale-page', 2000)]);
      await paging;

      expect(model.sessions.map((s) => s.id), ['fresh']);
      expect(model.loading, isFalse);
      expect(model.hasMore, isFalse);
    });
  });

  testWidgets('sidebar highlights unread chats and badges its button', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    SharedPreferences.setMockInitialValues({
      'nextgen.seen_chats.c1':
          '{"since": ${now - 3600}, "chats": {"read": $now}}',
    });
    final prefs = await SharedPreferences.getInstance();
    final conn = _conn();
    final gateway = NextGenGateway(conn);
    addTearDown(gateway.dispose);
    late NgSessionsModel model;
    await tester.pumpWidget(
      MaterialApp(
        theme: nextGenTheme(Brightness.light, NextGenLook.instance),
        home: NgScope(
          connManager: ConnectionManager(prefs),
          gateway: gateway,
          connections: [conn],
          switchTo: (_) async {},
          addGateway: () async {},
          signOut: (_) async {},
          reload: () async {},
          signInAgain: () async {},
          child: Builder(
            builder: (context) {
              model = NgSessionsModel(NgScope.of(context))
                ..sessions = [
                  _row('new', now - 10, title: 'Has news'),
                  _row('read', now - 20, title: 'Already read'),
                  _row('open', now - 5, title: 'On screen'),
                  _row('cron', now - 10, source: 'cron', title: 'Cron update'),
                ]
                ..currentId = 'open';
              return Scaffold(
                body: NgSessionsSidebar(
                  model: model,
                  currentSessionId: 'open',
                  onOpen: (_) {},
                  onNewChat: () {},
                  onDestination: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('ng-session-new-finished')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ng-session-read')), findsOneWidget);
    // The chat on screen is never unread.
    expect(find.byKey(const ValueKey('ng-session-open')), findsOneWidget);
    expect(find.text('Cron update'), findsNothing);
    expect(model.unreadCount, 1);
    final title = tester.widget<Text>(find.text('Has news'));
    expect(title.style?.fontWeight, FontWeight.w700);

    // Needs you lists unread chats too.
    expect(find.text('Needs you · 1'), findsOneWidget);

    // Running with unread updates is blue; waiting on you is orange, read
    // or not.
    expect(
      model.attentionOf(_row('run', now - 1, active: true)),
      NgChatAttention.updates,
    );
    expect(
      model.attentionOf(_row('read', now - 20), needsYou: {'read'}),
      NgChatAttention.waiting,
    );
    expect(model.attentionOf(_row('read', now - 20)), NgChatAttention.none);
    expect(model.topAttention, NgChatAttention.finished);

    model.markRead('new');
    await tester.pump();
    expect(find.byKey(const ValueKey('ng-session-new')), findsOneWidget);
    expect(model.unreadCount, 0);

    // sessions.changed from the gateway reads the list again (debounced).
    gateway.debugEmit(StreamEvent(type: 'sessions.changed', data: const {}));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    model.dispose();
  });

  testWidgets('sidebar search has a clear button that restores all chats', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final conn = _conn();
    final gateway = NextGenGateway(conn);
    final api = _ControlledSessionsApi(gateway.dashboard);
    gateway.api = api;
    late NgSessionsModel model;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: nextGenTheme(Brightness.light, NextGenLook.instance),
        home: NgScope(
          connManager: ConnectionManager(prefs),
          gateway: gateway,
          connections: [conn],
          switchTo: (_) async {},
          addGateway: () async {},
          signOut: (_) async {},
          reload: () async {},
          signInAgain: () async {},
          child: Builder(
            builder: (context) {
              model = NgSessionsModel(NgScope.of(context));
              return Scaffold(
                body: NgSessionsSidebar(
                  model: model,
                  currentSessionId: null,
                  onOpen: (_) {},
                  onNewChat: () {},
                  onDestination: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    final field = find.byKey(const Key('ng-session-search'));
    final clear = find.byKey(const Key('ng-clear-search'));
    expect(clear, findsNothing);

    await tester.enterText(field, 'daily');
    await tester.pump();
    expect(clear, findsOneWidget);
    expect(model.query, 'daily');

    await tester.tap(clear);
    await tester.pump();
    expect(model.query, isEmpty);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(clear, findsNothing);
    expect(api.calls, hasLength(1));
    expect(api.calls.single.title, isNull);

    // Clearing cancels the old 300 ms search rather than sending it later.
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.calls, hasLength(1));
    api.complete(0, [_row('ordinary', 1000, title: 'Ordinary chat')]);
    await tester.pump();
    expect(find.text('Ordinary chat'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    model.dispose();
    gateway.dispose();
  });

  testWidgets('cron conversations have their own sidebar section', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final conn = _conn();
    final gateway = NextGenGateway(conn);
    late NgSessionsModel model;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: nextGenTheme(Brightness.light, NextGenLook.instance),
        home: NgScope(
          connManager: ConnectionManager(prefs),
          gateway: gateway,
          connections: [conn],
          switchTo: (_) async {},
          addGateway: () async {},
          signOut: (_) async {},
          reload: () async {},
          signInAgain: () async {},
          child: Builder(
            builder: (context) {
              model = NgSessionsModel(NgScope.of(context))
                ..sessions = [
                  _row('ordinary', 1000, title: 'Ordinary chat'),
                  _row(
                    'daily-report',
                    2000,
                    source: 'cron',
                    title: 'Daily report',
                    active: true,
                  ),
                ];
              return Scaffold(
                body: NgSessionsSidebar(
                  model: model,
                  currentSessionId: null,
                  onOpen: (_) {},
                  onNewChat: () {},
                  onDestination: (_) {},
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Ordinary chat'), findsOneWidget);
    expect(find.text('Daily report'), findsNothing);
    expect(find.text('Crons'), findsOneWidget);

    await tester.tap(find.text('Running'));
    await tester.pump();
    expect(find.text('Daily report'), findsNothing);

    await tester.ensureVisible(find.text('Crons'));
    await tester.pump();
    await tester.tap(find.text('Crons'));
    await tester.pump();
    expect(find.text('Daily report'), findsOneWidget);
    expect(find.text('Ordinary chat'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    model.dispose();
    gateway.dispose();
  });
}
