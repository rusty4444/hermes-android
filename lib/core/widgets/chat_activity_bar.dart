import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';

/// Ephemeral turn activity, never a message or an item in saved chat history.
/// Terminal notices remain readable without implying that Hermes is typing.
class ChatActivityBar extends StatelessWidget {
  const ChatActivityBar({
    required this.text,
    this.isTerminalNotice = false,
    super.key,
  });

  final String text;
  final bool isTerminalNotice;

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Semantics(
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        key: ValueKey(
          isTerminalNotice ? 'chat-turn-notice' : 'chat-current-activity',
        ),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.accentContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (isTerminalNotice)
              Icon(
                Icons.info_outline,
                size: 14,
                color: tokens.onAccentContainer,
              )
            else
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: tokens.onAccentContainer,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: isTerminalNotice ? null : 2,
                overflow: isTerminalNotice ? null : TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.onAccentContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
