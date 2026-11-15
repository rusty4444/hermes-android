import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Ares',
      packageName: 'com.hermesagent.hermes_android',
      version: '4.0.0-rc.6',
      buildNumber: '3042',
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

  testWidgets('settings that only change the classic interface say so', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(tester.element(find.byType(HomeScreen))).push<void>(
        MaterialPageRoute(
          builder: (_) => SettingsScreen(
            connection: SavedConnection(
              id: 'classic-labels',
              label: 'Offline',
              host: 'offline.test',
              port: 8642,
              apiKey: 'test-only',
            ),
            dashboardClient: DashboardClient(
              host: 'offline.test',
              port: 9119,
              httpClient: MockClient(
                (_) async => http.Response('offline', 503),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    for (final section in ['Appearance', 'Voice', 'Session Sources']) {
      final chip = find.byKey(ValueKey('classic-only-$section'));
      await tester.scrollUntilVisible(chip, 300, scrollable: scroll);
      expect(chip, findsOneWidget, reason: section);
      expect(
        find.descendant(
          of: chip,
          matching: find.text('Classic interface only'),
        ),
        findsOneWidget,
      );
    }
    // Text size changes both interfaces, so it is not marked.
    expect(find.byKey(const ValueKey('classic-only-Text size')), findsNothing);
  });
}
