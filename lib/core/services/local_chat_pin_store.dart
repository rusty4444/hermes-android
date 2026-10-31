import 'package:shared_preferences/shared_preferences.dart';

import 'connection_manager.dart';

/// Device-only chat order. This never writes the Gateway's `pinned` flag.
class LocalChatPinStore {
  static const keyPrefix = 'local_chat_pins_v1_';
  static final Map<String, Future<void>> _writes = {};

  final SharedPreferences _preferences;
  final String connectionId;

  LocalChatPinStore(this._preferences, {required this.connectionId});

  String get _key => '$keyPrefix$connectionId';

  Future<List<String>> load() async {
    await _writes[_key];
    return _read();
  }

  List<String> _read() => List.unmodifiable({
    for (final id in _preferences.getStringList(_key) ?? const <String>[])
      if (id.isNotEmpty) id,
  });

  /// New pins lead existing ones. Serialize writes across screens sharing a
  /// connection so rapid pin/unpin actions cannot overwrite each other.
  Future<List<String>> setPinned(String sessionId, {required bool pinned}) {
    if (sessionId.isEmpty) throw ArgumentError.value(sessionId, 'sessionId');
    final previous = _writes[_key] ?? Future<void>.value();
    final operation = previous.then((_) async {
      final current = _read();
      final next = [
        if (pinned) sessionId,
        for (final id in current)
          if (id != sessionId) id,
      ];
      if (next.length != current.length ||
          !next.asMap().entries.every(
            (entry) => current[entry.key] == entry.value,
          )) {
        final saved = await _preferences.setStringList(_key, next);
        if (!saved) throw StateError('Could not save chat pins on this device');
      }
      return List<String>.unmodifiable(next);
    });
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _writes[_key] = settled;
    settled.whenComplete(() {
      if (identical(_writes[_key], settled)) _writes.remove(_key);
    });
    return operation;
  }

  Future<void> removeSession(String sessionId) async {
    await setPinned(sessionId, pinned: false);
  }

  static Future<void> removeConnection(
    SharedPreferences preferences,
    String connectionId,
  ) async {
    final key = '$keyPrefix$connectionId';
    await _writes[key];
    await preferences.remove(key);
  }
}

/// A compressed chat is listed under its live tip, but a pin may still name
/// the old root id that was visible when the user pinned it.
String? localPinIdForSession(Session session, Iterable<String> pinnedIds) {
  for (final id in pinnedIds) {
    if (id == session.id || id == session.lineageRootId) return id;
  }
  return null;
}

/// Apply device order without changing the server's session model or order.
List<Session> orderLocalPinnedChats(
  Iterable<Session> sessions,
  List<String> pinnedIds,
) {
  final rows = sessions.toList();
  final byId = <String, Session>{};
  for (final session in rows) {
    byId[session.id] = session;
    if (session.lineageRootId case final rootId?) byId[rootId] = session;
  }
  final seen = <String>{};
  return [
    for (final id in pinnedIds)
      if (byId[id] case final session?)
        if (seen.add(session.id)) session,
    for (final session in rows)
      if (seen.add(session.id)) session,
  ];
}

/// Fetch old local pins beyond the first page (or Home's bounded scan). An
/// exact-id row has neither the list's preview nor effective activity, and a
/// compressed root is not the live tip. Resolve its title through the rich
/// list route, which projects both fields and the continuation lineage.
Future<List<Session>> loadUnlistedLocalPins(
  ApiClient client,
  Iterable<Session> listed,
  List<String> pinnedIds,
) async {
  final listedIds = <String>{
    for (final session in listed) session.id,
    for (final session in listed) ?session.lineageRootId,
  };
  final missing = pinnedIds.where((id) => !listedIds.contains(id));
  final resolved = await Future.wait(
    missing.map((id) async {
      try {
        final metadata = await client.getSession(id);
        if (metadata['hidden'] == true ||
            metadata['archived'] == true ||
            metadata['is_internal_child'] == true) {
          return null;
        }
        final title = metadata['title'];
        if (title is! String || title.trim().isEmpty) return null;
        final rich = await client.getSessionsPage(limit: 200, title: title);
        for (final session in rich.sessions) {
          if (!session.archived &&
              (session.id == id || session.lineageRootId == id)) {
            return session;
          }
        }
        return null;
      } catch (_) {
        // Older gateways may not expose title-filtered rich rows. Do not
        // substitute a bare row: it could duplicate a compression tip and
        // would misrepresent the preview and recent activity.
        return null;
      }
    }),
  );
  final seen = listed.map((session) => session.id).toSet();
  return [
    for (final session in resolved.whereType<Session>())
      if (seen.add(session.id)) session,
  ];
}
