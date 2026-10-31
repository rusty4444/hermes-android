/// Pins the one production call site that opens the new navigation shell.
///
/// `WorkspaceScreen` now owns a chat route of its own, and that route only
/// resumes durable turns if it is handed the application-scoped
/// [GatewayTurnApplicationController]. The session list is the only place that
/// constructs the shell, so if it drops the controller every chat opened from
/// Home silently loses turn recovery — a regression no `WorkspaceScreen` test
/// can catch, because the shell would still look correct in isolation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the workspace shell inherits the turn recovery owner', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => InertTurnApplicationSession(),
    );
    addTearDown(controller.close);

    final connection = SavedConnection(
      id: 'conn-1',
      label: 'Miniserver',
      host: 'carlos-miniserver',
      port: 8642,
      apiKey: 'secret',
    );

    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
        home: SessionListScreen(
          connection: connection,
          turnApplicationController: controller,
        ),
      ),
    );
    await tester.pump();

    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('open-workspace')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final workspace = tester.widget<WorkspaceScreen>(
      find.byType(WorkspaceScreen),
    );
    expect(workspace.connection.id, connection.id);
    expect(workspace.turnApplicationController, same(controller));
  });
}
