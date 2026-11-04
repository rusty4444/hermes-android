// Where the issue-#232 Projects-root control lives, and where it must not.
//
// It is a More destination, reached only by an explicit navigation. Settings
// stays a device-settings screen with no dashboard-backed editors and no
// server discovery — an invariant already pinned by
// test/model_management_screen_test.dart, re-asserted here from the
// Projects-root side so a future move back into Settings fails loudly.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/projects_root_screen.dart';
import 'package:hermes_android/core/screens/settings_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/more_pane.dart';
import 'package:hermes_android/core/widgets/projects_root_settings_card.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _connection = SavedConnection(
  id: 'c1',
  label: 'Gateway',
  host: 'gateway.test',
  port: 8642,
  apiKey: 'k',
  desktopGatewayUrl: 'https://gateway.test:9119',
);

/// Records every request so "Settings asks the dashboard nothing" can be
/// asserted the same way the model-management invariant does.
class _RecordingDashboard {
  final List<String> requests = [];

  DashboardClient client() => DashboardClient(
    host: 'localhost',
    port: 9119,
    proxied: true,
    httpClient: MockClient(_handle),
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (request.url.path == '/api/files') {
      return http.Response(
        jsonEncode({
          'path': '/home/tester',
          'entries': <dynamic>[],
          'locked_root': null,
        }),
        200,
      );
    }
    return http.Response('{}', 200);
  }
}

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: home,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the Projects-root screen hosts the editor and reads the root', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dash = _RecordingDashboard();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.pumpWidget(
      _app(
        ProjectsRootScreen(
          connection: _connection,
          dashboardClient: dash.client(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProjectsRootSettingsCard), findsOneWidget);
    expect(find.text(l10n.projects_root_title), findsNWidgets(2));
    expect(find.byKey(const Key('projects-root-field')), findsOneWidget);
    // Exactly one server interface, and only on a screen the user opened.
    expect(dash.requests, contains('GET /api/files'));
  });

  testWidgets('Settings builds no Projects-root editor and asks the dashboard '
      'nothing', (tester) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dash = _RecordingDashboard();
    // Settings needs the real app shell for its device-preference cards, so it
    // is reached the way the app reaches it.
    await tester.pumpWidget(
      HermesApp(
        connManager: ConnectionManager(await SharedPreferences.getInstance()),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(tester.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            connection: _connection,
            dashboardClient: dash.client(),
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
    for (var i = 0; i < 12; i++) {
      expect(find.byType(ProjectsRootSettingsCard), findsNothing);
      expect(find.byKey(const Key('projects-root-card')), findsNothing);
      await tester.drag(scroll, const Offset(0, -350));
      await tester.pump(const Duration(seconds: 1));
    }
    // Settings must cost nothing: no dashboard traffic from merely opening or
    // scrolling it.
    expect(dash.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test(
    'the Projects-root destination is dashboard-gated in the More pane',
    () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      final online = buildMoreSections(dashboardReachable: true, l10n: l10n)
          .expand((section) => section.entries)
          .singleWhere((entry) => entry.id == 'projects-root');
      expect(online.title, l10n.projects_root_title);
      expect(online.subtitle, l10n.projects_root_more_subtitle);
      expect(online.availability, MoreEntryAvailability.available);

      // No dashboard route: disabled with a reason, never silently missing.
      final offline = buildMoreSections(dashboardReachable: false, l10n: l10n)
          .expand((section) => section.entries)
          .singleWhere((entry) => entry.id == 'projects-root');
      expect(offline.availability, MoreEntryAvailability.unavailable);
      expect(offline.unavailableReason, isNotEmpty);
      expect(offline.isSelectable, isFalse);
    },
  );

  test('every locale labels the Projects-root destination', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      final entry = buildMoreSections(dashboardReachable: true, l10n: l10n)
          .expand((section) => section.entries)
          .singleWhere((e) => e.id == 'projects-root');
      expect(entry.title.trim(), isNotEmpty, reason: '$locale');
      expect(entry.subtitle.trim(), isNotEmpty, reason: '$locale');
    }
  });
}
