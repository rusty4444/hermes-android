import 'dart:async';
import 'dart:convert';

// flutter_test supplies this deterministic clock through its SDK.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/operational_activity_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Exercise physical preference failures, not just a rejecting store mock. Turn
// settlement remains authoritative even when the optional Activity index fails.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a failed terminal index update is repaired after later successful work '
      'and does not survive restart as a pending approval', () async {
    final platform = _RejectingActivityPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final f = _OwnerFixture();
    addTearDown(f.close);
    await f.start();
    final firstTurn = f.owner.turnId!;
    f.emit('approval.request', {
      'server_request_id': 'socket-approval',
      'prompt': 'not-persistable-request',
    });
    expect(
      (await f.records()).single.state,
      OperationalActivityState.needsInput,
    );

    // Only Activity fails. Pending tombstone/removal and real terminal
    // settlement succeed. The post-terminal history GET throws, so it cannot
    // accidentally generate an unrelated observer notification/retry.
    platform.rejectActivity = true;
    await f.finish();
    expect(f.owner.phase, NormalGatewayTurnPhase.completed);
    expect(f.owner.snapshot.pendingInput, isEmpty);
    expect(await f.session.pendingStore.load('review-scope'), isEmpty);
    expect(
      (await f.records()).single.state,
      OperationalActivityState.needsInput,
    );
    expect(platform.rejections, greaterThan(0));

    // Storage is healthy again. A new turn uses this same owner and index.
    // Its successful writes must repair A even though the retained chat owner
    // now represents B and no more events arrive for A.
    platform.rejectActivity = false;
    await f.start();
    final secondTurn = f.owner.turnId!;
    await f.finish();
    final beforeRestart = await f.records();
    expect(beforeRestart, hasLength(2));
    expect(
      beforeRestart.singleWhere((r) => r.turnId == firstTurn).state,
      OperationalActivityState.completed,
    );
    expect(
      beforeRestart.singleWhere((r) => r.turnId == secondTurn).state,
      OperationalActivityState.completed,
    );
    await f.close();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final durable = <String, Object>{
      for (final key in prefs.getKeys()) key: prefs.get(key)!,
    };
    SharedPreferences.setMockInitialValues(durable);
    final restored = _OwnerFixture();
    addTearDown(restored.close);
    await restored.session.ready;
    expect(
      restored.session.chats,
      isEmpty,
      reason: 'No pending marker survives to repair the stale index row.',
    );
    final rows = await restored.records();
    expect(rows.map((r) => r.toJson()), beforeRestart.map((r) => r.toJson()));
    final first = rows.singleWhere((r) => r.turnId == firstTurn);
    expect(
      first.state,
      OperationalActivityState.completed,
      reason:
          'A single failed optional terminal write must not leave an '
          'unanswerable Needs You row forever after healthy writes/restart.',
    );
  });

  test('repeated write failures do not turn every streamed token into '
      'another physical metadata write at the same clock value', () async {
    final platform = _RejectingActivityPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final f = _OwnerFixture();
    addTearDown(f.close);
    await f.start();
    await f.records();
    platform.rejectActivity = true;
    f.now += NormalGatewayApplicationSession
        .activityHeartbeatInterval
        .inMilliseconds;
    final before = platform.activityAttempts;
    final readsBefore = platform.preferenceReads;
    final observationsBefore = f.observations;
    int repairReads() =>
        platform.preferenceReads -
        readsBefore -
        (f.observations - observationsBefore) -
        (platform.activityAttempts - before);
    const tokenEvents = 20;
    for (var i = 0; i < tokenEvents; i++) {
      f.emit('message.delta', {'text': 'token'});
      // Each token arrives after the preceding failed storage operation has
      // actually completed, as with independently delivered network frames.
      // load joins the store queue; no elapsed clock time or sleeps are used.
      await f.records();
    }
    final attempts = platform.activityAttempts - before;
    expect(f.owner.phase, NormalGatewayTurnPhase.running);
    expect(f.owner.snapshot.displayRows.last['content'], 'token' * tokenEvents);

    expect(
      attempts,
      lessThan(tokenEvents),
      reason:
          'Failure retries need a bounded backoff/coalesced dirty slot, '
          'not one SharedPreferences write plus reload per streamed token.',
    );
    // One failed heartbeat and one immediate repair probe. Neither settled
    // failures nor arbitrarily many later frames can bypass the cooldown.
    expect(attempts, 2);
    // Every explicit observer and accepted write now reads fresh physical
    // state after the shared WAL/cache reload integration. Repair alone remains
    // exactly one reload per failed write, not per streamed token.
    expect(repairReads(), attempts);

    f.now +=
        NormalGatewayApplicationSession.activityRetryInterval.inMilliseconds -
        1;
    for (var i = 0; i < tokenEvents; i++) {
      f.emit('message.delta', {'text': 'token'});
      await f.records();
    }
    expect(platform.activityAttempts - before, 2);
    expect(repairReads(), 2);

    platform.rejectActivity = false;
    f.now++;
    f.emit('message.delta', {'text': 'recovered'});
    final repaired = (await f.records()).single;
    expect(platform.activityAttempts - before, 3);
    expect(repairReads(), 2);
    expect(repaired.state, OperationalActivityState.running);
    expect(repaired.updatedAtEpochMs, f.now);
    for (var i = 0; i < tokenEvents; i++) {
      f.emit('message.delta', {'text': 'token'});
      await f.records();
    }
    expect(platform.activityAttempts - before, 3);
    expect(f.submissions, 1);
  });

  test('terminal repair probes back off without renewing observation time '
      'or treating passive notifications as progress', () async {
    final platform = _RejectingActivityPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final f = _OwnerFixture();
    addTearDown(f.close);
    await f.start();
    f.emit('approval.request', {'server_request_id': 'approval'});
    await f.records();
    platform.rejectActivity = true;
    await f.finish();
    final terminalAt = f.now;
    final before = platform.activityAttempts;
    for (var i = 0; i < 20; i++) {
      // Child observers can continue after the parent settles. Unlike an
      // active-turn heartbeat, this probes the same dirty terminal snapshot.
      f.emit('subagent.text', {
        'subagent_id': 'child',
        'text': 'not-persistable-output',
      });
      await f.records();
    }
    expect(platform.activityAttempts - before, 1);
    f.now +=
        NormalGatewayApplicationSession.activityRetryInterval.inMilliseconds -
        1;
    platform.rejectActivity = false;
    f.session.connectionChanged(DesktopConnectionState.disconnected);
    final subscription = f.owner.subscribe((_) {});
    f.owner.unsubscribe(subscription);
    await f.records();
    expect(platform.activityAttempts - before, 1);
    f.emit('subagent.text', {'subagent_id': 'child'});
    await f.records();
    expect(platform.activityAttempts - before, 1);
    f.now++;
    f.emit('subagent.text', {'subagent_id': 'child'});
    final repaired = (await f.records()).single;
    expect(platform.activityAttempts - before, 2);
    expect(repaired.state, OperationalActivityState.completed);
    expect(repaired.updatedAtEpochMs, terminalAt);
    expect(repaired.updatedAtEpochMs, lessThan(f.now));
    expect(f.owner.phase, NormalGatewayTurnPhase.completed);
    expect(await f.session.pendingStore.load(f.scope), isEmpty);
    expect(f.submissions, 1);
  });

  test('multiple failed turn outcomes are repaired in one later observation '
      'without renewing their times, then survive restart', () async {
    final platform = _RejectingActivityPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final f = _OwnerFixture();
    addTearDown(f.close);
    final expected = <String, OperationalActivityState>{};
    final observedAt = <String, int>{};
    for (final completed in [true, false]) {
      await f.start();
      final turn = f.owner.turnId!;
      f.emit('approval.request', {'server_request_id': turn});
      final rows = await f.records();
      if (expected.isEmpty) {
        expect(rows.single.state, OperationalActivityState.needsInput);
      } else {
        expect(rows.single.turnId, expected.keys.single);
        expect(rows.single.state, OperationalActivityState.needsInput);
        expect(rows.any((r) => r.turnId == turn), isFalse);
      }
      platform.rejectActivity = true;
      await f.finish(completed: completed);
      observedAt[turn] = f.now;
      expected[turn] = completed
          ? OperationalActivityState.completed
          : OperationalActivityState.failed;
      expect(await f.session.pendingStore.load(f.scope), isEmpty);
      f.now++;
    }

    // A and B are both dirty. C repairs them in its first accepted state with
    // one read/modify/write, not one physical write per dirty turn. No further
    // event for either A or B is needed, even at the same retry-clock value.
    platform.rejectActivity = false;
    final before = platform.activityAttempts;
    await f.start();
    expected[f.owner.turnId!] = OperationalActivityState.completed;
    await f.records();
    expect(platform.activityAttempts - before, 2); // submitted, running
    await f.finish();
    observedAt[f.owner.turnId!] = f.now;
    expect(platform.activityAttempts - before, 3);
    expect(f.submissions, expected.length);
    final beforeRestart = await f.records();
    expect(beforeRestart, hasLength(expected.length));
    expect({for (final row in beforeRestart) row.turnId: row.state}, expected);
    expect({
      for (final row in beforeRestart) row.turnId: row.updatedAtEpochMs,
    }, observedAt);
    expect(beforeRestart.where((r) => r.isUnresolved), isEmpty);
    await f.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    SharedPreferences.setMockInitialValues({
      for (final key in prefs.getKeys()) key: prefs.get(key)!,
    });
    final restored = _OwnerFixture();
    addTearDown(restored.close);
    await restored.session.ready;
    expect(restored.session.chats, isEmpty);
    expect(
      (await restored.records()).map((r) => r.toJson()),
      beforeRestart.map((r) => r.toJson()),
    );
  });

  test('a late terminal write failure is carried by already accepted newer '
      'turn writes and close drains the repair', () async {
    final platform = _RejectingActivityPreferences();
    SharedPreferencesStorePlatform.instance = platform;
    final f = _OwnerFixture();
    addTearDown(f.close);
    await f.start();
    final firstTurn = f.owner.turnId!;
    f.emit('approval.request', {'server_request_id': 'approval'});
    await f.records();
    final before = platform.activityAttempts;
    final held = platform.holdNextActivity();
    await f.finish(drainActivity: false);
    await held.entered.future;
    expect(f.owner.phase, NormalGatewayTurnPhase.completed);
    expect(await f.session.pendingStore.load(f.scope), isEmpty);

    // B's submitted/running snapshots are accepted before A's physical write
    // has even failed. Their immutable batches must already contain A's repair.
    await f.start();
    final secondTurn = f.owner.turnId!;
    expect(f.submissions, 2);
    var closed = false;
    final closing = f.session.close().then((_) => closed = true);
    await Future<void>.value();
    expect(closed, isFalse);
    f.emit('turn.error', {'error': 'not-persistable-error'});
    held.result.complete(false);
    await closing;
    final rows = await f.records();
    expect(platform.activityAttempts - before, 3);
    expect(rows, hasLength(2));
    expect(
      rows.singleWhere((r) => r.turnId == firstTurn).state,
      OperationalActivityState.completed,
    );
    expect(
      rows.singleWhere((r) => r.turnId == secondTurn).state,
      OperationalActivityState.running,
    );
    expect(f.owner.phase, NormalGatewayTurnPhase.running);
  });

  test('failed retries coalesce while held and leave no timers or writes '
      'after close', () {
    fakeAsync((clock) {
      final platform = _RejectingActivityPreferences();
      SharedPreferencesStorePlatform.instance = platform;
      final f = _OwnerFixture();
      var started = false;
      f.start().then((_) => started = true);
      clock.flushMicrotasks();
      expect(started, isTrue);
      final held = platform.holdNextActivity();
      final before = platform.activityAttempts;
      f.now += NormalGatewayApplicationSession
          .activityHeartbeatInterval
          .inMilliseconds;
      f.emit('message.delta', {'text': 'token'});
      clock.flushMicrotasks();
      expect(held.entered.isCompleted, isTrue);
      for (var i = 0; i < 100; i++) {
        f.emit('message.delta', {'text': 'token'});
        clock.flushMicrotasks();
      }
      expect(platform.activityAttempts - before, 1);
      platform.rejectActivity = true;
      held.result.complete(false);
      clock.flushMicrotasks();
      f.emit('message.delta', {'text': 'token'});
      clock.flushMicrotasks();
      expect(platform.activityAttempts - before, 2);
      var closed = false;
      f.close().then((_) => closed = true);
      clock.flushMicrotasks();
      expect(closed, isTrue);
      expect(clock.pendingTimers, isEmpty);
      platform.rejectActivity = false;
      f.now += const Duration(days: 1).inMilliseconds;
      clock.elapse(const Duration(days: 1));
      f.emit('message.delta', {'text': 'ignored'});
      clock.flushMicrotasks();
      expect(platform.activityAttempts - before, 2);
      expect(clock.pendingTimers, isEmpty);
      expect(f.submissions, 1);
    });
  });

  test('replacement scope writes remain ordered and private behind a held '
      'retiring owner write', () async {
    final gate = Completer<SharedPreferences>();
    final old = _OwnerFixture(
      activity: OperationalActivityStore(preferences: () => gate.future),
    );
    addTearDown(old.close);
    await old.start();
    var closed = false;
    final closing = old.session.close().then((_) => closed = true);
    await Future<void>.value();
    expect(closed, isFalse);

    final replacement = _OwnerFixture(scope: 'replacement-scope');
    addTearDown(replacement.close);
    await replacement.start();
    old.emit('turn.error', {'error': 'not-persistable-error'});
    final read = replacement.records();
    gate.complete(await SharedPreferences.getInstance());
    await closing;
    expect((await read).single.state, OperationalActivityState.running);
    expect(
      (await old.records()).single.state,
      OperationalActivityState.running,
    );
    expect((await replacement.records()).single.scope, 'replacement-scope');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(OperationalActivityStore.preferenceKey)!;
    expect(raw, isNot(contains('not-persistable')));
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    for (final row in rows) {
      expect(row.keys.toSet(), {
        'scope',
        'localSessionId',
        'storedSessionId',
        'turnId',
        'state',
        'updatedAtEpochMs',
      });
    }
  });
}

class _RejectingActivityPreferences extends InMemorySharedPreferencesStore {
  bool rejectActivity = false;
  int activityAttempts = 0;
  int rejections = 0;
  int preferenceReads = 0;
  _ActivityWriteGate? _held;
  _RejectingActivityPreferences() : super.empty();

  _ActivityWriteGate holdNextActivity() {
    expect(_held, isNull);
    return _held = _ActivityWriteGate();
  }

  @override
  Future<Map<String, Object>> getAll() {
    preferenceReads++;
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key.endsWith(OperationalActivityStore.preferenceKey)) {
      activityAttempts++;
      final held = _held;
      _held = null;
      if (held != null) held.entered.complete();
      if (held != null ? !await held.result.future : rejectActivity) {
        rejections++;
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}

class _ActivityWriteGate {
  final entered = Completer<void>();
  final result = Completer<bool>();
}

class _OwnerFixture {
  final String scope;
  late final OperationalActivityStore activity;
  late final NormalGatewayApplicationSession session;
  late NormalGatewayChatOwner owner;
  bool _hasOwner = false;
  Completer<void>? _rpc;
  Completer<void>? _sent;
  Future<void>? _flight;
  int now = 2000000000000;
  int submissions = 0;
  int observations = 0;

  _OwnerFixture({
    this.scope = 'review-scope',
    OperationalActivityStore? activity,
  }) {
    this.activity = activity ?? OperationalActivityStore(nowEpochMs: () => now);
    session = NormalGatewayApplicationSession(
      connection: SavedConnection(
        id: 'review-connection',
        label: 'not-persistable-label',
        host: 'review.invalid',
        port: 8642,
        apiKey: 'not-persistable-credential',
      ),
      scope: scope,
      activityStore: this.activity,
      activityNowEpochMs: () => now,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            submissions++;
            onSent();
            session.receiveEvent(
              'local',
              StreamEvent(
                type: 'message.delta',
                turnId: 'wire-${owner.turnId}',
                data: {'text': ''},
              ),
            );
            _sent!.complete();
            return _rpc!.future;
          },
      resume: ({required localSessionId, required storedSessionId}) async =>
          const ResumedGatewaySession(
            runtimeSessionId: 'runtime',
            running: true,
          ),
      history: (_) async => throw StateError('history unavailable'),
    );
    session.setLifecycle(background: true, backgroundWorkEnabled: false);
  }

  Future<void> start() async {
    await session.ready;
    if (!_hasOwner) {
      owner = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'not-persistable-title',
      );
      _hasOwner = true;
    }
    _rpc = Completer<void>();
    _sent = Completer<void>();
    _flight = owner.submitPrepared(
      reservation: owner.reserve()!,
      text: 'not-persistable-prompt',
      localContent: 'not-persistable-prompt',
    );
    _flight!.ignore();
    await _sent!.future;
  }

  Future<void> finish({
    bool completed = true,
    bool drainActivity = true,
  }) async {
    final terminal = Completer<void>();
    final subscription = owner.subscribe((state) {
      if (state.phase ==
              (completed
                  ? NormalGatewayTurnPhase.completed
                  : NormalGatewayTurnPhase.failed) &&
          !terminal.isCompleted) {
        terminal.complete();
      }
    });
    emit(
      completed ? 'turn.end' : 'turn.error',
      completed ? {'status': 'completed'} : {'error': 'not-persistable-error'},
    );
    await terminal.future;
    owner.unsubscribe(subscription);
    if (!_rpc!.isCompleted) _rpc!.complete();
    await _flight;
    if (drainActivity) await records();
  }

  void emit(String type, Map<String, dynamic> data) => session.receiveEvent(
    'local',
    StreamEvent(type: type, turnId: 'wire-${owner.turnId}', data: data),
  );
  Future<List<OperationalActivityRecord>> records() {
    observations++;
    return activity.load(scope);
  }

  Future<void> close() async {
    await session.close();
    final rpc = _rpc;
    if (rpc != null && !rpc.isCompleted) rpc.complete();
    await _flight;
    await records();
  }
}
