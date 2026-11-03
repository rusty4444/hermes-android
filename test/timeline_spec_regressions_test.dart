// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/timeline_spec_regressions_test.dart
// Base 4a53e32 blob 3a7eee8cc7218a550534e74c7d17f4486e4dcce8; SHA256 22ee8a55e6eb685abc4bb4adb100321829bd4aeb83a588a38b5f654eab50c838.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/completed_stock_turn.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': true}));

  for (final flag in [
    'response_previewed',
    'response_reused',
    'response_transformed',
  ]) {
    testWidgets('SPEC preview keeps append reasoning receipt runs: $flag', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote();
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'One prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      // Use the application-owned global session ingress, not route-local callbacks.
      void emit(String type, Map<String, dynamic> data) => controller
          .normalSessionFor(_connection)
          .receiveEvent('local-chat', StreamEvent(type: type, data: data));
      emit('reasoning.delta', {'text': 'R1'});
      emit('message.delta', {'text': 'A'});
      emit('message.interim', {'text': 'A', 'already_streamed': true});
      emit('tool.start', {'tool': 'read_file', 'tool_id': 't1'});
      emit('reasoning.delta', {'text': 'R2'});
      await tester.pump();
      final before = labels(tester);
      expect(before, ['One prompt', 'reasoning:R1', 'A', 't1', 'reasoning:R2']);
      final keysBefore = tester
          .widgetList<GatewayReasoningCard>(find.byType(GatewayReasoningCard))
          .map((w) => w.key)
          .toList();
      emit('message.complete', {'text': 'A', flag: true});
      remote.rpc.complete();
      await tester.pump();
      await tester.pump();
      final after = labels(tester);
      final keysAfter = tester
          .widgetList<GatewayReasoningCard>(find.byType(GatewayReasoningCard))
          .map((w) => w.key)
          .toList();
      debugPrint(
        'SPEC append reasoning $flag before=$before after=$after keysBefore=$keysBefore keysAfter=$keysAfter',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        after,
        before,
        reason:
            'Completion may reassign scope but must not move or merge append-mode reasoning across a tool/text run.',
      );
      expect(keysAfter, keysBefore);
    });
  }

  testWidgets(
    'SPEC latest route hydration clears completed optimistic presentation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote();
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'One prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      remote.event('message.delta', {'text': 'Wire reply'});
      remote.event('tool.start', {
        'tool': 'read_file',
        'tool_id': 'optimistic-only',
      });
      remote.event('message.complete', {'text': 'Wire reply'});
      remote.rpc.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(controller.hasActiveTurn, isFalse);
      final before = labels(tester);
      expect(before, ['One prompt', 'Wire reply', 'optimistic-only']);
      // The immediate post-completion GET is allowed to lag persistence. A later
      // successful latest route fetch must nevertheless become authoritative.
      final requestsBeforeReopen = remote.historyRequests;
      remote.history = [
        {'id': 1, 'role': 'user', 'content': 'One prompt'},
        {'id': 2, 'role': 'assistant', 'content': 'Canonical reply'},
      ];
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _open(
        tester,
        controller,
        remote,
        id: 'stored-chat',
        key: const ValueKey('canonical-reopen'),
      );
      await tester.pump();
      await tester.pump();
      final after = labels(tester);
      final owner = controller
          .normalSessionFor(_connection)
          .findChat('stored-chat')!;
      debugPrint(
        'SPEC latest hydration requests=$requestsBeforeReopen -> ${remote.historyRequests} after=$after ownerHistory=${owner.snapshot.historyRows} ownerDisplay=${owner.snapshot.displayRows}',
      );
      expect(remote.historyRequests, greaterThan(requestsBeforeReopen));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        after,
        [
          'One prompt',
          'Canonical reply',
          'One prompt',
          'Wire reply',
          'optimistic-only',
        ],
        reason:
            'Full C precedes R; a later saved reply cannot prove materialized R can retire.',
      );
    },
  );
}

List<String> labels(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (w) =>
            w is MessageBubble ||
            w is GatewayReasoningCard ||
            w is GatewayActivityCard,
      ),
    )
    .map(
      (w) => switch (w) {
        MessageBubble b => b.content,
        GatewayReasoningCard c => 'reasoning:${c.text}',
        GatewayActivityCard c => c.activities.map((a) => a.toolId).join(','),
        _ => throw StateError('Unexpected widget'),
      },
    )
    .toList();

final _connection = SavedConnection(
  id: 'spec-timeline-review',
  label: 'Fixture',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'test',
);

Future<void> _open(
  WidgetTester tester,
  GatewayTurnApplicationController controller,
  _Remote remote, {
  String id = 'local-chat',
  Key? key,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        key: key,
        connection: _connection,
        session: Session(
          id: id,
          title: 'Owner chat',
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
          apiKey: 'test',
          httpClient: MockClient((_) async {
            remote.historyRequests++;
            return http.Response(jsonEncode({'data': remote.history}), 200);
          }),
        ),
        // This fixture models a completed operation, with a correlated lifecycle
        // terminal after its RPC wait. ID-less completion safety has real-wire
        // regressions in normal_gateway_terminal_ownership_test.dart.
        testRemotePromptSubmit: completedStockTurn(remote.submit),
        testStoredSessionKey: (_) => 'stored-chat',
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _Remote {
  final rpc = Completer<void>();
  StreamCallback? onEvent;
  List<Map<String, dynamic>> history = [];
  int historyRequests = 0;
  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) {
    this.onEvent = onEvent;
    onSent();
    return rpc.future;
  }

  void event(String type, Map<String, dynamic> data) =>
      onEvent!(StreamEvent(type: type, data: data));
}
