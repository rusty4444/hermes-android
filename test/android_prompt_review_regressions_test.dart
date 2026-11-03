import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/utils/chat_history_scroll.dart';
import 'package:hermes_android/core/utils/message_content.dart';

void main() {
  for (final caption in ['', '  \n']) {
    test(
      'image-only SSE reload and retry omit empty text parts: ${jsonEncode(caption)}',
      () {
        final wire = GatewayChatClient.buildUserContent(
          message: caption,
          imageDataUrl: 'data:image/png;base64,Zml4dHVyZQ==',
        );
        final rows = <Map<String, dynamic>>[
          {'id': 1, 'role': 'user', 'content': wire},
          {'id': 2, 'role': 'assistant', 'content': 'Image response'},
        ];
        final before = jsonEncode(rows);
        final items = buildChatDisplayItems(
          messages: rows,
        ).cast<Map<String, dynamic>>();
        expect(items.first['_display_content'], '[Image]');
        expect(items.last['_retry_prompt'], '[Image]');
        // Delegated history carries images separately, not as prose labels.
        expect(parseTaskTranscript(rows).first.text, '');
        expect(buildRestChatHistory(rows).first['content'], same(wire));
        expect(jsonEncode(rows), before);
      },
    );
  }

  for (final text in [
    '/custom preserve this literal${AndroidPromptContext.suffix}',
    ' \n/model exact-id${AndroidPromptContext.suffix}',
  ]) {
    test(
      'exempt slash input keeps a literal suffix through saved presentation: ${text.split('\n').first}',
      () {
        final wire = AndroidPromptContext.forModel(text);
        expect(wire, text);
        expect(AndroidPromptContext.userText(wire), text);
        final rows = <Map<String, dynamic>>[
          {'id': 1, 'role': 'user', 'content': wire},
          {'id': 2, 'role': 'assistant', 'content': 'Reply'},
        ];
        final before = jsonEncode(rows);
        final items = buildChatDisplayItems(
          messages: rows,
        ).cast<Map<String, dynamic>>();
        expect(items.first['_display_content'], text.trim());
        expect(items.last['_retry_prompt'], text.trim());
        expect(parseTaskTranscript(rows).first.text, text);
        expect(AndroidPromptContext.sessionPreview(wire), wire);
        expect(jsonEncode(rows), before);
      },
    );
  }

  test('recognised empty text parts are empty, not unsupported content', () {
    for (final type in ['text', 'input_text', 'output_text']) {
      expect(messageContentToText({'type': type, 'text': ''}), '');
      expect(
        messageContentToText([
          {'type': type, 'text': ''},
          {
            'type': 'image_url',
            'image_url': {'url': 'fixture'},
          },
        ]),
        '[Image]',
      );
    }
    expect(
      messageContentToText({'type': 'unrecognised', 'payload': 1}),
      '[Unsupported content: unrecognised]',
    );
  });
}
