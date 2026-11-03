import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

const _selected = <WidgetState>{WidgetState.selected};
const _enabled = <WidgetState>{};

Map<String, Color> _tokenColors(HermesTokens tokens) => {
  'surface': tokens.surface,
  'raised': tokens.raised,
  'border': tokens.border,
  'onSurface': tokens.onSurface,
  'muted': tokens.muted,
  'accent': tokens.accent,
  'onAccent': tokens.onAccent,
  'accentContainer': tokens.accentContainer,
  'onAccentContainer': tokens.onAccentContainer,
  'success': tokens.success,
  'warning': tokens.warning,
  'danger': tokens.danger,
  'running': tokens.running,
  'blocked': tokens.blocked,
};

void _expectReadable(Color foreground, Color background, String reason) {
  expect(foreground.a, 1, reason: '$reason: foreground must be opaque');
  expect(background.a, 1, reason: '$reason: measure the composited background');
  expect(
    contrastRatio(foreground, background),
    greaterThanOrEqualTo(4.5),
    reason: '$reason: normal-size text needs WCAG AA 4.5:1',
  );
}

Future<HermesTokens> _pumpAndReadTokens(
  WidgetTester tester,
  ThemeData theme,
) async {
  late HermesTokens seen;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Builder(
        builder: (context) {
          seen = HermesTokens.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return seen;
}

Color? _renderedTextColor(WidgetTester tester, Finder text) {
  final richText = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)).first,
  );
  return richText.text.style?.color;
}

Material _coloredMaterialAbove(WidgetTester tester, Finder child) {
  return tester
      .widgetList<Material>(
        find.ancestor(of: child, matching: find.byType(Material)),
      )
      .firstWhere((material) => material.color != null);
}

void main() {
  group('HermesSpacing', () {
    test('exposes a strictly increasing 4dp-based scale', () {
      const scale = [
        HermesSpacing.xs,
        HermesSpacing.sm,
        HermesSpacing.md,
        HermesSpacing.lg,
        HermesSpacing.xl,
        HermesSpacing.xxl,
      ];
      for (final step in scale) {
        expect(step % 4, 0, reason: '$step must sit on the 4dp grid');
      }
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('radii grow from control to sheet', () {
      expect(HermesRadius.sm, lessThan(HermesRadius.md));
      expect(HermesRadius.md, lessThan(HermesRadius.lg));
      expect(HermesRadius.lg, lessThan(HermesRadius.xl));
    });

    test('motion durations stay inside the roadmap budget', () {
      expect(HermesMotion.fast.inMilliseconds, greaterThanOrEqualTo(100));
      expect(HermesMotion.standard.inMilliseconds, inInclusiveRange(150, 250));
      expect(HermesMotion.emphasized.inMilliseconds, lessThanOrEqualTo(400));
      expect(HermesMotion.standard, greaterThan(HermesMotion.fast));
    });
  });

  group('HermesPalette', () {
    test('has exactly ten stable storage IDs in the agreed order', () {
      expect(HermesPalette.values.map((palette) => palette.name), [
        'gold',
        'purple',
        'orange',
        'green',
        'blue',
        'red',
        'teal',
        'pink',
        'indigo',
        'cyan',
      ]);
      expect(
        HermesPalette.values.map((palette) => palette.seedColor).toSet(),
        hasLength(10),
      );
      for (final palette in HermesPalette.values) {
        expect(palette.displayName, isNotEmpty);
        expect(palette.seedColor.a, 1);
        expect(HermesPalette.values.byName(palette.name), palette);
      }
      expect(HermesPalette.gold.seedColor, HermesTokens.hermesGold);
    });

    test('changes full schemes and surfaces rather than only the primary', () {
      for (final brightness in Brightness.values) {
        final schemes = [
          for (final palette in HermesPalette.values)
            hermesTheme(brightness, palette: palette).colorScheme,
        ];
        // A scheme with ten primaries but one shared neutral/container family
        // is not ten complete themes. Exclude intentional white/black endpoints.
        for (final role in <Color Function(ColorScheme)>[
          (scheme) => scheme.primary,
          (scheme) => scheme.secondary,
          (scheme) => scheme.tertiary,
          (scheme) => scheme.primaryContainer,
          (scheme) => scheme.secondaryContainer,
          (scheme) => scheme.tertiaryContainer,
          (scheme) => scheme.surface,
          (scheme) => scheme.surfaceContainerLow,
          (scheme) => scheme.surfaceContainerHighest,
        ]) {
          expect(schemes.map(role).toSet(), hasLength(10));
        }
      }
    });
  });

  group('contrast helpers', () {
    test('uses the WCAG luminance calculation, not brightness heuristics', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.000001));
      expect(contrastRatio(Colors.red, Colors.red), 1);
      expect(
        contrastRatio(Colors.red, Colors.blue),
        contrastRatio(Colors.blue, Colors.red),
      );
      expect(foregroundFor(Colors.white), Colors.black);
      expect(foregroundFor(Colors.black), Colors.white);
      // Red has a dark-looking perceived brightness but black wins WCAG.
      expect(foregroundFor(const Color(0xFFFF0000)), Colors.black);
      expect(foregroundFor(const Color(0xFF0000FF)), Colors.white);
    });

    test('always chooses the higher-contrast black or white', () {
      for (var channel = 0; channel <= 255; channel++) {
        final background = Color.fromARGB(255, channel, channel, channel);
        final foreground = foregroundFor(background);
        final other = foreground == Colors.black ? Colors.white : Colors.black;
        _expectReadable(foreground, background, 'grey $channel');
        expect(
          contrastRatio(foreground, background),
          greaterThanOrEqualTo(contrastRatio(other, background)),
        );
      }
    });
  });

  group('HermesTokens', () {
    test(
      'default stays gold, with a deliberately darker light-mode accent',
      () {
        final dark = HermesTokens.dark();
        final light = HermesTokens.light();
        expect(dark.palette, HermesPalette.gold);
        expect(light.palette, HermesPalette.gold);
        expect(dark.accent, HermesTokens.hermesGold);
        // The original D4AF37 fails normal-size text contrast on white. Do not
        // restore the old identical-light/dark assertion: preserve the hue, not
        // an inaccessible foreground tone.
        expect(light.accent, isNot(HermesTokens.hermesGold));
        expect(
          light.accent.computeLuminance(),
          lessThan(dark.accent.computeLuminance()),
        );
        expect(
          contrastRatio(HermesTokens.hermesGold, light.surface),
          lessThan(4.5),
        );
        _expectReadable(light.accent, light.surface, 'light gold ink');
        expect(dark.onAccent, Colors.black);
        expect(light.onAccent, Colors.white);
      },
    );

    test(
      'copyWith preserves every unspecified token and supports new roles',
      () {
        final tokens = HermesTokens.dark(palette: HermesPalette.purple);
        final recolored = tokens.copyWith(
          onAccent: const Color(0xFF123456),
          accentContainer: const Color(0xFF654321),
          onAccentContainer: const Color(0xFFFEDCBA),
        );
        final before = _tokenColors(tokens);
        final after = _tokenColors(recolored);
        for (final entry in before.entries) {
          if ([
            'onAccent',
            'accentContainer',
            'onAccentContainer',
          ].contains(entry.key)) {
            expect(after[entry.key], isNot(entry.value));
          } else {
            expect(after[entry.key], entry.value, reason: entry.key);
          }
        }
        expect(recolored.onAccent, const Color(0xFF123456));
        expect(recolored.accentContainer, const Color(0xFF654321));
        expect(recolored.onAccentContainer, const Color(0xFFFEDCBA));
        expect(recolored.palette, HermesPalette.purple);
        expect(recolored.brightness, Brightness.dark);
        expect(recolored.typography, same(tokens.typography));
        expect(
          tokens.copyWith(palette: HermesPalette.cyan).palette,
          HermesPalette.cyan,
        );
        expect(
          tokens.copyWith(brightness: Brightness.light).brightness,
          Brightness.light,
        );
        expect(_tokenColors(tokens.copyWith()), before);
      },
    );

    test(
      'lerp interpolates all colors including the three new accent roles',
      () {
        final dark = HermesTokens.dark(palette: HermesPalette.purple);
        final light = HermesTokens.light(palette: HermesPalette.orange);
        final start = _tokenColors(dark);
        final end = _tokenColors(light);
        for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
          final mid = dark.lerp(light, t);
          final colors = _tokenColors(mid);
          for (final key in start.keys) {
            expect(
              colors[key],
              Color.lerp(start[key], end[key], t),
              reason: '$key at $t',
            );
          }
          expect(mid.brightness, t < 0.5 ? dark.brightness : light.brightness);
          expect(mid.palette, t < 0.5 ? dark.palette : light.palette);
          expect(
            mid.typography,
            same(t < 0.5 ? dark.typography : light.typography),
          );
        }
        expect(dark.lerp(null, 0.5), same(dark));
      },
    );
  });

  group('HermesTypography', () {
    test('the ramp is ordered and mono is a monospace family', () {
      final ramp = HermesTypography.ramp(Brightness.dark);
      expect(ramp.display.fontSize, greaterThan(ramp.title.fontSize!));
      expect(ramp.title.fontSize, greaterThan(ramp.section.fontSize!));
      expect(ramp.section.fontSize, greaterThan(ramp.body.fontSize!));
      expect(ramp.body.fontSize, greaterThan(ramp.label.fontSize!));
      expect(ramp.mono.fontFamily, isNotNull);
      expect(ramp.mono.fontFamilyFallback, contains('monospace'));
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('plain $brightness themes get a readable gold fallback', (
      tester,
    ) async {
      final tokens = await _pumpAndReadTokens(
        tester,
        ThemeData(brightness: brightness, useMaterial3: true),
      );
      expect(tokens.brightness, brightness);
      expect(tokens.palette, HermesPalette.gold);
      expect(tokens.accent, HermesTokens.forBrightness(brightness).accent);
      _expectReadable(tokens.accent, tokens.surface, 'fallback accent');
    });

    for (final palette in HermesPalette.values) {
      group('${palette.name} ${brightness.name}', () {
        late ThemeData theme;
        late HermesTokens tokens;
        late ColorScheme scheme;
        setUp(() {
          theme = hermesTheme(brightness, palette: palette);
          tokens = theme.extension<HermesTokens>()!;
          scheme = theme.colorScheme;
        });

        test('factories and Material roles agree on a complete opaque set', () {
          expect(theme.useMaterial3, isTrue);
          expect(theme.brightness, brightness);
          expect(scheme.brightness, brightness);
          expect(tokens.brightness, brightness);
          expect(tokens.palette, palette);
          expect(
            _tokenColors(tokens),
            _tokenColors(
              HermesTokens.forBrightness(brightness, palette: palette),
            ),
          );
          expect(
            _tokenColors(tokens),
            _tokenColors(
              brightness == Brightness.dark
                  ? HermesTokens.dark(palette: palette)
                  : HermesTokens.light(palette: palette),
            ),
          );
          for (final entry in _tokenColors(tokens).entries) {
            expect(entry.value.a, 1, reason: entry.key);
          }
          expect(tokens.surface, scheme.surface);
          expect(tokens.raised, scheme.surfaceContainerLow);
          expect(tokens.border, scheme.outlineVariant);
          expect(tokens.accent, scheme.primary);
          expect(tokens.onAccent, scheme.onPrimary);
          expect(tokens.accentContainer, scheme.primaryContainer);
          expect(tokens.onAccentContainer, scheme.onPrimaryContainer);
          expect(tokens.onSurface, scheme.onSurface);
          expect(tokens.muted, scheme.onSurfaceVariant);
          expect(tokens.danger, scheme.error);
        });

        test('body and muted normal-size text clear AA on every surface', () {
          final surfaces = {
            'base': tokens.surface,
            'raised': tokens.raised,
            'dim': scheme.surfaceDim,
            'bright': scheme.surfaceBright,
            'lowest': scheme.surfaceContainerLowest,
            'container': scheme.surfaceContainer,
            'high': scheme.surfaceContainerHigh,
            'highest': scheme.surfaceContainerHighest,
          };
          for (final entry in surfaces.entries) {
            _expectReadable(
              tokens.onSurface,
              entry.value,
              'body on ${entry.key}',
            );
            _expectReadable(tokens.muted, entry.value, 'muted on ${entry.key}');
          }
          _expectReadable(tokens.accent, tokens.surface, 'accent on base');
          _expectReadable(tokens.accent, tokens.raised, 'accent on raised');
          _expectReadable(
            theme.textTheme.bodyMedium!.color!,
            tokens.surface,
            'body theme',
          );
          _expectReadable(
            theme.textTheme.bodySmall!.color!,
            tokens.raised,
            'small body theme',
          );
          _expectReadable(
            theme.textTheme.labelMedium!.color!,
            tokens.raised,
            'small label theme',
          );
        });

        test('all filled, container, fixed, and inverse roles clear AA', () {
          final pairs = <String, (Color, Color)>{
            'primary': (scheme.onPrimary, scheme.primary),
            'primary container': (
              scheme.onPrimaryContainer,
              scheme.primaryContainer,
            ),
            'secondary': (scheme.onSecondary, scheme.secondary),
            'secondary container': (
              scheme.onSecondaryContainer,
              scheme.secondaryContainer,
            ),
            'tertiary': (scheme.onTertiary, scheme.tertiary),
            'tertiary container': (
              scheme.onTertiaryContainer,
              scheme.tertiaryContainer,
            ),
            'error': (scheme.onError, scheme.error),
            'error container': (scheme.onErrorContainer, scheme.errorContainer),
            'inverse': (scheme.onInverseSurface, scheme.inverseSurface),
            'primary fixed': (scheme.onPrimaryFixed, scheme.primaryFixed),
            'primary fixed dim': (
              scheme.onPrimaryFixed,
              scheme.primaryFixedDim,
            ),
            'primary fixed variant': (
              scheme.onPrimaryFixedVariant,
              scheme.primaryFixed,
            ),
            'primary fixed dim variant': (
              scheme.onPrimaryFixedVariant,
              scheme.primaryFixedDim,
            ),
            'secondary fixed': (scheme.onSecondaryFixed, scheme.secondaryFixed),
            'secondary fixed dim': (
              scheme.onSecondaryFixed,
              scheme.secondaryFixedDim,
            ),
            'secondary fixed variant': (
              scheme.onSecondaryFixedVariant,
              scheme.secondaryFixed,
            ),
            'secondary fixed dim variant': (
              scheme.onSecondaryFixedVariant,
              scheme.secondaryFixedDim,
            ),
            'tertiary fixed': (scheme.onTertiaryFixed, scheme.tertiaryFixed),
            'tertiary fixed dim': (
              scheme.onTertiaryFixed,
              scheme.tertiaryFixedDim,
            ),
            'tertiary fixed variant': (
              scheme.onTertiaryFixedVariant,
              scheme.tertiaryFixed,
            ),
            'tertiary fixed dim variant': (
              scheme.onTertiaryFixedVariant,
              scheme.tertiaryFixedDim,
            ),
          };
          for (final entry in pairs.entries) {
            _expectReadable(entry.value.$1, entry.value.$2, entry.key);
          }
          expect(tokens.onAccent, foregroundFor(tokens.accent));
        });

        test(
          'composited selected surfaces and text selection remain readable',
          () {
            for (final surface in [tokens.surface, tokens.raised]) {
              // These are the real tints used by cards, project icons, chips,
              // shell indicators, and selected rows. Measure the blended paint,
              // not the meaningless RGB channels of a transparent color.
              for (final alpha in [0.08, 0.10, 0.12, 0.14, 0.18]) {
                final selected = Color.alphaBlend(
                  tokens.accent.withValues(alpha: alpha),
                  surface,
                );
                _expectReadable(
                  tokens.accent,
                  selected,
                  'accent on $alpha tint',
                );
                _expectReadable(
                  tokens.onSurface,
                  selected,
                  'body on $alpha tint',
                );
                _expectReadable(tokens.muted, selected, 'muted on $alpha tint');
              }
              final textSelection = Color.alphaBlend(
                theme.textSelectionTheme.selectionColor!,
                surface,
              );
              _expectReadable(
                tokens.onSurface,
                textSelection,
                'selected body text',
              );
              _expectReadable(
                tokens.muted,
                textSelection,
                'selected muted text',
              );
            }
          },
        );

        test('semantic meanings and tinted status badges remain legible', () {
          expect(tokens.colorForStatus(HermesStatus.running), tokens.running);
          expect(tokens.colorForStatus(HermesStatus.blocked), tokens.blocked);
          expect(tokens.colorForStatus(HermesStatus.failed), tokens.danger);
          expect(tokens.colorForStatus(HermesStatus.completed), tokens.success);
          expect(tokens.colorForStatus(HermesStatus.idle), tokens.muted);
          expect(tokens.running, isNot(tokens.blocked));
          expect(tokens.success, isNot(tokens.danger));
          expect(tokens.blocked, isNot(tokens.warning));
          expect(
            HSLColor.fromColor(tokens.success).hue,
            inInclusiveRange(100, 165),
          );
          expect(
            HSLColor.fromColor(tokens.warning).hue,
            inInclusiveRange(30, 60),
          );
          expect(
            HSLColor.fromColor(tokens.blocked).hue,
            inInclusiveRange(20, 45),
          );
          expect(
            HSLColor.fromColor(tokens.running).hue,
            inInclusiveRange(200, 240),
          );
          final errorHue = HSLColor.fromColor(tokens.danger).hue;
          expect(
            errorHue < 25 || errorHue > 345,
            isTrue,
            reason: 'errors stay red',
          );
          for (final ink in [
            tokens.success,
            tokens.warning,
            tokens.danger,
            tokens.running,
            tokens.blocked,
            tokens.muted,
          ]) {
            for (final surface in [tokens.surface, tokens.raised]) {
              _expectReadable(ink, surface, 'semantic ink on surface');
              for (final alpha in [0.08, 0.14]) {
                final badge = Color.alphaBlend(
                  ink.withValues(alpha: alpha),
                  surface,
                );
                _expectReadable(ink, badge, 'semantic ink on $alpha badge');
                _expectReadable(
                  tokens.onSurface,
                  badge,
                  'body on $alpha status card',
                );
                _expectReadable(
                  tokens.muted,
                  badge,
                  'muted on $alpha status card',
                );
              }
              _expectReadable(
                foregroundFor(ink),
                ink,
                'filled semantic action',
              );
            }
          }
        });

        test('component states resolve matching readable foregrounds', () {
          for (final style in [
            theme.filledButtonTheme.style!,
            theme.elevatedButtonTheme.style!,
          ]) {
            for (final states in [
              _enabled,
              {WidgetState.hovered},
              {WidgetState.focused},
              {WidgetState.pressed},
            ]) {
              final background = style.backgroundColor!.resolve(states)!;
              final foreground = style.foregroundColor!.resolve(states)!;
              final overlay =
                  style.overlayColor?.resolve(states) ?? Colors.transparent;
              expect(background, tokens.accent);
              expect(foreground, tokens.onAccent);
              _expectReadable(
                foreground,
                Color.alphaBlend(overlay, background),
                'filled button $states',
              );
            }
          }
          expect(
            theme.floatingActionButtonTheme.backgroundColor,
            tokens.accent,
          );
          expect(
            theme.floatingActionButtonTheme.foregroundColor,
            tokens.onAccent,
          );
          expect(
            theme.checkboxTheme.fillColor!.resolve(_selected),
            tokens.accent,
          );
          expect(
            theme.checkboxTheme.checkColor!.resolve(_selected),
            tokens.onAccent,
          );
          final errorStates = {WidgetState.selected, WidgetState.error};
          _expectReadable(
            theme.checkboxTheme.checkColor!.resolve(errorStates)!,
            theme.checkboxTheme.fillColor!.resolve(errorStates)!,
            'error checkbox',
          );
          expect(theme.radioTheme.fillColor!.resolve(_selected), tokens.accent);
          expect(
            theme.switchTheme.trackColor!.resolve(_selected),
            tokens.accent,
          );
          expect(
            theme.switchTheme.thumbColor!.resolve(_selected),
            tokens.onAccent,
          );
          _expectReadable(
            theme.segmentedButtonTheme.style!.foregroundColor!.resolve(
              _selected,
            )!,
            theme.segmentedButtonTheme.style!.backgroundColor!.resolve(
              _selected,
            )!,
            'selected segment',
          );
          expect(
            theme.textButtonTheme.style!.foregroundColor!.resolve(_enabled),
            tokens.accent,
          );
          expect(
            theme.outlinedButtonTheme.style!.foregroundColor!.resolve(_enabled),
            tokens.accent,
          );
          expect(theme.sliderTheme.thumbColor, tokens.accent);
          _expectReadable(
            theme.sliderTheme.valueIndicatorTextStyle!.color!,
            theme.sliderTheme.valueIndicatorColor!,
            'slider value',
          );
          expect(theme.progressIndicatorTheme.color, tokens.accent);

          final indicator = theme.navigationBarTheme.indicatorColor!;
          for (final states in [_enabled, _selected]) {
            _expectReadable(
              theme.navigationBarTheme.iconTheme!.resolve(states)!.color!,
              states == _selected ? indicator : tokens.raised,
              'navigation icon',
            );
            _expectReadable(
              theme.navigationBarTheme.labelTextStyle!.resolve(states)!.color!,
              tokens.raised,
              'navigation label',
            );
            _expectReadable(
              theme.navigationDrawerTheme.labelTextStyle!
                  .resolve(states)!
                  .color!,
              states == _selected
                  ? theme.navigationDrawerTheme.indicatorColor!
                  : tokens.raised,
              'drawer label',
            );
          }
          _expectReadable(
            theme.navigationRailTheme.selectedIconTheme!.color!,
            theme.navigationRailTheme.indicatorColor!,
            'rail icon',
          );
          _expectReadable(
            theme.listTileTheme.selectedColor!,
            theme.listTileTheme.selectedTileColor!,
            'selected list tile',
          );
          _expectReadable(
            theme.chipTheme.labelStyle!.color!,
            theme.chipTheme.selectedColor!,
            'selected chip',
          );
          _expectReadable(
            theme.chipTheme.checkmarkColor!,
            theme.chipTheme.selectedColor!,
            'chip checkmark',
          );
          _expectReadable(
            theme.chipTheme.deleteIconColor!,
            theme.chipTheme.selectedColor!,
            'chip delete',
          );
        });

        test(
          'input, overlay, tooltip, and snackbar defaults match the palette',
          () {
            expect(theme.scaffoldBackgroundColor, tokens.surface);
            expect(theme.appBarTheme.backgroundColor, tokens.surface);
            expect(theme.appBarTheme.foregroundColor, tokens.onSurface);
            expect(theme.cardTheme.color, tokens.raised);
            expect(theme.bottomSheetTheme.backgroundColor, tokens.raised);
            expect(theme.bottomSheetTheme.modalBackgroundColor, tokens.raised);
            expect(theme.dialogTheme.backgroundColor, tokens.raised);
            expect(theme.popupMenuTheme.color, tokens.raised);
            expect(
              theme.menuTheme.style!.backgroundColor!.resolve(_enabled),
              tokens.raised,
            );
            expect(
              theme.dropdownMenuTheme.menuStyle!.backgroundColor!.resolve(
                _enabled,
              ),
              tokens.raised,
            );
            expect(theme.inputDecorationTheme.fillColor, tokens.raised);
            _expectReadable(
              theme.inputDecorationTheme.hintStyle!.color!,
              tokens.raised,
              'input hint',
            );
            _expectReadable(
              theme.inputDecorationTheme.labelStyle!.color!,
              tokens.raised,
              'input label',
            );
            _expectReadable(
              theme.inputDecorationTheme.errorStyle!.color!,
              tokens.raised,
              'input error',
            );
            expect(
              theme.inputDecorationTheme.focusedBorder!.borderSide.color,
              tokens.accent,
            );
            expect(
              theme.inputDecorationTheme.errorBorder!.borderSide.color,
              tokens.danger,
            );
            _expectReadable(
              theme.popupMenuTheme.labelTextStyle!.resolve(_enabled)!.color!,
              tokens.raised,
              'popup text',
            );
            _expectReadable(
              theme.dialogTheme.contentTextStyle!.color!,
              tokens.raised,
              'dialog content',
            );
            _expectReadable(
              theme.searchBarTheme.hintStyle!.resolve(_enabled)!.color!,
              theme.searchBarTheme.backgroundColor!.resolve(_enabled)!,
              'search hint',
            );
            final tooltipBackground =
                (theme.tooltipTheme.decoration! as BoxDecoration).color!;
            _expectReadable(
              theme.tooltipTheme.textStyle!.color!,
              tooltipBackground,
              'tooltip',
            );
            _expectReadable(
              theme.snackBarTheme.contentTextStyle!.color!,
              theme.snackBarTheme.backgroundColor!,
              'snackbar content',
            );
            _expectReadable(
              theme.snackBarTheme.actionTextColor!,
              theme.snackBarTheme.backgroundColor!,
              'snackbar action',
            );
            expect(theme.textSelectionTheme.cursorColor, tokens.accent);
            expect(
              theme.textSelectionTheme.selectionHandleColor,
              tokens.accent,
            );
          },
        );

        testWidgets(
          'real filled controls, icons, inputs, chips and navigation inherit the palette',
          (tester) async {
            late HermesTokens seen;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Builder(
                  builder: (context) {
                    seen = HermesTokens.of(context);
                    return Scaffold(
                      floatingActionButton: FloatingActionButton(
                        onPressed: () {},
                        child: const Icon(Icons.add, key: Key('fab-icon')),
                      ),
                      bottomNavigationBar: NavigationBar(
                        selectedIndex: 0,
                        destinations: const [
                          NavigationDestination(
                            icon: Icon(Icons.home),
                            label: 'Home',
                          ),
                          NavigationDestination(
                            icon: Icon(Icons.settings),
                            label: 'Settings',
                          ),
                        ],
                      ),
                      body: SingleChildScrollView(
                        child: Column(
                          children: [
                            FilledButton(
                              onPressed: () {},
                              child: const Text(
                                'Filled',
                                key: Key('filled-label'),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {},
                              child: const Text(
                                'Elevated',
                                key: Key('elevated-label'),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton.filled(
                                  onPressed: () {},
                                  icon: const Icon(
                                    Icons.star,
                                    key: Key('filled-icon'),
                                  ),
                                ),
                                IconButton.filledTonal(
                                  onPressed: () {},
                                  icon: const Icon(
                                    Icons.favorite,
                                    key: Key('tonal-icon'),
                                  ),
                                ),
                                Checkbox(value: true, onChanged: (_) {}),
                                Switch(value: true, onChanged: (_) {}),
                              ],
                            ),
                            SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(
                                  value: 0,
                                  label: Text('Selected'),
                                ),
                                ButtonSegment(value: 1, label: Text('Other')),
                              ],
                              selected: const {0},
                              onSelectionChanged: (_) {},
                            ),
                            const TextField(
                              decoration: InputDecoration(
                                hintText: 'Readable hint',
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('Chosen chip'),
                              selected: true,
                              onSelected: (_) {},
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(seen.palette, palette);
            expect(seen.brightness, brightness);
            for (final key in ['filled-label', 'elevated-label']) {
              final text = find.byKey(Key(key));
              final material = _coloredMaterialAbove(tester, text);
              expect(material.color, tokens.accent);
              expect(_renderedTextColor(tester, text), tokens.onAccent);
              _expectReadable(
                _renderedTextColor(tester, text)!,
                material.color!,
                key,
              );
            }
            for (final key in ['filled-icon', 'fab-icon']) {
              final icon = find.byKey(Key(key));
              final foreground = IconTheme.of(tester.element(icon)).color!;
              final background = _coloredMaterialAbove(tester, icon).color!;
              expect(foreground, tokens.onAccent);
              expect(background, tokens.accent);
              _expectReadable(foreground, background, key);
            }
            final tonal = find.byKey(const Key('tonal-icon'));
            final tonalForeground = IconTheme.of(tester.element(tonal)).color!;
            final tonalBackground = _coloredMaterialAbove(tester, tonal).color!;
            expect(tonalForeground, scheme.onSecondaryContainer);
            expect(tonalBackground, scheme.secondaryContainer);
            _expectReadable(
              tonalForeground,
              tonalBackground,
              'tonal icon button',
            );
            expect(
              _renderedTextColor(tester, find.text('Chosen chip')),
              tokens.onSurface,
            );
            expect(
              _renderedTextColor(tester, find.text('Readable hint')),
              tokens.muted,
            );
            expect(
              _renderedTextColor(tester, find.text('Selected')),
              tokens.onAccentContainer,
            );
            expect(
              _renderedTextColor(tester, find.text('Home')),
              tokens.accent,
            );
            expect(
              IconTheme.of(tester.element(find.byIcon(Icons.home))).color,
              tokens.accent,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );

        testWidgets(
          'dialog, sheet, popup and snackbar routes inherit matching surfaces',
          (tester) async {
            late BuildContext host;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Builder(
                  builder: (context) {
                    host = context;
                    return Scaffold(
                      body: PopupMenuButton<String>(
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'item',
                            child: Text('Popup content'),
                          ),
                        ],
                        child: const Text('Open popup'),
                      ),
                    );
                  },
                ),
              ),
            );
            final dialog = showDialog<void>(
              context: host,
              builder: (_) => const AlertDialog(
                title: Text('Dialog title'),
                content: Text('Dialog content'),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              _coloredMaterialAbove(tester, find.text('Dialog content')).color,
              tokens.raised,
            );
            expect(
              _renderedTextColor(tester, find.text('Dialog content')),
              tokens.onSurface,
            );
            Navigator.of(host).pop();
            await dialog;
            await tester.pumpAndSettle();

            final sheet = showModalBottomSheet<void>(
              context: host,
              builder: (_) =>
                  const SizedBox(height: 100, child: Text('Sheet content')),
            );
            await tester.pumpAndSettle();
            expect(
              _coloredMaterialAbove(tester, find.text('Sheet content')).color,
              tokens.raised,
            );
            _expectReadable(
              _renderedTextColor(tester, find.text('Sheet content'))!,
              tokens.raised,
              'sheet body',
            );
            Navigator.of(host).pop();
            await sheet;
            await tester.pumpAndSettle();

            await tester.tap(find.text('Open popup'));
            await tester.pumpAndSettle();
            expect(
              _coloredMaterialAbove(tester, find.text('Popup content')).color,
              tokens.raised,
            );
            expect(
              _renderedTextColor(tester, find.text('Popup content')),
              tokens.onSurface,
            );
            Navigator.of(host).pop();
            await tester.pumpAndSettle();

            ScaffoldMessenger.of(host).showSnackBar(
              SnackBar(
                content: const Text('Snackbar content'),
                action: SnackBarAction(label: 'Undo', onPressed: () {}),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              _coloredMaterialAbove(
                tester,
                find.text('Snackbar content'),
              ).color,
              tokens.raised,
            );
            expect(
              _renderedTextColor(tester, find.text('Snackbar content')),
              tokens.onSurface,
            );
            expect(
              _renderedTextColor(tester, find.text('Undo')),
              tokens.accent,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          },
        );
      });
    }
  }
}
