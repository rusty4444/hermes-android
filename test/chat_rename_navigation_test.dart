import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/screens/workspace_sessions_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/session_search_preferences.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/inert_turn_application_session.dart';

Map<String, dynamic> _row(String title) => {
  'id': 'chat-id',
  'title': title,
  'model': 'test-model',
  'source': 'api_server',
  'message_count': 2,
  'preview': 'Original preview',
  'started_at': 1,
  'last_active': 1,
};

SavedConnection _connection() => SavedConnection(
  id: 'rename-navigation',
  label: 'Test connection',
  host: 'fixture',
  port: 8642,
  apiKey: 'test-key',
  gatewayPrefix: '/mobile',
);

MaterialApp _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: hermesTheme(Brightness.dark),
  home: child,
);

Future<void> _rename(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Chat actions').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rename'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), title);
  await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  for (final mode in SessionSearchMode.values) {
    testWidgets(
      'classic ${mode.name} list refreshes after open-chat rename and fences old reads',
      (tester) async {
        final connection = _connection();
        final preferences = await SessionSearchPreferences.open();
        final identity = '${connection.baseUrl}|/mobile|';
        await preferences.saveMode(connectionIdentity: identity, mode: mode);
        await preferences.saveAiModel(
          connectionIdentity: identity,
          selection: const AiSearchModel(
            provider: 'test-provider',
            model: 'test-small-model',
          ),
        );
        const query = 'chat';
        const renamedTitle = 'Renamed chat from header';
        final serverMode = mode != SessionSearchMode.local;
        var savedTitle = 'Original chat';
        var listRequests = 0;
        var searchRequests = 0;
        var rewriteRequests = 0;
        var holdNextList = false;
        var holdNextSearch = false;
        final oldList = Completer<http.Response>();
        final oldSearch = Completer<http.Response>();
        final writes = <http.Request>[];
        final openedSessions = <Session>[];
        http.Response listResponse(String title) => http.Response(
          jsonEncode({
            'data': [_row(title)],
            'has_more': false,
          }),
          200,
        );
        http.Response searchResponse(String title, String snippet) =>
            http.Response(
              jsonEncode({
                'results': [
                  {
                    ..._row(title),
                    'model': 'search-model',
                    'message_count': 9,
                    'preview': 'Search preview',
                    'snippet': snippet,
                    'role': 'assistant',
                    'pinned': true,
                  },
                ],
              }),
              200,
            );
        http.Client makeClient() => MockClient((request) async {
          if (request.method == 'PATCH') {
            writes.add(request);
            expectSync(request.url.path, '/mobile/api/sessions/chat-id');
            expectSync(jsonDecode(request.body), {'title': renamedTitle});
            savedTitle = renamedTitle;
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
            if ((request.url.queryParameters['offset'] ?? '0') != '0') {
              return http.Response('{"data":[]}', 200);
            }
            listRequests++;
            if (holdNextList) {
              holdNextList = false;
              return oldList.future;
            }
            return listResponse(savedTitle);
          }
          if (request.url.path == '/') {
            return http.Response(
              'window.__HERMES_SESSION_TOKEN__="fixture-token";',
              200,
            );
          }
          if (request.url.path == '/api/sessions/search') {
            expectSync(
              request.url.queryParameters['q'],
              mode == SessionSearchMode.ai ? 'chat optics' : query,
            );
            searchRequests++;
            if (holdNextSearch) {
              holdNextSearch = false;
              return oldSearch.future;
            }
            return searchResponse(savedTitle, 'Current matching excerpt');
          }
          if (request.url.path == '/mobile/v1/search/rewrite') {
            rewriteRequests++;
            expectSync(jsonDecode(request.body), {
              'query': query,
              'provider': 'test-provider',
              'model': 'test-small-model',
            });
            return http.Response('{"query":"chat optics"}', 200);
          }
          return http.Response('{"data":[]}', 200);
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
              testHttpClient: makeClient(),
              testSessionScreenBuilder: (session) {
                openedSessions.add(session);
                return ChatScreen(
                  connection: connection,
                  session: session,
                  testApiClient: ApiClient(
                    baseUrl: connection.baseUrl,
                    pathPrefix: connection.gatewayPrefix!,
                    apiKey: connection.apiKey,
                    httpClient: makeClient(),
                  ),
                  testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(SearchBar), query);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final refreshList = tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed!;
        final refreshSearch = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh;
        await tester.tap(find.text('Original chat'));
        await tester.pumpAndSettle();

        // Hold snapshots taken before the rename, then finish them last.
        holdNextList = true;
        refreshList();
        Future<void>? pendingSearch;
        if (serverMode) {
          holdNextSearch = true;
          pendingSearch = refreshSearch();
        }
        await tester.pump();
        final listsBeforeReturn = listRequests;
        final searchesBeforeReturn = searchRequests;
        await _rename(tester, renamedTitle);
        expect(writes, hasLength(1));
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(listRequests, listsBeforeReturn + 1);
        expect(searchRequests, searchesBeforeReturn + (serverMode ? 1 : 0));
        expect(find.text(renamedTitle), findsOneWidget);
        expect(find.text('Original chat'), findsNothing);
        expect(
          tester.widget<SearchBar>(find.byType(SearchBar)).controller!.text,
          query,
        );

        oldList.complete(listResponse('Original chat'));
        if (serverMode) {
          oldSearch.complete(searchResponse('Original chat', 'Stale excerpt'));
          await pendingSearch;
        }
        await tester.pumpAndSettle();
        expect(find.text(renamedTitle), findsOneWidget);
        expect(find.text('Original chat'), findsNothing);
        expect(find.text('Stale excerpt'), findsNothing);
        expect(
          find.textContaining(serverMode ? 'search-model' : 'test-model'),
          findsOneWidget,
        );
        if (serverMode) {
          expect(find.text('Current matching excerpt'), findsOneWidget);
        }
        expect(
          rewriteRequests,
          mode == SessionSearchMode.ai ? searchRequests : 0,
        );
        await tester.tap(find.text(renamedTitle));
        await tester.pumpAndSettle();
        expect(openedSessions.last.title, renamedTitle);
        expect(
          openedSessions.last.model,
          serverMode ? 'search-model' : 'test-model',
        );
        expect(openedSessions.last.messageCount, serverMode ? 9 : 2);
        expect(
          openedSessions.last.preview,
          serverMode ? 'Search preview' : 'Original preview',
        );
        expect(openedSessions.last.pinned, serverMode);
        expect(
          find.descendant(
            of: find.byType(ChatScreen),
            matching: find.text(renamedTitle),
          ),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(SearchBar), '');
        await tester.pumpAndSettle();
        expect(find.text(renamedTitle), findsOneWidget);
        expect(find.text('Original preview'), findsOneWidget);
        expect(find.textContaining('test-model'), findsOneWidget);
        expect(writes, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'classic API-only list offers Rename and persists across reopening',
    (tester) async {
      var savedTitle = 'Original chat';
      final writes = <http.Request>[];
      http.Client makeClient() => MockClient((request) async {
        expect(request.url.path, startsWith('/mobile/'));
        if (request.method == 'PATCH') {
          writes.add(request);
          expect(request.url.path, '/mobile/api/sessions/chat-id');
          expect(jsonDecode(request.body), {'title': 'Renamed chat'});
          savedTitle = 'Renamed chat';
          return http.Response(jsonEncode({'session': _row(savedTitle)}), 200);
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
        return http.Response('{"data":[]}', 200);
      });
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) => InertTurnApplicationSession(),
      );
      addTearDown(controller.close);
      Widget screen() => SessionListScreen(
        connection: _connection(),
        turnApplicationController: controller,
        testHttpClient: makeClient(),
      );
      await tester.pumpWidget(_app(screen()));
      await tester.pumpAndSettle();
      expect(find.text('Original chat'), findsOneWidget);
      await _rename(tester, 'Renamed chat');
      expect(writes, hasLength(1));
      expect(find.text('Renamed chat'), findsOneWidget);
      expect(find.text('Original preview'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(screen()));
      await tester.pumpAndSettle();
      expect(find.text('Renamed chat'), findsOneWidget);
      expect(writes, hasLength(1));
    },
  );

  testWidgets(
    'Workspace Chats queues return refresh behind a pre-rename load',
    (tester) async {
      var savedTitle = 'Original chat';
      var holdNextLoad = false;
      var loads = 0;
      final staleLoad = Completer<List<Session>>();
      final openedTitles = <String>[];
      final writes = <http.Request>[];
      final connection = _connection();
      ApiClient makeApi() => ApiClient(
        baseUrl: connection.baseUrl,
        pathPrefix: connection.gatewayPrefix!,
        apiKey: connection.apiKey,
        httpClient: MockClient((request) async {
          expect(request.url.path, startsWith('/mobile/'));
          if (request.method == 'PATCH') {
            writes.add(request);
            savedTitle = (jsonDecode(request.body) as Map)['title'] as String;
            return http.Response(
              jsonEncode({'session': _row(savedTitle)}),
              200,
            );
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
      await tester.pumpWidget(
        _app(
          WorkspaceScreen(
            connection: connection,
            sessionsLoader: () async {
              loads++;
              if (holdNextLoad) {
                holdNextLoad = false;
                return staleLoad.future;
              }
              return [Session.fromJson(_row(savedTitle))];
            },
            sessionScreenBuilder: (session) {
              openedTitles.add(session.title);
              return ChatScreen(
                connection: connection,
                session: session,
                testApiClient: makeApi(),
                testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chats').last);
      await tester.pumpAndSettle();
      expect(find.text('Original chat'), findsOneWidget);

      holdNextLoad = true;
      final staleRefresh = tester
          .state<WorkspaceSessionsScreenState>(
            find.byType(WorkspaceSessionsScreen),
          )
          .refresh();
      await tester.pump();
      await tester.tap(find.text('Original chat'));
      await tester.pumpAndSettle();
      await _rename(tester, 'Renamed while load pending');
      expect(writes, hasLength(1));
      expect(find.text('Renamed while load pending'), findsOneWidget);
      await tester.pageBack();
      // The progressive loader now has a real animated loading bar. Keep
      // the held response pending without waiting for every frame to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final loadsBeforeCompletion = loads;

      staleLoad.complete([Session.fromJson(_row('Original chat'))]);
      await staleRefresh;
      await tester.pumpAndSettle();
      expect(loads, loadsBeforeCompletion + 1);
      expect(find.text('Renamed while load pending'), findsOneWidget);
      expect(find.text('Original chat'), findsNothing);
      expect(find.text('Original preview'), findsOneWidget);

      await tester.enterText(
        find.byKey(kWorkspaceSessionSearchKey),
        'Original chat',
      );
      await tester.pumpAndSettle();
      expect(find.text('Renamed while load pending'), findsNothing);
      await tester.enterText(
        find.byKey(kWorkspaceSessionSearchKey),
        'Renamed while load pending',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data == 'Renamed while load pending',
        ),
      );
      await tester.pumpAndSettle();
      expect(openedTitles.last, 'Renamed while load pending');
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatScreen),
          matching: find.text('Renamed while load pending'),
        ),
        findsOneWidget,
      );
      expect(writes, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Workspace Chats wires Rename to API and refreshes after chat return',
    (tester) async {
      var savedTitle = 'Original chat';
      final writes = <http.Request>[];
      http.Client makeClient() => MockClient((request) async {
        expect(request.url.path, startsWith('/mobile/'));
        if (request.method == 'PATCH') {
          writes.add(request);
          savedTitle = (jsonDecode(request.body) as Map)['title'] as String;
          return http.Response(jsonEncode({'session': _row(savedTitle)}), 200);
        }
        if (request.url.path.endsWith('/messages')) {
          return http.Response('{"data":[]}', 200);
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
        return http.Response('{}', 200);
      });
      final connection = _connection();
      await tester.pumpWidget(
        _app(
          WorkspaceScreen(
            connection: connection,
            testSessionsHttpClient: makeClient(),
            sessionScreenBuilder: (session) => ChatScreen(
              connection: connection,
              session: session,
              testApiClient: ApiClient(
                baseUrl: connection.baseUrl,
                pathPrefix: connection.gatewayPrefix!,
                apiKey: 'test-key',
                httpClient: makeClient(),
              ),
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chats').last);
      await tester.pumpAndSettle();
      expect(find.text('Original chat'), findsOneWidget);
      await _rename(tester, 'From Chats');
      expect(writes, hasLength(1));
      expect(find.text('From Chats'), findsOneWidget);
      await tester.tap(find.text('From Chats'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      await _rename(tester, 'From open chat');
      expect(writes, hasLength(2));
      expect(find.text('From open chat'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('From open chat'), findsOneWidget);
      expect(find.text('From Chats'), findsNothing);
      expect(find.text('Original preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
