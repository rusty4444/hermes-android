// Regression: stock-idle success settlement policy.
//
// Derived from normal_gateway_fresh_chat_test.dart at reviewed commit
// 20fbe573ed82405097f062ebdb4dd76730fb3fd2. Sole difference under test: the
// authoritative resume seam reports stock `idle` (running=false) instead of
// `completed` after a successful stock message.complete receipt.
//
// Policy: an owned successful message.complete plus authoritative idle and a
// fresh displayable response row above the turn floor settles success. It is
// deliberately narrower than "idle means success": without the wire receipt
// (lost/interrupted terminal) idle must still settle unknown — covered by
// normal_gateway_review_regression_test.dart and chat_verbose_mode_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/unreconciled_policy.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

void main() {
  testWidgets(
    'successful stock completion followed by resumed idle shows no unknown-outcome warning',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({'verbose_mode': true});
      final connection = SavedConnection(
        id: 'lab-stock-idle-probe',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture',
      );
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final rpc = Completer<void>();
      StreamCallback? event;
      var submits = 0;
      final baseline = Completer<http.Response>();
      var rows = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(
            connection: connection,
            session: Session(
              id: 'mob-lab-idle-chat',
              title: 'New chat',
              model: 'fixture',
              source: 'test',
              messageCount: 0,
              isActive: true,
              preview: '',
              startedAt: 1,
              isLocalDraft: true,
            ),
            turnApplicationController: controller,
            testApiClient: ApiClient(
              baseUrl: connection.baseUrl,
              apiKey: 'fixture',
              httpClient: MockClient((request) async {
                if (!request.url.path.endsWith('/messages')) {
                  return http.Response(
                    jsonEncode({
                      'session': {'id': 'stored-lab-idle-chat'},
                    }),
                    200,
                  );
                }
                if (request.url.path.contains('/mob-lab-idle-chat/')) {
                  return http.Response('{"error":"session not found"}', 404);
                }
                if (!baseline.isCompleted) return baseline.future;
                return http.Response(jsonEncode({'data': rows}), 200);
              }),
            ),
            testRemotePromptSubmit:
                ({
                  required sessionId,
                  required text,
                  required onEvent,
                  required onSent,
                }) async {
              submits++;
              event = onEvent;
              onSent();
              return rpc.future;
            },
            // Sole difference from the reviewed fresh-chat control: stock
            // resume reports idle after the turn, not completed.
            testNormalResume:
                ({required localSessionId, required storedSessionId}) async =>
                    const ResumedGatewaySession(
                      runtimeSessionId: 'runtime',
                      running: false,
                      status: 'idle',
                    ),
            testStoredSessionKey: (_) => 'stored-lab-idle-chat',
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'First prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      baseline.complete(http.Response('{"data":[]}', 200));
      await tester.pump();
      await tester.pump();
      expect(submits, 1);
      void emit(String type, Map<String, dynamic> data) =>
          event!(StreamEvent(type: type, data: data));
      emit('message.start', {});
      emit('message.delta', {'text': 'Final answer'});
      rows = [
        {'id': 1, 'role': 'user', 'content': 'First prompt'},
        {'id': 2, 'role': 'assistant', 'content': 'Final answer'},
      ];
      emit('message.complete', {'text': 'Final answer', 'status': 'complete'});
      rpc.complete();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      final session = controller.normalSessionFor(connection);
      final owner = session.findChat('stored-lab-idle-chat')!;
      // The persistent unknown-outcome warning must not appear for a
      // successfully received stock reply confirmed by authoritative idle.
      expect(
        find.text(
          'The gateway is idle. The previous turn’s outcome could not be confirmed.',
        ),
        findsNothing,
      );
      expect(owner.snapshot.phase, NormalGatewayTurnPhase.completed);
      final active = owner.snapshot.hasActiveTurn;
      expect(active, isFalse);
      for (final source in [
        ChatDisplaySource.canonical,
        ChatDisplaySource.received,
      ]) {
        expect(inChatSource(find.text('Final answer'), source), findsOneWidget);
        expect(inChatSource(find.text('First prompt'), source), findsOneWidget);
      }
      expect(find.byTooltip('Stop response'), findsNothing);
      expect(owner.snapshot.rowFloor, 0);
      expect(await session.pendingStore.load(session.scope), isEmpty);
      expect(submits, 1);
    },
  );
}
