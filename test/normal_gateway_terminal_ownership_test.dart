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

  for (final terminal in [
    'turn.end',
    'turn.error',
    'error',
    'message.complete',
  ]) {
    for (final identified in [false, true]) {
      test(
        'A trailing $terminal identified=$identified cannot retire B',
        () async {
          final f = _Owner();
          addTearDown(f.session.close);
          await f.start();
          f.emit('message.start', turn: identified ? 'A' : null);
          f.rows = [_row(11, 'A final')];
          // Real stock order: message.complete, post-turn hooks, running=false.
          final stillRunning = f.recovered();
          f.emit(
            'message.complete',
            data: {'text': 'A final'},
            turn: identified ? 'A' : null,
          );
          f.rpc.complete();
          await f.flight;
          await stillRunning;
          expect(
            f.chat.reserve(),
            isNull,
            reason: 'message.complete is not lifecycle settlement',
          );
          expect(await f.store.load('ownership'), hasLength(1));
          f.running = false;
          final settled = _when(f.chat, (s) => !s.hasActiveTurn);
          f.chat.requestRecovery();
          await settled;
          expect(await f.store.load('ownership'), isEmpty);

          f.running = true;
          await f.start();
          expect(
            f.chat.snapshot.rowFloor,
            11,
            reason: 'B baseline includes recovered A',
          );
          final b = f.chat.turnId;
          // B has crossed onSent, but has no activity yet. A's identified
          // terminal must not bind B either. Its ID-less terminal is ambiguous.
          final checked = f.recovered();
          f.emit(
            terminal,
            data: terminal == 'turn.end'
                ? {'status': 'completed'}
                : {'status': 'failed', 'error': 'Old A failure'},
            turn: identified ? 'A' : null,
          );
          // WsClient's terminal wait may finish on that old event; the owner
          // must still rely on authoritative running/history, never that Future.
          f.rpc.complete();
          await f.flight;
          await checked;
          expect(f.chat.snapshot.hasActiveTurn, isTrue);
          expect(f.chat.snapshot.error, isNull);
          expect((await f.store.load('ownership')).single.turnId, b);
          expect(f.chat.reserve(), isNull);
          expect(f.submits, 2);

          f.rows = [_row(11, 'A final'), _row(13, 'B final')];
          f.running = false;
          final bSettled = _when(f.chat, (s) => !s.hasActiveTurn);
          f.emit('message.complete', data: {'text': 'B final'});
          await bSettled;
          expect(f.chat.phase, NormalGatewayTurnPhase.completed);
          expect(await f.store.load('ownership'), isEmpty);
        },
      );
    }
  }

  test(
    'terminal before submit ACK cannot consume old idle history/failure',
    () async {
      final f = _Owner();
      addTearDown(f.session.close);
      await f.start();
      final entered = Completer<void>();
      final resume = Completer<ResumedGatewaySession>();
      f.resume = () {
        if (!entered.isCompleted) entered.complete();
        return resume.future;
      };
      f.emit('turn.error', data: {'message': 'A late error'});
      await entered.future;
      resume.complete(
        const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: false,
          status: 'error',
          inflight: {'error': 'A retained error'},
        ),
      );
      // Join the current read by queueing an explicitly controlled next read.
      final next = Completer<void>();
      final running = Completer<ResumedGatewaySession>();
      f.resume = () {
        if (!next.isCompleted) next.complete();
        return running.future;
      };
      f.chat.requestRecovery();
      await next.future;
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      expect(await f.store.load('ownership'), hasLength(1));
      f.rpc.complete();
      await f.flight;
      final checked = f.recovered();
      running.complete(
        const ResumedGatewaySession(runtimeSessionId: 'runtime', running: true),
      );
      await checked;
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      expect(f.chat.snapshot.error, isNull);
    },
  );

  test(
    'correlated lifecycle terminal requires earlier nonterminal identity',
    () async {
      final f = _Owner();
      addTearDown(f.session.close);
      await f.start();
      final checked = f.recovered();
      f.emit('turn.error', data: {'message': 'unowned'}, turn: 'old');
      f.rpc.complete();
      await f.flight;
      await checked;
      expect(f.chat.snapshot.hasActiveTurn, isTrue);
      f.emit('message.start', turn: 'B');
      final settled = _when(f.chat, (s) => !s.hasActiveTurn);
      f.emit('turn.error', data: {'message': 'B failed'}, turn: 'B');
      await settled;
      expect(f.chat.phase, NormalGatewayTurnPhase.failed);
      expect(f.chat.snapshot.error, 'B failed');
      expect(await f.store.load('ownership'), isEmpty);
    },
  );

  test(
    'ID-less error-only gateway settles from retained resume failure',
    () async {
      final f = _Owner();
      addTearDown(f.session.close);
      await f.start();
      f.resume = () async => const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        inflight: {'status': 'error', 'error': 'Actual retained failure'},
      );
      final settled = _when(f.chat, (s) => !s.hasActiveTurn);
      f.emit('error', data: {'message': 'Uncorrelated wire text'});
      f.rpc.complete();
      await f.flight;
      await settled;
      expect(f.chat.snapshot.error, 'Actual retained failure');
      expect(await f.store.load('ownership'), isEmpty);
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

class _Owner {
  final store = NormalGatewayPendingStore();
  late final NormalGatewayApplicationSession session;
  late final NormalGatewayChatOwner chat;
  Completer<void> rpc = Completer<void>();
  late Future<void> flight;
  final sent = <Completer<void>>[];
  int submits = 0;
  int reads = 0;
  bool running = true;
  List<Map<String, dynamic>> rows = [_row(10, 'Before')];
  Future<ResumedGatewaySession> Function()? resume;

  _Owner() {
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'ownership',
        label: 'Fixture',
        host: 'fixture',
        port: 8642,
        apiKey: '',
      ),
      scope: 'ownership',
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
      resume: ({required localSessionId, required storedSessionId}) =>
          resume?.call() ??
          Future.value(
            ResumedGatewaySession(
              runtimeSessionId: 'runtime',
              running: running,
              status: running ? null : 'completed',
            ),
          ),
      history: (_) async {
        reads++;
        return rows;
      },
    );
    chat = session.chatFor(
      'local',
      storedSessionId: 'stored',
      title: 'Fixture',
    );
    chat.observeHistory(rows);
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

  Future<void> recovered() {
    final target = reads + 1;
    return _when(chat, (_) => reads >= target);
  }

  void emit(
    String type, {
    Map<String, dynamic> data = const {},
    String? turn,
  }) => session.receiveEvent(
    'local',
    StreamEvent(type: type, data: data, turnId: turn),
  );
}
