import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/app_update_service.dart';

/// What the user chose in the update prompt.
enum UpdatePromptAction {
  /// The release page was opened in the browser.
  viewRelease,

  /// The user does not want to hear about this version again.
  skipVersion,

  /// Dismissed without a decision; the next launch may ask again.
  later,
}

/// Opens a release page. Injectable so widget tests do not need the plugin.
typedef ReleaseLauncher = Future<bool> Function(Uri url);

/// The real launcher: hands the release page to the system browser, which is
/// where an APK is downloaded from — the app never installs anything itself.
Future<bool> launchReleaseInBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Asks whether to go and look at a published release.
Future<UpdatePromptAction?> showUpdateAvailableDialog(
  BuildContext context, {
  required AppReleaseInfo release,
  ReleaseLauncher launcher = launchReleaseInBrowser,
}) {
  return showDialog<UpdatePromptAction>(
    context: context,
    builder: (context) =>
        UpdateAvailableDialog(release: release, launcher: launcher),
  );
}

/// The launch-time update prompt: what is out, and a way to go and get it.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.release,
    this.launcher = launchReleaseInBrowser,
  });

  final AppReleaseInfo release;
  final ReleaseLauncher launcher;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.update_available),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              release.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(l10n.version_label(release.version)),
            const SizedBox(height: 8),
            Text(l10n.a_newer_hermes_android_build_is_available_on_github),
            if (release.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.release_notes,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              MarkdownBody(
                data: release.notes,
                shrinkWrap: true,
                // Release notes are remote Markdown. Showing a tracking image
                // must not contact a third party without an explicit tap.
                sizedImageBuilder: (image) => Text(
                  image.alt?.isNotEmpty == true ? image.alt! : '[image]',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(UpdatePromptAction.later),
          child: Text(l10n.later),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(UpdatePromptAction.skipVersion),
          child: Text(l10n.skip_this_version),
        ),
        FilledButton(
          onPressed: () => _openRelease(context),
          child: Text(l10n.view_release),
        ),
      ],
    );
  }

  Future<void> _openRelease(BuildContext context) async {
    var opened = false;
    try {
      opened = await launcher(Uri.parse(release.releaseUrl));
    } catch (_) {
      // A device with no browser and a malformed URL are the same outcome for
      // the user: the page did not open, and the prompt stays dismissed.
      opened = false;
    }
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pop(opened ? UpdatePromptAction.viewRelease : UpdatePromptAction.later);
  }
}
