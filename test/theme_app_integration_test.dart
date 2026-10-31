import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/config_backup.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/theme_preference.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpRoot(
  WidgetTester tester,
  SharedPreferences prefs,
  GlobalKey<HermesAppState> key,
) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(),
      child: HermesApp(key: key, connManager: ConnectionManager(prefs)),
    ),
  );
  await tester.pumpAndSettle();
}

Color _activeAccent(WidgetTester tester, Finder target) {
  return HermesTokens.of(tester.element(target)).accent;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'Hermes',
      packageName: 'com.nous.hermes',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => <Object>[],
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  testWidgets('preconnection picker updates the root and survives relaunch', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = GlobalKey<HermesAppState>();
    await _pumpRoot(tester, prefs, key);
    expect(find.text('No connections'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home_appearance_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme_mode_dark')));
    await tester.pumpAndSettle();
    for (final palette in HermesPalette.values) {
      final target = find.byKey(Key('theme_palette_${palette.name}'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(
        _activeAccent(tester, target),
        hermesTheme(Brightness.dark, palette: palette).colorScheme.primary,
      );
      expect(prefs.getString('theme_palette'), palette.name);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await prefs.reload();
    await _pumpRoot(tester, prefs, GlobalKey<HermesAppState>());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      app.darkTheme!.colorScheme.primary,
      hermesTheme(
        Brightness.dark,
        palette: HermesPalette.cyan,
      ).colorScheme.primary,
    );
    expect(
      _activeAccent(tester, find.text('No connections')),
      app.darkTheme!.colorScheme.primary,
    );
  });

  testWidgets(
    'root updates both themes for every palette without replacing Navigator or route state',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final key = GlobalKey<HermesAppState>();
      await _pumpRoot(tester, prefs, key);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: TextField(key: Key('retained_route_field')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('retained_route_field'));
      await tester.enterText(field, 'Keep this draft');
      final fieldState = tester.state(field);

      for (final palette in HermesPalette.values) {
        for (final mode in [
          ThemeMode.light,
          ThemeMode.dark,
          ThemeMode.system,
        ]) {
          await key.currentState!.setThemePalette(palette);
          await key.currentState!.setThemeMode(mode);
          await tester.pumpAndSettle();
          final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
          expect(app.themeMode, mode);
          final expectedBrightness = switch (mode) {
            ThemeMode.dark => Brightness.dark,
            ThemeMode.light => Brightness.light,
            ThemeMode.system => tester.platformDispatcher.platformBrightness,
          };
          expect(
            Theme.of(tester.element(field)).brightness,
            expectedBrightness,
          );
          expect(
            _activeAccent(tester, field),
            hermesTheme(
              expectedBrightness,
              palette: palette,
            ).colorScheme.primary,
          );
          expect(
            app.theme!.colorScheme.primary,
            hermesTheme(Brightness.light, palette: palette).colorScheme.primary,
          );
          expect(
            app.darkTheme!.colorScheme.primary,
            hermesTheme(Brightness.dark, palette: palette).colorScheme.primary,
          );
          expect(
            identical(
              tester.state<NavigatorState>(find.byType(Navigator).first),
              navigator,
            ),
            isTrue,
          );
          expect(identical(tester.state(field), fieldState), isTrue);
          expect(find.text('Keep this draft'), findsOneWidget);
          expect(navigator.canPop(), isTrue);
        }
      }
    },
  );

  testWidgets(
    'HermesHeader follows palette surfaces and keeps Cinzel branding',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final palette in HermesPalette.values) {
          final theme = hermesTheme(brightness, palette: palette);
          final tokens = theme.extension<HermesTokens>()!;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: const Scaffold(
                body: HermesHeader(subtitle: 'Header subtitle'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final header = tester.widget<Container>(
            find
                .ancestor(
                  of: find.text('HERMES'),
                  matching: find.byType(Container),
                )
                .first,
          );
          final decoration = header.decoration! as BoxDecoration;
          expect(decoration.color, tokens.surface);
          expect((decoration.border! as Border).bottom.color, tokens.accent);
          final title = tester.widget<Text>(find.text('HERMES'));
          expect(title.style!.color, tokens.accent);
          expect(title.style!.fontFamily, 'Cinzel');
          expect(title.style!.letterSpacing, 6);
          expect(
            tester.widget<Text>(find.text('Header subtitle')).style!.color,
            tokens.muted,
          );
        }
      }
    },
  );

  testWidgets(
    'Appearance remains usable while settings load and after an offline failure',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final key = GlobalKey<HermesAppState>();
      await _pumpRoot(tester, prefs, key);
      final response = Completer<http.Response>();
      final client = DashboardClient(
        host: 'offline.test',
        port: 9119,
        httpClient: MockClient((_) => response.future),
      );
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              connection: SavedConnection(
                id: 'offline',
                label: 'Offline',
                host: 'offline.test',
                port: 8642,
                apiKey: '',
              ),
              dashboardClient: client,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.byKey(const Key('theme_palette_picker')), findsOneWidget);
      await tester.tap(find.byKey(const Key('theme_palette_blue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(prefs.getString('theme_palette'), 'blue');
      expect(find.byType(SettingsScreen), findsOneWidget);

      response.complete(http.Response('offline', 503));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Failed to load settings'),
        250,
      );
      expect(find.text('Failed to load settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('theme_palette_green')),
        -250,
      );
      await Scrollable.ensureVisible(
        tester.element(find.byKey(const Key('theme_palette_green'))),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('theme_palette_green')));
      await tester.pumpAndSettle();
      expect(prefs.getString('theme_palette'), 'green');
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restored palette and mode rebuild the existing root without resetting navigation',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final key = GlobalKey<HermesAppState>();
      await _pumpRoot(tester, prefs, key);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final backup = ConfigBackup(
        createdAt: DateTime.utc(2026),
        appVersion: 'test',
        connections: const [],
        preferences: const {'theme_palette': 'pink', 'theme_mode': 'dark'},
      );
      final result = await ConfigBackupService(
        connectionManager: key.currentState!.widget.connManager,
        preferences: prefs,
      ).import(backup, mode: ConfigImportMode.merge);
      key.currentState!.refreshAppearancePreferences();
      await tester.pumpAndSettle();
      expect(result.preferencesApplied, 2);
      expect(ThemePreferenceStore(prefs).readPalette(), HermesPalette.pink);
      expect(
        _activeAccent(tester, find.text('No connections')),
        hermesTheme(
          Brightness.dark,
          palette: HermesPalette.pink,
        ).colorScheme.primary,
      );
      expect(
        identical(
          tester.state<NavigatorState>(find.byType(Navigator).first),
          navigator,
        ),
        isTrue,
      );
    },
  );
}
