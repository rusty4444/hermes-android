import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/services/tool_activity_group_pins.dart';

import 'chat_timeline_test.dart' show reasoning, tool;

void main() {
  test(
    'first-render keys are stable across import and repeated projection',
    () {
      final donor = const ChatTimeline().reasoning('donor', reasoning('first'));
      final current = const ChatTimeline().reasoning(
        'current',
        reasoning('second'),
      );
      final before = donor.precededBy([]);
      final composed = current.precededBy([donor]);
      expect(before.runs.single.id, 'donor:timeline:0');
      expect(composed.runs.first.id, before.runs.single.id);
      expect(composed.runs.last.id, 'current:timeline:0');
      expect(
        composed.precededBy([]).runs.map((r) => r.id),
        composed.runs.map((r) => r.id),
      );
      expect(
        composed.precededBy([before]).runs.map((r) => r.id),
        composed.runs.map((r) => r.id),
      );
      expect(donor.runs.single.id, 'timeline:0');
      expect(current.runs.single.id, 'timeline:0');
      expect(identical(before, donor.precededBy([])), isTrue);
      expect(() => before.runs.clear(), throwsUnsupportedError);
    },
  );

  test(
    'preview ownership transfer keeps the first-render expansion identity',
    () {
      final raw = const ChatTimeline()
          .reasoning('preview', reasoning('before'))
          .tool('preview', tool('read'))
          .reasoning('continuation', reasoning('after'));
      final before = raw.precededBy([]);
      final moved = raw.reassignScope('continuation', 'preview').precededBy([]);
      expect(moved.runs.map((r) => r.id), before.runs.map((r) => r.id));
      expect(moved.runs.map((r) => r.text), before.runs.map((r) => r.text));
      expect(moved.runs.map((r) => r.kind), before.runs.map((r) => r.kind));
      expect(moved.runs.last.scope, 'preview');
      expect(raw.runs.last.scope, 'continuation');
    },
  );

  for (final expanded in [false, true]) {
    test(
      'independent raw timeline:0 cannot inherit pin expanded=$expanded',
      () {
        final donor = const ChatTimeline().reasoning(
          'donor',
          reasoning('first'),
        );
        final current = const ChatTimeline().reasoning(
          'current',
          reasoning('second'),
        );
        final pins = ToolActivityGroupPins();
        final before = donor.precededBy([]).runs.single.id;
        pins.pin(before, expanded);
        final composed = current.precededBy([donor]);
        expect(pins[composed.runs.first.id], expanded);
        expect(pins[composed.runs.last.id], isNull);
        final next = current
            .clear()
            .reasoning('next', reasoning('third'))
            .precededBy([]);
        expect(next.runs.single.id, isNot(composed.runs.last.id));
        expect(pins[next.runs.single.id], isNull);
        for (var i = 0; i < 120; i++) {
          pins.pin('scope-$i:timeline:0', true);
        }
        expect(pins[before], isNull);
        expect(pins['scope-119:timeline:0'], isTrue);
      },
    );
  }

  test(
    'projection leaves anonymous and learned durable tool identities intact',
    () {
      final anonymous = GatewayToolActivity(
        name: 'read_file',
        identity: 'local:fixture',
        phase: GatewayToolActivityPhase.running,
      );
      final learned = anonymous.merge(
        GatewayToolActivity(
          name: 'read_file',
          toolId: 'opaque-tool',
          phase: GatewayToolActivityPhase.completed,
        ),
      );
      final timeline = const ChatTimeline()
          .tool('scope', anonymous)
          .tool('scope', learned);
      final projected = timeline.precededBy([]);
      expect(projected.runs.single.id, timeline.runs.single.id);
      expect(
        projected.runs.single.activity,
        same(timeline.runs.single.activity),
      );
      expect(projected.runs.single.activity!.identity, 'local:fixture');
      expect(projected.runs.single.activity!.toolId, 'opaque-tool');
      final pruned = timeline.retainScopes([]).precededBy([]);
      expect(pruned.excludesTool(anonymous), isTrue);
      expect(pruned.excludesTool(tool('opaque-tool', complete: true)), isTrue);
    },
  );

  test('repeated composition shares run text and identity budgets', () {
    ChatTimeline make(String scope) {
      var timeline = const ChatTimeline();
      for (var i = 0; i < 600; i++) {
        timeline = timeline
            .appendText(scope, 'x' * 1024)
            .tool(scope, tool('$scope-$i'));
      }
      return timeline;
    }

    final donor = make('donor');
    final current = make('current');
    final combined = current.precededBy([donor]);
    final repeated = combined.precededBy([donor]);
    expect(combined.runs.length, lessThanOrEqualTo(ChatTimeline.maxRuns));
    expect(repeated.runs.length, lessThanOrEqualTo(ChatTimeline.maxRuns));
    expect(
      repeated.retainedToolIdentityCount,
      lessThanOrEqualTo(ChatTimeline.maxEvictedTools),
    );
    expect(
      repeated.runs.fold<int>(0, (sum, run) => sum + run.text.length),
      lessThanOrEqualTo(ChatTimeline.maxTextCodeUnits),
    );
    expect(
      repeated.runs.map((r) => (r.scope, r.id)).toSet().length,
      repeated.runs.length,
    );
    expect(current.runs.first.id.startsWith('current:'), isFalse);
    expect(donor.runs.first.id.startsWith('donor:'), isFalse);
  });
}
