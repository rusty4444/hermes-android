import '../models/background_report.dart';
import '../models/chat_timeline.dart';
import 'android_prompt_context.dart';
import 'generated_media.dart';
import 'message_content.dart';

/// A response receipt is different from lifecycle settlement or an idle socket.
/// Missing status is valid on stock message.complete; explicit uncertainty is not.
bool isSuccessfulResponseReceipt(Map<String, dynamic> data) {
  if (data['partial'] == true ||
      data['failed'] == true ||
      data['completed'] == false ||
      data['success'] == false ||
      (data['error'] != null && data['error'].toString().trim().isNotEmpty)) {
    return false;
  }
  final status = data['status']?.toString().toLowerCase();
  if (status != null &&
      !const {
        'completed',
        'complete',
        'done',
        'success',
        'succeeded',
      }.contains(status)) {
    return false;
  }
  final finish = data['finish_reason'];
  return finish == null || const {'stop', 'end_turn'}.contains(finish);
}

/// Saved prose has no implicit completion receipt. In particular, its position,
/// durable row ID and a later idle/successful turn do not prove it finished.
/// Received scopes require their own selected response marker instead of
/// borrowing completion from either lifecycle or the canonical source.
bool _hasFinalResponseEvidence(Map<String, dynamic> row, bool received) {
  if (!isSuccessfulResponseReceipt(row)) return false;
  if (row['_chat_response_complete'] == true) return true;
  if (received) return false;
  return row['completed'] == true ||
      row['success'] == true ||
      row['status'] != null ||
      const {'stop', 'end_turn'}.contains(row['finish_reason']);
}

/// Timestamp footers follow the same positive completion evidence as quiet chat.
bool isCompletedChatResponse(Map<String, dynamic> row) =>
    row['_gateway_pending_response'] != true &&
    row['_gateway_interim'] != true &&
    row['interim'] != true &&
    row['is_interim'] != true &&
    row['_chat_response_complete'] != false &&
    _hasFinalResponseEvidence(row, false);

/// Quiet chat is a conversation, not a trace. Do not change ingress or the raw
/// request history when hiding details. Canonical and received sources are
/// projected independently; no body/text matching associates the two sources.
List<Map<String, dynamic>> buildConversationDisplayItems({
  required List<Map<String, dynamic>> messages,
  ChatTimeline? timeline,
  bool received = false,
}) {
  final items = <Map<String, dynamic>>[];
  String? prompt;
  for (final row in messages) {
    if (!isPublicDeliveryMessage(row) ||
        BackgroundReport.fromMessage(row) != null ||
        isToolResultMessage({...row, 'content': publicDeliveryText(row)})) {
      continue;
    }
    final role = row['role'] == 'agent' ? 'assistant' : row['role'];
    if (role != 'user' && role != 'assistant') continue;
    var content = stripToolResultText(
      messageContentToText(
        AndroidPromptContext.displayContent(row, publicDeliveryContent(row)),
      ),
    );
    if (role == 'user') {
      if (content.isNotEmpty) {
        prompt = content;
        items.add({...row, '_display_content': content});
      }
      continue;
    }
    final calls = row['tool_calls'];
    final hasCalls = calls is List
        ? calls.isNotEmpty
        : calls != null && calls != '[]';
    if (hasCalls ||
        row['function_call'] != null ||
        row['tool_call_id'] != null ||
        row['toolCallId'] != null ||
        row['finish_reason'] == 'tool_calls') {
      continue;
    }
    if (row['_gateway_interim'] == true ||
        row['interim'] == true ||
        row['is_interim'] == true ||
        row['_gateway_pending_response'] == true ||
        row['_chat_response_complete'] == false ||
        !_hasFinalResponseEvidence(row, received)) {
      continue;
    }
    final scope = row['_normal_projection_id'] ?? row;
    if (!row.containsKey('display_content') &&
        timeline?.scopes.contains(scope) == true) {
      // Respect receipt retention, including scopes whose entire body was
      // evicted. Never resurrect their unbounded canonical accumulator.
      content = timeline!.runs
          .where(
            (run) => run.scope == scope && run.kind == ChatTimelineKind.text,
          )
          .map((run) => run.text)
          .join();
    }
    if (content.trim().isEmpty) continue;
    // Preserve source-local selected responses in source order. Neither another
    // assistant row nor a subsequent tool can invent or erase their receipts.
    items.add({
      ...row,
      'role': 'assistant',
      '_display_content': content,
      '_retry_prompt': ?prompt,
    });
  }
  return items;
}
