import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/gateway_turn_contract.dart';
import 'gateway_turn_recovery.dart';

abstract interface class GatewayTurnJournalStore {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();

  Future<String?> readLegacy();

  Future<void> deleteLegacy();
}

/// Optional shared read-modify-write authority for store wrappers that target
/// the same physical slot. The token carries no journal data or secret.
abstract interface class GatewayTurnJournalSerializationAuthority {
  Object get journalSerializationAuthority;
}

/// Android Keystore-backed production store for the single bounded journal.
class FlutterSecureGatewayTurnJournalStore
    implements
        GatewayTurnJournalStore,
        GatewayTurnJournalSerializationAuthority {
  // Keep the v2 slot name intentionally. A rollback must encounter the v3
  // schema in the same authority slot, never create a parallel v2 journal.
  static const _key = 'gateway_turn_journal_v2';
  static const _legacyKey = 'gateway_turn_journal_v1';
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateWithBackup: true,
    storageNamespace: 'hermes_android_turn_recovery',
  );
  static final Object _sharedSerializationAuthority = Object();

  final FlutterSecureStorage _storage;

  FlutterSecureGatewayTurnJournalStore({FlutterSecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorage(aOptions: _androidOptions);

  @override
  Object get journalSerializationAuthority => _sharedSerializationAuthority;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);

  @override
  Future<String?> readLegacy() => _storage
      .containsKey(key: _legacyKey)
      .then((present) => present ? 'incompatible' : null);

  @override
  Future<void> deleteLegacy() => _storage.delete(key: _legacyKey);
}

class GatewayTurnJournalException implements Exception {
  const GatewayTurnJournalException();

  @override
  String toString() => 'Turn recovery journal is unavailable.';
}

/// Durable server-owned session binding for one local chat.
///
/// Runtime session IDs are deliberately absent. A runtime ID is valid only for
/// the physical transport on which a fresh `session.open` returned it.
class GatewayTurnJournalBinding {
  static const allowedJsonKeys = <String>{
    'connection_id',
    'endpoint_digest',
    'local_session_id',
    'mobile_session_id',
    'stored_session_id',
    'binding_version',
    'updated_at_epoch_ms',
  };

  final String connectionId;
  final String endpointDigest;
  final String localSessionId;
  final String mobileSessionId;
  final String storedSessionId;
  final int bindingVersion;
  final int updatedAtEpochMs;

  factory GatewayTurnJournalBinding({
    required String connectionId,
    required String endpointDigest,
    required String localSessionId,
    required String mobileSessionId,
    required String storedSessionId,
    required int bindingVersion,
    required int updatedAtEpochMs,
  }) {
    if (!_boundedIdentity(connectionId) ||
        !_lowerHexDigest(endpointDigest) ||
        !_boundedIdentity(localSessionId) ||
        !_canonicalUuid(mobileSessionId) ||
        !_boundedIdentity(storedSessionId) ||
        bindingVersion <= 0 ||
        updatedAtEpochMs <= 0) {
      throw ArgumentError('Invalid recovery journal binding.');
    }
    return GatewayTurnJournalBinding._(
      connectionId: connectionId,
      endpointDigest: endpointDigest,
      localSessionId: localSessionId,
      mobileSessionId: mobileSessionId,
      storedSessionId: storedSessionId,
      bindingVersion: bindingVersion,
      updatedAtEpochMs: updatedAtEpochMs,
    );
  }

  const GatewayTurnJournalBinding._({
    required this.connectionId,
    required this.endpointDigest,
    required this.localSessionId,
    required this.mobileSessionId,
    required this.storedSessionId,
    required this.bindingVersion,
    required this.updatedAtEpochMs,
  });

  String get bindingIdentity =>
      _journalScopeIdentity(connectionId, endpointDigest, localSessionId);

  Map<String, Object> toJson() => <String, Object>{
    'connection_id': connectionId,
    'endpoint_digest': endpointDigest,
    'local_session_id': localSessionId,
    'mobile_session_id': mobileSessionId,
    'stored_session_id': storedSessionId,
    'binding_version': bindingVersion,
    'updated_at_epoch_ms': updatedAtEpochMs,
  };

  static GatewayTurnJournalBinding _fromJson(Map<String, dynamic> value) {
    if (value.length != allowedJsonKeys.length ||
        value.keys.any((key) => !allowedJsonKeys.contains(key)) ||
        value['connection_id'] is! String ||
        value['endpoint_digest'] is! String ||
        value['local_session_id'] is! String ||
        value['mobile_session_id'] is! String ||
        value['stored_session_id'] is! String ||
        value['binding_version'] is! int ||
        value['updated_at_epoch_ms'] is! int) {
      throw const GatewayTurnJournalException();
    }
    try {
      return GatewayTurnJournalBinding(
        connectionId: value['connection_id'] as String,
        endpointDigest: value['endpoint_digest'] as String,
        localSessionId: value['local_session_id'] as String,
        mobileSessionId: value['mobile_session_id'] as String,
        storedSessionId: value['stored_session_id'] as String,
        bindingVersion: value['binding_version'] as int,
        updatedAtEpochMs: value['updated_at_epoch_ms'] as int,
      );
    } on ArgumentError {
      throw const GatewayTurnJournalException();
    }
  }
}

/// Bounded write-ahead record for one client intent.
///
/// It references a separately durable binding. Only the stable message ID and
/// bounded assistant text required to render a completed turn may accompany
/// lifecycle metadata. Prompt text, attachments, tool output, reasoning,
/// credentials, endpoints, and runtime session IDs remain prohibited.
class GatewayTurnJournalEntry {
  static const allowedJsonKeys = <String>{
    'binding_id',
    'client_turn_id',
    'turn_id',
    'status',
    'last_seq',
    'event_payload_bytes',
    'terminal_event_recorded',
    'terminal_result',
    'ack_uncertain',
    'failure',
    'updated_at_epoch_ms',
  };

  final String bindingIdentity;
  final String clientTurnId;
  final String? turnId;
  final GatewayRecoveryTurnStatus? status;
  final int lastSeq;
  final int eventPayloadBytes;
  final bool terminalEventRecorded;
  final GatewayTurnTerminalResult? terminalResult;
  final bool ackUncertain;
  final GatewayTurnRecoveryFailure? failure;
  final int updatedAtEpochMs;

  factory GatewayTurnJournalEntry({
    required String bindingIdentity,
    required String clientTurnId,
    String? turnId,
    GatewayRecoveryTurnStatus? status,
    required int lastSeq,
    required int eventPayloadBytes,
    required bool terminalEventRecorded,
    GatewayTurnTerminalResult? terminalResult,
    required bool ackUncertain,
    GatewayTurnRecoveryFailure? failure,
    required int updatedAtEpochMs,
  }) {
    if (!_boundedReference(bindingIdentity) ||
        !_canonicalUuid(clientTurnId) ||
        turnId != null && !_boundedIdentity(turnId) ||
        lastSeq < 0 ||
        eventPayloadBytes < 0 ||
        terminalEventRecorded &&
            (status?.isTerminal != true || turnId == null || lastSeq == 0) ||
        terminalResult != null &&
            (status?.isTerminal != true ||
                turnId == null ||
                lastSeq == 0 ||
                ackUncertain ||
                failure != null) ||
        status == GatewayRecoveryTurnStatus.completed &&
            failure == null &&
            terminalResult == null ||
        failure != null && ackUncertain ||
        updatedAtEpochMs <= 0) {
      throw ArgumentError('Invalid recovery journal entry.');
    }
    return GatewayTurnJournalEntry._(
      bindingIdentity: bindingIdentity,
      clientTurnId: clientTurnId,
      turnId: turnId,
      status: status,
      lastSeq: lastSeq,
      eventPayloadBytes: eventPayloadBytes,
      terminalEventRecorded: terminalEventRecorded,
      terminalResult: terminalResult,
      ackUncertain: ackUncertain,
      failure: failure,
      updatedAtEpochMs: updatedAtEpochMs,
    );
  }

  const GatewayTurnJournalEntry._({
    required this.bindingIdentity,
    required this.clientTurnId,
    required this.turnId,
    required this.status,
    required this.lastSeq,
    required this.eventPayloadBytes,
    required this.terminalEventRecorded,
    required this.terminalResult,
    required this.ackUncertain,
    required this.failure,
    required this.updatedAtEpochMs,
  });

  bool get isTerminal => status?.isTerminal == true;

  String get entryIdentity => '$bindingIdentity:$clientTurnId';

  GatewayTurnJournalEntry copyWith({
    String? turnId,
    GatewayRecoveryTurnStatus? status,
    int? lastSeq,
    int? eventPayloadBytes,
    bool? terminalEventRecorded,
    GatewayTurnTerminalResult? terminalResult,
    bool? ackUncertain,
    GatewayTurnRecoveryFailure? failure,
    int? updatedAtEpochMs,
  }) {
    return GatewayTurnJournalEntry(
      bindingIdentity: bindingIdentity,
      clientTurnId: clientTurnId,
      turnId: turnId ?? this.turnId,
      status: status ?? this.status,
      lastSeq: lastSeq ?? this.lastSeq,
      eventPayloadBytes: eventPayloadBytes ?? this.eventPayloadBytes,
      terminalEventRecorded:
          terminalEventRecorded ?? this.terminalEventRecorded,
      terminalResult: terminalResult ?? this.terminalResult,
      ackUncertain: ackUncertain ?? this.ackUncertain,
      failure: failure ?? this.failure,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'binding_id': bindingIdentity,
    'client_turn_id': clientTurnId,
    if (turnId != null) 'turn_id': turnId,
    if (status != null) 'status': status!.wireValue,
    'last_seq': lastSeq,
    'event_payload_bytes': eventPayloadBytes,
    'terminal_event_recorded': terminalEventRecorded,
    if (terminalResult != null)
      'terminal_result': <String, Object>{
        'message_id': terminalResult!.messageId,
        'assistant_text': terminalResult!.assistantText,
      },
    'ack_uncertain': ackUncertain,
    if (failure != null) 'failure': failure!.name,
    'updated_at_epoch_ms': updatedAtEpochMs,
  };

  static GatewayTurnJournalEntry _fromJson(
    Map<String, dynamic> value, {
    required bool legacyV3,
  }) {
    final acceptedKeys = legacyV3
        ? allowedJsonKeys.difference(const {'terminal_result'})
        : allowedJsonKeys;
    if (value.keys.any((key) => !acceptedKeys.contains(key))) {
      throw const GatewayTurnJournalException();
    }
    final statusRaw = value['status'];
    final status = statusRaw == null
        ? null
        : GatewayRecoveryTurnStatus.fromWire(statusRaw);
    final failureRaw = value['failure'];
    final failure = failureRaw == null
        ? null
        : _recoveryFailureFromWire(failureRaw);
    final terminalRaw = value['terminal_result'];
    GatewayTurnTerminalResult? terminalResult;
    if (terminalRaw != null) {
      if (terminalRaw is! Map) throw const GatewayTurnJournalException();
      final terminal = Map<String, dynamic>.from(terminalRaw);
      if (terminal.length != 2 ||
          terminal.keys.toSet().difference(const {
            'message_id',
            'assistant_text',
          }).isNotEmpty ||
          terminal['message_id'] is! String ||
          terminal['assistant_text'] is! String) {
        throw const GatewayTurnJournalException();
      }
      try {
        terminalResult = GatewayTurnTerminalResult(
          messageId: terminal['message_id'] as String,
          assistantText: terminal['assistant_text'] as String,
        );
      } on ArgumentError {
        throw const GatewayTurnJournalException();
      }
    }
    if (statusRaw != null && status == null ||
        failureRaw != null && failure == null ||
        value['binding_id'] is! String ||
        value['client_turn_id'] is! String ||
        value['turn_id'] != null && value['turn_id'] is! String ||
        value['last_seq'] is! int ||
        value['event_payload_bytes'] is! int ||
        value['terminal_event_recorded'] is! bool ||
        value['ack_uncertain'] is! bool ||
        value['updated_at_epoch_ms'] is! int) {
      throw const GatewayTurnJournalException();
    }
    try {
      final legacyUnrecoverableCompletion =
          legacyV3 &&
          status == GatewayRecoveryTurnStatus.completed &&
          failure == null;
      return GatewayTurnJournalEntry(
        bindingIdentity: value['binding_id'] as String,
        clientTurnId: value['client_turn_id'] as String,
        turnId: value['turn_id'] as String?,
        status: status,
        lastSeq: value['last_seq'] as int,
        eventPayloadBytes: value['event_payload_bytes'] as int,
        terminalEventRecorded: value['terminal_event_recorded'] as bool,
        terminalResult: terminalResult,
        ackUncertain: legacyUnrecoverableCompletion
            ? false
            : value['ack_uncertain'] as bool,
        failure: legacyUnrecoverableCompletion
            ? GatewayTurnRecoveryFailure.protocolViolation
            : failure,
        updatedAtEpochMs: value['updated_at_epoch_ms'] as int,
      );
    } on ArgumentError {
      throw const GatewayTurnJournalException();
    }
  }
}

class GatewayTurnJournalSnapshot {
  final List<GatewayTurnJournalBinding> bindings;
  final List<GatewayTurnJournalEntry> entries;

  const GatewayTurnJournalSnapshot({
    required this.bindings,
    required this.entries,
  });
}

class GatewayTurnJournal {
  static const schema = 'hermes.android.turn-journal.v4';
  static const compatibleLegacySchema = 'hermes.android.turn-journal.v3';
  static const maxBindings = 64;
  static const maxEntries = 64;
  static const maxEncodedBytes = 5 * 1024 * 1024;
  static const activeRetention = Duration(days: 7);
  static const terminalRetention = Duration(hours: 24);

  final GatewayTurnJournalStore _store;
  final _GatewayTurnJournalSerializationQueue _serializationQueue;

  GatewayTurnJournal({GatewayTurnJournalStore? store})
    : this._(store ?? FlutterSecureGatewayTurnJournalStore());

  GatewayTurnJournal._(GatewayTurnJournalStore store)
    : _store = store,
      _serializationQueue = _journalSerializationQueueFor(store);

  /// Returns the absorbing, payload-free failure for this authority and local
  /// binding scope. The weak authority ledger exists only for this process.
  GatewayTurnRecoveryState? processPoisonedFailure({
    required String connectionId,
    required String endpointDigest,
    required String localSessionId,
  }) {
    final scope = _validatedJournalScope(
      connectionId,
      endpointDigest,
      localSessionId,
    );
    return _serializationQueue.processPoisonedFailures[scope] ??
        _serializationQueue.authorityWideProcessPoison;
  }

  /// Count-only hooks for bounded lifecycle verification. No poison reset is
  /// exposed by this API.
  int get processPoisonedScopeCount =>
      _serializationQueue.processPoisonedFailures.length;

  bool get authorityWideProcessPoisoned =>
      _serializationQueue.authorityWideProcessPoison != null;

  /// Atomically records the first failure whose durable seal could not be
  /// verified. There is deliberately no reset API; only process restart drops
  /// the weak authority ledger.
  void recordProcessPoison({
    required String connectionId,
    required String endpointDigest,
    required String localSessionId,
    required GatewayTurnRecoveryState failure,
  }) {
    if (!failure.isFailClosed) {
      throw ArgumentError.value(
        failure,
        'failure',
        'Failure is not fail-closed.',
      );
    }
    final scope = _validatedJournalScope(
      connectionId,
      endpointDigest,
      localSessionId,
    );
    final queue = _serializationQueue;
    if (queue.authorityWideProcessPoison != null ||
        queue.processPoisonedFailures.containsKey(scope)) {
      return;
    }
    final released = failure.releasePayloads();
    if (queue.processPoisonedFailures.length >= maxBindings) {
      // Never evict an absorbing scope poison. Escalation bounds memory while
      // stopping every scope that shares this physical journal authority.
      queue.authorityWideProcessPoison = released;
      return;
    }
    queue.processPoisonedFailures[scope] = released;
  }

  Future<GatewayTurnJournalSnapshot> loadSnapshot() {
    return _serialized(() async => _freeze(await _readData()));
  }

  Future<List<GatewayTurnJournalEntry>> loadAll() {
    return _serialized(() async {
      final data = await _readData();
      return List<GatewayTurnJournalEntry>.unmodifiable(data.entries);
    });
  }

  Future<GatewayTurnJournalBinding?> loadBinding({
    required String connectionId,
    required String endpointDigest,
    required String localSessionId,
  }) {
    return _serialized(() async {
      final probe = GatewayTurnJournalBinding(
        connectionId: connectionId,
        endpointDigest: endpointDigest,
        localSessionId: localSessionId,
        mobileSessionId: '00000000-0000-4000-8000-000000000001',
        storedSessionId: 'probe',
        bindingVersion: 1,
        updatedAtEpochMs: 1,
      );
      final data = await _readData();
      return data.bindings.cast<GatewayTurnJournalBinding?>().firstWhere(
        (binding) => binding!.bindingIdentity == probe.bindingIdentity,
        orElse: () => null,
      );
    });
  }

  Future<List<GatewayTurnJournalEntry>> loadForBinding(
    GatewayTurnJournalBinding binding,
  ) {
    return _serialized(() async {
      final data = await _readData();
      return List<GatewayTurnJournalEntry>.unmodifiable(
        data.entries.where(
          (entry) => entry.bindingIdentity == binding.bindingIdentity,
        ),
      );
    });
  }

  Future<void> upsertBinding(GatewayTurnJournalBinding binding) {
    return _serialized(() async {
      final data = await _readData();
      final index = data.bindings.indexWhere(
        (candidate) => candidate.bindingIdentity == binding.bindingIdentity,
      );
      if (index >= 0) {
        final previous = data.bindings[index];
        if (previous.mobileSessionId != binding.mobileSessionId ||
            previous.storedSessionId != binding.storedSessionId ||
            binding.bindingVersion < previous.bindingVersion ||
            binding.updatedAtEpochMs < previous.updatedAtEpochMs) {
          throw const GatewayTurnJournalException();
        }
        data.bindings[index] = binding;
      } else {
        data.bindings.add(binding);
      }
      await _writeData(
        _compact(
          data,
          DateTime.now().toUtc(),
          protectedBindingIdentity: binding.bindingIdentity,
        ),
      );
    });
  }

  Future<void> upsert(GatewayTurnJournalEntry entry, {DateTime? now}) {
    return _serialized(() async {
      final data = await _readData();
      if (!data.bindings.any(
        (binding) => binding.bindingIdentity == entry.bindingIdentity,
      )) {
        throw const GatewayTurnJournalException();
      }
      final index = data.entries.indexWhere(
        (candidate) => candidate.entryIdentity == entry.entryIdentity,
      );
      if (index >= 0) {
        _validateEntryUpdate(data.entries[index], entry);
        data.entries[index] = entry;
      } else {
        data.entries.add(entry);
      }
      await _writeData(_compact(data, now ?? DateTime.now().toUtc()));
    });
  }

  Future<void> remove(String entryIdentity) {
    return _serialized(() async {
      final data = await _readData();
      data.entries.removeWhere((entry) => entry.entryIdentity == entryIdentity);
      await _writeData(data);
    });
  }

  Future<GatewayTurnJournalSnapshot> compact({DateTime? now}) {
    return _serialized(() async {
      final compacted = _compact(
        await _readData(),
        now ?? DateTime.now().toUtc(),
      );
      await _writeData(compacted);
      return _freeze(compacted);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _serializationQueue.tail.then((_) => action());
    _serializationQueue.tail = run.then<void>((_) {}, onError: (_, _) {});
    return run;
  }

  Future<_JournalData> _readData() async {
    try {
      final encoded = await _readCurrentAfterLegacyPurge();
      if (encoded == null) return _JournalData.empty();
      if (utf8.encode(encoded).length > maxEncodedBytes) {
        throw const GatewayTurnJournalException();
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const GatewayTurnJournalException();
      final root = Map<String, dynamic>.from(decoded);
      final legacyV3 = root['schema'] == compatibleLegacySchema;
      if (root.length != 3 ||
          root['schema'] != schema && !legacyV3 ||
          root['bindings'] is! List ||
          root['entries'] is! List) {
        throw const GatewayTurnJournalException();
      }
      final rawBindings = root['bindings'] as List;
      final rawEntries = root['entries'] as List;
      if (rawBindings.length > maxBindings || rawEntries.length > maxEntries) {
        throw const GatewayTurnJournalException();
      }
      final bindings = <GatewayTurnJournalBinding>[];
      final bindingIds = <String>{};
      for (final rawBinding in rawBindings) {
        if (rawBinding is! Map) throw const GatewayTurnJournalException();
        final binding = GatewayTurnJournalBinding._fromJson(
          Map<String, dynamic>.from(rawBinding),
        );
        if (!bindingIds.add(binding.bindingIdentity)) {
          throw const GatewayTurnJournalException();
        }
        bindings.add(binding);
      }
      final entries = <GatewayTurnJournalEntry>[];
      final entryIds = <String>{};
      for (final rawEntry in rawEntries) {
        if (rawEntry is! Map) throw const GatewayTurnJournalException();
        final entry = GatewayTurnJournalEntry._fromJson(
          Map<String, dynamic>.from(rawEntry),
          legacyV3: legacyV3,
        );
        if (!bindingIds.contains(entry.bindingIdentity) ||
            !entryIds.add(entry.entryIdentity)) {
          throw const GatewayTurnJournalException();
        }
        entries.add(entry);
      }
      final data = _JournalData(bindings: bindings, entries: entries);
      if (legacyV3) await _writeData(data);
      return data;
    } on GatewayTurnJournalException {
      rethrow;
    } catch (_) {
      throw const GatewayTurnJournalException();
    }
  }

  _JournalData _compact(
    _JournalData data,
    DateTime now, {
    String? protectedBindingIdentity,
  }) {
    final nowMs = now.toUtc().millisecondsSinceEpoch;
    data.entries.removeWhere((entry) {
      final ageMs = nowMs - entry.updatedAtEpochMs;
      if (ageMs < 0) return false;
      return entry.isTerminal &&
          !entry.ackUncertain &&
          entry.failure == null &&
          ageMs > terminalRetention.inMilliseconds;
    });
    data.entries.sort(
      (left, right) => right.updatedAtEpochMs.compareTo(left.updatedAtEpochMs),
    );
    if (data.entries.length > maxEntries) {
      final removeCount = data.entries.length - maxEntries;
      final removable =
          data.entries
              .where((entry) => entry.isTerminal && !entry.ackUncertain)
              .where((entry) => entry.failure == null)
              .toList()
            ..sort(
              (left, right) =>
                  left.updatedAtEpochMs.compareTo(right.updatedAtEpochMs),
            );
      // Last resort: when safe terminal entries can't cover the overflow,
      // evict quarantined (failure != null) entries and entries older than
      // the active-retention window, oldest first, instead of throwing.
      // Throwing here used to be permanent for those classes: they are
      // never removed by any other path, so once maxEntries of them
      // accumulated EVERY write threw — a device-wide turn-recovery
      // lockout with no reset. A dropped stale quarantine is a
      // recovery-quality loss; the lockout is total. Young ack-uncertain
      // entries stay protected: refusing the 65th genuinely-pending turn
      // is intentional backpressure.
      bool lastResortEvictable(GatewayTurnJournalEntry entry) =>
          entry.failure != null ||
          nowMs - entry.updatedAtEpochMs >
              activeRetention.inMilliseconds;
      final evictable = [...removable];
      if (evictable.length < removeCount) {
        final stale =
            data.entries
                .where(
                  (entry) =>
                      !evictable.contains(entry) &&
                      lastResortEvictable(entry),
                )
                .toList()
              ..sort(
                (left, right) =>
                    left.updatedAtEpochMs.compareTo(right.updatedAtEpochMs),
              );
        evictable.addAll(stale.take(removeCount - evictable.length));
      }
      if (evictable.length < removeCount) {
        throw const GatewayTurnJournalException();
      }
      final removeIds = evictable
          .take(removeCount)
          .map((entry) => entry.entryIdentity)
          .toSet();
      data.entries.removeWhere(
        (entry) => removeIds.contains(entry.entryIdentity),
      );
    }

    // Session bindings have independent retention. They survive removal of the
    // last turn and are bounded only by recency/count. A referenced binding is
    // recovery authority and is never evicted silently.
    data.bindings.sort(
      (left, right) => right.updatedAtEpochMs.compareTo(left.updatedAtEpochMs),
    );
    if (data.bindings.length > maxBindings) {
      final referencedIds = data.entries
          .map((entry) => entry.bindingIdentity)
          .toSet();
      final removable =
          data.bindings
              .where(
                (binding) =>
                    !referencedIds.contains(binding.bindingIdentity) &&
                    binding.bindingIdentity != protectedBindingIdentity,
              )
              .toList()
            ..sort(
              (left, right) =>
                  left.updatedAtEpochMs.compareTo(right.updatedAtEpochMs),
            );
      final removeCount = data.bindings.length - maxBindings;
      if (removable.length < removeCount) {
        throw const GatewayTurnJournalException();
      }
      final removeIds = removable
          .take(removeCount)
          .map((binding) => binding.bindingIdentity)
          .toSet();
      data.bindings.removeWhere(
        (binding) => removeIds.contains(binding.bindingIdentity),
      );
    }
    return data;
  }

  Future<void> _writeData(_JournalData data) async {
    final encoded = data.bindings.isEmpty && data.entries.isEmpty
        ? null
        : jsonEncode(<String, Object>{
            'schema': schema,
            'bindings': data.bindings
                .map((binding) => binding.toJson())
                .toList(),
            'entries': data.entries.map((entry) => entry.toJson()).toList(),
          });
    if (encoded != null && utf8.encode(encoded).length > maxEncodedBytes) {
      throw const GatewayTurnJournalException();
    }

    String? previous;
    try {
      previous = await _store.read();
      if (encoded == null) {
        await _store.delete();
      } else {
        await _store.write(encoded);
      }
      final verified = await _store.read();
      if (verified != encoded) throw const GatewayTurnJournalException();
    } catch (_) {
      try {
        if (previous == null) {
          await _store.delete();
        } else {
          await _store.write(previous);
        }
      } catch (_) {
        // The caller still receives only the generic fail-closed exception.
      }
      throw const GatewayTurnJournalException();
    }
  }

  GatewayTurnJournalSnapshot _freeze(_JournalData data) {
    return GatewayTurnJournalSnapshot(
      bindings: List<GatewayTurnJournalBinding>.unmodifiable(data.bindings),
      entries: List<GatewayTurnJournalEntry>.unmodifiable(data.entries),
    );
  }

  Future<String?> _readCurrentAfterLegacyPurge() async {
    try {
      final hasV1 = await _store.readLegacy() != null;
      final encoded = await _store.read();
      if (encoded != null && utf8.encode(encoded).length > maxEncodedBytes) {
        throw const GatewayTurnJournalException();
      }
      final hasIncompatibleCurrent = _hasLegacySchema(encoded);
      if (!hasV1 && !hasIncompatibleCurrent) return encoded;

      if (hasV1) {
        await _store.deleteLegacy();
        if (await _store.readLegacy() != null) {
          throw const GatewayTurnJournalException();
        }
      }
      if (hasIncompatibleCurrent) {
        await _store.delete();
        if (await _store.read() != null) {
          throw const GatewayTurnJournalException();
        }
      }
    } catch (_) {
      throw const GatewayTurnJournalException();
    }
    // The first encounter always stops. No v2/v1 field, especially a runtime
    // session ID, is ever parsed or migrated into the v3 authority record.
    throw const GatewayTurnJournalException();
  }
}

class _JournalData {
  final List<GatewayTurnJournalBinding> bindings;
  final List<GatewayTurnJournalEntry> entries;

  _JournalData({required this.bindings, required this.entries});

  factory _JournalData.empty() => _JournalData(bindings: [], entries: []);
}

class _GatewayTurnJournalSerializationQueue {
  Future<void> tail = Future<void>.value();
  final Map<String, GatewayTurnRecoveryState> processPoisonedFailures = {};
  GatewayTurnRecoveryState? authorityWideProcessPoison;
}

final Expando<_GatewayTurnJournalSerializationQueue>
_journalSerializationQueues = Expando<_GatewayTurnJournalSerializationQueue>(
  'gateway-turn-journal-serialization',
);

_GatewayTurnJournalSerializationQueue _journalSerializationQueueFor(
  GatewayTurnJournalStore store,
) {
  final authority = store is GatewayTurnJournalSerializationAuthority
      ? (store as GatewayTurnJournalSerializationAuthority)
            .journalSerializationAuthority
      : store;
  final existing = _journalSerializationQueues[authority];
  if (existing != null) return existing;
  final created = _GatewayTurnJournalSerializationQueue();
  _journalSerializationQueues[authority] = created;
  return created;
}

String _validatedJournalScope(
  String connectionId,
  String endpointDigest,
  String localSessionId,
) {
  if (!_boundedIdentity(connectionId) ||
      !_lowerHexDigest(endpointDigest) ||
      !_boundedIdentity(localSessionId)) {
    throw ArgumentError('Invalid recovery journal scope.');
  }
  return _journalScopeIdentity(connectionId, endpointDigest, localSessionId);
}

String _journalScopeIdentity(
  String connectionId,
  String endpointDigest,
  String localSessionId,
) => jsonEncode(<String>[connectionId, endpointDigest, localSessionId]);

void _validateEntryUpdate(
  GatewayTurnJournalEntry previous,
  GatewayTurnJournalEntry next,
) {
  final previousTurnId = previous.turnId;
  if (previousTurnId != null && next.turnId != previousTurnId ||
      next.lastSeq < previous.lastSeq ||
      next.eventPayloadBytes < previous.eventPayloadBytes ||
      previous.terminalEventRecorded && !next.terminalEventRecorded ||
      previous.terminalResult != null &&
          (next.terminalResult == null ||
              !previous.terminalResult!.sameResult(next.terminalResult!)) ||
      next.updatedAtEpochMs < previous.updatedAtEpochMs) {
    throw const GatewayTurnJournalException();
  }

  final previousFailure = previous.failure;
  final nextFailure = next.failure;
  if (previousFailure != null &&
      (next.turnId != previous.turnId ||
          next.status != previous.status ||
          next.lastSeq != previous.lastSeq ||
          next.eventPayloadBytes != previous.eventPayloadBytes ||
          next.terminalEventRecorded != previous.terminalEventRecorded ||
          !_sameTerminalResult(next.terminalResult, previous.terminalResult) ||
          next.ackUncertain != previous.ackUncertain ||
          nextFailure != previousFailure)) {
    throw const GatewayTurnJournalException();
  }

  final previousStatus = previous.status;
  final nextStatus = next.status;
  if (previousStatus != null &&
      (nextStatus == null ||
          !_journalTransitionAllowed(previousStatus, nextStatus))) {
    throw const GatewayTurnJournalException();
  }
  if (previous.isTerminal &&
      (next.turnId != previous.turnId ||
          next.status != previous.status ||
          next.lastSeq != previous.lastSeq ||
          next.eventPayloadBytes != previous.eventPayloadBytes ||
          next.terminalEventRecorded != previous.terminalEventRecorded ||
          !_sameTerminalResult(next.terminalResult, previous.terminalResult) ||
          next.ackUncertain != previous.ackUncertain ||
          previousFailure != null && nextFailure != previousFailure)) {
    throw const GatewayTurnJournalException();
  }
}

bool _sameTerminalResult(
  GatewayTurnTerminalResult? left,
  GatewayTurnTerminalResult? right,
) {
  if (left == null || right == null) return left == null && right == null;
  return left.sameResult(right);
}

bool _journalTransitionAllowed(
  GatewayRecoveryTurnStatus from,
  GatewayRecoveryTurnStatus to,
) {
  if (from == to) return true;
  if (from.isTerminal) return false;
  if (to.isTerminal) return true;
  return switch (from) {
    GatewayRecoveryTurnStatus.accepted =>
      to == GatewayRecoveryTurnStatus.running,
    GatewayRecoveryTurnStatus.running =>
      to == GatewayRecoveryTurnStatus.waitingInput,
    GatewayRecoveryTurnStatus.waitingInput =>
      to == GatewayRecoveryTurnStatus.running,
    GatewayRecoveryTurnStatus.completed ||
    GatewayRecoveryTurnStatus.failed ||
    GatewayRecoveryTurnStatus.interrupted => false,
  };
}

bool _boundedIdentity(String value) {
  return value.isNotEmpty &&
      value.length <= 256 &&
      value.trim() == value &&
      !value.codeUnits.any((unit) => unit < 32);
}

bool _boundedReference(String value) {
  return value.isNotEmpty &&
      value.length <= 1024 &&
      value.trim() == value &&
      !value.codeUnits.any((unit) => unit < 32);
}

bool _lowerHexDigest(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _canonicalUuid(String value) {
  return value != '00000000-0000-0000-0000-000000000000' &&
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(value);
}

GatewayTurnRecoveryFailure? _recoveryFailureFromWire(Object? value) {
  if (value is! String) return null;
  for (final failure in GatewayTurnRecoveryFailure.values) {
    if (failure.name == value) return failure;
  }
  return null;
}

bool _hasLegacySchema(String? encoded) {
  if (encoded == null) return false;
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return false;
    final schema = decoded['schema'];
    return schema == 'hermes.android.turn-journal.v2' ||
        schema == 'hermes.android.turn-journal.v1';
  } catch (_) {
    return false;
  }
}
