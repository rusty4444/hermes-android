// A running turn must outlive the chat screen that started it.
//
// Disposing the screen used to close its HTTP client, and `IOClient.close()`
// terminates every active connection — aborting the in-flight SSE request. The
// stock Hermes API server treats a client disconnect as an agent interrupt
// ("SSE client disconnected" → hard interrupt), so leaving the chat mid-turn
// destroyed the turn and every tool call it had already made: the transcript
// came back holding a bare `Operation interrupted.` with the work gone.
//
// The screen now hands the connection to a detached owner and closes it once
// the stream settles.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/fake_voice_composer_adapter.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      picker,
      (_) async => null,
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, null);
  });

  group('leaving a chat mid-turn', () {
    testWidgets('keeps the SSE connection open while the turn is streaming', (
      tester,
    ) async {
      final client = _StreamLifecycleHttpClient();
      await _pumpChat(tester, client: client);

      await _sendPrompt(tester, 'Long running task');
      await client.postStarted.future;
      await tester.pump();

      await _dispose(tester);
      expect(
        client.closed,
        isFalse,
        reason:
            'disposing the screen must not abort a running turn: the server '
            'reads that disconnect as an interrupt',
      );

      client.finish();
      await _drainDetachedClose(tester, client);
      expect(
        client.closed,
        isTrue,
        reason: 'the detached client closes once the stream settles',
      );
    });

    testWidgets('closes the detached client when the stream fails', (
      tester,
    ) async {
      final client = _StreamLifecycleHttpClient();
      await _pumpChat(tester, client: client);

      await _sendPrompt(tester, 'Long running task');
      await client.postStarted.future;
      await tester.pump();

      await _dispose(tester);
      expect(client.closed, isFalse);

      client.fail();
      await _drainDetachedClose(tester, client);
      expect(
        client.closed,
        isTrue,
        reason: 'a failed stream is a settled stream',
      );
    });

    testWidgets('closes the client on dispose when no turn is streaming', (
      tester,
    ) async {
      final client = _StreamLifecycleHttpClient();
      await _pumpChat(tester, client: client);

      await _dispose(tester);
      expect(
        client.closed,
        isTrue,
        reason: 'an idle screen keeps no connection open',
      );
    });

    testWidgets('does not hold the client open forever on a stalled stream', (
      tester,
    ) async {
      final client = _StreamLifecycleHttpClient();
      await _pumpChat(tester, client: client);

      await _sendPrompt(tester, 'Long running task');
      await client.postStarted.future;
      await tester.pump();

      await _dispose(tester);
      expect(client.closed, isFalse);

      // The stream never settles: the backstop must still release the client.
      await tester.pump(const Duration(minutes: 31));
      expect(client.closed, isTrue);
    });

    testWidgets('releases the client when the request dies before any reply', (
      tester,
    ) async {
      final client = _StreamLifecycleHttpClient(
        answer: _PostAnswer.failBeforeHeaders,
      );
      await _pumpChat(tester, client: client);

      await _sendPrompt(tester, 'Long running task');
      await client.postStarted.future;
      await tester.pump();

      await _dispose(tester);
      expect(client.closed, isFalse);

      // No response headers ever arrived: the send is over, but nothing ever
      // completed the SSE subscription the detached closer is waiting on.
      client.failSend();
      await tester.pump();
      await tester.pump();
      expect(
        client.closed,
        isTrue,
        reason:
            'a send that never reached the response headers is a settled '
            'send, so the detached closer must not sit out the backstop',
      );
    });

    testWidgets(
      'releases the client when a non-200 reply outlives the screen',
      (tester) async {
        final client = _StreamLifecycleHttpClient(
          answer: _PostAnswer.statusError,
        );
        await _pumpChat(tester, client: client);

        await _sendPrompt(tester, 'Long running task');
        await client.postStarted.future;
        await tester.pump();

        await _dispose(tester);
        expect(client.closed, isFalse);

        // The rejection finishes arriving only after the screen is gone.
        client.finishErrorBody();
        await _drainDetachedClose(tester, client);
        expect(
          client.closed,
          isTrue,
          reason: 'a non-200 reply took the early return, not the SSE path',
        );
      },
    );
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required _StreamLifecycleHttpClient client,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        connection: SavedConnection(
          id: 'conn-fixture',
          label: 'Fixture',
          host: 'fixture.example',
          port: 8642,
          apiKey: 'synth...ey',
        ),
        session: Session(
          id: 'mob-fixture',
          title: 'Fixture chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: ApiClient(
          baseUrl: 'http://fixture.example',
          apiKey: 'synth...ey',
          httpClient: client,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _sendPrompt(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
  final sendButton = tester.widget<IconButton>(
    find.widgetWithIcon(IconButton, Icons.send),
  );
  sendButton.onPressed!();
  await tester.pump();
}

/// Replaces the tree so the chat screen's [State.dispose] runs.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SizedBox.shrink(),
    ),
  );
  await tester.pump();
}

/// Subscription.cancel can complete in the root zone even for mock streams.
/// Drain both zones so the joined detached owner can close, without a timing
/// sleep or weakening the observable closed/not-closed lifecycle assertions.
Future<void> _drainDetachedClose(
  WidgetTester tester,
  _StreamLifecycleHttpClient client,
) async {
  for (var turn = 0; turn < 10 && !client.closed; turn++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  await tester.pump();
}

/// How the fixture answers a chat-completions POST.
enum _PostAnswer {
  /// 200 + an SSE body the test drives.
  stream,

  /// The request dies before the response headers: no reply ever arrives.
  failBeforeHeaders,

  /// A non-200 reply whose body the test holds open, so the client is still
  /// reading the rejection when the screen goes away.
  statusError,
}

/// SSE fixture that records whether the screen closed its connection while a
/// turn was still streaming.
class _StreamLifecycleHttpClient extends http.BaseClient {
  _StreamLifecycleHttpClient({this.answer = _PostAnswer.stream});

  final _PostAnswer answer;
  final Completer<void> postStarted = Completer<void>();
  final Completer<void> _sendFailure = Completer<void>();
  StreamController<List<int>>? _completionStream;
  StreamController<List<int>>? _errorBodyStream;
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/v1/chat/completions')) {
      if (!postStarted.isCompleted) postStarted.complete();
      switch (answer) {
        case _PostAnswer.stream:
          _completionStream = StreamController<List<int>>();
          return http.StreamedResponse(
            _completionStream!.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        case _PostAnswer.failBeforeHeaders:
          await _sendFailure.future;
          throw http.ClientException(
            'Connection closed before full header was received',
            request.url,
          );
        case _PostAnswer.statusError:
          _errorBodyStream = StreamController<List<int>>();
          return http.StreamedResponse(
            _errorBodyStream!.stream,
            400,
            headers: {'content-type': 'application/json'},
          );
      }
    }
    if (request.method == 'GET') {
      return _jsonResponse({'data': const []});
    }
    return _jsonResponse({'error': 'unexpected request'}, statusCode: 404);
  }

  /// The server answered and closed the turn.
  void finish() {
    _completionStream!
      ..add(
        utf8.encode(
          'data: {"choices":[{"delta":{"content":"Finished reply"}}]}\n\n'
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
          'data: [DONE]\n\n',
        ),
      )
      ..close();
  }

  /// The connection died without a terminal frame.
  void fail() {
    _completionStream!
      ..addError(Exception('connection lost'))
      ..close();
  }

  /// The request gave up before the server answered.
  void failSend() {
    if (!_sendFailure.isCompleted) _sendFailure.complete();
  }

  /// The non-200 reply finishes arriving.
  void finishErrorBody() {
    _errorBodyStream!
      ..add(
        utf8.encode(
          jsonEncode({
            'error': {'message': 'model is not loaded'},
          }),
        ),
      )
      ..close();
  }

  http.StreamedResponse _jsonResponse(Object body, {int statusCode = 200}) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  }
}
