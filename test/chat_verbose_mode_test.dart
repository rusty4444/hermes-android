import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/background_report_card.dart';
import 'package:hermes_android/core/widgets/chat_activity_bar.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart' show mockChatImageRecovery;

// Exercise the real route, the application-owned stock reducer, and the real
// GatewayChatClient SSE parser. The fixture never turns RPC completion into a
// lifecycle terminal: each test supplies owned turn.end or post-ACK resume.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    mockChatImageRecovery();
  });

  testWidgets('quiet saved history is users plus final replies, not a trace', (
    tester,
  ) async {
    final f = _StockFixture();
    _cleanup(tester, f);
    f.history.rows = [
      _row(1, 'user', 'Saved question'),
      _row(
        2,
        'assistant',
        'I will inspect',
        extra: {
          'tool_calls': [
            {
              'id': 'saved-tool',
              'function': {'name': 'terminal', 'arguments': '{}'},
            },
          ],
        },
      ),
      _row(
        3,
        'tool',
        'Saved tool output',
        extra: {'name': 'terminal', 'tool_call_id': 'saved-tool'},
      ),
      _row(
        4,
        'assistant',
        'Saved final',
        extra: {
          '_gateway_reasoning': 'Saved reasoning detail',
          'model': 'private-model-metadata',
          'status': 'completed',
        },
      ),
      _reportRow(5),
    ];
    await f.open(tester);
    expect(_bubbles(tester), ['Saved question', 'Saved final']);
    _expectQuiet(tester);
    expect(find.textContaining('private-model-metadata'), findsNothing);
    expect(find.textContaining('Saved tool output'), findsNothing);
    expect(find.byType(ChatActivityBar), findsNothing);
  });

  testWidgets('cold-open stock interrupted history stays quiet, not deleted', (
    tester,
  ) async {
    final stock =
        jsonDecode(
              File(
                'test/fixtures/normal_gateway_interrupted_stock.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final rows = (stock['history'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final partial = rows.last['content'] as String;
    expect(rows.last.containsKey('status'), isFalse);
    expect(rows.last.containsKey('_chat_response_complete'), isFalse);
    final f = _StockFixture();
    _cleanup(tester, f);
    f.history.rows = rows;
    await f.open(tester);
    expect(_bubbles(tester), ['Prompt']);
    expect(f.chat.snapshot.historyRows.last['content'], partial);
    expect(find.byType(ChatActivityBar), findsNothing);
    _expectQuiet(tester);
    await f.leave(tester);
    await _verbose(true);
    await f.reopen(tester);
    expect(_bubbles(tester), ['Prompt', partial]);
    expect(find.text('Saved history'), findsOneWidget);
    expect(find.byType(ChatActivityBar), findsNothing);
    expect(f.submissions, 0);
  });

  testWidgets(
    'quiet saved finals keep source order across commentary and tools',
    (tester) async {
      await _largeSurface(tester);
      final f = _StockFixture();
      _cleanup(tester, f);
      f.history.rows = [
        _row(1, 'user', 'Saved question'),
        _row(2, 'assistant', 'First final', extra: {'completed': true}),
        _row(3, 'assistant', 'Unconfirmed commentary'),
        _row(4, 'tool', 'Tool result', extra: {'name': 'terminal'}),
        _row(5, 'assistant', 'Second final', extra: {'finish_reason': 'stop'}),
        _row(6, 'assistant', 'Unconfirmed tail'),
      ];
      await f.open(tester);
      expect(_bubbles(tester), [
        'Saved question',
        'First final',
        'Second final',
      ]);
      _expectQuiet(tester);
      expect(f.submissions, 0);
    },
  );

  for (final verbose in [false, true]) {
    testWidgets(
      'one bottom activity bar follows current work: verbose=$verbose',
      (tester) async {
        await _verbose(verbose);
        final f = _StockFixture();
        _cleanup(tester, f);
        await _largeSurface(tester);
        await f.open(tester);
        await f.send(tester);
        _expectActivity(tester, 'Hermes is responding…');

        f.emit('reasoning.delta', {
          'text': 'Hidden reasoning body',
          'verbose': true,
        });
        await _frames(tester);
        _expectActivity(tester, 'Reasoning');
        if (verbose) {
          expect(find.byType(GatewayReasoningCard), findsOneWidget);
          expect(_expanded(tester, _tile(GatewayReasoningCard)), isFalse);
          expect(find.text('Hidden reasoning body'), findsNothing);
        } else {
          _expectQuiet(tester);
        }

        f.emit('tool.start', {
          'name': 'terminal',
          'tool_id': 't1',
          'context': 'Running the regression tests',
        });
        f.emit('tool.start', {'name': 'read_file', 'tool_id': 't2'});
        await _frames(tester);
        _expectActivity(tester, 'Using Read file…');
        if (verbose) {
          expect(_expanded(tester, _tile(GatewayActivityCard)), isFalse);
          expect(find.text('Read file: Running'), findsOneWidget);
          expect(find.text('Terminal: Running'), findsNothing);
        }
        f.emit('tool.complete', {'name': 'read_file', 'tool_id': 't2'});
        await _frames(tester);
        _expectActivity(
          tester,
          'Using Terminal: Running the regression tests…',
        );
        f.emit('tool.progress', {
          'name': 'terminal',
          'tool_id': 't1',
          'preview': 'Checking the Android build',
        });
        await _frames(tester);
        _expectActivity(tester, 'Using Terminal: Checking the Android build…');
        f.emit('tool.complete', {'name': 'terminal', 'tool_id': 't1'});
        await _frames(tester);
        _expectActivity(tester, 'Hermes is responding…');
        f.emit('reasoning.delta', {'text': 'Reasoning resumes'});
        f.emit('tool.complete', {'name': 'terminal', 'tool_id': 't1'});
        await _frames(tester);
        _expectActivity(tester, 'Reasoning');
        f.emit('subagent.start', {
          'subagent_id': 'child',
          'goal': 'Inspect child',
        });
        await _frames(tester);
        _expectActivity(tester, 'Delegated task: Inspect child');
        if (verbose) {
          expect(_expanded(tester, _tile(GatewaySubagentCard)), isFalse);
          expect(find.text('Inspect child'), findsNothing);
        }
        f.emit('subagent.complete', {
          'subagent_id': 'child',
          'status': 'completed',
        });
        await _frames(tester);
        _expectActivity(tester, 'Hermes is responding…');

        f.emit('message.delta', {'text': 'Active commentary'});
        f.emit('message.interim', {
          'text': 'Active commentary',
          'already_streamed': true,
        });
        f.emit('message.delta', {'text': 'Partial draft'});
        await _frames(tester);
        _expectActivity(tester, 'Hermes is responding…');
        if (!verbose) {
          expect(_bubbles(tester), ['Question']);
          _expectQuiet(tester);
        }
        await f.complete(tester, 'Final answer');
        expect(find.byType(ChatActivityBar), findsNothing);
        if (!verbose) expect(_bubbles(tester), ['Question', 'Final answer']);
        f.globalEvent('subagent.update', {
          'subagent_id': 'child',
          'goal': 'Late child preview',
        });
        f.globalEvent('subagent.complete', {
          'subagent_id': 'child',
          'status': 'completed',
        });
        await _frames(tester);
        expect(find.byType(ChatActivityBar), findsNothing);
        expect(f.submissions, 1);
      },
    );

    testWidgets(
      'parent settlement ignores still-running and late children: verbose=$verbose',
      (tester) async {
        await _verbose(verbose);
        final f = _StockFixture();
        _cleanup(tester, f);
        await f.open(tester);
        await f.send(tester);
        f.emit('subagent.start', {
          'subagent_id': 'child',
          'goal': 'Slow child',
        });
        await _frames(tester);
        _expectActivity(tester, 'Delegated task: Slow child');
        await f.complete(tester, 'Parent done');
        expect(find.byType(ChatActivityBar), findsNothing);
        f.globalEvent('subagent.start', {
          'subagent_id': 'late-child',
          'goal': 'Late observer',
        });
        f.globalEvent('subagent.complete', {
          'subagent_id': 'child',
          'status': 'completed',
        });
        await _frames(tester);
        expect(find.byType(ChatActivityBar), findsNothing);
        expect(f.chat.snapshot.hasActiveTurn, isFalse);
        await f.send(tester, 'Next question');
        _expectActivity(tester, 'Hermes is responding…');
        f.globalEvent('subagent.update', {
          'subagent_id': 'late-child',
          'goal': 'Previous parent observer',
        });
        await _frames(tester);
        _expectActivity(tester, 'Hermes is responding…');
        f.emit('tool.start', {'name': 'read_file', 'tool_id': 'next-tool'});
        f.globalEvent('subagent.complete', {
          'subagent_id': 'late-child',
          'status': 'completed',
        });
        await _frames(tester);
        _expectActivity(tester, 'Using Read file…');
        await f.complete(tester, 'Next final');
        expect(find.byType(ChatActivityBar), findsNothing);
        expect(f.submissions, 2);
      },
    );

    testWidgets(
      'leave, fail, reopen retains a non-spinning error: verbose=$verbose',
      (tester) async {
        await _verbose(verbose);
        final f = _StockFixture();
        _cleanup(tester, f);
        await f.open(tester);
        await f.send(tester);
        f.emit('message.delta', {'text': 'Interrupted received partial'});
        await _frames(tester);
        await f.leave(tester);
        expect(find.byType(ChatScreen), findsNothing);
        f.emit('turn.error', {'error': 'Retained gateway failure'});
        f.ack();
        await _frames(tester);
        expect(f.chat.snapshot.phase, NormalGatewayTurnPhase.failed);
        expect(find.byType(SnackBar), findsNothing);
        await f.reopen(tester);
        _expectNotice(tester, 'Retained gateway failure');
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason:
              'reattachment must not require the missed foreground transition',
        );
        if (!verbose) expect(_bubbles(tester), ['Question']);
        expect(f.submissions, 1);
      },
    );
  }

  for (final verbose in [false, true]) {
    for (final io in ['held', 'rejected']) {
      testWidgets(
        'owned failure revokes prose and stops spinning before $io WAL: verbose=$verbose',
        (tester) async {
          await _verbose(verbose);
          await _largeSurface(tester);
          final original = SharedPreferencesStorePlatform.instance;
          final platform = _TerminalReceiptPlatform(await original.getAll());
          SharedPreferencesStorePlatform.instance = platform;
          addTearDown(() => SharedPreferencesStorePlatform.instance = original);
          final f = _StockFixture();
          _cleanup(tester, f);
          addTearDown(() {
            platform.reject = false;
            if (!platform.release.isCompleted) platform.release.complete();
          });
          await f.open(tester);
          await f.send(tester, 'Prior question');
          await f.complete(tester, 'Prior successful final');
          await f.send(tester, 'Failing question');
          f.emit('message.delta', {'text': 'Revoked current reply'});
          f.emit('message.complete', {'text': 'Revoked current reply'});
          await _frames(tester);
          expect(_bubbles(tester), contains('Revoked current reply'));
          platform
            ..armed = true
            ..hold = io == 'held'
            ..reject = io == 'rejected';
          f.emit('turn.error', {'error': 'Authoritative current failure'});
          f.ack();
          await _frames(tester);
          expect(platform.entered.isCompleted, isTrue);
          if (io == 'rejected') {
            expect(platform.attempts, greaterThanOrEqualTo(2));
          }
          expect(f.chat.snapshot.hasActiveTurn, isTrue);
          expect(f.chat.reserve(), isNull);
          expect(
            f.chat.snapshot.responseFailure,
            'Authoritative current failure',
          );
          _expectNotice(tester, 'Authoritative current failure');
          if (!verbose) {
            expect(_bubbles(tester), [
              'Prior question',
              'Prior successful final',
              'Failing question',
            ]);
            _expectQuiet(tester);
          }
          // Reattach before the tombstone is durable. The error is snapshot
          // state, not a missed foreground-only snackbar transition.
          await f.leave(tester);
          await f.reopen(tester);
          _expectNotice(tester, 'Authoritative current failure');
          expect(f.chat.snapshot.hasActiveTurn, isTrue);
          if (!verbose) {
            expect(_bubbles(tester), isNot(contains('Revoked current reply')));
            expect(_bubbles(tester), contains('Prior successful final'));
          }
          platform.reject = false;
          if (!platform.release.isCompleted) platform.release.complete();
          f.chat.requestRecovery();
          await _frames(tester);
          expect(f.chat.snapshot.phase, NormalGatewayTurnPhase.failed);
          _expectNotice(tester, 'Authoritative current failure');
          if (!verbose) {
            expect(_bubbles(tester), isNot(contains('Revoked current reply')));
          }
          expect(f.submissions, 2);
        },
      );
    }
  }

  testWidgets(
    'quiet active reattachment uses the stored alias without resending',
    (tester) async {
      final f = _StockFixture();
      _cleanup(tester, f);
      await f.open(tester);
      await f.send(tester);
      f.emit('message.delta', {'text': 'Hidden live prose'});
      f.emit('tool.start', {'name': 'terminal', 'tool_id': 'active'});
      await _frames(tester);
      final owner = f.chat;
      await f.leave(tester);
      await f.reopen(tester);
      expect(f.normal.findChat('stored-chat'), same(owner));
      expect(_bubbles(tester), ['Question']);
      _expectActivity(tester, 'Using Terminal…');
      _expectQuiet(tester);
      expect(f.submissions, 1);
      await f.complete(tester, 'Done after reattachment');
      expect(_bubbles(tester), ['Question', 'Done after reattachment']);
    },
  );

  testWidgets(
    'message.complete is a reply receipt, not RPC/lifecycle settlement',
    (tester) async {
      final f = _StockFixture();
      _cleanup(tester, f);
      await f.open(tester);
      await f.send(tester);
      f.emit('message.delta', {'text': 'Answer'});
      f.emit('message.complete', {'text': 'Answer'});
      await _frames(tester);
      expect(_bubbles(tester), ['Question', 'Answer']);
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      f.ack();
      await _frames(tester);
      expect(f.resumeReads, greaterThan(0));
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      _expectActivity(tester, 'Hermes is responding…');
      f.history.rows = [
        _row(1, 'user', 'Question'),
        _row(2, 'assistant', 'Saved answer', extra: {'status': 'completed'}),
      ];
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'completed',
      );
      f.chat.requestRecovery();
      await _frames(tester);
      expect(f.chat.snapshot.hasActiveTurn, isFalse);
      expect(find.byType(ChatActivityBar), findsNothing);
      // RC preserves C and R as separate sources; neither text nor row floor
      // establishes that these independently observed answers are one row.
      expect(_bubbles(tester), [
        'Question',
        'Saved answer',
        'Question',
        'Answer',
      ]);
      _expectQuiet(tester);
    },
  );

  testWidgets('owned successful turn.end promotes final deltas once', (
    tester,
  ) async {
    final f = _StockFixture();
    _cleanup(tester, f);
    await f.open(tester);
    await f.send(tester);
    f.emit('message.delta', {'text': 'Final deltas'});
    await _frames(tester);
    expect(_bubbles(tester), ['Question']);
    f.emit('turn.end', {'status': 'completed'});
    f.ack();
    await _frames(tester);
    expect(_bubbles(tester), ['Question', 'Final deltas']);
    expect(find.byType(ChatActivityBar), findsNothing);
    await f.leave(tester);
    await f.reopen(tester);
    expect(_bubbles(tester), ['Question', 'Final deltas']);
    expect(f.submissions, 1);
  });

  for (final flag in [
    'response_previewed',
    'response_reused',
    'response_transformed',
  ]) {
    testWidgets('quiet $flag selects only the final preview once', (
      tester,
    ) async {
      final f = _StockFixture();
      _cleanup(tester, f);
      await f.open(tester);
      await f.send(tester);
      f.emit('message.delta', {'text': 'Unselected commentary'});
      f.emit('message.interim', {
        'text': 'Unselected commentary',
        'already_streamed': true,
      });
      f.emit('message.delta', {'text': 'Selected final preview'});
      f.emit('message.interim', {
        'text': 'Selected final preview',
        'already_streamed': true,
      });
      await _frames(tester);
      expect(_bubbles(tester), ['Question']);
      f.emit('message.complete', {
        'text': 'Selected final preview',
        flag: true,
      });
      f.emit('turn.end', {'status': 'completed'});
      f.ack();
      await _frames(tester);
      expect(_bubbles(tester), ['Question', 'Selected final preview']);
      expect(find.byType(ChatActivityBar), findsNothing);
      await f.leave(tester);
      await f.reopen(tester);
      expect(_bubbles(tester), ['Question', 'Selected final preview']);
    });
  }

  for (final status in ['failed', 'interrupted', 'unknown']) {
    testWidgets('quiet $status completion never promotes partial prose', (
      tester,
    ) async {
      final f = _StockFixture();
      _cleanup(tester, f);
      await f.open(tester);
      await f.send(tester);
      f.emit('message.delta', {'text': 'Incomplete answer'});
      f.emit('message.complete', {
        'text': 'Incomplete answer',
        'status': status,
      });
      f.resumeResult = ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: status == 'unknown' ? 'idle' : status,
        inflight: status == 'unknown'
            ? null
            : {'status': status, 'error': 'Terminal $status'},
      );
      f.ack();
      await _frames(tester);
      expect(_bubbles(tester), ['Question']);
      expect(f.chat.snapshot.hasActiveTurn, isFalse);
      _expectNotice(
        tester,
        status == 'unknown' ? 'could not be confirmed' : 'Terminal $status',
      );
    });
  }

  for (final unknownFloor in [false, true]) {
    testWidgets(
      'idle recovery and next turn cannot revive interrupted C/R: unknownFloor=$unknownFloor',
      (tester) async {
        // Keep both source-local histories mounted so hiding an old partial
        // cannot be mistaken for ordinary lazy-list eviction at the new end.
        await _largeSurface(tester);
        final f = _StockFixture();
        _cleanup(tester, f);
        f.history.rows = [
          _row(10, 'user', 'Older question'),
          _row(
            11,
            'assistant',
            'Older confirmed answer',
            extra: {'completed': true},
          ),
        ];
        f.history.fail = unknownFloor;
        await f.open(tester);
        await f.send(tester);
        expect(f.chat.snapshot.rowFloor, unknownFloor ? isNull : 11);
        f.emit('message.delta', {'text': 'Interrupted received prose'});
        f.history.fail = false;
        f.history.rows = [
          _row(10, 'user', 'Older question'),
          _row(
            11,
            'assistant',
            'Older confirmed answer',
            extra: {'completed': true},
          ),
          _row(12, 'user', 'Question'),
          _row(13, 'assistant', 'Interrupted saved prose'),
        ];
        f.resumeResult = const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: false,
          status: 'idle',
        );
        f.ack();
        await _frames(tester);
        expect(f.chat.snapshot.phase, NormalGatewayTurnPhase.reconciledUnknown);
        _expectNoInterruptedProse(tester);
        expect(_bubbles(tester), contains('Older confirmed answer'));
        _expectNotice(tester, 'could not be confirmed');
        await f.leave(tester);
        await f.reopen(tester);
        _expectNoInterruptedProse(tester);
        _expectNotice(tester, 'could not be confirmed');
        f.resumeResult = const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: true,
        );
        await f.send(tester, 'Next question');
        _expectNoInterruptedProse(tester);
        f.history.rows = [
          ...f.history.rows,
          _row(14, 'user', 'Next question'),
          _row(
            15,
            'assistant',
            'Saved next final',
            extra: {'status': 'completed'},
          ),
        ];
        await f.complete(tester, 'Next final');
        _expectNoInterruptedProse(tester);
        expect(_bubbles(tester), contains('Next final'));
        expect(_bubbles(tester), contains('Older confirmed answer'));
        await f.leave(tester);
        await f.reopen(tester);
        _expectNoInterruptedProse(tester);
        expect(f.submissions, 2);
      },
    );
  }

  for (final terminal in ['message.complete', 'turn.end']) {
    for (final identified in [false, true]) {
      testWidgets(
        'successful A $terminal cannot complete B: identified=$identified',
        (tester) async {
          final f = _StockFixture();
          _cleanup(tester, f);
          await f.open(tester);
          await f.send(tester);
          final a = f.turn;
          await f.complete(tester, 'A final');
          f.autoStart = false;
          await f.send(tester, 'B question');
          final b = f.turn;
          f.globalEvent(terminal, {
            'status': 'completed',
            'text': 'Late A final',
          }, turn: identified ? a : null);
          f.ack();
          await _frames(tester);
          expect(f.chat.snapshot.hasActiveTurn, isTrue);
          expect(_bubbles(tester), ['Question', 'A final', 'B question']);
          _expectActivity(tester, 'Hermes is responding…');
          f.globalEvent('message.start', {}, turn: b);
          f.globalEvent('message.delta', {'text': 'B final'}, turn: b);
          f.globalEvent('turn.end', {'status': 'completed'}, turn: b);
          await _frames(tester);
          expect(_bubbles(tester), [
            'Question',
            'A final',
            'B question',
            'B final',
          ]);
          expect(find.byType(ChatActivityBar), findsNothing);
        },
      );
    }
  }

  testWidgets(
    'verbose detail, reports, notices and metadata start actually collapsed',
    (tester) async {
      await _verbose(true);
      await _largeSurface(tester);
      final f = _StockFixture();
      _cleanup(tester, f);
      f.history.rows = [
        _row(1, 'user', 'Saved question'),
        _row(
          2,
          'assistant',
          'Saved answer',
          extra: {
            '_gateway_reasoning': 'Sidecar reasoning body',
            '_gateway_reasoning_verbose': true,
            'model': 'metadata-model',
          },
        ),
        _reportRow(3),
      ];
      await f.open(tester);
      expect(find.text('Saved history'), findsOneWidget);
      expect(find.byType(BackgroundReportCard), findsOneWidget);
      expect(find.byType(GatewayReasoningCard), findsOneWidget);
      for (final element in find.byType(ExpansionTile).evaluate()) {
        expect(_expanded(tester, find.byWidget(element.widget)), isFalse);
      }
      expect(find.textContaining('role: assistant'), findsNothing);
      expect(find.text('Sidecar reasoning body'), findsNothing);
      expect(find.text('Internal report body'), findsNothing);
      await f.send(tester);
      f.emit('reasoning.delta', {
        'text': 'Live reasoning body',
        'verbose': true,
      });
      f.emit('tool.start', {
        'name': 'read_file',
        'tool_id': 'live',
        'arguments': 'private tool args',
      });
      f.emit('subagent.start', {
        'subagent_id': 'child',
        'goal': 'Private delegated goal',
      });
      f.globalEvent('background.complete', {
        'text': 'Private background notice',
        'task_id': 'background',
      });
      await _frames(tester);
      expect(find.byType(GatewayActivityCard), findsOneWidget);
      expect(find.byType(GatewaySubagentCard), findsOneWidget);
      expect(find.byType(GatewayNoticeCard), findsOneWidget);
      for (final element in find.byType(ExpansionTile).evaluate()) {
        expect(_expanded(tester, find.byWidget(element.widget)), isFalse);
      }
      expect(find.text('Live reasoning body'), findsNothing);
      expect(find.text('Private delegated goal'), findsNothing);
      expect(find.text('Private background notice'), findsNothing);
      expect(find.textContaining('private tool args'), findsNothing);
      _expectActivity(tester, 'Delegated task: Private delegated goal');
      await f.complete(tester, 'Done');
    },
  );

  testWidgets(
    'message metadata pins survive refresh and lazy eviction, reset on reopen',
    (tester) async {
      await _verbose(true);
      await tester.binding.setSurfaceSize(const Size(900, 1300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _StockFixture();
      _cleanup(tester, f);
      f.history.rows = [
        _row(1, 'user', 'Saved question'),
        _row(2, 'assistant', 'Saved answer', extra: {'model': 'first-model'}),
      ];
      await f.open(tester);
      Finder metadata() => find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is MessageBubble && w.content == 'Saved answer',
        ),
        matching: find.byKey(const ValueKey('message-metadata')),
      );
      expect(_expanded(tester, metadata()), isFalse);
      expect(find.text('model: first-model'), findsNothing);
      await _tapTile(tester, metadata());
      expect(_expanded(tester, metadata()), isTrue);
      expect(find.text('model: first-model'), findsOneWidget);
      f.history.rows = [
        _row(1, 'user', 'Saved question'),
        _row(2, 'assistant', 'Saved answer', extra: {'model': 'updated-model'}),
      ];
      final reads = f.history.historyReads;
      await _refresh(tester);
      expect(f.history.historyReads, greaterThan(reads));
      expect(_expanded(tester, metadata()), isTrue);
      expect(find.text('model: updated-model'), findsOneWidget);
      final state = tester.state(metadata());
      await f.send(tester);
      f.emit('message.delta', {'text': 'Receipt paragraph.\n\n' * 180});
      await _frames(tester);
      await _toEnd(tester);
      expect(state.mounted, isFalse);
      await _toStart(tester);
      expect(_expanded(tester, metadata()), isTrue);
      await f.leave(tester);
      await f.reopen(tester);
      await _toStart(tester);
      expect(_expanded(tester, metadata()), isFalse);
      expect(find.text('model: updated-model'), findsNothing);
      expect(f.submissions, 1);
      await f.complete(tester, 'Done');
    },
  );

  for (final flag in ['response_previewed', 'response_reused']) {
    testWidgets(
      'verbose preview keeps distinct reasoning pins across scope transfer: $flag',
      (tester) async {
        await _verbose(true);
        await _largeSurface(tester);
        final f = _StockFixture();
        _cleanup(tester, f);
        await f.open(tester);
        await f.send(tester);
        f.emit('reasoning.delta', {'text': 'First reasoning', 'verbose': true});
        f.emit('message.delta', {'text': 'Final preview'});
        f.emit('message.interim', {
          'text': 'Final preview',
          'already_streamed': true,
        });
        f.emit('tool.start', {'name': 'read_file', 'tool_id': 'preview-tool'});
        f.emit('reasoning.delta', {
          'text': 'Second reasoning',
          'verbose': true,
        });
        await _frames(tester);
        expect(find.byType(GatewayReasoningCard), findsNWidgets(2));
        final beforeKeys = tester
            .widgetList<GatewayReasoningCard>(find.byType(GatewayReasoningCard))
            .map((card) => card.key)
            .toList();
        final first = _tile(GatewayReasoningCard).first;
        final second = _tile(GatewayReasoningCard).last;
        expect(_expanded(tester, first), isFalse);
        expect(_expanded(tester, second), isFalse);
        await _tapTile(tester, first);
        // An actual open-close gesture pins the second card closed; defaults
        // alone cannot prove independent manual state survived completion.
        await _tapTile(tester, second);
        await _tapTile(tester, second);
        expect(_expanded(tester, first), isTrue);
        expect(_expanded(tester, second), isFalse);
        f.emit('message.complete', {'text': 'Final preview', flag: true});
        f.emit('turn.end', {'status': 'completed'});
        f.ack();
        await _frames(tester);
        expect(
          tester
              .widgetList<GatewayReasoningCard>(
                find.byType(GatewayReasoningCard),
              )
              .map((card) => card.key)
              .toList(),
          beforeKeys,
        );
        expect(_expanded(tester, first), isTrue);
        expect(_expanded(tester, second), isFalse);
        expect(find.text('First reasoning'), findsOneWidget);
        expect(find.text('Second reasoning'), findsNothing);
        expect(
          _bubbles(tester).where((s) => s == 'Final preview'),
          hasLength(1),
        );
        expect(find.byType(ChatActivityBar), findsNothing);
        final firstY = tester
            .getTopLeft(find.byType(GatewayReasoningCard).first)
            .dy;
        final toolY = tester.getTopLeft(find.byType(GatewayActivityCard)).dy;
        final secondY = tester
            .getTopLeft(find.byType(GatewayReasoningCard).last)
            .dy;
        expect(firstY, lessThan(toolY));
        expect(toolY, lessThan(secondY));
      },
    );
  }

  for (final completedAway in [false, true]) {
    testWidgets(
      'verbose manual pins survive updates and lazy eviction, reset on reopen: completedAway=$completedAway',
      (tester) async {
        await _verbose(true);
        await tester.binding.setSurfaceSize(const Size(900, 1300));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = _StockFixture();
        _cleanup(tester, f);
        await f.open(tester);
        await f.send(tester);
        f.emit('reasoning.delta', {
          'text': 'Pinned reasoning',
          'verbose': true,
        });
        f.emit('tool.start', {
          'name': 'terminal',
          'tool_id': 'pin-tool',
          'arguments': 'Pinned tool arguments',
        });
        f.emit('subagent.start', {
          'subagent_id': 'pin-child',
          'goal': 'Pinned child goal',
        });
        await _frames(tester);
        for (final type in [
          GatewayReasoningCard,
          GatewayActivityCard,
          GatewaySubagentCard,
        ]) {
          await tester.ensureVisible(_tile(type).first);
          expect(_expanded(tester, _tile(type).first), isFalse);
          await _tapTile(tester, _tile(type).first);
          expect(_expanded(tester, _tile(type).first), isTrue);
        }
        final reasoningState = tester.state(find.byType(GatewayReasoningCard));
        final toolState = tester.state(find.byType(GatewayActivityCard));
        f.emit('reasoning.delta', {'text': ' updated'});
        f.emit('tool.update', {
          'name': 'terminal',
          'tool_id': 'pin-tool',
          'detail': 'Updated tool',
        });
        f.emit('subagent.update', {
          'subagent_id': 'pin-child',
          'goal': 'Updated child goal',
        });
        await _frames(tester);
        for (final type in [
          GatewayReasoningCard,
          GatewayActivityCard,
          GatewaySubagentCard,
        ]) {
          await tester.ensureVisible(_tile(type).first);
          expect(_expanded(tester, _tile(type).first), isTrue);
        }
        // Long prose pushes the earlier cards outside the sliver cache. Verify
        // actual State disposal, not just an off-screen hit test.
        f.emit('message.delta', {'text': 'Long receipt line.\n\n' * 180});
        await _frames(tester);
        await _toEnd(tester);
        expect(reasoningState.mounted, isFalse);
        expect(toolState.mounted, isFalse);
        await _toStart(tester);
        expect(
          find.byType(GatewaySubagentCard),
          findsNothing,
          reason: 'delegation must really leave the lazy-list cache',
        );
        for (final type in [GatewayReasoningCard, GatewayActivityCard]) {
          await tester.ensureVisible(_tile(type).first);
          expect(_expanded(tester, _tile(type).first), isTrue);
        }
        await _toEnd(tester);
        await tester.ensureVisible(_tile(GatewaySubagentCard));
        expect(_expanded(tester, _tile(GatewaySubagentCard)), isTrue);
        // Pin all closed, then update: a closed manual choice is just as durable.
        for (final type in [GatewaySubagentCard]) {
          await _tapTile(tester, _tile(type).first);
        }
        await _toStart(tester);
        for (final type in [GatewayReasoningCard, GatewayActivityCard]) {
          await tester.ensureVisible(_tile(type).first);
          await _tapTile(tester, _tile(type).first);
          expect(_expanded(tester, _tile(type).first), isFalse);
        }
        f.emit('tool.start', {'name': 'read_file', 'tool_id': 'another-tool'});
        f.emit('reasoning.delta', {'text': 'More reasoning after prose'});
        await _frames(tester);
        await _toStart(tester);
        expect(_expanded(tester, _tile(GatewayReasoningCard).first), isFalse);
        expect(_expanded(tester, _tile(GatewayActivityCard).first), isFalse);
        // Leave with a genuinely open pin so reset is not a vacuous assertion.
        await _tapTile(tester, _tile(GatewayReasoningCard).first);
        expect(_expanded(tester, _tile(GatewayReasoningCard).first), isTrue);
        await _tapTile(tester, _tile(GatewayActivityCard).first);
        expect(_expanded(tester, _tile(GatewayActivityCard).first), isTrue);
        await _toEnd(tester);
        await _tapTile(tester, _tile(GatewaySubagentCard));
        expect(_expanded(tester, _tile(GatewaySubagentCard)), isTrue);
        await f.leave(tester);
        if (completedAway) await f.complete(tester, 'Completed while away');
        await f.reopen(tester);
        await _toStart(tester);
        expect(_expanded(tester, _tile(GatewayReasoningCard).first), isFalse);
        expect(_expanded(tester, _tile(GatewayActivityCard).first), isFalse);
        await _toEnd(tester);
        expect(_expanded(tester, _tile(GatewaySubagentCard)), isFalse);
        expect(f.submissions, 1);
        if (!completedAway) await f.complete(tester, 'Done');
      },
    );
  }

  testWidgets(
    'quiet to verbose reopen reveals retained details without a resend',
    (tester) async {
      await _largeSurface(tester);
      final f = _StockFixture();
      _cleanup(tester, f);
      await f.open(tester);
      await f.send(tester);
      f.emit('reasoning.delta', {
        'text': 'Retained quiet reasoning',
        'verbose': true,
      });
      f.emit('tool.start', {'name': 'terminal', 'tool_id': 'retained-tool'});
      f.emit('subagent.start', {
        'subagent_id': 'child',
        'goal': 'Retained quiet child',
      });
      f.globalEvent('background.complete', {
        'text': 'Retained quiet notice',
        'task_id': 'quiet-notice',
      });
      await _frames(tester);
      _expectQuiet(tester);
      await f.leave(tester);
      await _verbose(true);
      await f.reopen(tester);
      expect(find.byType(GatewayReasoningCard), findsOneWidget);
      expect(find.byType(GatewayActivityCard), findsOneWidget);
      expect(find.byType(GatewaySubagentCard), findsOneWidget);
      expect(find.byType(GatewayNoticeCard), findsOneWidget);
      expect(
        find.text('Received output — match to saved history unconfirmed'),
        findsNothing,
      );
      expect(find.text('Received · match unconfirmed'), findsWidgets);
      expect(find.text('Retained quiet reasoning'), findsNothing);
      await _tapTile(tester, _tile(GatewayReasoningCard));
      expect(find.text('Retained quiet reasoning'), findsOneWidget);
      expect(f.submissions, 1);
      await f.complete(tester, 'Retained final');
      await tester.tap(find.byTooltip('Chat actions').hitTestable());
      await _frames(tester);
      await tester.tap(find.text('About received output').hitTestable());
      await _frames(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Received output — match to saved history unconfirmed'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await _frames(tester);
      await f.leave(tester);
      await _verbose(false);
      await f.reopen(tester);
      expect(_bubbles(tester), ['Question', 'Retained final']);
      _expectQuiet(tester);
    },
  );

  for (final verbose in [false, true]) {
    testWidgets(
      'SSE activity follows reasoning, tool previews and status: verbose=$verbose',
      (tester) async {
        await _verbose(verbose);
        await _largeSurface(tester);
        final f = _SseFixture();
        _cleanup(tester, f);
        await f.open(tester);
        await f.send(tester);
        f.client.fragment(
          'data: {"choices":[{"delta":{"reasoning_content":"Private reasoning body"}}]}\r\n\r\n',
        );
        await _frames(tester);
        _expectActivity(tester, 'Reasoning');
        expect(find.text('Private reasoning body'), findsNothing);
        if (verbose) {
          expect(_expanded(tester, _tile(GatewayReasoningCard)), isFalse);
        } else {
          _expectQuiet(tester);
          expect(_bubbles(tester), ['Question']);
        }
        f.client.fragment(
          'event: hermes.tool.progress\ndata: {"tool":"web_search","toolCallId":"sse-work","label":"Searching the documentation","status":"running"}\n\n',
        );
        await _frames(tester);
        _expectActivity(
          tester,
          'Using Web search: Searching the documentation…',
        );
        f.client.fragment(
          'event: hermes.tool.progress\r\ndata: {"tool":"web_search","toolCallId":"sse-work","status":"completed"}\r\n\r\n',
        );
        await _frames(tester);
        _expectActivity(tester, 'Hermes is responding…');
        f.client.fragment(
          'event: hermes.status\ndata: {"kind":"compacting","text":"Compacting conversation context…"}\n\n',
        );
        await _frames(tester);
        _expectActivity(tester, 'Compacting conversation context…');
        f.client.fragment(
          'data: {"choices":[{"delta":{"reasoning_content":"More private reasoning"}}]}\n\n',
        );
        await _frames(tester);
        _expectActivity(tester, 'Reasoning');
        f.client.fragment(
          'data: {"choices":[{"delta":{"content":"Completed answer"}}]}\n\n',
        );
        await _frames(tester);
        _expectActivity(tester, 'Hermes is responding…');
        if (!verbose) {
          _expectQuiet(tester);
          expect(_bubbles(tester), ['Question']);
        }
        f.client.fragment(
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
        );
        await f.client.closeBody();
        await _frames(tester);
        await f.settle(tester);
        expect(find.byType(ChatActivityBar), findsNothing);
        expect(_bubbles(tester), ['Question', 'Completed answer']);
        expect(f.client.submissions, 1);
        if (!verbose) _expectQuiet(tester);
      },
    );
  }

  testWidgets(
    'verbose SSE retains text-tool-text order through stale success and refresh',
    (tester) async {
      await _verbose(true);
      await _largeSurface(tester);
      final f = _SseFixture();
      _cleanup(tester, f);
      await f.open(tester);
      await f.send(tester);
      f.client.fragment(
        'data: {"choices":[{"delta":{"content":"Before tool"}}]}\r\n\r\n',
      );
      f.client.fragment(
        'event: hermes.tool.progress\r\ndata: {"name":"terminal","tool_id":"ordered-tool","status":"running"}\r\n\r\n',
      );
      await _frames(tester);
      expect(_expanded(tester, _tile(GatewayActivityCard)), isFalse);
      _expectActivity(tester, 'Using Terminal…');
      f.client.fragment(
        'event: hermes.tool.progress\ndata: {"name":"terminal","tool_id":"ordered-tool","status":"completed"}\n\n',
      );
      f.client.fragment(
        'data: {"choices":[{"delta":{"content":"After tool"}}]}\n\n',
      );
      f.client.fragment(
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
      );
      await f.client.closeBody();
      await _frames(tester);
      await f.settle(tester);
      void expectOrder() {
        expect(_bubbles(tester), ['Question', 'Before tool', 'After tool']);
        expect(find.byType(GatewayActivityCard), findsOneWidget);
        final before = tester
            .getTopLeft(
              find.byWidgetPredicate(
                (w) => w is MessageBubble && w.content == 'Before tool',
              ),
            )
            .dy;
        final tool = tester.getTopLeft(find.byType(GatewayActivityCard)).dy;
        final after = tester
            .getTopLeft(
              find.byWidgetPredicate(
                (w) => w is MessageBubble && w.content == 'After tool',
              ),
            )
            .dy;
        expect(before, lessThan(tool));
        expect(tool, lessThan(after));
        expect(find.byType(ChatActivityBar), findsNothing);
      }

      expectOrder();
      expect(_expanded(tester, _tile(GatewayActivityCard)), isFalse);
      await _tapTile(tester, _tile(GatewayActivityCard));
      expect(_expanded(tester, _tile(GatewayActivityCard)), isTrue);
      final readsBefore = f.client.historyReads;
      await _refresh(tester);
      expect(f.client.historyReads, greaterThan(readsBefore));
      expectOrder();
      expect(_expanded(tester, _tile(GatewayActivityCard)), isTrue);
      expect(f.client.submissions, 1);
    },
  );

  for (final failure in [
    'named error',
    'JSON error',
    'bare EOF',
    'truncated EOF',
  ]) {
    testWidgets('quiet REST/SSE partial + $failure never yields a final reply', (
      tester,
    ) async {
      final f = _SseFixture();
      _cleanup(tester, f);
      await f.open(tester);
      await f.send(tester);
      f.client.fragment(
        'data: {"choices":[{"delta":{"content":"Incomplete SSE answer"}}]}\r\n\r\n',
      );
      await _frames(tester);
      expect(_bubbles(tester), ['Question']);
      _expectActivity(tester, 'Hermes is responding…');
      switch (failure) {
        case 'named error':
          f.client.fragment(
            'event: error\r\ndata: {"message":"SSE failed visibly"}\r\n\r\ndata: [DONE]\r\n\r\n',
          );
        case 'JSON error':
          f.client.fragment(
            'data: {"error":{"message":"SSE failed visibly"}}\n\ndata: [DONE]\n\n',
          );
        case 'bare EOF':
          break;
        case 'truncated EOF':
          f.client.fragment(
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\r\n',
          );
      }
      await f.client.closeBody();
      await _frames(tester);
      await f.settle(tester);
      expect(
        tester
            .widgetList<MessageBubble>(find.byType(MessageBubble))
            .where((b) => !b.isUser),
        isEmpty,
        reason: 'partial prose plus error/EOF must not become a final reply',
      );
      _expectNotice(
        tester,
        failure.contains('error') ? 'SSE failed visibly' : 'Stream ended',
      );
      expect(f.client.submissions, 1);
    });
  }

  for (final outcome in [
    'empty',
    'previous',
    'user-only',
    'failed',
    'untyped',
    'partial',
    'commentary',
    'typed-unrelated',
  ]) {
    testWidgets(
      'successful SSE survives $outcome history and a rejected later send',
      (tester) async {
        final f = _SseFixture();
        _cleanup(tester, f);
        final previous = [
          _row(1, 'user', 'Older question'),
          _row(2, 'assistant', 'Older answer', extra: {'status': 'completed'}),
        ];
        f.client.rows = previous;
        await f.open(tester);
        await f.send(tester);
        f.client.fragment(
          'event: hermes.tool.progress\r\ndata: {"name":"terminal","tool_id":"sse-tool","status":"running"}\r\n\r\n',
        );
        await _frames(tester);
        _expectActivity(tester, 'Using Terminal…');
        f.client.fragment(
          'data: {"choices":[{"delta":{"content":"Retained SSE final"}}]}\n\n',
        );
        await _frames(tester);
        expect(_bubbles(tester), [
          'Older question',
          'Older answer',
          'Question',
        ]);
        f.client.fail = outcome == 'failed';
        f.client.rows = switch (outcome) {
          'empty' => [],
          'user-only' => [...previous, _row(3, 'user', 'Question')],
          'untyped' => [
            ...previous,
            _row(3, 'user', 'Delayed prior question'),
            _row(4, 'assistant', 'Delayed prior untyped prose'),
          ],
          'partial' => [
            ...previous,
            _row(3, 'user', 'Delayed prior question'),
            _row(
              4,
              'assistant',
              'Delayed prior partial',
              extra: {'partial': true},
            ),
          ],
          'commentary' => [
            ...previous,
            _row(3, 'user', 'Delayed prior question'),
            _row(
              4,
              'assistant',
              'Delayed prior commentary',
              extra: {'interim': true},
            ),
          ],
          'typed-unrelated' => [
            ...previous,
            _row(3, 'user', 'Unrelated question'),
            // Even identical prose and explicit success are not a durable-ID
            // match for the ID-less response emitted by actual SSE.
            _row(
              4,
              'assistant',
              'Retained SSE final',
              extra: {'status': 'completed'},
            ),
          ],
          _ => previous,
        };
        f.client.fragment(
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\r\n\r\ndata: [DONE]\r\n\r\n',
        );
        await f.client.closeBody();
        await _frames(tester);
        await f.settle(tester);
        final expected = [
          'Older question',
          'Older answer',
          'Question',
          'Retained SSE final',
        ];
        expect(_bubbles(tester), expected);
        expect(find.byType(ChatActivityBar), findsNothing);
        f.client.rejectSubmissions = true;
        await f.send(tester, 'Rejected later prompt');
        await f.settle(tester);
        expect(_bubbles(tester), expected);
        _expectNotice(tester, 'Rejected next send');
        f.client.fail = false;
        final readsBefore = f.client.historyReads;
        await _refresh(tester);
        expect(
          f.client.historyReads,
          greaterThan(readsBefore),
          reason: 'a missed popup tap must not make retention falsely pass',
        );
        expect(_bubbles(tester), expected);
        expect(f.client.submissions, 2);
        _expectQuiet(tester);
      },
    );
  }
}

Future<void> _verbose(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('verbose_mode', value);
}

Future<void> _largeSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1000, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  // StreamSubscription.cancel can finish in the root zone. Drain both zones
  // before asserting SSE completion/error callbacks.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

List<String> _bubbles(WidgetTester tester) => tester
    .widgetList<MessageBubble>(find.byType(MessageBubble))
    .map((bubble) => bubble.content)
    .toList();

void _expectQuiet(WidgetTester tester) {
  for (final type in [
    GatewayActivityCard,
    GatewayReasoningCard,
    GatewaySubagentCard,
    GatewayNoticeCard,
    BackgroundReportCard,
  ]) {
    expect(find.byType(type), findsNothing);
  }
  for (final label in [
    'Saved history',
    'Received output — match to saved history unconfirmed',
    'Message details',
    'Local prompt context',
    'Received · match unconfirmed',
  ]) {
    expect(find.textContaining(label), findsNothing);
  }
  expect(find.byKey(const ValueKey('message-metadata')), findsNothing);
  expect(
    tester
        .widgetList<MessageBubble>(find.byType(MessageBubble))
        .every((b) => !b.verbose),
    isTrue,
  );
}

void _expectActivity(WidgetTester tester, String text) {
  final finder = find.byType(ChatActivityBar);
  expect(finder, findsOneWidget);
  final bar = tester.widget<ChatActivityBar>(finder);
  expect(bar.isTerminalNotice, isFalse);
  expect(bar.text, text);
  expect(find.byKey(const ValueKey('chat-current-activity')), findsOneWidget);
  expect(
    find.ancestor(of: finder, matching: find.byType(ListView)),
    findsNothing,
    reason: 'activity belongs below the transcript, never in its lazy list',
  );
  expect(
    find.ancestor(
      of: finder,
      matching: find.byKey(const Key('chat-input-bar')),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: finder,
      matching: find.byType(CircularProgressIndicator),
    ),
    findsOneWidget,
  );
}

void _expectNotice(WidgetTester tester, String text) {
  final finder = find.byType(ChatActivityBar);
  expect(finder, findsOneWidget);
  expect(tester.widget<ChatActivityBar>(finder).isTerminalNotice, isTrue);
  expect(tester.widget<ChatActivityBar>(finder).text, contains(text));
  expect(find.byKey(const ValueKey('chat-current-activity')), findsNothing);
  expect(find.byKey(const ValueKey('chat-turn-notice')), findsOneWidget);
  expect(
    find.descendant(
      of: finder,
      matching: find.byType(CircularProgressIndicator),
    ),
    findsNothing,
  );
}

void _expectNoInterruptedProse(WidgetTester tester) {
  expect(_bubbles(tester), isNot(contains('Interrupted received prose')));
  expect(_bubbles(tester), isNot(contains('Interrupted saved prose')));
}

Finder _tile(Type type) => find.descendant(
  of: find.byType(type),
  matching: find.byType(ExpansionTile),
);

bool _expanded(WidgetTester tester, Finder tile) => tester
    .widget<Expansible>(
      find.descendant(of: tile, matching: find.byType(Expansible)).first,
    )
    .controller
    .isExpanded;

Future<void> _tapTile(WidgetTester tester, Finder tile) async {
  await tester.ensureVisible(tile);
  final title = find
      .descendant(of: tile, matching: find.byType(ListTile))
      .first;
  await tester.tap(title.hitTestable());
  await _frames(tester);
}

ScrollController _listController(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView).first).controller!;

Future<void> _toStart(WidgetTester tester) async {
  _listController(tester).jumpTo(0);
  await _frames(tester);
}

Future<void> _toEnd(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    final controller = _listController(tester);
    controller.jumpTo(controller.position.maxScrollExtent);
    await _frames(tester);
  }
}

Future<void> _refresh(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Chat actions').hitTestable());
  await _frames(tester);
  await tester.tap(find.text('Refresh').hitTestable());
  await _frames(tester);
}

void _cleanup(WidgetTester tester, _ChatFixture fixture) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.close();
    await tester.pump();
  });
}

Map<String, dynamic> _row(
  int id,
  String role,
  String content, {
  Map<String, dynamic> extra = const {},
}) => {'id': id, 'role': role, 'content': content, ...extra};

Map<String, dynamic> _reportRow(int id) => _row(
  id,
  'assistant',
  'Internal report body',
  extra: {
    'display_kind': 'async_delegation_complete',
    'display_metadata': {'display_text': 'Internal report preview'},
  },
);

abstract class _ChatFixture {
  final controller = GatewayTurnApplicationController();
  final navigator = GlobalKey<NavigatorState>();
  final connection = SavedConnection(
    id: 'rc-verbose-fixture',
    label: 'Fixture',
    host: 'fixture.invalid',
    port: 8642,
    apiKey: 'fixture-key',
  );
  String nextId = 'local-chat';
  http.Client get httpClient;
  TestRemotePromptSubmit? get remoteSubmit => null;
  NormalGatewayResume? get resume => null;

  Widget screen() => ChatScreen(
    connection: connection,
    session: Session(
      id: nextId,
      title: 'Fixture chat',
      model: 'fixture',
      source: 'test',
      messageCount: 0,
      isActive: false,
      preview: '',
      startedAt: 1,
    ),
    turnApplicationController: controller,
    testApiClient: ApiClient(
      baseUrl: connection.baseUrl,
      apiKey: 'fixture-key',
      httpClient: httpClient,
    ),
    testRemotePromptSubmit: remoteSubmit,
    testNormalResume: resume,
    testStoredSessionKey: (_) => 'stored-chat',
    testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push<void>(MaterialPageRoute(builder: (_) => screen())),
              child: const Text('Open fixture chat'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open fixture chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _frames(tester);
  }

  Future<void> leave(WidgetTester tester) async {
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _frames(tester);
    expect(find.byType(ChatScreen), findsNothing);
  }

  Future<void> reopen(WidgetTester tester) async {
    nextId = 'stored-chat';
    await tester.tap(find.text('Open fixture chat'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await _frames(tester);
  }

  Future<void> send(WidgetTester tester, [String prompt = 'Question']) async {
    await tester.enterText(find.byType(TextField), prompt);
    await tester.tap(find.byTooltip('Send').hitTestable());
    await _frames(tester);
  }

  Future<void> close() => controller.close();
}

class _StockFixture extends _ChatFixture {
  final history = _HistoryClient();
  final calls = <_StockCall>[];
  bool autoStart = true;
  int resumeReads = 0;
  ResumedGatewaySession resumeResult = const ResumedGatewaySession(
    runtimeSessionId: 'runtime',
    running: true,
  );
  int get submissions => calls.length;
  String get turn => calls.last.turn;
  NormalGatewayApplicationSession get normal =>
      controller.normalSessionFor(connection);
  NormalGatewayChatOwner get chat => normal.findChat('local-chat')!;
  @override
  http.Client get httpClient => history;
  @override
  NormalGatewayResume get resume =>
      ({required localSessionId, required storedSessionId}) async {
        resumeReads++;
        return resumeResult;
      };
  @override
  TestRemotePromptSubmit get remoteSubmit =>
      ({required sessionId, required text, required onEvent, required onSent}) {
        final call = _StockCall('wire-turn-${calls.length + 1}', onEvent);
        calls.add(call);
        onSent();
        if (autoStart) {
          onEvent(
            StreamEvent(
              type: 'message.start',
              data: const {},
              turnId: call.turn,
            ),
          );
        }
        return call.rpc.future;
      };

  @override
  Future<void> send(WidgetTester tester, [String prompt = 'Question']) async {
    final before = submissions;
    await super.send(tester, prompt);
    expect(submissions, before + 1, reason: 'the real composer must submit');
    expect(chat.snapshot.wireEmitted, isTrue);
  }

  void emit(String type, Map<String, dynamic> data) =>
      calls.last.onEvent(StreamEvent(type: type, data: data, turnId: turn));
  void globalEvent(String type, Map<String, dynamic> data, {String? turn}) =>
      normal.receiveEvent(
        'local-chat',
        StreamEvent(type: type, data: data, turnId: turn),
      );
  void ack() {
    if (!calls.last.rpc.isCompleted) calls.last.rpc.complete();
  }

  Future<void> complete(WidgetTester tester, String text) async {
    emit('message.complete', {'text': text});
    emit('turn.end', {'status': 'completed'});
    ack();
    await _frames(tester);
    expect(chat.snapshot.phase, NormalGatewayTurnPhase.completed);
  }

  @override
  Future<void> close() async {
    for (final call in calls) {
      if (!call.rpc.isCompleted) call.rpc.complete();
    }
    await super.close();
  }
}

class _StockCall {
  _StockCall(this.turn, this.onEvent);
  final String turn;
  final StreamCallback onEvent;
  final rpc = Completer<void>();
}

class _HistoryClient extends http.BaseClient {
  List<Map<String, dynamic>> rows = [];
  bool fail = false;
  int historyReads = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final messages = request.url.path.endsWith('/messages');
    if (messages) historyReads++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'data': messages ? rows : []}))),
      messages && fail ? 500 : 200,
      headers: {'content-type': 'application/json'},
    );
  }
}

class _TerminalReceiptPlatform extends InMemorySharedPreferencesStore {
  _TerminalReceiptPlatform(super.data) : super.withData();
  bool armed = false;
  bool hold = false;
  bool reject = false;
  int attempts = 0;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (armed && key == 'flutter.${NormalGatewayPendingStore.preferenceKey}') {
      final rows = jsonDecode(value as String) as List;
      if (rows.any((row) => (row as Map)['phase'] == 'settled')) {
        attempts++;
        if (!entered.isCompleted) entered.complete();
        // Keep the first failed write real, then hold the retry rather than
        // allowing an in-memory immediate-rejection microtask loop to starve UI.
        if (hold || reject && attempts > 1) await release.future;
        if (reject) return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}

class _SseFixture extends _ChatFixture {
  final client = _SseClient();
  Future<void> settle(WidgetTester tester) async {
    // Raw controller.close() is not decoder/timeout subscription settlement.
    // Alternate the real cleanup zone and widget zone until the actual consumer
    // has received its terminal callback; advancing fake time cannot join it.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() async {});
      await tester.pump();
      final bars = tester.widgetList<ChatActivityBar>(
        find.byType(ChatActivityBar),
      );
      if (bars.isEmpty || bars.every((bar) => bar.isTerminalNotice)) return;
    }
    fail('SSE terminal callback did not cross the transformed body boundary');
  }

  @override
  http.Client get httpClient => client;
  @override
  Future<void> send(WidgetTester tester, [String prompt = 'Question']) async {
    final before = client.submissions;
    await super.send(tester, prompt);
    expect(client.submissions, before + 1);
  }

  @override
  Future<void> close() async {
    await client.closeBody();
    await super.close();
  }
}

class _SseClient extends _HistoryClient {
  StreamController<List<int>>? body;
  bool rejectSubmissions = false;
  int submissions = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'POST') return super.send(request);
    expect(request.url.path, endsWith('/v1/chat/completions'));
    submissions++;
    if (rejectSubmissions) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":{"message":"Rejected next send"}}')),
        409,
        headers: {'content-type': 'application/json'},
      );
    }
    body = StreamController<List<int>>();
    return http.StreamedResponse(
      body!.stream,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }

  void fragment(String frame) {
    final bytes = utf8.encode(frame);
    // Split LF/CRLF delimiters and JSON fields across genuine transport chunks.
    for (var i = 0; i < bytes.length; i += 7) {
      body!.add(bytes.sublist(i, (i + 7).clamp(0, bytes.length)));
    }
  }

  Future<void> closeBody() async {
    final current = body;
    if (current != null && !current.isClosed) await current.close();
  }
}
