import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// flutter_test supplies the deterministic timer clock.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final stage in ['settled', 'remove']) {
    for (final failure in _Failure.values) {
      test(
        'retiring prewire $stage $failure retries after storage recovery',
        () async {
          final original = SharedPreferencesStorePlatform.instance;
          final platform = _ReceiptPlatform(await original.getAll())
            ..stage = stage
            ..failure = failure
            ..writeAheadGate = Completer<void>();
          SharedPreferencesStorePlatform.instance = platform;
          addTearDown(() => SharedPreferencesStorePlatform.instance = original);
          final f = _Owners();
          addTearDown(f.session.close);
          await f.session.ready;
          // This owner/store seam supplies a verified later alias while receipt
          // I/O is held. It does not claim stock create normally binds after WAL.
          final source = f.session.chatFor(
            'source',
            storedSessionId: 'prealias',
            title: 'Source',
          );
          source.observeHistory([_row(37)]);
          Object? rejected;
          final old = f
              .send(source)
              .then<void>((_) {}, onError: (Object e) => rejected = e);
          await platform.writeAheadEntered.future;
          final winner = f.session.chatFor(
            'stored',
            storedSessionId: 'stored',
            title: 'Winner',
          );
          final reservation = winner.reserve()!;
          final winningTurn = winner.turnId;
          source.bindStoredSession('stored');
          expect(f.session.chats, hasLength(1));
          expect(f.session.activeChatActivities, hasLength(1));
          expect(source.reserve(), isNull);
          platform.writeAheadGate!.complete();
          await old;
          await pumpEventQueue();
          await f.store.load('scope');
          expect(rejected, isA<StateError>());
          expect(platform.cleanupAttempts, greaterThan(0));
          final failedAttempts = platform.cleanupAttempts;
          platform.failure = null;
          f.session.setLifecycle(background: false);
          await pumpEventQueue();
          await f.store.load('scope');
          expect(platform.cleanupAttempts, greaterThan(failedAttempts));
          final disk = await platform.receipts();
          expect(disk.where((row) => row['local_id'] == 'source'), isEmpty);
          expect(winner.turnId, winningTurn);
          expect(winner.phase, NormalGatewayTurnPhase.preparing);
          expect(f.submissions, 0);
          winner.cancelPreparation(reservation);
          await f.session.close();
          await (await SharedPreferences.getInstance()).reload();
          final restarted = _Owners();
          addTearDown(restarted.session.close);
          await restarted.session.ready;
          expect(restarted.session.chats, isEmpty);
          expect(restarted.submissions, 0);
        },
      );
    }
  }

  test(
    'held retiring tombstone cannot clobber the admitted winner or its unknown receipt',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final platform = _ReceiptPlatform(await original.getAll())
        ..cleanupGate = Completer<void>();
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final source = f.session.chatFor(
        'source',
        storedSessionId: 'prealias',
        title: 'Source',
      );
      source.observeHistory([_row(37)]);
      final old = f.send(source);
      old.ignore();
      await f.submitEntered.future;
      final winner = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Winner',
      );
      winner.observeHistory([_row(99)]);
      final reservation = winner.reserve()!;
      final turn = winner.turnId;
      source.bindStoredSession('stored');
      await platform.cleanupEntered.future;
      final sending = f.send(winner, reservation: reservation, emit: true);
      sending.ignore();
      // The global store queue holds winner WAL behind the old tombstone.
      expect(f.submissions, 1);
      platform.cleanupGate!.complete();
      await _until(() => winner.wireEmitted);
      expect(winner.turnId, turn);
      expect(winner.snapshot.rowFloor, 99);
      expect(f.session.activeChatActivities, hasLength(1));
      // The losing callback retained before convergence cannot touch the winner.
      f.oldOnSent!();
      f.oldEvent!(StreamEvent(type: 'turn.end', data: {}, turnId: 'old'));
      f.oldRpc.completeError(StateError('old callback'));
      await expectLater(old, throwsStateError);
      expect(winner.phase, NormalGatewayTurnPhase.running);
      final markers = await f.store.load('scope');
      expect(markers, hasLength(1));
      expect(markers.single.turnId, turn);
      expect(markers.single.rowFloor, 99);
      await f.session.close();
      f.newRpc.complete();
      await sending;
      await (await SharedPreferences.getInstance()).reload();
      final restarted = _Owners();
      addTearDown(restarted.session.close);
      await restarted.session.ready;
      expect(restarted.session.chats, hasLength(1));
      expect(restarted.session.findChat('stored')!.turnId, turn);
      expect(
        restarted.session.findChat('stored')!.snapshot.hasActiveTurn,
        isTrue,
      );
      expect(restarted.submissions, 0);
    },
  );

  test(
    'permanent I/O plus crash retains uncertain WAL; duplicate restoration cannot overwrite a current receipt',
    () async {
      final store = NormalGatewayPendingStore();
      final emitted = _marker(
        'winner',
        'winner-turn',
        phase: 'emitted',
        floor: 99,
      );
      final uncertain = _marker(
        'retired-before-crash',
        'unknown-turn',
        floor: 37,
      );
      // Neither WAL can be discarded just because a process died before ACK.
      await store.put(emitted);
      await store.put(uncertain);
      await (await SharedPreferences.getInstance()).reload();
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      expect(f.session.chats, hasLength(1));
      final owner = f.session.findChat('stored')!;
      expect(owner.turnId, 'winner-turn');
      expect(
        owner.snapshot.rowFloor,
        isNull,
        reason: 'two uncertain boundaries are not a known admission floor',
      );
      expect(f.session.findChat('retired-before-crash'), same(owner));
      expect(await store.load('scope'), hasLength(2));
      expect(f.submissions, 0);
      f.resume.complete(
        const ResumedGatewaySession(
          runtimeSessionId: 'runtime',
          running: false,
          status: 'completed',
        ),
      );
      await _until(() => !owner.snapshot.hasActiveTurn);
      expect(owner.phase, NormalGatewayTurnPhase.reconciledUnknown);
      expect(await store.load('scope'), isEmpty);
      expect(f.submissions, 0);
    },
  );

  test(
    'physical failed write cannot hide a valid unknown-wire receipt in process cache',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final platform = _ReceiptPlatform(await original.getAll());
      SharedPreferencesStorePlatform.instance = platform;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      final store = NormalGatewayPendingStore();
      final unknown = _marker('source', 'unknown-turn');
      await store.put(unknown);
      platform.failure = _Failure.reject;
      await expectLater(
        store.put(unknown.withPhase('settled')),
        throwsStateError,
      );
      expect((await platform.receipts()).single['phase'], 'write_ahead');
      final loaded = await store.load('scope');
      expect(loaded, hasLength(1));
      expect(loaded.single.turnId, 'unknown-turn');
    },
  );

  test(
    'reentrant convergence and unsubscribe do not publish old snapshots after redirect',
    () async {
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final source = f.session.chatFor('source', title: 'Source');
      final winner = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Winner',
      );
      final reservation = winner.reserve()!;
      var converge = false;
      source.subscribe((_) {
        if (converge) source.bindStoredSession('stored');
      });
      final seen = <NormalGatewayChatSnapshot>[];
      final token = source.subscribe(seen.add);
      seen.clear();
      converge = true;
      // reserve publishes a source snapshot; first callback redirects it.
      source.reserve();
      source.unsubscribe(token);
      await pumpEventQueue();
      expect(
        seen,
        isEmpty,
        reason: 'unsubscribe also fences the in-progress fan-out',
      );
      expect(f.session.activeChatActivities, hasLength(1));
      expect(source.turnId, winner.turnId);
      winner.cancelPreparation(reservation);
    },
  );

  test(
    'held losing resume and known settled wire IDs stay fenced independently of current turn',
    () async {
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final canonical = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      canonical.observeHistory([_row(10)]);
      final earlier = f.send(canonical, emit: true);
      earlier.ignore();
      await _until(() => canonical.wireEmitted);
      f.session.receiveEvent(
        'stored',
        StreamEvent(type: 'message.start', data: {}, turnId: 'A'),
      );
      canonical.requestRecovery();
      await pumpEventQueue();
      f.session.receiveEvent(
        'stored',
        StreamEvent(type: 'turn.end', data: {}, turnId: 'A'),
      );
      await _until(() => !canonical.snapshot.hasActiveTurn);
      final source = f.session.chatFor('source', title: 'Source');
      source.bindStoredSession('stored');
      final next = f.send(source, emit: true);
      next.ignore();
      await _until(() => source.wireEmitted && f.submissions == 2);
      final turn = source.turnId;
      // A held old recovery resumes after redirect; even its error cannot settle B.
      f.resume.complete(
        const ResumedGatewaySession(
          runtimeSessionId: 'old-runtime',
          running: false,
          status: 'failed',
        ),
      );
      f.session.receiveEvent(
        'stored',
        StreamEvent(type: 'message.start', data: {}, turnId: 'A'),
      );
      f.session.receiveEvent(
        'stored',
        StreamEvent(type: 'turn.end', data: {}, turnId: 'A'),
      );
      await pumpEventQueue();
      expect(source.turnId, turn);
      expect(source.snapshot.hasActiveTurn, isTrue);
      expect(source.snapshot.wireEmitted, isTrue);
      expect(f.session.activeChatActivities, hasLength(1));
      await f.session.close();
      f.newRpc.complete();
      await next;
      // Earlier RPC was never a terminal receipt; release it after close.
      f.oldRpc.complete();
      await earlier;
      canonical.bindStoredSession('late-after-close');
      expect(source.storedSessionId, 'stored');
      expect(f.session.findChat('late-after-close'), isNull);
    },
  );

  test(
    'a newer observation, not the larger row ID, owns unused prewire history',
    () async {
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final canonical = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      canonical.observeHistory([_row(99)]);
      final source = f.session.chatFor('source', title: 'Source');
      source.observeHistory([_row(37)]);
      source.bindStoredSession('stored');
      final flight = f.send(source, emit: true);
      flight.ignore();
      await _until(() => source.wireEmitted);
      expect(source.snapshot.rowFloor, 37);
      expect(source.snapshot.historyRows.single['id'], 37);
      expect((await f.store.load('scope')).single.rowFloor, 37);
      await f.session.close();
      f.oldRpc.complete();
      await flight;
    },
  );

  test(
    'an existing write-ahead floor cannot be rebased by a later alias observation',
    () async {
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final source = f.session.chatFor(
        'source',
        storedSessionId: 'prealias',
        title: 'Source',
      );
      source.observeHistory([_row(37)]);
      final flight = f.send(source);
      flight.ignore();
      await f.submitEntered.future;
      final canonical = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      canonical.observeHistory([_row(99)]);
      source.bindStoredSession('stored');
      expect(source.snapshot.rowFloor, 37);
      expect((await f.store.load('scope')).single.rowFloor, 37);
      await f.session.close();
      f.oldRpc.complete();
      await flight;
    },
  );

  test(
    'independently emitted turns reject convergence without dropping either unknown receipt',
    () async {
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final source = f.session.chatFor(
        'source',
        storedSessionId: 'prealias',
        title: 'Source',
      );
      final canonical = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      final first = f.send(source, emit: true);
      first.ignore();
      await _until(() => source.wireEmitted);
      final second = f.send(canonical, emit: true);
      second.ignore();
      await _until(() => canonical.wireEmitted);
      expect(() => source.bindStoredSession('stored'), throwsStateError);
      expect(f.session.chats, hasLength(2));
      expect(await f.store.load('scope'), hasLength(2));
      expect(source.storedSessionId, 'prealias');
      await f.session.close();
      f.oldRpc.complete();
      f.newRpc.complete();
      await Future.wait([first, second]);
    },
  );

  test(
    'a retiring reservation cannot cancel its winning replacement',
    () async {
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final source = f.session.chatFor('source', title: 'Source');
      final old = source.reserve()!;
      final canonical = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      final current = canonical.reserve()!;
      source.bindStoredSession('stored');
      source.cancelPreparation(old);
      expect(canonical.phase, NormalGatewayTurnPhase.preparing);
      source.cancelPreparation(current);
      expect(canonical.phase, NormalGatewayTurnPhase.idle);
    },
  );

  test(
    'reentrant cancellation and close fence the remainder of a notification batch',
    () async {
      final f = _Owners();
      await f.session.ready;
      final source = f.session.chatFor('source', title: 'Source');
      Object? reservation;
      var cancel = false;
      source.subscribe((snap) {
        if (cancel && snap.phase == NormalGatewayTurnPhase.preparing) {
          source.cancelPreparation(reservation!);
        }
      });
      reservation = source.reserve()!;
      // A retained preparing reservation can be cancelled during a later bind's
      // notification without changing its generation.
      final seen = <NormalGatewayTurnPhase>[];
      source.subscribe((snap) => seen.add(snap.phase));
      seen.clear();
      cancel = true;
      source.bindStoredSession('stored');
      expect(seen, [NormalGatewayTurnPhase.idle]);
      var close = false;
      source.subscribe((_) {
        if (close) unawaited(f.session.close());
      });
      var afterClose = 0;
      source.subscribe((_) => afterClose++);
      final before = afterClose;
      close = true;
      cancel = false;
      source.reserve();
      expect(afterClose, before);
      await f.session.close();
    },
  );

  for (final latestCanonical in [false, true]) {
    test(
      'child observation chronology survives convergence, latest canonical=$latestCanonical',
      () async {
        final f = _Owners();
        addTearDown(f.session.close);
        await f.session.ready;
        final source = f.session.chatFor('source', title: 'Source');
        final canonical = f.session.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Canonical',
        );
        void child(String alias, String id, String goal) =>
            f.session.receiveEvent(
              alias,
              StreamEvent(
                type: 'subagent.progress',
                data: {
                  'subagent_id': 'agent',
                  'child_session_id': id,
                  'goal': goal,
                },
              ),
            );
        child(
          latestCanonical ? 'source' : 'stored',
          'child-root',
          'Original goal',
        );
        child(latestCanonical ? 'stored' : 'source', 'child-tip', 'Newer goal');
        source.bindStoredSession('stored');
        final task = source.snapshot.subagents.single;
        expect(task.childSessionId, 'child-root');
        expect(task.latestChildSessionId, 'child-tip');
        expect(task.goal, 'Newer goal');
        f.session.receiveEvent(
          'stored',
          StreamEvent(
            type: 'subagent.complete',
            data: {'subagent_id': 'agent', 'status': 'failed'},
          ),
        );
        source.observeHistory([_row(99)]);
        expect(canonical.snapshot.subagents.single.goal, 'Newer goal');
        expect(canonical.snapshot.subagents.single.failed, isTrue);
      },
    );
  }

  test(
    'converged child identity remains bounded without replaying evicted observations as new',
    () async {
      final f = _Owners();
      addTearDown(f.session.close);
      await f.session.ready;
      final source = f.session.chatFor('source', title: 'Source');
      final canonical = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Canonical',
      );
      for (var id = 0; id < 256; id++) {
        f.session.receiveEvent(
          id < 128 ? 'stored' : 'source',
          StreamEvent(
            type: 'subagent.progress',
            data: {
              'subagent_id': 'agent-$id',
              'child_session_id': 'child-$id',
              'goal': 'Same goal',
            },
          ),
        );
      }
      source.bindStoredSession('stored');
      expect(source.snapshot.subagents, hasLength(128));
      expect(
        source.snapshot.subagents.every(
          (task) => int.parse(task.id.split('-').last) >= 128,
        ),
        isTrue,
      );
      expect(canonical.snapshot.subagents, source.snapshot.subagents);
    },
  );

  test(
    'close invalidates retirement retry timers without erasing uncertain disk receipts',
    () async {
      final prefs = await SharedPreferences.getInstance();
      fakeAsync((clock) {
        final store = _FailRetirementStore(prefs);
        final f = _Owners(store: store);
        clock.flushMicrotasks();
        final source = f.session.chatFor(
          'source',
          storedSessionId: 'prealias',
          title: 'Source',
        );
        source.observeHistory([_row(37)]);
        f.send(source).ignore();
        clock.flushMicrotasks();
        final canonical = f.session.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Winner',
        );
        canonical.reserve();
        source.bindStoredSession('stored');
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isNotEmpty);
        final attempts = store.attempts;
        f.session.close();
        f.oldRpc.completeError(StateError('closed old submit'));
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 2));
        expect(clock.pendingTimers, isEmpty);
        expect(store.attempts, attempts);
        store.load('scope').then((rows) => expect(rows, hasLength(1)));
        clock.flushMicrotasks();
      });
    },
  );
}

enum _Failure { reject, throwBefore, lostAck, throwAfter }

class _ReceiptPlatform extends InMemorySharedPreferencesStore {
  _ReceiptPlatform(super.data) : super.withData();
  String stage = 'settled';
  _Failure? failure;
  Completer<void>? writeAheadGate;
  Completer<void>? cleanupGate;
  final writeAheadEntered = Completer<void>();
  final cleanupEntered = Completer<void>();
  int cleanupAttempts = 0;
  bool sawSource = false;
  Future<List<dynamic>> receipts() async {
    final raw =
        (await getAll())['flutter.${NormalGatewayPendingStore.preferenceKey}'];
    return raw == null ? [] : jsonDecode(raw as String) as List;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${NormalGatewayPendingStore.preferenceKey}') {
      final rows = jsonDecode(value as String) as List;
      final source = rows
          .where((row) => row['local_id'] == 'source')
          .firstOrNull;
      if (source != null && source['phase'] == 'write_ahead') {
        sawSource = true;
        if (!writeAheadEntered.isCompleted) writeAheadEntered.complete();
        await writeAheadGate?.future;
      }
      final cleanup =
          sawSource &&
          (stage == 'settled'
              ? source != null && source['phase'] == 'settled'
              : source == null);
      if (cleanup) {
        cleanupAttempts++;
        if (!cleanupEntered.isCompleted) cleanupEntered.complete();
        await cleanupGate?.future;
        switch (failure) {
          case _Failure.reject:
            return false;
          case _Failure.throwBefore:
            throw StateError('before physical receipt write');
          case _Failure.lostAck:
            await super.setValue(valueType, key, value);
            return false;
          case _Failure.throwAfter:
            await super.setValue(valueType, key, value);
            throw StateError('after physical receipt write');
          case null:
            break;
        }
      }
    }
    return super.setValue(valueType, key, value);
  }
}

class _FailRetirementStore extends NormalGatewayPendingStore {
  _FailRetirementStore(SharedPreferences prefs)
    : super(preferences: () async => prefs);
  int attempts = 0;
  @override
  Future<void> put(NormalGatewayPendingMarker marker) {
    if (marker.phase == 'settled') {
      attempts++;
      return Future.error(StateError('permanent I/O'));
    }
    return super.put(marker);
  }
}

class _Owners {
  final NormalGatewayPendingStore store;
  late final NormalGatewayApplicationSession session;
  final oldRpc = Completer<void>();
  final newRpc = Completer<void>();
  final resume = Completer<ResumedGatewaySession>();
  final submitEntered = Completer<void>();
  StreamCallback? oldEvent;
  void Function()? oldOnSent;
  int submissions = 0;
  bool _emit = false;
  _Owners({NormalGatewayPendingStore? store})
    : store = store ?? NormalGatewayPendingStore() {
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'alias-unit',
        label: 'Fixture',
        host: 'fixture.invalid',
        port: 8642,
        apiKey: 'fixture',
      ),
      scope: 'scope',
      pendingStore: this.store,
      history: (_) async => [_row(99)],
      resume: ({required localSessionId, required storedSessionId}) =>
          resume.future,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            submissions++;
            if (_emit) onSent();
            if (submissions == 1) {
              oldEvent = onEvent;
              oldOnSent = onSent;
              submitEntered.complete();
              return oldRpc.future;
            }
            return newRpc.future;
          },
    );
  }
  Future<void> send(
    NormalGatewayChatOwner owner, {
    Object? reservation,
    bool emit = false,
  }) {
    _emit = emit;
    return owner.submitPrepared(
      reservation: reservation ?? owner.reserve()!,
      text: 'Prompt',
      localContent: 'Prompt',
    );
  }
}

Map<String, dynamic> _row(int id) => {
  'id': id,
  'role': 'assistant',
  'content': 'Context $id',
};
NormalGatewayPendingMarker _marker(
  String local,
  String turn, {
  String phase = 'write_ahead',
  int floor = 37,
}) => NormalGatewayPendingMarker(
  scope: 'scope',
  localSessionId: local,
  storedSessionId: 'stored',
  turnId: turn,
  rowFloor: floor,
  phase: phase,
  createdAt: 1,
  updatedAt: 1,
);
Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Owner barrier timed out');
    await Future<void>.delayed(Duration.zero);
  }
}
