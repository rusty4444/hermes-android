import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/theme_preference.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/theme_palette_picker.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Model the legacy plugin's documented cache-before-platform-write behaviour.
class _ControlledPreferences extends Fake implements SharedPreferences {
  _ControlledPreferences(Map<String, Object> values)
    : cache = Map.of(values),
      durable = Map.of(values);

  final Map<String, Object> cache;
  final Map<String, Object> durable;
  final List<(String, Object?)> writes = [];
  Future<bool> Function(String key, Object? value)? onWrite;

  Future<bool> _set(String key, Object? value) async {
    writes.add((key, value));
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    final accepted = await (onWrite?.call(key, value) ?? Future.value(true));
    if (accepted) {
      if (value == null) {
        durable.remove(key);
      } else {
        durable[key] = value;
      }
    }
    return accepted;
  }

  @override
  Object? get(String key) => cache[key];
  @override
  Set<String> getKeys() => cache.keys.toSet();
  @override
  String? getString(String key) => cache[key] as String?;
  @override
  List<String>? getStringList(String key) => cache[key] as List<String>?;
  @override
  bool? getBool(String key) => cache[key] as bool?;
  @override
  double? getDouble(String key) => cache[key] as double?;
  @override
  int? getInt(String key) => cache[key] as int?;
  @override
  Future<bool> setString(String key, String value) => _set(key, value);
  @override
  Future<bool> setBool(String key, bool value) => _set(key, value);
  @override
  Future<bool> setInt(String key, int value) => _set(key, value);
  @override
  Future<bool> setDouble(String key, double value) => _set(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _set(key, value);
  @override
  Future<bool> remove(String key) => _set(key, null);
  @override
  Future<void> reload() async {
    cache
      ..clear()
      ..addAll(durable);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final throwsException in [false, true]) {
    test(
      'failed writes restore palette and mode cache: exception=$throwsException',
      () async {
        final prefs = _ControlledPreferences({
          'theme_palette': 'blue',
          'theme_mode': 'dark',
        });
        prefs.onWrite = (key, value) async {
          if (value == 'green' || value == 'light') {
            if (throwsException) throw StateError('Storage unavailable');
            return false;
          }
          return true;
        };
        final store = ThemePreferenceStore(prefs);
        await expectLater(
          store.savePalette(HermesPalette.green),
          throwsStateError,
        );
        expect(store.readPalette(), HermesPalette.blue);
        await expectLater(store.saveMode(ThemeMode.light), throwsStateError);
        expect(store.readMode(), ThemeMode.dark);
        await prefs.reload();
        expect(store.readPalette(), HermesPalette.blue);
        expect(store.readMode(), ThemeMode.dark);
        expect(prefs.cache, prefs.durable);
      },
    );
  }

  test(
    'rollback restores absent and malformed values even while storage stays unavailable',
    () async {
      for (final previous in <Object?>[
        null,
        true,
        42,
        1.5,
        <String>['old'],
        <Object>['old'],
        'unknown',
      ]) {
        final prefs = _ControlledPreferences({'theme_palette': ?previous});
        prefs.onWrite = (_, _) async => false;
        await expectLater(
          ThemePreferenceStore(prefs).savePalette(HermesPalette.pink),
          throwsStateError,
        );
        expect(prefs.get('theme_palette'), previous);
        expect(ThemePreferenceStore(prefs).readPalette(), HermesPalette.gold);
        await prefs.reload();
        expect(prefs.get('theme_palette'), previous);
      }
    },
  );

  test(
    'an older rejected selection cannot roll back a newer successful selection',
    () async {
      final prefs = _ControlledPreferences({'theme_palette': 'blue'});
      final held = Completer<bool>();
      prefs.onWrite = (_, value) =>
          value == 'purple' ? held.future : Future.value(true);
      final older = ThemePreferenceStore(
        prefs,
      ).savePalette(HermesPalette.purple);
      final rejected = expectLater(older, throwsStateError);
      final newer = ThemePreferenceStore(
        prefs,
      ).savePalette(HermesPalette.green);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.writes, [('theme_palette', 'purple')]);
      held.complete(false);
      await rejected;
      await newer;
      expect(prefs.writes, [
        ('theme_palette', 'purple'),
        ('theme_palette', 'blue'),
        ('theme_palette', 'green'),
      ]);
      await prefs.reload();
      expect(ThemePreferenceStore(prefs).readPalette(), HermesPalette.green);

      prefs.onWrite = (_, value) async => value != 'red';
      await expectLater(
        ThemePreferenceStore(prefs).savePalette(HermesPalette.red),
        throwsStateError,
      );
      expect(ThemePreferenceStore(prefs).readPalette(), HermesPalette.green);
      await prefs.reload();
      expect(ThemePreferenceStore(prefs).readPalette(), HermesPalette.green);
    },
  );

  for (final paletteChange in [true, false]) {
    testWidgets(
      'held ${paletteChange ? 'palette' : 'mode'} save safely settles after root disposal',
      (tester) async {
        final prefs = _ControlledPreferences({
          'theme_palette': 'blue',
          'theme_mode': 'dark',
        });
        final save = Completer<bool>();
        prefs.onWrite = (_, _) => save.future;
        addTearDown(() {
          if (!save.isCompleted) save.complete(true);
        });
        final appKey = GlobalKey<HermesAppState>();
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(),
            child: HermesApp(
              key: appKey,
              connManager: ConnectionManager(prefs),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('home_appearance_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(paletteChange ? 'theme_palette_green' : 'theme_mode_light'),
          ),
        );
        await tester.pump();
        expect(prefs.writes, hasLength(1));
        final root = appKey.currentState!;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(root.mounted, isFalse);
        save.complete(true);
        await tester.pumpAndSettle();
        expect(prefs.cache, prefs.durable);
        expect(tester.takeException(), isNull);
      },
    );

    for (final outcome in ['success', 'rejected', 'exception']) {
      final kind = paletteChange ? 'palette' : 'mode';
      testWidgets('dismissed $kind picker refreshes root after held $outcome', (
        tester,
      ) async {
        final prefs = _ControlledPreferences({
          'theme_palette': 'blue',
          'theme_mode': 'dark',
        });
        final save = Completer<bool>();
        final rollback = Completer<bool>();
        final preferenceKey = paletteChange ? 'theme_palette' : 'theme_mode';
        final selected = paletteChange ? 'green' : 'light';
        prefs.onWrite = (key, value) {
          if (key != preferenceKey) return Future.value(true);
          return value == selected ? save.future : rollback.future;
        };
        addTearDown(() {
          if (!save.isCompleted) save.complete(false);
          if (!rollback.isCompleted) rollback.complete(true);
        });
        final appKey = GlobalKey<HermesAppState>();
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(),
            child: HermesApp(
              key: appKey,
              connManager: ConnectionManager(prefs),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        await tester.tap(find.byKey(const Key('home_appearance_button')));
        await tester.pumpAndSettle();
        final picker = tester.state(
          find.byType(paletteChange ? ThemePalettePicker : ThemeModePicker),
        );
        await tester.tap(find.byKey(Key('${preferenceKey}_$selected')));
        await tester.pump();
        expect(prefs.writes, [(preferenceKey, selected)]);
        expect(prefs.cache[preferenceKey], selected);

        if (outcome != 'success') {
          // A root rebuild can observe the plugin's optimistic cache while
          // persistence is held. Completion must reconcile that projection.
          appKey.currentState!.refreshAppearancePreferences();
          await tester.pumpAndSettle();
        }
        navigator.pop();
        await tester.pumpAndSettle();
        expect(picker.mounted, isFalse);

        if (outcome == 'exception') {
          save.completeError(StateError('Storage unavailable'));
        } else {
          save.complete(outcome == 'success');
        }
        await tester.pumpAndSettle();
        if (outcome != 'success') {
          expect(prefs.writes, [
            (preferenceKey, selected),
            (preferenceKey, paletteChange ? 'blue' : 'dark'),
          ]);
          // The root must still be reconciled when rollback itself awaits
          // storage after the picker has already gone away.
          rollback.complete(true);
          await tester.pumpAndSettle();
        }

        final tokens = HermesTokens.of(
          tester.element(find.text('No connections')),
        );
        expect(
          tokens.palette,
          paletteChange && outcome == 'success'
              ? HermesPalette.green
              : HermesPalette.blue,
        );
        expect(
          tokens.brightness,
          !paletteChange && outcome == 'success'
              ? Brightness.light
              : Brightness.dark,
        );
        expect(prefs.cache, prefs.durable);
        expect(find.byType(SnackBar), findsNothing);
        expect(
          tester.state<NavigatorState>(find.byType(Navigator).first),
          same(navigator),
        );
        expect(appKey.currentState!.mounted, isTrue);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await prefs.reload();
        expect(
          prefs.getString(preferenceKey),
          outcome == 'success' ? selected : (paletteChange ? 'blue' : 'dark'),
        );
      });
    }
  }

  testWidgets(
    'failed picker saves retain confirmed selection and root appearance',
    (tester) async {
      final prefs = _ControlledPreferences({
        'theme_palette': 'blue',
        'theme_mode': 'dark',
      });
      prefs.onWrite = (_, value) async => value != 'green' && value != 'light';
      final key = GlobalKey<HermesAppState>();
      Widget app() => MediaQuery(
        data: const MediaQueryData(),
        child: HermesApp(key: key, connManager: ConnectionManager(prefs)),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home_appearance_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme_palette_green')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(find.byKey(const Key('theme_palette_blue')))
            .properties
            .selected,
        isTrue,
      );
      final active = HermesTokens.of(
        tester.element(find.byKey(const Key('theme_palette_picker'))),
      );
      expect(active.palette, HermesPalette.blue);
      expect(active.brightness, Brightness.dark);

      await tester.tap(find.byKey(const Key('theme_mode_light')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await expectLater(
        key.currentState!.setThemePalette(HermesPalette.green),
        throwsStateError,
      );
      await expectLater(
        key.currentState!.setThemeMode(ThemeMode.light),
        throwsStateError,
      );
      await tester.pumpAndSettle();
      await prefs.reload();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final restored = HermesTokens.of(
        tester.element(find.text('No connections')),
      );
      expect(restored.palette, HermesPalette.blue);
      expect(restored.brightness, Brightness.dark);
      expect(tester.takeException(), isNull);
    },
  );
}
