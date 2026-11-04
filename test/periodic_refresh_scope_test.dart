// Request-level regressions for issue #149: the ordinary launcher configures
// a 10-second visible-pane refresh whose aggregate load used to include the
// dashboard's `archived=only` paging even while a non-archived filter was
// selected. Every assertion here counts HTTP requests, because the defect is
// repeated traffic, not a wrong pixel.
//
// No device or server transfer volume is measured or claimed anywhere in this
// file: these are request counts observed through MockClient.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_refresh_authority_test.dart' as fixture;

/// The cadence `main.dart` hands the ordinary launcher's WorkspaceScreen.
const _interval = Duration(seconds: 10);

/// Counts the physical reads each authority performs.
class _Traffic {
  /// `limit=5` previews: one per physical active-history scan.
  int activeScans = 0;

  /// Every `archived=only` page the dashboard router is asked for.
  int archivePages = 0;
}

bool _isArchiveRequest(http.BaseRequest request) =>
    request.url.queryParameters['archived'] == 'only';

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required String connectionId,
  required http.Client active,
  required http.Client dashboard,
  Duration? interval = _interval,
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
          id: connectionId,
          label: 'Test',
          host: 'fixture',
          port: 8642,
          apiKey: 'fixture-key',
          dashboardProxied: true,
        ),
        sessionsRefreshInterval: interval,
        testSessionsHttpClient: active,
        testDashboardHttpClient: dashboard,
        turnSignalsLoader: (_) async => HomeTurnSignals.empty,
      ),
    ),
  );
  await fixture.frames(tester);
}

/// Fires [count] visible-pane ticks and lets each one settle.
Future<void> _ticks(WidgetTester tester, int count) async {
  for (var tick = 0; tick < count; tick++) {
    await tester.pump(_interval);
    await fixture.frames(tester);
  }
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await fixture.frames(tester);
}

Future<void> _select(WidgetTester tester, String destination) async {
  await tester.tap(find.text(destination).last);
  await fixture.frames(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final destination in ['Chats', 'Crons']) {
    testWidgets(
      '$destination periodic ticks stop re-paging archives on a non-archived filter',
      (tester) async {
        final traffic = _Traffic();
        final rows = [
          fixture.row('human', 'Human chat'),
          fixture.row('cron', 'Cron run', source: 'cron'),
        ];
        await _pumpWorkspace(
          tester,
          connectionId: 'tick-scope-$destination',
          active: MockClient((request) async {
            if (request.url.queryParameters['limit'] == '5') {
              traffic.activeScans++;
              return fixture.page(rows);
            }
            return fixture.page(
              request.url.queryParameters['offset'] == '0' ? rows : [],
            );
          }),
          dashboard: MockClient((request) async {
            if (!_isArchiveRequest(request)) return http.Response('{}', 200);
            traffic.archivePages++;
            return fixture.archives([
              fixture.row(
                'archived',
                'Archived chat',
                source: destination == 'Crons' ? 'cron' : 'gateway',
                archived: true,
              ),
            ], 1);
          }),
        );
        if (destination == 'Crons') await _select(tester, 'Crons');
        final scansAfterFirstLoad = traffic.activeScans;
        final archivesAfterFirstLoad = traffic.archivePages;
        expect(
          archivesAfterFirstLoad,
          greaterThan(0),
          reason: 'the first load still pages the archive authority in full',
        );
        await _ticks(tester, 3);
        expect(
          traffic.activeScans,
          scansAfterFirstLoad + 3,
          reason: 'each tick still refreshes the authority the filter renders',
        );
        expect(
          traffic.archivePages,
          archivesAfterFirstLoad,
          reason:
              'a visible non-archived pane must not re-page archived=only '
              'on every tick (#149)',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final filter in ['All', 'Recent', 'Unassigned']) {
    testWidgets('$filter chip ticks never page the archive router', (
      tester,
    ) async {
      final traffic = _Traffic();
      final rows = [fixture.row('human', 'Human chat')];
      await _pumpWorkspace(
        tester,
        connectionId: 'tick-filter-$filter',
        active: MockClient((request) async {
          if (request.url.queryParameters['limit'] == '5') {
            traffic.activeScans++;
            return fixture.page(rows);
          }
          return fixture.page(
            request.url.queryParameters['offset'] == '0' ? rows : [],
          );
        }),
        dashboard: MockClient((request) async {
          if (!_isArchiveRequest(request)) return http.Response('{}', 200);
          traffic.archivePages++;
          return fixture.archives([], 0);
        }),
      );
      if (filter != 'All') await _tapChip(tester, filter);
      final archived = traffic.archivePages;
      await _ticks(tester, 3);
      expect(traffic.activeScans, greaterThan(1));
      expect(traffic.archivePages, archived);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Archived chip ticks keep refreshing the archive authority', (
    tester,
  ) async {
    final traffic = _Traffic();
    var archiveTitle = 'Archived chat';
    final rows = [fixture.row('human', 'Human chat')];
    await _pumpWorkspace(
      tester,
      connectionId: 'tick-archived',
      active: MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          traffic.activeScans++;
          return fixture.page(rows);
        }
        return fixture.page(
          request.url.queryParameters['offset'] == '0' ? rows : [],
        );
      }),
      dashboard: MockClient((request) async {
        if (!_isArchiveRequest(request)) return http.Response('{}', 200);
        traffic.archivePages++;
        return fixture.archives([
          fixture.row('archived', archiveTitle, archived: true),
        ], 1);
      }),
    );
    await _tapChip(tester, 'Archived');
    expect(find.text('Archived chat'), findsOneWidget);
    final pagesPerScan = traffic.archivePages;
    expect(pagesPerScan, greaterThan(0));
    archiveTitle = 'Renamed elsewhere';
    await _ticks(tester, 2);
    expect(
      traffic.archivePages,
      pagesPerScan * 3,
      reason: 'the Archived surface keeps its full-scope tick',
    );
    expect(
      find.text('Renamed elsewhere'),
      findsOneWidget,
      reason: 'a tick on Archived publishes freshly read archive rows',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'active-only ticks preserve archived rows, pins and Quick expiry',
    (tester) async {
      const connectionId = 'tick-preserve';
      final preferences = await SharedPreferences.getInstance();
      final quick = QuickChatStore(preferences, connectionId: connectionId);
      await quick.record(
        'quick',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final pins = LocalChatPinStore(preferences, connectionId: connectionId);
      await pins.setPinned('human', pinned: true);
      final traffic = _Traffic();
      final held = Completer<http.Response>();
      addTearDown(() {
        if (!held.isCompleted) held.complete(fixture.archives([], 0));
      });
      var hold = false;
      final rows = [
        fixture.row('human', 'Human chat'),
        fixture.row('quick', 'Expired quick chat'),
      ];
      await _pumpWorkspace(
        tester,
        connectionId: connectionId,
        active: MockClient((request) async {
          if (request.url.queryParameters['limit'] == '5') {
            traffic.activeScans++;
            return fixture.page(rows);
          }
          return fixture.page(
            request.url.queryParameters['offset'] == '0' ? rows : [],
          );
        }),
        dashboard: MockClient((request) async {
          if (!_isArchiveRequest(request)) return http.Response('{}', 200);
          traffic.archivePages++;
          if (hold) return held.future;
          return fixture.archives([
            fixture.row('archived', 'Archived chat', archived: true),
          ], 1);
        }),
      );
      expect(find.text('Pinned on this device'), findsOneWidget);
      expect(find.text('Human chat'), findsOneWidget);
      final archivesAfterFirstLoad = traffic.archivePages;
      await _ticks(tester, 3);
      expect(traffic.archivePages, archivesAfterFirstLoad);
      expect(
        find.text('Pinned on this device'),
        findsOneWidget,
        reason: 'a narrower tick is not evidence that a local pin was removed',
      );
      expect(await pins.load(), ['human']);
      expect((await quick.load()).archivedAt(DateTime.now()), {'quick'});
      // The catch-up read is held, so anything still on screen can only come
      // from the archive snapshot the scoped ticks carried forward.
      hold = true;
      await _tapChip(tester, 'Archived');
      expect(
        traffic.archivePages,
        greaterThan(archivesAfterFirstLoad),
        reason: 'selecting Archived catches the archive authority up',
      );
      expect(
        find.text('Archived chat'),
        findsOneWidget,
        reason: 'active-only ticks must not blank previously loaded archives',
      );
      expect(
        find.text('Expired quick chat'),
        findsOneWidget,
        reason: 'device-local Quick expiry survives a narrower tick',
      );
      expect(find.byType(EmptyState), findsNothing);
      held.complete(http.Response('offline', 503));
      await fixture.frames(tester);
      expect(
        find.text('Archived chat'),
        findsOneWidget,
        reason: 'a failed catch-up retains the rows it already had',
      );
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('switching to Archived loads archives without waiting a tick', (
    tester,
  ) async {
    final traffic = _Traffic();
    var archiveRows = <Map<String, Object?>>[];
    final rows = [fixture.row('human', 'Human chat')];
    await _pumpWorkspace(
      tester,
      connectionId: 'tick-switch',
      active: MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          traffic.activeScans++;
          return fixture.page(rows);
        }
        return fixture.page(
          request.url.queryParameters['offset'] == '0' ? rows : [],
        );
      }),
      dashboard: MockClient((request) async {
        if (!_isArchiveRequest(request)) return http.Response('{}', 200);
        traffic.archivePages++;
        return fixture.archives(archiveRows, archiveRows.length);
      }),
    );
    await _ticks(tester, 2);
    final skipped = traffic.archivePages;
    archiveRows = [
      fixture.row('archived', 'Archived while away', archived: true),
    ];
    await _tapChip(tester, 'Archived');
    expect(
      traffic.archivePages,
      greaterThan(skipped),
      reason: 'the chip gesture owns the archive read the tick stopped doing',
    );
    expect(find.text('Archived while away'), findsOneWidget);
    // Returning to All and back must not re-read an archive nothing skipped.
    final settled = traffic.archivePages;
    await _tapChip(tester, 'All');
    await _tapChip(tester, 'Archived');
    expect(traffic.archivePages, settled);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pull-to-refresh after scoped ticks keeps its own scope', (
    tester,
  ) async {
    final traffic = _Traffic();
    var rows = [fixture.row('human', 'Human chat')];
    await _pumpWorkspace(
      tester,
      connectionId: 'tick-refresh',
      active: MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          traffic.activeScans++;
          return fixture.page(rows);
        }
        return fixture.page(
          request.url.queryParameters['offset'] == '0' ? rows : [],
        );
      }),
      dashboard: MockClient((request) async {
        if (!_isArchiveRequest(request)) return http.Response('{}', 200);
        traffic.archivePages++;
        return fixture.archives([], 0);
      }),
    );
    await _ticks(tester, 2);
    final scans = traffic.activeScans;
    final archives = traffic.archivePages;
    rows = [...rows, fixture.row('later', 'Persisted before refresh')];
    final refreshed = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator).last)
        .onRefresh();
    await fixture.frames(tester);
    await refreshed;
    expect(
      traffic.activeScans,
      scans + 1,
      reason: 'an explicit gesture still owns fresh active I/O',
    );
    expect(
      traffic.archivePages,
      archives,
      reason:
          'Chats pull-to-refresh was already archive-free; #149 must not '
          'widen or narrow it',
    );
    expect(find.text('Persisted before refresh'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a hidden pane issues no requests at all', (tester) async {
    final traffic = _Traffic();
    final rows = [fixture.row('human', 'Human chat')];
    await _pumpWorkspace(
      tester,
      connectionId: 'tick-hidden',
      active: MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          traffic.activeScans++;
          return fixture.page(rows);
        }
        return fixture.page(
          request.url.queryParameters['offset'] == '0' ? rows : [],
        );
      }),
      dashboard: MockClient((request) async {
        if (!_isArchiveRequest(request)) return http.Response('{}', 200);
        traffic.archivePages++;
        return fixture.archives([], 0);
      }),
    );
    await _select(tester, 'More');
    final scans = traffic.activeScans;
    final archives = traffic.archivePages;
    await _ticks(tester, 3);
    expect(traffic.activeScans, scans);
    expect(traffic.archivePages, archives);
    await tester.pumpWidget(const SizedBox());
  });
}
