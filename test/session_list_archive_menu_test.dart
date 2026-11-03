import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/session_search_preferences.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';

const _title = 'Telescope conversation';
const _query = 'telescope';

Map<String, dynamic> _row(String id, String title, {bool archived = false}) => {
  'id': id,
  'title': title,
  'model': 'list-model',
  'source': 'api_server',
  'message_count': 2,
  'preview': 'List preview',
  'started_at': 10,
  'last_active': 19,
  'ended_at': 20,
  'is_active': false,
  'archived': archived,
};

Map<String, dynamic> _hit(bool archived, String snippet) => {
  ..._row('chat-id', _title, archived: archived),
  'model': 'search-model',
  'message_count': 9,
  'preview': 'Rich search preview',
  'snippet': snippet,
  'role': 'assistant',
  'pinned': true,
  '_lineage_root_id': 'lineage-root',
};

http.Response _json(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _saved(bool archived) => _json({
  'session': {'id': 'chat-id', 'archived': archived},
});

http.Response _page(List<Map<String, dynamic>> rows) =>
    _json({'data': rows, 'has_more': false});

http.Response _hits(
  bool archived, [
  String snippet = 'Initial matching excerpt',
]) => _json({
  'results': [_hit(archived, snippet)],
});

class _ArchiveServer {
  bool archived = false;
  int searches = 0;
  int rewrites = 0;
  int reads = 0;
  final pages = <int>[];
  final writes = <http.Request>[];
  Future<http.Response> Function(int offset, int request)? page;
  Future<http.Response> Function(int request)? search;
  Future<http.Response> Function(http.Request)? patch;
  Future<http.Response> Function(int request)? read;

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path == '/dashboard/api/sessions/search') {
      searches++;
      expectSync(request.method, 'GET');
      expectSync(
        request.url.queryParameters['q'],
        anyOf(_query, 'telescope optics'),
      );
      if (search != null) return search!(searches);
      return _hits(archived);
    }
    expectSync(request.headers['authorization'], 'Bearer test-key');
    if (path == '/mobile/v1/search/rewrite') {
      rewrites++;
      expectSync(jsonDecode(request.body), {
        'query': _query,
        'provider': 'test-provider',
        'model': 'test-small-model',
      });
      return _json({'query': 'telescope optics'});
    }
    if (path == '/mobile/health') return _json({'status': 'ok'});
    if (path == '/mobile/api/sessions') {
      if (!request.url.queryParameters.containsKey('offset')) {
        // The real health check separately validates the bearer token.
        return _page([]);
      }
      final offset = int.parse(request.url.queryParameters['offset']!);
      pages.add(offset);
      if (page != null) return page!(offset, pages.length);
      return _page(
        offset == 0
            ? [
                _row('chat-id', _title, archived: archived),
                _row('other-id', 'Other conversation'),
                // Stock servers may back-fill a server-pinned archived row even when
                // the requested ordinary window excludes archived sessions.
                {
                  ..._row(
                    'archived-pin',
                    'Archived server pin',
                    archived: true,
                  ),
                  'pinned': true,
                },
              ]
            : [],
      );
    }
    expectSync(path, '/mobile/api/sessions/chat-id');
    if (request.method == 'GET') {
      reads++;
      if (read != null) return read!(reads);
      return _saved(archived);
    }
    expectSync(request.method, 'PATCH');
    expectSync(request.headers['content-type'], 'application/json');
    writes.add(request);
    if (patch != null) return patch!(request);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expectSync(body.keys, ['archived']);
    archived = body['archived'] as bool;
    return _saved(archived);
  });
}

Future<void> _mount(
  WidgetTester tester,
  _ArchiveServer server, {
  SessionSearchMode mode = SessionSearchMode.local,
  Widget Function(Session)? route,
}) async {
  final connection = SavedConnection(
    id: 'archive-${mode.name}',
    label: 'Archive fixture',
    host: 'fixture',
    port: 8642,
    apiKey: 'test-key',
    gatewayPrefix: '/mobile',
    dashboardPrefix: '/dashboard',
    dashboardProxied: true,
  );
  final preferences = await SessionSearchPreferences.open();
  final identity = '${connection.baseUrl}|/mobile|';
  await preferences.saveMode(connectionIdentity: identity, mode: mode);
  await preferences.saveAiModel(
    connectionIdentity: identity,
    selection: const AiSearchModel(
      provider: 'test-provider',
      model: 'test-small-model',
    ),
  );
  final controller = GatewayTurnApplicationController(
    sessionFactory: (_) => InertTurnApplicationSession(),
  );
  addTearDown(controller.close);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: SessionListScreen(
        connection: connection,
        turnApplicationController: controller,
        testHttpClient: server.client,
        testSessionPageSize: 2,
        testSessionScreenBuilder: route,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rowTile([String title = _title]) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

PopupMenuButton<String> _rowMenu(WidgetTester tester) =>
    tester.widget<PopupMenuButton<String>>(
      find.descendant(
        of: _rowTile(),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );

Future<void> _openRowMenu(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: _rowTile(), matching: find.byTooltip('Chat actions')),
  );
  await tester.pump();
  await tester.pump(kThemeAnimationDuration);
  await tester.pump();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await _openRowMenu(tester);
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(kThemeAnimationDuration);
  await tester.pump();
}

Future<void> _typeQuery(WidgetTester tester) async {
  await tester.enterText(find.byType(SearchBar), _query);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void _startOlderPage(WidgetTester tester) {
  ScrollUpdateNotification(
    metrics: FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 100,
      pixels: 100,
      viewportDimension: 600,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    ),
    context: tester.element(find.byType(ListView)),
    scrollDelta: 1,
  ).dispatch(tester.element(find.byType(ListView)));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final heldRead in ['none', 'older', 'full']) {
    testWidgets(
      'archive restarts physical paging after $heldRead pre-change read',
      (tester) async {
        final server = _ArchiveServer();
        final oldPage = Completer<http.Response>();
        final before = [_row('chat-id', _title), _row('b', 'Conversation B')];
        final after = [
          _row('b', 'Conversation B'),
          _row('c', 'Conversation C'),
          _row('d', 'Conversation D'),
          _row('e', 'Conversation E'),
        ];
        server.page = (offset, count) async {
          if (count == 2 && heldRead != 'none') return oldPage.future;
          final rows = server.archived ? after : before;
          return _page(rows.skip(offset).take(2).toList());
        };
        await _mount(tester, server);
        final menu = _rowMenu(tester);
        Future<void>? refresh;
        if (heldRead == 'older') _startOlderPage(tester);
        if (heldRead == 'full') {
          refresh = tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh();
        }
        await tester.pump();
        menu.onSelected!('archive');
        await tester.pump();
        await tester.pump(kThemeAnimationDuration);
        await tester.pump();
        expectSync(server.writes, hasLength(1));
        if (heldRead != 'none') {
          // A duplicated old window would ordinarily exhaust the scan. It
          // must neither exhaust nor advance the post-mutation cursor.
          oldPage.complete(_page(before));
          if (refresh != null) await refresh;
        }
        await tester.pumpAndSettle();
        final priorReads = List<int>.of(server.pages);
        _startOlderPage(tester);
        await tester.pumpAndSettle();
        expectSync(server.pages, [...priorReads, 0]);
        expectSync(find.text('Conversation C'), findsOneWidget);
        expectSync(find.text(_title), findsNothing);
        _startOlderPage(tester);
        await tester.pumpAndSettle();
        expectSync(server.pages, [...priorReads, 0, 2]);
        await tester.pumpWidget(const SizedBox());
        expectSync(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Local archive waits for GET, rejects duplicates/conflicts', (
    tester,
  ) async {
    final server = _ArchiveServer();
    final readback = Completer<http.Response>();
    server.read = (_) => readback.future;
    await _mount(tester, server);
    expectSync(find.text('Archived server pin'), findsNothing);
    await _typeQuery(tester);
    final staleMenu = _rowMenu(tester);
    await _choose(tester, 'Archive chat');
    staleMenu.onSelected!('archive');
    staleMenu.onSelected!('unarchive');
    staleMenu.onSelected!('rename');
    staleMenu.onSelected!('delete');
    await tester.pump();
    expectSync(server.writes, hasLength(1));
    expectSync(jsonDecode(server.writes.single.body), {'archived': true});
    expectSync(server.reads, 1);
    expectSync(
      find.text(_title),
      findsOneWidget,
      reason: 'no optimistic removal',
    );
    expectSync(tester.widget<ListTile>(_rowTile()).enabled, isFalse);
    expectSync(find.byType(AlertDialog), findsNothing);
    readback.complete(_saved(true));
    await tester.pumpAndSettle();
    expectSync(find.text(_title), findsNothing);
    expectSync(find.text('Chat archived'), findsOneWidget);
    expectSync(
      tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
      _query,
    );
    expectSync(server.searches, 0);
    expectSync(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in [SessionSearchMode.server, SessionSearchMode.ai]) {
    testWidgets(
      '${mode.name} archive/unarchive retains rich hits and fences old search',
      (tester) async {
        final server = _ArchiveServer();
        final oldSearch = Completer<http.Response>();
        server.search = (count) async =>
            count == 2 ? await oldSearch.future : _hits(server.archived);
        Session? opened;
        await _mount(
          tester,
          server,
          mode: mode,
          route: (session) {
            opened = session;
            return Scaffold(
              appBar: AppBar(title: const Text('Opened fixture')),
            );
          },
        );
        await _typeQuery(tester);
        expectSync(server.searches, 1);
        final refresh = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pump();
        expectSync(server.searches, 2);
        await _choose(tester, 'Archive chat');
        expectSync(server.writes, hasLength(1));
        expectSync(server.reads, 1);
        expectSync(jsonDecode(server.writes.single.body), {'archived': true});
        expectSync(
          find.text(_title),
          findsOneWidget,
          reason: 'archived search hits remain actionable',
        );
        expectSync(find.text('Initial matching excerpt'), findsOneWidget);
        expectSync(find.textContaining('search-model'), findsOneWidget);
        await _openRowMenu(tester);
        expectSync(find.text('Unarchive chat'), findsOneWidget);
        Navigator.of(tester.element(find.text('Unarchive chat'))).pop();
        await tester.pump(kThemeAnimationDuration);

        oldSearch.complete(_hits(false, 'Delayed matching excerpt'));
        await refresh;
        await tester.pumpAndSettle();
        expectSync(find.text('Delayed matching excerpt'), findsOneWidget);
        expectSync(find.textContaining('search-model'), findsOneWidget);
        await _choose(tester, 'Unarchive chat');
        await tester.pumpAndSettle();
        expectSync(server.writes.map((r) => jsonDecode(r.body)), [
          {'archived': true},
          {'archived': false},
        ]);
        expectSync(server.reads, 2);
        expectSync(find.text('Delayed matching excerpt'), findsOneWidget);
        expectSync(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          _query,
        );
        expectSync(
          tester.widget<SearchBar>(find.byType(SearchBar)).hintText,
          mode == SessionSearchMode.ai
              ? 'Ask AI to find a conversation'
              : 'Search all message content',
        );
        if (mode == SessionSearchMode.ai) expectSync(server.rewrites, 2);
        await tester.tap(find.text(_title));
        await tester.pumpAndSettle();
        expectSync(opened!.id, 'chat-id');
        expectSync(opened!.archived, isFalse);
        expectSync(opened!.model, 'search-model');
        expectSync(opened!.messageCount, 9);
        expectSync(opened!.preview, 'Rich search preview');
        expectSync(opened!.pinned, isTrue);
        expectSync(opened!.lineageRootId, 'lineage-root');
        expectSync(opened!.startedAt, 10);
        expectSync(opened!.endedAt, 20);
        expectSync(opened!.lastActive, 19);
        expectSync(opened!.source, 'api_server');
        expectSync(opened!.isActive, isFalse);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expectSync(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          _query,
        );
        // A genuinely newer read can reflect another device's archive change.
        server.archived = true;
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pumpAndSettle();
        await _openRowMenu(tester);
        expectSync(find.text('Unarchive chat'), findsOneWidget);
        expectSync(server.writes, hasLength(2));
        await tester.pumpWidget(const SizedBox());
        expectSync(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('held pre-archive full list cannot resurrect archived rows', (
    tester,
  ) async {
    final server = _ArchiveServer();
    final oldPage = Completer<http.Response>();
    server.page = (offset, count) async => count == 2
        ? await oldPage.future
        : _page(
            offset == 0
                ? [
                    _row('chat-id', _title),
                    _row('other-id', 'Other conversation'),
                  ]
                : [],
          );
    await _mount(tester, server);
    final menu = _rowMenu(tester);
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    menu.onSelected!('archive');
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
    await tester.pump();
    expectSync(server.writes, hasLength(1));
    expectSync(server.reads, 1);
    oldPage.complete(
      _page([
        _row('chat-id', _title),
        _row('other-id', 'Other conversation'),
        {
          ..._row('archived-pin', 'Archived server pin', archived: true),
          'pinned': true,
        },
      ]),
    );
    await refresh;
    await tester.pumpAndSettle();
    expectSync(find.text(_title), findsNothing);
    expectSync(find.text('Archived server pin'), findsNothing);
    expectSync(find.text('Other conversation'), findsOneWidget);
    // Not a permanent device-only override: later server snapshots win.
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expectSync(find.text(_title), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expectSync(tester.takeException(), isNull);
  });

  testWidgets('held older page and archived pin backfill cannot undo archive', (
    tester,
  ) async {
    final server = _ArchiveServer();
    final oldPage = Completer<http.Response>();
    server.page = (offset, count) async => offset == 2
        ? await oldPage.future
        : _page(
            offset == 0
                ? [
                    _row('chat-id', _title),
                    _row('other-id', 'Other conversation'),
                  ]
                : [],
          );
    await _mount(tester, server);
    final menu = _rowMenu(tester);
    _startOlderPage(tester);
    await tester.pump();
    expectSync(server.pages, [0, 2]);
    menu.onSelected!('archive');
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
    await tester.pump();
    expectSync(server.writes, hasLength(1));
    oldPage.complete(
      _page([
        _row('chat-id', _title),
        _row('older', 'Older conversation'),
        {
          ..._row('archived-pin', 'Archived server pin', archived: true),
          'pinned': true,
        },
      ]),
    );
    await tester.pumpAndSettle();
    expectSync(find.text(_title), findsNothing);
    expectSync(find.text('Archived server pin'), findsNothing);
    expectSync(find.text('Older conversation'), findsOneWidget);
    expectSync(find.text('Other conversation'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expectSync(tester.takeException(), isNull);
  });

  testWidgets(
    'archived hits remain searchable when the ordinary list is empty',
    (tester) async {
      final server = _ArchiveServer()..archived = true;
      server.page = (_, count) async => _page([]);
      await _mount(tester, server, mode: SessionSearchMode.server);
      expectSync(find.byType(SearchBar), findsOneWidget);
      await _typeQuery(tester);
      await _choose(tester, 'Unarchive chat');
      await tester.pumpAndSettle();
      expectSync(server.writes, hasLength(1));
      expectSync(jsonDecode(server.writes.single.body), {'archived': false});
      expectSync(
        find.text('Rich search preview'),
        findsNothing,
        reason: 'search excerpt, not list preview, remains displayed',
      );
      expectSync(find.text('Initial matching excerpt'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expectSync(find.text(_title), findsOneWidget);
      expectSync(find.text('Rich search preview'), findsOneWidget);
      expectSync(find.textContaining('search-model'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('old ordinary read omitting an Unarchive retains the rich row', (
    tester,
  ) async {
    final server = _ArchiveServer()..archived = true;
    final oldList = Completer<http.Response>();
    server.page = (offset, count) async => count == 2
        ? await oldList.future
        : _page(offset == 0 ? [_row('other-id', 'Other conversation')] : []);
    await _mount(tester, server, mode: SessionSearchMode.server);
    final refreshList = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh;
    await _typeQuery(tester);
    final menu = _rowMenu(tester);
    final pending = refreshList();
    menu.onSelected!('unarchive');
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
    await tester.pump();
    expectSync(jsonDecode(server.writes.single.body), {'archived': false});
    oldList.complete(_page([_row('other-id', 'Other conversation')]));
    await pending;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expectSync(find.text(_title), findsOneWidget);
    expectSync(find.text('Rich search preview'), findsOneWidget);
    expectSync(find.textContaining('search-model'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an old failed search cannot erase a confirmed archived hit', (
    tester,
  ) async {
    final server = _ArchiveServer();
    final oldSearch = Completer<http.Response>();
    server.search = (count) async =>
        count == 2 ? await oldSearch.future : _hits(server.archived);
    await _mount(tester, server, mode: SessionSearchMode.server);
    await _typeQuery(tester);
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    await _choose(tester, 'Archive chat');
    oldSearch.complete(_json({'error': 'Obsolete failure'}, 500));
    await refresh;
    await tester.pumpAndSettle();
    expectSync(find.text(_title), findsOneWidget);
    expectSync(find.text('Initial matching excerpt'), findsOneWidget);
    await _openRowMenu(tester);
    expectSync(find.text('Unarchive chat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expectSync(tester.takeException(), isNull);
  });

  for (final failReadback in [false, true]) {
    testWidgets(
      'archive ${failReadback ? 'GET' : 'PATCH'} failure retains row and Retry works',
      (tester) async {
        final server = _ArchiveServer();
        server.patch = (request) async {
          expectSync(jsonDecode(request.body), {'archived': true});
          if (server.writes.length == 1) {
            return failReadback
                ? _saved(true)
                : _json({'error': 'Rejected'}, 500);
          }
          server.archived = true;
          return _saved(true);
        };
        await _mount(tester, server);
        await _choose(tester, 'Archive chat');
        await tester.pumpAndSettle();
        expectSync(find.text(_title), findsOneWidget);
        expectSync(
          find.textContaining('Could not update chat archive:'),
          findsOneWidget,
        );
        expectSync(tester.widget<ListTile>(_rowTile()).enabled, isTrue);
        expectSync(server.writes, hasLength(1));
        await tester.tap(find.text('Retry'));
        await tester.pump();
        await tester.pump(kThemeAnimationDuration);
        await tester.pumpAndSettle();
        expectSync(server.writes, hasLength(2));
        expectSync(find.text(_title), findsNothing);
        expectSync(find.text('Chat archived'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        expectSync(tester.takeException(), isNull);
      },
    );
  }

  for (final holdReadback in [false, true]) {
    testWidgets(
      'dispose during archive ${holdReadback ? 'GET' : 'PATCH'} is silent',
      (tester) async {
        final server = _ArchiveServer();
        final response = Completer<http.Response>();
        if (holdReadback) {
          server.read = (_) => response.future;
        } else {
          server.patch = (_) => response.future;
        }
        await _mount(tester, server);
        await _choose(tester, 'Archive chat');
        expectSync(server.writes, hasLength(1));
        await tester.pumpWidget(const SizedBox());
        server.archived = true;
        response.complete(_saved(true));
        await tester.pumpAndSettle();
        expectSync(tester.takeException(), isNull);
      },
    );
  }
}
