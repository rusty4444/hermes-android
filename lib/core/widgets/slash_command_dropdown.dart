import 'package:flutter/material.dart';

import '../controllers/slash_command_controller.dart';
import '../models/slash_command.dart';
import '../theme/hermes_theme.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Anchored command list above the composer. It only presents the controller's
/// local filter; it never fetches, submits or edits the draft itself.
class SlashCommandDropdown extends StatelessWidget {
  const SlashCommandDropdown({
    required this.controller,
    required this.onSelected,
    this.maxHeight = 180,
    super.key,
  });

  final SlashCommandController controller;
  final ValueChanged<SlashCommand> onSelected;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final matches = controller.matches;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Material(
        key: const Key('slash-command-dropdown'),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        elevation: 3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                context.l10n.slash_commands,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Flexible(
              child: !controller.catalogLoaded
                  ? _statusRow(context, context.l10n.slash_commands_loading)
                  : matches.isEmpty
                  ? _statusRow(context, context.l10n.slash_commands_empty)
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: matches.length,
                      itemBuilder: (context, index) =>
                          _entry(context, matches[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: HermesTokens.of(context).muted),
    ),
  );

  Widget _entry(BuildContext context, SlashCommand command) {
    final tokens = HermesTokens.of(context);
    return InkWell(
      key: ValueKey<String>('slash-command-${command.name}'),
      onTap: () => onSelected(command),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.terminal, size: 18, color: tokens.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    command.invocation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (command.description.isNotEmpty)
                    Text(
                      command.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                    ),
                ],
              ),
            ),
            if (command.category.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  command.category,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: tokens.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
