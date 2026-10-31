import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/projects_repository.dart';
import 'package:hermes_android/core/services/projects_gateway_client.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> row(int i, {bool archived = false}) => {
  'id': '${archived ? 'archived' : 'live'}-$i',
  'title': '${archived ? 'Archived' : 'Live'} chat $i',
  'source': 'gateway',
  'message_count': 2,
  'started_at': 1700000000 - i,
  'archived': archived,
};

http.Response livePage(List<Map<String, Object?>> rows) =>
    http.Response(jsonEncode({'data': rows, 'has_more': false}), 200);

http.Response archivePage(int offset, int count, int total) => http.Response(
  jsonEncode({
    'sessions': List.generate(count, (i) => row(offset + i, archived: true)),
    'total': total,
  }),
  200,
);

Future<void> mount(
  WidgetTester tester, {
  required http.Client active,
  required http.Client archive,
  SavedConnection? connection,
  ProjectsRepositoryFactory? repositoryFactory,
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
        connection:
            connection ??
            SavedConnection(
              id: 'scope-loading',
              label: 'Test',
              host: 'example.invalid',
              port: 8642,
              apiKey: 'test',
              dashboardProxied: true,
            ),
        repositoryFactory: repositoryFactory,
        testSessionsHttpClient: active,
        testArchivedSessionsHttpClient: archive,
        turnSignalsLoader: (_) async => HomeTurnSignals.empty,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Unassigned and Archived show five while independent pages load',
    (tester) async {
      final activeOlder = Completer<http.Response>();
      final archiveOlder = Completer<http.Response>();
      final activeRequests = <Uri>[];
      final archiveRequests = <Uri>[];
      final started = tester.binding.clock.now();
      await mount(
        tester,
        active: MockClient((request) async {
          activeRequests.add(request.url);
          if (request.url.queryParameters['limit'] == '5') {
            return livePage(List.generate(5, row));
          }
          if (request.url.queryParameters['offset'] == '0') {
            return activeOlder.future;
          }
          return livePage([]);
        }),
        archive: MockClient((request) async {
          archiveRequests.add(request.url);
          if (request.url.queryParameters['offset'] == '0') {
            return archivePage(0, 5, 12);
          }
          return archiveOlder.future;
        }),
      );
      await tester.tap(find.text('Chats').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
      await tester.pump();
      expect(find.text('Live chat 0'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pump();
      expect(archiveRequests.first.queryParameters['limit'], '5');
      expect(archiveRequests.last.queryParameters['offset'], '5');
      expect(find.text('Archived chat 0'), findsOneWidget);
      expect(find.text('Archived chat 4'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      // A large history can take longer than the old whole-scan deadline.
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Archived chat 0'), findsOneWidget);
      archiveOlder.complete(archivePage(5, 7, 12));
      await tester.pump();
      await tester.enterText(
        find.byKey(kWorkspaceSessionSearchKey),
        'Archived chat 11',
      );
      // Home's hidden animation must not advance the held active request
      // through its 20-second timeout before these independence assertions.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.binding.clock.now().difference(started).inMilliseconds,
        lessThan(20000),
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Archived chat 11',
        ),
        findsOneWidget,
      );
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'completed archive must not wait for unrelated active history',
      );
      await tester.enterText(find.byKey(kWorkspaceSessionSearchKey), '');
      activeOlder.complete(livePage(List.generate(12, row)));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.enterText(
        find.byKey(kWorkspaceSessionSearchKey),
        'Archived chat 11',
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Archived chat 11',
        ),
        findsOneWidget,
      );
      expect(
        activeRequests.where(
          (uri) =>
              uri.queryParameters['limit'] == '100' &&
              uri.queryParameters['offset'] == '0',
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'active-list failure does not hide a successfully loaded archive',
    (tester) async {
      await mount(
        tester,
        active: MockClient(
          (request) async => request.url.queryParameters['limit'] == '5'
              ? livePage([row(0)])
              : http.Response('API offline', 503),
        ),
        archive: MockClient(
          (request) async => request.url.queryParameters['offset'] == '0'
              ? archivePage(0, 5, 21)
              : archivePage(5, 16, 21),
        ),
      );
      await tester.tap(find.text('Chats').last);
      await tester.pumpAndSettle();
      expect(find.text('Could not load conversations'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load conversations'), findsNothing);
      await tester.enterText(
        find.byKey(kWorkspaceSessionSearchKey),
        'Archived chat 20',
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Archived chat 20',
        ),
        findsOneWidget,
      );
      expect(find.byType(EmptyState), findsNothing);
    },
  );

  testWidgets(
    'late Unassigned subscriber replays successful Home pages before failure',
    (tester) async {
      final later = Completer<http.Response>();
      final repository = ProjectsRepository(
        client: ProjectsGatewayClient(
          (method, params) async => {
            'jsonrpc': '2.0',
            'id': 1,
            'result': {
              'projects': [
                {
                  'id': 'filed',
                  'label': 'Filed project',
                  'sessionIds': List.generate(5, (i) => 'live-$i'),
                },
              ],
            },
          },
        ),
        preferences: await SharedPreferences.getInstance(),
        connectionId: 'scope-loading',
      );
      addTearDown(repository.close);
      await mount(
        tester,
        repositoryFactory: (_) => repository,
        active: MockClient((request) async {
          if (request.url.queryParameters['limit'] == '5') {
            return livePage(List.generate(5, row));
          }
          if (request.url.queryParameters['offset'] == '0') {
            return livePage(List.generate(100, row));
          }
          return later.future;
        }),
        archive: MockClient((_) async => archivePage(0, 0, 0)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('More').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Unassigned chats'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Live chat 5'), findsOneWidget);
      expect(find.text('Live chat 0'), findsNothing);
      later.complete(http.Response('older page failed', 503));
      await tester.pumpAndSettle();
      expect(find.text('Live chat 5'), findsOneWidget);
      expect(find.text('Could not load conversations'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    },
  );

  testWidgets(
    'post-rename refresh does not join an older aggregate authority epoch',
    (tester) async {
      final staleLater = Completer<http.Response>();
      final freshFull = Completer<http.Response>();
      var title = 'Original title';
      var fullReads = 0;
      var heldOnce = false;
      Map<String, Object?> currentRow() => {...row(0), 'title': title};
      await mount(
        tester,
        active: MockClient((request) async {
          if (request.method == 'PATCH') {
            title = (jsonDecode(request.body) as Map)['title'] as String;
            return http.Response(jsonEncode({'session': currentRow()}), 200);
          }
          if (request.url.queryParameters['limit'] == '5') {
            return livePage([currentRow()]);
          }
          if (request.url.queryParameters['offset'] == '0') {
            if (++fullReads == 2) return freshFull.future;
            return livePage([currentRow()]);
          }
          if (!heldOnce) {
            heldOnce = true;
            return staleLater.future;
          }
          return livePage([]);
        }),
        archive: MockClient((_) async => archivePage(0, 0, 0)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(heldOnce, isTrue);
      final heldAt = tester.binding.clock.now();
      final browser = tester.widget<WorkspaceSessionsScreen>(
        find.byType(WorkspaceSessionsScreen),
      );
      await browser.onRename!(
        Session.fromJson(currentRow()),
        'Confirmed new title',
      );
      final readsBeforeRefresh = fullReads;
      var refreshSettled = false;
      final refresh = tester
          .state<WorkspaceSessionsScreenState>(
            find.byType(WorkspaceSessionsScreen),
          )
          .refresh()
          .then((_) => refreshSettled = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        fullReads,
        greaterThan(readsBeforeRefresh),
        reason: 'fresh loader must not join the pre-save physical read',
      );
      expect(refreshSettled, isFalse);
      staleLater.complete(livePage([]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        refreshSettled,
        isFalse,
        reason: 'old completion cannot satisfy the post-rename refresh',
      );
      freshFull.complete(livePage([currentRow()]));
      await tester.pumpAndSettle();
      await refresh;
      expect(refreshSettled, isTrue);
      expect(
        tester.binding.clock.now().difference(heldAt).inMilliseconds,
        lessThan(20000),
      );
      expect(find.text('Confirmed new title'), findsOneWidget);
      expect(find.text('Original title'), findsNothing);
    },
  );

  testWidgets('archive failure is a retry state, never a false empty verdict', (
    tester,
  ) async {
    var fail = true;
    await mount(
      tester,
      active: MockClient(
        (request) async => livePage(
          request.url.queryParameters['offset'] == '0' ? [row(0)] : [],
        ),
      ),
      archive: MockClient(
        (_) async =>
            fail ? http.Response('unavailable', 503) : archivePage(0, 1, 1),
      ),
    );
    await tester.tap(find.text('Chats').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archived'));
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsNothing);
    expect(find.text('Could not load conversations'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Archived chat 0'), findsOneWidget);
    expect(find.text('Could not load conversations'), findsNothing);
  });

  testWidgets('archive uses the explicit gateway origin, prefix and profile', (
    tester,
  ) async {
    final requested = <Uri>[];
    await mount(
      tester,
      connection: SavedConnection(
        id: 'explicit-origin',
        label: 'Test',
        host: 'api.invalid',
        port: 8642,
        apiKey: 'test',
        dashboardProxied: true,
        desktopGatewayUrl: 'https://desktop.invalid:9443/hermes',
        gatewayProfile: 'work',
      ),
      active: MockClient((_) async => livePage([])),
      archive: MockClient((request) async {
        requested.add(request.url);
        final offset = int.parse(request.url.queryParameters['offset']!);
        return archivePage(offset, offset == 0 ? 1 : 0, 1);
      }),
    );
    await tester.tap(find.text('Chats').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(requested.map((uri) => uri.queryParameters['offset']), ['0', '5']);
    expect(requested.map((uri) => uri.queryParameters['limit']), ['5', '100']);
    for (final uri in requested) {
      expect(uri.host, 'desktop.invalid');
      expect(uri.port, 9443);
      expect(uri.scheme, 'https');
      expect(uri.path, '/hermes/api/sessions');
      expect(uri.queryParameters['profile'], 'work');
    }
    // The real projects transport is unrelated and intentionally unavailable.
    await tester.pump(const Duration(seconds: 9));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('More Unassigned shares the Home walk and shows its first five', (
    tester,
  ) async {
    final older = Completer<http.Response>();
    var fullRequests = 0;
    var refreshed = false;
    await mount(
      tester,
      active: MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          return livePage(refreshed ? [row(99)] : List.generate(5, row));
        }
        if (request.url.queryParameters['offset'] == '0') {
          fullRequests++;
          return refreshed ? livePage([row(99)]) : older.future;
        }
        return livePage([]);
      }),
      archive: MockClient((_) async => archivePage(0, 0, 0)),
    );
    await tester.tap(find.text('More').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Unassigned chats'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Live chat 0'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(fullRequests, 1);
    older.complete(livePage(List.generate(12, row)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(kWorkspaceSessionSearchKey),
      'Live chat 11',
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == 'Live chat 11'),
      findsOneWidget,
    );
    refreshed = true;
    await tester.enterText(find.byKey(kWorkspaceSessionSearchKey), '');
    unawaited(
      tester
          .state<WorkspaceSessionsScreenState>(
            find.byType(WorkspaceSessionsScreen),
          )
          .refresh(),
    );
    await tester.pumpAndSettle();
    expect(fullRequests, 2, reason: 'refresh must not reuse Home cache');
    expect(find.text('Live chat 99'), findsOneWidget);
  });
}
