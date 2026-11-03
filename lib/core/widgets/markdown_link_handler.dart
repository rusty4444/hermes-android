import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';

/// Opens web links only after an explicit tap. Gateway artifacts are handled by
/// their owning message; local files, relative paths and app intents stay inert.
Future<void> openMarkdownWebLink(BuildContext context, String? href) async {
  if (!context.mounted || href == null) return;
  final uri = Uri.tryParse(href);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty) {
    return;
  }

  final originatingRoute = ModalRoute.of(context);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Missing browser/plugin and rejected platform intents have the same UI.
  }
  if (opened || !context.mounted || originatingRoute?.isActive == false) return;
  // Popped routes remain mounted during their reverse animation. Only the
  // originating active route may present failure feedback above its modal.
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(dialogContext.l10n.could_not_open_link),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.l10n.close),
        ),
      ],
    ),
  );
}
