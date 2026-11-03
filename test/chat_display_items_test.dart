import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

GatewayToolActivity _tool(String name) =>
    GatewayToolActivity(name: name, phase: GatewayToolActivityPhase.completed);

GatewaySubagentActivity _subagent(String id) => GatewaySubagentActivity(
  id: id,
  goal: 'goal $id',
  phase: GatewaySubagentPhase.completed,
);

const _notice = GatewayNotice(
  kind: GatewayNoticeKind.background,
  text: 'task done',
);

void main() {
  group('buildChatDisplayItems', () {
    test('keeps user and assistant prose in order with display content', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'user', 'content': 'question'},
          {'role': 'assistant', 'content': 'answer'},
        ],
      );

      expect(items, hasLength(2));
      final user = items[0] as Map<String, dynamic>;
      final assistant = items[1] as Map<String, dynamic>;
      expect(user['role'], 'user');
      expect(user['_display_content'], 'question');
      expect(assistant['role'], 'assistant');
      expect(assistant['_display_content'], 'answer');
    });

    test('normalizes persisted agent replies to assistant bubbles', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'user', 'content': 'question'},
          {'role': 'agent', 'content': 'answer'},
        ],
      );

      final reply = items.last as Map<String, dynamic>;
      expect(reply['role'], 'assistant');
      expect(reply['_display_content'], 'answer');
      expect(reply['_retry_prompt'], 'question');
    });

    test('tags each assistant reply with the last user prompt for retry', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'user', 'content': 'first'},
          {'role': 'assistant', 'content': 'reply one'},
          {'role': 'user', 'content': 'second'},
          {'role': 'assistant', 'content': 'reply two'},
        ],
      );

      expect((items[1] as Map<String, dynamic>)['_retry_prompt'], 'first');
      expect((items[3] as Map<String, dynamic>)['_retry_prompt'], 'second');
      expect(
        (items[0] as Map<String, dynamic>).containsKey('_retry_prompt'),
        isFalse,
      );
    });

    test('never attaches a retry prompt before the first user message', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'assistant', 'content': 'unsolicited'},
        ],
      );

      expect(
        (items.single as Map<String, dynamic>).containsKey('_retry_prompt'),
        isFalse,
      );
    });

    test('drops messages that are neither user nor assistant', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'system', 'content': 'you are Hermes'},
          {'role': 'assistant', 'content': 'answer'},
        ],
      );

      expect(items, hasLength(1));
      expect((items.single as Map<String, dynamic>)['role'], 'assistant');
    });

    test('drops messages with no text and no reasoning', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'assistant', 'content': ''},
          {'role': 'assistant', 'content': 'answer'},
        ],
      );

      expect(items, hasLength(1));
      expect(
        (items.single as Map<String, dynamic>)['_display_content'],
        'answer',
      );
    });

    test('replaces a tool result message with the matching activity card', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'user', 'content': 'run it'},
          {'role': 'tool', 'content': 'raw output'},
          {'role': 'assistant', 'content': 'done'},
        ],
        toolActivities: [_tool('terminal')],
      );

      expect(items, hasLength(3));
      expect(items[0], isA<Map<String, dynamic>>());
      final group = items[1] as ChatToolActivityGroup;
      expect(group.activities.map((activity) => activity.name), ['terminal']);
      expect((items[2] as Map<String, dynamic>)['_display_content'], 'done');
    });

    test('groups consecutive tool results into a single card', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'tool', 'content': 'first'},
          {'role': 'tool', 'content': 'second'},
          {'role': 'assistant', 'content': 'done'},
        ],
        toolActivities: [_tool('read_file'), _tool('write_file')],
      );

      expect(items, hasLength(2));
      final group = items[0] as ChatToolActivityGroup;
      expect(group.activities.map((activity) => activity.name), [
        'read_file',
        'write_file',
      ]);
    });

    test(
      'projects durable row times independently and retains group anchor',
      () {
        final first = GatewayToolActivity.fromStoredResult(
          name: 'read_file',
          timestamp: 1792544523,
        );
        final second = GatewayToolActivity.fromStoredResult(
          name: 'terminal',
          timestamp: null,
        );
        final items = buildChatDisplayItems(
          messages: [
            {
              'id': 41,
              'role': 'tool',
              'content': 'first',
              'timestamp': 1792544523,
            },
            {'id': 42, 'role': 'tool', 'content': 'second'},
          ],
          toolActivities: [first, second],
        );
        final group = items.single as ChatToolActivityGroup;
        expect(group.id, 'message:41');
        expect(group.activities[0].lastActivityAt, first.lastActivityAt);
        expect(group.activities[1].lastActivityAt, isNull);
        expect(group.latestKnownActivity, same(first));
        expect(group.activities[0].startedAt, isNull);
      },
    );

    test('latest timestamp comes from any row, not merely the final row', () {
      final later = GatewayToolActivity(
        name: 'read_file',
        phase: GatewayToolActivityPhase.completed,
        lastActivityAt: DateTime.utc(2026, 10, 21, 1, 2, 9),
        lastActivityTimeSource: GatewayToolTimeSource.observed,
      );
      final earlier = GatewayToolActivity(
        name: 'terminal',
        phase: GatewayToolActivityPhase.completed,
        lastActivityAt: DateTime.utc(2026, 10, 21, 1, 2, 3),
        lastActivityTimeSource: GatewayToolTimeSource.storedResult,
      );
      final items = buildChatDisplayItems(
        messages: const [],
        toolActivities: [later, earlier, _tool('unknown')],
      );
      final group = items.single as ChatToolActivityGroup;
      expect(group.latestKnownActivity, same(later));
      expect(group.activities, hasLength(3));
    });

    test(
      'suppresses a tool result bubble even without a matching activity',
      () {
        final items = buildChatDisplayItems(
          messages: [
            {'role': 'tool', 'content': 'orphan output'},
            {'role': 'assistant', 'content': 'done'},
          ],
        );

        expect(items, hasLength(1));
        expect(
          (items.single as Map<String, dynamic>)['_display_content'],
          'done',
        );
      },
    );

    test('appends tool activities that never matched a stored message', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'assistant', 'content': 'streaming'},
        ],
        toolActivities: [_tool('search_files')],
      );

      expect(items, hasLength(2));
      expect(items[0], isA<Map<String, dynamic>>());
      expect(
        (items[1] as ChatToolActivityGroup).activities.single.name,
        'search_files',
      );
    });

    test('leaves the caller list untouched while consuming activities', () {
      final activities = [_tool('terminal')];
      buildChatDisplayItems(
        messages: [
          {'role': 'tool', 'content': 'output'},
        ],
        toolActivities: activities,
      );

      expect(activities, hasLength(1));
    });

    // Pinned as-is, not endorsed: isToolResultMessage classifies on the whole
    // text, so an assistant reply that *embeds* a tool-result block is treated
    // as a tool result and its surrounding prose is dropped rather than
    // stripped. Phase 1.5 reworks message hierarchy; this test records what
    // ships today so that rework is a visible, deliberate change.
    test('drops assistant prose that embeds a raw tool result block', () {
      final items = buildChatDisplayItems(
        messages: [
          {
            'role': 'assistant',
            'content':
                'before <untrusted_tool_result id="1">noise</untrusted_tool_result>',
          },
        ],
        toolActivities: [_tool('terminal')],
      );

      expect(items, hasLength(1));
      expect(
        (items.single as ChatToolActivityGroup).activities.single.name,
        'terminal',
      );
    });

    test(
      'strips a trailing tool result block when the role is not tool-like',
      () {
        final items = buildChatDisplayItems(
          messages: [
            {'role': 'assistant', 'content': 'plain answer'},
          ],
        );

        expect(
          (items.single as Map<String, dynamic>)['_display_content'],
          'plain answer',
        );
      },
    );

    test('emits a reasoning item before the assistant bubble', () {
      final items = buildChatDisplayItems(
        messages: [
          {
            'role': 'assistant',
            'content': 'answer',
            '_gateway_reasoning': 'thinking hard',
          },
        ],
      );

      expect(items, hasLength(2));
      final reasoning = items[0] as ChatReasoningItem;
      expect(reasoning.text, 'thinking hard');
      expect(reasoning.initiallyExpanded, isFalse);
      expect((items[1] as Map<String, dynamic>)['_display_content'], 'answer');
    });

    test('keeps reasoning visible when the message is still text-free', () {
      final items = buildChatDisplayItems(
        messages: [
          {
            'role': 'assistant',
            'content': '',
            '_gateway_reasoning': 'still thinking',
          },
        ],
      );

      expect(items, hasLength(1));
      expect((items.single as ChatReasoningItem).text, 'still thinking');
    });

    test('ignores reasoning attached to a user message', () {
      final items = buildChatDisplayItems(
        messages: [
          {
            'role': 'user',
            'content': 'question',
            '_gateway_reasoning': 'leaked',
          },
        ],
      );

      expect(items, hasLength(1));
      expect(items.single, isA<Map<String, dynamic>>());
    });

    test('keeps reasoning collapsed in verbose mode', () {
      final items = buildChatDisplayItems(
        messages: [
          {
            'role': 'assistant',
            'content': 'answer',
            '_gateway_reasoning': 'thinking',
          },
        ],
        verbose: true,
      );

      expect((items[0] as ChatReasoningItem).initiallyExpanded, isFalse);
    });

    test('keeps gateway-marked verbose reasoning collapsed by default', () {
      final items = buildChatDisplayItems(
        messages: [
          {
            'role': 'assistant',
            'content': 'answer',
            '_gateway_reasoning': 'thinking',
            '_gateway_reasoning_verbose': true,
          },
        ],
      );

      expect((items[0] as ChatReasoningItem).initiallyExpanded, isFalse);
    });

    test('flushes a pending tool card before a reasoning item', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'tool', 'content': 'output'},
          {
            'role': 'assistant',
            'content': 'answer',
            '_gateway_reasoning': 'thinking',
          },
        ],
        toolActivities: [_tool('terminal')],
      );

      expect(items[0], isA<ChatToolActivityGroup>());
      expect(items[1], isA<ChatReasoningItem>());
      expect(items[2], isA<Map<String, dynamic>>());
    });

    test('orders subagents after messages and notices last', () {
      final items = buildChatDisplayItems(
        messages: [
          {'role': 'assistant', 'content': 'answer'},
        ],
        subagentActivities: [_subagent('a1')],
        notices: [_notice],
      );

      expect(items, hasLength(3));
      expect(items[0], isA<Map<String, dynamic>>());
      expect((items[1] as List<GatewaySubagentActivity>).single.id, 'a1');
      expect((items[2] as GatewayNotice).text, 'task done');
    });

    test('returns nothing for an empty conversation', () {
      expect(buildChatDisplayItems(messages: const []), isEmpty);
    });

    test(
      'known Android suffix preserves the prompt, retry and raw history',
      () {
        final raw = AndroidPromptContext.forModel('Create a file');
        final messages = [
          {'role': 'user', 'content': raw},
          {'role': 'assistant', 'content': 'answer'},
        ];
        final items = buildChatDisplayItems(messages: messages);
        expect(items, hasLength(2));
        expect((items.first as Map)['_display_content'], 'Create a file');
        expect((items.last as Map)['_retry_prompt'], 'Create a file');
        expect(messages.first['content'], raw);
      },
    );

    test('literal marker references remain ordinary user and assistant text', () {
      for (final text in [
        'Explain Hermes Android client context',
        '[Hermes Android client context v1]\nclient=true\n[/Hermes Android client context]',
        'Hermes Android client context is mentioned here',
      ]) {
        final items = buildChatDisplayItems(
          messages: [
            {'role': 'user', 'content': text},
            {'role': 'assistant', 'content': text},
          ],
        );
        expect(items, hasLength(2));
        expect((items.first as Map)['_display_content'], text);
        expect((items.last as Map)['_display_content'], text);
        expect((items.last as Map)['_retry_prompt'], text);
      }
    });
  });
}
