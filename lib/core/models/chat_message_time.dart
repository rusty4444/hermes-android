/// Message time is either recorded by the server or observed once at ingress.
/// Never call the observation helper while hydrating history or building UI.
enum ChatMessageTimeSource { recorded, sent, received }

class ChatMessageTime {
  final DateTime at;
  final ChatMessageTimeSource source;

  const ChatMessageTime(this.at, this.source);

  static const observedAtKey = '_chat_observed_at_ms';
  static const sourceKey = '_chat_time_source';

  /// The messages API specifies Unix seconds, including fractional seconds.
  /// Do not guess units, coerce strings, or accept invalid/overflowing dates.
  static DateTime? recordedTime(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value <= 0 ||
        value > 253402300799) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  }

  static ChatMessageTime? fromRow(Map<String, dynamic> row) {
    final recorded = recordedTime(row['timestamp']);
    if (recorded != null) {
      return ChatMessageTime(recorded, ChatMessageTimeSource.recorded);
    }
    final ms = row[observedAtKey];
    final source = switch (row[sourceKey]) {
      'sent' => ChatMessageTimeSource.sent,
      'received' => ChatMessageTimeSource.received,
      _ => null,
    };
    if (ms is! int || source == null) return null;
    final at = recordedTime(ms / 1000);
    return at == null ? null : ChatMessageTime(at, source);
  }

  /// Capture at the live send/body-receipt boundary, never on fetch/replay.
  /// Duplicate updates retain the first observation; a recorded time wins.
  static void observe(
    Map<String, dynamic> row, {
    required ChatMessageTimeSource source,
    DateTime? at,
    Object? serverTimestamp,
  }) {
    assert(source != ChatMessageTimeSource.recorded);
    if (recordedTime(row['timestamp']) == null &&
        recordedTime(serverTimestamp) != null) {
      row['timestamp'] = serverTimestamp;
    }
    if (fromRow(row) != null) return;
    row[observedAtKey] = (at ?? DateTime.now()).millisecondsSinceEpoch;
    row[sourceKey] = source.name;
  }
}
