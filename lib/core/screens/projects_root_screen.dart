/// Where new server-side Project folders are created (issue #232).
///
/// Its own More-pane destination rather than a Settings card, deliberately:
/// Settings is a device-settings screen that must build no dashboard-backed
/// editors and perform no server discovery (pinned by
/// `test/model_management_screen_test.dart`), and dashboard-backed
/// configuration in this app lives behind an explicitly opened More
/// destination — the same place Model, Skills and Memory live. Reading the
/// server's Projects root therefore only happens when the user navigates here.
library;

import 'package:flutter/material.dart';

import '../services/connection_manager.dart';
import '../widgets/projects_root_settings_card.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class ProjectsRootScreen extends StatelessWidget {
  final SavedConnection connection;

  /// Injected dashboard client; the card builds and owns its own when null.
  final DashboardClient? dashboardClient;

  const ProjectsRootScreen({
    required this.connection,
    this.dashboardClient,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.projects_root_title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProjectsRootSettingsCard(
          connection: connection,
          dashboardClient: dashboardClient,
        ),
      ],
    ),
  );
}
