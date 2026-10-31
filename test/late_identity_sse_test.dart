import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_activity.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    mockChatImageRecovery();
  });

  for (final lateId in [false, true]) {
    testWidgets(
      'SSE pre-ID pin follows learned identity into canonical row lateId=$lateId',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final client = _Client();
        await _open(tester, controller, client);
        await _send(tester);
        client.emit(_tool('running', id: lateId ? null : 'hydrated-tool'));
        await tester.pump();
        final first = _activities(tester).single;
        expect(_expanded(tester), isFalse);
        await tester.tap(find.text('Tool activity'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_expanded(tester), isTrue);
        await tester.tap(find.text('Tool activity'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Tool activity'));
        await tester.pump(const Duration(milliseconds: 300));
        client.emit(_tool('progress', id: 'hydrated-tool'));
        await tester.pump();
        expect(_activities(tester).single.identity, first.identity);
        expect(_activities(tester).single.toolId, 'hydrated-tool');
        expect(_expanded(tester), isTrue);
        client.emit(_tool('completed', id: 'hydrated-tool'));
        await tester.pump();
        expect(_expanded(tester), isTrue);
        await client.finish();
        await pumpChatUpdates(tester);
        client.history = [
          {'id': 1, 'role': 'user', 'content': 'One prompt'},
          {
            'id': 2,
            'role': 'tool',
            'tool_call_id': 'hydrated-tool',
            'name': 'terminal',
            'content': 'ok',
          },
          {'id': 3, 'role': 'assistant', 'content': 'Canonical reply'},
        ];
        final originalState = tester.state(find.byType(ChatScreen));
        final requests = client.historyRequests;
        await tester.tap(find.byTooltip('Chat actions').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refresh').hitTestable());
        await tester.pumpAndSettle();
        expect(client.historyRequests, greaterThan(requests));
        expect(
          identical(tester.state(find.byType(ChatScreen)), originalState),
          isTrue,
        );
        expect(_expanded(tester), isTrue);
        expect(find.text('Completed'), findsOneWidget);
        expect(
          tester
              .widget<GatewayActivityCard>(find.byType(GatewayActivityCard))
              .key,
          const ValueKey('tool-activity-message:2'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await _open(tester, controller, client);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester
              .widget<GatewayActivityCard>(find.byType(GatewayActivityCard))
              .key,
          const ValueKey('tool-activity-message:2'),
        );
        expect(_expanded(tester), isFalse);
        expect(find.text('Completed'), findsNothing);
        await tester.tap(find.text('Tool activity'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_expanded(tester), isTrue);
        expect(find.text('Completed'), findsOneWidget);
        expect(_activities(tester).single.toolId, 'hydrated-tool');
        expect(find.text('Canonical reply'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(client.submissions, 1);
      },
    );
  }

  testWidgets(
    'SSE learned durable alias stays evicted in the actual ListView delegate',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final client = _Client();
      await _open(tester, controller, client);
      await _send(tester);
      client.emit(_tool('running') + _tool('progress', id: 'late-id'));
      await tester.pump();
      expect(_activities(tester).single.identity, startsWith('local:'));
      expect(_activities(tester).single.toolId, 'late-id');
      final buffer = StringBuffer();
      for (var i = 0; i < 520; i++) {
        buffer.write(_token('x'));
        buffer.write(_tool('completed', id: 'bulk-$i'));
      }
      client.emit(buffer.toString());
      await tester.pump();
      client.emit(_token('new call') + _tool('running'));
      await tester.pump();
      final before = _rows(tester).map((w) => w.key).toList();
      expect(before.length, 1025);
      expect(_activities(tester).any((a) => a.toolId == 'late-id'), isFalse);
      client.emit(_tool('completed', id: 'late-id'));
      await tester.pump();
      expect(_rows(tester).map((w) => w.key), before);
      expect(_activities(tester).any((a) => a.toolId == 'late-id'), isFalse);
      expect(_activities(tester).last.isTerminal, isFalse);
      expect(_activities(tester).last.toolId, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await client.finish();
      await pumpChatUpdates(tester);
    },
  );

  testWidgets(
    'SSE distinct starts and ambiguous same-name calls do not steal anonymous pins',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final client = _Client();
      await _open(tester, controller, client);
      await _send(tester);
      client.emit(_tool('running'));
      await tester.pump();
      final anonymous = _activities(tester).single.identity;
      await tester.tap(find.text('Tool activity'));
      await tester.pump(const Duration(milliseconds: 300));
      client.emit(_token('separate group') + _tool('running', id: 'unrelated'));
      await tester.pump();
      expect(_activities(tester).length, 2);
      expect(_activities(tester).first.identity, anonymous);
      final cards = _rows(tester).whereType<GatewayActivityCard>().toList();
      expect(cards.first.pinnedExpansion, isTrue);
      expect(cards.last.pinnedExpansion, isNull);
      client.emit(_tool('progress', id: 'ambiguous'));
      await tester.pump();
      expect(_activities(tester).length, 3);
      expect(_activities(tester).first.toolId, isNull);
      expect(
        _rows(tester).whereType<GatewayActivityCard>().last.pinnedExpansion,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await client.finish();
      await pumpChatUpdates(tester);
    },
  );
}

bool _expanded(WidgetTester tester) => tester
    .widget<ExpansionTile>(
      find.descendant(
        of: find.byType(GatewayActivityCard),
        matching: find.byType(ExpansionTile),
      ),
    )
    .controller!
    .isExpanded;
List<Widget> _rows(WidgetTester tester) {
  final finder = find.byType(ListView).first;
  final delegate =
      tester.widget<ListView>(finder).childrenDelegate
          as SliverChildBuilderDelegate;
  return [
    for (var i = 0; i < delegate.childCount!; i++)
      delegate.builder(tester.element(finder), i)!,
  ];
}

// Include off-screen lazy children, not just the visible viewport.
List<GatewayToolActivity> _activities(WidgetTester tester) => _rows(
  tester,
).whereType<GatewayActivityCard>().expand((c) => c.activities).toList();
String _tool(String status, {String? id}) =>
    'event: hermes.tool.progress\ndata: ${jsonEncode({'tool': 'terminal', 'status': status, 'toolCallId': ?id})}\n\n';
String _token(String text) =>
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    })}\n\n';
final _connection = SavedConnection(
  id: 'late-alias-sse',
  label: 'Fixture',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'fixture',
);
Future<void> _open(
  WidgetTester tester,
  GatewayTurnApplicationController controller,
  _Client client,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        key: UniqueKey(),
        connection: _connection,
        session: Session(
          id: 'stored',
          title: 'Fixture',
          model: 'fixture',
          source: 'test',
          messageCount: 0,
          isActive: true,
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
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _send(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'One prompt');
  await tester.tap(find.byTooltip('Send'));
  await tester.pump();
  await tester.pump();
}

class _Client extends http.BaseClient {
  final stream = StreamController<List<int>>();
  List<Map<String, dynamic>> history = [];
  int submissions = 0;
  int historyRequests = 0;
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
    historyRequests++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'data': history}))),
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
