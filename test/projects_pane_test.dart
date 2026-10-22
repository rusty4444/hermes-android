import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:hermes_android/core/widgets/projects_pane.dart';
import 'package:hermes_android/core/widgets/space_migration_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Map<String, dynamic> _projectJson({
  required String id,
  required String name,
  bool archived = false,
  List<Map<String, dynamic>>? folders,
}) => {
  'id': id,
  'slug': name.toLowerCase().replaceAll(' ', '-'),
  'name': name,
  'archived': archived,
  'created_at': 1750000000,
  'folders':
      folders ??
      [
        {
          'path': '/home/test/${name.toLowerCase().replaceAll(' ', '-')}',
          'label': name,
          'is_primary': true,
          'added_at': 1750000001,
        },
      ],
};

class _FakeGateway {
  List<Map<String, dynamic>> projects;
  String? activeId;
  Object? failNext;
  int listCalls = 0;
  final List<Map<String, dynamic>> assignments = [];
  final Map<String, int> counts;
  final List<Completer<void>> treeGates = [];
  int treeCalls = 0;

  /// When set, `projects.list` waits on this before answering, so a test can
  /// observe the pane's loading state deterministically.
  Completer<void>? gate;

  _FakeGateway({
    List<Map<String, dynamic>>? projects,
    this.activeId,
    this.counts = const {},
  }) : projects = projects ?? [];

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    switch (method) {
      case 'projects.list':
        final pending = gate;
        if (pending != null) await pending.future;
        listCalls++;
        return _ok({'projects': projects, 'active_id': activeId});
      case 'projects.tree':
        treeCalls++;
        final countSnapshot = Map<String, int>.of(counts);
        if (treeGates.isNotEmpty) await treeGates.removeAt(0).future;
        return _ok({
          'projects': [
            for (final project in projects)
              if (project['archived'] != true)
                {
                  'id': project['id'],
                  'label': project['name'],
                  'sessionCount': countSnapshot[project['id']] ?? 0,
                  'lastActive': 1750000100,
                  'previewSessions': const [],
                  'repos': const [],
                },
          ],
          'active_id': activeId,
          'scoped_session_ids': const [],
        });
      case 'projects.create':
        final created = _projectJson(
          id: 'srv-${projects.length + 1}',
          name: params['name'] as String,
        );
        projects = [...projects, created];
        return _ok({'project': created});
      case 'projects.update':
        final id = params['id'] as String;
        final name = params['name'] as String;
        projects = [
          for (final project in projects)
            if (project['id'] == id) {...project, 'name': name} else project,
        ];
        return _ok({'project': projects.firstWhere((p) => p['id'] == id)});
      case 'projects.archive':
        final id = params['id'] as String;
        final restore = params['restore'] == true;
        projects = [
          for (final project in projects)
            if (project['id'] == id)
              {...project, 'archived': !restore}
            else
              project,
        ];
        return _ok({'projects': projects, 'active_id': activeId});
      case 'session.workspace.move':
        assignments.add(Map<String, dynamic>.from(params));
        return _ok(const {'ok': true});
      case 'projects.set_active':
        activeId = params['id'] as String?;
        return _ok({'active_id': activeId});
      default:
        return _ok(const {});
    }
  }

  static Map<String, dynamic> _ok(Map<String, dynamic> result) => {
    'jsonrpc': '2.0',
    'id': 1,
    'result': result,
  };
}

Future<ProjectsRepository> _repo(
  _FakeGateway gateway, {
  String connectionId = 'gateway-a',
}) async {
  return ProjectsRepository(
    client: ProjectsGatewayClient(gateway.call),
    preferences: await SharedPreferences.getInstance(),
    connectionId: connectionId,
  );
}

Future<void> _pumpPane(
  WidgetTester tester,
  ProjectsRepository repository, {
  Future<void> Function(String projectId)? onProjectSelected,
  ChatSpaceStore? spaceStore,
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
  bool active = true,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: HermesPaneVisibility(
            active: active,
            child: ProjectsPane(
              repository: repository,
              onProjectSelected: onProjectSelected,
              spaceStore: spaceStore,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a loading skeleton before the first result', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
    )..gate = Completer<void>();
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pump();

    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(find.text('Hermes Android'), findsNothing);

    gateway.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Hermes Android'), findsOneWidget);
  });

  testWidgets('lists the projects returned by the gateway', (tester) async {
    final repository = await _repo(
      _FakeGateway(
        projects: [
          _projectJson(id: 'p1', name: 'Hermes Android'),
          _projectJson(id: 'p2', name: 'ScriptHive'),
        ],
      ),
    );

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
    expect(find.text('ScriptHive'), findsOneWidget);
    expect(find.byType(HermesCard), findsNWidgets(2));
  });

  testWidgets('shows authoritative chat counts on project cards', (
    tester,
  ) async {
    final repository = await _repo(
      _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
        counts: const {'p1': 3},
      ),
    );

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('3 chats'), findsOneWidget);
  });

  testWidgets('separates archived projects from the active section', (
    tester,
  ) async {
    final repository = await _repo(
      _FakeGateway(
        projects: [
          _projectJson(id: 'p1', name: 'Live'),
          _projectJson(id: 'p2', name: 'Retired', archived: true),
        ],
      ),
    );

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Live'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Retired'), findsOneWidget);
    expect(find.byKey(const Key('project-actions-p2')), findsOneWidget);
  });

  testWidgets('shows archived projects and restores them from their actions', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      projects: [
        _projectJson(id: 'p1', name: 'Live'),
        _projectJson(id: 'p2', name: 'Retired', archived: true),
      ],
    );
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Retired'), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-actions-p2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore project'));
    await tester.pumpAndSettle();

    expect(repository.current.projects.map((p) => p.name), contains('Retired'));
    expect(repository.current.archived, isEmpty);
  });

  testWidgets('renames and archives a live project from one actions menu', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Old name')],
    );
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('project-actions-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-project-name')),
      'New name',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text('New name'), findsOneWidget);
    await tester.tap(find.byKey(const Key('project-actions-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive project'));
    await tester.pumpAndSettle();
    expect(find.text('Archive New name?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    expect(repository.current.projects, isEmpty);
    expect(repository.current.archived.single.name, 'New name');
  });

  testWidgets('marks the active project', (tester) async {
    final repository = await _repo(
      _FakeGateway(
        projects: [
          _projectJson(id: 'p1', name: 'Hermes Android'),
          _projectJson(id: 'p2', name: 'ScriptHive'),
        ],
        activeId: 'p1',
      ),
    );

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('reports the tapped project', (tester) async {
    final selected = <String>[];
    final repository = await _repo(
      _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      ),
    );

    await _pumpPane(
      tester,
      repository,
      onProjectSelected: (id) async {
        selected.add(id);
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hermes Android'));
    await tester.pumpAndSettle();

    expect(selected, ['p1']);
  });

  testWidgets('updates the card count when returning from a Project chat', (
    tester,
  ) async {
    final counts = <String, int>{'p1': 0};
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      counts: counts,
    );
    final repository = await _repo(gateway);
    final chatClosed = Completer<void>();
    await _pumpPane(
      tester,
      repository,
      onProjectSelected: (_) => chatClosed.future,
    );
    await tester.pumpAndSettle();
    expect(find.text('0 chats'), findsOneWidget);

    await tester.tap(find.text('Hermes Android'));
    await tester.pump();
    counts['p1'] = 3;
    expect(find.text('0 chats'), findsOneWidget);
    chatClosed.complete();
    await tester.pumpAndSettle();
    expect(find.text('3 chats'), findsOneWidget);
  });

  testWidgets('shows the server count on first entry', (tester) async {
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      counts: const {'p1': 4},
    );
    await _pumpPane(tester, await _repo(gateway));
    await tester.pumpAndSettle();
    expect(find.text('4 chats'), findsOneWidget);
  });

  testWidgets('refreshes a mounted Projects tab when reselected', (
    tester,
  ) async {
    final counts = <String, int>{'p1': 0};
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      counts: counts,
    );
    final repository = await _repo(gateway);
    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('0 chats'), findsOneWidget);

    await _pumpPane(tester, repository, active: false);
    await tester.pump();
    counts['p1'] = 4;
    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('4 chats'), findsOneWidget);
  });

  testWidgets('refreshes visible project counts when the app resumes', (
    tester,
  ) async {
    final counts = <String, int>{'p1': 0};
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      counts: counts,
    );
    await _pumpPane(tester, await _repo(gateway));
    await tester.pumpAndSettle();
    expect(find.text('0 chats'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    counts['p1'] = 2;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('2 chats'), findsOneWidget);
  });

  testWidgets('an older tree read cannot restore a stale zero count', (
    tester,
  ) async {
    final counts = <String, int>{'p1': 0};
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      counts: counts,
    );
    final repository = await _repo(gateway);
    await _pumpPane(tester, repository, onProjectSelected: (_) async {});
    await tester.pumpAndSettle();
    expect(find.text('0 chats'), findsOneWidget);

    final stale = Completer<void>();
    final fresh = Completer<void>();
    gateway.treeGates.addAll([stale, fresh]);
    await tester.tap(find.text('Hermes Android'));
    await tester.pump();
    await tester.pump();
    expect(gateway.treeCalls, 2);

    await _pumpPane(tester, repository, active: false);
    counts['p1'] = 4;
    await _pumpPane(tester, repository);
    await tester.pump();
    await tester.pump();
    expect(gateway.treeCalls, 3);
    fresh.complete();
    await tester.pump();
    expect(find.text('4 chats'), findsOneWidget);

    stale.complete();
    await tester.pumpAndSettle();
    expect(find.text('4 chats'), findsOneWidget);
    // The pane generation guard alone does not protect repository consumers.
    // A later cached read must retain the newer tree after the stale reply.
    final cached = await repository.overview();
    expect(cached.projects.single.sessionCount, 4);
    expect(gateway.treeCalls, 3);
  });

  testWidgets('offers a designed empty state with a create action', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No projects yet'), findsOneWidget);

    await tester.tap(find.text('Create a project'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('project-name')), 'C-MAY');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('C-MAY'), findsOneWidget);
    expect(gateway.projects.single['name'], 'C-MAY');
  });

  testWidgets('refuses to create a project with a blank name', (tester) async {
    final gateway = _FakeGateway();
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create a project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a name'), findsOneWidget);
    expect(gateway.projects, isEmpty);
  });

  testWidgets('an old gateway keeps the pane usable in compatibility mode', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(preferences, connectionId: 'gateway-a');
    final space = await store.createSpace('Hermes Android');
    await store.assignSession('s1', space.id);

    final gateway = _FakeGateway()
      ..failNext = const ProjectsUnsupportedException(
        'projects.list',
        'unknown method',
      );
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository, spaceStore: store);
    await tester.pumpAndSettle();

    // Labelled, not a dead end: the local grouping is still listed.
    expect(find.text('Compatibility mode'), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Hermes Android'), findsOneWidget);
    expect(find.textContaining('1 chat'), findsOneWidget);
  });

  testWidgets('compatibility mode never offers to create a server project', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(preferences, connectionId: 'gateway-a');
    await store.createSpace('Hermes Android');

    final gateway = _FakeGateway()
      ..failNext = const ProjectsUnsupportedException(
        'projects.list',
        'unknown method',
      );
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository, spaceStore: store);
    await tester.pumpAndSettle();

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Create a project'), findsNothing);
    expect(gateway.projects, isEmpty);
  });

  testWidgets('compatibility mode explains an empty device grouping', (
    tester,
  ) async {
    final gateway = _FakeGateway()
      ..failNext = const ProjectsUnsupportedException(
        'projects.list',
        'unknown method',
      );
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Compatibility mode'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('Update Hermes'), findsOneWidget);
  });

  testWidgets('a transport failure with no cache offers a retry', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
    )..failNext = JsonRpcError('projects.list', 'closed');
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
  });

  testWidgets('a cached list stays usable and is labelled offline', (
    tester,
  ) async {
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
    );
    final warm = await _repo(gateway);
    await warm.refresh();

    gateway.failNext = JsonRpcError('projects.list', 'closed');
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('pull to refresh asks the gateway again', (tester) async {
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
    );
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository);
    await tester.pumpAndSettle();
    final before = gateway.listCalls;

    await tester.fling(find.text('Hermes Android'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(gateway.listCalls, greaterThan(before));
  });

  testWidgets('offers to review local spaces when some still exist', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(preferences, connectionId: 'gateway-a');
    await store.createSpace('Hermes Android');

    final repository = await _repo(
      _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      ),
    );

    await _pumpPane(tester, repository, spaceStore: store);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review local spaces'));
    await tester.pumpAndSettle();

    expect(find.byType(SpaceMigrationPreview), findsOneWidget);
    // The one local space matches the server project of the same name.
    expect(find.textContaining('Matches Hermes Android'), findsOneWidget);
  });

  testWidgets('migrates reviewed chats into their server Projects', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(preferences, connectionId: 'gateway-a');
    final space = await store.createSpace('Hermes Android');
    await store.assignSession('chat-1', space.id);
    final gateway = _FakeGateway(
      projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
    );
    final repository = await _repo(gateway);

    await _pumpPane(tester, repository, spaceStore: store);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review local spaces'));
    await tester.pumpAndSettle();

    expect(find.text('Migrate'), findsOneWidget);
    await tester.tap(find.text('Migrate'));
    await tester.pumpAndSettle();

    expect(gateway.assignments, [
      {'session_key': 'chat-1', 'cwd': '/home/test/hermes-android'},
    ]);
    expect(find.text('Migration complete'), findsOneWidget);
  });

  testWidgets('stays quiet when there are no local spaces to migrate', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final store = ChatSpaceStore(preferences, connectionId: 'gateway-a');

    final repository = await _repo(
      _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      ),
    );

    await _pumpPane(tester, repository, spaceStore: store);
    await tester.pumpAndSettle();

    expect(find.text('Review local spaces'), findsNothing);
  });

  testWidgets('renders in the light theme at a large text scale', (
    tester,
  ) async {
    final repository = await _repo(
      _FakeGateway(
        projects: [_projectJson(id: 'p1', name: 'Hermes Android')],
      ),
    );

    await _pumpPane(
      tester,
      repository,
      brightness: Brightness.light,
      textScale: 1.8,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Hermes Android'), findsOneWidget);
  });
}
