import '../models/chat_timeline.dart';
import '../models/gateway_activity.dart';
import '../models/received_scope_outcome.dart';
import 'chat_display_items.dart';

/// A route-local alternate view, not a saved/received match or retirement.
/// Uncertain output remains in the owner's snapshot and in full exports.
class ChatReceivedRecoveryProjection {
  const ChatReceivedRecoveryProjection({required this.sections, this.retained});

  final List<ChatDisplaySection> sections;
  final ChatDisplaySection? retained;

  factory ChatReceivedRecoveryProjection.build({
    required List<ChatDisplaySection> sections,
    required ChatTimeline timeline,
    required List<ReceivedScopeOutcome> outcomes,
    required Set<String> retainedOutcomeIds,
  }) {
    if (retainedOutcomeIds.isEmpty) {
      return ChatReceivedRecoveryProjection(sections: sections);
    }
    final scopes = {
      for (final outcome in outcomes)
        if (retainedOutcomeIds.contains(outcome.id) &&
            outcome.outcome == ReceivedLifecycleOutcome.unknown)
          ...outcome.scopes,
    };
    if (scopes.isEmpty) {
      return ChatReceivedRecoveryProjection(sections: sections);
    }
    final runScopes = {for (final run in timeline.runs) run.id: run.scope};
    final toolScopes = Map<GatewayToolActivity, Object>.identity();
    for (final run in timeline.runs) {
      if (run.activity != null) toolScopes[run.activity!] = run.scope;
    }
    bool retainedItem(dynamic item) {
      if (item is Map<String, dynamic>) {
        return scopes.contains(item['_normal_projection_id']);
      }
      if (item is ChatReasoningItem) {
        return scopes.contains(runScopes[item.id]);
      }
      if (item is ChatAttachmentItem) {
        return scopes.contains(item.scope ?? toolScopes[item.activity]);
      }
      if (item is ChatToolActivityGroup) {
        // Never assign an unscoped or mixed group by its public tool ID.
        return item.activities.isNotEmpty &&
            item.activities.every((tool) => scopes.contains(toolScopes[tool]));
      }
      return false;
    }

    final primary = <ChatDisplaySection>[];
    final retainedItems = <dynamic>[];
    final retainedFacts = <Object, ReceivedScopeOutcome>{};
    for (final section in sections) {
      if (section.source != ChatDisplaySource.received) {
        primary.add(section);
        continue;
      }
      final remaining = <dynamic>[];
      final remainingFacts = <Object, ReceivedScopeOutcome>{};
      for (final item in section.items) {
        final identity = chatDisplayItemIdentity(item);
        final fact = section.outcomes[identity];
        if (retainedItem(item)) {
          retainedItems.add(item);
          if (fact != null) retainedFacts[identity] = fact;
        } else {
          remaining.add(item);
          if (fact != null) remainingFacts[identity] = fact;
        }
      }
      if (remaining.isNotEmpty) {
        primary.add(
          ChatDisplaySection(
            source: section.source,
            items: remaining,
            outcomes: remainingFacts,
          ),
        );
      }
    }
    return ChatReceivedRecoveryProjection(
      sections: List.unmodifiable(primary),
      retained: retainedItems.isEmpty
          ? null
          : ChatDisplaySection(
              source: ChatDisplaySource.received,
              items: retainedItems,
              outcomes: retainedFacts,
            ),
    );
  }
}
