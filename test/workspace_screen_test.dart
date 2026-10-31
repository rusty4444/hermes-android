import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/nous_portal_screen.dart';
import 'package:hermes_android/core/screens/assets_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/android_share_intent_service.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:hermes_android/core/services/chat_assets_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';
import 'package:hermes_android/core/utils/home_digest.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/utils/new_chat_options.dart';
import 'package:hermes_android/core/widgets/activity_pane.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:hermes_android/core/widgets/chat_attention_section.dart';
import 'package:hermes_android/core/widgets/more_pane.dart';
import 'package:hermes_android/core/widgets/projects_pane.dart';
import 'package:hermes_android/core/widgets/project_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

Session _session({required String id, required String title}) {
  return Session(
    id: id,
    title: title,
    model: 'claude-opus-5',
    source: 'gateway',
    messageCount: 4,
    isActive: true,
    preview: 'preview',
    startedAt: DateTime.now().millisecondsSinceEpoch / 1000.0,
  );
}

SavedConnection _connection({
  String? desktopGatewayUrl,
  String host = 'carlos-miniserver',
}) {
  return SavedConnection(
    id: 'conn-1',
    label: 'Miniserver',
    host: host,
    port: 8642,
    apiKey: 'key',
    desktopGatewayUrl: desktopGatewayUrl,
  );
}

class _WorkspaceAssetsSource implements ChatAssetsDataSource {
  @override
  Future<ChatAssetsSessionPage> listSessions({
    int offset = 0,
    int limit = 10,
  }) async => ChatAssetsSessionPage(
    sessions: [_session(id: 'asset-source', title: 'Asset source')],
    nextOffset: 10,
    hasMore: false,
    partial: false,
  );

  @override
  Future<ChatAssetsMessagePage> getMessages(
    Session session, {
    int offset = 0,
    int limit = 100,
  }) async => ChatAssetsMessagePage(
    messages: const [
      {
        'id': 1,
        'role': 'assistant',
        'content': 'MEDIA:/out/chart.png',
        'timestamp': 10,
      },
    ],
    nextOffset: 100,
    hasMore: false,
  );
}

Map<String, dynamic> _projectJson({
  required String id,
  required String name,
  String? primaryPath,
}) => {
  'id': id,
  'slug': name.toLowerCase(),
  'name': name,
  'archived': false,
  'created_at': 1750000000,
  'primary_path': ?primaryPath,
  'folders': const [],
};

Future<ProjectsRepository> _repository(
  List<Map<String, dynamic>> projects, {
  List<Map<String, dynamic>>? assignments,
  List<String>? deletions,
  int assignmentFailures = 0,
  bool hangOverview = false,
  Map<String, ({String label, String sessionId})>? treeWithPreview,
  Map<String, int>? projectCounts,
}) async {
  var failuresLeft = assignmentFailures;
  var serverProjects = [...projects];
  return ProjectsRepository(
    client: ProjectsGatewayClient((method, params) async {
      if (method == 'projects.tree' && hangOverview) {
        return Completer<Map<String, dynamic>>().future;
      }
      if (method == 'projects.tree' && treeWithPreview != null) {
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'projects': [
              for (final entry in treeWithPreview.entries)
                {
                  'id': entry.key,
                  'label': entry.value.label,
                  'isNoProject': false,
                  'sessionCount': 1,
                  // The real gateway emits every claimed id on the node
                  // itself (project_tree.py::_project_node); the Chats row
                  // labels derive owner names from it.
                  'sessionIds': [entry.value.sessionId],
                  'previewSessions': [
                    {
                      'id': entry.value.sessionId,
                      'title': 'preview',
                      'started_at': 1750000000,
                    },
                  ],
                },
            ],
            'active_id': null,
            'scoped_session_ids': [
              for (final entry in treeWithPreview.entries)
                entry.value.sessionId,
            ],
          },
        };
      }
      if (method == 'projects.tree' && projectCounts != null) {
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {
            'projects': [
              for (final project in serverProjects)
                {
                  'id': project['id'],
                  'label': project['name'],
                  'sessionCount': projectCounts[project['id']] ?? 0,
                },
            ],
            'active_id': null,
            'scoped_session_ids': const [],
          },
        };
      }
      if (method == 'projects.list') {
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'projects': serverProjects, 'active_id': null},
        };
      }
      if (method == 'projects.delete') {
        final id = params['id'] as String;
        deletions?.add(id);
        serverProjects = [
          for (final project in serverProjects)
            if (project['id'] != id) project,
        ];
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'result': {'projects': serverProjects, 'active_id': null},
        };
      }
      if (method == 'session.workspace.move') {
        if (failuresLeft > 0) {
          failuresLeft--;
          throw Exception('gateway offline');
        }
        assignments?.add(Map<String, dynamic>.from(params));
        return {
          'jsonrpc': '2.0',
          'id': 1,
          'result': const {'ok': true},
        };
      }
      return {'jsonrpc': '2.0', 'id': 1, 'result': const {}};
    }),
    preferences: await SharedPreferences.getInstance(),
    connectionId: 'conn-1',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required SavedConnection connection,
  ProjectsRepository? repository,
  List<String>? openedProjects,
  List<String>? openedDashboards,
  List<String>? openedSessions,
  List<Session>? sessions,
  Object? sessionsError,
  VoidCallback? onSessionsLoad,
  WorkspaceSessionScreenBuilder? sessionScreenBuilder,
  WorkspaceFilesScreenBuilder? filesScreenBuilder,
  ChatAssetsDataSource Function(SavedConnection)? assetsSourceFactory,
  WorkspaceTurnSignalsLoader? turnSignalsLoader,
  WorkspaceActivityFeedLoader? activityFeedLoader,
  ValueChanged<NewChatDraft>? onNewChat,
  NewChatSessionIdFactory? newChatSessionIdFactory,
  GatewayTurnApplicationController? turnApplicationController,
  String? initialSharedText,
  AndroidSharePayload? initialSharedPayload,
  bool initialQuickChat = false,
  SharedAttachmentPreparer? sharedAttachmentPreparer,
  Size size = const Size(400, 800),
  http.Client? dashboardHttpClient,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceScreen(
        connection: connection,
        testDashboardHttpClient: dashboardHttpClient,
        repositoryFactory: repository == null ? null : (_) => repository,
        onOpenProject: openedProjects?.add,
        onOpenSession: openedSessions == null
            ? null
            : (session) => openedSessions.add(session.id),
        sessionsLoader: sessions == null && sessionsError == null
            ? null
            : () async {
                onSessionsLoad?.call();
                if (sessionsError != null) throw sessionsError;
                return sessions ?? const <Session>[];
              },
        sessionScreenBuilder: sessionScreenBuilder,
        filesScreenBuilder: filesScreenBuilder,
        assetsSourceFactory: assetsSourceFactory,
        turnSignalsLoader: turnSignalsLoader,
        activityFeedLoader: activityFeedLoader,
        onNewChat: onNewChat,
        newChatSessionIdFactory: newChatSessionIdFactory,
        turnApplicationController: turnApplicationController,
        initialSharedText: initialSharedText,
        initialSharedPayload: initialSharedPayload,
        initialQuickChat: initialQuickChat,
        sharedAttachmentPreparer: sharedAttachmentPreparer,
        onOpenDashboard: openedDashboards == null
            ? null
            : (url) async => openedDashboards.add(url),
      ),
    ),
  );
}

/// Limit the header assertion to the compact attention section, not rows.
Finder _sectionHeader(HomeSectionKind kind, AppLocalizations l10n) =>
    find.descendant(
      of: find.byType(ChatAttentionSection),
      matching: find.text(kind.title(l10n)),
    );

/// A turn session a widget test can drive: captures the workspace's
/// session-bound handler and fires it on demand, like the real coordinator
/// does when `session.open` first binds a draft id to a stored id.
class _ControllableTurnSession extends InertTurnApplicationSession {
  GatewayTurnSessionBoundCallback? boundCallback;
  Object? boundRegistration;

  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) {
    final token = Object();
    boundRegistration = token;
    boundCallback = listener;
    return token;
  }

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {
    if (!identical(boundRegistration, registration)) return;
    boundRegistration = null;
    boundCallback = null;
  }

  void fireSessionBound(String localSessionId, String storedSessionId) {
    boundCallback?.call(localSessionId, storedSessionId);
  }
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'More discovery is lazy single-flight and retries after held failure',
    (tester) async {
      final held = Completer<http.Response>();
      var probes = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/model/options')) {
          probes++;
          if (probes == 1) return held.future;
          return http.Response(
            jsonEncode({
              'providers': [
                {'slug': 'openrouter'},
                {'slug': 'openai'},
                {'slug': 'unsupported'},
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'sessions': [], 'total': 0}), 200);
      });
      await _pump(
        tester,
        connection: _connection(
          desktopGatewayUrl: 'https://host:8642',
        ).copyWith(dashboardProxied: true),
        repository: await _repository([]),
        sessions: [],
        dashboardHttpClient: client,
      );
      await tester.pumpAndSettle();
      expect(probes, 0);
      await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(probes, 1);
      expect(
        tester
            .widget<MorePane>(find.byType(MorePane))
            .sections
            .expand((section) => section.entries)
            .map((entry) => entry.id),
        contains('nous-portal'),
      );
      await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(probes, 1);
      held.complete(http.Response('unavailable', 503));
      await tester.pumpAndSettle();
      await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(probes, 2);
      final pane = tester.widget<MorePane>(find.byType(MorePane));
      final ids = pane.sections
          .expand((s) => s.entries)
          .map((e) => e.id)
          .toList();
      expect(ids, containsAll(['openrouter', 'nous-portal']));
      expect(ids, isNot(contains('unsupported')));
      expect(ids, isNot(contains('openai')));
      pane.onSelect(
        pane.sections
            .expand((s) => s.entries)
            .singleWhere((e) => e.id == 'nous-portal'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NousPortalScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('surfaces the local spaces still waiting to be migrated', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await ChatSpaceStore(
      preferences,
      connectionId: 'conn-1',
    ).createSpace('Hermes Android');

    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Hermes Android'),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.projects.label(l10n)).last);
    await tester.pumpAndSettle();

    expect(find.text('Review local spaces'), findsOneWidget);
  });

  testWidgets('opens on Chats inside the five-destination shell', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HermesShell), findsOneWidget);
    for (final destination in HermesDestination.values) {
      expect(find.text(destination.label(l10n)), findsWidgets);
    }
  });

  testWidgets('Chats is the single Workspace browser for all sessions', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Daily driver')],
      openedSessions: opened,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);
    expect(find.byKey(kWorkspaceSessionSearchKey), findsOneWidget);
    expect(find.text('Daily driver'), findsOneWidget);

    await tester.tap(find.text('Daily driver'));
    expect(opened, ['s1']);
  });

  testWidgets('Chats keeps its selected filter after switching away and back', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Loose chat')],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Unassigned'))
          .selected,
      isTrue,
    );

    await tester.tap(find.text(HermesDestination.crons.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Unassigned'))
          .selected,
      isTrue,
    );
    expect(find.text('Loose chat'), findsOneWidget);
  });

  testWidgets('Chats rows show the project label from the server tree', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository(
        [_projectJson(id: 'p1', name: 'Hermes Android')],
        treeWithPreview: {'p1': (label: 'Hermes Android', sessionId: 's1')},
      ),
      sessions: [_session(id: 's1', title: 'In project')],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(HermesCard),
        matching: find.byIcon(Icons.folder_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Chats still shows sessions when the Projects overview hangs', (
    tester,
  ) async {
    // Regression: a wedged Desktop Gateway (unreachable host, silent
    // socket) used to block the whole session list behind an infinite
    // skeleton because the Projects overview had no bound.
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([], hangOverview: true),
      sessions: [_session(id: 's1', title: 'Still reachable')],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 9));

    expect(find.byKey(kWorkspaceSessionSearchKey), findsOneWidget);
    expect(find.text('Still reachable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('names the connection so multi-gateway users stay oriented', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Miniserver'), findsWidgets);
  });

  testWidgets('the Projects destination renders live projects', (tester) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Hermes Android'),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    expect(find.byType(ProjectsPane), findsOneWidget);
    expect(find.text('Hermes Android'), findsOneWidget);
  });

  testWidgets('opening a project reports it to the host', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Hermes Android'),
      ]),
      openedProjects: opened,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hermes Android'));
    await tester.pumpAndSettle();

    expect(opened, ['p1']);
  });

  testWidgets('the shipped default opens the real project detail screen', (
    tester,
  ) async {
    // No host callback: the shell must not be a dead end. Before this, a
    // project card with no `onOpenProject` did nothing at all.
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Hermes Android'),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hermes Android'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    // The name is carried, so the screen never opens on "Untitled".
    expect(find.text('Hermes Android'), findsWidgets);
    expect(find.text('Chats'), findsWidgets);
  });

  testWidgets('deleting a Project returns to the refreshed Projects list', (
    tester,
  ) async {
    final deletions = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Delete me'),
        _projectJson(id: 'p2', name: 'Keep me'),
      ], deletions: deletions),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deletions, ['p1']);
    expect(find.byType(ProjectDetailScreen), findsNothing);
    expect(find.text('Delete me'), findsNothing);
    expect(find.text('Keep me'), findsOneWidget);
  });

  testWidgets('the Project detail plus creates inside that Project', (
    tester,
  ) async {
    final opened = <NewChatDraft>[];
    final assignments = <Map<String, dynamic>>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(
          id: 'p1',
          name: 'Hermes Android',
          primaryPath: '/srv/projects/hermes-android',
        ),
      ], assignments: assignments),
      onNewChat: opened.add,
      newChatSessionIdFactory: () => 'project-detail-chat',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hermes Android'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kProjectNewChatButtonKey));
    await tester.pumpAndSettle();

    // Stock flow: filing happens via the session cwd at create time, so
    // starting the chat issues no assignment RPC.
    expect(assignments, isEmpty);
    expect(opened.single.projectId, 'p1');
    expect(opened.single.isQuick, isFalse);
    expect(
      opened.single.projectWorkingDirectory,
      '/srv/projects/hermes-android',
    );
  });

  testWidgets('returning from a Project refreshes its card chat count', (
    tester,
  ) async {
    final counts = <String, int>{'p1': 0};
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(
          id: 'p1',
          name: 'Hermes Android',
          primaryPath: '/srv/projects/hermes-android',
        ),
      ], projectCounts: counts),
      sessions: const [],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(find.text('0 chats'), findsOneWidget);

    await tester.tap(find.text('Hermes Android'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    counts['p1'] = 4;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('4 chats'), findsOneWidget);
  });

  testWidgets('a folderless Project detail cannot start an unfiled chat', (
    tester,
  ) async {
    final opened = <NewChatDraft>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Folderless'),
      ]),
      onNewChat: opened.add,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Folderless'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kProjectNewChatButtonKey));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(find.textContaining('needs a folder'), findsOneWidget);
  });

  testWidgets('a host callback suppresses the built-in project route', (
    tester,
  ) async {
    // A host that owns navigation must not get a second screen pushed under
    // its own — the same rule the Home chat route already follows.
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Hermes Android'),
      ]),
      openedProjects: opened,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hermes Android'));
    await tester.pumpAndSettle();

    expect(opened, ['p1']);
    expect(find.byType(ProjectDetailScreen), findsNothing);
  });

  testWidgets('a legacy connection explains why projects are unavailable', (
    tester,
  ) async {
    await _pump(tester, connection: _connection());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('Desktop Gateway'), findsOneWidget);
    expect(find.byType(ProjectsPane), findsNothing);
  });

  testWidgets(
    'Activity uses real gateway sessions on a REST connection without a v2 journal',
    (tester) async {
      final opened = <String>[];
      await _pump(
        tester,
        connection: _connection(),
        sessions: [_session(id: 'real-chat', title: 'Actual gateway activity')],
        openedSessions: opened,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(find.text('Recently updated'), findsOneWidget);
      expect(find.text('Actual gateway activity'), findsOneWidget);
      expect(find.text('No recent activity'), findsNothing);
      expect(find.text('Running now'), findsNothing);
      expect(find.text('Completed'), findsNothing);
      await tester.tap(find.text('Actual gateway activity'));
      await tester.pumpAndSettle();
      expect(opened, ['real-chat']);
    },
  );

  testWidgets(
    'Activity observes a real stock owner and updates blocked work without a list request',
    (tester) async {
      final connection = _connection();
      final controller = GatewayTurnApplicationController();
      var listReads = 0;
      final sent = Completer<void>();
      final finish = Completer<void>();
      late NormalGatewayApplicationSession session;
      late Future<void> sending;
      session = controller.normalSessionFor(
        connection,
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              sent.complete();
              await finish.future;
            },
      );
      await session.ready;
      final owner = session.chatFor(
        'local-chat',
        storedSessionId: 'stored-chat',
        title: 'Tracked chat',
      );
      sending = owner.submitPrepared(
        reservation: owner.reserve()!,
        text: 'Do work',
        localContent: 'Do work',
      );
      await sent.future;
      await controller.readActivityRecords(connection);
      await _pump(
        tester,
        connection: connection,
        turnApplicationController: controller,
        onSessionsLoad: () => listReads++,
        sessions: [_session(id: 'stored-chat', title: 'Tracked chat')],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(find.text('Running now'), findsOneWidget);
      expect(find.text('Tracked chat'), findsOneWidget);
      expect(find.text('Recently updated'), findsNothing);
      final readsBeforeEvent = listReads;
      session.receiveEvent(
        'local-chat',
        StreamEvent(
          type: 'approval.request',
          data: {'request_id': 'request-1', 'command': 'private command'},
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for your input'), findsOneWidget);
      expect(find.text('Running now'), findsNothing);
      expect(find.text('private command'), findsNothing);
      expect(listReads, readsBeforeEvent);
      await tester.pumpWidget(const SizedBox());
      finish.complete();
      await sending;
      await controller.close();
    },
  );

  testWidgets(
    'retained hidden Activity still updates the badge without a list read',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      var blocked = 0;
      var listReads = 0;
      var feedReads = 0;
      await _pump(
        tester,
        connection: _connection(),
        turnApplicationController: controller,
        sessions: [_session(id: 'chat', title: 'Known chat')],
        onSessionsLoad: () => listReads++,
        activityFeedLoader: (_, _) async {
          feedReads++;
          return ActivityFeed(
            groups: [],
            blockedCount: blocked,
            runningCount: 0,
          );
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ActivityPane>(find.byType(ActivityPane)).active,
        isTrue,
      );
      await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ActivityPane>(
              find.byType(ActivityPane, skipOffstage: false),
            )
            .active,
        isFalse,
      );
      final listsBefore = listReads;
      final feedsBefore = feedReads;
      blocked = 1;
      final token = controller.beginLegacyTurn();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HermesShell>(find.byType(HermesShell))
            .badges[HermesDestination.activity],
        1,
      );
      expect(listReads, listsBefore);
      expect(feedReads, feedsBefore + 1);
      await tester.pumpWidget(const SizedBox());
      controller.endLegacyTurn(token);
      await controller.close();
    },
  );

  testWidgets('Activity no longer ships a placeholder', (tester) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: const [],
      activityFeedLoader: (_, _) async =>
          const ActivityFeed(groups: [], blockedCount: 0, runningCount: 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
    await tester.pumpAndSettle();

    expect(find.byType(ActivityPane), findsOneWidget);
    expect(find.textContaining('Coming'), findsNothing);
    // The empty timeline is a designed calm state, not a placeholder.
    expect(find.text('No recent activity'), findsOneWidget);
  });

  testWidgets('Chats renders the browser without a duplicate recent digest', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Roadmap slice')],
    );
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);
    expect(
      find.text(HomeSectionKind.continueWorking.title(l10n)),
      findsNothing,
    );
    expect(find.text('Roadmap slice'), findsOneWidget);
    // The placeholder it replaces must be gone, not merely pushed down.
    expect(find.textContaining('Home — Coming next'), findsNothing);
  });

  testWidgets('Chats search opens the focused global Chats search', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Searchable chat')],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search all chats'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Search')),
      findsOneWidget,
    );
    expect(find.byKey(kWorkspaceSessionSearchKey), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('Chats opens an actionable Inbox with a count', (tester) async {
    final now = DateTime.now();
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [
        _session(id: 'blocked', title: 'Approve deployment'),
        _session(id: 'failed', title: 'Repair failed turn'),
        _session(id: 'live', title: 'Still running'),
      ],
      openedSessions: opened,
      activityFeedLoader: (_, _) async => ActivityFeed(
        groups: [
          ActivityGroup(
            kind: ActivityGroupKind.needsYou,
            items: [
              ActivityItem(
                sessionId: 'blocked',
                title: 'Approve deployment',
                clientTurnId: 'turn-blocked',
                label: 'Waiting for your input',
                status: HermesStatus.blocked,
                updatedAt: now,
              ),
            ],
            totalCount: 1,
          ),
          ActivityGroup(
            kind: ActivityGroupKind.running,
            items: [
              ActivityItem(
                sessionId: 'live',
                title: 'Still running',
                clientTurnId: 'turn-live',
                label: 'Running',
                status: HermesStatus.running,
                updatedAt: now,
              ),
            ],
            totalCount: 1,
          ),
          ActivityGroup(
            kind: ActivityGroupKind.failed,
            items: [
              ActivityItem(
                sessionId: 'failed',
                title: 'Repair failed turn',
                clientTurnId: 'turn-failed',
                label: 'The turn failed',
                status: HermesStatus.failed,
                updatedAt: now,
              ),
            ],
            totalCount: 1,
          ),
        ],
        blockedCount: 1,
        runningCount: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open inbox (2)'), findsOneWidget);
    await tester.tap(find.byTooltip('Open inbox (2)'));
    await tester.pumpAndSettle();

    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Approve deployment'), findsOneWidget);
    expect(find.text('Repair failed turn'), findsOneWidget);
    expect(find.text('Still running'), findsNothing);

    await tester.tap(find.text('Approve deployment'));
    await tester.pumpAndSettle();
    expect(opened, ['blocked']);
  });

  testWidgets('opening a Home row reports the session to the host', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Roadmap slice')],
      openedSessions: opened,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roadmap slice').first);
    await tester.pumpAndSettle();

    expect(opened, ['s1']);
  });

  testWidgets('a Home row with no host callback opens the chat itself', (
    tester,
  ) async {
    // Without this the shell is a dead end: Home ranks the work that needs
    // Carlos and then refuses to open it.
    final opened = <Session>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Roadmap slice')],
      sessionScreenBuilder: (session) {
        opened.add(session);
        return Scaffold(body: Text('chat:${session.id}'));
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roadmap slice').first);
    await tester.pumpAndSettle();

    expect(opened.map((session) => session.id), ['s1']);
    expect(find.text('chat:s1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a host callback still wins over the built-in chat route', (
    tester,
  ) async {
    // A host that owns navigation must not get a second screen pushed under
    // its own.
    final reported = <String>[];
    final built = <Session>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Roadmap slice')],
      openedSessions: reported,
      sessionScreenBuilder: (session) {
        built.add(session);
        return const Scaffold(body: Text('chat'));
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roadmap slice').first);
    await tester.pumpAndSettle();

    expect(reported, ['s1']);
    expect(built, isEmpty);
    expect(find.text('chat'), findsNothing);
  });

  testWidgets('returning from a chat refreshes the Home digest', (
    tester,
  ) async {
    // Attention state changes while the user is inside the chat: coming back
    // to a stale digest would re-show work that is no longer blocked.
    var reads = 0;
    final repository = await _repository([]);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceScreen(
          connection: _connection(desktopGatewayUrl: 'https://host:8642'),
          repositoryFactory: (_) => repository,
          sessionsLoader: () async {
            reads++;
            return [_session(id: 's1', title: 'Roadmap slice')];
          },
          sessionScreenBuilder: (session) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('back'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final readsBeforeOpening = reads;

    await tester.tap(find.text('Roadmap slice').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    expect(reads, greaterThan(readsBeforeOpening));
    expect(find.text('Roadmap slice'), findsOneWidget);
  });

  testWidgets('the default chat route carries the session and connection', (
    tester,
  ) async {
    // The builder default is what ships; a test that only exercises an
    // injected builder would never notice it handing ChatScreen the wrong
    // connection.
    final connection = _connection(desktopGatewayUrl: 'https://host:8642');
    final session = _session(id: 's1', title: 'Roadmap slice');
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => InertTurnApplicationSession(),
    );
    addTearDown(controller.close);

    final screen = buildWorkspaceChatScreen(
      connection: connection,
      session: session,
      turnApplicationController: controller,
    );

    expect(screen, isA<ChatScreen>());
    final chat = screen as ChatScreen;
    expect(chat.session.id, 's1');
    expect(chat.connection.id, connection.id);
    // The recovery owner outlives the screen; dropping it here would silently
    // break durable turn resume for every chat opened from Home.
    expect(chat.turnApplicationController, same(controller));
  });

  testWidgets('a chat opened from Home inherits the turn recovery owner', (
    tester,
  ) async {
    // Home must not become a second, weaker way into a chat: a turn started
    // from here has to survive leaving the screen exactly like one started
    // from the session list.
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => InertTurnApplicationSession(),
    );
    addTearDown(controller.close);
    final repository = await _repository([]);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceScreen(
          connection: _connection(desktopGatewayUrl: 'https://host:8642'),
          repositoryFactory: (_) => repository,
          turnApplicationController: controller,
          sessionsLoader: () async => [
            _session(id: 's1', title: 'Roadmap slice'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Roadmap slice').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(chat.session.id, 's1');
    expect(chat.turnApplicationController, same(controller));
  });

  testWidgets('a Chats read failure stays recoverable rather than fatal', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessionsError: Exception('offline'),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.could_not_load_conversations), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.retry), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the More destination lists every capability', (tester) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
    await tester.pumpAndSettle();

    expect(find.byType(MorePane), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Cron'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cron'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Settings'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('More opens Unassigned chats as a native Smart View', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: [_session(id: 's1', title: 'Find me')],
      openedSessions: <String>[],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned chats'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);
    expect(find.text('Find me'), findsOneWidget);
  });

  testWidgets('Unassigned shows Home-bucket chats despite scoped_session_ids', (
    tester,
  ) async {
    // Regression: the server's scoped_session_ids covers EVERY tier
    // including the synthetic Home bucket (project_tree.py::_scope on
    // tier 0), so treating it as the claim set made the Unassigned
    // filter permanently empty. Only chats owned by a REAL project are
    // claimed; Home-bucket chats must show.
    final repository = ProjectsRepository(
      client: ProjectsGatewayClient((method, params) async {
        if (method == 'projects.tree') {
          return {
            'jsonrpc': '2.0',
            'id': 1,
            'result': {
              'projects': [
                {
                  'id': '__no_project__',
                  'label': 'Home',
                  'isNoProject': true,
                  'sessionCount': 1,
                  'sessionIds': ['s_home'],
                  'previewSessions': const [],
                },
                {
                  'id': 'p1',
                  'label': 'Filed Project',
                  'isNoProject': false,
                  'sessionCount': 1,
                  'sessionIds': ['s_filed'],
                  'previewSessions': const [],
                },
              ],
              'active_id': null,
              // Both tiers scoped — the trap this fix steps around.
              'scoped_session_ids': ['s_home', 's_filed'],
            },
          };
        }
        if (method == 'projects.list') {
          return {
            'jsonrpc': '2.0',
            'id': 1,
            'result': const {'projects': [], 'active_id': null},
          };
        }
        return {'jsonrpc': '2.0', 'id': 1, 'result': const {}};
      }),
      preferences: await SharedPreferences.getInstance(),
      connectionId: 'conn-1',
    );
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: repository,
      sessions: [
        _session(id: 's_home', title: 'Unfiled chat'),
        _session(id: 's_filed', title: 'Filed chat'),
      ],
      openedSessions: <String>[],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned chats'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);
    expect(find.text('Unfiled chat'), findsOneWidget);
    expect(find.text('Filed chat'), findsNothing);
  });

  testWidgets('More opens the native Files screen', (tester) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      filesScreenBuilder: (_) =>
          const Scaffold(body: Text('Native files ready')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();

    expect(find.text('Native files ready'), findsOneWidget);
  });

  testWidgets('More opens real Assets, opens its source chat and returns', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      sessions: const [],
      assetsSourceFactory: (_) => _WorkspaceAssetsSource(),
      sessionScreenBuilder: (session) {
        opened.add(session.id);
        return Scaffold(
          appBar: AppBar(title: Text(session.title)),
          body: Text('Opened source ${session.id}'),
        );
      },
      size: const Size(600, 1400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(find.byType(AssetsScreen), findsOneWidget);
    expect(find.text('chart.png'), findsOneWidget);
    await tester.tap(find.text('Open chat: Asset source'));
    await tester.pumpAndSettle();
    expect(find.text('Opened source asset-source'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('chart.png'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MorePane), findsOneWidget);
    await tester.tap(find.text('Assets'));
    await tester.pumpAndSettle();
    expect(find.text('chart.png'), findsOneWidget);
    expect(opened, ['asset-source']);
  });

  testWidgets('More offers the embedded dashboard fallback', (tester) async {
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      openedDashboards: opened,
      size: const Size(400, 1600),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Open the Hermes dashboard'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Open the Hermes dashboard'));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    // A distinct Desktop Gateway override is the dashboard authority too.
    expect(opened.single, 'https://host:8642');
    expect(Uri.parse(opened.single).scheme, 'https');
  });

  testWidgets('More disables dashboard entries without a reachable host', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(
      tester,
      connection: _connection(
        desktopGatewayUrl: 'https://host:8642',
        host: '   ',
      ),
      repository: await _repository([]),
      openedDashboards: opened,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cron'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Cron'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(
      find.textContaining('Needs a reachable Hermes dashboard'),
      findsWidgets,
    );
  });

  testWidgets('switching destinations keeps the projects state alive', (
    tester,
  ) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([
        _projectJson(id: 'p1', name: 'Hermes Android'),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();
    expect(find.text('Hermes Android'), findsOneWidget);

    await tester.tap(find.text('Chats').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projects').last);
    await tester.pumpAndSettle();

    expect(find.text('Hermes Android'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the tablet rail on a wide screen', (tester) async {
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: await _repository([]),
      size: const Size(900, 700),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('disposing the screen does not leak the repository stream', (
    tester,
  ) async {
    final repository = await _repository([]);
    await _pump(
      tester,
      connection: _connection(desktopGatewayUrl: 'https://host:8642'),
      repository: repository,
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();

    // A screen that owns an injected repository must not close it: the host
    // still owns that lifecycle.
    await expectLater(repository.refresh(), completes);
    expect(tester.takeException(), isNull);
  });

  group('turn signals feed compact chat attention', () {
    testWidgets('a blocked turn ranks its chat under Needs you', (
      tester,
    ) async {
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: [_session(id: 's1', title: 'Roadmap slice')],
        turnSignalsLoader: (_) async => const HomeTurnSignals(
          attention: {'s1': 'Waiting for your input'},
          running: {},
        ),
      );
      await tester.pumpAndSettle();

      expect(_sectionHeader(HomeSectionKind.needsYou, l10n), findsOneWidget);
      expect(find.text('Waiting for your input'), findsOneWidget);
      expect(
        _sectionHeader(HomeSectionKind.continueWorking, l10n),
        findsNothing,
      );
    });

    testWidgets('a running turn ranks its chat under Running now', (
      tester,
    ) async {
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: [_session(id: 's1', title: 'Roadmap slice')],
        turnSignalsLoader: (_) async =>
            const HomeTurnSignals(attention: {}, running: {'s1'}),
      );
      await tester.pumpAndSettle();

      expect(_sectionHeader(HomeSectionKind.running, l10n), findsOneWidget);
      expect(
        _sectionHeader(HomeSectionKind.continueWorking, l10n),
        findsNothing,
      );
    });

    testWidgets('blocked work raises the Chats badge', (tester) async {
      // The badge is the only signal visible from another destination, so it
      // must reflect blocked work rather than staying empty.
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: [
          _session(id: 's1', title: 'Roadmap slice'),
          _session(id: 's2', title: 'Second slice'),
        ],
        turnSignalsLoader: (_) async => const HomeTurnSignals(
          attention: {'s1': 'The last turn failed', 's2': 'Waiting for you'},
          running: {},
        ),
      );
      await tester.pumpAndSettle();

      final shell = tester.widget<HermesShell>(find.byType(HermesShell));
      expect(shell.badges[HermesDestination.chats], 2);
    });

    testWidgets('a signals read that fails still renders Chats', (
      tester,
    ) async {
      // Losing the recovery journal must degrade the ranking, never the
      // screen: every chat simply falls back to Continue working.
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: [_session(id: 's1', title: 'Roadmap slice')],
        turnSignalsLoader: (_) async => throw Exception('journal unavailable'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Roadmap slice'), findsOneWidget);
      expect(
        _sectionHeader(HomeSectionKind.continueWorking, l10n),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('returning from a chat re-reads the turn signals', (
      tester,
    ) async {
      // A chat is usually opened *because* it was blocked; the reason normally
      // stops being true inside it, so a stale signal would keep it pinned to
      // Needs you forever.
      var reads = 0;
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: [_session(id: 's1', title: 'Roadmap slice')],
        turnSignalsLoader: (_) async {
          reads++;
          return reads == 1
              ? const HomeTurnSignals(
                  attention: {'s1': 'Waiting for your input'},
                  running: {},
                )
              : const HomeTurnSignals(attention: {}, running: {});
        },
        sessionScreenBuilder: (session) => Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('back'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_sectionHeader(HomeSectionKind.needsYou, l10n), findsOneWidget);

      await tester.tap(find.text('Roadmap slice').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();

      expect(reads, greaterThan(1));
      expect(_sectionHeader(HomeSectionKind.needsYou, l10n), findsNothing);
      expect(
        _sectionHeader(HomeSectionKind.continueWorking, l10n),
        findsNothing,
      );
    });

    testWidgets('a legacy connection with no gateway reads no signals', (
      tester,
    ) async {
      // A REST-only connection has no recovery journal scope. Home must still
      // render rather than block on a scope that cannot exist.
      SavedConnection? scoped;
      await _pump(
        tester,
        connection: _connection(),
        sessions: [_session(id: 's1', title: 'Roadmap slice')],
        turnSignalsLoader: (connection) async {
          scoped = connection;
          return HomeTurnSignals.empty;
        },
      );
      await tester.pumpAndSettle();

      expect(find.text('Roadmap slice'), findsOneWidget);
      expect(endpointDigestForConnection(scoped!), isNull);
    });
  });

  group('the global New button', () {
    testWidgets('is offered on Home and Chats', (tester) async {
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: const [],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kWorkspaceNewChatButtonKey), findsOneWidget);

      await tester.tap(find.text(HermesDestination.chats.label(l10n)).last);
      await tester.pumpAndSettle();

      expect(find.byKey(kWorkspaceNewChatButtonKey), findsOneWidget);
    });

    testWidgets('is not offered on the other destinations', (tester) async {
      // New is a Home and Chats affordance. Leaving it floating over Projects
      // or More would make it ambiguous what it would create.
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: const [],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
      await tester.pumpAndSettle();

      expect(find.byKey(kWorkspaceNewChatButtonKey), findsNothing);

      await tester.tap(find.text(HermesDestination.projects.label(l10n)).last);
      await tester.pumpAndSettle();

      expect(find.byKey(kWorkspaceNewChatButtonKey), findsNothing);
    });

    testWidgets('offers both validated modes with their explanations', (
      tester,
    ) async {
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([
          _projectJson(id: 'p1', name: 'Hermes Android'),
        ]),
        sessions: const [],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();

      for (final mode in NewChatMode.values) {
        expect(find.text(mode.label(l10n)), findsOneWidget);
        expect(find.text(mode.description(l10n)), findsOneWidget);
      }
    });

    testWidgets('disables Project chat with a stated reason when the gateway '
        'hosts none, and keeps Quick chat usable', (tester) async {
      // Capability-discovery rule: never hide, always explain. And a legacy
      // gateway must still be able to start work from Home.
      await _pump(tester, connection: _connection(), sessions: const []);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();

      expect(find.text(NewChatMode.projectChat.label(l10n)), findsOneWidget);
      final blocked = tester.widget<ListTile>(
        find.ancestor(
          of: find.text(NewChatMode.projectChat.label(l10n)),
          matching: find.byType(ListTile),
        ),
      );
      expect(blocked.enabled, isFalse);

      final quick = tester.widget<ListTile>(
        find.ancestor(
          of: find.text(NewChatMode.quickChat.label(l10n)),
          matching: find.byType(ListTile),
        ),
      );
      expect(quick.enabled, isTrue);
    });

    testWidgets('a quick chat opens a chat that carries no project', (
      tester,
    ) async {
      final opened = <NewChatDraft>[];
      await _pump(
        tester,
        connection: _connection(),
        sessions: const [],
        onNewChat: opened.add,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.quickChat.label(l10n)));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.isQuick, isTrue);
      expect(opened.single.projectId, isNull);
      expect(opened.single.session.id, isNotEmpty);
    });

    testWidgets('a launcher shortcut opens a Quick Chat without a picker', (
      tester,
    ) async {
      final opened = <NewChatDraft>[];
      await _pump(
        tester,
        connection: _connection(),
        sessions: const [],
        initialQuickChat: true,
        onNewChat: opened.add,
      );
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.isQuick, isTrue);
      expect(opened.single.projectId, isNull);
      expect(find.text(NewChatMode.quickChat.label(l10n)), findsNothing);
    });

    testWidgets('a project chat asks which project and carries it', (
      tester,
    ) async {
      final opened = <NewChatDraft>[];
      final assignments = <Map<String, dynamic>>[];
      final repository = await _repository([
        _projectJson(id: 'p1', name: 'Hermes Android', primaryPath: '/srv/p1'),
        _projectJson(id: 'p2', name: 'ScriptHive', primaryPath: '/srv/p2'),
      ], assignments: assignments);
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: repository,
        sessions: const [],
        onNewChat: opened.add,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.projectChat.label(l10n)));
      await tester.pumpAndSettle();

      expect(find.text('ScriptHive'), findsOneWidget);
      await tester.tap(find.text('ScriptHive'));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.isQuick, isFalse);
      expect(opened.single.projectId, 'p2');
      expect(assignments, isEmpty);
    });

    testWidgets(
      'a project chat carries the project folder as its session cwd',
      (tester) async {
        // Stock filing: the draft's projectWorkingDirectory becomes the
        // session cwd at create time; no assignment RPC is issued and no
        // warning snackbar shows when the Project has a folder.
        final opened = <NewChatDraft>[];
        await _pump(
          tester,
          connection: _connection(desktopGatewayUrl: 'https://host:8642'),
          repository: await _repository([
            _projectJson(
              id: 'p1',
              name: 'Hermes Android',
              primaryPath: '/srv/projects/hermes-android',
            ),
          ]),
          sessions: const [],
          onNewChat: opened.add,
          newChatSessionIdFactory: () => 'stock-project-chat',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.text(NewChatMode.projectChat.label(l10n)));
        await tester.pumpAndSettle();

        expect(opened, hasLength(1));
        expect(opened.single.session.id, 'stock-project-chat');
        expect(opened.single.projectId, 'p1');
        expect(
          opened.single.projectWorkingDirectory,
          '/srv/projects/hermes-android',
        );
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('a folderless Project refuses to open an unassigned chat', (
      tester,
    ) async {
      // Android allows name-only Projects; without a folder the cwd
      // fallback cannot bind the session, so no chat is opened.
      final opened = <NewChatDraft>[];
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([
          _projectJson(id: 'p1', name: 'Nameless'),
        ]),
        sessions: const [],
        onNewChat: opened.add,
        newChatSessionIdFactory: () => 'folderless-chat',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.projectChat.label(l10n)));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(find.textContaining('needs a folder'), findsOneWidget);
    });

    testWidgets('a project chat with exactly one project skips the picker', (
      tester,
    ) async {
      // Asking "which project?" when there is only one is a tap that carries
      // no decision.
      final opened = <NewChatDraft>[];
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([
          _projectJson(
            id: 'p1',
            name: 'Hermes Android',
            primaryPath: '/srv/projects/hermes-android',
          ),
        ]),
        sessions: const [],
        onNewChat: opened.add,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.projectChat.label(l10n)));
      await tester.pumpAndSettle();

      expect(opened, hasLength(1));
      expect(opened.single.projectId, 'p1');
    });

    testWidgets('dismissing the sheet creates nothing', (tester) async {
      final opened = <NewChatDraft>[];
      await _pump(
        tester,
        connection: _connection(),
        sessions: const [],
        onNewChat: opened.add,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.text(NewChatMode.quickChat.label(l10n))),
      ).pop();
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
    });

    testWidgets('every new chat gets its own session id', (tester) async {
      // A reused id would resume the previous chat instead of starting one.
      final opened = <NewChatDraft>[];
      await _pump(
        tester,
        connection: _connection(),
        sessions: const [],
        onNewChat: opened.add,
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.text(NewChatMode.quickChat.label(l10n)));
        await tester.pumpAndSettle();
      }

      expect(opened, hasLength(2));
      expect(opened[0].session.id, isNot(opened[1].session.id));
    });

    testWidgets('the shipped default opens a real chat screen', (tester) async {
      // Without a host callback the shell must open the chat itself, exactly
      // like the Home rows do — otherwise New is an inert button.
      await _pump(tester, connection: _connection(), sessions: const []);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.quickChat.label(l10n)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ChatScreen), findsOneWidget);
    });

    testWidgets(
      'shared text is reviewed before opening a prefilled Quick chat',
      (tester) async {
        await _pump(
          tester,
          connection: _connection(),
          sessions: const [],
          initialSharedText: 'https://example.com/story',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Share to Hermes'), findsOneWidget);
        expect(find.byType(ChatScreen), findsNothing);
        await tester.tap(find.text('Summarize'));
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(ChatScreen), findsOneWidget);
        final composer = tester.widget<TextField>(
          find.byKey(const Key('chat-message-composer')),
        );
        expect(composer.controller?.text, contains('Summarize this content'));
        expect(
          composer.controller?.text,
          contains('https://example.com/story'),
        );
      },
    );

    testWidgets('shared text can commit directly into an active Project', (
      tester,
    ) async {
      final opened = <NewChatDraft>[];
      final assignments = <Map<String, dynamic>>[];
      final repository = await _repository([
        _projectJson(
          id: 'p1',
          name: 'Hermes Android',
          primaryPath: '/srv/projects/hermes-android',
        ),
      ], assignments: assignments);
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: repository,
        sessions: const [],
        initialSharedText: 'Project source material',
        newChatSessionIdFactory: () => 'shared-project-chat',
        onNewChat: opened.add,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.ensureVisible(find.text('Project chat'));
      await tester.tap(find.text('Project chat'));
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(opened.single.projectId, 'p1');
      expect(assignments, isEmpty);
    });
    testWidgets('shared files arrive as confirmed composer attachments', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 44);
      addTearDown(tester.view.resetPadding);

      final prepared = AttachmentDraft(
        id: 'shared-report',
        cachedPath: '/cache/report.pdf',
        name: 'report.pdf',
        byteLength: 2048,
        mediaType: 'application/pdf',
        kind: AttachmentDraftKind.genericFile,
      );
      await _pump(
        tester,
        connection: _connection(),
        sessions: const [],
        initialSharedPayload: const AndroidSharePayload(
          files: [
            AndroidSharedFile(
              path: '/native-cache/report.pdf',
              name: 'report.pdf',
              mediaType: 'application/pdf',
              byteLength: 2048,
            ),
          ],
        ),
        sharedAttachmentPreparer: (_) async => [prepared],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('1 attachment'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Share to Hermes')).dy,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      final composer = tester.widget<TextField>(
        find.byKey(const Key('chat-message-composer')),
      );
      expect(composer.controller?.text, 'Review the attached content.');
    });
  });

  group('Activity destination', () {
    testWidgets('renders the timeline instead of a placeholder', (
      tester,
    ) async {
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: const [],
        activityFeedLoader: (_, _) async => ActivityFeed(
          groups: [
            ActivityGroup(
              kind: ActivityGroupKind.running,
              items: [
                ActivityItem(
                  sessionId: 's1',
                  title: 'Deploy ScriptHive',
                  clientTurnId: 'turn-1',
                  label: 'Running',
                  status: HermesStatus.running,
                  updatedAt: DateTime.now(),
                ),
              ],
              totalCount: 1,
            ),
          ],
          blockedCount: 0,
          runningCount: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();

      expect(find.byType(ActivityPane), findsOneWidget);
      expect(find.text(ActivityGroupKind.running.title(l10n)), findsOneWidget);
      expect(find.text('Deploy ScriptHive'), findsOneWidget);
      expect(find.textContaining('Coming next'), findsNothing);
    });

    testWidgets('titles rows from the sessions Home already read', (
      tester,
    ) async {
      // The turn journal deliberately stores no prose, so without this the
      // whole timeline would read `Untitled chat`. Reusing the session list
      // costs no new gateway contract and no extra request.
      final seen = <Map<String, String>>[];
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: [
          _session(id: 's1', title: 'Roadmap slice'),
          _session(id: 's2', title: 'Other chat'),
        ],
        activityFeedLoader: (_, titles) async {
          seen.add(titles);
          return const ActivityFeed(
            groups: [],
            blockedCount: 0,
            runningCount: 0,
          );
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();

      expect(seen, isNotEmpty);
      expect(seen.last, {'s1': 'Roadmap slice', 's2': 'Other chat'});
    });

    testWidgets('opening a row opens that chat', (tester) async {
      final opened = <String>[];
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: [_session(id: 's1', title: 'Roadmap slice')],
        openedSessions: opened,
        activityFeedLoader: (_, _) async => ActivityFeed(
          groups: [
            ActivityGroup(
              kind: ActivityGroupKind.needsYou,
              items: [
                ActivityItem(
                  sessionId: 's1',
                  title: 'Roadmap slice',
                  clientTurnId: 'turn-1',
                  label: 'Waiting for your input',
                  status: HermesStatus.blocked,
                  updatedAt: DateTime.now(),
                ),
              ],
              totalCount: 1,
            ),
          ],
          blockedCount: 1,
          runningCount: 0,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roadmap slice').first);
      await tester.pumpAndSettle();

      expect(opened, ['s1']);
    });

    testWidgets('a row whose chat is gone does not open a phantom screen', (
      tester,
    ) async {
      // The journal outlives a deleted session. Opening a chat that no longer
      // exists would push a screen that can never load, so the row is a no-op.
      final opened = <String>[];
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: const [],
        openedSessions: opened,
        activityFeedLoader: (_, _) async => ActivityFeed(
          groups: [
            ActivityGroup(
              kind: ActivityGroupKind.running,
              items: [
                ActivityItem(
                  sessionId: 'ghost',
                  clientTurnId: 'turn-1',
                  label: 'Running',
                  status: HermesStatus.running,
                  updatedAt: DateTime.now(),
                ),
              ],
              totalCount: 1,
            ),
          ],
          blockedCount: 0,
          runningCount: 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Untitled chat'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('blocked work raises the Activity badge', (tester) async {
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: const [],
        activityFeedLoader: (_, _) async => ActivityFeed(
          groups: [
            ActivityGroup(
              kind: ActivityGroupKind.needsYou,
              items: [
                ActivityItem(
                  sessionId: 's1',
                  title: 'Blocked chat',
                  clientTurnId: 'turn-1',
                  label: 'Waiting for your input',
                  status: HermesStatus.blocked,
                  updatedAt: DateTime.now(),
                ),
              ],
              totalCount: 2,
            ),
          ],
          // Deliberately larger than the visible item count: a badge states
          // how much work is blocked, not how much of it fits on screen.
          blockedCount: 2,
          runningCount: 0,
        ),
      );
      await tester.pumpAndSettle();

      final shell = tester.widget<HermesShell>(find.byType(HermesShell));
      expect(shell.badges[HermesDestination.activity], 2);
    });

    testWidgets('a feed that cannot be read never breaks the shell', (
      tester,
    ) async {
      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: await _repository([]),
        sessions: const [],
        activityFeedLoader: (_, _) async => throw StateError('journal locked'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(HermesDestination.activity.label(l10n)).last);
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The rest of the shell must keep working while Activity is broken.
      await tester.tap(find.text(HermesDestination.more.label(l10n)).last);
      await tester.pumpAndSettle();
      expect(find.byType(MorePane), findsOneWidget);
    });
    testWidgets('a project chat issues no assignment writes on turn binding', (
      tester,
    ) async {
      // Stock filing is cwd-derived: the chat was created inside the
      // project's folder, so neither its own session.open binding nor any
      // unrelated binding may issue assignment writes.
      final assignments = <Map<String, dynamic>>[];
      final repository = await _repository([
        _projectJson(
          id: 'p1',
          name: 'Hermes Android',
          primaryPath: '/srv/projects/hermes-android',
        ),
      ], assignments: assignments);
      final turnSession = _ControllableTurnSession();
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) => turnSession,
      );
      addTearDown(controller.close);

      await _pump(
        tester,
        connection: _connection(desktopGatewayUrl: 'https://host:8642'),
        repository: repository,
        sessions: const [],
        turnApplicationController: controller,
        newChatSessionIdFactory: () => 'new-project-chat',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kWorkspaceNewChatButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(NewChatMode.projectChat.label(l10n)));
      await tester.pumpAndSettle();

      // A single Project skips the picker and opens the chat directly.
      expect(find.textContaining('New chat · Hermes Android'), findsOneWidget);
      expect(assignments, isEmpty);

      turnSession.fireSessionBound('new-project-chat', '20260829_stored_42');
      turnSession.fireSessionBound('some-other-chat', 'other-stored');
      await tester.pumpAndSettle();

      expect(assignments, isEmpty);
    });
  });
}
