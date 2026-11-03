import '../utils/chat_conversation_projection.dart';

/// Positive, whole-turn persistence evidence from an owned message.complete.
///
/// These are exact committed row addresses, not an admission floor or a match
/// inferred from prose. Partial receipts cannot retire a received turn.
class NormalGatewayPersistedTurn {
  NormalGatewayPersistedTurn._({
    required List<int> rowIds,
    required this.userRowId,
    required this.finalAssistantRowId,
  }) : rowIds = List<int>.unmodifiable(rowIds);

  // Receipt metadata is volatile and shares the retained presentation's bounds.
  static const maxRowIds = 4096;

  final List<int> rowIds;
  final int userRowId;
  final int finalAssistantRowId;

  static NormalGatewayPersistedTurn? fromWire(Object? value) {
    if (value is! Map || value['complete'] != true) return null;
    final ids = value['row_ids'];
    final user = value['user_row_id'];
    final assistant = value['final_assistant_row_id'];
    if (ids is! List ||
        ids.length < 2 ||
        ids.length > maxRowIds ||
        user is! int ||
        user <= 0 ||
        assistant is! int ||
        assistant <= 0) {
      return null;
    }
    final rows = <int>[];
    var previous = 0;
    for (final id in ids) {
      // Never coerce strings/doubles, repair order, or discard bad addresses.
      if (id is! int || id <= previous) return null;
      rows.add(id);
      previous = id;
    }
    if (rows.first != user || rows.last != assistant) return null;
    final users = value['user_row_ids'];
    if (users != null &&
        (users is! List ||
            users.length != 1 ||
            users.single is! int ||
            users.single != user)) {
      return null;
    }
    final submission = value['submission_id'];
    if (submission != null &&
        (submission is! String ||
            submission.isEmpty ||
            submission.length > 256 ||
            submission.trim() != submission ||
            submission.codeUnits.any(
              (unit) => unit < 32 || unit >= 127 && unit <= 159,
            ))) {
      return null;
    }
    return NormalGatewayPersistedTurn._(
      rowIds: rows,
      userRowId: user,
      finalAssistantRowId: assistant,
    );
  }

  /// Require every addressed row in one accepted physical history observation.
  /// A present final alone cannot prove that its tools/interims are available.
  bool isConfirmedBy(List<Map<String, dynamic>> rows) {
    final addressed = rowIds.toSet();
    final found = <int, Map<String, dynamic>>{};
    final ordered = <int>[];
    for (final row in rows) {
      final id = row['id'];
      if (id is! int || !addressed.contains(id)) continue;
      if (found.containsKey(id)) return false;
      found[id] = row;
      ordered.add(id);
    }
    if (ordered.length != rowIds.length) return false;
    for (var i = 0; i < rowIds.length; i++) {
      if (ordered[i] != rowIds[i]) return false;
    }
    if (found[userRowId]!['role'] != 'user' ||
        found.values.where((row) => row['role'] == 'user').length != 1) {
      return false;
    }
    // The saved source must independently expose a successful final response.
    // Matching IDs never promote a partial, hidden, tool or metadata-free row.
    final finalItems = buildConversationDisplayItems(
      messages: [found[finalAssistantRowId]!],
    );
    return finalItems.length == 1 && finalItems.single['role'] == 'assistant';
  }
}
