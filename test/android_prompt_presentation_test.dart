import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/utils/chat_history_scroll.dart';

void main() {
  test(
    'saved user bubbles and retry text omit context without changing rows',
    () {
      final rows = <Map<String, dynamic>>[
        {
          'id': 1,
          'role': 'user',
          'content': AndroidPromptContext.forModel('Make a PDF'),
        },
        {'id': 2, 'role': 'assistant', 'content': 'Created the file'},
        {'id': 3, 'role': 'user', 'content': 'An earlier terminal prompt'},
        {'id': 4, 'role': 'assistant', 'content': 'Another reply'},
      ];
      final before = jsonEncode(rows);
      final items = buildChatDisplayItems(
        messages: rows,
      ).cast<Map<String, dynamic>>();
      expect(items[0]['_display_content'], 'Make a PDF');
      expect(items[1]['_retry_prompt'], 'Make a PDF');
      expect(items[2]['_display_content'], 'An earlier terminal prompt');
      expect(items[3]['_retry_prompt'], 'An earlier terminal prompt');
      expect(jsonEncode(rows), before);
      expect(
        buildRestChatHistory(rows).first['content'],
        rows.first['content'],
      );
    },
  );

  test(
    'a literal known note survives local and saved user presentation once',
    () {
      const literal = 'Explain this example${AndroidPromptContext.suffix}';
      for (final row in <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': literal,
          AndroidPromptContext.localUserTextKey: true,
        },
        {'role': 'user', 'content': AndroidPromptContext.forModel(literal)},
      ]) {
        final items = buildChatDisplayItems(
          messages: [
            row,
            {'role': 'assistant', 'content': 'Reply'},
          ],
        ).cast<Map<String, dynamic>>();
        expect(items.first['_display_content'], literal);
        expect(items.last['_retry_prompt'], literal);
      }
    },
  );

  test(
    'public null/empty overrides and hidden user rows cannot reveal raw text',
    () {
      final wire = AndroidPromptContext.forModel(
        'Do not expose physical content',
      );
      for (final replacement in [null, '']) {
        expect(
          buildChatDisplayItems(
            messages: [
              {'role': 'user', 'content': wire, 'display_content': replacement},
            ],
          ),
          isEmpty,
        );
      }
      expect(
        buildChatDisplayItems(
          messages: [
            {'role': 'user', 'content': wire, 'display_kind': 'hidden'},
          ],
        ),
        isEmpty,
      );
      final visible =
          buildChatDisplayItems(
                messages: [
                  {
                    'role': 'user',
                    'content': wire,
                    'display_content': 'Public replacement',
                  },
                ],
              ).single
              as Map<String, dynamic>;
      expect(visible['_display_content'], 'Public replacement');
    },
  );

  test(
    'multimodal user display retains the image and assistant text verbatim',
    () {
      final answer = 'Assistant example${AndroidPromptContext.suffix}';
      final rows = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': AndroidPromptContext.forModel('Describe this'),
            },
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,Zml4dHVyZQ=='},
            },
          ],
        },
        {'role': 'assistant', 'content': answer},
      ];
      final before = jsonEncode(rows);
      final items = buildChatDisplayItems(
        messages: rows,
      ).cast<Map<String, dynamic>>();
      expect(items.first['_display_content'], 'Describe this\n\n[Image]');
      expect(items.last['_display_content'], answer);
      expect(items.last['_retry_prompt'], 'Describe this\n\n[Image]');
      expect(jsonEncode(rows), before);
    },
  );

  test(
    'local SSE history reuses actual wire content before a durable reload',
    () {
      final wire = GatewayChatClient.buildUserContent(
        message: 'First question',
      );
      final local = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': 'First question',
          AndroidPromptContext.localUserTextKey: true,
          AndroidPromptContext.wireContentKey: wire,
        },
        {'role': 'assistant', 'content': 'First reply'},
      ];
      final before = jsonEncode(local);
      final history = buildRestChatHistory(local);
      final next = GatewayChatClient.buildChatCompletionMessages(
        message: 'Second question',
        history: history,
      );
      expect(next.first, {'role': 'user', 'content': wire});
      expect(next[1], {'role': 'assistant', 'content': 'First reply'});
      expect(
        next.last['content'],
        AndroidPromptContext.forModel('Second question'),
      );
      expect(history.first.keys, unorderedEquals(['role', 'content']));
      expect(jsonEncode(local), before);
    },
  );

  test(
    'local SSE multimodal wire history retains the original image payload',
    () {
      const image = 'data:image/png;base64,Zml4dHVyZQ==';
      final wire = GatewayChatClient.buildUserContent(
        message: '',
        imageDataUrl: image,
      );
      final history = buildRestChatHistory([
        {
          'role': 'user',
          'content': '[Image]',
          AndroidPromptContext.localUserTextKey: true,
          AndroidPromptContext.wireContentKey: wire,
        },
      ]);
      expect(history.single['content'], same(wire));
      expect((history.single['content'] as List).last['image_url'], {
        'url': image,
      });
      expect(
        buildRestChatHistory([
          {
            'role': 'assistant',
            'content': 'Keep output',
            AndroidPromptContext.wireContentKey: 'Never borrow this',
          },
        ]).single['content'],
        'Keep output',
      );
    },
  );

  test('delegated transcript decodes users only and keeps its raw source', () {
    final answer = 'Quoted output${AndroidPromptContext.suffix}';
    final rows = <Map<String, dynamic>>[
      {
        'id': 1,
        'role': 'user',
        'content': AndroidPromptContext.forModel('Question'),
      },
      {'id': 2, 'role': 'assistant', 'content': answer},
    ];
    final before = jsonEncode(rows);
    final transcript = parseTaskTranscript(rows);
    expect(transcript.first.text, 'Question');
    expect(transcript.last.text, answer);
    expect(jsonEncode(rows), before);
  });

  test(
    'session preview cleans known context without changing the actual title',
    () {
      final wire = AndroidPromptContext.forModel('Make a chart');
      final session = Session.fromJson({
        'id': 'existing-session',
        'title': 'Actual title',
        'is_active': false,
        'preview': wire.substring(0, 120),
      });
      expect(session.title, 'Actual title');
      expect(session.preview, 'Make a chart');
    },
  );
}
