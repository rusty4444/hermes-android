import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/gateway_turn_contract.dart';
import '../utils/android_prompt_context.dart';
import 'gateway_turn_journal.dart';
import 'gateway_turn_recovery.dart';
import 'ws_client.dart';

typedef GatewayTurnFreshSocketFactory = Future<WsClient> Function();
typedef GatewayTurnIdFactory = String Function();
typedef GatewayTurnClock = DateTime Function();
typedef GatewayTurnStateCallback =
    void Function(GatewayTurnRecoveryState state);
typedef GatewayTurnSettledCallback =
    void Function(GatewayTurnRecoveryState state);

/// Fired whenever `session.open` authoritatively binds a draft (local) session
/// id to the server's durable stored id. Lets an owning layer reconcile
/// server-side records after both first persistence and reconnect.
typedef GatewayTurnSessionBoundCallback =
    void Function(String localSessionId, String storedSessionId);

/// Fired whenever a coordinator socket binds a local session to the live
/// runtime id carried by server-request and event frames.
typedef GatewayTurnRuntimeBoundCallback =
    void Function(String localSessionId, String runtimeSessionId);

class GatewayTurnAdmissionRevoked implements Exception {
  const GatewayTurnAdmissionRevoked();
  @override
  String toString() => 'Local turn admission was revoked before submission.';
}

enum GatewayTurnCoordinatorFailure {
  closed,
  transportUnavailable,
  unsupportedCapability,
  unsupportedCapabilityWithPendingTurns,
  invalidBinding,
  invalidResponse,
  turnUnknown,
  replayPruned,
}

class GatewayTurnCoordinatorException implements Exception {
  final GatewayTurnCoordinatorFailure failure;

  /// True when the failure came from a gateway whose `gateway.ready` greeting
  /// cleanly lacks the durable turn-recovery contract (a stock Hermes server),
  /// as opposed to a v2-capable gateway rejecting one feature (attachments)
  /// or an unsafe/malformed advertisement. Only the clean-absence case may
  /// be surfaced to the user as "this server doesn't offer recovery" rather
  /// than a failure.
  final bool stockGateway;

  const GatewayTurnCoordinatorException(
    this.failure, {
    this.stockGateway = false,
  });

  @override
  String toString() => 'Gateway turn coordinator stopped: ${failure.name}.';
}

enum GatewayTurnAttachmentKind { image, file }

/// Opaque receipt issued by the recovery runtime that staged the attachment.
///
/// Paths, `@file:` references, payload bytes, and display names never enter the
/// durable turn contract. A receipt is accepted by [GatewayTurnCoordinator]
/// only while the exact transport generation that issued it is still active.
class GatewayTurnAttachmentReceipt {
  final String attachmentId;
  final String clientAttachmentId;
  final String sha256;
  final int byteLength;
  final String mediaType;
  final GatewayTurnAttachmentKind kind;
  final int _transportGeneration;

  const GatewayTurnAttachmentReceipt._({
    required this.attachmentId,
    required this.clientAttachmentId,
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
    required this.kind,
    required this._transportGeneration,
  });

  Map<String, Object> toWire() => <String, Object>{
    'attachment_id': attachmentId,
    'client_attachment_id': clientAttachmentId,
    'sha256': sha256,
    'byte_length': byteLength,
    'media_type': mediaType,
  };
}

/// Count-only retention view for bounded lifecycle tests and diagnostics.
class GatewayTurnCoordinatorRetentionSnapshot {
  final int activeStates;
  final int settledTombstones;
  final int observers;
  final int activeTurnMappings;
  final int durableTimestampFloors;
  final int retainedEventCount;
  final int retainedSnapshots;
  final bool poisoned;

  const GatewayTurnCoordinatorRetentionSnapshot({
    required this.activeStates,
    required this.settledTombstones,
    required this.observers,
    required this.activeTurnMappings,
    required this.durableTimestampFloors,
    required this.retainedEventCount,
    required this.retainedSnapshots,
    required this.poisoned,
  });
}

/// Opt-in registry for recovery-v2 transports.
///
/// Each local chat owns a distinct physical socket. The registry is deliberately
/// separate from the legacy Desktop transport until a later activation slice.
class GatewayTurnCoordinatorRegistry {
  final String connectionId;
  final String endpointDigest;
  final GatewayTurnJournal journal;
  final GatewayTurnFreshSocketFactory freshSocketFactory;
  final GatewayTurnIdFactory uuidFactory;
  final GatewayTurnClock clock;
  final Map<String, GatewayTurnCoordinator> _coordinators = {};
  final Expando<bool> _leasedSockets = Expando<bool>();
  final Map<String, int> _sessionGenerations = {};
  final Map<String, _GatewayTurnSettledRegistration> _turnSettledListeners = {};
  final Map<Object, void Function()> _turnActivityListeners = {};
  final Map<String, _GatewayTurnSessionBoundRegistration>
  _sessionBoundListeners = {};
  Future<void> _tail = Future<void>.value();
  int _generation = 0;
  bool _closed = false;

  /// Set on every coordinator so request/event routing can translate the live
  /// runtime session id back to the app's local session id.
  GatewayTurnRuntimeBoundCallback? onRuntimeBound;

  GatewayTurnCoordinatorRegistry({
    required this.connectionId,
    required this.endpointDigest,
    required this.journal,
    required this.freshSocketFactory,
    GatewayTurnIdFactory? uuidFactory,
    GatewayTurnClock? clock,
  }) : uuidFactory = uuidFactory ?? const Uuid().v4,
       clock = clock ?? (() => DateTime.now().toUtc()) {
    if (!_boundedIdentity(connectionId) || !_lowerHexDigest(endpointDigest)) {
      throw ArgumentError('Invalid coordinator registry identity.');
    }
  }

  /// Registers the current route owner for one local session's settlements.
  ///
  /// Replacing a route returns a new token. A late dispose from the previous
  /// route cannot unregister its replacement because removal is token-checked.
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  ) {
    if (!_boundedIdentity(localSessionId)) {
      throw ArgumentError.value(
        localSessionId,
        'localSessionId',
        'Invalid local session identity.',
      );
    }
    if (_closed) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.closed,
      );
    }
    final token = Object();
    _turnSettledListeners[localSessionId] = _GatewayTurnSettledRegistration(
      token,
      listener,
    );
    return token;
  }

  /// Removes a route's listener only when [registration] still owns it.
  void removeTurnSettledListener(String localSessionId, Object registration) {
    final current = _turnSettledListeners[localSessionId];
    if (current == null || !identical(current.token, registration)) return;
    _turnSettledListeners.remove(localSessionId);
  }

  /// True when any retained coordinator has an unresolved turn. The
  /// background keep-alive policy uses this to bound the foreground
  /// service to user-visible work instead of merely-live sockets.
  bool get hasActiveTurn => _coordinators.values.any((c) => c.hasActiveTurn);

  /// Registers an app-level observer notified whenever any coordinator's
  /// active-turn state may have changed. Listeners recompute [hasActiveTurn]
  /// themselves; notifications are deliberately value-less and idempotent.
  Object addTurnActivityListener(void Function() listener) {
    if (_closed) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.closed,
      );
    }
    final token = Object();
    _turnActivityListeners[token] = listener;
    return token;
  }

  void removeTurnActivityListener(Object token) {
    _turnActivityListeners.remove(token);
  }

  void _notifyTurnActivity() {
    for (final listener in _turnActivityListeners.values.toList(
      growable: false,
    )) {
      listener();
    }
  }

  /// Registers the current route owner for one local session's bindings.
  ///
  /// Retained coordinators dispatch through this map, so replacing a route
  /// takes effect without rebuilding its recovery transport.
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) {
    if (!_boundedIdentity(localSessionId)) {
      throw ArgumentError.value(
        localSessionId,
        'localSessionId',
        'Invalid local session identity.',
      );
    }
    if (_closed) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.closed,
      );
    }
    final token = Object();
    _sessionBoundListeners[localSessionId] =
        _GatewayTurnSessionBoundRegistration(token, listener);
    final durable = _coordinators[localSessionId]?.durableBinding;
    if (durable != null) {
      listener(localSessionId, durable.storedSessionId);
    }
    return token;
  }

  /// Removes a route's listener only when [registration] still owns it.
  void removeSessionBoundListener(String localSessionId, Object registration) {
    final current = _sessionBoundListeners[localSessionId];
    if (current == null || !identical(current.token, registration)) return;
    _sessionBoundListeners.remove(localSessionId);
  }

  Future<GatewayTurnCoordinator> open(String localSessionId) {
    if (!_boundedIdentity(localSessionId)) {
      throw ArgumentError.value(
        localSessionId,
        'localSessionId',
        'Invalid local session identity.',
      );
    }
    final requestedGeneration = _sessionGenerations[localSessionId] ?? 0;
    final requestedRegistryGeneration = _generation;
    return _serialized(() async {
      _requireOpenGeneration(
        localSessionId,
        requestedGeneration,
        requestedRegistryGeneration,
      );
      final coordinator = _coordinators.putIfAbsent(
        localSessionId,
        () =>
            GatewayTurnCoordinator(
                connectionId: connectionId,
                endpointDigest: endpointDigest,
                localSessionId: localSessionId,
                journal: journal,
                freshSocketFactory: _leaseFreshSocket,
                uuidFactory: uuidFactory,
                clock: clock,
              )
              ..onTurnSettled = (state) {
                _turnSettledListeners[localSessionId]?.listener(state);
              }
              ..onTurnActivityChanged = (_) {
                _notifyTurnActivity();
              }
              ..onSessionBound = (local, stored) {
                _sessionBoundListeners[localSessionId]?.listener(local, stored);
              }
              ..onRuntimeBound = onRuntimeBound,
      );
      Object? firstError;
      StackTrace? firstStack;
      try {
        await coordinator.ensureOpen();
        _requireOpenGeneration(
          localSessionId,
          requestedGeneration,
          requestedRegistryGeneration,
        );
        if (!identical(_coordinators[localSessionId], coordinator)) {
          throw const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.closed,
          );
        }
        return coordinator;
      } catch (error, stack) {
        firstError = error;
        firstStack = stack;
      }
      // A fail-closed state that could not be sealed durably is an absorbing
      // same-process stop. Keep this exact coordinator registered until an
      // explicit registry close resets its lifecycle.
      if (coordinator._isPoisoned) {
        Error.throwWithStackTrace(firstError, firstStack);
      }
      if (identical(_coordinators[localSessionId], coordinator)) {
        _coordinators.remove(localSessionId);
      }
      try {
        await coordinator.close();
      } catch (_) {
        // The open failure remains the primary result.
      }
      Error.throwWithStackTrace(firstError, firstStack);
    });
  }

  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
    bool Function()? maySubmit,
  }) async {
    if (maySubmit?.call() == false) throw const GatewayTurnAdmissionRevoked();
    final coordinator = await open(localSessionId);
    if (maySubmit?.call() == false) throw const GatewayTurnAdmissionRevoked();
    return coordinator.submit(
      text: text,
      attachments: attachments,
      onState: onState,
      maySubmit: maySubmit,
    );
  }

  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) async {
    final coordinator = await open(localSessionId);
    return coordinator.stageAttachment(
      clientAttachmentId: clientAttachmentId,
      name: name,
      dataUrl: dataUrl,
      byteLength: byteLength,
      mediaType: mediaType,
      kind: kind,
    );
  }

  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) async {
    final coordinator = await open(localSessionId);
    await coordinator.detachAttachments(attachments);
  }

  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async {
    final coordinator = await open(localSessionId);
    return coordinator.recoverPending(onState: onState);
  }

  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) async {
    final coordinator = await open(localSessionId);
    return coordinator.interrupt(clientTurnId);
  }

  Future<void> close(String localSessionId) {
    _sessionGenerations[localSessionId] =
        (_sessionGenerations[localSessionId] ?? 0) + 1;
    _turnSettledListeners.remove(localSessionId);
    _sessionBoundListeners.remove(localSessionId);
    return _serialized(() async {
      final coordinator = _coordinators[localSessionId];
      if (coordinator == null) return;
      try {
        await coordinator.close();
      } finally {
        if (identical(_coordinators[localSessionId], coordinator)) {
          _coordinators.remove(localSessionId);
        }
      }
    });
  }

  Future<void> closeAll() {
    if (_closed) return _tail;
    _closed = true;
    _generation += 1;
    _turnSettledListeners.clear();
    _turnActivityListeners.clear();
    _sessionBoundListeners.clear();
    return _serialized(() async {
      final coordinators = _coordinators.values.toList(growable: false);
      Object? firstError;
      StackTrace? firstStack;
      for (final coordinator in coordinators) {
        try {
          await coordinator.close();
        } catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
        }
      }
      _coordinators.clear();
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStack!);
      }
    });
  }

  Future<WsClient> _leaseFreshSocket() async {
    final client = await freshSocketFactory();
    if (_leasedSockets[client] == true) {
      throw StateError('The fresh socket factory reused a transport.');
    }
    _leasedSockets[client] = true;
    return client;
  }

  void _requireOpenGeneration(
    String localSessionId,
    int requestedGeneration,
    int requestedRegistryGeneration,
  ) {
    if (_closed ||
        _generation != requestedRegistryGeneration ||
        (_sessionGenerations[localSessionId] ?? 0) != requestedGeneration) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.closed,
      );
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_, _) {});
    return run;
  }
}

class _GatewayTurnSettledRegistration {
  final Object token;
  final GatewayTurnSettledCallback listener;

  const _GatewayTurnSettledRegistration(this.token, this.listener);
}

class _GatewayTurnSessionBoundRegistration {
  final Object token;
  final GatewayTurnSessionBoundCallback listener;

  const _GatewayTurnSessionBoundRegistration(this.token, this.listener);
}

/// Serializes one local chat's open/submit/event/reconcile lifecycle.
class GatewayTurnCoordinator {
  static const int maxSettledTombstones = GatewayTurnJournal.maxEntries;

  final String connectionId;
  final String endpointDigest;
  final String localSessionId;
  final GatewayTurnJournal journal;
  final GatewayTurnFreshSocketFactory freshSocketFactory;
  final GatewayTurnIdFactory uuidFactory;
  final GatewayTurnClock clock;

  final Map<String, GatewayTurnRecoveryState> _states = {};
  final Map<String, String> _clientTurnByTurnId = {};
  final Map<String, GatewayTurnStateCallback> _observers = {};
  final LinkedHashMap<String, GatewayTurnRecoveryState> _settledTombstones =
      LinkedHashMap<String, GatewayTurnRecoveryState>();
  final Map<String, int> _durableTimestampFloors = {};
  final Map<String, GatewayTurnAttachmentReceipt> _stagedAttachments = {};
  final Expando<bool> _usedSockets = Expando<bool>();
  Future<void> _tail = Future<void>.value();
  WsClient? _client;
  GatewaySessionBinding? _runtimeBinding;
  GatewayTurnJournalBinding? _durableBinding;
  int _transportGeneration = 0;
  bool _closed = false;

  /// Called exactly once when a turn is settled into the tombstone,
  /// whether completed successfully or fail-closed.
  GatewayTurnSettledCallback? onTurnSettled;

  /// Called after every mutation that can cross the active/inactive
  /// boundary (submit, settle, discard, recovery restore), reporting the
  /// coordinator's current `hasActiveTurn`. The value is idempotent —
  /// consumers recompute the aggregate — so redundant calls are harmless.
  /// The background keep-alive policy uses this to bound the foreground
  /// service to unresolved turns.
  void Function(bool active)? onTurnActivityChanged;

  /// True while at least one submitted turn is unresolved (in flight or
  /// awaiting reconcile) AND the transport is live. Settled turns live in
  /// tombstones and do not count. A turn whose socket was lost does not
  /// count either: the foreground service exists to protect a live socket,
  /// and with the transport gone there is nothing to protect — reconcile
  /// runs on resume (never an auto-resend), so an FGS on a dead connection
  /// would pin the process for a socket that cannot deliver anything.
  bool get hasActiveTurn => _states.isNotEmpty && _client?.isConnected == true;

  void _notifyTurnActivity() => onTurnActivityChanged?.call(hasActiveTurn);

  /// Called after every authoritative durable `session.open` binding.
  GatewayTurnSessionBoundCallback? onSessionBound;

  /// Called whenever this coordinator binds to a live runtime session id.
  GatewayTurnRuntimeBoundCallback? onRuntimeBound;

  GatewayTurnCoordinator({
    required this.connectionId,
    required this.endpointDigest,
    required this.localSessionId,
    required this.journal,
    required this.freshSocketFactory,
    required this.uuidFactory,
    required this.clock,
  }) {
    if (!_boundedIdentity(connectionId) ||
        !_lowerHexDigest(endpointDigest) ||
        !_boundedIdentity(localSessionId)) {
      throw ArgumentError('Invalid turn coordinator identity.');
    }
  }

  GatewaySessionBinding? get runtimeBinding => _runtimeBinding;

  GatewayTurnJournalBinding? get durableBinding => _durableBinding;

  GatewayTurnRecoveryState? stateFor(String clientTurnId) {
    final local = _states[clientTurnId] ?? _settledTombstones[clientTurnId];
    if (local != null) return local;
    final processFailure = _processPoisonedFailure;
    return processFailure?.clientTurnId == clientTurnId ? processFailure : null;
  }

  GatewayTurnCoordinatorRetentionSnapshot get retentionSnapshot {
    final retained = <GatewayTurnRecoveryState>[
      ..._states.values,
      ..._settledTombstones.values,
    ];
    return GatewayTurnCoordinatorRetentionSnapshot(
      activeStates: _states.length,
      settledTombstones: _settledTombstones.length,
      observers: _observers.length,
      activeTurnMappings: _clientTurnByTurnId.length,
      durableTimestampFloors: _durableTimestampFloors.length,
      retainedEventCount: retained.fold<int>(
        0,
        (total, state) => total + state.eventsBySeq.length,
      ),
      retainedSnapshots: retained
          .where((state) => state.snapshot != null)
          .length,
      poisoned: _isPoisoned,
    );
  }

  Future<void> waitForIdle() => _tail;

  Future<void> ensureOpen() => _serialized(() async {
    _requireOperational();
    if (_client?.isConnected == true && _runtimeBinding != null) return;
    await _openFreshTransport();
  });

  Future<GatewayTurnRecoveryState> submit({
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
    bool Function()? maySubmit,
  }) => _serialized(() async {
    _requireOperational();
    if (maySubmit?.call() == false) throw const GatewayTurnAdmissionRevoked();
    if (attachments.isNotEmpty &&
        (_client?.isConnected != true || _runtimeBinding == null)) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.transportUnavailable,
      );
    }
    if (_client?.isConnected != true || _runtimeBinding == null) {
      await _openFreshTransport();
    }
    if (maySubmit?.call() == false) throw const GatewayTurnAdmissionRevoked();
    final client = _client!;
    final runtime = _runtimeBinding!;
    final durable = _durableBinding!;
    final promptText = attachments.isEmpty
        ? AndroidPromptContext.forModel(text)
        : AndroidPromptContext.forAttachment(text);
    if (utf8.encode(promptText).length > runtime.capability.maxPromptBytes!) {
      throw ArgumentError.value(
        text,
        'text',
        'Prompt plus Android context exceeds gateway limit.',
      );
    }
    final wireAttachments = _validatedAttachments(attachments, runtime);

    final clientTurnId = uuidFactory();
    if (!_canonicalV4Uuid(clientTurnId) ||
        _states.containsKey(clientTurnId) ||
        _settledTombstones.containsKey(clientTurnId)) {
      throw StateError('The coordinator UUID source returned an invalid ID.');
    }
    var state = GatewayTurnRecoveryState.initial(
      clientTurnId: clientTurnId,
    ).markSubmissionStarted();
    _states[clientTurnId] = state;
    if (onState != null) _observers[clientTurnId] = onState;
    _notifyTurnActivity();

    // The durable read-back performed by GatewayTurnJournal completes before
    // the first and only prompt.submit write is allowed onto the socket.
    try {
      await _persistDurableState(durable, state);
    } catch (_) {
      _discardUnsubmittedState(state);
      rethrow;
    }
    _requireNotPoisoned();
    if (maySubmit?.call() == false) {
      // This exact write-ahead was never dispatched. Remove it before releasing
      // the local reservation; a failed durable removal stays fail-closed.
      await journal.remove(
        _entryFromState(
          durable,
          state,
          updatedAtEpochMs: _nowEpochMs(),
        ).entryIdentity,
      );
      _discardUnsubmittedState(state);
      throw const GatewayTurnAdmissionRevoked();
    }
    Map<String, dynamic> result;
    try {
      final response = await client.send('prompt.submit', <String, dynamic>{
        'session_id': runtime.runtimeSessionId,
        'version': GatewayTurnRecoveryCapability.promptSubmitVersion,
        'client_turn_id': clientTurnId,
        'text': promptText,
        if (wireAttachments.isNotEmpty) 'attachments': wireAttachments,
      });
      result = _resultOrThrow('prompt.submit', response);
    } on JsonRpcError catch (error, stack) {
      if (!_ambiguousJsonRpcFailure(error)) {
        await _detachRejectedSubmissionAttachments(
          client: client,
          runtime: runtime,
          attachments: attachments,
        );
        try {
          await journal.remove(
            _entryFromState(
              durable,
              state,
              updatedAtEpochMs: _nowEpochMs(),
            ).entryIdentity,
          );
        } catch (journalError, journalStack) {
          state = state.failReconcile(
            GatewayTurnRecoveryFailure.protocolViolation,
          );
          _remember(state);
          _poisonIfUnpersistedFailure(state);
          try {
            await _quarantineAndCloseExactSource(
              client,
              sourceOwnedAtDispatch: identical(_client, client),
              correlatedClientTurnId: state.clientTurnId,
            );
          } catch (_) {
            // Preserve the first journal failure after exact-source shutdown.
          }
          Error.throwWithStackTrace(journalError, journalStack);
        }
        _discardUnsubmittedState(state);
        Error.throwWithStackTrace(error, stack);
      }
      if (identical(_client, client) && client.isConnected) {
        return _reconcileSubmittedState(state, attachments);
      }
      rethrow;
    } on GatewayTurnCoordinatorException {
      // A malformed/missing acknowledgement is ambiguous. Resolve only from
      // server authority; this path never writes prompt.submit again.
      if (identical(_client, client) && client.isConnected) {
        return _reconcileSubmittedState(state, attachments);
      }
      rethrow;
    } catch (error, stack) {
      if (error is IOException || error is TimeoutException) {
        if (identical(_client, client) && client.isConnected) {
          return _reconcileSubmittedState(state, attachments);
        }
        rethrow;
      }
      state = state.failReconcile(GatewayTurnRecoveryFailure.protocolViolation);
      _remember(state);
      await _persistWireStateOrClose(state, client);
      Error.throwWithStackTrace(error, stack);
    }
    final ack = GatewayTurnAck.fromWire(result);
    if (ack == null) {
      if (identical(_client, client) && client.isConnected) {
        return _reconcileSubmittedState(state, attachments);
      }
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
    if (ack.clientTurnId != clientTurnId) {
      state = state.failReconcile(GatewayTurnRecoveryFailure.protocolViolation);
      _remember(state);
      await _persistWireStateOrClose(state, client);
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
    state = state.applyAck(ack);
    _remember(state);
    await _persistWireStateOrClose(state, client);
    _requireHealthy(state);
    if (state.requiredAction == GatewayTurnRecoveryAction.reconcile) {
      state = await _reconcile(state);
    }
    if (state.turnId != null) _consumeAttachments(attachments);
    return state;
  });

  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) => _serialized(() async {
    _requireOperational();
    if (!_boundedIdentity(clientAttachmentId) ||
        !_boundedIdentity(name) ||
        byteLength <= 0 ||
        !_validMediaType(mediaType) ||
        !dataUrl.startsWith('data:') ||
        !dataUrl.contains(';base64,')) {
      throw ArgumentError('Invalid recovery attachment.');
    }
    if (_client?.isConnected != true || _runtimeBinding == null) {
      await _openFreshTransport();
    }
    final client = _client!;
    final runtime = _runtimeBinding!;
    final capability = runtime.capability;
    if (!capability.attachmentsSupported) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.unsupportedCapability,
      );
    }
    final itemLimit = kind == GatewayTurnAttachmentKind.image
        ? capability.maxImageAttachmentBytes!
        : capability.maxFileAttachmentBytes!;
    final stagedBytes = _stagedAttachments.values.fold<int>(
      0,
      (total, receipt) => total + receipt.byteLength,
    );
    if (byteLength > itemLimit ||
        _stagedAttachments.length >= capability.maxAttachments! ||
        stagedBytes + byteLength > capability.maxAttachmentRegistryBytes!) {
      throw ArgumentError('Attachment exceeds negotiated recovery limits.');
    }

    final method = kind == GatewayTurnAttachmentKind.image
        ? 'image.attach_bytes'
        : 'file.attach';
    final params = kind == GatewayTurnAttachmentKind.image
        ? <String, dynamic>{
            'session_id': runtime.runtimeSessionId,
            'content_base64': dataUrl,
            'filename': name,
          }
        : <String, dynamic>{
            'session_id': runtime.runtimeSessionId,
            'name': name,
            'path': '',
            'data_url': dataUrl,
          };
    try {
      final response = await client.send(method, params);
      final result = _resultOrThrow(method, response);
      final receipt = _attachmentReceiptFromWire(
        result,
        clientAttachmentId: clientAttachmentId,
        expectedByteLength: byteLength,
        kind: kind,
      );
      if (_stagedAttachments.containsKey(receipt.attachmentId)) {
        throw const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidResponse,
        );
      }
      _stagedAttachments[receipt.attachmentId] = receipt;
      return receipt;
    } catch (error) {
      if (error is IOException || error is TimeoutException) {
        // The transport-lost bookkeeping must never replace the original
        // upload failure the caller needs to classify: a journal error
        // inside _markTransportLost would mask an IOException as a
        // storage exception.
        try {
          await _markTransportLost(client);
        } catch (_) {
          // Best-effort; the original error below is the truth.
        }
      }
      rethrow;
    }
  });

  Future<void> detachAttachments(
    Iterable<GatewayTurnAttachmentReceipt> attachments,
  ) => _serialized(() async {
    _requireOperational();
    final client = _client;
    final runtime = _runtimeBinding;
    if (client == null || !client.isConnected || runtime == null) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.transportUnavailable,
      );
    }
    final snapshot = attachments.toList(growable: false);
    _validatedAttachments(snapshot, runtime);
    for (final receipt in snapshot) {
      final response = await client.send('attachment.detach', <String, dynamic>{
        'session_id': runtime.runtimeSessionId,
        'version': GatewayTurnRecoveryCapability.promptSubmitVersion,
        'attachment_id': receipt.attachmentId,
      });
      final result = _resultOrThrow('attachment.detach', response);
      if (result['detached'] != true ||
          result['attachment_id'] != receipt.attachmentId) {
        throw const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidResponse,
        );
      }
      _stagedAttachments.remove(receipt.attachmentId);
    }
  });

  Future<List<GatewayTurnRecoveryState>> recoverPending({
    GatewayTurnStateCallback? onState,
  }) => _serialized(() async {
    _requireOperational();
    if (_client?.isConnected != true || _runtimeBinding == null) {
      await _openFreshTransport(recoverJournal: false);
    }
    return _recoverJournal(onState: onState);
  });

  Future<GatewayTurnRecoveryState> interrupt(String clientTurnId) =>
      _serialized(() async {
        _requireOperational();
        final client = _client;
        final runtime = _runtimeBinding;
        final state = _states[clientTurnId];
        if (client == null ||
            !client.isConnected ||
            runtime == null ||
            state == null ||
            state.isTerminal ||
            state.isFailClosed) {
          throw const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.transportUnavailable,
          );
        }
        final params = <String, dynamic>{
          'session_id': runtime.runtimeSessionId,
          if (state.turnId != null) 'turn_id': state.turnId,
          if (state.turnId == null) 'client_turn_id': clientTurnId,
        };
        final uncertain = state.markDisconnected();
        _remember(uncertain);
        await _persistAndNotify(uncertain);
        _requireNotPoisoned();
        Map<String, dynamic> result;
        try {
          final response = await client.send('turn.interrupt', params);
          result = _resultOrThrow('turn.interrupt', response);
        } catch (_) {
          if (identical(_client, client) && client.isConnected) {
            return _reconcile(uncertain);
          }
          rethrow;
        }
        if (result['automatic_resubmit'] != false ||
            result['client_turn_id'] != clientTurnId ||
            state.turnId != null && result['turn_id'] != state.turnId ||
            GatewayRecoveryTurnStatus.fromWire(result['status']) == null ||
            result['last_seq'] is! int ||
            (result['last_seq'] as int) < state.lastSeq) {
          if (identical(_client, client) && client.isConnected) {
            return _reconcile(uncertain);
          }
          throw const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.invalidResponse,
          );
        }
        return _reconcile(uncertain);
      });

  Future<void> close() => _serialized(() async {
    if (_closed) return;
    _closed = true;
    final client = _client;
    _client = null;
    _runtimeBinding = null;
    _invalidateStagedAttachments();
    client?.onConnectionChanged = null;
    client?.onStreamEvent = null;
    Object? firstError;
    StackTrace? firstStack;
    try {
      await _markAllDisconnectedBestEffort();
    } catch (error, stack) {
      firstError = error;
      firstStack = stack;
    } finally {
      try {
        client?.close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      } finally {
        _releaseAllMemory();
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  });

  Future<void> _openFreshTransport({bool recoverJournal = true}) async {
    _requireOperational();
    final previous = await journal.loadBinding(
      connectionId: connectionId,
      endpointDigest: endpointDigest,
      localSessionId: localSessionId,
    );
    _requireOperational();
    final generatedMobileSessionId = previous == null;
    final mobileSessionId = previous?.mobileSessionId ?? uuidFactory();
    if (generatedMobileSessionId
        ? !_canonicalV4Uuid(mobileSessionId)
        : !_canonicalPersistedUuid(mobileSessionId)) {
      throw StateError('The coordinator mobile UUID is invalid.');
    }
    final client = await freshSocketFactory();
    if (_usedSockets[client] == true) {
      throw StateError('The coordinator socket factory reused a transport.');
    }
    _usedSockets[client] = true;
    final inheritedStreamListener = client.onStreamEvent;
    client.onStreamEvent = (event) {
      final receivedAt = clock();
      inheritedStreamListener?.call(event);
      _observeSocketAction(
        client,
        () => _handleLiveEvent(client, event, receivedAt),
      );
    };
    final inheritedConnectionListener = client.onConnectionChanged;
    client.onConnectionChanged = (connected) {
      inheritedConnectionListener?.call(connected);
      if (!connected) {
        _observeSocketAction(client, () => _markTransportLost(client));
      }
    };
    try {
      _requireOperational();
      await client.connect();
      _requireOperational();
      final readyFrame = await client.waitForGatewayReady();
      final ready = GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
        readyFrame,
      );
      _requireOperational();
      if (!_coordinatorCapabilitySupported(ready)) {
        if (!_readyFailureAllowsLegacy(ready.failure, readyFrame)) {
          throw const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.invalidResponse,
          );
        }
        final failure = await _unsupportedReadyFailure(previous);
        // The clean-absence label must never ride along with pending
        // durable turns: a stock gateway WITH pending turns is not a
        // calm "server just doesn't offer recovery" state. The invariant
        // is clean absence only.
        final cleanAbsence =
            failure == GatewayTurnCoordinatorFailure.unsupportedCapability &&
            _readyLacksRecoveryContractCleanly(ready.failure, readyFrame);
        throw GatewayTurnCoordinatorException(
          failure,
          stockGateway: cleanAbsence,
        );
      }
      final openResponse = await client.send('session.open', <String, dynamic>{
        'mobile_session_id': mobileSessionId,
      });
      _requireOperational();
      final openResult = _resultOrThrow('session.open', openResponse);
      final binding = GatewaySessionBinding.fromWire(
        openResult,
        readyCapability: ready,
        expectedMobileSessionId: mobileSessionId,
        expectedStoredSessionId: previous?.storedSessionId,
        minimumBindingVersion: previous == null
            ? null
            : previous.bindingVersion + 1,
      );
      if (binding == null ||
          !_coordinatorCapabilitySupported(binding.capability)) {
        throw const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidBinding,
        );
      }
      final durable = GatewayTurnJournalBinding(
        connectionId: connectionId,
        endpointDigest: endpointDigest,
        localSessionId: localSessionId,
        mobileSessionId: binding.mobileSessionId,
        storedSessionId: binding.storedSessionId,
        bindingVersion: binding.bindingVersion,
        updatedAtEpochMs: _causalTimestamp(
          previous?.updatedAtEpochMs,
          _nowEpochMs(),
        ),
      );
      await journal.upsertBinding(durable);
      _requireOperational();
      // The binding version is authoritative even when this is a reconnect.
      // Notify after its journal write so consumers can safely reconcile
      // metadata against the current durable identity.
      onSessionBound?.call(localSessionId, durable.storedSessionId);
      _invalidateStagedAttachments();
      _transportGeneration += 1;
      _client = client;
      _runtimeBinding = binding;
      _durableBinding = durable;
      onRuntimeBound?.call(localSessionId, binding.runtimeSessionId);
      if (recoverJournal) await _recoverJournal();
    } catch (error, stack) {
      if (identical(_client, client)) {
        _client = null;
        _runtimeBinding = null;
      }
      client.onConnectionChanged = null;
      client.onStreamEvent = null;
      try {
        client.close();
      } catch (_) {
        // Preserve the open failure after guaranteed close was attempted.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Legacy transport is safe only when the capability decision precedes all
  /// v2 writes and the previous durable binding has no unresolved authority.
  Future<GatewayTurnCoordinatorFailure> _unsupportedReadyFailure(
    GatewayTurnJournalBinding? previous,
  ) async {
    if (previous == null) {
      return GatewayTurnCoordinatorFailure.unsupportedCapability;
    }
    final entries = await journal.loadForBinding(previous);
    final hasUnsafeEntry = entries.any(
      (entry) =>
          !entry.isTerminal || entry.ackUncertain || entry.failure != null,
    );
    return hasUnsafeEntry
        ? GatewayTurnCoordinatorFailure.unsupportedCapabilityWithPendingTurns
        : GatewayTurnCoordinatorFailure.unsupportedCapability;
  }

  Future<List<GatewayTurnRecoveryState>> _recoverJournal({
    GatewayTurnStateCallback? onState,
  }) async {
    final durable = _durableBinding!;
    final entries = await journal.loadForBinding(durable);
    final recovered = <GatewayTurnRecoveryState>[];
    for (final entry in entries) {
      _durableTimestampFloors[entry.clientTurnId] = entry.updatedAtEpochMs;
      if (onState != null && entry.failure == null && !entry.isTerminal) {
        _observers[entry.clientTurnId] = onState;
      }
      var state = _states[entry.clientTurnId];
      if (state == null) {
        state = GatewayTurnRecoveryState.rehydrate(
          clientTurnId: entry.clientTurnId,
          turnId: entry.turnId,
          status: entry.status,
          lastSeq: entry.lastSeq,
          ackUncertain: entry.ackUncertain,
          eventPayloadBytes: entry.eventPayloadBytes,
          terminalEventRecorded: entry.terminalEventRecorded,
          terminalResult: entry.terminalResult,
          failure: entry.failure,
        );
        _states[entry.clientTurnId] = state;
        if (entry.turnId != null) {
          _clientTurnByTurnId[entry.turnId!] = entry.clientTurnId;
        }
        _notifyTurnActivity();
      }
      if (!_stateBytesWithinCapability(state, _runtimeBinding!.capability)) {
        state = state.failReconcile(
          GatewayTurnRecoveryFailure.protocolViolation,
        );
        _remember(state);
        await _persistWireStateOrClose(state, _client!);
      }
      if (state.isFailClosed) {
        _settleState(state);
      }
      _requireHealthy(state);
      if (state.requiredAction == GatewayTurnRecoveryAction.none) {
        recovered.add(state);
        if (onState != null) {
          try {
            onState(state);
          } catch (_) {
            // An already durable state remains authoritative.
          }
        }
        _settleIfDone(state);
        continue;
      }
      recovered.add(await _reconcile(state, durableCursor: entry));
    }
    return List<GatewayTurnRecoveryState>.unmodifiable(recovered);
  }

  Future<GatewayTurnRecoveryState> _reconcile(
    GatewayTurnRecoveryState state, {
    GatewayTurnJournalEntry? durableCursor,
  }) async {
    _requireNotPoisoned();
    final client = _client;
    final runtime = _runtimeBinding;
    if (client == null || !client.isConnected || runtime == null) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.transportUnavailable,
      );
    }
    var pinnedTurnId = state.turnId ?? durableCursor?.turnId;
    var cursor = durableCursor?.lastSeq ?? state.lastSeq;
    while (true) {
      final params = <String, dynamic>{
        'session_id': runtime.runtimeSessionId,
        'turn_id': ?pinnedTurnId,
        if (pinnedTurnId == null) 'client_turn_id': state.clientTurnId,
        'after_seq': cursor,
      };
      Map<String, dynamic> result;
      try {
        _requireNotPoisoned();
        final response = await client.send('turn.reconcile', params);
        result = _resultOrThrow('turn.reconcile', response);
      } on JsonRpcError catch (error) {
        if (error.reason == 'connection_closed' || error.message == 'Timeout') {
          rethrow;
        }
        final failure = switch (error.reason) {
          'turn_unknown' => GatewayTurnRecoveryFailure.turnUnknown,
          'turn_replay_pruned' => GatewayTurnRecoveryFailure.replayPruned,
          _ => GatewayTurnRecoveryFailure.protocolViolation,
        };
        state = state.failReconcile(failure);
        _remember(state);
        await _persistWireStateOrClose(state, client);
        throw GatewayTurnCoordinatorException(switch (failure) {
          GatewayTurnRecoveryFailure.turnUnknown =>
            GatewayTurnCoordinatorFailure.turnUnknown,
          GatewayTurnRecoveryFailure.replayPruned =>
            GatewayTurnCoordinatorFailure.replayPruned,
          _ => GatewayTurnCoordinatorFailure.invalidResponse,
        });
      } on GatewayTurnCoordinatorException {
        state = state.failReconcile(
          GatewayTurnRecoveryFailure.protocolViolation,
        );
        _remember(state);
        await _persistWireStateOrClose(state, client);
        throw const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidResponse,
        );
      }
      if (utf8.encode(jsonEncode(result)).length >
          runtime.capability.reconcileMaxPageBytes!) {
        state = state.failReconcile(
          GatewayTurnRecoveryFailure.protocolViolation,
        );
        _remember(state);
        await _persistWireStateOrClose(state, client);
        throw const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidResponse,
        );
      }
      final page = GatewayTurnReconcilePage.fromWire(
        result,
        expectedAfterSeq: cursor,
        expectedTurnId: pinnedTurnId,
        expectedClientTurnId: state.clientTurnId,
      );
      if (page == null ||
          page.events.length > runtime.capability.reconcileMaxEvents! ||
          page.hasMore && page.nextAfterSeq <= cursor) {
        state = state.failReconcile(
          GatewayTurnRecoveryFailure.protocolViolation,
        );
        _remember(state);
        await _persistWireStateOrClose(state, client);
        throw const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidResponse,
        );
      }
      state = _applyBoundedReconcilePage(state, page, runtime.capability);
      _remember(state);
      if (state.isFailClosed) {
        await _persistWireStateOrClose(state, client);
        _requireHealthy(state);
      }
      if (durableCursor == null || state.lastSeq >= durableCursor.lastSeq) {
        await _persistWireStateOrClose(state, client);
        durableCursor = null;
      }
      if (!page.hasMore) return state;
      pinnedTurnId ??= page.turnId;
      cursor = page.nextAfterSeq;
    }
  }

  Future<void> _handleLiveEvent(
    WsClient source,
    StreamEvent event,
    DateTime receivedAt,
  ) async {
    final runtime = _runtimeBinding;
    if (!identical(_client, source) ||
        runtime == null ||
        event.sessionId != runtime.runtimeSessionId) {
      return;
    }
    var correlatedClientTurnId = _clientTurnIdForTurnId(
      event.envelope['turn_id'],
    );
    final parsed = GatewayTurnEvent.fromWire(event.envelope);
    if (parsed == null) {
      if (GatewayTurnEvent.allowedTypes.contains(event.type)) {
        await _failActiveProtocol(
          source,
          correlatedClientTurnId: correlatedClientTurnId,
        );
      }
      return;
    }
    final clientTurnId =
        _clientTurnByTurnId[parsed.turnId] ??
        _clientTurnIdForTurnId(parsed.turnId);
    if (clientTurnId == null) {
      await _failActiveProtocol(source);
      return;
    }
    correlatedClientTurnId = clientTurnId;
    var state = _states[clientTurnId];
    if (state == null) {
      // A bounded settled tombstone can correlate a late frame, but terminal
      // history is never resurrected or converted into a durable failure.
      await _failActiveProtocol(
        source,
        correlatedClientTurnId: correlatedClientTurnId,
      );
      return;
    }
    try {
      final previousSeq = state.lastSeq;
      state = _applyBoundedEvent(state, parsed, runtime.capability);
      if (state.lastSeq > previousSeq &&
          !state.isFailClosed &&
          parsed.type.startsWith('message.')) {
        state = state.observeLiveMessage(parsed.messageId, receivedAt);
      }
      _remember(state);
      await _persistAndNotify(state);
      _requireHealthy(state);
      if (state.requiredAction == GatewayTurnRecoveryAction.reconcile) {
        await _reconcile(state);
      }
    } catch (_) {
      try {
        await _quarantineAndCloseExactSource(
          source,
          correlatedClientTurnId: correlatedClientTurnId,
        );
      } finally {
        if (state != null) _settleIfDone(state);
      }
    }
  }

  Future<void> _failActiveProtocol(
    WsClient source, {
    String? correlatedClientTurnId,
  }) async {
    await _quarantineAndCloseExactSource(
      source,
      correlatedClientTurnId: correlatedClientTurnId,
    );
  }

  Future<void> _markTransportLost(WsClient source) async {
    if (!identical(_client, source)) return;
    _client = null;
    _runtimeBinding = null;
    _invalidateStagedAttachments();
    source.onConnectionChanged = null;
    source.onStreamEvent = null;
    Object? firstError;
    StackTrace? firstStack;
    try {
      await _markAllDisconnectedBestEffort();
    } catch (error, stack) {
      firstError = error;
      firstStack = stack;
    } finally {
      try {
        source.close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
      // The transport is gone: the keep-alive signal must drop even when
      // no state changed (an already-uncertain turn would otherwise pin
      // the foreground service on a dead socket until resume).
      _notifyTurnActivity();
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  Future<void> _markAllDisconnectedBestEffort() async {
    Object? firstError;
    StackTrace? firstStack;
    for (final entry in _states.entries.toList(growable: false)) {
      final previous = entry.value;
      if (previous.isTerminal || previous.isFailClosed) {
        _settleState(previous);
        continue;
      }
      final state = previous.markDisconnected();
      if (state.ackUncertain == previous.ackUncertain &&
          state.reconcilePending == previous.reconcilePending) {
        continue;
      }
      _states[entry.key] = state;
      try {
        await _persistAndNotify(state);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  Future<void> _quarantineAndCloseExactSource(
    WsClient source, {
    bool sourceOwnedAtDispatch = false,
    String? correlatedClientTurnId,
  }) async {
    final ownsSource = identical(_client, source);
    final quarantineStates =
        ownsSource || sourceOwnedAtDispatch && _client == null;
    if (ownsSource) {
      _client = null;
      _runtimeBinding = null;
      _invalidateStagedAttachments();
    }
    source.onConnectionChanged = null;
    source.onStreamEvent = null;
    Object? firstError;
    StackTrace? firstStack;
    try {
      if (quarantineStates) {
        final candidates = correlatedClientTurnId == null
            ? _states.entries.toList(growable: false)
            : <MapEntry<String, GatewayTurnRecoveryState>>[
                if (_states[correlatedClientTurnId] case final state?)
                  MapEntry<String, GatewayTurnRecoveryState>(
                    correlatedClientTurnId,
                    state,
                  ),
              ];
        for (final entry in candidates) {
          if (entry.value.isTerminal || entry.value.isFailClosed) continue;
          final failed = entry.value.failReconcile(
            GatewayTurnRecoveryFailure.protocolViolation,
          );
          _states[entry.key] = failed;
          try {
            await _persistAndNotify(failed);
          } catch (error, stack) {
            firstError ??= error;
            firstStack ??= stack;
          } finally {
            _settleState(failed);
          }
        }
        try {
          // Closing the shared source makes every non-target active turn
          // uncertain. They reconcile later; they are not quarantined merely
          // because another correlated turn violated protocol.
          await _markAllDisconnectedBestEffort();
        } catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
        }
      }
    } finally {
      try {
        source.close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
      // The transport is gone: the keep-alive signal must drop even when
      // no state changed (an already-uncertain turn would otherwise pin
      // the foreground service on a dead socket until resume).
      _notifyTurnActivity();
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  void _observeSocketAction(WsClient source, Future<void> Function() action) {
    final run = _serialized(() async {
      try {
        await action();
      } catch (_) {
        try {
          if (identical(_client, source)) {
            await _markTransportLost(source);
          } else {
            source.onConnectionChanged = null;
            source.onStreamEvent = null;
            source.close();
          }
        } catch (_) {
          source.onConnectionChanged = null;
          source.onStreamEvent = null;
          try {
            source.close();
          } catch (_) {
            // Callback failures have no caller; close was still attempted.
          }
        }
      }
    });
    unawaited(run.then<void>((_) {}, onError: (_, _) {}));
  }

  GatewayTurnRecoveryState _applyBoundedReconcilePage(
    GatewayTurnRecoveryState state,
    GatewayTurnReconcilePage page,
    GatewayTurnRecoveryCapability capability,
  ) {
    if (page.mode == GatewayTurnReconcileMode.snapshot) {
      final snapshot = page.snapshot;
      if (snapshot == null ||
          utf8.encode(snapshot.assistant.text).length >
              capability.maxTurnBytes!) {
        return state.failReconcile(
          GatewayTurnRecoveryFailure.protocolViolation,
        );
      }
      return state.applyReconcilePage(page);
    }
    final payloadBytesBySeq = <int, int>{};
    var probe = state;
    for (final event in page.events) {
      final payloadBytes = GatewayTurnRecoveryState.payloadBytesFor(event);
      payloadBytesBySeq[event.seq] = payloadBytes;
      probe = _applyBoundedEvent(probe, event, capability);
      if (probe.isFailClosed) return probe;
    }
    return state.applyReconcilePage(page, payloadBytesBySeq: payloadBytesBySeq);
  }

  GatewayTurnRecoveryState _applyBoundedEvent(
    GatewayTurnRecoveryState state,
    GatewayTurnEvent event,
    GatewayTurnRecoveryCapability capability,
  ) {
    final payloadBytes = GatewayTurnRecoveryState.payloadBytesFor(event);
    if (payloadBytes > capability.maxEventBytes!) {
      return state.failReconcile(GatewayTurnRecoveryFailure.protocolViolation);
    }
    final newlyAccepted = event.seq == state.lastSeq + 1;
    final next = state.applyEvent(
      event,
      payloadBytes: newlyAccepted ? payloadBytes : 0,
    );
    if (!newlyAccepted || next.isFailClosed) return next;
    final maxTurnBytes = capability.maxTurnBytes!;
    final allowed = next.terminalEventRecorded
        ? maxTurnBytes
        : maxTurnBytes - capability.terminalEventReserveBytes!;
    if (allowed < 0 || next.eventPayloadBytes > allowed) {
      return state.failReconcile(GatewayTurnRecoveryFailure.protocolViolation);
    }
    return next;
  }

  bool _stateBytesWithinCapability(
    GatewayTurnRecoveryState state,
    GatewayTurnRecoveryCapability capability,
  ) {
    final maxTurnBytes = capability.maxTurnBytes!;
    final allowed = state.terminalEventRecorded
        ? maxTurnBytes
        : maxTurnBytes - capability.terminalEventReserveBytes!;
    return allowed >= 0 && state.eventPayloadBytes <= allowed;
  }

  void _remember(GatewayTurnRecoveryState state) {
    _settledTombstones.remove(state.clientTurnId);
    _states[state.clientTurnId] = state;
    if (state.turnId != null) {
      _clientTurnByTurnId[state.turnId!] = state.clientTurnId;
    }
    _notifyTurnActivity();
  }

  Future<void> _persistAndNotify(GatewayTurnRecoveryState state) async {
    final durable = _durableBinding;
    if (durable == null) {
      _poisonIfUnpersistedFailure(state);
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidBinding,
      );
    }
    await _persistDurableState(durable, state);
    try {
      _observers[state.clientTurnId]?.call(state);
    } catch (_) {
      // Durable state is authoritative; observer code cannot fail the turn.
    }
    _settleIfDone(state);
  }

  Future<void> _persistDurableState(
    GatewayTurnJournalBinding durable,
    GatewayTurnRecoveryState state,
  ) async {
    try {
      final entry = _entryFromState(
        durable,
        state,
        updatedAtEpochMs: _causalTimestamp(
          _durableTimestampFloors[state.clientTurnId],
          _nowEpochMs(),
        ),
      );
      await journal.upsert(entry);
      _durableTimestampFloors[state.clientTurnId] = entry.updatedAtEpochMs;
    } catch (_) {
      _poisonIfUnpersistedFailure(state);
      rethrow;
    }
  }

  Future<void> _persistWireStateOrClose(
    GatewayTurnRecoveryState state,
    WsClient source,
  ) async {
    try {
      await _persistAndNotify(state);
    } catch (error, stack) {
      try {
        await _quarantineAndCloseExactSource(
          source,
          sourceOwnedAtDispatch: identical(_client, source),
          correlatedClientTurnId: state.clientTurnId,
        );
      } catch (_) {
        // Preserve the first journal failure after exact-source shutdown.
      } finally {
        _settleIfDone(state);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  GatewayTurnJournalEntry _entryFromState(
    GatewayTurnJournalBinding durable,
    GatewayTurnRecoveryState state, {
    required int updatedAtEpochMs,
  }) => GatewayTurnJournalEntry(
    bindingIdentity: durable.bindingIdentity,
    clientTurnId: state.clientTurnId,
    turnId: state.turnId,
    status: state.status,
    lastSeq: state.lastSeq,
    eventPayloadBytes: state.eventPayloadBytes,
    terminalEventRecorded: state.terminalEventRecorded,
    terminalResult: state.terminalResult,
    ackUncertain: state.ackUncertain,
    failure: state.failure,
    updatedAtEpochMs: updatedAtEpochMs,
  );

  void _settleIfDone(GatewayTurnRecoveryState state) {
    if (state.isFailClosed ||
        state.isTerminal &&
            state.requiredAction == GatewayTurnRecoveryAction.none) {
      _settleState(state);
    }
  }

  void _settleState(GatewayTurnRecoveryState state) {
    _states.remove(state.clientTurnId);
    final turnId = state.turnId;
    if (turnId != null && _clientTurnByTurnId[turnId] == state.clientTurnId) {
      _clientTurnByTurnId.remove(turnId);
    }
    _observers.remove(state.clientTurnId);
    _durableTimestampFloors.remove(state.clientTurnId);
    _settledTombstones.remove(state.clientTurnId);
    _settledTombstones[state.clientTurnId] = state.releasePayloads();
    while (_settledTombstones.length > maxSettledTombstones) {
      _settledTombstones.remove(_settledTombstones.keys.first);
    }
    _notifyTurnActivity();
    onTurnSettled?.call(state);
  }

  void _discardUnsubmittedState(GatewayTurnRecoveryState state) {
    _states.remove(state.clientTurnId);
    _observers.remove(state.clientTurnId);
    _durableTimestampFloors.remove(state.clientTurnId);
    final turnId = state.turnId;
    if (turnId != null && _clientTurnByTurnId[turnId] == state.clientTurnId) {
      _clientTurnByTurnId.remove(turnId);
    }
    _notifyTurnActivity();
  }

  void _releaseAllMemory() {
    final wasActive = _states.isNotEmpty;
    _states.clear();
    _clientTurnByTurnId.clear();
    _observers.clear();
    _settledTombstones.clear();
    _durableTimestampFloors.clear();
    _invalidateStagedAttachments();
    if (wasActive) _notifyTurnActivity();
  }

  GatewayTurnRecoveryState? get _processPoisonedFailure =>
      journal.processPoisonedFailure(
        connectionId: connectionId,
        endpointDigest: endpointDigest,
        localSessionId: localSessionId,
      );

  bool get _isPoisoned => _processPoisonedFailure != null;

  void _poisonIfUnpersistedFailure(GatewayTurnRecoveryState state) {
    if (!state.isFailClosed || _isPoisoned) return;
    journal.recordProcessPoison(
      connectionId: connectionId,
      endpointDigest: endpointDigest,
      localSessionId: localSessionId,
      failure: state,
    );
  }

  String? _clientTurnIdForTurnId(Object? rawTurnId) {
    if (rawTurnId is! String) return null;
    final active = _clientTurnByTurnId[rawTurnId];
    if (active != null) return active;
    for (final entry in _settledTombstones.entries) {
      if (entry.value.turnId == rawTurnId) return entry.key;
    }
    return null;
  }

  int _nowEpochMs() {
    final value = clock().toUtc().millisecondsSinceEpoch;
    if (value <= 0) throw StateError('Coordinator clock is invalid.');
    return value;
  }

  List<Map<String, Object>> _validatedAttachments(
    Iterable<GatewayTurnAttachmentReceipt> attachments,
    GatewaySessionBinding runtime,
  ) {
    final snapshot = attachments.toList(growable: false);
    final capability = runtime.capability;
    if (snapshot.isEmpty) return const [];
    if (!capability.attachmentsSupported ||
        snapshot.length > capability.maxAttachments!) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.unsupportedCapability,
      );
    }
    final seen = <String>{};
    var totalBytes = 0;
    for (final receipt in snapshot) {
      final staged = _stagedAttachments[receipt.attachmentId];
      final itemLimit = receipt.kind == GatewayTurnAttachmentKind.image
          ? capability.maxImageAttachmentBytes!
          : capability.maxFileAttachmentBytes!;
      if (!identical(staged, receipt) ||
          receipt._transportGeneration != _transportGeneration ||
          !seen.add(receipt.attachmentId) ||
          receipt.byteLength > itemLimit) {
        throw const GatewayTurnCoordinatorException(
          GatewayTurnCoordinatorFailure.invalidResponse,
        );
      }
      totalBytes += receipt.byteLength;
    }
    if (totalBytes > capability.maxAttachmentRegistryBytes!) {
      throw ArgumentError('Attachments exceed the negotiated aggregate limit.');
    }
    return List<Map<String, Object>>.unmodifiable(
      snapshot.map((receipt) => receipt.toWire()),
    );
  }

  GatewayTurnAttachmentReceipt _attachmentReceiptFromWire(
    Map<String, dynamic> result, {
    required String clientAttachmentId,
    required int expectedByteLength,
    required GatewayTurnAttachmentKind kind,
  }) {
    if (result['attached'] != true ||
        result.keys.any(const {'path', 'ref_path', 'ref_text'}.contains)) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
    final attachmentId = result['attachment_id'];
    final digest = result['sha256'];
    final byteLength = result['byte_length'];
    final mediaType = result['media_type'];
    if (attachmentId is! String ||
        !_boundedIdentity(attachmentId) ||
        digest is! String ||
        !_lowerHexDigest(digest) ||
        byteLength is! int ||
        byteLength != expectedByteLength ||
        mediaType is! String ||
        !_validMediaType(mediaType)) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
    return GatewayTurnAttachmentReceipt._(
      attachmentId: attachmentId,
      clientAttachmentId: clientAttachmentId,
      sha256: digest,
      byteLength: byteLength,
      mediaType: mediaType,
      kind: kind,
      transportGeneration: _transportGeneration,
    );
  }

  void _consumeAttachments(Iterable<GatewayTurnAttachmentReceipt> attachments) {
    for (final receipt in attachments) {
      if (identical(_stagedAttachments[receipt.attachmentId], receipt)) {
        _stagedAttachments.remove(receipt.attachmentId);
      }
    }
  }

  Future<GatewayTurnRecoveryState> _reconcileSubmittedState(
    GatewayTurnRecoveryState state,
    Iterable<GatewayTurnAttachmentReceipt> attachments,
  ) async {
    final reconciled = await _reconcile(state);
    if (reconciled.turnId != null) _consumeAttachments(attachments);
    return reconciled;
  }

  Future<void> _detachRejectedSubmissionAttachments({
    required WsClient client,
    required GatewaySessionBinding runtime,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) async {
    for (final receipt in attachments) {
      try {
        final response = await client
            .send('attachment.detach', <String, dynamic>{
              'session_id': runtime.runtimeSessionId,
              'version': GatewayTurnRecoveryCapability.promptSubmitVersion,
              'attachment_id': receipt.attachmentId,
            });
        final result = _resultOrThrow('attachment.detach', response);
        if (result['detached'] != true ||
            result['attachment_id'] != receipt.attachmentId) {
          throw const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.invalidResponse,
          );
        }
        _stagedAttachments.remove(receipt.attachmentId);
      } catch (_) {
        await _markTransportLost(client);
        return;
      }
    }
  }

  void _invalidateStagedAttachments() => _stagedAttachments.clear();

  Map<String, dynamic> _resultOrThrow(
    String method,
    Map<String, dynamic> response,
  ) {
    final error = response['error'];
    if (error != null) {
      if (error is Map) {
        throw JsonRpcError.fromGateway(
          method,
          error,
          fallbackMessage: 'Gateway request failed.',
        );
      }
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
    final result = response['result'];
    if (result is! Map) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
    return <String, dynamic>{
      for (final entry in result.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  void _requireHealthy(GatewayTurnRecoveryState state) {
    if (state.isFailClosed) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
  }

  void _requireNotClosed() {
    if (_closed) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.closed,
      );
    }
  }

  void _requireNotPoisoned() {
    if (_isPoisoned) {
      throw const GatewayTurnCoordinatorException(
        GatewayTurnCoordinatorFailure.invalidResponse,
      );
    }
  }

  void _requireOperational() {
    _requireNotClosed();
    _requireNotPoisoned();
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then<void>((_) {}, onError: (_, _) {});
    return run;
  }
}

bool _canonicalV4Uuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);

bool _canonicalPersistedUuid(String value) =>
    value != '00000000-0000-0000-0000-000000000000' &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value);

bool _ambiguousJsonRpcFailure(JsonRpcError error) {
  if (error.message == 'Timeout') return true;
  return const <String>{
    'connection_closed',
    'transport_closed',
    'transport_error',
    'websocket_error',
    'socket_error',
  }.contains(error.reason);
}

/// Whether the gateway returned an authoritative rejection rather than an
/// ambiguous transport outcome. This never grants automatic resubmission; it
/// only lets the composer restore the user's local draft for an explicit edit.
bool gatewayTurnSubmissionWasDefinitelyRejected(Object error) =>
    error is JsonRpcError && !_ambiguousJsonRpcFailure(error);

bool _coordinatorCapabilitySupported(GatewayTurnRecoveryCapability capability) {
  final maxTurnBytes = capability.maxTurnBytes;
  final terminalReserveBytes = capability.terminalEventReserveBytes;
  return capability.supported &&
      maxTurnBytes != null &&
      terminalReserveBytes != null &&
      terminalReserveBytes <= maxTurnBytes;
}

bool _readyFailureAllowsLegacy(
  GatewayTurnCapabilityFailure failure,
  Map<String, dynamic> frame,
) {
  final params = frame['params'];
  if (params is! Map<String, dynamic> || params['type'] != 'gateway.ready') {
    return false;
  }
  final payload = params['payload'];
  if (payload is! Map<String, dynamic>) return false;
  final protocol = payload['protocol'];
  switch (failure) {
    case GatewayTurnCapabilityFailure.missingProtocol:
      return !payload.containsKey('protocol');
    case GatewayTurnCapabilityFailure.unsupportedProtocol:
      return protocol is Map<String, dynamic> &&
          protocol['name'] is String &&
          protocol['major'] is int;
    case GatewayTurnCapabilityFailure.missingCapability:
      if (protocol is! Map<String, dynamic>) return false;
      if (!payload.containsKey('capabilities')) return true;
      final capabilities = payload['capabilities'];
      return capabilities is Map<String, dynamic> &&
          !capabilities.containsKey('turn_recovery');
    case GatewayTurnCapabilityFailure.unsupportedCapabilityVersion:
      final capabilities = payload['capabilities'];
      return protocol is Map<String, dynamic> &&
          capabilities is Map<String, dynamic> &&
          capabilities['turn_recovery'] is Map<String, dynamic>;
    case GatewayTurnCapabilityFailure.none:
    case GatewayTurnCapabilityFailure.notGatewayReady:
    case GatewayTurnCapabilityFailure.unsafeShadowCapability:
    case GatewayTurnCapabilityFailure.automaticResubmitNotDisabled:
    case GatewayTurnCapabilityFailure.invalidRetention:
    case GatewayTurnCapabilityFailure.invalidLimits:
    case GatewayTurnCapabilityFailure.unsupportedCapability:
      return false;
  }
}

/// Whether the gateway cleanly does not offer the durable recovery contract,
/// as opposed to offering a broken or mismatched one.
///
/// Stock Hermes greets with `{skin, change_events, replay_epoch}` — no
/// `protocol` key at all — and a v2 server that simply doesn't implement
/// turn recovery advertises a protocol with a capabilities map that lacks
/// the `turn_recovery` family. Both are honest "not offered" states the UI
/// can label calmly. A present-but-wrong protocol name/major or a malformed
/// recovery payload is a mismatch or a violation, not an absence, and must
/// keep the failure presentation.
bool _readyLacksRecoveryContractCleanly(
  GatewayTurnCapabilityFailure failure,
  Map<String, dynamic> frame,
) {
  if (failure != GatewayTurnCapabilityFailure.missingProtocol &&
      failure != GatewayTurnCapabilityFailure.missingCapability) {
    return false;
  }
  final params = frame['params'];
  if (params is! Map<String, dynamic> || params['type'] != 'gateway.ready') {
    return false;
  }
  final payload = params['payload'];
  if (payload is! Map<String, dynamic>) return false;
  if (!payload.containsKey('protocol')) return true;
  final capabilities = payload['capabilities'];
  return capabilities is Map<String, dynamic> &&
      !capabilities.containsKey('turn_recovery');
}

int _causalTimestamp(int? durablePrior, int current) =>
    durablePrior != null && durablePrior > current ? durablePrior : current;

bool _boundedIdentity(String value) =>
    value.isNotEmpty &&
    value.length <= 256 &&
    value.trim() == value &&
    !value.codeUnits.any((unit) => unit < 32 || unit >= 127 && unit <= 159);

bool _lowerHexDigest(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _validMediaType(String value) =>
    value.isNotEmpty &&
    value.length <= 256 &&
    value.trim() == value &&
    RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$').hasMatch(value);
