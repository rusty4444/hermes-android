import 'package:shared_preferences/shared_preferences.dart';

import 'connection_manager.dart';

/// Device-only pins saved by Hermes Android 3.2.4 and earlier.
///
/// Chats now pin through the server's `pinned` flag, shared with Hermes
/// Desktop. This store remains only so [migrateLegacyChatPins] can move old
/// device pins to the server, and so backup/restore and connection deletion
/// keep handling any ids that have not migrated yet.
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
  /// connection so concurrent changes cannot overwrite each other.
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

final Map<String, Future<int>> _migrations = {};

/// Moves legacy device-only pins to the server `pinned` flag.
///
/// An id leaves the device only once its outcome is settled: the server
/// confirmed the pin (or already had it), the API server reported that exact
/// id `session_not_found`, or the chat is archived, hidden or an internal
/// child (the old device list never showed those). A network failure, a
/// mismatched read-back or a gateway without synced pins keeps the id for a
/// later attempt, so nothing the user pinned is lost.
///
/// Concurrent callers for the same connection share one migration. Returns
/// how many chats gained a confirmed server pin, so callers know whether a
/// list refresh is worthwhile.
Future<int> migrateLegacyChatPins(ApiClient client, LocalChatPinStore store) {
  final key = store._key;
  final existing = _migrations[key];
  if (existing != null) return existing;
  final migration = _migrateLegacyChatPins(client, store);
  _migrations[key] = migration;
  migration.whenComplete(() {
    if (identical(_migrations[key], migration)) _migrations.remove(key);
  }).ignore();
  return migration;
}

Future<int> _migrateLegacyChatPins(
  ApiClient client,
  LocalChatPinStore store,
) async {
  final ids = await store.load();
  var migrated = 0;
  for (final id in ids) {
    try {
      final metadata = await client.getSession(id);
      final retired =
          metadata['archived'] == true ||
          metadata['hidden'] == true ||
          metadata['is_internal_child'] == true;
      if (!retired && metadata['pinned'] != true) {
        await client.setSessionPinned(sessionId: id, pinned: true);
        migrated++;
      }
      await store.removeSession(id);
    } on SessionNotFoundException {
      await store.removeSession(id);
    } on SyncedPinsUnsupportedException {
      // Every remaining id would fail the same way on this gateway.
      break;
    } catch (_) {
      // Keep this id; the next list load retries it.
    }
  }
  return migrated;
}
