import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/delegated_task_controller.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final fixture =
    jsonDecode(
          File(
            'test/fixtures/delegated_task_dashboard.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> scenario(String source) =>
    fixture['rotations'][source] as Map<String, dynamic>;

DashboardTaskHistory historyFor(
  String source,
  List<Uri> requests, {
  void Function(Map<String, dynamic> row)? changeDetail,
  Map<String, dynamic> Function(http.Request request)? messages,
}) => DashboardTaskHistory.fromConnection(
  SavedConnection(
    id: 'fixture',
    label: 'fixture',
    host: 'fixture.test',
    port: 8642,
    apiKey: 'unused-fixture',
    dashboardProxied: true,
    gatewayProfile: 'fixture',
  ),
  httpClient: MockClient((request) async {
    requests.add(request.url);
    expectSync(request.method, 'GET');
    expectSync(request.url.queryParameters['profile'], 'fixture');
    final data = scenario(source);
    final Map<String, dynamic> response;
    if (request.url.path.endsWith('/messages')) {
      response =
          messages?.call(request) ??
          data[request.url.path.contains('/tip-')
                  ? 'tip_page'
                  : 'original_page']
              as Map<String, dynamic>;
    } else {
      expectSync(
        request.url.path,
        anyOf('/api/sessions/child-$source', '/api/sessions/tip-$source'),
      );
      response = {
        ...data[request.url.path.endsWith('/tip-$source')
                ? 'tip_detail'
                : 'detail']
            as Map<String, dynamic>,
      };
      changeDetail?.call(response);
    }
    return http.Response(
      jsonEncode(response),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

GatewaySubagentActivity activity(
  String source,
  String ref, {
  bool complete = false,
}) => GatewaySubagentActivity.fromGatewayEvent(
  complete ? 'subagent.complete' : 'subagent.text',
  {
    'subagent_id': 'runtime-$source',
    'child_session_id': ref,
    'status': complete ? 'completed' : 'running',
    'text': 'Public progress',
  },
)!;

void main() {
  test(
    'actual source-scoped listing and latest-descendant do not discover delegated rotation',
    () {
      // Captured by the actual GET route with maintenance disabled and fixture DB
      // reopened read-only; source selection still excludes child-session rows.
      final listing = fixture['source_scoped_listing'];
      expect(listing['limit'], 100);
      expect(listing['total'], 0);
      expect(listing['sessions'], isEmpty);
      for (final source in ['subagent', 'tool']) {
        expect(
          scenario(source)['latest_descendant']['session_id'],
          'child-$source',
        );
        expect(
          scenario(source)['original_page']['session_id'],
          'child-$source',
        );
      }
    },
  );

  test(
    'cold-open tool tip without root reference discloses actual missing ancestors',
    () async {
      final requests = <Uri>[];
      final history = historyFor('tool', requests);
      final page = await history.fetch('tip-tool', 0);
      expect(page.sessionId, 'tip-tool');
      expect(page.lineage, ['tip-tool']);
      expect(
        page.rows.map((row) => row['content']),
        contains('AFTER rotation: actual child completion'),
      );
      expect(
        page.rows.map((row) => row['content']),
        isNot(contains('BEFORE rotation')),
      );
      expect(page.limitation, TaskHistoryProblem.partialAncestors);
      expect(
        requests
            .where((uri) => uri.path.endsWith('/messages'))
            .map((uri) => uri.path),
        ['/api/sessions/tip-tool/messages'],
      );
      expect(
        requests.map((uri) => uri.path),
        contains('/api/sessions/child-tool'),
      );
      expect(requests.length, lessThanOrEqualTo(4));
      history.close();
    },
  );

  testWidgets(
    'cold-open completed tool tip visibly discloses ancestors omitted by the real messages route',
    (tester) async {
      final requests = <Uri>[];
      final controller = DelegatedTaskController(
        task: activity('tool', 'tip-tool', complete: true),
        history: historyFor('tool', requests),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DelegatedTaskTimeline(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.canonicalSessionId, 'tip-tool');
      expect(controller.unavailable, isNull);
      expect(controller.hasOlder, isFalse);
      expect(
        controller.rows.map((row) => row['content']),
        contains('AFTER rotation: actual child completion'),
      );
      expect(
        controller.rows.map((row) => row['content']),
        isNot(contains('BEFORE rotation')),
      );
      expect(controller.limitation, TaskHistoryProblem.partialAncestors);
      expect(
        find
            .textContaining('Earlier task segments may be missing')
            .hitTestable(),
        findsOneWidget,
      );
      expect(find.textContaining('verifiable newer reference'), findsNothing);
      expect(find.textContaining('Automatic refresh is paused'), findsNothing);
      final count = requests.length;
      await tester.pump(const Duration(seconds: 10));
      expect(requests, hasLength(count));
      await tester.tap(find.byTooltip('Refresh task history'));
      await tester.pumpAndSettle();
      expect(requests.length, greaterThan(count));
      expect(controller.limitation, TaskHistoryProblem.partialAncestors);
      expect(
        requests.every(
          (uri) =>
              uri.path.startsWith('/api/sessions/') &&
              !uri.path.endsWith('/latest-descendant'),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'cold-open running tool tip ancestor warning does not pause polling',
    (tester) async {
      final requests = <Uri>[];
      final controller = DelegatedTaskController(
        task: activity('tool', 'tip-tool'),
        history: historyFor('tool', requests),
      )..start();
      await tester.pump();
      expect(controller.limitation, TaskHistoryProblem.partialAncestors);
      expect(controller.canonicalSessionId, 'tip-tool');
      final count = requests.length;
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(requests.length, greaterThan(count));
      controller.updateTask(activity('tool', 'tip-tool', complete: true));
      await tester.pump();
      final completedCount = requests.length;
      await tester.pump(const Duration(seconds: 10));
      expect(requests, hasLength(completedCount));
      expect(controller.limitation, TaskHistoryProblem.partialAncestors);
      controller.dispose();
    },
  );

  for (final marker in ['_delegate_from', '_branched_from', '_reset_from']) {
    for (final direct in [false, true]) {
      test(
        'cold-open tool $marker ${direct ? 'root does not inherit parent-chat compression warning' : 'inherited grandparent proves missing compression ancestors'}',
        () async {
          final requests = <Uri>[];
          final history = historyFor(
            'tool',
            requests,
            changeDetail: (row) {
              row['model_config'] = {
                marker: direct && row['id'] == 'tip-tool'
                    ? 'child-tool'
                    : 'parent-tool',
              };
            },
          );
          final page = await history.fetch('tip-tool', 0);
          expect(
            page.limitation,
            direct ? null : TaskHistoryProblem.partialAncestors,
          );
          expect(requests.length, lessThanOrEqualTo(4));
          if (direct) {
            // A direct fork marker is conclusive even when the referenced
            // parent chat has compressed: do not inspect its history at all.
            expect(
              requests.any((uri) => uri.path.endsWith('/child-tool')),
              isFalse,
            );
          }
          expect(
            requests
                .where((uri) => uri.path.endsWith('/messages'))
                .map((uri) => uri.path),
            ['/api/sessions/tip-tool/messages'],
          );
          history.close();
        },
      );
    }
  }

  for (final invalid in [
    'prefix',
    'profile',
    'source-change',
    'changed-marker',
  ]) {
    test('cold-open ancestor proof checks $invalid metadata', () async {
      final requests = <Uri>[];
      final history = historyFor(
        'tool',
        requests,
        changeDetail: (row) {
          if (row['id'] != 'child-tool') return;
          switch (invalid) {
            case 'prefix':
              row['id'] = 'child-tool-longer';
            case 'profile':
              row['profile'] = 'other';
            case 'source-change':
              row['source'] = 'subagent';
            case 'changed-marker':
              row['model_config'] = {'_delegate_from': 'other-parent'};
          }
        },
      );
      final read = history.fetch('tip-tool', 0);
      if (invalid == 'prefix' || invalid == 'profile') {
        await expectLater(read, throwsA(isA<TaskHistoryUnavailable>()));
      } else {
        expect((await read).limitation, isNull);
      }
      expect(requests.length, lessThanOrEqualTo(4));
      history.close();
    });
  }

  testWidgets(
    'tool ancestor warning retains known rows and polls the live verified tip',
    (tester) async {
      final requests = <Uri>[];
      final controller = DelegatedTaskController(
        task: activity('tool', 'child-tool'),
        history: historyFor('tool', requests),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DelegatedTaskTimeline(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.limitation, TaskHistoryProblem.partialCompression);
      final pausedCount = requests.length;
      await tester.pump(const Duration(seconds: 10));
      expect(requests, hasLength(pausedCount));

      controller.updateTask(activity('tool', 'tip-tool'));
      await tester.pumpAndSettle();
      expect(controller.limitation, TaskHistoryProblem.partialAncestors);
      expect(controller.task.isComplete, isFalse);
      expect(
        controller.rows.map((row) => row['content']),
        containsAll([
          'BEFORE rotation',
          'AFTER rotation: actual child completion',
        ]),
      );
      final activeCount = requests.length;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final polledCount = requests.length;
      expect(polledCount, greaterThan(activeCount));
      expect(controller.limitation, TaskHistoryProblem.partialAncestors);

      controller.updateTask(activity('tool', 'tip-tool', complete: true));
      await tester.pumpAndSettle();
      final completedCount = requests.length;
      expect(completedCount, greaterThan(polledCount));
      await tester.pump(const Duration(seconds: 10));
      expect(requests, hasLength(completedCount));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final source in ['subagent', 'tool']) {
    test(
      'real $source rotation preserves inherited marker and includes final completion via latest reference',
      () async {
        final requests = <Uri>[];
        final history = historyFor(source, requests);
        final root = activity(source, 'child-$source');
        final merged = root.merge(
          activity(source, 'tip-$source', complete: true),
        );
        expect(merged.childSessionId, 'child-$source');
        expect(merged.latestChildSessionId, 'tip-$source');
        final page = await history.fetch(
          merged.childSessionId!,
          0,
          latestChildId: merged.latestChildSessionId,
        );
        expect(page.sessionId, 'tip-$source');
        expect(page.lineage, ['tip-$source', 'child-$source']);
        expect(page.partial, source == 'tool');
        expect(
          page.limitation,
          source == 'tool' ? TaskHistoryProblem.partialAncestors : null,
        );
        final transcript = parseTaskTranscript(page.rows);
        expect(
          transcript.map((row) => row.text),
          contains('AFTER rotation: actual child completion'),
        );
        expect(
          transcript.any((row) => row.text.contains('PARENT PRIVATE')),
          isFalse,
        );
        expect(
          requests.where((uri) => uri.path.endsWith('/messages')).single.path,
          '/api/sessions/tip-$source/messages',
        );
        expect(requests.length, lessThanOrEqualTo(5));
        history.close();
      },
    );

    testWidgets(
      'reopened compressed $source root shows known rows and explicit partial-history notice, not silent success',
      (tester) async {
        final requests = <Uri>[];
        final history = historyFor(source, requests);
        final controller = DelegatedTaskController(
          task: activity(source, 'child-$source', complete: true),
          history: history,
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: DelegatedTaskTimeline(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.hasRead, isTrue);
        expect(controller.unavailable, isNull);
        expect(controller.limitation, TaskHistoryProblem.partialCompression);
        expect(
          controller.rows.map((row) => row['content']),
          contains('BEFORE rotation'),
        );
        expect(
          controller.rows.map((row) => row['content']),
          isNot(contains('AFTER rotation: actual child completion')),
        );
        expect(find.textContaining('Partial history:'), findsOneWidget);
        final count = requests.length;
        await tester.pump(const Duration(seconds: 10));
        expect(requests, hasLength(count));
        await tester.tap(find.byTooltip('Refresh task history'));
        await tester.pumpAndSettle();
        expect(requests.length, greaterThan(count));
        // A real parent relay advertising the rotated ID wakes a paused viewer.
        controller.updateTask(activity(source, 'tip-$source', complete: true));
        await tester.pumpAndSettle();
        expect(controller.canonicalSessionId, 'tip-$source');
        expect(
          controller.limitation,
          source == 'tool' ? TaskHistoryProblem.partialAncestors : null,
        );
        expect(
          controller.rows.map((row) => row['content']),
          contains('BEFORE rotation'),
        );
        expect(
          controller.rows.map((row) => row['content']),
          contains('AFTER rotation: actual child completion'),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );

    test(
      'late ancestor reference never regresses verified $source canonical segment',
      () async {
        final history = historyFor(source, []);
        final page = await history.fetch(
          'child-$source',
          0,
          currentSessionId: 'tip-$source',
          latestChildId: 'child-$source',
        );
        expect(page.sessionId, 'tip-$source');
        expect(page.partial, source == 'tool');
        history.close();
      },
    );
  }

  for (final key in ['_delegate_from', '_branched_from', '_reset_from']) {
    for (final direct in [false, true]) {
      test(
        '$key ${direct ? 'direct-parent fork is rejected' : 'inherited grandparent survives genuine compression'}',
        () async {
          final history = historyFor(
            'subagent',
            [],
            changeDetail: (row) {
              final tip = row['id'] == 'tip-subagent';
              row['model_config'] = {
                key: direct && tip ? 'child-subagent' : 'parent-subagent',
              };
            },
          );
          final read = history.fetch(
            'child-subagent',
            0,
            latestChildId: 'tip-subagent',
          );
          if (direct) {
            await expectLater(
              read,
              throwsA(
                isA<TaskHistoryUnavailable>().having(
                  (e) => e.reason,
                  'reason',
                  TaskHistoryProblem.identityUnproven,
                ),
              ),
            );
          } else {
            expect((await read).sessionId, 'tip-subagent');
          }
          history.close();
        },
      );
    }
  }

  for (final problem in [
    'changed-grandparent',
    'pre-parent',
    'prefix',
    'wrong-profile',
    'source-change',
  ]) {
    test(
      'candidate proof fails closed before transcript read: $problem',
      () async {
        final requests = <Uri>[];
        final history = historyFor(
          'subagent',
          requests,
          changeDetail: (row) {
            if (row['id'] != 'tip-subagent') return;
            switch (problem) {
              case 'changed-grandparent':
                row['model_config'] = {'_delegate_from': 'other-parent'};
              case 'pre-parent':
                row['started_at'] = 0;
              case 'prefix':
                row['id'] = 'tip-subagent-longer';
              case 'wrong-profile':
                row['profile'] = 'other';
              case 'source-change':
                row['source'] = 'tool';
            }
          },
        );
        await expectLater(
          history.fetch('child-subagent', 0, latestChildId: 'tip-subagent'),
          throwsA(isA<TaskHistoryUnavailable>()),
        );
        expect(requests.any((uri) => uri.path.endsWith('/messages')), isFalse);
        history.close();
      },
    );
  }

  test(
    'multiple candidate continuations on different branches are ambiguous, not mixed',
    () async {
      // Two individually valid compression descendants are not sufficient to
      // prove they are the same branch. Never merge them by recency.
      final data = scenario('subagent');
      var messageReads = 0;
      final siblingHistory = DashboardTaskHistory.fromConnection(
        SavedConnection(
          id: 'c',
          label: 'c',
          host: 'fixture.test',
          port: 8642,
          apiKey: 'unused',
          dashboardProxied: true,
          gatewayProfile: 'fixture',
        ),
        httpClient: MockClient((request) async {
          expectSync(request.method, 'GET');
          if (request.url.path.endsWith('/messages')) messageReads++;
          final id = request.url.pathSegments.last;
          final row = id == 'child-subagent'
              ? data['detail']
              : {...data['tip_detail'] as Map<String, dynamic>, 'id': id};
          return http.Response(jsonEncode(row), 200);
        }),
      );
      await expectLater(
        siblingHistory.fetch(
          'child-subagent',
          0,
          currentSessionId: 'tip-subagent',
          latestChildId: 'sibling',
        ),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      expect(messageReads, 0);
      siblingHistory.close();
    },
  );

  test(
    'backward proof is bounded; no arbitrary full-store discovery',
    () async {
      var reads = 0;
      final data = scenario('subagent');
      final history = DashboardTaskHistory.fromConnection(
        SavedConnection(
          id: 'c',
          label: 'c',
          host: 'fixture.test',
          port: 8642,
          apiKey: 'unused',
          dashboardProxied: true,
          gatewayProfile: 'fixture',
        ),
        httpClient: MockClient((request) async {
          reads++;
          expectSync(request.method, 'GET');
          final id = request.url.pathSegments.last;
          final row = id == 'child-subagent'
              ? data['detail']
              : {
                  ...data['tip_detail'] as Map<String, dynamic>,
                  'id': id,
                  'parent_session_id':
                      'hop-${int.parse(id.split('-').last) + 1}',
                  'started_at': 1,
                  'ended_at': 2,
                  'end_reason': 'compression',
                };
          return http.Response(jsonEncode(row), 200);
        }),
      );
      await expectLater(
        history.fetch('child-subagent', 0, latestChildId: 'hop-0'),
        throwsA(isA<TaskHistoryUnavailable>()),
      );
      expect(reads, lessThanOrEqualTo(34));
      history.close();
    },
  );

  test(
    'rotation during older read discards old OFFSET and fetches new head',
    () async {
      final requests = <Uri>[];
      final data = scenario('subagent');
      final history = historyFor(
        'subagent',
        requests,
        messages: (request) => {
          ...data['tip_page'] as Map<String, dynamic>,
          'pagination': {
            ...data['tip_page']['pagination'] as Map<String, dynamic>,
            'offset': int.parse(request.url.queryParameters['offset']!),
          },
        },
      );
      final page = await history.fetch(
        'child-subagent',
        50,
        currentSessionId: 'child-subagent',
      );
      expect(page.offset, 0);
      expect(page.sessionId, 'tip-subagent');
      expect(
        requests
            .where((uri) => uri.path.endsWith('/messages'))
            .map((uri) => uri.queryParameters['offset']),
        ['50', '0'],
      );
      history.close();
    },
  );

  testWidgets(
    'latest reference fences held older read and atomically resets segment coverage',
    (tester) async {
      final source = HeldHistory();
      final controller = DelegatedTaskController(
        task: activity('subagent', 'child-subagent'),
        history: source,
      );
      await controller.refresh();
      expect(controller.olderOffset, 50);
      final older = controller.loadOlder();
      controller.updateTask(activity('subagent', 'tip-subagent'));
      expect(controller.canonicalSessionId, 'child-subagent');
      source.gate.complete(
        TaskHistoryPage(
          rows: [
            {'id': 999, 'role': 'assistant', 'content': 'STALE'},
          ],
          sessionId: 'child-subagent',
          offset: 50,
          lineage: ['child-subagent'],
        ),
      );
      await older;
      await tester.pump();
      expect(source.offsets, [0, 50, 0]);
      expect(controller.canonicalSessionId, 'tip-subagent');
      expect(controller.olderOffset, 1);
      expect(controller.hasOlder, isFalse);
      expect(controller.rows, hasLength(51));
      expect(controller.rows.any((row) => row['id'] == 999), isFalse);
      controller.dispose();
    },
  );
}

class HeldHistory implements TaskHistorySource {
  final gate = Completer<TaskHistoryPage>();
  final offsets = <int>[];
  @override
  Future<TaskHistoryPage> fetch(
    String childId,
    int offset, {
    String? latestChildId,
    String? currentSessionId,
  }) async {
    offsets.add(offset);
    if (offset != 0) return gate.future;
    if (latestChildId == 'tip-subagent') {
      return TaskHistoryPage(
        rows: [
          {'id': 101, 'role': 'assistant', 'content': 'Final'},
        ],
        sessionId: 'tip-subagent',
        offset: 0,
        lineage: ['tip-subagent', childId],
      );
    }
    return TaskHistoryPage(
      rows: [
        for (var id = 1; id <= 50; id++)
          {'id': id, 'role': 'assistant', 'content': 'Earlier'},
      ],
      sessionId: childId,
      offset: 0,
      lineage: [childId],
    );
  }

  @override
  void close() {}
}
