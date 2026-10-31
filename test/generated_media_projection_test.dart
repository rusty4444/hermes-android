import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/models/received_scope_outcome.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

GatewayToolActivity _complete(String id, String path) =>
    GatewayToolActivity.fromGatewayEvent('tool.complete', {
      'tool_id': id,
      'name': 'image_generate',
      'result': {'success': true, 'image': path},
    })!;

Map<String, dynamic> _row(String path, {String? name = 'image_generate'}) => {
  'id': 42,
  'role': 'tool',
  'tool_call_id': 'image-1',
  'name': ?name,
  'content': jsonEncode({'success': true, 'image': path}),
  'timestamp': 10,
};

List<ChatAttachmentItem> _attachments(List<dynamic> items) =>
    items.whereType<ChatAttachmentItem>().toList();

void main() {
  test(
    'raw named JSON results project independently of verbose tool cards',
    () {
      for (final verbose in [false, true]) {
        final rows = [_row('/out/a.png')];
        final before = jsonEncode(rows);
        final items = buildChatDisplayItems(messages: rows, verbose: verbose);
        final attachment = _attachments(items).single;
        expect(attachment.ref.path, '/out/a.png');
        expect(items.whereType<Map<String, dynamic>>(), isEmpty);
        expect(chatDisplayItemIdentity(attachment), (
          'attachment',
          attachment.id,
        ));
        expect(jsonEncode(rows), before);
      }
    },
  );

  test('raw unnamed JSON results require real function-call correlation', () {
    final rows = <Map<String, dynamic>>[
      {
        'id': 41,
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'id': 'image-1',
            'type': 'function',
            'function': {
              'name': 'image_generate',
              'arguments': '{"prompt":"draw"}',
            },
          },
        ],
      },
      _row('/out/a.png', name: null),
    ];
    expect(
      _attachments(buildChatDisplayItems(messages: rows)).single.ref.path,
      '/out/a.png',
    );
    expect(_attachments(buildChatDisplayItems(messages: [rows.last])), isEmpty);
  });

  test(
    'timeline completion adds a deliverable at its actual tool position',
    () {
      final row = <String, dynamic>{'role': 'assistant', 'content': ''};
      final activity = _complete('image-1', '/out/a.png');
      final timeline = const ChatTimeline()
          .appendText(row, 'Before')
          .tool(row, activity)
          .appendText(row, 'After');
      final before = jsonEncode(row);
      final items = buildChatDisplayItems(messages: [row], timeline: timeline);
      expect(items, hasLength(4));
      expect((items[0] as Map)['_display_content'], 'Before');
      expect(items[1], isA<ChatToolActivityGroup>());
      expect((items[2] as ChatAttachmentItem).ref.path, '/out/a.png');
      expect((items[3] as Map)['_display_content'], 'After');
      expect(jsonEncode(row), before);
    },
  );

  test(
    'attachment identity survives late tool id, text updates and group growth',
    () {
      final row = <String, dynamic>{'role': 'assistant', 'content': ''};
      final start = GatewayToolActivity(
        name: 'image_generate',
        phase: GatewayToolActivityPhase.running,
      );
      final completed = start.merge(_complete('image-1', '/out/a.png'));
      var timeline = const ChatTimeline().tool(row, start).tool(row, completed);
      final first = _attachments(
        buildChatDisplayItems(messages: [row], timeline: timeline),
      ).single;
      timeline = timeline
          .tool(row, _complete('image-2', '/out/b.png'))
          .appendText(row, 'A later final answer.');
      final updated = _attachments(
        buildChatDisplayItems(messages: [row], timeline: timeline),
      );
      expect(updated.map((a) => a.ref.path), ['/out/a.png', '/out/b.png']);
      expect(
        chatDisplayItemIdentity(updated.first),
        chatDisplayItemIdentity(first),
      );
      expect(updated.first.id, isNot(updated.last.id));
    },
  );

  test(
    'compact result omission does not invent files; raw history can supply it',
    () {
      final row = <String, dynamic>{'role': 'assistant', 'content': ''};
      final compact = GatewayToolActivity.fromGatewayEvent('tool.complete', {
        'tool_id': 'image-1',
        'name': 'image_generate',
      })!;
      final timeline = const ChatTimeline().tool(row, compact);
      expect(
        _attachments(
          buildChatDisplayItems(messages: [row], timeline: timeline),
        ),
        isEmpty,
      );
      final items = buildChatDisplayItems(
        messages: [row, _row('/out/saved.png')],
        toolActivities: [compact],
        timeline: timeline,
      );
      expect(_attachments(items).single.ref.path, '/out/saved.png');
      expect(items.whereType<ChatToolActivityGroup>(), hasLength(1));
    },
  );

  test(
    'exact assistant MEDIA or file-link echo wins without mutating transcript',
    () {
      for (final echo in [
        'Done.\nMEDIA:/out/a.png',
        'Here is [your image](/out/a.png).',
      ]) {
        final rows = <Map<String, dynamic>>[
          _row('/out/a.png'),
          {'role': 'assistant', 'content': echo},
        ];
        final before = jsonEncode(rows);
        final items = buildChatDisplayItems(
          messages: rows,
          toolActivities: [_complete('image-1', '/out/a.png')],
        );
        expect(_attachments(items), isEmpty);
        expect(
          items.whereType<Map<String, dynamic>>().single['_display_content'],
          echo,
        );
        expect(jsonEncode(rows), before);
      }
    },
  );

  test(
    'reasoning, examples and user uploads cannot suppress a real delivery',
    () {
      final items = buildChatDisplayItems(
        messages: [
          _row('/out/a.png'),
          {'role': 'user', 'content': 'MEDIA:/out/a.png'},
          {
            'role': 'assistant',
            'content':
                '```text\nMEDIA:/out/a.png\n```\n\n> [example](/out/a.png)',
            '_gateway_reasoning': 'MEDIA:/out/a.png',
          },
          {
            'role': 'assistant',
            'content': [
              {'type': 'reasoning', 'text': 'MEDIA:/out/a.png'},
            ],
          },
        ],
      );
      expect(_attachments(items).single.ref.path, '/out/a.png');
    },
  );

  test(
    'same-source tool echoes dedupe exact path, not distinct paths or calls',
    () {
      final activities = [
        _complete('image-1', '/out/a.png'),
        _complete('image-2', '/out/b.png'),
      ];
      final first = _attachments(
        buildChatDisplayItems(messages: const [], toolActivities: activities),
      );
      expect(first.map((a) => a.ref.path), ['/out/a.png', '/out/b.png']);
      final withDuplicate = _attachments(
        buildChatDisplayItems(
          messages: [
            _row('/out/a.png'),
            {..._row('/out/a.png'), 'id': 43},
          ],
          toolActivities: activities,
        ),
      );
      expect(withDuplicate.map((a) => a.ref.path), [
        '/out/a.png',
        '/out/b.png',
      ]);
    },
  );

  test(
    'saved/received sections retain separate attachment and echo authority',
    () {
      final receivedRow = <String, dynamic>{'role': 'assistant', 'content': ''};
      final received = _complete('image-1', '/out/a.png');
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [
          _row('/out/a.png'),
          {'id': 43, 'role': 'assistant', 'content': 'MEDIA:/out/a.png'},
        ],
        receivedRows: [receivedRow],
        receivedTools: [received],
        receivedTimeline: const ChatTimeline().tool(receivedRow, received),
      );
      expect(sections.map((s) => s.source), [
        ChatDisplaySource.canonical,
        ChatDisplaySource.received,
      ]);
      expect(_attachments(sections.first.items), isEmpty);
      expect(_attachments(sections.last.items).single.ref.path, '/out/a.png');
    },
  );

  test('public assistant deliveries replace physical tool-result wrappers', () {
    for (final retained in [false, true]) {
      for (final projection in <Object>[
        'MEDIA:/out/public.pdf',
        '[public report](/out/public.pdf)',
        [
          {'type': 'text', 'text': 'MEDIA:/out/public.pdf'},
        ],
      ]) {
        final row = <String, dynamic>{
          'role': 'assistant',
          '_normal_projection_id': 'replaced-wrapper',
          'content':
              '<untrusted_tool_result>MEDIA:/out/private.pdf</untrusted_tool_result>',
          'display_content': projection,
        };
        final before = jsonEncode(row);
        final activity = _complete('old-private-image', '/out/private.png');
        final items = buildChatDisplayItems(
          messages: [row],
          toolActivities: retained ? [activity] : [],
          timeline: retained
              ? const ChatTimeline()
                    .appendText('replaced-wrapper', 'MEDIA:/out/private.pdf')
                    .tool('replaced-wrapper', activity)
              : null,
        );
        expect(
          items.whereType<Map<String, dynamic>>().single['_display_content'],
          projection is String ? projection : 'MEDIA:/out/public.pdf',
        );
        expect(_attachments(items), isEmpty);
        expect(items.whereType<ChatToolActivityGroup>(), isEmpty);
        expect(jsonEncode(row), before);
      }
    }
  });

  test(
    'public text cannot reclassify an explicit tool role as assistant prose',
    () {
      for (final role in ['tool', 'function', 'tool_result', 'tool-result']) {
        expect(
          buildChatDisplayItems(
            messages: [
              {
                'role': role,
                'content':
                    '<untrusted_tool_result>private</untrusted_tool_result>',
                'display_content': 'MEDIA:/out/public.pdf',
              },
            ],
            toolActivities: [],
          ),
          isEmpty,
        );
      }
    },
  );

  test(
    'explicit public overrides replace retained live prose reasoning and files',
    () {
      for (final override in <Object?>[
        null,
        '',
        <Object>[],
        [
          {'type': 'reasoning', 'text': 'Not public'},
        ],
        'Public replacement.',
        'MEDIA:/out/public.pdf',
      ]) {
        final row = <String, dynamic>{
          'role': 'assistant',
          '_normal_projection_id': 'overridden',
          'content': 'Physical private accumulator',
          'display_content': override,
          '_gateway_reasoning': 'Physical private reasoning',
        };
        final before = jsonEncode(row);
        final activity = _complete('private-image', '/out/private.png');
        final timeline = const ChatTimeline()
            .appendText('overridden', 'MEDIA:/out/private.pdf')
            .reasoning(
              'overridden',
              const GatewayReasoningUpdate(
                text: 'Retained private reasoning',
                mode: GatewayReasoningEventMode.append,
                verbose: true,
              ),
            )
            .tool('overridden', activity);
        final items = buildChatDisplayItems(
          messages: [row],
          toolActivities: [activity],
          timeline: timeline,
          verbose: true,
        );
        expect(_attachments(items), isEmpty);
        expect(items.whereType<ChatReasoningItem>(), isEmpty);
        expect(items.whereType<ChatToolActivityGroup>(), isEmpty);
        expect(
          items.whereType<Map<String, dynamic>>().map(
            (m) => m['_display_content'],
          ),
          override is String && override.isNotEmpty ? [override] : isEmpty,
        );
        expect(jsonEncode(row), before);
      }
    },
  );

  test('a hidden live scope cannot suppress a public sibling receipt', () {
    final hidden = <String, dynamic>{
      'role': 'assistant',
      '_normal_projection_id': 'hidden',
      'content': 'Private accumulator',
      'display_content': null,
    };
    final visible = <String, dynamic>{
      'role': 'assistant',
      '_normal_projection_id': 'visible',
      'content': '',
    };
    final privateImage = _complete('private', '/out/private.png');
    final publicImage = _complete('public', '/out/public.png');
    final timeline = const ChatTimeline()
        .appendText('hidden', 'Private retained prose')
        .tool('hidden', privateImage)
        .appendText('visible', 'Public retained prose')
        .tool('visible', publicImage);
    final items = buildChatDisplayItems(
      messages: [hidden, visible],
      toolActivities: [privateImage, publicImage],
      timeline: timeline,
    );
    expect(_attachments(items).map((item) => item.ref.path), [
      '/out/public.png',
    ]);
    expect(
      items.whereType<Map<String, dynamic>>().map((m) => m['_display_content']),
      ['Public retained prose'],
    );
  });

  test(
    'hidden/failed/display-null result cannot revive stale live file metadata',
    () {
      final activity = _complete('image-1', '/out/a.png');
      for (final override in <Map<String, dynamic>>[
        {'display_kind': 'hidden'},
        {
          'display_metadata': {'model_only': true},
        },
        {'display_content': null},
        {'display_content': ''},
        {'display_content': <Object>[]},
        {
          'content': jsonEncode({'success': false, 'image': '/out/a.png'}),
        },
      ]) {
        expect(
          _attachments(
            buildChatDisplayItems(
              messages: [
                {..._row('/out/a.png'), ...override},
              ],
              toolActivities: [activity],
            ),
          ),
          isEmpty,
        );
      }
      final failed = activity.merge(
        GatewayToolActivity.fromGatewayEvent('tool.complete', {
          'tool_id': 'image-1',
          'name': 'image_generate',
          'error': 'failed',
        })!,
      );
      expect(
        _attachments(
          buildChatDisplayItems(
            messages: [_row('/out/a.png')],
            toolActivities: [failed],
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'evicted receipt tools are not resurrected through raw or trailing fallback',
    () {
      final row = <String, dynamic>{'role': 'assistant', 'content': ''};
      final activity = _complete('image-1', '/out/a.png');
      final timeline = const ChatTimeline()
          .tool(row, activity)
          .retainScopes([]);
      expect(
        _attachments(
          buildChatDisplayItems(
            messages: [row, _row('/out/a.png')],
            toolActivities: [activity],
            timeline: timeline,
          ),
        ),
        isEmpty,
      );
    },
  );

  test(
    'attachment-only outcome anchoring uses actual scope, not reused tool id',
    () {
      final activity = _complete('reused-tool-id', '/out/a.png');
      final timeline = const ChatTimeline().tool('scope-a', activity);
      final actual = timeline.runs.single.activity!;
      final attachment = ChatAttachmentItem(
        id: 'file',
        ref: actual.deliveredFiles.single,
        activity: actual,
      );
      final facts = [
        ReceivedScopeOutcome(
          id: 'other',
          scopes: ['scope-b'],
          outcome: ReceivedLifecycleOutcome.failed,
        ),
        ReceivedScopeOutcome(
          id: 'actual',
          scopes: ['scope-a'],
          outcome: ReceivedLifecycleOutcome.completed,
        ),
      ];
      final section = ChatDisplaySection(
        source: ChatDisplaySource.received,
        items: [attachment],
      ).withReceivedOutcomes(timeline, facts);
      expect(
        section.outcomes[chatDisplayItemIdentity(attachment)]?.id,
        'actual',
      );
    },
  );
}
