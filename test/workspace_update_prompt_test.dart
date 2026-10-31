// The launch-time update prompt, end to end: the shell asks, the service
// answers, and the prompt shows only when there is something to show.
//
// The service is the real one, driven by a fake GitHub; only the installed
// version is stubbed, because package_info has no platform channel in tests.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/android_share_intent_service.dart';
import 'package:hermes_android/core/services/app_update_service.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedConnection _connection() => SavedConnection(
  id: 'conn-update',
  label: 'Miniserver',
  host: '127.0.0.1',
  port: 8642,
  apiKey: '',
);

String _releaseJson(String tag) =>
    '{"tag_name":"$tag","name":"Hermes Android $tag","body":"Notes.","'
    'html_url":"https://github.com/rusty4444/hermes-android/releases/tag/$tag",'
    '"draft":false,"published_at":"2026-10-15T09:30:00Z"}';

/// Pumps the shell as the app opens it for a plain launch.
Future<void> pumpLaunch(
  WidgetTester tester, {
  required AppUpdateService service,
  Future<String?> Function()? installedVersion,
  AndroidSharePayload? sharedPayload,
  String? sharedText,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceScreen(
        connection: _connection(),
        sessionsLoader: () async => const <Session>[],
        updateService: service,
        installedVersionLoader: installedVersion ?? () async => '2.1.19',
        initialSharedPayload: sharedPayload,
        initialSharedText: sharedText,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Simulates the *next* launch: unmounting the shell first drops its State, so
/// the launch hook runs again instead of being skipped by element reuse.
Future<void> relaunch(
  WidgetTester tester, {
  required AppUpdateService service,
}) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pumpAndSettle();
  await pumpLaunch(tester, service: service);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a plain launch prompts when a newer release is published', (
    tester,
  ) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.20'), 200),
      ),
    );

    await pumpLaunch(tester, service: service);

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Hermes Android v2.1.20'), findsOneWidget);
    expect(find.text('Version 2.1.20'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('dismissing with Later asks again at the next launch', (
    tester,
  ) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.20'), 200),
      ),
    );
    await pumpLaunch(tester, service: service);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);

    await relaunch(tester, service: service);

    expect(find.text('Update available'), findsOneWidget);
  });

  testWidgets('skipping a version silences it at the next launch', (
    tester,
  ) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.20'), 200),
      ),
    );
    await pumpLaunch(tester, service: service);
    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();
    expect(await service.skippedVersion(), '2.1.20');

    await relaunch(tester, service: service);

    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('no prompt when the install is already current', (tester) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.19'), 200),
      ),
    );

    await pumpLaunch(tester, service: service);

    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('no prompt when the installed version is unreadable', (
    tester,
  ) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.20'), 200),
      ),
    );

    await pumpLaunch(
      tester,
      service: service,
      installedVersion: () async => null,
    );

    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('a share launch is not interrupted by the prompt', (
    tester,
  ) async {
    final service = AppUpdateService(
      client: MockClient(
        (request) async => http.Response(_releaseJson('v2.1.20'), 200),
      ),
    );

    await pumpLaunch(
      tester,
      service: service,
      sharedPayload: const AndroidSharePayload(text: 'https://example.com'),
    );

    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('a late release response does not interrupt a pushed route', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final service = AppUpdateService(
      client: MockClient((request) => response.future),
    );
    await pumpLaunch(tester, service: service);

    Navigator.of(tester.element(find.byType(WorkspaceScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Current task')),
      ),
    );
    await tester.pumpAndSettle();
    response.complete(http.Response(_releaseJson('v2.1.20'), 200));
    await tester.pumpAndSettle();

    expect(find.text('Current task'), findsOneWidget);
    expect(find.text('Update available'), findsNothing);
  });
}
