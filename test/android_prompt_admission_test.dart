import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';

void main() {
  late _PromptGateway gateway;
  setUp(() async => gateway = await _PromptGateway.start());
  tearDown(() => gateway.close());

  test(
    'Desktop admission is rechecked after a held profile configuration read',
    () async {
      final client = DesktopGatewayClient.fromConnection(gateway.connection);
      addTearDown(client.close);
      gateway.configBarrier = Completer<void>();
      var admitted = true;
      var sent = 0;
      final flight = client.submitPrompt(
        sessionId: 'stored',
        text: 'Create a report',
        onEvent: (_) {},
        onSent: () => sent++,
        maySend: () => admitted,
      );
      final rejected = expectLater(flight, throwsStateError);
      await gateway.configEntered.future;
      admitted = false;
      gateway.configBarrier!.complete();
      await rejected;
      expect(sent, 0);
      expect(gateway.prompts, isEmpty);
      expect(gateway.configReads.single['params'], {
        'key': 'full',
        'profile': 'work',
      });
    },
  );

  for (final reconnect in [false, true]) {
    test(
      'held configuration cannot send after socket close; reconnect=$reconnect',
      () async {
        final client = WsClient(gateway.baseUrl);
        addTearDown(client.close);
        await client.connect();
        gateway.configBarrier = Completer<void>();
        var sent = 0;
        final flight = client.submitPrompt(
          'Create a report',
          sessionId: 'runtime',
          onEvent: (_) {},
          onSent: () => sent++,
        );
        final rejected = expectLater(
          flight,
          throwsA(
            isA<JsonRpcError>().having(
              (e) => e.reason,
              'reason',
              'connection_closed',
            ),
          ),
        );
        await gateway.configEntered.future;
        client.close();
        if (reconnect) await client.connect();
        gateway.configBarrier!.complete();
        await rejected;
        expect(sent, 0);
        expect(gateway.prompts, isEmpty);
        if (reconnect) {
          gateway.configBarrier = null;
          await client.submitPrompt(
            'Fresh owner',
            sessionId: 'runtime',
            onEvent: (_) {},
          );
          expect(
            gateway.prompts.single['text'],
            AndroidPromptContext.forModel('Fresh owner'),
          );
        }
      },
    );
  }

  test(
    'a stock voice-stopped acknowledgement needs no nonexistent terminal event',
    () async {
      final client = WsClient(gateway.baseUrl);
      addTearDown(client.close);
      await client.connect();
      gateway.config = {
        'config': {
          'voice': {
            'stop_phrases': ['Bonne nuit'],
          },
        },
      };
      gateway.voiceStopped = true;
      final events = <StreamEvent>[];
      await client.submitPrompt(
        ' "BONNE NUIT!" ',
        sessionId: 'runtime',
        onEvent: events.add,
        timeout: const Duration(milliseconds: 100),
      );
      expect(gateway.prompts.single, {
        'session_id': 'runtime',
        'text': ' "BONNE NUIT!" ',
      });
      expect(events, isEmpty);
    },
  );

  test(
    'custom configuration is refreshed on the exact profile for each submit',
    () async {
      final client = WsClient(gateway.baseUrl, profile: 'work');
      addTearDown(client.close);
      await client.connect();
      await client.submitPrompt(
        'Buenas noches',
        sessionId: 'runtime',
        onEvent: (_) {},
      );
      gateway.config = {
        'config': {
          'voice': {
            'stop_phrases': ['Buenas noches'],
          },
        },
      };
      await client.submitPrompt(
        'Buenas noches',
        sessionId: 'runtime',
        onEvent: (_) {},
      );
      expect(gateway.configReads, hasLength(2));
      expect(
        gateway.configReads.map((r) => r['params']),
        everyElement({'key': 'full', 'profile': 'work'}),
      );
      expect(gateway.prompts, [
        {
          'session_id': 'runtime',
          'profile': 'work',
          'text': AndroidPromptContext.forModel('Buenas noches'),
          'title_preview': 'Buenas noches',
        },
        {'session_id': 'runtime', 'profile': 'work', 'text': 'Buenas noches'},
      ]);
    },
  );

  test(
    'unknown configuration replies cannot rewrite a possible typed control',
    () async {
      final client = WsClient(gateway.baseUrl);
      addTearDown(client.close);
      await client.connect();
      for (final reply in <Object?>[
        null,
        'bad',
        {},
        {'config': null},
      ]) {
        gateway.config = reply;
        await client.submitPrompt(
          'custom control',
          sessionId: 'runtime',
          onEvent: (_) {},
        );
        expect(gateway.prompts.last, {
          'session_id': 'runtime',
          'text': 'custom control',
        });
      }
    },
  );

  test(
    'timed-out discovery sends unchanged once and ignores its late reply',
    () async {
      final client = WsClient(gateway.baseUrl);
      addTearDown(client.close);
      await client.connect();
      gateway.configBarrier = Completer<void>();
      final flight = client.submitPrompt(
        'custom timeout control',
        sessionId: 'runtime',
        onEvent: (_) {},
      );
      await gateway.configEntered.future;
      await flight; // The production two-second lookup budget, not a test sleep.
      expect(gateway.prompts.single, {
        'session_id': 'runtime',
        'text': 'custom timeout control',
      });
      gateway.configBarrier!.complete();
      await client.send('gateway.ping', const {});
      expect(gateway.configReads, hasLength(1));
      expect(gateway.prompts, hasLength(1));
    },
  );
}

class _PromptGateway {
  _PromptGateway(this.server);
  final HttpServer server;
  final sockets = <WebSocket>[];
  final prompts = <Map<String, dynamic>>[];
  final configReads = <Map<String, dynamic>>[];
  final configEntered = Completer<void>();
  Completer<void>? configBarrier;
  Object? config = <String, dynamic>{'config': <String, dynamic>{}};
  bool voiceStopped = false;
  String get baseUrl => 'http://127.0.0.1:${server.port}';
  SavedConnection get connection => SavedConnection(
    id: 'prompt-admission',
    label: 'Fixture',
    host: '127.0.0.1',
    port: server.port,
    dashboardPortOverride: server.port,
    dashboardProxied: true,
    desktopGatewayUrl: baseUrl,
    gatewayProfile: 'work',
    apiKey: 'fixture',
  );

  static Future<_PromptGateway> start() async {
    final gateway = _PromptGateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.server.listen(gateway.handle);
    return gateway;
  }

  Future<void> handle(HttpRequest request) async {
    if (request.uri.path == '/api/auth/ws-ticket') {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ticket":"fixture"}');
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((raw) async {
      final frame = jsonDecode(raw as String) as Map<String, dynamic>;
      final method = frame['method'];
      Object? result = <String, dynamic>{};
      if (method == 'config.get') {
        configReads.add(frame);
        result = config;
        if (!configEntered.isCompleted) configEntered.complete();
        await configBarrier?.future;
      } else if (method == 'session.resume') {
        result = {
          'session_id': 'runtime',
          'stored_session_id': 'stored',
          'running': false,
        };
      } else if (method == 'prompt.submit') {
        prompts.add(Map<String, dynamic>.from(frame['params'] as Map));
        result = voiceStopped
            ? {'voice_stopped': true}
            : {'status': 'streaming'};
      }
      if (socket.readyState != WebSocket.open) return;
      socket.add(
        jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
      );
      if (method == 'prompt.submit' && !voiceStopped) {
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {
              'sid': 'runtime',
              'type': 'turn.end',
              'payload': <String, dynamic>{},
            },
          }),
        );
      }
    });
  }

  Future<void> close() async {
    if (configBarrier?.isCompleted == false) configBarrier!.complete();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
