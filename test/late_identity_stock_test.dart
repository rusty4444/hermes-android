// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/late_identity_stock_test.dart
// Base 4a53e32 blob e846a11cc25978eaea68b11448a30df3fb79a384; SHA256 201faa2f60d0ce5837af14e8a7c8f0f489f2670c596d83c3f66ddd82ab17f819.
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
import 'support/unreconciled_policy.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'support/completed_stock_turn.dart';
import 'support/pump_chat_updates.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    mockChatImageRecovery();
  });
  testWidgets('SPEC known late-ID tool must not resurrect after receipt eviction', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    addTearDown(controller.close);
    final remote = _Remote();
    await _open(tester, controller, remote);
    await tester.enterText(find.byType(TextField), 'One prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    remote.event('tool.start', {'tool': 'terminal'});
    remote.event('tool.progress', {
      'tool': 'terminal',
      'tool_id': 'late-id',
      'detail': 'bound ID',
    });
    await tester.pump();
    final owner = controller
        .normalSessionFor(_connection)
        .findChat('stored-chat')!;
    final first = owner.snapshot.timeline.runs.single;
    expect(first.activity!.toolId, 'late-id');
    expect(first.id, startsWith('local:'));
    for (var i = 0; i < 520; i++) {
      remote.event('message.delta', {'text': 'x'});
      remote.event('tool.complete', {'tool': 'terminal', 'tool_id': 'bulk-$i'});
    }
    await tester.pump();
    expect(owner.snapshot.timeline.runs.length, 1024);
    expect(
      _allRows(tester)
          .whereType<GatewayActivityCard>()
          .expand((c) => c.activities)
          .any((a) => a.toolId == 'late-id'),
      isFalse,
    );
    // A newer anonymous call must not absorb the evicted call's late ID.
    remote.event('tool.start', {'tool': 'terminal'});
    await tester.pump();
    final newest = owner.snapshot.timeline.runs.last.activity!;
    final keys = owner.snapshot.timeline.runs.map((r) => r.id).toList();
    remote.event('tool.complete', {'tool': 'terminal', 'tool_id': 'late-id'});
    await tester.pump();
    final after = _allRows(tester)
        .whereType<GatewayActivityCard>()
        .expand((c) => c.activities)
        .where((a) => a.toolId == 'late-id')
        .toList();
    debugPrint(
      'SPEC late-ID first=${first.id}/${first.activity!.toolId}; after eviction late-card=${after.map((a) => a.identity).toList()}; rows=${_allRows(tester).length}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      after,
      isEmpty,
      reason:
          'Eviction must remember durable tool ID as well as local presentation identity.',
    );
    expect(owner.snapshot.timeline.runs.map((r) => r.id), keys);
    expect(
      owner.snapshot.timeline.runs.last.activity!.identity,
      newest.identity,
    );
    expect(owner.snapshot.timeline.runs.last.activity!.isTerminal, isFalse);
  });
  for (final lateId in [false, true]) {
    for (final detached in [false, true]) {
      testWidgets(
        'pinned tool survives durable hydration lateId=$lateId detached=$detached',
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
          remote.event('tool.start', {
            'tool': 'terminal',
            if (!lateId) 'tool_id': 'hydrated-tool',
          });
          await tester.pump();
          final receivedKey = tester
              .widget<GatewayActivityCard>(
                inChatSource(
                  find.byType(GatewayActivityCard),
                  ChatDisplaySource.received,
                ),
              )
              .key;
          bool expanded() => tester
              .widget<ExpansionTile>(
                find.descendant(
                  of: inChatSource(
                    find.byType(GatewayActivityCard),
                    ChatDisplaySource.received,
                  ),
                  matching: find.byType(ExpansionTile),
                ),
              )
              .controller!
              .isExpanded;
          expect(expanded(), isFalse);
          await tester.tap(
            inChatSource(
              find.text('Tool activity'),
              ChatDisplaySource.received,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(expanded(), isTrue);
          await tester.tap(
            inChatSource(
              find.text('Tool activity'),
              ChatDisplaySource.received,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(
            inChatSource(
              find.text('Tool activity'),
              ChatDisplaySource.received,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(expanded(), isTrue);
          if (detached) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
          remote.event('tool.progress', {
            'tool': 'terminal',
            'tool_id': 'hydrated-tool',
          });
          remote.event('tool.complete', {
            'tool': 'terminal',
            'tool_id': 'hydrated-tool',
          });
          remote.event('message.complete', {'text': 'Wire reply'});
          remote.rpc.complete();
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expect(controller.hasActiveTurn, isFalse);
          if (!detached) expect(expanded(), isTrue);
          remote.history = [
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
          if (!detached) {
            final originalState = tester.state(find.byType(ChatScreen));
            final requests = remote.historyRequests;
            await tester.tap(find.byTooltip('Chat actions').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Refresh').hitTestable());
            await tester.pumpAndSettle();
            expect(remote.historyRequests, greaterThan(requests));
            expect(
              identical(tester.state(find.byType(ChatScreen)), originalState),
              isTrue,
            );
            expect(expanded(), isTrue);
            final savedCard = inChatSource(
              find.byType(GatewayActivityCard),
              ChatDisplaySource.canonical,
            );
            expect(
              tester.widget<GatewayActivityCard>(savedCard).key,
              const ValueKey('tool-activity-message:2'),
            );
            expect(
              tester
                  .widget<ExpansionTile>(
                    find.descendant(
                      of: savedCard,
                      matching: find.byType(ExpansionTile),
                    ),
                  )
                  .controller!
                  .isExpanded,
              isTrue,
            );
            expect(
              inChatSource(find.text('Completed'), ChatDisplaySource.received),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<GatewayActivityCard>(
                    inChatSource(
                      find.byType(GatewayActivityCard),
                      ChatDisplaySource.received,
                    ),
                  )
                  .key,
              receivedKey,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await _open(
            tester,
            controller,
            remote,
            id: 'stored-chat',
            key: ValueKey('hydration-$lateId'),
          );
          await tester.pump(const Duration(milliseconds: 300));
          final actual = expanded();
          expect(
            inChatSource(find.text('Completed'), ChatDisplaySource.received),
            findsNothing,
          );
          await tester.tap(
            inChatSource(
              find.text('Tool activity'),
              ChatDisplaySource.received,
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(expanded(), isTrue);
          expect(
            inChatSource(find.text('Completed'), ChatDisplaySource.received),
            findsOneWidget,
          );
          expect(
            tester
                .widget<GatewayActivityCard>(
                  inChatSource(
                    find.byType(GatewayActivityCard),
                    ChatDisplaySource.received,
                  ),
                )
                .activities
                .single
                .toolId,
            'hydrated-tool',
          );
          expect(find.text('Canonical reply'), findsOneWidget);
          expect(remote.submissions, 1);
          debugPrint(
            'SPEC hydration lateId=$lateId pinnedExpanded=true actual=$actual key=${tester.widget<GatewayActivityCard>(inChatSource(find.byType(GatewayActivityCard), ChatDisplaySource.received)).key}',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          expect(
            actual,
            isFalse,
            reason:
                'A new visit resets only tool UI choice, not the retained durable data (v2.1.32).',
          );
        },
      );
    }
  }
  testWidgets(
    'stock separate starts and ambiguous IDs cannot inherit anonymous pins',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote();
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'One prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      remote.event('tool.start', {'tool': 'terminal'});
      await tester.pump();
      await tester.ensureVisible(find.text('Tool activity'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Tool activity').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      remote.event('message.delta', {'text': 'separate calls'});
      remote.event('tool.start', {'tool': 'terminal', 'tool_id': 'other-call'});
      remote.event('tool.progress', {
        'tool': 'terminal',
        'tool_id': 'ambiguous-call',
      });
      await tester.pump();
      final activities = _allRows(
        tester,
      ).whereType<GatewayActivityCard>().expand((c) => c.activities).toList();
      expect(activities.length, 3);
      expect(activities.first.toolId, isNull);
      final cards = _allRows(tester).whereType<GatewayActivityCard>().toList();
      expect(cards.first.pinnedExpansion, isTrue);
      expect(cards[1].pinnedExpansion, isNull);
      // The same wire ID in another chat is not an expansion authority.
      expect(
        controller
            .presentationFor(_connection)
            .chatFor('different-chat')
            .openToolVisit()[activities.first.identity],
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'SPEC stock multi-turn saturation preserves starts and retained terminal updates',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote();
      await _open(tester, controller, remote);
      Future<void> send(String prompt) async {
        await tester.enterText(find.byType(TextField), prompt);
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump();
      }

      await send('First prompt');
      for (var i = 0; i < 100; i++) {
        remote.event('message.delta', {
          'text': i == 0 ? 'EVICTED_OLD_TEXT' : 'x',
        });
        remote.event('tool.complete', {
          'tool': 'terminal',
          'tool_id': 'turn1-$i',
        });
      }
      remote.event('message.complete', {});
      remote.rpc.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(controller.hasActiveTurn, isFalse);
      remote.rpc = Completer<void>();
      await send('Second prompt');
      for (var i = 0; i < 1700; i++) {
        remote.event('message.delta', {'text': 'y'});
        remote.event('tool.start', {'tool': 'terminal', 'tool_id': 'turn2-$i'});
      }
      await tester.pump();
      final owner = controller
          .normalSessionFor(_connection)
          .findChat('stored-chat')!;
      expect(owner.snapshot.timeline.runs.length, 1024);
      final before = owner.snapshot.timeline.runs.map((r) => r.id).toList();
      final retainedToolId = owner.snapshot.timeline.runs
          .lastWhere((r) => r.activity != null)
          .activity!
          .toolId!;
      expect(
        _allRows(tester)
            .whereType<MessageBubble>()
            .where((b) => !b.isUser)
            .any((b) => b.content.contains('EVICTED_OLD_TEXT')),
        isFalse,
      );
      remote.event('tool.complete', {'tool': 'terminal', 'tool_id': 'turn1-0'});
      remote.event('tool.complete', {
        'tool': 'terminal',
        'tool_id': 'turn2-1100',
      });
      remote.event('tool.complete', {
        'tool': 'terminal',
        'tool_id': 'ambiguous-completed-only',
      });
      await tester.pump();
      expect(owner.snapshot.timeline.runs.map((r) => r.id), before);
      remote.event('tool.start', {
        'tool': 'terminal',
        'tool_id': 'fresh-running',
      });
      remote.event('tool.complete', {
        'tool': 'terminal',
        'tool_id': 'fresh-running',
      });
      remote.event('tool.complete', {
        'tool': 'terminal',
        'tool_id': retainedToolId,
        'summary': 'valid update',
      });
      await tester.pump();
      final activities = _allRows(
        tester,
      ).whereType<GatewayActivityCard>().expand((c) => c.activities).toList();
      expect(
        activities.where((a) => a.toolId == 'fresh-running').single.isTerminal,
        isTrue,
      );
      expect(
        activities.where((a) => a.toolId == retainedToolId).single.detail,
        'valid update',
      );
      expect(
        activities.any(
          (a) => [
            'turn1-0',
            'turn2-1100',
            'ambiguous-completed-only',
          ].contains(a.toolId),
        ),
        isFalse,
      );
      expect(owner.snapshot.timeline.runs.length, 1024);
      expect(owner.snapshot.historyRows, isEmpty);
      debugPrint(
        'SPEC stock multi-turn saturated rows=${_allRows(tester).length} runs=${owner.snapshot.timeline.runs.length} retained-update=true fresh-start=true',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('SPEC stock newest-text budget across interim scopes', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    addTearDown(controller.close);
    final remote = _Remote();
    await _open(tester, controller, remote);
    await tester.enterText(find.byType(TextField), 'Text prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final owner = controller
        .normalSessionFor(_connection)
        .findChat('stored-chat')!;
    for (var i = 0; i < 5; i++) {
      final text =
          '${i == 0 ? 'EVICTED_PREFIX' : 'MARK$i'}${' ' * 300000}${i == 4 ? 'LATEST_SUFFIX' : ' END$i'}';
      remote.event('message.delta', {'text': text});
      if (i < 4) {
        remote.event('message.interim', {
          'text': text,
          'already_streamed': true,
        });
      }
      remote.event('tool.start', {'tool': 'terminal', 'tool_id': 'text-$i'});
    }
    await tester.pump();
    final bubbles = owner.snapshot.timeline.runs
        .where((r) => r.activity == null)
        .map((r) => r.text)
        .toList();
    expect(bubbles.fold<int>(0, (n, t) => n + t.length), 1048576);
    expect(bubbles.join().contains('EVICTED_PREFIX'), isFalse);
    expect(bubbles.last.endsWith('LATEST_SUFFIX'), isTrue);
    remote.event('message.delta', {'text': 'tail'});
    await tester.pump();
    final after = owner.snapshot.timeline.runs
        .where((r) => r.activity == null)
        .map((r) => r.text)
        .toList();
    expect(after.fold<int>(0, (n, t) => n + t.length), 1048576);
    expect(after.last, 'tail');
    debugPrint(
      'SPEC stock text rows=${after.length} codeunits=${after.fold<int>(0, (n, t) => n + t.length)}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

List<Widget> _allRows(WidgetTester tester) {
  final finder = find.byType(ListView).first;
  final list = tester.widget<ListView>(finder);
  final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
  final context = tester.element(finder);
  return [
    for (var i = 0; i < delegate.childCount!; i++)
      unwrapChatSourceCell(delegate.builder(context, i)!),
  ];
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
  apiKey: 'spec-fixture',
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
          apiKey: 'spec-fixture',
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
  Completer<void> rpc = Completer<void>();
  StreamCallback? onEvent;
  List<Map<String, dynamic>> history = [];
  int historyRequests = 0;
  int submissions = 0;
  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) {
    this.onEvent = onEvent;
    submissions++;
    onSent();
    return rpc.future;
  }

  void event(String type, Map<String, dynamic> data) =>
      onEvent!(StreamEvent(type: type, data: data));
}
