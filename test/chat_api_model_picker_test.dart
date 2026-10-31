import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

void main() {
  setUp(mockChatImageRecovery);
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets(
    'API-server-only model picker lists and applies models without Dashboard',
    (tester) async {
      final requests = <http.Request>[];
      final requestBodies = <String, Map<String, dynamic>>{};
      final apiClient = ApiClient(
        baseUrl: 'http://api.fixture:8642',
        apiKey: 'fixture-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.url.host, 'api.fixture');
          expect(request.url.port, 8642);
          if (request.method == 'GET' &&
              request.url.path == '/api/sessions/api-session/messages') {
            return http.Response('{"data":[]}', 200);
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/sessions/api-session') {
            return http.Response(
              jsonEncode({
                'object': 'hermes.session',
                'session': {'id': 'api-session', 'model': 'old-model'},
              }),
              200,
            );
          }
          if (request.method == 'GET' &&
              request.url.path == '/api/model/options') {
            return http.Response(
              jsonEncode({
                'model': 'profile-model',
                'provider': 'nous',
                'providers': [
                  {
                    'slug': 'nous',
                    'models': ['old-model', 'new-model'],
                  },
                ],
              }),
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/api/sessions/api-session/model') {
            requestBodies[request.url.path] =
                jsonDecode(request.body) as Map<String, dynamic>;
            expect(jsonDecode(request.body), {
              'provider': 'nous',
              'model': 'new-model',
              'require_model_lock': true,
            });
            return http.Response(
              '{"object":"hermes.session.model_lock",'
              '"session_id":"api-session"}',
              200,
            );
          }
          if (request.method == 'POST' &&
              request.url.path == '/v1/chat/completions') {
            requestBodies[request.url.path] =
                jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              'data: {"choices":[{"delta":{"content":"Done"}}]}\n\n'
              'data: [DONE]\n\n',
              200,
              headers: const {'content-type': 'text/event-stream'},
            );
          }
          return http.Response('not found', 404);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(
            connection: SavedConnection(
              id: 'api-only',
              label: 'API only',
              host: 'api.fixture',
              port: 8642,
              apiKey: 'fixture-key',
            ),
            session: const Session(
              id: 'api-session',
              title: 'API chat',
              model: 'stale-list-model',
              source: 'api_server',
              messageCount: 0,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: apiClient,
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await pumpChatUpdates(tester);

      await tester.tap(find.bySemanticsLabel('Choose chat model'));
      // The picker button intentionally keeps a progress spinner active while
      // its modal is open, so pumpAndSettle cannot become idle here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Profile default: profile-model • nous'),
        findsOneWidget,
      );
      expect(find.text('new-model'), findsOneWidget);
      await tester.tap(find.text('new-model'));
      await tester.tap(find.text('Apply to this chat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        containsAll([
          'GET /api/sessions/api-session',
          'GET /api/model/options',
          'POST /api/sessions/api-session/model',
        ]),
      );
      expect(requests.any((request) => request.url.port == 9119), isFalse);
      expect(find.textContaining('new-model'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'Use the selected model');
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await pumpChatUpdates(tester);

      final lockIndex = requests.indexWhere(
        (request) =>
            request.method == 'POST' &&
            request.url.path == '/api/sessions/api-session/model',
      );
      final chatIndex = requests.indexWhere(
        (request) =>
            request.method == 'POST' &&
            request.url.path == '/v1/chat/completions',
      );
      expect(chatIndex, greaterThan(lockIndex));
      expect(
        requestBodies['/v1/chat/completions'],
        containsPair('model', 'new-model'),
      );
      expect(
        requestBodies['/v1/chat/completions'],
        containsPair('provider', 'nous'),
      );
      expect(requests.any((request) => request.url.port == 9119), isFalse);
    },
  );

  testWidgets('draft selection creates the lock before the first turn', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final bodies = <String, Map<String, dynamic>>{};
    final apiClient = ApiClient(
      baseUrl: 'http://api.fixture:8642',
      apiKey: 'fixture-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'GET' &&
            path == '/api/sessions/draft-session/messages') {
          return http.Response('{"data":[]}', 200);
        }
        if (request.method == 'GET' && path == '/api/model/options') {
          return http.Response(
            jsonEncode({
              'model': 'old-model',
              'provider': 'nous',
              'providers': [
                {
                  'slug': 'nous',
                  'models': ['old-model', 'new-model'],
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' && path == '/api/sessions') {
          bodies[path] = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            '{"object":"hermes.session","session":{"id":"draft-session"}}',
            201,
          );
        }
        if (request.method == 'POST' && path == '/v1/chat/completions') {
          bodies[path] = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            'data: {"choices":[{"delta":{"content":"Done"}}]}\n\n'
            'data: [DONE]\n\n',
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await _pumpApiOnlyChat(
      tester,
      apiClient,
      const Session(
        id: 'draft-session',
        title: 'Draft chat',
        model: 'old-model',
        source: 'api_server',
        messageCount: 0,
        isActive: true,
        isLocalDraft: true,
        preview: '',
        startedAt: 1,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Choose chat model'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('new-model'));
    await tester.tap(find.text('Apply to this chat'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      requests.any(
        (request) =>
            request.method == 'GET' &&
            request.url.path == '/api/sessions/draft-session',
      ),
      isFalse,
    );
    expect(bodies['/api/sessions'], {
      'id': 'draft-session',
      'source': 'api_server',
      'provider': 'nous',
      'model': 'new-model',
      'require_model_lock': true,
    });

    await tester.enterText(find.byType(TextField), 'First turn');
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await pumpChatUpdates(tester);

    final createIndex = requests.indexWhere(
      (request) =>
          request.method == 'POST' && request.url.path == '/api/sessions',
    );
    final chatIndex = requests.indexWhere(
      (request) =>
          request.method == 'POST' &&
          request.url.path == '/v1/chat/completions',
    );
    expect(chatIndex, greaterThan(createIndex));
    expect(bodies['/v1/chat/completions'], containsPair('model', 'new-model'));
    expect(bodies['/v1/chat/completions'], containsPair('provider', 'nous'));
  });

  testWidgets('duplicate model ids require an explicit provider choice', (
    tester,
  ) async {
    Map<String, dynamic>? lockBody;
    final apiClient = ApiClient(
      baseUrl: 'http://api.fixture:8642',
      apiKey: 'fixture-key',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' &&
            path == '/api/sessions/duplicate-session/messages') {
          return http.Response('{"data":[]}', 200);
        }
        if (request.method == 'GET' &&
            path == '/api/sessions/duplicate-session') {
          return http.Response(
            '{"session":{"id":"duplicate-session","model":"shared-model"}}',
            200,
          );
        }
        if (request.method == 'GET' && path == '/api/model/options') {
          return http.Response(
            jsonEncode({
              'model': 'shared-model',
              'provider': 'alpha',
              'providers': [
                {
                  'slug': 'alpha',
                  'models': ['shared-model'],
                },
                {
                  'slug': 'beta',
                  'models': ['shared-model'],
                },
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            path == '/api/sessions/duplicate-session/model') {
          lockBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        }
        return http.Response('not found', 404);
      }),
    );

    await _pumpApiOnlyChat(
      tester,
      apiClient,
      const Session(
        id: 'duplicate-session',
        title: 'Duplicate model chat',
        model: 'shared-model',
        source: 'api_server',
        messageCount: 0,
        isActive: true,
        preview: '',
        startedAt: 1,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Choose chat model'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text(
        'This model is available from multiple providers. Choose a provider to continue.',
      ),
      findsOneWidget,
    );
    final applyFinder = find.widgetWithText(FilledButton, 'Apply to this chat');
    expect(tester.widget<FilledButton>(applyFinder).onPressed, isNull);

    await tester.tap(find.text('beta'));
    await tester.pump();
    expect(tester.widget<FilledButton>(applyFinder).onPressed, isNotNull);
    await tester.tap(applyFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(lockBody, containsPair('provider', 'beta'));
    expect(lockBody, containsPair('model', 'shared-model'));
  });
}

Future<void> _pumpApiOnlyChat(
  WidgetTester tester,
  ApiClient apiClient,
  Session session,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'api-only-test',
          label: 'API only',
          host: 'api.fixture',
          port: 8642,
          apiKey: 'fixture-key',
        ),
        session: session,
        testApiClient: apiClient,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await pumpChatUpdates(tester);
}
