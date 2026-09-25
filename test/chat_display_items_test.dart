import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/services/chat_detail_visibility.dart';
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
      final group = items[1] as List<GatewayToolActivity>;
      expect(group.map((activity) => activity.name), ['terminal']);
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
      final group = items[0] as List<GatewayToolActivity>;
      expect(group.map((activity) => activity.name), [
        'read_file',
        'write_file',
      ]);
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
        (items[1] as List<GatewayToolActivity>).single.name,
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
        (items.single as List<GatewayToolActivity>).single.name,
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

    test('expands reasoning in verbose mode', () {
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

      expect((items[0] as ChatReasoningItem).initiallyExpanded, isTrue);
    });

    test('expands reasoning the gateway marked verbose', () {
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

      expect((items[0] as ChatReasoningItem).initiallyExpanded, isTrue);
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

      expect(items[0], isA<List<GatewayToolActivity>>());
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

    group('detail visibility', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'go'},
        {'role': 'tool', 'tool_call_id': 'a', 'content': 'ok'},
        {
          'role': 'assistant',
          'content': 'done',
          '_gateway_reasoning': 'thinking',
          '_gateway_reasoning_verbose': true,
        },
        {'role': 'tool', 'tool_call_id': 'b', 'content': 'ok'},
        {'role': 'assistant', 'content': 'second'},
      ];

      test('hidden tool activity keeps positional matching intact', () {
        final items = buildChatDisplayItems(
          messages: messages,
          toolActivities: [_tool('first'), _tool('second'), _tool('late')],
          toolActivityVisibility: ChatDetailVisibility.hidden,
        );

        expect(items.whereType<List<GatewayToolActivity>>(), isEmpty);
        expect(items.whereType<ChatReasoningItem>(), hasLength(1));
        expect(
          items.whereType<Map<String, dynamic>>().map(
            (item) => item['_display_content'],
          ),
          ['go', 'done', 'second'],
        );
      });

      test('visible tool cards still receive their own activities', () {
        final items = buildChatDisplayItems(
          messages: messages,
          toolActivities: [_tool('first'), _tool('second')],
          toolActivityVisibility: ChatDetailVisibility.collapsed,
        );

        final cards = items.whereType<List<GatewayToolActivity>>().toList();
        expect(cards.map((card) => card.single.name), ['first', 'second']);
      });

      test('collapsed reasoning ignores verbose and gateway expansion', () {
        final items = buildChatDisplayItems(
          messages: messages,
          verbose: true,
          reasoningVisibility: ChatDetailVisibility.collapsed,
        );

        final reasoning = items.whereType<ChatReasoningItem>().single;
        expect(reasoning.text, 'thinking');
        expect(reasoning.initiallyExpanded, isFalse);
      });

      test('hidden reasoning removes only the reasoning card', () {
        final items = buildChatDisplayItems(
          messages: [
            ...messages,
            {'role': 'assistant', 'content': '', '_gateway_reasoning': 'x'},
          ],
          reasoningVisibility: ChatDetailVisibility.hidden,
        );

        expect(items.whereType<ChatReasoningItem>(), isEmpty);
        expect(
          items.whereType<Map<String, dynamic>>().map(
            (item) => item['_display_content'],
          ),
          ['go', 'done', 'second'],
        );
      });

      test('automatic keeps the historical expansion rule', () {
        final items = buildChatDisplayItems(messages: messages);

        expect(
          items.whereType<ChatReasoningItem>().single.initiallyExpanded,
          isTrue,
        );
      });

      test('unknown stored values fall back to automatic', () {
        expect(
          ChatDetailVisibility.fromStorage('bogus'),
          ChatDetailVisibility.automatic,
        );
        expect(
          ChatDetailVisibility.fromStorage(null),
          ChatDetailVisibility.automatic,
        );
        for (final visibility in ChatDetailVisibility.values) {
          expect(
            ChatDetailVisibility.fromStorage(visibility.storageValue),
            visibility,
          );
        }
      });
    });
  });
}
