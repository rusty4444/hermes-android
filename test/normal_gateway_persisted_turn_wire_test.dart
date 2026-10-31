import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';

// Exercise production Send, JSON-RPC ingress, REST history, Refresh and actual
// route reopen. The receipt uses the gateway's committed-row address contract,
// never prompt/body equality as a correspondence oracle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  const picker = MethodChannel('plugins.flutter.io/image_picker');

  setUp(() {
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, (_) async => null);
  });
  tearDown(() {
    HttpOverrides.global = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null);
  });

  for (final verbose in [false, true]) {
    for (final localDraft in [false, true]) {
      for (final longTurn in [false, true]) {
        testWidgets(
          'persisted receipt prevents duplicate and misordered bubbles: verbose=$verbose localDraft=$localDraft longTurn=$longTurn',
          (tester) async {
            SharedPreferences.setMockInitialValues({'verbose_mode': verbose});
            await tester.binding.setSurfaceSize(const Size(400, 2200));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final gateway = (await tester.runAsync(_ReceiptServer.start))!;
            final controller = GatewayTurnApplicationController();
            addTearDown(controller.close);
            addTearDown(() => tester.runAsync(gateway.close));
            if (!localDraft) {
              gateway.creates = 1;
              gateway.rows.addAll([
                {'id': 1, 'role': 'user', 'content': 'Prior prompt'},
                {
                  'id': 2,
                  'role': 'assistant',
                  'content': 'Prior answer',
                  'status': 'completed',
                },
              ]);
            }
            final navigator = GlobalKey<NavigatorState>();
            Widget screen(String id, {bool draft = false}) => ChatScreen(
              connection: gateway.connection,
              session: Session(
                id: id,
                title: 'Receipt regression',
                model: 'fixture',
                source: 'test',
                messageCount: gateway.rows.length,
                isActive: false,
                preview: '',
                startedAt: 1,
                isLocalDraft: draft,
              ),
              projectWorkingDirectory: draft ? '/fixture-project' : null,
              turnApplicationController: controller,
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            );
            await tester.pumpWidget(
              MaterialApp(
                navigatorKey: navigator,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const Scaffold(body: Text('Chats')),
              ),
            );
            unawaited(
              navigator.currentState!.push<void>(
                MaterialPageRoute(
                  builder: (_) => screen(
                    localDraft ? 'local-first' : 'stored',
                    draft: localDraft,
                  ),
                ),
              ),
            );
            await widgetUntil(tester, () => gateway.historyReads > 0);
            await tester.pumpAndSettle();
            await tester.enterText(find.byType(TextField), 'Current prompt');
            await widgetUntil(
              tester,
              () =>
                  tester
                      .widget<IconButton>(
                        find.widgetWithIcon(IconButton, Icons.send),
                      )
                      .onPressed !=
                  null,
            );
            await tester.tap(find.byTooltip('Send').hitTestable());
            if (localDraft) {
              await widgetUntil(
                tester,
                () => gateway.createEntered.isCompleted,
              );
              gateway.releaseCreate();
            }
            await widgetUntil(tester, () => gateway.prompts.length == 1);
            final owner = controller
                .normalSessionFor(gateway.connection)
                .findChat('stored')!;
            gateway.event('message.start', {}, turnId: 'wire-1');
            gateway.event('message.delta', {
              'text': 'Checking the code',
            }, turnId: 'wire-1');
            gateway.event('message.interim', {
              'text': 'Checking the code',
              'already_streamed': true,
            }, turnId: 'wire-1');
            gateway.event('tool.start', {
              'tool_id': 'terminal-1',
              'name': 'terminal',
            }, turnId: 'wire-1');
            gateway.event('tool.complete', {
              'tool_id': 'terminal-1',
              'name': 'terminal',
              'result': 'Passed',
            }, turnId: 'wire-1');
            gateway.event('message.delta', {
              'text': 'Final answer',
            }, turnId: 'wire-1');
            await widgetUntil(
              tester,
              () => owner.snapshot.displayRows.any(
                (row) => row['content'] == 'Final answer',
              ),
            );
            final firstId = localDraft ? 1 : 3;
            final extraTools = longTurn ? 64 : 0;
            final finalId = firstId + 3 + extraTools;
            final committed = <Map<String, dynamic>>[
              {'id': firstId, 'role': 'user', 'content': 'Current prompt'},
              {
                'id': firstId + 1,
                'role': 'assistant',
                'content': 'Checking the code',
                'tool_calls': [
                  {
                    'id': 'terminal-1',
                    'type': 'function',
                    'function': {'name': 'terminal', 'arguments': '{}'},
                  },
                ],
              },
              {
                'id': firstId + 2,
                'role': 'tool',
                'tool_call_id': 'terminal-1',
                'content': 'Passed',
              },
              for (var i = 0; i < extraTools; i++)
                {
                  'id': firstId + 3 + i,
                  'role': 'tool',
                  'tool_call_id': 'extra-$i',
                  'tool_name': 'terminal',
                  'content': 'Additional saved result $i',
                },
              {
                'id': finalId,
                'role': 'assistant',
                'content': 'Final answer',
                'status': 'completed',
              },
            ];
            if (longTurn) gateway.rows.addAll(committed);
            gateway.running = false;
            gateway.event('message.complete', {
              'text': 'Final answer',
              'status': 'complete',
              'persisted_turn': {
                'row_ids': [for (final row in committed) row['id']],
                'user_row_id': firstId,
                'user_row_ids': [firstId],
                'final_assistant_row_id': finalId,
                'complete': true,
              },
            }, turnId: 'wire-1');
            gateway.event('turn.end', {
              'status': 'completed',
            }, turnId: 'wire-1');
            await widgetUntil(tester, () => !owner.snapshot.hasActiveTurn);
            if (longTurn) {
              // A live settlement page can contain only the last 50 tool rows.
              // Fetch bounded fresh context automatically, even on an already
              // initialised route, then retire its whole received scope.
              await widgetUntil(
                tester,
                () =>
                    owner.snapshot.displayRows.isEmpty &&
                    gateway.offsets.contains(50),
              );
            } else {
              // The first GET deliberately lags the commit. Retain the reply
              // until the user's later physical Refresh observes the receipt.
              expect(owner.snapshot.displayRows, isNotEmpty);
              await tester.pumpAndSettle();
              expect(find.text('Final answer'), findsOneWidget);
              gateway.rows.addAll(committed);
            }
            final beforeRefresh = gateway.historyReads;
            await tester.tap(find.byTooltip('Chat actions').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Refresh').hitTestable());
            await widgetUntil(
              tester,
              () =>
                  gateway.historyReads > beforeRefresh &&
                  owner.snapshot.historyRows.any((row) => row['id'] == finalId),
            );
            await tester.pumpAndSettle();
            final expected = [
              if (!localDraft) ...['Prior prompt', 'Prior answer'],
              'Current prompt',
              if (verbose) 'Checking the code',
              'Final answer',
            ];
            expect(_bubbleTexts(tester), expected);
            expect(owner.snapshot.timeline.runs, isEmpty);
            expect(owner.snapshot.tools, isEmpty);
            expect(gateway.prompts, hasLength(1));
            final currentState = tester.state(find.byType(ChatScreen));
            // Repeating the same canonical read is idempotent and keeps State.
            await tester.tap(find.byTooltip('Chat actions').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Refresh').hitTestable());
            await widgetUntil(
              tester,
              () => gateway.historyReads > beforeRefresh + 1,
            );
            await tester.pumpAndSettle();
            expect(tester.state(find.byType(ChatScreen)), same(currentState));
            expect(_bubbleTexts(tester), expected);
            navigator.currentState!.pop();
            await tester.pumpAndSettle();
            unawaited(
              navigator.currentState!.push<void>(
                MaterialPageRoute(builder: (_) => screen('stored')),
              ),
            );
            await widgetUntil(
              tester,
              () =>
                  _bubbleTexts(tester).contains('Current prompt') &&
                  find.text('Final answer').evaluate().isNotEmpty,
            );
            await tester.pumpAndSettle();
            expect(_bubbleTexts(tester), expected);
            expect(
              gateway.prompts,
              hasLength(1),
              reason: 'reopen must never resubmit',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await controller.close();
            await tester.runAsync(gateway.close);
            await tester.pump(const Duration(seconds: 16));
          },
        );
      }
    }
  }
}

List<String> _bubbleTexts(WidgetTester tester) => tester
    .widgetList<MessageBubble>(find.byType(MessageBubble))
    .map((bubble) => bubble.content)
    .toList();

class _ReceiptServer extends BindingServer {
  _ReceiptServer(super.server);
  int historyReads = 0;
  final offsets = <int>[];

  static Future<_ReceiptServer> start() async {
    final fixture = _ReceiptServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen(fixture.handle);
    return fixture;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (request.uri.path.endsWith('/messages')) {
      historyReads++;
      final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
      final limit = int.parse(request.uri.queryParameters['limit'] ?? '50');
      offsets.add(offset);
      final end = (rows.length - offset).clamp(0, rows.length);
      final start = (end - limit).clamp(0, end);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': rows.sublist(start, end)}));
      await request.response.close();
      return;
    }
    await super.handle(request);
  }
}
