import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

void main() {
  test(
    'POLICY canonical projector cannot borrow received tool fallback metadata',
    () {
      final receivedTool = GatewayToolActivity.fromStoredResult(
        toolId: 'same-id',
        name: 'received-only',
        timestamp: null,
      );
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [
          {
            'id': 1,
            'role': 'tool',
            'tool_call_id': 'same-id',
            'content': 'Canonical result',
          },
          {'id': 2, 'role': 'assistant', 'content': 'Repeated body'},
        ],
        receivedRows: [
          {'role': 'assistant', 'content': 'Repeated body'},
        ],
        receivedTools: [receivedTool],
        receivedTimeline: const ChatTimeline(),
      );
      expect(sections.map((s) => s.source), [
        ChatDisplaySource.canonical,
        ChatDisplaySource.received,
      ]);
      expect(sections.first.items.whereType<ChatToolActivityGroup>(), isEmpty);
      expect(
        sections.last.items
            .whereType<ChatToolActivityGroup>()
            .single
            .activities
            .single,
        same(receivedTool),
      );
      expect(
        sections.first.items
            .whereType<Map<String, dynamic>>()
            .single['_display_content'],
        'Repeated body',
      );
      expect(
        sections.last.items
            .whereType<Map<String, dynamic>>()
            .single['_display_content'],
        'Repeated body',
      );
    },
  );

  test(
    'POLICY auxiliary task authority appears once and sections are immutable',
    () {
      final child = GatewaySubagentActivity.fromGatewayEvent('subagent.start', {
        'subagent_id': 'child',
        'child_session_id': 'durable-child',
        'goal': 'Inspect',
      })!;
      final saved = <Map<String, dynamic>>[
        {'id': 1, 'role': 'assistant', 'content': 'Saved'},
      ];
      final received = <Map<String, dynamic>>[
        {'role': 'assistant', 'content': 'Received'},
      ];
      final sections = buildNormalChatDisplaySections(
        canonicalRows: saved,
        receivedRows: received,
        receivedTimeline: const ChatTimeline(),
        subagentActivities: [child],
      );
      expect(sections.last.source, ChatDisplaySource.auxiliary);
      expect(
        sections
            .expand((s) => s.items)
            .whereType<List<GatewaySubagentActivity>>()
            .single
            .single,
        same(child),
      );
      expect(() => sections.add(sections.first), throwsUnsupportedError);
      expect(() => sections.first.items.clear(), throwsUnsupportedError);
      expect(saved.single.keys, ['id', 'role', 'content']);
      expect(received.single.keys, ['role', 'content']);
    },
  );
}
