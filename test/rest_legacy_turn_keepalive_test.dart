// Regression tests for issue #225: an API-server (REST SSE) send must
// register as app-wide turn activity so Settings → Background work can
// engage the foreground service on the stock-gateway transport. Before
// this fix the only writers of stock-turn activity
// (beginLegacyTurn/endLegacyTurn) had no production caller and REST sends
// never registered, so the keep-alive was a no-op on exactly the transport
// the app ships against.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

void main() {
  setUp(mockChatImageRecovery);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'REST send registers app-wide turn activity until the stream settles',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(() async {
        await controller.close();
      });
      final client = _SseClient();
      await _pumpApiChat(tester, controller, client, 'settle');
      await tester.enterText(find.byType(TextField), 'Long REST turn');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await client.started.future;
      expect(
        controller.hasActiveTurn,
        isTrue,
        reason:
            'a stock-gateway API-server send must register as turn '
            'activity while the SSE stream is in flight (issue #225)',
      );
      client.emit('${_token('A')}data: [DONE]\n\n');
      await pumpChatUpdates(tester);
      expect(controller.hasActiveTurn, isFalse);
      await _teardown(tester, client);
    },
  );

  testWidgets('mid-turn SSE disconnect releases the REST turn registration', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    addTearDown(controller.close);
    final client = _SseClient();
    await _pumpApiChat(tester, controller, client, 'drop');
    await tester.enterText(find.byType(TextField), 'Interrupted REST turn');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await client.started.future;
    expect(controller.hasActiveTurn, isTrue);
    // The issue's exact failure: the server reads the dropped socket as an
    // interrupt and the client reports "Connection closed while receiving
    // data". The registration must be released by the same settle.
    client.stream.addError(
      http.ClientException('Connection closed while receiving data'),
    );
    client.stream.close();
    await pumpChatUpdates(tester);
    expect(controller.hasActiveTurn, isFalse);
    // The rejected send restores the draft rather than losing the prompt.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Interrupted REST turn',
    );
    await _teardown(tester, client);
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

Future<void> _pumpApiChat(
  WidgetTester tester,
  GatewayTurnApplicationController controller,
  _SseClient client,
  String id,
) async {
  final connection = SavedConnection(
    id: 'rest-keepalive-$id',
    label: 'Fixture',
    host: 'fixture.invalid',
    port: 8642,
    apiKey: 'fixture-key',
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
          apiKey: 'fixture-key',
          httpClient: client,
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester, _SseClient client) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Emit the protocol terminal before closing, mirroring the retention
  // harness: a producer that closes without its [DONE] frame leaves the
  // fake-async pump unable to settle after the screen is disposed. The
  // disconnect test already closed its stream with the error event.
  if (!client.stream.isClosed) {
    client.stream
      ..add(utf8.encode('data: [DONE]\n\n'))
      ..close();
  }
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
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
