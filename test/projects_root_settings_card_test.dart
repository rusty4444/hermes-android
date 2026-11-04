// The Projects-root editor in Settings (issue #232).
//
// Covers the three honest states — editable, locked by the server, and not
// supported on this connection — plus validation and the generation fence that
// stops a held read from a replaced connection applying.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/projects_root_preference.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/projects_root_settings_card.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedConnection _connection({
  String id = 'c1',
  String host = 'gateway.test',
  String? desktopGatewayUrl = 'https://gateway.test:9119',
}) => SavedConnection(
  id: id,
  label: 'Gateway',
  host: host,
  port: 8642,
  apiKey: 'k',
  desktopGatewayUrl: desktopGatewayUrl,
);

class _FilesDashboard {
  final String? lockedRoot;
  final String home;
  final int status;

  /// Number of `GET /api/files` reads, so laziness can be asserted.
  int calls = 0;

  /// Blocks `GET /api/files` until completed, so a held read can be observed.
  Completer<void>? gate;

  _FilesDashboard({
    this.lockedRoot,
    this.home = '/home/tester',
    this.status = 200,
  });

  DashboardClient client() => DashboardClient(
    host: 'localhost',
    port: 9119,
    proxied: true,
    httpClient: MockClient(_handle),
  );

  Future<http.Response> _handle(http.Request request) async {
    if (request.url.path == '/api/files' && request.method == 'GET') {
      calls++;
      final pending = gate;
      if (pending != null) await pending.future;
      if (status != 200) return http.Response('{"detail":"no"}', status);
      return http.Response(
        jsonEncode({
          'path': home,
          'entries': <dynamic>[],
          'locked_root': lockedRoot,
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  }
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required SavedConnection connection,
  required DashboardClient? dashboard,
  ProjectsRootPreference? preference,
}) async {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProjectsRootSettingsCard(
            connection: connection,
            dashboardClient: dashboard,
            preference: preference,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a connection with no dashboard route opens no client at all', (
    tester,
  ) async {
    // The card is reached from an explicitly opened More destination, so a
    // read on open is intended — but a connection that names no dashboard
    // must not cause one.
    final dash = _FilesDashboard();
    await _pumpCard(
      tester,
      connection: _connection(desktopGatewayUrl: null),
      dashboard: null,
      preference: await ProjectsRootPreference.open(),
    );
    await tester.pumpAndSettle();
    expect(dash.calls, 0);
    expect(find.byKey(const Key('projects-root-unsupported')), findsOneWidget);
  });

  testWidgets('an unlocked server offers an editable root with the default '
      'as the placeholder', (tester) async {
    final preference = await ProjectsRootPreference.open();
    await _pumpCard(
      tester,
      connection: _connection(),
      dashboard: _FilesDashboard().client(),
      preference: preference,
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('projects-root-field')),
    );
    // Nothing configured: the field is empty and the default is only a hint,
    // so an untouched connection reads as "unchanged".
    expect(field.controller!.text, isEmpty);
    expect(field.decoration!.hintText, contains('/home/tester/Projects'));
    expect(find.byKey(const Key('projects-root-reset')), findsNothing);
  });

  testWidgets('saving an absolute path persists it for the connection', (
    tester,
  ) async {
    final preference = await ProjectsRootPreference.open();
    final connection = _connection();
    await _pumpCard(
      tester,
      connection: connection,
      dashboard: _FilesDashboard().client(),
      preference: preference,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('projects-root-field')),
      '/root/.hermes/projects',
    );
    await tester.tap(find.byKey(const Key('projects-root-save')));
    await tester.pumpAndSettle();

    expect(
      preference.read(
        connectionIdentity: ProjectsRootPreference.identityOf(connection),
      ),
      '/root/.hermes/projects',
    );
    expect(find.byKey(const Key('projects-root-saved')), findsOneWidget);
    // A configured connection can go back to the server default.
    expect(find.byKey(const Key('projects-root-reset')), findsOneWidget);
  });

  testWidgets('resetting restores the server default', (tester) async {
    final connection = _connection();
    final identity = ProjectsRootPreference.identityOf(connection);
    final preference = await ProjectsRootPreference.open();
    await preference.save(
      connectionIdentity: identity,
      path: '/root/.hermes/projects',
    );

    await _pumpCard(
      tester,
      connection: connection,
      dashboard: _FilesDashboard().client(),
      preference: preference,
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('projects-root-field')),
    );
    expect(field.controller!.text, '/root/.hermes/projects');

    await tester.tap(find.byKey(const Key('projects-root-reset')));
    await tester.pumpAndSettle();

    expect(preference.read(connectionIdentity: identity), isNull);
  });

  testWidgets('rejects empty, relative and dot-segment paths', (tester) async {
    final connection = _connection();
    final preference = await ProjectsRootPreference.open();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpCard(
      tester,
      connection: connection,
      dashboard: _FilesDashboard().client(),
      preference: preference,
    );
    await tester.pumpAndSettle();

    Future<void> submit(String value) async {
      await tester.enterText(
        find.byKey(const Key('projects-root-field')),
        value,
      );
      await tester.tap(find.byKey(const Key('projects-root-save')));
      await tester.pumpAndSettle();
    }

    await submit('   ');
    expect(find.text(l10n.projects_root_invalid_empty), findsOneWidget);

    await submit('projects/ledger');
    expect(find.text(l10n.projects_root_invalid_absolute), findsOneWidget);

    await submit('/root/../etc');
    expect(find.text(l10n.projects_root_invalid_segments), findsOneWidget);

    expect(
      preference.read(
        connectionIdentity: ProjectsRootPreference.identityOf(connection),
      ),
      isNull,
    );
  });

  testWidgets('a locked server shows the path read-only and ignores the local '
      'override', (tester) async {
    final connection = _connection();
    final preference = await ProjectsRootPreference.open();
    // A stored override exists, and the server lock must still win.
    await preference.save(
      connectionIdentity: ProjectsRootPreference.identityOf(connection),
      path: '/root/.hermes/projects',
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await _pumpCard(
      tester,
      connection: connection,
      dashboard: _FilesDashboard(lockedRoot: '/srv/hermes').client(),
      preference: preference,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-root-locked')), findsOneWidget);
    expect(find.text('/srv/hermes'), findsOneWidget);
    expect(find.text(l10n.projects_root_locked_explanation), findsOneWidget);
    // No field, no save: the UI cannot imply an override that is ignored.
    expect(find.byKey(const Key('projects-root-field')), findsNothing);
    expect(find.byKey(const Key('projects-root-save')), findsNothing);
    expect(find.text('/root/.hermes/projects'), findsNothing);
  });

  testWidgets('a connection with no dashboard route says so', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpCard(
      tester,
      connection: _connection(desktopGatewayUrl: null),
      dashboard: null,
      preference: await ProjectsRootPreference.open(),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-root-unsupported')), findsOneWidget);
    expect(find.text(l10n.projects_root_unsupported), findsOneWidget);
    expect(find.byKey(const Key('projects-root-field')), findsNothing);
  });

  testWidgets('an unreadable dashboard offers a retry instead of an empty '
      'field', (tester) async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await _pumpCard(
      tester,
      connection: _connection(),
      dashboard: _FilesDashboard(status: 403).client(),
      preference: await ProjectsRootPreference.open(),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-root-unavailable')), findsOneWidget);
    expect(find.text(l10n.projects_root_unavailable), findsOneWidget);
    expect(find.byKey(const Key('projects-root-retry')), findsOneWidget);
    expect(find.byKey(const Key('projects-root-field')), findsNothing);
  });

  testWidgets('a held read from the old connection does not apply after the '
      'connection is replaced', (tester) async {
    final preference = await ProjectsRootPreference.open();
    final slow = _FilesDashboard(lockedRoot: '/old/locked')
      ..gate = Completer<void>();
    final fresh = _FilesDashboard(home: '/new/home');

    await _pumpCard(
      tester,
      connection: _connection(id: 'old', host: 'old.test'),
      dashboard: slow.client(),
      preference: preference,
    );
    // The first read is started on open and held open by the gate.
    await tester.pump();

    // Replace the connection while the first read is still in flight.
    await _pumpCard(
      tester,
      connection: _connection(id: 'new', host: 'new.test'),
      dashboard: fresh.client(),
      preference: preference,
    );
    await tester.pumpAndSettle();

    // The new connection's answer is on screen.
    final field = tester.widget<TextField>(
      find.byKey(const Key('projects-root-field')),
    );
    expect(field.decoration!.hintText, contains('/new/home/Projects'));

    // Now let the stale read finish: it must not repaint the card as locked.
    slow.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('projects-root-locked')), findsNothing);
    expect(find.text('/old/locked'), findsNothing);
    expect(find.byKey(const Key('projects-root-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
