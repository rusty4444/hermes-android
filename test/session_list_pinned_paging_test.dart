// Review blocker #1: the stock gateway back-fills pinned sessions PAST the
// requested `limit` (api_server.py: list_sessions_rich include_pinned=True)
// and repeats those pins on later pages. A client that advances its offset
// by the RETURNED row count skips the window rows between the window and
// the back-fill, and a client that doesn't dedupe by id shows every pin
// once per page. This test drives both session-list loaders (the
// standalone SessionListScreen and Home's loader in WorkspaceScreen)
// against a fake that reproduces the stock paging semantics.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';


const _now = 1750000000.0;

Map<String, dynamic> _windowRow(int index) => {
  'id': 'w$index',
  'title': 'Window chat $index',
  'model': 'gpt-oss-20b',
  'source': 'gateway',
  'message_count': 2,
  'preview': 'hello',
  'started_at': _now - index,
  'last_active': _now - index,
};

/// A pinned row: newest activity so it sorts to the top of every rendered
/// list, and `pinned: true` so the stock back-fill semantics apply.
Map<String, dynamic> _pinnedRow(String id) => {
  'id': id,
  'title': 'Pinned chat',
  'model': 'gpt-oss-20b',
  'source': 'gateway',
  'message_count': 2,
  'preview': 'pinned preview',
  'started_at': _now + 1000,
  'last_active': _now + 1000,
  'pinned': true,
};

/// Fake of the stock `GET /api/sessions` paging contract:
/// - serves `limit` window rows for the requested offset,
/// - APPENDS the pinned rows beyond `limit` (back-fill),
/// - repeats the pins on EVERY page,
/// - `has_more` is decided by the window rows only (pins don't count):
///   `has_more = (non-pinned rows in the combined response) >= limit`.
///
/// Records every paged offset so the test can assert the client advanced
/// by the REQUESTED window rather than the returned row count.
class _PinnedBackfillClient extends http.BaseClient {
  _PinnedBackfillClient({
    required this.totalWindow,
    required this.pinnedIds,
    this.pinnedWindowIndexes = const {},
    this.pinnedWindowRanges = const [],
  });

  final int totalWindow;
  final List<String> pinnedIds;

  /// Window indices that are THEMSELVES pinned — the case the reviewer
  /// flagged: a pin that already sits inside the base window makes the
  /// non-pinned count fall below `limit`, so the server reports
  /// has_more=false even while rows exist past the offset.
  final Set<int> pinnedWindowIndexes;

  /// Inclusive [start, end] window-index ranges that are THEMSELVES
  /// pinned — the full reviewer reproduction: a later base window made
  /// ENTIRELY of pins contributes zero unseen ids while unseen non-pinned
  /// rows still sit at a further offset.
  final List<List<int>> pinnedWindowRanges;

  final List<String> requestedOffsets = [];

  bool _isPinnedWindowIndex(int i) =>
      pinnedWindowIndexes.contains(i) ||
      pinnedWindowRanges.any((r) => i >= r[0] && i <= r[1]);

  http.StreamedResponse _json(Map<String, dynamic> body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    if (uri.path.endsWith('/health')) {
      return _json({'status': 'ok'});
    }
    if (uri.path.endsWith('/api/sessions')) {
      final offsetParam = uri.queryParameters['offset'];
      if (offsetParam == null) {
        // Health-check auth confirmation: no paging params, answer empty.
        return _json({'object': 'list', 'data': [], 'has_more': false});
      }
      final offset = int.parse(offsetParam);
      requestedOffsets.add(offsetParam);
      final limit = int.tryParse(uri.queryParameters['limit'] ?? '') ?? 50;
      final windowRows = [
        for (var i = offset; i < offset + limit && i < totalWindow; i++)
          if (_isPinnedWindowIndex(i)) _pinnedRow('w$i') else _windowRow(i),
      ];
      // Back-fill: stock appends EVERY pinned row the window missed
      // (external pins AND pinned window rows outside the current
      // window), deduped against the window.
      final windowIds = windowRows.map((r) => r['id']).toSet();
      final allPinned = [
        ...pinnedIds.map(_pinnedRow),
        for (var i = 0; i < totalWindow; i++)
          if (_isPinnedWindowIndex(i)) _pinnedRow('w$i'),
      ];
      final seenBackfill = <String>{};
      final backfill = allPinned
          .where(
            (r) => !windowIds.contains(r['id']) && seenBackfill.add(r['id']!),
          )
          .toList();
      // Pins lead the payload so they always render in the viewport; the
      // stock gateway repeats them on every page.
      final rows = [...backfill, ...windowRows];
      // The stock computation: only non-pinned rows decide has_more
      // (api_server.py: windowed = sum(not pinned); has_more = windowed
      // >= limit). A pinned-in-window row drops the count below limit.
      final windowed = rows.where((r) => r['pinned'] != true).length;
      return _json({
        'object': 'list',
        'data': rows,
        'limit': limit,
        'offset': offset,
        'has_more': windowed >= limit,
      });
    }
    return _json({'error': 'unexpected request ${uri.path}'}, status: 404);
  }
}

Map<String, dynamic> _namedRow(
  String id,
  String title, {
  bool pinned = false,
}) => {
  'id': id,
  'title': title,
  'model': 'gpt-oss-20b',
  'source': 'gateway',
  'message_count': 2,
  'preview': title,
  'started_at': _now,
  'last_active': _now,
  if (pinned) 'pinned': true,
};

/// Deterministic refresh/load-more race: the first offset-2 page belongs to
/// the old generation and carries enough pins to corrupt the refreshed
/// exhaustion bound if it resumes after its paused preferences read.
class _StaleGenerationClient extends http.BaseClient {
  final List<String> requestedOffsets = [];
  int _zeroOffsetRequests = 0;
  int _offsetTwoRequests = 0;

  http.StreamedResponse _json(Map<String, dynamic> body) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        200,
        headers: {'content-type': 'application/json'},
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.endsWith('/api/sessions')) {
      return _json({'status': 'ok'});
    }
    final offsetParam = request.url.queryParameters['offset'];
    if (offsetParam == null) {
      return _json({'object': 'list', 'data': [], 'has_more': false});
    }
    requestedOffsets.add(offsetParam);
    final offset = int.parse(offsetParam);
    List<Map<String, dynamic>> rows;
    if (offset == 0) {
      _zeroOffsetRequests += 1;
      rows = _zeroOffsetRequests == 1
          ? [_namedRow('old-a', 'Old A'), _namedRow('old-b', 'Old B')]
          : [_namedRow('fresh-a', 'Fresh A'), _namedRow('fresh-b', 'Fresh B')];
    } else if (offset == 2) {
      _offsetTwoRequests += 1;
      rows = _offsetTwoRequests == 1
          ? [
              for (var i = 0; i < 6; i += 1)
                _namedRow('stale-pin-$i', 'Stale pin $i', pinned: true),
            ]
          : [];
    } else {
      rows = [];
    }
    return _json({
      'object': 'list',
      'data': rows,
      'limit': 2,
      'offset': offset,
      'has_more': rows.isNotEmpty,
    });
  }
}

SavedConnection _connection(String id) => SavedConnection(
  id: id,
  label: 'Paging fixture',
  host: 'paging.fixture',
  port: 8642,
  apiKey: 'fixture-key',
);

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SessionListScreen paging vs pinned back-fill', () {
    testWidgets('advances by the requested window and never duplicates pins', (
      tester,
    ) async {
      // 60 window rows, page size 50, two pins back-filled on every page.
      final fake = _PinnedBackfillClient(
        totalWindow: 60,
        pinnedIds: const ['pin-a', 'pin-b'],
      );
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: SessionListScreen(
            connection: _connection('paging-1'),
            turnApplicationController: controller,
            testHttpClient: fake,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First page rendered: pins on top, window rows behind them.
      expect(find.text('Pinned chat'), findsNWidgets(2));
      expect(find.text('Window chat 0'), findsOneWidget);

      final list = find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      );
      // scrollUntilVisible wants the Scrollable itself: ListView WRAPS it
      // (ListView -> Scrollable -> Viewport), so it is a descendant of the
      // ListView finder — find.byType(ListView) fails the Scrollable cast.
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );

      // Scroll to the bottom to trigger the load-more path.
      await tester.drag(list, const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -3000));
      await tester.pumpAndSettle();

      // The second page must be requested at the REQUESTED window offset
      // (50), not at 52 — advancing by the returned row count (50 window
      // + 2 back-filled pins) would skip 'Window chat 50' and 51. A
      // terminal no-progress request at offset 100 is expected: the
      // loader keeps paging until a page contributes zero new ids.
      expect(fake.requestedOffsets.first, '0');
      expect(fake.requestedOffsets, contains('50'));
      expect(
        fake.requestedOffsets.every((o) => int.parse(o) % 50 == 0),
        isTrue,
        reason:
            'offsets must advance by the requested window, never by '
            'the returned row count',
      );

      // Skip proof: the rows the old offset bug skipped exist in the
      // list — scrollUntilVisible only succeeds for rows actually built.
      await tester.scrollUntilVisible(
        find.text('Window chat 50'),
        500,
        scrollable: scrollable,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();
      expect(find.text('Window chat 50'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Window chat 59'),
        500,
        scrollable: scrollable,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();
      expect(find.text('Window chat 59'), findsOneWidget);
    });

    testWidgets(
      'a pin INSIDE the base window (has_more=false too early) does not '
      'stop pagination',
      (tester) async {
        // 60 window rows, page size 50. Window row 10 is itself pinned:
        // page 0's combined response carries 49 non-pinned rows, so the
        // stock has_more computation (windowed >= limit) reports FALSE
        // even though rows 50-59 still exist. A client that trusts
        // has_more stops after page 0 — truncating the list AND pruning
        // space assignments against an incomplete raw-id set.
        final fake = _PinnedBackfillClient(
          totalWindow: 60,
          pinnedIds: const ['pin-a'],
          pinnedWindowIndexes: const {10},
        );
        final controller = GatewayTurnApplicationController(
          sessionFactory: (_) => InertTurnApplicationSession(),
        );
        addTearDown(controller.close);

        await tester.pumpWidget(
          MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
            home: SessionListScreen(
              connection: _connection('paging-inwin'),
              turnApplicationController: controller,
              testHttpClient: fake,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sanity: a pinned row renders (viewport-clipped, so just
        // requires at least one "Pinned chat" on screen).
        expect(find.text('Pinned chat'), findsWidgets);

        final list = find.descendant(
          of: find.byType(RefreshIndicator),
          matching: find.byType(ListView),
        );
        final scrollable = find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        );

        // Scroll to the bottom to trigger the load-more path. With the
        // early-stop bug _hasMoreSessions would be false and no second
        // request would ever fire.
        await tester.drag(list, const Offset(0, -3000));
        await tester.pumpAndSettle();
        await tester.drag(list, const Offset(0, -3000));
        await tester.pumpAndSettle();

        expect(
          fake.requestedOffsets,
          contains('50'),
          reason:
              'has_more=false from a pinned-in-window row must not stop '
              'pagination',
        );

        // The rows past the falsely-terminated window are present.
        await tester.scrollUntilVisible(
          find.text('Window chat 55'),
          500,
          scrollable: scrollable,
          maxScrolls: 60,
        );
        await tester.pumpAndSettle();
        expect(find.text('Window chat 55'), findsOneWidget);
      },
    );

    testWidgets('a pin inside a later page (has_more=false too early) does not '
        'stop pagination', (tester) async {
      // Window row 55 is pinned. Page 50 therefore reports
      // has_more=false even though rows 100-119 still exist.
      final fake = _PinnedBackfillClient(
        totalWindow: 120,
        pinnedIds: const ['pin-a'],
        pinnedWindowIndexes: const {55},
      );
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(controller.close);

      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          home: SessionListScreen(
            connection: _connection('paging-inwin-later'),
            turnApplicationController: controller,
            testHttpClient: fake,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final list = find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(ListView),
      );
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );

      // Reach the bottom repeatedly so pages 50 and 100 can load.
      for (var i = 0; i < 5; i++) {
        await tester.drag(list, const Offset(0, -3000));
        await tester.pumpAndSettle();
      }

      expect(
        fake.requestedOffsets,
        contains('100'),
        reason:
            'has_more=false from a pin inside a later window must not '
            'stop pagination',
      );
      await tester.scrollUntilVisible(
        find.text('Window chat 119'),
        500,
        scrollable: scrollable,
        maxScrolls: 80,
      );
      await tester.pumpAndSettle();
      expect(find.text('Window chat 119'), findsOneWidget);
    });

    testWidgets(
      'a pin-ONLY base window does not stop pagination or delete assignments '
      '(reviewer reproduction)',
      (tester) async {
        // The reviewer's exact stock-SessionDB reproduction, at page size
        // 2: offset 0 -> s0,s1 (+ pins back-filled); offset 2 -> ONLY the
        // already-seen pinned s2,s3 (zero new ids, has_more=false) while
        // unseen s4,s5 still sit at offset 4. The old rule stopped at
        // offset 2 AND pruned space assignments against that partial set,
        // wiping s4's assignment as if the chat had been deleted.
        final fake = _PinnedBackfillClient(
          totalWindow: 6,
          pinnedIds: const [],
          pinnedWindowRanges: const [
            [2, 3],
          ],
        );
        // w4 is filed into a space. An assignment absent from this live
        // OFFSET scan must remain too: paging has no stable snapshot token,
        // so absence is not authoritative deletion evidence.
        final prefs = await SharedPreferences.getInstance();
        prefs.setString(
          'chat_spaces_v1_paging-pinonly',
          jsonEncode({
            'spaces': [
              {'id': 'sp1', 'name': 'Work', 'created_at': 1},
            ],
            'assignments': {'w4': 'sp1', 'gone': 'sp1'},
          }),
        );
        final controller = GatewayTurnApplicationController(
          sessionFactory: (_) => InertTurnApplicationSession(),
        );
        addTearDown(controller.close);

        await tester.pumpWidget(
          MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
            home: SessionListScreen(
              connection: _connection('paging-pinonly'),
              turnApplicationController: controller,
              testHttpClient: fake,
              testSessionPageSize: 2,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final list = find.descendant(
          of: find.byType(RefreshIndicator),
          matching: find.byType(ListView),
        );
        // Reach the bottom repeatedly so every window loads.
        for (var i = 0; i < 8; i++) {
          await tester.drag(list, const Offset(0, -3000));
          await tester.pumpAndSettle();
        }

        // Paging walked PAST the pin-only window at offset 2 to the
        // unseen rows at offset 4.
        expect(
          fake.requestedOffsets,
          contains('4'),
          reason: 'a zero-new pin-only window must not end pagination',
        );
        final scrollable = find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Window chat 5'),
          400,
          scrollable: scrollable,
          maxScrolls: 40,
        );
        await tester.pumpAndSettle();
        expect(find.text('Window chat 5'), findsOneWidget);

        // Both assignments survive. Explicit session deletion removes its
        // own assignment, but an exhausted live OFFSET scan cannot safely do
        // so because activity may move a row into an already-scanned prefix.
        final stored =
            jsonDecode(prefs.getString('chat_spaces_v1_paging-pinonly')!)
                as Map<String, dynamic>;
        final assignments = Map<String, dynamic>.from(
          stored['assignments'] as Map,
        );
        expect(assignments['w4'], 'sp1');
        expect(
          assignments['gone'],
          'sp1',
          reason: 'OFFSET scan absence is not deletion evidence',
        );
      },
    );
    testWidgets(
      'a stale load-more paused in preferences cannot mutate refreshed '
      'exhaustion state',
      (tester) async {
        final fake = _StaleGenerationClient();
        final prefs = await SharedPreferences.getInstance();
        final stalePreferences = Completer<SharedPreferences>();
        final stalePreferencesRequested = Completer<void>();
        var preferenceReads = 0;
        Future<SharedPreferences> loadPreferences() {
          preferenceReads += 1;
          if (preferenceReads == 2) {
            stalePreferencesRequested.complete();
            return stalePreferences.future;
          }
          return Future.value(prefs);
        }

        final controller = GatewayTurnApplicationController(
          sessionFactory: (_) => InertTurnApplicationSession(),
        );
        addTearDown(controller.close);
        tester.view.physicalSize = const Size(500, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
            home: SessionListScreen(
              connection: _connection('paging-generation'),
              turnApplicationController: controller,
              testHttpClient: fake,
              testSessionPageSize: 2,
              testPreferencesLoader: loadPreferences,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final list = find.descendant(
          of: find.byType(RefreshIndicator),
          matching: find.byType(ListView),
        );
        await tester.drag(list, const Offset(0, -1200));
        await tester.pump();
        await stalePreferencesRequested.future;
        expect(fake.requestedOffsets, ['0', '2']);

        // Refresh while the old offset-2 continuation is suspended inside
        // its preferences await. The refreshed generation must own all
        // accumulator and loading flags from this point onward.
        unawaited(
          tester
              .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
              .show(),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(fake.requestedOffsets, ['0', '2', '0']);
        expect(find.text('Fresh A'), findsWidgets);
        expect(find.text('Old A'), findsNothing);

        stalePreferences.complete(prefs);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('Stale pin 0'), findsNothing);

        // One empty offset-2 page is terminal for the refreshed no-pin scan.
        // If the stale page inflated _seenPinCount, the screen would request
        // offset 4 and beyond instead.
        await tester.drag(list, const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(fake.requestedOffsets, ['0', '2', '0', '2']);
        await tester.drag(list, const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(fake.requestedOffsets, ['0', '2', '0', '2']);
      },
    );
  });

  group('WorkspaceScreen Home loader paging vs pinned back-fill', () {
    testWidgets('advances by the requested window and never duplicates pins', (
      tester,
    ) async {
      // Home pages at 100; 120 window rows forces a second page.
      final fake = _PinnedBackfillClient(
        totalWindow: 120,
        pinnedIds: const ['pin-a'],
      );
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repository = ProjectsRepository(
        client: ProjectsGatewayClient((method, params) async {
          if (method == 'projects.list') {
            return {
              'jsonrpc': '2.0',
              'id': 1,
              'result': {'projects': const [], 'active_id': null},
            };
          }
          if (method == 'projects.tree') {
            return {
              'jsonrpc': '2.0',
              'id': 1,
              'result': {
                'projects': const [],
                'active_id': null,
                'scoped_session_ids': const [],
              },
            };
          }
          return {'jsonrpc': '2.0', 'id': 1, 'result': const {}};
        }),
        preferences: await SharedPreferences.getInstance(),
        connectionId: 'paging-2',
      );

      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceScreen(
            connection: _connection('paging-2'),
            repositoryFactory: (_) => repository,
            testSessionsHttpClient: fake,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the Chats browser over the same paged list.
      await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);

      // Second page requested at the window offset (100), not 101 —
      // advancing by the returned rows (100 window + 1 pin) would skip
      // 'Window chat 100'. The loader legitimately runs more than once
      // (Home refresh + Chats data), and a terminal no-progress probe at
      // offset 200 confirms the end, so assert every offset is a clean
      // window boundary and the real pages were read.
      expect(fake.requestedOffsets, contains('100'));
      expect(
        fake.requestedOffsets.every((o) => int.parse(o) % 100 == 0),
        isTrue,
        reason:
            'offsets must advance by the requested window, never by '
            'the returned row count',
      );

      final chatsScope = find.byType(WorkspaceSessionsScreen);
      // The Chats browser's ListView CLIPS: rows outside the viewport are
      // not in the widget tree at all, so every row assertion must scroll
      // the row into view first (scrollUntilVisible only succeeds for
      // rows actually built). scrollUntilVisible wants the Scrollable
      // ancestor, not the ListView child.
      // The pane also holds a horizontal chip SingleChildScrollView —
      // target only the vertical list Scrollable.
      final chatsScrollable = find.descendant(
        of: chatsScope,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.vertical,
        ),
      );

      // The pin repeated on page two appears exactly once (dedupe).
      await tester.scrollUntilVisible(
        find.descendant(of: chatsScope, matching: find.text('Pinned chat')),
        400,
        scrollable: chatsScrollable,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: chatsScope, matching: find.text('Pinned chat')),
        findsOneWidget,
      );

      // Rows past the first-page window boundary — the ones the old
      // offset-by-returned-count bug skipped — are present.
      await tester.scrollUntilVisible(
        find.descendant(of: chatsScope, matching: find.text('Window chat 100')),
        400,
        scrollable: chatsScrollable,
        maxScrolls: 80,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: chatsScope, matching: find.text('Window chat 100')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.descendant(of: chatsScope, matching: find.text('Window chat 119')),
        400,
        scrollable: chatsScrollable,
        maxScrolls: 80,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: chatsScope, matching: find.text('Window chat 119')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a pin INSIDE the base window (has_more=false too early) does not '
      'stop the Home loader',
      (tester) async {
        // Home pages at 100; 120 window rows. Window row 5 is itself
        // pinned: page 0's combined response carries 99 non-pinned rows,
        // so the stock has_more (windowed >= limit) reports FALSE even
        // though rows 100-119 exist. The loader must keep paging on the
        // new-id signal instead.
        final fake = _PinnedBackfillClient(
          totalWindow: 120,
          pinnedIds: const ['pin-a'],
          pinnedWindowIndexes: const {5},
        );
        tester.view.physicalSize = const Size(500, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repository = ProjectsRepository(
          client: ProjectsGatewayClient((method, params) async {
            if (method == 'projects.list') {
              return {
                'jsonrpc': '2.0',
                'id': 1,
                'result': {'projects': const [], 'active_id': null},
              };
            }
            if (method == 'projects.tree') {
              return {
                'jsonrpc': '2.0',
                'id': 1,
                'result': {
                  'projects': const [],
                  'active_id': null,
                  'scoped_session_ids': const [],
                },
              };
            }
            return {'jsonrpc': '2.0', 'id': 1, 'result': const {}};
          }),
          preferences: await SharedPreferences.getInstance(),
          connectionId: 'paging-inwin-home',
        );

        await tester.pumpWidget(
          MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
            theme: hermesTheme(Brightness.dark),
            home: WorkspaceScreen(
              connection: _connection('paging-inwin-home'),
              repositoryFactory: (_) => repository,
              testSessionsHttpClient: fake,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
        await tester.pumpAndSettle();
        expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);

        expect(
          fake.requestedOffsets.toSet(),
          contains('100'),
          reason:
              'has_more=false from a pinned-in-window row must not stop '
              'the Home loader',
        );

        final chatsScope = find.byType(WorkspaceSessionsScreen);
        final chatsScrollable = find.descendant(
          of: chatsScope,
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axis == Axis.vertical,
          ),
        );
        await tester.scrollUntilVisible(
          find.descendant(
            of: chatsScope,
            matching: find.text('Window chat 119'),
          ),
          400,
          scrollable: chatsScrollable,
          maxScrolls: 80,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: chatsScope,
            matching: find.text('Window chat 119'),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
