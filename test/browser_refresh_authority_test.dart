import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> row(
  String id,
  String title, {
  String source = 'gateway',
  bool archived = false,
}) => {
  'id': id,
  'title': title,
  'source': source,
  'started_at': 1,
  'last_active': 1,
  'archived': archived,
  'is_active': false,
};
http.Response page(List<Map<String, Object?>> rows) =>
    http.Response(jsonEncode({'data': rows, 'has_more': false}), 200);
http.Response archives(List<Map<String, Object?>> rows, int total) =>
    http.Response(jsonEncode({'sessions': rows, 'total': total}), 200);

Future<void> frames(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> pumpWorkspace(
  WidgetTester tester, {
  Future<List<Session>> Function()? sessions,
  http.Client? active,
  required http.Client dashboard,
}) async {
  tester.view.physicalSize = const Size(600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: WorkspaceScreen(
        connection: SavedConnection(
          id: 'spec-review',
          label: 'Test',
          host: 'fixture',
          port: 8642,
          apiKey: 'fixture-key',
          dashboardProxied: true,
        ),
        sessionsLoader: sessions,
        testSessionsHttpClient: active,
        testDashboardHttpClient: dashboard,
        turnSignalsLoader: (_) async => HomeTurnSignals.empty,
      ),
    ),
  );
  await frames(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('post-rename Chats refresh cannot reuse an older Crons scan', (
    tester,
  ) async {
    var savedTitle = 'Original chat';
    var scans = 0;
    final held = Completer<http.Response>();
    addTearDown(() {
      if (!held.isCompleted) held.complete(page([]));
    });
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        savedTitle = (jsonDecode(request.body) as Map)['title'] as String;
        return http.Response(
          jsonEncode({'session': row('human', savedTitle)}),
          200,
        );
      }
      final limit = request.url.queryParameters['limit'];
      final offset = request.url.queryParameters['offset'];
      if (limit == '5') {
        scans++;
        return page([
          row('human', savedTitle),
          row('cron', 'Cron run', source: 'cron'),
        ]);
      }
      if (offset == '0') {
        return page([
          row('human', savedTitle),
          row('cron', 'Cron run', source: 'cron'),
        ]);
      }
      if (scans == 2) return held.future;
      return page([]);
    });
    await pumpWorkspace(
      tester,
      active: client,
      dashboard: MockClient((_) async => archives([], 0)),
    );
    expect(scans, 1);
    await tester.tap(find.text('Crons').last);
    await frames(tester);
    expect(scans, 2);
    await tester.tap(find.text('Chats').last);
    await frames(tester);
    await tester.tap(find.byTooltip('Chat actions'));
    await frames(tester);
    await tester.tap(find.text('Rename'));
    await frames(tester);
    await tester.enterText(find.byType(TextField).last, 'Confirmed rename');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await frames(tester);
    expect(savedTitle, 'Confirmed rename');
    expect(find.text('Confirmed rename'), findsOneWidget);
    final browser = tester.state<WorkspaceSessionsScreenState>(
      find.byType(WorkspaceSessionsScreen),
    );
    final refreshed = browser.refresh();
    await frames(tester);
    expect(find.text('Confirmed rename'), findsOneWidget);
    expect(
      scans,
      3,
      reason: 'a post-mutation refresh starts a fresh physical scan',
    );
    held.complete(page([]));
    await frames(tester);
    await refreshed;
    expect(
      find.text('Confirmed rename'),
      findsOneWidget,
      reason:
          'a refresh begun after a confirmed rename must not restore an older physical snapshot',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('archive retry runs independently of a held active-history scan', (
    tester,
  ) async {
    final active = Completer<http.Response>();
    addTearDown(() {
      if (!active.isCompleted) active.complete(page([]));
    });
    final activeClient = MockClient((request) async {
      if (request.url.queryParameters['limit'] == '5' ||
          request.url.queryParameters['offset'] == '0') {
        return page([row('live', 'Live run', source: 'cron')]);
      }
      return active.future;
    });
    var archiveCalls = 0;
    var fail = true;
    final dashboard = MockClient((request) async {
      archiveCalls++;
      if (fail) return http.Response('offline', 503);
      return archives([
        row('archive', 'Recovered archive', source: 'cron', archived: true),
      ], 1);
    });
    await pumpWorkspace(tester, active: activeClient, dashboard: dashboard);
    await tester.tap(find.text('Crons').last);
    await frames(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await frames(tester);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    final beforeRetry = archiveCalls;
    fail = false;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await frames(tester);
    final afterRetry = archiveCalls;
    expect(find.text('Recovered archive'), findsOneWidget);
    active.complete(page([]));
    await frames(tester);
    expect(
      afterRetry,
      greaterThan(beforeRetry),
      reason:
          'archive Retry must start a new archive request independently of active history',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recovered archive survives the old aggregate final snapshot', (
    tester,
  ) async {
    final active = Completer<http.Response>();
    addTearDown(() {
      if (!active.isCompleted) active.complete(page([]));
    });
    final activeClient = MockClient((request) async {
      if (request.url.queryParameters['limit'] == '5' ||
          request.url.queryParameters['offset'] == '0') {
        return page([row('live', 'Live run', source: 'cron')]);
      }
      return active.future;
    });
    var failed = true;
    var calls = 0;
    final recovered = [
      for (var i = 0; i < 7; i++)
        row(
          'archive-$i',
          'Recovered archive $i',
          source: 'cron',
          archived: true,
        ),
    ];
    await pumpWorkspace(
      tester,
      active: activeClient,
      dashboard: MockClient((_) async {
        calls++;
        if (failed) return http.Response('offline', 503);
        return archives(recovered, recovered.length);
      }),
    );
    await tester.tap(find.text('Crons').last);
    await frames(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await frames(tester);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    failed = false;
    final before = calls;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await frames(tester);
    expect(calls, greaterThan(before));
    expect(find.text('Recovered archive 0'), findsOneWidget);
    expect(find.text('Recovered archive 6'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    active.complete(page([]));
    await frames(tester);
    expect(find.text('Recovered archive 0'), findsOneWidget);
    expect(find.text('Recovered archive 6'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late old Crons scan cannot rewrite Activity title cache', (
    tester,
  ) async {
    var title = 'Original chat';
    var scans = 0;
    final old = Completer<http.Response>();
    addTearDown(() {
      if (!old.isCompleted) old.complete(page([]));
    });
    final snapshots = <Map<String, String>>[];
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        title = (jsonDecode(request.body) as Map)['title'] as String;
        return http.Response(jsonEncode({'session': row('human', title)}), 200);
      }
      if (request.url.queryParameters['limit'] == '5') {
        scans++;
        return page([
          row('human', title),
          row('cron', 'Cron run', source: 'cron'),
        ]);
      }
      if (request.url.queryParameters['offset'] == '0') {
        return page([
          row('human', title),
          row('cron', 'Cron run', source: 'cron'),
        ]);
      }
      if (scans == 2) return old.future;
      return page([]);
    });
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceScreen(
          connection: SavedConnection(
            id: 'spec-title-cache',
            label: 'Test',
            host: 'fixture',
            port: 8642,
            apiKey: 'test-key',
            dashboardProxied: true,
          ),
          testSessionsHttpClient: client,
          testDashboardHttpClient: MockClient((_) async => archives([], 0)),
          turnSignalsLoader: (_) async => HomeTurnSignals.empty,
          activityFeedLoader: (_, titles) async {
            snapshots.add(Map.of(titles));
            return const ActivityFeed(
              groups: [],
              blockedCount: 0,
              runningCount: 0,
            );
          },
        ),
      ),
    );
    await frames(tester);
    await tester.tap(find.text('Crons').last);
    await frames(tester);
    expect(scans, 2);
    await tester.tap(find.text('Chats').last);
    await frames(tester);
    await tester.tap(find.byTooltip('Chat actions'));
    await frames(tester);
    await tester.tap(find.text('Rename'));
    await frames(tester);
    await tester.enterText(find.byType(TextField).last, 'Confirmed rename');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await frames(tester);
    final fresh = tester
        .state<WorkspaceSessionsScreenState>(
          find.byType(WorkspaceSessionsScreen),
        )
        .refresh();
    await frames(tester);
    await fresh;
    expect(scans, 3);
    old.complete(page([row('human', 'Original chat')]));
    await frames(tester);
    await tester.tap(find.text('Activity').last);
    await frames(tester);
    expect(snapshots, isNotEmpty);
    expect(snapshots.last['human'], 'Confirmed rename');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'explicit Archived refresh must not finish on pre-refresh physical snapshot',
    (tester) async {
      final held = Completer<http.Response>();
      addTearDown(() {
        if (!held.isCompleted) held.complete(archives([], 0));
      });
      var dashboardCalls = 0;
      final original = row(
        'original-archive',
        'Original archived run',
        source: 'cron',
        archived: true,
      );
      final newlyPersisted = row(
        'new-archive',
        'Newly persisted archived run',
        source: 'cron',
        archived: true,
      );
      final dashboard = MockClient((request) async {
        dashboardCalls++;
        if (dashboardCalls == 1) return held.future;
        return archives([original, newlyPersisted], 2);
      });
      await pumpWorkspace(
        tester,
        sessions: () async => [],
        dashboard: dashboard,
      );
      await tester.tap(find.text('Crons').last);
      await frames(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await frames(tester);
      expect(dashboardCalls, 1);
      final refresh = tester
          .state<WorkspaceSessionsScreenState>(
            find.byType(WorkspaceSessionsScreen),
          )
          .refresh();
      await frames(tester);
      // The first response captured the database before the new row existed.
      // An explicit refresh after that change must eventually perform fresh I/O.
      held.complete(archives([original], 1));
      await frames(tester);
      await refresh;
      expect(
        dashboardCalls,
        greaterThan(1),
        reason:
            'refresh must include an archive read started after the refresh request, not just join the initial old flight',
      );
      expect(find.text('Newly persisted archived run'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
