import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/activity_feed.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_refresh_authority_test.dart' as fixture;

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required http.Client active,
  required http.Client dashboard,
  required List<Map<String, String>> titleSnapshots,
  WorkspaceSessionScreenBuilder? sessionBuilder,
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
          id: 'active-authority',
          label: 'Test',
          host: 'fixture',
          port: 8642,
          apiKey: 'fixture-key',
          dashboardProxied: true,
        ),
        testSessionsHttpClient: active,
        testDashboardHttpClient: dashboard,
        sessionScreenBuilder: sessionBuilder,
        turnSignalsLoader: (_) async => HomeTurnSignals.empty,
        activityFeedLoader: (_, titles) async {
          titleSnapshots.add(Map.of(titles));
          return const ActivityFeed(
            groups: [],
            blockedCount: 0,
            runningCount: 0,
          );
        },
      ),
    ),
  );
  await fixture.frames(tester);
}

Future<void> _select(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab).last);
  await fixture.frames(tester);
}

Future<void> _filter(WidgetTester tester, String filter) async {
  await tester.tap(find.widgetWithText(ChoiceChip, filter));
  await fixture.frames(tester);
}

Future<void> _refresh(WidgetTester tester) => tester
    .widget<RefreshIndicator>(find.byType(RefreshIndicator).last)
    .onRefresh();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final target in ['Chats', 'Crons', 'Search', 'Unassigned']) {
    testWidgets('$target manual refresh and chat return own fresh active I/O', (
      tester,
    ) async {
      final old = Completer<http.Response>();
      addTearDown(() {
        if (!old.isCompleted) old.complete(fixture.page([]));
      });
      var holdOld = false;
      var oldEntered = false;
      var previews = 0;
      var rows = [
        fixture.row('human', 'Original human'),
        fixture.row('cron', 'Original cron', source: 'cron'),
      ];
      final captured = List.of(rows);
      await _pumpWorkspace(
        tester,
        titleSnapshots: [],
        active: MockClient((request) async {
          if (request.url.queryParameters['limit'] == '5') {
            previews++;
            return fixture.page(rows);
          }
          if (request.url.queryParameters['offset'] != '0') {
            return fixture.page([]);
          }
          if (holdOld) {
            holdOld = false;
            oldEntered = true;
            return old.future;
          }
          return fixture.page(rows);
        }),
        dashboard: MockClient((_) async => fixture.archives([], 0)),
        sessionBuilder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Test conversation')),
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                rows = [
                  ...rows,
                  fixture.row(
                    'after-chat',
                    'Persisted inside chat',
                    source: target == 'Crons' ? 'cron' : 'gateway',
                  ),
                ];
                Navigator.of(context).pop();
              },
              child: const Text('Persist and return'),
            ),
          ),
        ),
      );
      Future<void>? oldRefresh;
      if (target == 'Crons') {
        await _select(tester, 'Crons');
        await _select(tester, 'Chats');
        holdOld = true;
        oldRefresh = _refresh(tester);
        await fixture.frames(tester);
        await _select(tester, 'Crons');
      } else {
        holdOld = true;
        await _select(tester, 'Crons');
        await _select(tester, 'Chats');
        if (target == 'Search') {
          await tester.tap(find.byTooltip('Search all chats'));
          await fixture.frames(tester);
        } else if (target == 'Unassigned') {
          await _select(tester, 'More');
          await tester.tap(find.text('Unassigned chats'));
          await fixture.frames(tester);
        }
      }
      expect(oldEntered, isTrue);
      final before = previews;
      rows = [
        ...rows,
        fixture.row(
          'after-gesture',
          'Persisted before manual refresh',
          source: target == 'Crons' ? 'cron' : 'gateway',
        ),
      ];
      final refreshed = _refresh(tester);
      await fixture.frames(tester);
      await refreshed;
      expect(previews, before + 1);
      expect(find.text('Persisted before manual refresh'), findsOneWidget);
      await tester.tap(
        find.text(target == 'Crons' ? 'Original cron' : 'Original human').last,
      );
      await fixture.frames(tester);
      expect(find.text('Test conversation'), findsOneWidget);
      await tester.tap(find.text('Persist and return'));
      await fixture.frames(tester);
      expect(previews, before + 2);
      expect(find.text('Persisted inside chat'), findsOneWidget);
      old.complete(fixture.page(captured));
      await fixture.frames(tester);
      await oldRefresh;
      expect(find.text('Persisted inside chat'), findsOneWidget);
      expect(find.text('Persisted before manual refresh'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final target in ['Chats', 'Crons']) {
    for (final oldFirst in [true, false]) {
      for (final oldFails in [false, true]) {
        testWidgets(
          '$target held physical refresh: oldFirst=$oldFirst oldFails=$oldFails',
          (tester) async {
            final old = Completer<http.Response>();
            final fresh = Completer<http.Response>();
            for (final held in [old, fresh]) {
              addTearDown(() {
                if (!held.isCompleted) held.complete(fixture.page([]));
              });
            }
            var previews = 0;
            var holdOld = false;
            var holdFresh = false;
            var oldEntered = false;
            var freshEntered = false;
            final original = [
              fixture.row('human', 'Original human'),
              fixture.row('cron', 'Original cron', source: 'cron'),
            ];
            final newRows = [
              fixture.row('human', 'Fresh shared title'),
              fixture.row('cron', 'Original cron', source: 'cron'),
              fixture.row(
                'new-row',
                'Persisted after old physical read',
                source: target == 'Crons' ? 'cron' : 'gateway',
              ),
            ];
            final titleSnapshots = <Map<String, String>>[];
            await _pumpWorkspace(
              tester,
              titleSnapshots: titleSnapshots,
              active: MockClient((request) async {
                if (request.url.queryParameters['limit'] == '5') {
                  previews++;
                  // Only the held fresh full page contains the new row.
                  return fixture.page(original);
                }
                if (request.url.queryParameters['offset'] != '0') {
                  return fixture.page([]);
                }
                if (holdOld) {
                  holdOld = false;
                  oldEntered = true;
                  return old.future;
                }
                if (holdFresh) {
                  holdFresh = false;
                  freshEntered = true;
                  return fresh.future;
                }
                return fixture.page(original);
              }),
              dashboard: MockClient((_) async => fixture.archives([], 0)),
            );
            Future<void>? oldRefresh;
            if (target == 'Chats') {
              holdOld = true;
              await _select(tester, 'Crons');
              await _select(tester, 'Chats');
            } else {
              await _select(tester, 'Crons');
              await _select(tester, 'Chats');
              holdOld = true;
              oldRefresh = _refresh(tester);
              await fixture.frames(tester);
              await _select(tester, 'Crons');
            }
            expect(oldEntered, isTrue);
            final before = previews;
            holdFresh = true;
            var completed = false;
            final refreshed = _refresh(tester).then((_) => completed = true);
            await fixture.frames(tester);
            expect(previews, before + 1);
            expect(freshEntered, isTrue);
            expect(completed, isFalse);

            void releaseOld() => old.complete(
              oldFails
                  ? http.Response('old physical scan failed', 503)
                  : fixture.page(original),
            );
            if (oldFirst) {
              releaseOld();
              await fixture.frames(tester);
              expect(completed, isFalse);
              expect(
                find.text('Persisted after old physical read'),
                findsNothing,
              );
            }
            fresh.complete(fixture.page(newRows));
            await fixture.frames(tester);
            await refreshed;
            expect(completed, isTrue);
            expect(
              find.text('Persisted after old physical read'),
              findsOneWidget,
            );
            if (!oldFirst) {
              releaseOld();
              await fixture.frames(tester);
            }
            await oldRefresh;
            expect(
              find.text('Persisted after old physical read'),
              findsOneWidget,
            );
            expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNothing);

            await _select(tester, 'Activity');
            expect(titleSnapshots, isNotEmpty);
            expect(titleSnapshots.last['human'], 'Fresh shared title');
            expect(
              titleSnapshots.last['new-row'],
              'Persisted after old physical read',
            );
            await _select(tester, target);
            expect(
              find.text('Persisted after old physical read'),
              findsOneWidget,
            );
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }

    testWidgets(
      '$target active Retry recovers fully while archives stay held',
      (tester) async {
        final archive = Completer<http.Response>();
        addTearDown(() {
          if (!archive.isCompleted) archive.complete(fixture.archives([], 0));
        });
        var recovered = false;
        var activeRequests = 0;
        final rows = [
          for (var index = 0; index < 7; index++)
            fixture.row(
              'recovered-$index',
              'Recovered row $index',
              source: target == 'Crons' ? 'cron' : 'gateway',
            ),
        ];
        await fixture.pumpWorkspace(
          tester,
          active: MockClient((request) async {
            activeRequests++;
            if (!recovered) return http.Response('unavailable', 503);
            return fixture.page(
              request.url.queryParameters['offset'] == '0' ? rows : [],
            );
          }),
          dashboard: MockClient((_) => archive.future),
        );
        if (target == 'Crons') await _select(tester, 'Crons');
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
        final before = activeRequests;
        recovered = true;
        await tester.tap(find.widgetWithText(TextButton, 'Retry'));
        await fixture.frames(tester);
        expect(activeRequests, greaterThan(before));
        expect(find.text('Recovered row 6'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
        archive.complete(http.Response('old archive failed', 503));
        await fixture.frames(tester);
        expect(find.text('Recovered row 6'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
        await _filter(tester, 'Archived');
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    for (final archivesFirst in [true, false]) {
      for (final oldFails in [false, true]) {
        testWidgets(
          '$target overlapping scoped refreshes: archivesFirst=$archivesFirst oldFails=$oldFails',
          (tester) async {
            final oldActive = Completer<http.Response>();
            final oldArchive = Completer<http.Response>();
            final freshActive = Completer<http.Response>();
            final freshArchive = Completer<http.Response>();
            for (final held in [
              oldActive,
              oldArchive,
              freshActive,
              freshArchive,
            ]) {
              addTearDown(() {
                if (!held.isCompleted) held.complete(fixture.page([]));
              });
            }
            var fullActiveRequests = 0;
            var archiveRequests = 0;
            final activeRows = [
              for (var index = 0; index < 7; index++)
                fixture.row(
                  'active-$index',
                  'Fresh active $index',
                  source: target == 'Crons' ? 'cron' : 'gateway',
                ),
            ];
            final archiveRows = [
              for (var index = 0; index < 7; index++)
                fixture.row(
                  'archive-$index',
                  'Fresh archive $index',
                  source: target == 'Crons' ? 'cron' : 'gateway',
                  archived: true,
                ),
            ];
            await fixture.pumpWorkspace(
              tester,
              active: MockClient((request) async {
                if (request.url.queryParameters['limit'] == '5' ||
                    request.url.queryParameters['offset'] != '0') {
                  return fixture.page([]);
                }
                fullActiveRequests++;
                return fullActiveRequests == 1
                    ? oldActive.future
                    : freshActive.future;
              }),
              dashboard: MockClient((_) {
                archiveRequests++;
                return archiveRequests == 1
                    ? oldArchive.future
                    : freshArchive.future;
              }),
            );
            if (target == 'Crons') await _select(tester, 'Crons');
            final refreshedActive = _refresh(tester);
            await fixture.frames(tester);
            expect(fullActiveRequests, 2);
            await _filter(tester, 'Archived');
            final refreshedArchives = _refresh(tester);
            await fixture.frames(tester);
            expect(archiveRequests, 2);

            if (archivesFirst) {
              freshArchive.complete(fixture.archives(archiveRows, 7));
              await fixture.frames(tester);
              await refreshedArchives;
              expect(find.text('Fresh archive 6'), findsOneWidget);
              expect(find.byType(LinearProgressIndicator), findsNothing);
              freshActive.complete(fixture.page(activeRows));
            } else {
              freshActive.complete(fixture.page(activeRows));
              await fixture.frames(tester);
              await refreshedActive;
              await _filter(tester, 'All');
              expect(find.text('Fresh active 6'), findsOneWidget);
              expect(find.byType(LinearProgressIndicator), findsNothing);
              freshArchive.complete(fixture.archives(archiveRows, 7));
            }
            await fixture.frames(tester);
            await Future.wait([refreshedActive, refreshedArchives]);
            // The old aggregate now publishes progress, errors and its final
            // result. Neither selected authority may borrow that old ownership.
            oldArchive.complete(
              oldFails
                  ? http.Response('old archive failed', 503)
                  : fixture.archives([], 0),
            );
            await fixture.frames(tester);
            oldActive.complete(
              oldFails
                  ? http.Response('old active failed', 503)
                  : fixture.page([]),
            );
            await fixture.frames(tester);
            await _filter(tester, 'All');
            expect(find.text('Fresh active 6'), findsOneWidget);
            expect(find.text('Fresh archive 6'), findsNothing);
            expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            await _filter(tester, 'Archived');
            expect(find.text('Fresh archive 6'), findsOneWidget);
            expect(find.text('Fresh active 6'), findsNothing);
            expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
