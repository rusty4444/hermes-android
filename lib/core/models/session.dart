/// How recently a session must have been touched to count as live when the
/// Gateway does not report `is_active` itself.
///
/// Mirrors the Hermes dashboard's session-liveness window (`_ACTIVE_WINDOW_S`
/// in its sessions router): an un-ended session whose `last_active` is older
/// than this is idle, not running. While a turn is in flight the agent stamps
/// `last_active` at least once a minute, so the window cannot miss live work.
const double kSessionActiveWindowSeconds = 300;

/// Session model matching the Gateway API Server response format.
class Session {
  final String id;
  final String title;
  final String model;
  final String source;
  final int messageCount;
  final bool isActive;
  final String preview;
  final double startedAt;
  final double? endedAt;

  /// Most recent activity, in seconds since the epoch.
  ///
  /// The Gateway sends `last_active`; older gateways may not, so the parser
  /// falls back to [startedAt]. Every date grouping and "Recent" filter in
  /// the Chats browser ranks by this value.
  final double lastActive;

  /// Whether the user pinned the chat server-side.
  final bool pinned;

  /// Whether the Gateway archived the session.
  final bool archived;

  /// Whether this session exists only as a client-side draft.
  ///
  /// Recovery v2 may call `session.open`, so it is safe only before the first
  /// server session exists. Sessions parsed from the Gateway always keep this
  /// false and must use the exact-session legacy submit transport.
  final bool isLocalDraft;

  const Session({
    required this.id,
    required this.title,
    required this.model,
    required this.source,
    required this.messageCount,
    required this.isActive,
    required this.preview,
    required this.startedAt,
    this.endedAt,
    this.lastActive = 0,
    this.pinned = false,
    this.archived = false,
    this.isLocalDraft = false,
  });

  /// Parses one session row.
  ///
  /// Set [ignoreIsActive] when the payload's `is_active` is a fixed
  /// placeholder rather than a liveness signal — the Projects RPC hardcodes
  /// `is_active: false` on every row (`_project_tree_row` in the gateway's
  /// `methods_projects`), so project rows must fall back to the recency
  /// window instead of rendering every fresh chat as Done.
  factory Session.fromJson(
    Map<String, dynamic> json, {
    bool ignoreIsActive = false,
  }) {
    // Type-tolerant readers: one row with a string-typed number must not
    // take down the whole session list with a TypeError mid-map.
    double asDouble(Object? value, [double fallback = 0]) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    int asInt(Object? value, [int fallback = 0]) {
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    final endedAt = json['ended_at'];
    final startedAt = asDouble(json['started_at']);
    final lastActive = asDouble(json['last_active'], startedAt);
    // The Gateway reports session liveness via `is_active`. `ended_at` is
    // only set for explicitly ended sessions, so it is NOT a liveness
    // signal on its own — using it alone marks every finished-but-not-ended
    // session as running. When `is_active` is absent (the current Gateway
    // API does not send it), mirror the Hermes dashboard's definition of an
    // active session: not ended, and touched within
    // [kSessionActiveWindowSeconds]. Payloads whose `is_active` is a fixed
    // placeholder (Projects RPC rows) pass [ignoreIsActive] and always take
    // the recency path.
    final isActiveJson = json['is_active'];
    return Session(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      model: json['model'] ?? 'Default',
      source: json['source'] ?? '',
      messageCount: asInt(json['message_count']),
      isActive: !ignoreIsActive && isActiveJson is bool
          ? isActiveJson
          : (endedAt == null &&
              (DateTime.now().millisecondsSinceEpoch / 1000.0 - lastActive) <
                  kSessionActiveWindowSeconds),
      preview: json['preview'] ?? '',
      startedAt: startedAt,
      endedAt: endedAt == null ? null : asDouble(endedAt),
      lastActive: lastActive,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
      isLocalDraft: false,
    );
  }
}
