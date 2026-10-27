import 'dart:async';
import 'dart:convert';

// flutter_test supplies the deterministic timer clock; no new dependency.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;

String _data(Object value, [String newline = '\n']) =>
    'data: ${jsonEncode(value)}$newline$newline';

String _token(String text, [String newline = '\n']) => _data({
  'choices': [
    {
      'index': 0,
      'delta': {'content': text},
      'finish_reason': null,
    },
  ],
}, newline);

String _finish(String reason, [String newline = '\n']) => _data({
  'choices': [
    {'index': 0, 'delta': <String, dynamic>{}, 'finish_reason': reason},
  ],
}, newline);

String _done([String newline = '\n']) => 'data: [DONE]$newline$newline';

String _tool([String newline = '\n']) =>
    'event: hermes.tool.progress${newline}data: '
    '${jsonEncode({'tool': 'terminal', 'toolCallId': 'call-1', 'status': 'completed'})}'
    '$newline$newline';

String _reasoning(String text, [String newline = '\n']) => _data({
  'choices': [
    {
      'delta': {'reasoning_content': text},
    },
  ],
}, newline);

String _status([String newline = '\n']) =>
    'event: hermes.status$newline${_data({'kind': 'compacting', 'text': 'Compacting context…'}, newline)}';

void main() {
  group('GatewayChatClient body inactivity (#207 M1)', () {
    test('fragmented UTF-8 bytes renew the budget before text decoding', () {
      fakeAsync((clock) {
        final client = _ControlledClient();
        final response = client.enqueue(cleanup: Future<void>.value());
        final probe = _Probe(client);
        probe.send();
        clock.flushMicrotasks();
        try {
          final bytes = utf8.encode(_token('🐈'));
          final start = bytes.indexOf(0xf0);
          response.body.add(bytes.sublist(0, start + 1));
          clock.flushMicrotasks();
          for (var i = 1; i < 4; i++) {
            clock.elapse(const Duration(seconds: 59));
            response.body.add([bytes[start + i]]);
            clock.flushMicrotasks();
            expect(probe.errors, isEmpty);
          }
          response.body.add([
            ...bytes.sublist(start + 4),
            ...utf8.encode(_done()),
          ]);
          clock.flushMicrotasks();
          expect(probe.tokens, ['🐈']);
          expect(probe.done, 1);
        } finally {
          probe.gateway.abort();
          probe.api.close();
          clock.flushMicrotasks();
        }
      });
    });

    test('cancelled and superseded bodies cannot time out a newer send', () {
      fakeAsync((clock) {
        final client = _ControlledClient();
        final old = client.enqueue(cleanup: Future<void>.value());
        final current = client.enqueue(cleanup: Future<void>.value());
        final probe = _Probe(client);
        var oldSettled = false;
        probe.send();
        probe.gateway.whenStreamSettles().then((_) => oldSettled = true);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 59));
        probe.send();
        clock.flushMicrotasks();
        try {
          expect(old.cancelled, isTrue);
          expect(oldSettled, isTrue);
          clock.elapse(const Duration(seconds: 59));
          expect(probe.events, isEmpty);
          var cancelled = false;
          probe.gateway.cancelActiveMessage().then(
            (value) => cancelled = value,
          );
          clock.flushMicrotasks();
          clock.elapse(const Duration(minutes: 3));
          expect(current.cancelled, isTrue);
          expect(cancelled, isTrue);
          expect(probe.gateway.isStreaming, isFalse);
          expect(probe.events, isEmpty);
        } finally {
          probe.gateway.abort();
          probe.api.close();
          clock.flushMicrotasks();
        }
      });
    });

    for (final status in [200, 503]) {
      test(
        'stalled HTTP $status body fails once and settles without retry',
        () {
          fakeAsync((clock) {
            final client = _ControlledClient();
            final response = client.enqueue(
              status: status,
              cleanup: Future<void>.value(),
            );
            final probe = _Probe(client);
            var sent = false;
            var settled = false;
            probe.send().then((_) => sent = true);
            probe.gateway.whenStreamSettles().then((_) => settled = true);
            clock.flushMicrotasks();
            try {
              clock.elapse(const Duration(seconds: 59));
              expect(probe.events, isEmpty);
              expect(sent, isFalse);
              clock.elapse(const Duration(seconds: 1));
              clock.flushMicrotasks();
              expect(probe.errors, hasLength(1));
              expect(probe.errors.single, contains('TimeoutException'));
              expect(probe.done, 0);
              expect(sent, isTrue);
              expect(settled, isTrue);
              expect(response.cancelled, isTrue);
              expect(probe.gateway.isStreaming, isFalse);
              expect(
                client._next,
                1,
                reason: 'an uncertain POST is never resent',
              );
              expect(client.closed, isFalse);
              response.body.add(utf8.encode('${_token('late')}${_done()}'));
              clock.elapse(const Duration(minutes: 3));
              expect(probe.errors, hasLength(1));
              expect(probe.tokens, isEmpty);
            } finally {
              probe.gateway.abort();
              probe.api.close();
              clock.flushMicrotasks();
            }
          });
        },
      );
    }

    test(
      'keepalives and progress renew idle budget, not a total turn deadline',
      () {
        fakeAsync((clock) {
          final client = _ControlledClient();
          final response = client.enqueue(cleanup: Future<void>.value());
          final probe = _Probe(client);
          var sent = false;
          probe.send().then((_) => sent = true);
          clock.flushMicrotasks();
          try {
            for (final frame in [
              ': keepalive\n\n',
              _tool(),
              _reasoning('thinking'),
              _status(),
            ]) {
              clock.elapse(const Duration(seconds: 59));
              response.body.add(utf8.encode(frame));
              clock.flushMicrotasks();
              expect(probe.errors, isEmpty);
              expect(sent, isFalse);
            }
            clock.elapse(const Duration(seconds: 59));
            response.body.add(utf8.encode('${_token('answer')}${_done()}'));
            clock.flushMicrotasks();
            expect(probe.done, 1);
            expect(sent, isTrue);
            expect(probe.errors, isEmpty);
            clock.elapse(const Duration(minutes: 3));
            expect(
              probe.errors,
              isEmpty,
              reason: 'terminal cleanup cancels watchdog',
            );
          } finally {
            probe.gateway.abort();
            probe.api.close();
            clock.flushMicrotasks();
          }
        });
      },
    );

    test('partial reply and provisional stop still fail after an idle gap', () {
      fakeAsync((clock) {
        final client = _ControlledClient();
        final response = client.enqueue(cleanup: Future<void>.value());
        final probe = _Probe(client);
        probe.send();
        clock.flushMicrotasks();
        try {
          clock.elapse(const Duration(seconds: 59));
          response.body.add(
            utf8.encode('${_token('partial')}${_finish('stop')}'),
          );
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 59));
          expect(probe.errors, isEmpty);
          clock.elapse(const Duration(seconds: 1));
          clock.flushMicrotasks();
          expect(probe.tokens, ['partial']);
          expect(probe.done, 0);
          expect(probe.errors, hasLength(1));
          expect(response.cancelled, isTrue);
        } finally {
          probe.gateway.abort();
          probe.api.close();
          clock.flushMicrotasks();
        }
      });
    });

    test('timeout joins held body cleanup before reporting and settling', () {
      fakeAsync((clock) {
        final cleanup = Completer<void>();
        final client = _ControlledClient();
        final response = client.enqueue(cleanup: cleanup.future);
        final probe = _Probe(client);
        var settled = false;
        probe.send();
        probe.gateway.whenStreamSettles().then((_) => settled = true);
        clock.flushMicrotasks();
        try {
          clock.elapse(const Duration(seconds: 60));
          clock.flushMicrotasks();
          expect(response.cancelled, isTrue);
          expect(probe.events, isEmpty);
          expect(settled, isFalse);
          cleanup.complete();
          clock.flushMicrotasks();
          expect(probe.errors, hasLength(1));
          expect(settled, isTrue);
        } finally {
          if (!cleanup.isCompleted) cleanup.complete();
          probe.gateway.abort();
          probe.api.close();
          clock.flushMicrotasks();
        }
      });
    });
  });

  group('GatewayChatClient completion authority', () {
    for (final newline in ['\n', '\r\n']) {
      test('fragmented reasoning and status remain separate from reply text '
          'for newline ${newline.length}', () async {
        final result = await _run(
          '${_reasoning('Inspecting 🐈', newline)}'
          '${_tool(newline)}${_status(newline)}'
          '${_token('answer', newline)}${_finish('stop', newline)}'
          '${_done(newline)}',
          fragmentBytes: 1,
        );
        expect(result.events, [
          'reasoning:Inspecting 🐈',
          'tool:terminal',
          'status:compacting',
          'token:answer',
          'done',
        ]);
        expect(result.tokens, ['answer']);
        expect(result.errors, isEmpty);
      });
    }

    for (final newline in ['\n', '\r\n']) {
      final label = newline == '\n' ? 'LF' : 'CRLF';
      for (final fragmentBytes in [1, 7, 4096]) {
        test('$label fragmented $fragmentBytes bytes preserves receipt order '
            'and successful completion', () async {
          final result = await _run(
            ': keepalive$newline$newline'
            '${_token('first 🐈', newline)}'
            '${_tool(newline)}'
            '${_token('final', newline)}'
            '${_finish('stop', newline)}'
            '${_data({
              'choices': [],
              'usage': {'total_tokens': 3},
            }, newline)}'
            '${_done(newline)}',
            fragmentBytes: fragmentBytes,
          );
          expect(result.events, [
            'token:first 🐈',
            'tool:terminal',
            'token:final',
            'done',
          ]);
          expect(result.errors, isEmpty);
          expect(result.done, 1);
        });
      }
    }

    for (final terminal in {
      'stop followed by EOF': _finish('stop'),
      'stop and DONE': '${_finish('stop')}${_done()}',
      'legacy DONE without finish_reason': _done(),
    }.entries) {
      test('accepts ${terminal.key} after assistant text', () async {
        final result = await _run('${_token('answer')}${terminal.value}');
        expect(result.tokens, ['answer']);
        expect(result.done, 1);
        expect(result.errors, isEmpty);
      });
    }

    for (final incomplete in {
      'empty EOF': '',
      'partial then EOF': _token('partial'),
      'keepalive then EOF': ': keepalive\n\n',
      'role-only EOF': _data({
        'choices': [
          {
            'delta': {'role': 'assistant'},
          },
        ],
      }),
      'unframed stop':
          '${_token('partial')}data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
      'unframed DONE': '${_token('partial')}data: [DONE]',
      'partial JSON tail': '${_token('partial')}data: {"choices":',
      'DONE without assistant text': _done(),
      'stop without assistant text': _finish('stop'),
      'tool progress only': '${_tool()}${_done()}',
      'reasoning only': '${_reasoning('private reasoning')}${_done()}',
      'reasoning and status only':
          '${_reasoning('private reasoning')}${_status()}${_finish('stop')}${_done()}',
      'whitespace only': '${_token('  ')}${_done()}',
      'tool-call after commentary without a final assistant finish':
          '${_token('commentary')}${_data({
            'choices': [
              {
                'delta': {
                  'function_call': {'name': 'terminal'},
                },
              },
            ],
          })}${_done()}',
      'tool-call delta only':
          '${_data({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {'id': 'call-1'},
                  ],
                },
              },
            ],
          })}${_done()}',
    }.entries) {
      test(
        'rejects ${incomplete.key} without a completed assistant reply',
        () async {
          final result = await _run(incomplete.value);
          expect(result.done, 0);
          expect(result.errors, hasLength(1));
          expect(result.events.last, startsWith('error:'));
        },
      );
    }

    final errors = <String, String>{
      'OpenAI JSON error': _data({
        'error': {'message': 'upstream failed', 'type': 'server_error'},
      }),
      'string JSON error': _data({'error': 'upstream failed'}),
      'typed JSON error': _data({
        'type': 'error',
        'message': 'upstream failed',
      }),
      'Hermes backend failure envelope': _data({
        'object': 'chat.completion.chunk',
        'choices': [
          {'index': 0, 'delta': {}, 'finish_reason': 'length'},
        ],
        'error': {'message': 'upstream failed', 'type': 'agent_error'},
        'hermes': {
          'completed': false,
          'partial': true,
          'failed': false,
          'error': 'upstream failed',
          'error_code': 'output_truncated',
        },
      }),
      'event:error JSON':
          'event: error\n${_data({'message': 'upstream failed'})}',
      'event:error plain text': 'event:error\ndata: upstream failed\n\n',
      'event:error without data': 'event: error\n\n',
      'event:error with DONE payload': 'event: error\n${_done()}',
      'Hermes failed': _data({
        'hermes': {'failed': true, 'error': 'upstream failed'},
      }),
      'Hermes partial': _data({
        'hermes': {'partial': true, 'completed': false},
      }),
      'Hermes incomplete stop': _data({
        'choices': [
          {'delta': {}, 'finish_reason': 'stop'},
        ],
        'hermes': {'completed': false},
      }),
      for (final reason in [
        'error',
        'length',
        'content_filter',
        'tool_calls',
        'function_call',
        'unknown',
      ])
        'finish_reason $reason': _finish(reason),
    };
    for (final failure in errors.entries) {
      test('partial + ${failure.key} + DONE errors exactly once and mutes '
          'later frames in the same chunk', () async {
        final result = await _run(
          '${_token('partial')}${failure.value}'
          '${_reasoning('must be muted')}${_status()}'
          '${_token('must be muted')}${_tool()}${_finish('stop')}${_done()}',
        );
        expect(result.tokens, ['partial']);
        expect(result.tools, isEmpty);
        expect(result.reasoning, isEmpty);
        expect(result.statuses, isEmpty);
        expect(result.done, 0);
        expect(result.errors, hasLength(1));
        if (failure.value.contains('upstream failed')) {
          expect(result.errors.single, contains('upstream failed'));
        }
      });
    }

    for (final newline in ['\n', '\r\n']) {
      test(
        'fragmented error and DONE stay failed for newline ${newline.length}',
        () async {
          final result = await _run(
            '${_token('partial 🐈', newline)}'
            'event: error$newline${_data({
              'error': {'message': 'failed 🐈'},
            }, newline)}'
            '${_token('late', newline)}${_done(newline)}',
            fragmentBytes: 1,
          );
          expect(result.tokens, ['partial 🐈']);
          expect(result.done, 0);
          expect(result.errors, ['failed 🐈']);
        },
      );
    }

    test('a stop frame cannot hide a following error before DONE', () async {
      final result = await _run(
        '${_token('partial')}${_finish('stop')}'
        '${_data({
          'error': {'message': 'late failure'},
        })}${_done()}',
      );
      expect(result.done, 0);
      expect(result.errors, ['late failure']);
    });

    for (final malformed in [
      'not JSON',
      '{"choices":',
      '[]',
      'null',
      '{"choices": {}}',
      '{"choices": [null]}',
      '{"choices": [{"delta": "invalid"}]}',
      '{"choices": [{"delta": {"content": 42}}]}',
      '{"choices": [{"delta": {"reasoning_content": 42}}]}',
      '{"choices": [{"delta": {}, "finish_reason": 42}]}',
    ]) {
      test(
        'malformed frame $malformed fails closed despite later DONE',
        () async {
          final result = await _run(
            '${_token('partial')}data: $malformed\n\n${_token('late')}${_done()}',
          );
          expect(result.tokens, ['partial']);
          expect(result.done, 0);
          expect(result.errors, hasLength(1));
        },
      );
    }

    test(
      'multiline JSON, SSE metadata and unknown event types remain compatible',
      () async {
        final result = await _run(
          'id: 12\nretry: 1000\ndata: {"choices":\n'
          'data: [{"delta":{"content":"answer"}}]}\n\n'
          'event: hermes.status\n${_data({'status': 'working'})}'
          '${_done()}',
          fragmentBytes: 1,
        );
        expect(result.tokens, ['answer']);
        expect(result.done, 1);
        expect(result.errors, isEmpty);
      },
    );

    test(
      'invalid UTF-8 reports one error rather than successful EOF',
      () async {
        final client = _ControlledClient();
        final response = client.enqueue();
        final probe = _Probe(client);
        final sending = probe.send();
        final settled = probe.gateway.whenStreamSettles();
        await response.listening.future;
        response.body.add([...utf8.encode(_token('partial')), 0xff]);
        response.body.add(utf8.encode(_done()));
        await sending;
        await settled;
        expect(probe.done, 0);
        expect(probe.errors, hasLength(1));
        expect(probe.gateway.isStreaming, isFalse);
        probe.api.close();
      },
    );

    test('transport error after stop still fails exactly once', () async {
      final client = _ControlledClient();
      final response = client.enqueue();
      final probe = _Probe(client);
      final sending = probe.send();
      await response.listening.future;
      response.body.add(utf8.encode('${_token('partial')}${_finish('stop')}'));
      response.body.addError(StateError('socket lost'));
      response.body.add(utf8.encode(_done()));
      await sending;
      await probe.gateway.whenStreamSettles();
      expect(probe.tokens, ['partial']);
      expect(probe.done, 0);
      expect(probe.errors, hasLength(1));
      probe.api.close();
    });
  });

  group('GatewayChatClient cancellation and detached settlement', () {
    test(
      'cancellation in reasoning mutes the same-frame text and later status',
      () async {
        final client = _ControlledClient();
        final response = client.enqueue();
        final probe = _Probe(client);
        final sending = probe.send(
          onReasoning: (_) => probe.gateway.cancelActiveMessage(),
        );
        await response.listening.future;
        response.body.add(
          utf8.encode(
            '${_data({
              'choices': [
                {
                  'delta': {'reasoning_content': 'Before cancel', 'content': 'Must not arrive'},
                },
              ],
            })}${_status()}${_done()}',
          ),
        );
        await sending;
        await probe.gateway.whenStreamSettles();
        await response.body.close();
        expect(probe.events, ['reasoning:Before cancel']);
        expect(probe.tokens, isEmpty);
        expect(probe.statuses, isEmpty);
        expect(probe.done, 0);
        expect(probe.errors, isEmpty);
        probe.api.close();
      },
    );

    for (final reply in {
      'OpenAI JSON': '{"error":{"message":"model unavailable"}}',
      'string JSON': '{"error":"model unavailable"}',
      'non-JSON proxy': '<html>unavailable</html>',
    }.entries) {
      test(
        'non-200 ${reply.key} fails once and settles detached waiters',
        () async {
          final client = _ControlledClient();
          final response = client.enqueue(status: 503);
          final probe = _Probe(client);
          final sending = probe.send();
          final settling = probe.gateway.whenStreamSettles();
          await response.listening.future;
          response.body.add(utf8.encode(reply.value));
          await response.body.close();
          await sending;
          await settling;
          expect(probe.done, 0);
          expect(probe.errors, [
            reply.key == 'non-JSON proxy' ? 'HTTP 503' : 'model unavailable',
          ]);
          expect(probe.gateway.isStreaming, isFalse);
          probe.api.close();
        },
      );
    }

    test(
      'DONE without EOF joins cleanup before callback and detached settlement',
      () async {
        final cleanup = Completer<void>();
        final client = _ControlledClient();
        final response = client.enqueue(cleanup: cleanup.future);
        final probe = _Probe(client);
        final sending = probe.send();
        var settled = false;
        final settling = probe.gateway.whenStreamSettles().then(
          (_) => settled = true,
        );
        await response.listening.future;
        response.body.add(utf8.encode('${_token('answer')}${_done()}'));
        await pumpEventQueue();
        expect(response.cancelled, isTrue);
        expect(probe.done, 0);
        expect(settled, isFalse);
        cleanup.complete();
        await sending;
        await settling;
        expect(probe.done, 1);
        expect(probe.errors, isEmpty);
        expect(settled, isTrue);
        probe.api.close();
      },
    );

    for (final abort in [false, true]) {
      test('${abort ? 'abort' : 'cancel'} inside a token callback mutes later '
          'frames in that same network chunk', () async {
        final client = _ControlledClient();
        final response = client.enqueue();
        final probe = _Probe(client);
        Future<bool>? cancellation;
        final sending = probe.send(
          onToken: (_) {
            if (abort) {
              probe.gateway.abort();
            } else {
              cancellation = probe.gateway.cancelActiveMessage();
            }
          },
        );
        final settled = probe.gateway.whenStreamSettles();
        await response.listening.future;
        response.body.add(
          utf8.encode(
            '${_token('first')}${_token('late')}${_tool()}'
            '${_data({
              'error': {'message': 'late error'},
            })}${_done()}',
          ),
        );
        await pumpEventQueue();
        if (!abort) expect(await cancellation, isTrue);
        await sending;
        await settled;
        expect(probe.tokens, ['first']);
        expect(probe.tools, isEmpty);
        expect(probe.done, 0);
        expect(probe.errors, isEmpty);
        expect(response.cancelled, isTrue);
        expect(client.closed, isFalse);
        probe.api.close();
      });
    }

    test(
      'whenStreamSettles joins held body cancellation without late callbacks',
      () async {
        final cleanup = Completer<void>();
        final client = _ControlledClient();
        final response = client.enqueue(cleanup: cleanup.future);
        final probe = _Probe(client);
        final sending = probe.send();
        var settled = false;
        final settling = probe.gateway.whenStreamSettles().then(
          (_) => settled = true,
        );
        await response.listening.future;
        final cancelling = probe.gateway.cancelActiveMessage();
        response.body.add(utf8.encode('${_token('late')}${_done()}'));
        await pumpEventQueue();
        expect(
          settled,
          isFalse,
          reason: 'socket cleanup must be joined before detached close',
        );
        cleanup.complete();
        expect(await cancelling, isTrue);
        await sending;
        await settling;
        expect(settled, isTrue);
        expect(probe.events, isEmpty);
        expect(probe.gateway.isStreaming, isFalse);
        probe.api.close();
      },
    );

    test(
      'supersession mutes old tokens, errors and DONE without retiring the new stream',
      () async {
        final client = _ControlledClient();
        final oldResponse = client.enqueue();
        final newResponse = client.enqueue();
        final probe = _Probe(client);
        final oldSending = probe.send();
        final oldSettling = probe.gateway.whenStreamSettles();
        await oldResponse.listening.future;
        oldResponse.body.add(utf8.encode(_token('first')));
        await pumpEventQueue();
        final newSending = probe.send();
        await newResponse.listening.future;
        oldResponse.body.add(
          utf8.encode(
            '${_token('late')}${_data({'error': 'old failure'})}${_done()}',
          ),
        );
        await oldSending;
        await oldSettling;
        expect(probe.gateway.isStreaming, isTrue);
        newResponse.body.add(utf8.encode('${_token('second')}${_done()}'));
        await newSending;
        await probe.gateway.whenStreamSettles();
        expect(probe.tokens, ['first', 'second']);
        expect(probe.done, 1);
        expect(probe.errors, isEmpty);
        expect(oldResponse.cancelled, isTrue);
        expect(client.closed, isFalse);
        probe.api.close();
      },
    );

    for (final lateFailure in [false, true]) {
      test('pre-header cancellation settles and ignores late '
          '${lateFailure ? 'failure' : 'response'}', () async {
        final headers = Completer<void>();
        final client = _ControlledClient();
        final response = client.enqueue(
          headers: headers.future,
          failHeaders: lateFailure,
        );
        final probe = _Probe(client);
        final sending = probe.send();
        final settling = probe.gateway.whenStreamSettles();
        expect(await probe.gateway.cancelActiveMessage(), isTrue);
        await sending.timeout(const Duration(seconds: 1));
        await settling.timeout(const Duration(seconds: 1));
        headers.complete();
        await pumpEventQueue();
        expect(probe.events, isEmpty);
        expect(probe.gateway.isStreaming, isFalse);
        if (!lateFailure) expect(response.cancelled, isTrue);
        expect(client.closed, isFalse);
        probe.api.close();
      });
    }

    test(
      'cancellation while reading a held non-200 body settles without late error',
      () async {
        final client = _ControlledClient();
        final response = client.enqueue(status: 503);
        final probe = _Probe(client);
        final sending = probe.send();
        final settling = probe.gateway.whenStreamSettles();
        await response.listening.future;
        expect(await probe.gateway.cancelActiveMessage(), isTrue);
        await sending.timeout(const Duration(seconds: 1));
        await settling.timeout(const Duration(seconds: 1));
        response.body.add(
          utf8.encode('{"error":{"message":"late rejection"}}'),
        );
        await response.body.close();
        expect(probe.events, isEmpty);
        expect(client.closed, isFalse);
        probe.api.close();
      },
    );

    test(
      'failed headers settle detached waiters with exactly one error',
      () async {
        final headers = Completer<void>();
        final client = _ControlledClient();
        client.enqueue(headers: headers.future, failHeaders: true);
        final probe = _Probe(client);
        final sending = probe.send();
        final settling = probe.gateway.whenStreamSettles();
        headers.complete();
        await sending;
        await settling;
        expect(probe.done, 0);
        expect(probe.errors, hasLength(1));
        expect(probe.gateway.isStreaming, isFalse);
        probe.api.close();
      },
    );

    test(
      'protocol failure settles even when the server never sends EOF',
      () async {
        final client = _ControlledClient();
        final response = client.enqueue();
        final probe = _Probe(client);
        final sending = probe.send();
        final settling = probe.gateway.whenStreamSettles();
        await response.listening.future;
        response.body.add(
          utf8.encode(
            _data({
              'error': {'message': 'failed'},
            }),
          ),
        );
        await sending.timeout(const Duration(seconds: 1));
        await settling.timeout(const Duration(seconds: 1));
        response.body.add(utf8.encode('${_token('late')}${_done()}'));
        await response.body.close();
        expect(probe.done, 0);
        expect(probe.errors, ['failed']);
        expect(response.cancelled, isTrue);
        probe.api.close();
      },
    );
  });
}

Future<_Probe> _run(String wire, {int fragmentBytes = 4096}) async {
  final client = _ControlledClient();
  final response = client.enqueue();
  final probe = _Probe(client);
  final sending = probe.send();
  await response.listening.future;
  final bytes = utf8.encode(wire);
  for (var offset = 0; offset < bytes.length; offset += fragmentBytes) {
    response.body.add(
      bytes.sublist(offset, (offset + fragmentBytes).clamp(0, bytes.length)),
    );
  }
  await response.body.close();
  await sending;
  await probe.gateway.whenStreamSettles();
  expect(probe.gateway.isStreaming, isFalse);
  probe.api.close();
  return probe;
}

class _Probe {
  _Probe(_ControlledClient transport) {
    api = ApiClient(
      baseUrl: 'http://gateway.test:8642',
      apiKey: 'test-key',
      httpClient: transport,
    );
    gateway = GatewayChatClient(api);
  }

  late final ApiClient api;
  late final GatewayChatClient gateway;
  final tokens = <String>[];
  final reasoning = <String>[];
  final tools = <Map<String, dynamic>>[];
  final statuses = <Map<String, dynamic>>[];
  final errors = <String>[];
  final events = <String>[];
  var done = 0;

  Future<void> send({
    void Function(String)? onToken,
    void Function(String)? onReasoning,
  }) => gateway.sendMessageStreaming(
    message: 'question',
    sessionId: 'mob-sse-test',
    onToken: (token) {
      tokens.add(token);
      events.add('token:$token');
      onToken?.call(token);
    },
    onToolProgress: (progress) {
      tools.add(progress);
      events.add('tool:${progress['tool']}');
    },
    onReasoning: (text) {
      reasoning.add(text);
      events.add('reasoning:$text');
      onReasoning?.call(text);
    },
    onStatus: (status) {
      statuses.add(status);
      events.add('status:${status['kind']}');
    },
    onDone: () {
      done++;
      events.add('done');
    },
    onError: (error) {
      errors.add(error);
      events.add('error:$error');
    },
  );
}

class _ControlledResponse {
  _ControlledResponse({
    this.status = 200,
    this.headers,
    this.failHeaders = false,
    this.cleanup,
  }) {
    body = StreamController<List<int>>(
      onListen: listening.complete,
      onCancel: () {
        cancelled = true;
        return cleanup;
      },
    );
  }

  final int status;
  final Future<void>? headers;
  final bool failHeaders;
  final Future<void>? cleanup;
  final listening = Completer<void>();
  late final StreamController<List<int>> body;
  bool cancelled = false;
}

class _ControlledClient extends http.BaseClient {
  final responses = <_ControlledResponse>[];
  var _next = 0;
  bool closed = false;

  _ControlledResponse enqueue({
    int status = 200,
    Future<void>? headers,
    bool failHeaders = false,
    Future<void>? cleanup,
  }) {
    final response = _ControlledResponse(
      status: status,
      headers: headers,
      failHeaders: failHeaders,
      cleanup: cleanup,
    );
    responses.add(response);
    return response;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = responses[_next++];
    await response.headers;
    if (response.failHeaders) throw http.ClientException('headers failed');
    return http.StreamedResponse(response.body.stream, response.status);
  }

  @override
  void close() {
    closed = true;
    for (final response in responses) {
      if (!response.body.isClosed) unawaited(response.body.close());
    }
  }
}
