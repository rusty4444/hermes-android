import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

void main() {
  group('GatewayChatClient', () {
    test('appends latest user message to existing history exactly once', () {
      final messages = GatewayChatClient.buildChatCompletionMessages(
        message: 'new question',
        history: [
          {'role': 'user', 'content': 'old question'},
          {'role': 'assistant', 'content': 'old answer'},
        ],
      );

      expect(messages, [
        {'role': 'user', 'content': 'old question'},
        {'role': 'assistant', 'content': 'old answer'},
        {'role': 'user', 'content': 'new question'},
      ]);
    });

    test(
      'does not duplicate latest user message already present in history',
      () {
        final messages = GatewayChatClient.buildChatCompletionMessages(
          message: 'new question',
          history: [
            {'role': 'user', 'content': 'old question'},
            {'role': 'assistant', 'content': 'old answer'},
            {'role': 'user', 'content': 'new question'},
          ],
        );

        expect(
          messages.where((m) => m['content'] == 'new question'),
          hasLength(1),
        );
        expect(messages.last, {'role': 'user', 'content': 'new question'});
      },
    );

    test('parses normal chat completion SSE token frames', () {
      final token = GatewayChatClient.parseSseFrame(
        'data: {"choices":[{"delta":{"content":"hello"}}]}',
      );

      expect(token, 'hello');
    });

    test('parses Hermes tool progress SSE frames via callback', () {
      Map<String, dynamic>? progress;
      final token = GatewayChatClient.parseSseFrame(
        'event: hermes.tool.progress\n'
        'data: {"tool":"read_file","toolCallId":"call_1","status":"running"}',
        onToolProgress: (p) => progress = p,
      );

      expect(token, isNull);
      expect(progress, isNotNull);
      expect(progress!['tool'], 'read_file');
      expect(progress!['toolCallId'], 'call_1');
      expect(progress!['status'], 'running');
    });
  });

  group('DashboardClient', () {
    test('wraps cron job updates for dashboard endpoint', () {
      final updates = {'name': 'Daily', 'no_agent': true};

      expect(DashboardClient.buildCronUpdateBody(updates), {
        'updates': updates,
      });
    });
  });
}
