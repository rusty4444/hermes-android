import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Asks for a non-empty conversation name without owning a controller outside
/// the dialog route's lifetime.
Future<String?> showSessionNameDialog({
  required BuildContext context,
  required String title,
  required String initialValue,
  required String actionLabel,
}) async {
  var draft = initialValue;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void submit() {
          if (draft.trim().isNotEmpty) {
            Navigator.pop(dialogContext, draft.trim());
          }
        }

        return AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: initialValue,
            autofocus: true,
            maxLength: 120,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (value) => setDialogState(() => draft = value),
            onFieldSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: draft.trim().isEmpty ? null : submit,
              child: Text(actionLabel),
            ),
          ],
        );
      },
    ),
  );
  return result;
}
