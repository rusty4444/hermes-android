import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<Map<String, dynamic>> _normalPrompt(
  String text, {
  bool loseAck = false,
  Map<String, dynamic>? config = const {},
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <Map<String, dynamic>>[];
  final sockets = <WebSocket>[];
  final subscription = server.transform(WebSocketTransformer()).listen((
    socket,
  ) {
    sockets.add(socket);
    socket.listen((raw) {
      final request = jsonDecode(raw as String) as Map<String, dynamic>;
      if (request['method'] == 'config.get') {
        expect(request['params'], {'key': 'full'});
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': request['id'],
            if (config == null)
              'error': {'code': -32601, 'message': 'Unavailable'}
            else
              'result': {'config': config},
          }),
        );
        return;
      }
      if (request['method'] != 'prompt.submit') return;
      requests.add(request);
      if (loseAck) {
        unawaited(socket.close(WebSocketStatus.goingAway));
        return;
      }
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': request['id'],
          'result': {'status': 'streaming'},
        }),
      );
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'sid': 'warm-tui-session',
            'type': 'turn.end',
            'payload': <String, dynamic>{},
          },
        }),
      );
    });
  });
  final client = WsClient('http://127.0.0.1:${server.port}');
  try {
    await client.connect();
    final submitted = client.submitPrompt(
      text,
      sessionId: 'warm-tui-session',
      onEvent: (_) {},
      timeout: const Duration(seconds: 5),
    );
    if (loseAck) {
      await expectLater(
        submitted,
        throwsA(
          isA<JsonRpcError>().having(
            (error) => error.reason,
            'reason',
            'connection_closed',
          ),
        ),
      );
    } else {
      await submitted;
    }
    expect(
      requests,
      hasLength(1),
      reason: 'Guidance must not add a turn/retry.',
    );
    return Map<String, dynamic>.from(requests.single['params'] as Map);
  } finally {
    client.close();
    for (final socket in sockets) {
      await socket.close();
    }
    await subscription.cancel();
    await server.close(force: true);
  }
}

void main() {
  test(
    'configured typed voice-stop phrases retain exact stock wire text',
    () async {
      for (final phrases in <dynamic>[
        'silencio total',
        ['silencio total', '静かにして'],
      ]) {
        const text = ' "Silencio Total!" ';
        expect(
          await _normalPrompt(
            text,
            config: {
              'voice': {'stop_phrases': phrases},
            },
          ),
          {'session_id': 'warm-tui-session', 'text': text},
        );
      }
      const unicode = '静かにして';
      expect(
        await _normalPrompt(
          unicode,
          config: {
            'voice': {
              'stop_phrases': [unicode],
            },
          },
        ),
        {'session_id': 'warm-tui-session', 'text': unicode},
      );
    },
  );

  test(
    'unavailable stop configuration preserves text instead of guessing',
    () async {
      expect(
        await _normalPrompt('a completely custom stop phrase', config: null),
        {
          'session_id': 'warm-tui-session',
          'text': 'a completely custom stop phrase',
        },
      );
    },
  );

  test(
    'disabled configured stop phrases still allow ordinary context',
    () async {
      final params = await _normalPrompt(
        'Create a report',
        config: {
          'voice': {'stop_phrases': []},
        },
      );
      expect(params['text'], AndroidPromptContext.forModel('Create a report'));
    },
  );

  test(
    'stock normal prompt carries guidance without an Android backend field',
    () async {
      final params = await _normalPrompt('Create a report');
      expect(
        params.keys,
        unorderedEquals(['session_id', 'text', 'title_preview']),
      );
      expect(params['session_id'], 'warm-tui-session');
      expect(params['title_preview'], 'Create a report');
      expect(params['text'], startsWith('Create a report\n\n'));
      expect(
        params['text'],
        contains('native Hermes Android app, not a terminal'),
      );
      expect(params['text'], contains('`MEDIA:/absolute/host/path`'));
      expect(params['text'], contains('previews, Download and Share'));
      expect(params, isNot(contains('surface')));
      expect(params, isNot(contains('api_text')));
    },
  );

  test(
    'lost acknowledgement never causes a context turn or resubmission',
    () async {
      final params = await _normalPrompt('Generate an image', loseAck: true);
      expect(
        params['text'],
        AndroidPromptContext.forModel('Generate an image'),
      );
    },
  );

  test(
    'slash commands and typed stop controls retain their exact wire shape',
    () async {
      for (final text in ['/model provider/exact-id', ' STOP! ']) {
        expect(await _normalPrompt(text), {
          'session_id': 'warm-tui-session',
          'text': text,
        });
      }
    },
  );

  test(
    'SSE retains prior wire history and frames only the latest user input',
    () {
      final old = AndroidPromptContext.forModel('Earlier prompt');
      final history = [
        {'role': 'user', 'content': old},
        {'role': 'assistant', 'content': 'Earlier reply'},
      ];
      final before = jsonEncode(history);
      final messages = GatewayChatClient.buildChatCompletionMessages(
        message: 'New prompt',
        history: history,
      );
      expect(messages, [
        ...history,
        {
          'role': 'user',
          'content': AndroidPromptContext.forModel('New prompt'),
        },
      ]);
      expect(jsonEncode(history), before);
    },
  );

  test(
    'SSE deduplicates plain or already-framed latest input without wrapping twice',
    () {
      final wire = AndroidPromptContext.forModel('Question');
      for (final latest in ['Question', wire]) {
        final messages = GatewayChatClient.buildChatCompletionMessages(
          message: 'Question',
          history: [
            {'role': 'assistant', 'content': 'Earlier reply'},
            {'role': 'user', 'content': latest},
          ],
        );
        expect(messages, hasLength(2));
        expect(messages.last, {'role': 'user', 'content': wire});
        expect(
          RegExp(
            RegExp.escape(AndroidPromptContext.header),
          ).allMatches(messages.last['content'] as String),
          hasLength(1),
        );
      }
    },
  );

  test(
    'SSE attachment-only turns retain image bytes and get Android guidance',
    () {
      const image = 'data:image/png;base64,Zml4dHVyZQ==';
      final messages = GatewayChatClient.buildChatCompletionMessages(
        message: '',
        imageDataUrl: image,
      );
      final content = messages.single['content'] as List;
      expect(content, hasLength(2));
      expect(content.first['type'], 'text');
      expect(content.first['text'], contains('native Hermes Android app'));
      expect(
        AndroidPromptContext.userText(content.first['text'] as String),
        '',
      );
      expect(content.last, {
        'type': 'image_url',
        'image_url': {'url': image},
      });
    },
  );

  test(
    'actual SSE request keeps routing and session identity unchanged',
    () async {
      late http.Request captured;
      final api = ApiClient(
        baseUrl: 'http://fixture.invalid',
        apiKey: 'synthetic-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            'data: {"choices":[{"delta":{"content":"Done."}}]}\n\n'
            'data: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      addTearDown(api.close);
      Object? failure;
      var done = 0;
      await GatewayChatClient(api).sendMessageStreaming(
        message: 'Make a file',
        sessionId: 'existing-session',
        model: 'exact-model',
        provider: 'exact-provider',
        onToken: (_) {},
        onDone: () => done += 1,
        onError: (error) => failure = error,
      );
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(
        body.keys,
        unorderedEquals(['model', 'provider', 'messages', 'stream']),
      );
      expect(body['model'], 'exact-model');
      expect(body['provider'], 'exact-provider');
      expect(body['stream'], isTrue);
      expect(body['messages'], [
        {
          'role': 'user',
          'content': AndroidPromptContext.forModel('Make a file'),
        },
      ]);
      expect(captured.url.path, '/v1/chat/completions');
      expect(
        captured.headers.entries.any(
          (entry) =>
              entry.key.toLowerCase() == 'x-hermes-session-id' &&
              entry.value == 'existing-session',
        ),
        isTrue,
      );
      expect(failure, isNull);
      expect(done, 1);
    },
  );
}
