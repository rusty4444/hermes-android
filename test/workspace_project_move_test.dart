import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/new_chat_sheet.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_test_utils.dart';

const _filed = Session(
  id: 'stored-filed',
  title: 'Filed title',
  model: 'model',
  source: 'cli',
  messageCount: 42,
  isActive: false,
  preview: 'Preserved preview',
  startedAt: 1750000000,
  pinned: true,
);
const _loose = Session(
  id: 'stored-loose',
  title: 'Loose title',
  model: 'model',
  source: 'cli',
  messageCount: 9,
  isActive: false,
  preview: 'Loose preview',
  startedAt: 1750000000,
);

class _Gateway {
  final owners = <String, String>{_filed.id: 'a'};
  final calls = <({String method, Map<String, dynamic> params})>[];
  Completer<Map<String, dynamic>>? heldTree;
  Completer<Map<String, dynamic>>? heldProject;
  Completer<void>? heldMove;
  bool failMove = false;
  bool failTree = false;
  List<String> projectIds = ['a', 'b', 'archived', 'folderless'];
  List<Map<String, dynamic>> get projects => [
    for (final id in projectIds)
      {
        'id': id,
        'slug': id,
        'name': 'Project $id',
        'archived': id == 'archived',
        if (id != 'folderless') 'primary_path': '/srv/$id',
        'folders': <Object>[],
      },
  ];
  Map<String, dynamic> tree() => {
    'projects': [
      for (final project in projects)
        {
          'id': project['id'],
          'label': project['name'],
          'sessionIds': [
            for (final entry in owners.entries)
              if (entry.value == project['id']) entry.key,
          ],
          'sessionCount': owners.values
              .where((id) => id == project['id'])
              .length,
        },
    ],
  };
  Map<String, dynamic> ok(Map<String, dynamic> data) => {
    'jsonrpc': '2.0',
    'id': 1,
    'result': data,
  };
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add((method: method, params: Map.of(params)));
    switch (method) {
      case 'projects.list':
        return ok({'projects': projects});
      case 'projects.tree':
        final held = heldTree;
        heldTree = null;
        if (held != null) return held.future;
        if (failTree) throw StateError('metadata offline');
        return ok(tree());
      case 'session.workspace.move':
        await heldMove?.future;
        if (failMove) throw StateError('move offline');
        owners[params['session_key'] as String] = (params['cwd'] as String)
            .split('/')
            .last;
        return ok({'ok': true});
      case 'projects.project_sessions':
        final held = heldProject;
        heldProject = null;
        if (held != null) return held.future;
        final id = params['project_id'];
        return ok({
          'project': {
            'id': id,
            'label': 'Project $id',
            'previewSessions': [
              for (final chat in [_filed, _loose])
                if (owners[chat.id] == id)
                  {
                    'id': chat.id,
                    'title': chat.title,
                    'started_at': chat.startedAt,
                    'message_count': chat.messageCount,
                  },
            ],
          },
        });
      default:
        throw StateError('Unexpected RPC $method');
    }
  }

  Iterable<Map<String, dynamic>> get moves => calls
      .where((call) => call.method == 'session.workspace.move')
      .map((call) => call.params);
}

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(HermesCard));

Future<void> _openMove(
  WidgetTester tester,
  String title,
  AppLocalizations l10n, {
  bool loading = false,
}) async {
  await tester.tap(
    find.descendant(
      of: _row(title),
      matching: find.byTooltip(l10n.chat_actions),
    ),
  );
  if (loading) {
    // Do not consume the held metadata response's timeout via an animated
    // progressive loading bar while the move menu is opening.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  } else {
    await tester.pumpAndSettle();
  }
  expect(find.text(l10n.rename), findsOneWidget);
  expect(find.text(l10n.unpin_on_this_device), findsOneWidget);
  await tester.tap(find.text(l10n.move_to_project));
  await tester.pump();
  await tester.pump(kThemeAnimationDuration);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late AppLocalizations l10n;
  late _Gateway gateway;
  late ProjectsRepository repository;
  late SharedPreferences preferences;
  setUpAll(() async => l10n = await loadTestL10n());
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    gateway = _Gateway();
    repository = ProjectsRepository(
      client: ProjectsGatewayClient(gateway.call),
      preferences: preferences,
      connectionId: 'moves',
    );
    await repository.refresh();
    await LocalChatPinStore(
      preferences,
      connectionId: 'moves',
    ).setPinned(_filed.id, pinned: true);
    await LocalChatPinStore(
      preferences,
      connectionId: 'moves',
    ).setPinned(_loose.id, pinned: true);
  });
  tearDown(() async => repository.close());

  Future<void> pumpWorkspace(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceScreen(
          connection: SavedConnection(
            id: 'moves',
            label: 'Test',
            host: '',
            port: 8642,
            apiKey: 'test',
          ),
          repositoryFactory: (_) => repository,
          sessionsLoader: () async => [_filed, _loose],
          turnSignalsLoader: (_) async => HomeTurnSignals.empty,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.chats).last);
    await tester.pumpAndSettle();
  }

  for (final chat in [_filed, _loose]) {
    testWidgets('All menu moves ${chat.id} persistently and keeps row metadata', (
      tester,
    ) async {
      await pumpWorkspace(tester);
      // Populate both caches before the move; revisit must fetch fresh membership.
      await repository.projectSessions('a');
      await repository.projectSessions('b');
      await _openMove(tester, chat.title, l10n);
      expect(find.byType(ProjectPickerSheet), findsOneWidget);
      expect(gateway.moves, isEmpty);
      final picker = find.byType(ProjectPickerSheet);
      if (chat == _filed) {
        expect(
          find.descendant(of: picker, matching: find.text('Project a')),
          findsNothing,
        );
      }
      expect(
        find.descendant(of: picker, matching: find.text('Project archived')),
        findsNothing,
      );
      final folderless = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Project folderless'),
      );
      expect(folderless.enabled, isFalse);
      expect(
        find.text(l10n.this_project_has_no_folder_to_open_the_chat_in),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ListTile, 'Project folderless'));
      await tester.pump();
      expect(gateway.moves, isEmpty);
      expect(find.byType(ProjectPickerSheet), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Project b'));
      await tester.pumpAndSettle();
      expect(gateway.moves.toList(), [
        {'session_key': chat.id, 'cwd': '/srv/b'},
      ]);
      expect(
        gateway.calls.any((call) => call.method == 'projects.assign_session'),
        isFalse,
      );
      expect(
        find.descendant(of: _row(chat.title), matching: find.text('Project b')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row(chat.title),
          matching: find.text(chat.preview),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row(chat.title),
          matching: find.byIcon(Icons.push_pin),
        ),
        findsOneWidget,
      );
      expect(
        (await LocalChatPinStore(preferences, connectionId: 'moves').load()),
        contains(chat.id),
      );
      expect(
        (await repository.projectSessions('b')).sessions.map((s) => s.id),
        contains(chat.id),
      );
      expect(
        (await repository.projectSessions('a')).sessions.map((s) => s.id),
        isNot(contains(chat.id)),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.unassigned));
      await tester.pumpAndSettle();
      expect(find.text(chat.title), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.filter_all));
      await tester.pumpAndSettle();
      expect(find.text(chat.title), findsOneWidget);
      // A new screen instance reads durable ownership from the fake server.
      await tester.pumpWidget(const SizedBox());
      await pumpWorkspace(tester);
      expect(
        find.descendant(of: _row(chat.title), matching: find.text('Project b')),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'cancel, failed move and retry leave ownership and Quick retention honest',
    (tester) async {
      final store = QuickChatStore(preferences, connectionId: 'moves');
      await store.record(_loose.id, expiresAt: DateTime(2020));
      await pumpWorkspace(tester);
      await _openMove(tester, _loose.title, l10n);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(gateway.moves, isEmpty);
      expect((await store.load()).isQuick(_loose.id), isTrue);
      expect(gateway.owners[_loose.id], isNull);
      gateway.failMove = true;
      await _openMove(tester, _loose.title, l10n);
      await tester.tap(find.widgetWithText(ListTile, 'Project b'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(l10n.couldn_t_move_conversation),
        findsOneWidget,
      );
      expect(gateway.owners[_loose.id], isNull);
      expect((await store.load()).isQuick(_loose.id), isTrue);
      gateway.failMove = false;
      await tester.tap(find.text(l10n.retry));
      await tester.pump();
      await tester.pump(kThemeAnimationDuration);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.widgetWithText(ListTile, 'Project b'));
      await tester.pumpAndSettle();
      expect(gateway.owners[_loose.id], 'b');
      expect((await store.load()).isQuick(_loose.id), isFalse);
      expect(gateway.moves, hasLength(2));
    },
  );

  testWidgets('one eligible destination still requires an explicit choice', (
    tester,
  ) async {
    gateway.projectIds = ['a', 'b'];
    await pumpWorkspace(tester);
    await _openMove(tester, _filed.title, l10n);
    expect(find.byType(ProjectPickerSheet), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Project a'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Project b'), findsOneWidget);
    expect(gateway.moves, isEmpty);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(gateway.owners[_filed.id], 'a');
    expect(gateway.moves, isEmpty);
  });

  testWidgets('picker and remote write share one flight per chat', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    final button = tester.widget<PopupMenuButton<String>>(
      find.descendant(
        of: _row(_filed.title),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await _openMove(tester, _filed.title, l10n);
    final before = gateway.calls.length;
    button.onSelected!('move');
    await tester.pump(kThemeAnimationDuration);
    expect(find.byType(ProjectPickerSheet), findsOneWidget);
    expect(gateway.calls, hasLength(before));
    final held = Completer<void>();
    gateway.heldMove = held;
    await tester.tap(find.widgetWithText(ListTile, 'Project b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    button.onSelected!('move');
    await tester.pump(kThemeAnimationDuration);
    expect(gateway.moves, hasLength(1));
    expect(gateway.owners[_filed.id], 'a');
    held.complete();
    await tester.pumpAndSettle();
    expect(gateway.moves, hasLength(1));
    expect(gateway.owners[_filed.id], 'b');
  });

  testWidgets('concurrent moves preserve both Quick Chat promotions', (
    tester,
  ) async {
    final store = QuickChatStore(preferences, connectionId: 'moves');
    for (final chat in [_filed, _loose]) {
      await store.record(chat.id, expiresAt: DateTime(2099));
    }
    final held = Completer<void>();
    gateway.heldMove = held;
    await pumpWorkspace(tester);
    await _openMove(tester, _filed.title, l10n);
    await tester.tap(find.widgetWithText(ListTile, 'Project b'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Drive the other row while the first RPC is pending. Its spinner must
    // not make pumpAndSettle wait forever while opening the second popup.
    final otherMenu = tester.widget<PopupMenuButton<String>>(
      find.descendant(
        of: _row(_loose.title),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    otherMenu.onSelected!('move');
    await tester.pump(kThemeAnimationDuration);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.widgetWithText(ListTile, 'Project b'));
    await tester.pump();
    expect(gateway.moves, hasLength(2));
    expect((await store.load()).promoted, isEmpty);
    held.complete();
    await tester.pumpAndSettle();
    expect((await store.load()).promoted, containsAll([_filed.id, _loose.id]));
    expect(gateway.owners, {_filed.id: 'b', _loose.id: 'b'});
    expect(
      find.descendant(of: _row(_filed.title), matching: find.text('Project b')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _row(_loose.title), matching: find.text('Project b')),
      findsOneWidget,
    );
  });

  testWidgets(
    'old overview response cannot restore source ownership after move',
    (tester) async {
      await pumpWorkspace(tester);
      final pending = Completer<Map<String, dynamic>>();
      final staleTree = gateway.ok(gateway.tree());
      gateway.heldTree = pending;
      final state = tester.state<WorkspaceSessionsScreenState>(
        find.byType(WorkspaceSessionsScreen),
      );
      final refresh = state.refresh();
      await tester.pump();
      await _openMove(tester, _filed.title, l10n, loading: true);
      await tester.tap(find.widgetWithText(ListTile, 'Project b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      pending.complete(staleTree);
      await refresh;
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _row(_filed.title),
          matching: find.text('Project b'),
        ),
        findsOneWidget,
      );
      expect((await repository.overview()).sessionProjects[_filed.id], 'b');
      await tester.tap(find.widgetWithText(ChoiceChip, l10n.unassigned));
      await tester.pumpAndSettle();
      expect(find.text(_filed.title), findsNothing);
      expect(find.text(_loose.title), findsOneWidget);
    },
  );

  testWidgets('standalone Search move also refreshes retained embedded Chats', (
    tester,
  ) async {
    await pumpWorkspace(tester);
    await tester.tap(find.text(l10n.chats).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.search_all_chats));
    await tester.pumpAndSettle();
    await _openMove(tester, _filed.title, l10n);
    await tester.tap(find.widgetWithText(ListTile, 'Project b'));
    await tester.pumpAndSettle();
    expect(gateway.owners[_filed.id], 'b');
    expect(
      find.descendant(of: _row(_filed.title), matching: find.text('Project b')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.chats).last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _row(_filed.title), matching: find.text('Project b')),
      findsOneWidget,
    );
  });

  testWidgets(
    'leaving standalone view during destination lookup never opens a late picker',
    (tester) async {
      await pumpWorkspace(tester);
      await tester.tap(find.text(l10n.chats).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.search_all_chats));
      await tester.pumpAndSettle();
      final held = Completer<Map<String, dynamic>>();
      gateway.heldTree = held;
      await _openMove(tester, _filed.title, l10n);
      expect(find.byType(ProjectPickerSheet), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      held.complete(gateway.ok(gateway.tree()));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectPickerSheet), findsNothing);
      expect(gateway.moves, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source and destination Project counts and drill-ins refresh on revisit',
    (tester) async {
      await pumpWorkspace(tester);
      await tester.tap(find.text(l10n.nav_projects).last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _row('Project a'),
          matching: find.text(l10n.chats_count(1)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Project b'),
          matching: find.text(l10n.chats_count(0)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Project a'));
      await tester.pumpAndSettle();
      expect(find.text(_filed.title), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.chats).last);
      await tester.pumpAndSettle();
      await _openMove(tester, _filed.title, l10n);
      await tester.tap(find.widgetWithText(ListTile, 'Project b'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.nav_projects).last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _row('Project a'),
          matching: find.text(l10n.chats_count(0)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row('Project b'),
          matching: find.text(l10n.chats_count(1)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Project a'));
      await tester.pumpAndSettle();
      expect(find.text(_filed.title), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project b'));
      await tester.pumpAndSettle();
      expect(find.text(_filed.title), findsOneWidget);
    },
  );

  for (final fails in [false, true]) {
    test(
      'pending Project read ${fails ? 'failure' : 'success'} cannot repopulate pre-move cache',
      () async {
        final held = Completer<Map<String, dynamic>>();
        gateway.heldProject = held;
        final oldRead = repository.projectSessions('a');
        await repository.moveSessionToProject(_filed.id, 'b');
        final fresh = await repository.projectSessions('a');
        expect(fresh.sessions, isEmpty);
        if (fails) {
          held.completeError(StateError('old offline response'));
        } else {
          held.complete(
            gateway.ok({
              'project': {
                'id': 'a',
                'label': 'Project a',
                'previewSessions': [
                  {
                    'id': _filed.id,
                    'title': _filed.title,
                    'started_at': _filed.startedAt,
                  },
                ],
              },
            }),
          );
        }
        expect((await oldRead).sessions, isEmpty);
        expect((await repository.projectSessions('a')).sessions, isEmpty);
        expect(
          (await repository.projectSessions('b')).sessions.single.id,
          _filed.id,
        );
      },
    );
  }

  testWidgets(
    'metadata refresh failure cannot turn a committed move into failure',
    (tester) async {
      await pumpWorkspace(tester);
      await _openMove(tester, _filed.title, l10n);
      gateway.failTree = true;
      await tester.tap(find.widgetWithText(ListTile, 'Project b'));
      await tester.pumpAndSettle();
      expect(gateway.owners[_filed.id], 'b');
      expect(
        find.descendant(
          of: _row(_filed.title),
          matching: find.text('Project b'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(l10n.couldn_t_move_conversation),
        findsNothing,
      );
    },
  );
}
