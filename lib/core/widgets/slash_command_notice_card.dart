import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Command output is local transcript context. Identity is per observation so
/// repeated `/status` runs each keep their own card.
class SlashCommandNotice {
  const SlashCommandNotice({
    required this.command,
    required this.output,
    required this.observedAt,
  });

  final String command;
  final String output;
  final int observedAt;

  String get identity => '$command|$observedAt';
}

/// Command output is local transcript context, not an assistant turn. It
/// reuses the notice card's shell so it reads as system output, never as a
/// reply the model produced.
class SlashCommandNoticeCard extends StatelessWidget {
  const SlashCommandNoticeCard({
    required this.command,
    required this.output,
    super.key,
  });

  final String command;
  final String output;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Card(
      key: const Key('slash-command-notice'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.terminal, size: 21, color: tokens.muted),
        title: Text(context.l10n.slash_command_output),
        subtitle: Text(
          command,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectionArea(
                child: Text(
                  output.isEmpty
                      ? context.l10n.slash_command_no_output
                      : output,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
