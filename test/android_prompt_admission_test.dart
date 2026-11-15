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

  // Kyllene-style delivery: `source: desktop` already selects stock Hermes'
  // desktop platform hint, so the Desktop gateway never needs the Android
  // note or the voice stop-phrase lookup that used to guard it.
  test('Desktop prompts go out exactly as typed with no config read', () async {
    final client = DesktopGatewayClient.fromConnection(gateway.connection);
    addTearDown(client.close);
    var sent = 0;
    await client.submitPrompt(
      sessionId: 'stored',
      text: 'Create a report',
      onEvent: (_) {},
      onSent: () => sent++,
    );
    expect(sent, 1);
    expect(gateway.prompts.single['text'], 'Create a report');
    expect(
      gateway.prompts.single['text'],
      isNot(contains(AndroidPromptContext.header)),
    );
    expect(gateway.configReads, isEmpty);
  });

  test('revoked Desktop admission sends nothing', () async {
    final client = DesktopGatewayClient.fromConnection(gateway.connection);
    addTearDown(client.close);
    var sent = 0;
    await expectLater(
      client.submitPrompt(
        sessionId: 'stored',
        text: 'Create a report',
        onEvent: (_) {},
        onSent: () => sent++,
        maySend: () => false,
      ),
      throwsStateError,
    );
    expect(sent, 0);
    expect(gateway.prompts, isEmpty);
  });

  test('runtime prompts are unchanged for prose and controls alike', () async {
    final client = WsClient(gateway.baseUrl);
    addTearDown(client.close);
    await client.connect();
    for (final text in [
      'Create a report',
      'stop',
      '/model',
      'custom control',
    ]) {
      await client.submitPrompt(text, sessionId: 'runtime', onEvent: (_) {});
      expect(gateway.prompts.last, {'session_id': 'runtime', 'text': text});
    }
    expect(gateway.configReads, isEmpty);
  });
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
