import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/received_scope_outcome.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/utils/chat_received_recovery_projection.dart';

void main() {
  test('retained unknown output cannot follow newer saved history', () {
    final saved = [
      {'id': 10, 'role': 'user', 'content': 'New saved question'},
      {
        'id': 11,
        'role': 'assistant',
        'content': 'New saved reply',
        'finish_reason': 'stop',
      },
    ];
    final received = [
      {
        'role': 'user',
        'content': 'Old question',
        '_normal_projection_id': 'old-user',
      },
      {
        'role': 'assistant',
        'content': 'Old unconfirmed reply',
        '_normal_projection_id': 'old-reply',
      },
    ];
    final fact = ReceivedScopeOutcome(
      id: 'old-turn',
      scopes: ['old-user', 'old-reply'],
      outcome: ReceivedLifecycleOutcome.unknown,
    );
    final sections = buildNormalChatDisplaySections(
      canonicalRows: saved,
      receivedRows: received,
      receivedTimeline: const ChatTimeline(),
      receivedOutcomes: [fact],
      verbose: true,
    );
    final projection = ChatReceivedRecoveryProjection.build(
      sections: sections,
      timeline: const ChatTimeline(),
      outcomes: [fact],
      retainedOutcomeIds: {'old-turn'},
    );
    expect(projection.sections.single.source, ChatDisplaySource.canonical);
    expect(projection.sections.single.items.last['id'], 11);
    expect(projection.retained!.items.map((item) => item['content']), [
      'Old question',
      'Old unconfirmed reply',
    ]);
    expect(projection.retained!.outcomes.values.single, same(fact));
    expect(received.last['content'], 'Old unconfirmed reply');
    expect(
      sections.last.items,
      hasLength(2),
      reason: 'Export/source projection remains complete',
    );
  });

  test('new live rows and same-public-id tools keep their exact ownership', () {
    final oldTool = GatewayToolActivity(
      name: 'terminal',
      toolId: 'reused',
      phase: GatewayToolActivityPhase.completed,
    );
    final newTool = GatewayToolActivity(
      name: 'terminal',
      toolId: 'reused',
      phase: GatewayToolActivityPhase.running,
    );
    final timeline = const ChatTimeline().tool('new-reply', newTool).precededBy(
      [const ChatTimeline().tool('old-reply', oldTool)],
    );
    final rows = [
      {
        'role': 'user',
        'content': 'Old question',
        '_normal_projection_id': 'old-user',
      },
      {
        'role': 'assistant',
        'content': '',
        '_normal_projection_id': 'old-reply',
      },
      {
        'role': 'user',
        'content': 'Current question',
        '_normal_projection_id': 'new-user',
      },
      {
        'role': 'assistant',
        'content': '',
        '_normal_projection_id': 'new-reply',
      },
    ];
    final fact = ReceivedScopeOutcome(
      id: 'old-turn',
      scopes: ['old-user', 'old-reply'],
      outcome: ReceivedLifecycleOutcome.unknown,
    );
    final sections = buildNormalChatDisplaySections(
      canonicalRows: const [],
      receivedRows: rows,
      receivedTimeline: timeline,
      receivedTools: [oldTool, newTool],
      receivedOutcomes: [fact],
      verbose: true,
    );
    final projection = ChatReceivedRecoveryProjection.build(
      sections: sections,
      timeline: timeline,
      outcomes: [fact],
      retainedOutcomeIds: {'old-turn'},
    );
    expect(
      projection.retained!.items
          .whereType<ChatToolActivityGroup>()
          .single
          .activities
          .single,
      same(oldTool),
    );
    expect(
      projection.sections.single.items
          .whereType<ChatToolActivityGroup>()
          .single
          .activities
          .single,
      same(newTool),
    );
    expect(
      projection.sections.single.items
          .whereType<Map<String, dynamic>>()
          .single['content'],
      'Current question',
    );
  });

  for (final outcome in [
    ReceivedLifecycleOutcome.completed,
    ReceivedLifecycleOutcome.failed,
  ]) {
    test('$outcome is never reclassified as uncertain output', () {
      final fact = ReceivedScopeOutcome(
        id: 'turn',
        scopes: ['reply'],
        outcome: outcome,
      );
      final sections = buildNormalChatDisplaySections(
        canonicalRows: const [],
        receivedRows: const [
          {
            'role': 'assistant',
            'content': 'Kept inline',
            '_normal_projection_id': 'reply',
          },
        ],
        receivedTimeline: const ChatTimeline(),
        receivedOutcomes: [fact],
        verbose: true,
      );
      final projection = ChatReceivedRecoveryProjection.build(
        sections: sections,
        timeline: const ChatTimeline(),
        outcomes: [fact],
        retainedOutcomeIds: {'turn'},
      );
      expect(projection.retained, isNull);
      expect(projection.sections, same(sections));
    });
  }

  test(
    'no explicit route retention choice leaves source projection unchanged',
    () {
      final sections = buildNormalChatDisplaySections(
        canonicalRows: const [],
        receivedRows: const [
          {
            'role': 'user',
            'content': 'Not yet grouped',
            '_normal_projection_id': 'prompt',
          },
        ],
        receivedTimeline: const ChatTimeline(),
      );
      final projection = ChatReceivedRecoveryProjection.build(
        sections: sections,
        timeline: const ChatTimeline(),
        outcomes: const [],
        retainedOutcomeIds: const {},
      );
      expect(projection.sections, same(sections));
      expect(projection.retained, isNull);
    },
  );
}
