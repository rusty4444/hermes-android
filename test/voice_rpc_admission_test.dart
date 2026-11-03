import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';

void main() {
  for (final status in ['streaming', 'queued', 'unknown', 'rejected']) {
    test('voice receipt requires correlated RPC admission: $status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <WebSocket>[];
      final prompt = Completer<void>();
      final accepted = Completer<void>();
      var admissions = 0;
      final subscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        peers.add(socket);
        socket.listen((frame) {
          final value = jsonDecode(frame as String) as Map;
          if (value['id'] == null) return;
          final method = value['method'];
          final reply = <String, dynamic>{'jsonrpc': '2.0', 'id': value['id']};
          if (method == 'prompt.submit') {
            if (status == 'rejected') {
              reply['error'] = {'code': 4090, 'message': 'Fixture refusal'};
            } else {
              reply['result'] = {'status': status};
            }
            socket.add(jsonEncode(reply));
            prompt.complete();
          } else {
            reply['result'] = {};
            socket.add(jsonEncode(reply));
          }
        });
      });
      final client = WsClient('http://127.0.0.1:${server.port}');
      try {
        await client.connect();
        final operation = client.submitPrompt(
          'fixture voice text',
          sessionId: 'fixture',
          onEvent: (_) {},
          onAccepted: () {
            admissions++;
            if (!accepted.isCompleted) accepted.complete();
          },
        );
        final ended = expectLater(operation, throwsA(isA<JsonRpcError>()));
        await prompt.future.timeout(const Duration(seconds: 5));
        if (status == 'streaming' || status == 'queued') {
          await accepted.future.timeout(const Duration(seconds: 5));
          expect(admissions, 1);
        } else if (status == 'unknown') {
          await client.send('fixture.barrier', {});
          expect(admissions, 0);
        } else {
          await ended;
          expect(admissions, 0);
        }
        client.close();
        await ended;
      } finally {
        client.close();
        for (final peer in peers) {
          await peer.close();
        }
        await subscription.cancel();
        await server.close(force: true);
      }
    });
  }
}
