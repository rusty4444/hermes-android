import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/utils/chat_conversation_projection.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

void main() {
  group('quiet conversation projection', () {
    test('keeps users and only row-locally confirmed saved replies', () {
      final rows = [
        _user('First question'),
        _assistant('Plain commentary'),
        _assistant('Saved final', extra: {'status': 'completed'}),
        _user('Second question'),
        _assistant('Second final', extra: {'role': 'agent', 'success': true}),
      ];
      final before = jsonEncode(rows);
      final result = buildConversationDisplayItems(messages: rows);
      expect(_texts(result), [
        'First question',
        'Saved final',
        'Second question',
        'Second final',
      ]);
      expect(result[1]['_retry_prompt'], 'First question');
      expect(result.last['_retry_prompt'], 'Second question');
      expect(result.last['role'], 'assistant');
      expect(jsonEncode(rows), before, reason: 'projection is not ingress');
    });

    test('image-only and mixed image user rows remain conversation rows', () {
      final image = {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,fixture'},
      };
      final rows = <Map<String, dynamic>>[
        {
          'role': 'user',
          'content': [image],
        },
        _assistant('Image answer', extra: {'completed': true}),
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Describe this'},
            image,
          ],
        },
        _assistant('Mixed answer', extra: {'finish_reason': 'stop'}),
      ];
      final result = buildConversationDisplayItems(messages: rows);
      expect(_texts(result), [
        '[Image]',
        'Image answer',
        'Describe this\n\n[Image]',
        'Mixed answer',
      ]);
      expect(result.first['content'], same(rows.first['content']));
      expect(result.last['_retry_prompt'], 'Describe this\n\n[Image]');
    });

    for (final toolRow in <Map<String, dynamic>>[
      {'role': 'tool', 'content': 'tool result'},
      {'role': 'function', 'content': 'function result'},
      {
        'role': 'assistant',
        'content': '<untrusted_tool_result>raw result</untrusted_tool_result>',
      },
      {
        'role': 'assistant',
        'content': 'call commentary',
        'tool_calls': [{}],
      },
      {'role': 'assistant', 'content': 'call commentary', 'tool_calls': '[{}]'},
      {'role': 'assistant', 'content': 'call commentary', 'function_call': {}},
      {'role': 'assistant', 'content': 'call commentary', 'tool_call_id': 't1'},
      {'role': 'assistant', 'content': 'call commentary', 'toolCallId': 't1'},
      {
        'role': 'assistant',
        'content': 'call commentary',
        'finish_reason': 'tool_calls',
      },
    ]) {
      test('tool boundary discards plain pre-tool commentary: $toolRow', () {
        final rows = [_user('Question'), _assistant('I will inspect'), toolRow];
        expect(_texts(buildConversationDisplayItems(messages: rows)), [
          'Question',
        ]);
        expect(
          _texts(
            buildConversationDisplayItems(
              messages: [
                ...rows,
                _assistant('Final after tool', extra: {'status': 'completed'}),
              ],
            ),
          ),
          ['Question', 'Final after tool'],
        );
      });
    }

    test('empty tool_calls is not itself a tool boundary', () {
      for (final calls in [[], '[]', null]) {
        expect(
          _texts(
            buildConversationDisplayItems(
              messages: [
                _user('Question'),
                _assistant(
                  'Final',
                  extra: {'tool_calls': calls, 'completed': true},
                ),
              ],
            ),
          ),
          ['Question', 'Final'],
        );
      }
    });

    for (final flag in [
      '_gateway_interim',
      'interim',
      'is_interim',
      '_gateway_pending_response',
    ]) {
      test('$flag does not become final even with a completion flag', () {
        expect(
          _texts(
            buildConversationDisplayItems(
              messages: [
                _user('Question'),
                _assistant(
                  'Partial',
                  extra: {flag: true, '_chat_response_complete': true},
                ),
              ],
            ),
          ),
          ['Question'],
        );
      });
    }

    test('received output requires a positive response receipt per scope', () {
      final result = buildConversationDisplayItems(
        received: true,
        messages: [
          _user('Question'),
          _assistant('Unconfirmed'),
          _assistant('Lifecycle only', extra: {'status': 'completed'}),
          _assistant('Rejected', extra: {'_chat_response_complete': false}),
          _assistant(
            'Selected final',
            extra: {'_chat_response_complete': true},
          ),
          _assistant(
            'Other selected final',
            extra: {'_chat_response_complete': true},
          ),
        ],
      );
      expect(_texts(result), [
        'Question',
        'Selected final',
        'Other selected final',
      ]);
    });

    test(
      'received commentary/tool boundaries do not erase selected finals',
      () {
        final result = buildConversationDisplayItems(
          received: true,
          messages: [
            _user('Question'),
            _assistant(
              'Selected preview',
              extra: {'_chat_response_complete': true},
            ),
            _assistant('Unselected commentary'),
            {'role': 'tool', 'content': 'detail'},
            _assistant(
              'Continuation',
              extra: {'_gateway_pending_response': true},
            ),
          ],
        );
        expect(_texts(result), ['Question', 'Selected preview']);
      },
    );

    for (final kind in ['async_delegation_complete', 'process_complete']) {
      for (final role in ['assistant', 'user']) {
        test('hides annotated $kind report with role=$role', () {
          expect(
            _texts(
              buildConversationDisplayItems(
                messages: [
                  _user('Question'),
                  _assistant('Answer', extra: {'status': 'completed'}),
                  {
                    'role': role,
                    'content': 'Internal report body',
                    'display_kind': kind,
                    'display_metadata': {'display_text': 'Internal summary'},
                  },
                ],
              ),
            ),
            ['Question', 'Answer'],
          );
        });
      }
    }

    test('ordinary quoted report prose is not classified by its text', () {
      const prose = 'The background task completed; here is the answer.';
      expect(
        _texts(
          buildConversationDisplayItems(
            messages: [
              _assistant(prose, extra: {'success': true}),
            ],
          ),
        ),
        [prose],
      );
    });

    test('system, developer and reasoning-only rows do not make bubbles', () {
      expect(
        _texts(
          buildConversationDisplayItems(
            messages: [
              {'role': 'system', 'content': 'System detail'},
              {'role': 'developer', 'content': 'Developer detail'},
              _user('Question'),
              _assistant('', extra: {'_gateway_reasoning': 'Reasoning detail'}),
              _assistant(
                'Final',
                extra: {
                  '_gateway_reasoning': 'Sidecar detail',
                  'finish_reason': 'end_turn',
                },
              ),
            ],
          ),
        ),
        ['Question', 'Final'],
      );
    });

    test('row-local failure vetoes preserve unrelated completed answers', () {
      final result = buildConversationDisplayItems(
        messages: [
          _user('Older question', id: 1),
          _assistant(
            'Older confirmed answer',
            id: 2,
            extra: {'completed': true},
          ),
          _user('Interrupted question', id: 3),
          _assistant(
            'Known interrupted answer',
            id: 4,
            extra: {'completed': true, 'failed': true},
          ),
          _user('Newer question', id: 5),
          _assistant(
            'Unconfirmed tail',
            id: 6,
            extra: {'completed': true, 'status': 'interrupted'},
          ),
        ],
      );
      expect(_texts(result), [
        'Older question',
        'Older confirmed answer',
        'Interrupted question',
        'Newer question',
      ]);
    });

    test('anonymous partial is hidden by its own flags, not row position', () {
      expect(
        _texts(
          buildConversationDisplayItems(
            messages: [
              _user('Older question'),
              _assistant(
                'Older confirmed answer',
                extra: {'status': 'completed'},
              ),
              _user('Interrupted question'),
              _assistant(
                'Anonymous partial',
                extra: {'completed': true, 'partial': true},
              ),
            ],
          ),
        ),
        ['Older question', 'Older confirmed answer', 'Interrupted question'],
      );
    });

    test(
      'timeline is the retained source of prose, not its raw accumulator',
      () {
        final row = _assistant(
          'Unbounded raw accumulator',
          extra: {
            '_normal_projection_id': 'scope',
            '_chat_response_complete': true,
          },
        );
        final timeline = const ChatTimeline()
            .appendText('scope', 'Retained before. ')
            .reasoning(
              'scope',
              const GatewayReasoningUpdate(
                text: 'Hidden reasoning',
                mode: GatewayReasoningEventMode.append,
                verbose: true,
              ),
            )
            .appendText('scope', 'Retained after.');
        expect(
          _texts(
            buildConversationDisplayItems(
              messages: [row],
              timeline: timeline,
              received: true,
            ),
          ),
          ['Retained before. Retained after.'],
        );
      },
    );

    test('fully evicted scope never resurrects raw final text', () {
      var timeline = const ChatTimeline().appendText('evicted', 'Old receipt');
      for (var i = 0; i < ChatTimeline.maxRuns; i++) {
        timeline = timeline.appendText('new-$i', 'Retained $i');
      }
      expect(timeline.scopes, contains('evicted'));
      expect(timeline.forScope('evicted'), isEmpty);
      expect(
        buildConversationDisplayItems(
          messages: [
            _assistant(
              'Old raw accumulator',
              extra: {
                '_normal_projection_id': 'evicted',
                '_chat_response_complete': true,
              },
            ),
          ],
          timeline: timeline,
          received: true,
        ),
        isEmpty,
      );
    });

    test('text budget eviction keeps only retained suffix', () {
      final timeline = const ChatTimeline().appendText(
        'bounded',
        'x' * ChatTimeline.maxTextCodeUnits + 'retained suffix',
      );
      final result = buildConversationDisplayItems(
        received: true,
        timeline: timeline,
        messages: [
          _assistant(
            'Raw body must not win',
            extra: {
              '_normal_projection_id': 'bounded',
              '_chat_response_complete': true,
            },
          ),
        ],
      );
      final text = result.single['_display_content'] as String;
      expect(text.length, ChatTimeline.maxTextCodeUnits);
      expect(text, endsWith('retained suffix'));
      expect(text, isNot(contains('Raw body')));
    });
  });

  group('strict source-local final evidence', () {
    for (final evidence in <Map<String, dynamic>>[
      {'_chat_response_complete': true},
      {'status': 'completed'},
      {'status': 'complete'},
      {'status': 'done'},
      {'status': 'success'},
      {'status': 'succeeded'},
      {'finish_reason': 'stop'},
      {'finish_reason': 'end_turn'},
      {'completed': true},
      {'success': true},
    ]) {
      test('canonical accepts positive row-local evidence: $evidence', () {
        final rows = [_user('Question'), _assistant('Final', extra: evidence)];
        expect(_texts(buildConversationDisplayItems(messages: rows)), [
          'Question',
          'Final',
        ]);
        expect(
          _texts(buildConversationDisplayItems(messages: rows, received: true)),
          [
            'Question',
            if (evidence['_chat_response_complete'] == true) 'Final',
          ],
          reason: 'received prose requires its own explicit completion flag',
        );
      });
    }

    for (final metadata in <Map<String, dynamic>>[
      {},
      {'id': 900},
      {'timestamp': 1234.0},
      {'type': 'final'},
      {'_gateway_pending_response': false},
      {'tool_calls': []},
      {'model': 'saved-model', 'usage': <String, dynamic>{}},
    ]) {
      test('untyped history is not successful evidence: $metadata', () {
        final rows = [
          _user('Question'),
          _assistant('Saved prose, not a confirmed reply', extra: metadata),
        ];
        final before = jsonEncode(rows);
        expect(_texts(buildConversationDisplayItems(messages: rows)), [
          'Question',
        ]);
        expect(jsonEncode(rows), before);
        expect(
          _texts(buildChatDisplayItems(messages: rows, verbose: true)),
          contains('Saved prose, not a confirmed reply'),
          reason: 'quiet must hide, not delete, unknown history from Verbose',
        );
      });
    }

    test('preserves every positive final in source order across tools', () {
      final rows = [
        _user('Question', id: 1),
        _assistant('First confirmed reply', id: 2, extra: {'success': true}),
        _assistant('Unconfirmed commentary', id: 3),
        {'id': 4, 'role': 'tool', 'content': 'Tool detail'},
        _assistant('Second confirmed reply', id: 5, extra: {'completed': true}),
        _assistant('More unconfirmed commentary', id: 6),
        _assistant(
          'Third confirmed reply',
          id: 7,
          extra: {'finish_reason': 'end_turn'},
        ),
        _user('Next question', id: 8),
        _assistant('Next confirmed reply', id: 9, extra: {'status': 'success'}),
        _assistant('Trailing untyped partial', id: 10),
      ];
      final result = buildConversationDisplayItems(messages: rows);
      expect(_texts(result), [
        'Question',
        'First confirmed reply',
        'Second confirmed reply',
        'Third confirmed reply',
        'Next question',
        'Next confirmed reply',
      ]);
      expect(result.map((row) => row['id']), [1, 2, 5, 7, 8, 9]);
      expect(result[1]['_retry_prompt'], 'Question');
      expect(result[2]['_retry_prompt'], 'Question');
      expect(result[3]['_retry_prompt'], 'Question');
      expect(result.last['_retry_prompt'], 'Next question');
    });

    for (final veto in <Map<String, dynamic>>[
      {'partial': true},
      {'failed': true},
      {'completed': false},
      {'success': false},
      {'status': 'interrupted'},
      {'status': 'unknown'},
      {'error': 'late failure'},
      {'finish_reason': 'length'},
      {'finish_reason': 'tool_calls'},
      {'interim': true},
      {'is_interim': true},
      {'_gateway_interim': true},
      {'_gateway_pending_response': true},
      {
        'tool_calls': [{}],
      },
      {'function_call': <String, dynamic>{}},
      {'tool_call_id': 'call'},
      {'toolCallId': 'call'},
      {'_chat_response_complete': false},
    ]) {
      for (final received in [false, true]) {
        test('positive final never overrides $veto: received=$received', () {
          expect(
            buildConversationDisplayItems(
              received: received,
              messages: [
                _assistant(
                  'Vetoed prose',
                  extra: {
                    '_chat_response_complete': true,
                    'completed': true,
                    'status': 'completed',
                    ...veto,
                  },
                ),
              ],
            ),
            isEmpty,
          );
        });
      }
    }

    test('later B success cannot bless a delayed prior A partial', () {
      final b = _assistant(
        'Confirmed B reply',
        id: 22,
        extra: {'status': 'completed'},
      );
      final lagging = [
        _user('A question', id: 10),
        _user('B question', id: 21),
        b,
      ];
      expect(_texts(buildConversationDisplayItems(messages: lagging)), [
        'A question',
        'B question',
        'Confirmed B reply',
      ]);
      for (final partial in <Map<String, dynamic>>[
        {},
        {'partial': true},
        {'status': 'interrupted'},
        {'status': 'completed', 'partial': true},
      ]) {
        // The ID is older, but its history observation arrives after B settled.
        // No floor, last-assistant heuristic or B receipt supplies A evidence.
        final delayed = [
          ...lagging,
          _assistant('Delayed A partial', id: 11, extra: partial),
        ];
        expect(_texts(buildConversationDisplayItems(messages: delayed)), [
          'A question',
          'B question',
          'Confirmed B reply',
        ]);
        expect(
          _texts(buildChatDisplayItems(messages: delayed, verbose: true)),
          contains('Delayed A partial'),
        );
      }
    });
  });

  group('independent saved and received sources', () {
    test('unconfirmed canonical prose cannot suppress a completed receipt', () {
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [
          _user('Saved question', id: 1),
          _assistant('Unconfirmed saved tail', id: 2),
        ],
        receivedRows: [
          _user('Received question'),
          _assistant(
            'Explicit received final',
            id: 2,
            extra: {'_chat_response_complete': true},
          ),
        ],
        receivedTimeline: const ChatTimeline(),
        conversationOnly: true,
      );
      expect(sections.map((s) => s.source), [
        ChatDisplaySource.canonical,
        ChatDisplaySource.received,
      ]);
      expect(_texts(sections.first.items), ['Saved question']);
      expect(_texts(sections.last.items), [
        'Received question',
        'Explicit received final',
      ]);
    });

    for (final sameText in [true, false]) {
      test(
        'quiet sources do not correlate by IDs or prose: sameText=$sameText',
        () {
          final sections = buildNormalChatDisplaySections(
            canonicalRows: [
              _user('Repeated question', id: 101),
              _assistant(
                'Saved final',
                id: 102,
                extra: {'status': 'completed'},
              ),
            ],
            receivedRows: [
              _user('Repeated question'),
              _assistant(
                sameText ? 'Saved final' : 'Received final',
                extra: {'_chat_response_complete': true, 'id': 102},
              ),
            ],
            receivedTimeline: const ChatTimeline(),
            conversationOnly: true,
          );
          expect(sections.map((s) => s.source), [
            ChatDisplaySource.canonical,
            ChatDisplaySource.received,
          ]);
          expect(_texts(sections.first.items), [
            'Repeated question',
            'Saved final',
          ]);
          expect(_texts(sections.last.items), [
            'Repeated question',
            sameText ? 'Saved final' : 'Received final',
          ]);
        },
      );
    }

    test('conversationOnly, not legacy verbose flag, chooses quiet helper', () {
      final tool = GatewayToolActivity.fromGatewayEvent('tool.start', {
        'name': 'terminal',
        'tool_id': 't1',
      })!;
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [
          _user('Question'),
          _assistant('Final', extra: {'completed': true}),
        ],
        receivedRows: [
          _assistant('Partial', extra: {'_gateway_pending_response': true}),
        ],
        canonicalTools: [tool],
        receivedTools: [tool],
        receivedTimeline: const ChatTimeline(),
        subagentActivities: const [
          GatewaySubagentActivity(
            id: 'child',
            goal: 'Hidden task',
            phase: GatewaySubagentPhase.running,
          ),
        ],
        notices: const [
          GatewayNotice(
            kind: GatewayNoticeKind.background,
            text: 'Hidden notice',
          ),
        ],
        verbose: true,
        conversationOnly: true,
      );
      expect(sections, hasLength(1));
      expect(_texts(sections.single.items), ['Question', 'Final']);
    });

    test('saved finals cannot confer a received partial completion', () {
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [
          _assistant('Identical answer', id: 50, extra: {'status': 'success'}),
        ],
        receivedRows: [_assistant('Identical answer')],
        receivedTimeline: const ChatTimeline(),
        conversationOnly: true,
      );
      expect(sections, hasLength(1));
      expect(sections.single.source, ChatDisplaySource.canonical);
    });
  });

  group('response success receipts', () {
    for (final metadata in <Map<String, dynamic>>[
      {},
      {'status': 'completed'},
      {'status': 'complete'},
      {'status': 'done'},
      {'status': 'success'},
      {'status': 'succeeded'},
      {'status': 'COMPLETED', 'finish_reason': 'stop'},
      {'success': true, 'finish_reason': 'end_turn'},
    ]) {
      test('accepts explicit successful or stock metadata: $metadata', () {
        expect(isSuccessfulResponseReceipt(metadata), isTrue);
      });
    }
    for (final metadata in <Map<String, dynamic>>[
      {'partial': true},
      {'failed': true},
      {'completed': false},
      {'success': false},
      {'error': 'failed'},
      {'status': 'failed'},
      {'status': 'error'},
      {'status': 'interrupted'},
      {'status': 'cancelled'},
      {'status': 'unknown'},
      {'status': 'running'},
      {'status': 'idle'},
      {'status': ''},
      {'finish_reason': 'length'},
      {'finish_reason': 'tool_calls'},
      {'finish_reason': 'content_filter'},
      {'status': 'completed', 'partial': true},
      {'status': 'completed', 'success': false},
      {'status': 'completed', 'error': 'late failure'},
    ]) {
      test('rejects partial, failed or uncertain metadata: $metadata', () {
        expect(isSuccessfulResponseReceipt(metadata), isFalse);
        for (final received in [false, true]) {
          expect(
            buildConversationDisplayItems(
              messages: [
                _assistant(
                  'Must not be a final reply',
                  extra: {...metadata, '_chat_response_complete': true},
                ),
              ],
              received: received,
            ),
            isEmpty,
            reason: 'neither persisted nor received metadata proves success',
          );
        }
      });
    }
  });
}

Map<String, dynamic> _user(String content, {int? id}) => {
  'role': 'user',
  'content': content,
  'id': ?id,
};

Map<String, dynamic> _assistant(
  String content, {
  int? id,
  Map<String, dynamic> extra = const {},
}) => {'role': 'assistant', 'content': content, 'id': ?id, ...extra};

List<String> _texts(Iterable<dynamic> items) => [
  for (final item in items)
    (item as Map<String, dynamic>)['_display_content'] as String,
];
