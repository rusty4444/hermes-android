import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/apk_update_installer.dart';
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

/// The fallback launcher: opens the release page in the system browser.
Future<bool> launchReleaseInBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Asks whether to go and look at a published release.
Future<UpdatePromptAction?> showUpdateAvailableDialog(
  BuildContext context, {
  required AppReleaseInfo release,
  ReleaseLauncher launcher = launchReleaseInBrowser,
  ApkUpdateInstaller? installer,
}) {
  if (AppUpdateService.isPlayBuild) {
    return Future<UpdatePromptAction?>.value(UpdatePromptAction.later);
  }
  return showDialog<UpdatePromptAction>(
    context: context,
    barrierDismissible: false,
    builder: (context) => UpdateAvailableDialog(
      release: release,
      launcher: launcher,
      installer: installer,
    ),
  );
}

/// The prompt keeps the browser fallback and offers a user-initiated download.
class UpdateAvailableDialog extends StatefulWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.release,
    this.launcher = launchReleaseInBrowser,
    this.installer,
  });

  final AppReleaseInfo release;
  final ReleaseLauncher launcher;
  final ApkUpdateInstaller? installer;

  @override
  State<UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<UpdateAvailableDialog> {
  late final ApkUpdateInstaller _installer =
      widget.installer ?? ApkUpdateInstaller();
  AppReleaseApk? _apk;
  bool _downloading = false;
  bool _ready = false;
  bool _openingInstaller = false;
  bool _externalHandoff = false;
  bool _permissionRequired = false;
  bool _failed = false;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _findApk();
  }

  Future<void> _findApk() async {
    if (AppUpdateService.isPlayBuild) return;
    try {
      final abis = await _installer.supportedAbis();
      final apk = widget.release.apkForAbis(abis);
      final ready =
          apk != null &&
          await _installer.hasPreparedUpdate(apk, widget.release.tagName);
      if (!mounted) return;
      setState(() {
        _apk = apk;
        _ready = ready;
      });
    } catch (_) {
      // No supported Android installer: keep the existing browser fallback.
    }
  }

  @override
  void dispose() {
    // Android may destroy the Activity while its settings/installer is open.
    // Keep the verified file available to the new process in that case.
    if (!_externalHandoff) _installer.cancel().catchError((Object _) {});
    super.dispose();
  }

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
              widget.release.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(l10n.version_label(widget.release.version)),
            const SizedBox(height: 8),
            Text(l10n.a_newer_hermes_android_build_is_available_on_github),
            if (_downloading) ...[
              const SizedBox(height: 12),
              Text(l10n.update_downloading),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
            ],
            if (_permissionRequired) ...[
              const SizedBox(height: 12),
              Text(l10n.update_allow_install),
            ],
            if (_failed) ...[
              const SizedBox(height: 12),
              Text(l10n.update_failed),
            ],
            if (widget.release.notes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.release_notes,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              MarkdownBody(
                data: widget.release.notes,
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
          onPressed: _openingInstaller ? null : _dismiss,
          child: Text(_downloading ? l10n.cancel : l10n.later),
        ),
        if (!_downloading && !_ready)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(UpdatePromptAction.skipVersion),
            child: Text(l10n.skip_this_version),
          ),
        if (!_downloading)
          TextButton(
            onPressed: _openingInstaller ? null : () => _openRelease(context),
            child: Text(l10n.view_release),
          ),
        if (_apk != null)
          FilledButton(
            onPressed: _downloading || _openingInstaller ? null : _update,
            child: Text(_ready ? l10n.update_install : l10n.update_now),
          ),
      ],
    );
  }

  void _dismiss() {
    _externalHandoff = false;
    Navigator.of(context).pop(UpdatePromptAction.later);
  }

  Future<void> _update() async {
    final apk = _apk;
    if (apk == null || _downloading || _openingInstaller) return;
    if (!_ready) {
      setState(() {
        _downloading = true;
        _failed = false;
        _permissionRequired = false;
        _progress = null;
      });
      try {
        await _installer.download(
          apk: apk,
          tag: widget.release.tagName,
          onProgress: (received, total) {
            if (mounted) setState(() => _progress = received / total);
          },
        );
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _ready = true;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _failed = true;
        });
        return;
      }
    }
    setState(() {
      _openingInstaller = true;
      _externalHandoff = true;
      _failed = false;
      _permissionRequired = false;
    });
    try {
      final outcome = await _installer.install();
      if (!mounted) return;
      final failed = outcome != 'permission_required' && outcome != 'launched';
      setState(() {
        _openingInstaller = false;
        _permissionRequired = outcome == 'permission_required';
        _failed = failed;
        _externalHandoff = !failed;
        if (failed) _ready = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _openingInstaller = false;
        _permissionRequired = false;
        _externalHandoff = false;
        _failed = true;
        _ready = false;
      });
    }
  }

  Future<void> _openRelease(BuildContext context) async {
    var opened = false;
    try {
      opened = await widget.launcher(Uri.parse(widget.release.releaseUrl));
    } catch (_) {
      // A device with no browser and a malformed URL are the same outcome for
      // the user: the page did not open, and the prompt stays dismissed.
      opened = false;
    }
    if (!context.mounted) return;
    _externalHandoff = false;
    Navigator.of(
      context,
    ).pop(opened ? UpdatePromptAction.viewRelease : UpdatePromptAction.later);
  }
}
