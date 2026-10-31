import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../services/theme_preference.dart';
import '../theme/hermes_theme.dart';

String paletteLabel(BuildContext context, HermesPalette palette) {
  final l10n = context.l10n;
  return switch (palette) {
    HermesPalette.gold => l10n.theme_palette_gold,
    HermesPalette.purple => l10n.theme_palette_purple,
    HermesPalette.orange => l10n.theme_palette_orange,
    HermesPalette.green => l10n.theme_palette_green,
    HermesPalette.blue => l10n.theme_palette_blue,
    HermesPalette.red => l10n.theme_palette_red,
    HermesPalette.teal => l10n.theme_palette_teal,
    HermesPalette.pink => l10n.theme_palette_pink,
    HermesPalette.indigo => l10n.theme_palette_indigo,
    HermesPalette.cyan => l10n.theme_palette_cyan,
  };
}

/// Reused by Settings and the connection screen; never needs a gateway.
class ThemeAppearanceSettings extends StatelessWidget {
  const ThemeAppearanceSettings({
    required this.preferences,
    this.onChanged,
    super.key,
  });

  final SharedPreferences preferences;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThemeModePicker(preferences: preferences, onChanged: onChanged),
        const SizedBox(height: 8),
        ThemePalettePicker(preferences: preferences, onChanged: onChanged),
      ],
    );
  }
}

/// Labeled swatches remain identifiable without color vision or a touch screen.
class ThemePalettePicker extends StatefulWidget {
  const ThemePalettePicker({
    required this.preferences,
    this.onChanged,
    super.key,
  });

  final SharedPreferences preferences;

  /// Called after the saved preference, or a failed save's rollback, settles.
  final VoidCallback? onChanged;

  @override
  State<ThemePalettePicker> createState() => _ThemePalettePickerState();
}

class _ThemePalettePickerState extends State<ThemePalettePicker> {
  Future<void> _select(HermesPalette palette) async {
    final onChanged = widget.onChanged;
    try {
      await ThemePreferenceStore(widget.preferences).savePalette(palette);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.failed(error))));
      }
    } finally {
      if (mounted) setState(() {});
      // The app outlives this picker and still needs the settled save/rollback.
      onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final selected = ThemePreferenceStore(widget.preferences).readPalette();
    return Card(
      key: const Key('theme_palette_picker'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.theme_palette,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final palette in HermesPalette.values)
                  Semantics(
                    key: Key('theme_palette_${palette.name}'),
                    label: paletteLabel(context, palette),
                    button: true,
                    selected: palette == selected,
                    onTap: () => _select(palette),
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 104,
                        child: Material(
                          color: palette == selected
                              ? tokens.accentContainer
                              : tokens.raised,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () => _select(palette),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: palette == selected
                                      ? tokens.accent
                                      : tokens.border,
                                  width: palette == selected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: palette.seedColor,
                                      border: Border.all(
                                        color: foregroundFor(palette.seedColor),
                                      ),
                                    ),
                                    child: palette == selected
                                        ? Icon(
                                            Icons.check,
                                            color: foregroundFor(
                                              palette.seedColor,
                                            ),
                                            size: 22,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    paletteLabel(context, palette),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: palette == selected
                                              ? tokens.onAccentContainer
                                              : tokens.onSurface,
                                          fontWeight: palette == selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ThemeModePicker extends StatefulWidget {
  const ThemeModePicker({required this.preferences, this.onChanged, super.key});

  final SharedPreferences preferences;
  final VoidCallback? onChanged;

  @override
  State<ThemeModePicker> createState() => _ThemeModePickerState();
}

class _ThemeModePickerState extends State<ThemeModePicker> {
  Future<void> _select(ThemeMode mode) async {
    final onChanged = widget.onChanged;
    try {
      await ThemePreferenceStore(widget.preferences).saveMode(mode);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.failed(error))));
      }
    } finally {
      if (mounted) setState(() {});
      onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ThemePreferenceStore(widget.preferences).readMode();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in ThemeMode.values)
          ChoiceChip(
            key: Key('theme_mode_${mode.name}'),
            avatar: Icon(switch (mode) {
              ThemeMode.system => Icons.brightness_auto,
              ThemeMode.light => Icons.light_mode,
              ThemeMode.dark => Icons.dark_mode,
            }, size: 18),
            label: Text(switch (mode) {
              ThemeMode.system => context.l10n.system,
              ThemeMode.light => context.l10n.light,
              ThemeMode.dark => context.l10n.dark,
            }),
            selected: selected == mode,
            showCheckmark: false,
            onSelected: (_) => _select(mode),
          ),
      ],
    );
  }
}
