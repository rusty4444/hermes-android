// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_presentation_authority_test.dart
// Base 4a53e32 blob 98b486dbfdf396e5089ba6ecddb9eb03038bf5fb; SHA256 fccd1be4a2c01696446e2776c378d2f26aaa7e0fe029057c2b5dd2d365ceeed1.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/models/gateway_insight.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart' show send, until;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final laterAtSettlement in [false, true]) {
    test(
      'canonical suffix is complete and live, later=$laterAtSettlement',
      () async {
        final fixture = _OwnerFixture();
        addTearDown(fixture.close);
        await fixture.start();
        final receipt = (await fixture.session.pendingStore.load(
          'presentation',
        )).single;
        expect(receipt.rowFloor, 37);
        final receivedScope =
            fixture.current.snapshot.displayRows.last['_normal_projection_id'];
        fixture.finishCurrent();
        await until(() => !fixture.current.snapshot.hasActiveTurn);
        final settlementRead = await fixture.nextRead.future;
        settlementRead.complete(_canonical(later: laterAtSettlement));
        await until(() => fixture.current.snapshot.historyRows.length >= 5);
        expect(_presented(fixture.current), [
          'Old context',
          'Donor prompt',
          'Donor stored partial',
          'Current prompt',
          'Current canonical',
          if (laterAtSettlement) ...['Later prompt', 'Later answer'],
          'Donor prompt',
          'Donor received',
          'Current prompt',
          'Current received',
        ]);
        expect(
          fixture.current.snapshot.timeline.forScope(receivedScope),
          isNotEmpty,
        );
        fixture.current.observeHistory(_canonical(later: true));
        expect(_presented(fixture.current), [
          'Old context',
          'Donor prompt',
          'Donor stored partial',
          'Current prompt',
          'Current canonical',
          'Later prompt',
          'Later answer',
          'Donor prompt',
          'Donor received',
          'Current prompt',
          'Current received',
        ]);
        expect(fixture.current.snapshot.rowFloor, receipt.rowFloor);
        expect(fixture.current.snapshot.historyRows, _canonical(later: true));
        expect(fixture.current.snapshot.tools.single.toolId, 'donor-tool');
        expect(
          fixture.current.snapshot.timeline.runs.map((r) => r.text),
          contains('Donor reasoning'),
        );
        // A successful latest snapshot replaces its suffix, not an append-only cache.
        fixture.current.observeHistory(_canonical(later: false));
        expect(_presented(fixture.current), isNot(contains('Later answer')));
        fixture.current.observeHistory([_row(7, 'Compressed')]);
        expect(fixture.current.snapshot.historyRows, [_row(7, 'Compressed')]);
        expect(
          _presented(fixture.current),
          isNot(contains('Current canonical')),
        );
        fixture.current.observeHistory([]);
        expect(fixture.current.snapshot.historyRows, isEmpty);
        expect(_presented(fixture.current), contains('Donor received'));
      },
    );
  }

  for (final replacement in ['lower', 'empty', 'unidentified']) {
    test('new accepted $replacement fences held suffix hydration', () async {
      final fixture = _OwnerFixture();
      addTearDown(fixture.close);
      await fixture.start();
      fixture.finishCurrent();
      await until(() => !fixture.current.snapshot.hasActiveTurn);
      final held = await fixture.nextRead.future;
      final rows = switch (replacement) {
        'lower' => [_row(7, 'Compressed')],
        'empty' => <Map<String, dynamic>>[],
        _ => <Map<String, dynamic>>[
          {'role': 'assistant', 'content': 'Unidentified'},
        ],
      };
      fixture.current.observeHistory(rows);
      held.complete(_canonical(later: true));
      await pumpEventQueue();
      expect(fixture.current.snapshot.historyRows, rows);
      expect(_presented(fixture.current), contains('Current received'));
      expect(_presented(fixture.current), isNot(contains('Later answer')));
    });
  }

  test('failed owned read cannot replace a later live suffix', () async {
    final fixture = _OwnerFixture();
    addTearDown(fixture.close);
    await fixture.start();
    fixture.finishCurrent();
    await until(() => !fixture.current.snapshot.hasActiveTurn);
    final held = await fixture.nextRead.future;
    fixture.current.observeHistory(_canonical(later: false));
    fixture.current.observeHistory(_canonical(later: true));
    held.completeError(StateError('read unavailable'));
    await pumpEventQueue();
    expect(
      fixture.current.snapshot.historyRows.last['content'],
      'Later answer',
    );
    expect(
      fixture.current.snapshot.displayRows.last['content'],
      'Current received',
    );
    expect(fixture.current.snapshot.historyRows, _canonical(later: true));
  });

  test('unknown donor and admission never claim a canonical suffix', () async {
    final fixture = _OwnerFixture(unknown: true);
    addTearDown(fixture.close);
    await fixture.start();
    expect(fixture.current.snapshot.rowFloor, isNull);
    expect(
      (await fixture.session.pendingStore.load('presentation')).single.rowFloor,
      isNull,
    );
    fixture.finishCurrent();
    await until(() => !fixture.current.snapshot.hasActiveTurn);
    (await fixture.nextRead.future).complete(_canonical(later: true));
    await pumpEventQueue();
    fixture.current.observeHistory(_canonical(later: true));
    expect(
      _presented(fixture.current),
      containsAll(['Donor received', 'Current received']),
    );
    expect(fixture.current.snapshot.historyRows, _canonical(later: true));
    expect(_presented(fixture.current), contains('Current canonical'));
  });

  for (final (canonicalWins, expanded) in [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]) {
    test(
      'reasoning identity and pin before handoff, canonicalWins=$canonicalWins expanded=$expanded',
      () async {
        final fixture = _OwnerFixture();
        addTearDown(fixture.close);
        await fixture.session.ready;
        final source = fixture.session.chatFor('local', title: 'Source');
        final canonical = fixture.session.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Canonical',
        );
        final donor = canonicalWins ? source : canonical;
        final winner = canonicalWins ? canonical : source;
        donor.bindStoredSession(canonicalWins ? 'donor-stored' : 'stored');
        donor.observeHistory([_row(37, 'Old context')]);
        await fixture.sendAndFail(donor);
        final before = donor.snapshot.timeline.runs.firstWhere(
          (r) => r.kind == ChatTimelineKind.reasoning,
        );
        expect(before.id, isNot('timeline:0'));
        // MAIN81D: the same mounted-view token follows stable run identity.
        final pins =
            fixture.presentation
                .chatFor(donor.localSessionId)
                .openReasoningVisit()
              ..pin(before.id, expanded);
        winner.bindStoredSession(canonicalWins ? 'stored' : 'current-stored');
        await send(winner, 'Current prompt', reservation: winner.reserve());
        final currentScope =
            winner.snapshot.displayRows.last['_normal_projection_id'];
        source.bindStoredSession('stored');
        final after = winner.snapshot.timeline.runs.firstWhere(
          (r) => r.scope == before.scope,
        );
        expect(after.id, before.id);
        expect(pins[after.id], expanded);
        fixture.session.receiveEvent(
          winner.localSessionId,
          StreamEvent(
            type: 'reasoning.delta',
            data: {'text': 'Current reasoning'},
          ),
        );
        final current = winner.snapshot.timeline.forScope(currentScope).single;
        expect(current.id, isNot(before.id));
        expect(pins[current.id], isNull);
        pins.pin(current.id, !expanded);
        expect(pins[after.id], expanded);
        expect(
          winner.snapshot.timeline.runs.map((r) => r.id).toSet().length,
          winner.snapshot.timeline.runs.length,
        );
        expect(
          winner.snapshot.timeline.runs.map((r) => r.id),
          winner.snapshot.timeline.runs.map((r) => r.id),
        );
      },
    );
  }

  test('reasoning projection identity survives append scope reassignment', () {
    final original = const ChatTimeline().reasoning(
      'continuation',
      const GatewayReasoningUpdate(
        text: 'Reasoning',
        mode: GatewayReasoningEventMode.append,
        verbose: false,
      ),
    );

    // Raw reducer IDs remain transport-local; projection must not mutate them.
    expect(original.runs.single.id, 'timeline:0');
    final before = original.precededBy([]).runs.single.id;
    final moved = original.reassignScope('continuation', 'preview');
    expect(moved.runs.single.id, original.runs.single.id);
    expect(moved.precededBy([]).runs.single.id, before);
  });
}

List<String> _presented(NormalGatewayChatOwner owner) {
  final snapshot = owner.snapshot;
  return [
    ...snapshot.historyRows,
    ...snapshot.displayRows,
  ].map((row) => row['content'] as String).toList();
}

Map<String, dynamic> _row(
  int id,
  String content, {
  String role = 'assistant',
}) => {'id': id, 'role': role, 'content': content};
List<Map<String, dynamic>> _canonical({required bool later}) => [
  _row(37, 'Old context'),
  _row(98, 'Donor prompt', role: 'user'),
  _row(99, 'Donor stored partial'),
  _row(100, 'Current prompt', role: 'user'),
  _row(101, 'Current canonical'),
  if (later) ...[
    _row(102, 'Later prompt', role: 'user'),
    _row(103, 'Later answer'),
  ],
];

class _OwnerFixture {
  _OwnerFixture({this.unknown = false}) {
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'presentation',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture',
      ),
      scope: 'presentation',
      presentation: presentation,
      history: (_) {
        if (unknown && !holdReads) {
          return Future.error(StateError('unknown history'));
        }
        if (!holdReads) return Future.value([_row(37, 'Old context')]);
        final read = Completer<List<Map<String, dynamic>>>();
        reads.add(read);
        if (!nextRead.isCompleted) nextRead.complete(read);
        return read.future;
      },
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
          }) async => onSent(),
    );
  }
  final bool unknown;
  final presentation = ChatPresentationRegistry('presentation');
  late final NormalGatewayApplicationSession session;
  late NormalGatewayChatOwner current;
  bool holdReads = false;
  final reads = <Completer<List<Map<String, dynamic>>>>[];
  final nextRead = Completer<Completer<List<Map<String, dynamic>>>>();

  Future<void> start() async {
    await session.ready;
    final donor = session.chatFor(
      'stored',
      storedSessionId: 'stored',
      title: 'Donor',
    );
    if (!unknown) donor.observeHistory([_row(37, 'Old context')]);
    await sendAndFail(donor);
    current = session.chatFor('local', title: 'Current');
    final reservation = current.reserve()!;
    current.bindStoredSession('stored');
    // Owner-seam schedule; the independent nine retain actual held-create I/O.
    await send(current, 'Current prompt', reservation: reservation);
  }

  Future<void> sendAndFail(NormalGatewayChatOwner owner) async {
    await send(owner, 'Donor prompt');
    session.receiveEvent(
      owner.localSessionId,
      StreamEvent(type: 'message.start', turnId: 'donor', data: {}),
    );
    session.receiveEvent(
      owner.localSessionId,
      StreamEvent(type: 'reasoning.delta', data: {'text': 'Donor reasoning'}),
    );
    session.receiveEvent(
      owner.localSessionId,
      StreamEvent(
        type: 'tool.start',
        data: {'tool': 'read_file', 'tool_id': 'donor-tool'},
      ),
    );
    session.receiveEvent(
      owner.localSessionId,
      StreamEvent(type: 'message.delta', data: {'text': 'Donor received'}),
    );
    session.receiveEvent(
      owner.localSessionId,
      StreamEvent(
        type: 'turn.error',
        turnId: 'donor',
        data: {'message': 'failed'},
      ),
    );
    await until(() => !owner.snapshot.hasActiveTurn);
    await pumpEventQueue();
  }

  Future<void> close() async {
    await session.close();
    presentation.close();
    for (final read in reads) {
      if (!read.isCompleted) read.complete([]);
    }
  }

  void finishCurrent() {
    holdReads = true;
    session.receiveEvent(
      current.localSessionId,
      StreamEvent(type: 'message.start', turnId: 'current', data: {}),
    );
    session.receiveEvent(
      current.localSessionId,
      StreamEvent(type: 'message.delta', data: {'text': 'Current received'}),
    );
    session.receiveEvent(
      current.localSessionId,
      StreamEvent(type: 'turn.end', turnId: 'current', data: {}),
    );
  }
}
