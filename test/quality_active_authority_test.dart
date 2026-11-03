import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_refresh_authority_test.dart' as fixture;

void main() {
  // Review-only tests live outside test/ to preserve the committed full suite.
  // ignore: invalid_use_of_visible_for_testing_member
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final target in ['Chats', 'Crons']) {
    testWidgets(
      '$target explicit active refresh must include post-gesture physical I/O',
      (tester) async {
        var previewRequests = 0;
        var holdNextFullPage = false;
        final held = Completer<http.Response>();
        final entered = Completer<void>();
        var rows = [
          fixture.row('human', 'Original human chat'),
          fixture.row('cron', 'Original cron run', source: 'cron'),
        ];
        List<Map<String, Object?>>? captured;
        addTearDown(() {
          if (!held.isCompleted) held.complete(fixture.page(captured ?? []));
        });
        final client = MockClient((request) async {
          if (request.url.queryParameters['limit'] == '5') {
            previewRequests++;
            return fixture.page(rows);
          }
          if (request.url.queryParameters['offset'] == '0') {
            if (holdNextFullPage) {
              holdNextFullPage = false;
              captured = List.of(rows);
              entered.complete();
              return held.future;
            }
            return fixture.page(rows);
          }
          return fixture.page([]);
        });
        await fixture.pumpWorkspace(
          tester,
          active: client,
          dashboard: MockClient((_) async => fixture.archives([], 0)),
        );
        expect(previewRequests, 1);
        if (target == 'Chats') {
          // Crons starts a passive old scan after Chats has finished its read.
          holdNextFullPage = true;
          await tester.tap(find.text('Crons').last);
          await fixture.frames(tester);
          expect(entered.isCompleted, isTrue);
          await tester.tap(find.text('Chats').last);
          await fixture.frames(tester);
        } else {
          // Retain a completed Crons pane, then start an old read from Chats.
          await tester.tap(find.text('Crons').last);
          await fixture.frames(tester);
          await tester.tap(find.text('Chats').last);
          await fixture.frames(tester);
          holdNextFullPage = true;
          final oldRefresh = tester
              .widget<RefreshIndicator>(find.byType(RefreshIndicator))
              .onRefresh();
          await fixture.frames(tester);
          expect(entered.isCompleted, isTrue);
          unawaited(oldRefresh);
          await tester.tap(find.text('Crons').last);
          await fixture.frames(tester);
        }
        final before = previewRequests;
        rows = [
          ...rows,
          fixture.row(
            'new-row',
            'Persisted after old read',
            source: target == 'Crons' ? 'cron' : 'gateway',
          ),
        ];
        final refreshed = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await fixture.frames(tester);
        final startedBeforeOldRelease = previewRequests;
        held.complete(fixture.page(captured!));
        await fixture.frames(tester);
        await refreshed;
        final freshVisible = find
            .text('Persisted after old read')
            .evaluate()
            .length;
        debugPrint(
          'QUALITY_ACTIVE target=$target before=$before '
          'afterGesture=$startedBeforeOldRelease afterRefresh=$previewRequests '
          'newRowVisible=$freshVisible',
        );
        await tester.pumpWidget(const SizedBox());
        expect(
          previewRequests,
          greaterThan(before),
          reason:
              'explicit refresh cannot finish on a sibling pre-gesture flight',
        );
        expect(freshVisible, 1);
      },
    );
  }

  testWidgets('active Retry does not wait for unrelated dashboard history', (
    tester,
  ) async {
    var recovered = false;
    var activeRequests = 0;
    final archiveHeld = Completer<http.Response>();
    addTearDown(() {
      if (!archiveHeld.isCompleted) {
        archiveHeld.complete(fixture.archives([], 0));
      }
    });
    await fixture.pumpWorkspace(
      tester,
      active: MockClient((request) async {
        activeRequests++;
        if (!recovered) return http.Response('unavailable', 503);
        if (request.url.queryParameters['offset'] == '0') {
          return fixture.page([
            fixture.row('recovered', 'Recovered human chat'),
          ]);
        }
        return fixture.page([]);
      }),
      dashboard: MockClient((_) => archiveHeld.future),
    );
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    final before = activeRequests;
    recovered = true;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await fixture.frames(tester);
    final duringArchiveRead = activeRequests;
    final recoveredBeforeArchiveRelease = find
        .text('Recovered human chat')
        .evaluate()
        .length;
    debugPrint(
      'QUALITY_ACTIVE_RETRY before=$before whileArchiveHeld=$duringArchiveRead '
      'recoveredBeforeArchiveRelease=$recoveredBeforeArchiveRelease',
    );
    archiveHeld.complete(fixture.archives([], 0));
    await fixture.frames(tester);
    expect(find.text('Recovered human chat'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(
      duringArchiveRead,
      greaterThan(before),
      reason:
          'active Retry must issue active I/O before dashboard history finishes',
    );
    expect(recoveredBeforeArchiveRelease, 1);
  });
}
