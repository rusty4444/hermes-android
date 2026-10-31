import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/services/operational_activity_store.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/activity_pane.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

Session row(
  String title, {
  String id = 'chat',
  String? root,
  bool archived = false,
}) => Session(
  id: id,
  title: title,
  model: 'model',
  source: 'cli',
  messageCount: 4,
  isActive: false,
  preview: 'Retained preview',
  startedAt: 1,
  lastActive: DateTime.now().millisecondsSinceEpoch / 1000,
  lineageRootId: root,
  archived: archived,
);
Widget app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: Scaffold(body: child),
);
Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> rename(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Chat actions').last);
  await frames(tester);
  await tester.tap(find.text('Rename'));
  await frames(tester);
  await tester.enterText(find.byType(TextFormField), title);
  await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
  await frames(tester);
}

SavedConnection connection(String id, {bool dashboard = false}) =>
    SavedConnection(
      id: id,
      label: 'Test',
      host: 'fixture.invalid',
      port: 8642,
      apiKey: 'fixture',
      dashboardProxied: dashboard,
    );
http.Response response(Object body) => http.Response(jsonEncode(body), 200);

class RejectingPreferences extends InMemorySharedPreferencesStore {
  RejectingPreferences() : super.empty();
  bool reject = false;
  bool rejectReload = false;
  int attempts = 0;
  @override
  Future<Map<String, Object>> getAll() {
    if (rejectReload) throw StateError('preference reload unavailable');
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.startsWith('flutter.quick_chats_v1_')) {
      attempts++;
      if (reject) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Quick promotion rejects false durability and repairs phantom cache before retry',
    () async {
      final platform = RejectingPreferences();
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      final store = QuickChatStore(prefs, connectionId: 'reject');
      final expired = DateTime.now().subtract(const Duration(days: 1));
      await store.record('chat', expiresAt: expired);
      platform.reject = true;
      await expectLater(store.promote('chat'), throwsStateError);
      expect(
        (await store.load()).statusFor('chat', DateTime.now()),
        QuickChatStatus.archived,
      );
      platform.reject = false;
      await store.promote('chat');
      await prefs.reload();
      expect(
        (await QuickChatStore(
          prefs,
          connectionId: 'reject',
        ).load()).statusFor('chat', DateTime.now()),
        QuickChatStatus.promoted,
      );
      expect(platform.attempts, 3);
    },
  );

  test(
    'failed cache repair cannot turn a rejected promotion into later success',
    () async {
      final platform = RejectingPreferences();
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      final original = QuickChatStore(prefs, connectionId: 'repair-retry');
      await original.record(
        'chat',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      platform.reject = true;
      platform.rejectReload = true;
      await expectLater(original.promote('chat'), throwsStateError);
      final replacement = QuickChatStore(prefs, connectionId: 'repair-retry');
      await expectLater(replacement.promote('chat'), throwsStateError);
      expect(
        platform.attempts,
        2,
        reason: 'the phantom cache cannot bypass failed repair',
      );
      platform.reject = false;
      platform.rejectReload = false;
      await replacement.promote('chat');
      await prefs.reload();
      expect(
        (await replacement.load()).statusFor('chat', DateTime.now()),
        QuickChatStatus.promoted,
      );
      expect(platform.attempts, 3);
    },
  );

  testWidgets(
    'Workspace unarchive keeps retryable expired row after rejected local persistence',
    (tester) async {
      final platform = RejectingPreferences();
      SharedPreferencesStorePlatform.instance = platform;
      final prefs = await SharedPreferences.getInstance();
      final store = QuickChatStore(prefs, connectionId: 'restore-reject');
      await store.record(
        'chat',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      var archived = true;
      var patches = 0;
      Map<String, Object?> jsonRow() => {
        'id': 'chat',
        'title': 'Expired conversation',
        'archived': archived,
        'source': 'cli',
        'message_count': 4,
        'started_at': 1,
      };
      await tester.pumpWidget(
        app(
          WorkspaceScreen(
            connection: connection('restore-reject', dashboard: true),
            installedVersionLoader: () async => null,
            turnSignalsLoader: (_) async => HomeTurnSignals.empty,
            testSessionsHttpClient: MockClient((request) async {
              if (request.method == 'PATCH') {
                patches++;
                archived = false;
                return response({'session': jsonRow()});
              }
              if (request.url.path.endsWith('/chat')) {
                return response({'session': jsonRow()});
              }
              return response({
                'data': request.url.queryParameters['offset'] == '0'
                    ? [jsonRow()]
                    : [],
                'has_more': false,
              });
            }),
            testArchivedSessionsHttpClient: MockClient(
              (_) async => response({
                'sessions': archived ? [jsonRow()] : [],
                'total': archived ? 1 : 0,
              }),
            ),
          ),
        ),
      );
      await frames(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await frames(tester);
      platform.reject = true;
      await tester.tap(find.byTooltip('Chat actions').last);
      await frames(tester);
      await tester.tap(find.text('Unarchive chat'));
      await frames(tester);
      expect(patches, 1);
      expect(find.text('Chat unarchived'), findsNothing);
      expect(find.text('Expired conversation'), findsOneWidget);
      expect(find.textContaining('Could not update'), findsOneWidget);
      expect(
        (await store.load()).statusFor('chat', DateTime.now()),
        QuickChatStatus.archived,
      );
      platform.reject = false;
      await tester.tap(find.text('Retry'));
      await frames(tester);
      expect(patches, 2);
      expect(find.text('Chat unarchived'), findsOneWidget);
      await prefs.reload();
      expect(
        (await store.load()).statusFor('chat', DateTime.now()),
        QuickChatStatus.promoted,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'complete empty archive replaces removed rows while active scan stays held',
    (tester) async {
      final held = Completer<WorkspaceSessionsData>();
      late void Function(WorkspaceSessionsData) publish;
      await tester.pumpWidget(
        app(
          WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            initialData: WorkspaceSessionsData(
              archivedSessions: [row('Removed archive', archived: true)],
            ),
            load: () => held.future,
            loadProgressively: (emit) {
              publish = emit;
              return held.future;
            },
            onOpenSession: (_) {},
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await frames(tester);
      expect(find.text('Removed archive'), findsOneWidget);
      publish(
        const WorkspaceSessionsData(
          isPartial: true,
          sessionsKnown: false,
          archivesKnown: true,
        ),
      );
      await frames(tester);
      expect(find.text('Removed archive'), findsNothing);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
      held.complete(const WorkspaceSessionsData());
      await tester.pump();
    },
  );

  for (final failed in [false, true]) {
    testWidgets(
      'unresolved expired Quick ID cannot claim empty archive: failed=$failed',
      (tester) async {
        await tester.pumpWidget(
          app(
            WorkspaceSessionsScreen(
              title: 'Chats',
              view: WorkspaceSessionView.all,
              embedded: true,
              load: () async => WorkspaceSessionsData(
                sessionsKnown: false,
                isPartial: !failed,
                sessionsError: failed ? StateError('active offline') : null,
                archivesKnown: true,
                archivedQuickChatIds: const {'missing-expired'},
              ),
              onOpenSession: (_) {},
            ),
          ),
        );
        await frames(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
        await frames(tester);
        expect(find.byType(EmptyState), findsNothing);
        expect(
          failed ? find.text('Retry') : find.byType(LinearProgressIndicator),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Archived Retry resolves unknown Quick history through active authority',
    (tester) async {
      var activeReads = 0;
      var archiveReads = 0;
      await tester.pumpWidget(
        app(
          WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            load: () async => WorkspaceSessionsData(
              sessionsKnown: false,
              sessionsError: StateError('active offline'),
              archivesKnown: true,
              archivedQuickChatIds: const {'expired'},
            ),
            reloadActive: (_) async {
              activeReads++;
              return WorkspaceSessionsData(
                sessions: [row('Recovered expired chat', id: 'expired')],
                archivedQuickChatIds: const {'expired'},
              );
            },
            reloadArchives: (_) async {
              archiveReads++;
              return [];
            },
            onOpenSession: (_) {},
          ),
        ),
      );
      await frames(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await frames(tester);
      expect(find.byType(EmptyState), findsNothing);
      await tester.tap(find.text('Retry'));
      await frames(tester);
      expect(activeReads, 1);
      expect(
        archiveReads,
        0,
        reason: 'the completed server archive cannot resolve local Quick IDs',
      );
      expect(find.text('Recovered expired chat'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final archives in [false, true]) {
    testWidgets(
      'old aggregate preserves fresh ${archives ? 'archive' : 'active'} title epoch after local rename',
      (tester) async {
        final held = Completer<WorkspaceSessionsData>();
        final key = GlobalKey<WorkspaceSessionsScreenState>();
        final initial = row('Initial', archived: archives);
        WorkspaceSessionsData data(Session r) => WorkspaceSessionsData(
          sessions: archives ? const [] : [r],
          archivedSessions: archives ? [r] : const [],
        );
        await tester.pumpWidget(
          app(
            WorkspaceSessionsScreen(
              key: key,
              title: 'Chats',
              view: WorkspaceSessionView.all,
              embedded: true,
              initialData: data(initial),
              load: () => held.future,
              reloadActive: (_) async =>
                  data(initial.withTitle('New external title')),
              reloadArchives: (_) async => [
                initial.withTitle('New external title'),
              ],
              onRename: (_, title) async => title,
              onOpenSession: (_) {},
            ),
          ),
        );
        if (archives) {
          await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
          await frames(tester);
        }
        await rename(tester, 'Confirmed local rename');
        expect(find.text('Confirmed local rename'), findsOneWidget);
        await key.currentState!.refresh();
        await frames(tester);
        expect(find.text('New external title'), findsOneWidget);
        held.complete(data(initial));
        await frames(tester);
        expect(find.text('New external title'), findsOneWidget);
        expect(find.text('Confirmed local rename'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'preconstructed pin store hydrates at mount before held history completes',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final pins = LocalChatPinStore(prefs, connectionId: 'ready-pins');
      await pins.setPinned('chat', pinned: true);
      final held = Completer<WorkspaceSessionsData>();
      await tester.pumpWidget(
        app(
          WorkspaceSessionsScreen(
            title: 'Chats',
            view: WorkspaceSessionView.all,
            embedded: true,
            initialData: WorkspaceSessionsData(
              sessions: [row('Pinned conversation')],
              archivedIsPartial: true,
            ),
            pinStore: pins,
            load: () => held.future,
            onOpenSession: (_) {},
          ),
        ),
      );
      await frames(tester);
      expect(find.text('Pinned on this device'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      held.complete(const WorkspaceSessionsData());
      await tester.pump();
    },
  );

  for (final view in [
    WorkspaceSessionView.search,
    WorkspaceSessionView.unassigned,
  ]) {
    testWidgets(
      'standalone ${view.name} rename reconciles retained embedded Chats',
      (tester) async {
        var title = 'Initial title';
        await tester.pumpWidget(
          app(
            WorkspaceScreen(
              connection: connection('standalone-${view.name}'),
              installedVersionLoader: () async => null,
              sessionsLoader: () async => [row(title)],
              turnSignalsLoader: (_) async => HomeTurnSignals.empty,
              testSessionsHttpClient: MockClient((request) async {
                title = (jsonDecode(request.body) as Map)['title'] as String;
                return response({
                  'session': {'id': 'chat', 'title': title},
                });
              }),
            ),
          ),
        );
        await frames(tester);
        if (view == WorkspaceSessionView.search) {
          await tester.tap(find.byTooltip('Search all chats'));
        } else {
          await tester.tap(find.text('More').last);
          await frames(tester);
          await tester.tap(find.text('Unassigned chats'));
        }
        await frames(tester);
        await rename(tester, 'Standalone saved title');
        await tester.pageBack();
        await frames(tester);
        if (view == WorkspaceSessionView.unassigned) {
          await tester.tap(find.text('Chats').last);
          await frames(tester);
        }
        expect(find.text('Standalone saved title'), findsOneWidget);
        expect(find.text('Initial title'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'persisted historical Activity tip retains root across workspace and preference restart',
    (tester) async {
      final store = OperationalActivityStore();
      final c = connection('lineage-restart');
      final controller = GatewayTurnApplicationController(activityStore: store);
      final scope = controller.normalSessionFor(c).scope;
      await store.put(
        OperationalActivityRecord(
          scope: scope,
          localSessionId: 'local',
          storedSessionId: 'tip-1',
          turnId: 'actual-turn',
          state: OperationalActivityState.completed,
          updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      Widget workspace(
        GatewayTurnApplicationController owner,
        String tip,
        List<String> opened,
      ) => app(
        WorkspaceScreen(
          connection: c,
          turnApplicationController: owner,
          sessionsLoader: () async => [
            row('Conversation', id: tip, root: 'root'),
          ],
          installedVersionLoader: () async => null,
          onOpenSession: (session) => opened.add(session.id),
        ),
      );
      await tester.pumpWidget(workspace(controller, 'tip-1', []));
      await frames(tester);
      await tester.tap(find.text('Activity').last);
      await frames(tester);
      expect(find.text('Conversation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await controller.close();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final durable = prefs.getKeys().fold<Map<String, Object>>(
        {},
        (all, key) => all..[key] = prefs.get(key)!,
      );
      SharedPreferences.setMockInitialValues(durable);
      final replacement = GatewayTurnApplicationController();
      final opened = <String>[];
      await tester.pumpWidget(workspace(replacement, 'tip-2', opened));
      await frames(tester);
      await tester.tap(find.text('Activity').last);
      await frames(tester);
      final feed = await tester
          .widget<ActivityPane>(find.byType(ActivityPane))
          .loadFeed();
      expect(
        feed.groups
            .expand((group) => group.items)
            .map((item) => item.sessionId),
        ['tip-2'],
      );
      expect(find.text('Conversation'), findsOneWidget);
      await tester.tap(find.text('Conversation'));
      await frames(tester);
      expect(opened, ['tip-2']);
      await tester.pumpWidget(const SizedBox());
      await replacement.close();
    },
  );

  testWidgets(
    'uncached Activity root lookup navigates to canonical returned tip',
    (tester) async {
      final opened = <String>[];
      var lookups = 0;
      await tester.pumpWidget(
        app(
          WorkspaceScreen(
            connection: connection('fallback'),
            sessionsLoader: () async => [],
            installedVersionLoader: () async => null,
            activityFeedLoader: (_, _) async => ActivityFeed(
              groups: [
                ActivityGroup(
                  kind: ActivityGroupKind.completed,
                  totalCount: 1,
                  items: [
                    ActivityItem(
                      sessionId: 'root',
                      clientTurnId: 'turn',
                      title: 'Older activity',
                      label: 'Completed',
                      status: HermesStatus.completed,
                      updatedAt: DateTime.now(),
                    ),
                  ],
                ),
              ],
              blockedCount: 0,
              runningCount: 0,
            ),
            testSessionsHttpClient: MockClient((_) async {
              lookups++;
              return response({
                'data': [
                  {
                    'id': 'current-tip',
                    '_lineage_root_id': 'root',
                    'title': 'Canonical conversation',
                    'source': 'cli',
                  },
                ],
                'has_more': false,
              });
            }),
            onOpenSession: (session) => opened.add(session.id),
          ),
        ),
      );
      await frames(tester);
      await tester.tap(find.text('Activity').last);
      await frames(tester);
      await tester.tap(find.text('Older activity'));
      await frames(tester);
      expect(lookups, 1);
      expect(opened, ['current-tip']);
      expect(find.text('This chat is no longer available'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
