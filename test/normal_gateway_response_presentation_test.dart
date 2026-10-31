import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cold owner never upgrades stock interrupted history into a final',
    () async {
      // This is the existing stock-contract capture, not a hand-annotated final.
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
      final f = _Fixture(rows: rows);
      addTearDown(f.close);
      final chat = await f.open();
      expect(_quiet(chat.snapshot), ['Prompt']);
      expect(
        _verbose(chat.snapshot),
        contains('Partial answer before interruption'),
      );
      expect(chat.snapshot.historyRows, rows);
      expect(chat.snapshot.hasActiveTurn, isFalse);
      expect(f.calls, isEmpty);
    },
  );

  for (final unknownFloor in [false, true]) {
    test(
      'lagging A history, B success, delayed A partial remains hidden: unknownFloor=$unknownFloor',
      () async {
        final f = _Fixture()..historyFails = unknownFloor;
        addTearDown(f.close);
        final chat = await f.open(seedHistory: !unknownFloor);
        final a = await f.begin(chat, 'A question');
        expect(chat.snapshot.rowFloor, unknownFloor ? isNull : 11);
        a.emit('message.delta', {'text': 'A received partial'});
        f.historyFails = false;
        // The authoritative idle read still contains only the previous turn.
        // A's persisted partial does not exist in any observed page yet.
        f.resumeResult = const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: false,
          status: 'idle',
        );
        a.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        expect(chat.snapshot.phase, NormalGatewayTurnPhase.reconciledUnknown);
        expect(_quiet(chat.snapshot), isNot(contains('A received partial')));

        f.resumeResult = const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: true,
        );
        final b = await f.begin(chat, 'B question');
        await f.complete(chat, b, 'B received final');
        expect(_quiet(chat.snapshot), contains('B received final'));

        final beforeReads = f.historyReads;
        for (final aMetadata in <Map<String, dynamic>>[
          {},
          {'partial': true},
          {'status': 'interrupted'},
          {'status': 'completed', 'partial': true},
        ]) {
          f.rows = [
            ..._previous,
            _row(12, 'user', 'A question'),
            _row(13, 'assistant', 'Delayed A saved partial', extra: aMetadata),
            _row(14, 'user', 'B question'),
            _row(
              15,
              'assistant',
              'B saved final',
              extra: {'status': 'completed'},
            ),
          ];
          // Exercise a later physical history observation, not a mutation of
          // the previous receipt or a guessed association by prose/order.
          final read = chat.beginHistoryRead('stored');
          final delayed = await f.readHistory('stored');
          expect(chat.observeHistory(delayed, read: read), isTrue);
          expect(
            _quiet(chat.snapshot),
            isNot(contains('Delayed A saved partial')),
          );
          expect(_quiet(chat.snapshot), isNot(contains('A received partial')));
          expect(_quiet(chat.snapshot), contains('B received final'));
          expect(_quiet(chat.snapshot), contains('Older confirmed answer'));
          expect(_verbose(chat.snapshot), contains('Delayed A saved partial'));
        }
        expect(f.historyReads, beforeReads + 4);
        final reopened = f.session.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Reopened',
        );
        expect(reopened, same(chat));
        expect(
          _quiet(reopened.snapshot),
          isNot(contains('Delayed A saved partial')),
        );
        expect(_quiet(reopened.snapshot), contains('B received final'));
        expect(f.calls, hasLength(2));
      },
    );
  }

  test(
    'unresolved donor alias import cannot promote its delayed saved partial',
    () async {
      final f = _Fixture()..historyFails = true;
      addTearDown(f.close);
      await f.session.ready;
      final donor = f.session.chatFor(
        'donor',
        storedSessionId: 'donor-stored',
        title: 'Donor',
      );
      final a = await f.begin(donor, 'Donor question');
      expect(donor.snapshot.rowFloor, isNull);
      a.emit('message.delta', {'text': 'Unresolved donor receipt'});
      f.historyFails = false;
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      a.ack();
      await _until(() => !donor.snapshot.hasActiveTurn);
      expect(donor.snapshot.phase, NormalGatewayTurnPhase.reconciledUnknown);

      final winner = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical route',
      );
      winner.observeHistory(_previous);
      final reservation = winner.reserve()!;
      donor.bindStoredSession('stored');
      await pumpEventQueue();
      expect(f.session.findChat('donor'), same(winner));
      expect(f.session.findChat('stored'), same(winner));
      expect(_verbose(winner.snapshot), contains('Unresolved donor receipt'));
      expect(
        _quiet(winner.snapshot),
        isNot(contains('Unresolved donor receipt')),
      );

      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: true,
      );
      final b = await f.begin(
        winner,
        'Winner question',
        reservation: reservation,
      );
      await f.complete(winner, b, 'Winner final');
      f.rows = [
        ..._previous,
        _row(12, 'user', 'Donor question'),
        _row(13, 'assistant', 'Delayed donor saved partial'),
        _row(14, 'user', 'Winner question'),
        _row(15, 'assistant', 'Winner saved final', extra: {'success': true}),
      ];
      final read = winner.beginHistoryRead('stored');
      expect(
        winner.observeHistory(await f.readHistory('stored'), read: read),
        isTrue,
      );
      expect(
        _quiet(winner.snapshot),
        isNot(contains('Delayed donor saved partial')),
      );
      expect(
        _quiet(winner.snapshot),
        isNot(contains('Unresolved donor receipt')),
      );
      expect(_quiet(winner.snapshot), contains('Winner final'));
      expect(
        _verbose(winner.snapshot),
        contains('Delayed donor saved partial'),
      );
      expect(_verbose(winner.snapshot), contains('Unresolved donor receipt'));
      expect(f.calls, hasLength(2));
    },
  );

  for (final boundary in ['resume', 'history']) {
    for (final staleStatus in ['idle', 'completed']) {
      test(
        'held $boundary $staleStatus cannot replace a retained owned failure',
        () async {
          final store = _SettlementStore();
          final f = _Fixture(pendingStore: store);
          addTearDown(f.close);
          final chat = await f.open();
          final call = await f.begin(chat, 'Question');
          call.emit('message.delta', {'text': 'Owned incomplete prose'});
          final entered = Completer<void>();
          final resumed = Completer<ResumedGatewaySession>();
          final history = Completer<List<Map<String, dynamic>>>();
          final stale = ResumedGatewaySession(
            runtimeSessionId: 'runtime',
            running: false,
            status: staleStatus,
          );
          if (boundary == 'resume') {
            f.resumeHook = () {
              if (!entered.isCompleted) entered.complete();
              return resumed.future;
            };
          } else {
            f.resumeResult = stale;
            f.historyHook = () {
              if (!entered.isCompleted) entered.complete();
              return history.future;
            };
          }
          call.ack();
          await entered.future;
          f.rows = [
            ..._previous,
            _row(12, 'user', 'Question'),
            _row(13, 'assistant', 'Owned incomplete prose'),
          ];
          store
            ..armed = true
            ..reject = true;
          call.emit('turn.error', {'error': 'Authoritative owned failure'});
          await store.entered.future;
          await _until(
            () =>
                chat.snapshot.phase == NormalGatewayTurnPhase.reconciling &&
                chat.snapshot.responseFailure != null,
          );
          if (boundary == 'resume') {
            resumed.complete(stale);
          } else {
            history.complete(f.rows);
          }
          await store.retryEntered.future;
          expect(chat.snapshot.responseFailure, 'Authoritative owned failure');
          expect(chat.snapshot.hasActiveTurn, isTrue);
          expect(chat.reserve(), isNull);
          expect(
            _quiet(chat.snapshot),
            isNot(contains('Owned incomplete prose')),
          );
          store.reject = false;
          store.release.complete();
          await _until(() => !chat.snapshot.hasActiveTurn);
          expect(chat.snapshot.phase, NormalGatewayTurnPhase.failed);
          expect(chat.snapshot.error, 'Authoritative owned failure');
          expect(_quiet(chat.snapshot), contains('Older confirmed answer'));
          expect(
            _quiet(chat.snapshot),
            isNot(contains('Owned incomplete prose')),
          );
          expect(f.calls, hasLength(1));
          expect(await store.load(_Fixture.scope), isEmpty);
        },
      );
    }
  }

  for (final veto in <Map<String, dynamic>>[
    {'partial': true},
    {'status': 'interrupted'},
    {'finish_reason': 'length'},
  ]) {
    test(
      'successful turn terminal cannot promote a vetoed response: $veto',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Question');
        call.emit('message.complete', {'text': 'Incomplete response', ...veto});
        expect(_quiet(chat.snapshot), isNot(contains('Incomplete response')));
        call.emit('turn.end', {'status': 'completed'});
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        expect(chat.snapshot.phase, NormalGatewayTurnPhase.completed);
        expect(
          chat.snapshot.displayRows.last['_chat_response_complete'],
          isFalse,
        );
        expect(_quiet(chat.snapshot), isNot(contains('Incomplete response')));
        expect(_verbose(chat.snapshot), contains('Incomplete response'));
      },
    );
  }

  test(
    'owned successful terminal can still confirm delta-only final prose',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Question');
      call.emit('message.delta', {'text': 'Completed delta-only reply'});
      call.emit('turn.end', {'status': 'completed'});
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      expect(_quiet(chat.snapshot), contains('Completed delta-only reply'));
    },
  );

  for (final io in ['held', 'rejected']) {
    test(
      'owned failure revokes current flags before $io settled-marker write',
      () async {
        final store = _SettlementStore();
        final f = _Fixture(pendingStore: store);
        addTearDown(f.close);
        final chat = await f.open();
        final a = await f.begin(chat, 'Successful prior question');
        await f.complete(chat, a, 'Successful prior reply');
        final priorScope =
            chat.snapshot.displayRows.last['_normal_projection_id'];
        final b = await f.begin(chat, 'Failing current question');
        b.emit('message.delta', {'text': 'Current provisional reply'});
        b.emit('message.complete', {'text': 'Current provisional reply'});
        final currentScope =
            chat.snapshot.displayRows.last['_normal_projection_id'];
        expect(currentScope, isNot(priorScope));
        expect(_quiet(chat.snapshot), contains('Current provisional reply'));
        final observed = <NormalGatewayChatSnapshot>[];
        final token = chat.subscribe(observed.add);
        addTearDown(() => chat.unsubscribe(token));
        store
          ..armed = true
          ..hold = io == 'held'
          ..reject = io == 'rejected';

        b.emit('turn.error', {'error': 'Owned authoritative failure'});
        // Revocation and subscriber visibility must precede every await, not just
        // eventual failure settlement after preferences acknowledges a tombstone.
        expect(chat.snapshot.responseFailure, 'Owned authoritative failure');
        expect(
          _scopeRow(chat.snapshot, currentScope)['_chat_response_complete'],
          isFalse,
        );
        expect(
          _scopeRow(chat.snapshot, priorScope)['_chat_response_complete'],
          isTrue,
        );
        expect(
          _quiet(chat.snapshot),
          isNot(contains('Current provisional reply')),
        );
        expect(_quiet(chat.snapshot), contains('Successful prior reply'));
        expect(observed.last.responseFailure, 'Owned authoritative failure');
        expect(
          _quiet(observed.last),
          isNot(contains('Current provisional reply')),
        );
        expect(chat.snapshot.hasActiveTurn, isTrue);
        expect(chat.reserve(), isNull);
        b.ack();
        await _until(() => store.entered.isCompleted);
        await pumpEventQueue();
        if (io == 'rejected') {
          expect(store.attempts, greaterThanOrEqualTo(2));
        }
        expect(chat.snapshot.hasActiveTurn, isTrue);
        expect(chat.reserve(), isNull);
        expect(_verbose(chat.snapshot), contains('Current provisional reply'));
        final durable = await NormalGatewayPendingStore().load(_Fixture.scope);
        expect(durable, hasLength(1));
        expect(durable.single.phase, 'emitted');

        // Reattachment cannot borrow a prior success or revive this admission.
        final reopened = f.session.chatFor('stored', title: 'Reopened');
        expect(reopened, same(chat));
        expect(
          reopened.snapshot.responseFailure,
          'Owned authoritative failure',
        );
        expect(
          _quiet(reopened.snapshot),
          isNot(contains('Current provisional reply')),
        );
        expect(_quiet(reopened.snapshot), contains('Successful prior reply'));
        store.reject = false;
        if (!store.release.isCompleted) store.release.complete();
        chat.requestRecovery();
        await _until(() => !chat.snapshot.hasActiveTurn);
        expect(chat.snapshot.phase, NormalGatewayTurnPhase.failed);
        expect(chat.snapshot.error, 'Owned authoritative failure');
        expect(await store.load(_Fixture.scope), isEmpty);
        expect(
          _quiet(chat.snapshot),
          isNot(contains('Current provisional reply')),
        );
        expect(_quiet(chat.snapshot), contains('Successful prior reply'));
        expect(f.calls, hasLength(2));
      },
    );
  }

  test(
    'permanent settlement rejection backs off without starving the UI',
    () async {
      final store = _SettlementStore();
      final f = _Fixture(pendingStore: store);
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Failing question');
      call.emit('message.complete', {'text': 'Provisional answer'});
      store
        ..armed = true
        ..reject = true
        ..rejectPermanently = true;
      call.emit('turn.error', {'error': 'Permanent storage rejection'});
      call.ack();
      // An unbounded microtask retry loop prevents even this event-loop turn.
      await pumpEventQueue();
      final attempts = store.attempts;
      expect(attempts, inInclusiveRange(1, 4));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        store.attempts,
        attempts,
        reason: 'Recovery must use its retry timer',
      );
      expect(chat.snapshot.responseFailure, 'Permanent storage rejection');
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(chat.reserve(), isNull);
      expect(_quiet(chat.snapshot), isNot(contains('Provisional answer')));
      expect(_quiet(chat.snapshot), contains('Older confirmed answer'));
      expect(
        await NormalGatewayPendingStore().load(_Fixture.scope),
        hasLength(1),
      );
    },
  );

  test(
    'rejected failure receipt restart cannot display untyped saved partial',
    () async {
      final store = _SettlementStore();
      final f = _Fixture(pendingStore: store);
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Interrupted question');
      call.emit('message.complete', {'text': 'Revoked pre-restart partial'});
      store
        ..armed = true
        ..reject = true;
      call.emit('turn.error', {'error': 'Failure before restart'});
      call.ack();
      await _until(() => store.entered.isCompleted);
      await pumpEventQueue();
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(
        _quiet(chat.snapshot),
        isNot(contains('Revoked pre-restart partial')),
      );
      expect(
        await NormalGatewayPendingStore().load(_Fixture.scope),
        hasLength(1),
      );
      await f.close();

      final restarted = _Fixture(
        rows: [
          ..._previous,
          _row(12, 'user', 'Interrupted question'),
          _row(13, 'assistant', 'Delayed post-restart partial'),
        ],
        resumeResult: const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: false,
          status: 'idle',
        ),
      );
      addTearDown(restarted.close);
      await restarted.session.ready;
      final reopened = restarted.session.chatFor(
        'stored',
        title: 'Cold reopen',
      );
      await _until(() => !reopened.snapshot.hasActiveTurn);
      expect(
        _quiet(reopened.snapshot),
        isNot(contains('Delayed post-restart partial')),
      );
      expect(_quiet(reopened.snapshot), contains('Older confirmed answer'));
      expect(
        _verbose(reopened.snapshot),
        contains('Delayed post-restart partial'),
      );
      expect(restarted.calls, isEmpty, reason: 'recovery must not resubmit');
    },
  );
  group('explicit persisted-turn handover', () {
    for (final unknownFloor in [false, true]) {
      for (final sameText in [false, true]) {
        test(
          'committed IDs hand over one prompt/reply: unknownFloor=$unknownFloor sameText=$sameText',
          () async {
            final f = _Fixture()..historyFails = unknownFloor;
            addTearDown(f.close);
            final chat = await f.open(seedHistory: !unknownFloor);
            final observed = <NormalGatewayChatSnapshot>[];
            final token = chat.subscribe(observed.add);
            addTearDown(() => chat.unsubscribe(token));
            final call = await f.begin(chat, 'Current question');
            call.emit('message.delta', {'text': 'Wire answer'});
            call.emit('message.complete', {
              'text': 'Wire answer',
              'status': 'complete',
              'persisted_turn': _receipt(),
            });
            expect(chat.snapshot.hasActiveTurn, isTrue);
            expect(chat.snapshot.displayRows, isNotEmpty);
            // Completion identifies stored rows, not lifecycle settlement.
            expect(chat.reserve(), isNull);
            f.historyFails = false;
            final saved = sameText
                ? 'Wire answer'
                : 'Saved authoritative answer';
            f.rows = _committedRows(answer: saved);
            expect(chat.observeHistory(f.rows), isFalse);
            call.emit('turn.end', {'status': 'completed'});
            call.ack();
            await _until(() => !chat.snapshot.hasActiveTurn);
            await pumpEventQueue();
            expect(chat.snapshot.historyRows, f.rows);
            expect(chat.snapshot.displayRows, isEmpty);
            expect(chat.snapshot.timeline.runs, isEmpty);
            expect(chat.snapshot.tools, isEmpty);
            expect(chat.snapshot.receivedOutcomes, isEmpty);
            expect(_quiet(chat.snapshot), [
              'Older question',
              'Older confirmed answer',
              'Current question',
              saved,
            ]);
            expect(
              observed.every(
                (s) =>
                    _quiet(s).where((t) => t == 'Current question').length <= 1,
              ),
              isTrue,
              reason: 'handover must not publish canonical and received copies',
            );
            final reopened = f.session.chatFor('stored', title: 'Reopened');
            expect(reopened, same(chat));
            expect(_quiet(reopened.snapshot), _quiet(chat.snapshot));
            expect(f.calls, hasLength(1));
          },
        );
      }
    }

    test(
      'lagging history retains output until a later exact-ID read',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Current question');
        call.emit('message.complete', {
          'text': 'Wire answer',
          'persisted_turn': _receipt(),
        });
        call.emit('turn.end', {'status': 'completed'});
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        final retained = chat.snapshot.displayRows;
        expect(_quiet(chat.snapshot), contains('Wire answer'));
        for (final stale in <List<Map<String, dynamic>>>[
          [],
          _previous,
          [_row(12, 'user', 'Current question')],
          _committedRows(finalMetadata: {}),
          _committedRows(finalMetadata: {'status': 'interrupted'}),
          _committedRows(
            finalMetadata: {'status': 'completed', 'partial': true},
          ),
          [
            ..._previous,
            _row(12, 'assistant', 'Wrong anchor role'),
            _row(
              13,
              'assistant',
              'Wire answer',
              extra: {'status': 'completed'},
            ),
          ],
          [
            ..._previous,
            _row(12, 'user', 'Current question'),
            _row(
              13,
              'tool',
              'Not a final reply',
              extra: {'status': 'completed'},
            ),
          ],
          [
            ..._previous,
            _row(100, 'user', 'Current question'),
            _row(
              101,
              'assistant',
              'Wire answer',
              extra: {'status': 'completed'},
            ),
          ],
        ]) {
          expect(chat.observeHistory(stale), isTrue);
          expect(chat.snapshot.displayRows, retained);
        }
        expect(chat.observeHistory(_committedRows()), isTrue);
        expect(chat.snapshot.displayRows, isEmpty);
        expect(
          _quiet(chat.snapshot).where((s) => s == 'Wire answer'),
          hasLength(1),
        );
        expect(f.calls, hasLength(1));
      },
    );

    for (final invalid in <dynamic>[
      null,
      'not a receipt',
      {
        'row_ids': [12, 13],
        'complete': false,
        'user_row_id': 12,
        'final_assistant_row_id': 13,
      },
      {
        'row_ids': [12, 13],
        'complete': 'true',
        'user_row_id': 12,
        'final_assistant_row_id': 13,
      },
      {
        'row_ids': ['12', 13],
        'complete': true,
        'user_row_id': 12,
        'final_assistant_row_id': 13,
      },
      {
        'row_ids': [12, 12, 13],
        'complete': true,
        'user_row_id': 12,
        'final_assistant_row_id': 13,
      },
      {
        'row_ids': [13, 12],
        'complete': true,
        'user_row_id': 12,
        'final_assistant_row_id': 13,
      },
      {
        'row_ids': [12, 13],
        'complete': true,
        'user_row_id': 11,
        'final_assistant_row_id': 13,
      },
      {
        'row_ids': [12, 13],
        'complete': true,
        'user_row_id': 12,
        'final_assistant_row_id': 14,
      },
      {
        'row_ids': [12, 13],
        'complete': true,
        'user_row_id': 12,
      },
    ]) {
      test(
        'unproved receipt cannot retire received output: $invalid',
        () async {
          final f = _Fixture();
          addTearDown(f.close);
          final chat = await f.open();
          final call = await f.begin(chat, 'Current question');
          f.rows = _committedRows();
          call.emit('message.complete', {
            'text': 'Wire answer',
            'persisted_turn': invalid,
          });
          call.emit('turn.end', {'status': 'completed'});
          call.ack();
          await _until(() => !chat.snapshot.hasActiveTurn);
          await pumpEventQueue();
          expect(
            chat.snapshot.displayRows.map((r) => r['content']),
            contains('Wire answer'),
          );
          expect(f.calls, hasLength(1));
        },
      );
    }

    test(
      'receipt removes only its own prior scope after the next turn',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final a = await f.begin(chat, 'Unproved question');
        await f.complete(chat, a, 'Unproved earlier answer');
        final b = await f.begin(chat, 'Current question');
        b.emit('message.complete', {
          'text': 'Wire answer',
          'persisted_turn': _receipt(),
        });
        b.emit('turn.end', {'status': 'completed'});
        b.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        final c = await f.begin(chat, 'Later question');
        c.emit('message.delta', {'text': 'Later live answer'});
        c.emit('message.complete', {'text': 'Later live answer'});
        c.emit('turn.end', {'status': 'completed'});
        c.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        expect(chat.observeHistory(_committedRows()), isTrue);
        expect(chat.snapshot.displayRows.map((r) => r['content']), [
          'Unproved question',
          'Unproved earlier answer',
          'Later question',
          'Later live answer',
        ]);
        expect(
          _quiet(chat.snapshot).where((s) => s == 'Current question'),
          hasLength(1),
        );
        expect(chat.snapshot.receivedOutcomes, hasLength(2));
        expect(f.calls, hasLength(3));
      },
    );

    test('owned receipt settles success after idle without losing handover', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      f.rows = _committedRows();
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      call.emit('message.delta', {'text': 'Wire answer'});
      call.emit('message.complete', {
        'text': 'Wire answer',
        'persisted_turn': _receipt(),
      });
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      // Policy (stock-idle receipt settlement): an owned successful wire
      // receipt plus authoritative idle and committed rows settles success;
      // stock resume never reports a terminal status itself.
      expect(chat.phase, NormalGatewayTurnPhase.completed);
      expect(chat.snapshot.status, isNull);
      expect(chat.snapshot.displayRows, isEmpty);
      expect(
        _quiet(chat.snapshot).where((s) => s == 'Wire answer'),
        hasLength(1),
      );
      expect(await f.pendingStore.load(_Fixture.scope), isEmpty);
      expect(f.calls, hasLength(1));
    });

    test('body activity after a successful completion revokes receipt settlement', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      f.rows = _committedRows(answer: 'Part one more');
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      call.emit('message.delta', {'text': 'Part one'});
      call.emit('message.complete', {'text': 'Part one', 'status': 'complete'});
      // Same-generation body activity extends the response scope: the earlier
      // completion no longer proves the current scope, and no final receipt
      // covers the extension. Authoritative idle plus the partial durable row
      // must therefore settle unknown, not completed.
      call.emit('message.delta', {'text': ' more'});
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.reconciledUnknown);
      expect(chat.snapshot.status?.kind, 'reconciled_unknown');
      expect(f.calls, hasLength(1));
    });

    test('a renewed matching completion restores receipt settlement', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      f.rows = _committedRows(answer: 'Part one more');
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      call.emit('message.delta', {'text': 'Part one'});
      call.emit('message.complete', {'text': 'Part one', 'status': 'complete'});
      call.emit('message.delta', {'text': ' more'});
      // A subsequent valid final receipt covering the extended scope
      // re-establishes success settlement.
      call.emit('message.complete', {
        'text': 'Part one more',
        'status': 'complete',
      });
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.completed);
      expect(f.calls, hasLength(1));
    });

    test('a foreign delayed ID-less completion cannot settle the next turn', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final a = await f.begin(chat, 'First question');
      f.rows = _committedRows(answer: 'First answer');
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      a.emit('message.delta', {'text': 'First answer'});
      a.emit('message.complete', {
        'text': 'First answer',
        'status': 'complete',
      });
      a.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.completed);
      final b = await f.begin(chat, 'Second question');
      f.rows = [
        ..._committedRows(answer: 'First answer'),
        _row(14, 'user', 'Second question'),
        _row(15, 'assistant', 'Second partial'),
      ];
      b.emit('message.delta', {'text': 'Second partial'});
      // Delayed replay of the previous turn's completion, delivered through
      // the production global ingress with no turn identity. Prior-response
      // activity alone must not let it settle B; its payload does not match
      // anything B streamed.
      f.session.receiveEvent(
        'local',
        StreamEvent(
          type: 'message.complete',
          data: {'text': 'First answer', 'status': 'complete'},
        ),
      );
      b.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.reconciledUnknown);
      expect(chat.snapshot.status?.kind, 'reconciled_unknown');
      expect(f.calls, hasLength(2));
    });

    test('empty or absent completion payload cannot establish the receipt', () async {
      for (final payload in <Map<String, dynamic>>[
        {},
        {'rendered': ''},
        {'text': ''},
      ]) {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Current question');
        f.rows = _committedRows(answer: 'Streamed answer');
        f.resumeResult = const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: false,
          status: 'idle',
        );
        call.emit('message.delta', {'text': 'Streamed answer'});
        // ID-less empty-payload completion through the global ingress: an
        // absent or empty payload vacuously "matches" any stream and must
        // not grant success authority.
        f.session.receiveEvent(
          'local',
          StreamEvent(type: 'message.complete', data: payload),
        );
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        expect(chat.phase, NormalGatewayTurnPhase.reconciledUnknown,
            reason: 'payload $payload must not settle success');
        expect(chat.snapshot.status?.kind, 'reconciled_unknown');
        expect(f.calls, hasLength(1));
      }
    });

    test('confirmed steering without new body activity settles unknown', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      f.rows = _committedRows(answer: 'Streamed answer');
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      call.emit('message.delta', {'text': 'Streamed answer'});
      call.emit('message.complete', {
        'text': 'Streamed answer',
        'status': 'complete',
      });
      // Accepted guidance advances the response scope; interrupting before
      // any post-steer body activity leaves the pre-steer receipt stale, so
      // authoritative idle plus the prior durable row must settle unknown.
      expect(await chat.steer('Focus on the payload contract'), isTrue);
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.reconciledUnknown);
      expect(chat.snapshot.status?.kind, 'reconciled_unknown');
      expect(f.calls, hasLength(1));
    });

    test('renewed matching completion after steering restores success', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      f.rows = _committedRows(answer: 'Streamed answer');
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      call.emit('message.delta', {'text': 'Streamed answer'});
      call.emit('message.complete', {
        'text': 'Streamed answer',
        'status': 'complete',
      });
      expect(await chat.steer('Focus on the payload contract'), isTrue);
      // The server finishes the guided turn with the same streamed text: a
      // renewed exact-match completion re-establishes success settlement.
      call.emit('message.complete', {
        'text': 'Streamed answer',
        'status': 'complete',
      });
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.completed);
      expect(f.calls, hasLength(1));
    });

    test('reused preview completion settles success from its selected scope', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      f.rows = _committedRows(answer: 'Selected final preview');
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      call.emit('message.delta', {'text': 'Unselected commentary'});
      call.emit('message.interim', {
        'text': 'Unselected commentary',
        'already_streamed': true,
      });
      call.emit('message.delta', {'text': 'Selected final preview'});
      call.emit('message.interim', {
        'text': 'Selected final preview',
        'already_streamed': true,
      });
      // The sealed same-turn preview is the selected scope; the empty
      // pending boundary must carry no authority. ID-less reused completion
      // through the global ingress settles success from that scope.
      f.session.receiveEvent(
        'local',
        StreamEvent(
          type: 'message.complete',
          data: {
            'text': 'Selected final preview',
            'response_reused': true,
            'persisted_turn': _receipt(),
          },
        ),
      );
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.completed);
      expect(
        chat.snapshot.displayRows,
        isEmpty,
        reason: 'handover retires the received scope; no duplicate row',
      );
      expect(
        _quiet(chat.snapshot).where((s) => s == 'Selected final preview'),
        hasLength(1),
        reason: 'exact target retained exactly once',
      );
      expect(f.calls, hasLength(1));
    });

    test('transformed completion settles success via its raw streamed text', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final call = await f.begin(chat, 'Current question');
      f.rows = _committedRows(answer: 'Selected final preview');
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      call.emit('message.delta', {'text': 'Selected final preview'});
      f.session.receiveEvent(
        'local',
        StreamEvent(
          type: 'message.complete',
          data: {
            'text': 'Selected final preview',
            'rendered': '**Selected final preview**',
            'response_transformed': true,
          },
        ),
      );
      call.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      await pumpEventQueue();
      expect(chat.phase, NormalGatewayTurnPhase.completed);
      expect(f.calls, hasLength(1));
    });

    test(
      'an unowned completion cannot lend its saved IDs to the next turn',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Current question');
        f.session.receiveEvent(
          'local',
          StreamEvent(
            type: 'message.complete',
            turnId: 'another-turn',
            data: {'text': 'Wire answer', 'persisted_turn': _receipt()},
          ),
        );
        f.rows = _committedRows();
        await f.complete(chat, call, 'Wire answer');
        expect(
          chat.snapshot.displayRows.map((r) => r['content']),
          contains('Wire answer'),
        );
        expect(f.calls, hasLength(1));
      },
    );

    test(
      'failed completion cannot use a positive persistence receipt',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Current question');
        f.rows = _committedRows();
        call.emit('message.complete', {
          'text': 'Wire answer',
          'status': 'error',
          'partial': true,
          'persisted_turn': _receipt(),
        });
        call.emit('turn.error', {'error': 'Current turn failed'});
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        expect(chat.phase, NormalGatewayTurnPhase.failed);
        expect(chat.snapshot.displayRows, isNotEmpty);
        expect(_verbose(chat.snapshot), contains('Wire answer'));
        expect(f.calls, hasLength(1));
      },
    );

    test(
      'a pre-submit history request cannot confirm a later receipt',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final stale = chat.beginHistoryRead('stored');
        final call = await f.begin(chat, 'Current question');
        call.emit('message.complete', {
          'text': 'Wire answer',
          'persisted_turn': _receipt(),
        });
        call.emit('turn.end', {'status': 'completed'});
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        expect(chat.observeHistory(_committedRows(), read: stale), isFalse);
        expect(chat.snapshot.displayRows, isNotEmpty);
        expect(chat.observeHistory(_committedRows()), isTrue);
        expect(chat.snapshot.displayRows, isEmpty);
      },
    );
    test(
      'complete context confirms all rows without expanding latest authority',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Current question');
        call.emit('tool.start', {'tool_id': 'one', 'name': 'terminal'});
        call.emit('tool.complete', {
          'tool_id': 'one',
          'name': 'terminal',
          'result': 'Passed',
        });
        final receipt = {
          ..._receipt(),
          'row_ids': [12, 13, 14],
          'final_assistant_row_id': 14,
        };
        call.emit('message.complete', {
          'text': 'Wire answer',
          'persisted_turn': receipt,
        });
        call.emit('turn.end', {'status': 'completed'});
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        final context = [
          _row(12, 'user', 'Current question'),
          _row(13, 'tool', 'Passed', extra: {'tool_call_id': 'one'}),
          _row(14, 'assistant', 'Wire answer', extra: {'status': 'completed'}),
        ];
        final latest = [context.last];
        expect(chat.persistedTurnContextKey(latest), isNotNull);
        // Matching endpoints alone must not discard the received tool.
        expect(chat.observeHistory([context.first, context.last]), isTrue);
        expect(chat.snapshot.tools, hasLength(1));
        expect(chat.snapshot.displayRows, isNotEmpty);
        // A stale completed context copy cannot override a current partial veto.
        final partial = [
          {...context.last, 'partial': true},
        ];
        expect(chat.observeHistory(partial, confirmedRows: context), isTrue);
        expect(chat.snapshot.displayRows, isNotEmpty);
        expect(chat.observeHistory(latest, confirmedRows: context), isTrue);
        expect(
          chat.snapshot.historyRows,
          latest,
          reason: 'only offset zero is latest authority',
        );
        expect(chat.snapshot.displayRows, isEmpty);
        expect(chat.snapshot.timeline.runs, isEmpty);
        expect(chat.snapshot.tools, isEmpty);
        expect(chat.persistedTurnContextKey(latest), isNull);
      },
    );

    test(
      'post-completion body activity revokes an earlier persistence claim',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Current question');
        call.emit('message.complete', {
          'text': 'Wire answer',
          'persisted_turn': _receipt(),
        });
        call.emit('message.delta', {'text': ' plus later output'});
        f.rows = _committedRows();
        call.emit('turn.end', {'status': 'completed'});
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        expect(
          chat.snapshot.displayRows.map((r) => r['content']),
          contains('Wire answer plus later output'),
        );
        expect(chat.snapshot.timeline.runs, isNotEmpty);
      },
    );

    test(
      'captured receipt does not borrow mutable callback payloads',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final chat = await f.open();
        final call = await f.begin(chat, 'Current question');
        final receipt = _receipt();
        call.emit('message.complete', {
          'text': 'Wire answer',
          'persisted_turn': receipt,
        });
        (receipt['row_ids'] as List)[0] = 99;
        receipt['complete'] = false;
        f.rows = _committedRows();
        call.emit('turn.end', {'status': 'completed'});
        call.ack();
        await _until(() => !chat.snapshot.hasActiveTurn);
        await pumpEventQueue();
        expect(chat.snapshot.displayRows, isEmpty);
      },
    );

    test(
      'verified alias handoff retains the receipt and independent child observer',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final donor = await f.open();
        final call = await f.begin(donor, 'Current question');
        call.emit('subagent.start', {
          'subagent_id': 'child-1',
          'child_session_id': 'child-chat',
          'goal': 'Keep observing',
        });
        call.emit('message.complete', {
          'text': 'Wire answer',
          'persisted_turn': _receipt(),
        });
        call.emit('turn.end', {'status': 'completed'});
        call.ack();
        await _until(() => !donor.snapshot.hasActiveTurn);
        await pumpEventQueue();
        final canonical = f.session.chatFor(
          'canonical',
          storedSessionId: 'canonical',
          title: 'Canonical',
        );
        final reservation = canonical.reserve()!;
        donor.bindStoredSession('canonical');
        expect(f.session.findChat('local'), same(canonical));
        canonical.cancelPreparation(reservation);
        expect(canonical.observeHistory(_committedRows()), isTrue);
        expect(canonical.snapshot.displayRows, isEmpty);
        expect(canonical.snapshot.subagents, isNotEmpty);
        f.session.receiveEvent(
          'canonical',
          StreamEvent(
            type: 'subagent.complete',
            data: {
              'subagent_id': 'child-1',
              'status': 'completed',
              'result': 'Child finished',
            },
          ),
        );
        expect(canonical.snapshot.subagents.single.isComplete, isTrue);
        expect(f.calls, hasLength(1));
      },
    );

    test('unknown floor with an owned successful receipt releases admission as '
        'unknown instead of leaving the turn busy', () async {
      final f = _Fixture()..historyFails = true;
      addTearDown(f.close);
      final chat = await f.open(seedHistory: false);
      final a = await f.begin(chat, 'A question');
      expect(chat.snapshot.rowFloor, isNull);
      a.emit('message.delta', {'text': 'Final answer'});
      // An owned successful wire receipt is the only success evidence, and
      // it cannot be proven without the durable response-row floor.
      a.emit('message.complete', {
        'text': 'Final answer',
        'status': 'complete',
      });
      f.historyFails = false;
      f.rows = [
        _row(1, 'user', 'A question'),
        _row(2, 'assistant', 'Final answer'),
      ];
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      a.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      expect(chat.snapshot.phase, NormalGatewayTurnPhase.reconciledUnknown);
    });

    test('a rejected ID-less completion cannot manufacture the next completion '
        'evidence', () async {
      final f = _Fixture();
      addTearDown(f.close);
      final chat = await f.open();
      final a = await f.begin(chat, 'A question');
      a.emit('message.delta', {'text': 'Second partial'});
      // Two ID-less completions carry an earlier answer. The first fails the
      // raw-scope gate but overwrites the presentation row; the second must
      // not compare against that overwritten content.
      for (var i = 0; i < 2; i++) {
        a.onEvent(
          StreamEvent(
            type: 'message.complete',
            data: {'text': 'Previous answer', 'status': 'complete'},
          ),
        );
      }
      // Authoritative idle plus a persisted partial must not complete the
      // turn: no owned receipt was ever established.
      f.rows = [
        ..._previous,
        _row(12, 'user', 'A question'),
        _row(
          13,
          'assistant',
          'Previous answer',
          extra: {'status': 'interrupted'},
        ),
      ];
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      a.ack();
      await _until(() => !chat.snapshot.hasActiveTurn);
      expect(chat.snapshot.phase, NormalGatewayTurnPhase.reconciledUnknown);
    });
  });
}

Map<String, dynamic> _receipt() => {
  'row_ids': [12, 13],
  'complete': true,
  'user_row_id': 12,
  'user_row_ids': [12],
  'final_assistant_row_id': 13,
};

List<Map<String, dynamic>> _committedRows({
  String answer = 'Wire answer',
  Map<String, dynamic> finalMetadata = const {'status': 'completed'},
}) => [
  ..._previous,
  _row(12, 'user', 'Current question'),
  _row(13, 'assistant', answer, extra: finalMetadata),
];

Map<String, dynamic> _row(
  int id,
  String role,
  String content, {
  Map<String, dynamic> extra = const {},
}) => {'id': id, 'role': role, 'content': content, ...extra};

final _previous = [
  _row(10, 'user', 'Older question'),
  _row(
    11,
    'assistant',
    'Older confirmed answer',
    extra: {'status': 'completed'},
  ),
];

List<String> _present(
  NormalGatewayChatSnapshot snapshot, {
  required bool quiet,
}) => [
  for (final section in buildNormalChatDisplaySections(
    canonicalRows: snapshot.historyRows,
    receivedRows: snapshot.displayRows,
    receivedTimeline: snapshot.timeline,
    receivedTools: snapshot.tools,
    receivedOutcomes: snapshot.receivedOutcomes,
    conversationOnly: quiet,
    verbose: !quiet,
  ))
    for (final row in section.items.whereType<Map<String, dynamic>>())
      row['_display_content'] as String,
];

List<String> _quiet(NormalGatewayChatSnapshot snapshot) =>
    _present(snapshot, quiet: true);
List<String> _verbose(NormalGatewayChatSnapshot snapshot) =>
    _present(snapshot, quiet: false);

Map<String, dynamic> _scopeRow(
  NormalGatewayChatSnapshot snapshot,
  Object? scope,
) => snapshot.displayRows.singleWhere(
  (row) => row['_normal_projection_id'] == scope,
);

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(
    predicate(),
    isTrue,
    reason: 'bounded owner transition did not arrive',
  );
}

class _SettlementStore extends NormalGatewayPendingStore {
  bool armed = false;
  bool hold = false;
  bool reject = false;
  bool rejectPermanently = false;
  int attempts = 0;
  final entered = Completer<void>();
  final retryEntered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> put(NormalGatewayPendingMarker marker) async {
    if (armed && marker.phase == 'settled') {
      attempts++;
      if (!entered.isCompleted) entered.complete();
      if (attempts > 1 && !retryEntered.isCompleted) retryEntered.complete();
      // Held/rejected fixtures control their retry I/O independently. The
      // permanent-rejection case instead verifies the production retry timer.
      if (hold || reject && attempts > 1 && !rejectPermanently) {
        await release.future;
      }
      if (reject) throw StateError('settled marker storage rejected');
    }
    await super.put(marker);
  }
}

class _Fixture {
  static const scope = 'strict-response-presentation';
  final NormalGatewayPendingStore pendingStore;
  late final NormalGatewayApplicationSession session;
  List<Map<String, dynamic>> rows;
  bool historyFails = false;
  int historyReads = 0;
  ResumedGatewaySession resumeResult;
  Future<ResumedGatewaySession> Function()? resumeHook;
  Future<List<Map<String, dynamic>>> Function()? historyHook;
  bool steerAccepted = true;
  final calls = <_Call>[];
  final flights = <Future<void>>[];
  bool _closed = false;

  _Fixture({
    NormalGatewayPendingStore? pendingStore,
    List<Map<String, dynamic>>? rows,
    this.resumeResult = const ResumedGatewaySession(
      runtimeSessionId: 'runtime',
      running: true,
    ),
  }) : pendingStore = pendingStore ?? NormalGatewayPendingStore(),
       rows = rows ?? List.of(_previous) {
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'strict-response',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture-key',
      ),
      scope: scope,
      pendingStore: this.pendingStore,
      history: readHistory,
      resume: ({required localSessionId, required storedSessionId}) async {
        final hook = resumeHook;
        return hook == null ? resumeResult : await hook();
      },
      steer: ({required sessionId, required text}) async => steerAccepted,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            // The constructor's submit hook uses global application ingress;
            // its per-submit callback is intentionally inert in production.
            final call = _Call(
              'wire-${calls.length + 1}',
              (event) => session.receiveEvent(sessionId, event),
            );
            calls.add(call);
            onSent();
            return call.rpc.future;
          },
    );
  }

  Future<List<Map<String, dynamic>>> readHistory(String id) async {
    historyReads++;
    final hook = historyHook;
    if (hook != null) return hook();
    if (historyFails) throw StateError('history is unavailable');
    return rows;
  }

  Future<NormalGatewayChatOwner> open({bool seedHistory = true}) async {
    await session.ready;
    final chat = session.chatFor(
      'local',
      storedSessionId: 'stored',
      title: 'Fixture',
    );
    if (seedHistory) expect(chat.observeHistory(rows), isTrue);
    return chat;
  }

  Future<_Call> begin(
    NormalGatewayChatOwner chat,
    String prompt, {
    Object? reservation,
  }) async {
    await session.ready;
    final before = calls.length;
    final admission = reservation ?? chat.reserve();
    expect(admission, isNotNull);
    final flight = chat.submitPrepared(
      reservation: admission!,
      text: prompt,
      localContent: prompt,
    );
    flights.add(flight);
    flight.ignore();
    await _until(() => calls.length > before);
    final call = calls.last;
    call.emit('message.start', {});
    expect(chat.snapshot.wireEmitted, isTrue);
    return call;
  }

  Future<void> complete(
    NormalGatewayChatOwner chat,
    _Call call,
    String text,
  ) async {
    call.emit('message.complete', {'text': text});
    call.emit('turn.end', {'status': 'completed'});
    call.ack();
    await _until(() => !chat.snapshot.hasActiveTurn);
    expect(chat.snapshot.phase, NormalGatewayTurnPhase.completed);
    await pumpEventQueue();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await session.close();
    final store = pendingStore;
    if (store is _SettlementStore) {
      if (!store.release.isCompleted) store.release.complete();
    }
    for (final call in calls) {
      call.ack();
    }
    for (final flight in flights) {
      await flight.catchError((Object _) {});
    }
  }
}

class _Call {
  _Call(this.turn, this.onEvent);
  final String turn;
  final StreamCallback onEvent;
  final rpc = Completer<void>();

  void emit(String type, Map<String, dynamic> data) =>
      onEvent(StreamEvent(type: type, turnId: turn, data: data));

  void ack() {
    if (!rpc.isCompleted) rpc.complete();
  }
}
