import 'package:flutter/material.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Accessible floating action that returns a chat to its current end.
class ChatEndAffordance extends StatelessWidget {
  static const buttonKey = Key('chat-go-to-end');
  static const countKey = Key('chat-new-message-count');

  final int newMessageCount;
  final VoidCallback onPressed;
  final String? label;

  const ChatEndAffordance({
    required this.newMessageCount,
    required this.onPressed,
    this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasNewMessages = newMessageCount > 0;
    final indicatorText = hasNewMessages
        ? context.l10n.new_count_indicator(newMessageCount)
        : context.l10n.latest_label;
    final semanticsValue = switch (newMessageCount) {
      0 => context.l10n.no_new_messages,
      _ => context.l10n.new_messages(newMessageCount),
    };

    return Semantics(
      label: context.l10n.go_to_end,
      value: semanticsValue,
      button: true,
      excludeSemantics: true,
      child: FloatingActionButton.extended(
        key: buttonKey,
        heroTag: null,
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_downward_rounded),
        label: Text(label ?? indicatorText, key: countKey),
      ),
    );
  }
}
