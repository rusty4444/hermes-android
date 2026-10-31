import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/home_pane.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 23, 12);
Session _chat({bool archived = false}) => Session(
  id: 'stored-chat',
  title: 'A conversation worth keeping',
  model: 'test-model',
  source: 'cli',
  messageCount: 23,
  isActive: false,
  preview: 'The original preview',
  startedAt: _now.millisecondsSinceEpoch / 1000 - 100,
  lastActive: _now.millisecondsSinceEpoch / 1000 - 10,
  pinned: true,
  lineageRootId: 'root-chat',
  archived: archived,
);

WorkspaceSessionsData _data({bool archived = false}) => WorkspaceSessionsData(
  sessions: [_chat(archived: archived)],
  archivedSessions: archived ? [_chat(archived: true)] : const [],
  projectLabels: const {'stored-chat': 'A project'},
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: child,
);

// Bounded pumps must not drive held network futures through their timeouts.
Future<void> _tick(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Chat actions').last);
  await _tick(tester);
  await tester.tap(find.text(label));
  await _tick(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Workspace archive/unarchive fences old progress and final reads', (
    tester,
  ) async {
    final key = GlobalKey<WorkspaceSessionsScreenState>();
    final oldRead = Completer<WorkspaceSessionsData>();
    late void Function(WorkspaceSessionsData) oldProgress;
    final archive = Completer<bool>();
    final restore = Completer<bool>();
    final writes = <(String, bool)>[];
    final opened = <Session>[];
    var loads = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: WorkspaceSessionsScreen(
            key: key,
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            now: _now,
            load: () async => _data(),
            loadProgressively: (emit) {
              if (++loads == 1) {
                oldProgress = emit;
                emit(_data());
                return oldRead.future;
              }
              // A later physical read may reflect an archive from another device.
              return Future.value(_data(archived: true));
            },
            onOpenSession: opened.add,
            onRename: (session, title) async => title,
            onPromote: (_) async => 'Destination',
            onArchive: (session, archived) {
              writes.add((session.id, archived));
              return archived ? archive.future : restore.future;
            },
          ),
        ),
      ),
    );
    await _tick(tester);
    await _choose(tester, 'Archive chat');
    expect(writes, [('stored-chat', true)]);
    expect(find.text(_chat().title), findsOneWidget);
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byType(PopupMenuButton<String>).last,
    );
    // Duplicate dispatch while the first save is held cannot start another.
    menu.onSelected!('archive');
    await _tick(tester);
    expect(writes.length, 1);
    archive.complete(true);
    await _tick(tester);
    expect(find.text(_chat().title), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await _tick(tester);
    expect(find.text(_chat().title), findsOneWidget);
    oldProgress(_data());
    await _tick(tester);
    oldRead.complete(_data());
    await _tick(tester);
    expect(find.text(_chat().title), findsOneWidget);
    await tester.tap(find.byType(HermesCard));
    expect(opened.single.archived, isTrue);
    expect(opened.single.preview, _chat().preview);
    expect(opened.single.messageCount, 23);
    expect(opened.single.pinned, isTrue);
    expect(opened.single.lineageRootId, 'root-chat');
    await _choose(tester, 'Unarchive chat');
    expect(writes.last, ('stored-chat', false));
    restore.complete(false);
    await _tick(tester);
    expect(find.text(_chat().title), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await _tick(tester);
    expect(find.text(_chat().title), findsOneWidget);
    await key.currentState!.refresh();
    await _tick(tester);
    expect(loads, 2);
    expect(find.text(_chat().title), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await _tick(tester);
    expect(find.text(_chat().title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed archive keeps the row and Retry repeats the same intent',
    (tester) async {
      final attempts = <bool>[];
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: WorkspaceSessionsScreen(
              title: 'Unassigned chats',
              view: WorkspaceSessionView.unassigned,
              now: _now,
              load: () async => _data(),
              onOpenSession: (_) {},
              onArchive: (_, archived) async {
                attempts.add(archived);
                if (attempts.length == 1) throw StateError('Gateway offline');
                return archived;
              },
            ),
          ),
        ),
      );
      await _tick(tester);
      await _choose(tester, 'Archive chat');
      expect(find.text(_chat().title), findsOneWidget);
      expect(find.text(_chat().preview), findsOneWidget);
      expect(find.textContaining('Gateway offline'), findsOneWidget);
      expect(attempts, [true]);
      await tester.tap(find.text('Retry'));
      await _tick(tester);
      expect(attempts, [true, true]);
      expect(find.text(_chat().title), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing a list during archive does not emit after teardown', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var attempts = 0;
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            load: () async => _data(),
            onOpenSession: (_) {},
            onArchive: (_, archived) {
              attempts++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    await _tick(tester);
    await _choose(tester, 'Archive chat');
    expect(attempts, 1);
    await tester.pumpWidget(const SizedBox());
    pending.complete(true);
    await _tick(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home reconciles explicit archive and rejects its held old scan',
    (tester) async {
      final key = GlobalKey<HomePaneState>();
      final oldRead = Completer<List<Session>>();
      late void Function(List<Session>?) oldProgress;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: HomePane(
              key: key,
              clock: () => _now,
              attention: const {'stored-chat': 'Approval requested'},
              running: const {'stored-chat'},
              loadSessions: () async => [_chat()],
              loadProgressiveSessions: (emit) {
                oldProgress = emit;
                return oldRead.future;
              },
            ),
          ),
        ),
      );
      await _tick(tester);
      key.currentState!.reconcileArchive(_chat(), true);
      oldRead.complete([_chat()]);
      await _tick(tester);
      expect(find.text(_chat().title), findsNothing);
      oldProgress([_chat()]);
      await _tick(tester);
      expect(find.text(_chat().title), findsNothing);
      key.currentState!.reconcileArchive(_chat(), false);
      await _tick(tester);
      expect(find.text(_chat().title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Chats Archived restores an expired Quick Chat and clears its local archive',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      final store = QuickChatStore(preferences, connectionId: 'quick-restore');
      await store.record('stored-chat', expiresAt: DateTime(2000));
      final requests = <http.Request>[];
      final row = {
        'id': 'stored-chat',
        'title': _chat().title,
        'source': 'cli',
        'message_count': 2,
        'started_at': DateTime.now().millisecondsSinceEpoch / 1000 - 30,
        'archived': false,
      };
      final active = MockClient((request) async {
        requests.add(request);
        if (request.method == 'PATCH') {
          expect(jsonDecode(request.body), {'archived': false});
          return http.Response(jsonEncode({'session': row}), 200);
        }
        if (request.url.path.endsWith('/stored-chat')) {
          return http.Response(jsonEncode({'session': row}), 200);
        }
        return http.Response(
          jsonEncode({
            'data': (request.url.queryParameters['offset'] ?? '0') == '0'
                ? [row]
                : [],
            'has_more': false,
          }),
          200,
        );
      });
      final archives = MockClient(
        (_) async => http.Response('{"sessions":[],"total":0}', 200),
      );
      tester.view.physicalSize = const Size(650, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          WorkspaceScreen(
            connection: SavedConnection(
              id: 'quick-restore',
              label: 'Test',
              host: 'example.invalid',
              port: 8642,
              apiKey: 'fixture-token',
              dashboardProxied: true,
            ),
            testSessionsHttpClient: active,
            testArchivedSessionsHttpClient: archives,
            turnSignalsLoader: (_) async => HomeTurnSignals.empty,
          ),
        ),
      );
      await _tick(tester);
      await tester.tap(find.text('More').last);
      await _tick(tester);
      expect(find.text('Archived quick chats'), findsNothing);
      await tester.tap(find.text('Chats').last);
      await _tick(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await _tick(tester);
      expect(find.text(_chat().title), findsOneWidget);
      await _choose(tester, 'Unarchive chat');
      expect(requests.where((request) => request.method == 'PATCH').length, 1);
      expect(find.text(_chat().title), findsNothing);
      final reopened = QuickChatStore(
        preferences,
        connectionId: 'quick-restore',
      );
      expect(
        (await reopened.load()).statusFor('stored-chat', DateTime.now()),
        QuickChatStatus.promoted,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await _tick(tester);
      expect(find.text(_chat().title), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real Workspace wiring archives, reads back and restores a chat',
    (tester) async {
      var archived = false;
      var readBacks = 0;
      final writes = <bool>[];
      final chat = _chat();
      Map<String, Object?> row() => {
        'id': chat.id,
        'title': chat.title,
        'model': chat.model,
        'source': chat.source,
        'message_count': chat.messageCount,
        'preview': chat.preview,
        'started_at': chat.startedAt,
        'last_active': chat.lastActive,
        'pinned': true,
        'archived': archived,
        '_lineage_root_id': chat.lineageRootId,
      };
      final activeClient = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer fixture-token');
        if (request.method == 'PATCH') {
          expect(request.url.path, '/mobile/api/sessions/stored-chat');
          final body = jsonDecode(request.body) as Map;
          expect(body.keys, ['archived']);
          archived = body['archived'] as bool;
          writes.add(archived);
          return http.Response(jsonEncode({'session': row()}), 200);
        }
        if (request.url.path == '/mobile/api/sessions/stored-chat') {
          readBacks++;
          return http.Response(jsonEncode({'session': row()}), 200);
        }
        expect(request.url.path, '/mobile/api/sessions');
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        return http.Response(
          jsonEncode({
            // Stock repeats archived pins in the otherwise active list.
            'data': offset == 0 ? [row()] : [],
            'has_more': false,
          }),
          200,
        );
      });
      final archiveClient = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'sessions': archived ? [row()] : [],
            'total': archived ? 1 : 0,
          }),
          200,
        ),
      );
      tester.view.physicalSize = const Size(650, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          WorkspaceScreen(
            connection: SavedConnection(
              id: 'archive-integration',
              label: 'Test',
              host: 'example.invalid',
              port: 8642,
              apiKey: 'fixture-token',
              gatewayPrefix: '/mobile',
              dashboardProxied: true,
            ),
            testSessionsHttpClient: activeClient,
            testArchivedSessionsHttpClient: archiveClient,
            turnSignalsLoader: (_) async => HomeTurnSignals.empty,
          ),
        ),
      );
      await _tick(tester);
      await tester.tap(find.text('Chats').last);
      await _tick(tester);
      await _choose(tester, 'Archive chat');
      expect(writes, [true]);
      expect(readBacks, 1);
      expect(find.text(chat.title), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await _tick(tester);
      expect(find.text(chat.title), findsOneWidget);
      await _choose(tester, 'Unarchive chat');
      expect(writes, [true, false]);
      expect(readBacks, 2);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await _tick(tester);
      expect(find.text(chat.title), findsOneWidget);
      expect(find.text(chat.preview), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
