// Regression sequences adapted from the preserved reviewer-d82da04 probes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/widgets/activity_pane.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

final _connection = SavedConnection(
  id: 'source-regression',
  label: 'Source regression',
  host: 'activity.invalid',
  port: 8642,
  apiKey: '',
);

Session _row(String id, {String? root, String? title, double? at}) => Session(
  id: id,
  title: title ?? id,
  model: '',
  source: 'gateway',
  messageCount: 2,
  isActive: false,
  preview: '',
  startedAt: 1,
  lastActive: at ?? DateTime.now().millisecondsSinceEpoch / 1000,
  lineageRootId: root,
);

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: home,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('late Home response cannot regress newer Activity metadata', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    final oldHome = Completer<List<Session>>();
    var reads = 0;
    await tester.pumpWidget(
      _app(
        WorkspaceScreen(
          connection: _connection,
          turnApplicationController: controller,
          sessionsLoader: () => ++reads == 1
              ? oldHome.future
              : Future.value([_row('chat', title: 'New title')]),
          installedVersionLoader: () async => null,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Activity').last);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();
    expect(find.text('New title'), findsOneWidget);
    oldHome.complete([_row('chat', title: 'Obsolete title')]);
    await tester.pumpAndSettle();
    // A local-only observer refresh must use the newest shared metadata,
    // rather than appearing correct only until the next full server refresh.
    final token = controller.beginLegacyTurn();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    final newTitles = find.text('New title').evaluate().length;
    final oldTitles = find.text('Obsolete title').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    controller.endLegacyTurn(token);
    await controller.close();
    expect(newTitles, 1);
    expect(oldTitles, 0);
    expect(reads, 2, reason: 'observer updates must not fetch session lists');
  });

  for (final failOldRead in [false, true]) {
    testWidgets(
      'new Home metadata fences a held Activity ${failOldRead ? 'failure' : 'response'}',
      (tester) async {
        final controller = GatewayTurnApplicationController();
        final oldActivity = Completer<List<Session>>();
        var reads = 0;
        await tester.pumpWidget(
          _app(
            WorkspaceScreen(
              connection: _connection,
              turnApplicationController: controller,
              sessionsLoader: () {
                reads++;
                if (reads == 3) return oldActivity.future;
                return Future.value([
                  _row(
                    'chat',
                    title: reads > 3 ? 'Newest Home title' : 'Initial title',
                  ),
                ]);
              },
              installedVersionLoader: () async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Activity').last);
        await tester.pumpAndSettle();
        expect(reads, 2);
        final held = tester
            .widget<ActivityPane>(find.byType(ActivityPane))
            .loadFeed();
        await tester.pump();
        expect(reads, 3);
        await tester
            .state<WorkspaceSessionsScreenState>(
              find.byType(WorkspaceSessionsScreen, skipOffstage: false),
            )
            .refresh();
        await tester.pumpAndSettle();
        expect(reads, 4);
        if (failOldRead) {
          oldActivity.completeError(StateError('obsolete offline response'));
        } else {
          oldActivity.complete([
            _row('chat', title: 'Obsolete Activity title'),
          ]);
        }
        final feed = await held;
        expect(feed.groups.single.items.single.title, 'Newest Home title');
        expect(feed.isStale, isFalse);
        expect(feed.isPartial, failOldRead);
        await tester.pumpWidget(const SizedBox());
        await controller.close();
      },
    );
  }

  testWidgets(
    'a shared progressive Home scan cannot restore its earlier title',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      final oldHome = Completer<http.Response>();
      var pageZeroReads = 0;
      http.Response response(String? title) => http.Response(
        jsonEncode({
          'data': title == null
              ? []
              : [
                  {
                    'id': 'chat',
                    'title': title,
                    'message_count': 4,
                    'last_active': DateTime.now().millisecondsSinceEpoch / 1000,
                  },
                ],
          'has_more': false,
        }),
        200,
      );
      final client = MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          return response('Home preview title');
        }
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        if (offset != 0) return response(null);
        return ++pageZeroReads == 1
            ? oldHome.future
            : response('New Activity title');
      });
      await tester.pumpWidget(
        _app(
          WorkspaceScreen(
            connection: _connection,
            turnApplicationController: controller,
            testSessionsHttpClient: client,
            installedVersionLoader: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(pageZeroReads, 1);
      await tester.tap(find.text('Activity').last);
      await tester.pumpAndSettle();
      expect(find.text('New Activity title'), findsOneWidget);
      oldHome.complete(response('Obsolete full Home title'));
      await tester.pumpAndSettle();
      final token = controller.beginLegacyTurn();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('New Activity title'), findsOneWidget);
      expect(find.text('Obsolete full Home title'), findsNothing);
      expect(pageZeroReads, 2);
      await tester.pumpWidget(const SizedBox());
      controller.endLegacyTurn(token);
      await controller.close();
    },
  );

  testWidgets('compression refresh shows and opens only the current tip', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    var sessions = [_row('root', title: 'Before compression')];
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        WorkspaceScreen(
          connection: _connection,
          turnApplicationController: controller,
          sessionsLoader: () async => sessions,
          onOpenSession: (session) => opened.add(session.id),
          installedVersionLoader: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    sessions = [_row('tip-1', root: 'root', title: 'First continuation')];
    await tester.state<ActivityPaneState>(find.byType(ActivityPane)).refresh();
    await tester.pumpAndSettle();
    sessions = [_row('tip-2', root: 'root', title: 'Current continuation')];
    await tester.state<ActivityPaneState>(find.byType(ActivityPane)).refresh();
    await tester.pumpAndSettle();
    final before = find.text('Before compression').evaluate().length;
    final first = find.text('First continuation').evaluate().length;
    final current = find.text('Current continuation').evaluate().length;
    if (current == 1) {
      await tester.tap(find.text('Current continuation'));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    expect(before, 0);
    expect(first, 0);
    expect(current, 1);
    expect(opened, ['tip-2']);
  });

  for (final scenario in [
    (name: 'empty full pages', size: 100, messages: 0, hasMore: true, pages: 3),
    (
      name: 'short pages still reporting more',
      size: 1,
      messages: 0,
      hasMore: true,
      pages: 3,
    ),
    (
      name: 'filled recent preview',
      size: 100,
      messages: 4,
      hasMore: true,
      pages: 1,
    ),
    (
      name: 'full pages under-reporting has_more',
      size: 100,
      messages: 0,
      hasMore: false,
      pages: 3,
    ),
  ]) {
    testWidgets('bounded Activity coverage stays partial: ${scenario.name}', (
      tester,
    ) async {
      final controller = GatewayTurnApplicationController();
      final offsets = <int>[];
      final client = MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          return http.Response('{}', 503);
        }
        final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
        offsets.add(offset);
        return http.Response(
          jsonEncode({
            'data': List.generate(
              scenario.size,
              (i) => {
                'id': 'chat-${offset + i}',
                'title': 'Chat ${offset + i}',
                'message_count': scenario.messages,
                'last_active': DateTime.now().millisecondsSinceEpoch / 1000,
              },
            ),
            'has_more': scenario.hasMore,
          }),
          200,
        );
      });
      await tester.pumpWidget(
        _app(
          WorkspaceScreen(
            connection: _connection,
            turnApplicationController: controller,
            testSessionsHttpClient: client,
            installedVersionLoader: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity').last);
      await tester.pumpAndSettle();
      expect(find.text('No recent activity'), findsNothing);
      offsets.clear();
      final feed = await tester
          .widget<ActivityPane>(find.byType(ActivityPane))
          .loadFeed();
      expect(feed.isPartial, isTrue);
      expect(feed.isStale, isFalse);
      expect(offsets, List.generate(scenario.pages, (i) => i * 100));
      if (scenario.messages == 0) {
        expect(feed.groups, isEmpty);
      } else {
        expect(feed.groups.single.totalCount, 100);
        expect(feed.groups.single.items, hasLength(20));
        expect(feed.groups.single.overflow, 80);
      }
      await tester.pumpWidget(const SizedBox());
      await controller.close();
    });
  }

  testWidgets('Activity seeks beyond a first page of empty sessions', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    final offsets = <int>[];
    final client = MockClient((request) async {
      if (request.url.queryParameters['limit'] == '5') {
        return http.Response(
          '{}',
          503,
        ); // Keep the Home scan out of this probe.
      }
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      offsets.add(offset);
      return http.Response(
        jsonEncode({
          'data': offset == 0
              ? List.generate(
                  100,
                  (i) => {
                    'id': 'empty-$i',
                    'title': 'Empty $i',
                    'message_count': 0,
                    'last_active': DateTime.now().millisecondsSinceEpoch / 1000,
                  },
                )
              : [
                  {
                    'id': 'real-work',
                    'title': 'Actual recent work',
                    'message_count': 4,
                    'last_active': DateTime.now().millisecondsSinceEpoch / 1000,
                  },
                ],
          'has_more': offset == 0,
        }),
        200,
      );
    });
    await tester.pumpWidget(
      _app(
        WorkspaceScreen(
          connection: _connection,
          turnApplicationController: controller,
          testSessionsHttpClient: client,
          installedVersionLoader: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity').last);
    await tester.pumpAndSettle();
    final empty = find.text('No recent activity').evaluate().length;
    final useful = find.text('Actual recent work').evaluate().length;
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    expect(offsets, contains(100));
    expect(empty, 0);
    expect(useful, 1);
  });
}
