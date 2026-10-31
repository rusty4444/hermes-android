import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  bool? granted;
  Map<String, bool>? darwinPermissions;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    granted = false;
    darwinPermissions = {'isEnabled': false};
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'areNotificationsEnabled' ||
        'requestNotificationsPermission' => granted,
        'checkPermissions' => darwinPermissions,
        'getNotificationAppLaunchDetails' => null,
        _ => true,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Android passive checks use the real plugin query, never its request API',
    () async {
      final sink = PluginTurnNotificationSink();
      await sink.initialize();
      expect(await sink.checkPermission(), isFalse);
      granted = true;
      expect(await sink.checkPermission(), isTrue);
      granted = false;
      expect(await sink.checkPermission(), isFalse);
      granted = null;
      expect(await sink.checkPermission(), isFalse);
      expect(calls.map((c) => c.method), [
        'initialize',
        'areNotificationsEnabled',
        'areNotificationsEnabled',
        'areNotificationsEnabled',
        'areNotificationsEnabled',
      ]);
    },
  );

  test(
    'iOS initialization and passive queries cannot prompt, including provisional access',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      final sink = PluginTurnNotificationSink();
      await sink.initialize();
      final initialization = calls.single.arguments as Map;
      expect(initialization['requestAlertPermission'], isFalse);
      expect(initialization['requestBadgePermission'], isFalse);
      expect(initialization['requestSoundPermission'], isFalse);
      expect(await sink.checkPermission(), isFalse);
      darwinPermissions = {'isEnabled': true};
      expect(await sink.checkPermission(), isTrue);
      darwinPermissions = {'isEnabled': false, 'isProvisionalEnabled': true};
      expect(await sink.checkPermission(), isTrue);
      darwinPermissions = {'isEnabled': false};
      expect(await sink.checkPermission(), isFalse);
      darwinPermissions = null;
      expect(await sink.checkPermission(), isFalse);
      expect(calls.where((c) => c.method == 'requestPermissions'), isEmpty);
      expect(calls.where((c) => c.method == 'checkPermissions'), hasLength(5));
    },
  );

  testWidgets(
    'root resume and mounted Settings refresh grants and the visible denial hint without re-prompting',
    (tester) async {
      await TurnNotificationService.shared.ensureInitialized(
        requestPermission: true,
      );
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
      await tester.pumpAndSettle();

      Future<void> resumeWith(bool value) async {
        // Settings now remains complete while offline, including editable
        // controls whose lifecycle listeners enforce Android's real sequence.
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        granted = value;
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
      }

      // The root refreshes even when Settings has never been opened. It must
      // not consume the initial foreground permission prompt on a resume.
      await resumeWith(false);
      expect(TurnNotificationService.shared.permissionGranted, isFalse);
      await resumeWith(true);
      expect(TurnNotificationService.shared.permissionGranted, isTrue);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(
          1,
        ), // Initial foreground opt-in only; resumes never re-prompt.
      );

      granted = false;
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
                apiKey: 'test',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Send test notification'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final strings = AppLocalizations.of(
        tester.element(find.byType(SettingsScreen)),
      )!;
      final denialHint = find.text(strings.notifications_permission_denied);
      expect(denialHint, findsOneWidget);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(1),
      );

      await resumeWith(true);
      expect(TurnNotificationService.shared.permissionGranted, isTrue);
      expect(denialHint, findsNothing);
      await resumeWith(false);
      expect(TurnNotificationService.shared.permissionGranted, isFalse);
      expect(denialHint, findsOneWidget);

      // A test tap also refreshes the hint, without needing another resume.
      granted = true;
      await tester.ensureVisible(find.text('Send test notification'));
      await tester.tap(find.text('Send test notification'));
      await tester.pumpAndSettle();
      expect(denialHint, findsNothing);
      expect(calls.where((c) => c.method == 'show'), hasLength(1));
      ScaffoldMessenger.of(
        tester.element(find.byType(SettingsScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      granted = false;
      await tester.ensureVisible(find.text('Send test notification'));
      await tester.tap(find.text('Send test notification'));
      await tester.pumpAndSettle();
      expect(denialHint, findsOneWidget);
      expect(calls.where((c) => c.method == 'show'), hasLength(1));
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
      expect(calls.where((c) => c.method == 'cancelAll'), isEmpty);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await resumeWith(true);
      expect(tester.takeException(), isNull);
      // Widget binding verifies debug globals before the outer tearDown runs.
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
