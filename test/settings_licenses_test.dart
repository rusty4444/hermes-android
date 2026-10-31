import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _openOfflineSettings(WidgetTester tester) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
  await tester.pumpAndSettle();
  unawaited(
    Navigator.of(tester.element(find.byType(HomeScreen))).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          connection: SavedConnection(
            id: 'offline-licences',
            label: 'Offline',
            host: 'offline.test',
            port: 8642,
            apiKey: 'test-only',
          ),
          dashboardClient: DashboardClient(
            host: 'offline.test',
            port: 9119,
            httpClient: MockClient((_) async => http.Response('offline', 503)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(SettingsScreen));
  await tester.scrollUntilVisible(
    find.text(context.l10n.failed_to_load_settings),
    250,
    scrollable: _settingsScroll,
  );
  expect(find.text(context.l10n.failed_to_load_settings), findsOneWidget);
  return prefs;
}

Finder get _settingsScroll => find
    .descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<String> _openLicenses(WidgetTester tester) async {
  final title = MaterialLocalizations.of(
    tester.element(find.byType(SettingsScreen)),
  ).licensesPageTitle;
  await tester.scrollUntilVisible(
    find.text(title),
    400,
    scrollable: _settingsScroll,
  );
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(
    tester.element(find.text(title)),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await _settleLicensePage(tester);
  expect(find.byType(LicensePage), findsOneWidget);
  expect(find.text(title), findsOneWidget);
  return title;
}

Future<void> _settleLicensePage(WidgetTester tester) async {
  await tester.pump();
  // Let platform asset I/O finish outside the widget's fake clock.
  for (var attempt = 0; attempt < 500; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        !tester.binding.hasScheduledFrame) {
      break;
    }
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
}

Future<void> _expectFullNotices(
  WidgetTester tester,
  List<String> assets,
) async {
  final expected = <String>{
    for (final asset in assets)
      ...LicenseEntryWithLineBreaks(
        const [],
        File(asset).readAsStringSync(),
      ).paragraphs.map((paragraph) => paragraph.text),
  };
  final seen = <String>{};
  for (var step = 0; step < 1000; step++) {
    seen.addAll(
      tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? ''),
    );
    if (seen.containsAll(expected)) break;
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  expect(
    seen,
    containsAll(expected),
    reason: 'Full notices: ${assets.join(', ')}',
  );
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // The test binding omits Flutter's normal dependency licence collector.
    LicenseRegistry.addLicense(
      () => Stream.value(
        const LicenseEntryWithLineBreaks([
          'test_dependency',
        ], 'Existing dependency test notice'),
      ),
    );
  });

  setUp(() {
    // Do not retain asset Futures owned by a previous widget's fake-async zone.
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Hermes',
      packageName: 'com.hermesagent.hermes_android',
      version: '3.0.0-rc.1',
      buildNumber: '3000',
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

  testWidgets('About opens local licences even when dashboard settings fail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await _openOfflineSettings(tester);
    await _openLicenses(tester);
    expect(find.text('3.0.0-rc.1+3000'), findsOneWidget);

    const packages = <String, List<String>>{
      'Hermes Android': ['LICENSE'],
      'Cinzel': ['assets/fonts/OFL.txt'],
      'embedded-fcm-distributor (3.1.0)': [
        'third_party/embedded-push-notice.md',
        'third_party/embedded-push-relink.md',
        'third_party/licenses/embedded-fcm-distributor-LGPL-2.1.txt',
      ],
      'Flutter iOS scaffold (source material)': [
        'third_party/licenses/flutter-BSD-3-Clause.txt',
      ],
      'Gradle wrapper (Library build material)': [
        'third_party/licenses/Apache-2.0.txt',
        'third_party/licenses/gradle-NOTICE.txt',
      ],
      'Graphify viewer template (source material)': [
        'third_party/licenses/graphify-MIT.txt',
      ],
      'Hermes Agent message templates (source material)': [
        'third_party/licenses/hermes-agent-MIT.txt',
      ],
      'Third-party source/build materials (scope)': ['third_party/NOTICE.md'],
    };
    for (final package in packages.entries) {
      tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(package.key),
        300,
        maxScrolls: 100,
      );
      await tester.tap(find.text(package.key));
      await _settleLicensePage(tester);
      await _expectFullNotices(tester, package.value);
      await _back(tester);
    }

    // App notices supplement, rather than replace, existing dependency entries.
    tester
        .state<ScrollableState>(find.byType(Scrollable).last)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('test_dependency'),
      300,
      maxScrolls: 100,
    );
    expect(find.text('test_dependency'), findsOneWidget);
    await _back(tester);
    await tester.scrollUntilVisible(
      find.text('Check for updates on launch'),
      200,
      scrollable: _settingsScroll,
    );
    expect(find.text('Check for updates'), findsOneWidget);
    await tester.tap(find.text('Check for updates on launch'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('app_update_check_on_launch_v1'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About uses the framework-localized licence page on reopen', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openOfflineSettings(tester);
    final title = await _openLicenses(tester);
    expect(title, isNot('Licenses'));
    await _back(tester);
    expect(await _openLicenses(tester), title);
    await tester.scrollUntilVisible(
      find.text('embedded-fcm-distributor (3.1.0)'),
      300,
      maxScrolls: 100,
    );
    final tile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('embedded-fcm-distributor (3.1.0)'),
        matching: find.byType(ListTile),
      ),
    );
    final expectedCount = MaterialLocalizations.of(
      tester.element(find.byType(LicensePage)),
    ).licensesPackageDetailText(3);
    expect((tile.subtitle! as Text).data, expectedCount);
    expect(tester.takeException(), isNull);
  });
}
