import '../models/chat_timeline.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_insight.dart';
import 'message_content.dart';

/// Assistant reasoning rendered as its own collapsible item in the chat list.
class ChatReasoningItem {
  final String text;
  final bool initiallyExpanded;
  final String? id;

  const ChatReasoningItem(this.text, this.initiallyExpanded, {this.id});
}

/// Consecutive tool activities rendered as a single activity card.
///
/// [id] names the group rather than the slot it happens to occupy, and the
/// first activity retains it across merges — including while the group is still
/// growing. Callers can therefore hang per-group UI state (a
/// card the user collapsed) off it and keep it across list reordering and
/// lazy-list eviction, which a position-bound widget State cannot do.
class ChatToolActivityGroup {
  const ChatToolActivityGroup({required this.id, required this.activities});

  final String id;
  final List<GatewayToolActivity> activities;

  /// The most recent timestamp we can substantiate, not a guessed time for
  /// unobserved calls or for an older result without a server timestamp.
  GatewayToolActivity? get latestKnownActivity =>
      latestKnownToolActivity(activities);
}

/// Project a raw Hermes message list into the heterogeneous list the chat
/// screen renders.
///
/// The result mixes four item kinds, in the order the conversation produced
/// them:
///
/// - `Map<String, dynamic>` — a user or assistant bubble, carrying
///   `_display_content` (tool-result blocks stripped) and, for assistant
///   replies, `_retry_prompt` with the user prompt that caused it;
/// - [ChatToolActivityGroup] — consecutive tool results collapsed into one
///   activity card;
/// - [ChatReasoningItem] — exposed reasoning at its receipt position (or before
///   the bubble when only a legacy snapshot exists);
/// - `GatewaySubagentActivity` list and [GatewayNotice] — appended last.
///
/// When supplied, [timeline] projects actual live receipt chronology without
/// adding synthetic rows to request history. Otherwise durable tool IDs match
/// [toolActivities], with positional fallback only for rows without call IDs.
/// Unmatched activities retain the legacy trailing card: snapshots/recovery-v2
/// do not provide enough evidence to invent chronology. Inputs are not mutated.
List<dynamic> buildChatDisplayItems({
  required List<Map<String, dynamic>> messages,
  List<GatewayToolActivity> toolActivities = const [],
  List<GatewaySubagentActivity> subagentActivities = const [],
  List<GatewayNotice> notices = const [],
  bool verbose = false,
  ChatTimeline? timeline,
}) {
  final toolQueue = List<GatewayToolActivity>.from(toolActivities);
  // A turn can contain several canonical interim rows. Project their receipt
  // runs together at the first live anchor so consuming an earlier preview
  // cannot pull later tools/reasoning ahead of intervening commentary.
  final scopeTurns = <Object, int>{};
  final scopeRows = <Object, Map<String, dynamic>>{};
  Object scopeFor(Map<String, dynamic> row) =>
      row['_normal_projection_id'] ?? row;
  var turn = 0;
  for (final message in messages) {
    if (message['role'] == 'user') turn++;
    final scope = scopeFor(message);
    scopeTurns[scope] = turn;
    scopeRows[scope] = message;
  }
  final liveRuns =
      timeline?.runs.where((r) => scopeTurns.containsKey(r.scope)).toList() ??
      const <ChatTimelineRun>[];
  final liveScopes = liveRuns.map((r) => r.scope).toSet();
  final anchors = <int, Object>{};
  for (final message in messages) {
    final scope = scopeFor(message);
    if (liveScopes.contains(scope)) {
      anchors.putIfAbsent(scopeTurns[scope]!, () => scope);
    }
  }
  final anchoredRuns = <Object, List<ChatTimelineRun>>{};
  for (final run in liveRuns) {
    (anchoredRuns[anchors[scopeTurns[run.scope]]!] ??= []).add(run);
  }
  // A live reference owns its place in the receipt projection, not the
  // fallback's unmatched trailing strip. Never render the same tool twice.
  final liveTools = liveRuns
      .where((r) => r.kind == ChatTimelineKind.tool)
      .map((r) => r.activity!)
      .toList();
  toolQueue.removeWhere(
    (activity) => liveTools.any(
      (live) =>
          live.identity == activity.identity ||
          live.toolId != null && live.toolId == activity.toolId,
    ),
  );
  final displayItems = <dynamic>[];
  final currentGroup = <GatewayToolActivity>[];
  String? currentGroupId;
  String? lastUserPrompt;

  void flushToolGroup() {
    if (currentGroup.isEmpty) return;
    displayItems.add(
      ChatToolActivityGroup(
        id: currentGroupId ?? currentGroup.first.identity,
        activities: currentGroup.toList(),
      ),
    );
    currentGroup.clear();
    currentGroupId = null;
  }

  for (final msg in messages) {
    final rawRole = (msg['role'] as String?) ?? 'assistant';
    final role = rawRole == 'agent' ? 'assistant' : rawRole;
    if (isToolResultMessage(msg)) {
      final callId = msg['tool_call_id'] ?? msg['toolCallId'];
      final match = callId == null || callId == ''
          ? (toolQueue.isEmpty ? -1 : 0)
          : toolQueue.indexWhere((activity) => activity.toolId == callId);
      if (match >= 0) {
        final activity = toolQueue.removeAt(match);
        if (currentGroup.isEmpty) {
          // A stored row's id survives latest-history window shifts. If
          // neither the activity nor the row has an id, its local identity
          // is intentionally not shared with another same-name run.
          final rowId = msg['id'] ?? msg['message_id'];
          currentGroupId = rowId is num || rowId is String && rowId.isNotEmpty
              ? 'message:$rowId'
              : activity.identity;
        }
        currentGroup.add(activity);
      }
      continue;
    }
    if (role != 'user' && role != 'assistant') continue;

    final scope = scopeFor(msg);
    if (liveScopes.contains(scope) && !anchoredRuns.containsKey(scope)) {
      continue;
    }
    final runs = anchoredRuns[scope] ?? const <ChatTimelineRun>[];
    if (role == 'assistant' && runs.isNotEmpty) {
      for (final run in runs) {
        if (run.kind == ChatTimelineKind.tool) {
          currentGroupId ??= run.activity!.identity;
          currentGroup.add(run.activity!);
          continue;
        }
        flushToolGroup();
        if (run.kind == ChatTimelineKind.reasoning) {
          displayItems.add(ChatReasoningItem(run.text, verbose, id: run.id));
        } else if (run.text.isNotEmpty) {
          displayItems.add({
            ...scopeRows[run.scope]!,
            'role': role,
            '_timeline_id': run.id,
            '_display_content': run.text,
            '_retry_prompt': ?lastUserPrompt,
          });
        }
      }
      continue;
    }

    final content = stripToolResultText(messageContentToText(msg['content']));
    final reasoning = msg['_gateway_reasoning']?.toString() ?? '';
    final hasReasoning = role == 'assistant' && reasoning.trim().isNotEmpty;
    if (content.isEmpty && !hasReasoning) continue;

    flushToolGroup();

    if (hasReasoning) {
      displayItems.add(
        ChatReasoningItem(
          reasoning,
          // Only the app's explicit verbose setting opens reasoning by
          // default. Gateway metadata must not reopen it on updates/reentry.
          verbose,
          id: 'reasoning:${msg['id'] ?? msg['message_id'] ?? identityHashCode(msg)}',
        ),
      );
    }
    if (content.isNotEmpty) {
      if (role == 'user') lastUserPrompt = content;
      displayItems.add({
        ...msg,
        'role': role,
        '_display_content': content,
        if (role == 'assistant' && lastUserPrompt != null)
          '_retry_prompt': lastUserPrompt,
      });
    }
  }
  flushToolGroup();

  // Tools from gateway events that arrived during streaming but were never
  // matched to a stored message — show them as a trailing card.
  if (toolQueue.isNotEmpty) {
    displayItems.add(
      ChatToolActivityGroup(
        id: toolQueue.first.identity,
        activities: toolQueue.toList(),
      ),
    );
  }
  if (subagentActivities.isNotEmpty) {
    displayItems.add(List<GatewaySubagentActivity>.from(subagentActivities));
  }
  displayItems.addAll(notices);

  return displayItems;
}
