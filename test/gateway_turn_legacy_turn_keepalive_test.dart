// Reviewer finding (stock gateway): the keep-alive must follow the turns a
// stock gateway actually runs. Stock gateways (and every stored chat) submit
// through the legacy `_sendDesktopGatewayMessage` transport and never enter
// the recovery-v2 coordinator, so the app-wide active-turn signal must
// include legacy sends — otherwise backgrounding mid-reply starts no
// foreground service on exactly the gateway the app ships against.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy turn slots drive the app-wide active-turn signal', () async {
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => throw StateError('no recovery session expected'),
    );
    var notifications = 0;
    controller.addTurnActivityListener(() => notifications++);

    expect(controller.hasActiveTurn, isFalse);
    final token = controller.beginLegacyTurn();
    expect(controller.hasActiveTurn, isTrue);
    expect(notifications, greaterThan(0));

    // Two screens may send at once; one settling must not clear the other.
    final second = controller.beginLegacyTurn();
    controller.endLegacyTurn(token);
    expect(controller.hasActiveTurn, isTrue);
    controller.endLegacyTurn(second);
    expect(controller.hasActiveTurn, isFalse);

    // Double-end and foreign tokens must not flip the signal or spam
    // listeners into a spurious start.
    controller.endLegacyTurn(second);
    controller.endLegacyTurn(Object());
    expect(controller.hasActiveTurn, isFalse);

    // Close-interaction contract (reviewer gap): the true→false flip
    // must reach listeners at close (a backgrounded keep-alive gets its
    // stop through the notify path), begin-after-close is inert, and
    // end-after-close never throws.
    final live = controller.beginLegacyTurn();
    expect(controller.hasActiveTurn, isTrue);
    var sawFalseAfterClose = false;
    controller.addTurnActivityListener(
      () =>
          sawFalseAfterClose = sawFalseAfterClose || !controller.hasActiveTurn,
    );
    await controller.close();
    expect(sawFalseAfterClose, isTrue);
    expect(controller.hasActiveTurn, isFalse);
    final inert = controller.beginLegacyTurn();
    expect(controller.hasActiveTurn, isFalse);
    controller.endLegacyTurn(inert);
    controller.endLegacyTurn(live);
    expect(controller.hasActiveTurn, isFalse);
  });

  testWidgets(
    'backgrounding during a stock-gateway send earns the service, settle ends it',
    (tester) async {
      SharedPreferences.setMockInitialValues({'verbose_mode': false});
      // A throwing factory pins the stock path: a legacy send must not
      // open a recovery-v2 session to earn keep-alive.
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) =>
            throw StateError('stock path must not open recovery sessions'),
      );
      final submitGate = Completer<void>();
      var submitted = false;
      var settled = false;
      await _pumpChat(
        tester,
        controller,
        isSettled: () => settled,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              submitted = true;
              await submitGate.future;
              settled = true;
              onEvent(
                StreamEvent(
                  type: 'message.complete',
                  data: const {'text': 'Stock final'},
                ),
              );
            },
      );

      await tester.enterText(find.byType(TextField), 'Long stock turn');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(submitted, isTrue);

      // The turn is in flight on the stock transport: the app-wide signal
      // must see it even though no recovery-v2 session exists.
      expect(controller.hasActiveTurn, isTrue);

      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
            call,
          ) async {
            calls.add(call.method);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ConnectionKeepAliveService.channel, null),
      );
      // Wire exactly like main.dart: the listener recomputes the aggregate.
      final keepAlive = ConnectionKeepAliveService();
      controller.addTurnActivityListener(
        () => keepAlive.onTurnActivityChanged(controller.hasActiveTurn),
      );

      // The reviewer's regression: background during a stock-gateway turn.
      keepAlive.onAppLifecycleState(
        AppLifecycleState.paused,
        hasActiveTurn: controller.hasActiveTurn,
      );
      await tester.pump();
      expect(calls, contains('start'));
      expect(keepAlive.isActive, isTrue);

      // The reply lands while still backgrounded: the service must end
      // then, not wait for resume.
      submitGate.complete();
      await tester.pumpAndSettle();
      expect(controller.hasActiveTurn, isFalse);
      expect(calls, containsAllInOrder(['start', 'stop']));
      expect(keepAlive.isActive, isFalse);
    },
  );

  testWidgets(
    'a post-wire stock-gateway loss remains unresolved while backgrounded',
    (tester) async {
      // A dead socket is not a dead server turn. Keep the active receipt and
      // foreground service until authoritative terminal evidence arrives.
      SharedPreferences.setMockInitialValues({'verbose_mode': false});
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) =>
            throw StateError('stock path must not open recovery sessions'),
      );
      final submitGate = Completer<void>();
      await _pumpChat(
        tester,
        controller,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              await submitGate.future;
            },
      );

      await tester.enterText(find.byType(TextField), 'Doomed stock turn');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(controller.hasActiveTurn, isTrue);

      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
            call,
          ) async {
            calls.add(call.method);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ConnectionKeepAliveService.channel, null),
      );
      final keepAlive = ConnectionKeepAliveService();
      controller.addTurnActivityListener(
        () => keepAlive.onTurnActivityChanged(controller.hasActiveTurn),
      );
      keepAlive.onAppLifecycleState(
        AppLifecycleState.paused,
        hasActiveTurn: controller.hasActiveTurn,
      );
      await tester.pump();
      expect(calls, contains('start'));

      submitGate.completeError(StateError('socket died mid-reply'));
      await tester.pump();
      await tester.pump();
      expect(controller.hasActiveTurn, isTrue);
      expect(calls, isNot(contains('stop')));
      expect(keepAlive.isActive, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.close();
      await tester.pump();
    },
  );
}

Future<void> _pumpChat(
  WidgetTester tester,
  GatewayTurnApplicationController controller, {
  required TestRemotePromptSubmit remoteSubmit,
  bool Function()? isSettled,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://legacy.fixture',
    apiKey: 'legacy-key',
    httpClient: _EmptyChatHttpClient(isSettled),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'legacy-fixture',
          label: 'Legacy fixture',
          host: 'legacy.fixture',
          port: 8642,
          apiKey: 'legacy-key',
        ),
        session: const Session(
          id: 'legacy-session',
          title: 'Legacy chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        turnApplicationController: controller,
        testApiClient: apiClient,
        testRemotePromptSubmit: remoteSubmit,
        testNormalResume:
            ({required localSessionId, required storedSessionId}) async =>
                ResumedGatewaySession(
                  runtimeSessionId: 'runtime',
                  running: !(isSettled?.call() ?? false),
                ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _EmptyChatHttpClient extends http.BaseClient {
  final bool Function()? isSettled;
  _EmptyChatHttpClient(this.isSettled);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'data': isSettled?.call() == true
                  ? [
                      {'id': 2, 'role': 'assistant', 'content': 'Stock final'},
                    ]
                  : <Object>[],
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}
