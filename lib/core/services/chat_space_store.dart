import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/session.dart';

class ChatSpace {
  final String id;
  final String name;
  final int createdAt;

  const ChatSpace({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_at': createdAt,
  };

  factory ChatSpace.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final createdAt = json['created_at'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        createdAt is! int) {
      throw const FormatException('Invalid chat space');
    }
    return ChatSpace(id: id, name: name.trim(), createdAt: createdAt);
  }
}

enum ChatSpaceScopeKind { all, unassigned, space }

class ChatSpaceScope {
  final ChatSpaceScopeKind kind;
  final String? spaceId;

  const ChatSpaceScope.all() : kind = ChatSpaceScopeKind.all, spaceId = null;

  const ChatSpaceScope.unassigned()
    : kind = ChatSpaceScopeKind.unassigned,
      spaceId = null;

  const ChatSpaceScope.space(String id)
    : kind = ChatSpaceScopeKind.space,
      spaceId = id;
}

class ChatSpaceState {
  final List<ChatSpace> spaces;
  final Map<String, String> assignments;

  const ChatSpaceState({required this.spaces, required this.assignments});

  String? spaceIdForSession(String sessionId) => assignments[sessionId];

  double? latestActivityFor(Iterable<Session> sessions, String spaceId) {
    double? latest;
    for (final session in sessions) {
      if (assignments[session.id] != spaceId) continue;
      if (latest == null || session.startedAt > latest) {
        latest = session.startedAt;
      }
    }
    return latest;
  }

  List<Session> sessionsFor(Iterable<Session> sessions, ChatSpaceScope scope) {
    return sessions.where((session) {
      final assigned = assignments[session.id];
      return switch (scope.kind) {
        ChatSpaceScopeKind.all => true,
        ChatSpaceScopeKind.unassigned => assigned == null,
        ChatSpaceScopeKind.space => assigned == scope.spaceId,
      };
    }).toList();
  }
}

class ChatSpaceStore {
  static const _uuid = Uuid();
  static final _owners = Expando<_SpacePreferenceOwner>();

  final SharedPreferences _preferences;
  final String connectionId;

  ChatSpaceStore(this._preferences, {required this.connectionId});

  String get _key => 'chat_spaces_v1_$connectionId';
  _SpacePreferenceOwner get _owner =>
      _owners[_preferences] ??= _SpacePreferenceOwner();

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final owner = _owner;
    final previous = owner.tail;
    final completed = Completer<void>();
    final tail = completed.future;
    owner.tail = tail;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (identical(owner.tail, tail)) owner.tail = null;
      completed.complete();
    }
  }

  Future<T> _mutate<T>(Future<T> Function() action) => _serialized(() async {
    // A failed repair leaves only the prior confirmed projection readable.
    // No successor may serialize it (or speculative prefs) without fresh I/O.
    if (_owner.dirty.contains(_key)) await _reload();
    return action();
  });

  Future<void> _reload() async {
    try {
      await _preferences.reload();
      _owner.confirmed[_key] = _preferences.getString(_key);
      _owner.dirty.remove(_key);
    } catch (_) {
      throw StateError('Could not read chat spaces on this device');
    }
  }

  Future<ChatSpaceState> load() => _serialized(() async => _readState());

  ChatSpaceState _readState() {
    final raw = _owner.dirty.contains(_key)
        ? _owner.confirmed[_key]
        : _preferences.getString(_key);
    if (!_owner.dirty.contains(_key)) _owner.confirmed[_key] = raw;
    if (raw == null || raw.isEmpty) {
      return const ChatSpaceState(spaces: [], assignments: {});
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final map = Map<String, dynamic>.from(decoded);
      final rawSpaces = map['spaces'];
      final rawAssignments = map['assignments'];
      if (rawSpaces is! List || rawAssignments is! Map) {
        throw const FormatException();
      }
      final spaces = rawSpaces
          .map(
            (value) =>
                ChatSpace.fromJson(Map<String, dynamic>.from(value as Map)),
          )
          .toList();
      final knownIds = spaces.map((space) => space.id).toSet();
      final assignments = <String, String>{};
      for (final entry in rawAssignments.entries) {
        if (entry.key is String &&
            entry.value is String &&
            knownIds.contains(entry.value)) {
          assignments[entry.key as String] = entry.value as String;
        }
      }
      return ChatSpaceState(
        spaces: List.unmodifiable(spaces),
        assignments: Map.unmodifiable(assignments),
      );
    } catch (_) {
      return const ChatSpaceState(spaces: [], assignments: {});
    }
  }

  Future<ChatSpace> createSpace(String name) => _mutate(() async {
    final normalized = _normalizeName(name);
    final state = _readState();
    if (state.spaces.any(
      (space) => space.name.toLowerCase() == normalized.toLowerCase(),
    )) {
      throw const FormatException('A space with this name already exists');
    }
    final space = ChatSpace(
      id: _uuid.v4(),
      name: normalized,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _save(
      ChatSpaceState(
        spaces: [...state.spaces, space],
        assignments: state.assignments,
      ),
    );
    return space;
  });

  Future<void> renameSpace(String spaceId, String name) => _mutate(() async {
    final normalized = _normalizeName(name);
    final state = _readState();
    final index = state.spaces.indexWhere((space) => space.id == spaceId);
    if (index < 0) {
      throw ArgumentError.value(spaceId, 'spaceId', 'Unknown chat space');
    }
    if (state.spaces.any(
      (space) =>
          space.id != spaceId &&
          space.name.toLowerCase() == normalized.toLowerCase(),
    )) {
      throw const FormatException('A space with this name already exists');
    }
    final spaces = List<ChatSpace>.from(state.spaces);
    final existing = spaces[index];
    spaces[index] = ChatSpace(
      id: existing.id,
      name: normalized,
      createdAt: existing.createdAt,
    );
    await _save(ChatSpaceState(spaces: spaces, assignments: state.assignments));
  });

  Future<void> assignSession(
    String sessionId,
    String? spaceId,
  ) => _mutate(() async {
    if (sessionId.trim().isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId');
    }
    final state = _readState();
    if (spaceId != null && !state.spaces.any((space) => space.id == spaceId)) {
      throw ArgumentError.value(spaceId, 'spaceId', 'Unknown chat space');
    }
    final assignments = Map<String, String>.from(state.assignments);
    if (spaceId == null) {
      assignments.remove(sessionId);
    } else {
      assignments[sessionId] = spaceId;
    }
    await _save(ChatSpaceState(spaces: state.spaces, assignments: assignments));
  });

  String _normalizeName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty ||
        normalized.length > 80 ||
        normalized.contains('\u0000') ||
        RegExp(r'[\r\n]').hasMatch(normalized)) {
      throw const FormatException('Space name must be 1–80 characters');
    }
    return normalized;
  }

  Future<void> _save(ChatSpaceState state) async {
    final encoded = jsonEncode({
      'spaces': state.spaces.map((space) => space.toJson()).toList(),
      'assignments': state.assignments,
    });
    try {
      final saved = await _preferences.setString(_key, encoded);
      if (saved) {
        _owner.confirmed[_key] = encoded;
        return;
      }
    } catch (_) {
      // Surface one safe storage error, not a platform exception payload.
    }
    // SharedPreferences mutates cache before platform acknowledgement. Share
    // the confirmed snapshot across wrappers even if physical repair fails.
    // The dirty fence also blocks later writes until a fresh read succeeds.
    _owner.dirty.add(_key);
    try {
      await _reload();
    } catch (_) {
      // A failed cache repair is still a failed save, not a platform payload.
    }
    throw StateError('Could not save chat spaces on this device');
  }
}

class _SpacePreferenceOwner {
  Future<void>? tail;
  final confirmed = <String, String?>{};
  final dirty = <String>{};
}
