// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_unknown_floor_route_test.dart
// Base 4a53e32 blob be33f661499f257c2542a027ce6fbb91a1a52096; SHA256 28b6bbeca4ae016fab22f9773ed61069cacd284d347f3e056a95274ebef335af.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
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
  // These assertions concern independent source/admission authority. Verbose
  // exposes metadata-free saved rows without claiming quiet final evidence.
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': true}));

  for (final mode in [
    'stored-held-initial',
    'local-initial-404',
    'known-empty-control',
    'known-context-unknown-floor',
  ]) {
    testWidgets(
      'canonical hydration does not duplicate materialized reply: $mode',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final first = Completer<http.Response>();
        final rpc = Completer<void>();
        late StreamCallback emit;
        var submissions = 0;
        final requests = <String>[];
        final connection = SavedConnection(
          id: 'unknown-floor-$mode',
          label: 'Fixture',
          host: 'fixture.invalid',
          port: 8642,
          apiKey: 'fixture-key',
        );
        const canonical = [
          {'id': 1, 'role': 'user', 'content': 'Early prompt'},
          {'id': 2, 'role': 'assistant', 'content': 'Early answer'},
        ];
        final client = ApiClient(
          baseUrl: connection.baseUrl,
          apiKey: connection.apiKey,
          httpClient: MockClient((request) async {
            if (request.url.path == '/api/sessions/stored-chat') {
              return http.Response(
                jsonEncode({
                  'session': {'id': 'stored-chat', 'archived': false},
                }),
                200,
              );
            }
            requests.add(request.url.toString());
            if (requests.length == 1) {
              if (mode == 'stored-held-initial') return first.future;
              if (mode == 'local-initial-404') {
                return http.Response('not found', 404);
              }
              if (mode == 'known-context-unknown-floor') {
                return http.Response(
                  jsonEncode({
                    'data': [
                      {
                        'id': 'legacy',
                        'role': 'assistant',
                        'content': 'Older known context',
                      },
                    ],
                  }),
                  200,
                );
              }
              return http.Response(jsonEncode({'data': []}), 200);
            }
            if (submissions == 0 &&
                const {
                  'stored-held-initial',
                  'local-initial-404',
                }.contains(mode)) {
              return http.Response('admission unavailable', 503);
            }
            return http.Response(jsonEncode({'data': canonical}), 200);
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatScreen(
              connection: connection,
              session: Session(
                id: mode == 'local-initial-404' ? 'local-draft' : 'stored-chat',
                title: 'Early chat',
                model: 'fixture',
                source: 'test',
                messageCount: 0,
                isActive: false,
                preview: '',
                startedAt: 1,
                isLocalDraft: mode == 'local-initial-404',
              ),
              turnApplicationController: controller,
              testApiClient: client,
              testStoredSessionKey: (_) => 'stored-chat',
              testRemotePromptSubmit:
                  ({
                    required sessionId,
                    required text,
                    required onEvent,
                    required onSent,
                  }) {
                    submissions++;
                    emit = onEvent;
                    onSent();
                    return rpc.future;
                  },
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        expect(requests, hasLength(1));
        await tester.enterText(find.byType(TextField), 'Early prompt');
        await tester.tap(find.byTooltip('Send'));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final owner = controller
            .normalSessionFor(connection)
            .findChat('stored-chat')!;
        expect(submissions, 1);
        expect(
          owner.snapshot.rowFloor,
          mode == 'known-empty-control' ? 0 : isNull,
        );
        emit(
          StreamEvent(
            type: 'message.delta',
            data: {'text': 'Early answer'},
            turnId: 'owned-turn',
          ),
        );
        await tester.pump();
        emit(
          StreamEvent(
            type: 'message.complete',
            data: {'text': 'Early answer'},
            turnId: 'owned-turn',
          ),
        );
        emit(
          StreamEvent(
            type: 'turn.end',
            data: const {'status': 'completed'},
            turnId: 'owned-turn',
          ),
        );
        rpc.complete();
        for (var i = 0; i < 10; i++) {
          await tester.pump();
        }
        expect(owner.phase, NormalGatewayTurnPhase.completed);
        expect(owner.snapshot.historyRows, canonical);
        if (!first.isCompleted) {
          first.complete(http.Response(jsonEncode({'data': []}), 200));
        }
        await tester.pumpAndSettle();
        final bubbles = tester
            .widgetList<MessageBubble>(
              inChatSource(
                find.byType(MessageBubble),
                ChatDisplaySource.received,
              ),
            )
            .map(
              (b) => {
                'role': b.isUser ? 'user' : 'assistant',
                'content': b.content,
              },
            )
            .toList();

        expect(owner.snapshot.historyRows, canonical);
        expect(
          tester
              .widgetList<MessageBubble>(
                inChatSource(
                  find.byType(MessageBubble),
                  ChatDisplaySource.canonical,
                ),
              )
              .map((b) => b.content),
          ['Early prompt', 'Early answer'],
        );
        if (mode == 'known-context-unknown-floor') {
          expect(
            bubbles.where((b) => b['content'] == 'Older known context'),
            isEmpty,
          );
          expect(owner.snapshot.historyRows, canonical);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          bubbles.where(
            (b) => b['role'] == 'user' && b['content'] == 'Early prompt',
          ),
          hasLength(1),
        );
        expect(
          bubbles.where(
            (b) => b['role'] == 'assistant' && b['content'] == 'Early answer',
          ),
          hasLength(1),
        );
      },
    );
  }
}
