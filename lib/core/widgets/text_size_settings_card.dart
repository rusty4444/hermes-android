import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/text_size_preference.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

String _sizeLabel(AppLocalizations l10n, TextSizePreference preference) {
  return switch (preference) {
    TextSizePreference.system => l10n.system,
    TextSizePreference.small => l10n.text_size_small,
    TextSizePreference.standard => l10n.text_size_default,
    TextSizePreference.large => l10n.text_size_large,
    TextSizePreference.extraLarge => l10n.text_size_extra_large,
  };
}

String _sizeDescription(AppLocalizations l10n, TextSizePreference preference) {
  return preference.followsSystemExactly
      ? l10n.text_size_use_system_description
      : l10n.text_size_percent_description(
          (preference.multiplier * 100).round(),
        );
}
/// App-wide text-size control. It stores only the selected display preference;
/// connection, profile, and credential data never enter this namespace.
class TextSizeSettingsCard extends StatefulWidget {
  const TextSizeSettingsCard({
    required this.preferences,
    required this.onChanged,
    super.key,
  });

  final SharedPreferences preferences;
  final ValueChanged<TextSizePreference> onChanged;

  @override
  State<TextSizeSettingsCard> createState() => _TextSizeSettingsCardState();
}

class _TextSizeSettingsCardState extends State<TextSizeSettingsCard> {
  late final TextSizePreferenceStore _store;
  late TextSizePreference _preference;

  @override
  void initState() {
    super.initState();
    _store = TextSizePreferenceStore(widget.preferences);
    _preference = _store.read();
  }

  Future<void> _select(TextSizePreference preference) async {
    if (preference == _preference) {
      Navigator.of(context).pop();
      return;
    }
    await _store.save(preference);
    if (!mounted) return;
    setState(() => _preference = preference);
    widget.onChanged(preference);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showPicker() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.text_size,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.explicit_choices_adjust_android_accessibility_text_size_system_leaves_it,
                ),
                const SizedBox(height: 8),
                RadioGroup<TextSizePreference>(
                  groupValue: _preference,
                  onChanged: (value) {
                    if (value != null) _select(value);
                  },
                  child: Column(
                    children: [
                      for (final preference in TextSizePreference.values)
                        RadioListTile<TextSizePreference>(
                          value: preference,
                          title: Text(_sizeLabel(context.l10n, preference)),
                          subtitle: Text(
                            _sizeDescription(context.l10n, preference),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: context.l10n.text_size_2(
              _sizeLabel(context.l10n, _preference),
            ),
            button: true,
            child: ExcludeSemantics(
              child: ListTile(
                leading: const Icon(Icons.format_size),
                title: Text(context.l10n.text_size),
                subtitle: Text(
                  context.l10n.text_size_label_description(
                    _sizeDescription(context.l10n, _preference),
                    _sizeLabel(context.l10n, _preference),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showPicker,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Semantics(
              label: context.l10n.text_size_preview,
              child: ExcludeSemantics(
                child: Text(
                  context.l10n.preview_label,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              context.l10n.hermes_keeps_android_accessibility_text_scaling_active,
            ),
          ),
        ],
      ),
    );
  }
}
