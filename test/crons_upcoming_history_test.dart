// Crons = Upcoming schedules + run History (issue #259).
//
// The destination used to list cron *session rows*, so a job an agent had just
// scheduled stayed invisible until it first fired, and a tab holding only
// finished one-offs looked like nothing was scheduled. These tests pin the
// five acceptance checks from the issue:
//
//   a) a future weekly job appears in Upcoming before its first run;
//   b) the next-run time carries an explicit timezone;
//   c) finished one-off runs do not hide future jobs;
//   d) switching the saved connection cannot reuse stale rows;
//   e) an API-only connection gets an accurate capability message.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/cron_upcoming_pane.dart';
import 'package:hermes_android/core/widgets/crons_pane.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Session _cronRun(String id, {double? endedAt}) => Session(
  id: id,
  title: id,
  source: 'cron',
  model: 'test',
  messageCount: 2,
  isActive: false,
  preview: '',
  startedAt: 1,
  lastActive: 1,
  endedAt: endedAt,
);

/// A weekly job that has never run: `last_run_at` null, a future `next_run_at`
/// carrying the host's configured-zone offset, exactly as `cron/jobs.py`
/// persists it.
Map<String, Object?> _weeklyJob({
  String name = 'Weekly report',
  String? nextRun = '2026-11-09T09:00:00+11:00',
  String? lastRun,
  bool enabled = true,
  String state = 'scheduled',
  String schedule = 'every monday 9am',
  String? deliver,
}) => {
  'id': name.toLowerCase().replaceAll(' ', '-'),
  'name': name,
  'prompt': 'Summarise the week',
  'schedule': {'kind': 'cron', 'expr': '0 9 * * 1', 'display': schedule},
  'schedule_display': schedule,
  'enabled': enabled,
  'state': state,
  'paused_at': null,
  'last_run_at': lastRun,
  'next_run_at': nextRun,
  'deliver': ?deliver,
};

/// Routes the dashboard transport: cron job definitions, archived sessions,
/// and the SPA homepage the unauthenticated auth ladder scrapes.
MockClient _dashboard({
  required List<Map<String, Object?>> jobs,
  int cronStatus = 200,
  int homepageStatus = 200,
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    final path = request.url.path;
    if (path.endsWith('/api/cron/jobs')) {
      if (cronStatus != 200) return http.Response('nope', cronStatus);
      return http.Response(jsonEncode(jobs), 200);
    }
    if (path.endsWith('/api/sessions')) {
      return http.Response(jsonEncode({'sessions': [], 'total': 0}), 200);
    }
    if (path == '/' || path.isEmpty) {
      if (homepageStatus != 200) return http.Response('', homepageStatus);
      return http.Response(
        '<html>window.__HERMES_SESSION_TOKEN__="test-token";</html>',
        200,
      );
    }
    return http.Response('{}', 200);
  });
}

SavedConnection _connection({
  String id = 'crons-upcoming',
  String host = 'example.invalid',
  bool proxied = true,
}) => SavedConnection(
  id: id,
  label: 'Test',
  host: host,
  port: 8642,
  apiKey: 'k',
  dashboardProxied: proxied,
);

/// Opens the Crons destination of a real [WorkspaceScreen].
Future<void> _openCrons(
  WidgetTester tester, {
  required http.Client dashboard,
  List<Session> sessions = const [],
  SavedConnection? connection,
}) async {
  tester.view.physicalSize = const Size(500, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceScreen(
        connection: connection ?? _connection(),
        sessionsLoader: () async => sessions,
        testDashboardHttpClient: dashboard,
        turnSignalsLoader: (_) async => HomeTurnSignals.empty,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Crons').last);
  await tester.pumpAndSettle();
}

/// A minimal host for the pane alone, so connection fencing and the
/// visibility gate can be driven without the rest of the shell.
Widget _paneHost({
  required SavedConnection connection,
  required http.Client dashboard,
  bool active = true,
  Duration? refreshInterval,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: Scaffold(
    body: HermesPaneVisibility(
      active: true,
      child: CronUpcomingPane(
        connection: connection,
        testDashboardHttpClient: dashboard,
        active: active,
        refreshInterval: refreshInterval,
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a future weekly job appears in Upcoming before it has ever run',
    (tester) async {
      // History is deliberately empty: the only reason this job can be seen
      // is that Upcoming reads job definitions, not run rows.
      await _openCrons(
        tester,
        dashboard: _dashboard(jobs: [_weeklyJob()]),
        sessions: const [],
      );

      expect(find.text('Weekly report'), findsOneWidget);
      expect(find.text('every monday 9am'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Upcoming'), findsWidgets);
      // It has never run, so no last-run line is invented.
      expect(find.textContaining('Last:'), findsNothing);

      // The same destination's History view has nothing, which is exactly the
      // reported defect when it was the only view.
      await tester.tap(find.byKey(kCronsHistoryChipKey));
      await tester.pumpAndSettle();
      expect(find.text('Weekly report'), findsNothing);
    },
  );

  testWidgets('the next-run time always states which timezone it is in', (
    tester,
  ) async {
    await _openCrons(
      tester,
      dashboard: _dashboard(
        jobs: [
          _weeklyJob(nextRun: '2026-11-09T09:00:00+11:00'),
          // A legacy, zone-less timestamp must never be presented as if the
          // phone's zone were the schedule's zone.
          _weeklyJob(name: 'Zoneless job', nextRun: '2026-12-01T06:30:00'),
        ],
      ),
    );

    expect(find.text('Next: 2026-11-09 09:00 (UTC+11:00)'), findsOneWidget);
    expect(
      find.text('Next: 2026-12-01 06:30 (timezone unknown)'),
      findsOneWidget,
    );
    // No next-run line is rendered without a zone statement of some kind.
    final bare = find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final text = widget.data ?? '';
      if (!text.startsWith('Next: ')) return false;
      return !text.contains('(UTC') && !text.contains('(timezone unknown)');
    });
    expect(bare, findsNothing);
  });

  testWidgets('finished one-off runs do not hide future jobs', (tester) async {
    await _openCrons(
      tester,
      dashboard: _dashboard(
        jobs: [
          // A one-off that already fired: enabled false, no next run.
          _weeklyJob(
            name: 'Yesterday reminder',
            schedule: 'once at 2026-11-03 18:00',
            nextRun: null,
            lastRun: '2026-11-03T18:00:00+11:00',
            enabled: false,
            state: 'completed',
          ),
          _weeklyJob(name: 'Next Monday report'),
        ],
      ),
      // History holds only the finished run.
      sessions: [_cronRun('cron_yesterday_1', endedAt: 2)],
    );

    expect(find.text('Next Monday report'), findsOneWidget);
    expect(find.text('Next: 2026-11-09 09:00 (UTC+11:00)'), findsOneWidget);
    // The finished one-off is grouped, not hidden, and not called upcoming.
    expect(find.text('No next run scheduled'), findsWidgets);
    expect(find.text('Yesterday reminder'), findsOneWidget);
    expect(find.text('Last: 2026-11-03 18:00 (UTC+11:00)'), findsOneWidget);

    await tester.tap(find.byKey(kCronsHistoryChipKey));
    await tester.pumpAndSettle();
    expect(find.text('cron_yesterday_1'), findsOneWidget);
  });

  testWidgets('switching the saved connection never reuses its rows', (
    tester,
  ) async {
    final held = Completer<http.Response>();
    final dashboard = MockClient((request) async {
      if (!request.url.path.endsWith('/api/cron/jobs')) {
        return http.Response('{}', 200);
      }
      if (request.url.host == 'first.invalid') return held.future;
      return http.Response(
        jsonEncode([_weeklyJob(name: 'Second server job')]),
        200,
      );
    });

    await tester.pumpWidget(
      _paneHost(
        connection: _connection(id: 'first', host: 'first.invalid'),
        dashboard: dashboard,
      ),
    );
    await tester.pump();

    // Replace the connection while the first read is still in flight.
    await tester.pumpWidget(
      _paneHost(
        connection: _connection(id: 'second', host: 'second.invalid'),
        dashboard: dashboard,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Second server job'), findsOneWidget);

    // The first connection's answer lands late and must be fenced out.
    held.complete(
      http.Response(jsonEncode([_weeklyJob(name: 'First server job')]), 200),
    );
    await tester.pumpAndSettle();
    expect(find.text('First server job'), findsNothing);
    expect(find.text('Second server job'), findsOneWidget);
  });

  testWidgets('an API-only connection is told it needs a Dashboard', (
    tester,
  ) async {
    // No dashboard credentials and no proxy: the auth ladder scrapes the SPA
    // homepage, and an API-server-only origin answers 404 there.
    await _openCrons(
      tester,
      connection: _connection(id: 'api-only', proxied: false),
      dashboard: _dashboard(jobs: const [], homepageStatus: 404),
    );

    expect(find.text('Scheduled jobs unavailable'), findsOneWidget);
    expect(
      find.textContaining('Scheduled jobs need a Dashboard connection'),
      findsOneWidget,
    );
    // An unsupported connection must never read as an empty schedule.
    expect(find.text('No scheduled jobs'), findsNothing);
    // Nor as a fault with a retry that cannot help.
    expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
  });

  testWidgets('a dashboard without the cron route is a capability gap', (
    tester,
  ) async {
    await _openCrons(
      tester,
      dashboard: _dashboard(jobs: const [], cronStatus: 404),
    );
    expect(
      find.textContaining('Scheduled jobs need a Dashboard connection'),
      findsOneWidget,
    );
    expect(find.text('No scheduled jobs'), findsNothing);
  });

  testWidgets('an empty schedule reads as empty, not as unsupported', (
    tester,
  ) async {
    await _openCrons(tester, dashboard: _dashboard(jobs: const []));

    expect(find.text('No scheduled jobs'), findsOneWidget);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(
      find.textContaining('Scheduled jobs need a Dashboard connection'),
      findsNothing,
    );
    expect(find.text('Scheduled jobs unavailable'), findsNothing);
  });

  testWidgets('a server fault keeps a retry and is not called unsupported', (
    tester,
  ) async {
    var status = 500;
    final dashboard = MockClient((request) async {
      if (!request.url.path.endsWith('/api/cron/jobs')) {
        return http.Response('{}', 200);
      }
      if (status != 200) return http.Response('boom', status);
      return http.Response(jsonEncode([_weeklyJob()]), 200);
    });
    await tester.pumpWidget(
      _paneHost(connection: _connection(), dashboard: dashboard),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scheduled jobs unavailable'), findsOneWidget);
    expect(
      find.textContaining('Scheduled jobs need a Dashboard connection'),
      findsNothing,
    );
    status = 200;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly report'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the last schedule behind a notice', (
    tester,
  ) async {
    var status = 200;
    final dashboard = MockClient((request) async {
      if (!request.url.path.endsWith('/api/cron/jobs')) {
        return http.Response('{}', 200);
      }
      if (status != 200) return http.Response('gone', status);
      return http.Response(jsonEncode([_weeklyJob()]), 200);
    });
    await tester.pumpWidget(
      _paneHost(
        connection: _connection(),
        dashboard: dashboard,
        refreshInterval: const Duration(seconds: 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly report'), findsOneWidget);

    status = 503;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    // Stale-but-usable is labelled, never silently presented as current.
    expect(
      find.textContaining('Could not refresh the schedule'),
      findsOneWidget,
    );
    expect(find.text('Weekly report'), findsOneWidget);
    expect(find.text('Scheduled jobs unavailable'), findsNothing);
  });

  testWidgets('a delivery target is shown when the payload names one', (
    tester,
  ) async {
    await _openCrons(
      tester,
      dashboard: _dashboard(jobs: [_weeklyJob(deliver: 'telegram:4242')]),
    );
    expect(find.text('Delivers to telegram:4242'), findsOneWidget);
  });

  group('visibility-gated refresh', () {
    testWidgets('an inactive pane never reads the dashboard', (tester) async {
      var cronReads = 0;
      final dashboard = _dashboard(
        jobs: [_weeklyJob()],
        onRequest: (request) {
          if (request.url.path.endsWith('/api/cron/jobs')) cronReads++;
        },
      );
      await tester.pumpWidget(
        _paneHost(
          connection: _connection(),
          dashboard: dashboard,
          active: false,
          refreshInterval: const Duration(seconds: 1),
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(cronReads, 0);

      // Selecting it reads once, then the timer keeps it fresh.
      await tester.pumpWidget(
        _paneHost(
          connection: _connection(),
          dashboard: dashboard,
          refreshInterval: const Duration(seconds: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(cronReads, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(cronReads, greaterThanOrEqualTo(2));

      // Hiding it again stops the polling. Settle first so a read started
      // while it was still visible is counted before the quiet window, then
      // five missed ticks must add nothing at all.
      await tester.pumpWidget(
        _paneHost(
          connection: _connection(),
          dashboard: dashboard,
          active: false,
          refreshInterval: const Duration(seconds: 1),
        ),
      );
      await tester.pumpAndSettle();
      final whileHidden = cronReads;
      await tester.pump(const Duration(seconds: 5));
      expect(cronReads, whileHidden);
    });

    testWidgets('resuming the app re-reads the schedule', (tester) async {
      var cronReads = 0;
      final dashboard = _dashboard(
        jobs: [_weeklyJob()],
        onRequest: (request) {
          if (request.url.path.endsWith('/api/cron/jobs')) cronReads++;
        },
      );
      await tester.pumpWidget(
        _paneHost(connection: _connection(), dashboard: dashboard),
      );
      await tester.pumpAndSettle();
      expect(cronReads, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(cronReads, 1, reason: 'a backgrounded pane must not poll');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(cronReads, 2);
    });

    testWidgets('History stops polling while Upcoming is selected', (
      tester,
    ) async {
      var sessionReads = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceScreen(
            connection: _connection(),
            sessionsRefreshInterval: const Duration(seconds: 1),
            sessionsLoader: () async {
              sessionReads++;
              return [_cronRun('cron_old_1', endedAt: 2)];
            },
            testDashboardHttpClient: _dashboard(jobs: [_weeklyJob()]),
            turnSignalsLoader: (_) async => HomeTurnSignals.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crons').last);
      await tester.pumpAndSettle();
      final afterOpen = sessionReads;

      // Upcoming is selected, so the history browser's timer is parked.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(sessionReads, afterOpen);

      await tester.tap(find.byKey(kCronsHistoryChipKey));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(sessionReads, greaterThan(afterOpen));
    });
  });

  testWidgets('Upcoming opens first and both views stay reachable', (
    tester,
  ) async {
    await _openCrons(
      tester,
      dashboard: _dashboard(jobs: [_weeklyJob()]),
      sessions: [_cronRun('cron_old_1', endedAt: 2)],
    );
    final pane = tester.state<CronsPaneState>(find.byType(CronsPane));
    expect(pane.view, CronsView.upcoming);
    expect(find.byKey(kCronsUpcomingChipKey), findsOneWidget);
    expect(find.byKey(kCronsHistoryChipKey), findsOneWidget);

    await tester.tap(find.byKey(kCronsHistoryChipKey));
    await tester.pumpAndSettle();
    expect(pane.view, CronsView.history);
    expect(find.text('cron_old_1'), findsOneWidget);
    // The existing history controls are untouched.
    expect(find.byKey(kWorkspaceSessionSearchKey), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Archived'), findsOneWidget);

    await tester.tap(find.byKey(kCronsUpcomingChipKey));
    await tester.pumpAndSettle();
    expect(pane.view, CronsView.upcoming);
    expect(find.text('Weekly report'), findsOneWidget);
  });
}
