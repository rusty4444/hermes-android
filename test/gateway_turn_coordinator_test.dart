import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';

const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _mobileA = '11111111-1111-4111-8111-111111111111';
const _mobileB = '22222222-2222-4222-8222-222222222222';
const _clientA = '33333333-3333-4333-8333-333333333333';
const _clientB = '44444444-4444-4444-8444-444444444444';
const _baseMs = 2000000000000;

class _MemoryJournalStore implements GatewayTurnJournalStore {
  String? value;
  bool failNextWrite = false;

  @override
  Future<void> delete() async {
    value = null;
  }

  @override
  Future<void> deleteLegacy() async {}

  @override
  Future<String?> read() async => value;

  @override
  Future<String?> readLegacy() async => null;

  @override
  Future<void> write(String newValue) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('synthetic write failure');
    }
    value = newValue;
  }
}

class _VoiceAdmissionJournalStore extends _MemoryJournalStore {
  final written = Completer<void>();
  final release = Completer<void>();
  bool held = false;
  @override
  Future<void> write(String newValue) async {
    await super.write(newValue);
    if (!held && newValue.contains(_clientA)) {
      held = true;
      written.complete();
      await release.future;
    }
  }
}

class _CrashJournalSlot {
  String? value;
  final ackSealed = Completer<void>();
}

class _CrashJournalStore implements GatewayTurnJournalStore {
  final _CrashJournalSlot slot;
  final bool crashOnAckSeal;

  _CrashJournalStore(this.slot, {this.crashOnAckSeal = false});

  @override
  Future<void> delete() async => slot.value = null;

  @override
  Future<void> deleteLegacy() async {}

  @override
  Future<String?> read() async => slot.value;

  @override
  Future<String?> readLegacy() async => null;

  @override
  Future<void> write(String newValue) async {
    slot.value = newValue;
    if (crashOnAckSeal &&
        newValue.contains('"turn_id":"turn-1"') &&
        newValue.contains('"ack_uncertain":true')) {
      if (!slot.ackSealed.isCompleted) slot.ackSealed.complete();
      // The write reached durable storage; the original process never gets
      // control back to begin reconcile.
      await Completer<void>().future;
    }
  }
}

class _SharedMemoryJournalSlot {
  final Object authority = Object();
  String? value;
  bool failNextWrite = false;
}

class _SharedMemoryJournalStore
    implements
        GatewayTurnJournalStore,
        GatewayTurnJournalSerializationAuthority {
  final _SharedMemoryJournalSlot slot;

  _SharedMemoryJournalStore(this.slot);

  @override
  Object get journalSerializationAuthority => slot.authority;

  @override
  Future<void> delete() async {
    slot.value = null;
  }

  @override
  Future<void> deleteLegacy() async {}

  @override
  Future<String?> read() async => slot.value;

  @override
  Future<String?> readLegacy() async => null;

  @override
  Future<void> write(String newValue) async {
    if (slot.failNextWrite) {
      slot.failNextWrite = false;
      throw StateError('synthetic shared write failure');
    }
    slot.value = newValue;
  }
}

typedef _RequestHandler =
    FutureOr<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int connectionIndex,
    );

class _GatewayFixture {
  final HttpServer server;
  final _RequestHandler? handler;
  final Map<String, dynamic> readyFrame;
  final List<Map<String, dynamic>> requests = [];
  final List<String> order = [];
  final List<WebSocket> _sockets = [];
  final List<Completer<void>> _socketClosed = [];
  late final StreamSubscription<WebSocket> _subscription;
  int connectionCount = 0;

  _GatewayFixture._(this.server, this.handler, this.readyFrame) {
    _subscription = server.transform(WebSocketTransformer()).listen((socket) {
      final connectionIndex = ++connectionCount;
      _sockets.add(socket);
      final closed = Completer<void>();
      _socketClosed.add(closed);
      order.add('socket');
      socket.add(jsonEncode(readyFrame));
      socket.listen(
        (raw) async {
          final request = jsonDecode(raw as String) as Map<String, dynamic>;
          // WsClient negotiates interactive server requests for every socket.
          // This fixture exercises turn recovery, so exclude that independent,
          // best-effort negotiation from turn request assertions. Dedicated
          // transport tests cover its response contract.
          if (request['method'] == 'client.capabilities') return;
          requests.add(request);
          order.add(request['method'] as String);
          final result = await (handler == null
              ? _defaultResult(request, connectionIndex)
              : handler!(request, connectionIndex));
          final fixtureError = result['__fixture_error__'];
          socket.add(
            jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': request['id'],
              if (fixtureError is Map)
                'error': fixtureError
              else
                'result': result,
            }),
          );
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!closed.isCompleted) closed.completeError(error, stack);
        },
      );
    });
  }

  static Future<_GatewayFixture> start({
    _RequestHandler? handler,
    Map<String, dynamic>? readyFrame,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _GatewayFixture._(server, handler, readyFrame ?? _readyFrame());
  }

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  void sendEvent(Map<String, dynamic> params, {int socketIndex = 0}) {
    _sockets[socketIndex].add(
      jsonEncode(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'event',
        'params': params,
      }),
    );
  }

  Future<void> closeSocket([int socketIndex = 0]) =>
      _sockets[socketIndex].close(WebSocketStatus.goingAway, 'fixture close');

  Future<void> waitForSocketClosed([int socketIndex = 0]) =>
      _socketClosed[socketIndex].future.timeout(const Duration(seconds: 5));

  Future<Map<String, dynamic>> _defaultResult(
    Map<String, dynamic> request,
    int connectionIndex,
  ) async {
    final method = request['method'];
    final params = request['params'] as Map<String, dynamic>;
    if (method == 'session.open') {
      return _openResult(
        mobileSessionId: params['mobile_session_id'] as String,
        connectionIndex: connectionIndex,
      );
    }
    if (method == 'prompt.submit') {
      return <String, dynamic>{
        'accepted': true,
        'automatic_resubmit': false,
        'client_turn_id': params['client_turn_id'],
        'turn_id': 'turn-$connectionIndex',
        'status': 'accepted',
        'last_seq': 0,
        'created': true,
      };
    }
    throw StateError('Unexpected synthetic method: $method');
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _subscription.cancel();
    await server.close(force: true);
  }
}

Map<String, dynamic> _readyFrame({Map<String, dynamic>? recovery}) =>
    <String, dynamic>{
      'jsonrpc': '2.0',
      'method': 'event',
      'params': <String, dynamic>{
        'type': 'gateway.ready',
        'payload': <String, dynamic>{
          'protocol': <String, dynamic>{'name': 'hermes-jsonrpc', 'major': 2},
          'capabilities': <String, dynamic>{
            'turn_recovery': recovery ?? _recoveryCapability(),
          },
        },
      },
    };

Map<String, dynamic> _recoveryCapability({
  int maxEventBytes = 65536,
  int maxTurnBytes = 4194304,
  int terminalEventReserveBytes = 1024,
  int reconcileMaxPageBytes = 524288,
  bool attachments = false,
}) => <String, dynamic>{
  'version': 2,
  'shadow_only': false,
  'methods': <String>[
    'session.open',
    'turn.reconcile',
    'turn.interrupt',
    if (attachments) 'attachment.detach@2',
  ],
  'prompt_submit_version': 2,
  'applies_to': <String>[
    'session.open',
    'prompt.submit@2',
    'turn.reconcile',
    'turn.interrupt',
    if (attachments) 'attachment.detach@2',
  ],
  'automatic_resubmit': false,
  'execution_route': 'single_process_in_process',
  'event_retention_seconds': 86400,
  'turn_retention_seconds': 604800,
  'max_event_bytes': maxEventBytes,
  'max_turn_bytes': maxTurnBytes,
  'terminal_event_reserve_bytes': terminalEventReserveBytes,
  'max_prompt_bytes': 65536,
  'mobile_session_id_format': 'canonical_lowercase_uuid',
  'client_turn_id_format': 'canonical_lowercase_uuid',
  'reconcile_max_events': 256,
  'reconcile_max_page_bytes': reconcileMaxPageBytes,
  if (attachments) ...<String, dynamic>{
    'max_attachments': 10,
    'max_file_attachment_bytes': 16777216,
    'max_image_attachment_bytes': 16777216,
    'max_pdf_attachment_bytes': 16777216,
    'max_attachment_registry_bytes': 67108864,
  },
};

Map<String, dynamic> _openResult({
  required String mobileSessionId,
  required int connectionIndex,
  String? storedSessionId,
  int bindingVersion = 1,
  Map<String, dynamic>? recovery,
}) => <String, dynamic>{
  'runtime_session_id': 'runtime-$connectionIndex',
  'stored_session_id': storedSessionId ?? 'stored-$connectionIndex',
  'mobile_session_id': mobileSessionId,
  'binding_version': bindingVersion,
  'turn_recovery': true,
  'automatic_resubmit': false,
  'capabilities': <String, dynamic>{
    'turn_recovery': recovery ?? _recoveryCapability(),
  },
};

GatewayTurnJournalBinding _binding({
  String localSessionId = 'local-a',
  String mobileSessionId = _mobileA,
  String storedSessionId = 'stored-a',
  int bindingVersion = 1,
}) => GatewayTurnJournalBinding(
  connectionId: 'connection-a',
  endpointDigest: _digest,
  localSessionId: localSessionId,
  mobileSessionId: mobileSessionId,
  storedSessionId: storedSessionId,
  bindingVersion: bindingVersion,
  updatedAtEpochMs: _baseMs,
);

GatewayTurnJournalEntry _entry({
  required GatewayTurnJournalBinding binding,
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
  bindingIdentity: binding.bindingIdentity,
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

GatewayTurnCoordinator _coordinator({
  required _GatewayFixture fixture,
  required GatewayTurnJournal journal,
  GatewayTurnIdFactory? uuidFactory,
  GatewayTurnClock? clock,
  String localSessionId = 'local-a',
}) => GatewayTurnCoordinator(
  connectionId: 'connection-a',
  endpointDigest: _digest,
  localSessionId: localSessionId,
  journal: journal,
  freshSocketFactory: () async => WsClient(fixture.baseUrl),
  uuidFactory: uuidFactory ?? (() => _clientA),
  clock:
      clock ??
      (() => DateTime.fromMillisecondsSinceEpoch(_baseMs + 1000, isUtc: true)),
);

String _uuidFor(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

Map<String, dynamic> _reconcilePage({
  required String turnId,
  required String status,
  required int lastSeq,
  required List<Map<String, dynamic>> events,
  required bool hasMore,
  required int nextAfterSeq,
}) => <String, dynamic>{
  'mode': 'events',
  'turn_id': turnId,
  'status': status,
  'earliest_seq': 1,
  'last_seq': lastSeq,
  'events': events,
  'has_more': hasMore,
  'next_after_seq': nextAfterSeq,
  'automatic_resubmit': false,
};

Map<String, dynamic> _snapshotPage({
  required String clientTurnId,
  required String text,
}) => <String, dynamic>{
  'mode': 'snapshot',
  'earliest_seq': 1,
  'last_seq': 1,
  'next_after_seq': 1,
  'has_more': false,
  'automatic_resubmit': false,
  'snapshot': <String, dynamic>{
    'turn_id': 'turn-1',
    'client_turn_id': clientTurnId,
    'status': 'completed',
    'last_seq': 1,
    'assistant': <String, dynamic>{
      'message_id': 'snapshot-message',
      'text': text,
      'complete': true,
    },
    'attachment_manifest_digest': _digest,
    'final_message_ref': 1,
  },
};

Map<String, dynamic> _turnEvent({
  required String turnId,
  required int seq,
  required String type,
  required Map<String, dynamic> payload,
}) => <String, dynamic>{
  'turn_id': turnId,
  'seq': seq,
  'message_id': 'message-$seq',
  'type': type,
  'payload': payload,
};

Map<String, dynamic> _rpcError(String reason) => <String, dynamic>{
  '__fixture_error__': <String, dynamic>{
    'code': -32600,
    'message': 'synthetic definitive rejection',
    'data': <String, dynamic>{'reason': reason},
  },
};

Map<String, dynamic> _liveEventParams({
  required String type,
  required String turnId,
  required int seq,
  required Map<String, dynamic> payload,
  String sessionId = 'runtime-1',
}) => <String, dynamic>{
  'type': type,
  'session_id': sessionId,
  'turn_id': turnId,
  'seq': seq,
  'message_id': 'live-message-$seq',
  'payload': payload,
};

Future<void> _expectBadSecondReconcilePage({required bool crossTurn}) async {
  var reconcileCount = 0;
  late _GatewayFixture fixture;
  fixture = await _GatewayFixture.start(
    handler: (request, connectionIndex) {
      final params = request['params'] as Map<String, dynamic>;
      if (request['method'] == 'session.open') {
        return _openResult(
          mobileSessionId: params['mobile_session_id'] as String,
          connectionIndex: connectionIndex,
        );
      }
      if (request['method'] == 'prompt.submit') {
        // Incomplete ACK: the connected client may reconcile only.
        return <String, dynamic>{'accepted': true};
      }
      if (request['method'] == 'turn.reconcile') {
        reconcileCount += 1;
        if (reconcileCount == 1) {
          return _reconcilePage(
            turnId: 'turn-a',
            status: 'running',
            lastSeq: 2,
            events: <Map<String, dynamic>>[
              _turnEvent(
                turnId: 'turn-a',
                seq: 1,
                type: 'message.start',
                payload: <String, dynamic>{},
              ),
            ],
            hasMore: true,
            nextAfterSeq: 1,
          );
        }
        if (crossTurn) {
          return _reconcilePage(
            turnId: 'turn-b',
            status: 'completed',
            lastSeq: 2,
            events: <Map<String, dynamic>>[
              _turnEvent(
                turnId: 'turn-b',
                seq: 2,
                type: 'message.complete',
                payload: <String, dynamic>{
                  'text': 'wrong turn',
                  'status': 'completed',
                },
              ),
            ],
            hasMore: false,
            nextAfterSeq: 2,
          );
        }
        return _reconcilePage(
          turnId: 'turn-a',
          status: 'running',
          lastSeq: 2,
          events: <Map<String, dynamic>>[],
          hasMore: true,
          nextAfterSeq: 1,
        );
      }
      throw StateError('Unexpected method ${request['method']}');
    },
  );
  final coordinator = _coordinator(
    fixture: fixture,
    journal: GatewayTurnJournal(store: _MemoryJournalStore()),
  );

  try {
    await expectLater(
      coordinator.submit(text: 'adversarial page'),
      throwsA(
        isA<GatewayTurnCoordinatorException>().having(
          (error) => error.failure,
          'failure',
          GatewayTurnCoordinatorFailure.invalidResponse,
        ),
      ),
    );
    expect(
      fixture.requests.where((request) => request['method'] == 'prompt.submit'),
      hasLength(1),
    );
    expect(
      fixture.requests.where(
        (request) => request['method'] == 'turn.reconcile',
      ),
      hasLength(2),
    );
  } finally {
    await coordinator.close();
    await fixture.close();
  }
}

Future<void> _expectPoisonStopsAllWire(
  GatewayTurnCoordinator coordinator,
  _GatewayFixture fixture,
) async {
  final requestCount = fixture.requests.length;
  for (final action in <Future<Object?> Function()>[
    () => coordinator.ensureOpen(),
    () => coordinator.recoverPending(),
    () => coordinator.submit(text: 'must not reach wire'),
    () => coordinator.interrupt(_clientA),
  ]) {
    await expectLater(
      action(),
      throwsA(
        isA<GatewayTurnCoordinatorException>().having(
          (error) => error.failure,
          'failure',
          GatewayTurnCoordinatorFailure.invalidResponse,
        ),
      ),
    );
  }
  expect(fixture.requests, hasLength(requestCount));
}

Future<void> _triggerDefinitiveProcessPoison({
  required GatewayTurnCoordinator coordinator,
  required _GatewayFixture fixture,
  required Completer<void> promptSeen,
  required Completer<void> releaseError,
  required void Function() failNextWrite,
}) async {
  final pending = coordinator.submit(text: 'definitive process poison');
  final assertion = expectLater(
    pending,
    throwsA(isA<GatewayTurnJournalException>()),
  );
  await promptSeen.future.timeout(const Duration(seconds: 5));
  failNextWrite();
  releaseError.complete();
  await assertion;
  await fixture.waitForSocketClosed();
  await coordinator.waitForIdle();
  expect(coordinator.retentionSnapshot.poisoned, isTrue);
}

void _expectPayloadFreePoison(GatewayTurnRecoveryState? failure) {
  expect(failure, isNotNull);
  expect(failure!.isFailClosed, isTrue);
  expect(failure.eventsBySeq, isEmpty);
  expect(failure.snapshot, isNull);
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test(
    'HF05 revoked local voice consent after durable write never emits prompt.submit',
    () async {
      final fixture = await _GatewayFixture.start();
      final store = _VoiceAdmissionJournalStore();
      var current = true;
      var nextId = 0;
      final coordinator = _coordinator(
        fixture: fixture,
        journal: GatewayTurnJournal(store: store),
        uuidFactory: () => nextId++ == 0 ? _clientA : _clientB,
      );
      try {
        final submission = coordinator.submit(
          text: 'fixture voice prompt',
          maySubmit: () => current,
        );
        final rejected = expectLater(
          submission,
          throwsA(isA<GatewayTurnAdmissionRevoked>()),
        );
        await store.written.future;
        current = false;
        store.release.complete();
        await rejected;
        expect(
          fixture.requests.where(
            (request) => request['method'] == 'prompt.submit',
          ),
          isEmpty,
        );
        expect(
          (jsonDecode(store.value!) as Map<String, dynamic>)['entries'],
          isEmpty,
        );
        expect(coordinator.stateFor(_clientA), isNull);
        current = true;
        await coordinator.submit(
          text: 'later explicit prompt',
          maySubmit: () => current,
        );
        expect(
          fixture.requests.where(
            (request) => request['method'] == 'prompt.submit',
          ),
          hasLength(1),
        );
      } finally {
        if (!store.release.isCompleted) store.release.complete();
        await coordinator.close();
        await fixture.close();
      }
    },
  );
  test(
    'registry binding listeners are session-scoped and token-owned',
    () async {
      final fixture = await _GatewayFixture.start();
      final registry = GatewayTurnCoordinatorRegistry(
        connectionId: 'connection-a',
        endpointDigest: _digest,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        freshSocketFactory: () async => WsClient(fixture.baseUrl),
      );
      final delivered = <(String, String, String)>[];
      final oldA = registry.setSessionBoundListener(
        'local-a',
        (local, stored) => delivered.add(('stale-a', local, stored)),
      );
      final currentA = registry.setSessionBoundListener(
        'local-a',
        (local, stored) => delivered.add(('current-a', local, stored)),
      );
      // A late dispose from the replaced route must not remove its successor.
      registry.removeSessionBoundListener('local-a', oldA);
      registry.setSessionBoundListener(
        'local-b',
        (local, stored) => delivered.add(('session-b', local, stored)),
      );

      try {
        await registry.open('local-a');
        await registry.open('local-b');

        expect(delivered, [
          ('current-a', 'local-a', 'stored-1'),
          ('session-b', 'local-b', 'stored-2'),
        ]);

        registry.setSessionBoundListener(
          'local-a',
          (local, stored) => delivered.add(('replacement-a', local, stored)),
        );
        registry.removeSessionBoundListener('local-a', currentA);
        expect(delivered.last, ('replacement-a', 'local-a', 'stored-1'));
      } finally {
        await registry.closeAll();
        await fixture.close();
      }
    },
  );

  test(
    'registry settlement listeners are session-scoped and token-owned',
    () async {
      final fixture = await _GatewayFixture.start();
      var uuidIndex = 0;
      final registry = GatewayTurnCoordinatorRegistry(
        connectionId: 'connection-a',
        endpointDigest: _digest,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        freshSocketFactory: () async => WsClient(fixture.baseUrl),
        uuidFactory: () => _uuidFor(++uuidIndex),
      );
      final delivered = <String>[];
      final oldA = registry.setTurnSettledListener(
        'local-a',
        (_) => delivered.add('stale-a'),
      );
      registry.setTurnSettledListener(
        'local-a',
        (_) => delivered.add('current-a'),
      );
      // A late dispose from the replaced route must not remove its successor.
      registry.removeTurnSettledListener('local-a', oldA);
      final sessionB = registry.setTurnSettledListener(
        'local-b',
        (_) => delivered.add('session-b'),
      );

      try {
        final stateA = await registry.submit(
          localSessionId: 'local-a',
          text: 'alpha',
        );
        final stateB = await registry.submit(
          localSessionId: 'local-b',
          text: 'beta',
        );
        registry.removeTurnSettledListener('local-b', sessionB);

        fixture.sendEvent(
          _liveEventParams(
            type: 'message.start',
            turnId: stateA.turnId!,
            seq: 1,
            payload: <String, dynamic>{},
          ),
        );
        fixture.sendEvent(
          _liveEventParams(
            type: 'turn.status',
            turnId: stateA.turnId!,
            seq: 2,
            payload: <String, dynamic>{'status': 'completed'},
          ),
        );
        fixture.sendEvent(
          _liveEventParams(
            type: 'message.start',
            turnId: stateB.turnId!,
            seq: 1,
            payload: <String, dynamic>{},
            sessionId: 'runtime-2',
          ),
          socketIndex: 1,
        );
        fixture.sendEvent(
          _liveEventParams(
            type: 'turn.status',
            turnId: stateB.turnId!,
            seq: 2,
            payload: <String, dynamic>{'status': 'completed'},
            sessionId: 'runtime-2',
          ),
          socketIndex: 1,
        );

        await _waitFor(() => delivered.isNotEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(delivered, ['current-a']);
      } finally {
        await registry.closeAll();
        await fixture.close();
      }
    },
  );

  test(
    'registry reports active turns and notifies activity listeners',
    () async {
      final fixture = await _GatewayFixture.start();
      var uuidIndex = 0;
      final registry = GatewayTurnCoordinatorRegistry(
        connectionId: 'connection-a',
        endpointDigest: _digest,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        freshSocketFactory: () async => WsClient(fixture.baseUrl),
        uuidFactory: () => _uuidFor(++uuidIndex),
      );
      final activity = <bool>[];
      final token = registry.addTurnActivityListener(
        () => activity.add(registry.hasActiveTurn),
      );

      try {
        expect(registry.hasActiveTurn, isFalse);

        final stateA = await registry.submit(
          localSessionId: 'local-a',
          text: 'alpha',
        );
        expect(registry.hasActiveTurn, isTrue);
        // Notifications are "may have changed" signals (submit persists via
        // _remember too), so assert every observed value, not the count.
        expect(activity, isNotEmpty);
        expect(activity.every((active) => active), isTrue);

        // A second active turn must not make the aggregate stop early.
        final stateB = await registry.submit(
          localSessionId: 'local-b',
          text: 'beta',
        );
        expect(registry.hasActiveTurn, isTrue);

        fixture.sendEvent(
          _liveEventParams(
            type: 'message.start',
            turnId: stateA.turnId!,
            seq: 1,
            payload: <String, dynamic>{},
          ),
        );
        fixture.sendEvent(
          _liveEventParams(
            type: 'turn.status',
            turnId: stateA.turnId!,
            seq: 2,
            payload: <String, dynamic>{'status': 'completed'},
          ),
        );
        await _waitFor(() => !registry.hasActiveTurn || activity.length > 1);
        // B is still unresolved: the aggregate must remain active.
        expect(registry.hasActiveTurn, isTrue);

        fixture.sendEvent(
          _liveEventParams(
            type: 'message.start',
            turnId: stateB.turnId!,
            seq: 1,
            payload: <String, dynamic>{},
            sessionId: 'runtime-2',
          ),
          socketIndex: 1,
        );
        fixture.sendEvent(
          _liveEventParams(
            type: 'turn.status',
            turnId: stateB.turnId!,
            seq: 2,
            payload: <String, dynamic>{'status': 'completed'},
            sessionId: 'runtime-2',
          ),
          socketIndex: 1,
        );
        await _waitFor(() => !registry.hasActiveTurn);
        expect(activity.last, isFalse);

        registry.removeTurnActivityListener(token);
        await registry.submit(localSessionId: 'local-c', text: 'gamma');
        expect(activity.length, lessThan(100));
        final countAfterRemoval = activity.length;
        await registry.submit(localSessionId: 'local-d', text: 'delta');
        expect(activity.length, countAfterRemoval);
      } finally {
        await registry.closeAll();
        await fixture.close();
      }
    },
  );

  test(
    'transport loss bounds the keep-alive signal while the turn stays retained',
    () async {
      // Reviewer finding: a disconnected recovery-v2 turn must not pin
      // the foreground service — there is no live socket to protect, and
      // reconcile happens on resume (never an auto-resend). The turn
      // stays journaled, but the app-wide active-turn signal must drop
      // the moment the transport is lost.
      final fixture = await _GatewayFixture.start();
      var uuidIndex = 0;
      final registry = GatewayTurnCoordinatorRegistry(
        connectionId: 'connection-a',
        endpointDigest: _digest,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        freshSocketFactory: () async => WsClient(fixture.baseUrl),
        uuidFactory: () => _uuidFor(++uuidIndex),
      );
      final activity = <bool>[];
      final token = registry.addTurnActivityListener(
        () => activity.add(registry.hasActiveTurn),
      );

      try {
        await registry.submit(localSessionId: 'local-a', text: 'alpha');
        expect(registry.hasActiveTurn, isTrue);

        await fixture.closeSocket();
        await _waitFor(() => !registry.hasActiveTurn);
        expect(activity.last, isFalse);
        // No live socket and no background reconnect loop: the signal
        // stays down until a resume-driven operation re-establishes it.
        expect(registry.hasActiveTurn, isFalse);

        registry.removeTurnActivityListener(token);
      } finally {
        await registry.closeAll();
        await fixture.close();
      }
    },
  );

  test(
    'transport loss over an already-uncertain turn still drops the signal',
    () async {
      // Reviewer gap: the loss notify must fire even when no state
      // changes. An interrupt-marked-uncertain turn has no transition
      // left to fire on socket death, so without an unconditional
      // notify the backgrounded service would pin on it forever.
      String? clientTurnId;
      final fixture = await _GatewayFixture.start(
        handler: (request, connectionIndex) {
          final params = request['params'] as Map<String, dynamic>;
          if (request['method'] == 'session.open') {
            return _openResult(
              mobileSessionId: params['mobile_session_id'] as String,
              connectionIndex: connectionIndex,
            );
          }
          if (request['method'] == 'prompt.submit') {
            return <String, dynamic>{
              'accepted': true,
              'automatic_resubmit': false,
              'client_turn_id': params['client_turn_id'],
              'turn_id': 'turn-1',
              'status': 'accepted',
              'last_seq': 0,
              'created': true,
            };
          }
          if (request['method'] == 'turn.interrupt') {
            return <String, dynamic>{
              'automatic_resubmit': false,
              'client_turn_id': clientTurnId,
              'turn_id': 'turn-1',
              'status': 'running',
              'last_seq': 0,
            };
          }
          if (request['method'] == 'turn.reconcile') {
            return _reconcilePage(
              turnId: 'turn-1',
              status: 'running',
              lastSeq: 0,
              events: <Map<String, dynamic>>[],
              hasMore: false,
              nextAfterSeq: 0,
            );
          }
          throw StateError('Unexpected method ${request['method']}');
        },
      );
      var uuidIndex = 0;
      final registry = GatewayTurnCoordinatorRegistry(
        connectionId: 'connection-a',
        endpointDigest: _digest,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        freshSocketFactory: () async => WsClient(fixture.baseUrl),
        uuidFactory: () => _uuidFor(++uuidIndex),
      );
      final activity = <bool>[];
      final token = registry.addTurnActivityListener(
        () => activity.add(registry.hasActiveTurn),
      );

      try {
        final state = await registry.submit(
          localSessionId: 'local-a',
          text: 'alpha',
        );
        clientTurnId = state.clientTurnId;
        await registry.interrupt(
          localSessionId: 'local-a',
          clientTurnId: state.clientTurnId,
        );
        // Uncertain but the socket is live: the turn still earns
        // keep-alive (reconcile reported it running, not terminal).
        expect(registry.hasActiveTurn, isTrue);
        activity.clear();

        await fixture.closeSocket();
        await _waitFor(() => activity.isNotEmpty);
        expect(registry.hasActiveTurn, isFalse);
        expect(activity.last, isFalse);

        registry.removeTurnActivityListener(token);
      } finally {
        await registry.closeAll();
        await fixture.close();
      }
    },
  );

  test(
    'coordinator reports runtime binding and preserves inherited events',
    () async {
      final fixture = await _GatewayFixture.start();
      addTearDown(fixture.close);
      final inheritedEvents = <StreamEvent>[];
      final runtimeBindings = <String, String>{};
      final coordinator =
          GatewayTurnCoordinator(
              connectionId: 'connection-a',
              endpointDigest: _digest,
              localSessionId: 'local-a',
              journal: GatewayTurnJournal(store: _MemoryJournalStore()),
              freshSocketFactory: () async {
                final client = WsClient(fixture.baseUrl);
                client.onStreamEvent = inheritedEvents.add;
                return client;
              },
              uuidFactory: () => _clientA,
              clock: () => DateTime.fromMillisecondsSinceEpoch(
                _baseMs + 1000,
                isUtc: true,
              ),
            )
            ..onRuntimeBound = (localSessionId, runtimeSessionId) {
              runtimeBindings[localSessionId] = runtimeSessionId;
            };
      addTearDown(coordinator.close);

      await coordinator.ensureOpen();
      expect(runtimeBindings, {'local-a': 'runtime-1'});

      fixture.sendEvent({
        'type': 'request.cancel',
        'session_id': 'runtime-1',
        'payload': {'id': 'srq-1', 'method': 'clarify'},
      });
      await _waitFor(() => inheritedEvents.isNotEmpty);
      expect(inheritedEvents.single.type, 'request.cancel');
    },
  );

  group('GatewayTurnRecoveryState rehydrate', () {
    test('accepts unresolved and known nonterminal durable states', () {
      final unresolved = GatewayTurnRecoveryState.rehydrate(
        clientTurnId: _clientA,
        turnId: null,
        status: null,
        lastSeq: 0,
        ackUncertain: true,
      );
      final running = GatewayTurnRecoveryState.rehydrate(
        clientTurnId: _clientA,
        turnId: 'turn-a',
        status: GatewayRecoveryTurnStatus.running,
        lastSeq: 7,
        ackUncertain: false,
      );

      expect(unresolved.isFailClosed, isFalse);
      expect(unresolved.requiredAction, GatewayTurnRecoveryAction.reconcile);
      expect(running.isFailClosed, isFalse);
      expect(running.lastSeq, 7);
      expect(running.requiredAction, GatewayTurnRecoveryAction.reconcile);
    });

    test('accepts clean terminal state without scheduling recovery', () {
      final terminal = GatewayTurnRecoveryState.rehydrate(
        clientTurnId: _clientA,
        turnId: 'turn-a',
        status: GatewayRecoveryTurnStatus.completed,
        lastSeq: 9,
        ackUncertain: false,
        terminalResult: GatewayTurnTerminalResult(
          messageId: 'message-terminal',
          assistantText: 'Durable recovery completed.',
        ),
      );

      expect(terminal.isTerminal, isTrue);
      expect(terminal.isFailClosed, isFalse);
      expect(terminal.requiredAction, GatewayTurnRecoveryAction.none);
      expect(
        terminal.terminalResult?.assistantText,
        'Durable recovery completed.',
      );
    });

    test('fails closed on impossible durable combinations', () {
      final impossible = <GatewayTurnRecoveryState>[
        GatewayTurnRecoveryState.rehydrate(
          clientTurnId: _clientA,
          turnId: null,
          status: null,
          lastSeq: 0,
          ackUncertain: false,
        ),
        GatewayTurnRecoveryState.rehydrate(
          clientTurnId: _clientA,
          turnId: null,
          status: GatewayRecoveryTurnStatus.running,
          lastSeq: 0,
          ackUncertain: true,
        ),
        GatewayTurnRecoveryState.rehydrate(
          clientTurnId: _clientA,
          turnId: null,
          status: null,
          lastSeq: 1,
          ackUncertain: true,
        ),
        GatewayTurnRecoveryState.rehydrate(
          clientTurnId: _clientA,
          turnId: 'turn-a',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 2,
          ackUncertain: true,
        ),
        GatewayTurnRecoveryState.rehydrate(
          clientTurnId: 'not-a-uuid',
          turnId: null,
          status: null,
          lastSeq: 0,
          ackUncertain: true,
        ),
      ];

      expect(
        impossible,
        everyElement(
          isA<GatewayTurnRecoveryState>()
              .having((state) => state.isFailClosed, 'fail closed', isTrue)
              .having(
                (state) => state.requiredAction,
                'action',
                GatewayTurnRecoveryAction.stopFailClosed,
              ),
        ),
      );
    });
  });

  group('GatewayTurnCoordinator durable transport', () {
    test(
      'restart preserves every durable failure and performs zero recovery writes',
      () async {
        for (final failure in GatewayTurnRecoveryFailure.values) {
          late _GatewayFixture fixture;
          fixture = await _GatewayFixture.start(
            handler: (request, connectionIndex) {
              final params = request['params'] as Map<String, dynamic>;
              if (request['method'] == 'session.open') {
                return _openResult(
                  mobileSessionId: params['mobile_session_id'] as String,
                  connectionIndex: connectionIndex,
                  storedSessionId: 'stored-a',
                  bindingVersion: 2,
                );
              }
              throw StateError('Restart must not call ${request['method']}');
            },
          );
          final journal = GatewayTurnJournal(store: _MemoryJournalStore());
          final binding = _binding();
          await journal.upsertBinding(binding);
          await journal.upsert(
            _entry(
              binding: binding,
              turnId: 'turn-${failure.name}',
              status: GatewayRecoveryTurnStatus.running,
              lastSeq: 1,
              ackUncertain: false,
              failure: failure,
            ),
          );
          final coordinator = _coordinator(fixture: fixture, journal: journal);

          try {
            await expectLater(
              coordinator.ensureOpen(),
              throwsA(
                isA<GatewayTurnCoordinatorException>().having(
                  (error) => error.failure,
                  'failure',
                  GatewayTurnCoordinatorFailure.invalidResponse,
                ),
              ),
              reason: failure.name,
            );
            expect(coordinator.stateFor(_clientA)?.failure, failure);
            expect(
              fixture.requests.map((request) => request['method']),
              <Object?>['session.open'],
              reason: failure.name,
            );
            expect(
              (await journal.loadAll()).single.failure,
              failure,
              reason: failure.name,
            );
          } finally {
            await coordinator.close();
            await fixture.close();
          }
        }
      },
    );

    test('definitive submit errors discard WAL without reconcile', () async {
      for (final reason in <String>[
        'client_turn_conflict',
        'auth_failed',
        'schema_violation',
      ]) {
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return _rpcError(reason);
            }
            throw StateError(
              'Definitive error must not call ${request['method']}',
            );
          },
        );
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          await expectLater(
            coordinator.submit(text: 'reject definitively'),
            throwsA(
              isA<JsonRpcError>().having(
                (error) => error.reason,
                'reason',
                reason,
              ),
            ),
          );
          expect(
            fixture.requests.map((request) => request['method']),
            <Object?>['session.open', 'prompt.submit'],
          );
          expect(await journal.loadAll(), isEmpty);
          expect(coordinator.stateFor(_clientA), isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      }
    });

    test(
      'journal failure during close still physically closes the socket',
      () async {
        final fixture = await _GatewayFixture.start();
        final store = _MemoryJournalStore();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: store),
        );

        try {
          await coordinator.submit(text: 'active while closing');
          store.failNextWrite = true;

          await expectLater(
            coordinator.close(),
            throwsA(isA<GatewayTurnJournalException>()),
          );
          await fixture.waitForSocketClosed();
          expect(coordinator.runtimeBinding, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'journal failure in disconnect callback is contained and closes source',
      () async {
        final fixture = await _GatewayFixture.start();
        final store = _MemoryJournalStore();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: store),
        );

        try {
          await coordinator.submit(text: 'disconnect callback');
          store.failNextWrite = true;
          await fixture.closeSocket();
          await fixture.waitForSocketClosed();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await coordinator.waitForIdle();
          expect(coordinator.runtimeBinding, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'malformed live protocol plus journal failure quarantines exact socket',
      () async {
        final fixture = await _GatewayFixture.start();
        final store = _MemoryJournalStore();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: store),
        );

        try {
          await coordinator.submit(text: 'malformed live event');
          store.failNextWrite = true;
          fixture.sendEvent(<String, dynamic>{
            'type': 'message.delta',
            'session_id': 'runtime-1',
            'turn_id': 'turn-1',
            'payload': <String, dynamic>{'text': 'missing sequence'},
          });

          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();
          expect(coordinator.runtimeBinding, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'late terminal plus journal failure quarantines exact socket',
      () async {
        final fixture = await _GatewayFixture.start();
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final terminalSeen = Completer<void>();
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          await coordinator.submit(
            text: 'terminal then late terminal',
            onState: (state) {
              if (state.terminalEventRecorded && !terminalSeen.isCompleted) {
                terminalSeen.complete();
              }
            },
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.start',
              turnId: 'turn-1',
              seq: 1,
              payload: <String, dynamic>{},
            ),
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'turn.status',
              turnId: 'turn-1',
              seq: 2,
              payload: <String, dynamic>{'status': 'completed'},
            ),
          );
          await terminalSeen.future.timeout(const Duration(seconds: 5));
          await coordinator.waitForIdle();
          expect(
            (await journal.loadAll()).single.terminalEventRecorded,
            isTrue,
          );

          store.failNextWrite = true;
          fixture.sendEvent(
            _liveEventParams(
              type: 'turn.status',
              turnId: 'turn-1',
              seq: 3,
              payload: <String, dynamic>{'status': 'completed'},
            ),
          );
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();
          expect(coordinator.runtimeBinding, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'live max_event_bytes accepts boundary and rejects plus one',
      () async {
        final recovery = _recoveryCapability(
          maxEventBytes: 32,
          maxTurnBytes: 128,
          terminalEventReserveBytes: 16,
          reconcileMaxPageBytes: 512,
        );
        for (final overflow in <bool>[false, true]) {
          late _GatewayFixture fixture;
          fixture = await _GatewayFixture.start(
            readyFrame: _readyFrame(recovery: recovery),
            handler: (request, connectionIndex) {
              final params = request['params'] as Map<String, dynamic>;
              if (request['method'] == 'session.open') {
                return _openResult(
                  mobileSessionId: params['mobile_session_id'] as String,
                  connectionIndex: connectionIndex,
                  recovery: recovery,
                );
              }
              if (request['method'] == 'prompt.submit') {
                return <String, dynamic>{
                  'accepted': true,
                  'automatic_resubmit': false,
                  'client_turn_id': params['client_turn_id'],
                  'turn_id': 'turn-1',
                  'status': 'accepted',
                  'last_seq': 0,
                  'created': true,
                };
              }
              throw StateError(
                'Unexpected byte-bound method ${request['method']}',
              );
            },
          );
          final settled = Completer<GatewayTurnRecoveryState>();
          final coordinator = _coordinator(
            fixture: fixture,
            journal: GatewayTurnJournal(store: _MemoryJournalStore()),
          );
          final text = 'x' * (overflow ? 22 : 21);
          expect(
            utf8.encode(jsonEncode(<String, dynamic>{'text': text})).length,
            overflow ? 33 : 32,
          );

          try {
            await coordinator.submit(
              text: 'live event boundary',
              onState: (state) {
                if ((state.lastSeq == 2 || state.isFailClosed) &&
                    !settled.isCompleted) {
                  settled.complete(state);
                }
              },
            );
            fixture.sendEvent(
              _liveEventParams(
                type: 'message.start',
                turnId: 'turn-1',
                seq: 1,
                payload: <String, dynamic>{},
              ),
            );
            fixture.sendEvent(
              _liveEventParams(
                type: 'message.delta',
                turnId: 'turn-1',
                seq: 2,
                payload: <String, dynamic>{'text': text},
              ),
            );
            final state = await settled.future.timeout(
              const Duration(seconds: 5),
            );
            await coordinator.waitForIdle();
            if (overflow) {
              expect(
                state.failure,
                GatewayTurnRecoveryFailure.protocolViolation,
              );
              await fixture.waitForSocketClosed();
            } else {
              expect(state.failure, isNull);
              expect(state.eventPayloadBytes, 34);
              expect(state.liveMessageId, 'live-message-2');
              expect(
                state.liveReceivedAt,
                DateTime.fromMillisecondsSinceEpoch(
                  _baseMs + 1000,
                  isUtc: true,
                ),
              );
            }
          } finally {
            await coordinator.close();
            await fixture.close();
          }
        }
      },
    );

    test(
      'replay max_event_bytes accepts boundary and rejects plus one',
      () async {
        final recovery = _recoveryCapability(
          maxEventBytes: 32,
          maxTurnBytes: 128,
          terminalEventReserveBytes: 16,
          reconcileMaxPageBytes: 512,
        );
        for (final overflow in <bool>[false, true]) {
          late _GatewayFixture fixture;
          fixture = await _GatewayFixture.start(
            readyFrame: _readyFrame(recovery: recovery),
            handler: (request, connectionIndex) {
              final params = request['params'] as Map<String, dynamic>;
              if (request['method'] == 'session.open') {
                return _openResult(
                  mobileSessionId: params['mobile_session_id'] as String,
                  connectionIndex: connectionIndex,
                  recovery: recovery,
                );
              }
              if (request['method'] == 'prompt.submit') {
                return <String, dynamic>{'accepted': true};
              }
              if (request['method'] == 'turn.reconcile') {
                final text = 'x' * (overflow ? 22 : 21);
                return _reconcilePage(
                  turnId: 'turn-1',
                  status: 'running',
                  lastSeq: 2,
                  events: <Map<String, dynamic>>[
                    _turnEvent(
                      turnId: 'turn-1',
                      seq: 1,
                      type: 'message.start',
                      payload: <String, dynamic>{},
                    ),
                    _turnEvent(
                      turnId: 'turn-1',
                      seq: 2,
                      type: 'message.delta',
                      payload: <String, dynamic>{'text': text},
                    ),
                  ],
                  hasMore: false,
                  nextAfterSeq: 2,
                );
              }
              throw StateError('Unexpected replay method ${request['method']}');
            },
          );
          final journal = GatewayTurnJournal(store: _MemoryJournalStore());
          final coordinator = _coordinator(fixture: fixture, journal: journal);

          try {
            if (overflow) {
              await expectLater(
                coordinator.submit(text: 'replay overflow'),
                throwsA(
                  isA<GatewayTurnCoordinatorException>().having(
                    (error) => error.failure,
                    'failure',
                    GatewayTurnCoordinatorFailure.invalidResponse,
                  ),
                ),
              );
              expect(
                (await journal.loadAll()).single.failure,
                GatewayTurnRecoveryFailure.protocolViolation,
              );
            } else {
              final state = await coordinator.submit(text: 'replay boundary');
              expect(state.failure, isNull);
              expect(state.eventPayloadBytes, 34);
            }
            expect(
              fixture.requests.where(
                (request) => request['method'] == 'prompt.submit',
              ),
              hasLength(1),
            );
          } finally {
            await coordinator.close();
            await fixture.close();
          }
        }
      },
    );

    test(
      'terminal reserve reaches cumulative boundary and survives restart',
      () async {
        final recovery = _recoveryCapability(
          maxEventBytes: 64,
          maxTurnBytes: 62,
          terminalEventReserveBytes: 22,
          reconcileMaxPageBytes: 512,
        );
        final firstFixture = await _GatewayFixture.start(
          readyFrame: _readyFrame(recovery: recovery),
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                recovery: recovery,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'turn-1',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError(
              'Unexpected cumulative method ${request['method']}',
            );
          },
        );
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final terminalSeen = Completer<GatewayTurnRecoveryState>();
        final first = _coordinator(fixture: firstFixture, journal: journal);
        final deltaText = 'x' * 27;
        expect(
          utf8.encode(jsonEncode(<String, dynamic>{'text': deltaText})).length,
          38,
        );
        expect(
          utf8
              .encode(jsonEncode(<String, dynamic>{'status': 'completed'}))
              .length,
          22,
        );

        try {
          await first.submit(
            text: 'cumulative boundary',
            onState: (state) {
              if (state.terminalEventRecorded && !terminalSeen.isCompleted) {
                terminalSeen.complete(state);
              }
            },
          );
          firstFixture.sendEvent(
            _liveEventParams(
              type: 'message.start',
              turnId: 'turn-1',
              seq: 1,
              payload: <String, dynamic>{},
            ),
          );
          firstFixture.sendEvent(
            _liveEventParams(
              type: 'message.delta',
              turnId: 'turn-1',
              seq: 2,
              payload: <String, dynamic>{'text': deltaText},
            ),
          );
          firstFixture.sendEvent(
            _liveEventParams(
              type: 'turn.status',
              turnId: 'turn-1',
              seq: 3,
              payload: <String, dynamic>{'status': 'completed'},
            ),
          );
          final terminal = await terminalSeen.future.timeout(
            const Duration(seconds: 5),
          );
          await first.waitForIdle();
          expect(terminal.eventPayloadBytes, 62);
          expect(terminal.terminalEventRecorded, isTrue);
          await first.close();
          await firstFixture.close();

          late _GatewayFixture restartFixture;
          restartFixture = await _GatewayFixture.start(
            readyFrame: _readyFrame(recovery: recovery),
            handler: (request, connectionIndex) {
              final params = request['params'] as Map<String, dynamic>;
              if (request['method'] == 'session.open') {
                return _openResult(
                  mobileSessionId: params['mobile_session_id'] as String,
                  connectionIndex: connectionIndex,
                  storedSessionId: 'stored-1',
                  bindingVersion: 2,
                  recovery: recovery,
                );
              }
              throw StateError(
                'Terminal restart must not call ${request['method']}',
              );
            },
          );
          final restarted = _coordinator(
            fixture: restartFixture,
            journal: journal,
            uuidFactory: () => _clientB,
          );
          try {
            await restarted.ensureOpen();
            final state = restarted.stateFor(_clientA)!;
            expect(state.lastSeq, 3);
            expect(state.eventPayloadBytes, 62);
            expect(state.terminalEventRecorded, isTrue);
            expect(state.requiredAction, GatewayTurnRecoveryAction.none);
            expect(
              restartFixture.requests.map((request) => request['method']),
              <Object?>['session.open'],
            );
          } finally {
            await restarted.close();
            await restartFixture.close();
          }
        } finally {
          await first.close();
          await firstFixture.close();
        }
      },
    );

    test(
      'nonterminal cumulative plus one cannot consume terminal reserve',
      () async {
        final recovery = _recoveryCapability(
          maxEventBytes: 64,
          maxTurnBytes: 62,
          terminalEventReserveBytes: 22,
          reconcileMaxPageBytes: 512,
        );
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          readyFrame: _readyFrame(recovery: recovery),
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                recovery: recovery,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'turn-1',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError('Unexpected reserve method ${request['method']}');
          },
        );
        final failed = Completer<GatewayTurnRecoveryState>();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        );

        try {
          await coordinator.submit(
            text: 'reserve plus one',
            onState: (state) {
              if (state.isFailClosed && !failed.isCompleted) {
                failed.complete(state);
              }
            },
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.start',
              turnId: 'turn-1',
              seq: 1,
              payload: <String, dynamic>{},
            ),
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.delta',
              turnId: 'turn-1',
              seq: 2,
              payload: <String, dynamic>{'text': 'x' * 28},
            ),
          );
          final state = await failed.future.timeout(const Duration(seconds: 5));
          expect(state.eventPayloadBytes, 2);
          expect(state.failure, GatewayTurnRecoveryFailure.protocolViolation);
          await fixture.waitForSocketClosed();
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'message.complete cannot consume turn.status terminal reserve',
      () async {
        final recovery = _recoveryCapability(
          maxEventBytes: 64,
          maxTurnBytes: 72,
          terminalEventReserveBytes: 32,
          reconcileMaxPageBytes: 512,
        );
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          readyFrame: _readyFrame(recovery: recovery),
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                recovery: recovery,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'turn-1',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError(
              'Unexpected terminal reserve method ${request['method']}',
            );
          },
        );
        final failed = Completer<GatewayTurnRecoveryState>();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        );
        final completePayload = <String, dynamic>{
          'text': '',
          'status': 'completed',
        };
        expect(utf8.encode(jsonEncode(completePayload)).length, 32);

        try {
          await coordinator.submit(
            text: 'message complete has no reserve',
            onState: (state) {
              if (state.isFailClosed && !failed.isCompleted) {
                failed.complete(state);
              }
            },
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.start',
              turnId: 'turn-1',
              seq: 1,
              payload: <String, dynamic>{},
            ),
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.delta',
              turnId: 'turn-1',
              seq: 2,
              payload: <String, dynamic>{'text': 'x' * 27},
            ),
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.complete',
              turnId: 'turn-1',
              seq: 3,
              payload: completePayload,
            ),
          );
          final state = await failed.future.timeout(const Duration(seconds: 5));
          expect(state.eventPayloadBytes, 40);
          expect(state.terminalEventRecorded, isFalse);
          expect(state.failure, GatewayTurnRecoveryFailure.protocolViolation);
          await fixture.waitForSocketClosed();
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'more than 64 terminal turns remain bounded and payload free',
      () async {
        var promptCount = 0;
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              promptCount += 1;
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'bounded-turn-$promptCount',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError('Unexpected bounded method ${request['method']}');
          },
        );
        var uuidIndex = 0;
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
          uuidFactory: () => _uuidFor(++uuidIndex),
        );
        final clientIds = <String>[];
        final turnIds = <String>[];

        try {
          for (
            var index = 0;
            index < GatewayTurnCoordinator.maxSettledTombstones + 2;
            index += 1
          ) {
            final terminalSeen = Completer<void>();
            final submitted = await coordinator.submit(
              text: 'bounded turn $index',
              onState: (state) {
                if (state.isTerminal && !terminalSeen.isCompleted) {
                  terminalSeen.complete();
                }
              },
            );
            clientIds.add(submitted.clientTurnId);
            turnIds.add(submitted.turnId!);
            fixture.sendEvent(
              _liveEventParams(
                type: 'message.start',
                turnId: submitted.turnId!,
                seq: 1,
                payload: <String, dynamic>{},
              ),
            );
            fixture.sendEvent(
              _liveEventParams(
                type: 'turn.status',
                turnId: submitted.turnId!,
                seq: 2,
                payload: <String, dynamic>{'status': 'completed'},
              ),
            );
            await terminalSeen.future.timeout(const Duration(seconds: 5));
            await coordinator.waitForIdle();
          }

          final bounded = coordinator.retentionSnapshot;
          expect(bounded.activeStates, 0);
          expect(bounded.settledTombstones, 64);
          expect(bounded.observers, 0);
          expect(bounded.activeTurnMappings, 0);
          expect(bounded.durableTimestampFloors, 0);
          expect(bounded.retainedEventCount, 0);
          expect(bounded.retainedSnapshots, 0);
          expect(coordinator.stateFor(clientIds.first), isNull);
          expect(coordinator.stateFor(clientIds[1]), isNull);
          final newest = coordinator.stateFor(clientIds.last)!;
          expect(newest.status, GatewayRecoveryTurnStatus.completed);
          expect(newest.failure, isNull);
          expect(newest.events, isEmpty);
          expect(newest.snapshot, isNull);

          fixture.sendEvent(<String, dynamic>{
            'type': 'message.delta',
            'session_id': 'runtime-1',
            'turn_id': turnIds.last,
            'payload': <String, dynamic>{'text': 'late malformed'},
          });
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();
          final afterFault = coordinator.stateFor(clientIds.last)!;
          expect(afterFault.status, GatewayRecoveryTurnStatus.completed);
          expect(afterFault.failure, isNull);
          expect(coordinator.retentionSnapshot.settledTombstones, 64);

          await coordinator.close();
          final released = coordinator.retentionSnapshot;
          expect(released.activeStates, 0);
          expect(released.settledTombstones, 0);
          expect(released.observers, 0);
          expect(released.retainedEventCount, 0);
          expect(released.retainedSnapshots, 0);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'correlated fault fails target and only disconnects other active',
      () async {
        var promptCount = 0;
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              promptCount += 1;
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'correlated-turn-$promptCount',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError(
              'Unexpected correlated method ${request['method']}',
            );
          },
        );
        var uuidIndex = 100;
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final coordinator = _coordinator(
          fixture: fixture,
          journal: journal,
          uuidFactory: () => _uuidFor(++uuidIndex),
        );

        try {
          final target = await coordinator.submit(text: 'correlated target');
          final other = await coordinator.submit(text: 'correlated survivor');
          fixture.sendEvent(<String, dynamic>{
            'type': 'message.delta',
            'session_id': 'runtime-1',
            'turn_id': target.turnId,
            'payload': <String, dynamic>{'text': 'missing seq'},
          });
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();

          expect(
            coordinator.stateFor(target.clientTurnId)?.failure,
            GatewayTurnRecoveryFailure.protocolViolation,
          );
          final survivor = coordinator.stateFor(other.clientTurnId)!;
          expect(survivor.failure, isNull);
          expect(survivor.ackUncertain, isTrue);
          expect(survivor.requiredAction, GatewayTurnRecoveryAction.reconcile);
          final retained = coordinator.retentionSnapshot;
          expect(retained.activeStates, 1);
          expect(retained.settledTombstones, 1);
          expect(retained.activeTurnMappings, 1);
          final durable = await journal.loadAll();
          expect(
            durable
                .singleWhere(
                  (entry) => entry.clientTurnId == target.clientTurnId,
                )
                .failure,
            GatewayTurnRecoveryFailure.protocolViolation,
          );
          final otherEntry = durable.singleWhere(
            (entry) => entry.clientTurnId == other.clientTurnId,
          );
          expect(otherEntry.failure, isNull);
          expect(otherEntry.ackUncertain, isTrue);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'uncorrelated fault fails active but never settled terminal',
      () async {
        var promptCount = 0;
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              promptCount += 1;
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'uncorrelated-turn-$promptCount',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError(
              'Unexpected uncorrelated method ${request['method']}',
            );
          },
        );
        var uuidIndex = 200;
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
          uuidFactory: () => _uuidFor(++uuidIndex),
        );

        try {
          final terminalSeen = Completer<void>();
          final settled = await coordinator.submit(
            text: 'settled survivor',
            onState: (state) {
              if (state.isTerminal && !terminalSeen.isCompleted) {
                terminalSeen.complete();
              }
            },
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.start',
              turnId: settled.turnId!,
              seq: 1,
              payload: <String, dynamic>{},
            ),
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'turn.status',
              turnId: settled.turnId!,
              seq: 2,
              payload: <String, dynamic>{'status': 'completed'},
            ),
          );
          await terminalSeen.future.timeout(const Duration(seconds: 5));
          await coordinator.waitForIdle();
          final active = await coordinator.submit(text: 'active target');

          fixture.sendEvent(<String, dynamic>{
            'type': 'message.delta',
            'session_id': 'runtime-1',
            'turn_id': 'unknown-turn',
            'payload': <String, dynamic>{'text': 'uncorrelated'},
          });
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();

          final settledAfter = coordinator.stateFor(settled.clientTurnId)!;
          expect(settledAfter.status, GatewayRecoveryTurnStatus.completed);
          expect(settledAfter.failure, isNull);
          expect(
            coordinator.stateFor(active.clientTurnId)?.failure,
            GatewayTurnRecoveryFailure.protocolViolation,
          );
          final retained = coordinator.retentionSnapshot;
          expect(retained.activeStates, 0);
          expect(retained.settledTombstones, 2);
          expect(retained.observers, 0);
          expect(retained.activeTurnMappings, 0);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'late correlated terminal leaves terminal clean and active uncertain',
      () async {
        var promptCount = 0;
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              promptCount += 1;
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'late-turn-$promptCount',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError('Unexpected late method ${request['method']}');
          },
        );
        var uuidIndex = 300;
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final coordinator = _coordinator(
          fixture: fixture,
          journal: journal,
          uuidFactory: () => _uuidFor(++uuidIndex),
        );

        try {
          final terminalSeen = Completer<void>();
          final settled = await coordinator.submit(
            text: 'late terminal source',
            onState: (state) {
              if (state.isTerminal && !terminalSeen.isCompleted) {
                terminalSeen.complete();
              }
            },
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'message.start',
              turnId: settled.turnId!,
              seq: 1,
              payload: <String, dynamic>{},
            ),
          );
          fixture.sendEvent(
            _liveEventParams(
              type: 'turn.status',
              turnId: settled.turnId!,
              seq: 2,
              payload: <String, dynamic>{'status': 'completed'},
            ),
          );
          await terminalSeen.future.timeout(const Duration(seconds: 5));
          await coordinator.waitForIdle();
          final before = await journal.loadAll();
          final active = await coordinator.submit(text: 'late active survivor');

          fixture.sendEvent(<String, dynamic>{
            'type': 'message.delta',
            'session_id': 'runtime-1',
            'turn_id': settled.turnId,
            'payload': <String, dynamic>{'text': 'late terminal frame'},
          });
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();

          final settledAfter = coordinator.stateFor(settled.clientTurnId)!;
          expect(settledAfter.status, GatewayRecoveryTurnStatus.completed);
          expect(settledAfter.failure, isNull);
          final activeAfter = coordinator.stateFor(active.clientTurnId)!;
          expect(activeAfter.failure, isNull);
          expect(activeAfter.ackUncertain, isTrue);
          final after = await journal.loadAll();
          final terminalBefore = before.singleWhere(
            (entry) => entry.clientTurnId == settled.clientTurnId,
          );
          final terminalAfter = after.singleWhere(
            (entry) => entry.clientTurnId == settled.clientTurnId,
          );
          expect(terminalAfter.toJson(), terminalBefore.toJson());
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'clock rollback reconnect and active event preserve causal timestamp',
      () async {
        var nowMs = _baseMs + 5000;
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                storedSessionId: 'stored-1',
                bindingVersion: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'clock-turn',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            if (request['method'] == 'turn.reconcile') {
              return _reconcilePage(
                turnId: 'clock-turn',
                status: 'accepted',
                lastSeq: 0,
                events: <Map<String, dynamic>>[],
                hasMore: false,
                nextAfterSeq: 0,
              );
            }
            throw StateError('Unexpected clock method ${request['method']}');
          },
        );
        final issued = <String>[_mobileA, _clientA].iterator;
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final runningSeen = Completer<void>();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: journal,
          uuidFactory: () {
            if (!issued.moveNext()) throw StateError('UUID source exhausted');
            return issued.current;
          },
          clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
        );

        try {
          final submitted = await coordinator.submit(
            text: 'clock rollback',
            onState: (state) {
              if (state.status == GatewayRecoveryTurnStatus.running &&
                  !runningSeen.isCompleted) {
                runningSeen.complete();
              }
            },
          );
          final beforeRollback =
              (await journal.loadAll()).single.updatedAtEpochMs;
          nowMs -= 4000;
          await fixture.closeSocket();
          await fixture.waitForSocketClosed();
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await coordinator.waitForIdle();

          await coordinator.ensureOpen();
          fixture.sendEvent(
            _liveEventParams(
              sessionId: 'runtime-2',
              type: 'message.start',
              turnId: submitted.turnId!,
              seq: 1,
              payload: <String, dynamic>{},
            ),
            socketIndex: 1,
          );
          await runningSeen.future.timeout(const Duration(seconds: 5));
          await coordinator.waitForIdle();
          final afterRollback = (await journal.loadAll()).single;
          expect(
            afterRollback.updatedAtEpochMs,
            greaterThanOrEqualTo(beforeRollback),
          );
          expect(afterRollback.lastSeq, 1);
          expect(afterRollback.status, GatewayRecoveryTurnStatus.running);
          expect(coordinator.retentionSnapshot.activeStates, 1);
          expect(coordinator.retentionSnapshot.durableTimestampFloors, 1);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'snapshot assistant text enforces maxTurnBytes boundary and plus one',
      () async {
        final recovery = _recoveryCapability(
          maxEventBytes: 64,
          maxTurnBytes: 32,
          terminalEventReserveBytes: 8,
          reconcileMaxPageBytes: 1024,
        );
        for (final overflow in <bool>[false, true]) {
          late _GatewayFixture fixture;
          fixture = await _GatewayFixture.start(
            readyFrame: _readyFrame(recovery: recovery),
            handler: (request, connectionIndex) {
              final params = request['params'] as Map<String, dynamic>;
              if (request['method'] == 'session.open') {
                return _openResult(
                  mobileSessionId: params['mobile_session_id'] as String,
                  connectionIndex: connectionIndex,
                  recovery: recovery,
                );
              }
              if (request['method'] == 'prompt.submit') {
                return <String, dynamic>{'accepted': true};
              }
              if (request['method'] == 'turn.reconcile') {
                return _snapshotPage(
                  clientTurnId: params['client_turn_id'] as String,
                  text: 'x' * (overflow ? 33 : 32),
                );
              }
              throw StateError(
                'Unexpected snapshot method ${request['method']}',
              );
            },
          );
          final journal = GatewayTurnJournal(store: _MemoryJournalStore());
          final coordinator = _coordinator(fixture: fixture, journal: journal);

          try {
            if (overflow) {
              await expectLater(
                coordinator.submit(text: 'snapshot overflow'),
                throwsA(
                  isA<GatewayTurnCoordinatorException>().having(
                    (error) => error.failure,
                    'failure',
                    GatewayTurnCoordinatorFailure.invalidResponse,
                  ),
                ),
              );
              expect(
                (await journal.loadAll()).single.failure,
                GatewayTurnRecoveryFailure.protocolViolation,
              );
            } else {
              final state = await coordinator.submit(text: 'snapshot boundary');
              expect(state.snapshot?.assistant.text.length, 32);
              expect(state.status, GatewayRecoveryTurnStatus.completed);
              expect(
                coordinator.stateFor(state.clientTurnId)?.snapshot,
                isNull,
              );
              expect(coordinator.retentionSnapshot.retainedSnapshots, 0);
              expect(coordinator.retentionSnapshot.retainedEventCount, 0);
            }
            expect(
              fixture.requests.where(
                (request) => request['method'] == 'prompt.submit',
              ),
              hasLength(1),
            );
          } finally {
            await coordinator.close();
            await fixture.close();
          }
        }
      },
    );

    test(
      'terminal reserve above max turn rejects before session open',
      () async {
        final invalidRecovery = _recoveryCapability(
          maxEventBytes: 64,
          maxTurnBytes: 32,
          terminalEventReserveBytes: 33,
          reconcileMaxPageBytes: 512,
        );
        final fixture = await _GatewayFixture.start(
          readyFrame: _readyFrame(recovery: invalidRecovery),
          handler: (request, connectionIndex) {
            throw StateError(
              'Invalid capability must not call ${request['method']}',
            );
          },
        );
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        );

        try {
          await expectLater(
            coordinator.ensureOpen(),
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure.invalidResponse,
              ),
            ),
          );
          expect(fixture.requests, isEmpty);
          await fixture.waitForSocketClosed();
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'explicit missing ready capability allows fallback before any write',
      () async {
        final ready = _readyFrame();
        final payload =
            (ready['params'] as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        (payload['capabilities'] as Map<String, dynamic>).remove(
          'turn_recovery',
        );
        final fixture = await _GatewayFixture.start(
          readyFrame: ready,
          handler: (request, _) => throw StateError(
            'Unsupported ready must not call ${request['method']}',
          ),
        );
        final store = _MemoryJournalStore();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: store),
        );

        try {
          await expectLater(
            coordinator.recoverPending(),
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure.unsupportedCapability,
              ),
            ),
          );
          expect(fixture.requests, isEmpty);
          expect(store.value, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'unsupported ready blocks fallback when previous binding is unsafe',
      () async {
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final binding = _binding();
        await journal.upsertBinding(binding);
        await journal.upsert(
          _entry(
            binding: binding,
            turnId: 'turn-pending',
            status: GatewayRecoveryTurnStatus.accepted,
            ackUncertain: false,
          ),
        );
        final before = store.value;
        final ready = _readyFrame();
        final payload =
            (ready['params'] as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        (payload['capabilities'] as Map<String, dynamic>).remove(
          'turn_recovery',
        );
        final fixture = await _GatewayFixture.start(
          readyFrame: ready,
          handler: (request, _) => throw StateError(
            'Unsafe fallback must not call ${request['method']}',
          ),
        );
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          await expectLater(
            coordinator.recoverPending(),
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure
                    .unsupportedCapabilityWithPendingTurns,
              ),
            ),
          );
          expect(fixture.requests, isEmpty);
          expect(store.value, before);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'stock Hermes ready frame marks the fallback as a clean absence',
      () async {
        // Exactly what tui_gateway/ws.py emits: skin + change_events +
        // replay_epoch, no protocol, no capabilities.
        final stockReady = <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'event',
          'params': <String, dynamic>{
            'type': 'gateway.ready',
            'payload': <String, dynamic>{
              'skin': <String, dynamic>{'name': 'default'},
              'change_events': true,
              'heartbeat': true,
              'replay_epoch': 'epoch-a',
            },
          },
        };
        final fixture = await _GatewayFixture.start(
          readyFrame: stockReady,
          handler: (request, _) => throw StateError(
            'Unsupported ready must not call ${request['method']}',
          ),
        );
        final store = _MemoryJournalStore();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: store),
        );

        try {
          await expectLater(
            coordinator.recoverPending(),
            throwsA(
              isA<GatewayTurnCoordinatorException>()
                  .having(
                    (error) => error.failure,
                    'failure',
                    GatewayTurnCoordinatorFailure.unsupportedCapability,
                  )
                  .having(
                    (error) => error.stockGateway,
                    'stockGateway',
                    isTrue,
                  ),
            ),
          );
          expect(fixture.requests, isEmpty);
          expect(store.value, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test('v2 protocol without turn_recovery is also a clean absence', () async {
      final ready = _readyFrame();
      final payload =
          (ready['params'] as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      (payload['capabilities'] as Map<String, dynamic>).remove('turn_recovery');
      final fixture = await _GatewayFixture.start(
        readyFrame: ready,
        handler: (request, _) => throw StateError(
          'Unsupported ready must not call ${request['method']}',
        ),
      );
      final coordinator = _coordinator(
        fixture: fixture,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
      );

      try {
        await expectLater(
          coordinator.recoverPending(),
          throwsA(
            isA<GatewayTurnCoordinatorException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  GatewayTurnCoordinatorFailure.unsupportedCapability,
                )
                .having((error) => error.stockGateway, 'stockGateway', isTrue),
          ),
        );
      } finally {
        await coordinator.close();
        await fixture.close();
      }
    });

    test(
      'a wrong protocol name is a mismatch, never a clean absence',
      () async {
        final ready = _readyFrame();
        final payload =
            (ready['params'] as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        (payload['protocol'] as Map<String, dynamic>)['name'] = 'not-hermes';
        final fixture = await _GatewayFixture.start(
          readyFrame: ready,
          handler: (request, _) => throw StateError(
            'Unsupported ready must not call ${request['method']}',
          ),
        );
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        );

        try {
          await expectLater(
            coordinator.recoverPending(),
            throwsA(
              isA<GatewayTurnCoordinatorException>()
                  .having(
                    (error) => error.failure,
                    'failure',
                    GatewayTurnCoordinatorFailure.unsupportedCapability,
                  )
                  .having(
                    (error) => error.stockGateway,
                    'stockGateway',
                    isFalse,
                  ),
            ),
          );
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test('clean terminal journal still permits explicit fallback', () async {
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      final binding = _binding();
      await journal.upsertBinding(binding);
      await journal.upsert(
        _entry(
          binding: binding,
          turnId: 'turn-clean',
          status: GatewayRecoveryTurnStatus.completed,
          lastSeq: 1,
          ackUncertain: false,
        ),
      );
      final before = store.value;
      final ready = _readyFrame();
      final payload =
          (ready['params'] as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      (payload['capabilities'] as Map<String, dynamic>).remove('turn_recovery');
      final fixture = await _GatewayFixture.start(readyFrame: ready);
      final coordinator = _coordinator(fixture: fixture, journal: journal);

      try {
        await expectLater(
          coordinator.recoverPending(),
          throwsA(
            isA<GatewayTurnCoordinatorException>().having(
              (error) => error.failure,
              'failure',
              GatewayTurnCoordinatorFailure.unsupportedCapability,
            ),
          ),
        );
        expect(fixture.requests, isEmpty);
        expect(store.value, before);
      } finally {
        await coordinator.close();
        await fixture.close();
      }
    });

    test(
      'unsafe or malformed ready capability never grants legacy fallback',
      () async {
        for (final mutate in <void Function(Map<String, dynamic>)>[
          (recovery) => recovery['automatic_resubmit'] = true,
          (recovery) => recovery['max_event_bytes'] = 0,
        ]) {
          final recovery = _recoveryCapability();
          mutate(recovery);
          final fixture = await _GatewayFixture.start(
            readyFrame: _readyFrame(recovery: recovery),
          );
          final store = _MemoryJournalStore();
          final coordinator = _coordinator(
            fixture: fixture,
            journal: GatewayTurnJournal(store: store),
          );
          try {
            await expectLater(
              coordinator.recoverPending(),
              throwsA(
                isA<GatewayTurnCoordinatorException>().having(
                  (error) => error.failure,
                  'failure',
                  GatewayTurnCoordinatorFailure.invalidResponse,
                ),
              ),
            );
            expect(fixture.requests, isEmpty);
            expect(store.value, isNull);
          } finally {
            await coordinator.close();
            await fixture.close();
          }
        }
      },
    );

    test('wrong-type ready structures never grant legacy fallback', () async {
      final frames = <Map<String, dynamic>>[];
      for (var index = 0; index < 4; index += 1) {
        final frame = _readyFrame();
        final params = frame['params'] as Map<String, dynamic>;
        final payload = params['payload'] as Map<String, dynamic>;
        switch (index) {
          case 0:
            params['payload'] = 'malformed';
          case 1:
            payload['protocol'] = <Object>[];
          case 2:
            payload['capabilities'] = 'malformed';
          case 3:
            (payload['capabilities'] as Map<String, dynamic>)['turn_recovery'] =
                <Object>[];
        }
        frames.add(frame);
      }

      for (final frame in frames) {
        final fixture = await _GatewayFixture.start(readyFrame: frame);
        final store = _MemoryJournalStore();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: store),
        );
        try {
          await expectLater(
            coordinator.recoverPending(),
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure.invalidResponse,
              ),
            ),
          );
          expect(fixture.requests, isEmpty);
          expect(store.value, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      }
    });

    test(
      'generic malformed recovery shapes never grant legacy fallback',
      () async {
        final frames = <Map<String, dynamic>>[];
        for (var index = 0; index < 4; index += 1) {
          final frame = _readyFrame();
          final payload =
              (frame['params'] as Map<String, dynamic>)['payload']
                  as Map<String, dynamic>;
          final capabilities = payload['capabilities'] as Map<String, dynamic>;
          final recovery =
              capabilities['turn_recovery'] as Map<String, dynamic>;
          switch (index) {
            case 0:
              capabilities['turn_recovery'] = <String, dynamic>{};
            case 1:
              recovery['version'] = '2';
            case 2:
              recovery['methods'] = 'session.open';
            case 3:
              (recovery['methods'] as List).remove('turn.interrupt');
          }
          frames.add(frame);
        }

        for (final frame in frames) {
          final fixture = await _GatewayFixture.start(readyFrame: frame);
          final store = _MemoryJournalStore();
          final coordinator = _coordinator(
            fixture: fixture,
            journal: GatewayTurnJournal(store: store),
          );
          try {
            await expectLater(
              coordinator.recoverPending(),
              throwsA(
                isA<GatewayTurnCoordinatorException>().having(
                  (error) => error.failure,
                  'failure',
                  GatewayTurnCoordinatorFailure.invalidResponse,
                ),
              ),
            );
            expect(fixture.requests, isEmpty);
            expect(store.value, isNull);
          } finally {
            await coordinator.close();
            await fixture.close();
          }
        }
      },
    );

    test(
      'fully valid numeric recovery version mismatch permits fallback',
      () async {
        final recovery = _recoveryCapability()..['version'] = 3;
        final fixture = await _GatewayFixture.start(
          readyFrame: _readyFrame(recovery: recovery),
          handler: (request, _) => throw StateError(
            'Version fallback must not call ${request['method']}',
          ),
        );
        final store = _MemoryJournalStore();
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: store),
        );
        try {
          await expectLater(
            coordinator.recoverPending(),
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure.unsupportedCapability,
              ),
            ),
          );
          expect(fixture.requests, isEmpty);
          expect(store.value, isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'failed definitive-error seal poisons all reopen and recovery paths',
      () async {
        final promptSeen = Completer<void>();
        final releaseError = Completer<void>();
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) async {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              if (!promptSeen.isCompleted) promptSeen.complete();
              await releaseError.future;
              return _rpcError('client_turn_conflict');
            }
            throw StateError(
              'Poisoned definitive path called ${request['method']}',
            );
          },
        );
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          final pending = coordinator.submit(text: 'definitive poison');
          final assertion = expectLater(
            pending,
            throwsA(isA<GatewayTurnJournalException>()),
          );
          await promptSeen.future.timeout(const Duration(seconds: 5));
          store.failNextWrite = true;
          releaseError.complete();
          await assertion;
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();

          expect(coordinator.retentionSnapshot.poisoned, isTrue);
          expect(
            coordinator.stateFor(_clientA)?.failure,
            GatewayTurnRecoveryFailure.protocolViolation,
          );
          final durable = (await journal.loadAll()).single;
          expect(durable.failure, isNull);
          expect(durable.ackUncertain, isTrue);
          final wireCount = fixture.requests.length;
          await _expectPoisonStopsAllWire(coordinator, fixture);
          expect(fixture.requests, hasLength(wireCount));
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'process poison survives direct recreation and isolates session and store authorities',
      () async {
        final promptSeen = Completer<void>();
        final releaseError = Completer<void>();
        final poisonFixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) async {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              if (!promptSeen.isCompleted) promptSeen.complete();
              await releaseError.future;
              return _rpcError('client_turn_conflict');
            }
            throw StateError('Unexpected poison method ${request['method']}');
          },
        );
        final blockedFixture = await _GatewayFixture.start();
        final otherSessionFixture = await _GatewayFixture.start();
        final otherStoreFixture = await _GatewayFixture.start();
        final store = _MemoryJournalStore();
        final firstJournal = GatewayTurnJournal(store: store);
        final first = _coordinator(
          fixture: poisonFixture,
          journal: firstJournal,
        );
        GatewayTurnCoordinator? blocked;
        GatewayTurnCoordinator? otherSession;
        GatewayTurnCoordinator? otherStore;

        try {
          await _triggerDefinitiveProcessPoison(
            coordinator: first,
            fixture: poisonFixture,
            promptSeen: promptSeen,
            releaseError: releaseError,
            failNextWrite: () => store.failNextWrite = true,
          );
          _expectPayloadFreePoison(
            firstJournal.processPoisonedFailure(
              connectionId: 'connection-a',
              endpointDigest: _digest,
              localSessionId: 'local-a',
            ),
          );

          await first.close();
          final secondJournal = GatewayTurnJournal(store: store);
          blocked = _coordinator(
            fixture: blockedFixture,
            journal: secondJournal,
          );
          expect(blocked.retentionSnapshot.poisoned, isTrue);
          _expectPayloadFreePoison(blocked.stateFor(_clientA));
          await _expectPoisonStopsAllWire(blocked, blockedFixture);
          expect(blockedFixture.connectionCount, 0);
          expect(blockedFixture.requests, isEmpty);

          otherSession = _coordinator(
            fixture: otherSessionFixture,
            journal: secondJournal,
            localSessionId: 'local-b',
          );
          expect(otherSession.retentionSnapshot.poisoned, isFalse);
          await otherSession.ensureOpen();
          expect(otherSessionFixture.connectionCount, 1);
          expect(
            otherSessionFixture.requests.map((request) => request['method']),
            <Object?>['session.open'],
          );

          otherStore = _coordinator(
            fixture: otherStoreFixture,
            journal: GatewayTurnJournal(store: _MemoryJournalStore()),
          );
          expect(otherStore.retentionSnapshot.poisoned, isFalse);
          await otherStore.ensureOpen();
          expect(otherStoreFixture.connectionCount, 1);
          expect(
            otherStoreFixture.requests.map((request) => request['method']),
            <Object?>['session.open'],
          );
        } finally {
          await otherStore?.close();
          await otherSession?.close();
          await blocked?.close();
          await first.close();
          await otherStoreFixture.close();
          await otherSessionFixture.close();
          await blockedFixture.close();
          await poisonFixture.close();
        }
      },
    );

    test(
      'registry close and reopen preserves process poison with zero wire',
      () async {
        final promptSeen = Completer<void>();
        final releaseError = Completer<void>();
        final fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) async {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              if (!promptSeen.isCompleted) promptSeen.complete();
              await releaseError.future;
              return _rpcError('client_turn_conflict');
            }
            throw StateError('Unexpected registry method ${request['method']}');
          },
        );
        final store = _MemoryJournalStore();
        final registry = GatewayTurnCoordinatorRegistry(
          connectionId: 'connection-a',
          endpointDigest: _digest,
          journal: GatewayTurnJournal(store: store),
          freshSocketFactory: () async => WsClient(fixture.baseUrl),
          uuidFactory: () => _clientA,
          clock: () =>
              DateTime.fromMillisecondsSinceEpoch(_baseMs + 1000, isUtc: true),
        );

        try {
          final coordinator = await registry.open('local-a');
          await _triggerDefinitiveProcessPoison(
            coordinator: coordinator,
            fixture: fixture,
            promptSeen: promptSeen,
            releaseError: releaseError,
            failNextWrite: () => store.failNextWrite = true,
          );
          await registry.close('local-a');
          final wireCount = fixture.requests.length;
          final connectionCount = fixture.connectionCount;

          await expectLater(
            registry.open('local-a'),
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure.invalidResponse,
              ),
            ),
          );
          expect(fixture.connectionCount, connectionCount);
          expect(fixture.requests, hasLength(wireCount));
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'turn.reconcile',
            ),
            isEmpty,
          );
        } finally {
          await registry.closeAll();
          await fixture.close();
        }
      },
    );

    test(
      'registry recreation over shared store authority preserves process poison',
      () async {
        final promptSeen = Completer<void>();
        final releaseError = Completer<void>();
        final firstFixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) async {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              if (!promptSeen.isCompleted) promptSeen.complete();
              await releaseError.future;
              return _rpcError('client_turn_conflict');
            }
            throw StateError(
              'Unexpected first registry method ${request['method']}',
            );
          },
        );
        final recreatedFixture = await _GatewayFixture.start();
        final slot = _SharedMemoryJournalSlot();
        final firstStore = _SharedMemoryJournalStore(slot);
        final firstRegistry = GatewayTurnCoordinatorRegistry(
          connectionId: 'connection-a',
          endpointDigest: _digest,
          journal: GatewayTurnJournal(store: firstStore),
          freshSocketFactory: () async => WsClient(firstFixture.baseUrl),
          uuidFactory: () => _clientA,
          clock: () =>
              DateTime.fromMillisecondsSinceEpoch(_baseMs + 1000, isUtc: true),
        );
        GatewayTurnCoordinatorRegistry? recreatedRegistry;

        try {
          final coordinator = await firstRegistry.open('local-a');
          await _triggerDefinitiveProcessPoison(
            coordinator: coordinator,
            fixture: firstFixture,
            promptSeen: promptSeen,
            releaseError: releaseError,
            failNextWrite: () => slot.failNextWrite = true,
          );
          await firstRegistry.closeAll();

          final recreatedJournal = GatewayTurnJournal(
            store: _SharedMemoryJournalStore(slot),
          );
          recreatedRegistry = GatewayTurnCoordinatorRegistry(
            connectionId: 'connection-a',
            endpointDigest: _digest,
            journal: recreatedJournal,
            freshSocketFactory: () async => WsClient(recreatedFixture.baseUrl),
            uuidFactory: () => _clientA,
            clock: () => DateTime.fromMillisecondsSinceEpoch(
              _baseMs + 1000,
              isUtc: true,
            ),
          );
          _expectPayloadFreePoison(
            recreatedJournal.processPoisonedFailure(
              connectionId: 'connection-a',
              endpointDigest: _digest,
              localSessionId: 'local-a',
            ),
          );
          await expectLater(
            recreatedRegistry.open('local-a'),
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure.invalidResponse,
              ),
            ),
          );
          expect(recreatedFixture.connectionCount, 0);
          expect(recreatedFixture.requests, isEmpty);
        } finally {
          await recreatedRegistry?.closeAll();
          await firstRegistry.closeAll();
          await recreatedFixture.close();
          await firstFixture.close();
        }
      },
    );

    test(
      'process poison ledger bounds 64 scopes then stops the whole authority',
      () async {
        final slot = _SharedMemoryJournalSlot();
        final firstJournal = GatewayTurnJournal(
          store: _SharedMemoryJournalStore(slot),
        );
        final failure = GatewayTurnRecoveryState.rehydrate(
          clientTurnId: _clientA,
          turnId: null,
          status: null,
          lastSeq: 0,
          ackUncertain: false,
          failure: GatewayTurnRecoveryFailure.protocolViolation,
        );

        for (var index = 0; index < GatewayTurnJournal.maxBindings; index++) {
          firstJournal.recordProcessPoison(
            connectionId: 'connection-a',
            endpointDigest: _digest,
            localSessionId: 'local-poison-$index',
            failure: failure,
          );
        }
        expect(firstJournal.processPoisonedScopeCount, 64);
        expect(firstJournal.authorityWideProcessPoisoned, isFalse);

        firstJournal.recordProcessPoison(
          connectionId: 'connection-a',
          endpointDigest: _digest,
          localSessionId: 'local-poison-overflow',
          failure: failure,
        );
        expect(firstJournal.processPoisonedScopeCount, 64);
        expect(firstJournal.authorityWideProcessPoisoned, isTrue);

        final sharedJournal = GatewayTurnJournal(
          store: _SharedMemoryJournalStore(slot),
        );
        expect(sharedJournal.processPoisonedScopeCount, 64);
        expect(sharedJournal.authorityWideProcessPoisoned, isTrue);
        _expectPayloadFreePoison(
          sharedJournal.processPoisonedFailure(
            connectionId: 'connection-a',
            endpointDigest: _digest,
            localSessionId: 'previously-unseen-scope',
          ),
        );

        final blockedFixture = await _GatewayFixture.start();
        final isolatedFixture = await _GatewayFixture.start();
        final blocked = _coordinator(
          fixture: blockedFixture,
          journal: sharedJournal,
          localSessionId: 'previously-unseen-scope',
        );
        final isolatedJournal = GatewayTurnJournal(
          store: _SharedMemoryJournalStore(_SharedMemoryJournalSlot()),
        );
        final isolated = _coordinator(
          fixture: isolatedFixture,
          journal: isolatedJournal,
          localSessionId: 'previously-unseen-scope',
        );

        try {
          expect(blocked.retentionSnapshot.poisoned, isTrue);
          _expectPayloadFreePoison(blocked.stateFor(_clientA));
          await _expectPoisonStopsAllWire(blocked, blockedFixture);
          expect(blockedFixture.connectionCount, 0);
          expect(blockedFixture.requests, isEmpty);

          expect(isolatedJournal.processPoisonedScopeCount, 0);
          expect(isolatedJournal.authorityWideProcessPoisoned, isFalse);
          expect(isolated.retentionSnapshot.poisoned, isFalse);
          await isolated.ensureOpen();
          expect(isolatedFixture.connectionCount, 1);
          expect(
            isolatedFixture.requests.map((request) => request['method']),
            <Object?>['session.open'],
          );
        } finally {
          await isolated.close();
          await blocked.close();
          await isolatedFixture.close();
          await blockedFixture.close();
        }
      },
    );

    test('failed reconcile-error seal poisons with zero later wire', () async {
      final reconcileSeen = Completer<void>();
      final releaseError = Completer<void>();
      late _GatewayFixture fixture;
      fixture = await _GatewayFixture.start(
        handler: (request, connectionIndex) async {
          final params = request['params'] as Map<String, dynamic>;
          if (request['method'] == 'session.open') {
            return _openResult(
              mobileSessionId: params['mobile_session_id'] as String,
              connectionIndex: connectionIndex,
            );
          }
          if (request['method'] == 'prompt.submit') {
            return <String, dynamic>{'accepted': true};
          }
          if (request['method'] == 'turn.reconcile') {
            if (!reconcileSeen.isCompleted) reconcileSeen.complete();
            await releaseError.future;
            return _rpcError('turn_replay_pruned');
          }
          throw StateError(
            'Poisoned reconcile path called ${request['method']}',
          );
        },
      );
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      final coordinator = _coordinator(fixture: fixture, journal: journal);

      try {
        final pending = coordinator.submit(text: 'reconcile poison');
        final assertion = expectLater(
          pending,
          throwsA(isA<GatewayTurnJournalException>()),
        );
        await reconcileSeen.future.timeout(const Duration(seconds: 5));
        store.failNextWrite = true;
        releaseError.complete();
        await assertion;
        await fixture.waitForSocketClosed();
        await coordinator.waitForIdle();

        expect(coordinator.retentionSnapshot.poisoned, isTrue);
        expect(
          coordinator.stateFor(_clientA)?.failure,
          GatewayTurnRecoveryFailure.replayPruned,
        );
        final durable = (await journal.loadAll()).single;
        expect(durable.failure, isNull);
        expect(durable.ackUncertain, isTrue);
        final reconcileCount = fixture.requests
            .where((request) => request['method'] == 'turn.reconcile')
            .length;
        await _expectPoisonStopsAllWire(coordinator, fixture);
        expect(
          fixture.requests
              .where((request) => request['method'] == 'turn.reconcile')
              .length,
          reconcileCount,
        );
      } finally {
        await coordinator.close();
        await fixture.close();
      }
    });

    test(
      'failed malformed-live seal cannot be overwritten by durable old state',
      () async {
        final fixture = await _GatewayFixture.start();
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          final submitted = await coordinator.submit(text: 'live poison');
          final durableBefore = (await journal.loadAll()).single;
          store.failNextWrite = true;
          fixture.sendEvent(<String, dynamic>{
            'type': 'message.delta',
            'session_id': 'runtime-1',
            'turn_id': submitted.turnId,
            'payload': <String, dynamic>{'text': 'missing seq'},
          });
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();

          expect(coordinator.retentionSnapshot.poisoned, isTrue);
          expect(
            coordinator.stateFor(submitted.clientTurnId)?.failure,
            GatewayTurnRecoveryFailure.protocolViolation,
          );
          final durableAfter = (await journal.loadAll()).single;
          expect(durableAfter.toJson(), durableBefore.toJson());
          final wireCount = fixture.requests.length;
          await _expectPoisonStopsAllWire(coordinator, fixture);
          expect(fixture.requests, hasLength(wireCount));
          expect(coordinator.retentionSnapshot.poisoned, isTrue);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'recovers from the exact durable after_seq and skips clean terminal',
      () async {
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                storedSessionId: 'stored-a',
                bindingVersion: 2,
              );
            }
            if (request['method'] == 'turn.reconcile') {
              return <String, dynamic>{
                'mode': 'events',
                'turn_id': 'turn-a',
                'status': 'running',
                'earliest_seq': 1,
                'last_seq': 7,
                'events': <Object>[],
                'has_more': false,
                'next_after_seq': 7,
                'automatic_resubmit': false,
              };
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final binding = _binding();
        await journal.upsertBinding(binding);
        await journal.upsert(
          _entry(
            binding: binding,
            turnId: 'turn-a',
            status: GatewayRecoveryTurnStatus.running,
            lastSeq: 7,
            ackUncertain: true,
          ),
        );
        await journal.upsert(
          _entry(
            binding: binding,
            clientTurnId: _clientB,
            turnId: 'turn-terminal',
            status: GatewayRecoveryTurnStatus.completed,
            lastSeq: 3,
            ackUncertain: false,
            updatedAtEpochMs: _baseMs + 1,
          ),
        );
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          await coordinator.ensureOpen();

          final reconcile = fixture.requests.singleWhere(
            (request) => request['method'] == 'turn.reconcile',
          );
          expect(reconcile['params'], <String, dynamic>{
            'session_id': 'runtime-1',
            'turn_id': 'turn-a',
            'after_seq': 7,
          });
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'prompt.submit',
            ),
            isEmpty,
          );
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'turn.reconcile',
            ),
            hasLength(1),
          );
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'controller recreation returns durable terminal without resubmit',
      () async {
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                storedSessionId: 'stored-a',
                bindingVersion: 2,
              );
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final store = _MemoryJournalStore();
        final journal = GatewayTurnJournal(store: store);
        final binding = _binding();
        await journal.upsertBinding(binding);
        await journal.upsert(
          _entry(
            binding: binding,
            turnId: 'turn-terminal-recreated',
            status: GatewayRecoveryTurnStatus.completed,
            lastSeq: 7,
            terminalEventRecorded: true,
            terminalResult: GatewayTurnTerminalResult(
              messageId: 'message-terminal-recreated',
              assistantText: 'Recovered after process recreation.',
            ),
            ackUncertain: false,
          ),
        );
        final coordinator = _coordinator(fixture: fixture, journal: journal);
        final observed = <GatewayTurnRecoveryState>[];

        try {
          final recovered = await coordinator.recoverPending(
            onState: observed.add,
          );
          expect(recovered, hasLength(1));
          expect(observed, hasLength(1));
          expect(
            recovered.single.terminalResult?.assistantText,
            'Recovered after process recreation.',
          );
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'prompt.submit',
            ),
            isEmpty,
          );
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'turn.reconcile',
            ),
            isEmpty,
          );
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'onSessionBound reports every authoritative durable binding',
      () async {
        late _GatewayFixture fixture;
        var opens = 0;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              opens += 1;
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                storedSessionId: 'stored-a',
                bindingVersion: opens,
              );
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final coordinator = _coordinator(fixture: fixture, journal: journal);
        final bounds = <(String, String)>[];
        coordinator.onSessionBound = (local, stored) {
          bounds.add((local, stored));
        };

        try {
          await coordinator.ensureOpen();

          // The first binding carries the durable stored id an owner needs to
          // reconcile records keyed by the draft id.
          expect(bounds, [('local-a', 'stored-a')]);

          // A reconnect advances the authoritative binding version. Metadata
          // consumers must hear about it even though the stored id is stable.
          await fixture.closeSocket();
          await fixture.waitForSocketClosed();
          await coordinator.waitForIdle();
          await coordinator.ensureOpen();
          expect(bounds, [('local-a', 'stored-a'), ('local-a', 'stored-a')]);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test('WAL write failure sends zero prompt.submit requests', () async {
      final fixture = await _GatewayFixture.start();
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      final coordinator = _coordinator(fixture: fixture, journal: journal);

      try {
        await coordinator.ensureOpen();
        store.failNextWrite = true;

        await expectLater(
          coordinator.submit(text: 'must stay local'),
          throwsA(isA<GatewayTurnJournalException>()),
        );
        expect(
          fixture.requests.where(
            (request) => request['method'] == 'prompt.submit',
          ),
          isEmpty,
        );
      } finally {
        await coordinator.close();
        await fixture.close();
      }
    });

    test('persists intent then emits exactly one prompt.submit v2', () async {
      final fixture = await _GatewayFixture.start();
      final store = _MemoryJournalStore();
      final journal = GatewayTurnJournal(store: store);
      final coordinator = _coordinator(fixture: fixture, journal: journal);
      final observed = <GatewayTurnRecoveryState>[];

      try {
        final state = await coordinator.submit(
          text: 'one execution',
          onState: observed.add,
        );

        final submits = fixture.requests.where(
          (request) => request['method'] == 'prompt.submit',
        );
        expect(submits, hasLength(1));
        expect(submits.single['params'], <String, dynamic>{
          'session_id': 'runtime-1',
          'version': 2,
          'client_turn_id': _clientA,
          'text': AndroidPromptContext.forModel('one execution'),
        });
        expect(state.clientTurnId, _clientA);
        expect(state.turnId, 'turn-1');
        expect(state.status, GatewayRecoveryTurnStatus.accepted);
        final persisted = await journal.loadAll();
        expect(persisted, hasLength(1));
        expect(persisted.single.clientTurnId, _clientA);
        expect(persisted.single.ackUncertain, isFalse);

        await coordinator.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(observed, hasLength(2));
        expect(observed.first.ackUncertain, isFalse);
        expect(observed.last.ackUncertain, isTrue);
        expect((await journal.loadAll()).single.ackUncertain, isTrue);
      } finally {
        await coordinator.close();
        await fixture.close();
      }
    });

    test(
      'completed ACK reconciles payload before terminal persistence',
      () async {
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'turn-1',
                'status': 'completed',
                'last_seq': 0,
                'created': true,
              };
            }
            if (request['method'] == 'turn.reconcile') {
              return _snapshotPage(
                clientTurnId: _clientA,
                text: 'Completed before ACK was observed.',
              );
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          final state = await coordinator.submit(text: 'fast completion');
          expect(state.status, GatewayRecoveryTurnStatus.completed);
          expect(
            state.terminalResult?.assistantText,
            'Completed before ACK was observed.',
          );
          expect(state.isFailClosed, isFalse);
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'prompt.submit',
            ),
            hasLength(1),
          );
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'turn.reconcile',
            ),
            hasLength(1),
          );
          expect((await journal.loadAll()).single.terminalResult, isNotNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'restart after completed ACK seal reconciles without resubmit',
      () async {
        final slot = _CrashJournalSlot();
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                storedSessionId: 'stored-1',
                bindingVersion: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'turn-1',
                'status': 'completed',
                'last_seq': 0,
                'created': true,
              };
            }
            if (request['method'] == 'turn.reconcile') {
              return _snapshotPage(
                clientTurnId: _clientA,
                text: 'Recovered after completed ACK seal.',
              );
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final first = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(
            store: _CrashJournalStore(slot, crashOnAckSeal: true),
          ),
        );

        try {
          unawaited(first.submit(text: 'complete during process loss'));
          await slot.ackSealed.future.timeout(const Duration(seconds: 5));
          final restartedJournal = GatewayTurnJournal(
            store: _CrashJournalStore(slot),
          );
          final sealed = await restartedJournal.loadAll();
          expect(sealed, hasLength(1));
          expect(sealed.single.turnId, 'turn-1');
          expect(sealed.single.status, isNull);
          expect(sealed.single.ackUncertain, isTrue);

          final restarted = _coordinator(
            fixture: fixture,
            journal: restartedJournal,
          );
          try {
            final recovered = await restarted.recoverPending();
            expect(recovered, hasLength(1));
            expect(
              recovered.single.status,
              GatewayRecoveryTurnStatus.completed,
            );
            expect(
              recovered.single.terminalResult?.assistantText,
              'Recovered after completed ACK seal.',
            );
            expect(recovered.single.isFailClosed, isFalse);
          } finally {
            await restarted.close();
          }

          expect(
            fixture.requests.where(
              (request) => request['method'] == 'prompt.submit',
            ),
            hasLength(1),
          );
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'turn.reconcile',
            ),
            hasLength(1),
          );
          expect(
            (await restartedJournal.loadAll())
                .single
                .terminalResult
                ?.assistantText,
            'Recovered after completed ACK seal.',
          );
        } finally {
          await fixture.close();
        }
      },
    );

    test(
      'stages two images and one document on the submit socket in manifest order',
      () async {
        final capability = _recoveryCapability(attachments: true);
        var attachmentIndex = 0;
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          readyFrame: _readyFrame(recovery: capability),
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                recovery: capability,
              );
            }
            if (request['method'] == 'image.attach_bytes' ||
                request['method'] == 'file.attach') {
              attachmentIndex += 1;
              return <String, dynamic>{
                'attached': true,
                'attachment_id': 'attachment-$attachmentIndex',
                'sha256': _digest,
                'byte_length': switch (attachmentIndex) {
                  1 => 4,
                  2 => 5,
                  _ => 6,
                },
                'media_type': attachmentIndex < 3
                    ? 'image/png'
                    : 'application/octet-stream',
              };
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'turn-1',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        );

        try {
          final first = await coordinator.stageAttachment(
            clientAttachmentId: 'local-image-one',
            name: 'one.png',
            dataUrl: 'data:image/png;base64,AAAA',
            byteLength: 4,
            mediaType: 'image/png',
            kind: GatewayTurnAttachmentKind.image,
          );
          final second = await coordinator.stageAttachment(
            clientAttachmentId: 'local-image-two',
            name: 'two.png',
            dataUrl: 'data:image/png;base64,BBBB',
            byteLength: 5,
            mediaType: 'image/png',
            kind: GatewayTurnAttachmentKind.image,
          );
          final document = await coordinator.stageAttachment(
            clientAttachmentId: 'local-document',
            name: 'notes.txt',
            dataUrl: 'data:application/octet-stream;base64,CCCC',
            byteLength: 6,
            mediaType: 'application/octet-stream',
            kind: GatewayTurnAttachmentKind.file,
          );

          await coordinator.submit(
            text: 'Use these inputs',
            attachments: [first, second, document],
          );

          expect(fixture.connectionCount, 1);
          expect(
            fixture.requests.map((request) => request['method']),
            <Object?>[
              'session.open',
              'image.attach_bytes',
              'image.attach_bytes',
              'file.attach',
              'prompt.submit',
            ],
          );
          final submit = fixture.requests.last;
          final submitParams = submit['params'] as Map<String, dynamic>;
          expect(
            submitParams['text'],
            AndroidPromptContext.forModel('Use these inputs'),
          );
          expect(submitParams['text'], isNot(contains('@file:')));
          expect(submitParams['attachments'], <Map<String, dynamic>>[
            {
              'attachment_id': 'attachment-1',
              'client_attachment_id': 'local-image-one',
              'sha256': _digest,
              'byte_length': 4,
              'media_type': 'image/png',
            },
            {
              'attachment_id': 'attachment-2',
              'client_attachment_id': 'local-image-two',
              'sha256': _digest,
              'byte_length': 5,
              'media_type': 'image/png',
            },
            {
              'attachment_id': 'attachment-3',
              'client_attachment_id': 'local-document',
              'sha256': _digest,
              'byte_length': 6,
              'media_type': 'application/octet-stream',
            },
          ]);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'definitive rejection detaches receipts and removes the WAL intent',
      () async {
        final capability = _recoveryCapability(attachments: true);
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          readyFrame: _readyFrame(recovery: capability),
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
                recovery: capability,
              );
            }
            if (request['method'] == 'image.attach_bytes') {
              return <String, dynamic>{
                'attached': true,
                'attachment_id': 'rejected-attachment',
                'sha256': _digest,
                'byte_length': 4,
                'media_type': 'image/png',
              };
            }
            if (request['method'] == 'prompt.submit') {
              return _rpcError('schema_violation');
            }
            if (request['method'] == 'attachment.detach') {
              return <String, dynamic>{
                'detached': true,
                'attachment_id': params['attachment_id'],
              };
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final coordinator = _coordinator(fixture: fixture, journal: journal);

        try {
          final receipt = await coordinator.stageAttachment(
            clientAttachmentId: 'local-rejected-image',
            name: 'rejected.png',
            dataUrl: 'data:image/png;base64,AAAA',
            byteLength: 4,
            mediaType: 'image/png',
            kind: GatewayTurnAttachmentKind.image,
          );
          await expectLater(
            coordinator.submit(text: 'reject', attachments: [receipt]),
            throwsA(
              isA<JsonRpcError>().having(
                (error) => error.reason,
                'reason',
                'schema_violation',
              ),
            ),
          );

          expect(
            fixture.requests.map((request) => request['method']),
            <Object?>[
              'session.open',
              'image.attach_bytes',
              'prompt.submit',
              'attachment.detach',
            ],
          );
          expect(await journal.loadAll(), isEmpty);
          expect(coordinator.stateFor(_clientA), isNull);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test('accepted reconcile releases attachment capacity', () async {
      final capability = _recoveryCapability(attachments: true);
      var attachmentIndex = 0;
      late _GatewayFixture fixture;
      fixture = await _GatewayFixture.start(
        readyFrame: _readyFrame(recovery: capability),
        handler: (request, connectionIndex) {
          final params = request['params'] as Map<String, dynamic>;
          if (request['method'] == 'session.open') {
            return _openResult(
              mobileSessionId: params['mobile_session_id'] as String,
              connectionIndex: connectionIndex,
              recovery: capability,
            );
          }
          if (request['method'] == 'image.attach_bytes') {
            attachmentIndex += 1;
            return <String, dynamic>{
              'attached': true,
              'attachment_id': 'reconciled-attachment-$attachmentIndex',
              'sha256': _digest,
              'byte_length': 1,
              'media_type': 'image/png',
            };
          }
          if (request['method'] == 'prompt.submit') {
            return <String, dynamic>{'accepted': true};
          }
          if (request['method'] == 'turn.reconcile') {
            return _reconcilePage(
              turnId: 'turn-reconciled',
              status: 'accepted',
              lastSeq: 0,
              events: const <Map<String, dynamic>>[],
              hasMore: false,
              nextAfterSeq: 0,
            );
          }
          throw StateError('Unexpected method ${request['method']}');
        },
      );
      final coordinator = _coordinator(
        fixture: fixture,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
      );

      try {
        final submittedReceipt = await coordinator.stageAttachment(
          clientAttachmentId: 'submitted-image',
          name: 'submitted.png',
          dataUrl: 'data:image/png;base64,AA==',
          byteLength: 1,
          mediaType: 'image/png',
          kind: GatewayTurnAttachmentKind.image,
        );
        final state = await coordinator.submit(
          text: 'reconcile attachment',
          attachments: [submittedReceipt],
        );
        expect(state.turnId, 'turn-reconciled');

        for (var index = 0; index < 10; index++) {
          await coordinator.stageAttachment(
            clientAttachmentId: 'next-image-$index',
            name: 'next-$index.png',
            dataUrl: 'data:image/png;base64,AA==',
            byteLength: 1,
            mediaType: 'image/png',
            kind: GatewayTurnAttachmentKind.image,
          );
        }
        expect(attachmentIndex, 11);
        expect(
          fixture.requests.where(
            (request) => request['method'] == 'prompt.submit',
          ),
          hasLength(1),
        );
      } finally {
        await coordinator.close();
        await fixture.close();
      }
    });

    test(
      'malformed ACK reconciles across pages and pins the discovered turn',
      () async {
        var reconcileCount = 0;
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{'accepted': true};
            }
            if (request['method'] == 'turn.reconcile') {
              reconcileCount += 1;
              if (reconcileCount == 1) {
                return _reconcilePage(
                  turnId: 'turn-a',
                  status: 'running',
                  lastSeq: 2,
                  events: <Map<String, dynamic>>[
                    _turnEvent(
                      turnId: 'turn-a',
                      seq: 1,
                      type: 'message.start',
                      payload: <String, dynamic>{},
                    ),
                  ],
                  hasMore: true,
                  nextAfterSeq: 1,
                );
              }
              return _reconcilePage(
                turnId: 'turn-a',
                status: 'completed',
                lastSeq: 2,
                events: <Map<String, dynamic>>[
                  _turnEvent(
                    turnId: 'turn-a',
                    seq: 2,
                    type: 'message.complete',
                    payload: <String, dynamic>{
                      'text': 'done',
                      'status': 'completed',
                    },
                  ),
                ],
                hasMore: false,
                nextAfterSeq: 2,
              );
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        );

        try {
          final state = await coordinator.submit(text: 'recover this ACK');
          final submits = fixture.requests.where(
            (request) => request['method'] == 'prompt.submit',
          );
          final reconciles = fixture.requests
              .where((request) => request['method'] == 'turn.reconcile')
              .toList(growable: false);

          expect(submits, hasLength(1));
          expect(reconciles, hasLength(2));
          expect(reconciles[0]['params'], <String, dynamic>{
            'session_id': 'runtime-1',
            'client_turn_id': _clientA,
            'after_seq': 0,
          });
          expect(reconciles[1]['params'], <String, dynamic>{
            'session_id': 'runtime-1',
            'turn_id': 'turn-a',
            'after_seq': 1,
          });
          expect(state.turnId, 'turn-a');
          expect(state.lastSeq, 2);
          expect(state.status, GatewayRecoveryTurnStatus.completed);
          expect(state.isFailClosed, isFalse);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test('stalled second reconcile cursor fails closed', () async {
      await _expectBadSecondReconcilePage(crossTurn: false);
    });

    test('cross-turn second reconcile page fails closed', () async {
      await _expectBadSecondReconcilePage(crossTurn: true);
    });

    test(
      'interrupt uses the authoritative turn and never a legacy route',
      () async {
        late _GatewayFixture fixture;
        fixture = await _GatewayFixture.start(
          handler: (request, connectionIndex) {
            final params = request['params'] as Map<String, dynamic>;
            if (request['method'] == 'session.open') {
              return _openResult(
                mobileSessionId: params['mobile_session_id'] as String,
                connectionIndex: connectionIndex,
              );
            }
            if (request['method'] == 'prompt.submit') {
              return <String, dynamic>{
                'accepted': true,
                'automatic_resubmit': false,
                'client_turn_id': params['client_turn_id'],
                'turn_id': 'turn-1',
                'status': 'accepted',
                'last_seq': 0,
                'created': true,
              };
            }
            if (request['method'] == 'turn.interrupt') {
              return <String, dynamic>{
                'automatic_resubmit': false,
                'client_turn_id': _clientA,
                'turn_id': 'turn-1',
                'status': 'interrupted',
                'last_seq': 0,
              };
            }
            if (request['method'] == 'turn.reconcile') {
              return _reconcilePage(
                turnId: 'turn-1',
                status: 'interrupted',
                lastSeq: 0,
                events: <Map<String, dynamic>>[],
                hasMore: false,
                nextAfterSeq: 0,
              );
            }
            throw StateError('Unexpected method ${request['method']}');
          },
        );
        final coordinator = _coordinator(
          fixture: fixture,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        );

        try {
          await coordinator.submit(text: 'interrupt once');
          final state = await coordinator.interrupt(_clientA);
          final interrupt = fixture.requests.singleWhere(
            (request) => request['method'] == 'turn.interrupt',
          );

          expect(interrupt['params'], <String, dynamic>{
            'session_id': 'runtime-1',
            'turn_id': 'turn-1',
          });
          expect(
            fixture.requests.map((request) => request['method']),
            <Object?>[
              'session.open',
              'prompt.submit',
              'turn.interrupt',
              'turn.reconcile',
            ],
          );
          expect(state.clientTurnId, _clientA);
          expect(state.turnId, 'turn-1');
          expect(state.status, GatewayRecoveryTurnStatus.interrupted);
        } finally {
          await coordinator.close();
          await fixture.close();
        }
      },
    );

    test(
      'persisted canonical UUID versions one through eight reopen',
      () async {
        for (var version = 1; version <= 8; version += 1) {
          final persistedMobile =
              '11111111-1111-${version}111-8111-111111111111';
          late _GatewayFixture fixture;
          fixture = await _GatewayFixture.start(
            handler: (request, connectionIndex) {
              final params = request['params'] as Map<String, dynamic>;
              if (request['method'] == 'session.open') {
                return _openResult(
                  mobileSessionId: params['mobile_session_id'] as String,
                  connectionIndex: connectionIndex,
                  storedSessionId: 'stored-a',
                  bindingVersion: 2,
                );
              }
              throw StateError(
                'UUID reopen must not call ${request['method']}',
              );
            },
          );
          final journal = GatewayTurnJournal(store: _MemoryJournalStore());
          await journal.upsertBinding(
            _binding(mobileSessionId: persistedMobile),
          );
          final coordinator = _coordinator(fixture: fixture, journal: journal);

          try {
            await coordinator.ensureOpen();
            final open = fixture.requests.single;
            expect(open['method'], 'session.open');
            expect(
              (open['params'] as Map<String, dynamic>)['mobile_session_id'],
              persistedMobile,
              reason: 'UUID version $version',
            );
          } finally {
            await coordinator.close();
            await fixture.close();
          }
        }
      },
    );

    test('new mobile and turn identifiers reject non-v4 UUIDs', () async {
      const versionOne = '11111111-1111-1111-8111-111111111111';
      final unopenedFixture = await _GatewayFixture.start();
      final unopened = _coordinator(
        fixture: unopenedFixture,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        uuidFactory: () => versionOne,
      );
      try {
        await expectLater(unopened.ensureOpen(), throwsA(isA<StateError>()));
        expect(unopenedFixture.connectionCount, 0);
        expect(unopenedFixture.requests, isEmpty);
      } finally {
        await unopened.close();
        await unopenedFixture.close();
      }

      final openedFixture = await _GatewayFixture.start();
      final issued = <String>[_mobileA, versionOne].iterator;
      final opened = _coordinator(
        fixture: openedFixture,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        uuidFactory: () {
          if (!issued.moveNext()) throw StateError('UUID source exhausted');
          return issued.current;
        },
      );
      try {
        await expectLater(
          opened.submit(text: 'invalid generated client turn'),
          throwsA(isA<StateError>()),
        );
        expect(
          openedFixture.requests.map((request) => request['method']),
          <Object?>['session.open'],
        );
      } finally {
        await opened.close();
        await openedFixture.close();
      }
    });

    test('open racing close is rejected before a socket is leased', () async {
      final fixture = await _GatewayFixture.start();
      final registry = GatewayTurnCoordinatorRegistry(
        connectionId: 'connection-a',
        endpointDigest: _digest,
        journal: GatewayTurnJournal(store: _MemoryJournalStore()),
        freshSocketFactory: () async => WsClient(fixture.baseUrl),
        uuidFactory: () => _mobileA,
        clock: () =>
            DateTime.fromMillisecondsSinceEpoch(_baseMs + 1000, isUtc: true),
      );

      try {
        final opening = registry.open('local-race');
        final closing = registry.close('local-race');
        await expectLater(
          opening,
          throwsA(
            isA<GatewayTurnCoordinatorException>().having(
              (error) => error.failure,
              'failure',
              GatewayTurnCoordinatorFailure.closed,
            ),
          ),
        );
        await closing;
        expect(fixture.connectionCount, 0);
        expect(fixture.requests, isEmpty);
      } finally {
        await registry.closeAll();
        await fixture.close();
      }
    });

    test(
      'open racing closeAll is rejected and registry stays closed',
      () async {
        final fixture = await _GatewayFixture.start();
        final registry = GatewayTurnCoordinatorRegistry(
          connectionId: 'connection-a',
          endpointDigest: _digest,
          journal: GatewayTurnJournal(store: _MemoryJournalStore()),
          freshSocketFactory: () async => WsClient(fixture.baseUrl),
          uuidFactory: () => _mobileA,
          clock: () =>
              DateTime.fromMillisecondsSinceEpoch(_baseMs + 1000, isUtc: true),
        );

        try {
          final opening = registry.open('local-race-all');
          final closing = registry.closeAll();
          await expectLater(
            opening,
            throwsA(
              isA<GatewayTurnCoordinatorException>().having(
                (error) => error.failure,
                'failure',
                GatewayTurnCoordinatorFailure.closed,
              ),
            ),
          );
          await closing;
          await expectLater(
            registry.open('after-close-all'),
            throwsA(isA<GatewayTurnCoordinatorException>()),
          );
          expect(fixture.connectionCount, 0);
          expect(fixture.requests, isEmpty);
        } finally {
          await registry.closeAll();
          await fixture.close();
        }
      },
    );

    test(
      'opens fresh sockets in order and isolates registry sessions',
      () async {
        final fixture = await _GatewayFixture.start();
        final journal = GatewayTurnJournal(store: _MemoryJournalStore());
        final issued = <String>[_mobileA, _mobileB].iterator;
        final registry = GatewayTurnCoordinatorRegistry(
          connectionId: 'connection-a',
          endpointDigest: _digest,
          journal: journal,
          freshSocketFactory: () async {
            fixture.order.add('factory');
            return WsClient(fixture.baseUrl);
          },
          uuidFactory: () {
            if (!issued.moveNext()) throw StateError('UUID source exhausted');
            return issued.current;
          },
          clock: () =>
              DateTime.fromMillisecondsSinceEpoch(_baseMs + 1000, isUtc: true),
        );

        try {
          final raced = await Future.wait(<Future<GatewayTurnCoordinator>>[
            registry.open('local-a'),
            registry.open('local-a'),
          ]);
          final first = raced.first;
          final same = raced.last;
          final second = await registry.open('local-b');

          expect(identical(first, same), isTrue);
          expect(identical(first, second), isFalse);
          expect(fixture.connectionCount, 2);
          expect(
            fixture.requests.where(
              (request) => request['method'] == 'session.open',
            ),
            hasLength(2),
          );
          expect(fixture.order, <String>[
            'factory',
            'socket',
            'session.open',
            'factory',
            'socket',
            'session.open',
          ]);
          expect(first.runtimeBinding?.runtimeSessionId, 'runtime-1');
          expect(second.runtimeBinding?.runtimeSessionId, 'runtime-2');
          expect(first.durableBinding?.localSessionId, 'local-a');
          expect(second.durableBinding?.localSessionId, 'local-b');
        } finally {
          await registry.closeAll();
          await fixture.close();
        }
      },
    );
  });
}
