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

  testWidgets(
    'model search filters names and providers without changing selection',
    (tester) async {
      final fixture = await _pumpSearchableModelChat(tester);
      await _openModelPicker(tester);
      final search = find.byKey(const Key('chat-model-search'));
      final apply = find.widgetWithText(FilledButton, 'Apply to this chat');

      await tester.enterText(search, '  FaBlE  ');
      await tester.pump();
      expect(find.text('anthropic/claude-fable-5'), findsOneWidget);
      expect(find.text('gpt-5'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('shared-model'),
        ),
        findsNothing,
      );
      expect(fixture.writes, isEmpty);

      // A provider match returns that provider's models, not every copy of a
      // shared model id. Typing must never resolve ambiguous choices for us.
      await tester.enterText(search, '  BeTa  ');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('shared-model'),
        ),
        findsOneWidget,
      );
      expect(find.text('beta'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('shared-model'),
        ),
      );
      await tester.pump();

      // Hiding a selected row must not discard it or select the first result.
      await tester.enterText(search, 'no-such-model');
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget);
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      expect(fixture.writes, isEmpty);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('shared-model'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('anthropic/claude-fable-5'), findsOneWidget);
      await tester.tap(apply);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(fixture.writes, [
        {
          'provider': 'beta',
          'model': 'shared-model',
          'require_model_lock': true,
        },
      ]);
    },
  );

  testWidgets('cancelled model search resets when the picker reopens', (
    tester,
  ) async {
    final fixture = await _pumpSearchableModelChat(tester);
    await _openModelPicker(tester);
    final search = find.byKey(const Key('chat-model-search'));
    await tester.enterText(search, 'not-a-model');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(fixture.writes, isEmpty);
    await _openModelPicker(tester);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('shared-model'),
      ),
      findsNWidgets(2),
    );
    expect(find.text('No matches'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  for (final scenario in [
    (412.0, 860.0, 340.0, 1.0),
    (320.0, 860.0, 340.0, 2.0),
    (860.0, 412.0, 180.0, 1.0),
  ]) {
    final (width, height, keyboardHeight, textScale) = scenario;
    testWidgets('model search remains usable above the keyboard at '
        '$width x $height, scale $textScale', (tester) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpSearchableModelChat(tester, textScale: textScale);
      await _openModelPicker(tester);
      final search = find.byKey(const Key('chat-model-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'fable');
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(search);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(search).bottom,
        lessThanOrEqualTo(height - keyboardHeight),
      );
      final result = find.text('anthropic/claude-fable-5');
      await tester.ensureVisible(result);
      await tester.tap(result);
      await tester.pump();
      final apply = find.widgetWithText(FilledButton, 'Apply to this chat');
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      expect(
        tester.getRect(apply).bottom,
        lessThanOrEqualTo(height - keyboardHeight),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
  }

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

Future<void> _openModelPicker(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Choose chat model'));
  // A progress spinner stays active while this modal is open.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<({List<Map<String, dynamic>> writes})> _pumpSearchableModelChat(
  WidgetTester tester, {
  double textScale = 1,
}) async {
  final writes = <Map<String, dynamic>>[];
  final client = ApiClient(
    baseUrl: 'http://api.fixture:8642',
    apiKey: 'fixture-key',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'GET' && path.endsWith('/messages')) {
        return http.Response('{"data":[]}', 200);
      }
      if (request.method == 'GET' && path == '/api/sessions/search-session') {
        return http.Response('{"session":{"model":"shared-model"}}', 200);
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
              {
                'slug': 'nous',
                'models': ['anthropic/claude-fable-5', 'gpt-5'],
              },
            ],
          }),
          200,
        );
      }
      if (request.method == 'POST' && path.endsWith('/model')) {
        writes.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{}', 200);
      }
      return http.Response('not found', 404);
    }),
  );
  await _pumpApiOnlyChat(
    tester,
    client,
    const Session(
      id: 'search-session',
      title: 'Search models',
      model: 'shared-model',
      source: 'api_server',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: 1,
    ),
    textScale: textScale,
  );
  return (writes: writes);
}

Future<void> _pumpApiOnlyChat(
  WidgetTester tester,
  ApiClient apiClient,
  Session session, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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
