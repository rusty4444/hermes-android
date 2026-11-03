import 'dart:convert';

import '../models/gateway_turn_contract.dart';

enum GatewayTurnRecoveryAction { none, reconcile, stopFailClosed }

enum GatewayTurnRecoveryFailure {
  turnUnknown,
  replayPruned,
  turnMismatch,
  clientTurnMismatch,
  duplicateConflict,
  sequenceGap,
  invalidTransition,
  protocolViolation,
}

/// Minimal terminal assistant material retained by the encrypted journal.
///
/// Prompt text, tool output, reasoning, attachments, and event history remain
/// excluded. The UTF-8 limit bounds both secure-storage use and process-memory
/// retention without truncating an authoritative response.
class GatewayTurnTerminalResult {
  static const maxAssistantTextBytes = 32 * 1024;

  final String messageId;
  final String assistantText;

  factory GatewayTurnTerminalResult({
    required String messageId,
    required String assistantText,
  }) {
    if (!_validRecoveryReference(messageId) ||
        assistantText.codeUnits.contains(0) ||
        utf8.encode(assistantText).length > maxAssistantTextBytes) {
      throw ArgumentError('Invalid durable terminal result.');
    }
    return GatewayTurnTerminalResult._(
      messageId: messageId,
      assistantText: assistantText,
    );
  }

  const GatewayTurnTerminalResult._({
    required this.messageId,
    required this.assistantText,
  });

  static GatewayTurnTerminalResult? tryCreate({
    required String messageId,
    required String assistantText,
  }) {
    try {
      return GatewayTurnTerminalResult(
        messageId: messageId,
        assistantText: assistantText,
      );
    } on ArgumentError {
      return null;
    }
  }

  bool sameResult(GatewayTurnTerminalResult other) =>
      messageId == other.messageId && assistantText == other.assistantText;
}

/// Immutable, transport-free state for one server-authoritative turn.
///
/// There is intentionally no submit/resubmit action. Once a write-ahead entry
/// exists, an uncertain acknowledgement, disconnect, or process restart may
/// only reconcile by `client_turn_id`/`turn_id` from the durable server.
class GatewayTurnRecoveryState {
  final String clientTurnId;
  final String? turnId;
  final GatewayRecoveryTurnStatus? status;
  final int lastSeq;
  final int eventPayloadBytes;
  final bool terminalEventRecorded;
  final GatewayTurnTerminalResult? terminalResult;
  final Map<int, GatewayTurnEvent> eventsBySeq;
  final GatewayTurnSnapshot? snapshot;
  final bool ackUncertain;
  final bool reconcilePending;
  final GatewayTurnRecoveryFailure? failure;
  // UI-only live observations. Rehydrate/reconcile never infer these times.
  final DateTime? liveReceivedAt;
  final String? liveMessageId;

  GatewayTurnRecoveryState.initial({required this.clientTurnId})
    : turnId = null,
      status = null,
      lastSeq = 0,
      eventPayloadBytes = 0,
      terminalEventRecorded = false,
      terminalResult = null,
      eventsBySeq = const {},
      snapshot = null,
      ackUncertain = false,
      reconcilePending = false,
      failure = null,
      liveReceivedAt = null,
      liveMessageId = null;

  /// Restores the metadata-only reducer baseline stored by the durable
  /// journal. Historical payloads remain absent; the next accepted event must
  /// begin at exactly `lastSeq + 1`, or recovery fails closed.
  factory GatewayTurnRecoveryState.rehydrate({
    required String clientTurnId,
    required String? turnId,
    required GatewayRecoveryTurnStatus? status,
    required int lastSeq,
    required bool ackUncertain,
    int eventPayloadBytes = 0,
    bool terminalEventRecorded = false,
    GatewayTurnTerminalResult? terminalResult,
    GatewayTurnRecoveryFailure? failure,
  }) {
    final initial = GatewayTurnRecoveryState.initial(
      clientTurnId: clientTurnId,
    );
    final validTurnId = turnId == null || _validRecoveryReference(turnId);
    final hasServerState = turnId != null;
    final structurallyValid =
        _canonicalRecoveryUuid(clientTurnId) &&
        validTurnId &&
        lastSeq >= 0 &&
        eventPayloadBytes >= 0 &&
        (!terminalEventRecorded ||
            status?.isTerminal == true && turnId != null && lastSeq > 0) &&
        (terminalResult == null ||
            status?.isTerminal == true &&
                turnId != null &&
                lastSeq > 0 &&
                failure == null) &&
        (status != GatewayRecoveryTurnStatus.completed ||
            failure != null ||
            terminalResult != null) &&
        (hasServerState || status == null && lastSeq == 0) &&
        (status != null || lastSeq == 0) &&
        (failure == null || !ackUncertain);
    final activeCombination =
        failure != null ||
        ((hasServerState || ackUncertain) &&
            (status != null || ackUncertain) &&
            !(status?.isTerminal == true && ackUncertain));
    final validCombination = structurallyValid && activeCombination;
    if (!validCombination) {
      return initial._fail(GatewayTurnRecoveryFailure.protocolViolation);
    }
    return GatewayTurnRecoveryState._(
      clientTurnId: clientTurnId,
      turnId: turnId,
      status: status,
      lastSeq: lastSeq,
      eventPayloadBytes: eventPayloadBytes,
      terminalEventRecorded: terminalEventRecorded,
      terminalResult: terminalResult,
      eventsBySeq: const {},
      snapshot: null,
      ackUncertain: ackUncertain,
      reconcilePending: failure == null && status?.isTerminal != true,
      failure: failure,
    );
  }

  const GatewayTurnRecoveryState._({
    required this.clientTurnId,
    required this.turnId,
    required this.status,
    required this.lastSeq,
    required this.eventPayloadBytes,
    required this.terminalEventRecorded,
    required this.terminalResult,
    required this.eventsBySeq,
    required this.snapshot,
    required this.ackUncertain,
    required this.reconcilePending,
    required this.failure,
    this.liveReceivedAt,
    this.liveMessageId,
  });

  /// Called only for a newly accepted live socket message, not replay pages.
  GatewayTurnRecoveryState observeLiveMessage(String messageId, DateTime at) {
    if (failure != null || liveMessageId == messageId) return this;
    return _copyWith(liveMessageId: messageId, liveReceivedAt: at);
  }

  bool get isFailClosed => failure != null;

  bool get isTerminal => status?.isTerminal == true;

  GatewayTurnRecoveryAction get requiredAction {
    if (failure != null) return GatewayTurnRecoveryAction.stopFailClosed;
    if (ackUncertain || reconcilePending) {
      return GatewayTurnRecoveryAction.reconcile;
    }
    return GatewayTurnRecoveryAction.none;
  }

  List<GatewayTurnEvent> get events {
    final values = eventsBySeq.values.toList(growable: false);
    values.sort((left, right) => left.seq.compareTo(right.seq));
    return values;
  }

  static int payloadBytesFor(GatewayTurnEvent event) =>
      utf8.encode(jsonEncode(event.payload)).length;

  GatewayTurnRecoveryState markSubmissionStarted() {
    if (failure != null || isTerminal) return this;
    return _copyWith(ackUncertain: true, reconcilePending: false);
  }

  GatewayTurnRecoveryState markDisconnected() {
    if (failure != null || isTerminal) return this;
    return _copyWith(ackUncertain: true, reconcilePending: false);
  }

  /// Retains only metadata needed for bounded terminal/failure introspection.
  GatewayTurnRecoveryState releasePayloads() {
    if (eventsBySeq.isEmpty && snapshot == null) return this;
    return _copyWith(eventsBySeq: const {}, clearSnapshot: true);
  }

  GatewayTurnRecoveryState applyAck(GatewayTurnAck ack) {
    if (failure != null) return this;
    if (ack.clientTurnId != clientTurnId) {
      return _fail(GatewayTurnRecoveryFailure.clientTurnMismatch);
    }
    if (turnId != null && turnId != ack.turnId) {
      return _fail(GatewayTurnRecoveryFailure.turnMismatch);
    }
    if (ack.lastSeq < lastSeq) {
      return _fail(GatewayTurnRecoveryFailure.protocolViolation);
    }
    if (ack.lastSeq > lastSeq) {
      // The server has committed events not yet applied locally. Preserve the
      // local cursor and reconcile; never infer that the prompt should be sent.
      return _copyWith(
        turnId: ack.turnId,
        ackUncertain: true,
        reconcilePending: false,
      );
    }
    if (status != null && !_transitionAllowed(status!, ack.status)) {
      return _fail(GatewayTurnRecoveryFailure.invalidTransition);
    }
    final completedWithoutMaterial =
        ack.status == GatewayRecoveryTurnStatus.completed &&
        terminalResult == null;
    return _copyWith(
      turnId: ack.turnId,
      // A completed ACK proves that execution is terminal, but it does not
      // carry the assistant payload. Keep the last materialized status until
      // reconcile supplies an events page or snapshot that can be rendered.
      status: completedWithoutMaterial ? status : ack.status,
      // The ACK proves acceptance, but until reconcile materializes the
      // terminal payload a restart must still recover this turn. This flag is
      // part of the durable journal contract; reconcilePending is in-memory.
      ackUncertain: completedWithoutMaterial,
      reconcilePending: completedWithoutMaterial,
    );
  }

  GatewayTurnRecoveryState applyEvent(
    GatewayTurnEvent event, {
    int? payloadBytes,
  }) {
    if (failure != null) return this;
    if (turnId != null && turnId != event.turnId) {
      return _fail(GatewayTurnRecoveryFailure.turnMismatch);
    }
    final duplicate = eventsBySeq[event.seq];
    if (duplicate != null) {
      return duplicate.sameWireEvent(event)
          ? this
          : _fail(GatewayTurnRecoveryFailure.duplicateConflict);
    }
    if (isTerminal) {
      // A terminal turn is immutable. Only the exact duplicate handled above
      // is idempotent; any unseen sequence (including a gap) is a violation.
      return _fail(GatewayTurnRecoveryFailure.invalidTransition);
    }
    if (event.seq <= lastSeq) {
      // A terminal snapshot may cover sequences whose individual events were
      // compacted. They are already materialized from the client's view.
      return this;
    }
    if (event.seq != lastSeq + 1) {
      // Live delivery may race listener installation or a transport break.
      // Keep the last contiguous cursor and recover the missing range from the
      // durable server. A sequence gap never authorizes another submit.
      return _copyWith(reconcilePending: true);
    }
    final acceptedPayloadBytes = payloadBytes ?? payloadBytesFor(event);
    if (acceptedPayloadBytes < 0) {
      return _fail(GatewayTurnRecoveryFailure.protocolViolation);
    }

    var nextStatus = status;
    GatewayRecoveryTurnStatus? eventStatus;
    if (event.type == 'message.start') {
      eventStatus = GatewayRecoveryTurnStatus.running;
    } else if (event.type == 'message.complete' ||
        event.type == 'turn.status') {
      final parsed = GatewayRecoveryTurnStatus.fromWire(
        event.payload['status'],
      );
      if (parsed == null) {
        return _fail(GatewayTurnRecoveryFailure.protocolViolation);
      }
      eventStatus = parsed;
    }
    if (eventStatus != null) {
      if (nextStatus != null && !_transitionAllowed(nextStatus, eventStatus)) {
        return _fail(GatewayTurnRecoveryFailure.invalidTransition);
      }
      nextStatus = eventStatus;
    }

    final nextEvents = Map<int, GatewayTurnEvent>.from(eventsBySeq)
      ..[event.seq] = event;
    final nextTerminalResult = nextStatus?.isTerminal == true
        ? terminalResult ?? _terminalResultFromEvents(nextEvents.values)
        : terminalResult;
    final next = _copyWith(
      turnId: turnId ?? event.turnId,
      status: nextStatus,
      lastSeq: event.seq,
      eventPayloadBytes: eventPayloadBytes + acceptedPayloadBytes,
      terminalEventRecorded:
          terminalEventRecorded ||
          event.type == 'turn.status' && eventStatus?.isTerminal == true,
      terminalResult: nextTerminalResult,
      eventsBySeq: Map<int, GatewayTurnEvent>.unmodifiable(nextEvents),
      ackUncertain: false,
      reconcilePending: false,
    );
    return next.status == GatewayRecoveryTurnStatus.completed &&
            next.terminalResult == null
        ? next._fail(GatewayTurnRecoveryFailure.protocolViolation)
        : next;
  }

  GatewayTurnRecoveryState applyReconcilePage(
    GatewayTurnReconcilePage page, {
    Map<int, int>? payloadBytesBySeq,
  }) {
    if (failure != null) return this;
    if (turnId != null && turnId != page.turnId) {
      return _fail(GatewayTurnRecoveryFailure.turnMismatch);
    }
    if (page.mode == GatewayTurnReconcileMode.snapshot) {
      final nextSnapshot = page.snapshot;
      if (nextSnapshot == null ||
          nextSnapshot.clientTurnId != clientTurnId ||
          nextSnapshot.lastSeq < lastSeq ||
          status != null &&
              !_snapshotTransitionAllowed(status!, nextSnapshot.status)) {
        return _fail(GatewayTurnRecoveryFailure.protocolViolation);
      }
      final terminalResult = GatewayTurnTerminalResult.tryCreate(
        messageId: nextSnapshot.assistant.messageId,
        assistantText: nextSnapshot.assistant.text,
      );
      final next = _copyWith(
        turnId: nextSnapshot.turnId,
        status: nextSnapshot.status,
        lastSeq: nextSnapshot.lastSeq,
        terminalResult: terminalResult,
        eventsBySeq: const {},
        snapshot: nextSnapshot,
        ackUncertain: false,
        reconcilePending: false,
      );
      return next.status == GatewayRecoveryTurnStatus.completed &&
              terminalResult == null
          ? next._fail(GatewayTurnRecoveryFailure.protocolViolation)
          : next;
    }

    var next = _copyWith(
      turnId: page.turnId,
      ackUncertain: false,
      reconcilePending: false,
    );
    for (final event in page.events) {
      next = next.applyEvent(
        event,
        payloadBytes: payloadBytesBySeq?[event.seq],
      );
      if (next.failure != null) return next;
    }
    if (next.lastSeq != page.nextAfterSeq) {
      return next._fail(GatewayTurnRecoveryFailure.protocolViolation);
    }
    if (page.hasMore) {
      return next._copyWith(reconcilePending: true);
    }
    if (page.lastSeq != next.lastSeq) {
      return next._fail(GatewayTurnRecoveryFailure.protocolViolation);
    }
    if (next.status != null && !_transitionAllowed(next.status!, page.status)) {
      return next._fail(GatewayTurnRecoveryFailure.invalidTransition);
    }
    next = next._copyWith(status: page.status, reconcilePending: false);
    return next.status == GatewayRecoveryTurnStatus.completed &&
            next.terminalResult == null
        ? next._fail(GatewayTurnRecoveryFailure.protocolViolation)
        : next;
  }

  GatewayTurnRecoveryState failReconcile(GatewayTurnRecoveryFailure reason) {
    if (reason != GatewayTurnRecoveryFailure.turnUnknown &&
        reason != GatewayTurnRecoveryFailure.replayPruned &&
        reason != GatewayTurnRecoveryFailure.protocolViolation) {
      throw ArgumentError.value(reason, 'reason', 'invalid reconcile failure');
    }
    return _fail(reason);
  }

  GatewayTurnRecoveryState _fail(GatewayTurnRecoveryFailure reason) {
    if (failure != null) return this;
    return _copyWith(
      failure: reason,
      ackUncertain: false,
      reconcilePending: false,
    );
  }

  GatewayTurnRecoveryState _copyWith({
    DateTime? liveReceivedAt,
    String? liveMessageId,
    String? turnId,
    GatewayRecoveryTurnStatus? status,
    int? lastSeq,
    int? eventPayloadBytes,
    bool? terminalEventRecorded,
    GatewayTurnTerminalResult? terminalResult,
    Map<int, GatewayTurnEvent>? eventsBySeq,
    GatewayTurnSnapshot? snapshot,
    bool clearSnapshot = false,
    bool? ackUncertain,
    bool? reconcilePending,
    GatewayTurnRecoveryFailure? failure,
  }) {
    return GatewayTurnRecoveryState._(
      clientTurnId: clientTurnId,
      liveReceivedAt: liveReceivedAt ?? this.liveReceivedAt,
      liveMessageId: liveMessageId ?? this.liveMessageId,
      turnId: turnId ?? this.turnId,
      status: status ?? this.status,
      lastSeq: lastSeq ?? this.lastSeq,
      eventPayloadBytes: eventPayloadBytes ?? this.eventPayloadBytes,
      terminalEventRecorded:
          terminalEventRecorded ?? this.terminalEventRecorded,
      terminalResult: terminalResult ?? this.terminalResult,
      eventsBySeq: eventsBySeq ?? this.eventsBySeq,
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      ackUncertain: ackUncertain ?? this.ackUncertain,
      reconcilePending: reconcilePending ?? this.reconcilePending,
      failure: failure ?? this.failure,
    );
  }
}

GatewayTurnTerminalResult? _terminalResultFromEvents(
  Iterable<GatewayTurnEvent> events,
) {
  final ordered = events.toList(growable: false)
    ..sort((left, right) => left.seq.compareTo(right.seq));
  String? messageId;
  var assistantText = '';
  for (final event in ordered) {
    switch (event.type) {
      case 'message.start':
        if (messageId != event.messageId) assistantText = '';
        messageId = event.messageId;
        break;
      case 'message.delta':
        if (messageId != event.messageId) {
          messageId = event.messageId;
          assistantText = '';
        }
        assistantText += event.payload['text'] as String;
        break;
      case 'message.complete':
        messageId = event.messageId;
        assistantText = event.payload['text'] as String;
        break;
      case 'turn.status':
        break;
    }
  }
  if (messageId == null) return null;
  return GatewayTurnTerminalResult.tryCreate(
    messageId: messageId,
    assistantText: assistantText,
  );
}

bool _canonicalRecoveryUuid(String value) =>
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(value) &&
    value != '00000000-0000-0000-0000-000000000000';

bool _validRecoveryReference(String value) =>
    value.isNotEmpty &&
    value.length <= 256 &&
    value.trim() == value &&
    !value.codeUnits.any((unit) => unit < 32 || unit >= 127 && unit <= 159);

bool _transitionAllowed(
  GatewayRecoveryTurnStatus from,
  GatewayRecoveryTurnStatus to,
) {
  if (from == to) return true;
  if (from.isTerminal) return false;
  return switch (from) {
    GatewayRecoveryTurnStatus.accepted =>
      to == GatewayRecoveryTurnStatus.running ||
          to == GatewayRecoveryTurnStatus.failed ||
          to == GatewayRecoveryTurnStatus.interrupted,
    GatewayRecoveryTurnStatus.running =>
      to == GatewayRecoveryTurnStatus.waitingInput ||
          to == GatewayRecoveryTurnStatus.completed ||
          to == GatewayRecoveryTurnStatus.failed ||
          to == GatewayRecoveryTurnStatus.interrupted,
    GatewayRecoveryTurnStatus.waitingInput =>
      to == GatewayRecoveryTurnStatus.running ||
          to == GatewayRecoveryTurnStatus.failed ||
          to == GatewayRecoveryTurnStatus.interrupted,
    GatewayRecoveryTurnStatus.completed ||
    GatewayRecoveryTurnStatus.failed ||
    GatewayRecoveryTurnStatus.interrupted => false,
  };
}

bool _snapshotTransitionAllowed(
  GatewayRecoveryTurnStatus from,
  GatewayRecoveryTurnStatus to,
) {
  if (from == to) return true;
  if (from.isTerminal) return false;
  // A server-selected snapshot may skip replayed intermediate states but can
  // never regress to accepted or leave a terminal state.
  return to.isTerminal;
}
