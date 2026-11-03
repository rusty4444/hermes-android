import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/theme_preference.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'every stable palette ID round-trips without changing theme mode',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = ThemePreferenceStore(prefs);
      expect(ThemePreferenceStore.paletteKey, 'theme_palette');
      expect(store.readPalette(), HermesPalette.gold);

      for (final mode in ThemeMode.values) {
        await store.saveMode(mode);
        for (final palette in HermesPalette.values) {
          await store.savePalette(palette);
          expect(prefs.getString('theme_palette'), palette.name);
          expect(store.readPalette(), palette);
          expect(store.readMode(), mode);
        }
      }
    },
  );

  test('mode changes preserve the independently persisted palette', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ThemePreferenceStore(prefs);
    await store.savePalette(HermesPalette.teal);
    for (final mode in ThemeMode.values) {
      await store.saveMode(mode);
      expect(prefs.getString('theme_mode'), mode.name);
      expect(store.readPalette(), HermesPalette.teal);
    }
    await prefs.reload();
    expect(ThemePreferenceStore(prefs).readPalette(), HermesPalette.teal);
  });

  test(
    'unknown and malformed IDs fall back without overwriting storage',
    () async {
      for (final value in <Object?>[
        null,
        '',
        'future-palette',
        'Purple',
        ' purple ',
        'purple\n',
        '{"palette":"blue"}',
        42,
        0.5,
        true,
        <String>['purple'],
      ]) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'theme_palette': ?value,
          'theme_mode': 'dark',
        });
        final prefs = await SharedPreferences.getInstance();
        final store = ThemePreferenceStore(prefs);
        expect(store.readPalette(), HermesPalette.gold, reason: '$value');
        expect(prefs.get('theme_palette'), value);
        expect(store.readMode(), ThemeMode.dark);
        expect(prefs.getString('theme_mode'), 'dark');
      }
    },
  );
}
