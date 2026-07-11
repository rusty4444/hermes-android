import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/message_content.dart';

void main() {
  group('messageContentToText', () {
    test('keeps legacy string content unchanged', () {
      expect(messageContentToText('hello'), 'hello');
    });

    test('joins OpenAI text content parts', () {
      expect(
        messageContentToText([
          {'type': 'text', 'text': 'first'},
          {'type': 'text', 'text': 'second'},
        ]),
        'first\n\nsecond',
      );
    });

    test('renders mixed text and image content without throwing', () {
      expect(
        messageContentToText([
          {'type': 'text', 'text': 'caption'},
          {
            'type': 'image_url',
            'image_url': {'url': 'https://example.invalid/image.png'},
          },
        ]),
        'caption\n\n[Image]',
      );
    });

    test('handles null and unknown structured content safely', () {
      expect(messageContentToText(null), '');
      expect(
        messageContentToText([
          {'type': 'custom_part', 'payload': 42},
        ]),
        '[Unsupported content: custom_part]',
      );
    });
  });
}
