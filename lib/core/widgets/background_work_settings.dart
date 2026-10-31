import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/background_work_prefs.dart';

/// Device-local controls, intentionally independent of dashboard/model reads.
class BackgroundWorkSettings extends StatefulWidget {
  final Future<bool> Function()? openBatterySettings;

  const BackgroundWorkSettings({super.key, this.openBatterySettings});

  @override
  State<BackgroundWorkSettings> createState() => _BackgroundWorkSettingsState();
}

class _BackgroundWorkSettingsState extends State<BackgroundWorkSettings> {
  bool _saving = false;
  bool _opening = false;

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await BackgroundWorkPrefsStore.setEnabled(enabled);
    } catch (_) {
      if (mounted) _showError(context.l10n.background_work_save_failed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openBatterySettings() async {
    setState(() => _opening = true);
    var opened = false;
    try {
      opened =
          await (widget.openBatterySettings ??
              BackgroundWorkPlatform.openBatterySettings)();
    } catch (_) {
      // Optional platform integration must not turn a tap into a crash.
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) _showError(context.l10n.battery_settings_unavailable);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: backgroundWorkEnabled,
          builder: (context, enabled, _) => SwitchListTile(
            secondary: const Icon(Icons.sync_outlined),
            title: Text(context.l10n.keep_chats_active_in_background),
            subtitle: Text(context.l10n.background_work_description),
            value: enabled,
            onChanged: _saving ? null : _setEnabled,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.background_work_limits),
              const SizedBox(height: 8),
              Text(context.l10n.background_work_disclosure),
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.battery_saver_outlined),
          title: Text(context.l10n.battery_optimisation_settings),
          subtitle: Text(context.l10n.battery_optimisation_description),
          trailing: const Icon(Icons.open_in_new),
          onTap: _opening ? null : _openBatterySettings,
        ),
      ],
    ),
  );
}
