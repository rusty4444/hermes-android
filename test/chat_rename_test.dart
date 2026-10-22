import 'dart:async';
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

const _session = Session(
  id: 'listed-tip',
  title: 'Original title',
  model: 'test-model',
  source: 'api_server',
  messageCount: 2,
  isActive: false,
  preview: 'Keep this preview',
  startedAt: 10,
  endedAt: 20,
  lastActive: 19,
  pinned: true,
  lineageRootId: 'root',
  archived: true,
);

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      baseUrl: 'https://fixture:8642',
      pathPrefix: '/profile/mobile',
      apiKey: 'test-key',
      httpClient: MockClient(handler),
    );

http.Response _saved(String id, String title) => http.Response(
  jsonEncode({
    'object': 'hermes.session',
    'session': {'id': id, 'title': title},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

Future<void> _mountChat(
  WidgetTester tester,
  ApiClient client, {
  String? storedId,
  Session session = _session,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'rename-test',
          label: 'Test',
          host: 'fixture',
          port: 8642,
          apiKey: 'test-key',
        ),
        session: session,
        testApiClient: client,
        testStoredSessionKey: storedId == null ? null : (_) => storedId,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openRename(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Chat actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rename'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  test('withTitle changes only the title, retaining all session metadata', () {
    final renamed = _session.withTitle('New title');
    expect(renamed.title, 'New title');
    expect(renamed.id, _session.id);
    expect(renamed.model, _session.model);
    expect(renamed.source, _session.source);
    expect(renamed.messageCount, _session.messageCount);
    expect(renamed.isActive, _session.isActive);
    expect(renamed.preview, _session.preview);
    expect(renamed.startedAt, _session.startedAt);
    expect(renamed.endedAt, _session.endedAt);
    expect(renamed.lastActive, _session.lastActive);
    expect(renamed.pinned, _session.pinned);
    expect(renamed.lineageRootId, _session.lineageRootId);
    expect(renamed.archived, _session.archived);
    expect(renamed.isLocalDraft, _session.isLocalDraft);
  });

  test(
    'rename PATCH uses Bearer auth, prefix, encoded ID and title only',
    () async {
      final client = _client((request) async {
        expect(request.method, 'PATCH');
        expect(
          request.url.toString(),
          'https://fixture:8642/profile/mobile/api/sessions/chat%2F%23%20one',
        );
        expect(request.headers['authorization'], 'Bearer test-key');
        expect(jsonDecode(request.body), {'title': 'A new title'});
        return _saved('chat/# one', 'Server-normalised title');
      });
      addTearDown(client.close);
      expect(
        await client.renameSession(
          sessionId: 'chat/# one',
          title: '  A new title  ',
        ),
        'Server-normalised title',
      );
    },
  );

  test('rename rejects blank names before any request', () async {
    var requests = 0;
    final client = _client((_) async {
      requests++;
      return _saved('id', '');
    });
    addTearDown(client.close);
    await expectLater(
      client.renameSession(sessionId: 'id', title: '   '),
      throwsArgumentError,
    );
    expect(requests, 0);
  });

  for (final status in [400, 401, 404, 405, 500]) {
    test('rename surfaces HTTP $status without pretending it saved', () async {
      final client = _client(
        (_) async => http.Response('Rejected title', status),
      );
      addTearDown(client.close);
      await expectLater(
        client.renameSession(sessionId: 'id', title: 'Changed'),
        throwsA(
          predicate((error) => error.toString().contains('HTTP $status')),
        ),
      );
    });
  }

  for (final body in [
    '{}',
    '{"session":{"id":"other","title":"Wrong session"}}',
    '{"session":{"id":"id"}}',
  ]) {
    test('rename rejects an invalid acknowledgement: $body', () async {
      final client = _client((_) async => http.Response(body, 200));
      addTearDown(client.close);
      await expectLater(
        client.renameSession(sessionId: 'id', title: 'Changed'),
        throwsFormatException,
      );
    });
  }

  for (final storedId in <String?>[null, 'durable-id']) {
    testWidgets('open chat renames the stored identity ($storedId)', (
      tester,
    ) async {
      final writes = <http.Request>[];
      final client = _client((request) async {
        if (request.method == 'PATCH') {
          writes.add(request);
          return _saved(storedId ?? _session.id, 'Confirmed title');
        }
        return http.Response('{"data":[]}', 200);
      });
      await _mountChat(tester, client, storedId: storedId);
      await tester.enterText(find.byType(TextField), 'Unsent composer draft');
      await _openRename(tester);
      expect(find.text('Rename chat'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Original title'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField), '  New name  ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single.url.pathSegments.last, storedId ?? _session.id);
      expect(jsonDecode(writes.single.body), {'title': 'New name'});
      expect(find.text('Confirmed title'), findsOneWidget);
      expect(find.text('Unsent composer draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancel, blank and unchanged names never write', (tester) async {
    var writes = 0;
    final client = _client((request) async {
      if (request.method == 'PATCH') writes++;
      return http.Response('{"data":[]}', 200);
    });
    await _mountChat(tester, client);
    await _openRename(tester);
    await tester.enterText(find.byType(TextFormField), 'Discarded');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _openRename(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    await _openRename(tester);
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Rename chat'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Original title'), findsOneWidget);
  });

  testWidgets(
    'failed rename keeps the old title and surfaces the server error',
    (tester) async {
      final client = _client(
        (request) async => request.method == 'PATCH'
            ? http.Response('Title already exists', 400)
            : http.Response('{"data":[]}', 200),
      );
      await _mountChat(tester, client);
      await _openRename(tester);
      await tester.enterText(find.byType(TextFormField), 'Duplicate name');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Original title'), findsOneWidget);
      expect(find.textContaining('Could not rename chat:'), findsOneWidget);
      expect(find.textContaining('Title already exists'), findsOneWidget);
    },
  );

  testWidgets('pending rename is single-flight and safe after route disposal', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var writes = 0;
    final client = _client((request) async {
      if (request.method == 'PATCH') {
        writes++;
        return response.future;
      }
      return http.Response('{"data":[]}', 200);
    });
    await _mountChat(tester, client);
    await _openRename(tester);
    await tester.enterText(find.byType(TextFormField), 'New title');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(writes, 1);
    await tester.tap(find.byTooltip('Chat actions'));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text('Rename'),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );
    expect(item.enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    response.complete(_saved(_session.id, 'New title'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(tester.takeException(), isNull);
  });
}
