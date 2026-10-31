import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';
import 'support/unreconciled_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  final spoken = <String>[];
  final speechCompletions = <Completer<int>>[];
  final shared = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
    spoken.clear();
    speechCompletions.clear();
    shared.clear();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'), (
      call,
    ) async {
      if (call.method == 'getMaxSpeechInputLength') return 4000;
      if (call.method == 'speak') {
        final args = call.arguments;
        spoken.add(args is String ? args : (args as Map)['text'] as String);
        // With awaitSpeakCompletion enabled Android replies only when this
        // utterance finishes, not merely when it has been enqueued.
        final completion = Completer<int>();
        speechCompletions.add(completion);
        return completion.future;
      }
      return 1;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        if (call.method == 'share') {
          shared.add((call.arguments as Map)['text'] as String);
        }
        return 'success';
      },
    );
  });
  tearDown(() {
    for (final completion in speechCompletions) {
      if (!completion.isCompleted) completion.complete(0);
    }
    HttpOverrides.global = previous;
    for (final name in [
      'plugins.flutter.io/image_picker',
      'flutter_tts',
      'dev.fluttercommunity.plus/share',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  for (final width in [400.0, 1000.0]) {
    for (final verbose in [false, true]) {
      testWidgets(
        'NOTICE details are on demand at $width with verbose $verbose',
        (tester) async {
          SharedPreferences.setMockInitialValues({'verbose_mode': verbose});
          await tester.binding.setSurfaceSize(Size(width, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final wire = (await tester.runAsync(BindingServer.start))!;
          wire.creates = 1;
          wire.rows.add({
            'id': 37,
            'role': 'assistant',
            'content': 'Saved context',
          });
          final controller = GatewayTurnApplicationController();
          try {
            await _mount(tester, wire, controller, textScale: 1.7);
            final owner = controller
                .normalSessionFor(wire.connection)
                .findChat('stored')!;
            await widgetUntil(
              tester,
              () => owner.snapshot.historyRows.isNotEmpty,
            );
            await tester.enterText(find.byType(TextField), 'Prompt');
            await tester.tap(find.byTooltip('Send'));
            await widgetUntil(tester, () => wire.prompts.length == 1);
            wire.event('message.delta', {
              'text': 'Received reply',
            }, turnId: 'wire-1');
            await widgetUntil(
              tester,
              () => owner.snapshot.displayRows.any(
                (row) =>
                    row['role'] == 'assistant' &&
                    row['content'] == 'Received reply',
              ),
            );
            await tester.pump();
            expect(
              find.text('Received reply'),
              verbose ? findsOneWidget : findsNothing,
              reason:
                  'quiet mode requires this response\'s positive completion receipt',
            );
            final l10n = AppLocalizations.of(
              tester.element(find.byType(ChatScreen)),
            )!;
            void expectNoNotice() {
              expect(find.text(l10n.received_output_heading), findsNothing);
              expect(find.text(l10n.received_output_explanation), findsNothing);
              expect(find.text(l10n.received_output_lifetime), findsNothing);
              expect(
                find.byKey(
                  const ValueKey((ChatDisplaySource.received, 'heading')),
                ),
                findsNothing,
              );
            }

            expectNoNotice();
            wire.running = false;
            wire.event('message.complete', {
              'text': 'Received reply',
            }, turnId: 'wire-1');
            wire.event('turn.end', {}, turnId: 'wire-1');
            await widgetUntil(tester, () => !owner.snapshot.hasActiveTurn);
            await tester.pumpAndSettle();
            expectNoNotice();
            expect(find.text('Received reply'), findsOneWidget);
            expect(
              find.textContaining(l10n.received_output_badge),
              verbose ? findsOneWidget : findsNothing,
            );

            await tester.enterText(find.byType(TextField), 'Keep draft');
            final composer = tester
                .widget<TextField>(find.byType(TextField))
                .controller!;
            composer.selection = const TextSelection(
              baseOffset: 2,
              extentOffset: 6,
            );
            final draft = composer.value;
            final receivedRows = owner.snapshot.displayRows;
            final historyRows = owner.snapshot.historyRows;
            final screen = tester.state(find.byType(ChatScreen));
            await tester.tap(find.byTooltip('Chat actions').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('About received output').hitTestable());
            await tester.pump(kThemeAnimationDuration);
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.text(l10n.received_output_heading), findsOneWidget);
            expect(find.text(l10n.received_output_explanation), findsOneWidget);
            expect(find.text(l10n.received_output_lifetime), findsOneWidget);
            await tester.tap(find.widgetWithText(TextButton, 'Close'));
            await tester.pumpAndSettle();

            expectNoNotice();
            expect(find.text('Received reply'), findsOneWidget);
            expect(tester.state(find.byType(ChatScreen)), same(screen));
            expect(composer.value, draft);
            expect(owner.snapshot.displayRows, receivedRows);
            expect(owner.snapshot.historyRows, historyRows);
            expect(wire.prompts, hasLength(1));
            expect(tester.takeException(), isNull);
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

  for (final width in [400.0, 1000.0]) {
    for (final mode in ['loading', '500']) {
      testWidgets(
        'POLICY idle accepted saved rows remain usable during $mode at $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final wire = (await tester.runAsync(_AvailabilityServer.start))!;
          wire.rows.add({
            'id': 37,
            'role': 'assistant',
            'content': 'Already accepted saved context',
          });
          final controller = GatewayTurnApplicationController();
          final normal = controller.normalSessionFor(wire.connection);
          final api = ApiClient(
            baseUrl: wire.connection.baseUrl,
            apiKey: wire.connection.apiKey,
          );
          try {
            await normal.ready;
            final owner = normal.chatFor(
              'stored',
              storedSessionId: 'stored',
              title: 'Policy',
            );
            final read = owner.beginHistoryRead('stored');
            final rows = (await tester.runAsync(
              () => api.getMessages('stored', latest: true),
            ))!;
            expect(owner.observeHistory(rows, read: read), isTrue);
            expect(owner.snapshot.turnId, isNull);
            wire.mode = mode;
            await _mount(tester, wire, controller);
            await widgetUntil(tester, () => wire.entered.isCompleted);
            if (mode == '500') {
              await widgetUntil(
                tester,
                () => find.byType(MaterialBanner).evaluate().isNotEmpty,
              );
            }
            await tester.pump();
            expect(
              inChatSource(
                find.text('Already accepted saved context'),
                ChatDisplaySource.canonical,
              ),
              findsOneWidget,
            );
            expect(find.text('Saved history'), findsOneWidget);
            expect(find.byType(ListView), findsOneWidget);
            expect(wire.prompts, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            wire.release();
            await tester.pumpWidget(const SizedBox.shrink());
            api.close();
            await controller.close();
            await tester.runAsync(wire.close);
            await tester.pump(const Duration(seconds: 16));
          }
        },
      );
    }
  }

  for (final width in [400.0, 1000.0]) {
    testWidgets('POLICY labels, lazy identity, drafts and export at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      final wire = (await tester.runAsync(BindingServer.start))!;
      wire.creates = 1;
      wire.rows.add({
        'id': 37,
        'role': 'assistant',
        'content': 'Old saved context',
      });
      final controller = GatewayTurnApplicationController();
      try {
        await _mount(tester, wire, controller, textScale: 1.7);
        await widgetUntil(
          tester,
          () => find.text('Saved history').evaluate().isNotEmpty,
        );
        final screen = tester.state(find.byType(ChatScreen));
        final route = ModalRoute.of(tester.element(find.byType(ChatScreen)));
        final scroll = tester
            .widget<ListView>(find.byType(ListView).first)
            .controller!;
        expect(
          tester
              .getSemantics(find.text('Saved history'))
              .flagsCollection
              .isHeader,
          isTrue,
        );
        await tester.enterText(find.byType(TextField), 'Prompt');
        await tester.tap(find.byTooltip('Send'));
        await widgetUntil(tester, () => wire.prompts.length == 1);
        wire.event('reasoning.delta', {
          'text': 'Inspect reasoning',
        }, turnId: 'wire-1');
        wire.event('tool.start', {
          'tool': 'read_file',
          'tool_id': 'tool-id',
        }, turnId: 'wire-1');
        wire.event('message.delta', {
          'text': 'Current received answer',
        }, turnId: 'wire-1');
        await widgetUntil(
          tester,
          () => find.byType(GatewayReasoningCard).evaluate().isNotEmpty,
        );
        scroll.jumpTo(0);
        await tester.pump();
        expect(find.text('Local prompt context'), findsOneWidget);
        final heading = find.text(
          'Received output — match to saved history unconfirmed',
        );
        expect(heading, findsNothing);
        expect(
          find.text(
            'This may also appear in saved history. The app cannot confirm a match.',
          ),
          findsNothing,
        );
        expect(find.text('Received · match unconfirmed'), findsWidgets);
        expect(find.byType(ListView), findsOneWidget);
        final reason = inChatSource(
          find.byType(GatewayReasoningCard),
          ChatDisplaySource.received,
        );
        final tool = inChatSource(
          find.byType(GatewayActivityCard),
          ChatDisplaySource.received,
        );
        await tester.ensureVisible(reason);
        if (tester
            .widget<ExpansionTile>(
              find.descendant(of: reason, matching: find.byType(ExpansionTile)),
            )
            .controller!
            .isExpanded) {
          await tester.tap(
            find.descendant(of: reason, matching: find.text('Reasoning')),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.tap(
          find.descendant(of: reason, matching: find.text('Reasoning')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(tool);
        if (tester
            .widget<ExpansionTile>(
              find.descendant(of: tool, matching: find.byType(ExpansionTile)),
            )
            .controller!
            .isExpanded) {
          await tester.tap(
            find.descendant(of: tool, matching: find.text('Tool activity')),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.tap(
          find.descendant(of: tool, matching: find.text('Tool activity')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final reasonState = tester.state(reason);
        final toolState = tester.state(tool);
        final reasonKey = tester.widget(reason).key;
        final toolKey = tester.widget(tool).key;
        final reasonController = tester
            .widget<ExpansionTile>(
              find.descendant(of: reason, matching: find.byType(ExpansionTile)),
            )
            .controller!;
        final toolController = tester
            .widget<ExpansionTile>(
              find.descendant(of: tool, matching: find.byType(ExpansionTile)),
            )
            .controller!;
        expect(reasonController.isExpanded, isTrue);
        expect(toolController.isExpanded, isTrue);
        await tester.enterText(find.byType(TextField), 'Keep draft');
        final composer = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        composer.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 6,
        );
        final draft = composer.value;
        wire.rows.addAll([
          {'id': 100, 'role': 'user', 'content': 'Prompt'},
          {'id': 101, 'role': 'assistant', 'content': 'Unrelated saved answer'},
        ]);
        wire.running = false;
        wire.event('tool.complete', {
          'tool': 'read_file',
          'tool_id': 'tool-id',
          'status': 'completed',
        }, turnId: 'wire-1');
        wire.event('message.complete', {
          'text': 'Current received answer',
        }, turnId: 'wire-1');
        wire.event('turn.end', {}, turnId: 'wire-1');
        final owner = controller
            .normalSessionFor(wire.connection)
            .findChat('stored')!;
        await widgetUntil(
          tester,
          () =>
              !owner.snapshot.hasActiveTurn &&
              owner.snapshot.historyRows.length == 3,
        );
        await tester.pump();
        expect(tester.state(find.byType(ChatScreen)), same(screen));
        expect(
          ModalRoute.of(tester.element(find.byType(ChatScreen))),
          same(route),
        );
        expect(
          tester.widget<ListView>(find.byType(ListView).first).controller,
          same(scroll),
        );
        expect(composer.value, draft);
        expect(tester.widget(reason).key, reasonKey);
        expect(tester.widget(tool).key, toolKey);
        expect(tester.state(reason), same(reasonState));
        expect(tester.state(tool), same(toolState));
        expect(
          tester
              .widget<ExpansionTile>(
                find.descendant(
                  of: reason,
                  matching: find.byType(ExpansionTile),
                ),
              )
              .controller,
          same(reasonController),
        );
        expect(
          tester
              .widget<ExpansionTile>(
                find.descendant(of: tool, matching: find.byType(ExpansionTile)),
              )
              .controller,
          same(toolController),
        );
        expect(reasonController.isExpanded, isTrue);
        expect(toolController.isExpanded, isTrue);
        await tester.scrollUntilVisible(
          inChatSource(
            find.text('Unrelated saved answer'),
            ChatDisplaySource.canonical,
          ),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          inChatSource(
            find.text('Unrelated saved answer'),
            ChatDisplaySource.canonical,
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          inChatSource(
            find.text('Current received answer'),
            ChatDisplaySource.received,
          ),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          inChatSource(
            find.text('Current received answer'),
            ChatDisplaySource.received,
          ),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Chat actions').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Export / share').hitTestable());
        await tester.pumpAndSettle();
        expect(shared, hasLength(1));
        expect(shared.single, contains('## Saved history'));
        expect(
          shared.single,
          contains('## Received output — match to saved history unconfirmed'),
        );
        expect(shared.single, contains('Local prompt context'));
        expect(
          shared.single.indexOf('Unrelated saved answer'),
          lessThan(shared.single.indexOf('Current received answer')),
        );
        expect(shared.single, contains('Inspect reasoning'));
        expect(spoken, isEmpty);
        expect(wire.prompts, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.close();
        await tester.runAsync(wire.close);
        await tester.pump(const Duration(seconds: 16));
        semantics.dispose();
      }
    });
  }

  for (final width in [400.0, 1000.0]) {
    for (final mode in ['loading', '404', '500']) {
      testWidgets(
        'POLICY usable received survives empty saved $mode at $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1400));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final wire = (await tester.runAsync(_AvailabilityServer.start))!;
          wire.creates = 1;
          final controller = GatewayTurnApplicationController();
          try {
            await _mount(tester, wire, controller);
            await tester.enterText(find.byType(TextField), 'Prompt');
            await tester.tap(find.byTooltip('Send'));
            await widgetUntil(tester, () => wire.prompts.length == 1);
            wire.event('message.delta', {
              'text': 'Usable received',
            }, turnId: 'wire-1');
            wire.running = false;
            wire.event('message.complete', {
              'text': 'Usable received',
            }, turnId: 'wire-1');
            wire.event('turn.end', {}, turnId: 'wire-1');
            final owner = controller
                .normalSessionFor(wire.connection)
                .findChat('stored')!;
            await widgetUntil(tester, () => !owner.snapshot.hasActiveTurn);
            await tester.pump();
            expect(owner.snapshot.historyRows, isEmpty);
            wire.mode = mode;
            await tester.tap(find.byTooltip('Chat actions').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Refresh').hitTestable());
            await widgetUntil(tester, () => wire.entered.isCompleted);
            await tester.pump();
            expect(
              inChatSource(
                find.text('Usable received'),
                ChatDisplaySource.received,
              ),
              findsOneWidget,
            );
            expect(find.text('Received · match unconfirmed'), findsOneWidget);
            expect(find.text('Saved history'), findsNothing);
            expect(find.byType(ListView), findsOneWidget);
            expect(wire.prompts, hasLength(1));
            expect(tester.takeException(), isNull);
          } finally {
            wire.release();
            await tester.pumpWidget(const SizedBox.shrink());
            await controller.close();
            await tester.runAsync(wire.close);
            await tester.pump(const Duration(seconds: 16));
          }
        },
      );
    }
  }

  testWidgets(
    'POLICY repeated saved rows and source labels do not add unread received work',
    (tester) async {
      final wire = (await tester.runAsync(BindingServer.start))!;
      wire.creates = 1;
      wire.rows.addAll([
        for (var id = 1; id <= 30; id++)
          {
            'id': id,
            'role': id.isOdd ? 'user' : 'assistant',
            'content': 'History $id',
          },
      ]);
      final controller = GatewayTurnApplicationController();
      try {
        await _mount(tester, wire, controller);
        final owner = controller
            .normalSessionFor(wire.connection)
            .findChat('stored')!;
        await widgetUntil(
          tester,
          () => owner.snapshot.historyRows.length == 30,
        );
        await tester.pumpAndSettle();
        final list = find.byType(ListView).first;
        final scroll = tester.widget<ListView>(list).controller!;
        await tester.drag(list, const Offset(0, 600));
        await tester.pumpAndSettle();
        scroll.jumpTo(80);
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Unread prompt');
        await tester.tap(find.byTooltip('Send'));
        await widgetUntil(tester, () => wire.prompts.length == 1);
        wire.event('message.delta', {
          'text': 'Received unread',
        }, turnId: 'wire-1');
        await widgetUntil(
          tester,
          () => find.text('1 new').evaluate().isNotEmpty,
        );
        wire.rows.addAll([
          {'id': 100, 'role': 'user', 'content': 'Unread prompt'},
          {'id': 101, 'role': 'assistant', 'content': 'Received unread'},
          {'id': 103, 'role': 'assistant', 'content': 'Foreign saved'},
        ]);
        wire.running = false;
        wire.event('message.complete', {
          'text': 'Received unread',
        }, turnId: 'wire-1');
        wire.event('turn.end', {}, turnId: 'wire-1');
        await widgetUntil(tester, () => !owner.snapshot.hasActiveTurn);
        owner.observeHistory(wire.rows);
        owner.observeHistory(wire.rows);
        await tester.pump();
        expect(find.text('1 new'), findsOneWidget);
        expect(wire.prompts, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.close();
        await tester.runAsync(wire.close);
        await tester.pump(const Duration(seconds: 16));
      }
    },
  );

  testWidgets(
    'POLICY current-owned voice completion is once, not latest saved text',
    (tester) async {
      final wire = (await tester.runAsync(BindingServer.start))!;
      wire.creates = 1;
      final controller = GatewayTurnApplicationController();
      try {
        await _mount(tester, wire, controller);
        await widgetUntil(
          tester,
          () => !tester.widget<TextField>(find.byType(TextField)).readOnly,
        );
        await tester.enterText(find.byType(TextField), 'Voice prompt');
        // Widened existing send tearoff: normal Send currently uses its default
        // speakResponse=false. No production voice gesture is claimed here.
        final dynamic send = tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed;
        send(speakResponse: true);
        await widgetUntil(tester, () => wire.prompts.length == 1);
        wire.event('message.delta', {
          'text': 'Current spoken answer',
        }, turnId: 'wire-1');
        wire.rows.addAll([
          {'id': 100, 'role': 'user', 'content': 'Other prompt'},
          {'id': 101, 'role': 'assistant', 'content': 'Foreign saved answer'},
        ]);
        wire.running = false;
        wire.event('message.complete', {
          'text': 'Current spoken answer',
        }, turnId: 'wire-1');
        wire.event('turn.end', {}, turnId: 'wire-1');
        final owner = controller
            .normalSessionFor(wire.connection)
            .findChat('stored')!;
        await widgetUntil(tester, () => !owner.snapshot.hasActiveTurn);
        await tester.pump();
        owner.observeHistory(wire.rows);
        owner.observeHistory(wire.rows);
        await tester.pump();
        expect(spoken, ['Current spoken answer']);
        expect(speechCompletions, hasLength(1));
        speechCompletions.single.complete(1);
        await tester.pump();
        owner.observeHistory(wire.rows);
        await tester.pump();
        expect(spoken, ['Current spoken answer']);
        expect(wire.prompts, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.close();
        await tester.runAsync(wire.close);
        await tester.pump(const Duration(seconds: 16));
      }
    },
  );
}

class _AvailabilityServer extends BindingServer {
  _AvailabilityServer(super.server);
  String? mode;
  final entered = Completer<void>();
  final held = Completer<void>();
  static Future<_AvailabilityServer> start() async {
    final wire = _AvailabilityServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    wire.server.listen(wire.handle);
    return wire;
  }

  void release() {
    if (!held.isCompleted) held.complete();
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (mode != null && request.uri.path.endsWith('/messages')) {
      if (!entered.isCompleted) entered.complete();
      if (mode == 'loading') await held.future;
      request.response.statusCode = mode == '404'
          ? 404
          : mode == '500'
          ? 500
          : 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': []}));
      await request.response.close();
      return;
    }
    await super.handle(request);
  }
}

Future<void> _mount(
  WidgetTester tester,
  BindingServer wire,
  GatewayTurnApplicationController controller, {
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: ChatScreen(
      connection: wire.connection,
      session: const Session(
        id: 'stored',
        title: 'Policy',
        model: 'fixture',
        source: 'test',
        messageCount: 0,
        isActive: false,
        preview: '',
        startedAt: 1,
      ),
      turnApplicationController: controller,
      testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
    ),
  ),
);
