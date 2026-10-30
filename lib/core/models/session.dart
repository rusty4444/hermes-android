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
  });

  /// Cron sessions created by the server-side wake-gate skip path have no
  /// title and no messages. They clutter the session list, so the app hides
  /// them unless the user explicitly opts into seeing every source.
  bool get isUntitledCronShell =>
      source == 'cron' &&
      messageCount == 0 &&
      (title.isEmpty || title == 'Untitled');

  factory Session.fromJson(Map<String, dynamic> json) {
    final endedAt = json['ended_at'];
    final startedAt = (json['started_at'] ?? 0).toDouble();
    final lastActive = (json['last_active'] ?? startedAt).toDouble();
    return Session(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      model: json['model'] ?? 'Default',
      source: json['source'] ?? '',
      messageCount: json['message_count'] ?? 0,
      isActive: endedAt == null,
      preview: json['preview'] ?? '',
      startedAt: startedAt,
      endedAt: endedAt?.toDouble(),
      lastActive: lastActive,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
    );
  }
}
