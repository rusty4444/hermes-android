import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/chat_density_preference.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('update controls remain available if dashboard settings fail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
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
              apiKey: 'test-only',
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
      find.text('Check for updates on launch'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Check for updates on launch'), findsOneWidget);
    await tester.tap(find.text('Check for updates on launch'));
    await tester.pumpAndSettle();
    expect(prefs.getBool('app_update_check_on_launch_v1'), isFalse);
  });

  testWidgets('chat density remains usable if dashboard settings fail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    chatDensitySelection.value = ChatDensity.comfortable;
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
      find.text('Appearance'),
      -250,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Appearance'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Chat density'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Chat density')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat density'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(prefs.getString(ChatDensity.preferenceKey), 'compact');
    expect(chatDensitySelection.value, ChatDensity.compact);
  });
}
