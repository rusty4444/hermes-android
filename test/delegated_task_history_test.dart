import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/controllers/delegated_task_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const task = GatewaySubagentActivity(
  id: 'runtime',
  goal: 'Inspect',
  phase: GatewaySubagentPhase.running,
  childSessionId: 'stored-child',
);
List<Map<String, dynamic>> rows(int start, int end) => [
  for (var i = start; i <= end; i++)
    {'id': i, 'role': 'assistant', 'content': 'Same'},
];
void main() {
  test(
    'literal JSON prose is preserved and encrypted reasoning is never rendered',
    () {
      final row = parseTaskTranscript([
        {
          'id': 1,
          'role': 'assistant',
          'content': '["first","second"]',
          'reasoning_details': [
            {'type': 'reasoning.encrypted', 'text': 'CIPHERTEXT'},
            {'type': 'redacted_thinking', 'data': 'HIDDEN'},
          ],
        },
      ]).single;
      expect(row.text, '["first","second"]');
      expect(row.reasoning, isEmpty);
    },
  );
  test(
    'rejected Dashboard login is explicit and does not repeatedly poll credentials',
    () async {
      var count = 0;
      final source = DashboardTaskHistory.fromConnection(
        SavedConnection(
          id: 'c',
          label: 'c',
          host: 'gateway.test',
          port: 8642,
          apiKey: 'fixture',
          dashboardUsername: 'user',
          dashboardPassword: 'wrong',
        ),
        httpClient: MockClient((request) async {
          count++;
          expectSync(request.url.path, '/auth/password-login');
          return http.Response('{}', 401);
        }),
      );
      await expectLater(
        source.fetch('child', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      expect(count, 1);
      source.close();
    },
  );
  test(
    'growth between older request and head refresh cannot skip an old tail',
    () async {
      final history = FakeHistory()..data = rows(51, 100);
      final controller = DelegatedTaskController(task: task, history: history);
      await controller.refresh();
      // Ten rows were appended before OFFSET 50 was read: it now overlaps the
      // original head by ten. The following head refresh must not count them twice.
      history.data = rows(11, 60);
      await controller.loadOlder();
      history.data = rows(61, 110);
      await controller.refresh();
      expect(controller.olderOffset, 100);
      history.data = rows(1, 10);
      await controller.loadOlder();
      expect(history.offsets, [0, 50, 0, 100]);
      expect(
        controller.rows.map((row) => row['id']),
        List.generate(110, (index) => index + 1),
      );
      expect(controller.hasOlder, isFalse);
      controller.dispose();
    },
  );
  test(
    'proxied default profile is clean; rejected auth retries exactly once',
    () async {
      final requests = <http.Request>[];
      final source = DashboardTaskHistory.fromConnection(
        SavedConnection(
          id: 'c',
          label: 'c',
          host: 'gateway.test',
          port: 8642,
          dashboardPortOverride: 9443,
          apiKey: 'not-dashboard',
          dashboardPrefix: '/profile/default',
          dashboardProxied: true,
          dashboardUsername: 'ignored',
          dashboardPassword: 'ignored',
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          expectSync(request.url.port, 9443);
          expectSync(request.url.path, '/profile/default/api/sessions/child');
          expectSync(
            request.url.queryParameters.containsKey('profile'),
            isFalse,
          );
          expectSync(request.headers.containsKey('cookie'), isFalse);
          expectSync(request.headers.containsKey('authorization'), isFalse);
          expectSync(
            request.headers.containsKey('x-hermes-session-token'),
            isFalse,
          );
          return http.Response('{}', 401);
        }),
      );
      await expectLater(
        source.fetch('child', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      expect(requests, hasLength(2));
      await expectLater(
        source.fetch(' bad ', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      expect(requests, hasLength(2));
      source.close();
    },
  );

  test('closing during authentication prevents a late follow-up GET', () async {
    final started = Completer<void>();
    final login = Completer<http.Response>();
    final requests = <http.Request>[];
    final source = DashboardTaskHistory.fromConnection(
      SavedConnection(
        id: 'c',
        label: 'c',
        host: 'gateway.test',
        port: 8642,
        dashboardUsername: 'user',
        dashboardPassword: 'pass',
        apiKey: 'not-dashboard',
      ),
      httpClient: MockClient((request) {
        requests.add(request);
        started.complete();
        return login.future;
      }),
    );
    final pending = source.fetch('child', 0);
    await started.future;
    source.close();
    login.complete(
      http.Response(
        '{}',
        200,
        headers: {'set-cookie': 'hermes_session_at=fixture'},
      ),
    );
    await expectLater(pending, throwsStateError);
    expect(requests, hasLength(1));
  });

  test(
    'empty/short latest pages never erase retained rows or merge identical content',
    () async {
      final history = FakeHistory()..data = rows(1, 50);
      final controller = DelegatedTaskController(task: task, history: history);
      await controller.refresh();
      history.data = rows(49, 51);
      await controller.refresh();
      expect(controller.rows.map((row) => row['id']).toSet(), hasLength(51));
      history.data = [];
      await controller.refresh();
      expect(controller.rows, hasLength(51));
      expect(controller.hasOlder, isTrue);
      history.failure = Exception('older failed');
      final offset = controller.olderOffset;
      await controller.loadOlder();
      expect(controller.olderOffset, offset);
      expect(controller.rows, hasLength(51));
      controller.dispose();
    },
  );

  test('notification re-entrancy cannot start a read after pausing', () async {
    final history = FakeHistory();
    final controller = DelegatedTaskController(task: task, history: history);
    void pauseOnLoading() {
      if (controller.loading) controller.setForeground(false);
    }

    controller.addListener(pauseOnLoading);
    await controller.refresh();
    expect(history.offsets, isEmpty);
    controller.dispose();
    expect(history.closed, isTrue);
  });

  testWidgets(
    'post-completion transient failure retries; delayed flush stays manually refreshable',
    (tester) async {
      final history = FakeHistory()..failure = Exception('offline');
      final controller = DelegatedTaskController(
        task: task.merge(
          const GatewaySubagentActivity(
            id: 'runtime',
            goal: '',
            phase: GatewaySubagentPhase.completed,
            status: 'completed',
          ),
        ),
        history: history,
      )..start();
      await tester.pump();
      expect(controller.error, isNotNull);
      history.failure = null;
      await tester.pump(const Duration(seconds: 2));
      expect(controller.hasRead, isTrue);
      expect(controller.rows, isEmpty);
      final count = history.offsets.length;
      await tester.pump(const Duration(seconds: 20));
      expect(history.offsets, hasLength(count));
      history.data = rows(1, 2);
      await controller.refresh();
      expect(controller.rows, hasLength(2));
      controller.dispose();
    },
  );

  test(
    'dashboard GET uses exact gateway origin, encoded id/profile, auth and bounded page',
    () async {
      const id = 'stored:/子?x#%';
      final requests = <http.Request>[];
      final client = DashboardTaskHistory.fromConnection(
        SavedConnection(
          id: 'c',
          label: 'c',
          host: 'wrong',
          port: 8642,
          apiKey: 'never-send',
          desktopGatewayUrl: 'https://gateway.test:9443/prefix',
          dashboardUsername: 'user',
          dashboardPassword: 'pass',
          gatewayProfile: 'profile &子',
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/auth/password-login')) {
            return http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'hermes_session_at=fixture; Path=/'},
            );
          }
          expectSync(request.method, 'GET');
          expectSync(request.headers['cookie'], 'hermes_session_at=fixture');
          if (!request.url.path.endsWith('/messages')) {
            expectSync(
              request.url.toString(),
              contains('/prefix/api/sessions/${Uri.encodeComponent(id)}?'),
            );
            expectSync(request.url.queryParameters, {'profile': 'profile &子'});
            return http.Response(
              jsonEncode({'id': id, 'profile': 'profile &子'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expectSync(
            request.url.toString(),
            contains(
              '/prefix/api/sessions/${Uri.encodeComponent(id)}/messages?',
            ),
          );
          expectSync(request.url.queryParameters, {
            'profile': 'profile &子',
            'limit': '50',
            'offset': '0',
            'order': 'latest',
            'inline_images': 'false',
            'include_compacted': 'true',
          });
          expectSync(request.headers['cookie'], 'hermes_session_at=fixture');
          expectSync(request.headers.containsKey('authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'session_id': id,
              'profile': 'profile &子',
              'messages': rows(1, 2),
              'pagination': {
                'limit': 50,
                'offset': 0,
                'order': 'latest',
                'returned': 2,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect((await client.fetch(id, 0)).rows, hasLength(2));
      expect(requests.last.url.host, 'gateway.test');
      expect(requests.last.url.scheme, 'https');
      client.close();
    },
  );

  test(
    'missing dashboard auth is explicit; API-server data shape is not empty history',
    () async {
      final noAuth = DashboardTaskHistory.fromConnection(
        SavedConnection(
          id: 'c',
          label: 'c',
          host: 'example.test',
          port: 8642,
          apiKey: 'not-dashboard',
        ),
        httpClient: MockClient(
          (_) async => throw StateError('must not request'),
        ),
      );
      await expectLater(
        noAuth.fetch('child', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      noAuth.close();
      final wrong = DashboardTaskHistory.fromConnection(
        SavedConnection(
          id: 'c',
          label: 'c',
          host: 'example.test',
          port: 8642,
          apiKey: 'not-dashboard',
          dashboardProxied: true,
        ),
        httpClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
      );
      await expectLater(
        wrong.fetch('child', 0),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      wrong.close();
    },
  );

  test(
    'raw transcript parses JSON tools, actual arguments/results and exposed reasoning only',
    () {
      final transcript = parseTaskTranscript([
        {
          'id': 3,
          'role': 'tool',
          'tool_call_id': 'call-a',
          'content': '{"ok":true}',
        },
        {
          'id': 2,
          'role': 'assistant',
          'content': '**Plan**',
          'tool_calls': jsonEncode([
            {
              'id': 'call-a',
              'function': {
                'name': 'terminal',
                'arguments': '{"command":"pwd"}',
              },
            },
          ]),
          'reasoning': 'First',
          'reasoning_content': 'Second',
          'reasoning_details': '[{"type":"thinking","thinking":"Third"}]',
          'codex_reasoning_items': [
            {
              'summary': [
                {'text': 'Fourth'},
              ],
              'encrypted_content': 'SECRET',
            },
          ],
        },
        {'id': 4, 'role': 'agent', 'content': 'Done'},
        {
          'id': 5,
          'role': 'assistant',
          'content': '',
          'codex_reasoning_items': [
            {'encrypted_content': 'HIDDEN'},
          ],
        },
      ]);
      expect(transcript.map((r) => r.id), [2, 3, 4, 5]);
      expect(transcript.first.text, '**Plan**');
      expect(transcript.first.reasoning, [
        'First',
        'Second',
        'Third',
        'Fourth',
      ]);
      expect(transcript.first.calls.single.id, 'call-a');
      expect(transcript.first.calls.single.arguments, contains('pwd'));
      expect(transcript[1].text, '{"ok":true}');
      expect(transcript[1].toolName, 'terminal');
      expect(transcript[2].role, 'assistant');
      expect(transcript.last.reasoning, isEmpty);
    },
  );

  test(
    'structured delegation recovery never collects unrelated session_id recursively',
    () {
      final recovered = recoverDelegatedTasks([
        {
          'id': 1,
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'delegate-1',
              'function': {
                'name': 'delegate_task',
                'arguments': '{"goal":"Inspect"}',
              },
            },
          ],
        },
        {
          'id': 2,
          'role': 'tool',
          'tool_call_id': 'delegate-1',
          'content': jsonEncode({
            'results': [
              {
                'goal': 'Inspect',
                'child_session_id': 'real-child',
                'status': 'completed',
              },
              {
                'goal': 'Inspect',
                'status': 'failed',
                'nested': {'session_id': 'not-a-child'},
              },
            ],
          }),
        },
      ]);
      expect(recovered, hasLength(2));
      expect(recovered.first.childSessionId, 'real-child');
      expect(recovered.last.childSessionId, isNull);
      expect(recovered.first.id, isNot(recovered.last.id));
    },
  );

  test(
    'single flight, retain older rows, dedupe durable ids, repair latest-window gap',
    () async {
      final source = FakeHistory()..data = rows(51, 100);
      final controller = DelegatedTaskController(task: task, history: source);
      await controller.refresh();
      source.data = rows(1, 50);
      await controller.loadOlder();
      source.data = rows(81, 130);
      await controller.refresh();
      expect(controller.rows, hasLength(130));
      expect(controller.olderOffset, 130);
      source.data = rows(181, 230);
      await controller.refresh();
      expect(controller.olderOffset, 50);
      source.data = rows(131, 180);
      await controller.loadOlder();
      expect(controller.rows, hasLength(230));
      source.gate = Completer<List<Map<String, dynamic>>>();
      final pending = controller.refresh();
      final count = source.offsets.length;
      unawaited(controller.refresh());
      unawaited(controller.loadOlder());
      expect(source.offsets, hasLength(count));
      controller.dispose();
      source.gate!.complete(rows(300, 301));
      await pending;
      expect(controller.rows, hasLength(230));
      expect(source.closed, isTrue);
    },
  );

  testWidgets(
    'active polling pauses in background; final refresh survives old in-flight response',
    (tester) async {
      final source = FakeHistory()..data = rows(1, 2);
      final controller = DelegatedTaskController(task: task, history: source)
        ..start();
      await tester.pump();
      expect(source.offsets, [0]);
      await tester.pump(const Duration(seconds: 2));
      expect(source.offsets, [0, 0]);
      controller.setForeground(false);
      await tester.pump(const Duration(seconds: 10));
      expect(source.offsets, [0, 0]);
      source.gate = Completer<List<Map<String, dynamic>>>();
      controller.setForeground(true);
      await tester.pump();
      controller.updateTask(
        task.merge(
          const GatewaySubagentActivity(
            id: 'runtime',
            goal: '',
            phase: GatewaySubagentPhase.completed,
            status: 'failed',
          ),
        ),
      );
      final gate = source.gate!;
      source.gate = null;
      source.data = rows(1, 3);
      gate.complete(rows(1, 2));
      await tester.pump();
      expect(controller.rows, hasLength(3));
      expect(controller.task.status, 'failed');
      final count = source.offsets.length;
      await tester.pump(const Duration(seconds: 20));
      expect(source.offsets, hasLength(count));
      controller.dispose();
    },
  );

  test('transient error retains rows; no-id never fetches', () async {
    final source = FakeHistory()..data = rows(1, 2);
    final controller = DelegatedTaskController(task: task, history: source);
    await controller.refresh();
    source.failure = Exception('offline');
    await controller.refresh();
    expect(controller.rows, hasLength(2));
    expect(controller.error, TaskHistoryProblem.refreshFailed);
    source.failure = null;
    await controller.refresh();
    expect(controller.error, isNull);
    controller.dispose();
    final absent = FakeHistory();
    final noId = DelegatedTaskController(
      task: const GatewaySubagentActivity(
        id: 'r',
        goal: '',
        phase: GatewaySubagentPhase.completed,
      ),
      history: absent,
    );
    await noId.refresh();
    expect(absent.offsets, isEmpty);
    expect(noId.unavailable, TaskHistoryProblem.missingReference);
    noId.dispose();
  });
}

class FakeHistory implements TaskHistorySource {
  List<Map<String, dynamic>> data = [];
  final List<int> offsets = [];
  Completer<List<Map<String, dynamic>>>? gate;
  Object? failure;
  bool closed = false;
  @override
  Future<TaskHistoryPage> fetch(
    String childId,
    int offset, {
    String? latestChildId,
    String? currentSessionId,
  }) async {
    offsets.add(offset);
    if (failure != null) throw failure!;
    return TaskHistoryPage(
      rows: gate == null ? data : await gate!.future,
      sessionId: childId,
      offset: offset,
      lineage: [childId],
    );
  }

  @override
  void close() {
    closed = true;
  }
}
