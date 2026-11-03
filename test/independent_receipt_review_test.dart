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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'receipt handoff on sibling route preserves prompt on retained route',
    (tester) async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previous);
      SharedPreferences.setMockInitialValues({'verbose_mode': false});
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gateway = (await tester.runAsync(_HeldContextServer.start))!;
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      addTearDown(() => tester.runAsync(gateway.close));
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
      final navigator = GlobalKey<NavigatorState>();
      Widget screen() => ChatScreen(
        connection: gateway.connection,
        session: Session(
          id: 'stored',
          title: 'Receipt concurrency',
          model: 'fixture',
          source: 'test',
          messageCount: gateway.rows.length,
          isActive: false,
          preview: '',
          startedAt: 1,
        ),
        turnApplicationController: controller,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen(),
        ),
      );
      await widgetUntil(tester, () => gateway.historyReads > 0);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Current prompt');
      await widgetUntil(
        tester,
        () =>
            tester
                .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
                .onPressed !=
            null,
      );
      await tester.tap(find.byTooltip('Send').hitTestable());
      await widgetUntil(tester, () => gateway.prompts.length == 1);
      final owner = controller
          .normalSessionFor(gateway.connection)
          .findChat('stored')!;
      gateway.event('message.start', {}, turnId: 'wire-1');
      gateway.event('message.delta', {
        'text': 'Final answer',
      }, turnId: 'wire-1');
      await widgetUntil(
        tester,
        () => owner.snapshot.displayRows.any(
          (row) => row['content'] == 'Final answer',
        ),
      );
      final committed = <Map<String, dynamic>>[
        {'id': 3, 'role': 'user', 'content': 'Current prompt'},
        for (var id = 4; id < 70; id++)
          {
            'id': id,
            'role': 'tool',
            'tool_call_id': 'tool-$id',
            'content': 'Result $id',
          },
        {
          'id': 70,
          'role': 'assistant',
          'content': 'Final answer',
          'status': 'completed',
        },
      ];
      gateway.rows.addAll(committed);
      gateway.running = false;
      gateway.event('message.complete', {
        'text': 'Final answer',
        'status': 'complete',
        'persisted_turn': {
          'complete': true,
          'row_ids': [for (final row in committed) row['id']],
          'user_row_id': 3,
          'final_assistant_row_id': 70,
        },
      }, turnId: 'wire-1');
      gateway.event('turn.end', {'status': 'completed'}, turnId: 'wire-1');
      await widgetUntil(tester, () => gateway.heldOlder.isCompleted);
      expect(owner.snapshot.displayRows, isNotEmpty);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => screen()),
        ),
      );
      await widgetUntil(tester, () => owner.snapshot.displayRows.isEmpty);
      await tester.pumpAndSettle();
      expect(
        _bubbles(tester),
        contains('Current prompt'),
        reason: 'sibling with its own context should be complete',
      );
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      gateway.releaseOlder.complete();
      await widgetUntil(tester, () => gateway.heldOlderReturned);
      await tester.pumpAndSettle();
      final retainedRoute = _bubbles(tester);
      debugPrint(
        'RETAINED_ROUTE_BUBBLES=$retainedRoute; historyReads=${gateway.historyReads}; offsets=${gateway.offsets}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.close();
      await tester.runAsync(gateway.close);
      await tester.pump(const Duration(seconds: 16));
      expect(
        retainedRoute,
        contains('Current prompt'),
        reason:
            'handoff must preserve the prompt on every still-mounted owner subscriber',
      );
    },
  );
}

List<String> _bubbles(WidgetTester tester) => tester
    .widgetList<MessageBubble>(find.byType(MessageBubble))
    .map((bubble) => bubble.content)
    .toList();

class _HeldContextServer extends BindingServer {
  _HeldContextServer(super.server);
  int historyReads = 0;
  final offsets = <int>[];
  final heldOlder = Completer<void>();
  final releaseOlder = Completer<void>();
  bool heldOlderReturned = false;

  static Future<_HeldContextServer> start() async {
    final fixture = _HeldContextServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen(fixture.handle);
    return fixture;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (!request.uri.path.endsWith('/messages')) return super.handle(request);
    historyReads++;
    final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
    final limit = int.parse(request.uri.queryParameters['limit'] ?? '50');
    offsets.add(offset);
    final end = (rows.length - offset).clamp(0, rows.length);
    final start = (end - limit).clamp(0, end);
    final body = jsonEncode({'data': rows.sublist(start, end)});
    final held = offset == 50 && !heldOlder.isCompleted;
    if (held) {
      heldOlder.complete();
      await releaseOlder.future;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
    if (held) heldOlderReturned = true;
  }

  @override
  Future<void> close() async {
    if (!releaseOlder.isCompleted) releaseOlder.complete();
    await super.close();
  }
}
