import 'chat_conversation_projection.dart';

/// A successful SSE response is evidence even when a subsequent history GET
/// succeeds before persistence. A newer row is not evidence of correspondence;
/// retain the local transcript until an exact authoritative response ID matches.
class RestChatReplyRetention {
  final int? admissionFloor;
  List<Map<String, dynamic>>? _completedRows;
  int? _completedReplyId;

  RestChatReplyRetention.admit(
    List<Map<String, dynamic>> history, {
    required bool historyKnown,
  }) : admissionFloor = historyKnown && history.every((row) => _id(row) != null)
           ? history.fold<int>(0, (floor, row) {
               final id = _id(row)!;
               return id > floor ? id : floor;
             })
           : null;

  static int? _id(Map<String, dynamic> row) =>
      int.tryParse(row['id']?.toString() ?? '');

  bool get hasRetainedReply => _completedRows != null;

  void complete(List<Map<String, dynamic>> rows) {
    _completedRows = List.of(rows);
    _completedReplyId = null;
    // Only this response's own durable ID can authorise handover. The current
    // SSE contract supplies no such ID, so its receipt stays route-local.
    final lastAssistant = rows.lastIndexWhere(
      (row) => row['role'] == 'assistant' || row['role'] == 'agent',
    );
    if (lastAssistant < 0) return;
    final reply = rows[lastAssistant];
    final id = _id(reply);
    if (id != null &&
        (admissionFloor == null || id > admissionFloor!) &&
        buildConversationDisplayItems(
          messages: [reply],
          received: true,
        ).isNotEmpty) {
      _completedReplyId = id;
    }
  }

  List<Map<String, dynamic>> reconcile(List<Map<String, dynamic>> canonical) {
    final retained = _completedRows;
    if (retained == null) return canonical;
    final replyId = _completedReplyId;
    if (replyId != null &&
        buildConversationDisplayItems(
          messages: canonical.where((row) => _id(row) == replyId).toList(),
        ).any((row) => row['role'] == 'assistant')) {
      _completedRows = null;
      _completedReplyId = null;
      return canonical;
    }
    // Older pages can be prepended by identity without replacing the streamed
    // tail. Unknown-floor histories are deliberately not text-deduplicated.
    final ids = retained.map(_id).whereType<int>().toList()..sort();
    return [
      if (ids.isNotEmpty)
        ...canonical.where((row) => _id(row) != null && _id(row)! < ids.first),
      ...retained,
    ];
  }
}
