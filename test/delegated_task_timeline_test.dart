import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/delegated_task_controller.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';

import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/delegated_task_labels.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'delegated_task_spec_regression_test.dart' show fixture, delegationRows;
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';
import 'delegated_task_history_test.dart' show FakeHistory, rows, task;

Widget app(Widget home) => MaterialApp(
  theme: hermesTheme(Brightness.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    mockChatImageRecovery();
  });

  test(
    'every shipped locale resolves task labels and typed failures',
    () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(l10n.task_timeline, isNotEmpty);
        expect(l10n.task_call_details('call', '{}'), contains('call'));
        expect(
          l10n.task_status(l10n.status_running),
          contains(l10n.status_running),
        );
        expect(
          delegatedTaskGoal(
            l10n,
            const GatewaySubagentActivity(
              id: 'r',
              goal: '',
              phase: GatewaySubagentPhase.running,
            ),
          ),
          l10n.task_default_goal,
        );
        for (final problem in TaskHistoryProblem.values) {
          expect(taskHistoryProblemLabel(l10n, problem), isNotEmpty);
        }
      }
    },
  );

  for (final (status, icon, label) in [
    ('failed', Icons.error_outline, 'Failed'),
    ('error', Icons.error_outline, 'Failed'),
    ('interrupted', Icons.pause_circle_outline, 'Interrupted'),
    ('cancelled', Icons.cancel_outlined, 'Cancelled'),
    ('completed', Icons.check_circle_outline, 'Completed'),
  ]) {
    testWidgets(
      '$status has an accessible honest terminal icon and group heading',
      (tester) async {
        final activity = GatewaySubagentActivity.fromGatewayEvent(
          'subagent.complete',
          {'subagent_id': 'r', 'goal': 'Inspect', 'status': status},
        )!;
        await tester.pumpWidget(
          app(Scaffold(body: GatewaySubagentCard(activities: [activity]))),
        );
        final succeeded = status == 'completed';
        expect(
          find.text(
            succeeded
                ? '1 delegated task(s) completed'
                : '1 delegated task(s) finished',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('delegated-task-r'));
        final leading = tester.widget<ListTile>(row).leading! as Icon;
        expect(leading.icon, icon);
        expect(leading.semanticLabel, label);
        if (!succeeded) {
          expect(find.byIcon(Icons.check_circle_outline), findsNothing);
        }
        if (status == 'failed' || status == 'error') {
          expect(
            leading.color,
            Theme.of(tester.element(row)).colorScheme.error,
          );
        }
      },
    );
  }

  testWidgets(
    'backend commentary-only row renders public prose with one collapsed reasoning carrier',
    (tester) async {
      final projected = (fixture['with_compacted']['messages'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((row) => row.containsKey('display_commentary'));
      final history = FakeHistory()..data = [projected];
      final controller = DelegatedTaskController(task: task, history: history);
      await tester.pumpWidget(
        app(Scaffold(body: DelegatedTaskTimeline(controller: controller))),
      );
      await tester.pump();
      expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
        'Public progress',
      );
      expect(find.widgetWithText(ExpansionTile, 'Reasoning'), findsOneWidget);
      await tester.tap(find.text('Reasoning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Exposed reasoning').hitTestable(), findsOneWidget);
      expect(find.text('Public progress\n\nExposed reasoning'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final action in ['steer', 'stop']) {
    testWidgets(
      'ChatScreen hydrate $action ACK preserves live child until real completion',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final hook = TestDesktopAsyncEventHook();
        final history = FakeHistory();
        var persistedAck = false;
        var reads = 0;
        await tester.pumpWidget(
          app(
            ChatScreen(
              connection: SavedConnection(
                id: 'ack',
                label: 'ack',
                host: 'parent.fixture',
                port: 8642,
                apiKey: 'fixture',
              ),
              session: const Session(
                id: 'parent',
                title: 'Parent',
                model: 'fixture',
                source: 'api_server',
                messageCount: 2,
                isActive: true,
                preview: '',
                startedAt: 1,
              ),
              testApiClient: ApiClient(
                baseUrl: 'http://parent.fixture',
                apiKey: 'fixture',
                httpClient: MockClient((request) async {
                  reads++;
                  return http.Response(
                    jsonEncode({
                      'data': [
                        {'id': 10, 'role': 'user', 'content': 'Delegate'},
                        {
                          'id': 11,
                          'role': 'assistant',
                          'content': 'Delegating',
                        },
                        if (persistedAck)
                          ...delegationRows(
                            action,
                            fixture['${action}_ack'] as Map<String, dynamic>,
                          ).map(
                            (row) => {...row, 'id': (row['id'] as int) + 11},
                          ),
                      ],
                    }),
                    200,
                  );
                }),
              ),
              testDesktopAsyncEventHook: hook,
              testTaskHistorySource: () => history,
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        hook.handler!(
          StreamEvent(
            type: 'subagent.start',
            data: {
              'subagent_id': 'runtime',
              'child_session_id': 'stored-child',
              'goal': 'Inspect',
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        persistedAck = true;
        final before = reads;
        await tester.tap(find.byTooltip('Chat actions'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Refresh'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(reads, greaterThan(before));
        hook.handler!(
          StreamEvent(
            type: 'subagent.text',
            data: {'subagent_id': 'runtime', 'text': 'Late progress'},
          ),
        );
        await tester.pump();
        final card = tester.widget<GatewaySubagentCard>(
          find.byType(GatewaySubagentCard),
        );
        expect(card.activities, hasLength(1));
        expect(card.activities.single.isComplete, isFalse);
        final taskSection = find.descendant(
          of: find.byType(GatewaySubagentCard),
          matching: find.byType(ExpansionTile),
        );
        bool taskExpanded() => tester
            .widget<Expansible>(
              find.descendant(
                of: taskSection,
                matching: find.byType(Expansible),
              ),
            )
            .controller
            .isExpanded;
        expect(taskExpanded(), isFalse);
        await tester.ensureVisible(taskSection);
        await tester.tap(taskSection);
        await tester.pump(const Duration(milliseconds: 300));
        expect(taskExpanded(), isTrue);
        final row = find.byKey(const ValueKey('delegated-task-runtime'));
        await tester.scrollUntilVisible(
          row.hitTestable(),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(row.hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final count = history.offsets.length;
        await tester.pump(const Duration(seconds: 2));
        expect(history.offsets.length, greaterThan(count));
        hook.handler!(
          StreamEvent(
            type: 'subagent.complete',
            data: {'subagent_id': 'runtime', 'status': 'completed'},
          ),
        );
        await tester.pump();
        expect(find.text('Status: Completed'), findsOneWidget);
        final finalCount = history.offsets.length;
        await tester.pump(const Duration(seconds: 4));
        expect(history.offsets, hasLength(finalCount));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'widget lifecycle pauses polling and disposal fences a pending response',
    (tester) async {
      final history = FakeHistory()..data = rows(1, 2);
      final controller = DelegatedTaskController(task: task, history: history);
      await tester.pumpWidget(
        app(Scaffold(body: DelegatedTaskTimeline(controller: controller))),
      );
      await tester.pump();
      expect(history.offsets, [0]);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump(const Duration(seconds: 10));
      expect(history.offsets, [0]);
      history.gate = Completer<List<Map<String, dynamic>>>();
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(history.offsets, [0, 0]);
      await tester.pumpWidget(const SizedBox());
      history.gate!.complete(rows(1, 3));
      await tester.pump();
      expect(controller.rows, hasLength(2));
      expect(history.closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final retained in [true, false]) {
    testWidgets(
      'completed stored delegation reopens with retained reference=$retained',
      (tester) async {
        final history = FakeHistory()
          ..data = [
            {'id': 1, 'role': 'assistant', 'content': 'Recorded child reply'},
          ];
        await tester.pumpWidget(
          app(
            ChatScreen(
              connection: SavedConnection(
                id: 'stored-c',
                label: 'c',
                host: 'parent.fixture',
                port: 8642,
                apiKey: 'fixture',
              ),
              session: const Session(
                id: 'stored-parent',
                title: 'Parent',
                model: 'fixture',
                source: 'api_server',
                messageCount: 3,
                isActive: false,
                preview: '',
                startedAt: 1,
              ),
              testApiClient: ApiClient(
                baseUrl: 'http://parent.fixture',
                apiKey: 'fixture',
                httpClient: MockClient(
                  (request) async => http.Response(
                    jsonEncode({
                      'data': [
                        {'id': 1, 'role': 'user', 'content': 'Delegate this'},
                        {
                          'id': 2,
                          'role': 'assistant',
                          'content': '',
                          'tool_calls': [
                            {
                              'id': 'delegation-call',
                              'function': {
                                'name': 'delegate_task',
                                'arguments': '{"goal":"Stored task"}',
                              },
                            },
                          ],
                        },
                        {
                          'id': 3,
                          'role': 'tool',
                          'tool_call_id': 'delegation-call',
                          'content': jsonEncode({
                            'results': [
                              {
                                'status': 'completed',
                                'summary': 'Task finished',
                                if (retained)
                                  'child_session_id': 'stored-child',
                              },
                            ],
                          }),
                        },
                      ],
                    }),
                    200,
                  ),
                ),
              ),
              testTaskHistorySource: () => history,
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byType(GatewaySubagentCard);
        expect(card, findsOneWidget);
        await tester.tap(
          find.descendant(of: card, matching: find.byType(ExpansionTile)),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Stored task'));
        await tester.tap(find.text('Stored task'));
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.text('Status: Completed'), findsOneWidget);
        if (retained) {
          expect(history.offsets, [0]);
          expect(find.text('Stored session: stored-child'), findsOneWidget);
          expect(find.byType(MarkdownBody), findsWidgets);
        } else {
          expect(history.offsets, isEmpty);
          expect(
            find.textContaining('did not retain its session reference'),
            findsOneWidget,
          );
        }
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'overlay loading/error/retry, rich transcript and stable collapsed details',
    (tester) async {
      final history = FakeHistory()
        ..gate = Completer<List<Map<String, dynamic>>>();
      final controller = DelegatedTaskController(task: task, history: history);
      await tester.pumpWidget(
        app(Scaffold(body: DelegatedTaskTimeline(controller: controller))),
      );
      expect(find.text('Loading task history…'), findsOneWidget);
      history.gate!.completeError(Exception('offline'));
      await tester.pump();
      expect(
        find.textContaining('Could not refresh task history'),
        findsOneWidget,
      );
      history.gate = null;
      history.data = [
        {
          'id': 1,
          'role': 'assistant',
          'content': '**Recorded prose**',
          'reasoning_details': '[{"text":"Exposed thought"}]',
          'tool_calls': [
            {
              'id': 'c',
              'function': {
                'name': 'terminal',
                'arguments': '{"command":"pwd"}',
              },
            },
          ],
        },
        {
          'id': 2,
          'role': 'tool',
          'tool_call_id': 'c',
          'content': 'actual result',
        },
      ];
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
      final reasoning = find.widgetWithText(ExpansionTile, 'Reasoning');
      expect(
        tester.widget<ExpansionTile>(reasoning).initiallyExpanded,
        isFalse,
      );
      await tester.tap(find.text('Reasoning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Exposed thought').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Tool call · terminal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('"command":"pwd"').hitTestable(),
        findsOneWidget,
      );
      history.data.first['reasoning'] = 'New sidecar';
      await controller.refresh();
      await tester.pump();
      expect(find.text('Exposed thought').hitTestable(), findsOneWidget);
      final newReasoning = find.byKey(
        const PageStorageKey('reasoning:1:reasoning:0'),
      );
      expect(
        tester.widget<ExpansionTile>(newReasoning).initiallyExpanded,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      expect(history.closed, isTrue);
    },
  );

  testWidgets(
    'empty differs from unavailable metadata and older paging is explicit',
    (tester) async {
      final history = FakeHistory()..data = rows(51, 100);
      final controller = DelegatedTaskController(task: task, history: history);
      await tester.pumpWidget(
        app(Scaffold(body: DelegatedTaskTimeline(controller: controller))),
      );
      await tester.pump();
      expect(history.offsets, [0]);
      expect(find.text('Load older'), findsOneWidget);
      history.data = rows(1, 50);
      await tester.tap(find.text('Load older'));
      await tester.pump();
      expect(history.offsets, [0, 50]);
      expect(controller.rows, hasLength(100));
      await tester.pumpWidget(const SizedBox());

      final empty = DelegatedTaskController(task: task, history: FakeHistory());
      await tester.pumpWidget(
        app(Scaffold(body: DelegatedTaskTimeline(controller: empty))),
      );
      await tester.pump();
      expect(find.textContaining('No recorded messages yet'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      final absent = DelegatedTaskController(
        task: const GatewaySubagentActivity(
          id: 'r',
          goal: 'Legacy',
          phase: GatewaySubagentPhase.completed,
        ),
        history: FakeHistory(),
      );
      await tester.pumpWidget(
        app(Scaffold(body: DelegatedTaskTimeline(controller: absent))),
      );
      expect(
        find.textContaining('did not retain its session reference'),
        findsOneWidget,
      );
      expect(find.textContaining('No recorded messages yet'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final (width, completeWhileOpen) in [
    (430.0, true),
    (1000.0, true),
    (430.0, false),
    (1000.0, false),
  ]) {
    testWidgets(
      'ChatScreen parent stream and queued follow stay frozen under task modal at width $width; complete while open=$completeWhileOpen',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final hook = TestDesktopAsyncEventHook();
        final requests = <Uri>[];
        var childSourceCount = 0;
        final submit = Completer<void>();
        late StreamCallback parentEvent;
        final history = FakeHistory()
          ..data = [
            {'id': 1, 'role': 'agent', 'content': 'Child answer'},
          ];
        final chatKey = GlobalKey();
        final turnController = GatewayTurnApplicationController();
        addTearDown(turnController.close);
        final connection = SavedConnection(
          id: 'c',
          label: 'c',
          host: 'parent.fixture',
          port: 8642,
          apiKey: 'unused',
        );
        await tester.pumpWidget(
          app(
            ChatScreen(
              key: chatKey,
              connection: connection,
              turnApplicationController: turnController,
              session: const Session(
                id: 'parent',
                title: 'Parent',
                model: 'fixture',
                source: 'api_server',
                messageCount: 2,
                isActive: true,
                preview: '',
                startedAt: 1,
              ),
              testApiClient: ApiClient(
                baseUrl: 'http://parent.fixture',
                apiKey: 'unused',
                httpClient: MockClient((request) async {
                  requests.add(request.url);
                  expectSync(request.method, 'GET');
                  return http.Response(
                    jsonEncode({
                      'data': [
                        {'id': 1, 'role': 'user', 'content': 'Parent question'},
                        {
                          'id': 2,
                          'role': 'assistant',
                          'content': 'Parent answer\n\n' * 25,
                        },
                      ],
                    }),
                    200,
                  );
                }),
              ),
              testDesktopAsyncEventHook: hook,
              testRemotePromptSubmit:
                  ({
                    required sessionId,
                    required text,
                    required onEvent,
                    required onSent,
                  }) {
                    parentEvent = onEvent;
                    onSent();
                    return submit.future;
                  },
              testTaskHistorySource: () {
                childSourceCount++;
                return history;
              },
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final composer = find.byType(TextField).first;
        await tester.enterText(composer, 'Continue parent');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        hook.handler!(
          StreamEvent(
            type: 'subagent.start',
            data: {
              'subagent_id': 'runtime',
              'child_session_id': 'stored-child',
              'goal': 'Inspect',
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final taskSection = find.descendant(
          of: find.byType(GatewaySubagentCard),
          matching: find.byType(ExpansionTile),
        );
        bool taskExpanded() => tester
            .widget<Expansible>(
              find.descendant(
                of: taskSection,
                matching: find.byType(Expansible),
              ),
            )
            .controller
            .isExpanded;
        expect(taskExpanded(), isFalse);
        await tester.ensureVisible(taskSection);
        await tester.tap(taskSection);
        await tester.pump(const Duration(milliseconds: 300));
        expect(taskExpanded(), isTrue);
        final row = find.byKey(const ValueKey('delegated-task-runtime'));
        await tester.ensureVisible(row);
        await tester.pump();
        await tester.enterText(composer, 'Keep this draft');
        final parentState = chatKey.currentState;
        final parentScrollable = find
            .descendant(
              of: find.byType(ChatScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester
            .state<ScrollableState>(parentScrollable)
            .position;
        // Programmatic positioning must not change the sticky follow intent.
        // The parent is near the end but not at it when inspection opens.
        // Expanded verbose cards update lazy extent estimates after layout.
        for (var i = 0; i < 3; i++) {
          position.jumpTo(position.maxScrollExtent - 10);
          await tester.pump(const Duration(milliseconds: 300));
        }
        final offset = position.pixels;
        expect(offset, lessThan(position.maxScrollExtent));
        expect(row.hitTestable(), findsOneWidget);
        final requestsBefore = requests.length;
        const queuedText = 'Queued parent text\n\n';
        // Hold the real stream's scheduled post-frame follow until AFTER the
        // task tap opens the modal synchronously (no intervening pump).
        parentEvent(
          StreamEvent(type: 'message.delta', data: {'text': queuedText}),
        );
        await tester.tap(row.hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Task timeline'), findsOneWidget);
        expect(
          width >= 700 ? find.byType(Dialog) : find.byType(BottomSheet),
          findsOneWidget,
        );
        expect(childSourceCount, 1);
        expect(history.offsets, [0]);
        expect(chatKey.currentState, same(parentState));
        expect(position.pixels, offset, reason: 'pre-open queued callback');
        const liveText = 'Parent text while inspecting\n\n';
        parentEvent(
          StreamEvent(type: 'message.delta', data: {'text': liveText}),
        );
        await tester.pump();
        expect(position.pixels, offset, reason: 'parent text');
        parentEvent(
          StreamEvent(
            type: 'reasoning.delta',
            data: {'text': 'Parent exposed reasoning while inspecting'},
          ),
        );
        await tester.pump();
        expect(position.pixels, offset, reason: 'parent reasoning');
        parentEvent(
          StreamEvent(
            type: 'tool.start',
            data: {
              'tool': 'terminal',
              'tool_id': 'parent-tool',
              'label': 'Parent tool while inspecting',
            },
          ),
        );
        await tester.pump();
        expect(position.pixels, offset, reason: 'parent tool');
        parentEvent(
          StreamEvent(
            type: 'tool.complete',
            data: {
              'tool': 'terminal',
              'tool_id': 'parent-tool',
              'summary': 'Parent tool completed while inspecting',
            },
          ),
        );
        await tester.pump();
        expect(position.pixels, offset, reason: 'parent tool completion');
        expect(
          requests,
          hasLength(requestsBefore),
          reason: 'inspection makes no parent request',
        );
        const finalText =
            '$queuedText${liveText}Parent completed while inspecting';
        if (completeWhileOpen) {
          parentEvent(
            StreamEvent(type: 'message.complete', data: {'text': finalText}),
          );
          submit.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(position.pixels, offset, reason: 'parent completion target');
        }
        // The app owner may hydrate parent history after its own terminal.
        final requestsAfterParentTerminal = requests.length;
        hook.handler!(
          StreamEvent(
            type: 'subagent.complete',
            data: {
              'subagent_id': 'runtime',
              'status': 'failed',
              'summary': 'Failed safely',
            },
          ),
        );
        await tester.pump();
        expect(find.text('Status: Failed'), findsOneWidget);
        expect(requests, hasLength(requestsAfterParentTerminal));
        expect(position.pixels, offset);
        if (width < 700) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.text('Close'));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Task timeline'), findsNothing);
        expect(chatKey.currentState, same(parentState));
        expect(
          tester.widget<TextField>(composer).controller!.text,
          'Keep this draft',
        );
        expect(position.pixels, offset);
        expect(history.closed, isTrue);
        if (!completeWhileOpen) {
          // Inspection did not cancel sticky follow. A NEW post-dismissal
          // parent event follows normally; dismissal itself never jumps.
          parentEvent(
            StreamEvent(type: 'message.complete', data: {'text': finalText}),
          );
          submit.complete();
          await pumpChatUpdates(tester);
          expect(position.pixels, greaterThan(offset));
          // An unsettled owner keeps its activity bar animating. Wait for
          // the actual follow target, not global animation idleness.
          for (
            var i = 0;
            i < 20 && (position.pixels - position.maxScrollExtent).abs() > 1;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 50));
            await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          }
          expect(position.pixels, closeTo(position.maxScrollExtent, 1));
        }
        // Only scroll application was suppressed, never stream content.
        // Receipt-ordered prose remains split around reasoning/tool runs.
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        // Source headings can move an earlier receipt outside a phone's lazy
        // viewport. Prove the complete retained prose as well as the actual
        // mounted final bubble; absence of an evicted child is not data loss.
        final retained = turnController
            .normalSessionFor(connection)
            .findChat('parent')!
            .snapshot;
        expect(
          retained.displayRows
              .where((row) => row['role'] == 'assistant')
              .map((row) => row['content'])
              .join(),
          endsWith(finalText),
        );
        expect(
          tester
              .widgetList<MessageBubble>(find.byType(MessageBubble))
              .map((bubble) => bubble.content)
              .join(),
          endsWith('Parent completed while inspecting'),
        );
        await tester.scrollUntilVisible(
          find.byType(GatewayReasoningCard),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widgetList<GatewayReasoningCard>(
                find.byType(GatewayReasoningCard),
              )
              .map((card) => card.text),
          contains('Parent exposed reasoning while inspecting'),
        );
        await tester.scrollUntilVisible(
          find.byType(GatewayActivityCard),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byType(GatewayActivityCard), findsOneWidget);
        final parentTool = tester
            .widget<GatewayActivityCard>(find.byType(GatewayActivityCard))
            .activities
            .single;
        expect(parentTool.toolId, 'parent-tool');
        expect(parentTool.isTerminal, isTrue);
        expect(parentTool.detail, 'Parent tool completed while inspecting');
        // A late task progress event cannot regress failure or target another ID.
        hook.handler!(
          StreamEvent(
            type: 'subagent.text',
            data: {'subagent_id': 'runtime', 'text': 'Late'},
          ),
        );
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byType(GatewaySubagentCard),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          tester
              .widget<GatewaySubagentCard>(find.byType(GatewaySubagentCard))
              .activities
              .single
              .failed,
          isTrue,
        );
        await turnController.close();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
