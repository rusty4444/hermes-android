import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/core/widgets/hermes_system_ui.dart';
import 'package:hermes_android/main.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';

class _ImageFiles extends Fake implements RemoteFilesDataSource {
  @override
  Future<RemoteFileDownload> download(String path) async => RemoteFileDownload(
    filename: 'fixture.png',
    bytes: image.encodePng(image.Image(width: 2, height: 2)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'all palettes keep app status bars and OS-compatible navigation bars readable',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final key = GlobalKey<HermesAppState>();
      await tester.pumpWidget(
        HermesApp(key: key, connManager: ConnectionManager(prefs)),
      );
      await tester.pumpAndSettle();
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      for (final palette in HermesPalette.values) {
        for (final brightness in Brightness.values) {
          tester.platformDispatcher.platformBrightnessTestValue =
              brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark;
          await key.currentState!.setThemePalette(palette);
          await key.currentState!.setThemeMode(
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          );
          await tester.pumpAndSettle();
          final tokens = HermesTokens.of(
            tester.element(find.text('No connections')),
          );
          final style = SystemChrome.latestStyle!;
          final expectedIcons = brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark;
          expect(tokens.palette, palette);
          expect(tokens.brightness, brightness);
          final nativeBrightness = tester.platformDispatcher.platformBrightness;
          final navigationScheme = hermesTheme(
            nativeBrightness,
            palette: palette,
          ).colorScheme;
          expect(style.systemNavigationBarColor, navigationScheme.surface);
          expect(
            style.systemNavigationBarDividerColor,
            navigationScheme.surface,
          );
          expect(
            style.systemNavigationBarIconBrightness,
            nativeBrightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          );
          expect(style.statusBarIconBrightness, expectedIcons);
          expect(style.systemNavigationBarContrastEnforced, isTrue);
          expect(style.systemStatusBarContrastEnforced, isFalse);
        }
      }
    },
  );

  testWidgets(
    'button navigation owns an OS-readable palette surface; gestures stay transparent',
    (tester) async {
      for (final osBrightness in Brightness.values) {
        for (final gestures in [false, true]) {
          final appBrightness = osBrightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark;
          await tester.pumpWidget(
            MaterialApp(
              theme: hermesTheme(appBrightness, palette: HermesPalette.purple),
              home: MediaQuery(
                data: MediaQueryData(
                  platformBrightness: osBrightness,
                  viewPadding: EdgeInsets.only(bottom: gestures ? 24 : 48),
                  // Android 15 reports a bottom system-gesture inset even in
                  // three-button mode. Only gesture back-navigation adds sides.
                  systemGestureInsets: EdgeInsets.fromLTRB(
                    gestures ? 24 : 0,
                    0,
                    gestures ? 24 : 0,
                    gestures ? 24 : 48,
                  ),
                ),
                child: const HermesSystemUi(child: Scaffold()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final backdrop = find.byKey(
            const Key('hermes_system_navigation_surface'),
          );
          expect(backdrop, gestures ? findsNothing : findsOneWidget);
          if (!gestures) {
            expect(
              tester.widget<ColoredBox>(backdrop).color,
              hermesTheme(
                osBrightness,
                palette: HermesPalette.purple,
              ).colorScheme.surface,
            );
          }
          final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find
                .descendant(
                  of: find.byType(HermesSystemUi),
                  matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
                )
                .first,
          );
          expect(region.value.systemNavigationBarContrastEnforced, gestures);
        }
      }
    },
  );

  testWidgets(
    'fullscreen media overrides light app bars then restores them on close',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', 'light');
      await prefs.setString('theme_palette', 'purple');
      final key = GlobalKey<HermesAppState>();
      await tester.pumpWidget(
        HermesApp(key: key, connManager: ConnectionManager(prefs)),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              body: Center(
                child: MediaArtifactCard(
                  ref: const MediaTagRef(path: '/fixture.png'),
                  filesClient: () => _ImageFiles(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.dark,
      );
      await tester.tap(find.text('fixture.png'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.dark,
      );
      expect(
        SystemChrome.latestStyle!.statusBarIconBrightness,
        Brightness.light,
      );
      expect(
        tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
        Colors.black,
      );
      expect(
        SystemChrome.latestStyle!.systemNavigationBarContrastEnforced,
        isTrue,
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(
        SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
        Brightness.dark,
      );
      expect(
        SystemChrome.latestStyle!.systemNavigationBarColor,
        hermesTheme(
          Brightness.light,
          palette: HermesPalette.purple,
        ).colorScheme.surface,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
