// Which chats have progress the user hasn't seen, as in Kyllene's SeenStore:
// the gateway's shared read watermark (`last_read_at` / `unread`) when it keeps
// one, else when this phone last looked at each chat. Kept per connection.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/session.dart';

/// Timestamps from the gateway and this phone's clock round differently.
const double _slackSeconds = 1.0;

/// Sources held in the gateway's own clients (Hermes Desktop's local ids).
const _localSources = {
  'acp',
  'cli',
  'codex',
  'desktop',
  'gateway',
  'kanban',
  'local',
  'oneshot',
  'tui',
};

/// Runs the machine starts itself (cron jobs, subagents...).
const _machineSources = {
  'acp',
  'cron',
  'kanban',
  'oneshot',
  'subagent',
  'tool',
};

/// A chat from a messaging platform or bridge (Telegram, Discord...), read
/// where it came in, so its activity alone doesn't make it unread here.
bool ngIsExternalSource(String source) {
  final id = source.trim().toLowerCase();
  return id.isNotEmpty &&
      id != 'unknown' &&
      !_localSources.contains(id) &&
      !_machineSources.contains(id);
}

double _nowSeconds() => DateTime.now().millisecondsSinceEpoch / 1000.0;

class NgSeenChats {
  NgSeenChats({
    required this.since,
    Map<String, double>? chats,
    Set<String>? leftRunning,
    Set<String>? markedUnread,
  }) : chats = chats ?? {},
       leftRunning = leftRunning ?? {},
       markedUnread = markedUnread ?? {};

  /// When tracking began: anything older counts as read.
  final double since;

  /// When the user last looked at each chat on this phone (epoch seconds).
  final Map<String, double> chats;

  /// Chats left on this phone while a turn still ran, until looked at again.
  final Set<String> leftRunning;

  /// Chats the user marked unread here, until they look at them again.
  final Set<String> markedUnread;

  double lastLook(String id) => chats[id] ?? since;

  /// The gateway's watermark wins over a local look when it keeps one; with
  /// none, activity after the last look here counts as new.
  bool isUnread(Session s) {
    if (markedUnread.contains(s.id)) return true;
    final activity = s.lastActive > 0 ? s.lastActive : s.startedAt;
    final shared = s.lastReadAt;
    if (shared != null && shared.isFinite && shared >= 0) {
      final looked = chats[s.id];
      // A read here outranks the watermark until the gateway catches up;
      // zero is an explicit mark-unread no earlier look outranks.
      if (shared > 0 && looked != null && activity <= looked + _slackSeconds) {
        return false;
      }
      return s.unread || activity > shared;
    }
    if (s.unread) return true;
    if (activity <= 0 || activity <= lastLook(s.id) + _slackSeconds) {
      return false;
    }
    return !ngIsExternalSource(s.source) || leftRunning.contains(s.id);
  }

  Map<String, dynamic> toJson() => {
    'since': since,
    'chats': chats,
    'left_running': leftRunning.toList(),
    'marked_unread': markedUnread.toList(),
  };

  static NgSeenChats fromJson(Object? json) {
    if (json is! Map) return NgSeenChats(since: _nowSeconds());
    final chats = <String, double>{};
    final raw = json['chats'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) chats['$k'] = v.toDouble();
      });
    }
    final since = json['since'];
    return NgSeenChats(
      since: since is num ? since.toDouble() : _nowSeconds(),
      chats: chats,
      leftRunning: {
        if (json['left_running'] is List)
          for (final id in json['left_running'] as List) '$id',
      },
      markedUnread: {
        if (json['marked_unread'] is List)
          for (final id in json['marked_unread'] as List) '$id',
      },
    );
  }
}

/// Loads and saves [NgSeenChats] for one connection.
class NgSeenStore {
  NgSeenStore(this.prefs, this.connectionId)
    : chats = _load(prefs, connectionId);

  final SharedPreferences prefs;
  final String connectionId;
  final NgSeenChats chats;

  static const _maxChats = 400;

  static String _key(String id) => 'nextgen.seen_chats.$id';

  static NgSeenChats _load(SharedPreferences prefs, String id) {
    final raw = prefs.getString(_key(id));
    if (raw == null) {
      final fresh = NgSeenChats(since: _nowSeconds());
      prefs.setString(_key(id), jsonEncode(fresh.toJson()));
      return fresh;
    }
    try {
      return NgSeenChats.fromJson(jsonDecode(raw));
    } catch (_) {
      return NgSeenChats(since: _nowSeconds());
    }
  }

  /// Records that [id] was on screen with everything up to [at] in it, and
  /// whether a turn still ran there. Never moves a look back.
  void markLooked(String id, double at, {bool running = false}) {
    final before = chats.chats[id];
    if (before == null || at > before) chats.chats[id] = at;
    chats.markedUnread.remove(id);
    if (running) {
      chats.leftRunning.add(id);
    } else {
      chats.leftRunning.remove(id);
    }
    _trim();
    _save();
  }

  /// Marks [id] unread again on this phone.
  void markUnread(String id) {
    chats.markedUnread.add(id);
    _save();
  }

  void _trim() {
    if (chats.chats.length <= _maxChats) return;
    final oldest = chats.chats.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final e in oldest.take(chats.chats.length - _maxChats)) {
      chats.chats.remove(e.key);
    }
  }

  void _save() {
    prefs.setString(_key(connectionId), jsonEncode(chats.toJson()));
  }
}
