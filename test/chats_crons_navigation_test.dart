import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _session(String id, {String source = 'gateway', double? endedAt}) =>
    Session(
      id: id,
      title: id,
      source: source,
      model: 'test',
      messageCount: 1,
      isActive: false,
      preview: '',
      startedAt: 1,
      lastActive: 1,
      endedAt: endedAt,
    );

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required List<Session> sessions,
  HomeTurnSignals signals = HomeTurnSignals.empty,
  ValueChanged<Session>? onOpenSession,
}) async {
  tester.view.physicalSize = const Size(500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceScreen(
        connection: SavedConnection(
          id: 'chats-crons-navigation',
          label: 'Test',
          host: 'example.invalid',
          port: 8642,
          apiKey: 'test-key',
        ),
        sessionsLoader: () async => sessions,
        turnSignalsLoader: (_) async => signals,
        onOpenSession: onOpenSession,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Chats is first and Crons second, without a Home destination', () {
    expect(HermesDestination.values.map((destination) => destination.name), [
      'chats',
      'crons',
      'projects',
      'activity',
      'more',
    ]);
  });

  testWidgets('Chats opens by default with only human conversations', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      sessions: [
        _session('Human conversation'),
        _session('Scheduled run', source: 'cron'),
        _session('Kanban task', source: 'kanban'),
        _session('One-shot task', source: 'oneshot'),
      ],
    );
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    expect(
      bar.destinations.cast<NavigationDestination>().map((item) => item.label),
      ['Chats', 'Crons', 'Projects', 'Activity', 'More'],
    );
    expect(find.text('Human conversation'), findsOneWidget);
    expect(find.text('Scheduled run'), findsNothing);
    expect(find.text('Kanban task'), findsNothing);
    expect(find.text('One-shot task'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Continue working'), findsNothing);
    expect(find.text('Recently completed'), findsNothing);
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('Running now'), findsNothing);
    expect(find.byKey(kWorkspaceNewChatButtonKey), findsOneWidget);
  });

  testWidgets('Chats shows actionable work without leaking cron sessions', (
    tester,
  ) async {
    final opened = <String>[];
    await _pumpWorkspace(
      tester,
      sessions: [
        _session('Approval chat'),
        _session('Running chat'),
        _session('Cron approval', source: 'cron'),
      ],
      signals: const HomeTurnSignals(
        attention: {
          'Approval chat': 'Approve this request',
          'Cron approval': 'Cron approval',
        },
        running: {'Running chat'},
      ),
      onOpenSession: (session) => opened.add(session.id),
    );
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Running now'), findsOneWidget);
    expect(find.text('Approve this request'), findsOneWidget);
    expect(find.text('Cron approval'), findsNothing);
    await tester.tap(find.text('Approve this request'));
    await tester.pumpAndSettle();
    expect(opened, ['Approval chat']);
  });

  testWidgets('Crons lists old and ended cron chats, with its own search', (
    tester,
  ) async {
    final opened = <String>[];
    await _pumpWorkspace(
      tester,
      sessions: [
        _session('Human conversation'),
        _session('Daily report', source: 'cron'),
        _session('Old ended run', source: 'cron', endedAt: 2),
        _session('Kanban task', source: 'kanban'),
      ],
      onOpenSession: (session) => opened.add(session.id),
    );
    await tester.tap(find.text('Crons').last);
    await tester.pumpAndSettle();
    expect(find.text('Daily report'), findsOneWidget);
    expect(find.text('Old ended run'), findsOneWidget);
    expect(find.text('Human conversation'), findsNothing);
    expect(find.text('Kanban task'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Unassigned'), findsNothing);
    expect(find.byKey(kWorkspaceNewChatButtonKey), findsNothing);
    await tester.enterText(find.byKey(kWorkspaceSessionSearchKey), 'Old ended');
    await tester.pumpAndSettle();
    expect(find.text('Daily report'), findsNothing);
    await tester.tap(find.text('Old ended run'));
    await tester.pumpAndSettle();
    expect(opened, ['Old ended run']);
    await tester.tap(find.text('Chats').last);
    await tester.pumpAndSettle();
    expect(find.text('Human conversation'), findsOneWidget);
    expect(find.text('Daily report'), findsNothing);
    expect(find.text('Old ended run'), findsNothing);
  });

  testWidgets('attention disappears after a fresh read clears the signals', (
    tester,
  ) async {
    var signals = const HomeTurnSignals(
      attention: {'Approval chat': 'Approval required'},
      running: {},
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceScreen(
          connection: SavedConnection(
            id: 'attention-refresh',
            label: 'Test',
            host: 'example.invalid',
            port: 8642,
            apiKey: 'test-key',
          ),
          sessionsLoader: () async => [_session('Approval chat')],
          turnSignalsLoader: (_) async => signals,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Needs you'), findsOneWidget);
    signals = HomeTurnSignals.empty;
    final browser = tester.state<WorkspaceSessionsScreenState>(
      find.byType(WorkspaceSessionsScreen),
    );
    unawaited(browser.refresh());
    await tester.pumpAndSettle();
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('Approval chat'), findsOneWidget);
  });
}
