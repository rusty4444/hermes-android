import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/utils/chat_history_scroll.dart';

GatewayToolActivity tool(
  String id, {
  bool complete = false,
  String? identity,
  DateTime? at,
}) => GatewayToolActivity(
  name: 'terminal',
  toolId: id,
  identity: identity,
  phase: complete
      ? GatewayToolActivityPhase.completed
      : GatewayToolActivityPhase.running,
  lastActivityAt: at,
  lastActivityTimeSource: at == null ? null : GatewayToolTimeSource.observed,
);
GatewayReasoningUpdate reasoning(String text, {bool replace = false}) =>
    GatewayReasoningUpdate(
      text: text,
      mode: replace
          ? GatewayReasoningEventMode.replace
          : GatewayReasoningEventMode.append,
      verbose: false,
    );

List<String> labels(List<dynamic> items) => items
    .map(
      (dynamic item) => switch (item) {
        ChatToolActivityGroup g => g.activities.map((a) => a.toolId).join(','),
        ChatReasoningItem r => 'reasoning:${r.text}',
        Map<String, dynamic> m => m['_display_content'] as String,
        _ => throw StateError('unexpected item'),
      },
    )
    .toList();

void main() {
  test('a pruned scope cannot reintroduce its late tool under a new scope', () {
    final state = const ChatTimeline()
        .tool('old', tool('old-tool'))
        .appendText('new', 'new')
        .retainScopes(['new']);
    final late = state.tool('new', tool('old-tool', complete: true));
    expect(late.runs, state.runs);
  });

  test(
    'fully evicted scopes never render their canonical accumulators or fallback tools',
    () {
      final old = <String, dynamic>{
        'role': 'assistant',
        'content': 'evicted prose',
        '_gateway_reasoning': 'evicted reasoning',
      };
      final live = <String, dynamic>{
        'role': 'assistant',
        'content': 'unbounded canonical accumulator',
      };
      final evicted = tool('evicted');
      var state = const ChatTimeline()
          .appendText(old, 'old')
          .reasoning(old, reasoning('old reasoning'))
          .tool(old, evicted);
      for (var i = 0; i < 600; i++) {
        state = state.appendText(live, 'new $i').tool(live, tool('t$i'));
      }
      final ids = state.runs.map((r) => r.id).toList();
      final pending = <String, dynamic>{
        'role': 'assistant',
        'content': 'new target',
      };
      state = state.reassignScope(old, pending).retainScopes([pending, live]);
      state = state.tool(live, tool('evicted', complete: true));
      expect(state.runs.map((r) => r.id), ids);
      final display = labels(
        buildChatDisplayItems(
          messages: [pending, live],
          timeline: state,
          toolActivities: [evicted],
        ),
      );
      expect(display.length, ChatTimeline.maxRuns);
      expect(
        display.any((s) => s.contains('evicted') || s.contains('unbounded')),
        isFalse,
      );
      expect(old['content'], 'evicted prose');
    },
  );

  test(
    'saturated identity tombstones reject ambiguous late terminals without fallback resurrection',
    () {
      final scope = <String, dynamic>{
        'role': 'assistant',
        'content': 'canonical',
      };
      var state = const ChatTimeline();
      for (var i = 0; i < 2200; i++) {
        state = state.appendText(scope, 'x').tool(scope, tool('t$i'));
      }
      final ids = state.runs.map((r) => r.id).toList();
      final late = tool('t1200', complete: true);
      state = state.tool(scope, late);
      expect(state.runs.map((r) => r.id), ids);
      final display = labels(
        buildChatDisplayItems(
          messages: [scope],
          timeline: state,
          toolActivities: [late],
        ),
      );
      expect(display, isNot(contains('t1200')));
      expect(display.length, ChatTimeline.maxRuns);
    },
  );
  for (final verbose in [false, true]) {
    test(
      'gateway verbose timeline reasoning stays collapsed: app verbose=$verbose',
      () {
        final row = <String, dynamic>{
          'role': 'assistant',
          'content': '',
          '_normal_projection_id': 'verbose-reasoning',
        };
        final timeline = const ChatTimeline().reasoning(
          'verbose-reasoning',
          const GatewayReasoningUpdate(
            text: 'Gateway-marked verbose reasoning',
            mode: GatewayReasoningEventMode.append,
            verbose: true,
          ),
        );
        final items = buildChatDisplayItems(
          messages: [row],
          timeline: timeline,
          verbose: verbose,
        );
        final item = items.single as ChatReasoningItem;
        expect(item.text, 'Gateway-marked verbose reasoning');
        expect(item.initiallyExpanded, isFalse);
        expect(item.id, timeline.runs.single.id);
      },
    );
  }

  test('stable presentation ids survive immutable snapshot row copies', () {
    final row = <String, dynamic>{
      'role': 'assistant',
      'content': 'AB',
      '_normal_projection_id': 'turn-row',
    };
    final before = Map<String, dynamic>.from(row);
    final state = const ChatTimeline()
        .appendText('turn-row', 'A')
        .tool('turn-row', tool('t1'))
        .appendText('turn-row', 'B');
    expect(
      labels(
        buildChatDisplayItems(
          messages: [Map<String, dynamic>.unmodifiable(row)],
          timeline: state,
        ),
      ),
      ['A', 't1', 'B'],
    );
    expect(row, before);
  });

  test(
    'retained live view prunes anchors and bounds runs without reusing ids',
    () {
      var state = const ChatTimeline().appendText('old', 'not retained');
      for (var i = 0; i < 600; i++) {
        state = state.appendText('live', 'text $i').tool('live', tool('t$i'));
      }
      final bounded = state.retainScopes(['live']);
      expect(bounded.runs, hasLength(1024));
      expect(bounded.runs.every((run) => run.scope == 'live'), isTrue);
      expect(bounded.runs.last.id, state.runs.last.id);
      final cleared = bounded.retainScopes([]).appendText('new', 'new');
      expect(
        state.runs.map((run) => run.id),
        isNot(contains(cleared.runs.single.id)),
      );
    },
  );

  test('retained live view bounds text while preserving run identity', () {
    final source = 'x' * 2097152;
    final state = const ChatTimeline().appendText('live', source);
    final bounded = state.retainScopes(['live']);
    expect(bounded.runs.single.text, hasLength(1048576));
    expect(bounded.runs.single.id, state.runs.single.id);
    expect(state.runs.single.text.length, ChatTimeline.maxTextCodeUnits);
    expect(
      source.length,
      2097152,
    ); // The request/canonical source is untouched.
  });

  test(
    'new exposed reasoning deltas after tools are separate receipt runs',
    () {
      final assistant = <String, dynamic>{
        'role': 'assistant',
        'content': 'ABC',
      };
      final state = const ChatTimeline()
          .appendText(assistant, 'A')
          .reasoning(assistant, reasoning('R1'))
          .tool(assistant, tool('t1'))
          .appendText(assistant, 'B')
          .reasoning(assistant, reasoning('R2'))
          .tool(assistant, tool('t2'))
          .appendText(assistant, 'C');
      expect(
        labels(buildChatDisplayItems(messages: [assistant], timeline: state)),
        ['A', 'reasoning:R1', 't1', 'B', 'reasoning:R2', 't2', 'C'],
      );
      final snapshot = state.reasoning(
        assistant,
        reasoning('R1R2', replace: true),
      );
      expect(
        labels(
          buildChatDisplayItems(messages: [assistant], timeline: snapshot),
        ),
        ['A', 'reasoning:R1', 't1', 'B', 'reasoning:R2', 't2', 'C'],
      );
    },
  );
  test('hydration clears references without reusing reasoning identities', () {
    final scope = Object();
    final initial = const ChatTimeline().reasoning(scope, reasoning('R'));
    final next = initial.clear().reasoning(Object(), reasoning('next R'));
    expect(next.runs.single.id, isNot(initial.runs.single.id));
  });

  test(
    'earlier preview completion cannot pull late tools before later commentary',
    () {
      final a = <String, dynamic>{'role': 'assistant', 'content': 'A rendered'};
      final b = <String, dynamic>{'role': 'assistant', 'content': 'B'};
      final pending = <String, dynamic>{'role': 'assistant', 'content': ''};
      final state = const ChatTimeline()
          .appendText(a, 'A')
          .appendText(b, 'B')
          .tool(pending, tool('t'))
          .reassignScope(pending, a)
          .textSnapshot(a, 'A rendered', preservePosition: true);
      expect(labels(buildChatDisplayItems(messages: [a, b], timeline: state)), [
        'A rendered',
        'B',
        't',
      ]);
    },
  );

  test(
    'durable call IDs match exact references rather than activity queue position',
    () {
      final items = buildChatDisplayItems(
        messages: [
          {'id': 1, 'role': 'tool', 'tool_call_id': 'one', 'content': 'ok'},
          {'id': 2, 'role': 'assistant', 'content': 'middle'},
          {'id': 3, 'role': 'tool', 'tool_call_id': 'two', 'content': 'ok'},
        ],
        toolActivities: [tool('two'), tool('one')],
      );
      expect(labels(items), ['one', 'middle', 'two']);
    },
  );
  test(
    'receipt order, adjacent batches, ID updates and immutable prior state',
    () {
      final assistant = <String, dynamic>{
        'role': 'assistant',
        'content': 'ABC',
      };
      final t1 = tool('t1');
      final t2 = tool('t2');
      final t3 = tool('t3');
      final before = const ChatTimeline()
          .appendText(assistant, 'A')
          .reasoning(assistant, reasoning('R'))
          .tool(assistant, t1)
          .tool(assistant, t2)
          .appendText(assistant, 'B')
          .tool(assistant, t3)
          .appendText(assistant, 'C');
      final now = DateTime.utc(2026, 10, 23, 1, 2, 3);
      final after = before.tool(assistant, tool('t1', complete: true, at: now));
      final items = buildChatDisplayItems(
        messages: [assistant],
        toolActivities: [t1, t2, t3],
        timeline: after,
      );
      expect(labels(items), ['A', 'reasoning:R', 't1,t2', 'B', 't3', 'C']);
      expect(after.runs.map((r) => r.id), before.runs.map((r) => r.id));
      expect(before.runs[2].activity!.isTerminal, false);
      final group = items[2] as ChatToolActivityGroup;
      expect(group.activities.first.isTerminal, true);
      expect(group.latestKnownActivity!.lastActivityAt, now);
      expect(
        group.latestKnownActivity!.lastActivityTimeSource,
        GatewayToolTimeSource.observed,
      );
      expect(() => after.runs.clear(), throwsUnsupportedError);
    },
  );

  test('late ID updates an explicit reference, never a same-name run', () {
    final scope = Object();
    final noId = GatewayToolActivity(
      name: 'terminal',
      phase: GatewayToolActivityPhase.generating,
    );
    final initial = const ChatTimeline()
        .tool(scope, noId)
        .appendText(scope, 'B')
        .tool(scope, tool('other'));
    final after = initial.tool(
      scope,
      tool('late', identity: noId.identity, complete: true),
    );
    expect(after.runs, hasLength(3));
    expect(after.runs.first.id, noId.identity);
    expect(after.runs.first.activity!.toolId, 'late');
    expect(after.runs.last.activity!.toolId, 'other');
    expect(after.runs.last.activity!.isTerminal, false);
  });

  test(
    'token whitespace and snapshots retain boundaries without duplicating prose',
    () {
      final scope = Object();
      var state = const ChatTimeline()
          .appendText(scope, '  ```dart\n')
          .appendText(scope, '  value\n```\n')
          .tool(scope, tool('t'))
          .appendText(scope, '\nB ');
      final ids = state.runs.map((r) => r.id).toList();
      final snapshot = state.forScope(scope).map((r) => r.text).join();
      expect(state.textSnapshot(scope, snapshot), same(state));
      state = state.textSnapshot(scope, '${snapshot}C');
      expect(state.runs.map((r) => r.id), ids);
      expect(state.runs.first.text, '  ```dart\n  value\n```\n');
      expect(state.runs.last.text, '\nB C');
      state = state.textSnapshot(scope, 'Transformed');
      expect(
        state.runs
            .where((r) => r.kind == ChatTimelineKind.text)
            .map((r) => r.text),
        ['Transformed'],
      );
      expect(state.runs.last.activity!.toolId, 't');
    },
  );

  test(
    'reasoning snapshots replace in their own scope with stable identity',
    () {
      final a = Object();
      final b = Object();
      final initial = const ChatTimeline()
          .reasoning(a, reasoning('old '))
          .appendText(a, 'A')
          .reasoning(b, reasoning('private? No: explicitly exposed.'));
      final next = initial.reasoning(a, reasoning('snapshot', replace: true));
      expect(next.runs.first.id, initial.runs.first.id);
      expect(next.forScope(a).first.text, 'snapshot');
      expect(next.forScope(b).single.text, 'private? No: explicitly exposed.');
    },
  );

  for (final withBarrier in [false, true]) {
    test(
      'append-mode scope transfer preserves receipt ids; barrier=$withBarrier',
      () {
        final original = Object();
        final pending = Object();
        var state = const ChatTimeline().reasoning(original, reasoning('R1'));
        if (withBarrier) {
          state = state.appendText(original, 'A').tool(pending, tool('t1'));
        }
        state = state.reasoning(pending, reasoning('R2'));
        final next = state.reassignScope(pending, original);
        expect(next.runs.map((run) => run.id), state.runs.map((run) => run.id));
        expect(
          next.runs.map((run) => run.text),
          state.runs.map((run) => run.text),
        );
        expect(
          next.runs.map((run) => run.kind),
          state.runs.map((run) => run.kind),
        );
        expect(next.forScope(pending), isEmpty);
        expect(next.forScope(original).length, state.runs.length);
      },
    );
  }

  for (final separatedByTool in [false, true]) {
    test(
      'append reassignment preserves reasoning run IDs and receipt boundaries (tool: $separatedByTool)',
      () {
        final assistant = <String, dynamic>{
          'role': 'assistant',
          'content': 'A',
        };
        final pending = <String, dynamic>{'role': 'assistant', 'content': ''};
        var state = const ChatTimeline()
            .appendText(assistant, 'A')
            .reasoning(assistant, reasoning('R1'));
        if (separatedByTool) state = state.tool(pending, tool('t1'));
        state = state.reasoning(pending, reasoning('R2'));
        final next = state.reassignScope(pending, assistant);
        final expected = [
          'A',
          'reasoning:R1',
          if (separatedByTool) 't1',
          'reasoning:R2',
        ];
        expect(
          labels(buildChatDisplayItems(messages: [assistant], timeline: next)),
          expected,
        );
        expect(next.runs.map((run) => run.id), state.runs.map((run) => run.id));
        expect(
          next.runs.map((run) => run.text),
          state.runs.map((run) => run.text),
        );
        expect(next.forScope(pending), isEmpty);
        expect(next.forScope(assistant), next.runs);
        expect(state.forScope(pending).last.text, 'R2');
        final confirmed = next.reasoning(
          assistant,
          reasoning('R1R2', replace: true),
        );
        expect(
          confirmed.runs.map((run) => run.id),
          next.runs.map((run) => run.id),
        );
        expect(
          labels(
            buildChatDisplayItems(messages: [assistant], timeline: confirmed),
          ),
          expected,
        );
      },
    );
  }

  test(
    'replacement reassignment replaces late reasoning at the existing anchor',
    () {
      final a = Object();
      final pending = Object();
      final state = const ChatTimeline()
          .appendText(a, 'A')
          .reasoning(a, reasoning('old '))
          .tool(pending, tool('t'))
          .reasoning(pending, reasoning('latest'));
      final next = state.reassignScope(pending, a, replaceReasoning: true);
      expect(next.forScope(pending), isEmpty);
      expect(next.runs.map((r) => r.kind), [
        ChatTimelineKind.text,
        ChatTimelineKind.reasoning,
        ChatTimelineKind.tool,
      ]);
      expect(next.runs[1].id, state.runs[1].id);
      expect(next.runs[1].text, 'latest');
    },
  );

  test(
    'presentation never mutates canonical history or inserts request markers',
    () {
      final user = <String, dynamic>{'role': 'user', 'content': 'Question'};
      final assistant = <String, dynamic>{'role': 'assistant', 'content': 'AB'};
      final messages = [user, assistant];
      final state = const ChatTimeline()
          .appendText(assistant, 'A')
          .tool(assistant, tool('t'))
          .reasoning(assistant, reasoning('R'))
          .appendText(assistant, 'B');
      buildChatDisplayItems(
        messages: messages,
        timeline: state,
        toolActivities: [tool('t')],
      );
      expect(messages, [
        {'role': 'user', 'content': 'Question'},
        {'role': 'assistant', 'content': 'AB'},
      ]);
      expect(buildRestChatHistory(messages), messages);
    },
  );

  test(
    'durable rows replace optimistic projection, even if old references remain',
    () {
      final optimistic = <String, dynamic>{
        'role': 'assistant',
        'content': 'AB',
      };
      final state = const ChatTimeline()
          .appendText(optimistic, 'A')
          .tool(optimistic, tool('t'))
          .appendText(optimistic, 'B');
      final durable = <Map<String, dynamic>>[
        {'id': 1, 'role': 'assistant', 'content': 'A'},
        {'id': 2, 'role': 'tool', 'content': 'ok', 'tool_call_id': 't'},
        {'id': 3, 'role': 'assistant', 'content': 'B'},
      ];
      expect(
        labels(
          buildChatDisplayItems(
            messages: durable,
            timeline: const ChatTimeline(),
            toolActivities: [tool('t', complete: true)],
          ),
        ),
        ['A', 't', 'B'],
      );
      // Replacing row identities must never project the old optimistic prose.
      expect(
        labels(
          buildChatDisplayItems(
            messages: durable,
            timeline: state,
            toolActivities: [tool('t', complete: true)],
          ),
        ),
        ['A', 't', 'B'],
      );
    },
  );
}
