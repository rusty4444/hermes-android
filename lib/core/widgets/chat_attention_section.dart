import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/hermes_theme.dart';
import '../utils/home_digest.dart';
import 'hermes_components.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Only work that needs attention belongs above the conversation browser.
/// Recent and completed chats are already represented by the list below it.
class ChatAttentionSection extends StatelessWidget {
  final List<Session> sessions;
  final Map<String, String> attention;
  final Set<String> running;
  final ValueChanged<Session> onOpenSession;
  final VoidCallback? onOpenActivity;

  const ChatAttentionSection({
    required this.sessions,
    required this.attention,
    required this.running,
    required this.onOpenSession,
    this.onOpenActivity,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sections =
        buildHomeDigest(
          sessions: sessions,
          now: DateTime.now(),
          attention: attention,
          running: running,
          sectionLimit: 3,
        ).sections.where(
          (section) =>
              section.kind == HomeSectionKind.needsYou ||
              section.kind == HomeSectionKind.running,
        );
    if (sections.isEmpty) return const SizedBox.shrink();
    final tokens = HermesTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: HermesSpacing.md),
            child: HermesCard(
              padding: const EdgeInsets.all(HermesSpacing.sm),
              status: section.kind == HomeSectionKind.needsYou
                  ? HermesStatus.blocked
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(HermesSpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          section.kind == HomeSectionKind.needsYou
                              ? Icons.front_hand_outlined
                              : Icons.bolt_outlined,
                          size: 18,
                          color: tokens.colorForStatus(
                            section.kind == HomeSectionKind.needsYou
                                ? HermesStatus.blocked
                                : HermesStatus.running,
                          ),
                        ),
                        const SizedBox(width: HermesSpacing.sm),
                        Expanded(
                          child: Text(
                            section.title(context.l10n),
                            style: tokens.typography.section,
                          ),
                        ),
                        Text(
                          '${section.totalCount}',
                          style: tokens.typography.label,
                        ),
                      ],
                    ),
                  ),
                  for (final item in section.items)
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: HermesSpacing.sm,
                        ),
                        title: Text(
                          item.session.title.trim().isEmpty
                              ? context.l10n.untitled_chat
                              : item.session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.attentionLabel == null
                            ? null
                            : Text(
                                item.attentionLabel!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => onOpenSession(item.session),
                      ),
                    ),
                  if (section.overflow > 0)
                    TextButton(
                      onPressed: onOpenActivity,
                      child: Text(context.l10n.and_more(section.overflow)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
