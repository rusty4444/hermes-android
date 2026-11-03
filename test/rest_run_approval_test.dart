import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_approval.dart';
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/gateway_approval_dialog.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

Map<String, Object> _prompt(String id, Object generation) => {
  'kind': 'approval',
  'prompt_id': id,
  'execution_generation': generation,
};

void main() {
  test('canonical event preserves exact prompt and typed generation', () {
    final prompt = GatewayApprovalRequest.fromEventData({
      ..._prompt(' prompt:exact ', 7),
      'request_id': 'wrong',
      'server_request_id': 'also-wrong',
      'run_id': 'run',
    });
    expect(prompt.requestId, ' prompt:exact ');
    expect(prompt.executionGeneration, 7);
    expect(prompt.canonicalControl, isTrue);
  });

  for (final malformedId in <Object?>[
    null,
    7,
    true,
    <String>[],
    <String, Object>{},
  ]) {
    test('malformed canonical prompt ID $malformedId fails closed', () async {
      final prompt = GatewayApprovalRequest.fromEventData({
        'prompt_id': malformedId,
        'request_id': 'unrelated-legacy-id',
        'execution_generation': 7,
      });
      expect(prompt.requestId, isNull);
      expect(prompt.canonicalControl, isTrue);
      var requests = 0;
      final client = ApiClient(
        baseUrl: 'https://fixture.invalid',
        apiKey: 'fixture',
        httpClient: MockClient((_) async {
          requests++;
          return _json({});
        }),
      );
      await expectLater(
        client.respondToRunApproval(
          runId: 'run',
          choice: 'once',
          requestId: prompt.requestId,
          executionGeneration: prompt.executionGeneration,
          canonicalControl: prompt.canonicalControl,
        ),
        throwsStateError,
      );
      expect(requests, 0);
      client.close();
    });
  }

  for (final choice in ['once', 'session', 'always', 'deny']) {
    test(
      'captured canonical generation sends exactly one $choice response',
      () async {
        final requests = <http.Request>[];
        final client = ApiClient(
          baseUrl: 'https://fixture.invalid',
          apiKey: 'fixture',
          pathPrefix: '/p/selected',
          httpClient: MockClient((r) async {
            requests.add(r);
            return _json({
              'run_id': 'run',
              'prompt_id': ' prompt ',
              'status': 'resolved',
            });
          }),
        );
        await client.respondToRunApproval(
          runId: 'run',
          choice: choice,
          requestId: ' prompt ',
          executionGeneration: 7,
        );
        expect(requests, hasLength(1));
        expect(requests.single.url.path, '/p/selected/v1/runs/run/approval');
        expect(requests.single.headers['authorization'], 'Bearer fixture');
        expect(jsonDecode(requests.single.body), {
          'request_id': ' prompt ',
          'execution_generation': 7,
          'choice': choice,
        });
        client.close();
      },
    );
  }

  test(
    'lookup selects only exact approval, not first prompt or clarify',
    () async {
      final methods = <String>[];
      final client = ApiClient(
        baseUrl: 'http://fixture.invalid',
        apiKey: 'fixture',
        httpClient: MockClient((r) async {
          methods.add(r.method);
          if (r.method == 'GET') {
            return _json({
              'execution_generation': 9,
              'pending_controls': [
                _prompt('other', 9),
                {..._prompt('wanted', 9), 'kind': 'clarify'},
                _prompt('wanted', 9),
              ],
            });
          }
          expect(jsonDecode(r.body), {
            'request_id': 'wanted',
            'execution_generation': 9,
            'choice': 'once',
          });
          return _json({
            'run_id': 'run',
            'prompt_id': 'wanted',
            'status': 'resolved',
          });
        }),
      );
      await client.respondToRunApproval(
        runId: 'run',
        requestId: 'wanted',
        choice: 'once',
      );
      expect(methods, ['GET', 'POST']);
      client.close();
    },
  );

  for (final scenario in [
    'missing',
    'identityless',
    'duplicate',
    'malformed',
    'mismatch',
    'revoked',
    'read-failure',
  ]) {
    test('$scenario lookup fails closed without POST', () async {
      var current = true;
      var posts = 0;
      final client = ApiClient(
        baseUrl: 'http://fixture.invalid',
        apiKey: 'fixture',
        httpClient: MockClient((r) async {
          if (r.method == 'POST') posts++;
          if (scenario == 'revoked') current = false;
          if (scenario == 'read-failure') return _json({}, 503);
          return _json({
            'execution_generation': 9,
            'pending_controls': [
              if (scenario != 'missing')
                _prompt(
                  'wanted',
                  scenario == 'malformed'
                      ? '9'
                      : scenario == 'mismatch'
                      ? 8
                      : 9,
                ),
              if (scenario == 'duplicate') _prompt('wanted', 9),
            ],
          });
        }),
      );
      await expectLater(
        client.respondToRunApproval(
          runId: 'run',
          choice: 'once',
          requestId: scenario == 'identityless' ? null : 'wanted',
          isCurrent: () => current,
        ),
        throwsA(anything),
      );
      expect(posts, 0);
      client.close();
    });
  }

  for (final failure in [
    'stale_generation',
    'approval_not_pending',
    'invalid_params',
    'lost-ack',
    'bad-ack',
  ]) {
    test('$failure never refreshes generation or resends', () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'http://fixture.invalid',
        apiKey: 'fixture',
        httpClient: MockClient((r) async {
          requests.add(r);
          if (failure == 'lost-ack') {
            throw http.ClientException('connection lost');
          }
          if (failure == 'bad-ack') {
            return _json({
              'run_id': 'run',
              'prompt_id': 'successor',
              'status': 'resolved',
            });
          }
          return _json({
            'error': {'code': failure},
          }, failure == 'invalid_params' ? 400 : 409);
        }),
      );
      await expectLater(
        client.respondToRunApproval(
          runId: 'run',
          requestId: 'wanted',
          choice: 'once',
          executionGeneration: 7,
        ),
        throwsA(
          failure == 'stale_generation' || failure == 'approval_not_pending'
              ? isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  'This approval is no longer pending.',
                )
              : anything,
        ),
      );
      expect(requests, hasLength(1));
      expect(jsonDecode(requests.single.body)['execution_generation'], 7);
      client.close();
    });
  }

  for (final id in <String?>['legacy-prompt', null]) {
    test('legacy projection retains original body for $id', () async {
      final requests = <http.Request>[];
      final client = ApiClient(
        baseUrl: 'http://fixture.invalid',
        apiKey: 'fixture',
        httpClient: MockClient((r) async {
          requests.add(r);
          return r.method == 'GET'
              ? _json({
                  'object': 'hermes.run',
                  'status': 'waiting_for_approval',
                })
              : _json({'object': 'hermes.run.approval_response'});
        }),
      );
      await client.respondToRunApproval(
        runId: 'run',
        requestId: id,
        choice: 'deny',
      );
      expect(requests.map((r) => r.method), ['GET', 'POST']);
      expect(jsonDecode(requests.last.body), {
        'choice': 'deny',
        'request_id': ?id,
      });
      client.close();
    });
  }

  test('malformed event generation cannot downgrade to legacy', () async {
    var requests = 0;
    final client = ApiClient(
      baseUrl: 'http://fixture.invalid',
      apiKey: 'fixture',
      httpClient: MockClient((_) async {
        requests++;
        return _json({});
      }),
    );
    await expectLater(
      client.respondToRunApproval(
        runId: 'run',
        requestId: 'wanted',
        choice: 'once',
        executionGeneration: '7',
      ),
      throwsFormatException,
    );
    expect(requests, 0);
    client.close();
  });

  for (final scenario in [
    'captured generation',
    'held preflight blocks Back',
    'failed preflight restores Back denial',
    'Back before submission denies',
    'explicit denial',
  ]) {
    testWidgets('real REST chat approval: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({'verbose_mode': false});
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <http.Request>[];
      final stream = StreamController<List<int>>();
      final preflight = Completer<void>();
      var preflightReads = 0;
      final connection = SavedConnection(
        id: 'rest-approval',
        label: 'REST',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture',
      );
      final client = ApiClient(
        baseUrl: connection.baseUrl,
        apiKey: 'fixture',
        httpClient: MockClient.streaming((r, body) async {
          final request = http.Request(r.method, r.url)
            ..body = await body.bytesToString();
          requests.add(request);
          if (r.url.path.endsWith('/completions')) {
            return http.StreamedResponse(stream.stream, 200);
          }
          if (r.url.path.endsWith('/runs/run')) {
            preflightReads++;
            if (preflightReads == 1) {
              await preflight.future;
              if (scenario == 'failed preflight restores Back denial') {
                return http.StreamedResponse(
                  Stream.value(utf8.encode('{}')),
                  503,
                );
              }
            }
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'execution_generation': 11,
                    'pending_controls': [_prompt('exact-prompt', 11)],
                  }),
                ),
              ),
              200,
            );
          }
          final value = r.url.path.endsWith('/approval')
              ? {
                  'run_id': 'run',
                  'prompt_id': 'exact-prompt',
                  'status': 'resolved',
                }
              : r.url.path.endsWith('/messages')
              ? {'data': []}
              : {
                  'session': {'id': 'session', 'archived': false},
                };
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(value))),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(
            connection: connection,
            session: Session(
              id: 'session',
              title: 'REST',
              model: 'fixture',
              source: 'test',
              messageCount: 0,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: client,
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            testProjectOverviewLoader: () async => ProjectsTreeOverview.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'approval fixture');
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      stream.add(
        utf8.encode(
          'event: approval.request\ndata: ${jsonEncode({
            'kind': 'approval',
            'prompt_id': 'exact-prompt',
            if (scenario == 'captured generation') 'execution_generation': 11,
            'run_id': 'run',
            'command': 'echo fixture',
            'choices': ['once', 'deny'],
          })}\n\n',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GatewayApprovalDialog), findsOneWidget);
      if (scenario == 'Back before submission denies') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(
          find.byKey(
            Key(
              scenario == 'explicit denial' ? 'approval-deny' : 'approval-once',
            ),
          ),
        );
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (scenario != 'captured generation') {
        expect(preflightReads, 1);
        expect(
          requests.where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/approval'),
          ),
          isEmpty,
        );
        if (scenario.startsWith('held') || scenario.startsWith('failed')) {
          await tester.binding.handlePopRoute();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(GatewayApprovalDialog), findsOneWidget);
          expect(preflightReads, 1, reason: 'Back must not start a denial');
          expect(
            requests.where(
              (r) => r.method == 'POST' && r.url.path.endsWith('/approval'),
            ),
            isEmpty,
          );
        }
        preflight.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        if (scenario == 'failed preflight restores Back denial') {
          expect(find.byKey(const Key('approval-error')), findsOneWidget);
          expect(find.byType(GatewayApprovalDialog), findsOneWidget);
          await tester.binding.handlePopRoute();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(preflightReads, 2);
        }
      }
      final posts = requests
          .where((r) => r.url.path.endsWith('/approval'))
          .toList();
      expect(posts, hasLength(1));
      expect(jsonDecode(posts.single.body), {
        'request_id': 'exact-prompt',
        'execution_generation': 11,
        'choice':
            scenario == 'captured generation' ||
                scenario == 'held preflight blocks Back'
            ? 'once'
            : 'deny',
      });
      expect(find.byType(GatewayApprovalDialog), findsNothing);
      expect(
        requests.where((r) => r.url.path.endsWith('/completions')),
        hasLength(1),
      );
      stream.add(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"Done"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
        ),
      );
      await stream.close();
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      // Disposing a REST route retains the HTTP owner for its bounded
      // background-stream grace period. Drain that owner before timer checks.
      await tester.pump(const Duration(minutes: 30));
    });
  }
}
