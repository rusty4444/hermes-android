import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_refresh_authority_test.dart' as fixture;

Map<String, dynamic> _tree(String label) => {
  'jsonrpc': '2.0',
  'id': 1,
  'result': {
    'projects': [
      {
        'id': 'project',
        'label': label,
        'sessionIds': ['filed'],
        'sessionCount': 1,
      },
    ],
  },
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final oldTreeFirst in [true, false]) {
    testWidgets(
      'fresh active metadata keeps readiness, Quick IDs and pins: oldTreeFirst=$oldTreeFirst',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final preferences = await SharedPreferences.getInstance();
        const connectionId = 'active-metadata';
        final quick = QuickChatStore(preferences, connectionId: connectionId);
        final expired = DateTime.now().subtract(const Duration(days: 1));
        await quick.record('quick', expiresAt: expired);
        await quick.record('outside-window', expiresAt: expired);
        final pins = LocalChatPinStore(preferences, connectionId: connectionId);
        await pins.setPinned('filed', pinned: true);
        final oldArchive = Completer<http.Response>();
        final oldTree = Completer<Map<String, dynamic>>();
        final freshTree = Completer<Map<String, dynamic>>();
        addTearDown(() {
          if (!oldArchive.isCompleted) {
            oldArchive.complete(fixture.archives([], 0));
          }
          if (!oldTree.isCompleted) oldTree.complete(_tree('Old Project'));
          if (!freshTree.isCompleted) {
            freshTree.complete(_tree('Fresh Project'));
          }
        });
        var trees = 0;
        final repository = ProjectsRepository(
          client: ProjectsGatewayClient((method, params) async {
            expectSync(method, 'projects.tree');
            trees++;
            return trees == 1 ? oldTree.future : freshTree.future;
          }),
          preferences: preferences,
          connectionId: connectionId,
        );
        addTearDown(repository.close);
        var previews = 0;
        final rows = [
          fixture.row('filed', 'Filed chat'),
          fixture.row('quick', 'Promoted Quick'),
          fixture.row('loose', 'New expired Quick'),
        ];
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
              repositoryFactory: (_) => repository,
              testSessionsHttpClient: MockClient((request) async {
                if (request.url.queryParameters['limit'] == '5') previews++;
                return fixture.page(
                  request.url.queryParameters['offset'] == '0' ? rows : [],
                );
              }),
              testDashboardHttpClient: MockClient((_) => oldArchive.future),
              turnSignalsLoader: (_) async => HomeTurnSignals.empty,
            ),
          ),
        );
        await fixture.frames(tester);
        expect(trees, 1);
        expect(previews, 1);
        expect(find.text('Pinned on this device'), findsOneWidget);
        await quick.promote('quick');
        await quick.record('loose', expiresAt: expired);
        final refreshed = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await fixture.frames(tester);
        expect(trees, 2);
        expect(previews, 2);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
        await fixture.frames(tester);
        expect(find.text('Filed chat'), findsNothing);
        expect(find.text('Promoted Quick'), findsNothing);
        expect(find.byType(EmptyState), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        if (oldTreeFirst) {
          oldTree.complete(_tree('Old Project'));
          await fixture.frames(tester);
          // Old aggregate progress cannot turn unknown fresh placement into
          // a false Unassigned verdict while the new Project read is held.
          expect(find.text('Filed chat'), findsNothing);
          expect(find.text('Promoted Quick'), findsNothing);
          expect(find.byType(EmptyState), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
        }
        freshTree.complete(_tree('Fresh Project'));
        await fixture.frames(tester);
        await refreshed;
        expect(find.text('Filed chat'), findsNothing);
        expect(find.text('Promoted Quick'), findsOneWidget);
        expect(find.text('New expired Quick'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        if (!oldTreeFirst) oldTree.complete(_tree('Old Project'));
        oldArchive.complete(fixture.archives([], 0));
        await fixture.frames(tester);
        expect(find.text('Filed chat'), findsNothing);
        expect(find.text('Promoted Quick'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
        await fixture.frames(tester);
        expect(find.text('Fresh Project'), findsOneWidget);
        expect(find.text('Old Project'), findsNothing);
        expect(find.text('Pinned on this device'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
        await fixture.frames(tester);
        expect(find.text('New expired Quick'), findsOneWidget);
        expect(find.text('Promoted Quick'), findsNothing);
        final saved = await quick.load();
        // Promotion is terminal metadata, not deletion of its original clock.
        expect(
          saved.expiries.keys,
          unorderedEquals(['quick', 'loose', 'outside-window']),
        );
        expect(saved.promoted, {'quick'});
        expect(saved.archivedAt(DateTime.now()), {'loose', 'outside-window'});
        expect(await pins.load(), ['filed']);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
