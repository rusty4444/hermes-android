import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/completed_stock_turn.dart';

void main() {
  setUp(() {
    // These hydration/admission races assert raw saved history, not final-only
    // quiet policy; leave the untyped source fixtures unchanged.
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
  });

  testWidgets(
    'remote chat remains usable while bounded history hydration is pending',
    (tester) async {
      final httpClient = _DelayedMessagesHttpClient();
      addTearDown(httpClient.release);
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final apiClient = ApiClient(
        baseUrl: 'http://large-session.fixture',
        apiKey: 'fixture-key',
        httpClient: httpClient,
      );
      var submitted = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: preferredSupportedLocales(),
          localeListResolutionCallback: resolvePreferredLocale,
          home: ChatScreen(
            connection: SavedConnection(
              id: 'large-session-fixture',
              label: 'Large session fixture',
              host: 'large-session.fixture',
              port: 8642,
              apiKey: 'fixture-key',
            ),
            session: const Session(
              id: 'stored-large-session',
              title: 'Large chat',
              model: 'fixture-model',
              source: 'api_server',
              messageCount: 4261,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: apiClient,
            turnApplicationController: controller,
            testRemotePromptSubmit: completedStockTurn(({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              submitted += 1;
              onSent();
            }),
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await tester.pump();

      final messagesUri = await httpClient.messagesUri.future;
      expect(messagesUri.queryParameters, {'limit': '50', 'order': 'latest'});
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-message-composer')))
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.attach_file),
            )
            .onPressed,
        isNotNull,
      );

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'Prompt while history is loading',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      expect(submitted, 1);
      final snapshot = _ownerSnapshot(controller, tester);
      expect(snapshot.phase, NormalGatewayTurnPhase.completed);
      expect(snapshot.rowFloor, isNull);
      expect(snapshot.historyRows.last['content'], 'Fresh reply');
      expect(snapshot.displayRows, isEmpty);
      expect(snapshot.timeline.runs, isEmpty);
      expect(find.text('Prompt while history is loading'), findsOneWidget);

      httpClient.release();
      final refreshedMessagesUri = await httpClient.refreshedMessagesUri.future;
      expect(refreshedMessagesUri.queryParameters, {
        'limit': '50',
        'order': 'latest',
      });
      await tester.pumpAndSettle();

      expect(find.text('Stale transcript row'), findsNothing);
      expect(find.text('Existing transcript row'), findsOneWidget);
      expect(find.text('Prompt while history is loading'), findsOneWidget);
      expect(find.text('Fresh reply'), findsOneWidget);
    },
  );

  testWidgets(
    'failed remote send restores the pending authoritative transcript',
    (tester) async {
      final httpClient = _DelayedMessagesHttpClient(
        refreshedMessages: const [
          {'role': 'assistant', 'content': 'Existing transcript row'},
        ],
      );
      final failSubmit = Completer<void>();
      addTearDown(() {
        httpClient.release();
        if (!failSubmit.isCompleted) failSubmit.complete();
      });
      final apiClient = ApiClient(
        baseUrl: 'http://large-session.fixture',
        apiKey: 'test-key',
        httpClient: httpClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: preferredSupportedLocales(),
          localeListResolutionCallback: resolvePreferredLocale,
          home: ChatScreen(
            connection: SavedConnection(
              id: 'large-session-fixture',
              label: 'Large session fixture',
              host: 'large-session.fixture',
              port: 8642,
              apiKey: 'test-key',
            ),
            session: const Session(
              id: 'stored-large-session',
              title: 'Large chat',
              model: 'fixture-model',
              source: 'api_server',
              messageCount: 4261,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: apiClient,
            testRemotePromptSubmit: completedStockTurn(({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              await failSubmit.future;
              throw StateError('submit rejected');
            }),
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await tester.pump();
      await httpClient.messagesUri.future;

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'Keep this draft',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      httpClient.release();
      await httpClient.firstResponseReturned.future;
      await tester.pump();
      failSubmit.complete();
      await httpClient.refreshedMessagesUri.future;
      await tester.pumpAndSettle();

      expect(find.text('Stale transcript row'), findsNothing);
      expect(find.text('Existing transcript row'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-message-composer')))
            .controller
            ?.text,
        'Keep this draft',
      );
    },
  );

  testWidgets(
    'a newer turn prevents an older deferred refresh from replacing it',
    (tester) async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      var submitted = 0;
      final httpClient = _MultiTurnRaceHttpClient(() => submitted);
      addTearDown(httpClient.releaseAll);
      final apiClient = ApiClient(
        baseUrl: 'http://large-session.fixture',
        apiKey: 'test-key',
        httpClient: httpClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: preferredSupportedLocales(),
          localeListResolutionCallback: resolvePreferredLocale,
          home: ChatScreen(
            connection: SavedConnection(
              id: 'large-session-fixture',
              label: 'Large session fixture',
              host: 'large-session.fixture',
              port: 8642,
              apiKey: 'test-key',
            ),
            session: const Session(
              id: 'stored-large-session',
              title: 'Large chat',
              model: 'fixture-model',
              source: 'api_server',
              messageCount: 4261,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            testApiClient: apiClient,
            turnApplicationController: controller,
            testRemotePromptSubmit: completedStockTurn(({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              submitted += 1;
              onSent();
            }),
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await tester.pump();
      await httpClient.firstMessagesUri.future;

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'First turn',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      httpClient.releaseFirst();
      await httpClient.deferredRefreshUri.future;
      await tester.pump();
      expect(submitted, 1);

      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'Second turn',
      );
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(submitted, 2);

      httpClient.releaseDeferredRefresh();
      await httpClient.authoritativeRefreshUri.future;
      await tester.pumpAndSettle();

      expect(find.text('Pre-second-turn snapshot'), findsNothing);
      final snapshot = _ownerSnapshot(controller, tester);
      expect(snapshot.historyRows.first['content'], 'Existing transcript row');
      expect(snapshot.historyRows.last['content'], 'Second reply');
      expect(snapshot.displayRows, isEmpty);
      // Verbose keeps the independent saved/received sections; reveal the
      // earlier saved rows instead of relying on their lazy layout at the end.
      await tester.scrollUntilVisible(
        find.text('Existing transcript row'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Existing transcript row'), findsOneWidget);
      expect(find.text('First turn'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Second reply'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Second turn'), findsOneWidget);
      expect(find.text('Second reply'), findsOneWidget);
    },
  );

  testWidgets('stopping a remote turn releases its deferred history refresh', (
    tester,
  ) async {
    final httpClient = _DelayedMessagesHttpClient(
      refreshedMessages: const [
        {'role': 'assistant', 'content': 'Existing transcript row'},
      ],
    );
    final submitGate = Completer<void>();
    addTearDown(() {
      httpClient.release();
      if (!submitGate.isCompleted) submitGate.complete();
    });
    final apiClient = ApiClient(
      baseUrl: 'http://large-session.fixture',
      apiKey: 'test-key',
      httpClient: httpClient,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: preferredSupportedLocales(),
        localeListResolutionCallback: resolvePreferredLocale,
        home: ChatScreen(
          connection: SavedConnection(
            id: 'large-session-fixture',
            label: 'Large session fixture',
            host: 'large-session.fixture',
            port: 8642,
            apiKey: 'test-key',
          ),
          session: const Session(
            id: 'stored-large-session',
            title: 'Large chat',
            model: 'fixture-model',
            source: 'api_server',
            messageCount: 4261,
            isActive: true,
            preview: '',
            startedAt: 1,
          ),
          testApiClient: apiClient,
          testRemotePromptSubmit: completedStockTurn(({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            onSent();
            await submitGate.future;
          }),
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      ),
    );
    await tester.pump();
    await httpClient.messagesUri.future;

    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      'Stop this turn',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    httpClient.release();
    await httpClient.firstResponseReturned.future;
    await tester.pump();

    await tester.tap(find.byTooltip('Stop response'));
    // The fixture now supplies the server terminal receipt. A stop RPC ack
    // alone must not settle an app-owned stock turn.
    submitGate.complete();
    await httpClient.refreshedMessagesUri.future;
    await tester.pumpAndSettle();

    expect(find.text('Stale transcript row'), findsNothing);
    expect(find.text('Existing transcript row'), findsOneWidget);
  });
}

NormalGatewayChatSnapshot _ownerSnapshot(
  GatewayTurnApplicationController controller,
  WidgetTester tester,
) => controller
    .normalSessionFor(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).connection,
    )
    .findChat('stored-large-session')!
    .snapshot;

class _DelayedMessagesHttpClient extends http.BaseClient {
  _DelayedMessagesHttpClient({
    this.refreshedMessages = const [
      {'role': 'assistant', 'content': 'Existing transcript row'},
      {'role': 'user', 'content': 'Prompt while history is loading'},
      {'role': 'assistant', 'content': 'Fresh reply'},
    ],
  });

  final List<Map<String, dynamic>> refreshedMessages;
  final Completer<Uri> messagesUri = Completer<Uri>();
  final Completer<Uri> refreshedMessagesUri = Completer<Uri>();
  final Completer<void> firstResponseReturned = Completer<void>();
  final Completer<void> _released = Completer<void>();
  int _messageRequestCount = 0;

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      _messageRequestCount += 1;
      if (_messageRequestCount == 1) {
        if (!messagesUri.isCompleted) messagesUri.complete(request.url);
        await _released.future;
        if (!firstResponseReturned.isCompleted) {
          firstResponseReturned.complete();
        }
        return _jsonResponse([
          {'role': 'assistant', 'content': 'Stale transcript row'},
        ]);
      }
      if (!refreshedMessagesUri.isCompleted) {
        refreshedMessagesUri.complete(request.url);
      }
      return _jsonResponse(refreshedMessages);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  http.StreamedResponse _jsonResponse(List<Map<String, dynamic>> messages) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': messages}))),
        200,
        headers: {'content-type': 'application/json'},
      );
}

class _MultiTurnRaceHttpClient extends http.BaseClient {
  _MultiTurnRaceHttpClient(this.submittedTurns);

  final int Function() submittedTurns;
  static const _firstTurnHistory = [
    {'id': 1, 'role': 'assistant', 'content': 'Existing transcript row'},
    {'id': 2, 'role': 'user', 'content': 'First turn'},
    {'id': 3, 'role': 'assistant', 'content': 'First reply'},
  ];
  final Completer<Uri> firstMessagesUri = Completer<Uri>();
  final Completer<Uri> deferredRefreshUri = Completer<Uri>();
  final Completer<Uri> authoritativeRefreshUri = Completer<Uri>();
  final Completer<void> _releaseFirst = Completer<void>();
  final Completer<void> _releaseDeferredRefresh = Completer<void>();
  int _messageRequestCount = 0;

  void releaseFirst() {
    if (!_releaseFirst.isCompleted) _releaseFirst.complete();
  }

  void releaseDeferredRefresh() {
    if (!_releaseDeferredRefresh.isCompleted) {
      _releaseDeferredRefresh.complete();
    }
  }

  void releaseAll() {
    releaseFirst();
    releaseDeferredRefresh();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      _messageRequestCount += 1;
      if (_messageRequestCount == 1) {
        firstMessagesUri.complete(request.url);
        await _releaseFirst.future;
        return _response([
          {'id': 1, 'role': 'assistant', 'content': 'Initial stale snapshot'},
        ]);
      }
      // Canonical admission reads happen before the corresponding prompt.
      // Do not confuse one with a post-turn refresh or invent future replies.
      if (submittedTurns() == 0) {
        return _response(_firstTurnHistory.take(1).toList());
      }
      if (submittedTurns() == 1) {
        if (!deferredRefreshUri.isCompleted) {
          deferredRefreshUri.complete(request.url);
          await _releaseDeferredRefresh.future;
          return _response([
            {
              'id': 1,
              'role': 'assistant',
              'content': 'Pre-second-turn snapshot',
            },
            ..._firstTurnHistory.skip(1),
          ]);
        }
        return _response(_firstTurnHistory);
      }
      if (!authoritativeRefreshUri.isCompleted) {
        authoritativeRefreshUri.complete(request.url);
      }
      return _response([
        ..._firstTurnHistory,
        {'id': 4, 'role': 'user', 'content': 'Second turn'},
        {'id': 5, 'role': 'assistant', 'content': 'Second reply'},
      ]);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }

  http.StreamedResponse _response(List<Map<String, dynamic>> messages) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': messages}))),
        200,
        headers: {'content-type': 'application/json'},
      );
}
