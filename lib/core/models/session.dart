/// Session model for Hermes dashboard sessions.
class Session {
  final String id;
  final String title;
  final String model;
  final int messageCount;
  final bool isActive;
  final String preview;
  final String createdAt;

  const Session({
    required this.id,
    required this.title,
    required this.model,
    required this.messageCount,
    required this.isActive,
    required this.preview,
    required this.createdAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      model: json['model'] ?? 'Default',
      messageCount: json['message_count'] ?? 0,
      isActive: json['is_active'] ?? false,
      preview: json['preview'] ?? 'Tap to view session...',
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'model': model,
      'message_count': messageCount,
      'is_active': isActive,
      'preview': preview,
      'created_at': createdAt,
    };
  }
}
