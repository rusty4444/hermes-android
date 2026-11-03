import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/session_archive_ledger.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _title = 'Reviewed archive conversation';
Session _row(
  String id, {
  String? root,
  bool archived = false,
  double started = 10,
}) => Session(
  id: id,
  title: _title,
  model: 'model',
  source: 'cli',
  messageCount: 2,
  isActive: false,
  preview: 'Rich conversation preview',
  startedAt: started,
  lastActive: started,
  lineageRootId: root,
  archived: archived,
);
Map<String, Object?> _jsonRow(bool archived) => {
  'id': 'chat',
  'title': _title,
  'model': 'model',
  'source': 'cli',
  'message_count': 2,
  'preview': 'Rich conversation preview',
  'started_at': DateTime.now().millisecondsSinceEpoch / 1000 - 100,
  'last_active': DateTime.now().millisecondsSinceEpoch / 1000 - 10,
  'archived': archived,
  'is_active': false,
};
http.Response _json(Object body) => http.Response(jsonEncode(body), 200);
http.Response _page(List<Map<String, Object?>> rows) =>
    _json({'data': rows, 'has_more': false});
Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: child,
);
Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _choose(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Chat actions').last);
  await _tick(tester);
  await tester.tap(find.text(action));
  await _tick(tester);
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(650, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

SavedConnection _connection(String id) => SavedConnection(
  id: id,
  label: 'Test connection',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'fixture-token',
  dashboardProxied: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  test('canonical rebinding retains the original verified alias', () {
    final original = _row('root-without-lineage');
    final canonical = original.withStoredId('stored-tip');
    expect(canonical.id, 'stored-tip');
    expect(canonical.isLocalDraft, isFalse);
    expect(canonical.lineageRootId, original.id);
    final ledger = SessionArchiveLedger();
    ledger.record(canonical, true);
    expect(ledger.apply([original], 0).single.archived, isTrue);
    ledger.record(canonical, false);
    expect(
      ledger.apply([original.withArchived(true)], 0).single.archived,
      isFalse,
    );
    expect(canonical.preview, original.preview);
    expect(canonical.messageCount, original.messageCount);
  });

  testWidgets('fresh empty archive wins when active authority fails', (
    tester,
  ) async {
    final key = GlobalKey<WorkspaceSessionsScreenState>();
    var loads = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: WorkspaceSessionsScreen(
            key: key,
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            onOpenSession: (_) {},
            load: () async => ++loads == 1
                ? WorkspaceSessionsData(
                    archivedSessions: [_row('chat', archived: true)],
                  )
                : const WorkspaceSessionsData(
                    sessionsKnown: false,
                    archivesKnown: true,
                  ),
          ),
        ),
      ),
    );
    await _tick(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await _tick(tester);
    expect(find.text(_title), findsOneWidget);
    await key.currentState!.refresh();
    await _tick(tester);
    expect(find.text(_title), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compression aliases render one newest-tip archive and navigation',
    (tester) async {
      Session? opened;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: WorkspaceSessionsScreen(
              title: 'Chats',
              view: WorkspaceSessionView.all,
              embedded: true,
              onOpenSession: (session) => opened = session,
              onArchive: (_, archived) async => archived,
              load: () async => WorkspaceSessionsData(
                sessions: [_row('tip-1', root: 'root')],
                archivedSessions: [
                  _row('tip-2', root: 'root', archived: true, started: 20),
                ],
              ),
            ),
          ),
        ),
      );
      await _tick(tester);
      expect(find.text(_title), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await _tick(tester);
      expect(find.byType(HermesCard), findsOneWidget);
      await tester.tap(find.byType(HermesCard));
      expect(opened!.id, 'tip-2');
      await _choose(tester, 'Unarchive chat');
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await _tick(tester);
      expect(find.byType(HermesCard), findsOneWidget);
      await tester.tap(find.byType(HermesCard));
      expect(opened!.id, 'tip-2');
      expect(opened!.archived, isFalse);
    },
  );

  for (final view in [
    WorkspaceSessionView.search,
    WorkspaceSessionView.unassigned,
  ]) {
    for (final aliased in [false, true]) {
      testWidgets(
        'standalone ${view.name} hides archived ${aliased ? 'lineage' : 'exact'} alias',
        (tester) async {
          await tester.pumpWidget(
            _app(
              Scaffold(
                body: WorkspaceSessionsScreen(
                  title: 'Standalone',
                  view: view,
                  onOpenSession: (_) => fail(
                    'An archived conversation must not be actionable here',
                  ),
                  load: () async => WorkspaceSessionsData(
                    sessions: [
                      _row(
                        aliased ? 'tip-1' : 'chat',
                        root: aliased ? 'root' : null,
                      ),
                    ],
                    archivedSessions: [
                      _row(
                        aliased ? 'tip-2' : 'chat',
                        root: aliased ? 'root' : null,
                        archived: true,
                        started: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await _tick(tester);
          expect(find.text(_title), findsNothing);
          expect(find.byType(HermesCard), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'standalone ${view.name} refreshes after a late chat archive commit',
      (tester) async {
        _viewport(tester);
        var archived = false;
        var activeReads = 0;
        var writes = 0;
        final gate = Completer<http.Response>();
        final started = tester.binding.clock.now();
        final active = MockClient((request) async {
          if (request.method == 'PATCH') {
            writes++;
            return gate.future;
          }
          if (request.url.path.endsWith('/chat')) {
            return _json({'session': _jsonRow(archived)});
          }
          activeReads++;
          return _page(
            (request.url.queryParameters['offset'] ?? '0') == '0' && !archived
                ? [_jsonRow(false)]
                : [],
          );
        });
        final archives = MockClient(
          (_) async => _json({
            'sessions': archived ? [_jsonRow(true)] : [],
            'total': archived ? 1 : 0,
          }),
        );
        await tester.pumpWidget(
          _app(
            WorkspaceScreen(
              connection: _connection('standalone-${view.name}'),
              testSessionsHttpClient: active,
              testArchivedSessionsHttpClient: archives,
              testChatApiClientFactory: () => ApiClient(
                baseUrl: 'http://fixture.invalid:8642',
                apiKey: 'fixture-token',
                httpClient: MockClient(
                  (request) async => request.url.path.endsWith('/messages')
                      ? _json({
                          'data': [
                            {'id': 1, 'role': 'user', 'content': 'Question'},
                            {'id': 2, 'role': 'assistant', 'content': 'Answer'},
                          ],
                        })
                      : _json({'session': _jsonRow(archived)}),
                ),
              ),
              turnSignalsLoader: (_) async => HomeTurnSignals.empty,
            ),
          ),
        );
        await _tick(tester);
        if (view == WorkspaceSessionView.search) {
          await tester.tap(find.byTooltip('Search all chats'));
        } else {
          await tester.tap(find.text('More').last);
          await _tick(tester);
          await tester.tap(find.text('Unassigned chats'));
        }
        await _tick(tester);
        await tester.tap(find.text(_title));
        await _tick(tester);
        await _choose(tester, 'Archive chat');
        expect(writes, 1);
        await tester.pageBack();
        await _tick(tester);
        expect(find.byType(ChatScreen), findsNothing);
        expect(
          find.text(_title),
          findsOneWidget,
          reason: 'the return refresh precedes the commit',
        );
        final readsAfterPop = activeReads;
        expect(
          tester.binding.clock.now().difference(started),
          lessThan(const Duration(seconds: 20)),
        );
        archived = true;
        gate.complete(_json({'session': _jsonRow(true)}));
        await _tick(tester);
        expect(
          activeReads,
          greaterThan(readsAfterPop),
          reason: 'the standalone owner receives a post-commit read',
        );
        expect(find.text(_title), findsNothing);
        expect(writes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final restoring in [true, false]) {
    testWidgets(
      'old shared Home scan preserves ${restoring ? 'restoration' : 'archive'} for new search',
      (tester) async {
        _viewport(tester);
        var archived = restoring;
        var fullReads = 0;
        final oldFull = Completer<http.Response>();
        final active = MockClient((request) async {
          if (request.method == 'PATCH') {
            archived = (jsonDecode(request.body) as Map)['archived'] as bool;
            return _json({'session': _jsonRow(archived)});
          }
          if (request.url.path.endsWith('/chat')) {
            return _json({'session': _jsonRow(archived)});
          }
          final offset = request.url.queryParameters['offset'] ?? '0';
          if (request.url.queryParameters['limit'] == '100' && offset == '0') {
            if (++fullReads == 1) return oldFull.future;
          }
          return _page(offset == '0' && !archived ? [_jsonRow(false)] : []);
        });
        final archives = MockClient(
          (_) async => _json({
            'sessions': archived ? [_jsonRow(true)] : [],
            'total': archived ? 1 : 0,
          }),
        );
        await tester.pumpWidget(
          _app(
            WorkspaceScreen(
              connection: _connection('shared-scan-$restoring'),
              testSessionsHttpClient: active,
              testArchivedSessionsHttpClient: archives,
              turnSignalsLoader: (_) async => HomeTurnSignals.empty,
            ),
          ),
        );
        await _tick(tester);
        expect(fullReads, 1);
        if (!restoring) {
          // Capture a second first page ahead of the original held full scan.
          await tester
              .state<WorkspaceSessionsScreenState>(
                find.byType(WorkspaceSessionsScreen),
              )
              .refresh();
          await _tick(tester);
        }
        await tester.tap(find.text('Chats').last);
        await _tick(tester);
        if (restoring) {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
          await _tick(tester);
        }
        expect(find.text(_title), findsOneWidget);
        await _choose(tester, restoring ? 'Unarchive chat' : 'Archive chat');
        expect(archived, !restoring);
        // Must settle well before the held HTTP timeout; otherwise the test
        // would no longer exercise a successful pre-mutation scan completion.
        oldFull.complete(_page(restoring ? [] : [_jsonRow(false)]));
        await _tick(tester);
        final readsBeforeSearch = fullReads;
        final messenger = ScaffoldMessenger.of(
          tester.element(find.byType(WorkspaceScreen)),
        );
        messenger.clearSnackBars();
        messenger.removeCurrentSnackBar();
        await _tick(tester);
        await tester.tap(find.text('Chats').last);
        await _tick(tester);
        await tester.tap(find.byTooltip('Search all chats'));
        await _tick(tester);
        expect(
          fullReads,
          greaterThan(readsBeforeSearch),
          reason: 'new subscriber starts a post-mutation physical scan',
        );
        expect(find.text(_title), restoring ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final competing in [false, true]) {
    testWidgets(
      'Workspace owns archive across ${competing ? 'competing chat action' : 'chat pop before commit'}',
      (tester) async {
        _viewport(tester);
        var archived = false;
        final gate = Completer<http.Response>();
        final writes = <bool>[];
        var held = false;
        final active = MockClient((request) async {
          if (request.method == 'PATCH') {
            final target =
                (jsonDecode(request.body) as Map)['archived'] as bool;
            writes.add(target);
            if (!competing && writes.length == 1) {
              held = true;
              return gate.future;
            }
            archived = target;
            return _json({'session': _jsonRow(archived)});
          }
          if (request.url.path.endsWith('/chat')) {
            if (competing && writes.length == 1 && !held) {
              held = true;
              return gate.future;
            }
            return _json({'session': _jsonRow(archived)});
          }
          return _page(
            (request.url.queryParameters['offset'] ?? '0') == '0' && !archived
                ? [_jsonRow(false)]
                : [],
          );
        });
        final chatRequests = <String>[];
        final archives = MockClient(
          (_) async => _json({
            'sessions': archived ? [_jsonRow(true)] : [],
            'total': archived ? 1 : 0,
          }),
        );
        await tester.pumpWidget(
          _app(
            WorkspaceScreen(
              connection: _connection('owned-$competing'),
              testSessionsHttpClient: active,
              testArchivedSessionsHttpClient: archives,
              testChatApiClientFactory: () => ApiClient(
                baseUrl: 'http://fixture.invalid:8642',
                apiKey: 'fixture-token',
                httpClient: MockClient((request) async {
                  chatRequests.add(request.method);
                  if (request.url.path.endsWith('/messages')) {
                    return _json({
                      'data': [
                        {'id': 1, 'role': 'user', 'content': 'Question'},
                        {'id': 2, 'role': 'assistant', 'content': 'Answer'},
                      ],
                    });
                  }
                  return _json({'session': _jsonRow(archived)});
                }),
              ),
              turnSignalsLoader: (_) async => HomeTurnSignals.empty,
            ),
          ),
        );
        await _tick(tester);
        await tester.tap(find.text('Chats').last);
        await _tick(tester);
        if (competing) await _choose(tester, 'Archive chat');
        await tester.tap(find.text(_title));
        await _tick(tester);
        expect(find.byType(ChatScreen), findsOneWidget);
        await _choose(tester, competing ? 'Unarchive chat' : 'Archive chat');
        expect(writes, [true]);
        expect(held, isTrue);
        if (competing) {
          expect(find.textContaining('already being updated'), findsOneWidget);
        }
        await tester.pageBack();
        await _tick(tester);
        archived = true;
        gate.complete(_json({'session': _jsonRow(true)}));
        await _tick(tester);
        expect(
          chatRequests,
          everyElement('GET'),
          reason: 'the disposed chat never owned the write transport',
        );
        expect(find.text(_title), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
        await _tick(tester);
        expect(find.text(_title), findsOneWidget);
        await _choose(tester, 'Unarchive chat');
        expect(writes, [true, false]);
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await _tick(tester);
        expect(find.text(_title), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
