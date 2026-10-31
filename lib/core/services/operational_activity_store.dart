import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A presentation index, never recovery or transcript authority.
enum OperationalActivityState {
  submitted,
  running,
  needsInput,
  reconciling,
  unknown,
  completed,
  failed,
}

/// Only identifiers and lifecycle metadata may cross this persistence boundary.
/// In particular, do not add titles, prompts, request payloads or error prose.
class OperationalActivityRecord {
  final String scope;
  final String localSessionId;
  final String? storedSessionId;
  final String? lineageRootId;
  final String turnId;
  final OperationalActivityState state;
  final int updatedAtEpochMs;

  const OperationalActivityRecord({
    required this.scope,
    required this.localSessionId,
    required this.storedSessionId,
    this.lineageRootId,
    required this.turnId,
    required this.state,
    required this.updatedAtEpochMs,
  });

  // A restored owner may have been opened through its stored alias. The turn,
  // not the currently mounted chat alias, is the row's durable identity.
  String get key => jsonEncode([scope, turnId]);

  bool get isUnresolved => switch (state) {
    OperationalActivityState.completed ||
    OperationalActivityState.failed ||
    OperationalActivityState.unknown => false,
    _ => true,
  };

  OperationalActivityRecord withLineageRoot(String root) =>
      OperationalActivityRecord(
        scope: scope,
        localSessionId: localSessionId,
        storedSessionId: storedSessionId,
        lineageRootId: root,
        turnId: turnId,
        state: state,
        updatedAtEpochMs: updatedAtEpochMs,
      );

  Map<String, Object?> toJson() => {
    'scope': scope,
    'localSessionId': localSessionId,
    'storedSessionId': storedSessionId,
    if (lineageRootId != null) 'lineageRootId': lineageRootId,
    'turnId': turnId,
    'state': state.name,
    'updatedAtEpochMs': updatedAtEpochMs,
  };

  static OperationalActivityRecord? parse(Object? raw) {
    if (raw is! Map) return null;
    String? id(String key) {
      final value = raw[key];
      return value is String && value.isNotEmpty && value.length <= 512
          ? value
          : null;
    }

    final scope = id('scope');
    final local = id('localSessionId');
    final stored = id('storedSessionId');
    final root = id('lineageRootId');
    final turn = id('turnId');
    final updated = raw['updatedAtEpochMs'];
    final state = OperationalActivityState.values
        .where((state) => state.name == raw['state'])
        .firstOrNull;
    if (scope == null ||
        local == null ||
        (raw['storedSessionId'] != null && stored == null) ||
        (raw['lineageRootId'] != null && root == null) ||
        turn == null ||
        state == null ||
        updated is! int ||
        updated < 0) {
      return null;
    }
    return OperationalActivityRecord(
      scope: scope,
      localSessionId: local,
      storedSessionId: stored,
      lineageRootId: root,
      turnId: turn,
      state: state,
      updatedAtEpochMs: updated,
    );
  }
}

/// All instances share one physical read/modify/write queue. Reads join writes
/// already accepted, including a retiring owner's writes during replacement.
/// Unresolved rows never expire; finished/unknown rows have bounded retention.
class OperationalActivityStore {
  static const preferenceKey = 'operational_activity_v1';
  static const finishedRetention = Duration(days: 7);
  static const maxFinishedRecords = 256;
  static Future<void>? _tail;
  final Future<SharedPreferences> Function() _preferences;
  final int Function() _nowEpochMs;

  OperationalActivityStore({
    Future<SharedPreferences> Function()? preferences,
    int Function()? nowEpochMs,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _nowEpochMs =
           nowEpochMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  Future<T> _serialized<T>(Future<T> Function(SharedPreferences) action) {
    Future<T> perform() async {
      final prefs = await _preferences();
      // Receipt/account stores reload the same process-wide preferences cache.
      // Join our accepted writes, then read physical state rather than a cache
      // an overlapping unrelated reload may have rolled back.
      await prefs.reload();
      return action(prefs);
    }

    final previous = _tail;
    final flight = previous == null
        ? perform()
        : previous.then((_) => perform());
    final tail = flight.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = tail;
    // Do not retain a completed Future (and its Flutter fake-async zone).
    tail.whenComplete(() {
      if (identical(_tail, tail)) _tail = null;
    }).ignore();
    return flight;
  }

  List<OperationalActivityRecord> _read(SharedPreferences prefs) {
    final value = prefs.getString(preferenceKey);
    if (value == null) return [];
    Object? raw;
    try {
      raw = jsonDecode(value);
    } on FormatException {
      return []; // Corrupt presentation metadata is not recovery evidence.
    }
    if (raw is! List) return [];
    final rows = <String, OperationalActivityRecord>{};
    for (final value in raw) {
      final row = OperationalActivityRecord.parse(value);
      if (row != null) rows[row.key] = row;
    }
    return rows.values.toList();
  }

  List<OperationalActivityRecord> _retained(
    Iterable<OperationalActivityRecord> records,
  ) {
    final cutoff = _nowEpochMs() - finishedRetention.inMilliseconds;
    final unresolved = <OperationalActivityRecord>[];
    final finished = <OperationalActivityRecord>[];
    for (final record in records) {
      if (record.isUnresolved) {
        unresolved.add(record);
      } else if (record.updatedAtEpochMs >= cutoff) {
        finished.add(record);
      }
    }
    finished.sort(_newestFirst);
    return [...unresolved, ...finished.take(maxFinishedRecords)]
      ..sort(_newestFirst);
  }

  /// Returns newest first, without creating a gateway transport or chat owner.
  Future<List<OperationalActivityRecord>> load(
    String scope, {
    Map<String, String> sessionRoots = const {},
  }) => _serialized((prefs) async {
    final rows = _retained(_read(prefs));
    var changed = false;
    final resolved = <OperationalActivityRecord>[];
    for (final record in rows) {
      final root =
          sessionRoots[record.storedSessionId] ??
          sessionRoots[record.localSessionId];
      if (record.scope == scope &&
          root != null &&
          root.isNotEmpty &&
          root.length <= 512 &&
          root != record.lineageRootId) {
        resolved.add(record.withLineageRoot(root));
        changed = true;
      } else {
        resolved.add(record);
      }
    }
    // Persist only aliases belonging to retained turns, never an unbounded
    // session catalogue or any title/transcript content.
    if (changed) await _write(prefs, resolved);
    return List.unmodifiable(resolved.where((record) => record.scope == scope));
  });

  Future<void> put(OperationalActivityRecord record) => putAll([record]);

  /// Piggyback failed turn repairs on new observations in one physical write.
  /// Capture the batch at acceptance, not after waiting for the global queue.
  Future<void> putAll(Iterable<OperationalActivityRecord> records) {
    final accepted = records.toList(growable: false);
    return _serialized((prefs) async {
      if (accepted.any(
        (record) => OperationalActivityRecord.parse(record.toJson()) == null,
      )) {
        throw ArgumentError('Invalid operational activity metadata.');
      }
      final rows = {for (final row in _read(prefs)) row.key: row};
      for (final record in accepted) {
        final root = record.lineageRootId ?? rows[record.key]?.lineageRootId;
        rows[record.key] = root == null ? record : record.withLineageRoot(root);
      }
      await _write(prefs, _retained(rows.values));
    });
  }

  Future<void> clearScope(String scope) => _serialized((prefs) async {
    final rows = _read(prefs)..removeWhere((row) => row.scope == scope);
    await _write(prefs, _retained(rows));
  });

  Future<void> _write(
    SharedPreferences prefs,
    List<OperationalActivityRecord> rows,
  ) async {
    try {
      if (!await prefs.setString(
        preferenceKey,
        jsonEncode(rows.map((row) => row.toJson()).toList()),
      )) {
        throw StateError('Could not persist operational activity.');
      }
    } catch (_) {
      // SharedPreferences updates its cache optimistically, even on failure.
      await prefs.reload();
      rethrow;
    }
  }
}

int _newestFirst(OperationalActivityRecord a, OperationalActivityRecord b) {
  final byTime = b.updatedAtEpochMs.compareTo(a.updatedAtEpochMs);
  return byTime != 0 ? byTime : a.key.compareTo(b.key);
}
