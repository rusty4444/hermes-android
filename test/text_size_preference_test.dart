import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/text_size_preference.dart';
import 'package:hermes_android/core/widgets/text_size_settings_card.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('System returns the exact OS scaler without a clamp or override', () {
    final osScaler = _NonlinearTextScaler();

    final result = TextSizePreference.system.applyTo(osScaler);

    expect(identical(result, osScaler), isTrue);
    expect(result.scale(16), 25);
  });

  test('explicit choices multiply each OS scale within documented limits', () {
    const base = TextScaler.linear(1.6);

    expect(TextSizePreference.small.multiplier, 0.90);
    expect(TextSizePreference.standard.multiplier, 1.0);
    expect(TextSizePreference.large.multiplier, 1.15);
    expect(TextSizePreference.extraLarge.multiplier, 1.30);
    expect(TextSizePreference.minimumExplicitMultiplier, 0.90);
    expect(TextSizePreference.maximumExplicitMultiplier, 1.30);
    expect(TextSizePreference.large.applyTo(base).scale(10), 18.4);
    expect(TextSizePreference.extraLarge.applyTo(base).scale(10), 20.8);
  });

  test(
    'persists the global non-secret preference independently of profiles',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = TextSizePreferenceStore(prefs);

      await store.save(TextSizePreference.extraLarge);

      expect(store.read(), TextSizePreference.extraLarge);
      expect(
        prefs.getString(TextSizePreference.preferenceKey),
        TextSizePreference.extraLarge.storageValue,
      );
    },
  );

  testWidgets('picker has an accessible preview and persists a selected size', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    TextSizePreference? changed;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TextSizeSettingsCard(
            preferences: prefs,
            onChanged: (preference) => changed = preference,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Text size: System',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Text size preview',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Text size'));
    await tester.pumpAndSettle();
    final extraLarge = find.text('Extra large');
    await tester.scrollUntilVisible(extraLarge, 200);
    await tester.tap(extraLarge);
    await tester.pumpAndSettle();

    expect(changed, TextSizePreference.extraLarge);
    expect(
      prefs.getString(TextSizePreference.preferenceKey),
      TextSizePreference.extraLarge.storageValue,
    );
    semantics.dispose();
  });

  testWidgets('card remains usable on compact screens at 100 to 200 percent', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: TextSizeSettingsCard(
                preferences: prefs,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Text size'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('HermesApp updates its inherited scaler immediately', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final appKey = GlobalKey<HermesAppState>();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: HermesApp(key: appKey, connManager: ConnectionManager(prefs)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.textScalerOf(
        tester.element(find.text('No connections')),
      ).scale(10),
      16,
    );

    await appKey.currentState!.setTextSizePreference(
      TextSizePreference.extraLarge,
    );
    await tester.pump();

    expect(
      MediaQuery.textScalerOf(
        tester.element(find.text('No connections')),
      ).scale(10),
      20.8,
    );
  });
}

class _NonlinearTextScaler extends TextScaler {
  @override
  double get textScaleFactor => 1.5;

  @override
  double scale(double fontSize) => fontSize < 20 ? fontSize + 9 : fontSize * 2;
}
