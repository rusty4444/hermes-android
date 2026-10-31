// Review blocker #3: a mid-turn socket drop must actually reattach, with
// the REAL production close ordering. WsClient._handleClosedConnection
// rejects every pending RPC the instant the socket closes — so the submit
// catch fires BEFORE the reconnect. Once onSent has confirmed wire acceptance,
// that uncertain close must keep the composer cleared and the optimistic turn;
// the resync runs later, on the fresh socket, while the
// detached server turn may still be settling. The resync must therefore:
// - fetch by the gateway's STORED session key (a newly created stock
//   session's DB row is not addressable by the mobile session id),
// - retry until the detached reply lands rather than trusting one fetch,
// - never clear the transcript on a 404 (row not readable yet ≠ empty).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/projects_tree_overview.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

void main() {
  setUp(() {
    // Reattach/admission watermarks are not row-local completion evidence.
    // Inspect the unchanged metadata-free history in Verbose Mode instead.
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
  });

  testWidgets(
    'production close ordering: submit fails at close, reconnect resyncs '
    'by stored session id and lands the detached reply',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      var ensureCount = 0;
      final submission = Completer<void>();
      final history = _ReattachChatHttpClient();
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'reattach-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        apiClient: apiClient,
        ensureCount: () => ensureCount++,
        storedKey: 'stored_sess_9f3a',
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return submission.future;
            },
      );
      // Baseline: no Desktop gateway is configured for this fixture, so
      // initState never ensured a session; history was fetched once.
      expect(ensureCount, 0);
      expect(history.messageRequestCount, 1);

      // The socket is live, then the user sends and the turn goes in flight.
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Long running task');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      // Socket drops mid-turn: the snackbar promises automatic reattach.
      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();
      expect(
        find.text(
          'Connection switched — the running reply continues on the '
          'server and will reattach automatically.',
        ),
        findsOneWidget,
      );
      // Nothing has been resynced yet — the promise is still pending.
      expect(ensureCount, 0);
      expect(history.messageRequestCount, 1);

      // PRODUCTION ORDERING: WsClient rejects the pending prompt.submit AT
      // CLOSE, before any reconnect. onSent already confirmed wire acceptance,
      // so the catch keeps the composer cleared and the optimistic turn while
      // the later resync reconciles the uncertain acknowledgement.
      history.includeCompletedTurn = true;
      submission.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: 'an accepted prompt must not be restored and submitted twice',
      );
      final composer = find.byKey(const Key('chat-message-composer'));
      expect(tester.widget<TextField>(composer).enabled, isNot(false));
      await tester.enterText(composer, 'Draft during reconnect');
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull,
      );
      expect(
        history.messageRequestCount,
        1,
        reason: 'no resync before reconnect',
      );

      // The reconnect succeeds: the screen must re-bind and refetch now,
      // without waiting for any user action. The server finished the turn
      // detached during the outage.
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(ensureCount, 1, reason: 'reattach must re-ensure the session');
      expect(
        history.messageRequestCount,
        2,
        reason: 'reattach must refetch history',
      );
      // STORED IDENTITY: the refetch must target the gateway's stored DB
      // key, not the mobile session id — a newly created stock session is
      // not addressable by the mobile id, and a 404 there would wipe the
      // transcript.
      expect(
        history.requestedMessagePaths.last,
        contains('stored_sess_9f3a'),
        reason: 'resync must fetch by the stored session identity',
      );
      expect(find.text('Server-side final response'), findsOneWidget);

      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Draft during reconnect',
      );

      // The reply landed (transcript grew past the pre-resync count), so
      // the resync is done: no further fetches were triggered.
      await tester.pump(const Duration(seconds: 3));
      expect(history.messageRequestCount, 2);
    },
  );

  testWidgets('reattach history recovery does not wait for Project metadata', (
    tester,
  ) async {
    final hook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    final metadataRelease = Completer<void>();
    final history = _ReattachChatHttpClient();
    var metadataLoads = 0;
    await _pumpChat(
      tester,
      hook: hook,
      apiClient: ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'synthetic-key',
        httpClient: history,
      ),
      ensureCount: () {},
      storedKey: 'stored_sess_latency',
      projectOverviewLoader: () async {
        metadataLoads += 1;
        await metadataRelease.future;
        return ProjectsTreeOverview.fromJson({
          'projects': [
            {
              'id': 'project-latency',
              'label': 'Metadata arrived later',
              'sessionIds': ['stored_sess_latency'],
            },
          ],
        });
      },
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            onSent();
            return submission.future;
          },
    );

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Recover before metadata');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    hook.handler?.call(DesktopConnectionState.reconnecting);
    submission.completeError(
      JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    history.includeCompletedTurn = true;
    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(metadataRelease.isCompleted, isFalse);
    expect(metadataLoads, greaterThanOrEqualTo(2));
    expect(find.text('Server-side final response'), findsOneWidget);

    metadataRelease.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Metadata arrived later'), findsOneWidget);
  });

  testWidgets(
    'resync retries while the detached turn settles and never clears the '
    'transcript on 404',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      final submission = Completer<void>();
      // The initial history fetch (request 1) succeeds; the resync fetch
      // (request 2) 404s — the stored row isn't readable yet.
      final history = _ReattachChatHttpClient()..failMessagesAfterFirst = 1;
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'reattach-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        apiClient: apiClient,
        ensureCount: () {},
        storedKey: 'stored_sess_retry',
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return submission.future;
            },
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Slow settling turn');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      // Close-ordering: submit fails at close after wire acceptance, so the
      // composer stays cleared while reattachment reconciles the turn.
      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();
      submission.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Reconnect: the stored row is NOT readable yet — the first resync
      // fetch 404s. The transcript must survive (never cleared by a
      // failed resync) and the resync must retry, not give up on one shot.
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final afterFirstResync = history.messageRequestCount;
      expect(afterFirstResync, 2, reason: 'first resync fetch attempted');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: 'a failed resync must not resurrect an accepted prompt',
      );

      // The row becomes readable: the next retry must land the reply.
      history.failMessagesAfterFirst = 0;
      history.includeCompletedTurn = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));

      expect(
        history.messageRequestCount,
        greaterThan(afterFirstResync),
        reason: 'resync must retry until the settling turn lands',
      );
      expect(find.text('Server-side final response'), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate connected callbacks stay single-flight and disconnect pauses '
    'the pending retry',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      final submission = Completer<void>();
      final history = _ReattachChatHttpClient()..userOnlyTurn = true;
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'reattach-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        apiClient: apiClient,
        ensureCount: () {},
        storedKey: 'stored_sess_connection',
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return submission.future;
            },
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Long running task');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();
      submission.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      hook.handler?.call(DesktopConnectionState.connected);
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(history.messageRequestCount, 2);

      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(
        history.messageRequestCount,
        2,
        reason: 'disconnect must pause the scheduled retry',
      );

      history.userOnlyTurn = false;
      history.includeCompletedTurn = true;
      hook.handler?.call(DesktopConnectionState.connected);
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        history.messageRequestCount,
        3,
        reason: 'reconnect retries immediately and duplicates do not fan out',
      );
      expect(find.text('Server-side final response'), findsOneWidget);
    },
  );

  testWidgets(
    'resync survives the old 27.5s deadline, pauses in background, and '
    'resumes immediately for the terminal assistant row',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      final submission = Completer<void>();
      var ensureCount = 0;
      // Requests 2..7 stay user-only. Request 8 lands after the old
      // ten-attempt implementation would already have abandoned recovery.
      final history = _ReattachChatHttpClient()
        ..oldHistory = const [
          {'id': 1, 'role': 'user', 'content': 'Earlier question'},
          {'id': 2, 'role': 'assistant', 'content': 'Earlier answer'},
        ]
        ..userOnlyUntilRequest = 7;
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: ['fixture', 'key'].join('-'),
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        apiClient: apiClient,
        ensureCount: () => ensureCount += 1,
        storedKey: 'stored_sess_longturn',
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return submission.future;
            },
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Long running task');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();

      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();
      submission.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(history.messageRequestCount, 2);

      // Run requests 3..7 at 0.5, 1, 2, 4, and 8 second backoffs.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 8));
      expect(history.messageRequestCount, 7);
      expect(find.text('Server-side final response'), findsNothing);

      // Reach the old implementation's ~27.5-second total delay without
      // firing the new controller's next (16-second) retry yet.
      await tester.pump(const Duration(seconds: 12));
      expect(history.messageRequestCount, 7);

      hook.handler?.call(DesktopConnectionState.reconnecting);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      history.userOnlyUntilRequest = 0;
      history.includeCompletedTurn = true;
      await tester.pump(const Duration(minutes: 1));
      expect(
        history.messageRequestCount,
        7,
        reason: 'backgrounding must pause recovery network requests',
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final ensuresBeforeResume = ensureCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        ensureCount,
        greaterThan(ensuresBeforeResume),
        reason: 'resume must explicitly restart an exhausted socket loop',
      );
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        history.messageRequestCount,
        8,
        reason: 'resume must retry immediately rather than wait for backoff',
      );
      expect(find.text('Server-side final response'), findsOneWidget);
      final settledCount = history.messageRequestCount;
      await tester.pump(const Duration(minutes: 1));
      expect(history.messageRequestCount, settledCount);
    },
  );

  testWidgets(
    'durable row IDs detect completion when the capped 500-row window '
    'rolls over without growing',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      final submission = Completer<void>();
      final history = _ReattachChatHttpClient()
        ..cappedHistoryWindow = true
        ..userOnlyUntilRequest = 2;
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: ['fixture', 'key'].join('-'),
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        apiClient: apiClient,
        ensureCount: () {},
        storedKey: 'stored_sess_capped',
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return submission.future;
            },
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Long running task');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();
      submission.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(history.messageRequestCount, 2);
      expect(find.text('Server-side final response'), findsNothing);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(history.messageRequestCount, 3);
      expect(find.text('Server-side final response'), findsOneWidget);
      final settledCount = history.messageRequestCount;
      await tester.pump(const Duration(minutes: 1));
      expect(history.messageRequestCount, settledCount);
    },
  );

  testWidgets('watermark accepts an agent-role reply as terminal (not just '
      'assistant-role)', (tester) async {
    // The watermark's role check is `role != 'assistant' && role !=
    // 'agent'` — some stock rows carry role 'agent'. If the 'agent'
    // branch were dropped, this reply would never satisfy the watermark
    // and the resync would spin the whole budget instead of stopping.
    final hook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    final history = _ReattachChatHttpClient()
      ..oldHistory = const [
        {'id': 1, 'role': 'user', 'content': 'Earlier question'},
        {'id': 2, 'role': 'assistant', 'content': 'Earlier answer'},
      ]
      ..userOnlyUntilRequest = 2
      ..replyRole = 'agent';
    final apiClient = ApiClient(
      baseUrl: 'http://reattach.fixture',
      apiKey: 'reattach-key',
      httpClient: history,
    );
    await _pumpChat(
      tester,
      hook: hook,
      apiClient: apiClient,
      ensureCount: () {},
      storedKey: 'stored_sess_agentrole',
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            onSent();
            return submission.future;
          },
    );

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Long running task');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();

    hook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();
    submission.completeError(
      JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 4));

    // The agent-role reply satisfies the watermark and is normalized to an
    // assistant bubble instead of stopping recovery on an invisible row.
    expect(find.text('Server-side final response'), findsOneWidget);
    final settledCount = history.messageRequestCount;
    expect(
      settledCount,
      lessThanOrEqualTo(5),
      reason:
          'an agent-role terminal row must end the resync, not '
          'spin the full 10-attempt budget',
    );
    await tester.pump(const Duration(seconds: 5));
    expect(
      history.messageRequestCount,
      settledCount,
      reason: 'an agent-role terminal row must end the resync',
    );
  });

  testWidgets('watermark rejects a tool-call intermediate reply; resync keeps '
      'waiting for the final row', (tester) async {
    // A reply row with a non-empty tool_calls list is an intermediate,
    // not the final answer. If the tool_calls skip were dropped, the
    // resync would stop on the intermediate and never show the real
    // final reply that lands later.
    final hook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    final history = _ReattachChatHttpClient()
      ..oldHistory = const [
        {'id': 1, 'role': 'user', 'content': 'Earlier question'},
        {'id': 2, 'role': 'assistant', 'content': 'Earlier answer'},
      ]
      ..userOnlyUntilRequest = 2
      ..replyHasToolCalls = true;
    final apiClient = ApiClient(
      baseUrl: 'http://reattach.fixture',
      apiKey: 'reattach-key',
      httpClient: history,
    );
    await _pumpChat(
      tester,
      hook: hook,
      apiClient: apiClient,
      ensureCount: () {},
      storedKey: 'stored_sess_toolcall',
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            onSent();
            return submission.future;
          },
    );

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Long running task');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();

    hook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();
    submission.completeError(
      JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 4));

    // Past the point where the tool-call row was served: the resync is
    // still running because the intermediate is not terminal.
    expect(
      history.messageRequestCount,
      greaterThan(3),
      reason: 'a tool-call intermediate must not end the resync',
    );

    // The same durable row is later finalized without tool_calls. The
    // next retry accepts it and cancels the otherwise unbounded timer.
    history.replyHasToolCalls = false;
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(find.text('Server-side final response'), findsOneWidget);
    final settledCount = history.messageRequestCount;
    await tester.pump(const Duration(minutes: 1));
    expect(history.messageRequestCount, settledCount);
  });

  testWidgets(
    'submit failure with no resync landed still restores the composer',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      final history = _ReattachChatHttpClient();
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'reattach-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        apiClient: apiClient,
        ensureCount: () {},
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              throw JsonRpcError(
                'prompt.submit',
                'Desktop gateway connection closed',
              );
            },
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Plain failure');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // No reconnect happened, so the classic restore behavior stands.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Plain failure',
      );
      expect(history.messageRequestCount, 1);
    },
  );

  testWidgets(
    'retained terminal failure stops polling and re-enables sending',
    (tester) async {
      String? retainedError;
      final hook = TestDesktopConnectionHook();
      final asyncHook = TestDesktopAsyncEventHook();
      final submission = Completer<void>();
      final history = _ReattachChatHttpClient()..userOnlyTurn = true;
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'fixture-api-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        asyncHook: asyncHook,
        apiClient: apiClient,
        ensureCount: () {},
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return submission.future;
            },
        retainedError: () => retainedError,
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Detached failure');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();
      submission.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(history.messageRequestCount, 2);
      expect(asyncHook.handler, isNotNull);
      final sendButton = find.widgetWithIcon(IconButton, Icons.send);
      expect(
        tester.widget<IconButton>(sendButton).onPressed,
        isNull,
        reason: 'reattach recovery must still be pending before the failure',
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithIcon(TextButton, Icons.tune))
            .onPressed,
        isNull,
        reason: 'model changes must not race the authoritative history fetch',
      );
      await tester.tap(find.byTooltip('Chat actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final refreshItem = find.ancestor(
        of: find.text('Refresh'),
        matching: find.byType(PopupMenuItem<String>),
      );
      expect(
        tester.widget<PopupMenuItem<String>>(refreshItem).enabled,
        isFalse,
      );
      await tester.tapAt(Offset.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      retainedError = 'Provider unavailable';
      asyncHook.handler?.call(
        StreamEvent(
          type: 'turn.error',
          data: const {'status': 'error', 'message': 'Provider unavailable'},
          isComplete: true,
        ),
      );
      await tester.pump();
      expect(
        tester.widget<IconButton>(sendButton).onPressed,
        isNotNull,
        reason: 'terminal failure must clear reattach recovery',
      );

      final settledCount = history.messageRequestCount;
      await tester.pump(const Duration(minutes: 1));
      expect(
        history.messageRequestCount,
        settledCount,
        reason: 'authoritative terminal failure must cancel persistent polling',
      );
    },
  );

  testWidgets(
    'a stale recovery flight hands the single-flight slot to a newer turn',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      final asyncHook = TestDesktopAsyncEventHook();
      final submissions = <Completer<void>>[];
      final blockedHistory = Completer<void>();
      final history = _ReattachChatHttpClient()
        ..userOnlyTurn = true
        ..blockMessageRequest = 2
        ..blockedMessageGate = blockedHistory;
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'fixture-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        asyncHook: asyncHook,
        apiClient: apiClient,
        ensureCount: () {},
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              // This regression settles A while its old history read is held:
              // give that lifecycle terminal a previously bound identity.
              onEvent(
                StreamEvent(
                  type: 'message.start',
                  data: const {},
                  turnId: 'generation-${submissions.length}',
                ),
              );
              final submission = Completer<void>();
              submissions.add(submission);
              return submission.future;
            },
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Generation A');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      hook.handler?.call(DesktopConnectionState.reconnecting);
      submissions.single.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      expect(history.messageRequestCount, 2);

      asyncHook.handler?.call(
        StreamEvent(
          type: 'turn.error',
          data: const {'status': 'error', 'message': 'Generation A failed'},
          isComplete: true,
          turnId: 'generation-0',
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Generation B');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(submissions, hasLength(2));
      hook.handler?.call(DesktopConnectionState.reconnecting);
      submissions.last.completeError(
        JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();

      history
        ..userOnlyTurn = false
        ..includeCompletedTurn = true;
      blockedHistory.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        history.messageRequestCount,
        4,
        reason:
            'generation B must run when A unwinds; the failed A turn also refreshes its durable pre-submit baseline',
      );
      expect(find.text('Server-side final response'), findsOneWidget);
      final settledCount = history.messageRequestCount;
      await tester.pump(const Duration(minutes: 1));
      expect(history.messageRequestCount, settledCount);
    },
  );

  testWidgets(
    'disconnect before the prompt wire-send boundary never arms recovery',
    (tester) async {
      final hook = TestDesktopConnectionHook();
      final beforeWire = Completer<void>();
      final history = _ReattachChatHttpClient();
      final apiClient = ApiClient(
        baseUrl: 'http://reattach.fixture',
        apiKey: 'fixture-key',
        httpClient: history,
      );
      await _pumpChat(
        tester,
        hook: hook,
        apiClient: apiClient,
        ensureCount: () {},
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) => beforeWire.future,
      );

      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Binding phase');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      hook.handler?.call(DesktopConnectionState.reconnecting);
      await tester.pump();

      expect(find.textContaining('will reattach automatically'), findsNothing);
      beforeWire.completeError(
        JsonRpcError('session.resume', 'Desktop gateway connection closed'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      hook.handler?.call(DesktopConnectionState.connected);
      await tester.pump(const Duration(seconds: 3));
      expect(history.messageRequestCount, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Binding phase',
      );
    },
  );

  testWidgets('reconnect with no turn in flight does not trigger a resync', (
    tester,
  ) async {
    final hook = TestDesktopConnectionHook();
    var ensureCount = 0;
    final history = _ReattachChatHttpClient();
    final apiClient = ApiClient(
      baseUrl: 'http://reattach.fixture',
      apiKey: 'reattach-key',
      httpClient: history,
    );
    await _pumpChat(
      tester,
      hook: hook,
      apiClient: apiClient,
      ensureCount: () => ensureCount++,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {},
    );

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    hook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();
    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Idle drop: no snackbar, no extra ensure, no extra history fetch.
    expect(
      find.text(
        'Connection switched — the running reply continues on the '
        'server and will reattach automatically.',
      ),
      findsNothing,
    );
    expect(ensureCount, 0);
    expect(history.messageRequestCount, 1);
  });
}

Future<void> _pumpChat(
  WidgetTester tester, {
  required TestDesktopConnectionHook hook,
  TestDesktopAsyncEventHook? asyncHook,
  required ApiClient apiClient,
  required VoidCallback ensureCount,
  required TestRemotePromptSubmit remoteSubmit,
  String? storedKey,
  TestProjectOverviewLoader? projectOverviewLoader,
  String? Function()? retainedError,
}) async {
  final connection = SavedConnection(
    id: 'reattach-fixture',
    label: 'Reattach fixture',
    host: 'reattach.fixture',
    port: 8642,
    apiKey: 'fixture',
  );
  final controller = GatewayTurnApplicationController();
  controller.setLifecycle(background: false, backgroundWorkEnabled: false);
  addTearDown(controller.close);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: connection,
        turnApplicationController: controller,
        session: const Session(
          id: 'reattach-session',
          title: 'Reattach chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: apiClient,
        testRemotePromptSubmit: remoteSubmit,
        testNormalResume:
            ({required localSessionId, required storedSessionId}) async {
              final state = controller
                  .normalSessionFor(connection)
                  .findChat(localSessionId)!
                  .snapshot
                  .connectionState;
              if (state != DesktopConnectionState.connected) {
                throw StateError('Fixture socket is disconnected');
              }
              ensureCount();
              final error = retainedError?.call();
              return ResumedGatewaySession(
                runtimeSessionId: 'fixture-runtime',
                running: false,
                // Success requires explicit terminal status; idle is unknown.
                status: error == null ? 'completed' : null,
                inflight: error == null
                    ? null
                    : {'status': 'error', 'error': error},
              );
            },
        testDesktopConnectionHook: hook,
        testDesktopAsyncEventHook: asyncHook,
        testDesktopSessionEnsured: ensureCount,
        testStoredSessionKey: storedKey == null ? null : (_) => storedKey,
        testProjectOverviewLoader: projectOverviewLoader,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _ReattachChatHttpClient extends http.BaseClient {
  int messageRequestCount = 0;
  bool includeCompletedTurn = false;
  int? blockMessageRequest;
  Completer<void>? blockedMessageGate;

  /// Rows served BEFORE the detached turn's rows — the transcript that
  /// existed before the drop. The resync watermark counts growth past
  /// this, so an old trailing assistant row must not satisfy it.
  List<Map<String, dynamic>> oldHistory = const [];

  /// Serve the synchronously-persisted USER row of the detached turn
  /// without the assistant reply — the stock `prompt.submit` ordering the
  /// resync must not mistake for completion.
  bool userOnlyTurn = false;

  /// While the /messages request count is at or below this number, serve
  /// the user-only turn; after it, the completed turn. Models a long
  /// model turn whose reply lands beyond the resync retry budget's OLD
  /// 3.5-second horizon.
  int userOnlyUntilRequest = 0;

  /// /messages requests BEYOND this count get a 404 (simulates the
  /// stored row not being readable yet while the detached turn settles).
  /// 0 = never fail.
  int failMessagesAfterFirst = 0;

  final List<String> requestedMessagePaths = [];

  /// Role used for the completed turn's reply row. 'assistant' by
  /// default; 'agent' exercises the second branch of the watermark's
  /// role check (both count as terminal).
  String replyRole = 'assistant';

  /// When true, emulate the stock endpoint's latest-500-row cap: adding a
  /// row evicts the oldest one, so list length and assistant count do not
  /// increase even though durable IDs advance.
  bool cappedHistoryWindow = false;

  /// When true, the completed reply carries a non-empty tool_calls list:
  /// a tool-call intermediate that must NOT satisfy the watermark.
  bool replyHasToolCalls = false;

  List<Map<String, dynamic>> _normalMessages() {
    final highestOldId = oldHistory.fold<int>(0, (highest, message) {
      final id = message['id'];
      return id is int && id > highest ? id : highest;
    });
    final completed =
        includeCompletedTurn ||
        (userOnlyUntilRequest > 0 &&
            messageRequestCount > userOnlyUntilRequest);
    return [
      ...oldHistory,
      if (completed) ...[
        {
          'id': highestOldId + 1,
          'role': 'user',
          'content': 'Long running task',
        },
        {
          'id': highestOldId + 2,
          'role': replyRole,
          'content': 'Server-side final response',
          if (replyHasToolCalls)
            'tool_calls': const [
              {'id': 'tc1'},
            ],
        },
      ] else if (userOnlyTurn || userOnlyUntilRequest > 0)
        {
          'id': highestOldId + 1,
          'role': 'user',
          'content': 'Long running task',
        },
    ];
  }

  List<Map<String, dynamic>> _cappedMessages() {
    final completed =
        includeCompletedTurn ||
        (userOnlyUntilRequest > 0 &&
            messageRequestCount > userOnlyUntilRequest);
    if (!completed && !userOnlyTurn && userOnlyUntilRequest == 0) {
      return List.generate(500, (index) {
        final id = index + 1;
        return {
          'id': id,
          'role': id.isEven ? 'assistant' : 'user',
          'content': 'History row $id',
        };
      });
    }
    final firstOldId = completed ? 3 : 2;
    final rows = <Map<String, dynamic>>[
      for (var id = firstOldId; id <= 500; id += 1)
        {
          'id': id,
          'role': id.isEven ? 'assistant' : 'user',
          'content': 'History row $id',
        },
      {'id': 501, 'role': 'user', 'content': 'Long running task'},
    ];
    if (completed) {
      rows.add({
        'id': 502,
        'role': replyRole,
        'content': 'Server-side final response',
        if (replyHasToolCalls)
          'tool_calls': const [
            {'id': 'tc1'},
          ],
      });
    }
    return rows;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' && request.url.path.endsWith('/messages')) {
      messageRequestCount += 1;
      requestedMessagePaths.add(request.url.path);
      if (messageRequestCount == blockMessageRequest) {
        await blockedMessageGate?.future;
      }
      if (failMessagesAfterFirst > 0 &&
          messageRequestCount > failMessagesAfterFirst) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'error': 'not found'}))),
          404,
          headers: {'content-type': 'application/json'},
        );
      }
      final messages = cappedHistoryWindow
          ? _cappedMessages()
          : _normalMessages();
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({'data': messages}))),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'error': 'unexpected request'}))),
      404,
      headers: {'content-type': 'application/json'},
    );
  }
}
