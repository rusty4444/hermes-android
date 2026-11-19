import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';

void main() {
  group('isRejectedSubmissionIdError', () {
    test('matches gateway code 4094', () {
      expect(
        isRejectedSubmissionIdError(
          JsonRpcError('prompt.submit', 'unsupported', code: 4094),
        ),
        isTrue,
      );
    });

    test('matches legacy 4000/-32602 extra-field validation errors', () {
      expect(
        isRejectedSubmissionIdError(
          JsonRpcError(
            'prompt.submit',
            'Invalid params: submission_id: Extra inputs are not permitted',
            code: 4000,
          ),
        ),
        isTrue,
      );
      expect(
        isRejectedSubmissionIdError(
          JsonRpcError(
            'prompt.submit',
            'Unexpected parameter submission_id',
            code: -32602,
          ),
        ),
        isTrue,
      );
    });

    test('ignores unrelated 4000 errors and other error codes', () {
      expect(
        isRejectedSubmissionIdError(
          JsonRpcError(
            'prompt.submit',
            'Invalid params: session_id is required',
            code: 4000,
          ),
        ),
        isFalse,
      );
      expect(
        isRejectedSubmissionIdError(
          JsonRpcError(
            'prompt.submit',
            'submission_id: Extra inputs are not permitted',
            code: 4001,
          ),
        ),
        isFalse,
      );
    });
  });

  group('WsClient.submitPrompt submission_id', () {
    test(
      'retries without submission_id when legacy gateway rejects it',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final recordedPrompts = <Map<String, dynamic>>[];
        server.listen((req) async {
          if (!WebSocketTransformer.isUpgradeRequest(req)) {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
            return;
          }
          final ws = await WebSocketTransformer.upgrade(req);
          ws.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'gateway.ready',
                'protocol_version': 1,
                'capabilities': ['prompt.submit'],
              },
            }),
          );
          ws.listen((raw) {
            final frame = jsonDecode(raw as String) as Map<String, dynamic>;
            if (frame['method'] != 'prompt.submit') return;
            final params = Map<String, dynamic>.from(frame['params'] as Map);
            recordedPrompts.add(params);
            final id = frame['id'];
            if (params.containsKey('submission_id')) {
              ws.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': id,
                  'error': {
                    'code': 4000,
                    'message':
                        'Invalid params: submission_id: Extra inputs are not permitted',
                  },
                }),
              );
              return;
            }
            ws.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': id,
                'result': {'accepted': true},
              }),
            );
            ws.add(
              jsonEncode({
                'jsonrpc': '2.0',
                'method': 'event',
                'params': {
                  'type': 'turn.end',
                  'session_id': params['session_id'],
                  'payload': {},
                },
              }),
            );
          });
        });

        final client = WsClient('http://127.0.0.1:${server.port}');
        addTearDown(client.close);
        await client.connect().timeout(const Duration(seconds: 5));

        final events = <String>[];
        await client.submitPrompt(
          'hi there',
          sessionId: 'sess-1',
          onEvent: (event) => events.add(event.type),
        );

        expect(recordedPrompts, hasLength(2));
        expect(recordedPrompts[0]['submission_id'], isA<String>());
        expect(recordedPrompts[1].containsKey('submission_id'), isFalse);
        expect(recordedPrompts[1]['text'], 'hi there');
        expect(events, contains('turn.end'));
      },
    );

    test('fallback re-checks admission after a legacy refusal', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final recordedPrompts = <Map<String, dynamic>>[];
      var admitted = true;
      server.listen((req) async {
        if (!WebSocketTransformer.isUpgradeRequest(req)) {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        ws.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {
              'type': 'gateway.ready',
              'protocol_version': 1,
              'capabilities': ['prompt.submit'],
            },
          }),
        );
        ws.listen((raw) {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          if (frame['method'] != 'prompt.submit') return;
          final params = Map<String, dynamic>.from(frame['params'] as Map);
          recordedPrompts.add(params);
          // The owner loses admission while the refusal is in flight; the
          // compatibility retry must not write onto a stale admission.
          admitted = false;
          ws.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': frame['id'],
              'error': {
                'code': 4000,
                'message':
                    'Invalid params: submission_id: Extra inputs are not permitted',
              },
            }),
          );
        });
      });

      final client = WsClient('http://127.0.0.1:${server.port}');
      addTearDown(client.close);
      await client.connect().timeout(const Duration(seconds: 5));

      await expectLater(
        client.submitPrompt(
          'hi there',
          sessionId: 'sess-1',
          onEvent: (_) {},
          maySend: () => admitted,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        recordedPrompts,
        hasLength(1),
        reason: 'the fallback must not write after admission is lost',
      );
    });
  });
}
