import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/data/session_control.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/session_dock.dart';
import 'package:hermes_android/nextgen/ui/widgets.dart';

SavedConnection _conn() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
);

Map<String, dynamic> _plan(int revision, List<(String, String)> steps) => {
  'revision': revision,
  'todos': [
    for (final (i, (content, status)) in steps.indexed)
      {'id': '${i + 1}', 'content': content, 'status': status},
  ],
};

const _control = {
  'revision': 'r1',
  'goal': {
    'title': 'Ship the release',
    'status': 'active',
    'turns_used': 4,
    'max_turns': 20,
    'subgoals': ['Tests pass', 'Changelog written'],
    'contract': {'outcome': 'A tagged release', 'verification': 'gh release'},
    'gates': [
      {
        'command': 'flutter test',
        'attempts': 1,
        'max_retries': 2,
        'last_exit_code': 0,
      },
    ],
  },
  'loop': {
    'prompt': 'Check CI',
    'status': 'active',
    'interval_seconds': 1800,
    'times': 6,
    'ticks_fired': 2,
  },
};

void main() {
  test('plans parse with nesting, counts and the step in hand', () {
    final list = NgTodoList.parse({
      'revision': 3,
      'todos': [
        {'id': 1, 'content': 'Build', 'status': 'completed'},
        {'id': 2, 'content': 'Test', 'status': 'in_progress'},
        {'id': 3, 'content': 'Unit', 'status': 'pending', 'parent': 2},
        {'id': 4, 'content': 'Skip', 'status': 'cancelled'},
        {'id': 5, 'content': 'Bad', 'status': 'unknown'},
      ],
    })!;
    expect(list.done, 1);
    expect(list.total, 3);
    expect(list.current?.content, 'Test');
    expect(list.tree().map((e) => '${e.$1.content}:${e.$2}'), [
      'Build:0',
      'Test:0',
      'Unit:1',
      'Skip:0',
    ]);
    expect(NgTodoList.parse({'todos': [], 'revision': 0}), isNull);
  });

  test('control snapshots parse goal phase, loop and nothing', () {
    final control = NgSessionControl.parse(_control)!;
    expect(control.goal!.title, 'Ship the release');
    expect(control.goal!.phase, NgGoalPhase.active);
    expect(control.goal!.subgoals, hasLength(2));
    expect(control.goal!.gates.single.lastExitCode, 0);
    expect(control.loop!.ticksFired, 2);
    expect(
      NgGoal.parse({
        'title': 'x',
        'status': 'paused',
        'last_verdict': 'blocked',
      })!.phase,
      NgGoalPhase.blocked,
    );
    expect(NgSessionControl.parse({'goal': null}), isNull);
  });

  group('controller', () {
    late NextGenGateway gateway;
    late NgChatController chat;
    setUp(() {
      gateway = NextGenGateway(_conn());
      chat = NgChatController(gateway, sessionId: 'stored')..runtimeId = 'rt';
    });
    tearDown(() {
      chat.dispose();
      gateway.dispose();
    });
    StreamEvent ev(String type, [Map<String, dynamic> data = const {}]) =>
        StreamEvent(type: type, data: data, sessionId: 'rt');

    test('todo.updated drives a live plan that folds after the turn', () async {
      gateway.debugEmit(ev('message.start'));
      gateway.debugEmit(
        ev(
          'todo.updated',
          _plan(2, [('Build', 'in_progress'), ('Test', 'pending')]),
        ),
      );
      await pumpEventQueue();
      expect(chat.todos!.total, 2);
      expect(chat.todosLive, isTrue);
      // A late, older snapshot doesn't roll the plan back.
      gateway.debugEmit(ev('todo.updated', _plan(1, [('Old', 'pending')])));
      await pumpEventQueue();
      expect(chat.todos!.items.first.content, 'Build');
      gateway.debugEmit(ev('message.complete'));
      await pumpEventQueue();
      expect(chat.todos, isNotNull);
      expect(chat.todosLive, isFalse);
    });

    test('subagent events build the live team the dock shows', () async {
      Map<String, dynamic> sub(
        String id, [
        Map<String, dynamic> more = const {},
      ]) => {'subagent_id': id, 'goal': 'Goal $id', 'task_count': 2, ...more};
      gateway.debugEmit(ev('subagent.spawn_requested', sub('a')));
      gateway.debugEmit(ev('subagent.spawn_requested', sub('b')));
      await pumpEventQueue();
      expect(chat.dockSubagents.map((a) => a.status), [
        NgSubagentStatus.queued,
        NgSubagentStatus.queued,
      ]);
      gateway.debugEmit(ev('subagent.start', sub('a', {'model': 'm1'})));
      gateway.debugEmit(
        ev(
          'subagent.tool',
          sub('a', {
            'tool_name': 'terminal',
            'tool_preview': 'ls   -la',
            'tool_count': 1,
          }),
        ),
      );
      gateway.debugEmit(ev('subagent.thinking', sub('b', {'text': 'Hmm'})));
      await pumpEventQueue();
      final a = chat.subagents.firstWhere((s) => s.id == 'a');
      expect(a.status, NgSubagentStatus.running);
      expect(a.current, 'terminal: ls -la');
      expect(a.model, 'm1');
      expect(chat.subagents.firstWhere((s) => s.id == 'b').current, 'Hmm');
      gateway.debugEmit(
        ev(
          'subagent.complete',
          sub('a', {
            'status': 'completed',
            'summary': 'Listed',
            'duration_seconds': 3.2,
          }),
        ),
      );
      await pumpEventQueue();
      expect(a.status, NgSubagentStatus.done);
      // A finished sibling stays beside the live one.
      expect(chat.dockSubagents, hasLength(2));
      gateway.debugEmit(ev('subagent.complete', sub('b', {'status': 'weird'})));
      await pumpEventQueue();
      expect(chat.subagents.last.status, NgSubagentStatus.failed);
      expect(chat.dockSubagents, isEmpty);
    });

    test('subagent ids fall back to parent, index and goal', () {
      final list = <NgSubagent>[];
      ngApplySubagentEvent(list, 'subagent.start', {
        'goal': 'G',
        'task_index': 1,
      });
      ngApplySubagentEvent(list, 'subagent.progress', {
        'goal': 'G',
        'task_index': 1,
      });
      expect(list.single.id, 'root:1:G');
      ngApplySubagentSnapshots(list, [
        {
          'subagent_id': 'x',
          'goal': 'Late',
          'status': 'running',
          'last_tool': 'read_file',
        },
      ]);
      expect(list.last.current, 'read_file');
    });

    test('session.control.update sets and clears the goal strip', () async {
      gateway.debugEmit(ev('session.control.update', {'control': _control}));
      await pumpEventQueue();
      expect(chat.control!.goal!.title, 'Ship the release');
      gateway.debugEmit(
        ev('session.control.update', {
          'control': {'goal': null, 'loop': null, 'heartbeat': null},
        }),
      );
      await pumpEventQueue();
      expect(chat.control, isNull);
    });

    test('tool calls and replies are timestamped live', () async {
      gateway.debugEmit(ev('message.start'));
      gateway.debugEmit(ev('tool.start', {'tool_id': 't', 'name': 'terminal'}));
      gateway.debugEmit(ev('tool.complete', {'tool_id': 't'}));
      gateway.debugEmit(ev('message.delta', {'text': 'Done'}));
      gateway.debugEmit(ev('message.complete'));
      await pumpEventQueue();
      final reply = chat.items.whereType<NgAssistantItem>().single;
      expect(reply.tools.single.startedAt, isNotNull);
      expect(reply.tools.single.finishedAt, isNotNull);
      expect(reply.time, isNotNull);
    });

    test('history rows keep their own times', () {
      chat.debugApplyHistory([
        {'role': 'user', 'content': 'Hi', 'timestamp': 1700000000},
        {
          'role': 'assistant',
          'content': '',
          'timestamp': 1700000005,
          'tool_calls': [
            {
              'id': 'c1',
              'function': {'name': 'terminal', 'arguments': '{}'},
            },
          ],
        },
        {
          'role': 'tool',
          'tool_call_id': 'c1',
          'content': 'ok',
          'timestamp': 1700000007,
        },
        {'role': 'assistant', 'content': 'Done', 'timestamp': 1700000009},
      ]);
      final user = chat.items.whereType<NgUserItem>().single;
      final reply = chat.items.whereType<NgAssistantItem>().single;
      expect(user.time!.millisecondsSinceEpoch, 1700000000000);
      expect(
        reply.tools.single.startedAt!.millisecondsSinceEpoch,
        1700000005000,
      );
      expect(
        reply.tools.single.finishedAt!.millisecondsSinceEpoch,
        1700000007000,
      );
      expect(reply.time!.millisecondsSinceEpoch, 1700000009000);
    });
  });

  Widget host(Widget child) => MaterialApp(
    theme: nextGenTheme(Brightness.light, NextGenLook.instance),
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  );

  testWidgets('task list shows progress, the current step and every step', (
    tester,
  ) async {
    final todos = NgTodoList.parse(
      _plan(1, [
        ('Build', 'completed'),
        ('Test', 'in_progress'),
        ('Ship', 'pending'),
      ]),
    )!;
    await tester.pumpWidget(host(NgTodoPanel(todos: todos, live: true)));
    expect(find.text('Tasks · 1 of 3'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Ship'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ng-todo-header')));
    await tester.pump();
    // Folded while live, the step in hand still shows.
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Build'), findsNothing);

    await tester.pumpWidget(
      host(NgTodoPanel(key: const ValueKey('past'), todos: todos, live: false)),
    );
    expect(find.text('Last plan · 1 of 3'), findsOneWidget);
    expect(find.text('Build'), findsNothing);
  });

  testWidgets('subagent panel lists each child and stops a live one', (
    tester,
  ) async {
    final list = <NgSubagent>[];
    ngApplySubagentEvent(list, 'subagent.complete', {
      'subagent_id': 'a',
      'goal': 'Read the docs',
      'status': 'completed',
      'summary': 'Read them',
    });
    ngApplySubagentEvent(list, 'subagent.tool', {
      'subagent_id': 'b',
      'goal': 'Fix the build',
      'tool_name': 'terminal',
      'tool_preview': 'make',
      'tool_count': 3,
    });
    final stopped = <String>[];
    await tester.pumpWidget(
      host(
        NgSubagentPanel(agents: list, onStop: (a) async => stopped.add(a.id)),
      ),
    );
    expect(find.text('Subagents · 1 of 2 done'), findsOneWidget);
    expect(find.text('Read them'), findsOneWidget);
    expect(find.text('terminal: make'), findsOneWidget);
    expect(find.textContaining('3 tools'), findsOneWidget);
    expect(find.byKey(const ValueKey('ng-subagent-stop-a')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ng-subagent-stop-b')));
    await tester.pump();
    expect(stopped, ['b']);
    await tester.tap(find.byKey(const ValueKey('ng-subagent-header')));
    await tester.pump();
    expect(find.text('Read them'), findsNothing);
    expect(find.text('Fix the build'), findsOneWidget);
  });

  testWidgets('goal strip summarises goal and loop, and opens the sheet', (
    tester,
  ) async {
    final control = NgSessionControl.parse(_control)!;
    var opened = 0;
    await tester.pumpWidget(
      host(NgControlStrip(control: control, onOpen: () => opened++)),
    );
    expect(find.text('Goal · Working · 4 of 20 turns'), findsOneWidget);
    expect(find.text('Ship the release'), findsOneWidget);
    expect(find.textContaining('Loop · Running · 2 of 6 runs'), findsOneWidget);
    await tester.tap(find.text('Ship the release'));
    expect(opened, 1);
  });

  testWidgets('dock panels fit a narrow phone at large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final control = NgSessionControl.parse({
      'goal': {
        'title': 'A very long goal title that keeps going and going ' * 3,
        'turns_used': 12,
        'max_turns': 200,
        'wait_barrier': {'type': 'session', 'target': 'x', 'reason': 'CI'},
      },
      'heartbeat': {
        'prompt': 'ping',
        'interval_seconds': 5400,
        'fire_count': 12,
      },
    })!;
    final todos = NgTodoList.parse(
      _plan(1, [
        ('A long step name that wraps onto several lines ' * 3, 'in_progress'),
      ]),
    )!;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.6),
        ),
        child: host(
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                NgControlStrip(control: control, onOpen: () {}),
                NgTodoPanel(todos: todos, live: true),
                NgSubagentPanel(
                  agents: [
                    for (var i = 0; i < 6; i++)
                      NgSubagent('s$i', goal: 'A long delegated goal ' * 4)
                        ..model = 'some-provider/a-very-long-model-name'
                        ..toolCount = 42
                        ..activity.add('terminal: ${'x' * 200}'),
                  ],
                  onStop: (_) async {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the control sheet lists contract, sub-goals and checks', (
    tester,
  ) async {
    final gateway = NextGenGateway(_conn());
    final chat = NgChatController(gateway, sessionId: 'stored')
      ..runtimeId = 'rt';
    addTearDown(() {
      chat.dispose();
      gateway.dispose();
    });
    gateway.debugEmit(
      StreamEvent(
        type: 'session.control.update',
        data: {'control': _control},
        sessionId: 'rt',
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      host(SingleChildScrollView(child: NgControlSheet(chat: chat))),
    );
    expect(find.text('Goal and automation'), findsOneWidget);
    expect(find.text('A tagged release'), findsOneWidget);
    expect(find.text('Tests pass'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('1 of 3 attempts · exit 0'), findsOneWidget);
    expect(find.text('Pause'), findsWidgets);
    expect(find.text('Clear goal'), findsOneWidget);
  });

  testWidgets('stamps show the time today and the date before today', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 15, 4, 9);
    String plain(String s) => s.replaceAll(RegExp(r'[\u202f\u00a0]'), ' ');
    expect(plain(ngStamp(ctx, today)), '3:04 PM');
    expect(plain(ngStamp(ctx, today, seconds: true)), '3:04:09 PM');
    final older = DateTime(2020, 3, 5, 9, 30);
    expect(plain(ngStamp(ctx, older)), 'Mar 5, 2020, 9:30 AM');
  });
}
