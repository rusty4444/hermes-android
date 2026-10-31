/// The project detail screen: what a project card opens into.
///
/// `ProjectsRepository.projectSessions` and the `projects.project_sessions`
/// contract under it were both delivered, but nothing rendered them — a
/// project card had nowhere to go. This is that screen, and the rules pinned
/// here are the ones the roadmap's Phase 1 acceptance depends on:
///
/// - the four designed states (skeleton, empty, offline, retryable error) are
///   expressed the same way `HomePane` and `ActivityPane` express them, so the
///   three panes never disagree about the same failure;
/// - a *first* read that fails is retryable, while a *later* failure keeps the
///   chats already on screen behind an offline notice — losing the network
///   must never blank a screen the user is reading;
/// - a gateway that predates the drill-in explains itself instead of showing a
///   dead end, and never claims the project is empty;
/// - Overview reports what the server counted, never what the lanes happen to
///   hold, so a hydrated-empty tier cannot make a project read as zero chats;
/// - opening a chat reports the session the server sent, so the existing chat
///   route is reused rather than a second one invented.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_project.dart';
import 'package:hermes_android/core/models/project_sessions_tree.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/project_detail_screen.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Session _session({
  String id = 's1',
  String title = 'Ship the Files browser',
  double startedAt = 1750000000,
  bool isActive = true,
  double? lastActive,
}) => Session(
  id: id,
  title: title,
  model: 'claude-opus-5',
  preview: 'Ran flutter analyze',
  startedAt: startedAt,
  source: 'cli',
  messageCount: 3,
  isActive: isActive,
  lastActive: lastActive ?? startedAt,
);

ProjectSessionsTree _tree({
  String id = 'p1',
  String label = 'Hermes Android',
  List<Session> sessions = const [],
  int? sessionCount,
}) => ProjectSessionsTree(
  id: id,
  label: label,
  path: '/home/carlos/dev/hermes-android',
  sessionCount: sessionCount ?? sessions.length,
  lastActive: 1750000900,
  repos: [
    ProjectRepo(
      id: '/home/carlos/dev/hermes-android',
      label: 'hermes-android',
      path: '/home/carlos/dev/hermes-android',
      sessionCount: sessions.length,
      lanes: [
        ProjectLane(
          id: 'main',
          label: 'main',
          isMain: true,
          sessions: sessions,
        ),
      ],
    ),
  ],
);

/// Pumps the screen with a scripted loader, so every state is deterministic.
Future<void> _pump(
  WidgetTester tester, {
  required Future<ProjectSessionsView> Function({required bool refresh}) load,
  String projectId = 'p1',
  String projectName = 'Hermes Android',
  ValueChanged<Session>? onOpenSession,
  Future<void> Function()? onNewChat,
  List<HermesProject> projects = const [],
  ProjectSessionMover? onMoveSession,
  Future<void> Function(String name)? onRenameProject,
  Future<void> Function()? onArchiveProject,
  Future<void> Function()? onDeleteProject,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: ProjectDetailScreen(
        projectId: projectId,
        projectName: projectName,
        loadSessions: load,
        onOpenSession: onOpenSession,
        onNewChat: onNewChat,
        projects: projects,
        onMoveSession: onMoveSession,
        onRenameProject: onRenameProject,
        onArchiveProject: onArchiveProject,
        onDeleteProject: onDeleteProject,
      ),
    ),
  );
}

void main() {
  testWidgets('Project chat refreshes the detail after its route returns', (
    tester,
  ) async {
    final chatClosed = Completer<void>();
    var refreshes = 0;
    await _pump(
      tester,
      load: ({required refresh}) async {
        if (refresh) refreshes++;
        return ProjectSessionsView(
          projectId: 'p1',
          tree: _tree(sessions: refresh ? [_session()] : const []),
          sessions: refresh ? [_session()] : const [],
          support: ProjectsSupport.native,
        );
      },
      onNewChat: () => chatClosed.future,
    );
    await tester.pumpAndSettle();
    expect(find.text('No chats yet'), findsOneWidget);

    await tester.tap(find.byKey(kProjectNewChatButtonKey));
    await tester.pump();
    expect(refreshes, 0);

    chatClosed.complete();
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('Ship the Files browser'), findsOneWidget);
  });

  testWidgets('holds a skeleton until the first read lands', (tester) async {
    final gate = Completer<ProjectSessionsView>();
    await _pump(tester, load: ({required refresh}) => gate.future);
    await tester.pump();

    expect(find.byType(LoadingSkeleton), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);

    gate.complete(
      ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(sessions: [_session()]),
        sessions: [_session()],
        support: ProjectsSupport.native,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoadingSkeleton), findsNothing);
    expect(find.text('Ship the Files browser'), findsOneWidget);
  });

  testWidgets('a project with no chats states so instead of looking broken', (
    tester,
  ) async {
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(),
        support: ProjectsSupport.native,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.textContaining('No chats'), findsOneWidget);
  });

  testWidgets('a failed first read is retryable', (tester) async {
    var attempts = 0;
    await _pump(
      tester,
      load: ({required refresh}) async {
        attempts++;
        if (attempts == 1) {
          return ProjectSessionsView(
            projectId: 'p1',
            support: ProjectsSupport.native,
            error: Exception('socket closed'),
          );
        }
        return ProjectSessionsView(
          projectId: 'p1',
          tree: _tree(sessions: [_session()]),
          sessions: [_session()],
          support: ProjectsSupport.native,
        );
      },
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Ship the Files workspace'), findsNothing);
    expect(find.text('Ship the Files browser'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('a later failure keeps the chats behind an offline notice', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      load: ({required refresh}) async {
        attempts++;
        if (attempts == 1) {
          return ProjectSessionsView(
            projectId: 'p1',
            tree: _tree(sessions: [_session()]),
            sessions: [_session()],
            support: ProjectsSupport.native,
          );
        }
        return ProjectSessionsView(
          projectId: 'p1',
          tree: _tree(sessions: [_session()]),
          sessions: [_session()],
          support: ProjectsSupport.native,
          isStale: true,
          error: Exception('offline'),
        );
      },
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
    await tester.pumpAndSettle();

    // The chat the user was reading survives the failed refresh.
    expect(find.text('Ship the Files browser'), findsOneWidget);
    expect(find.byType(ErrorState), findsNothing);
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('an older gateway explains itself and claims nothing', (
    tester,
  ) async {
    await _pump(
      tester,
      load: ({required refresh}) async => const ProjectSessionsView(
        projectId: 'p1',
        support: ProjectsSupport.unsupported,
      ),
    );
    await tester.pumpAndSettle();

    // Never the empty state: "no chats" would be a claim this gateway cannot
    // support, and a red error would blame the user for an old server.
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('does not support'), findsOneWidget);
  });

  testWidgets('Overview reports the counts the server sent', (tester) async {
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        // The server counts 12 chats but hydrated only the two lanes rows.
        tree: _tree(sessions: [_session()], sessionCount: 12),
        sessions: [_session()],
        support: ProjectsSupport.native,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // Deriving the count from the rows on screen would report 1.
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining('hermes-android'), findsWidgets);
  });

  testWidgets('declares the five project tabs', (tester) async {
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(sessions: [_session()]),
        sessions: [_session()],
        support: ProjectsSupport.native,
      ),
    );
    await tester.pumpAndSettle();

    for (final tab in ['Chats', 'Overview', 'Files', 'Assets', 'Activity']) {
      expect(find.text(tab), findsWidgets, reason: '$tab tab must exist');
    }
  });

  testWidgets('Files tab lists the server folder paths', (tester) async {
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(sessions: [_session()]),
        sessions: [_session()],
        support: ProjectsSupport.native,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('/home/carlos/dev/hermes-android'), findsWidgets);
    expect(find.textContaining('hermes-android'), findsWidgets);
  });

  testWidgets('Assets tab explains the missing server index', (tester) async {
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(sessions: [_session()]),
        sessions: [_session()],
        support: ProjectsSupport.native,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('server-authoritative Assets index'),
      findsOneWidget,
    );
  });

  testWidgets('Activity tab shows the project chat activity', (tester) async {
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(
          sessions: [
            _session(id: 's-run', title: 'Running build'),
            _session(
              id: 's-done',
              title: 'Finished task',
              startedAt: 1749990000,
              isActive: false,
            ),
          ],
        ),
        sessions: [
          _session(id: 's-run', title: 'Running build'),
          _session(
            id: 's-done',
            title: 'Finished task',
            startedAt: 1749990000,
            isActive: false,
          ),
        ],
        support: ProjectsSupport.native,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('opening a chat reports the session the server sent', (
    tester,
  ) async {
    Session? opened;
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(sessions: [_session(id: 's-42')]),
        sessions: [_session(id: 's-42')],
        support: ProjectsSupport.native,
      ),
      onOpenSession: (session) => opened = session,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ship the Files browser'));
    await tester.pumpAndSettle();

    expect(opened, isNotNull);
    expect(opened!.id, 's-42');
  });

  testWidgets('moves a chat to another Project and refreshes the list', (
    tester,
  ) async {
    final moves = <String?>[];
    final refreshes = <bool>[];
    await _pump(
      tester,
      load: ({required refresh}) async {
        refreshes.add(refresh);
        return ProjectSessionsView(
          projectId: 'p1',
          tree: _tree(sessions: [_session(id: 's-42')]),
          sessions: [_session(id: 's-42')],
          support: ProjectsSupport.native,
        );
      },
      projects: const [
        HermesProject(id: 'p1', slug: 'android', name: 'Hermes Android'),
        HermesProject(id: 'p2', slug: 'scripthive', name: 'ScriptHive'),
      ],
      onMoveSession: (session, projectId) async {
        expect(session.id, 's-42');
        moves.add(projectId);
        return null;
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('move-session-s-42')));
    await tester.pumpAndSettle();
    expect(find.text('Move conversation'), findsOneWidget);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('ScriptHive'), findsOneWidget);
    // The current Project remains only in the app bar, never as a destination.
    expect(find.text('Hermes Android'), findsOneWidget);

    await tester.tap(find.text('ScriptHive'));
    await tester.pumpAndSettle();

    expect(moves, ['p2']);
    expect(refreshes, [false, true]);
    expect(find.text('Moved to ScriptHive'), findsOneWidget);
  });

  testWidgets('project actions rename and archive through explicit flows', (
    tester,
  ) async {
    final renamed = <String>[];
    var archives = 0;
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(),
        support: ProjectsSupport.native,
      ),
      onRenameProject: (name) async => renamed.add(name),
      onArchiveProject: () async => archives++,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename project'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('rename-project-name')),
      'Mobile',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(renamed, ['Mobile']);
    expect(find.text('Mobile'), findsOneWidget);

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive project'));
    await tester.pumpAndSettle();
    expect(find.text('Archive Mobile?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();
    expect(archives, 1);
  });

  testWidgets('delete requires confirmation and preserves chats', (
    tester,
  ) async {
    var deletions = 0;
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(sessions: [_session()]),
        sessions: [_session()],
        support: ProjectsSupport.native,
      ),
      onDeleteProject: () async => deletions++,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete project'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Hermes Android?'), findsOneWidget);
    expect(find.textContaining('Chats will not be deleted'), findsOneWidget);
    expect(find.textContaining('Unassigned'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deletions, 0);

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deletions, 1);
  });

  testWidgets('a failed delete keeps the project open with a retry action', (
    tester,
  ) async {
    await _pump(
      tester,
      load: ({required refresh}) async => ProjectSessionsView(
        projectId: 'p1',
        tree: _tree(),
        support: ProjectsSupport.native,
      ),
      onDeleteProject: () async => throw Exception('offline'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(find.text('Couldn’t delete project'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('pull to refresh forces a live read', (tester) async {
    final refreshes = <bool>[];
    await _pump(
      tester,
      load: ({required refresh}) async {
        refreshes.add(refresh);
        return ProjectSessionsView(
          projectId: 'p1',
          tree: _tree(sessions: [_session()]),
          sessions: [_session()],
          support: ProjectsSupport.native,
        );
      },
    );
    await tester.pumpAndSettle();

    expect(refreshes, [false]);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      800,
    );
    await tester.pumpAndSettle();

    // The first open may use the cache; an explicit pull must not.
    expect(refreshes, [false, true]);
  });

  group('per-Project search', () {
    Finder searchField() => find.descendant(
      of: find.byKey(kProjectSearchFieldKey),
      matching: find.byType(TextField),
    );

    Future<void> pumpThree(tester, {ValueChanged<Session>? onOpenSession}) =>
        _pump(
          tester,
          load: ({required refresh}) async => ProjectSessionsView(
            projectId: 'p1',
            tree: _tree(
              sessions: [
                _session(id: 's1', title: 'Ship the Files browser'),
                _session(id: 's2', title: 'Review the draft'),
                _session(id: 's3', title: 'Pushed the release tag'),
              ],
            ),
            sessions: [
              _session(id: 's1', title: 'Ship the Files browser'),
              _session(id: 's2', title: 'Review the draft'),
              _session(id: 's3', title: 'Pushed the release tag'),
            ],
            support: ProjectsSupport.native,
          ),
          onOpenSession: onOpenSession,
        );

    testWidgets('typing narrows the chats to the matches', (tester) async {
      await pumpThree(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(kProjectSearchFieldKey), findsOneWidget);
      expect(find.text('Ship the Files browser'), findsOneWidget);
      expect(find.text('Review the draft'), findsOneWidget);
      expect(find.text('Pushed the release tag'), findsOneWidget);

      await tester.enterText(searchField(), 'ship');
      await tester.pumpAndSettle();

      expect(find.text('Ship the Files browser'), findsOneWidget);
      expect(find.text('Review the draft'), findsNothing);
      expect(find.text('Pushed the release tag'), findsNothing);
      expect(find.byType(EmptyState), findsNothing);
    });

    testWidgets('clearing the search restores every chat', (tester) async {
      await pumpThree(tester);
      await tester.pumpAndSettle();

      await tester.enterText(searchField(), 'draft');
      await tester.pumpAndSettle();
      expect(find.text('Review the draft'), findsOneWidget);
      expect(find.text('Ship the Files browser'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();

      expect(find.text('Ship the Files browser'), findsOneWidget);
      expect(find.text('Review the draft'), findsOneWidget);
      expect(find.text('Pushed the release tag'), findsOneWidget);
    });

    testWidgets('an empty project shows no search field and keeps its state', (
      tester,
    ) async {
      await _pump(
        tester,
        load: ({required refresh}) async => ProjectSessionsView(
          projectId: 'p1',
          tree: _tree(),
          support: ProjectsSupport.native,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kProjectSearchFieldKey), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('No chats'), findsOneWidget);
    });

    testWidgets('a query with no match shows a distinct no-match state', (
      tester,
    ) async {
      await pumpThree(tester);
      await tester.pumpAndSettle();

      await tester.enterText(searchField(), 'zzz-no-such-chat');
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No matches'), findsOneWidget);
      // Never the "empty project" claim: the chat may exist elsewhere.
      expect(find.textContaining('No chats yet'), findsNothing);
    });

    testWidgets('a filtered row still opens its chat', (tester) async {
      Session? opened;
      await pumpThree(tester, onOpenSession: (session) => opened = session);
      await tester.pumpAndSettle();

      await tester.enterText(searchField(), 'release');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pushed the release tag'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.id, 's3');
    });
  });
}
