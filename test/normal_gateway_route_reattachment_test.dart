// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_route_reattachment_test.dart
// Base 4a53e32 blob baa0e1c4f79d32480b3f7a370ee73d12e1878bae; SHA256 4651fb0e02e0edf581f4cba43b50d36639d333a26fbf02b5c89aae3703b3dc82.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
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
import 'support/recording_turn_notification_sink.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': true}));

  for (final (following, width) in [
    (true, 400.0),
    (false, 400.0),
    (true, 1000.0),
    (false, 1000.0),
  ]) {
    testWidgets(
      'owner stream updates open task aliases and final history without changing parent (following=$following, width=$width)',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final remote = _Remote();
        final history = _OwnerTaskHistory();
        final sink = RecordingTurnNotificationSink();
        final notifications = TurnNotificationService(sink: sink);
        notificationPrefs.value = NotificationPrefs.defaults;
        controller.normalSessionFor(
          _connection,
          submit: remote.submit,
          notifications: notifications,
        );
        await _open(tester, controller, remote, taskHistory: history);
        await tester.enterText(find.byType(TextField), 'Delegate');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump();
        remote.event('subagent.start', {
          'subagent_id': 'runtime-root',
          'child_session_id': 'child-root',
          'goal': 'Inspect',
        });
        await tester.pump();
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Keep next draft');
        final card = tester.widget<GatewaySubagentCard>(
          find.byType(GatewaySubagentCard),
        );
        remote.event('message.delta', {
          'text': List.filled(80, 'Parent stream line.\n\n').join(),
        });
        await tester.pump();
        await tester.pump();
        final parentScroll = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ChatScreen),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        expect(parentScroll.maxScrollExtent, greaterThan(0));
        // Finish the composer's reveal/expansion animations before pinning a
        // reader position; the stream itself remains controlled and pending.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        parentScroll.jumpTo(parentScroll.maxScrollExtent);
        if (!following) {
          await tester.drag(find.byType(ListView).first, const Offset(0, 400));
          parentScroll.jumpTo(parentScroll.pixels);
          await tester.pump();
        }
        final offset = parentScroll.pixels;
        // Queue an owner follow callback, then open before it can execute.
        remote.event('message.delta', {'text': 'Queued before modal.\n'});
        card.onOpenTask!(card.activities.single);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final overlay = tester.widget<DelegatedTaskTimeline>(
          find.byType(DelegatedTaskTimeline),
        );
        expect(history.requests, [('child-root', null)]);
        expect(
          parentScroll.pixels,
          offset,
          reason: 'Opening the overlay preserves parent offset',
        );
        // Hold a read while a new advertised tip and terminal status arrive.
        final held = Completer<TaskHistoryPage>();
        history.gate = held;
        unawaited(overlay.controller.refresh());
        await tester.pump();
        remote.event('subagent.text', {
          'subagent_id': 'runtime-root',
          'child_session_id': 'child-tip',
          'text': 'Child progressing',
        });
        remote.event('subagent.text', {
          'subagent_id': 'new-runtime-alias',
          'child_session_id': 'child-tip',
          'text': 'Alias progressing',
        });
        remote.event('message.delta', {
          'text': List.filled(20, 'More parent text.\n\n').join(),
        });
        await tester.pump();
        expect(overlay.controller.task.livePreview, 'Alias progressing');
        await tester.tap(find.text('Live preview from parent events'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('Alias progressing'), findsOneWidget);
        expect(parentScroll.pixels, offset);
        remote.event('subagent.complete', {
          'subagent_id': 'new-runtime-alias',
          'child_session_id': 'child-tip',
          'status': 'failed',
        });
        await tester.pump();
        expect(find.text('Status: Failed'), findsOneWidget);
        history.gate = null;
        history.finalRow = true;
        held.complete(
          const TaskHistoryPage(
            rows: [],
            sessionId: 'child-root',
            offset: 0,
            lineage: ['child-root'],
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(history.requests.last, ('child-root', 'child-tip'));
        expect(
          overlay.controller.rows.single['content'],
          'Recorded child final',
        );
        await tester.scrollUntilVisible(
          find.text('Recorded child final', findRichText: true),
          200,
          scrollable: find
              .descendant(
                of: find.byType(DelegatedTaskTimeline),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          find.text('Recorded child final', findRichText: true),
          findsOneWidget,
        );
        expect(
          controller
              .normalSessionFor(_connection)
              .findChat('local-chat')!
              .snapshot
              .subagents,
          hasLength(1),
        );
        expect(parentScroll.pixels, offset);
        expect(
          tester
              .widget<TextField>(find.byType(TextField, skipOffstage: false))
              .controller!
              .text,
          'Keep next draft',
        );
        if (following) {
          await tester.tap(find.widgetWithText(TextButton, 'Close'));
        } else {
          await tester.binding.handlePopRoute();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(history.closed, isTrue);
        expect(parentScroll.pixels, offset);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Keep next draft',
        );
        expect(remote.submissions, 1);
        expect(sink.shown, isEmpty);
        // Parent settlement belongs to the application, not the modal or route.
        controller.setLifecycle(background: true, backgroundWorkEnabled: true);
        await tester.pumpWidget(const SizedBox.shrink());
        remote.event('message.complete', {'text': 'Parent final'});
        remote.event('turn.end', {'status': 'completed'});
        remote.rpc.complete();
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        expect(sink.shown.where((n) => !n.ongoing), hasLength(1));
        expect(sink.shown.single.payload, contains('stored-chat'));
        expect(sink.shown.single.payload, contains(_connection.id));
        expect(controller.hasActiveTurn, isFalse);
      },
    );
  }

  testWidgets(
    'notification-style push keeps both real ChatScreens mounted without build-time notifications',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote();
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'One prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      remote.event('message.delta', {'text': 'Active B'});
      await tester.pump();
      final owner = controller
          .normalSessionFor(_connection)
          .findChat('local-chat')!;
      final turn = owner.turnId;
      await _open(
        tester,
        controller,
        remote,
        id: 'stored-chat',
        key: const ValueKey('notification-route'),
        push: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));
      expect(find.text('Active B'), findsOneWidget);
      expect(owner.turnId, turn);
      expect(owner.snapshot.hasActiveTurn, isTrue);
      expect(remote.submissions, 1);
      remote.event('message.delta', {'text': ' continued'});
      await tester.pump();
      expect(find.text('Active B continued'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(ChatScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Active B continued'), findsOneWidget);
      expect(remote.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'pop/reopen restores owner deltas and tools, terminal while absent settles',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      final remote = _Remote();
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'One prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(remote.submissions, 1);
      remote.event('message.delta', {'text': 'Before pop. '});
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      remote.event('message.delta', {'text': 'Continued while absent.'});
      remote.event('tool.start', {'tool': 'read_file', 'tool_id': 'call-1'});
      expect(controller.hasActiveTurn, isTrue);
      await _open(tester, controller, remote, id: 'stored-chat');
      expect(find.textContaining('Continued while absent.'), findsOneWidget);
      expect(remote.submissions, 1);
      expect(find.byTooltip('Stop response'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      remote.event('tool.complete', {
        'tool': 'read_file',
        'tool_id': 'call-1',
        'status': 'completed',
      });
      remote.event('message.complete', {
        'text': 'Finished while no route existed.',
      });
      remote.rpc.complete();
      await tester.pump();
      await tester.pump();
      expect(controller.hasActiveTurn, isFalse);
      await _open(tester, controller, remote, id: 'stored-chat');
      expect(find.text('Finished while no route existed.'), findsOneWidget);
      expect(find.byTooltip('Stop response'), findsNothing);
      expect(remote.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.close();
    },
  );

  for (final completesAway in [false, true]) {
    testWidgets(
      'reasoning defaults collapsed and resets on canonical reopen (completesAway=$completesAway)',
      (tester) async {
        // C/R headings occupy real space; keep both source cards tappable.
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final remote = _Remote();
        await _open(tester, controller, remote, navigable: true);
        await tester.tap(find.text('Open chat'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Explain the result');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump();
        remote.event('reasoning.delta', {
          'text': 'First reasoning. ',
          'verbose': true,
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        bool expanded() => tester
            .widget<ExpansionTile>(
              find.descendant(
                of: find.byType(GatewayReasoningCard),
                matching: find.byType(ExpansionTile),
              ),
            )
            .controller!
            .isExpanded;

        expect(expanded(), isFalse);
        expect(find.text('First reasoning. '), findsNothing);
        // MAIN81D C/R geometry: reveal the actual lazy header before tapping.
        await tester.ensureVisible(
          find.descendant(
            of: find.byType(GatewayReasoningCard),
            matching: find.text('Reasoning'),
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byType(GatewayReasoningCard),
            matching: find.text('Reasoning'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(expanded(), isTrue);
        expect(find.text('First reasoning. '), findsOneWidget);
        remote.event('reasoning.delta', {'text': 'More reasoning.'});
        await tester.pump();
        expect(expanded(), isTrue);
        expect(find.text('First reasoning. More reasoning.'), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ChatScreen), findsNothing);
        expect(find.text('Open chat'), findsOneWidget);
        if (completesAway) {
          remote.event('message.complete', {'text': 'Explained result'});
          remote.rpc.complete();
          await tester.pump();
          await tester.pump();
        }
        await _open(
          tester,
          controller,
          remote,
          id: 'stored-chat',
          navigable: true,
        );
        await tester.tap(find.text('Open chat'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(expanded(), isFalse);
        expect(find.text('First reasoning. More reasoning.'), findsNothing);
        // The reasoning itself is retained; only the expansion choice resets.
        expect(
          tester
              .widget<GatewayReasoningCard>(find.byType(GatewayReasoningCard))
              .text,
          'First reasoning. More reasoning.',
        );
        if (!completesAway) {
          remote.event('reasoning.available', {
            'text': 'Final reasoning',
            'verbose': true,
          });
          await tester.pump();
          expect(expanded(), isFalse);
          expect(find.text('Final reasoning'), findsNothing);
          remote.event('message.complete', {'text': 'Explained result'});
          remote.rpc.complete();
          await tester.pump();
        }
        await tester.ensureVisible(
          find.descendant(
            of: find.byType(GatewayReasoningCard),
            matching: find.text('Reasoning'),
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byType(GatewayReasoningCard),
            matching: find.text('Reasoning'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(expanded(), isTrue);
        expect(
          find.text(
            completesAway
                ? 'First reasoning. More reasoning.'
                : 'Final reasoning',
          ),
          findsOneWidget,
        );
        expect(remote.submissions, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  for (final completesAway in [false, true]) {
    testWidgets(
      'tool sections reset on canonical chat reopen and show only the current/latest call (completesAway=$completesAway)',
      (tester) async {
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        // Preserve the retained wire tools rather than hydrating assistant-only
        // canonical history, which deliberately retires optimistic tool rows.
        final remote = _Remote()..history = [];
        await _open(tester, controller, remote);
        await tester.enterText(find.byType(TextField), 'Inspect files');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump();
        remote.event('tool.start', {
          'tool': 'terminal',
          'tool_id': 'call-1',
          'detail': 'First call detail',
        });
        remote.event('tool.complete', {
          'tool': 'terminal',
          'tool_id': 'call-1',
        });
        remote.event('tool.start', {
          'tool': 'read_file',
          'tool_id': 'call-2',
          'detail': 'Current call detail',
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        bool expanded() => tester
            .widget<ExpansionTile>(
              find.descendant(
                of: find.byType(GatewayActivityCard),
                matching: find.byType(ExpansionTile),
              ),
            )
            .controller!
            .isExpanded;

        expect(expanded(), isFalse);
        expect(find.text('Read file: Running'), findsOneWidget);
        expect(find.textContaining('Terminal'), findsNothing);
        await tester.ensureVisible(find.text('Tool activity'));
        await tester.pump();
        await tester.tap(find.text('Tool activity'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(expanded(), isTrue);
        expect(find.text('First call detail'), findsOneWidget);
        expect(find.text('Current call detail'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (completesAway) {
          remote.event('tool.complete', {
            'tool': 'read_file',
            'tool_id': 'call-2',
          });
          remote.event('message.complete', {'text': 'Inspection finished'});
          remote.rpc.complete();
          await tester.pump();
          await tester.pump();
        }
        await _open(tester, controller, remote, id: 'stored-chat');
        await tester.pump(const Duration(milliseconds: 400));
        expect(expanded(), isFalse);
        expect(
          find.text('Read file: ${completesAway ? 'Completed' : 'Running'}'),
          findsOneWidget,
        );
        expect(find.textContaining('Terminal'), findsNothing);
        expect(find.text('First call detail'), findsNothing);
        expect(find.text('Current call detail'), findsNothing);

        if (!completesAway) {
          remote.event('tool.start', {
            'tool': 'search_files',
            'tool_id': 'call-3',
          });
          await tester.pump();
          await tester.pump();
          expect(expanded(), isFalse);
          expect(find.text('Search files: Running'), findsOneWidget);
          expect(find.textContaining('Read file'), findsNothing);
          remote.event('message.complete', {'text': 'Inspection finished'});
          remote.rpc.complete();
          await tester.pump();
        }
        expect(remote.submissions, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets(
    'covered canonical visit retains its own tool pin while another visit closes',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote()..history = [];
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'Inspect once');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      remote.event('tool.start', {
        'tool': 'terminal',
        'detail': 'Retained call detail',
      });
      await tester.pump();
      bool expanded() => tester
          .widget<ExpansionTile>(
            find.descendant(
              of: find.byType(GatewayActivityCard),
              matching: find.byType(ExpansionTile),
            ),
          )
          .controller!
          .isExpanded;
      expect(expanded(), isFalse);
      await tester.ensureVisible(find.text('Tool activity'));
      await tester.pump();
      await tester.tap(find.text('Tool activity'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(expanded(), isTrue);
      final originalState = tester.state(find.byType(ChatScreen));
      await _open(
        tester,
        controller,
        remote,
        id: 'stored-chat',
        key: const ValueKey('independent-tool-visit'),
        push: true,
      );
      expect(expanded(), isFalse);
      expect(find.text('Retained call detail'), findsNothing);
      await tester.ensureVisible(find.text('Tool activity'));
      await tester.pump();
      await tester.tap(find.text('Tool activity'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(expanded(), isTrue);
      await tester.ensureVisible(find.text('Tool activity'));
      await tester.pump();
      await tester.tap(find.text('Tool activity'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(expanded(), isFalse);
      remote.event('tool.progress', {
        'tool': 'terminal',
        'tool_id': 'late-covered-id',
        'detail': 'Updated call detail',
      });
      await tester.pump();
      expect(expanded(), isFalse);
      Navigator.of(tester.element(find.byType(ChatScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        identical(tester.state(find.byType(ChatScreen)), originalState),
        isTrue,
      );
      expect(expanded(), isTrue);
      expect(find.text('Updated call detail'), findsOneWidget);
      final owner = controller
          .normalSessionFor(_connection)
          .findChat('stored-chat')!;
      expect(owner.snapshot.tools.single.toolId, 'late-covered-id');
      expect(remote.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _open(tester, controller, remote, id: 'stored-chat');
      await tester.pump(const Duration(milliseconds: 400));
      expect(expanded(), isFalse);
      expect(find.text('Terminal: Working'), findsOneWidget);
      expect(find.text('Updated call detail'), findsNothing);
      await tester.ensureVisible(find.text('Tool activity'));
      await tester.pump();
      await tester.tap(find.text('Tool activity'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Updated call detail'), findsOneWidget);
      expect(remote.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'late latest history retires a settled optimistic timeline on real route reopen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote()..history = [];
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'One prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      remote.event('message.start', {}, turnId: 'A');
      remote.event('message.delta', {'text': 'Wire reply'}, turnId: 'A');
      remote.event('tool.start', {
        'tool': 'read_file',
        'tool_id': 'optimistic-only',
      }, turnId: 'A');
      remote.event('message.complete', {'text': 'Wire reply'}, turnId: 'A');
      // A correlated lifecycle can finish before HTTP persistence is visible.
      // Stock ID-less terminals are separately covered by reconciliation tests.
      remote.event('turn.end', {'status': 'completed'}, turnId: 'A');
      remote.rpc.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final owner = controller
          .normalSessionFor(_connection)
          .findChat('stored-chat')!;
      expect(controller.hasActiveTurn, isFalse);
      expect(find.text('Wire reply'), findsOneWidget);
      expect(find.byType(GatewayActivityCard), findsOneWidget);
      expect(owner.snapshot.tools, hasLength(1));
      final before = remote.historyRequests;
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
        key: const ValueKey('late-canonical'),
      );
      await tester.pump();
      expect(remote.historyRequests, greaterThan(before));
      expect(
        inChatSource(find.text('One prompt'), ChatDisplaySource.canonical),
        findsOneWidget,
      );
      expect(
        inChatSource(find.text('One prompt'), ChatDisplaySource.received),
        findsOneWidget,
      );
      expect(find.text('Canonical reply'), findsOneWidget);
      expect(find.text('Wire reply'), findsOneWidget);
      expect(
        inChatSource(
          find.byType(GatewayActivityCard),
          ChatDisplaySource.received,
        ),
        findsOneWidget,
      );
      expect(owner.snapshot.displayRows, isNotEmpty);
      expect(owner.snapshot.tools, isNotEmpty);
      expect(owner.snapshot.timeline.runs, isNotEmpty);
      expect(remote.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'canonical reopen preserves independent completed wire output after delayed persistence',
    (tester) async {
      // End-aligned reopening and collapsed metadata add real row height.
      // Keep both complete source projections mounted for the order assertion;
      // lazy eviction in a short viewport is not missing canonical history.
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final remote = _Remote();
      var durable = <Map<String, dynamic>>[
        {'id': 1, 'role': 'user', 'content': 'Previous question'},
        {'id': 2, 'role': 'assistant', 'content': 'Previous answer'},
      ];
      var settlementReads = 0;
      final session = controller.normalSessionFor(
        _connection,
        submit: remote.submit,
        history: (_) async {
          settlementReads++;
          return durable;
        },
      );
      await session.ready;
      await _open(tester, controller, remote, history: () => durable);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ask');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      remote.event('message.delta', {'text': 'Wire preview'});
      remote.event('message.complete', {'text': 'Wire preview'});
      remote.rpc.complete();
      await tester.pumpAndSettle();
      final owner = session.findChat('stored-chat')!;
      expect(owner.phase, NormalGatewayTurnPhase.completed);
      expect(owner.snapshot.rowFloor, 2);
      expect(settlementReads, 1);
      expect(owner.snapshot.historyRows.last['id'], 2);
      expect(find.text('Wire preview'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      durable = [
        ...durable,
        {'id': 3, 'role': 'user', 'content': 'Ask'},
        {'id': 4, 'role': 'assistant', 'content': 'Canonical final'},
      ];
      await _open(
        tester,
        controller,
        remote,
        id: 'stored-chat',
        key: const ValueKey('canonical-reopen'),
        history: () => durable,
      );
      await tester.pumpAndSettle();
      expect(session.findChat('stored-chat'), same(owner));
      expect(owner.snapshot.historyRows.last['content'], 'Canonical final');
      await tester.scrollUntilVisible(
        find.text('Previous question'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(owner.snapshot.displayRows.last['content'], 'Wire preview');
      expect(owner.snapshot.timeline.runs, isNotEmpty);
      expect(
        tester
            .widgetList<MessageBubble>(
              inChatSource(
                find.byType(MessageBubble),
                ChatDisplaySource.canonical,
              ),
            )
            .map((bubble) => bubble.content),
        ['Previous question', 'Previous answer', 'Ask', 'Canonical final'],
      );
      await tester.scrollUntilVisible(
        inChatSource(find.text('Wire preview'), ChatDisplaySource.received),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        inChatSource(find.text('Wire preview'), ChatDisplaySource.received),
        findsOneWidget,
      );
      expect(find.byTooltip('Stop response'), findsNothing);
      expect(remote.submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('older-only paging preserves completed wire chronology', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = GatewayTurnApplicationController();
    addTearDown(controller.close);
    final remote = _Remote();
    final latest = <Map<String, dynamic>>[
      for (var id = 11; id <= 60; id++)
        {
          'id': id,
          'role': id.isOdd ? 'user' : 'assistant',
          'content': 'History $id',
        },
    ];
    final session = controller.normalSessionFor(
      _connection,
      submit: remote.submit,
      history: (_) async => latest,
    );
    await session.ready;
    final offsets = <int>[];
    await _open(
      tester,
      controller,
      remote,
      historyClient: MockClient((request) async {
        if (request.url.path == '/api/sessions/stored-chat') {
          return http.Response(
            jsonEncode({
              'session': {'id': 'stored-chat', 'archived': false},
            }),
            200,
          );
        }
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        offsets.add(offset);
        return http.Response(
          jsonEncode({
            'data': offset == 0
                ? latest
                : [
                    {'id': 1, 'role': 'user', 'content': 'Older question'},
                    {'id': 2, 'role': 'assistant', 'content': 'Older answer'},
                  ],
          }),
          200,
        );
      }),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ask');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    remote.event('message.delta', {'text': 'Before tool'});
    remote.event('tool.start', {'tool': 'read_file', 'tool_id': 't1'});
    remote.event('message.delta', {'text': 'After tool'});
    remote.event('tool.complete', {
      'tool': 'read_file',
      'tool_id': 't1',
      'status': 'completed',
    });
    remote.event('message.complete', {'text': 'Before toolAfter tool'});
    remote.rpc.complete();
    await tester.pumpAndSettle();
    final owner = session.findChat('stored-chat')!;
    final retained = owner.snapshot;
    expect(retained.phase, NormalGatewayTurnPhase.completed);
    expect(retained.rowFloor, 60);
    final olderButton = find.byKey(const Key('chat-load-older')).hitTestable();
    await tester.scrollUntilVisible(
      olderButton,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(olderButton);
    await tester.pumpAndSettle();
    expect(offsets, [0, 50]);
    expect(owner.snapshot.historyRows, retained.historyRows);
    expect(owner.snapshot.displayRows, retained.displayRows);
    expect(owner.snapshot.timeline, same(retained.timeline));
    final parentScroll = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    parentScroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Older question'), findsOneWidget);
    expect(find.text('Older answer'), findsOneWidget);
    parentScroll.jumpTo(parentScroll.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('After tool'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final labels = tester
        .widgetList(
          find.byWidgetPredicate(
            (widget) =>
                widget is MessageBubble || widget is GatewayActivityCard,
          ),
        )
        .map(
          (widget) => switch (widget) {
            MessageBubble bubble => bubble.content,
            GatewayActivityCard _ => 'tool',
            _ => throw StateError('Unexpected widget'),
          },
        )
        .toList();
    expect(labels.sublist(labels.length - 4), [
      'Ask',
      'Before tool',
      'tool',
      'After tool',
    ]);
    expect(remote.submissions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final width in [400.0, 1000.0]) {
    testWidgets(
      'canonical parent hydration preserves open child observation ($width)',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final remote = _Remote();
        final history = _OwnerTaskHistory();
        var durable = <Map<String, dynamic>>[];
        final session = controller.normalSessionFor(
          _connection,
          submit: remote.submit,
          history: (_) async => durable,
        );
        await session.ready;
        await _open(tester, controller, remote, taskHistory: history);
        await tester.enterText(find.byType(TextField), 'Delegate');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump();
        remote.event('subagent.start', {
          'subagent_id': 'runtime-root',
          'child_session_id': 'child-root',
          'goal': 'Inspect',
        });
        remote.event('subagent.text', {
          'subagent_id': 'runtime-root',
          'child_session_id': 'child-tip',
          'text': 'Progress',
        });
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'Keep draft');
        final card = tester.widget<GatewaySubagentCard>(
          find.byType(GatewaySubagentCard),
        );
        card.onOpenTask!(card.activities.single);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final overlay = tester.widget<DelegatedTaskTimeline>(
          find.byType(DelegatedTaskTimeline),
        );
        expect(overlay.controller.task.childSessionId, 'child-root');
        durable = [
          {'id': 1, 'role': 'user', 'content': 'Delegate'},
          {'id': 2, 'role': 'assistant', 'content': 'Canonical parent final'},
        ];
        remote.event('message.complete', {'text': 'Wire parent preview'});
        remote.rpc.complete();
        for (var i = 0; i < 6; i++) {
          await tester.pump();
        }
        final owner = session.findChat('stored-chat')!;
        expect(owner.phase, NormalGatewayTurnPhase.completed);
        expect(
          owner.snapshot.displayRows.last['content'],
          'Wire parent preview',
        );
        expect(owner.snapshot.subagents, isNotEmpty);
        remote.event('subagent.complete', {
          'subagent_id': 'new-runtime-alias',
          'child_session_id': 'child-tip',
          'status': 'failed',
        });
        await tester.pump();
        expect(find.text('Status: Failed'), findsOneWidget);
        expect(overlay.controller.task.childSessionId, 'child-root');
        expect(overlay.controller.task.latestChildSessionId, 'child-tip');
        expect(owner.snapshot.subagents.single.childSessionId, 'child-root');
        expect(
          owner.snapshot.displayRows.last['content'],
          'Wire parent preview',
        );
        expect(owner.snapshot.hasActiveTurn, isFalse);
        expect(remote.submissions, 1);
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Keep draft',
        );
        final canonicalFinal = inChatSource(
          find.text('Canonical parent final'),
          ChatDisplaySource.canonical,
        );
        final receivedPreview = inChatSource(
          find.text('Wire parent preview'),
          ChatDisplaySource.received,
        );
        await tester.scrollUntilVisible(
          canonicalFinal,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(canonicalFinal, findsOneWidget);
        await tester.scrollUntilVisible(
          receivedPreview,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(receivedPreview, findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  testWidgets(
    'retained owner preserves timeline order across snapshots and route reattachment',
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
      remote.event('message.delta', {'text': 'Commentary A'});
      remote.event('message.interim', {
        'text': 'Commentary A',
        'already_streamed': true,
      });
      remote.event('tool.start', {'tool': 'read_file', 'tool_id': 't1'});
      remote.event('message.delta', {'text': 'Commentary B'});
      remote.event('reasoning.delta', {'text': 'Exposed reasoning'});
      remote.event('tool.start', {'tool': 'read_file', 'tool_id': 't2'});
      await tester.pump();
      List<String> labels() => tester
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
              GatewayActivityCard c =>
                c.activities.map((a) => a.toolId).join(','),
              _ => throw StateError('Unexpected timeline widget'),
            },
          )
          .toList();
      expect(labels(), [
        'One prompt',
        'Commentary A',
        't1',
        'Commentary B',
        'reasoning',
        't2',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      remote.event('tool.complete', {
        'tool': 'read_file',
        'tool_id': 't1',
        'status': 'completed',
      });
      remote.event('message.delta', {'text': ' continued'});
      await _open(
        tester,
        controller,
        remote,
        id: 'stored-chat',
        key: const ValueKey('timeline-remount'),
      );
      expect(labels(), [
        'One prompt',
        'Commentary A',
        't1',
        'Commentary B',
        'reasoning',
        't2',
        ' continued',
      ]);
      expect(remote.submissions, 1);
      remote.event('message.complete', {'text': 'Commentary B continued'});
      remote.rpc.complete();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'duplicate route cannot send a second turn through stored alias',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      final remote = _Remote();
      await _open(tester, controller, remote);
      await tester.enterText(find.byType(TextField), 'First turn');
      final oldSend = tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed!;
      oldSend();
      oldSend();
      await tester.pump();
      await tester.pump();
      await _open(
        tester,
        controller,
        remote,
        id: 'stored-chat',
        key: const ValueKey('replacement'),
      );
      await tester.enterText(find.byType(TextField), 'Keep this newer draft');
      expect(find.byTooltip('Send'), findsOneWidget);
      expect(find.byTooltip('Stop response'), findsOneWidget);
      // The replacement can attempt guidance, never reserve or submit a
      // second turn through the same app-owned stored/local alias.
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      expect(remote.submissions, 1);
      remote.event('turn.end', {'status': 'completed'});
      remote.rpc.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this newer draft',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.close();
    },
  );

  for (final newer in <String?>[null, 'A newer draft', '']) {
    testWidgets(
      'pre-wire rejection after pop restores only the owned draft: $newer',
      (tester) async {
        final controller = GatewayTurnApplicationController();
        final remote = _Remote()..emitOnSent = false;
        await _open(tester, controller, remote);
        await tester.enterText(find.byType(TextField), 'Unsent after handoff');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await tester.pump();
        expect(remote.submissions, 1);
        if (newer != null) {
          await tester.enterText(find.byType(TextField), 'Intervening edit');
          await tester.enterText(find.byType(TextField), newer);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        remote.rpc.completeError(StateError('Definite pre-wire rejection'));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(controller.hasActiveTurn, isFalse);
        await _open(
          tester,
          controller,
          remote,
          key: const ValueKey('reattached'),
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          newer ?? 'Unsent after handoff',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await controller.close();
      },
    );

    testWidgets(
      'dispose before handoff cancels admission and preserves draft: $newer',
      (tester) async {
        final controller = GatewayTurnApplicationController();
        final remote = _Remote();
        final ensure = Completer<void>();
        await _open(
          tester,
          controller,
          remote,
          prepare: (_, _) => ensure.future,
        );
        await tester.enterText(
          find.byType(TextField),
          'Admitted unsent prompt',
        );
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        if (newer != null) {
          await tester.enterText(find.byType(TextField), 'Intervening edit');
          await tester.enterText(find.byType(TextField), newer);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(controller.hasActiveTurn, isFalse);
        ensure.complete();
        await tester.pump();
        await tester.pump();
        expect(remote.submissions, 0);
        expect(
          await ComposerDraftStore.read(
            connectionId: _connection.id,
            sessionId: 'local-chat',
          ),
          (newer ?? 'Admitted unsent prompt').isEmpty
              ? isNull
              : newer ?? 'Admitted unsent prompt',
        );
        await _open(tester, controller, remote, prepare: (_, _) async {});
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          newer ?? 'Admitted unsent prompt',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await controller.close();
      },
    );
  }
}

final _connection = SavedConnection(
  id: 'app-owner-widget',
  label: 'Fixture',
  host: 'fixture.invalid',
  port: 8642,
  apiKey: 'fixture',
);

Future<void> _open(
  WidgetTester tester,
  GatewayTurnApplicationController controller,
  _Remote remote, {
  String id = 'local-chat',
  Key? key,
  Future<void> Function(String, String)? prepare,
  bool push = false,
  TaskHistorySource? taskHistory,
  List<Map<String, dynamic>> Function()? history,
  http.Client? historyClient,
  bool navigable = false,
}) async {
  final screen = ChatScreen(
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
      isLocalDraft: prepare != null,
    ),
    projectWorkingDirectory: prepare == null ? null : '/project',
    turnApplicationController: controller,
    testApiClient: ApiClient(
      baseUrl: _connection.baseUrl,
      apiKey: 'fixture',
      httpClient:
          historyClient ??
          MockClient((_) async {
            remote.historyRequests++;
            return http.Response(
              history == null
                  ? remote.historyJson
                  : jsonEncode({'data': history()}),
              200,
            );
          }),
    ),
    testRemotePromptSubmit: remote.submit,
    testNormalResume:
        ({required localSessionId, required storedSessionId}) async =>
            ResumedGatewaySession(
              runtimeSessionId: 'runtime',
              running: !remote.completed,
              status: remote.completed ? 'completed' : null,
            ),
    testStoredSessionKey: (_) => 'stored-chat',
    testLegacyProjectSessionEnsure: prepare,
    testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
    testTaskHistorySource: taskHistory == null ? null : () => taskHistory,
  );
  if (push) {
    unawaited(
      Navigator.of(
        tester.element(find.byType(ChatScreen)),
      ).push<void>(MaterialPageRoute(builder: (_) => screen)),
    );
  } else {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _ChatRouteFixture(navigable: navigable, child: screen),
      ),
    );
  }
  await tester.pump();
  await tester.pump();
  if (push) {
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }
}

class _ChatRouteFixture extends StatelessWidget {
  const _ChatRouteFixture({required this.navigable, required this.child});

  final bool navigable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!navigable) return child;
    return Scaffold(
      body: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => child)),
        child: const Text('Open chat'),
      ),
    );
  }
}

class _OwnerTaskHistory implements TaskHistorySource {
  final requests = <(String, String?)>[];
  Completer<TaskHistoryPage>? gate;
  bool finalRow = false;
  bool closed = false;

  @override
  Future<TaskHistoryPage> fetch(
    String childId,
    int offset, {
    String? latestChildId,
    String? currentSessionId,
  }) async {
    requests.add((childId, latestChildId));
    if (gate != null) return gate!.future;
    return TaskHistoryPage(
      rows: [
        if (finalRow)
          {'id': 1, 'role': 'assistant', 'content': 'Recorded child final'},
      ],
      sessionId: latestChildId ?? childId,
      offset: offset,
      lineage: [childId, ?latestChildId],
    );
  }

  @override
  void close() {
    closed = true;
  }
}

class _Remote {
  final rpc = Completer<void>();
  StreamCallback? onEvent;
  int submissions = 0;
  bool emitOnSent = true;
  bool completed = false;
  String finalText = '';
  int historyRequests = 0;
  List<Map<String, dynamic>>? history;
  String get historyJson => jsonEncode({
    'data':
        history ??
        (completed
            ? [
                {'id': 2, 'role': 'assistant', 'content': finalText},
              ]
            : []),
  });
  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) {
    submissions++;
    this.onEvent = onEvent;
    if (emitOnSent) onSent();
    return rpc.future;
  }

  void event(String type, Map<String, dynamic> data, {String? turnId}) {
    if (type == 'message.complete' || type == 'turn.end') {
      completed = true;
      finalText = data['text']?.toString() ?? 'Final';
    }
    final id = turnId ?? 'route-turn-$submissions';
    onEvent!(StreamEvent(type: 'turn.start', data: const {}, turnId: id));
    onEvent!(StreamEvent(type: type, data: data, turnId: id));
    if (type == 'message.complete') {
      onEvent!(
        StreamEvent(
          type: 'turn.end',
          data: const {'status': 'completed'},
          turnId: id,
        ),
      );
    }
  }
}
