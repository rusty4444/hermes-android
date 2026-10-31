// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/chat_history_scroll_test.dart
// Base 4a53e32 blob 96c3d8ad1b9544e7a460e9cf87d09b7372398341; SHA256 c95bedb2b6edb44b14298bc408629209bf68efcce9c442127ecc736623ae8981.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'support/unreconciled_policy.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'support/completed_stock_turn.dart';
import 'support/pump_chat_updates.dart';
import 'support/fake_voice_composer_adapter.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/utils/chat_history_scroll.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/core/widgets/chat_end_affordance.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    mockChatImageRecovery();
  });

  group('REST history', () {
    test('stays chronological and appends the current prompt exactly once', () {
      final history = buildRestChatHistory([
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
      ]);

      final requestMessages = GatewayChatClient.buildChatCompletionMessages(
        message: 'current question',
        history: history,
      );

      expect(requestMessages, [
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
        {
          'role': 'user',
          'content': AndroidPromptContext.forModel('current question'),
        },
      ]);
      expect(
        requestMessages.where(
          (message) =>
              message['content'] ==
              AndroidPromptContext.forModel('current question'),
        ),
        hasLength(1),
      );
    });
  });

  group('scroll coordinator', () {
    test('normal opening exposes only one end alignment', () {
      final coordinator = ChatScrollCoordinator();

      final first = coordinator.consumeInitialEndAlignment();
      final second = coordinator.consumeInitialEndAlignment();

      expect(first, isA<ChatScrollTarget>());
      expect(second, isNull);
      expect(coordinator.initialEndAlignmentConsumed, isTrue);
    });

    for (final transport in const ['REST', 'Remote']) {
      test(
        '$transport completion follows only when streaming started at end',
        () {
          final following = ChatScrollCoordinator();
          following.beginStreaming(isNearEnd: true);
          expect(following.streamingContentChanged(), isNotNull);
          expect(following.endStreaming(), isNotNull);

          final readingHistory = ChatScrollCoordinator();
          readingHistory.beginStreaming(isNearEnd: false);
          expect(readingHistory.streamingContentChanged(), isNull);
          expect(readingHistory.endStreaming(), isNull);
        },
      );
    }

    test('direct user scrolling disables and can resume sticky follow', () {
      final coordinator = ChatScrollCoordinator();
      coordinator.beginStreaming(isNearEnd: true);

      coordinator.updateFromUserScroll(isNearEnd: false);
      expect(coordinator.streamingContentChanged(), isNull);

      coordinator.updateFromUserScroll(isNearEnd: true);
      expect(coordinator.streamingContentChanged(), isNotNull);
    });
  });

  group('end affordance controller', () {
    test('visibility uses distance while unread clears only at actual end', () {
      final controller = ChatEndAffordanceController(
        showThreshold: 200,
        endTolerance: 1,
      );

      controller.updatePosition(pixels: 400, maxScrollExtent: 1000);
      expect(controller.isVisible, isTrue);
      expect(controller.isAtEnd, isFalse);
      expect(controller.registerMaterializedMessage(willFollow: false), isTrue);
      expect(controller.newMessageCount, 1);

      controller.updatePosition(pixels: 850, maxScrollExtent: 1000);
      expect(controller.isVisible, isFalse);
      expect(controller.newMessageCount, 1);

      controller.updatePosition(pixels: 998, maxScrollExtent: 1000);
      expect(controller.isAtEnd, isFalse);
      expect(controller.newMessageCount, 1);

      controller.updatePosition(pixels: 999.5, maxScrollExtent: 1000);
      expect(controller.isAtEnd, isTrue);
      expect(controller.newMessageCount, 0);
    });

    test('followed messages never create transient unread state', () {
      final controller = ChatEndAffordanceController();
      controller.updatePosition(pixels: 500, maxScrollExtent: 1000);

      expect(controller.registerMaterializedMessage(willFollow: true), isFalse);
      expect(controller.newMessageCount, 0);
    });
  });

  group('ChatScreen integration', () {
    for (final completionFlag in ['response_previewed', 'response_reused']) {
      testWidgets(
        '$completionFlag completion preserves reasoning receipt order and card identity',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1000, 2400);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final remote = _ControlledRemotePrompt();
          await _pumpChat(
            tester,
            client: _ControlledChatHttpClient(const []),
            connectionId: 'reasoning-order-$completionFlag',
            sessionId: 'reasoning-order-$completionFlag',
            remoteSubmit: remote.submit,
          );
          await tester.enterText(find.byType(TextField), 'Question');
          await tester.tap(find.byTooltip('Send'));
          await tester.pump();
          await remote.started.future;
          remote.emit('message.delta', {'text': 'A'});
          remote.emit('reasoning.delta', {'text': 'R1'});
          remote.emit('message.interim', {
            'text': 'A',
            'already_streamed': true,
          });
          remote.emit('tool.start', {'tool_id': 't1', 'name': 'terminal'});
          remote.emit('reasoning.delta', {'text': 'R2', 'verbose': true});
          await tester.pump(const Duration(milliseconds: 300));

          List<String> rendered() => tester
              .widgetList(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is MessageBubble ||
                      widget is GatewayReasoningCard ||
                      widget is GatewayActivityCard,
                ),
              )
              .map(
                (widget) => switch (widget) {
                  MessageBubble bubble => bubble.content,
                  GatewayReasoningCard card => 'reasoning:${card.text}',
                  GatewayActivityCard card =>
                    card.activities
                        .map((activity) => activity.toolId)
                        .join(','),
                  _ => throw StateError('unexpected item'),
                },
              )
              .toList();
          final before = rendered();
          expect(before, [
            'Question',
            'A',
            'reasoning:R1',
            't1',
            'reasoning:R2',
          ]);
          final cards = find.byType(GatewayReasoningCard);
          final keys = tester
              .widgetList(cards)
              .map((widget) => widget.key)
              .toList();
          final states = tester.stateList(cards).toList();
          // Pin the two cards in opposite states before their scopes merge.
          await tester.tap(
            find
                .descendant(
                  of: find.byType(GatewayReasoningCard),
                  matching: find.text('Reasoning'),
                )
                .first,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(
            find
                .descendant(
                  of: find.byType(GatewayReasoningCard),
                  matching: find.text('Reasoning'),
                )
                .last,
          );
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(
            find
                .descendant(
                  of: find.byType(GatewayReasoningCard),
                  matching: find.text('Reasoning'),
                )
                .last,
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('R1'), findsOneWidget);
          expect(find.text('R2'), findsNothing);

          remote.emit('message.complete', {'text': 'A', completionFlag: true});
          remote.finish();
          await tester.pump(const Duration(milliseconds: 300));
          expect(rendered(), before);
          expect(tester.widgetList(cards).map((widget) => widget.key), keys);
          expect(tester.stateList(cards), states);
          expect(
            tester
                .widgetList<GatewayReasoningCard>(cards)
                .map((card) => card.pinnedExpansion),
            [true, false],
          );
          expect(find.text('R1'), findsOneWidget);
          expect(find.text('R2'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    for (final newline in ['\n', '\r\n']) {
      testWidgets(
        'fragmented SSE ${newline.length} byte newline preserves receipt order and durable hydrate',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1000, 2400);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final client = _ControlledChatHttpClient(const []);
          await _pumpChat(
            tester,
            client: client,
            connectionId: 'sse-${newline.length}',
            sessionId: 'sse',
          );
          await tester.enterText(find.byType(TextField), 'SSE order');
          await tester.tap(find.byTooltip('Send'));
          await tester.pump();
          await client.postStarted.future;
          String token(String text) =>
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': text},
                  },
                ],
              })}$newline$newline';
          String tool(String id, String status) =>
              'event: hermes.tool.progress${newline}data: ${jsonEncode({'tool': 'terminal', 'toolCallId': id, 'status': status})}$newline$newline';
          // Fragment every byte, including CRLF delimiters and UTF-8 text. The
          // parser must synchronously deliver each token/tool in receipt order.
          client.emitFragmented(
            token('A 🐈') +
                tool('t1', 'running') +
                tool('t2', 'running') +
                token('B') +
                tool('t3', 'running') +
                token('C') +
                tool('t1', 'completed'),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(_timelineLabels(tester), [
            'SSE order',
            'A 🐈',
            't1,t2',
            'B',
            't3',
            'C',
          ]);
          final group = tester.widget<GatewayActivityCard>(
            find.byType(GatewayActivityCard).first,
          );
          expect(group.activities.first.isTerminal, true);
          expect(group.activities.last.isTerminal, false);
          // A durable transcript replaces the receipt overlay in one rebuild.
          client.finish([
            {'id': 1, 'role': 'user', 'content': 'SSE order'},
            {'id': 2, 'role': 'assistant', 'content': 'A 🐈'},
            {
              'id': 3,
              'role': 'tool',
              'tool_call_id': 't1',
              'name': 'terminal',
              'content': 'ok',
              'timestamp': 1792544523,
            },
            {
              'id': 4,
              'role': 'tool',
              'tool_call_id': 't2',
              'name': 'terminal',
              'content': 'ok',
            },
            {'id': 5, 'role': 'assistant', 'content': 'B'},
            {
              'id': 6,
              'role': 'tool',
              'tool_call_id': 't3',
              'name': 'terminal',
              'content': 'ok',
            },
            {'id': 7, 'role': 'assistant', 'content': 'C'},
          ]);
          await pumpChatUpdates(tester);
          expect(_timelineLabels(tester), [
            'SSE order',
            'A 🐈',
            't1,t2',
            'B',
            't3',
            'C',
          ]);
          expect(find.byType(GatewayReasoningCard), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await pumpChatUpdates(tester);
        },
      );
    }

    testWidgets(
      'reattach replaces optimistic runs with durable rows without duplicate bubbles or tools',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 2400);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final hook = TestDesktopConnectionHook();
        final remote = _ControlledRemotePrompt();
        final client = _ControlledChatHttpClient([
          {'id': 1, 'role': 'user', 'content': 'Old question'},
          {'id': 2, 'role': 'assistant', 'content': 'Old answer'},
        ]);
        await _pumpChat(
          tester,
          client: client,
          connectionId: 'reattach-order',
          sessionId: 'reattach-order',
          remoteSubmit: remote.submit,
          connectionHook: hook,
          resume: ({required localSessionId, required storedSessionId}) async =>
              const ResumedGatewaySession(
                runtimeSessionId: 'runtime-fixture',
                running: false,
                status: 'completed',
              ),
        );
        hook.handler!(DesktopConnectionState.connected);
        await tester.enterText(find.byType(TextField), 'Continue');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;
        remote.emit('message.delta', {'text': 'A'});
        remote.emit('tool.start', {'tool_id': 't1', 'name': 'terminal'});
        remote.emit('message.delta', {'text': 'B'});
        await tester.pump(const Duration(milliseconds: 300));
        expect(_timelineLabels(tester), [
          'Old question',
          'Old answer',
          'Continue',
          'A',
          't1',
          'B',
        ]);
        hook.handler!(DesktopConnectionState.reconnecting);
        remote.fail();
        await tester.pump(const Duration(milliseconds: 300));
        // No old-row overlap in the latest page: ChatHistoryWindow still retains
        // the earlier durable bubbles, while replacing this turn's optimism.
        client.serverMessages = [
          {'id': 3, 'role': 'user', 'content': 'Continue'},
          {'id': 4, 'role': 'assistant', 'content': 'A'},
          {
            'id': 5,
            'role': 'tool',
            'tool_call_id': 't1',
            'name': 'terminal',
            'content': 'ok',
            'timestamp': 1792544523,
          },
          {'id': 6, 'role': 'assistant', 'content': 'B'},
        ];
        hook.handler!(DesktopConnectionState.connected);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(_timelineLabels(tester), [
          'Old question',
          'Old answer',
          'Continue',
          'A',
          't1',
          'B',
          'Continue',
          'A',
          't1',
          'B',
        ]);
        expect(
          tester
              .widget<GatewayActivityCard>(
                inChatSource(
                  find.byType(GatewayActivityCard),
                  ChatDisplaySource.canonical,
                ),
              )
              .activities
              .single
              .isTerminal,
          true,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'older paging retains completed receipt runs and pinned cards',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 1400);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final remote = _ControlledRemotePrompt();
        final client = _ControlledChatHttpClient([
          for (var i = 1; i <= 50; i++)
            {
              'id': i,
              'role': i.isOdd ? 'user' : 'assistant',
              'content': 'History row $i',
            },
        ]);
        await _pumpChat(
          tester,
          client: client,
          connectionId: 'paging-order',
          sessionId: 'paging-order',
          remoteSubmit: remote.submit,
        );
        await tester.enterText(find.byType(TextField), 'Continue');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;
        remote.emit('thinking.delta', {
          'text': 'Thinking status, not exposed reasoning',
        });
        await tester.pump();
        expect(find.byType(GatewayReasoningCard), findsNothing);
        remote.emit('message.delta', {'text': 'A'});
        remote.emit('tool.start', {'tool_id': 't1', 'name': 'terminal'});
        remote.emit('message.delta', {'text': 'B'});
        await tester.pump(const Duration(milliseconds: 300));
        final controller = _chatListController(tester);
        for (var attempt = 0; attempt < 3; attempt++) {
          controller.jumpTo(controller.position.maxScrollExtent);
          await tester.pump(const Duration(milliseconds: 300));
        }
        // Tool sections now start closed. Explicitly open, then pin closed.
        await tester.tap(find.text('Tool activity'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Tool activity'));
        remote.emit('message.complete', {'text': 'AB'});
        remote.finish();
        await tester.pump(const Duration(milliseconds: 300));
        controller.jumpTo(0);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('chat-load-older')));
        await tester.pump(const Duration(milliseconds: 300));
        // Lazy-list extent estimates change as the older rows are laid out.
        // Scroll to the actual final bubble rather than an estimated end.
        await tester.scrollUntilVisible(
          find.byWidgetPredicate((w) => w is MessageBubble && w.content == 'B'),
          500,
          scrollable: find.descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final order = _timelineLabels(tester);
        expect(order.sublist(order.length - 4), ['Continue', 'A', 't1', 'B']);
        expect(
          tester
              .widget<GatewayActivityCard>(find.byType(GatewayActivityCard))
              .pinnedExpansion,
          false,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'stock interim sequence leaves commentary between separate tool batches',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 2400);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final remote = _ControlledRemotePrompt();
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(const []),
          connectionId: 'stock-order',
          sessionId: 'stock-order',
          remoteSubmit: remote.submit,
        );
        await tester.enterText(find.byType(TextField), 'Stock ordering');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;
        remote.emit('message.delta', {'text': 'Commentary A'});
        remote.emit('message.interim', {
          'text': 'Commentary A',
          'already_streamed': true,
        });
        remote.emit('tool.start', {'tool_id': 't1', 'name': 'terminal'});
        remote.emit('tool.complete', {'tool_id': 't1', 'name': 'terminal'});
        remote.emit('message.delta', {'text': 'Commentary B'});
        remote.emit('message.interim', {
          'text': 'Commentary B',
          'already_streamed': true,
        });
        remote.emit('reasoning.available', {'text': 'Exposed reasoning'});
        remote.emit('tool.start', {'tool_id': 't2', 'name': 'terminal'});
        await tester.pump(const Duration(milliseconds: 300));
        expect(_timelineLabels(tester), [
          'Stock ordering',
          'Commentary A',
          't1',
          'Commentary B',
          'reasoning',
          't2',
        ]);
        remote.finish();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('receipt timeline interleaves prose reasoning and tool batches', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 2400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final remote = _ControlledRemotePrompt();
      await _pumpChat(
        tester,
        client: _ControlledChatHttpClient(const []),
        connectionId: 'ordered',
        sessionId: 'ordered',
        remoteSubmit: remote.submit,
      );
      await tester.enterText(find.byType(TextField), 'Order these');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await remote.started.future;
      remote.emit('message.delta', {'text': 'A'});
      remote.emit('reasoning.delta', {'text': 'R'});
      remote.emit('tool.start', {'tool_id': 't1', 'name': 'terminal'});
      remote.emit('tool.start', {'tool_id': 't2', 'name': 'terminal'});
      remote.emit('message.delta', {'text': 'B'});
      remote.emit('tool.start', {'tool_id': 't3', 'name': 'terminal'});
      remote.emit('message.delta', {'text': 'C'});
      await tester.pump(const Duration(milliseconds: 300));
      List<String> order() => _timelineLabels(tester);
      expect(order(), [
        'Order these',
        'A',
        'reasoning',
        't1,t2',
        'B',
        't3',
        'C',
      ]);
      // A completion is an update to the first batch, not a new trailing batch.
      final reasoningKey = tester
          .widget<GatewayReasoningCard>(find.byType(GatewayReasoningCard))
          .key;
      await tester.tap(
        find.descendant(
          of: find.byType(GatewayReasoningCard),
          matching: find.text('Reasoning'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('R'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(GatewayReasoningCard),
          matching: find.text('Reasoning'),
        ),
      );
      await tester.tap(find.text('Tool activity').first);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Tool activity').first);
      await tester.pump(const Duration(milliseconds: 300));
      remote.emit('tool.complete', {'tool_id': 't1', 'name': 'terminal'});
      remote.emit('reasoning.available', {
        'text': 'Revised R',
        'verbose': true,
      });
      remote.emit('message.complete', {'text': 'ABC'});
      remote.finish();
      await tester.pump(const Duration(milliseconds: 300));
      expect(order(), [
        'Order these',
        'A',
        'reasoning',
        't1,t2',
        'B',
        't3',
        'C',
      ]);
      expect(
        tester
            .widget<GatewayReasoningCard>(find.byType(GatewayReasoningCard))
            .text,
        'Revised R',
      );
      expect(
        tester
            .widget<GatewayReasoningCard>(find.byType(GatewayReasoningCard))
            .key,
        reasoningKey,
      );
      expect(find.text('Revised R'), findsNothing);
      expect(
        tester
            .widget<GatewayActivityCard>(find.byType(GatewayActivityCard).first)
            .pinnedExpansion,
        false,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      'composer stays overflow-free at font scale 200% on compact screens',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        for (final width in [320.0, 360.0]) {
          tester.view.physicalSize = Size(width, 640);
          await _pumpChat(
            tester,
            client: _ControlledChatHttpClient(const []),
            connectionId: 'compact-$width',
            sessionId: 'compact-$width',
            textScale: 2,
          );

          for (final label in const [
            'Add attachment',
            'Message',
            'Start voice input',
            'Spoken replies',
            'Send message',
          ]) {
            expect(find.bySemanticsLabel(label), findsOneWidget);
          }
          for (final tooltip in const [
            'Attach image or file',
            'Speak to Hermes',
            'Send',
          ]) {
            expect(tester.getSize(find.byTooltip(tooltip)), const Size(48, 48));
          }
          final messageField = tester.widget<TextField>(
            find.descendant(
              of: find.bySemanticsLabel('Message'),
              matching: find.byType(TextField),
            ),
          );
          expect(messageField.minLines, 1);
          expect(messageField.maxLines, 5);
          expect(messageField.decoration?.hintText, 'Message Hermes…');
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'opens a materialized long history at end after stable layout',
      (tester) async {
        final historyGate = Completer<void>();
        final client = _ControlledChatHttpClient(
          _longHistory(),
          historyGate: historyGate,
        );

        await _pumpChat(
          tester,
          client: client,
          connectionId: 'delayed-opening',
          sessionId: 'delayed-opening',
          settle: false,
        );
        await tester.pump();
        expect(find.byType(ListView), findsNothing);

        historyGate.complete();
        await pumpChatUpdates(tester);

        final controller = _chatListController(tester);
        expect(controller.position.maxScrollExtent, greaterThan(0));
        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);
      },
    );

    for (final remote in [false, true]) {
      testWidgets(
        'opens mixed-height ${remote ? 'Remote' : 'REST'} history at the latest message on a phone',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 720);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final messages = [
            for (var index = 0; index < 48; index++)
              {
                'id': index + 1,
                'role': index.isEven ? 'user' : 'assistant',
                'content': index == 47
                    ? 'Latest reply'
                    : 'Message $index\n${List.filled(index < 16 ? 80 : 2, 'History line').join('\n')}',
              },
          ];
          await _pumpChat(
            tester,
            client: _ControlledChatHttpClient(messages),
            connectionId: 'mixed-height-$remote',
            sessionId: 'mixed-height-$remote',
            remoteSubmit: remote ? _ControlledRemotePrompt().submit : null,
          );

          final controller = _chatListController(tester);
          expect(
            controller.position.pixels,
            closeTo(controller.position.maxScrollExtent, 1),
          );
          final latest = find.byWidgetPredicate(
            (widget) =>
                widget is MessageBubble && widget.content == 'Latest reply',
          );
          expect(latest, findsOneWidget);
          expect(
            tester.getRect(latest).bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byType(ListView).first).bottom,
            ),
          );
          expect(find.bySemanticsLabel('Go to end'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    for (final (status, readHistory) in [
      (200, false),
      (200, true),
      (503, false),
      (503, true),
    ]) {
      testWidgets(
        'opens retained Remote history at end before latest read (status=$status, reading=$readHistory)',
        (tester) async {
          final controller = GatewayTurnApplicationController();
          addTearDown(controller.close);
          final remote = _ControlledRemotePrompt();
          final historyGate = Completer<void>();
          addTearDown(() {
            if (!historyGate.isCompleted) historyGate.complete();
          });
          final messages = [
            for (final (index, row) in _longHistory().indexed)
              {'id': index + 1, ...row},
          ];
          final connection = SavedConnection(
            id: 'retained-opening',
            label: 'Fixture',
            host: 'fixture.example',
            port: 8642,
            apiKey: 'synthetic-key',
          );
          final session = controller.normalSessionFor(
            connection,
            submit: remote.submit,
          );
          session
              .chatFor(
                'retained-opening',
                storedSessionId: 'retained-opening',
                title: 'Fixture chat',
              )
              .observeHistory(messages);

          await _pumpChat(
            tester,
            client: _ControlledChatHttpClient(
              messages,
              historyGate: historyGate,
              historyStatusCode: status,
            ),
            connectionId: 'retained-opening',
            sessionId: 'retained-opening',
            savedConnection: connection,
            remoteSubmit: remote.submit,
            turnController: controller,
            settle: false,
          );
          for (var frame = 0; frame < 16; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }

          final scroll = _chatListController(tester);
          expect(scroll.position.maxScrollExtent, greaterThan(0));
          expect(
            scroll.position.pixels,
            closeTo(scroll.position.maxScrollExtent, 1),
          );
          expect(historyGate.isCompleted, isFalse);
          final position = scroll.position;
          final openingViewport = position.viewportDimension;
          final latest = find.byWidgetPredicate(
            (widget) =>
                widget is MessageBubble &&
                widget.content == messages.last['content'],
          );
          expect(latest, findsOneWidget);
          expect(
            tester.getRect(latest).bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byType(ListView).first).bottom,
            ),
          );
          if (readHistory) {
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, 400),
            );
            scroll.jumpTo(320);
            await tester.pump();
          }
          final readingOffset = scroll.position.pixels;
          historyGate.complete();
          await tester.pumpAndSettle();
          expect(scroll.position, same(position));
          if (readHistory) {
            expect(scroll.position.pixels, closeTo(readingOffset, 1));
          } else {
            expect(
              scroll.position.pixels,
              closeTo(scroll.position.maxScrollExtent, 1),
            );
            expect(latest, findsOneWidget);
            expect(
              tester.getRect(latest).bottom,
              lessThanOrEqualTo(
                tester.getRect(find.byType(ListView).first).bottom,
              ),
            );
            if (status == 503) {
              expect(position.viewportDimension, lessThan(openingViewport));
            }
          }
          expect(
            find.byType(MaterialBanner),
            status == 200 ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('an empty first read does not consume opening alignment', (
      tester,
    ) async {
      final client = _ControlledChatHttpClient(const []);
      await _pumpChat(
        tester,
        client: client,
        connectionId: 'empty-opening',
        sessionId: 'empty-opening',
      );
      client.serverMessages = _longHistory();
      await tester.tap(find.byTooltip('Chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      final scroll = _chatListController(tester);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(
        scroll.position.pixels,
        closeTo(scroll.position.maxScrollExtent, 1),
      );
      expect(find.bySemanticsLabel('Go to end'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('dragging during opening cancels pending end alignment', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        client: _ControlledChatHttpClient(_longHistory()),
        connectionId: 'opening-drag',
        sessionId: 'opening-drag',
        settle: false,
      );
      await tester.pump();
      final scroll = _chatListController(tester);
      await tester.drag(find.byType(ListView).first, const Offset(0, 300));
      scroll.jumpTo(320);
      for (var frame = 0; frame < 16; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(scroll.position.pixels, closeTo(320, 1));
      expect(find.bySemanticsLabel('Go to end'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reopening ignores an old position and returns to end', (
      tester,
    ) async {
      final messages = _longHistory();
      await _pumpChat(
        tester,
        client: _ControlledChatHttpClient(messages),
        connectionId: 'no-restore',
        sessionId: 'no-restore',
      );
      final firstController = _chatListController(tester);
      firstController.jumpTo(320);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await _pumpChat(
        tester,
        client: _ControlledChatHttpClient(messages),
        connectionId: 'no-restore',
        sessionId: 'no-restore',
      );
      final reopenedController = _chatListController(tester);

      expect(
        reopenedController.position.pixels,
        reopenedController.position.maxScrollExtent,
      );
      expect(reopenedController.position.pixels, isNot(closeTo(320, 0.01)));
    });

    testWidgets('sends chronological REST history through the real screen', (
      tester,
    ) async {
      final initialMessages = [
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
      ];
      final client = _ControlledChatHttpClient(initialMessages);

      await _pumpChat(
        tester,
        client: client,
        connectionId: 'integration-history',
        sessionId: 'history-session',
      );
      await tester.enterText(find.byType(TextField), 'current question');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await client.postStarted.future;

      final request =
          jsonDecode(client.lastRequestBody!) as Map<String, dynamic>;
      expect(request['messages'], [
        {'role': 'user', 'content': 'oldest question'},
        {'role': 'assistant', 'content': 'middle answer'},
        {
          'role': 'user',
          'content': AndroidPromptContext.forModel('current question'),
        },
      ]);

      client.finish([
        ...initialMessages,
        {'role': 'user', 'content': 'current question'},
        {'role': 'assistant', 'content': 'final answer'},
      ]);
      await pumpChatUpdates(tester);
    });

    testWidgets(
      'REST follows at end but preserves history through refresh and completion',
      (tester) async {
        final initialMessages = _longHistory();
        final client = _ControlledChatHttpClient(initialMessages);

        await _pumpChat(
          tester,
          client: client,
          connectionId: 'rest-scroll',
          sessionId: 'rest-scroll',
        );
        final controller = _chatListController(tester);
        expect(controller.position.pixels, controller.position.maxScrollExtent);

        controller.jumpTo(80);
        await tester.pump();
        await tester.tap(find.byTooltip('Chat actions'));
        await pumpChatUpdates(tester);
        await tester.tap(find.text('Refresh'));
        await pumpChatUpdates(tester);
        expect(controller.position.pixels, closeTo(80, 0.01));

        await tester.enterText(find.byType(TextField), 'stay in history');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await client.postStarted.future;

        client.emitToken('first materialized delta');
        await tester.pump();
        await tester.pump();
        final historyPosition = controller.position.pixels;
        expect(_indicatorText(tester), '1 new');
        expect(_goToEndSemantics(tester).value, '1 new message');

        client.emitToken(' and a second delta of the same message');
        await tester.pump();
        await tester.pump();
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));
        expect(_indicatorText(tester), '1 new');

        client.finish([
          ...initialMessages,
          {'role': 'user', 'content': 'stay in history'},
          {
            'role': 'assistant',
            'content':
                'first materialized delta and a second delta of the same message',
          },
        ]);
        await pumpChatUpdates(tester);
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));
        expect(_indicatorText(tester), '1 new');

        await tester.tap(find.bySemanticsLabel('Go to end'));
        await pumpChatUpdates(tester);
        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);
      },
    );

    testWidgets(
      'REST streaming at end follows content growth before completion',
      (tester) async {
        final initialMessages = _longHistory();
        final client = _ControlledChatHttpClient(initialMessages);
        await _pumpChat(
          tester,
          client: client,
          connectionId: 'rest-follow',
          sessionId: 'rest-follow',
        );
        final controller = _chatListController(tester);

        await tester.enterText(find.byType(TextField), 'follow this');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await client.postStarted.future;
        client.emitToken(List.filled(60, 'growing response').join('\n'));
        await tester.pump();
        await tester.pump();

        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);

        client.finish([
          ...initialMessages,
          {'role': 'user', 'content': 'follow this'},
          {'role': 'assistant', 'content': 'done'},
        ]);
        await pumpChatUpdates(tester);
        expect(controller.position.pixels, controller.position.maxScrollExtent);
      },
    );

    testWidgets(
      'Remote completion preserves history and counts each new message once',
      (tester) async {
        final remote = _ControlledRemotePrompt();
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(_longHistory()),
          connectionId: 'remote-history',
          sessionId: 'remote-history',
          remoteSubmit: remote.submit,
        );
        final controller = _chatListController(tester);
        controller.jumpTo(80);
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'remote response');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;

        remote.emit('message.delta', {'text': 'first'});
        await tester.pump();
        await tester.pump();
        final historyPosition = controller.position.pixels;
        expect(_indicatorText(tester), '1 new');

        remote.emit('message.delta', {'text': ' second delta'});
        await tester.pump();
        await tester.pump();
        expect(_indicatorText(tester), '1 new');
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));

        remote.emit('message.interim', {
          'text': ' interim',
          'already_streamed': false,
        });
        remote.emit('message.delta', {'text': 'second message'});
        await tester.pump();
        await tester.pump();
        expect(_indicatorText(tester), '2 new');
        expect(_goToEndSemantics(tester).value, '2 new messages');

        remote.emit('message.complete', {'rendered': 'second message final'});
        remote.finish();
        await pumpChatUpdates(tester);
        expect(controller.position.pixels, closeTo(historyPosition, 0.01));
        expect(_indicatorText(tester), '2 new');

        await _dragToEnd(tester, controller);
        expect(controller.position.pixels, controller.position.maxScrollExtent);
        expect(find.bySemanticsLabel('Go to end'), findsNothing);
      },
    );

    testWidgets(
      'Remote previewed or reused completion appears once per turn, not once per chat',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final remote = _ControlledRemotePrompt();
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(const []),
          connectionId: 'previewed-completion',
          sessionId: 'previewed-completion',
          remoteSubmit: remote.submit,
        );

        for (var turn = 1; turn <= 2; turn++) {
          remote.started = Completer<void>();
          await tester.enterText(find.byType(TextField), '3+4');
          await tester.tap(find.byTooltip('Send'));
          await tester.pump();
          await remote.started.future;

          remote.emit('message.start', {});
          remote.emit('message.delta', {'text': 'Computing.'});
          remote.emit('message.interim', {
            'text': 'Computing.',
            'already_streamed': true,
          });
          remote.emit('message.delta', {'text': '7'});
          remote.emit('message.interim', {
            'text': '7',
            'already_streamed': true,
          });
          remote.emit('message.complete', {
            'text': '7',
            (turn == 1 ? 'response_previewed' : 'response_reused'): true,
            'status': 'complete',
          });
          remote.finish();
          await pumpChatUpdates(tester);

          expect(find.text('7', findRichText: true), findsNWidgets(turn));
          expect(
            find.text('Computing.', findRichText: true),
            findsNWidgets(turn),
          );
          expect(find.byTooltip('Send'), findsOneWidget);
        }
      },
    );

    testWidgets(
      'Remote distinct transformed completion preserves commentary and a new message stays distinct',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final remote = _ControlledRemotePrompt();
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(const []),
          connectionId: 'rewritten-completion',
          sessionId: 'rewritten-completion',
          remoteSubmit: remote.submit,
        );
        await tester.enterText(find.byType(TextField), 'Rewrite the preview');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;

        remote.emit('message.delta', {'text': 'Unfiltered preview'});
        remote.emit('message.interim', {
          'text': 'Unfiltered preview',
          'already_streamed': true,
        });
        remote.emit('message.complete', {
          'text': 'Final answer',
          'response_transformed': true,
        });
        await tester.pump();
        expect(
          find.text('Unfiltered preview', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Final answer', findRichText: true), findsOneWidget);

        remote.finish();
        await pumpChatUpdates(tester);
        remote.started = Completer<void>();
        await tester.enterText(find.byType(TextField), 'A separate reply');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;
        remote.emit('message.delta', {'text': 'Earlier interim'});
        remote.emit('message.interim', {
          'text': 'Earlier interim',
          'already_streamed': true,
        });
        remote.emit('message.start', {});
        remote.emit('message.complete', {
          'text': 'Distinct reply',
          'response_previewed': true,
        });
        remote.finish();
        await pumpChatUpdates(tester);
        expect(find.text('Final answer', findRichText: true), findsOneWidget);
        expect(
          find.text('Earlier interim', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('Distinct reply', findRichText: true), findsOneWidget);

        remote.started = Completer<void>();
        await tester.enterText(find.byType(TextField), 'Two separate replies');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;
        remote.emit('message.delta', {'text': 'Repeated reply'});
        remote.emit('message.interim', {
          'text': 'Repeated reply',
          'already_streamed': true,
        });
        remote.emit('message.start', {});
        remote.emit('message.complete', {
          'text': 'Repeated reply',
          'response_reused': true,
        });
        remote.finish();
        await pumpChatUpdates(tester);
        expect(
          find.text('Repeated reply', findRichText: true),
          findsNWidgets(2),
        );
      },
    );

    for (final verbose in [false, true]) {
      for (final density in ChatDensity.values) {
        testWidgets(
          'Remote previewed completion matches an earlier interim without discarding later commentary '
          'verbose=$verbose density=$density',
          (tester) async {
            SharedPreferences.setMockInitialValues({
              'verbose_mode': verbose,
              ChatDensity.preferenceKey: density.storageValue,
            });
            await tester.binding.setSurfaceSize(const Size(800, 1600));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final remote = _ControlledRemotePrompt();
            await _pumpChat(
              tester,
              client: _ControlledChatHttpClient(const []),
              connectionId: 'earlier-interim-preview',
              sessionId: 'earlier-interim-preview',
              remoteSubmit: remote.submit,
            );
            await tester.enterText(
              find.byType(TextField),
              'Explain the result',
            );
            await tester.tap(find.byTooltip('Send'));
            await tester.pump();
            await remote.started.future;

            remote.emit('message.start', {});
            remote.emit('message.delta', {'text': 'First answer'});
            remote.emit('message.interim', {
              'text': 'First answer',
              'already_streamed': true,
            });
            remote.emit('message.delta', {'text': 'Later commentary'});
            remote.emit('message.interim', {
              'text': 'Later commentary',
              'already_streamed': true,
            });
            // No message.start between the interims and completion: the gateway
            // only sends it at turn start, so this exercises the real boundary.
            remote.emit('message.complete', {
              'text': 'First answer',
              'response_previewed': true,
            });
            remote.finish();
            await pumpChatUpdates(tester);
            expect(
              find.text('First answer', findRichText: true),
              findsOneWidget,
            );
            expect(
              find.text('Later commentary', findRichText: true),
              verbose ? findsOneWidget : findsNothing,
            );
            final completedBubble = find.byWidgetPredicate(
              (widget) =>
                  widget is MessageBubble && widget.content == 'First answer',
            );
            expect(
              tester.widget<MessageBubble>(completedBubble).density,
              density,
            );
            expect(
              find.descendant(
                of: completedBubble,
                matching: find.byKey(const Key('message-timestamp')),
              ),
              findsOneWidget,
              reason:
                  'later interim text must not suppress the completed reply time',
            );
            expect(
              find.byKey(const Key('message-timestamp')),
              findsNWidgets(2),
              reason: 'only the user and completed reply have time footers',
            );
          },
        );
      }
    }

    testWidgets(
      'Remote rendered completion matches raw interim text, then displays rendered text',
      (tester) async {
        final remote = _ControlledRemotePrompt();
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(const []),
          connectionId: 'rendered-interim-preview',
          sessionId: 'rendered-interim-preview',
          remoteSubmit: remote.submit,
        );
        await tester.enterText(find.byType(TextField), 'Render the result');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await remote.started.future;
        remote.emit('message.delta', {'text': 'Raw answer'});
        remote.emit('message.interim', {
          'text': 'Raw answer',
          'already_streamed': true,
        });
        remote.emit('message.complete', {
          'text': 'Raw answer',
          'rendered': 'Rendered answer',
          'response_previewed': true,
        });
        remote.finish();
        await pumpChatUpdates(tester);
        expect(find.text('Raw answer', findRichText: true), findsNothing);
        expect(
          find.text('Rendered answer', findRichText: true),
          findsOneWidget,
        );
      },
    );

    for (final event in ['reasoning.delta', 'reasoning.available']) {
      testWidgets(
        'Remote completed preview retains late $event without auto-expanding reasoning',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(800, 1200);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final remote = _ControlledRemotePrompt();
          await _pumpChat(
            tester,
            client: _ControlledChatHttpClient(const []),
            connectionId: 'late-$event',
            sessionId: 'late-$event',
            remoteSubmit: remote.submit,
          );
          await tester.enterText(find.byType(TextField), 'Explain $event');
          await tester.tap(find.byTooltip('Send'));
          await tester.pump();
          await remote.started.future;
          remote.emit('message.delta', {'text': 'Answer for $event'});
          final lateVerbose = event == 'reasoning.delta';
          remote.emit('reasoning.delta', {
            'text': 'Partial reasoning. ',
            'verbose': !lateVerbose,
          });
          remote.emit('message.interim', {
            'text': 'Answer for $event',
            'already_streamed': true,
          });
          remote.emit(event, {
            'text': 'Reasoning for $event',
            'verbose': lateVerbose,
          });
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Reasoning for $event'), findsNothing);
          remote.emit('message.complete', {
            'text': 'Answer for $event',
            'response_previewed': true,
          });
          remote.finish();
          await pumpChatUpdates(tester);
          final completedCards = tester
              .widgetList<GatewayReasoningCard>(
                find.byType(GatewayReasoningCard),
              )
              .toList();
          expect(
            completedCards.map((card) => card.text),
            event == 'reasoning.available'
                ? ['Reasoning for $event']
                : ['Partial reasoning. ', 'Reasoning for $event'],
          );
          expect(
            completedCards.map((card) => card.initiallyExpanded),
            everyElement(isFalse),
          );
          for (final header
              in find
                  .descendant(
                    of: find.byType(GatewayReasoningCard),
                    matching: find.text('Reasoning'),
                  )
                  .evaluate()
                  .toList()) {
            await tester.tap(find.byWidget(header.widget));
          }
          await pumpChatUpdates(tester);
          expect(find.text('Reasoning for $event'), findsOneWidget);
          expect(
            find.text('Partial reasoning. '),
            event == 'reasoning.available' ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('Answer for $event', findRichText: true),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'end action stays above compact composer, IME, and attachment panel',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(_longHistory()),
          connectionId: 'compact-end-action',
          sessionId: 'compact-end-action',
          viewInsets: const EdgeInsets.only(bottom: 220),
          initialDrafts: [_fixtureDraft('one'), _fixtureDraft('two')],
        );
        final controller = _chatListController(tester);
        controller.jumpTo(0);
        await pumpChatUpdates(tester);

        final button = find.byKey(ChatEndAffordance.buttonKey);
        final inputBar = find.byKey(const Key('chat-input-bar'));
        expect(button, findsOneWidget);
        expect(find.bySemanticsLabel('Attachment drafts'), findsOneWidget);
        expect(
          tester.getRect(button).bottom,
          lessThanOrEqualTo(tester.getRect(inputBar).top),
        );
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(500));
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'server file picker inserts an @file reference in the composer',
      (tester) async {
        await _pumpChat(
          tester,
          client: _ControlledChatHttpClient(const []),
          connectionId: 'server-file',
          sessionId: 'server-file',
          serverFilePicker: () async => '/srv/project/README.md',
        );

        await tester.tap(find.bySemanticsLabel('Add attachment'));
        await pumpChatUpdates(tester);
        expect(find.text('Browse server files'), findsOneWidget);

        await tester.tap(find.text('Browse server files'));
        await pumpChatUpdates(tester);

        final composer = tester.widget<TextField>(find.byType(TextField));
        expect(composer.controller!.text, '@file /srv/project/README.md ');
      },
    );
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _ControlledChatHttpClient client,
  required String connectionId,
  required String sessionId,
  SavedConnection? savedConnection,
  double textScale = 1,
  EdgeInsets viewInsets = EdgeInsets.zero,
  TestRemotePromptSubmit? remoteSubmit,
  GatewayTurnApplicationController? turnController,
  TestDesktopConnectionHook? connectionHook,
  NormalGatewayResume? resume,
  Future<String?> Function()? serverFilePicker,
  List<AttachmentDraft> initialDrafts = const [],
  bool settle = true,
}) async {
  final apiClient = ApiClient(
    baseUrl: 'http://fixture.example',
    apiKey: 'synthetic-test-key',
    httpClient: client,
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: viewInsets,
        ),
        child: child!,
      ),
      home: ChatScreen(
        connection:
            savedConnection ??
            SavedConnection(
              id: connectionId,
              label: 'Fixture',
              host: 'fixture.example',
              port: 8642,
              apiKey: 'synthetic-test-key',
            ),
        session: Session(
          id: sessionId,
          title: 'Fixture chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: client.serverMessages.length,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: apiClient,
        testRemotePromptSubmit: completedStockTurn(remoteSubmit),
        turnApplicationController: turnController,
        testDesktopConnectionHook: connectionHook,
        testNormalResume: resume,
        testServerFilePicker: serverFilePicker,
        testInitialAttachmentDrafts: initialDrafts,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  if (settle) await pumpChatUpdates(tester);
}

List<String> _timelineLabels(WidgetTester tester) => tester
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
        GatewayReasoningCard _ => 'reasoning',
        GatewayActivityCard c => c.activities.map((a) => a.toolId).join(','),
        _ => throw StateError('unexpected item'),
      },
    )
    .toList();

ScrollController _chatListController(WidgetTester tester) {
  return tester.widget<ListView>(find.byType(ListView).first).controller!;
}

String? _indicatorText(WidgetTester tester) {
  return tester.widget<Text>(find.byKey(ChatEndAffordance.countKey)).data;
}

SemanticsNode _goToEndSemantics(WidgetTester tester) {
  return tester.getSemantics(find.bySemanticsLabel('Go to end'));
}

Future<void> _dragToEnd(
  WidgetTester tester,
  ScrollController controller,
) async {
  for (
    var attempt = 0;
    attempt < 12 &&
        controller.position.pixels < controller.position.maxScrollExtent - 1;
    attempt++
  ) {
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await pumpChatUpdates(tester);
  }
}

AttachmentDraft _fixtureDraft(String id) {
  return AttachmentDraft(
    id: id,
    cachedPath: 'C:/synthetic/$id.txt',
    name: '$id.txt',
    byteLength: 4,
    mediaType: 'text/plain',
    kind: AttachmentDraftKind.genericFile,
  );
}

List<Map<String, dynamic>> _longHistory() {
  return [
    for (var index = 0; index < 24; index++)
      {
        'role': index.isEven ? 'user' : 'assistant',
        'content':
            'message $index\n${List.filled(5, 'history line').join('\n')}',
      },
  ];
}

class _ControlledRemotePrompt {
  Completer<void> started = Completer<void>();
  Completer<void>? _completion;
  StreamCallback? _onEvent;

  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) async {
    onSent();
    _onEvent = onEvent;
    _completion = Completer<void>();
    if (!started.isCompleted) started.complete();
    await _completion!.future;
  }

  void emit(String type, Map<String, dynamic> data) {
    _onEvent!(StreamEvent(type: type, data: data));
  }

  void finish() {
    _completion!.complete();
  }

  void fail() => _completion!.completeError(
    JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
  );
}

class _ControlledChatHttpClient extends http.BaseClient {
  List<Map<String, dynamic>> serverMessages;
  final Completer<void> postStarted = Completer<void>();
  final Completer<void>? historyGate;
  final int historyStatusCode;
  StreamController<List<int>>? _completionStream;
  String? lastRequestBody;

  _ControlledChatHttpClient(
    List<Map<String, dynamic>> messages, {
    this.historyGate,
    this.historyStatusCode = 200,
  }) : serverMessages = List<Map<String, dynamic>>.from(messages);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      await historyGate?.future;
      return _jsonResponse({
        'data': serverMessages,
      }, statusCode: historyStatusCode);
    }
    if (request.method == 'POST' &&
        request.url.path.endsWith('/v1/chat/completions')) {
      lastRequestBody = (request as http.Request).body;
      _completionStream = StreamController<List<int>>();
      if (!postStarted.isCompleted) postStarted.complete();
      return http.StreamedResponse(
        _completionStream!.stream,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    return _jsonResponse({'error': 'unexpected request'}, statusCode: 404);
  }

  void emitToken(String token) {
    _completionStream!.add(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': token},
            },
          ],
        })}\n\n',
      ),
    );
  }

  void emitFragmented(String frames) {
    for (final byte in utf8.encode(frames)) {
      _completionStream!.add([byte]);
    }
  }

  void finish(List<Map<String, dynamic>> finalMessages) {
    serverMessages = List<Map<String, dynamic>>.from(finalMessages);
    _completionStream!
      ..add(utf8.encode('data: [DONE]\n\n'))
      ..close();
  }

  http.StreamedResponse _jsonResponse(Object body, {int statusCode = 200}) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}
