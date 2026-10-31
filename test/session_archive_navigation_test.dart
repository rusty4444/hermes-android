import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/session_list_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

http.Response _json(Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

class _TrackedClient extends MockClient {
  _TrackedClient(super.handler);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

class _NavigationServer {
  static const title = 'Canonical conversation';
  static const storedId = 'stored-session';

  final connection = SavedConnection(
    id: 'archive-navigation',
    label: 'Fixture',
    host: 'fixture',
    port: 8642,
    apiKey: 'test-key',
    gatewayPrefix: '/mobile',
  );
  bool archived = false;
  bool omitStoredRow = false;
  final offsets = <int>[];
  final writes = <http.Request>[];
  final readOwners = <bool>[];
  final opened = <Session>[];
  final children = <_TrackedClient>[];
  Future<http.Response> Function(int count)? page;
  Future<http.Response> Function(http.Request request)? patch;

  Map<String, dynamic> row() => {
    'id': storedId,
    'title': title,
    'model': 'rich-model',
    'source': 'api_server',
    'message_count': 8,
    'preview': 'Retained rich preview',
    'started_at': 10,
    'last_active': 19,
    'ended_at': 20,
    'archived': archived,
    '_lineage_root_id': 'lineage-root',
  };

  http.Response saved() => _json({
    'session': {'id': storedId, 'archived': archived},
  });

  http.Response snapshot() => _json({
    'data': [
      if (!archived && !omitStoredRow) row(),
      {
        'id': 'other',
        'title': 'Other conversation',
        'source': 'api_server',
        'message_count': 2,
      },
    ],
    'has_more': false,
  });

  late final parent = _TrackedClient(
    (request) => _handle(request, child: false),
  );

  Future<http.Response> _handle(
    http.Request request, {
    required bool child,
  }) async {
    expectSync(request.headers['authorization'], 'Bearer test-key');
    final path = request.url.path;
    if (path == '/mobile/health') return _json({'status': 'ok'});
    if (path == '/mobile/api/sessions') {
      expectSync(child, isFalse);
      if (!request.url.queryParameters.containsKey('offset')) {
        return _json({'data': []});
      }
      offsets.add(int.parse(request.url.queryParameters['offset']!));
      if (page != null) return page!(offsets.length);
      return snapshot();
    }
    if (path.endsWith('/messages')) {
      expectSync(child, isTrue);
      return _json({
        'data': [
          {'id': 1, 'role': 'user', 'content': 'Fixture question'},
          {'id': 2, 'role': 'assistant', 'content': 'Fixture reply'},
        ],
      });
    }
    expectSync(path, '/mobile/api/sessions/$storedId');
    if (request.method == 'GET') {
      readOwners.add(child);
      return saved();
    }
    expectSync(child, isFalse, reason: 'the parent owns every archive PATCH');
    expectSync(parent.closed, isFalse);
    expectSync(request.method, 'PATCH');
    writes.add(request);
    if (patch != null) return patch!(request);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expectSync(body.keys, ['archived']);
    archived = body['archived'] as bool;
    return saved();
  }

  Widget chat(Session session, Future<bool> Function(String, bool) archiver) {
    opened.add(session);
    final transport = _TrackedClient(
      (request) => _handle(request, child: true),
    );
    children.add(transport);
    return ChatScreen(
      connection: connection,
      session: session,
      sessionArchiver: archiver,
      testApiClient: ApiClient(
        baseUrl: connection.baseUrl,
        apiKey: connection.apiKey,
        pathPrefix: '/mobile',
        httpClient: transport,
      ),
      testStoredSessionKey: (_) => storedId,
      testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
    );
  }
}

Future<void> _mount(WidgetTester tester, _NavigationServer server) async {
  final controller = GatewayTurnApplicationController();
  addTearDown(controller.close);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: hermesTheme(Brightness.dark),
      home: SessionListScreen(
        connection: server.connection,
        turnApplicationController: controller,
        testHttpClient: server.parent,
        testChatScreenBuilder: server.chat,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rootTile(String title) => find.ancestor(
  of: find.text(title, skipOffstage: false),
  matching: find.byType(ListTile, skipOffstage: false),
);

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Chat actions'));
  await tester.pump();
  await tester.pump(kThemeAnimationDuration);
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  testWidgets('long-lived archive failure reaches chat Retry without success', (
    tester,
  ) async {
    final server = _NavigationServer();
    server.patch = (request) async {
      if (server.writes.length == 1) {
        return http.Response(jsonEncode({'error': 'Rejected fixture'}), 500);
      }
      server.archived = jsonDecode(request.body)['archived'] as bool;
      return server.saved();
    };
    await _mount(tester, server);
    await tester.tap(find.text(_NavigationServer.title));
    await tester.pumpAndSettle();
    await _choose(tester, 'Archive chat');
    await tester.pumpAndSettle();
    expectSync(server.writes, hasLength(1));
    expectSync(find.text('Chat archived'), findsNothing);
    expectSync(
      find.textContaining('Could not update chat archive:'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expectSync(server.writes, hasLength(2));
    expectSync(server.readOwners, [true, false]);
    expectSync(find.text('Chat archived'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expectSync(find.byType(ChatScreen), findsNothing);
    expectSync(find.text(_NavigationServer.title), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expectSync(tester.takeException(), isNull);
  });

  for (final holdPopRead in [false, true]) {
    testWidgets(
      'real chat pop preserves late archive (held parent read: $holdPopRead)',
      (tester) async {
        final server = _NavigationServer();
        final patch = Completer<http.Response>();
        final oldPopRead = Completer<http.Response>();
        final oldSnapshot = server.snapshot();
        server.patch = (_) => patch.future;
        server.page = (count) async => count == 2 && holdPopRead
            ? await oldPopRead.future
            : server.snapshot();
        await _mount(tester, server);
        final staleMenu = tester.widget<PopupMenuButton<String>>(
          find.descendant(
            of: _rootTile(_NavigationServer.title),
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await tester.tap(find.text(_NavigationServer.title));
        await tester.pumpAndSettle();
        expectSync(find.byType(ChatScreen), findsOneWidget);
        await _choose(tester, 'Archive chat');
        expectSync(server.writes, hasLength(1));
        expectSync(jsonDecode(server.writes.single.body), {'archived': true});
        final transition = ModalRoute.of(
          tester.element(find.byType(ChatScreen)),
        )!.reverseTransitionDuration;
        Navigator.of(tester.element(find.byType(ChatScreen))).pop();
        // Advance the finite route/hero animations, not the pending PATCH's
        // unbounded progress indicator.
        for (var i = 0; i < 4; i++) {
          await tester.pump(transition);
        }
        expectSync(find.byType(ChatScreen), findsNothing);
        expectSync(server.children.single.closed, isTrue);
        expectSync(server.parent.closed, isFalse);
        expectSync(server.offsets, [0, 0]);
        if (!holdPopRead) {
          expectSync(
            tester.widget<ListTile>(_rootTile(_NavigationServer.title)).enabled,
            isFalse,
            reason: 'the parent retains same-row ownership after chat disposal',
          );
        }
        staleMenu.onSelected!('archive');
        staleMenu.onSelected!('unarchive');
        staleMenu.onSelected!('rename');
        await tester.pump(kThemeAnimationDuration);
        expectSync(server.writes, hasLength(1));
        expectSync(find.byType(AlertDialog), findsNothing);

        server.archived = true;
        patch.complete(server.saved());
        await tester.pumpAndSettle();
        expectSync(server.readOwners, [true, false]);
        expectSync(server.offsets, [0, 0, 0]);
        expectSync(find.text(_NavigationServer.title), findsNothing);
        expectSync(find.text('Other conversation'), findsOneWidget);
        if (holdPopRead) {
          oldPopRead.complete(oldSnapshot);
          await tester.pumpAndSettle();
          expectSync(find.text(_NavigationServer.title), findsNothing);
        }
        expectSync(find.text('Chat archived'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        expectSync(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'draft Unarchive restores and fences the stored identity, not L',
    (tester) async {
      final server = _NavigationServer()
        ..archived = true
        ..omitStoredRow = true;
      final oldList = Completer<http.Response>();
      final oldSnapshot = server.snapshot();
      server.page = (count) async =>
          count == 2 ? await oldList.future : server.snapshot();
      await _mount(tester, server);
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      await tester.tap(find.byTooltip('New Chat'));
      await tester.pumpAndSettle();
      final local = server.opened.single;
      expectSync(local.isLocalDraft, isTrue);
      expectSync(local.id, isNot(_NavigationServer.storedId));
      final pendingRead = refresh();
      await tester.pump();
      await _choose(tester, 'Unarchive chat');
      await tester.pumpAndSettle();
      expectSync(jsonDecode(server.writes.single.body), {'archived': false});
      oldList.complete(oldSnapshot);
      await pendingRead;
      await tester.pumpAndSettle();

      // Observe the retained parent projection before a fresh route-return read
      // can mask a wrong local-id insertion with a later canonical server row.
      final restored = tester.widget<ListTile>(_rootTile(local.title));
      final menu = tester.widget<PopupMenuButton<String>>(
        find.descendant(
          of: _rootTile(local.title),
          matching: find.byType(PopupMenuButton<String>, skipOffstage: false),
          skipOffstage: false,
        ),
      );
      final archiveItem = menu
          .itemBuilder(tester.element(_rootTile(local.title)))
          .whereType<PopupMenuItem<String>>()
          .singleWhere((item) => item.value == 'archive');
      expectSync(archiveItem.enabled, isTrue, reason: 'S is no longer a draft');
      restored.onTap!();
      await tester.pumpAndSettle();
      final canonical = server.opened.last;
      expectSync(canonical.id, _NavigationServer.storedId);
      expectSync(canonical.isLocalDraft, isFalse);
      expectSync(canonical.archived, isFalse);
      expectSync(canonical.title, local.title);
      expectSync(canonical.model, local.model);
      expectSync(canonical.source, local.source);
      expectSync(canonical.preview, local.preview);
      expectSync(canonical.startedAt, local.startedAt);
      expectSync(canonical.messageCount, local.messageCount);

      // A subsequent stale read of S must be fenced by S's confirmed archive,
      // not by the unrelated original local draft identifier.
      server.omitStoredRow = false;
      final staleCanonical = Completer<http.Response>();
      server.page = (_) => staleCanonical.future;
      final pendingCanonical = refresh();
      await tester.pump();
      await _choose(tester, 'Archive chat');
      await tester.pumpAndSettle();
      staleCanonical.complete(
        _json({
          'data': [
            {...server.row(), 'archived': false},
          ],
        }),
      );
      await pendingCanonical;
      await tester.pumpAndSettle();
      expectSync(_rootTile(local.title), findsNothing);
      expectSync(_rootTile(_NavigationServer.title), findsNothing);
      expectSync(server.writes.map((r) => r.url.path), [
        '/mobile/api/sessions/${_NavigationServer.storedId}',
        '/mobile/api/sessions/${_NavigationServer.storedId}',
      ]);
      await tester.pumpWidget(const SizedBox());
      expectSync(tester.takeException(), isNull);
    },
  );
}
