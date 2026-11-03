import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/normal_gateway_persisted_turn.dart';
import 'package:hermes_android/core/services/chat_history_window.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'receipt replacement reaches both subscribers before scopes retire',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final owner = await f.open();
      final context = _committedRows();
      await f.settleReceipt(owner, context);
      final routeA = <NormalGatewayChatSnapshot>[];
      final routeB = <NormalGatewayChatSnapshot>[];
      owner.subscribe(routeA.add);
      owner.subscribe(routeB.add);
      routeA.clear();
      routeB.clear();
      final heldA = owner.beginHistoryRead('stored');
      final freshB = owner.beginHistoryRead('stored');

      expect(
        owner.observeHistory(f.rows, read: freshB, confirmedRows: context),
        isTrue,
      );

      expect(routeA, hasLength(1));
      expect(routeB, hasLength(1));
      final handoff = routeA.single;
      expect(routeB.single, same(handoff));
      expect(handoff.historyRows, f.rows);
      expect(handoff.historyRows, hasLength(ChatHistoryWindow.pageSize));
      expect(handoff.historyPresentationRows, [..._previous, ...context]);
      expect(handoff.displayRows, isEmpty);
      expect(handoff.timeline.runs, isEmpty);
      expect(handoff.tools, isEmpty);
      expect(handoff.receivedOutcomes, isEmpty);
      expect(handoff.rowFloor, 2);
      expect(handoff.phase, NormalGatewayTurnPhase.completed);
      // A presentation fan-out supplies no physical OFFSET or exhaustion proof.
      final window = ChatHistoryWindow()
        ..acceptRecent(ChatHistoryPageBatch(f.rows, f.rows.length, true));
      final offset = window.olderOffset;
      window.mergeObservedRows(handoff.historyPresentationRows);
      expect(window.olderOffset, offset);
      expect(window.hasOlder, isTrue);

      expect(
        owner.observeHistory(f.rows, read: heldA, confirmedRows: context),
        isFalse,
      );
      expect(routeA, hasLength(1));
      final updated = {
        ...context.last,
        'content': 'Corrected saved final',
        'partial': true,
      };
      expect(owner.observeHistory([updated]), isTrue);
      expect(owner.snapshot.historyRows, [updated]);
      expect(
        owner.snapshot.historyPresentationRows.firstWhere(
          (r) => r['id'] == 3,
        )['content'],
        'Current prompt',
      );
      expect(owner.snapshot.historyPresentationRows.last, updated);
      NormalGatewayChatSnapshot? reopened;
      f.session
          .chatFor('stored', title: 'Reopened')
          .subscribe((s) => reopened = s);
      expect(
        reopened!.historyPresentationRows,
        owner.snapshot.historyPresentationRows,
      );
      expect(f.calls, hasLength(1));
    },
  );

  test(
    'retained union and aliases never assemble confirmation evidence',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final donor = await f.open();
      final context = _committedRows();
      await f.settleReceipt(donor, context);
      expect(
        donor.observeHistory(context.sublist(0, context.length - 1)),
        isTrue,
      );
      expect(donor.observeHistory([context.last]), isTrue);
      expect(donor.snapshot.historyPresentationRows, [
        ..._previous,
        ...context,
      ]);
      expect(donor.snapshot.displayRows, isNotEmpty);
      expect(donor.snapshot.tools, hasLength(1));

      final canonical = f.session.chatFor(
        'canonical',
        storedSessionId: 'canonical',
        title: 'Canonical',
      );
      final reservation = canonical.reserve()!;
      donor.bindStoredSession('canonical');
      canonical.cancelPreparation(reservation);
      await pumpEventQueue();
      expect(canonical.snapshot.historyPresentationRows, [
        ..._previous,
        ...context,
      ]);
      expect(canonical.observeHistory([context.last]), isTrue);
      expect(canonical.snapshot.displayRows, isNotEmpty);
      expect(canonical.persistedTurnContextKey([context.last]), isNotNull);
      // The latest payload's explicit veto wins over a completed context copy.
      final veto = {...context.last, 'partial': true};
      expect(canonical.observeHistory([veto], confirmedRows: context), isTrue);
      expect(canonical.snapshot.displayRows, isNotEmpty);
      expect(canonical.snapshot.historyPresentationRows.last, veto);
      expect(
        canonical.observeHistory([context.last], confirmedRows: context),
        isTrue,
      );
      expect(canonical.snapshot.displayRows, isEmpty);
      expect(canonical.snapshot.tools, isEmpty);
      expect(
        donor.snapshot.historyPresentationRows,
        canonical.snapshot.historyPresentationRows,
      );
    },
  );

  test(
    'a newer alias presentation cannot borrow an older confirming read',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final donor = await f.open();
      final context = _committedRows();
      await f.settleReceipt(donor, context);
      final canonical = f.session.chatFor(
        'canonical',
        storedSessionId: 'canonical',
        title: 'Canonical',
      );
      expect(
        canonical.observeHistory([context.last], confirmedRows: context),
        isTrue,
      );
      final veto = {...context.last, 'partial': true};
      expect(donor.observeHistory([veto]), isTrue);
      final reservation = canonical.reserve()!;

      donor.bindStoredSession('canonical');
      canonical.cancelPreparation(reservation);
      await pumpEventQueue();

      expect(canonical.snapshot.historyRows, [context.last]);
      expect(canonical.snapshot.historyPresentationRows.last, veto);
      expect(canonical.snapshot.displayRows, isNotEmpty);
      expect(canonical.snapshot.tools, hasLength(1));
      expect(
        canonical.observeHistory([context.last], confirmedRows: context),
        isTrue,
      );
      expect(canonical.snapshot.displayRows, isEmpty);
      expect(canonical.snapshot.tools, isEmpty);
    },
  );

  test(
    'over-budget complete context cannot retire a half-presented turn',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final owner = await f.open();
      const budget =
          ChatHistoryWindow.pageSize * ChatHistoryWindow.initialPageBudget;
      final context = _committedRows(rawCount: budget + 1);
      await f.settleReceipt(owner, context);
      expect(
        NormalGatewayPersistedTurn.fromWire(
          _receipt(context),
        )!.isConfirmedBy(context),
        isTrue,
      );

      expect(owner.observeHistory(f.rows, confirmedRows: context), isTrue);

      expect(owner.snapshot.historyPresentationRows, hasLength(budget));
      expect(
        owner.snapshot.historyPresentationRows.any((r) => r['id'] == 3),
        isFalse,
      );
      expect(owner.snapshot.historyRows, f.rows);
      expect(owner.snapshot.displayRows, isNotEmpty);
      expect(owner.snapshot.timeline.runs, isNotEmpty);
      expect(owner.snapshot.tools, hasLength(1));
      expect(owner.persistedTurnContextKey(f.rows), isNotNull);
    },
  );

  test(
    'raw union is bounded and latest values replace IDs without text dedup',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      final owner = await f.open();
      const budget =
          ChatHistoryWindow.pageSize * ChatHistoryWindow.initialPageBudget;
      final context = [
        for (var id = 1; id <= budget; id++) _row(id, 'tool', 'Repeated'),
      ];
      expect(
        owner.observeHistory([context.last], confirmedRows: context),
        isTrue,
      );
      final next = _row(budget + 1, 'tool', 'Repeated');
      expect(owner.observeHistory([next]), isTrue);
      final correction = _row(
        budget - 10,
        'assistant',
        'Corrected',
        status: 'interrupted',
      );
      expect(owner.observeHistory([correction]), isTrue);
      final rows = owner.snapshot.historyPresentationRows;
      expect(rows, hasLength(budget));
      expect(rows.map((r) => r['id']), [
        for (var id = 2; id <= budget + 1; id++) id,
      ]);
      expect(rows.firstWhere((r) => r['id'] == budget - 10), correction);
      expect(
        rows.where((r) => r['content'] == 'Repeated'),
        hasLength(budget - 1),
      );
      expect(owner.snapshot.historyRows, [correction]);
      final legacy = <String, dynamic>{
        'id': 'legacy-address',
        'role': 'user',
        'content': 'Unaddressed',
      };
      expect(owner.observeHistory([legacy]), isTrue);
      expect(owner.snapshot.historyPresentationRows.last, legacy);
      expect(owner.observeHistory([]), isTrue);
      expect(owner.snapshot.historyRows, isEmpty);
      expect(
        owner.snapshot.historyPresentationRows.any(
          (r) => r['id'] == 'legacy-address',
        ),
        isFalse,
      );
    },
  );

  for (final latest in <List<Map<String, dynamic>>>[
    [],
    [_row(1, 'user', 'Latest only')],
    [
      {'role': 'assistant', 'content': 'Unknown floor'},
    ],
  ]) {
    test(
      'presentation context does not seed admission floor: $latest',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final owner = await f.open();
        final context = _committedRows();
        expect(
          owner.observeHistory(latest, confirmedRows: [...latest, ...context]),
          isTrue,
        );
        expect(
          owner.snapshot.historyPresentationRows.any((r) => r['id'] == 70),
          isTrue,
        );
        final call = await f.begin(owner);
        expect(
          owner.snapshot.rowFloor,
          latest.isEmpty
              ? 0
              : latest.first['id'] is int
              ? 1
              : null,
        );
        expect(owner.snapshot.historyRows, latest);
        call.ack();
      },
    );
  }

  for (final canonicalWins in [false, true]) {
    test(
      'verified alias transfers per-row freshness: canonicalWins=$canonicalWins',
      () async {
        final f = _Fixture();
        addTearDown(f.close);
        final source = await f.open();
        final canonical = f.session.chatFor(
          'canonical',
          storedSessionId: 'canonical',
          title: 'Canonical',
        );
        expect(
          source.observeHistory([_row(70, 'assistant', 'Old value')]),
          isTrue,
        );
        final fresh = _row(70, 'assistant', 'New value', status: 'interrupted');
        expect(
          canonical.observeHistory([fresh, _row(71, 'tool', 'Canonical only')]),
          isTrue,
        );
        final sourceLatest = [_row(80, 'tool', 'Source only')];
        expect(source.observeHistory(sourceLatest), isTrue);
        // Source owns the newest aggregate read, but not the newest row 70.
        final canonicalLatest = canonical.snapshot.historyRows;
        final reservation = canonicalWins ? canonical.reserve() : null;
        source.bindStoredSession('canonical');
        await pumpEventQueue();
        final winner = f.session.findChat('canonical')!;
        expect(winner, same(canonicalWins ? canonical : source));
        expect(winner.snapshot.historyPresentationRows.map((r) => r['id']), [
          1,
          2,
          70,
          71,
          80,
        ]);
        expect(
          winner.snapshot.historyPresentationRows.firstWhere(
            (r) => r['id'] == 70,
          ),
          fresh,
        );
        expect(
          winner.snapshot.historyRows,
          canonicalWins ? canonicalLatest : sourceLatest,
        );
        expect(
          source.snapshot.historyPresentationRows,
          canonical.snapshot.historyPresentationRows,
        );
        if (reservation != null) canonical.cancelPreparation(reservation);
        await f.close();
        expect(source.snapshot.historyPresentationRows, isEmpty);
        expect(canonical.snapshot.historyPresentationRows, isEmpty);
      },
    );
  }

  test(
    'snapshot context is immutable and scoped; close rejects a held read',
    () async {
      final f = _Fixture();
      final other = _Fixture(scope: 'other-scope');
      addTearDown(f.close);
      addTearDown(other.close);
      final owner = await f.open();
      final siblingScope = await other.open();
      final nested = <String, dynamic>{'name': 'terminal'};
      final calls = <Map<String, dynamic>>[
        {'function': nested},
      ];
      final row = <String, dynamic>{
        'id': 3,
        'role': 'assistant',
        'tool_calls': calls,
      };
      expect(owner.observeHistory([row]), isTrue);
      final snapshot = owner.snapshot;
      row['role'] = 'tool';
      nested['name'] = 'Changed externally';
      calls.clear();
      expect(snapshot.historyPresentationRows.last['role'], 'assistant');
      final frozenCalls =
          snapshot.historyPresentationRows.last['tool_calls'] as List;
      expect((frozenCalls.single['function'] as Map)['name'], 'terminal');
      expect(
        () => snapshot.historyPresentationRows.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => snapshot.historyPresentationRows.last['role'] = 'tool',
        throwsUnsupportedError,
      );
      expect(() => frozenCalls.clear(), throwsUnsupportedError);
      expect(
        () => (frozenCalls.single['function'] as Map)['name'] = 'Changed',
        throwsUnsupportedError,
      );
      expect(siblingScope.snapshot.historyPresentationRows, _previous);
      final held = owner.beginHistoryRead('stored');
      await f.close();
      expect(owner.snapshot.historyPresentationRows, isEmpty);
      expect(
        owner.observeHistory([_row(999, 'user', 'Late')], read: held),
        isFalse,
      );
      expect(owner.snapshot.historyPresentationRows, isEmpty);
      expect(snapshot.historyPresentationRows.last['id'], 3);
      expect(siblingScope.snapshot.historyPresentationRows, _previous);

      const legacy = NormalGatewayChatSnapshot(
        turnId: null,
        storedSessionId: null,
        phase: NormalGatewayTurnPhase.idle,
        wireEmitted: false,
        rowFloor: null,
        displayRows: [],
        historyRows: [],
        tools: [],
        subagents: [],
        pendingInput: [],
        inputUpdates: [],
        auxiliaryEvents: [],
        status: null,
        error: null,
        rejectedDraft: null,
        connectionState: DesktopConnectionState.disconnected,
      );
      expect(legacy.historyPresentationRows, isEmpty);
    },
  );
}

Map<String, dynamic> _row(
  int id,
  String role,
  String content, {
  String? status,
}) => {'id': id, 'role': role, 'content': content, 'status': ?status};

final _previous = [
  _row(1, 'user', 'Prior prompt'),
  _row(2, 'assistant', 'Prior answer', status: 'completed'),
];

List<Map<String, dynamic>> _committedRows({int rawCount = 68}) => [
  _row(3, 'user', 'Current prompt'),
  for (var id = 4; id < rawCount + 2; id++)
    {..._row(id, 'tool', 'Saved result $id'), 'tool_call_id': 'tool-$id'},
  _row(rawCount + 2, 'assistant', 'Saved final', status: 'completed'),
];

Map<String, dynamic> _receipt(List<Map<String, dynamic>> rows) => {
  'complete': true,
  'row_ids': [for (final row in rows) row['id']],
  'user_row_id': rows.first['id'],
  'final_assistant_row_id': rows.last['id'],
};

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue, reason: 'Owner transition did not settle');
}

class _Fixture {
  final String scope;
  late final NormalGatewayApplicationSession session;
  List<Map<String, dynamic>> rows = List.of(_previous);
  final calls = <_Call>[];
  final flights = <Future<void>>[];

  _Fixture({this.scope = 'history-presentation-owner'}) {
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: scope,
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture-only',
      ),
      scope: scope,
      history: (_) async => rows,
      resume: ({required localSessionId, required storedSessionId}) async =>
          const ResumedGatewaySession(
            runtimeSessionId: 'runtime',
            running: true,
          ),
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            final call = _Call(
              'wire-${calls.length}',
              (event) => session.receiveEvent(sessionId, event),
            );
            calls.add(call);
            onSent();
            return call.rpc.future;
          },
    );
  }

  Future<NormalGatewayChatOwner> open() async {
    await session.ready;
    final owner = session.chatFor(
      'local',
      storedSessionId: 'stored',
      title: 'Fixture',
    );
    expect(owner.observeHistory(rows), isTrue);
    return owner;
  }

  Future<_Call> begin(NormalGatewayChatOwner owner) async {
    final reservation = owner.reserve();
    expect(reservation, isNotNull);
    final before = calls.length;
    final flight = owner.submitPrepared(
      reservation: reservation!,
      text: 'Current prompt',
      localContent: 'Current prompt',
    );
    flights.add(flight);
    flight.ignore();
    await _until(() => calls.length > before);
    final call = calls.last;
    call.emit('message.start', {});
    return call;
  }

  Future<void> settleReceipt(
    NormalGatewayChatOwner owner,
    List<Map<String, dynamic>> context,
  ) async {
    final call = await begin(owner);
    rows = context.sublist(context.length - ChatHistoryWindow.pageSize);
    call.emit('message.delta', {'text': 'Received final'});
    call.emit('tool.start', {'tool_id': 'received-tool', 'name': 'terminal'});
    call.emit('tool.complete', {
      'tool_id': 'received-tool',
      'name': 'terminal',
      'result': 'Passed',
    });
    call.emit('message.complete', {
      'text': 'Received final',
      'persisted_turn': _receipt(context),
    });
    call.emit('turn.end', {'status': 'completed'});
    call.ack();
    await _until(() => !owner.snapshot.hasActiveTurn);
    await pumpEventQueue();
    expect(owner.snapshot.historyRows, rows);
    expect(owner.snapshot.displayRows, isNotEmpty);
  }

  Future<void> close() async {
    await session.close();
    for (final call in calls) {
      call.ack();
    }
    await Future.wait(flights);
  }
}

class _Call {
  final String turn;
  final StreamCallback onEvent;
  final rpc = Completer<void>();
  _Call(this.turn, this.onEvent);

  void emit(String type, Map<String, dynamic> data) =>
      onEvent(StreamEvent(type: type, turnId: turn, data: data));
  void ack() {
    if (!rpc.isCompleted) rpc.complete();
  }
}
