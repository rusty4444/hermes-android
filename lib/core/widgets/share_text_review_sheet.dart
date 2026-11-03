import 'package:flutter/material.dart';

import '../services/android_share_intent_service.dart';
import '../theme/hermes_theme.dart';
import '../utils/new_chat_options.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

enum ShareFavoriteAction {
  useAsIs(Icons.edit_note_rounded),
  summarize(Icons.summarize_rounded),
  explain(Icons.lightbulb_outline_rounded),
  research(Icons.travel_explore_rounded),
  extractTasks(Icons.task_alt_rounded),
  remember(Icons.memory_rounded),
  fillFromDocument(Icons.description_outlined);

  final IconData icon;
  const ShareFavoriteAction(this.icon);

  String label(AppLocalizations l10n) => switch (this) {
    ShareFavoriteAction.useAsIs => l10n.use_as_is,
    ShareFavoriteAction.summarize => l10n.share_action_summarize,
    ShareFavoriteAction.explain => l10n.share_action_explain,
    ShareFavoriteAction.research => l10n.share_action_research,
    ShareFavoriteAction.extractTasks => l10n.extract_tasks,
    ShareFavoriteAction.remember => l10n.share_action_remember,
    ShareFavoriteAction.fillFromDocument => l10n.fill_from_document,
  };
}

String buildSharedPrompt(
  ShareFavoriteAction action,
  String source, {
  bool hasAttachments = false,
  required AppLocalizations l10n,
}) {
  final text = source.trim();
  if (text.isEmpty && hasAttachments) {
    return switch (action) {
      ShareFavoriteAction.useAsIs => l10n.review_the_attached_content,
      ShareFavoriteAction.summarize => l10n.summarize_the_attached_content,
      ShareFavoriteAction.explain => l10n.explain_the_attached_content_clearly,
      ShareFavoriteAction.research =>
        l10n.research_the_attached_content_verify_the_important_claims_and_cite,
      ShareFavoriteAction.extractTasks =>
        l10n.extract_the_decisions_deadlines_owners_and_actionable_action_items_from,
      ShareFavoriteAction.remember =>
        l10n.save_the_durable_facts_from_the_attached_content_to_memory,
      ShareFavoriteAction.fillFromDocument =>
        l10n.use_the_attached_content_to_identify_and_fill_the_relevant,
    };
  }
  return switch (action) {
    ShareFavoriteAction.useAsIs => text,
    ShareFavoriteAction.summarize => l10n.summarize_this_content(text),
    ShareFavoriteAction.explain => l10n.explain_this_content_clearly(text),
    ShareFavoriteAction.research =>
      l10n.research_this_content_verify_the_important_claims_and_cite_sources(
        text,
      ),
    ShareFavoriteAction.extractTasks =>
      l10n.extract_the_decisions_deadlines_owners_and_actionable_action_items_from_2(
        text,
      ),
    ShareFavoriteAction.remember =>
      l10n.save_the_durable_facts_from_this_content_to_memory_then(text),
    ShareFavoriteAction.fillFromDocument =>
      l10n.use_this_content_to_identify_and_fill_the_relevant_document(text),
  };
}

class ShareTextDecision {
  final ShareFavoriteAction action;
  final NewChatMode mode;

  const ShareTextDecision({required this.action, required this.mode});
}

class ShareTextReviewSheet extends StatefulWidget {
  final String sharedText;
  final List<AndroidSharedFile> sharedFiles;
  final bool projectChatEnabled;

  const ShareTextReviewSheet({
    required this.sharedText,
    this.sharedFiles = const [],
    required this.projectChatEnabled,
    super.key,
  });

  @override
  State<ShareTextReviewSheet> createState() => _ShareTextReviewSheetState();
}

class _ShareTextReviewSheetState extends State<ShareTextReviewSheet> {
  ShareFavoriteAction _action = ShareFavoriteAction.useAsIs;
  NewChatMode _mode = NewChatMode.quickChat;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          HermesSpacing.lg,
          HermesSpacing.lg,
          HermesSpacing.lg,
          HermesSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.share_to_hermes,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: HermesSpacing.sm),
                    Text(
                      widget.sharedText.trim().isEmpty
                          ? context.l10n.no_text_shared
                          : widget.sharedText,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (widget.sharedFiles.isNotEmpty) ...[
                      const SizedBox(height: HermesSpacing.md),
                      Text(
                        context.l10n.attachment_count(
                          widget.sharedFiles.length,
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: HermesSpacing.xs),
                      for (final file in widget.sharedFiles)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(
                            file.isImage
                                ? Icons.image_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(file.mediaType),
                        ),
                    ],
                    const SizedBox(height: HermesSpacing.lg),
                    Text(
                      context.l10n.action_label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: HermesSpacing.sm),
                    Wrap(
                      spacing: HermesSpacing.sm,
                      runSpacing: HermesSpacing.sm,
                      children: [
                        for (final action in ShareFavoriteAction.values)
                          ChoiceChip(
                            avatar: Icon(action.icon, size: 18),
                            label: Text(action.label(context.l10n)),
                            selected: _action == action,
                            onSelected: (_) => setState(() => _action = action),
                          ),
                      ],
                    ),
                    const SizedBox(height: HermesSpacing.lg),
                    Text(
                      context.l10n.destination_label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    RadioGroup<NewChatMode>(
                      groupValue: _mode,
                      onChanged: (mode) {
                        if (mode != null) setState(() => _mode = mode);
                      },
                      child: Column(
                        children: [
                          RadioListTile<NewChatMode>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(context.l10n.quick_chat),
                            value: NewChatMode.quickChat,
                          ),
                          RadioListTile<NewChatMode>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(context.l10n.project_chat),
                            subtitle: Text(
                              widget.projectChatEnabled
                                  ? context.l10n.choose_an_active_project_next
                                  : context
                                        .l10n
                                        .no_active_projects_on_this_gateway,
                            ),
                            value: NewChatMode.projectChat,
                            enabled: widget.projectChatEnabled,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: HermesSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                const SizedBox(width: HermesSpacing.sm),
                FilledButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(ShareTextDecision(action: _action, mode: _mode)),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(context.l10n.continue_label),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
