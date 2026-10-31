import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/background_work_settings.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backgroundWorkEnabled.value = true;
  });

  Widget host({
    Locale locale = const Locale('en'),
    Future<bool> Function()? open,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: BackgroundWorkSettings(openBatterySettings: open),
      ),
    ),
  );

  testWidgets('honest background controls persist an opt-out', (tester) async {
    await tester.pumpWidget(host());
    expect(find.text('Keep chats active in the background'), findsOneWidget);
    expect(
      find.textContaining('Idle connections may disconnect'),
      findsOneWidget,
    );
    expect(find.textContaining('battery and network data'), findsOneWidget);
    expect(
      find.textContaining('does not stop work on the server'),
      findsOneWidget,
    );
    expect(find.textContaining('Doze'), findsOneWidget);
    expect(find.textContaining('separate push setup'), findsOneWidget);
    expect(find.textContaining('Force stop is not supported'), findsOneWidget);
    expect(
      find.textContaining('even when optional chat notifications are off'),
      findsOneWidget,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(backgroundWorkEnabled.value, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(BackgroundWorkPrefsStore.storageKey), isFalse);
  });

  testWidgets('unavailable battery platform never claims success', (
    tester,
  ) async {
    await tester.pumpWidget(host(open: () async => false));
    await tester.ensureVisible(find.text('Battery optimisation settings'));
    await tester.tap(find.text('Battery optimisation settings'));
    await tester.pumpAndSettle();
    expect(
      find.text('Battery settings could not be opened on this device.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'battery settings tap is single-flight and only opens on request',
    (tester) async {
      final gate = Completer<bool>();
      var calls = 0;
      await tester.pumpWidget(
        host(
          open: () {
            calls++;
            return gate.future;
          },
        ),
      );
      expect(calls, 0);
      await tester.ensureVisible(find.text('Battery optimisation settings'));
      await tester.tap(find.text('Battery optimisation settings'));
      await tester.pump();
      await tester.tap(find.text('Battery optimisation settings'));
      expect(calls, 1);
      gate.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.textContaining('No exemption is requested automatically'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'late battery failure after disposal does not touch old context',
    (tester) async {
      final gate = Completer<bool>();
      await tester.pumpWidget(host(open: () => gate.future));
      await tester.ensureVisible(find.text('Battery optimisation settings'));
      await tester.tap(find.text('Battery optimisation settings'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete(false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('background settings have shipped strings for $locale', (
      tester,
    ) async {
      await tester.pumpWidget(host(locale: locale));
      final context = tester.element(find.byType(BackgroundWorkSettings));
      expect(context.l10n.background_work, isNotEmpty);
      expect(context.l10n.background_work_limits, isNotEmpty);
      expect(context.l10n.background_work_disclosure, isNotEmpty);
      expect(
        find.text(context.l10n.keep_chats_active_in_background),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'background controls remain usable when dashboard settings fail',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
      await tester.pumpAndSettle();
      unawaited(
        Navigator.of(tester.element(find.byType(HomeScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              connection: SavedConnection(
                id: 'offline-dashboard',
                label: 'Offline dashboard',
                host: '127.0.0.1',
                port: 8642,
                dashboardPortOverride: 1,
                apiKey: 'test-key',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Failed to load settings'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Failed to load settings'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Keep chats active in the background'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Voice availability can still be loading farther down the same list;
      // do not wait for its unrelated indeterminate progress animation.
      await Scrollable.ensureVisible(
        tester.element(find.text('Keep chats active in the background')),
        alignment: 0.5,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Keep chats active in the background'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(backgroundWorkEnabled.value, isFalse);
      expect(prefs.getBool(BackgroundWorkPrefsStore.storageKey), isFalse);
    },
  );
}
