import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'support/l10n_test_utils.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

/// The test environment's default font is Ahem (1em squares), which makes
/// label measurements meaningless. Load the real Roboto so widths match
/// devices; CJK stays on fallback boxes, which the short labels still pass.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  );
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(
      Future.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  await loader.load();
}

/// The app ships the platform font (family null); the test environment's
/// default is Ahem (1em squares). Pin the loaded Roboto so measurements
/// match devices. CJK keeps the fallback boxes, which the short labels pass.
ThemeData _testTheme(Brightness brightness) {
  final base = hermesTheme(brightness);
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Roboto'));
}

Future<void> _pumpShell(
  WidgetTester tester, {
  HermesDestination initial = HermesDestination.chats,
  ValueChanged<HermesDestination>? onDestinationChanged,
  Map<HermesDestination, int> badges = const {},
  Widget? floatingActionButton,
  Size size = const Size(360, 720),
  double textScale = 1.0,
  Brightness brightness = Brightness.dark,
  Locale? locale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: _testTheme(brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          // Keep the real view metrics; only override the text scale, so the
          // shell still sees the width the test configured.
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: HermesShell(
            initialDestination: initial,
            badges: badges,
            onDestinationChanged: onDestinationChanged,
            floatingActionButton: floatingActionButton,
            builder: (context, destination) =>
                Center(child: Text('pane:${destination.name}')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadTestL10n();
    await _loadRoboto();
  });
  group('HermesDestination', () {
    test('declares the five validated top-level destinations in order', () {
      expect(HermesDestination.values, [
        HermesDestination.chats,
        HermesDestination.crons,
        HermesDestination.projects,
        HermesDestination.activity,
        HermesDestination.more,
      ]);
    });

    test('each destination carries a label and distinct icons', () {
      final labels = <String>{};
      final icons = <IconData>{};
      for (final destination in HermesDestination.values) {
        expect(destination.label(l10n), isNotEmpty);
        labels.add(destination.label(l10n));
        icons.add(destination.icon);
        expect(destination.selectedIcon, isNotNull);
      }
      expect(labels, hasLength(HermesDestination.values.length));
      expect(icons, hasLength(HermesDestination.values.length));
    });
  });

  group('HermesShell', () {
    testWidgets('shows the initial destination pane', (tester) async {
      await _pumpShell(tester);

      expect(find.text('pane:chats'), findsOneWidget);
      expect(find.text('pane:projects'), findsNothing);
    });

    testWidgets('builds destination panes lazily', (tester) async {
      final built = <HermesDestination>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: HermesShell(
            builder: (context, destination) {
              built.add(destination);
              return Text('pane:${destination.name}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(built.toSet(), {HermesDestination.chats});

      await tester.tap(find.text(HermesDestination.crons.label(l10n)));
      await tester.pumpAndSettle();

      expect(built.toSet(), {HermesDestination.chats, HermesDestination.crons});
      expect(built, isNot(contains(HermesDestination.projects)));
    });

    testWidgets('opens on any requested destination', (tester) async {
      await _pumpShell(tester, initial: HermesDestination.activity);

      expect(find.text('pane:activity'), findsOneWidget);
    });

    testWidgets('switches panes when a destination is tapped', (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();

      expect(find.text('pane:projects'), findsOneWidget);
      expect(find.text('pane:chats'), findsNothing);
    });

    testWidgets('reports every destination change exactly once', (
      tester,
    ) async {
      final changes = <HermesDestination>[];
      await _pumpShell(tester, onDestinationChanged: changes.add);

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(changes, [HermesDestination.activity, HermesDestination.more]);
    });

    testWidgets('re-tapping the current destination does not re-notify', (
      tester,
    ) async {
      final changes = <HermesDestination>[];
      await _pumpShell(tester, onDestinationChanged: changes.add);

      await tester.tap(find.text('Chats'));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.text('pane:chats'), findsOneWidget);
    });

    testWidgets('shows an attention badge and hides zero counts', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        badges: const {
          HermesDestination.activity: 3,
          HermesDestination.projects: 0,
        },
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('caps an oversized badge instead of breaking the layout', (
      tester,
    ) async {
      await _pumpShell(tester, badges: const {HermesDestination.activity: 250});

      expect(find.text('99+'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every destination is reachable and renders its pane', (
      tester,
    ) async {
      await _pumpShell(tester);

      for (final destination in HermesDestination.values) {
        await tester.tap(find.text(destination.label(l10n)));
        await tester.pumpAndSettle();
        expect(find.text('pane:${destination.name}'), findsOneWidget);
      }
    });

    testWidgets('uses a bottom bar on a phone width', (tester) async {
      await _pumpShell(tester, size: const Size(360, 720));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('uses a side rail on a tablet width', (tester) async {
      await _pumpShell(tester, size: const Size(900, 700));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the rail keeps navigation working', (tester) async {
      await _pumpShell(tester, size: const Size(900, 700));

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      expect(find.text('pane:activity'), findsOneWidget);
    });

    testWidgets('survives a large text scale on a narrow phone', (
      tester,
    ) async {
      await _pumpShell(tester, size: const Size(320, 640), textScale: 1.8);

      expect(tester.takeException(), isNull);
      expect(find.text('pane:chats'), findsOneWidget);
    });

    testWidgets(
      'every locale keeps bar labels on one line at both breakpoints',
      (tester) async {
        // The app's largest text-size preference (1.30x) at the narrowest
        // supported widths: every shipped label must render one line and fit
        // inside its destination.
        for (final locale in AppLocalizations.supportedLocales) {
          for (final width in const [320.0, 360.0]) {
            await _pumpShell(
              tester,
              size: Size(width, 720),
              textScale: 1.3,
              locale: locale,
            );
            final l10n = await AppLocalizations.delegate.load(locale);
            for (final destination in HermesDestination.values) {
              final label = destination.label(l10n);
              // Measure the rendered paragraph, not the reserved label slot:
              // count distinct line tops of the selection boxes (a wrapped
              // label yields one top per line).
              final para = tester.renderObject<RenderParagraph>(
                find
                    .descendant(
                      of: find.byType(NavigationBar),
                      matching: find.text(label),
                    )
                    .first,
              );
              final boxes = para.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              );
              final lineTops = boxes.map((b) => b.top.round()).toSet();
              expect(
                lineTops.length,
                1,
                reason: '$locale @${width}dp: "$label" must render one line',
              );
              final textWidth = boxes.last.right - boxes.first.left;
              expect(
                textWidth,
                lessThanOrEqualTo(width / 5),
                reason:
                    '$locale @${width}dp: "$label" must fit its destination',
              );
            }
          }
        }
      },
    );

    testWidgets(
      'bar labels honour the app text-size preference within the built-in clamp',
      (tester) async {
        await _pumpShell(
          tester,
          size: const Size(360, 720),
          textScale: 1.0,
          locale: const Locale('ja'),
        );
        final at1x = tester.getSize(find.text('チャット')).height;

        await _pumpShell(
          tester,
          size: const Size(360, 720),
          textScale: 1.3,
          locale: const Locale('ja'),
        );
        final at13x = tester.getSize(find.text('チャット')).height;

        // The preference must actually scale the label (not be ignored)…
        expect(at13x, greaterThan(at1x));
        // …while the label stays a single line at the clamp.
        expect(at13x, lessThan(20));

        // Beyond the clamp the label must not grow further (still one line).
        await _pumpShell(
          tester,
          size: const Size(360, 720),
          textScale: 1.8,
          locale: const Locale('ja'),
        );
        expect(tester.getSize(find.text('チャット')).height, lessThan(20));
      },
    );

    testWidgets('renders in the light theme', (tester) async {
      await _pumpShell(tester, brightness: Brightness.light);

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('destination labels are exposed to screen readers', (
      tester,
    ) async {
      await _pumpShell(tester);

      for (final destination in HermesDestination.values) {
        expect(
          find.bySemanticsLabel(RegExp(destination.label(l10n))),
          findsWidgets,
          reason:
              '${destination.label(l10n)} must be reachable by screen reader',
        );
      }
    });

    testWidgets('a floating action button never covers the navigation bar', (
      tester,
    ) async {
      // The shell owns the bottom bar, so it must own the FAB too: one placed
      // by an outer Scaffold sits over the last destination and swallows its
      // taps.
      await _pumpShell(
        tester,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          label: const Text('New'),
        ),
      );

      await tester.tap(find.text(HermesDestination.more.label(l10n)));
      await tester.pumpAndSettle();

      expect(find.text('pane:more'), findsOneWidget);
    });

    testWidgets('a floating action button is drawn when supplied', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          label: const Text('New'),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('no floating action button is drawn by default', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('the rail also accepts a floating action button', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        size: const Size(900, 700),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          label: const Text('New'),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.text(HermesDestination.more.label(l10n)));
      await tester.pumpAndSettle();
      expect(find.text('pane:more'), findsOneWidget);
    });
  });
}
