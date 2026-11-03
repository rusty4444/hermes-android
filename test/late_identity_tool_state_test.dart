import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/tool_activity_group_pins.dart';

void main() {
  for (final prune in [false, true]) {
    test(
      'learned durable identity stays excluded after ${prune ? 'scope pruning' : 'run eviction'}',
      () {
        final initial = GatewayToolActivity(
          name: 'terminal',
          phase: GatewayToolActivityPhase.running,
        );
        final learned = initial.merge(
          GatewayToolActivity(
            name: 'terminal',
            toolId: 'late-id',
            phase: GatewayToolActivityPhase.progress,
          ),
        );
        var timeline = const ChatTimeline()
            .tool('old', initial)
            .tool('old', learned);
        expect(timeline.runs.single.id, initial.identity);
        if (prune) {
          timeline = timeline.retainScopes(['new']);
        } else {
          for (var i = 0; i < ChatTimeline.maxRuns; i++) {
            timeline = timeline
                .appendText('new', 'x')
                .tool(
                  'new',
                  GatewayToolActivity(
                    name: 'terminal',
                    toolId: 'bulk-$i',
                    phase: GatewayToolActivityPhase.completed,
                  ),
                );
          }
        }
        final late = GatewayToolActivity(
          name: 'terminal',
          toolId: 'late-id',
          phase: GatewayToolActivityPhase.completed,
        );
        expect(timeline.excludesTool(learned), isTrue);
        expect(timeline.excludesTool(late), isTrue);
        final ids = timeline.runs.map((r) => r.id).toList();
        timeline = timeline.tool('new', late);
        expect(timeline.runs.map((r) => r.id), ids);
        // A true canonical replacement, unlike scope pruning, releases aliases.
        timeline = timeline.clear().tool('new', late);
        expect(timeline.runs.single.activity!.toolId, 'late-id');
      },
    );
  }

  test(
    'anonymous correlation never joins two candidates or a different known ID',
    () {
      GatewayToolActivity call(String? id) => GatewayToolActivity(
        name: 'terminal',
        toolId: id,
        phase: GatewayToolActivityPhase.running,
      );
      final anonymous = call(null);
      final update = GatewayToolActivity(
        name: 'terminal',
        toolId: 'late-id',
        phase: GatewayToolActivityPhase.progress,
      );
      expect(toolActivityUpdateIndex([anonymous], update, 'tool.progress'), 0);
      expect(
        toolActivityUpdateIndex([anonymous], call('new-start'), 'tool.start'),
        -1,
      );
      expect(
        toolActivityUpdateIndex(
          [anonymous, call(null)],
          update,
          'tool.progress',
        ),
        -1,
      );
      expect(
        toolActivityUpdateIndex(
          [anonymous, call('different')],
          update,
          'tool.progress',
        ),
        -1,
      );
      expect(
        toolActivityUpdateIndex([call('different')], update, 'tool.progress'),
        -1,
      );
      expect(
        toolActivityUpdateIndex([call('late-id')], update, 'tool.progress'),
        0,
      );
      expect(
        toolActivityUpdateIndex([anonymous], call(null), 'tool.progress'),
        -1,
      );
    },
  );

  test(
    'learned aliases preserve separate chat choices and the existing 100-entry bounds',
    () {
      final registry = ChatPresentationRegistry('connection');
      final first = registry.chatFor('first');
      final second = registry.chatFor('second');
      final firstPins = first.openToolVisit();
      final secondPins = second.openToolVisit();
      // MAIN81D reasoning choice lifetime is an explicit bounded view visit.
      final reasoningPins = first.openReasoningVisit();
      firstPins.pin('local:first', true);
      first.aliasTool('local:first', 'tool:shared-wire-id');
      secondPins.pin('local:second', false);
      second.aliasTool('local:second', 'tool:shared-wire-id');
      expect(firstPins['tool:shared-wire-id'], isTrue);
      expect(secondPins['tool:shared-wire-id'], isFalse);
      for (var i = 0; i < 600; i++) {
        firstPins.pin('local:$i', true);
        first.aliasTool('local:$i', 'tool:$i');
        reasoningPins.pin('reasoning:$i', false);
      }
      expect(firstPins.length, ToolActivityGroupPins.maxPins);
      expect(reasoningPins.length, ToolActivityGroupPins.maxPins);
      registry.close();
      final replacement = ChatPresentationRegistry('connection');
      expect(
        replacement.chatFor('first').openToolVisit()['tool:shared-wire-id'],
        isNull,
      );
      replacement.close();
    },
  );
}
