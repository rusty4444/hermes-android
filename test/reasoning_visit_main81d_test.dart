import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/tool_activity_group_pins.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    mockChatImageRecovery();
  });

  for (final reverse in [false, true]) {
    test(
      'MAIN81D independent bounded reasoning visits alias reverse=$reverse',
      () async {
        final registry = ChatPresentationRegistry('visits');
        final local = registry.chatFor('local');
        final stored = registry.chatFor('stored');
        final a = local.openReasoningVisit()..pin('same-id', true);
        final b = stored.openReasoningVisit()..pin('same-id', false);
        final tools = local.openToolVisit()..pin('tool', true);
        registry.bind(
          reverse ? 'stored' : 'local',
          reverse ? 'local' : 'stored',
        );
        expect(a['same-id'], isTrue);
        expect(b['same-id'], isFalse);
        expect(local.openReasoningVisit()['same-id'], isNull);
        for (var i = 0; i < 350; i++) {
          a.alias('r$i', 'durable$i');
          a.pin('r$i', true);
        }
        expect(a.length, ToolActivityGroupPins.maxPins);
        expect(a['r0'], isNull);
        a.pin('r0', false);
        expect(a['durable0'], isNull, reason: 'evicted alias cannot resurrect');
        expect(b['same-id'], isFalse);
        local.closeReasoningVisit(a);
        expect(a.length, 0);
        expect(b['same-id'], isFalse);
        expect(
          tools['tool'],
          isTrue,
          reason: 'reasoning close is not tool close',
        );
        expect(stored.openReasoningVisit()['same-id'], isNull);
        registry.close();
        expect(b.length, 0);
        expect(tools.length, 0);
        expect(() => local.openReasoningVisit(), throwsStateError);
        local.closeReasoningVisit(a);
        await Future<void>.delayed(Duration.zero);
      },
    );
  }

  for (final width in [400.0, 1000.0]) {
    for (final verbose in [false, true]) {
      for (final manual in [false, true]) {
        testWidgets(
          'MAIN81D C/R visit cover lazy reopen width=$width verbose=$verbose manual=$manual',
          (tester) async {
            SharedPreferences.setMockInitialValues({'verbose_mode': verbose});
            await tester.binding.setSurfaceSize(Size(width, 2400));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final controller = GatewayTurnApplicationController();
            final remote = _Remote();
            final key = GlobalKey<NavigatorState>();
            final rows = <Map<String, dynamic>>[
              {'id': 1, 'role': 'user', 'content': 'Saved prompt'},
              {
                'id': 2,
                'role': 'assistant',
                'content': 'Saved answer',
                // This hand-written fixture is a known completed older reply.
                'completed': true,
                '_gateway_reasoning': 'Saved reasoning',
                '_gateway_reasoning_verbose': true,
              },
            ];
            Widget screen() => _screen(controller, remote, rows);
            try {
              await tester.pumpWidget(
                MaterialApp(
                  navigatorKey: key,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => screen()),
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open'));
              await pumpChatUpdates(tester);
              final state = tester.state(find.byType(ChatScreen));
              final route = ModalRoute.of(
                tester.element(find.byType(ChatScreen)),
              );
              final composer = tester
                  .widget<TextField>(find.byType(TextField))
                  .controller!;
              final scroll = tester
                  .widget<ListView>(find.byType(ListView).first)
                  .controller!;
              if (verbose) {
                // New visits align to the latest section. Reveal the older
                // saved card before checking that its route-local pin reset.
                if (_reason('Saved reasoning').evaluate().isEmpty) {
                  await tester.scrollUntilVisible(
                    _reason('Saved reasoning'),
                    -250,
                    scrollable: find.byType(Scrollable).first,
                  );
                }
                expect(_expanded(tester, _reason('Saved reasoning')), isFalse);
                await _choose(tester, _reason('Saved reasoning'), manual);
              } else {
                _expectQuiet(tester);
                expect(find.text('Saved prompt'), findsOneWidget);
                expect(find.text('Saved answer'), findsOneWidget);
              }
              final savedKey = verbose
                  ? tester.widget(_reason('Saved reasoning')).key
                  : null;
              final savedState = verbose
                  ? tester.state(_reason('Saved reasoning'))
                  : null;
              await tester.enterText(find.byType(TextField), 'Received prompt');
              await tester.tap(find.byTooltip('Send'));
              await tester.pump();
              await tester.pump();
              remote.event('reasoning.delta', {
                'text': 'Received reasoning',
                'verbose': true,
              });
              remote.event('tool.start', {
                'tool': 'terminal',
                'tool_id': 't',
                'detail': 'Tool body',
              });
              await tester.pump(const Duration(milliseconds: 350));
              if (verbose) {
                await _reveal(tester, _reason('Received reasoning'));
                expect(
                  _expanded(tester, _reason('Received reasoning')),
                  isFalse,
                );
                await _choose(tester, _reason('Received reasoning'), manual);
              } else {
                _expectQuiet(tester);
                expect(find.text('Received prompt'), findsOneWidget);
              }
              final receivedKey = verbose
                  ? tester.widget(_reason('Received reasoning')).key
                  : null;
              final receivedState = verbose
                  ? tester.state(_reason('Received reasoning'))
                  : null;
              final tool = find.byType(GatewayActivityCard);
              if (verbose) await _choose(tester, tool, true);
              final owner = controller
                  .normalSessionFor(_connection)
                  .findChat('stored')!;
              final receiptIds = owner.snapshot.timeline.runs
                  .map((run) => run.id)
                  .toList();
              await tester.enterText(find.byType(TextField), 'Keep next draft');
              key.currentState!.push<void>(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('Covered')),
                ),
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              remote.event('reasoning.available', {
                'text': 'Received reasoning updated',
                'verbose': true,
              });
              await tester.pump();
              key.currentState!.pop();
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 350));
              expect(tester.state(find.byType(ChatScreen)), same(state));
              expect(
                ModalRoute.of(tester.element(find.byType(ChatScreen))),
                same(route),
              );
              expect(
                tester.widget<TextField>(find.byType(TextField)).controller,
                same(composer),
              );
              expect(composer.text, 'Keep next draft');
              expect(
                owner.snapshot.timeline.runs.map((run) => run.id),
                receiptIds,
              );
              if (verbose) {
                expect(
                  _expanded(tester, _reason('Received reasoning updated')),
                  manual,
                );
                expect(_expanded(tester, tool), isTrue);
                expect(
                  tester.widget(_reason('Received reasoning updated')).key,
                  receivedKey,
                );
                expect(
                  tester.state(_reason('Received reasoning updated')),
                  same(receivedState),
                );
              } else {
                _expectQuiet(tester);
                expect(find.text('Received prompt'), findsOneWidget);
              }
              // At phone width/2x text, revealing the received/tool cells already
              // evicts saved reasoning. A wide mounted card keeps its controller.
              if (verbose && width == 1000) {
                expect(tester.widget(_reason('Saved reasoning')).key, savedKey);
                expect(
                  tester.state(_reason('Saved reasoning')),
                  same(savedState),
                );
              }
              remote.event('message.delta', {
                'text': List.generate(
                  200,
                  (i) => 'Long received line $i',
                ).join('\n\n'),
              });
              await tester.pump(const Duration(milliseconds: 350));
              scroll.jumpTo(scroll.position.maxScrollExtent);
              await tester.pump(const Duration(milliseconds: 350));
              expect(_reason('Saved reasoning'), findsNothing);
              expect(_reason('Received reasoning updated'), findsNothing);
              scroll.jumpTo(0);
              await tester.pump(const Duration(milliseconds: 350));
              if (verbose) {
                expect(_expanded(tester, _reason('Saved reasoning')), manual);
                expect(tester.widget(_reason('Saved reasoning')).key, savedKey);
                await tester.scrollUntilVisible(
                  _reason('Received reasoning updated'),
                  350,
                  scrollable: find.byType(Scrollable).first,
                );
                expect(
                  _expanded(tester, _reason('Received reasoning updated')),
                  manual,
                );
                if (tool.evaluate().isEmpty) {
                  await tester.scrollUntilVisible(
                    tool,
                    250,
                    scrollable: find.byType(Scrollable).first,
                  );
                }
                expect(_expanded(tester, tool), isTrue);
              } else {
                _expectQuiet(tester);
                expect(find.text('Saved answer'), findsOneWidget);
                expect(find.textContaining('Long received line'), findsNothing);
              }
              expect(
                tester.widget<ListView>(find.byType(ListView).first).controller,
                same(scroll),
              );
              remote.event('tool.complete', {
                'tool': 'terminal',
                'tool_id': 't',
              });
              remote.event('message.complete', {'text': 'Received final'});
              remote.done.complete();
              await pumpChatUpdates(tester);
              // Real route disposal resets choices, not retained output or draft.
              key.currentState!.pop();
              await tester.pump();
              await tester.pump(route!.reverseTransitionDuration);
              await pumpChatUpdates(tester);
              expect(state.mounted, isFalse);
              await tester.tap(find.text('Open'));
              await pumpChatUpdates(tester);
              expect(tester.state(find.byType(ChatScreen)), isNot(same(state)));
              expect(
                tester
                    .widget<TextField>(find.byType(TextField))
                    .controller!
                    .text,
                'Keep next draft',
              );
              final reopenedScroll = tester
                  .widget<ListView>(find.byType(ListView).first)
                  .controller!;
              expect(
                reopenedScroll.position.pixels,
                closeTo(reopenedScroll.position.maxScrollExtent, 1),
              );
              if (verbose) {
                // New visits align to the latest section. Reveal the older
                // saved card before checking that its route-local pin reset.
                if (_reason('Saved reasoning').evaluate().isEmpty) {
                  await tester.scrollUntilVisible(
                    _reason('Saved reasoning'),
                    -250,
                    scrollable: find.byType(Scrollable).first,
                  );
                }
                expect(_expanded(tester, _reason('Saved reasoning')), isFalse);
                if (_reason('Received reasoning updated').evaluate().isEmpty) {
                  await tester.scrollUntilVisible(
                    _reason('Received reasoning updated'),
                    250,
                    scrollable: find.byType(Scrollable).first,
                  );
                }
                expect(
                  _expanded(tester, _reason('Received reasoning updated')),
                  isFalse,
                );
                expect(
                  tester
                      .widget<GatewayReasoningCard>(
                        _reason('Received reasoning updated'),
                      )
                      .text,
                  'Received reasoning updated',
                );
              } else {
                _expectQuiet(tester);
                expect(find.text('Saved answer'), findsOneWidget);
                expect(find.text('Received final'), findsOneWidget);
              }
              expect(remote.submissions, 1);
              expect(rows.map((r) => r['id']), [1, 2]);
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              await controller.close();
              await pumpChatUpdates(tester);
            }
          },
        );
      }
    }
  }

  for (final width in [400.0, 1000.0]) {
    for (final verbose in [false, true]) {
      testWidgets(
        'MAIN81D SSE retains stored reasoning manual choice width=$width verbose=$verbose',
        (tester) async {
          SharedPreferences.setMockInitialValues({'verbose_mode': verbose});
          await tester.binding.setSurfaceSize(Size(width, 1800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final controller = GatewayTurnApplicationController();
          final client = _SseClient();
          Widget app() => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatScreen(
              key: UniqueKey(),
              connection: _connection,
              session: const Session(
                id: 'stored',
                title: 'SSE',
                model: 'fixture',
                source: 'test',
                messageCount: 2,
                isActive: false,
                preview: '',
                startedAt: 1,
              ),
              turnApplicationController: controller,
              testApiClient: ApiClient(
                baseUrl: _connection.baseUrl,
                apiKey: 'fixture',
                httpClient: client,
              ),
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          );
          await tester.pumpWidget(app());
          await pumpChatUpdates(tester);
          final state = tester.state(find.byType(ChatScreen));
          if (verbose) {
            expect(_expanded(tester, _reason('SSE saved reasoning')), isFalse);
            await _choose(tester, _reason('SSE saved reasoning'), true);
            expect(find.text('Saved reply'), findsOneWidget);
          } else {
            _expectQuiet(tester);
            expect(find.text('Saved prompt'), findsOneWidget);
            // The metadata-free saved row is retained, not assumed final.
            expect(find.text('Saved reply'), findsNothing);
          }
          final key = verbose
              ? tester.widget(_reason('SSE saved reasoning')).key
              : null;
          await tester.enterText(find.byType(TextField), 'SSE prompt');
          await tester.tap(find.byTooltip('Send'));
          await tester.pump();
          await tester.pump();
          client.emit(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': 'SSE streamed reply'},
                },
              ],
            })}\n\n',
          );
          await tester.pump(const Duration(milliseconds: 350));
          if (verbose) {
            expect(_expanded(tester, _reason('SSE saved reasoning')), isTrue);
            expect(tester.widget(_reason('SSE saved reasoning')).key, key);
            // Pin closed explicitly; verbose no longer supplies an open default.
            await _choose(tester, _reason('SSE saved reasoning'), false);
          } else {
            _expectQuiet(tester);
            expect(find.text('SSE streamed reply'), findsNothing);
            expect(find.text('SSE prompt'), findsOneWidget);
          }
          expect(tester.state(find.byType(ChatScreen)), same(state));
          await client.finish();
          await pumpChatUpdates(tester);
          if (verbose) {
            expect(_expanded(tester, _reason('SSE saved reasoning')), isFalse);
            expect(tester.widget(_reason('SSE saved reasoning')).key, key);
          } else {
            _expectQuiet(tester);
            expect(find.text('SSE streamed reply'), findsOneWidget);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.pumpWidget(app());
          await pumpChatUpdates(tester);
          if (verbose) {
            expect(_expanded(tester, _reason('SSE saved reasoning')), isFalse);
            expect(
              tester
                  .widget<GatewayReasoningCard>(_reason('SSE saved reasoning'))
                  .text,
              'SSE saved reasoning',
            );
          } else {
            _expectQuiet(tester);
            expect(find.text('Saved reply'), findsNothing);
          }
          expect(client.submissions, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          await controller.close();
          await pumpChatUpdates(tester);
        },
      );
    }
  }

  for (final profile in [false, true]) {
    testWidgets(
      'MAIN81D same-State config replacement cannot lend reasoning pins profile=$profile',
      (tester) async {
        final controller = GatewayTurnApplicationController();
        final remote = _Remote();
        final rows = <Map<String, dynamic>>[
          {
            'id': 2,
            'role': 'assistant',
            'content': 'Saved answer',
            '_gateway_reasoning': 'Saved reasoning',
            '_gateway_reasoning_verbose': true,
          },
        ];
        Widget app(SavedConnection connection) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _screen(controller, remote, rows, connection: connection),
        );
        await tester.pumpWidget(app(_connection));
        await pumpChatUpdates(tester);
        final state = tester.state(find.byType(ChatScreen));
        await _choose(tester, _reason('Saved reasoning'), true);
        final changed = SavedConnection(
          id: _connection.id,
          label: 'Fixture',
          host: 'fixture.invalid',
          port: 8642,
          apiKey: profile ? 'fixture' : 'replacement',
          gatewayProfile: profile ? 'second' : null,
        );
        await tester.pumpWidget(app(changed));
        await pumpChatUpdates(tester);
        expect(tester.state(find.byType(ChatScreen)), same(state));
        expect(_expanded(tester, _reason('Saved reasoning')), isFalse);
        expect(remote.submissions, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.close();
        await pumpChatUpdates(tester);
      },
    );
  }
}

final _connection = SavedConnection(
  id: 'reasoning-main81d',
  label: 'Fixture',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'fixture',
);

Widget _screen(
  GatewayTurnApplicationController controller,
  _Remote remote,
  List<Map<String, dynamic>> rows, {
  SavedConnection? connection,
}) => ChatScreen(
  connection: connection ?? _connection,
  session: const Session(
    id: 'stored',
    title: 'Reasoning visits',
    model: 'fixture',
    source: 'test',
    messageCount: 2,
    isActive: false,
    preview: '',
    startedAt: 1,
  ),
  turnApplicationController: controller,
  testApiClient: ApiClient(
    baseUrl: _connection.baseUrl,
    apiKey: 'fixture',
    httpClient: MockClient(
      (_) async => http.Response(jsonEncode({'data': rows}), 200),
    ),
  ),
  testRemotePromptSubmit: remote.submit,
  testStoredSessionKey: (_) => 'stored',
  testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
);

Finder _reason(String text) =>
    find.byWidgetPredicate((w) => w is GatewayReasoningCard && w.text == text);
bool _expanded(WidgetTester tester, Finder card) => tester
    .widget<ExpansionTile>(
      find.descendant(of: card, matching: find.byType(ExpansionTile)),
    )
    .controller!
    .isExpanded;
Future<void> _choose(WidgetTester tester, Finder card, bool expanded) async {
  await _reveal(tester, card);
  if (!expanded && !_expanded(tester, card)) {
    // An untouched collapsed default is not a manual closed pin.
    await tester.tap(
      find.descendant(of: card, matching: find.byType(ListTile)).first,
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(_expanded(tester, card), isTrue);
  }
  if (_expanded(tester, card) != expanded) {
    await tester.tap(
      find.descendant(of: card, matching: find.byType(ListTile)).first,
    );
    await tester.pump(const Duration(milliseconds: 350));
  }
  expect(_expanded(tester, card), expanded);
}

void _expectQuiet(WidgetTester tester) {
  expect(find.byType(GatewayReasoningCard), findsNothing);
  expect(find.byType(GatewayActivityCard), findsNothing);
  expect(find.byType(GatewaySubagentCard), findsNothing);
}

Future<void> _reveal(WidgetTester tester, Finder card) async {
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      card,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final header = find
      .descendant(of: card, matching: find.byType(ListTile))
      .first;
  await Scrollable.ensureVisible(tester.element(header), alignment: 0.2);
  await tester.pump(const Duration(milliseconds: 350));
  await Scrollable.ensureVisible(tester.element(header), alignment: 0.2);
  await tester.pump();
}

class _SseClient extends http.BaseClient {
  final stream = StreamController<List<int>>();
  int submissions = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      submissions++;
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          jsonEncode({
            'data': [
              {'id': 1, 'role': 'user', 'content': 'Saved prompt'},
              {
                'id': 2,
                'role': 'assistant',
                'content': 'Saved reply',
                '_gateway_reasoning': 'SSE saved reasoning',
                '_gateway_reasoning_verbose': true,
              },
            ],
          }),
        ),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  void emit(String text) => stream.add(utf8.encode(text));
  Future<void> finish() async {
    emit('data: [DONE]\n\n');
    await stream.close();
  }
}

class _Remote {
  final done = Completer<void>();
  StreamCallback? callback;
  int submissions = 0;
  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) {
    submissions++;
    callback = onEvent;
    onSent();
    return done.future;
  }

  void event(String type, Map<String, dynamic> data) =>
      callback!(StreamEvent(type: type, data: data));
}
