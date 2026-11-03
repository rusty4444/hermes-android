import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/local_chat_pin_store.dart';
import 'package:hermes_android/core/services/quick_chat_store.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/utils/home_turn_signals.dart';
import 'package:hermes_android/core/widgets/hermes_components.dart';

import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> _row(int index, {bool pinned = false}) => {
  'id': 'session-$index',
  'title': index == 101 ? 'Late unassigned' : 'Chat $index',
  'model': 'test',
  'source': 'gateway',
  'message_count': 1,
  'started_at': DateTime.now().millisecondsSinceEpoch / 1000.0 - index,
  'pinned': pinned,
};

http.Response _page(List<Map<String, Object?>> rows) => http.Response(
  jsonEncode({'object': 'list', 'data': rows, 'has_more': false}),
  200,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'five-row Chats preview retains older work, local pins and Quick deadlines',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final laterPage = Completer<http.Response>();
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        final limit = request.url.queryParameters['limit'];
        final offset = request.url.queryParameters['offset'];
        if (limit == '5') {
          // Stock can append pinned rows outside the requested window.
          return _page([...List.generate(5, _row), _row(100, pinned: true)]);
        }
        if (offset == '0') {
          return _page([...List.generate(100, _row), _row(100, pinned: true)]);
        }
        if (offset == '100') return laterPage.future;
        return _page([]);
      });
      final connection = SavedConnection(
        id: 'progressive-test',
        label: 'Test',
        host: 'example.invalid',
        port: 8642,
        apiKey: 'test-key',
      );
      final preferences = await SharedPreferences.getInstance();
      final quick = QuickChatStore(preferences, connectionId: connection.id);
      await quick.record(
        'session-101',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      // A bounded or mutable OFFSET scan cannot prove this old chat was
      // deleted; its archive deadline must survive a completed Home scan.
      await quick.record(
        'session-beyond-scan',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final pins = LocalChatPinStore(preferences, connectionId: connection.id);
      await pins.setPinned('session-101', pinned: true);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceScreen(
            connection: connection,
            testSessionsHttpClient: client,
            turnSignalsLoader: (_) async => const HomeTurnSignals(
              attention: {'session-100': 'Approval required'},
              running: {'session-101'},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(requested.first.queryParameters['limit'], '5');
      expect(requested.first.queryParameters['offset'], '0');
      expect(find.text('Chat 0'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Chat 100'), findsOneWidget);
      expect(find.text('Late unassigned'), findsNothing);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect((await quick.load()).expiries, contains('session-101'));
      expect((await quick.load()).expiries, contains('session-beyond-scan'));
      expect(await pins.load(), contains('session-101'));

      final home = tester.state<WorkspaceSessionsScreenState>(
        find.byType(WorkspaceSessionsScreen),
      );
      final refreshed = home.refresh();
      expect(identical(home.refresh(), refreshed), isTrue);
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        requested.where(
          (uri) =>
              uri.queryParameters['limit'] == '100' &&
              uri.queryParameters['offset'] == '0',
        ),
        // Explicit refresh now starts independently of the older aggregate.
        // Both full scans remain held on their later page, preserving the
        // original pin/Quick/retained-history harmful ordering.
        hasLength(2),
      );

      laterPage.complete(_page([_row(100, pinned: true), _row(101)]));
      await tester.pumpAndSettle();
      await refreshed;
      expect(
        requested.any((uri) => uri.queryParameters['offset'] == '100'),
        isTrue,
      );
      expect(find.text('Chat 100'), findsOneWidget);
      expect(find.text('Approval required'), findsOneWidget);
      expect(find.text('Late unassigned'), findsNWidgets(2));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect((await quick.load()).expiries, contains('session-101'));
      expect((await quick.load()).expiries, contains('session-beyond-scan'));
      expect(await pins.load(), contains('session-101'));

      final completePageRequests = requested
          .where((uri) => uri.queryParameters['limit'] == '100')
          .length;
      await tester.tap(find.text('Chats').last);
      await tester.pump();
      // Home's complete list is already in memory. Chats must be usable
      // before the optional Projects/archived metadata completes, without
      // paying for the twenty-page walk a second time.
      expect(
        find.descendant(
          of: find.byType(WorkspaceSessionsScreen),
          matching: find.text('Chat 0'),
        ),
        findsOneWidget,
      );
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(
        requested.where((uri) => uri.queryParameters['limit'] == '100'),
        hasLength(completePageRequests),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceSessionsScreen), findsOneWidget);
      // Search proves the old unassigned row is in the complete Chats dataset,
      // not just a Home-only background projection.
      await tester.enterText(
        find.byKey(kWorkspaceSessionSearchKey),
        'Late unassigned',
      );
      await tester.pumpAndSettle();
      expect(find.text('Late unassigned'), findsNWidgets(2));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Unassigned'));
      await tester.pumpAndSettle();
      expect(find.text('Late unassigned'), findsNWidgets(2));
    },
  );

  testWidgets(
    'explicit refreshes share a fresh scan independently of bootstrap',
    (tester) async {
      final held = Completer<http.Response>();
      final freshHeld = Completer<http.Response>();
      addTearDown(() {
        if (!held.isCompleted) held.complete(_page([]));
        if (!freshHeld.isCompleted) freshHeld.complete(_page([]));
      });
      var fullReads = 0;
      var firstReads = 0;
      final client = MockClient((request) async {
        if (request.url.queryParameters['limit'] == '5') {
          firstReads++;
          return _page([_row(0)]);
        }
        if (request.url.queryParameters['offset'] == '0') {
          fullReads++;
          return fullReads == 1 ? held.future : freshHeld.future;
        }
        return _page([]);
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceScreen(
            connection: SavedConnection(
              id: 'queued',
              label: 'Test',
              host: 'example.invalid',
              port: 8642,
              apiKey: 'test-key',
            ),
            testSessionsHttpClient: client,
            turnSignalsLoader: (_) async => HomeTurnSignals.empty,
          ),
        ),
      );
      await tester.pump();
      final browser = tester.state<WorkspaceSessionsScreenState>(
        find.byType(WorkspaceSessionsScreen),
      );
      final refresh = browser.refresh();
      expect(identical(browser.refresh(), refresh), isTrue);
      var refreshCompleted = false;
      unawaited(refresh.then((_) => refreshCompleted = true));
      await tester.pump();
      expect(firstReads, 2);
      expect(fullReads, 2);
      expect(find.text('Chat 0'), findsOneWidget);
      held.complete(_page([_row(0)]));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(refreshCompleted, isFalse);
      expect(find.text('Fresh title'), findsNothing);
      freshHeld.complete(
        _page([
          {..._row(0), 'title': 'Fresh title'},
        ]),
      );
      await tester.pumpAndSettle();
      await refresh;
      expect(refreshCompleted, isTrue);
      expect(firstReads, 2);
      expect(fullReads, 2);
      expect(find.text('Fresh title'), findsOneWidget);
      expect(find.text('Chat 0'), findsNothing);
    },
  );

  testWidgets(
    'opening Crons during a Chats scan shares and replays the pending request',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final laterPage = Completer<http.Response>();
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        if (request.url.queryParameters['limit'] == '5') {
          return _page(List.generate(5, _row));
        }
        if (request.url.queryParameters['offset'] == '0') {
          return _page(
            List.generate(
              100,
              (i) => {..._row(i), if (i >= 10) 'source': 'cron'},
            ),
          );
        }
        return laterPage.future;
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: hermesTheme(Brightness.dark),
          home: WorkspaceScreen(
            connection: SavedConnection(
              id: 'early-switch',
              label: 'Test',
              host: 'example.invalid',
              port: 8642,
              apiKey: 'test-key',
            ),
            testSessionsHttpClient: client,
            turnSignalsLoader: (_) async => HomeTurnSignals.empty,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        requested.where((uri) => uri.queryParameters['limit'] == '100'),
        hasLength(2),
      );

      await tester.tap(find.text('Crons').last);
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.descendant(
          of: find.byType(WorkspaceSessionsScreen),
          matching: find.text('Chat 10'),
        ),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsNothing);
      expect(
        requested.where(
          (uri) =>
              uri.queryParameters['limit'] == '100' &&
              uri.queryParameters['offset'] == '0',
        ),
        hasLength(1),
      );

      laterPage.complete(_page([]));
      await tester.pumpAndSettle();
      expect(find.text('Chat 10'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('Chats fills its preview from the scan when five rows are cron', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final firstFullPage = Completer<http.Response>();
    final laterPage = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.queryParameters['limit'] == '5') {
        return _page([
          for (var i = 0; i < 5; i++) {..._row(i), 'source': 'cron'},
        ]);
      }
      if (request.url.queryParameters['offset'] == '0') {
        return firstFullPage.future;
      }
      return laterPage.future;
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: hermesTheme(Brightness.dark),
        home: WorkspaceScreen(
          connection: SavedConnection(
            id: 'cron-preview',
            label: 'Test',
            host: 'example.invalid',
            port: 8642,
            apiKey: 'test-key',
          ),
          testSessionsHttpClient: client,
          turnSignalsLoader: (_) async => HomeTurnSignals.empty,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.text('Chats').last);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.text('Chat 0'), findsNothing);

    firstFullPage.complete(
      _page([
        for (var i = 0; i < 100; i++)
          if (i >= 5 && i < 10) _row(i) else {..._row(i), 'source': 'cron'},
      ]),
    );
    await tester.pump();
    expect(find.text('Chat 5'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    laterPage.complete(_page([]));
    await tester.pumpAndSettle();
    expect(find.text('Chat 5'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
