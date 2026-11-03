import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/delegated_task_controller.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'delegated_task_history_test.dart' show FakeHistory, rows, task;

// Captured from stock route functions + an actual disposable SessionDB, not a
// client-invented identity/projection contract. See the capture tool and docs.
final fixture =
    jsonDecode(
          File(
            'test/fixtures/delegated_task_dashboard.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

DashboardTaskHistory historyWith(
  Map<String, dynamic> Function(http.Request request) answer,
) => DashboardTaskHistory.fromConnection(
  SavedConnection(
    id: 'fixture',
    label: 'fixture',
    host: 'fixture.test',
    port: 8642,
    apiKey: 'fixture',
    dashboardProxied: true,
    gatewayProfile: 'fixture',
  ),
  httpClient: MockClient(
    (request) async => http.Response(
      jsonEncode(answer(request)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  ),
);

List<Map<String, dynamic>> delegationRows(
  String action,
  Map<String, dynamic> result,
) => [
  {
    'id': 1,
    'role': 'assistant',
    'tool_calls': [
      {
        'id': 'control',
        'function': {
          'name': 'delegate_task',
          'arguments': jsonEncode({'action': action, 'subagent_id': 'runtime'}),
        },
      },
    ],
  },
  {
    'id': 2,
    'role': 'tool',
    'tool_call_id': 'control',
    'name': 'delegate_task',
    'content': jsonEncode(result),
  },
];

void main() {
  test(
    'compacted archived tools and reasoning survive the real Dashboard contract',
    () async {
      final source = historyWith((request) {
        if (!request.url.path.endsWith('/messages')) {
          return fixture[request.url.path.endsWith('/compression-tip')
                  ? 'tip_detail'
                  : 'detail']
              as Map<String, dynamic>;
        }
        return fixture[request.url.queryParameters['include_compacted'] ==
                    'true'
                ? 'with_compacted'
                : 'without_compacted']
            as Map<String, dynamic>;
      });
      final transcript = parseTaskTranscript(
        (await source.fetch('stored-child', 0)).rows,
      );
      expect(
        transcript.any((row) => row.text == 'Archived tool result'),
        isTrue,
      );
      expect(
        transcript.expand((row) => row.reasoning),
        contains('Archived exposed reasoning'),
      );
      source.close();
    },
  );

  for (final action in ['steer', 'stop']) {
    testWidgets(
      'persisted $action ACK cannot finish a running child or stop polling',
      (tester) async {
        final history = FakeHistory()..data = rows(1, 2);
        final controller = DelegatedTaskController(task: task, history: history)
          ..start();
        await tester.pump();
        final ack = fixture['${action}_ack'] as Map<String, dynamic>;
        final recovered = recoverDelegatedTasks(delegationRows(action, ack));
        for (final item in recovered) {
          controller.updateTask(item);
        }
        controller.updateTask(
          GatewaySubagentActivity.fromGatewayEvent('subagent.text', {
            'subagent_id': 'runtime',
            'text': 'Late progress',
          })!,
        );
        expect(controller.task.isComplete, isFalse);
        expect(recovered, isEmpty);
        await tester.pump(const Duration(seconds: 2));
        expect(history.offsets, [0, 0]);
        controller.updateTask(
          GatewaySubagentActivity.fromGatewayEvent('subagent.complete', {
            'subagent_id': 'runtime',
            'status': 'completed',
          })!,
        );
        await tester.pump();
        expect(controller.task.isComplete, isTrue);
        final count = history.offsets.length;
        await tester.pump(const Duration(seconds: 4));
        expect(history.offsets, hasLength(count));
        controller.dispose();
      },
    );
  }

  test(
    'orphan control ACK and list schemas are not spawn results; unknown status stays active',
    () {
      for (final payload in [
        fixture['steer_ack'],
        fixture['stop_ack'],
        {'action': 'list', 'count': 0, 'subagents': []},
      ]) {
        expect(
          recoverDelegatedTasks([
            {
              'id': 1,
              'role': 'tool',
              'name': 'delegate_task',
              'tool_call_id': 'orphan',
              'content': jsonEncode(payload),
            },
          ]),
          isEmpty,
        );
      }
      final recovered = recoverDelegatedTasks(
        delegationRows('spawn', {
          'subagent_id': 'runtime',
          'status': 'future_unknown_status',
          'child_session_id': 'stored-child',
        }),
      );
      expect(recovered.single.isComplete, isFalse);
    },
  );

  test(
    'missing exact child plus unambiguous longer prefix never shows foreign history',
    () async {
      var messageReads = 0;
      final source = historyWith((request) {
        if (!request.url.path.endsWith('/messages')) {
          return fixture['prefix_detail'] as Map<String, dynamic>;
        }
        messageReads++;
        return fixture['prefix_messages'] as Map<String, dynamic>;
      });
      await expectLater(
        source.fetch('missing-child', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      expect(messageReads, 0);
      source.close();
    },
  );

  test(
    'exact original detail and proven compression continuation are accepted',
    () async {
      final requests = <String>[];
      final source = historyWith((request) {
        requests.add(request.url.path);
        if (request.url.path.endsWith('/messages')) {
          return fixture['tip_messages'] as Map<String, dynamic>;
        }
        return fixture[request.url.path.endsWith('/compression-tip')
                ? 'tip_detail'
                : 'detail']
            as Map<String, dynamic>;
      });
      final result = (await source.fetch(
        'stored-child',
        0,
        latestChildId: 'compression-tip',
      )).rows;
      expect(result.any((row) => row['content'] == 'After rotation'), isTrue);
      expect(requests.first, endsWith('/stored-child'));
      expect(requests, contains(endsWith('/compression-tip')));
      source.close();
    },
  );

  test(
    'arbitrary valid response id without compression ancestry fails closed',
    () async {
      final source = historyWith((request) {
        if (request.url.path.endsWith('/messages')) {
          return {
            ...fixture['tip_messages'] as Map<String, dynamic>,
            'session_id': 'unrelated',
          };
        }
        if (request.url.path.endsWith('/stored-child')) {
          return fixture['detail'] as Map<String, dynamic>;
        }
        return {
          ...fixture['tip_detail'] as Map<String, dynamic>,
          'id': 'unrelated',
          'parent_session_id': null,
        };
      });
      await expectLater(
        source.fetch('stored-child', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      source.close();
    },
  );

  test(
    'spawn and real background dispatch recover without invented durable refs',
    () {
      final dispatched = recoverDelegatedTasks(
        delegationRows('spawn', {
          'status': 'dispatched',
          'mode': 'background',
          'count': 2,
          'delegation_id': 'unit',
          'goals': ['First', 'Second'],
          'subagent_ids': ['runtime-a', 'runtime-b'],
          'live_transcripts': ['/not/a/session/a', '/not/a/session/b'],
        }),
      );
      expect(dispatched.map((task) => task.id), ['runtime-a', 'runtime-b']);
      expect(dispatched.map((task) => task.goal), ['First', 'Second']);
      expect(
        dispatched.every(
          (task) => !task.isComplete && task.childSessionId == null,
        ),
        isTrue,
      );
      for (final status in [
        'completed',
        'failed',
        'error',
        'interrupted',
        'cancelled',
      ]) {
        final recovered = recoverDelegatedTasks(
          delegationRows('spawn', {
            'results': [
              {'status': status, 'summary': 'Actual result', 'task_index': 0},
            ],
          }),
        ).single;
        expect(recovered.isComplete, isTrue);
        expect(recovered.status, status);
        expect(recovered.childSessionId, isNull);
      }
      final noStatus = recoverDelegatedTasks(
        delegationRows('spawn', {'summary': 'Not a terminal signal'}),
      ).single;
      expect(noStatus.isComplete, isFalse);
    },
  );

  for (final invalid in [
    'branch',
    'delegate',
    'reset',
    'source-change',
    'not-compression',
    'cycle',
    'profile',
    'malformed-config',
    'missing-fields',
  ]) {
    test('compression identity proof rejects $invalid metadata', () async {
      final source = historyWith((request) {
        if (request.url.path.endsWith('/messages')) {
          return fixture['tip_messages'] as Map<String, dynamic>;
        }
        final isOriginal = request.url.path.endsWith('/stored-child');
        final detail = {
          ...fixture[isOriginal ? 'detail' : 'tip_detail']
              as Map<String, dynamic>,
        };
        if (isOriginal && invalid == 'not-compression') {
          detail['end_reason'] = 'branched';
        }
        if (!isOriginal) {
          if (invalid == 'branch') {
            detail['model_config'] = '{"_branched_from":"stored-child"}';
          }
          if (invalid == 'delegate') {
            detail['model_config'] = {'_delegate_from': 'stored-child'};
          }
          if (invalid == 'reset') {
            detail['model_config'] = {'_reset_from': 'stored-child'};
          }
          if (invalid == 'source-change') detail['source'] = 'tool';
          if (invalid == 'cycle') {
            detail['parent_session_id'] = 'compression-tip';
            detail['end_reason'] = 'compression';
          }
          if (invalid == 'profile') detail['profile'] = 'another-profile';
          if (invalid == 'malformed-config') detail['model_config'] = '{broken';
          if (invalid == 'missing-fields') detail.remove('model_config');
        }
        return detail;
      });
      await expectLater(
        source.fetch('stored-child', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      source.close();
    });
  }

  test(
    'projected JSON-looking prose and explicitly empty or null projections are authoritative',
    () {
      final projected = parseTaskTranscript([
        {
          'id': 1,
          'role': 'assistant',
          'content': '',
          'display_commentary': ['true', '["public"]'],
          'display_reasoning': '123',
          'reasoning': 'raw',
        },
        {
          'id': 2,
          'role': 'assistant',
          'content': 'raw',
          'display_content': null,
          'display_commentary': [],
          'display_reasoning': null,
          'reasoning': 'raw',
        },
      ]);
      expect(projected.first.text, 'true\n\n["public"]');
      expect(projected.first.reasoning, ['123']);
      expect(projected.last.text, isEmpty);
      expect(projected.last.reasoning, isEmpty);
    },
  );

  test(
    'real display commentary is prose and canonical reasoning suppresses raw duplicates',
    () {
      final transcript = parseTaskTranscript(
        (fixture['with_compacted']['messages'] as List)
            .cast<Map<String, dynamic>>(),
      );
      final projected = transcript.singleWhere(
        (row) => row.text == 'Public progress',
      );
      expect(projected.reasoning, ['Exposed reasoning']);
      final disabled = parseTaskTranscript(
        (fixture['commentary_disabled']['messages'] as List)
            .cast<Map<String, dynamic>>(),
      );
      expect(
        disabled.any((row) => row.text.contains('Public progress')),
        isFalse,
      );
      final empty = parseTaskTranscript([
        {
          'id': 1,
          'role': 'assistant',
          'content': 'RAW ANSWER',
          'display_content': '',
          'reasoning': 'RAW REASONING',
          'display_reasoning': '',
          'display_commentary': [],
          'codex_reasoning_items': [
            {
              'summary': [
                {'text': 'RAW SIDECAR'},
              ],
            },
          ],
        },
      ]).single;
      expect(empty.text, isEmpty);
      expect(empty.reasoning, isEmpty);
    },
  );
}
