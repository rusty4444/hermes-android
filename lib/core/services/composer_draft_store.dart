import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// An unavailable read is not evidence that a draft is absent. Keep provider
/// details out of this public error, including paths and stored values.
class ComposerDraftReadException implements Exception {
  const ComposerDraftReadException();

  @override
  String toString() => 'Composer draft is unavailable.';
}

/// A route's write authority, independent of its composer edit revision. A
/// replacement route owns later writes; disposing the old route cannot erase
/// the replacement's draft. This handle contains no widget or callback.
class ComposerDraftHandle {
  final String connectionId;
  final String sessionId;
  final int _owner;

  ComposerDraftHandle._(this.connectionId, this.sessionId, this._owner);

  /// An explicit edit may take ownership back, including a deliberate clear.
  void edited() => ComposerDraftStore._claim(this);

  /// Transfer only a participating lease after a verified durable alias. This
  /// does not manufacture user intent or reclaim an unrelated newer writer.
  Future<void> handoffFrom(
    Iterable<ComposerDraftHandle> participants, {
    required String canonicalSessionId,
    required bool Function() isCurrent,
  }) => ComposerDraftStore._serialized((prefs) async {
    if (!isCurrent()) return;
    final key = ComposerDraftStore._resolve(prefs, connectionId, sessionId);
    final canonical = ComposerDraftStore._resolve(
      prefs,
      connectionId,
      canonicalSessionId,
    );
    if (key != canonical) return; // failed alias publication is not a handoff
    final owner = ComposerDraftStore._owners[key];
    if (participants.any(
      (handle) => handle.connectionId == connectionId && handle._owner == owner,
    )) {
      ComposerDraftStore._owners[key] = _owner;
    }
  }).catchError((Object _) {});

  Future<void> save(String text, {bool Function()? isCurrent}) =>
      ComposerDraftStore._save(
        connectionId: connectionId,
        sessionId: sessionId,
        text: text,
        owner: _owner,
        isCurrent: isCurrent,
      );
}

/// Connection-scoped composer drafts and durable local -> stored aliases.
/// All reads, writes, and alias migrations share one physical queue, including
/// writes from an old route during replacement. Empty strings are tombstones:
/// an intentional canonical clear must not resurrect an older local draft.
abstract final class ComposerDraftStore {
  static const _prefix = 'composer_draft';
  static const _aliasPrefix = 'composer_draft_alias';
  static const _writtenPrefix = 'composer_draft_written';
  static Future<void>? _tail;
  static int _nextOwner = 0;
  static final Map<String, int> _owners = {};
  static SharedPreferences? _ownerPreferences;

  static String _key(String connectionId, String sessionId) {
    final namespace = base64Url
        .encode(utf8.encode('$connectionId\u0000$sessionId'))
        .replaceAll('=', '');
    return '$_prefix.$namespace';
  }

  static String _aliasKey(String key) =>
      '$_aliasPrefix.${key.substring(_prefix.length + 1)}';

  static String _resolve(
    SharedPreferences prefs,
    String connectionId,
    String sessionId,
  ) {
    var key = _key(connectionId, sessionId);
    final seen = <String>{};
    while (seen.add(key)) {
      final target = prefs.getString(_aliasKey(key));
      if (target == null) return key;
      key = _key(connectionId, target);
    }
    throw StateError('Cyclic composer draft alias.');
  }

  static Future<T> _serialized<T>(
    Future<T> Function(SharedPreferences) action,
  ) {
    Future<T> perform() async {
      final prefs = await SharedPreferences.getInstance();
      if (!identical(_ownerPreferences, prefs)) {
        _owners.clear();
        _ownerPreferences = prefs;
      }
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
    tail.whenComplete(() {
      if (identical(_tail, tail)) _tail = null;
    }).ignore();
    return flight;
  }

  static ComposerDraftHandle open({
    required String connectionId,
    required String sessionId,
  }) {
    final handle = ComposerDraftHandle._(connectionId, sessionId, ++_nextOwner);
    _claim(handle);
    return handle;
  }

  static void _claim(ComposerDraftHandle handle) {
    _serialized((prefs) async {
      _owners[_resolve(prefs, handle.connectionId, handle.sessionId)] =
          handle._owner;
    }).ignore();
  }

  /// Copy before publishing the alias, with best-effort physical rollback.
  /// Existing canonical text/clear wins; retain the public legacy source copy.
  /// This shares the same physical queue and writer ownership as normal saves.
  static Future<void> bind({
    required String connectionId,
    required String localSessionId,
    required String storedSessionId,
    bool Function()? isCurrent,
  }) async {
    try {
      await _serialized((prefs) async {
        // Activity/WAL reloads can roll back the speculative cache during a
        // draft write. Join draft writes, then read the physical source,
        // canonical value and clear marker before migrating.
        await prefs.reload();
        if (isCurrent?.call() == false) return;
        final local = _resolve(prefs, connectionId, localSessionId);
        final stored = _resolve(prefs, connectionId, storedSessionId);
        if (local == stored) return;
        final targetMarker = _writtenKey(stored);
        final aliasKey = _aliasKey(local);
        final oldAlias = prefs.getString(aliasKey);
        final oldText = prefs.getString(stored);
        final oldMarker = prefs.getBool(targetMarker);
        final canonicalExists = oldText != null || oldMarker == true;
        var copied = false;
        try {
          if (!canonicalExists) {
            final draft = prefs.getString(local);
            if (draft != null || prefs.getBool(_writtenKey(local)) == true) {
              await _write(prefs, stored, draft ?? '');
              copied = true;
            }
          }
          if (isCurrent?.call() == false ||
              !await prefs.setString(aliasKey, storedSessionId)) {
            throw StateError('Composer draft alias was not committed.');
          }
        } catch (_) {
          await _restoreValue(prefs, aliasKey, oldAlias);
          await prefs.reload();
          // A physically committed alias after ACK loss and rejected rollback
          // retains its copied target AND joins the same ownership handoff.
          if (prefs.getString(aliasKey) != storedSessionId) {
            if (copied) {
              await _restoreValue(prefs, stored, oldText);
              await _restoreValue(prefs, targetMarker, oldMarker);
            }
            await prefs.reload();
            return;
          }
        }
        // Never let an old local checkpoint/rejection steal a canonical draft.
        // Only an explicit later edit can claim this shared lease again.
        _owners[stored] ??= canonicalExists ? 0 : _owners[local] ?? 0;
        _owners.remove(local);
      });
    } catch (_) {
      // Best-effort; the untouched source remains available to retry migration.
    }
  }

  /// Returns null only after successfully observing no nonempty draft. Throws
  /// [ComposerDraftReadException] if storage or alias resolution is unavailable.
  static Future<String?> read({
    required String connectionId,
    required String sessionId,
  }) async {
    try {
      return await _serialized((prefs) async {
        // Remount hydration must observe physical drafts, not a process-wide
        // cache that an older unrelated reload may have replaced during save.
        await prefs.reload();
        final value = prefs.getString(_resolve(prefs, connectionId, sessionId));
        return (value == null || value.isEmpty) ? null : value;
      });
    } catch (_) {
      throw const ComposerDraftReadException();
    }
  }

  static Future<void> save({
    required String connectionId,
    required String sessionId,
    required String text,
    bool Function()? isCurrent,
  }) => _save(
    connectionId: connectionId,
    sessionId: sessionId,
    text: text,
    isCurrent: isCurrent,
  );

  static Future<void> _save({
    required String connectionId,
    required String sessionId,
    required String text,
    int? owner,
    bool Function()? isCurrent,
  }) async {
    try {
      await _serialized((prefs) async {
        if (isCurrent?.call() == false) return;
        final key = _resolve(prefs, connectionId, sessionId);
        if (owner != null && _owners[key] != owner) return;
        if (owner == null) _owners[key] = 0;
        await _write(prefs, key, text);
      });
    } catch (_) {
      // Best-effort: a failed save must never break the screen.
    }
  }

  static Future<void> _write(
    SharedPreferences prefs,
    String key,
    String text,
  ) async {
    // A clear is a deliberate value, even though the string entry is removed.
    // Without this marker, a delayed local alias migration can resurrect it.
    final marker = _writtenKey(key);
    final oldText = prefs.getString(key);
    final oldMarker = prefs.getBool(marker);
    try {
      // Whitespace may be the literal body of a recovered paste. Only an
      // explicit empty string is a clear; keep all nonempty draft bytes.
      final saved = text.isEmpty
          ? await prefs.remove(key)
          : await prefs.setString(key, text);
      if (!saved || !await prefs.setBool(marker, true)) {
        throw StateError('Composer draft write was rejected.');
      }
    } catch (_) {
      // SharedPreferences updates its cache even when the platform rejects a
      // write. Restore that cache as well as making a best-effort disk rollback.
      if (oldText == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, oldText);
      }
      if (oldMarker == null) {
        await prefs.remove(marker);
      } else {
        await prefs.setBool(marker, oldMarker);
      }
      rethrow;
    }
  }

  static String _writtenKey(String key) =>
      "$_writtenPrefix.${key.substring(_prefix.length + 1)}";

  static Future<void> _restoreValue(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    try {
      if (value == null) {
        await prefs.remove(key);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      }
    } catch (_) {
      // Continue restoring the other transaction keys if one rollback fails.
    }
  }

  /// Clear through aliases too; retain a tombstone against stale migration.
  static Future<void> remove({
    required String connectionId,
    required String sessionId,
  }) => save(connectionId: connectionId, sessionId: sessionId, text: '');

  /// Drops every draft and alias for this connection only.
  static Future<void> removeConnection(String connectionId) async {
    try {
      await _serialized((prefs) async {
        final marker = '$connectionId\u0000';
        for (final key in prefs.getKeys()) {
          final prefix = key.startsWith('$_prefix.')
              ? _prefix
              : key.startsWith('$_aliasPrefix.')
              ? _aliasPrefix
              : key.startsWith('$_writtenPrefix.')
              ? _writtenPrefix
              : null;
          if (prefix == null) continue;
          final decoded = _decode(key, prefix);
          if (decoded != null && decoded.startsWith(marker)) {
            await prefs.remove(key);
            _owners.remove(key);
          }
        }
      });
    } catch (_) {
      // Best-effort.
    }
  }

  static String? _decode(String key, String prefix) {
    final encoded = key.substring(prefix.length + 1);
    try {
      return utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    } catch (_) {
      return null;
    }
  }
}
