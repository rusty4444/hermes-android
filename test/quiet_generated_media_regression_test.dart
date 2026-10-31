import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

Map<String, dynamic> _savedImage() => {
  'role': 'tool',
  'tool_name': 'image_generate',
  'tool_call_id': 'image',
  'content': jsonEncode({'success': true, 'image': '/generated.png'}),
};

Map<String, dynamic> _reply(Map<String, dynamic> evidence) => {
  'role': 'assistant',
  'content': 'Done.',
  ...evidence,
};

void main() {
  test(
    'saved producer needs a completed reply before the next user boundary',
    () {
      for (final evidence in <Map<String, dynamic>>[
        {},
        {'status': 'running'},
        {'status': 'failed'},
        {'completed': true, '_chat_response_complete': false},
      ]) {
        final rows = [_savedImage(), _reply(evidence)];
        final before = jsonEncode(rows);
        expect(
          buildConversationAttachmentItems(
            messages: rows,
          ).whereType<ChatAttachmentItem>(),
          isEmpty,
        );
        expect(jsonEncode(rows), before);
        expect(
          buildConversationAttachmentItems(
            messages: [
              ...rows,
              {'role': 'user', 'content': 'Another question'},
              _reply({'finish_reason': 'stop'}),
            ],
          ).whereType<ChatAttachmentItem>(),
          isEmpty,
        );
      }
      expect(
        buildConversationAttachmentItems(
          messages: [
            _savedImage(),
            _reply({'finish_reason': 'stop'}),
          ],
        ).whereType<ChatAttachmentItem>(),
        hasLength(1),
      );
    },
  );

  test('received producer requires its own selected completion scope', () {
    final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
      'tool_id': 'image',
      'name': 'image_generate',
      'result': {'success': true, 'image': '/generated.png'},
    })!;
    for (final completed in [false, true]) {
      final row = _reply({'_chat_response_complete': completed});
      final timeline = const ChatTimeline()
          .tool(row, activity)
          .appendText(row, 'Done.');
      final items = buildConversationAttachmentItems(
        messages: [
          row,
          _reply({'_chat_response_complete': true}),
        ],
        timeline: timeline,
        received: true,
      );
      expect(
        items.whereType<ChatAttachmentItem>(),
        hasLength(completed ? 1 : 0),
      );
      expect(items.whereType<ChatToolActivityGroup>(), isEmpty);
    }
  });

  test('quiet public overrides suppress physical prose and producer runs', () {
    final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
      'tool_id': 'image',
      'name': 'image_generate',
      'result': {'success': true, 'image': '/private.png'},
    })!;
    for (final public in [null, '', 'Public replacement']) {
      final row = _reply({
        '_chat_response_complete': true,
        'display_content': public,
      });
      final timeline = const ChatTimeline()
          .tool(row, activity)
          .appendText(row, 'PRIVATE');
      final items = buildConversationAttachmentItems(
        messages: [row],
        timeline: timeline,
        received: true,
      );
      expect(items.whereType<ChatAttachmentItem>(), isEmpty);
      expect(
        items.whereType<Map<String, dynamic>>().map(
          (r) => r['_display_content'],
        ),
        public == 'Public replacement' ? [public] : isEmpty,
      );
    }
  });

  test(
    'quiet echo dedup retains generated image hints without raw mutation',
    () {
      const url = 'https://cdn.example/opaque?format=png';
      final tool = _savedImage()
        ..['content'] = jsonEncode({'success': true, 'image': url});
      final rows = [
        tool,
        _reply({'finish_reason': 'stop', 'content': 'MEDIA:"$url"'}),
      ];
      final before = jsonEncode(rows);
      final items = buildConversationAttachmentItems(messages: rows);
      expect(items.whereType<ChatAttachmentItem>(), isEmpty);
      final hints =
          items.whereType<Map<String, dynamic>>().single['_delivery_refs']
              as Map;
      expect(hints[url].filename, 'generated-image.png');
      expect(jsonEncode(rows), before);
    },
  );

  test('a saved final cannot confirm a received producer', () {
    final received = _reply({});
    final activity = GatewayToolActivity.fromGatewayEvent('tool.complete', {
      'tool_id': 'image',
      'name': 'image_generate',
      'result': {'success': true, 'image': '/received.png'},
    })!;
    final sections = buildNormalChatDisplaySections(
      canonicalRows: [
        _reply({'finish_reason': 'stop'}),
      ],
      receivedRows: [received],
      receivedTimeline: const ChatTimeline().tool(received, activity),
      conversationOnly: true,
    );
    expect(
      sections.expand((s) => s.items).whereType<ChatAttachmentItem>(),
      isEmpty,
    );
  });
}
