import 'dart:convert';

import '../models/background_report.dart';
import '../models/chat_timeline.dart';
import '../models/received_scope_outcome.dart';
import '../models/gateway_activity.dart';
import '../models/gateway_insight.dart';
import 'android_prompt_context.dart';
import 'delivered_files.dart';
import 'generated_media.dart';
import 'media_tags.dart';
import 'message_content.dart';
import 'chat_conversation_projection.dart';

/// UI provenance only. These sections never enter history, wire payloads or WAL.
enum ChatDisplaySource { canonical, received, auxiliary }

class ChatDisplaySection {
  ChatDisplaySection({
    required this.source,
    required List<dynamic> items,
    Map<Object, ReceivedScopeOutcome> outcomes = const {},
  }) : items = List<dynamic>.unmodifiable(items),
       outcomes = Map.unmodifiable(outcomes);

  final ChatDisplaySource source;
  final List<dynamic> items;
  final Map<Object, ReceivedScopeOutcome> outcomes;

  ChatDisplaySection withReceivedOutcomes(
    ChatTimeline timeline,
    List<ReceivedScopeOutcome> facts,
  ) => ChatDisplaySection(
    source: source,
    items: items,
    outcomes: _receivedOutcomeAnchors(items, timeline, facts),
  );
}

/// Two independent source-local projections, not a cross-channel chronology.
List<ChatDisplaySection> buildNormalChatDisplaySections({
  required List<Map<String, dynamic>> canonicalRows,
  required List<Map<String, dynamic>> receivedRows,
  List<GatewayToolActivity> canonicalTools = const [],
  List<GatewayToolActivity> receivedTools = const [],
  required ChatTimeline receivedTimeline,
  List<ReceivedScopeOutcome> receivedOutcomes = const [],
  List<GatewaySubagentActivity> subagentActivities = const [],
  List<GatewayNotice> notices = const [],
  bool verbose = false,
  bool conversationOnly = false,
}) => List<ChatDisplaySection>.unmodifiable([
  for (final section in [
    ChatDisplaySection(
      source: ChatDisplaySource.canonical,
      items: conversationOnly
          ? buildConversationAttachmentItems(messages: canonicalRows)
          : buildChatDisplayItems(
              messages: canonicalRows,
              toolActivities: canonicalTools,
              verbose: verbose,
            ),
    ),
    ChatDisplaySection(
      source: ChatDisplaySource.received,
      items: conversationOnly
          ? buildConversationAttachmentItems(
              messages: receivedRows,
              toolActivities: receivedTools,
              timeline: receivedTimeline,
              received: true,
            )
          : buildChatDisplayItems(
              messages: receivedRows,
              toolActivities: receivedTools,
              timeline: receivedTimeline,
              verbose: verbose,
            ),
    ).withReceivedOutcomes(receivedTimeline, receivedOutcomes),
    ChatDisplaySection(
      source: ChatDisplaySource.auxiliary,
      items: [
        if (!conversationOnly && subagentActivities.isNotEmpty)
          List<GatewaySubagentActivity>.unmodifiable(subagentActivities),
        if (!conversationOnly) ...notices,
      ],
    ),
  ])
    if (section.items.isNotEmpty) section,
]);

Map<Object, ReceivedScopeOutcome> _receivedOutcomeAnchors(
  List<dynamic> items,
  ChatTimeline timeline,
  List<ReceivedScopeOutcome> outcomes,
) {
  final runScopes = {for (final run in timeline.runs) run.id: run.scope};
  // Imported reducers can reuse public tool IDs. The projected card contains
  // these exact activity objects; sibling string IDs are not scope authority.
  final toolScopes = Map<GatewayToolActivity, Object>.identity();
  for (final run in timeline.runs) {
    if (run.activity != null) toolScopes[run.activity!] = run.scope;
  }
  final emitted = <String>{};
  return {
    for (final item in items)
      for (final fact in outcomes)
        if (!emitted.contains(fact.id) &&
            (item is Map<String, dynamic> &&
                    fact.scopes.contains(item['_normal_projection_id']) ||
                item is ChatReasoningItem &&
                    fact.scopes.contains(runScopes[item.id]) ||
                item is ChatAttachmentItem &&
                    fact.scopes.contains(
                      item.scope ?? toolScopes[item.activity],
                    ) ||
                item is ChatToolActivityGroup &&
                    item.activities.any(
                      (tool) => fact.scopes.contains(toolScopes[tool]),
                    )) &&
            emitted.add(fact.id))
          chatDisplayItemIdentity(item): fact,
  };
}

/// Stable within its source; anonymous saved rows deliberately have no inferred
/// correspondence across physical observations. Inner card/pin IDs are unchanged.
Object chatDisplayItemIdentity(dynamic item) {
  if (item is ChatToolActivityGroup) return ('tool', item.id);
  if (item is ChatReasoningItem) return ('reasoning', item.id);
  if (item is ChatAttachmentItem) return ('attachment', item.id);
  if (item is GatewayNotice) return ('notice', item.identity);
  if (item is List<GatewaySubagentActivity>) return 'tasks';
  final row = item as Map<String, dynamic>;
  return (
    'row',
    row['_timeline_id'] ??
        row['_normal_projection_id'] ??
        row['id'] ??
        row['message_id'] ??
        identityHashCode(row),
  );
}

/// Quiet replies retain delivered files, not diagnostic tool cards. Both
/// sources reuse the same audited extractor and source-local deduplication.
List<dynamic> buildConversationAttachmentItems({
  required List<Map<String, dynamic>> messages,
  List<GatewayToolActivity> toolActivities = const [],
  ChatTimeline? timeline,
  bool received = false,
}) => buildChatDisplayItems(
  messages: messages,
  toolActivities: toolActivities,
  timeline: timeline,
  conversationOnly: true,
  received: received,
);

/// Assistant reasoning rendered as its own collapsible item in the chat list.
class ChatReasoningItem {
  final String text;
  final bool initiallyExpanded;
  final String? id;

  const ChatReasoningItem(this.text, this.initiallyExpanded, {this.id});
}

/// A validated producer deliverable, not tool/debug text or an assistant row.
/// Identity belongs to its originating call/reference, never its list position.
class ChatAttachmentItem {
  const ChatAttachmentItem({
    required this.id,
    required this.ref,
    this.scope,
    this.activity,
  });

  final String id;
  final MediaTagRef ref;

  /// UI-only provenance. Independent reducers may reuse public tool ids, so
  /// those strings alone must never infer a received lifecycle scope.
  final Object? scope;
  final GatewayToolActivity? activity;
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
/// The result mixes these item kinds, in the order the conversation produced
/// them:
///
/// - `Map<String, dynamic>` — a user or assistant bubble, carrying
///   `_display_content` (tool-result blocks stripped) and, for assistant
///   replies, `_retry_prompt` with the user prompt that caused it;
/// - [ChatToolActivityGroup] — consecutive tool results collapsed into one
///   activity card;
/// - [ChatAttachmentItem] — independently visible validated tool deliveries;
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
  bool conversationOnly = false,
  bool received = false,
}) {
  final toolNamesById = generatedMediaToolCallNames(messages);
  final storedResults =
      Map<Map<String, dynamic>, GeneratedMediaResult>.identity();
  final storedResultsById = <String, GeneratedMediaResult>{};
  for (final message in messages) {
    if (message['role'] != 'tool') continue;
    final result = generatedMediaResultFromToolMessage(
      message,
      toolNamesById: toolNamesById,
    );
    storedResults[message] = result;
    final id = message['tool_call_id'] ?? message['toolCallId'];
    if (id is String && id.isNotEmpty) {
      if (storedResultsById[id]?.isFailure != true) {
        storedResultsById[id] = result;
      }
    }
  }
  final suppressedDeliveryIds = <String>{
    for (final message in messages)
      if (message['role'] == 'tool' &&
          (!isPublicDeliveryMessage(message) ||
              message.containsKey('display_content') &&
                  storedResults[message]!.deliveredFiles.isEmpty ||
              storedResults[message]!.isFailure))
        if ((message['tool_call_id'] ?? message['toolCallId'])
            case final String id)
          id,
  };
  final toolQueue = toolActivities
      .where((a) => timeline?.excludesTool(a) != true)
      .toList();
  // A turn can contain several canonical interim rows. Project their receipt
  // runs together at the first live anchor so consuming an earlier preview
  // cannot pull later tools/reasoning ahead of intervening commentary.
  final scopeTurns = <Object, int>{};
  final scopeRows = <Object, Map<String, dynamic>>{};
  Object scopeFor(Map<String, dynamic> row) =>
      row['_normal_projection_id'] ?? row;
  final quietRows = <Object, Map<String, dynamic>>{};
  final quietDeliveryScopes = <Object>{};
  if (conversationOnly) {
    var pendingTools = <Object>[];
    String? prompt;
    for (final row in messages) {
      final scope = scopeFor(row);
      if (row['role'] == 'user') pendingTools = [];
      if (row['role'] == 'tool') pendingTools.add(scope);
      final selected = buildConversationDisplayItems(
        messages: [row],
        timeline: timeline,
        received: received,
      );
      if (selected.isEmpty) continue;
      final item = selected.single;
      if (item['role'] == 'user') {
        prompt = item['_display_content'] as String;
      } else {
        // A received sibling final cannot lend authority to this scope.
        quietDeliveryScopes.add(scope);
        if (!received) quietDeliveryScopes.addAll(pendingTools);
        pendingTools = [];
      }
      quietRows[scope] = {
        ...item,
        if (item['role'] == 'assistant') '_retry_prompt': ?prompt,
      };
    }
  }
  var turn = 0;
  for (final message in messages) {
    if (message['role'] == 'user') turn++;
    final scope = scopeFor(message);
    scopeTurns[scope] = turn;
    scopeRows[scope] = message;
  }
  final liveRuns =
      timeline?.runs
          .where(
            (r) =>
                scopeTurns.containsKey(r.scope) &&
                isPublicDeliveryMessage(scopeRows[r.scope]!) &&
                !scopeRows[r.scope]!.containsKey('display_content'),
          )
          .toList() ??
      const <ChatTimelineRun>[];
  // Ownership survives full eviction of a scope's runs. Otherwise its canonical
  // assistant accumulator would silently re-render all the evicted prose.
  // An explicit server public-content projection replaces this scope's live
  // accumulator, even when null/empty. Do not replay its physical text/tools
  // or let receipt ownership suppress the replacement public prose below.
  final liveScopes = (timeline?.scopes ?? const <Object>{})
      .where(
        (scope) => !(scopeRows[scope]?.containsKey('display_content') ?? false),
      )
      .toSet();
  final anchors = <int, Object>{};
  for (final message in messages) {
    final scope = scopeFor(message);
    if (liveScopes.contains(scope) && isPublicDeliveryMessage(message)) {
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
  final currentAttachments = <ChatAttachmentItem>[];
  String? currentGroupId;
  String? lastUserPrompt;

  void flushToolGroup() {
    if (currentGroup.isNotEmpty) {
      displayItems.add(
        ChatToolActivityGroup(
          id: currentGroupId ?? currentGroup.first.identity,
          activities: currentGroup.toList(),
        ),
      );
    }
    displayItems.addAll(currentAttachments);
    currentGroup.clear();
    currentAttachments.clear();
    currentGroupId = null;
  }

  void addAttachments(
    Iterable<MediaTagRef> refs,
    String origin, {
    Object? scope,
    GatewayToolActivity? activity,
  }) {
    if (activity?.hasFailedDelivery == true ||
        suppressedDeliveryIds.contains(activity?.toolId) ||
        storedResultsById[activity?.toolId]?.isFailure == true) {
      return;
    }
    for (final ref in refs) {
      currentAttachments.add(
        ChatAttachmentItem(
          id: jsonEncode([origin, ref.path]),
          ref: ref,
          scope: scope,
          activity: activity,
        ),
      );
    }
  }

  for (final msg in messages) {
    final rawRole = (msg['role'] as String?) ?? 'assistant';
    final role = rawRole == 'agent' ? 'assistant' : rawRole;
    if ((role == 'user' || role == 'assistant') &&
        BackgroundReport.fromMessage(msg) != null) {
      // Reports may consist entirely of tool-looking output. Preserve the raw
      // row before the ordinary bubble/tool text filters can discard it.
      flushToolGroup();
      displayItems.add({...msg, 'role': role});
      continue;
    }
    // A physical tool wrapper cannot overrule replacement public assistant text.
    // Explicit tool roles still take the tool-result path.
    if (isToolResultMessage(
      role == 'assistant' ? {...msg, 'content': publicDeliveryText(msg)} : msg,
    )) {
      final callId = msg['tool_call_id'] ?? msg['toolCallId'];
      final match = callId == null || callId == ''
          ? (toolQueue.isEmpty ? -1 : 0)
          : toolQueue.indexWhere((activity) => activity.toolId == callId);
      final activity = match >= 0 ? toolQueue.removeAt(match) : null;
      if (!isPublicDeliveryMessage(msg)) continue;
      if (activity != null) {
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
      // Receipt chronology, including eviction, owns live tools. A durable
      // result cannot invent a second slot ahead of its actual receipt run.
      final liveOwned =
          callId is String &&
          callId.isNotEmpty &&
          (liveTools.any((tool) => tool.toolId == callId) ||
              timeline?.excludesTool(
                    GatewayToolActivity(
                      toolId: callId,
                      name: 'tool',
                      phase: GatewayToolActivityPhase.completed,
                    ),
                  ) ==
                  true);
      if (!liveOwned && !suppressedDeliveryIds.contains(callId)) {
        final storedResult = storedResults[msg];
        final refs = storedResult?.deliveredFiles ?? const <MediaTagRef>[];
        if (storedResult?.isFailure != true) {
          final rowId = msg['id'] ?? msg['message_id'];
          addAttachments(
            refs.isNotEmpty ? refs : activity?.deliveredFiles ?? const [],
            activity?.identity ??
                (callId is String && callId.isNotEmpty
                    ? 'tool:$callId'
                    : 'message:${rowId ?? identityHashCode(msg)}'),
            activity: activity,
            scope: scopeFor(msg),
          );
        }
      }
      continue;
    }
    if (role != 'user' && role != 'assistant') continue;
    if (!isPublicDeliveryMessage(msg)) continue;

    final scope = scopeFor(msg);
    if (liveScopes.contains(scope) && !anchoredRuns.containsKey(scope)) {
      continue;
    }
    final runs = anchoredRuns[scope] ?? const <ChatTimelineRun>[];
    if (role == 'assistant' && liveScopes.contains(scope)) {
      // Anchored runs share turn chronology, but each message owns its footer.
      final lastTextRunByScope = <Object, String>{
        for (final run in runs)
          if (run.kind == ChatTimelineKind.text && run.text.isNotEmpty)
            run.scope: run.id,
      };
      for (final run in runs) {
        if (run.kind == ChatTimelineKind.tool) {
          currentGroupId ??= run.activity!.identity;
          currentGroup.add(run.activity!);
          if (isPublicDeliveryMessage(scopeRows[run.scope]!)) {
            final storedRefs =
                storedResultsById[run.activity!.toolId]?.deliveredFiles;
            addAttachments(
              storedRefs?.isNotEmpty == true
                  ? storedRefs!
                  : run.activity!.deliveredFiles,
              run.activity!.identity,
              scope: run.scope,
              activity: run.activity,
            );
          }
          continue;
        }
        flushToolGroup();
        if (run.kind == ChatTimelineKind.reasoning) {
          displayItems.add(ChatReasoningItem(run.text, false, id: run.id));
        } else if (run.text.isNotEmpty) {
          displayItems.add({
            ...scopeRows[run.scope]!,
            'role': role,
            '_timeline_id': run.id,
            '_message_time_continuation':
                run.id != lastTextRunByScope[run.scope],
            if (conversationOnly) '_quiet_projection_scope': run.scope,
            '_display_content': run.text,
            '_retry_prompt': ?lastUserPrompt,
          });
        }
      }
      continue;
    }

    final content = stripToolResultText(
      role == 'assistant'
          ? publicDeliveryText(msg)
          : messageContentToText(
              AndroidPromptContext.displayContent(
                msg,
                publicDeliveryContent(msg),
              ),
            ),
    );
    final reasoning = msg['_gateway_reasoning']?.toString() ?? '';
    final hasReasoning =
        role == 'assistant' &&
        !msg.containsKey('display_content') &&
        reasoning.trim().isNotEmpty;
    if (content.isEmpty && !hasReasoning) continue;

    flushToolGroup();

    if (hasReasoning) {
      displayItems.add(
        ChatReasoningItem(
          reasoning,
          // Detailed mode exposes reasoning, but never opens it automatically.
          false,
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
        if (conversationOnly) '_quiet_projection_scope': scope,
        if (role == 'assistant' && lastUserPrompt != null)
          '_retry_prompt': lastUserPrompt,
      });
    }
  }
  flushToolGroup();

  // An active receipt projection is authoritative even after eviction. Only
  // legacy snapshots without receipt ownership get an unmatched trailing card;
  // otherwise this queue could resurrect tools removed by the live budget.
  if (toolQueue.isNotEmpty && (timeline == null || timeline.scopes.isEmpty)) {
    currentGroupId = toolQueue.first.identity;
    currentGroup.addAll(toolQueue);
    for (final activity in toolQueue) {
      addAttachments(
        activity.deliveredFiles,
        activity.identity,
        activity: activity,
      );
    }
    flushToolGroup();
  }
  if (subagentActivities.isNotEmpty) {
    displayItems.add(List<GatewaySubagentActivity>.from(subagentActivities));
  }
  displayItems.addAll(notices);

  // Filter before echo suppression so hidden commentary cannot swallow a
  // completed delivery. Reuse the public projection for prose and producer
  // hints; never reinterpret hidden physical content or cross saved/received.
  if (conversationOnly) {
    final emittedScopes = <Object>{};
    final quietItems = <dynamic>[
      for (final item in displayItems)
        if (item is ChatAttachmentItem &&
            quietDeliveryScopes.contains(item.scope))
          item
        else if (item is Map<String, dynamic>)
          if (quietRows.containsKey(item['_quiet_projection_scope']) &&
              emittedScopes.add(item['_quiet_projection_scope']))
            quietRows[item['_quiet_projection_scope']]!,
    ];
    displayItems
      ..clear()
      ..addAll(quietItems);
  }

  // Prefer an explicit public assistant delivery over its tool-result echo.
  // Inspect only actual projected text, never reasoning or evicted prose. Each
  // saved/received source calls this independently; no cross-source matching.
  final echoedPaths = <String>{
    for (final item in displayItems)
      if (item is Map<String, dynamic> &&
          (item['role'] == 'assistant' || item['role'] == 'agent') &&
          isPublicDeliveryMessage(item))
        for (final ref in extractDeliveredFileRefs(
          item['_display_content'] is String
              ? item['_display_content'] as String
              : publicDeliveryText(item),
          isFinal: item['_gateway_pending_response'] != true,
        ))
          ref.path,
  };
  final deliveredPaths = <String>{};
  final producerRefs = <String, MediaTagRef>{};
  for (final item in displayItems.whereType<ChatAttachmentItem>()) {
    if (item.ref.suggestedFilename != null) {
      producerRefs.putIfAbsent(item.ref.path, () => item.ref);
    }
  }
  return [
    for (final item in displayItems)
      if (item is! ChatAttachmentItem ||
          !echoedPaths.contains(item.ref.path) &&
              deliveredPaths.add(item.ref.path))
        if (item is Map<String, dynamic> &&
            (item['role'] == 'assistant' || item['role'] == 'agent') &&
            isPublicDeliveryMessage(item))
          {
            ...item,
            // Presentation metadata only: the original history/wire rows are
            // untouched. Keep a producer's image hint when its card yields to
            // an exact public echo within this saved/received source.
            if (producerRefs.isNotEmpty)
              '_delivery_refs': Map<String, MediaTagRef>.unmodifiable({
                for (final path in echoedPaths)
                  if (producerRefs.containsKey(path)) path: producerRefs[path]!,
              }),
          }
        else
          item,
  ];
}
