/// The Quick chat lifecycle store.
///
/// Phase 1 of `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` validates Quick chat as a
/// creation mode that "auto-archives after 72 hours, never silently deletes"
/// and "can be promoted into a normal Project conversation at any time".
/// `buildNewChatDraft` already *computes* that deadline, but nothing kept it:
/// the draft was carried into a chat screen and forgotten, so no Quick chat
/// ever archived. This store is the missing persistence.
///
/// It is deliberately device-local and needs **no gateway contract**. The
/// gateway exposes no way to bind a session to a project or to mark one
/// ephemeral, so a legacy REST-only connection keeps working exactly as
/// before — an unrecorded chat is simply durable.
///
/// Four rules are encoded here rather than in a widget, so they can be
/// asserted without pumping a frame:
///
/// 1. **Archived is a state, never a deletion.** Passing the deadline changes
///    what [QuickChatState.statusFor] reports; the record survives, so the
///    chat stays searchable in Archived exactly as the roadmap requires.
/// 2. **The clock starts once.** Re-recording an existing Quick chat keeps its
///    original deadline, so reopening one cannot keep it alive forever.
/// 3. **Promotion is terminal.** Once the user keeps a chat, a replayed draft
///    can never put it back on an archive timer.
/// 4. **Never archive on a guess.** A record whose deadline cannot be read is
///    dropped rather than treated as expired.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where a chat sits in the Quick chat lifecycle. `null` from
/// [QuickChatState.statusFor] means the chat was never a Quick chat.
enum QuickChatStatus {
  /// Quick, and still inside its retention window.
  active,

  /// Quick, past its deadline, and eligible for the Archived view.
  archived,

  /// Deliberately kept by the user: durable, with no deadline.
  promoted,
}

/// An immutable snapshot of the Quick chat records for one connection.
class QuickChatState {
  /// Session id to the moment it becomes eligible for auto-archive.
  final Map<String, DateTime> expiries;

  /// Session ids the user promoted to durable work.
  final Set<String> promoted;

  const QuickChatState({required this.expiries, required this.promoted});

  static const QuickChatState empty = QuickChatState(
    expiries: <String, DateTime>{},
    promoted: <String>{},
  );

  /// Whether this chat is still on a Quick chat timer.
  bool isQuick(String sessionId) =>
      expiries.containsKey(sessionId) && !promoted.contains(sessionId);

  /// When this chat archives itself, or null when it is not on a timer.
  DateTime? expiresAtFor(String sessionId) =>
      promoted.contains(sessionId) ? null : expiries[sessionId];

  /// This chat's lifecycle state at [now], or null when it was never Quick.
  QuickChatStatus? statusFor(String sessionId, DateTime now) {
    if (promoted.contains(sessionId)) return QuickChatStatus.promoted;
    final expiresAt = expiries[sessionId];
    if (expiresAt == null) return null;
    // The deadline itself has not passed yet.
    return now.isAfter(expiresAt)
        ? QuickChatStatus.archived
        : QuickChatStatus.active;
  }

  /// Every Quick chat that has reached its deadline by [now].
  Set<String> archivedAt(DateTime now) {
    return {
      for (final entry in expiries.entries)
        if (!promoted.contains(entry.key) && now.isAfter(entry.value))
          entry.key,
    };
  }
}

class QuickChatStore {
  static final _reloadRequired = Expando<bool>();
  final SharedPreferences _preferences;
  final String connectionId;

  QuickChatStore(this._preferences, {required this.connectionId});

  String get _key => 'quick_chats_v1_$connectionId';

  Future<void> _repairCache() async {
    if (_reloadRequired[_preferences] != true) return;
    await _preferences.reload();
    _reloadRequired[_preferences] = false;
  }

  Future<QuickChatState> load() async {
    await _repairCache();
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return QuickChatState.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException();
      final rawExpiries = decoded['expiries'];
      final rawPromoted = decoded['promoted'];
      if (rawExpiries is! Map || rawPromoted is! List) {
        throw const FormatException();
      }

      final expiries = <String, DateTime>{};
      for (final entry in rawExpiries.entries) {
        final id = entry.key;
        final millis = entry.value;
        // An unreadable deadline is dropped: archiving on a guess would hide
        // work the user never agreed to make ephemeral.
        if (id is! String || id.isEmpty || millis is! int) continue;
        expiries[id] = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      }

      final promoted = <String>{
        for (final id in rawPromoted)
          if (id is String && id.isNotEmpty) id,
      };

      return QuickChatState(
        expiries: Map.unmodifiable(expiries),
        promoted: Set.unmodifiable(promoted),
      );
    } catch (_) {
      return QuickChatState.empty;
    }
  }

  /// Marks a chat as Quick, starting its retention clock.
  ///
  /// Idempotent by design: an existing record keeps its original deadline, and
  /// a promoted chat is never demoted back onto a timer.
  Future<void> record(String sessionId, {required DateTime expiresAt}) async {
    final id = _requireId(sessionId);
    final state = await load();
    if (state.promoted.contains(id)) return;
    if (state.expiries.containsKey(id)) return;
    await _save(
      QuickChatState(
        expiries: {...state.expiries, id: expiresAt},
        promoted: state.promoted,
      ),
    );
  }

  /// Keeps a Quick chat for good. A chat that was never Quick is untouched.
  Future<void> promote(String sessionId) async {
    final id = _requireId(sessionId);
    final state = await load();
    if (!state.expiries.containsKey(id)) return;
    if (state.promoted.contains(id)) return;
    await _save(
      QuickChatState(
        expiries: state.expiries,
        promoted: {...state.promoted, id},
      ),
    );
  }

  /// Forgets records for chats the gateway no longer lists.
  ///
  /// Absence alone is not enough to forget a record. A Quick chat created
  /// seconds ago has not appeared in the gateway's session list yet — it
  /// becomes one on its first turn — so dropping it here would silently make
  /// it durable. Only a record whose deadline has already passed at [now] may
  /// be pruned on absence.
  Future<void> prune(
    Set<String> liveSessionIds, {
    required DateTime now,
  }) async {
    final state = await load();
    bool keep(String id) {
      if (liveSessionIds.contains(id)) return true;
      final expiresAt = state.expiries[id];
      // A promoted record has no deadline of its own; it is kept until its
      // chat is gone, exactly like a live one.
      if (expiresAt == null) return false;
      return !now.isAfter(expiresAt);
    }

    final expiries = <String, DateTime>{
      for (final entry in state.expiries.entries)
        if (keep(entry.key)) entry.key: entry.value,
    };
    final promoted = <String>{
      for (final id in state.promoted)
        if (keep(id)) id,
    };
    if (expiries.length == state.expiries.length &&
        promoted.length == state.promoted.length) {
      return;
    }
    await _save(QuickChatState(expiries: expiries, promoted: promoted));
  }

  String _requireId(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must not be blank');
    }
    return id;
  }

  Future<void> _save(QuickChatState state) async {
    try {
      final saved = await _preferences.setString(
        _key,
        jsonEncode({
          'expiries': {
            for (final entry in state.expiries.entries)
              entry.key: entry.value.millisecondsSinceEpoch,
          },
          'promoted': state.promoted.toList(),
        }),
      );
      if (!saved) throw StateError('Could not persist Quick Chat retention.');
    } catch (_) {
      // setString updates the process cache even when the physical write fails.
      // Reload before a retry can mistake a phantom promotion for durability.
      _reloadRequired[_preferences] = true;
      await _repairCache();
      rethrow;
    }
  }
}
