import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/session_search_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/inert_turn_application_session.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/utils/home_digest.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/core/services/session_browser_loader.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/core/utils/project_session_filter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<Map<String, dynamic>> _rows() => [
  {'id': 'empty', 'source': 'cron', 'message_count': 0},
  {
    'id': 'placeholder',
    'source': 'cron',
    'title': 'Untitled',
    'message_count': 0,
  },
  {'id': 'human', 'source': 'cli', 'message_count': 0},
  {'id': 'content', 'source': 'cron', 'message_count': 2},
  {'id': 'named', 'source': 'cron', 'title': 'Daily brief', 'message_count': 0},
  {
    'id': 'preview',
    'source': 'cron',
    'message_count': 0,
    'preview': 'Real work',
  },
  {'id': 'missing', 'source': 'cron'},
  {'id': 'null', 'source': 'cron', 'message_count': null},
  {'id': 'negative', 'source': 'cron', 'message_count': -1},
];

const _visible = [
  'human',
  'content',
  'named',
  'preview',
  'missing',
  'null',
  'negative',
];
List<Session> _sessions() => [
  for (final row in _rows())
    Session.fromJson({
      ...row,
      'started_at': 1750000000,
      'last_active': 1750000000,
      'archived': false,
    }),
];

void main() {
  test('only proven empty cron rows are shells', () {
    final sessions = _sessions();
    expect(
      sessions.where((s) => !s.isUntitledCronShell).map((s) => s.id),
      _visible,
    );
  });

  test('malformed counts remain unknown rather than empty', () {
    for (final count in [
      '0',
      0.0,
      false,
      {},
      [],
      double.nan,
      double.infinity,
    ]) {
      final session = Session.fromJson({
        'id': 'sparse',
        'source': 'cron',
        'message_count': count,
      });
      expect(session.isUntitledCronShell, isFalse, reason: 'count: $count');
    }
  });

  test('shell matching stays narrow across sources and titles', () {
    for (final source in ['', 'cli', 'gateway', 'kanban', 'oneshot']) {
      expect(
        Session.fromJson({
          'id': 'cron_job_20261031_123456',
          'source': source,
          'message_count': 0,
        }).isUntitledCronShell,
        isFalse,
      );
    }
    for (final title in ['', 'Untitled']) {
      expect(
        Session.fromJson({
          'id': 'shell',
          'source': 'cron',
          'title': title,
          'message_count': 0,
        }).isUntitledCronShell,
        isTrue,
      );
    }
    for (final title in ['untitled', ' Untitled ', 'Cron report']) {
      expect(
        Session.fromJson({
          'id': 'named',
          'source': 'cron',
          'title': title,
          'message_count': 0,
        }).isUntitledCronShell,
        isFalse,
      );
    }
  });

  testWidgets('hidden shell reappears when refresh proves content', (
    tester,
  ) async {
    var row = <String, dynamic>{
      'id': 'run',
      'source': 'cron',
      'message_count': 0,
    };
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WorkspaceSessionsScreen(
          title: 'Crons',
          kind: WorkspaceSessionKind.crons,
          view: WorkspaceSessionView.all,
          load: () async =>
              WorkspaceSessionsData(sessions: [Session.fromJson(row)]),
          onOpenSession: (session) => opened.add(session.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    row = {...row, 'message_count': 2, 'preview': 'Completed report'};
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Completed report'), findsOneWidget);
    await tester.tap(find.text('Completed report'));
    expect(opened, ['run']);
  });

  test(
    'modern source and archive scopes suppress shells after partitioning',
    () {
      for (final archived in [false, true]) {
        final sessions = _sessions()
            .map((s) => s.withArchived(archived))
            .toList();
        for (final kind in WorkspaceSessionKind.values) {
          final expected = kind == WorkspaceSessionKind.chats
              ? ['human']
              : _visible.where((id) => id != 'human').toList();
          for (final filter in WorkspaceChatsFilter.values) {
            expect(
              filterChats(
                sessions: sessions,
                filter: filter,
                kind: kind,
                now: DateTime.fromMillisecondsSinceEpoch(1750000000000),
              ).map((s) => s.id),
              (filter == WorkspaceChatsFilter.archived) == archived
                  ? expected
                  : [],
              reason: '$archived $kind $filter',
            );
          }
          for (final view in WorkspaceSessionView.values) {
            expect(
              filterWorkspaceSessions(
                sessions: sessions,
                view: view,
                kind: kind,
                archivedQuickChatIds: sessions.map((s) => s.id).toSet(),
              ).map((s) => s.id),
              view == WorkspaceSessionView.archivedQuick || !archived
                  ? expected
                  : [],
              reason: '$archived $kind $view',
            );
          }
        }
      }
      expect(
        filterChats(
          sessions: _sessions(),
          filter: WorkspaceChatsFilter.all,
          kind: WorkspaceSessionKind.crons,
          query: 'empty',
        ),
        isEmpty,
      );
      expect(
        filterWorkspaceSessions(
          sessions: _sessions(),
          view: WorkspaceSessionView.search,
          kind: WorkspaceSessionKind.crons,
          query: 'placeholder',
        ),
        isEmpty,
      );
    },
  );

  test('Home counts and project search do not resurrect shells', () {
    final sessions = _sessions();
    final digest = buildHomeDigest(
      sessions: sessions,
      now: DateTime.fromMillisecondsSinceEpoch(1750000000000),
      attention: {for (final s in sessions) s.id: 'Needs input'},
      sectionLimit: 20,
    );
    expect(digest.blockedCount, _visible.length);
    expect(
      digest.sections
          .expand((section) => section.items)
          .map((item) => item.session.id),
      _visible,
    );
    expect(filterProjectSessions(sessions, '').map((s) => s.id), _visible);
    expect(filterProjectSessions(sessions, 'empty'), isEmpty);
    expect(filterProjectSessions(sessions, 'real work').single.id, 'preview');
  });

  test(
    'transport retains sparse rows and full membership for non-UI consumers',
    () async {
      final api = ApiClient(
        baseUrl: 'http://localhost:8642',
        apiKey: 'test',
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'data': _rows()}), 200),
        ),
      );
      addTearDown(api.close);
      final sessions = await api.getSessions();
      expect(sessions.map((s) => s.id), _rows().map((row) => row['id']));
      expect(
        filterWorkspaceSessions(
          sessions: sessions,
          view: WorkspaceSessionView.all,
        ).map((s) => s.id),
        ['human'],
      );
    },
  );

  for (final embedded in [false, true]) {
    testWidgets(
      'actual browser renders retained content, not shells (embedded=$embedded)',
      (tester) async {
        // Unique models give every untitled row a distinct searchable label.
        final sessions = [
          for (final row in _rows())
            Session.fromJson({
              ...row,
              'model': 'model-${row['id']}',
              'started_at': 1750000000,
            }),
        ];
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: WorkspaceSessionsScreen(
                title: 'Crons',
                kind: WorkspaceSessionKind.crons,
                view: embedded
                    ? WorkspaceSessionView.all
                    : WorkspaceSessionView.search,
                embedded: embedded,
                load: () async => WorkspaceSessionsData(sessions: sessions),
                onOpenSession: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final id in ['empty', 'placeholder', ..._visible]) {
          await tester.enterText(
            find.byKey(kWorkspaceSessionSearchKey),
            'model-$id',
          );
          await tester.pumpAndSettle();
          expect(
            find.byIcon(Icons.chat_bubble_outline),
            _visible.contains(id) && id != 'human'
                ? findsOneWidget
                : findsNothing,
            reason: id,
          );
        }
      },
    );
  }

  test('all Session copies retain count and raw preview authority', () {
    for (final row in [
      {'id': 'unknown', 'source': 'cron'},
      {'id': 'shell', 'source': 'cron', 'message_count': 0},
      {
        'id': 'preview',
        'source': 'cron',
        'message_count': 0,
        'preview': AndroidPromptContext.suffix.trimLeft(),
      },
    ]) {
      final original = Session.fromJson(row);
      final copies = [
        original.withTitle('Untitled'),
        original.withArchived(true),
        original.withStoredId('stored'),
        original
            .withTitle('Untitled')
            .withArchived(true)
            .withStoredId('stored'),
      ];
      for (final copy in copies) {
        expect(copy.hasKnownMessageCount, original.hasKnownMessageCount);
        expect(copy.hasContentPreview, original.hasContentPreview);
        expect(copy.isUntitledCronShell, original.isUntitledCronShell);
      }
    }
    final note = Session.fromJson({
      'id': 'note',
      'source': 'cron',
      'message_count': 0,
      'preview': AndroidPromptContext.suffix.trimLeft(),
    });
    expect(note.preview, isEmpty);
    expect(
      note.isUntitledCronShell,
      isFalse,
      reason: 'presentation stripping cannot prove a raw row empty',
    );
  });

  for (final archived in [false, true]) {
    testWidgets(
      'Crons cached seed, held progress and scoped refresh (archive=$archived)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<Session> rows({bool content = false}) => [
          for (final row in [
            {'id': 'shell', 'source': 'cron', 'message_count': 0},
            {'id': 'unknown', 'source': 'cron'},
            for (var i = 0; i < 6; i++)
              {'id': 'real-$i', 'source': 'cron', 'message_count': 2},
          ])
            Session.fromJson({
              ...row,
              'archived': archived,
              'model': 'model-${row['id']}',
              'last_active': row['id'] == 'unknown' ? 1000 : 1,
              if (content && row['id'] == 'shell')
                'preview': 'Now real content',
            }),
        ];
        WorkspaceSessionsData data(
          List<Session> sessions, {
          bool partial = false,
        }) => WorkspaceSessionsData(
          sessions: archived ? const [] : sessions,
          archivedSessions: archived ? sessions : const [],
          isPartial: !archived && partial,
          archivedIsPartial: archived && partial,
        );
        final done = Completer<WorkspaceSessionsData>();
        late void Function(WorkspaceSessionsData) publish;
        final refreshed = Completer<WorkspaceSessionsData>();
        final refreshedArchive = Completer<List<Session>>();
        final key = GlobalKey<WorkspaceSessionsScreenState>();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: WorkspaceSessionsScreen(
                key: key,
                title: 'Crons',
                kind: WorkspaceSessionKind.crons,
                view: WorkspaceSessionView.all,
                embedded: true,
                initialData: data(rows(), partial: true),
                load: () async => data(rows()),
                loadProgressively: (onProgress) {
                  publish = onProgress;
                  return done.future;
                },
                reloadActive: (_) => refreshed.future,
                reloadArchives: (_) => refreshedArchive.future,
                onOpenSession: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        if (archived) {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
          await tester.pump();
        }
        expect(find.textContaining('model-shell'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        publish(data(rows(), partial: true));
        await tester.pump();
        expect(find.textContaining('model-shell'), findsNothing);
        expect(find.text('Untitled'), findsNWidgets(5));
        // Five matching rows, not five raw rows (the shell must not consume a slot).
        expect(find.byIcon(Icons.chat_bubble_outline), findsNWidgets(5));
        done.complete(data(rows()));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.chat_bubble_outline), findsNWidgets(7));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        var completed = false;
        final refresh = key.currentState!.refresh().then(
          (_) => completed = true,
        );
        await tester.pump();
        expect(completed, isFalse);
        expect(find.textContaining('model-shell'), findsNothing);
        if (archived) {
          refreshedArchive.complete(rows(content: true));
        } else {
          refreshed.complete(data(rows(content: true)));
        }
        await refresh;
        await tester.pumpAndSettle();
        expect(find.text('Now real content'), findsOneWidget);
        expect(find.byIcon(Icons.chat_bubble_outline), findsNWidgets(8));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'active paging retains all-shell windows and late progress replay',
    () async {
      final held = Completer<http.Response>();
      final preview = Completer<void>();
      final requests = <String>[];
      final shellRows = [
        for (var i = 0; i < 100; i++)
          {'id': 'shell-$i', 'source': 'cron', 'message_count': 0},
      ];
      final api = ApiClient(
        baseUrl: 'http://localhost:8642',
        apiKey: 'test',
        httpClient: MockClient((request) async {
          final q = request.url.queryParameters;
          requests.add('${q['limit']}:${q['offset']}');
          final rows = q['limit'] == '5'
              ? shellRows.take(5).toList()
              : q['offset'] == '0'
              ? shellRows
              : q['offset'] == '100'
              ? null
              : [];
          if (rows == null) return held.future;
          return http.Response(
            jsonEncode({'data': rows, 'has_more': false}),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final loader = SessionBrowserLoader(api: api, loadPins: () async => []);
      addTearDown(loader.close);
      final first = loader.load(
        onProgress: (rows) {
          if (rows.length == 100 && !preview.isCompleted) preview.complete();
        },
      );
      await preview.future;
      final replay = <List<Session>>[];
      final second = loader.load(onProgress: replay.add);
      expect(replay.single, hasLength(100));
      expect(
        filterChats(
          sessions: replay.single,
          filter: WorkspaceChatsFilter.all,
          kind: WorkspaceSessionKind.crons,
        ),
        isEmpty,
      );
      held.complete(
        http.Response(
          jsonEncode({
            'data': [
              {'id': 'unknown', 'source': 'cron'},
              {'id': 'real', 'source': 'cron', 'message_count': 2},
            ],
          }),
          200,
        ),
      );
      final result = await first;
      expect(await second, hasLength(102));
      expect(result, hasLength(102));
      expect(requests, ['5:0', '100:0', '100:100', '100:200']);
      expect(
        filterChats(
          sessions: result,
          filter: WorkspaceChatsFilter.all,
          kind: WorkspaceSessionKind.crons,
        ).map((s) => s.id),
        ['unknown', 'real'],
      );
    },
  );

  test(
    'dashboard archived paging keeps shell membership and raw totals',
    () async {
      final offsets = <int>[];
      final client = DashboardClient(
        host: 'localhost',
        port: 9119,
        proxied: true,
        httpClient: MockClient((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          final limit = int.parse(request.url.queryParameters['limit']!);
          offsets.add(offset);
          return http.Response(
            jsonEncode({
              'sessions': [
                for (var i = offset; i < offset + limit && i < 107; i++)
                  {
                    'id': 'archive-$i',
                    'source': 'cron',
                    'archived': true,
                    'message_count': i < 105 ? 0 : 2,
                  },
              ],
              'total': 107,
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final progress = <List<Session>>[];
      final rows = await client.getArchivedSessions(
        firstPageSize: 5,
        onProgress: progress.add,
      );
      expect(rows, hasLength(107));
      expect(progress.first, hasLength(5));
      expect(offsets, [0, 5, 105, 205]);
      expect(
        filterChats(
          sessions: rows,
          filter: WorkspaceChatsFilter.archived,
          kind: WorkspaceSessionKind.crons,
        ).map((s) => s.id),
        ['archive-105', 'archive-106'],
      );
    },
  );

  testWidgets(
    'classic refresh preserves sparse rows and full-text content evidence',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final connection = SavedConnection(
        id: 'cron-classic',
        label: 'Fixture',
        host: 'fixture',
        port: 8642,
        apiKey: 'test',
        dashboardProxied: true,
      );
      final prefs = await SessionSearchPreferences.open();
      await prefs.saveMode(
        connectionIdentity: '${connection.baseUrl}||',
        mode: SessionSearchMode.server,
      );
      var content = false;
      final client = MockClient((request) async {
        if (request.url.path == '/health') return http.Response('{}', 200);
        if (request.url.path == '/api/sessions/search') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 'snippet',
                  'source': 'cron',
                  'message_count': 0,
                  'snippet': 'Real transcript evidence',
                },
                {'id': 'empty-hit', 'source': 'cron', 'message_count': 0},
              ],
            }),
            200,
          );
        }
        if (request.url.path == '/api/sessions') {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'shell',
                  'source': 'cron',
                  'message_count': 0,
                  if (content) 'preview': 'Shell now contains a report',
                },
                {'id': 'unknown', 'source': 'cron', 'model': 'uncertain-model'},
              ],
              'has_more': false,
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      addTearDown(client.close);
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SessionListScreen(
            connection: connection,
            turnApplicationController: controller,
            testHttpClient: client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Untitled'), findsOneWidget);
      expect(find.textContaining('uncertain-model'), findsOneWidget);
      content = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('Untitled'), findsNWidgets(2));
      expect(find.text('Shell now contains a report'), findsOneWidget);
      await tester.enterText(find.byType(SearchBar), 'transcript');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Real transcript evidence'), findsOneWidget);
      expect(find.text('Untitled'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
