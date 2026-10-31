import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/operational_activity_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'late owner coalescence preserves canonical Activity root without replay',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      final turn = f.owner.turnId;
      final canonical = f.session.chatFor(
        'current-tip',
        storedSessionId: 'current-tip',
        lineageRootId: 'root',
        title: 'Canonical',
      );
      final winner = f.session.chatFor(
        'local',
        storedSessionId: 'current-tip',
        title: 'Canonical',
      );
      expect(winner, same(f.owner));
      expect(f.session.findChat('current-tip'), same(winner));
      expect(canonical.turnId, turn);
      expect(canonical.snapshot.hasActiveTurn, isTrue);
      f.emit('message.delta', {'text': 'received-once'});
      final record = (await f.records()).single;
      expect(record.turnId, turn);
      expect(record.storedSessionId, 'current-tip');
      expect(record.lineageRootId, 'root');
      expect(record.state, OperationalActivityState.running);
      expect(f.submissions, 1);
      final completed = _phase(winner, NormalGatewayTurnPhase.completed);
      f.emit('turn.end', {'status': 'completed'});
      await completed;
      await f.close();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final restored = (await OperationalActivityStore().load('scope')).single;
      expect(restored.lineageRootId, 'root');
      expect(restored.turnId, turn);
      expect(restored.state, OperationalActivityState.completed);
      expect(f.submissions, 1);
    },
  );

  test(
    'opening and cancelled preparation never create Activity work',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.ready();
      expect(await f.records(), isEmpty);
      final reservation = f.owner.reserve()!;
      expect(await f.records(), isEmpty);
      f.owner.cancelPreparation(reservation);
      expect(await f.records(), isEmpty);
      expect(f.activity.writes, isEmpty);
    },
  );

  test(
    'actual turn persists compression root before any Activity read',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.ready();
      f.owner = f.session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'private-title',
        lineageRootId: 'root',
      );
      f.begin();
      await f.sent.future;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final persisted =
          jsonDecode(prefs.getString(OperationalActivityStore.preferenceKey)!)
              as List;
      expect((persisted.single as Map)['lineageRootId'], 'root');
      expect((persisted.single as Map).keys.toSet(), {
        'scope',
        'localSessionId',
        'storedSessionId',
        'lineageRootId',
        'turnId',
        'state',
        'updatedAtEpochMs',
      });
      final reopened = (await OperationalActivityStore().load('scope')).single;
      expect(reopened.lineageRootId, 'root');
      expect(reopened.storedSessionId, 'stored');
      expect(reopened.state, OperationalActivityState.running);
    },
  );

  test('submitted is recorded before wire emission', () async {
    final pending = _HeldPendingStore(heldPhase: 'write_ahead');
    final f = _Fixture(pending: pending);
    addTearDown(f.close);
    await f.ready();
    f.begin();
    await pending.entered.future;
    expect(
      (await f.records()).single.state,
      OperationalActivityState.submitted,
    );
    expect(f.submissions, 0);
    pending.release.complete();
    await f.sent.future;
    expect((await f.records()).single.state, OperationalActivityState.running);
    expect(f.submissions, 1);
  });

  test(
    'failed preparation has nullable stored identity without prompt metadata',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.ready(bind: false);
      final failed = _phase(f.owner, NormalGatewayTurnPhase.failed);
      f.begin(); // No client/binding: a definite pre-wire failure.
      await failed;
      final record = (await f.records()).single;
      expect(record.storedSessionId, isNull);
      expect(record.state, OperationalActivityState.failed);
      expect(f.submissions, 0);
      await expectLater(f.flight, throwsA(anything));
      await _assertPrivateMetadataAbsent();
    },
  );

  test(
    'needsInput follows exact pending requests, clears and reconnects honestly',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      for (final type in [
        'approval.request',
        'secret.request',
        'sudo.request',
        'clarify.request',
      ]) {
        f.emit(type, {'request_id': type, 'prompt': 'private-request'});
      }
      expect(
        (await f.records()).single.state,
        OperationalActivityState.needsInput,
      );
      f.emit('message.delta', {'text': 'private-reply'});
      expect(
        (await f.records()).single.state,
        OperationalActivityState.needsInput,
      );
      f.session.forgetAnsweredInput('approval.request');
      f.session.forgetAnsweredInput('secret.request');
      f.session.forgetAnsweredInput('sudo.request');
      f.emit('clarify.remaining', {
        'request_id': 'clarify.request',
        'remaining': [],
      });
      expect(
        (await f.records()).single.state,
        OperationalActivityState.running,
      );
      f.emit('secret.request', {
        'request_id': 'late-secret',
        'prompt': 'private-request',
      });
      expect(
        (await f.records()).single.state,
        OperationalActivityState.needsInput,
      );
      f.session.connectionChanged(DesktopConnectionState.disconnected);
      expect(f.owner.snapshot.pendingInput, isEmpty);
      expect(
        (await f.records()).single.state,
        OperationalActivityState.reconciling,
      );
      f.session.connectionChanged(DesktopConnectionState.connected);
      f.emit('message.delta', {'text': 'private-reply'});
      expect(
        (await f.records()).single.state,
        OperationalActivityState.running,
      );
      await _assertPrivateMetadataAbsent();
    },
  );

  test(
    'terminal Activity waits for settled owner, not a terminal hint',
    () async {
      final pending = _HeldPendingStore(heldPhase: 'settled');
      final f = _Fixture(pending: pending);
      addTearDown(f.close);
      await f.start();
      f.emit('message.complete', {'text': 'private-reply'});
      expect(pending.entered.isCompleted, isFalse);
      expect(f.owner.snapshot.hasActiveTurn, isTrue);
      f.emit('turn.end', {'status': 'completed'});
      await pending.entered.future;
      expect(f.owner.snapshot.hasActiveTurn, isTrue);
      expect(
        (await f.records()).single.state,
        OperationalActivityState.running,
      );
      final settled = _phase(f.owner, NormalGatewayTurnPhase.completed);
      pending.release.complete();
      await settled;
      expect(
        (await f.records()).single.state,
        OperationalActivityState.completed,
      );
      expect(await f.pending.load('scope'), isEmpty);
      await _assertPrivateMetadataAbsent();
    },
  );

  test(
    'completed and failed turns remain separate across new turn and restart',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      final a = f.owner.turnId!;
      final completed = _phase(f.owner, NormalGatewayTurnPhase.completed);
      f.emit('turn.end', {'status': 'completed'});
      await completed;
      await f.releaseRpc();
      final afterA = (await f.records()).single;
      final cancelled = f.owner.reserve()!;
      expect(f.owner.turnId, isNot(a));
      expect((await f.records()).single.toJson(), afterA.toJson());
      f.owner.cancelPreparation(cancelled);
      f.resetRpc();
      f.begin();
      await f.sent.future;
      final b = f.owner.turnId!;
      final failed = _phase(f.owner, NormalGatewayTurnPhase.failed);
      f.emit('turn.error', {'error': 'private-error'});
      await failed;
      final rows = await f.records();
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((row) => row.turnId == a).state,
        OperationalActivityState.completed,
      );
      expect(
        rows.singleWhere((row) => row.turnId == b).state,
        OperationalActivityState.failed,
      );
      expect(rows.every((row) => row.localSessionId == 'local'), isTrue);
      await f.close();
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(OperationalActivityStore.preferenceKey)!;
      SharedPreferences.setMockInitialValues({
        OperationalActivityStore.preferenceKey: saved,
      });
      final restored = await OperationalActivityStore().load('scope');
      expect(
        restored.map((row) => row.toJson()),
        rows.map((row) => row.toJson()),
      );
      await _assertPrivateMetadataAbsent();
    },
  );

  test('idle reconciliation is unknown, never completed or failed', () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.start();
    f.session.connectionChanged(DesktopConnectionState.disconnected);
    expect(
      (await f.records()).single.state,
      OperationalActivityState.reconciling,
    );
    f.resumeResult = const ResumedGatewaySession(
      runtimeSessionId: 'runtime',
      running: false,
      status: 'idle',
    );
    final unknown = _phase(f.owner, NormalGatewayTurnPhase.reconciledUnknown);
    // A pre-ACK idle observation is not authority; observe after submission wait.
    await f.releaseRpc();
    f.session.setLifecycle(background: false);
    await unknown;
    expect((await f.records()).single.state, OperationalActivityState.unknown);
    expect(await f.pending.load('scope'), isEmpty);
    expect(f.submissions, 1);
  });

  test(
    'pending restart records reconciling at receipt time, not restart time',
    () async {
      final pending = NormalGatewayPendingStore();
      const marker = NormalGatewayPendingMarker(
        scope: 'scope',
        localSessionId: 'original-local',
        storedSessionId: 'stored',
        turnId: 'restored-turn',
        rowFloor: null,
        phase: 'emitted',
        createdAt: 100,
        updatedAt: 200,
      );
      await pending.put(marker);
      final activity = _CountingActivityStore();
      await activity.put(
        const OperationalActivityRecord(
          scope: 'scope',
          localSessionId: 'original-local',
          storedSessionId: 'stored',
          turnId: 'restored-turn',
          state: OperationalActivityState.needsInput,
          updatedAtEpochMs: 200,
        ),
      );
      final f = _Fixture(activity: activity, pending: pending);
      addTearDown(f.close);
      // Route may open via canonical identity while restoration is suspended.
      final canonical = f.session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'private-title',
      );
      await f.session.ready;
      expect(f.session.findChat('original-local'), same(canonical));
      final row = (await f.records()).single;
      expect(row.state, OperationalActivityState.reconciling);
      expect(row.updatedAtEpochMs, marker.updatedAt);
      expect(row.localSessionId, marker.localSessionId);
      expect(row.turnId, marker.turnId);
      expect(f.submissions, 0);
      final resumed = _phase(canonical, NormalGatewayTurnPhase.running);
      f.session.setLifecycle(background: false);
      await resumed;
      expect(
        (await f.records()).single.state,
        OperationalActivityState.running,
      );
      expect(f.submissions, 0);
    },
  );

  test('stream tokens and tool progress do not write per event', () async {
    final f = _Fixture();
    addTearDown(f.close);
    await f.start();
    final before = (await f.records()).single;
    final writes = f.activity.writes.length;
    for (var i = 0; i < 100; i++) {
      f.emit('message.delta', {'text': 'private-reply'});
      f.emit('reasoning.delta', {'text': 'private-reasoning'});
      f.emit('tool.progress', {
        'tool': 'terminal',
        'tool_id': 'tool',
        'arguments': 'private-tool-arguments',
      });
    }
    final after = (await f.records()).single;
    expect(after.toJson(), before.toJson());
    expect(f.activity.writes, hasLength(writes));
    expect(f.owner.snapshot.displayRows.last['content'], isNotEmpty);
    expect(f.owner.snapshot.timeline.runs, isNotEmpty);
    await _assertPrivateMetadataAbsent();
  });

  test(
    'meaningful progress heartbeats are bounded and passive replay is not activity',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      final first = (await f.records()).single;
      final initialWrites = f.activity.writes.length;
      f.activityNow += NormalGatewayApplicationSession
          .activityHeartbeatInterval
          .inMilliseconds;
      // A passive subscription or binding must not keep an old running receipt
      // apparently fresh. Only real progress or confirmed running recovery can.
      f.owner.subscribe((_) {});
      f.session.connectionChanged(DesktopConnectionState.connected);
      expect((await f.records()).single.toJson(), first.toJson());
      f.emit('message.delta', {'text': 'private-reply'});
      final heartbeat = (await f.records()).single;
      expect(heartbeat.updatedAtEpochMs, f.activityNow);
      expect(heartbeat.state, first.state);
      expect(f.activity.writes, hasLength(initialWrites + 1));
      for (var i = 0; i < 100; i++) {
        f.emit('message.delta', {'text': 'private-reply'});
      }
      expect((await f.records()).single.toJson(), heartbeat.toJson());
      expect(f.activity.writes, hasLength(initialWrites + 1));
    },
  );

  test(
    'late recovery from an earlier turn cannot overwrite newer work',
    () async {
      final f = _Fixture();
      addTearDown(f.close);
      await f.start();
      final a = f.owner.turnId!;
      f.resumeResult = const ResumedGatewaySession(
        runtimeSessionId: 'runtime',
        running: false,
        status: 'idle',
      );
      f.historyGate = Completer<List<Map<String, dynamic>>>();
      await f.releaseRpc();
      f.session.setLifecycle(background: false);
      await f.historyEntered.future;
      final completed = _phase(f.owner, NormalGatewayTurnPhase.completed);
      f.emit('turn.end', {'status': 'completed'});
      await completed;
      await f.releaseRpc();
      f.resetRpc();
      f.begin();
      await f.sent.future;
      final b = f.owner.turnId!;
      // Complete A's idle read only after B has emitted. B must not become
      // unknown, nor may A's old read change either turn's durable outcome.
      f.session.setLifecycle(background: true, backgroundWorkEnabled: false);
      f.historyGate!.complete([]);
      await f.historyDelivered.future;
      final rows = await f.records();
      expect(f.owner.turnId, b);
      expect(f.owner.phase, NormalGatewayTurnPhase.running);
      expect(
        rows.singleWhere((row) => row.turnId == a).state,
        OperationalActivityState.completed,
      );
      expect(
        rows.singleWhere((row) => row.turnId == b).state,
        OperationalActivityState.running,
      );
      expect(f.submissions, 2);
    },
  );

  test(
    'close fences events immediately and joins accepted metadata writes',
    () async {
      final prefsGate = Completer<SharedPreferences>();
      final store = _CountingActivityStore(preferences: () => prefsGate.future);
      final f = _Fixture(activity: store);
      addTearDown(f.close);
      await f.start();
      f.emit('message.delta', {'text': 'private-reply'});
      expect(f.owner.snapshot.displayRows.last['content'], 'private-reply');
      var closed = false;
      final closing = f.session.close().then((_) => closed = true);
      await Future<void>.value();
      expect(closed, isFalse);
      f.emit('turn.error', {'error': 'private-error'});
      expect(store.writes.map((row) => row.state), [
        OperationalActivityState.submitted,
        OperationalActivityState.running,
      ]);
      prefsGate.complete(await SharedPreferences.getInstance());
      await closing;
      expect(
        (await OperationalActivityStore().load('scope')).single.state,
        OperationalActivityState.running,
      );
    },
  );

  test(
    'metadata write failure never changes turn or recovery semantics',
    () async {
      final f = _Fixture(activity: _CountingActivityStore()..reject = true);
      addTearDown(f.close);
      await f.start();
      expect(f.owner.phase, NormalGatewayTurnPhase.running);
      expect((await f.pending.load('scope')).single.phase, 'emitted');
      expect(await f.records(), isEmpty);
      f.activity.reject = false;
      f.emit('message.delta', {'text': 'private-reply'});
      expect(
        (await f.records()).single.state,
        OperationalActivityState.running,
      );
      final completed = _phase(f.owner, NormalGatewayTurnPhase.completed);
      f.emit('turn.end', {'status': 'completed'});
      await completed;
      expect(
        (await f.records()).single.state,
        OperationalActivityState.completed,
      );
      expect(await f.pending.load('scope'), isEmpty);
    },
  );

  test(
    'app listeners reading immediately join the just-queued state',
    () async {
      final activity = _CountingActivityStore();
      final controller = GatewayTurnApplicationController(
        activityStore: activity,
      );
      final sent = Completer<void>();
      final rpc = Completer<void>();
      final session = controller.normalSessionFor(
        _connection,
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              sent.complete();
              return rpc.future;
            },
      );
      session.setLifecycle(background: true, backgroundWorkEnabled: false);
      await session.ready;
      final owner = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'private-title',
      );
      final reads = <Future<List<OperationalActivityRecord>>>[];
      controller.addTurnActivityListener(
        () => reads.add(controller.readActivityRecords(_connection)),
      );
      final flight = owner.submitPrepared(
        reservation: owner.reserve()!,
        text: 'private-prompt',
        localContent: 'private-prompt',
      );
      await sent.future;
      final snapshots = await Future.wait(reads);
      expect(
        snapshots.any((rows) => rows.isEmpty),
        isTrue,
      ); // Preparing is not work.
      expect(
        snapshots.any(
          (rows) =>
              rows.isNotEmpty &&
              rows.single.state == OperationalActivityState.submitted,
        ),
        isTrue,
      );
      expect(snapshots.last.single.state, OperationalActivityState.running);
      await controller.close();
      rpc.complete();
      await flight;
      await controller.readActivityRecords(
        _connection,
      ); // Drain accepted metadata.
    },
  );

  test(
    'controller scope read survives restart without creating transports',
    () async {
      var recoveryCreations = 0;
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) {
          recoveryCreations++;
          throw StateError('Activity reads must not construct a gateway.');
        },
      );
      final sent = Completer<void>();
      final rpc = Completer<void>();
      final session = controller.normalSessionFor(
        _connection,
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              sent.complete();
              return rpc.future;
            },
      );
      session.setLifecycle(background: true, backgroundWorkEnabled: false);
      await session.ready;
      final owner = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'private-title',
      );
      final flight = owner.submitPrepared(
        reservation: owner.reserve()!,
        text: 'private-prompt',
        localContent: 'private-prompt',
      );
      await sent.future;
      final expected = (await controller.readActivityRecords(
        _connection,
      )).single;
      expect(expected.scope, session.scope);
      expect(expected.scope, matches(RegExp(r'^[0-9a-f]{64}$')));
      await controller.close();
      rpc.complete();
      await flight;
      final replacement = GatewayTurnApplicationController(
        sessionFactory: (_) {
          recoveryCreations++;
          throw StateError('Activity reads must not construct a gateway.');
        },
      );
      expect(
        (await replacement.readActivityRecords(_connection)).single.toJson(),
        expected.toJson(),
      );
      for (final changed in [
        _connection.copyWith(apiKey: 'rotated-key'),
        _connection.copyWith(dashboardPassword: 'rotated-password'),
        _connection.copyWith(host: 'other.fixture'),
        _connection.copyWith(port: 9999),
        _connection.copyWith(desktopGatewayUrl: 'ws://other.fixture/ws'),
        _connection.copyWith(gatewayProfile: 'other-profile'),
      ]) {
        expect(changed.id, _connection.id);
        expect(await replacement.readActivityRecords(changed), isEmpty);
      }
      expect(recoveryCreations, 0);
      expect(replacement.retainedSessionCount, 0);
      expect(replacement.activeChatActivities, isEmpty);
      expect(replacement.hasActiveTurn, isFalse);
      await replacement.close();
      await _assertPrivateMetadataAbsent();
    },
  );
}

final _connection = SavedConnection(
  id: 'activity-fixture',
  label: 'private-label',
  host: 'activity.fixture',
  port: 8642,
  apiKey: 'private-api-key',
  dashboardPassword: 'private-dashboard-password',
);

Future<void> _phase(
  NormalGatewayChatOwner owner,
  NormalGatewayTurnPhase phase,
) async {
  final reached = Completer<void>();
  final token = owner.subscribe((snapshot) {
    if (snapshot.phase == phase && !reached.isCompleted) reached.complete();
  });
  await reached.future;
  owner.unsubscribe(token);
}

Future<void> _assertPrivateMetadataAbsent() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getKeys().map(prefs.get).join('\n');
  for (final secret in [
    'private-title',
    'private-label',
    'private-prompt',
    'private-reply',
    'private-error',
    'private-reasoning',
    'private-tool-arguments',
    'private-request',
    'private-api-key',
    'private-dashboard-password',
  ]) {
    expect(saved, isNot(contains(secret)));
  }
  final encoded = prefs.getString(OperationalActivityStore.preferenceKey);
  if (encoded != null) {
    for (final row
        in (jsonDecode(encoded) as List).cast<Map<String, dynamic>>()) {
      expect(row.keys.toSet(), {
        'scope',
        'localSessionId',
        'storedSessionId',
        'turnId',
        'state',
        'updatedAtEpochMs',
      });
    }
  }
}

class _Fixture {
  final _CountingActivityStore activity;
  final NormalGatewayPendingStore pending;
  late final NormalGatewayApplicationSession session;
  late NormalGatewayChatOwner owner;
  Completer<void> rpc = Completer<void>();
  Completer<void> sent = Completer<void>();
  Future<void>? flight;
  int submissions = 0;
  int activityNow = 2000000000000;
  Completer<List<Map<String, dynamic>>>? historyGate;
  final historyEntered = Completer<void>();
  final historyDelivered = Completer<void>();
  ResumedGatewaySession resumeResult = const ResumedGatewaySession(
    runtimeSessionId: 'runtime',
    running: true,
  );

  _Fixture({
    _CountingActivityStore? activity,
    NormalGatewayPendingStore? pending,
  }) : activity = activity ?? _CountingActivityStore(),
       pending = pending ?? NormalGatewayPendingStore() {
    session = NormalGatewayApplicationSession(
      connection: _connection,
      scope: 'scope',
      activityStore: this.activity,
      activityNowEpochMs: () => activityNow,
      pendingStore: this.pending,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            submissions++;
            onSent();
            // The stock contract requires identified activity before a terminal
            // may settle this turn. Empty prose is not a fabricated reply.
            session.receiveEvent(
              'local',
              StreamEvent(
                type: 'message.delta',
                turnId: 'wire-${owner.turnId}',
                data: {'text': ''},
              ),
            );
            sent.complete();
            return rpc.future;
          },
      resume: ({required localSessionId, required storedSessionId}) async =>
          resumeResult,
      history: (_) async {
        final gate = historyGate;
        if (gate == null) return [];
        if (!historyEntered.isCompleted) historyEntered.complete();
        final rows = await gate.future;
        if (!historyDelivered.isCompleted) historyDelivered.complete();
        return rows;
      },
    );
    session.setLifecycle(background: true, backgroundWorkEnabled: false);
  }

  Future<void> ready({bool bind = true}) async {
    await session.ready;
    owner = session.chatFor(
      'local',
      storedSessionId: bind ? 'stored' : null,
      title: 'private-title',
    );
  }

  void begin() {
    flight = owner.submitPrepared(
      reservation: owner.reserve()!,
      text: 'private-prompt',
      localContent: 'private-prompt',
    );
    flight!.ignore();
  }

  Future<void> start() async {
    await ready();
    begin();
    await sent.future;
  }

  void emit(String type, Map<String, dynamic> data) => session.receiveEvent(
    'local',
    StreamEvent(type: type, turnId: 'wire-${owner.turnId}', data: data),
  );

  Future<List<OperationalActivityRecord>> records() => activity.load('scope');

  void resetRpc() {
    rpc = Completer<void>();
    sent = Completer<void>();
  }

  Future<void> releaseRpc() async {
    if (!rpc.isCompleted) rpc.complete();
    await flight?.catchError((Object _) {});
  }

  Future<void> close() async {
    await session.close();
    await releaseRpc();
    await records();
  }
}

class _CountingActivityStore extends OperationalActivityStore {
  final List<OperationalActivityRecord> writes = [];
  bool reject = false;
  _CountingActivityStore({super.preferences});

  @override
  Future<void> put(OperationalActivityRecord record) {
    writes.add(record);
    return reject
        ? Future.error(StateError('metadata unavailable'))
        : super.put(record);
  }
}

class _HeldPendingStore extends NormalGatewayPendingStore {
  final String heldPhase;
  final entered = Completer<void>();
  final release = Completer<void>();
  _HeldPendingStore({required this.heldPhase});

  @override
  Future<void> put(NormalGatewayPendingMarker marker) async {
    if (marker.phase == heldPhase) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    await super.put(marker);
  }
}
