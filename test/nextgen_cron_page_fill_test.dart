// Regression for #297: on a cron-heavy gateway the first activity-ordered
// pages are nothing but cron runs, which the chat list hides. One 60-row
// page left one or two chats and no scroll extent, so scroll-only paging
// never reached the rest. Refresh must read bounded pages until the list is
// usable, and load-more must page from raw rows read, not the filtered count.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_api_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:hermes_android/nextgen/ui/sessions_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _chat(String id, double lastActive) => Session(
  id: id,
  title: 'Chat $id',
  model: 'm',
  source: 'desktop',
  messageCount: 2,
  isActive: false,
  preview: '',
  startedAt: 1000,
  lastActive: lastActive,
);

Session _shell(String id) => Session(
  id: id,
  title: '',
  model: 'm',
  source: 'cron',
  messageCount: 0,
  isActive: false,
  preview: '',
  startedAt: 1000,
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

class _PagedApi extends DashboardApiClient {
  _PagedApi(super.dashboard) : super.withDashboard();

  final calls = <({int offset, int limit, String? title})>[];
  final _pages = <Completer<SessionListPage>>[];

  @override
  Future<SessionListPage> getSessionsPage({
    int limit = 50,
    int offset = 0,
    String? title,
    Duration timeout = ApiClient.requestTimeout,
  }) {
    calls.add((offset: offset, limit: limit, title: title));
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

Future<(NgSessionsModel, _PagedApi, NextGenGateway)> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final conn = _conn();
  final gateway = NextGenGateway(conn);
  final api = _PagedApi(gateway.dashboard);
  gateway.api = api;
  final model = _model(gateway, prefs, conn);
  return (model, api, gateway);
}

void main() {
  test(
    'refresh reads past cron-only pages until the chat list is usable',
    () async {
      final (model, api, gateway) = await _setup();
      addTearDown(() {
        model.dispose();
        gateway.dispose();
      });

      final refreshing = model.refresh();
      await pumpEventQueue();
      expect(api.calls.single.offset, 0);
      // Page 0: nothing but untitled cron shells, as on the reported gateway.
      api.complete(0, [
        for (var i = 0; i < 60; i++) _shell('s$i'),
      ], hasMore: true);
      await pumpEventQueue();
      expect(api.calls, hasLength(2));
      expect(api.calls[1].offset, 60);
      // Page 1: still mostly shells, two real chats near the end.
      api.complete(1, [
        for (var i = 60; i < 118; i++) _shell('s$i'),
        _chat('a', 5000),
        _chat('b', 4000),
      ], hasMore: true);
      await pumpEventQueue();
      expect(api.calls, hasLength(3));
      expect(api.calls[2].offset, 120);
      // Page 2: enough chats to fill the list; the store ends here.
      api.complete(2, [
        for (var i = 0; i < 20; i++) _chat('c$i', 3000.0 + i),
      ], hasMore: false);
      await refreshing;

      expect(model.sessions.map((s) => s.id), [
        'a',
        'b',
        for (var i = 0; i < 20; i++) 'c$i',
      ]);
      expect(model.sessions.where((s) => s.isUntitledCronShell), isEmpty);
      expect(model.hasMore, isFalse);
      expect(model.loading, isFalse);
    },
  );

  test(
    'a cron-heavy store is bounded per refresh and load-more continues',
    () async {
      final (model, api, gateway) = await _setup();
      addTearDown(() {
        model.dispose();
        gateway.dispose();
      });

      final refreshing = model.refresh();
      await pumpEventQueue();
      for (var i = 0; i < 10; i++) {
        expect(api.calls, hasLength(i + 1));
        expect(api.calls[i].offset, i * 60);
        api.complete(i, [
          for (var j = 0; j < 60; j++) _shell('s${i * 60 + j}'),
        ], hasMore: true);
        await pumpEventQueue();
      }
      await refreshing;
      // Bounded: no unbounded scan, and the store is not declared exhausted.
      expect(api.calls, hasLength(10));
      expect(model.sessions, isEmpty);
      expect(model.hasMore, isTrue);
      expect(model.loading, isFalse);

      final paging = model.loadMore();
      await pumpEventQueue();
      expect(api.calls, hasLength(11));
      expect(api.calls[10].offset, 600);
      api.complete(10, [_shell('s600'), _chat('deep', 9000)], hasMore: false);
      await paging;
      expect(model.sessions.map((s) => s.id), ['deep']);
      expect(model.hasMore, isFalse);
    },
  );

  test(
    'load-more pages from raw rows read, not the filtered list length',
    () async {
      final (model, api, gateway) = await _setup();
      addTearDown(() {
        model.dispose();
        gateway.dispose();
      });

      final seeding = model.refresh();
      await pumpEventQueue();
      // 40 shells + 20 chats: the list shows 20 rows but 60 were consumed.
      api.complete(0, [
        for (var i = 0; i < 40; i++) _shell('s$i'),
        for (var i = 0; i < 20; i++) _chat('c$i', 2000.0 + i),
      ], hasMore: true);
      await seeding;
      expect(model.sessions, hasLength(20));

      final paging = model.loadMore();
      await pumpEventQueue();
      expect(api.calls[1].offset, 60);
      api.complete(1, [
        _shell('s60'),
        _chat('next', 8000),
        _chat('c0', 7000), // duplicate of a loaded row
      ], hasMore: false);
      await paging;
      expect(model.sessions.map((s) => s.id), [
        for (var i = 0; i < 20; i++) 'c$i',
        'next',
      ]);
      expect(model.hasMore, isFalse);
    },
  );

  test('search stays one read and does not page', () async {
    final (model, api, gateway) = await _setup();
    addTearDown(() {
      model.dispose();
      gateway.dispose();
    });

    model.query = 'needle';
    final searching = model.refresh();
    await pumpEventQueue();
    expect(api.calls.single.title, 'needle');
    api.complete(0, [_chat('hit', 5000)], hasMore: true);
    await searching;
    expect(api.calls, hasLength(1));
    expect(model.sessions.map((s) => s.id), ['hit']);
    expect(model.hasMore, isFalse);
  });

  testWidgets('a short chat list offers Load more and grows on tap', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final conn = _conn();
    final gateway = NextGenGateway(conn);
    final api = _PagedApi(gateway.dashboard);
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

    final refreshing = model.refresh();
    await tester.pump();
    // Two chats buried in shells, then nine more cron-only pages: the list
    // stays short while the store continues.
    for (var i = 0; i < 10; i++) {
      api.complete(
        i,
        i == 0
            ? [
                _chat('a', 5000),
                _chat('b', 4000),
                for (var j = 0; j < 58; j++) _shell('s$j'),
              ]
            : [for (var j = 0; j < 60; j++) _shell('s${i * 60 + j}')],
        hasMore: true,
      );
      await tester.pump();
    }
    await refreshing;
    await tester.pump();
    expect(find.text('Chat a'), findsOneWidget);
    expect(find.text('Chat b'), findsOneWidget);
    final more = find.byKey(const Key('ng-sessions-load-more'));
    expect(more, findsOneWidget);

    await tester.tap(more);
    await tester.pump();
    expect(api.calls, hasLength(11));
    expect(api.calls[10].offset, 600);
    api.complete(10, [_chat('deep', 9000)], hasMore: false);
    await tester.pump();
    expect(find.text('Chat deep'), findsOneWidget);
    expect(find.byKey(const Key('ng-sessions-load-more')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    model.dispose();
    gateway.dispose();
  });
}
