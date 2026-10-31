import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/hermes_project.dart';
import 'package:hermes_android/core/services/chat_space_store.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/space_migration_preview.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

ChatSpace _space(String id, String name) =>
    ChatSpace(id: id, name: name, createdAt: 1750000000);

HermesProject _project(String id, String name) =>
    HermesProject(id: id, slug: name.toLowerCase(), name: name);

Future<void> _pump(
  WidgetTester tester,
  SpaceMigrationPlan plan, {
  VoidCallback? onDismiss,
  Future<SpaceMigrationResult> Function()? onMigrate,
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SpaceMigrationPreview(
              plan: plan,
              onDismiss: onDismiss,
              onMigrate: onMigrate,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('names the project each local space already maps onto', (
    tester,
  ) async {
    const plan = SpaceMigrationPlan([
      SpaceMigrationEntry(
        space: ChatSpace(id: 's1', name: 'ScriptHive', createdAt: 1),
        matchedProject: HermesProject(
          id: 'p1',
          slug: 'scripthive',
          name: 'ScriptHive',
        ),
        sessionCount: 4,
      ),
    ]);

    await _pump(tester, plan);

    expect(find.text('ScriptHive'), findsOneWidget);
    expect(find.textContaining('Matches'), findsOneWidget);
    expect(find.textContaining('4 chats'), findsOneWidget);
  });

  testWidgets('marks a space with no server match as a new project', (
    tester,
  ) async {
    final plan = SpaceMigrationPlan([
      SpaceMigrationEntry(
        space: _space('s1', 'C-MAY'),
        matchedProject: null,
        sessionCount: 1,
      ),
    ]);

    await _pump(tester, plan);

    expect(find.text('C-MAY'), findsOneWidget);
    expect(find.textContaining('New project'), findsOneWidget);
  });

  testWidgets('summarizes what the migration would do', (tester) async {
    final plan = SpaceMigrationPlan([
      SpaceMigrationEntry(
        space: _space('s1', 'ScriptHive'),
        matchedProject: _project('p1', 'ScriptHive'),
        sessionCount: 4,
      ),
      SpaceMigrationEntry(
        space: _space('s2', 'C-MAY'),
        matchedProject: null,
        sessionCount: 3,
      ),
    ]);

    await _pump(tester, plan);

    expect(find.textContaining('2 spaces'), findsOneWidget);
    expect(find.textContaining('7 chats'), findsOneWidget);
    expect(find.textContaining('1 project'), findsOneWidget);
  });

  testWidgets('states plainly that nothing has been changed yet', (
    tester,
  ) async {
    final plan = SpaceMigrationPlan([
      SpaceMigrationEntry(
        space: _space('s1', 'ScriptHive'),
        matchedProject: _project('p1', 'ScriptHive'),
        sessionCount: 1,
      ),
    ]);

    await _pump(tester, plan);

    expect(find.textContaining('Nothing has moved yet'), findsOneWidget);
    // The read-only preview must not offer a migrate button while the write
    // half of the migration is unimplemented.
    expect(find.widgetWithText(FilledButton, 'Migrate'), findsNothing);
  });

  testWidgets('executes the reviewed plan and reports full success', (
    tester,
  ) async {
    final plan = SpaceMigrationPlan([
      SpaceMigrationEntry(
        space: _space('s1', 'ScriptHive'),
        matchedProject: _project('p1', 'ScriptHive'),
        sessionCount: 2,
      ),
    ]);
    var calls = 0;

    await _pump(
      tester,
      plan,
      onMigrate: () async {
        calls++;
        return const SpaceMigrationResult(
          createdProjects: 0,
          alreadyLinked: 1,
          linkedSessions: 2,
          unlinkedSessions: 0,
          failures: {},
        );
      },
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Migrate'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.textContaining('2 chats migrated'), findsOneWidget);
    expect(find.text('Migration complete'), findsOneWidget);
  });

  testWidgets('reports a partial migration without hiding local data', (
    tester,
  ) async {
    final plan = SpaceMigrationPlan([
      SpaceMigrationEntry(
        space: _space('s1', 'Legacy'),
        matchedProject: null,
        sessionCount: 2,
      ),
    ]);

    await _pump(
      tester,
      plan,
      onMigrate: () async => SpaceMigrationResult(
        createdProjects: 1,
        alreadyLinked: 0,
        linkedSessions: 0,
        unlinkedSessions: 2,
        failures: {'Legacy/chat-1': StateError('unsupported')},
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Migrate'));
    await tester.pumpAndSettle();

    expect(find.text('Migration incomplete'), findsOneWidget);
    expect(
      find.textContaining('2 chats stayed in local Spaces'),
      findsOneWidget,
    );
  });

  testWidgets('an empty plan explains there is nothing to migrate', (
    tester,
  ) async {
    await _pump(tester, const SpaceMigrationPlan([]));

    expect(find.textContaining('No local spaces'), findsOneWidget);
  });

  testWidgets('dismiss reports back to the caller', (tester) async {
    var dismissed = 0;
    final plan = SpaceMigrationPlan([
      SpaceMigrationEntry(
        space: _space('s1', 'ScriptHive'),
        matchedProject: _project('p1', 'ScriptHive'),
        sessionCount: 1,
      ),
    ]);

    await _pump(tester, plan, onDismiss: () => dismissed++);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(dismissed, 1);
  });

  testWidgets('renders in the light theme at a large text scale', (
    tester,
  ) async {
    final plan = SpaceMigrationPlan([
      for (var i = 0; i < 4; i++)
        SpaceMigrationEntry(
          space: _space('s$i', 'Space number $i'),
          matchedProject: i.isEven ? _project('p$i', 'Space number $i') : null,
          sessionCount: i,
        ),
    ]);

    await _pump(tester, plan, brightness: Brightness.light, textScale: 1.8);

    expect(tester.takeException(), isNull);
    expect(find.text('Space number 0'), findsOneWidget);
  });
}
