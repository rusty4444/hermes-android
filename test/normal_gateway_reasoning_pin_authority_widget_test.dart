import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, send, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
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

  for (final width in [400.0, 1000.0]) {
    for (final keepOpen in [false, true]) {
      testWidgets(
        'mounted reasoning pin survives import and lazy eviction width=$width open=$keepOpen',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final (wire, controller, session, source, original) = (await tester
              .runAsync(() async {
                final wire = await _Wire.start();
                final controller = GatewayTurnApplicationController();
                final session = controller.normalSessionFor(wire.connection);
                await session.ready;
                final source = session.chatFor('local', title: 'Original');
                final original = send(source, 'Current prompt')..ignore();
                await wire.createEntered.future;
                return (wire, controller, session, source, original);
              }))!;
          addTearDown(() async {
            await controller.close();
            await wire.close();
            await original;
          });
          try {
            await widgetUntil(tester, () => wire.createEntered.isCompleted);
            wire.rows.add({
              'id': 37,
              'role': 'assistant',
              'content': 'Old context',
            });
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ChatScreen(
                  connection: wire.connection,
                  session: const Session(
                    id: 'stored',
                    title: 'Canonical',
                    model: 'fixture',
                    source: 'test',
                    messageCount: 1,
                    isActive: false,
                    preview: '',
                    startedAt: 1,
                  ),
                  turnApplicationController: controller,
                  testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
                ),
              ),
            );
            final donor = session.findChat('stored')!;
            await widgetUntil(
              tester,
              () => donor.snapshot.historyRows.isNotEmpty,
            );
            final mounted = tester.state(find.byType(ChatScreen));
            send(donor, 'Donor prompt').ignore();
            await widgetUntil(tester, () => wire.prompts.length == 1);
            wire.event('message.start', {}, turnId: 'wire-1');
            wire.event('reasoning.delta', {
              'text': 'Donor reasoning',
            }, turnId: 'wire-1');
            final reads = wire.reads;
            wire.finishReceived('Donor answer');
            await widgetUntil(
              tester,
              () => !donor.snapshot.hasActiveTurn && wire.reads > reads,
            );
            await widgetUntil(
              tester,
              () => _card('Donor reasoning').evaluate().isNotEmpty,
            );
            final beforeId = tester
                .widget<GatewayReasoningCard>(_card('Donor reasoning'))
                .id;
            expect(_expanded(tester, 'Donor reasoning'), isFalse);
            await tester.tap(
              find.descendant(
                of: _card('Donor reasoning'),
                matching: find.text('Reasoning'),
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            if (!keepOpen) {
              await tester.tap(
                find.descendant(
                  of: _card('Donor reasoning'),
                  matching: find.text('Reasoning'),
                ),
              );
              await tester.pump(const Duration(milliseconds: 300));
            }
            expect(_expanded(tester, 'Donor reasoning'), keepOpen);
            wire.releaseCreate();
            await widgetUntil(tester, () => wire.prompts.length == 2);
            wire.event('message.start', {}, turnId: 'wire-2');
            wire.event('reasoning.delta', {
              'text': 'Current reasoning',
            }, turnId: 'wire-2');
            await widgetUntil(
              tester,
              () => _card('Current reasoning').evaluate().isNotEmpty,
            );
            expect(tester.state(find.byType(ChatScreen)), same(mounted));
            expect(
              tester.widget<GatewayReasoningCard>(_card('Donor reasoning')).id,
              beforeId,
            );
            expect(_expanded(tester, 'Donor reasoning'), keepOpen);
            expect(_expanded(tester, 'Current reasoning'), isFalse);
            await tester.tap(
              find.descendant(
                of: _card('Current reasoning'),
                matching: find.text('Reasoning'),
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(_expanded(tester, 'Current reasoning'), isTrue);
            // A real sliver must dispose both cards; a stable key alone is not a
            // lazy-list expansion authority. No route is replaced or reopened.
            final scroll = tester
                .widget<ListView>(
                  find
                      .ancestor(
                        of: _card('Donor reasoning'),
                        matching: find.byType(ListView),
                      )
                      .first,
                )
                .controller!;
            wire.event('message.delta', {
              'text': List.generate(240, (i) => 'Line $i').join('\n\n'),
            }, turnId: 'wire-2');
            await widgetUntil(
              tester,
              () => source.snapshot.displayRows.last['content']
                  .toString()
                  .contains('Line 239'),
            );
            await tester.pump(const Duration(seconds: 1));
            scroll.jumpTo(scroll.position.maxScrollExtent);
            await tester.pump();
            expect(_card('Donor reasoning'), findsNothing);
            expect(_card('Current reasoning'), findsNothing);
            scroll.jumpTo(0);
            await tester.pump();
            expect(_expanded(tester, 'Donor reasoning'), keepOpen);
            expect(_expanded(tester, 'Current reasoning'), isTrue);
            expect(tester.state(find.byType(ChatScreen)), same(mounted));
            final ids = source.snapshot.timeline.runs
                .map((run) => run.id)
                .toList();
            expect(source.snapshot.timeline.runs.map((run) => run.id), ids);
            expect(wire.prompts.map((prompt) => prompt['text']), [
              AndroidPromptContext.forModel('Donor prompt'),
              AndroidPromptContext.forModel('Current prompt'),
            ]);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await controller.close();
            await tester.runAsync(wire.close);
            await tester.pump(const Duration(seconds: 16));
          }
        },
      );
    }
  }
}

Finder _card(String text) => find.byWidgetPredicate(
  (widget) => widget is GatewayReasoningCard && widget.text == text,
);
bool _expanded(WidgetTester tester, String text) => tester
    .widget<ExpansionTile>(
      find.descendant(of: _card(text), matching: find.byType(ExpansionTile)),
    )
    .controller!
    .isExpanded;

class _Wire extends BindingServer {
  _Wire(super.server);
  int reads = 0;
  static Future<_Wire> start() async {
    final wire = _Wire(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    wire.server.listen(wire.handle);
    return wire;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    await super.handle(request);
    if (request.uri.path.endsWith('/messages')) reads++;
  }

  void finishReceived(String text) {
    running = false;
    event('message.delta', {'text': text}, turnId: 'wire-1');
    event('message.complete', {'text': text}, turnId: 'wire-1');
    event('turn.error', {'message': 'fixture failure'}, turnId: 'wire-1');
  }
}
