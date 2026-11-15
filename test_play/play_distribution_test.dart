import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/app_update_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Play builds never contact the GitHub APK updater', () async {
    expect(AppUpdateService.isPlayBuild, isTrue);
    // This opt-in suite intentionally lives outside test/ so the ordinary
    // suite runs it only with ARES_PLAY_BUILD=true.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{}', 500);
    });
    final preferences = await SharedPreferences.getInstance();
    final service = AppUpdateService(client: client, preferences: preferences);
    final result = await service.checkForUpdate(
      currentVersion: '4.0.0',
      force: true,
    );
    expect(result.outcome, AppUpdateOutcome.failed);
    expect(await service.launchPromptRelease(currentVersion: '4.0.0'), isNull);
    expect(await service.checkOnLaunchEnabled(), isFalse);
    expect(requests, 0);
    client.close();
  });

  testWidgets('Play Settings hide GitHub updates and retain the privacy link', (
    tester,
  ) async {
    // This opt-in suite intentionally lives outside test/ so the ordinary
    // suite runs it only with ARES_PLAY_BUILD=true.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(tester.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            connection: SavedConnection(
              id: 'play',
              label: 'Play',
              host: '127.0.0.1',
              port: 8642,
              dashboardPortOverride: 1,
              apiKey: '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Privacy policy'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Check for updates'), findsNothing);
    expect(find.text('Check for updates on launch'), findsNothing);
  });
}
