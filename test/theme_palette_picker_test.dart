import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/theme_preference.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/theme_palette_picker.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _pickerApp(
  SharedPreferences prefs, {
  VoidCallback? onChanged,
  double scale = 1,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: hermesTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ThemeAppearanceSettings(
          preferences: prefs,
          onChanged: onChanged,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets(
    'all ten labeled swatches select, announce selection and persist',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      var changes = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_pickerApp(prefs, onChanged: () => changes++));
      await tester.pumpAndSettle();
      expect(HermesPalette.values, hasLength(10));

      for (final palette in HermesPalette.values) {
        final target = find.byKey(Key('theme_palette_${palette.name}'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();

        expect(ThemePreferenceStore(prefs).readPalette(), palette);
        final swatch = tester.widget<Semantics>(target);
        expect(swatch.properties.button, isTrue);
        expect(swatch.properties.selected, isTrue);
        expect(swatch.properties.label, isNotEmpty);
        expect(swatch.properties.onTap, isNotNull);
        expect(
          find.descendant(of: target, matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        final selected = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'theme_palette_',
              ) &&
              widget.properties.selected == true,
        );
        expect(selected, findsOneWidget);
      }
      expect(changes, 10);
      semantics.dispose();
    },
  );

  testWidgets('mode controls and palette selection remain independent', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_pickerApp(prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme_palette_purple')));
    await tester.pumpAndSettle();

    for (final mode in ThemeMode.values) {
      final modeChoice = find.byKey(Key('theme_mode_${mode.name}'));
      await tester.ensureVisible(modeChoice);
      await tester.tap(modeChoice);
      await tester.pumpAndSettle();
      expect(ThemePreferenceStore(prefs).readMode(), mode);
      expect(ThemePreferenceStore(prefs).readPalette(), HermesPalette.purple);
    }
  });

  testWidgets('all swatches are usable on compact screens with large text', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final scale in [1.0, 1.6, 2.0]) {
      await tester.pumpWidget(_pickerApp(prefs, scale: scale));
      await tester.pumpAndSettle();
      for (final palette in HermesPalette.values) {
        final target = find.byKey(Key('theme_palette_${palette.name}'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(ThemePreferenceStore(prefs).readPalette(), palette);
      }
      expect(tester.takeException(), isNull);
    }
  });
}
