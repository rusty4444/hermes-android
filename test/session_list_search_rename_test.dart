import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/session_search_preferences.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/inert_turn_application_session.dart';

Map<String, dynamic> _row(String title) => {
  'id': 'chat-id',
  'title': title,
  'model': 'list-model',
  'source': 'api_server',
  'message_count': 2,
  'preview': 'List preview',
  'started_at': 1,
  'last_active': 1,
};

Map<String, dynamic> _hit(String title, String snippet) => {
  ..._row(title),
  'model': 'search-model',
  'message_count': 9,
  'preview': 'Search preview',
  'snippet': snippet,
  'role': 'assistant',
  'pinned': true,
  '_lineage_root_id': 'lineage-root',
};

http.Response _searchResponse(String title, String snippet) => http.Response(
  jsonEncode({
    'results': [
      _hit(title, snippet),
      {..._hit('Unrelated hit', 'Other excerpt'), 'id': 'other-id'},
    ],
  }),
  200,
);

MaterialApp _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: child,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in [SessionSearchMode.server, SessionSearchMode.ai]) {
    testWidgets(
      '${mode.name} search renames current hits and fences a delayed old response',
      (tester) async {
        final connection = SavedConnection(
          id: 'search-rename-${mode.name}',
          label: 'Search connection',
          host: 'fixture',
          port: 8642,
          apiKey: 'test-key',
          gatewayPrefix: '/mobile',
          dashboardPrefix: '/dashboard',
          dashboardProxied: true,
        );
        final identity = '${connection.baseUrl}|/mobile|';
        final preferences = await SessionSearchPreferences.open();
        await preferences.saveMode(connectionIdentity: identity, mode: mode);
        await preferences.saveAiModel(
          connectionIdentity: identity,
          selection: const AiSearchModel(
            provider: 'test-provider',
            model: 'test-small-model',
          ),
        );

        const query = 'find telescope discussions';
        const rewrittenQuery = 'telescope optics';
        var savedTitle = 'Original title';
        var searchRequests = 0;
        var rewriteRequests = 0;
        final writes = <http.Request>[];
        final delayedSearch = Completer<http.Response>();
        final client = MockClient((request) async {
          if (request.url.path == '/dashboard/api/sessions/search') {
            searchRequests++;
            expectSync(
              request.url.queryParameters['q'],
              mode == SessionSearchMode.ai ? rewrittenQuery : query,
            );
            if (searchRequests == 2) return delayedSearch.future;
            return _searchResponse(savedTitle, 'Initial matching excerpt');
          }
          if (request.url.path == '/mobile/v1/search/rewrite') {
            rewriteRequests++;
            expectSync(jsonDecode(request.body), {
              'query': query,
              'provider': 'test-provider',
              'model': 'test-small-model',
            });
            return http.Response(jsonEncode({'query': rewrittenQuery}), 200);
          }
          if (request.method == 'PATCH') {
            writes.add(request);
            expectSync(request.url.path, '/mobile/api/sessions/chat-id');
            expectSync(jsonDecode(request.body), {'title': 'Requested title'});
            // The saved title, not the requested text or sparse response row,
            // must be merged into the rich search hit.
            savedTitle = 'Authoritative saved title';
            return http.Response(
              jsonEncode({
                'session': {'id': 'chat-id', 'title': savedTitle},
              }),
              200,
            );
          }
          if (request.url.path == '/mobile/health') {
            return http.Response('{"status":"ok"}', 200);
          }
          if (request.url.path == '/mobile/api/sessions') {
            return http.Response(
              jsonEncode({
                'data': [_row(savedTitle)],
                'has_more': false,
              }),
              200,
            );
          }
          fail('Unexpected request: ${request.method} ${request.url}');
        });
        final controller = GatewayTurnApplicationController(
          sessionFactory: (_) => InertTurnApplicationSession(),
        );
        addTearDown(controller.close);
        await tester.pumpWidget(
          _app(
            SessionListScreen(
              connection: connection,
              turnApplicationController: controller,
              testHttpClient: client,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(SearchBar), query);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(searchRequests, 1);
        expect(find.text('Original title'), findsOneWidget);
        expect(find.text('Initial matching excerpt'), findsOneWidget);

        final row = find.ancestor(
          of: find.text('Original title'),
          matching: find.byType(ListTile),
        );
        await tester.tap(
          find.descendant(of: row, matching: find.byTooltip('Chat actions')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Requested title');

        // Start a second search before the save and hold its old snapshot.
        final pendingRefresh = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pump();
        expect(searchRequests, 2);
        await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(writes, hasLength(1));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Authoritative saved title'), findsOneWidget);
        expect(find.text('Original title'), findsNothing);
        expect(find.text('Requested title'), findsNothing);
        expect(find.text('Initial matching excerpt'), findsOneWidget);
        expect(find.text('Unrelated hit'), findsOneWidget);
        expect(find.textContaining('search-model'), findsNWidgets(2));
        expect(find.textContaining('list-model'), findsNothing);

        delayedSearch.complete(
          _searchResponse('Original title', 'Delayed matching excerpt'),
        );
        await pendingRefresh;
        await tester.pumpAndSettle();

        expect(find.text('Authoritative saved title'), findsOneWidget);
        expect(find.text('Original title'), findsNothing);
        expect(find.text('Delayed matching excerpt'), findsOneWidget);
        expect(find.text('Initial matching excerpt'), findsNothing);
        expect(find.text('Other excerpt'), findsOneWidget);
        expect(find.textContaining('search-model'), findsNWidgets(2));
        expect(searchRequests, 2);
        final searchBar = tester.widget<SearchBar>(find.byType(SearchBar));
        expect(searchBar.controller!.text, query);
        expect(
          searchBar.hintText,
          mode == SessionSearchMode.ai
              ? 'Ask AI to find a conversation'
              : 'Search all message content',
        );
        if (mode == SessionSearchMode.ai) {
          expect(rewriteRequests, 2);
          expect(find.textContaining(rewrittenQuery), findsOneWidget);
        } else {
          expect(rewriteRequests, 0);
        }

        // Do not turn the fence into a permanent local title override: a
        // search started after the save may see a newer edit on another device.
        savedTitle = 'Newer title from another device';
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await tester.pumpAndSettle();
        expect(searchRequests, 3);
        expect(find.text('Newer title from another device'), findsOneWidget);
        expect(find.text('Authoritative saved title'), findsNothing);
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          query,
        );
        expect(writes, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
