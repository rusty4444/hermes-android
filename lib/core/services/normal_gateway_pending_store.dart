import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A receipt, not a prompt journal. No text, credentials, runtime session ids,
/// approvals or sensitive answers may cross this persistence boundary.
class NormalGatewayPendingMarker {
  final String scope;
  final String localSessionId;
  final String storedSessionId;
  final String turnId;
  final int? rowFloor;
  final String phase;
  final int createdAt;
  final int updatedAt;

  const NormalGatewayPendingMarker({
    required this.scope,
    required this.localSessionId,
    required this.storedSessionId,
    required this.turnId,
    required this.rowFloor,
    required this.phase,
    required this.createdAt,
    required this.updatedAt,
  });

  String get key => jsonEncode([scope, localSessionId, turnId]);

  NormalGatewayPendingMarker withPhase(String value) =>
      NormalGatewayPendingMarker(
        scope: scope,
        localSessionId: localSessionId,
        storedSessionId: storedSessionId,
        turnId: turnId,
        rowFloor: rowFloor,
        phase: value,
        createdAt: createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, Object?> toJson() => {
    'schema': 1,
    'scope': scope,
    'local_id': localSessionId,
    'stored_id': storedSessionId,
    'local_turn_id': turnId,
    'row_floor': rowFloor,
    'phase': phase,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  static NormalGatewayPendingMarker? parse(Object? raw) {
    if (raw is! Map || raw['schema'] != 1) return null;
    String? id(String key) {
      final value = raw[key];
      return value is String && value.isNotEmpty && value.length <= 512
          ? value
          : null;
    }

    final scope = id('scope');
    final local = id('local_id');
    final stored = id('stored_id');
    final turn = id('local_turn_id');
    final phase = raw['phase'];
    final floor = raw['row_floor'];
    if (scope == null ||
        local == null ||
        stored == null ||
        turn == null ||
        !{'write_ahead', 'emitted', 'settled'}.contains(phase) ||
        (floor != null && (floor is! int || floor < 0)) ||
        raw['created_at'] is! int ||
        raw['updated_at'] is! int) {
      return null;
    }
    return NormalGatewayPendingMarker(
      scope: scope,
      localSessionId: local,
      storedSessionId: stored,
      turnId: turn,
      rowFloor: floor as int?,
      phase: phase as String,
      createdAt: raw['created_at'] as int,
      updatedAt: raw['updated_at'] as int,
    );
  }
}

/// All instances share the physical read/modify/write queue. Never expire an
/// unresolved receipt or evict it to admit another prompt: absence is not proof
/// that a server-side turn stopped. The bounded store fails closed when full.
class NormalGatewayPendingStore {
  static const preferenceKey = 'normal_gateway_pending_v1';
  static const maxMarkers = 256;
  static Future<void>? _tail;
  final Future<SharedPreferences> Function() _preferences;

  NormalGatewayPendingStore({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  Future<T> _serialized<T>(Future<T> Function(SharedPreferences) action) {
    final previous = _tail;
    Future<T> perform() async {
      final prefs = await _preferences();
      // SharedPreferences updates its process cache before physical ACK. A
      // rejected or lost-ACK write must not hide an unresolved WAL on reload or
      // let the next transaction persist a speculative tombstone.
      await prefs.reload();
      return action(prefs);
    }

    final flight = previous == null
        ? perform()
        : previous.then((_) => perform());
    final tail = flight.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tail = tail;
    tail.whenComplete(() {
      if (identical(_tail, tail)) _tail = null;
    }).ignore();
    return flight;
  }

  List<NormalGatewayPendingMarker> _read(SharedPreferences prefs) {
    final value = prefs.getString(preferenceKey);
    if (value == null) return [];
    final raw = jsonDecode(value);
    if (raw is! List || raw.length > maxMarkers) {
      throw StateError('Invalid normal gateway pending receipts.');
    }
    final markers = raw.map(NormalGatewayPendingMarker.parse).toList();
    if (markers.any((marker) => marker == null)) {
      throw StateError('Invalid normal gateway pending receipt.');
    }
    return markers.cast<NormalGatewayPendingMarker>();
  }

  Future<List<NormalGatewayPendingMarker>> load(String scope) => _serialized(
    (prefs) async => _read(prefs)
        .where((marker) => marker.scope == scope && marker.phase != 'settled')
        .toList(growable: false),
  );

  Future<void> put(NormalGatewayPendingMarker marker) => _serialized((
    prefs,
  ) async {
    final rows = _read(prefs)
      ..removeWhere((row) => row.key == marker.key || row.phase == 'settled');
    if (rows.length >= maxMarkers) {
      throw StateError('Pending turn receipt capacity reached.');
    }
    rows.add(marker);
    if (!await prefs.setString(
      preferenceKey,
      jsonEncode(rows.map((row) => row.toJson()).toList()),
    )) {
      throw StateError('Could not persist pending turn receipt.');
    }
  });

  Future<void> remove(NormalGatewayPendingMarker marker) =>
      _serialized((prefs) async {
        final rows = _read(prefs)..removeWhere((row) => row.key == marker.key);
        if (!await prefs.setString(
          preferenceKey,
          jsonEncode(rows.map((row) => row.toJson()).toList()),
        )) {
          throw StateError('Could not clear pending turn receipt.');
        }
      });
}
