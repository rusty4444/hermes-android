import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'support/completed_stock_turn.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'support/pump_chat_updates.dart';

/// Answers the chat screen's initial reads with empty payloads.
class _EmptyChatHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"messages": []}')),
      200,
    );
  }
}

/// Answers reads with empty payloads but refuses prompt submissions, so the
/// REST send fails at the request level while the screen stays usable.
class _FailingSendChatHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET') {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"messages": []}')),
        200,
      );
    }
    throw http.ClientException('connection refused');
  }
}

/// Accepts the REST stream, then fails only the post-stream history refresh.
class _AcceptedSendHistoryFailureHttpClient extends http.BaseClient {
  var _messageReads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET') {
      _messageReads += 1;
      if (_messageReads == 1) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"data": []}')),
          200,
        );
      }
      throw http.ClientException('history refresh failed');
    }
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"accepted reply"}}]}\n\n'
          'data: [DONE]\n\n',
        ),
      ),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

final _fixtureConnection = SavedConnection(
  id: 'draft-fixture',
  label: 'Draft fixture',
  host: 'draft.fixture',
  port: 8642,
  apiKey: '',
);

String get _fixtureConnectionId => _fixtureConnection.id;

const _fixtureSession = Session(
  id: 'draft-session',
  title: 'Draft chat',
  model: 'fixture-model',
  source: 'test',
  messageCount: 0,
  isActive: true,
  preview: '',
  startedAt: 1,
);

Future<void> _pumpChat(
  WidgetTester tester, {
  http.Client? client,
  SavedConnection? connection,
  String? initialComposerText,
  TestComposerDraftReader? draftReader,
  TestRemotePromptSubmit? remoteSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: connection ?? _fixtureConnection,
        session: _fixtureSession,
        initialComposerText: initialComposerText,
        testComposerDraftReader: draftReader,
        testRemotePromptSubmit: completedStockTurn(remoteSubmit),
        testApiClient: ApiClient(
          baseUrl: 'http://draft.fixture',
          apiKey: '',
          httpClient: client ?? _EmptyChatHttpClient(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(mockChatImageRecovery);
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  testWidgets('leaving a chat keeps its composer draft', (tester) async {
    await _pumpChat(tester);
    await tester.enterText(find.byType(TextField).first, 'half typed');
    await tester.pump();

    // Leave the chat: the screen is disposed and the draft persisted.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // Reopen the same session: the draft comes back.
    await _pumpChat(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('half typed'), findsOneWidget);
  });

  testWidgets('a share-sheet prefill wins over a stored draft', (tester) async {
    await ComposerDraftStore.save(
      connectionId: _fixtureConnectionId,
      sessionId: 'draft-session',
      text: 'stale draft',
    );

    await _pumpChat(tester, initialComposerText: 'shared text');
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('shared text'), findsOneWidget);
    expect(find.text('stale draft'), findsNothing);
  });

  testWidgets('a definite send rejection restores the draft', (tester) async {
    await _pumpChat(tester, client: _FailingSendChatHttpClient());
    await tester.enterText(find.byType(TextField).first, 'resend me');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The composer has the text back…
    expect(find.text('resend me'), findsOneWidget);
    // …and the stored draft was restored, not left cleared.
    expect(
      await ComposerDraftStore.read(
        connectionId: _fixtureConnectionId,
        sessionId: 'draft-session',
      ),
      'resend me',
    );
  });

  testWidgets('draft follows a stable connection id after endpoint edits', (
    tester,
  ) async {
    await ComposerDraftStore.save(
      connectionId: _fixtureConnectionId,
      sessionId: _fixtureSession.id,
      text: 'survives endpoint edit',
    );
    final editedConnection = SavedConnection(
      id: _fixtureConnection.id,
      label: _fixtureConnection.label,
      host: 'edited-draft.fixture',
      port: 9443,
      apiKey: '',
      useHttps: true,
      gatewayPrefix: '/new-prefix',
    );

    await _pumpChat(tester, connection: editedConnection);

    expect(find.text('survives endpoint edit'), findsOneWidget);
  });

  testWidgets('delayed restore cannot overwrite a newer cleared edit', (
    tester,
  ) async {
    final restore = Completer<String?>();
    await _pumpChat(
      tester,
      draftReader: ({required connectionId, required sessionId}) =>
          restore.future,
    );
    final composer = find.byType(TextField).first;

    await tester.enterText(composer, 'new local edit');
    await tester.enterText(composer, '');
    restore.complete('stale stored draft');
    await tester.pump();

    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    expect(find.text('stale stored draft'), findsNothing);
  });

  testWidgets('delayed restore cannot resurrect a prompt cleared for send', (
    tester,
  ) async {
    final restore = Completer<String?>();
    final submitGate = Completer<void>();
    await _pumpChat(
      tester,
      draftReader: ({required connectionId, required sessionId}) =>
          restore.future,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            onSent();
            await submitGate.future;
          },
    );
    final composer = find.byType(TextField).first;

    await tester.enterText(composer, 'send once');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    restore.complete('stale stored draft');
    await tester.pump();

    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    expect(find.text('stale stored draft'), findsNothing);

    submitGate.complete();
    await tester.pump();
  });

  testWidgets('accepted REST prompt stays cleared when history refresh fails', (
    tester,
  ) async {
    await _pumpChat(tester, client: _AcceptedSendHistoryFailureHttpClient());
    final composer = find.byType(TextField).first;

    await tester.enterText(composer, 'accepted prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    expect(find.text('accepted prompt'), findsOneWidget);
    await pumpChatUpdates(tester);
    expect(find.text('accepted reply'), findsOneWidget);
    expect(
      await ComposerDraftStore.read(
        connectionId: _fixtureConnectionId,
        sessionId: _fixtureSession.id,
      ),
      isNull,
    );
  });
}
