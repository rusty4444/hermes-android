import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final oldState in ['idle', 'running', 'unknown', 'error', 'exception']) {
    test(
      'SPEC immutable pre-wait boundary discards $oldState before history; unknown fresh state stays active',
      () async {
        final f = _Epoch();
        addTearDown(f.session.close);
        await f.start();
        final b = f.chat.turnId;
        f.emit('turn.error', {'message': 'Old A'});
        await f.resumeStarted[0].future;
        f.rpc.complete();
        await f.flight;
        if (oldState == 'exception') {
          f.resumes[0].completeError(StateError('Old read failed'));
        } else {
          f.resumes[0].complete(
            ResumedGatewaySession(
              runtimeSessionId: 'old',
              running: oldState == 'unknown' ? null : oldState == 'running',
              status: oldState == 'unknown' ? null : oldState,
              inflight: oldState == 'error'
                  ? {'status': 'error', 'error': 'Old A retained failure'}
                  : null,
            ),
          );
        }
        await f.resumeStarted[1].future;
        expect(
          f.resumeCount,
          2,
          reason: 'Queued post-wait observation must be an actual new read.',
        );
        expect(
          f.historyCount,
          0,
          reason: 'Discard every pre-wait result before history.',
        );
        expect(f.chat.snapshot.hasActiveTurn, isTrue);
        expect(f.chat.snapshot.error, isNull);
        expect(f.chat.snapshot.rowFloor, 10);
        expect((await f.store.load('spec-matrix')).single.turnId, b);
        // Unknown current server status must not settle even with a fresh final row.
        f.resumes[1].complete(
          const ResumedGatewaySession(runtimeSessionId: 'new'),
        );
        await f.historyStarted.future;
        final observed = _when(
          f.chat,
          (s) => s.historyRows.any((r) => r['id'] == 99),
        );
        f.historyReply.complete([
          _row(99, 'Fresh canonical but unknown lifecycle'),
        ]);
        await observed;
        expect(f.chat.snapshot.hasActiveTurn, isTrue);
        expect(f.chat.snapshot.rowFloor, 10);
        expect((await f.store.load('spec-matrix')).single.turnId, b);
        // A genuinely later inactive read remains sufficient with fresh history.
        final settled = _when(f.chat, (s) => !s.hasActiveTurn);
        f.chat.requestRecovery();
        await f.resumeStarted[2].future;
        f.resumes[2].complete(
          const ResumedGatewaySession(
            runtimeSessionId: 'new',
            running: false,
            status: 'completed',
          ),
        );
        await settled;
        expect(f.chat.phase, NormalGatewayTurnPhase.completed);
        expect(await f.store.load('spec-matrix'), isEmpty);
        expect(f.submits, 1);
        expect(f.resumeCount, 3);
      },
    );
  }

  test(
    'SPEC held A resume hands new generation B a new post-wait read',
    () async {
      final f = _Epoch();
      addTearDown(f.session.close);
      await f.start();
      f.emit('message.start', {}, turnId: 'A');
      f.rpc.complete();
      await f.flight;
      await f.resumeStarted[0].future;
      final a = f.chat.turnId;
      final settledA = _when(f.chat, (s) => !s.hasActiveTurn);
      f.emit('turn.end', {'status': 'completed'}, turnId: 'A');
      await settledA;
      f.chat.observeHistory([_row(10, 'Prior canonical')]);
      await f.start();
      final b = f.chat.turnId;
      expect(b, isNot(a));
      f.rpc.complete();
      await f.flight;
      // This retained failure belongs to A's old read, not B's admission epoch.
      f.resumes[0].complete(
        const ResumedGatewaySession(
          runtimeSessionId: 'A-old',
          running: false,
          inflight: {'status': 'error', 'error': 'A late failure'},
        ),
      );
      await f.resumeStarted[1].future;
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      expect(f.chat.turnId, b);
      expect(f.chat.snapshot.error, isNull);
      expect((await f.store.load('spec-matrix')).single.turnId, b);
      f.resumes[1].complete(
        const ResumedGatewaySession(runtimeSessionId: 'B-new', running: true),
      );
      await f.historyStarted.future;
      final checked = _when(
        f.chat,
        (s) => s.historyRows.any((r) => r['id'] == 99),
      );
      f.historyReply.complete([_row(99, 'B interim while running')]);
      await checked;
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      expect(f.chat.snapshot.error, isNull);
      expect(f.submits, 2);
      expect(f.resumeCount, 2);
    },
  );
}

Map<String, dynamic> _row(int id, String text) => {
  'id': id,
  'role': 'assistant',
  'content': text,
};

Future<void> _when(
  NormalGatewayChatOwner chat,
  bool Function(NormalGatewayChatSnapshot) predicate,
) {
  final done = Completer<void>();
  final token = chat.subscribe((s) {
    if (predicate(s) && !done.isCompleted) done.complete();
  });
  return done.future.whenComplete(() => chat.unsubscribe(token));
}

class _Epoch {
  final store = NormalGatewayPendingStore();
  final resumes = List.generate(4, (_) => Completer<ResumedGatewaySession>());
  final resumeStarted = List.generate(4, (_) => Completer<void>());
  final historyStarted = Completer<void>();
  final historyReply = Completer<List<Map<String, dynamic>>>();
  late final NormalGatewayApplicationSession session;
  late final NormalGatewayChatOwner chat;
  var rpc = Completer<void>();
  late Future<void> flight;
  var submits = 0;
  var resumeCount = 0;
  var historyCount = 0;
  final sent = <Completer<void>>[];

  _Epoch() {
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'spec-matrix',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture',
      ),
      scope: 'spec-matrix',
      pendingStore: store,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            submits++;
            onSent();
            sent.last.complete();
            return rpc.future;
          },
      resume: ({required localSessionId, required storedSessionId}) {
        final index = resumeCount++;
        resumeStarted[index].complete();
        return resumes[index].future;
      },
      history: (_) {
        historyCount++;
        if (!historyStarted.isCompleted) historyStarted.complete();
        return historyReply.future;
      },
    );
    chat = session.chatFor(
      'local',
      storedSessionId: 'stored',
      title: 'Fixture',
    );
    chat.observeHistory([_row(10, 'Prior canonical')]);
  }

  Future<void> start() async {
    await session.ready;
    rpc = Completer<void>();
    sent.add(Completer<void>());
    flight = chat.submitPrepared(
      reservation: chat.reserve()!,
      text: 'Prompt',
      localContent: 'Prompt',
    );
    flight.ignore();
    await sent.last.future;
  }

  void emit(String type, Map<String, dynamic> data, {String? turnId}) =>
      session.receiveEvent(
        'local',
        StreamEvent(type: type, data: data, turnId: turnId),
      );
}
