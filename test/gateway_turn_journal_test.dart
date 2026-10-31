import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';

const _digestA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _digestB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _mobileA = '11111111-1111-4111-8111-111111111111';
const _mobileB = '22222222-2222-4222-8222-222222222222';
const _clientA = '33333333-3333-4333-8333-333333333333';
const _baseMs = 1720000000000;

class _MemoryJournalStore implements GatewayTurnJournalStore {
  String? value;
  String? v1Value;
  bool unavailable = false;
  bool failNextWrite = false;
  bool corruptNextReadback = false;
  bool failV1Delete = false;
  Duration delay = Duration.zero;

  @override
  Future<void> delete() async {
    await Future<void>.delayed(delay);
    if (unavailable) throw StateError('unavailable');
    value = null;
  }

  @override
  Future<String?> read() async {
    await Future<void>.delayed(delay);
    if (unavailable) throw StateError('unavailable');
    if (corruptNextReadback) {
      corruptNextReadback = false;
      return '${value ?? ''}corrupt';
    }
    return value;
  }

  @override
  Future<void> write(String newValue) async {
    await Future<void>.delayed(delay);
    if (unavailable) throw StateError('unavailable');
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('write failed');
    }
    value = newValue;
  }

  @override
  Future<void> deleteLegacy() async {
    await Future<void>.delayed(delay);
    if (unavailable) throw StateError('unavailable');
    if (failV1Delete) throw StateError('v1 delete unavailable');
    v1Value = null;
  }

  @override
  Future<String?> readLegacy() async {
    await Future<void>.delayed(delay);
    if (unavailable) throw StateError('unavailable');
    return v1Value != null ? 'incompatible' : null;
  }
}

GatewayTurnJournalBinding _binding({
  String connectionId = 'connection-a',
  String endpointDigest = _digestA,
  String localSessionId = 'local-session-a',
  String mobileSessionId = _mobileA,
  String storedSessionId = 'stored-session-a',
  int bindingVersion = 1,
  int updatedAtEpochMs = _baseMs,
}) => GatewayTurnJournalBinding(
  connectionId: connectionId,
  endpointDigest: endpointDigest,
  localSessionId: localSessionId,
  mobileSessionId: mobileSessionId,
  storedSessionId: storedSessionId,
  bindingVersion: bindingVersion,
  updatedAtEpochMs: updatedAtEpochMs,
);

GatewayTurnJournalEntry _entry({
  GatewayTurnJournalBinding? binding,
  String clientTurnId = _clientA,
  String? turnId,
  GatewayRecoveryTurnStatus? status,
  int lastSeq = 0,
  int eventPayloadBytes = 0,
  bool terminalEventRecorded = false,
  GatewayTurnTerminalResult? terminalResult,
  bool ackUncertain = true,
  GatewayTurnRecoveryFailure? failure,
  int updatedAtEpochMs = _baseMs,
}) => GatewayTurnJournalEntry(
  bindingIdentity: (binding ?? _binding()).bindingIdentity,
  clientTurnId: clientTurnId,
  turnId: turnId,
  status: status,
  lastSeq: lastSeq,
  eventPayloadBytes: eventPayloadBytes,
  terminalEventRecorded: terminalEventRecorded,
  terminalResult:
      terminalResult ??
      (status == GatewayRecoveryTurnStatus.completed && failure == null
          ? GatewayTurnTerminalResult(
              messageId: 'message-$clientTurnId',
              assistantText: 'Durable recovery completed.',
            )
          : null),
  ackUncertain: ackUncertain,
  failure: failure,
  updatedAtEpochMs: updatedAtEpochMs,
);

String _uuidFor(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

String _repeat(String value, int count) => List.filled(count, value).join();

GatewayTurnRecoveryState _failureWithPayload() {
  var state = GatewayTurnRecoveryState.initial(
    clientTurnId: _clientA,
  ).markSubmissionStarted();
  state = state.applyAck(
    const GatewayTurnAck(
      clientTurnId: _clientA,
      turnId: 'turn-process-poison',
      status: GatewayRecoveryTurnStatus.accepted,
      lastSeq: 0,
      created: true,
    ),
  );
  state = state.applyEvent(
    const GatewayTurnEvent(
      turnId: 'turn-process-poison',
      seq: 1,
      messageId: 'message-process-poison',
      type: 'message.start',
      payload: <String, dynamic>{},
    ),
  );
  return state.failReconcile(GatewayTurnRecoveryFailure.protocolViolation);
}

Future<void> _seedBinding(
  GatewayTurnJournal journal, [
  GatewayTurnJournalBinding? binding,
]) => journal.upsertBinding(binding ?? _binding());

void main() {
  group('durable turn journal v4', () {
    test('round-trips a durable binding and metadata-only turn', () async {
      final store = _MemoryJournalStore();
      final firstProcess = GatewayTurnJournal(store: store);
      final binding = _binding();
      await firstProcess.upsertBinding(binding);
      await firstProcess.upsert(
        _entry(
          binding: binding,
          turnId: 'turn-1',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 3,
          eventPayloadBytes: 321,
          ackUncertain: false,
        ),
        now: DateTime.fromMillisecondsSinceEpoch(_baseMs, isUtc: true),
      );

      final secondProcess = GatewayTurnJournal(store: store);
      final restoredBinding = await secondProcess.loadBinding(
        connectionId: binding.connectionId,
        endpointDigest: binding.endpointDigest,
        localSessionId: binding.localSessionId,
      );
      expect(restoredBinding?.mobileSessionId, _mobileA);
      expect(restoredBinding?.storedSessionId, 'stored-session-a');
      final restored = await secondProcess.loadForBinding(restoredBinding!);
      expect(restored, hasLength(1));
      expect(restored.single.clientTurnId, _clientA);
      expect(restored.single.turnId, 'turn-1');
      expect(restored.single.lastSeq, 3);
      expect(restored.single.eventPayloadBytes, 321);
      expect(restored.single.failure, isNull);

      final rehydrated = GatewayTurnRecoveryState.rehydrate(
        clientTurnId: restored.single.clientTurnId,
        turnId: restored.single.turnId,
        status: restored.single.status,
        lastSeq: restored.single.lastSeq,
        ackUncertain: restored.single.ackUncertain,
        eventPayloadBytes: restored.single.eventPayloadBytes,
        terminalEventRecorded: restored.single.terminalEventRecorded,
        failure: restored.single.failure,
      );
      expect(rehydrated.clientTurnId, restored.single.clientTurnId);
      expect(rehydrated.turnId, restored.single.turnId);
      expect(rehydrated.status, restored.single.status);
      expect(rehydrated.lastSeq, restored.single.lastSeq);
      expect(rehydrated.eventPayloadBytes, restored.single.eventPayloadBytes);
      expect(
        rehydrated.terminalEventRecorded,
        restored.single.terminalEventRecorded,
      );
      expect(rehydrated.ackUncertain, restored.single.ackUncertain);
      expect(rehydrated.requiredAction, GatewayTurnRecoveryAction.reconcile);

      final encoded = store.value!;
      expect(encoded, contains(GatewayTurnJournal.schema));
      for (final forbidden in <String>[
        'runtime_session_id',
        'prompt',
        'credential',
        'token',
        'password',
        'attachment_path',
        'attachment_bytes',
        'ref_text',
        'assistant_text',
        'output',
        'tool_result',
        'reasoning',
        'sudo',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }
    });

    test(
      'serializes two journal instances over the same delayed authority',
      () async {
        final store = _MemoryJournalStore()
          ..delay = const Duration(milliseconds: 2);
        final first = GatewayTurnJournal(store: store);
        final second = GatewayTurnJournal(store: store);
        final bindingA = _binding();
        final bindingB = _binding(
          connectionId: 'connection-b',
          endpointDigest: _digestB,
          localSessionId: 'local-session-b',
          mobileSessionId: _mobileB,
          storedSessionId: 'stored-session-b',
        );

        await Future.wait(<Future<void>>[
          first.upsertBinding(bindingA),
          second.upsertBinding(bindingB),
        ]);
        await Future.wait(<Future<void>>[
          first.upsert(
            _entry(
              binding: bindingA,
              clientTurnId: _clientA,
              updatedAtEpochMs: _baseMs + 1,
            ),
          ),
          second.upsert(
            _entry(
              binding: bindingB,
              clientTurnId: _uuidFor(2),
              updatedAtEpochMs: _baseMs + 2,
            ),
          ),
        ]);

        final snapshot = await GatewayTurnJournal(store: store).loadSnapshot();
        expect(
          snapshot.bindings.map((binding) => binding.bindingIdentity).toSet(),
          <String>{bindingA.bindingIdentity, bindingB.bindingIdentity},
        );
        expect(
          snapshot.entries.map((entry) => entry.clientTurnId).toSet(),
          <String>{_clientA, _uuidFor(2)},
        );
      },
    );

    test(
      'bounds process poison scopes and escalates without cross-authority leak',
      () {
        final sharedStore = _MemoryJournalStore();
        final first = GatewayTurnJournal(store: sharedStore);
        final second = GatewayTurnJournal(store: sharedStore);
        final isolated = GatewayTurnJournal(store: _MemoryJournalStore());
        final failure = _failureWithPayload();

        for (
          var index = 0;
          index < GatewayTurnJournal.maxBindings;
          index += 1
        ) {
          first.recordProcessPoison(
            connectionId: 'connection-a',
            endpointDigest: _digestA,
            localSessionId: 'local-process-$index',
            failure: failure,
          );
        }

        expect(
          second.processPoisonedScopeCount,
          GatewayTurnJournal.maxBindings,
        );
        expect(second.authorityWideProcessPoisoned, isFalse);
        expect(
          second.processPoisonedFailure(
            connectionId: 'connection-a',
            endpointDigest: _digestA,
            localSessionId: 'local-not-yet-poisoned',
          ),
          isNull,
        );
        final scoped = second.processPoisonedFailure(
          connectionId: 'connection-a',
          endpointDigest: _digestA,
          localSessionId: 'local-process-0',
        )!;
        expect(scoped.failure, GatewayTurnRecoveryFailure.protocolViolation);
        expect(scoped.events, isEmpty);
        expect(scoped.snapshot, isNull);

        second.recordProcessPoison(
          connectionId: 'connection-a',
          endpointDigest: _digestA,
          localSessionId: 'local-process-overflow',
          failure: failure,
        );

        expect(first.processPoisonedScopeCount, GatewayTurnJournal.maxBindings);
        expect(first.authorityWideProcessPoisoned, isTrue);
        final authorityWide = first.processPoisonedFailure(
          connectionId: 'connection-b',
          endpointDigest: _digestB,
          localSessionId: 'arbitrary-local-session',
        )!;
        expect(
          authorityWide.failure,
          GatewayTurnRecoveryFailure.protocolViolation,
        );
        expect(authorityWide.events, isEmpty);
        expect(authorityWide.snapshot, isNull);

        expect(isolated.processPoisonedScopeCount, 0);
        expect(isolated.authorityWideProcessPoisoned, isFalse);
        expect(
          isolated.processPoisonedFailure(
            connectionId: 'connection-a',
            endpointDigest: _digestA,
            localSessionId: 'local-process-0',
          ),
          isNull,
        );
      },
    );

    test('round-trips monotonic byte cursor and failure quarantine', () async {
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      await _seedBinding(journal);
      await journal.upsert(
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 2,
          eventPayloadBytes: 97,
          ackUncertain: false,
        ),
      );
      await journal.upsert(
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 2,
          eventPayloadBytes: 97,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.duplicateConflict,
          updatedAtEpochMs: _baseMs + 1,
        ),
      );

      final restored = (await GatewayTurnJournal(
        store: store,
      ).loadAll()).single;
      expect(restored.eventPayloadBytes, 97);
      expect(restored.failure, GatewayTurnRecoveryFailure.duplicateConflict);

      for (final invalid in <GatewayTurnJournalEntry>[
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 2,
          eventPayloadBytes: 96,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.duplicateConflict,
          updatedAtEpochMs: _baseMs + 2,
        ),
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 2,
          eventPayloadBytes: 97,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 2,
        ),
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 2,
          eventPayloadBytes: 97,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.sequenceGap,
          updatedAtEpochMs: _baseMs + 2,
        ),
        _entry(
          turnId: 'turn-mutated',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 2,
          eventPayloadBytes: 97,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.duplicateConflict,
          updatedAtEpochMs: _baseMs + 2,
        ),
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 3,
          eventPayloadBytes: 97,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.duplicateConflict,
          updatedAtEpochMs: _baseMs + 2,
        ),
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 2,
          eventPayloadBytes: 98,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.duplicateConflict,
          updatedAtEpochMs: _baseMs + 2,
        ),
        _entry(
          turnId: 'turn-quarantine',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 3,
          eventPayloadBytes: 120,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.duplicateConflict,
          updatedAtEpochMs: _baseMs + 2,
        ),
      ]) {
        await expectLater(
          journal.upsert(invalid),
          throwsA(isA<GatewayTurnJournalException>()),
        );
      }
      expect((await journal.loadAll()).single.failure, restored.failure);
    });

    test(
      'first failure may seal accepted monotonic progress atomically',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        await journal.upsert(
          _entry(
            turnId: 'turn-progress-then-failure',
            status: GatewayRecoveryTurnStatus.running,
            lastSeq: 2,
            eventPayloadBytes: 97,
            ackUncertain: false,
          ),
        );

        await journal.upsert(
          _entry(
            turnId: 'turn-progress-then-failure',
            status: GatewayRecoveryTurnStatus.completed,
            lastSeq: 3,
            eventPayloadBytes: 120,
            terminalEventRecorded: true,
            ackUncertain: false,
            failure: GatewayTurnRecoveryFailure.protocolViolation,
            updatedAtEpochMs: _baseMs + 1,
          ),
        );

        final restored = (await journal.loadAll()).single;
        expect(restored.turnId, 'turn-progress-then-failure');
        expect(restored.status, GatewayRecoveryTurnStatus.completed);
        expect(restored.lastSeq, 3);
        expect(restored.eventPayloadBytes, 120);
        expect(restored.terminalEventRecorded, isTrue);
        expect(restored.ackUncertain, isFalse);
        expect(restored.failure, GatewayTurnRecoveryFailure.protocolViolation);
      },
    );

    test(
      'restarts every recovery failure enum as durable quarantine',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        for (
          var index = 0;
          index < GatewayTurnRecoveryFailure.values.length;
          index += 1
        ) {
          await journal.upsert(
            _entry(
              clientTurnId: _uuidFor(index + 1),
              ackUncertain: false,
              failure: GatewayTurnRecoveryFailure.values[index],
              updatedAtEpochMs: _baseMs + index,
            ),
          );
        }

        final restarted = await GatewayTurnJournal(store: store).loadAll();
        expect(
          restarted.map((entry) => entry.failure).toSet(),
          GatewayTurnRecoveryFailure.values.toSet(),
        );
        expect(restarted.every((entry) => !entry.ackUncertain), isTrue);
        for (final entry in restarted) {
          final state = GatewayTurnRecoveryState.rehydrate(
            clientTurnId: entry.clientTurnId,
            turnId: entry.turnId,
            status: entry.status,
            lastSeq: entry.lastSeq,
            ackUncertain: entry.ackUncertain,
            eventPayloadBytes: entry.eventPayloadBytes,
            terminalEventRecorded: entry.terminalEventRecorded,
            failure: entry.failure,
          );
          expect(state.failure, entry.failure);
          expect(
            state.requiredAction,
            GatewayTurnRecoveryAction.stopFailClosed,
          );
        }
      },
    );

    test('persists terminal failure and never compacts quarantine', () async {
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      final now = DateTime.utc(2026, 8, 10, 12);
      await _seedBinding(journal);
      await journal.upsert(
        _entry(
          turnId: 'turn-terminal-quarantine',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 7,
          eventPayloadBytes: 700,
          terminalEventRecorded: true,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.invalidTransition,
          updatedAtEpochMs: now
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
        ),
        now: now.subtract(const Duration(days: 30)),
      );

      final compacted = await journal.compact(now: now);
      expect(compacted.entries, hasLength(1));
      expect(compacted.entries.single.isTerminal, isTrue);
      expect(compacted.entries.single.terminalEventRecorded, isTrue);
      expect(
        compacted.entries.single.failure,
        GatewayTurnRecoveryFailure.invalidTransition,
      );
      final restarted = await GatewayTurnJournal(store: store).loadAll();
      expect(restarted.single.terminalEventRecorded, isTrue);
      expect(
        restarted.single.failure,
        GatewayTurnRecoveryFailure.invalidTransition,
      );
    });

    test(
      'retains the session binding after its terminal turn expires',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final now = DateTime.utc(2026, 8, 10, 12);
        final binding = _binding(
          updatedAtEpochMs: now
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch,
        );
        await journal.upsertBinding(binding);
        await journal.upsert(
          _entry(
            binding: binding,
            turnId: 'terminal-old',
            status: GatewayRecoveryTurnStatus.completed,
            lastSeq: 1,
            terminalEventRecorded: true,
            ackUncertain: false,
            updatedAtEpochMs: now
                .subtract(const Duration(hours: 25))
                .millisecondsSinceEpoch,
          ),
          now: now.subtract(const Duration(hours: 25)),
        );

        final compacted = await journal.compact(now: now);
        expect(compacted.entries, isEmpty);
        expect(compacted.bindings, hasLength(1));
        expect(compacted.bindings.single.mobileSessionId, _mobileA);
      },
    );

    test(
      'isolates bindings by connection, endpoint, and local session',
      () async {
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        await _seedBinding(journal);

        expect(
          await journal.loadBinding(
            connectionId: 'connection-b',
            endpointDigest: _digestA,
            localSessionId: 'local-session-a',
          ),
          isNull,
        );
        expect(
          await journal.loadBinding(
            connectionId: 'connection-a',
            endpointDigest: _digestB,
            localSessionId: 'local-session-a',
          ),
          isNull,
        );
        expect(
          await journal.loadBinding(
            connectionId: 'connection-a',
            endpointDigest: _digestA,
            localSessionId: 'local-session-b',
          ),
          isNull,
        );
        expect(
          await journal.loadBinding(
            connectionId: 'connection-a',
            endpointDigest: _digestA,
            localSessionId: 'local-session-a',
          ),
          isNotNull,
        );
      },
    );

    test(
      'rejects binding mutation, version regression, and orphan turns',
      () async {
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        await _seedBinding(journal);

        await expectLater(
          journal.upsertBinding(_binding(mobileSessionId: _mobileB)),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        await journal.upsertBinding(_binding(bindingVersion: 2));
        await expectLater(
          journal.upsertBinding(_binding(bindingVersion: 1)),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        await expectLater(
          journal.upsertBinding(
            _binding(bindingVersion: 2, updatedAtEpochMs: _baseMs - 1),
          ),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        await expectLater(
          journal.upsert(
            _entry(binding: _binding(localSessionId: 'missing-binding')),
          ),
          throwsA(isA<GatewayTurnJournalException>()),
        );
      },
    );

    test('rejects stale or nonmonotonic turn entry replacement', () async {
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      await _seedBinding(journal);
      await journal.upsert(
        _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 4,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 10,
        ),
      );

      for (final invalid in <GatewayTurnJournalEntry>[
        _entry(
          turnId: 'turn-mutated',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 4,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 11,
        ),
        _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 3,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 11,
        ),
        _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.accepted,
          lastSeq: 4,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 11,
        ),
        _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 4,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 9,
        ),
      ]) {
        final before = store.value;
        await expectLater(
          journal.upsert(invalid),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect(store.value, before);
      }

      await journal.upsert(
        _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 5,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 12,
        ),
        now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 12, isUtc: true),
      );
      final terminal = store.value;
      for (final invalid in <GatewayTurnJournalEntry>[
        _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 5,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 13,
        ),
        _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 6,
          ackUncertain: false,
          updatedAtEpochMs: _baseMs + 13,
        ),
      ]) {
        await expectLater(
          journal.upsert(invalid),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect(store.value, terminal);
      }
      expect(
        () => _entry(
          turnId: 'turn-authoritative',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 5,
          ackUncertain: true,
          updatedAtEpochMs: _baseMs + 13,
        ),
        throwsArgumentError,
      );
      expect(store.value, terminal);
    });

    test(
      'fails closed on unavailable, malformed, and orphaned storage',
      () async {
        final unavailable = _MemoryJournalStore()..unavailable = true;
        await expectLater(
          GatewayTurnJournal(store: unavailable).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );

        final corrupt = _MemoryJournalStore()..value = '{not-json';
        await expectLater(
          GatewayTurnJournal(store: corrupt).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );

        final binding = _binding();
        final unknownField = _MemoryJournalStore()
          ..value = jsonEncode(<String, Object>{
            'schema': GatewayTurnJournal.schema,
            'bindings': <Object>[binding.toJson()],
            'entries': <Object>[
              <String, Object?>{
                ..._entry(binding: binding).toJson(),
                'prompt': 'must fail closed',
              },
            ],
          });
        await expectLater(
          GatewayTurnJournal(store: unknownField).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );

        final missingTerminalEvidence = _entry(binding: binding).toJson()
          ..remove('terminal_event_recorded');
        final missingRequired = _MemoryJournalStore()
          ..value = jsonEncode(<String, Object>{
            'schema': GatewayTurnJournal.schema,
            'bindings': <Object>[binding.toJson()],
            'entries': <Object>[missingTerminalEvidence],
          });
        await expectLater(
          GatewayTurnJournal(store: missingRequired).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );

        final orphan = _MemoryJournalStore()
          ..value = jsonEncode(<String, Object>{
            'schema': GatewayTurnJournal.schema,
            'bindings': const <Object>[],
            'entries': <Object>[_entry().toJson()],
          });
        await expectLater(
          GatewayTurnJournal(store: orphan).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );
      },
    );

    test(
      'purges incompatible v2 and v1 fail-first without migration',
      () async {
        final v2Payload = jsonEncode(<String, Object>{
          'schema': 'hermes.android.turn-journal.v2',
          'runtime_session_id': 'runtime-must-never-migrate',
          'entries': const <Object>[],
        });
        final v1Payload = jsonEncode(<String, Object>{
          'schema': 'hermes.android.turn-journal.v1',
          'runtime_session_id': 'runtime-must-never-migrate',
          'entries': const <Object>[],
        });
        final store = _MemoryJournalStore()
          ..value = v2Payload
          ..v1Value = v1Payload;
        final journal = GatewayTurnJournal(store: store);

        await expectLater(
          journal.loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect(store.v1Value, isNull);
        expect(store.value, isNull);
        expect((await journal.loadSnapshot()).bindings, isEmpty);

        final blocked = _MemoryJournalStore()
          ..value = v2Payload
          ..v1Value = v1Payload
          ..failV1Delete = true;
        await expectLater(
          GatewayTurnJournal(store: blocked).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect(blocked.v1Value, v1Payload);
        expect(blocked.value, v2Payload);
      },
    );

    test(
      'keeps v4 in the same authority slot while purging legacy v1',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        final v4Authority = store.value;
        store.v1Value = jsonEncode(<String, Object>{
          'schema': 'hermes.android.turn-journal.v1',
          'entries': const <Object>[],
        });

        await expectLater(
          journal.loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect(store.v1Value, isNull);
        expect(store.value, v4Authority);
        expect((await journal.loadSnapshot()).bindings, hasLength(1));

        final root = jsonDecode(store.value!) as Map<String, dynamic>;
        expect(root['schema'], GatewayTurnJournal.schema);
        // A downgraded v2 reader sees incompatible v4 in its own slot; there is
        // no parallel v2 authority to revive after rollback.
        expect(root['schema'], isNot('hermes.android.turn-journal.v2'));
      },
    );

    test(
      'migrates active v3 and quarantines payload-free completed v3',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final binding = _binding();
        await journal.upsertBinding(binding);
        await journal.upsert(
          _entry(
            binding: binding,
            turnId: 'turn-active-v3',
            status: GatewayRecoveryTurnStatus.running,
            lastSeq: 2,
            ackUncertain: true,
          ),
        );
        await journal.upsert(
          _entry(
            binding: binding,
            clientTurnId: _uuidFor(2),
            turnId: 'turn-completed-v3',
            status: GatewayRecoveryTurnStatus.completed,
            lastSeq: 7,
            terminalEventRecorded: true,
            ackUncertain: false,
            updatedAtEpochMs: _baseMs + 1,
          ),
          now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 2, isUtc: true),
        );

        final legacy = jsonDecode(store.value!) as Map<String, dynamic>;
        legacy['schema'] = GatewayTurnJournal.compatibleLegacySchema;
        for (final raw in legacy['entries'] as List<dynamic>) {
          (raw as Map<String, dynamic>).remove('terminal_result');
        }
        store.value = jsonEncode(legacy);

        final migrated = await GatewayTurnJournal(store: store).loadAll();
        final active = migrated.singleWhere(
          (entry) => entry.turnId == 'turn-active-v3',
        );
        final completed = migrated.singleWhere(
          (entry) => entry.turnId == 'turn-completed-v3',
        );
        expect(active.failure, isNull);
        expect(active.status, GatewayRecoveryTurnStatus.running);
        expect(completed.failure, GatewayTurnRecoveryFailure.protocolViolation);
        expect(completed.terminalResult, isNull);
        expect(
          (jsonDecode(store.value!) as Map<String, dynamic>)['schema'],
          GatewayTurnJournal.schema,
        );
      },
    );

    test(
      'bounds UTF-8 bytes before parsing current or incompatible data',
      () async {
        final padding = _repeat(
          '😀',
          GatewayTurnJournal.maxEncodedBytes ~/ 4 + 128,
        );
        final encoded = jsonEncode(<String, Object>{
          'schema': GatewayTurnJournal.schema,
          'bindings': const <Object>[],
          'entries': const <Object>[],
          'padding': padding,
        });
        expect(encoded.length, lessThan(GatewayTurnJournal.maxEncodedBytes));
        expect(
          utf8.encode(encoded).length,
          greaterThan(GatewayTurnJournal.maxEncodedBytes),
        );
        final store = _MemoryJournalStore()..value = encoded;
        await expectLater(
          GatewayTurnJournal(store: store).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect(store.value, same(encoded));

        final oversizedV2 = jsonEncode(<String, Object>{
          'schema': 'hermes.android.turn-journal.v2',
          'runtime_session_id': padding,
          'entries': const <Object>[],
        });
        expect(
          utf8.encode(oversizedV2).length,
          greaterThan(GatewayTurnJournal.maxEncodedBytes),
        );
        store.value = oversizedV2;
        await expectLater(
          GatewayTurnJournal(store: store).loadSnapshot(),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        // Oversized content is never parsed to decide whether deletion is safe.
        expect(store.value, same(oversizedV2));
      },
    );

    test('rolls back a failed write or readback verification', () async {
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      await _seedBinding(journal);
      final original = store.value;

      store.failNextWrite = true;
      await expectLater(
        journal.upsertBinding(
          _binding(localSessionId: 'local-b', mobileSessionId: _mobileB),
        ),
        throwsA(isA<GatewayTurnJournalException>()),
      );
      expect(store.value, original);

      store.corruptNextReadback = true;
      await expectLater(
        journal.upsert(
          _entry(clientTurnId: _uuidFor(2), updatedAtEpochMs: _baseMs + 1),
        ),
        throwsA(isA<GatewayTurnJournalException>()),
      );
      expect(store.value, original);
    });

    test('serializes writes and refuses a sixty-fifth active turn', () async {
      final store = _MemoryJournalStore()
        ..delay = const Duration(milliseconds: 1);
      final journal = GatewayTurnJournal(store: store);
      await _seedBinding(journal);
      final now = DateTime.fromMillisecondsSinceEpoch(
        _baseMs + 1000,
        isUtc: true,
      );
      await Future.wait(<Future<void>>[
        for (var index = 1; index <= GatewayTurnJournal.maxEntries; index += 1)
          journal.upsert(
            _entry(
              clientTurnId: _uuidFor(index),
              updatedAtEpochMs: _baseMs + index,
            ),
            now: now,
          ),
      ]);

      final entries = await journal.loadAll();
      expect(entries, hasLength(GatewayTurnJournal.maxEntries));
      final before = store.value;
      await expectLater(
        journal.upsert(
          _entry(
            clientTurnId: _uuidFor(GatewayTurnJournal.maxEntries + 1),
            updatedAtEpochMs: _baseMs + GatewayTurnJournal.maxEntries + 1,
          ),
          now: now,
        ),
        throwsA(isA<GatewayTurnJournalException>()),
      );
      expect(store.value, before);
      expect(await journal.loadAll(), hasLength(GatewayTurnJournal.maxEntries));
    });

    test(
      'evicts only safe terminal turns and retains uncertain history',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        final now = DateTime.fromMillisecondsSinceEpoch(
          _baseMs + 10000,
          isUtc: true,
        );
        for (var index = 1; index < GatewayTurnJournal.maxEntries; index += 1) {
          await journal.upsert(
            _entry(
              clientTurnId: _uuidFor(index),
              updatedAtEpochMs: _baseMs + index,
            ),
            now: now,
          );
        }
        await journal.upsert(
          _entry(
            clientTurnId: _uuidFor(64),
            turnId: 'terminal-safe',
            status: GatewayRecoveryTurnStatus.completed,
            lastSeq: 1,
            terminalEventRecorded: true,
            ackUncertain: false,
            updatedAtEpochMs: _baseMs + 64,
          ),
          now: now,
        );
        await journal.upsert(
          _entry(clientTurnId: _uuidFor(65), updatedAtEpochMs: _baseMs + 65),
          now: now,
        );
        final entries = await journal.loadAll();
        expect(entries, hasLength(GatewayTurnJournal.maxEntries));
        expect(
          entries.map((entry) => entry.clientTurnId),
          isNot(contains(_uuidFor(64))),
        );

        final oldUncertain = _entry(
          clientTurnId: _uuidFor(1),
          turnId: 'still-uncertain',
          status: GatewayRecoveryTurnStatus.failed,
          ackUncertain: true,
          updatedAtEpochMs: _baseMs + 1,
        );
        final isolated = GatewayTurnJournal(store: _MemoryJournalStore());
        await _seedBinding(isolated);
        await isolated.upsert(oldUncertain, now: now);
        expect((await isolated.compact(now: now)).entries, hasLength(1));
      },
    );

    test(
      'quarantined failure entries evict last-resort instead of starving the '
      'journal forever',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        final oldMs = _baseMs;
        final now = DateTime.fromMillisecondsSinceEpoch(
          oldMs + 60000,
          isUtc: true,
        );
        // Fill the journal to capacity with entries the old eviction rules
        // could never remove: terminal-failed with a durable failure
        // (quarantine). These are not ack-uncertain, so they are not
        // genuinely-pending backpressure.
        for (var index = 1; index <= GatewayTurnJournal.maxEntries; index += 1) {
          await journal.upsert(
            _entry(
              clientTurnId: _uuidFor(index),
              turnId: 'turn-quarantine-$index',
              status: GatewayRecoveryTurnStatus.failed,
              lastSeq: 1,
              terminalEventRecorded: true,
              ackUncertain: false,
              failure: GatewayTurnRecoveryFailure.turnUnknown,
              updatedAtEpochMs: oldMs + index,
            ),
            now: now,
          );
        }
        expect(await journal.loadAll(), hasLength(GatewayTurnJournal.maxEntries));

        // Without the last-resort rule this 65th write would throw forever.
        await journal.upsert(
          _entry(
            clientTurnId: _uuidFor(GatewayTurnJournal.maxEntries + 1),
            updatedAtEpochMs: now.millisecondsSinceEpoch,
          ),
          now: now,
        );
        final entries = await journal.loadAll();
        expect(entries, hasLength(GatewayTurnJournal.maxEntries));
        expect(
          entries.map((entry) => entry.clientTurnId),
          contains(_uuidFor(GatewayTurnJournal.maxEntries + 1)),
        );
        // The OLDEST quarantined entries were dropped, not the newest.
        expect(
          entries.map((entry) => entry.clientTurnId),
          isNot(contains(_uuidFor(1))),
        );
        expect(
          entries.map((entry) => entry.clientTurnId),
          contains(_uuidFor(GatewayTurnJournal.maxEntries)),
        );
      },
    );

    test(
      'young ack-uncertain entries still survive compaction and still '
      'backpressure a full journal',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        final now = DateTime.fromMillisecondsSinceEpoch(
          _baseMs + 60000,
          isUtc: true,
        );
        await journal.upsert(
          _entry(
            clientTurnId: _uuidFor(1),
            turnId: 'turn-quarantine-1',
            status: GatewayRecoveryTurnStatus.failed,
            lastSeq: 1,
            terminalEventRecorded: true,
            ackUncertain: false,
            failure: GatewayTurnRecoveryFailure.turnUnknown,
            updatedAtEpochMs: _baseMs + 1,
          ),
          now: now,
        );
        await journal.upsert(
          _entry(
            clientTurnId: _uuidFor(2),
            ackUncertain: true,
            updatedAtEpochMs: _baseMs + 2,
          ),
          now: now,
        );
        final compacted = await journal.compact(now: now);
        expect(compacted.entries, hasLength(2));

        // Fill the rest with young ack-uncertain (genuinely pending)
        // entries. A 65th write must NOT throw forever: it evicts the
        // oldest quarantine entry and keeps every pending one.
        for (var index = 3; index <= GatewayTurnJournal.maxEntries; index += 1) {
          await journal.upsert(
            _entry(
              clientTurnId: _uuidFor(index),
              ackUncertain: true,
              updatedAtEpochMs: now.millisecondsSinceEpoch - 10000 + index,
            ),
            now: now,
          );
        }
        await journal.upsert(
          _entry(
            clientTurnId: _uuidFor(GatewayTurnJournal.maxEntries + 1),
            updatedAtEpochMs: now.millisecondsSinceEpoch,
          ),
          now: now,
        );
        final after = await journal.loadAll();
        expect(after, hasLength(GatewayTurnJournal.maxEntries));
        expect(
          after.map((entry) => entry.clientTurnId),
          isNot(contains(_uuidFor(1))),
        );
        for (var index = 2; index <= GatewayTurnJournal.maxEntries + 1; index += 1) {
          expect(
            after.map((entry) => entry.clientTurnId),
            contains(_uuidFor(index)),
          );
        }
      },
    );

    test(
      'quarantine survives below capacity and evicts oldest-first under '
      'pressure only',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        final now = DateTime.fromMillisecondsSinceEpoch(
          _baseMs + GatewayTurnJournal.activeRetention.inMilliseconds + 1000,
          isUtc: true,
        );
        // An ancient ack-uncertain entry survives compaction while the
        // journal is below capacity — quarantine is durable by design.
        await journal.upsert(
          _entry(
            clientTurnId: _uuidFor(1),
            ackUncertain: true,
            updatedAtEpochMs: _baseMs,
          ),
          now: now,
        );
        final compacted = await journal.compact(now: now);
        expect(compacted.entries, hasLength(1));
        expect(compacted.entries.single.clientTurnId, _uuidFor(1));
      },
    );

    test('never evicts a binding referenced by an active turn', () async {
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      for (var index = 1; index <= GatewayTurnJournal.maxBindings; index += 1) {
        final binding = _binding(
          connectionId: 'connection-$index',
          localSessionId: 'local-$index',
          mobileSessionId: _uuidFor(index),
          storedSessionId: 'stored-$index',
          updatedAtEpochMs: _baseMs + index,
        );
        await journal.upsertBinding(binding);
        await journal.upsert(
          _entry(
            binding: binding,
            clientTurnId: _uuidFor(index),
            updatedAtEpochMs: _baseMs + index,
          ),
        );
      }
      final before = store.value;
      await expectLater(
        journal.upsertBinding(
          _binding(
            connectionId: 'connection-overflow',
            localSessionId: 'local-overflow',
            mobileSessionId: _uuidFor(65),
            storedSessionId: 'stored-overflow',
            updatedAtEpochMs: _baseMs + 65,
          ),
        ),
        throwsA(isA<GatewayTurnJournalException>()),
      );
      expect(store.value, before);
      expect(
        (await journal.loadSnapshot()).bindings,
        hasLength(GatewayTurnJournal.maxBindings),
      );
    });

    test(
      'advances byte cursor monotonically and restores it after restart',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        await journal.upsert(_entry());
        await journal.upsert(
          _entry(
            turnId: 'turn-byte-cursor',
            status: GatewayRecoveryTurnStatus.accepted,
            lastSeq: 1,
            eventPayloadBytes: 41,
            ackUncertain: false,
            updatedAtEpochMs: _baseMs + 1,
          ),
          now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 1, isUtc: true),
        );

        final restarted = GatewayTurnJournal(store: store);
        expect((await restarted.loadAll()).single.eventPayloadBytes, 41);
        await expectLater(
          restarted.upsert(
            _entry(
              turnId: 'turn-byte-cursor',
              status: GatewayRecoveryTurnStatus.running,
              lastSeq: 2,
              eventPayloadBytes: 40,
              ackUncertain: false,
              updatedAtEpochMs: _baseMs + 2,
            ),
          ),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect((await restarted.loadAll()).single.eventPayloadBytes, 41);
      },
    );

    test(
      'records terminal-event evidence monotonically across restart',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        await journal.upsert(
          _entry(
            turnId: 'turn-terminal-event',
            status: GatewayRecoveryTurnStatus.running,
            lastSeq: 1,
            eventPayloadBytes: 40,
            ackUncertain: false,
          ),
        );
        await journal.upsert(
          _entry(
            turnId: 'turn-terminal-event',
            status: GatewayRecoveryTurnStatus.completed,
            lastSeq: 2,
            eventPayloadBytes: 88,
            terminalEventRecorded: true,
            ackUncertain: false,
            updatedAtEpochMs: _baseMs + 1,
          ),
          now: DateTime.fromMillisecondsSinceEpoch(_baseMs + 1, isUtc: true),
        );

        final restarted = GatewayTurnJournal(store: store);
        final terminal = (await restarted.loadAll()).single;
        expect(terminal.terminalEventRecorded, isTrue);
        await expectLater(
          restarted.upsert(
            _entry(
              turnId: 'turn-terminal-event',
              status: GatewayRecoveryTurnStatus.completed,
              lastSeq: 2,
              eventPayloadBytes: 88,
              terminalEventRecorded: false,
              ackUncertain: false,
              updatedAtEpochMs: _baseMs + 2,
            ),
          ),
          throwsA(isA<GatewayTurnJournalException>()),
        );

        final messageCompleteOnly = _entry(
          clientTurnId: _uuidFor(2),
          turnId: 'turn-message-complete-only',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 1,
          eventPayloadBytes: 44,
          terminalEventRecorded: false,
          ackUncertain: false,
        );
        expect(messageCompleteOnly.terminalEventRecorded, isFalse);
      },
    );

    test('accepts canonical persisted UUID versions one through eight', () {
      for (var version = 1; version <= 8; version += 1) {
        final mobile = '123e4567-e89b-${version}12d-a456-426614174000';
        final client = '223e4567-e89b-${version}12d-b456-426614174000';
        final binding = _binding(
          localSessionId: 'local-v$version',
          mobileSessionId: mobile,
        );
        expect(binding.mobileSessionId, mobile);
        expect(
          _entry(binding: binding, clientTurnId: client).clientTurnId,
          client,
        );
      }

      for (final invalid in <String>[
        '123e4567-e89b-012d-a456-426614174000',
        '123e4567-e89b-912d-a456-426614174000',
        '123e4567-e89b-412d-7456-426614174000',
        '123E4567-E89B-412D-A456-426614174000',
        '{123e4567-e89b-412d-a456-426614174000}',
        '123e4567e89b412da456426614174000',
        '00000000-0000-0000-0000-000000000000',
      ]) {
        expect(() => _binding(mobileSessionId: invalid), throwsArgumentError);
        expect(() => _entry(clientTurnId: invalid), throwsArgumentError);
      }
    });

    test(
      'writes a closed metadata-only schema with no sensitive fields',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        await _seedBinding(journal);
        await journal.upsert(
          _entry(
            turnId: 'turn-schema',
            status: GatewayRecoveryTurnStatus.running,
            lastSeq: 4,
            eventPayloadBytes: 404,
            ackUncertain: false,
            failure: GatewayTurnRecoveryFailure.protocolViolation,
          ),
        );

        final root = jsonDecode(store.value!) as Map<String, dynamic>;
        expect(root.keys.toSet(), <String>{'schema', 'bindings', 'entries'});
        final binding =
            (root['bindings'] as List).single as Map<String, dynamic>;
        final entry = (root['entries'] as List).single as Map<String, dynamic>;
        expect(binding.keys.toSet(), GatewayTurnJournalBinding.allowedJsonKeys);
        expect(
          entry.keys.toSet(),
          GatewayTurnJournalEntry.allowedJsonKeys.difference(const <String>{
            'terminal_result',
          }),
        );
        expect(entry['event_payload_bytes'], 404);
        expect(entry['terminal_event_recorded'], isFalse);
        expect(entry['failure'], 'protocolViolation');
        for (final forbidden in <String>{
          'runtime_session_id',
          'session_id',
          'prompt',
          'prompt_text',
          'output',
          'assistant_text',
          'event_payload',
          'token',
          'credential',
          'attachment_bytes',
        }) {
          expect(binding, isNot(contains(forbidden)));
          expect(entry, isNot(contains(forbidden)));
        }
      },
    );

    test('rejects noncanonical identities before touching storage', () {
      expect(
        () => _binding(endpointDigest: _digestA.toUpperCase()),
        throwsArgumentError,
      );
      expect(
        () => _binding(mobileSessionId: 'not-a-uuid'),
        throwsArgumentError,
      );
      expect(() => _entry(clientTurnId: 'not-a-uuid'), throwsArgumentError);
      expect(
        () => _entry(
          ackUncertain: true,
          failure: GatewayTurnRecoveryFailure.protocolViolation,
        ),
        throwsArgumentError,
      );
      for (final invalid in <GatewayTurnJournalEntry Function()>[
        () => _entry(
          turnId: 'turn-running',
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 1,
          terminalEventRecorded: true,
          ackUncertain: false,
        ),
        () => _entry(
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 1,
          terminalEventRecorded: true,
          ackUncertain: false,
        ),
        () => _entry(
          turnId: 'turn-zero-seq',
          status: GatewayRecoveryTurnStatus.completed,
          terminalEventRecorded: true,
          ackUncertain: false,
        ),
      ]) {
        expect(invalid, throwsArgumentError);
      }
    });
  });
}
