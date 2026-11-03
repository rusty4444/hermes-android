import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';

void main() {
  test(
    'preview keeps its exposed event source when a status-only update arrives',
    () {
      final thinking = GatewaySubagentActivity.fromGatewayEvent(
        'subagent.thinking',
        {'subagent_id': 'a', 'text': 'Exposed thought'},
      )!;
      final completed = GatewaySubagentActivity.fromGatewayEvent(
        'subagent.complete',
        {'subagent_id': 'a', 'status': 'failed'},
      )!;
      final merged = thinking.merge(completed);
      expect(merged.livePreview, 'Exposed thought');
      expect(merged.previewKind, 'subagent.thinking');
    },
  );
  GatewaySubagentActivity event(String type, Map<String, dynamic> data) =>
      GatewaySubagentActivity.fromGatewayEvent(type, data)!;

  test(
    'retains exact child identity and known goal across id-only progress',
    () {
      final start = event('subagent.start', {
        'subagent_id': 'runtime-1',
        'child_session_id': 'stored:/子?x#%',
        'delegation_id': 'deleg-1',
        'parent_id': 'parent-1',
        'goal': 'Inspect',
      });
      final merged = start.merge(
        event('subagent.thinking', {'subagent_id': 'runtime-1'}),
      );
      expect(merged.childSessionId, 'stored:/子?x#%');
      expect(merged.id, 'runtime-1');
      expect(merged.delegationId, 'deleg-1');
      expect(merged.parentId, 'parent-1');
      expect(merged.goal, 'Inspect');
    },
  );

  test(
    'same goal is not identity and missing/invalid ids are never repaired',
    () {
      final a = event('subagent.start', {'subagent_id': 'a', 'goal': 'Same'});
      final b = event('subagent.start', {'subagent_id': 'b', 'goal': 'Same'});
      expect(a.id, isNot(b.id));
      expect(a.childSessionId, isNull);
      for (final id in ['', ' padded ', '..', 'bad\u0000id', 'x' * 513]) {
        expect(
          event('subagent.start', {'child_session_id': id}).childSessionId,
          isNull,
        );
      }
    },
  );

  for (final status in ['failed', 'interrupted', 'completed']) {
    test('$status is terminal-sticky under late progress', () {
      final done = event('subagent.complete', {
        'subagent_id': 'a',
        'status': status,
      });
      final merged = done.merge(
        event('subagent.text', {'subagent_id': 'a', 'text': 'Late'}),
      );
      expect(merged.isComplete, isTrue);
      expect(merged.status, status);
      expect(merged.phase, GatewaySubagentPhase.completed);
    });
  }
}
