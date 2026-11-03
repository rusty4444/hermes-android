import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _filed = Session(
  id: 'cwd-filed',
  title: 'Filed chat',
  model: 'hermes-agent',
  source: 'cli',
  messageCount: 4,
  isActive: false,
  preview: 'Filed preview',
  startedAt: 1750000000,
);
const _loose = Session(
  id: 'unfiled',
  title: 'Loose chat',
  model: 'hermes-agent',
  source: 'cli',
  messageCount: 2,
  isActive: false,
  preview: 'Loose preview',
  startedAt: 1750000001,
);
const _newChat = Session(
  id: 'new-chat',
  title: 'Newly discovered chat',
  model: 'hermes-agent',
  source: 'cli',
  messageCount: 2,
  isActive: false,
  preview: '',
  startedAt: 1750000002,
);

Map<String, dynamic> _ok(Map<String, dynamic> result) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': result,
};
Map<String, dynamic> _unsupported(String method) => {
  'jsonrpc': '2.0',
  'id': 1,
  'error': {'code': -32601, 'message': 'Unknown method: $method'},
};
Map<String, dynamic> _tree({bool empty = false}) => _ok({
  'projects': [
    if (!empty) ...[
      {
        'id': 'project',
        'label': 'Cwd project',
        'path': '/srv/project',
        'sessionCount': 1,
        'sessionIds': [_filed.id],
        // Ownership must not depend on the preview window.
        'previewSessions': <Object>[],
      },
      {
        'id': '__no_project__',
        'label': 'Home',
        'isNoProject': true,
        'sessionIds': [_loose.id],
      },
    ],
  ],
  'scoped_session_ids': empty ? <String>[] : [_filed.id, _loose.id],
});

class _Gateway {
  final calls = <String>[];
  bool listUnsupported = false;
  Future<Map<String, dynamic>> Function() readTree = () async => _tree();

  int get treeCalls => calls.where((m) => m == 'projects.tree').length;

  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params,
  ) async {
    calls.add(method);
    switch (method) {
      case 'projects.list':
        if (listUnsupported) return _unsupported(method);
        return _ok({
          'projects': [
            {
              'id': 'project',
              'name': 'Cwd project',
              'slug': 'project',
              'primary_path': '/srv/project',
            },
          ],
        });
      case 'projects.tree':
        return readTree();
      default:
        throw StateError('Unexpected RPC $method');
    }
  }
}

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(HermesCard));

void main() {
  late _Gateway gateway;
  late ProjectsRepository repository;
  late List<Session> sessions;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    gateway = _Gateway();
    repository = ProjectsRepository(
      client: ProjectsGatewayClient(gateway.call),
      preferences: await SharedPreferences.getInstance(),
      connectionId: 'project-metadata',
    );
    sessions = [_filed, _loose];
  });
  tearDown(() async => repository.close());

  Future<void> mount(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await repository.refresh();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceScreen(
          connection: SavedConnection(
            id: 'project-metadata',
            label: 'Test',
            host: '',
            port: 8642,
            apiKey: '',
          ),
          repositoryFactory: (_) => repository,
          sessionsLoader: () async => List.of(sessions),
          turnSignalsLoader: (_) async => HomeTurnSignals.empty,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> unassigned(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
  }

  void expectUnknown() {
    expect(find.text(_filed.title), findsNothing);
    expect(find.text(_loose.title), findsNothing);
    expect(find.text('Could not load conversations'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  }

  testWidgets(
    'supported tree files chats and excludes the synthetic Home owner',
    (tester) async {
      await mount(tester);
      expect(find.text(_filed.title), findsOneWidget);
      expect(find.text(_loose.title), findsOneWidget);
      expect(
        find.descendant(
          of: _row(_filed.title),
          matching: find.text('Cwd project'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _row(_loose.title),
          matching: find.text('Unassigned'),
        ),
        findsOneWidget,
      );
      await unassigned(tester);
      expect(find.text(_filed.title), findsNothing);
      expect(find.text(_loose.title), findsOneWidget);
      expect(find.text('Could not load conversations'), findsNothing);
    },
  );

  testWidgets('a confirmed empty tree really does make every chat Unassigned', (
    tester,
  ) async {
    gateway.readTree = () async => _tree(empty: true);
    await mount(tester);
    await unassigned(tester);
    expect(find.text(_filed.title), findsOneWidget);
    expect(find.text(_loose.title), findsOneWidget);
    expect(find.text('Could not load conversations'), findsNothing);
  });

  for (final familyUnsupported in [false, true]) {
    testWidgets(
      'unsupported ${familyUnsupported ? 'Projects family' : 'tree sibling'} leaves membership unknown',
      (tester) async {
        gateway.listUnsupported = familyUnsupported;
        gateway.readTree = () async => _unsupported('projects.tree');
        await mount(tester);
        await unassigned(tester);
        expectUnknown();
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await tester.pumpAndSettle();
        // All remains usable without inventing Unassigned labels on its rows.
        expect(find.text(_filed.title), findsOneWidget);
        expect(find.text(_loose.title), findsOneWidget);
        expect(
          find.descendant(
            of: _row(_filed.title),
            matching: find.text('Unassigned'),
          ),
          findsNothing,
        );
        expect(
          repository.current.support,
          familyUnsupported
              ? ProjectsSupport.unsupported
              : ProjectsSupport.native,
        );
        if (!familyUnsupported) {
          expect(repository.current.projects.single.name, 'Cwd project');
          expect(repository.client.cachedSupport, isTrue);
        }
        await unassigned(tester);
        expectUnknown();
        await expectLater(
          repository.overview(refresh: true),
          throwsA(isA<ProjectsUnsupportedException>()),
        );
        expect(gateway.treeCalls, familyUnsupported ? 0 : 1);
      },
    );
  }

  testWidgets(
    'tree transport error is unknown and Retry recovers classification',
    (tester) async {
      gateway.readTree = () async => throw StateError('offline');
      await mount(tester);
      expect(find.text(_filed.title), findsOneWidget);
      await unassigned(tester);
      expectUnknown();
      gateway.readTree = () async => _tree();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text(_filed.title), findsNothing);
      expect(find.text(_loose.title), findsOneWidget);
      expect(find.text('Could not load conversations'), findsNothing);
    },
  );

  testWidgets(
    'a failed refresh cannot classify new chats from a cached empty tree',
    (tester) async {
      gateway.readTree = () async => _tree(empty: true);
      await mount(tester);
      await unassigned(tester);
      expect(find.text(_filed.title), findsOneWidget);
      sessions = [...sessions, _newChat];
      gateway.readTree = () async => throw StateError('offline');
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('Could not load conversations'), findsOneWidget);
      expect(find.text(_newChat.title), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text(_newChat.title), findsOneWidget);
      expect(
        find.descendant(
          of: _row(_newChat.title),
          matching: find.text('Unassigned'),
        ),
        findsNothing,
      );
    },
  );

  for (final staleResult in [
    'empty success',
    'unsupported',
    'transport error',
  ]) {
    testWidgets(
      'stale $staleResult cannot replace newer supported membership',
      (tester) async {
        final old = Completer<Map<String, dynamic>>();
        gateway.readTree = () => old.future;
        addTearDown(() {
          if (!old.isCompleted) old.complete(_tree(empty: true));
        });
        await mount(tester, settle: false);
        expect(gateway.treeCalls, 1);
        await unassigned(tester);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.byType(EmptyState), findsNothing);
        gateway.readTree = () async => _tree();
        final fresh = await repository.overview(refresh: true);
        expect(fresh.ownerLabelOf(_filed.id), 'Cwd project');
        switch (staleResult) {
          case 'empty success':
            old.complete(_tree(empty: true));
          case 'unsupported':
            old.complete(_unsupported('projects.tree'));
          case 'transport error':
            old.completeError(StateError('old transport failed'));
        }
        await tester.pumpAndSettle();
        expect(find.text(_filed.title), findsNothing);
        expect(find.text(_loose.title), findsOneWidget);
        expect(find.text('Could not load conversations'), findsNothing);
        expect(
          (await repository.overview()).ownerLabelOf(_filed.id),
          'Cwd project',
        );
      },
    );
  }

  for (final cachedEmpty in [false, true]) {
    testWidgets(
      'superseded tree without an accepted replacement stays unknown (old empty cache=$cachedEmpty)',
      (tester) async {
        if (cachedEmpty) {
          gateway.readTree = () async => _tree(empty: true);
          await repository.overview();
        }
        final old = Completer<Map<String, dynamic>>();
        final fresh = Completer<Map<String, dynamic>>();
        gateway.readTree = () => old.future;
        addTearDown(() {
          if (!old.isCompleted) old.complete(_tree(empty: true));
          if (!fresh.isCompleted) fresh.complete(_tree());
        });
        await mount(tester, settle: false);
        gateway.readTree = () => fresh.future;
        final newRead = repository.overview(refresh: true);
        await unassigned(tester);
        old.complete(_tree(empty: true));
        await tester.pumpAndSettle();
        expectUnknown();
        fresh.complete(_tree());
        await newRead;
        gateway.readTree = () async => _tree();
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text(_filed.title), findsNothing);
        expect(find.text(_loose.title), findsOneWidget);
        expect(find.text('Could not load conversations'), findsNothing);
      },
    );
  }

  test(
    'a closed repository cannot serve an old empty cache as known',
    () async {
      gateway.readTree = () async => _tree(empty: true);
      await repository.overview();
      await repository.close();
      await expectLater(repository.overview(), throwsStateError);
      expect(gateway.treeCalls, 1);
    },
  );

  test(
    'an empty response arriving after close cannot confirm membership',
    () async {
      final held = Completer<Map<String, dynamic>>();
      gateway.readTree = () => held.future;
      final read = repository.overview();
      final rejected = expectLater(read, throwsStateError);
      await repository.close();
      held.complete(_tree(empty: true));
      await rejected;
      await expectLater(repository.overview(), throwsStateError);
      expect(gateway.treeCalls, 1);
    },
  );

  testWidgets('an old empty success cannot undo a newer unsupported verdict', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    gateway.readTree = () => old.future;
    addTearDown(() {
      if (!old.isCompleted) old.complete(_tree(empty: true));
    });
    await mount(tester, settle: false);
    gateway.readTree = () async => _unsupported('projects.tree');
    await expectLater(
      repository.overview(refresh: true),
      throwsA(isA<ProjectsUnsupportedException>()),
    );
    await unassigned(tester);
    old.complete(_tree(empty: true));
    await tester.pumpAndSettle();
    expectUnknown();
    expect(repository.current.support, ProjectsSupport.native);
    expect(repository.current.projects.single.name, 'Cwd project');
  });
}
