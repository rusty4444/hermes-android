import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/chat_message_time.dart';
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
  setUp(mockChatImageRecovery);
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': true}));

  testWidgets('SSE message times survive updates and empty history refresh', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = await _start(tester, 'message-times');
    final user = _rows(
      tester,
    ).whereType<MessageBubble>().singleWhere((b) => b.isUser);
    final sent = ChatMessageTime.fromRow(user.metadata)!;
    expect(sent.source, ChatMessageTimeSource.sent);
    client.emit(
      _token('A') + _tool('timestamp-tool', 'completed') + _token('B'),
    );
    await tester.pump();
    final received = _rows(tester).whereType<MessageBubble>().last;
    final at = ChatMessageTime.fromRow(received.metadata)!;
    expect(at.source, ChatMessageTimeSource.received);
    expect(
      find.byKey(const Key('message-timestamp')),
      findsOneWidget,
      reason: 'the partial assistant must not show a footer',
    );
    // A long tool turn remains alive via the producer's SSE keepalive contract,
    // not five minutes of body silence (which must now fail as stalled).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 30));
      client.emit(': keepalive\n\n');
      await tester.pump();
    }
    client.emit('${_token('C')}data: [DONE]\n\n');
    await pumpChatUpdates(tester);
    final completed = _rows(tester).whereType<MessageBubble>().last;
    expect(ChatMessageTime.fromRow(completed.metadata)!.at, at.at);
    expect(completed.metadata['_chat_response_complete'], isTrue);
    expect(
      find.byKey(const Key('message-timestamp')),
      findsNWidgets(2),
      reason:
          'one user footer and one final assistant footer, not per text run',
    );
    expect(
      ChatMessageTime.fromRow(
        _rows(tester).whereType<MessageBubble>().first.metadata,
      )!.at,
      sent.at,
    );
    await _finish(tester, client);
  });

  testWidgets('QUALITY SSE retained presentation obeys 1024-run bound', (
    tester,
  ) async {
    final client = await _start(tester, 'run-bound');
    final frames = StringBuffer();
    for (var i = 0; i < 520; i++) {
      frames.write(_token('x'));
      frames.write(_tool('q-$i', 'completed'));
    }
    client.emit(frames.toString());
    await tester.pump(const Duration(milliseconds: 300));
    final rows = _rows(tester);
    debugPrint(
      'QUALITY SSE retained display rows=${rows.length}; permitted=1024 runs + 1 user',
    );
    expect(rows.length, 1025);
    expect(
      rows.whereType<MessageBubble>().where((b) => b.isUser),
      hasLength(1),
    );
    final tools = rows.whereType<GatewayActivityCard>().expand(
      (c) => c.activities,
    );
    expect(tools.first.toolId, 'q-8');
    expect(tools.last.toolId, 'q-519');
    final retainedKey = rows.last.key;
    // An evicted completion is not a new receipt; retained updates stay put.
    client.emit(_tool('q-0', 'completed') + _tool('q-519', 'completed'));
    await tester.pump(const Duration(milliseconds: 300));
    final updated = _rows(tester);
    expect(updated.length, 1025);
    expect(updated.last.key, retainedKey);
    expect(
      updated
          .whereType<GatewayActivityCard>()
          .expand((c) => c.activities)
          .any((a) => a.toolId == 'q-0'),
      isFalse,
    );
    await _finish(tester, client);
  });

  testWidgets(
    'SSE text budget applies before render without full assistant fallback',
    (tester) async {
      final client = await _start(tester, 'text-bound');
      client.emit(
        _token('OLD_PREFIX${' ' * 600000}') +
            _tool('separator', 'running') +
            _token('${' ' * 600000}LATEST_SUFFIX'),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final prose = _rows(tester)
          .whereType<MessageBubble>()
          .where((b) => !b.isUser)
          .map((b) => b.content)
          .toList();
      expect(
        prose.fold<int>(0, (n, text) => n + text.length),
        ChatTimeline.maxTextCodeUnits,
      );
      expect(prose.join().contains('OLD_PREFIX'), isFalse);
      expect(prose.last.endsWith('LATEST_SUFFIX'), isTrue);
      client.emit(_token('tail'));
      await tester.pump();
      final next = _rows(tester)
          .whereType<MessageBubble>()
          .where((b) => !b.isUser)
          .map((b) => b.content);
      expect(
        next.fold<int>(0, (n, text) => n + text.length),
        ChatTimeline.maxTextCodeUnits,
      );
      expect(next.last.endsWith('tail'), isTrue);
      await _finish(tester, client);
    },
  );

  testWidgets('SSE retains adjacent groups and card identities', (
    tester,
  ) async {
    final client = await _start(tester, 'groups');
    client.emit(
      _token('A') +
          _tool('t1', 'running') +
          _tool('t2', 'running') +
          _token('B') +
          _tool('t3', 'running') +
          _token('C'),
    );
    await tester.pump();
    final before = _rows(tester);
    expect(
      before.whereType<GatewayActivityCard>().map(
        (c) => c.activities.map((a) => a.toolId).join(','),
      ),
      ['t1,t2', 't3'],
    );
    final keys = before.map((w) => w.key).toList();
    client.emit(_tool('t1', 'completed'));
    await tester.pump();
    final after = _rows(tester);
    expect(after.map((w) => w.key), keys);
    expect(
      after.whereType<GatewayActivityCard>().first.activities.first.isTerminal,
      isTrue,
    );
    await _finish(tester, client);
  });
}

String _token(String text) =>
    'data: ${jsonEncode({
      'choices': [
        {
          'delta': {'content': text},
        },
      ],
    })}\n\n';
String _tool(String id, String status) =>
    'event: hermes.tool.progress\ndata: ${jsonEncode({'tool': 'terminal', 'toolCallId': id, 'status': status})}\n\n';

// Inspect the production ListView delegate, including lazy off-screen rows.
List<Widget> _rows(WidgetTester tester) {
  final finder = find.byType(ListView).first;
  final list = tester.widget<ListView>(finder);
  final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
  final context = tester.element(finder);
  return [
    for (var i = 0; i < delegate.childCount!; i++)
      delegate.builder(context, i)!,
  ];
}

Future<_SseClient> _start(WidgetTester tester, String id) async {
  final controller = GatewayTurnApplicationController();
  addTearDown(controller.close);
  final client = _SseClient();
  final connection = SavedConnection(
    id: 'sse-$id',
    label: 'Fixture',
    host: 'fixture.invalid',
    port: 8642,
    apiKey: 'fixture',
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: connection,
        session: Session(
          id: id,
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
          baseUrl: connection.baseUrl,
          apiKey: 'fixture',
          httpClient: client,
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Long tool turn');
  await tester.tap(find.byTooltip('Send'));
  await tester.pump();
  await client.started.future;
  return client;
}

Future<void> _finish(WidgetTester tester, _SseClient client) async {
  await tester.pumpWidget(const SizedBox.shrink());
  client.stream
    ..add(utf8.encode('data: [DONE]\n\n'))
    ..close();
  await pumpChatUpdates(tester);
  expect(client.requests, 1);
}

class _SseClient extends http.BaseClient {
  final started = Completer<void>();
  final stream = StreamController<List<int>>();
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST') {
      requests++;
      started.complete();
      return http.StreamedResponse(
        stream.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"data":[]}')),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  void emit(String frames) => stream.add(utf8.encode(frames));
}
