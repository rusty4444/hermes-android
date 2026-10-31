// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/chat_history_widget_test.dart
// Base 4a53e32 blob d9ab33d2ecc9b84ed810f8d6da3ec2e4e6918cbb; SHA256 1c6a3e4307b3ec1cd87d4f34f5da73a4811de1af67f7ea2e08fd35e83837b8b1.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';
import 'support/completed_stock_turn.dart';

class _HistoryHttpClient extends http.BaseClient {
  _HistoryHttpClient(this.rows);

  List<Map<String, dynamic>> rows;
  final List<int> offsets = [];
  final List<Uri> requests = [];
  Completer<void>? responseGate;
  bool failNextRequest = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'GET' &&
        request.url.path == '/api/sessions/stored-history-fixture') {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'session': {'id': 'stored-history-fixture', 'archived': false},
            }),
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method != 'GET' || !request.url.path.endsWith('/messages')) {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 404);
    }
    requests.add(request.url);
    final gate = responseGate;
    if (gate != null) await gate.future;
    if (failNextRequest) {
      failNextRequest = false;
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
    }

    final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
    offsets.add(offset);
    final end = rows.length - offset;
    final page = end <= 0
        ? <Map<String, dynamic>>[]
        : rows.sublist((end - 50).clamp(0, end), end);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode({'data': page}))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

List<Map<String, dynamic>> _toolHeavyRows(int lastToolId) => [
  {'id': 1, 'role': 'user', 'content': 'Earlier question'},
  {'id': 2, 'role': 'assistant', 'content': 'Earlier answer'},
  for (var id = 3; id <= lastToolId; id++)
    {
      'id': id,
      'role': 'tool',
      'name': 'fixture_tool',
      'tool_call_id': 'tool-$id',
      'content': 'Tool output $id',
    },
];

Widget _chat(
  _HistoryHttpClient httpClient, {
  Key? key,
  TestDesktopConnectionHook? connectionHook,
  TestRemotePromptSubmit? remoteSubmit,
  VoidCallback? onSessionEnsured,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: preferredSupportedLocales(),
  localeListResolutionCallback: resolvePreferredLocale,
  home: ChatScreen(
    key: key,
    connection: SavedConnection(
      id: 'history-fixture',
      label: 'History fixture',
      host: 'history.fixture',
      port: 8642,
      apiKey: 'fixture-key',
    ),
    session: const Session(
      id: 'stored-history-fixture',
      title: 'History fixture',
      model: 'fixture-model',
      source: 'api_server',
      messageCount: 500,
      isActive: true,
      preview: '',
      startedAt: 1,
    ),
    testApiClient: ApiClient(
      baseUrl: 'http://history.fixture',
      apiKey: 'fixture-key',
      httpClient: httpClient,
    ),
    testDesktopConnectionHook: connectionHook,
    testRemotePromptSubmit: completedStockTurn(remoteSubmit),
    testNormalResume:
        ({required localSessionId, required storedSessionId}) async {
          if (connectionHook?.currentState !=
              DesktopConnectionState.connected) {
            throw StateError('Fixture socket is disconnected');
          }
          onSessionEnsured?.call();
          return const ResumedGatewaySession(
            runtimeSessionId: 'history-runtime',
            running: false,
          );
        },
    testDesktopSessionEnsured: onSessionEnsured,
    testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
  ),
);

void main() {
  setUp(mockChatImageRecovery);
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': true}));

  for (final verbose in [false, true]) {
    testWidgets('persisted times survive refresh and reopen verbose=$verbose', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'verbose_mode': verbose});
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final client = _HistoryHttpClient([
        {
          'id': 1,
          'role': 'user',
          'content': 'Recorded question',
          'timestamp': 1718456700,
        },
        {
          'id': 2,
          'role': 'assistant',
          'content': 'Recorded reply',
          'timestamp': 1718456760.125,
          'completed': true,
        },
        {'id': 3, 'role': 'user', 'content': 'No recorded time'},
        {
          'id': 4,
          'role': 'assistant',
          'content': 'Invalid recorded time',
          'timestamp': 'not a time',
          'completed': true,
        },
      ]);
      await tester.pumpWidget(
        _chat(client, key: const ValueKey('timed-first')),
      );
      await pumpChatUpdates(tester);
      final footers = find.byKey(const Key('message-timestamp'));
      expect(footers, findsNWidgets(2));
      final labels = tester
          .widgetList<Text>(footers)
          .map((w) => w.data)
          .toList();
      await tester.pump(const Duration(hours: 3));
      final reads = client.requests.length;
      await tester.tap(find.byTooltip('Chat actions'));
      await pumpChatUpdates(tester);
      await tester.tap(find.text('Refresh'));
      await pumpChatUpdates(tester);
      expect(client.requests.length, greaterThan(reads));
      expect(tester.widgetList<Text>(footers).map((w) => w.data), labels);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _chat(client, key: const ValueKey('timed-reopen')),
      );
      await pumpChatUpdates(tester);
      expect(footers, findsNWidgets(2));
      expect(tester.widgetList<Text>(footers).map((w) => w.data), labels);
    });
  }

  testWidgets('tool-heavy reopen restores earlier bubbles; sliding refresh '
      'retains them and adds the completed reply', (tester) async {
    final client = _HistoryHttpClient(_toolHeavyRows(124));
    await tester.pumpWidget(_chat(client, key: const ValueKey('first-open')));
    await pumpChatUpdates(tester);
    expect(client.offsets, [0, 50, 100]);
    expect(find.text('Earlier question'), findsOneWidget);
    expect(find.text('Earlier answer'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_chat(client, key: const ValueKey('reopen')));
    await pumpChatUpdates(tester);
    expect(client.offsets, [0, 50, 100, 0, 50, 100]);
    expect(find.text('Earlier question'), findsOneWidget);

    client.rows = [
      ...client.rows,
      for (var id = 125; id <= 184; id++)
        {
          'id': id,
          'role': 'tool',
          'name': 'fixture_tool',
          'tool_call_id': 'tool-$id',
          'content': 'Tool output $id',
        },
      {'id': 185, 'role': 'assistant', 'content': 'Completed answer'},
    ];
    await tester.tap(find.byTooltip('Chat actions'));
    await pumpChatUpdates(tester);
    await tester.tap(find.text('Refresh'));
    await pumpChatUpdates(tester);
    expect(client.offsets.last, 0);
    expect(find.text('Earlier question'), findsOneWidget);
    expect(find.text('Earlier answer'), findsOneWidget);
    // Source labels and collapsed metadata change the visible row heights.
    // Verify the retained final row through the real lazy list, not a viewport
    // assumption that every bubble fits at once.
    await tester.scrollUntilVisible(
      find.text('Completed answer'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Completed answer'), findsOneWidget);
  });

  testWidgets('refresh keeps dialogue visible while loading and on failure', (
    tester,
  ) async {
    final client = _HistoryHttpClient([
      {'id': 1, 'role': 'user', 'content': 'Keep this question'},
      {'id': 2, 'role': 'assistant', 'content': 'Keep this answer'},
    ]);
    await tester.pumpWidget(_chat(client));
    await pumpChatUpdates(tester);
    expect(find.text('Keep this question'), findsOneWidget);

    final gate = client.responseGate = Completer<void>();
    await tester.tap(find.byTooltip('Chat actions'));
    await pumpChatUpdates(tester);
    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(find.text('Keep this question'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    client.failNextRequest = true;
    gate.complete();
    await pumpChatUpdates(tester);
    expect(find.text('Keep this question'), findsOneWidget);
    expect(find.text('Keep this answer'), findsOneWidget);
    expect(find.text('Failed to load messages'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('bounded open exposes Load more and fetches older conversation', (
    tester,
  ) async {
    final client = _HistoryHttpClient(_toolHeavyRows(612));
    await tester.pumpWidget(_chat(client));
    await pumpChatUpdates(tester);
    expect(client.offsets, [
      for (var offset = 0; offset < 600; offset += 50) offset,
    ]);
    expect(find.text('Earlier question'), findsNothing);

    final olderButton = find.byKey(const Key('chat-load-older'));
    await tester.scrollUntilVisible(
      olderButton,
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(olderButton);
    await pumpChatUpdates(tester);
    expect(client.offsets.last, 600);
    expect(find.text('Earlier question'), findsOneWidget);
    expect(find.text('Earlier answer'), findsOneWidget);
  });

  testWidgets('reattach keeps backfilled bubbles when its latest page slides', (
    tester,
  ) async {
    final client = _HistoryHttpClient(_toolHeavyRows(124));
    final hook = TestDesktopConnectionHook();
    final submitted = Completer<void>();
    var sent = false;
    var ensures = 0;
    await tester.pumpWidget(
      _chat(
        client,
        connectionHook: hook,
        onSessionEnsured: () => ensures++,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              sent = true;
              onSent();
              return submitted.future;
            },
      ),
    );
    await pumpChatUpdates(tester);
    expect(find.text('Earlier question'), findsOneWidget);
    expect(ensures, 0);

    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      'Pending prompt',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump();
    expect(sent, isTrue);
    hook.handler?.call(DesktopConnectionState.reconnecting);
    await tester.pump();
    expect(
      find.textContaining('the running reply continues on the server'),
      findsOneWidget,
    );
    submitted.completeError(
      JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
    );
    await pumpChatUpdates(tester);
    expect(ensures, 0);

    client.rows = [
      ...client.rows,
      for (var id = 125; id <= 184; id++)
        {
          'id': id,
          'role': 'tool',
          'name': 'fixture_tool',
          'tool_call_id': 'tool-$id',
          'content': 'Tool output $id',
        },
      {'id': 185, 'role': 'assistant', 'content': 'Detached final reply'},
    ];
    hook.handler?.call(DesktopConnectionState.connected);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await pumpChatUpdates(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ensures, greaterThan(0), reason: 'socket rebind ran');
    expect(
      client.offsets.where((offset) => offset == 0).length,
      greaterThan(1),
    );
    expect(
      client.requests.every(
        (uri) =>
            uri.queryParameters['limit'] == '50' &&
            uri.queryParameters['order'] == 'latest',
      ),
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Earlier question'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Earlier question'), findsOneWidget);
    expect(find.text('Earlier answer'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Detached final reply'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Detached final reply'), findsOneWidget);
  });
}
