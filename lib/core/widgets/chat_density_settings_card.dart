import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/chat_density_preference.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

String _densityLabel(AppLocalizations l10n, ChatDensity density) {
  return switch (density) {
    ChatDensity.comfortable => l10n.chat_density_comfortable,
    ChatDensity.compact => l10n.chat_density_compact,
  };
}

String _densityDescription(AppLocalizations l10n, ChatDensity density) {
  return switch (density) {
    ChatDensity.comfortable => l10n.chat_density_comfortable_description,
    ChatDensity.compact => l10n.chat_density_compact_description,
  };
}

/// App-wide chat-density control. It stores only the selected layout
/// preference; connection, profile, and credential data never enter this
/// namespace.
class ChatDensitySettingsCard extends StatefulWidget {
  const ChatDensitySettingsCard({
    required this.preferences,
    this.testSaveDensity,
    super.key,
  });

  final SharedPreferences preferences;

  /// Lets tests hold the write open, to cover a picker dismissed mid-write.
  final Future<void> Function(ChatDensity density)? testSaveDensity;

  @override
  State<ChatDensitySettingsCard> createState() =>
      _ChatDensitySettingsCardState();
}

class _ChatDensitySettingsCardState extends State<ChatDensitySettingsCard> {
  late final ChatDensityStore _store;
  late ChatDensity _density;

  @override
  void initState() {
    super.initState();
    _store = ChatDensityStore(widget.preferences);
    _density = ChatDensity.fromStorage(
      widget.preferences.getString(ChatDensity.preferenceKey),
    );
    // A restore can rewrite the preference while this card is mounted, and a
    // rebuild does not rerun initState, so follow the broadcast as well.
    chatDensitySelection.addListener(_handleSelectionChanged);
  }

  @override
  void dispose() {
    chatDensitySelection.removeListener(_handleSelectionChanged);
    super.dispose();
  }

  void _handleSelectionChanged() {
    if (!mounted) return;
    final density = chatDensitySelection.value;
    if (density == _density) return;
    setState(() => _density = density);
  }

  Future<void> _save(ChatDensity density) {
    final override = widget.testSaveDensity;
    return override != null ? override(density) : _store.save(density);
  }

  /// [sheetContext] belongs to the picker, not to this card: the write is
  /// asynchronous and the user can dismiss the picker while it is in flight, in
  /// which case popping through the Settings route would close Settings itself.
  Future<void> _select(BuildContext sheetContext, ChatDensity density) async {
    final navigator = Navigator.of(sheetContext);
    final route = ModalRoute.of(sheetContext);
    if (density != _density) {
      await _save(density);
      if (!mounted) return;
      setState(() => _density = density);
    }
    if (route == null || !route.isActive || !route.isCurrent) return;
    navigator.pop();
  }

  Future<void> _showPicker() {
    bool saving = false;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.chat_density,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context
                        .l10n
                        .compact_removes_the_you_and_hermes_labels_and_trims_bubble_padding_spacing_and_side_margins,
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<ChatDensity>(
                    groupValue: _density,
                    onChanged: (value) {
                      if (value == null || saving) return;
                      if (value != _density) setSheetState(() => saving = true);
                      _select(sheetContext, value).whenComplete(() {
                        if (sheetContext.mounted &&
                            ModalRoute.of(sheetContext)?.isCurrent == true) {
                          setSheetState(() => saving = false);
                        }
                      });
                    },
                    child: Column(
                      children: [
                        for (final density in ChatDensity.values)
                          RadioListTile<ChatDensity>(
                            value: density,
                            enabled: !saving,
                            title: Text(_densityLabel(context.l10n, density)),
                            subtitle: Text(
                              _densityDescription(context.l10n, density),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Semantics(
        label: context.l10n.chat_density_2(
          _densityLabel(context.l10n, _density),
        ),
        button: true,
        onTap: _showPicker,
        child: ExcludeSemantics(
          child: ListTile(
            leading: const Icon(Icons.view_agenda_outlined),
            title: Text(context.l10n.chat_density),
            subtitle: Text(
              context.l10n.chat_density_label_description(
                _densityDescription(context.l10n, _density),
                _densityLabel(context.l10n, _density),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPicker,
          ),
        ),
      ),
    );
  }
}
