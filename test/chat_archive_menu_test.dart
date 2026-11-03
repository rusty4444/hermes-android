import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/services/ws_client.dart';
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
  preview: 'Rich preview',
  startedAt: 10,
  endedAt: 20,
  lastActive: 19,
  pinned: true,
  lineageRootId: 'root',
);

http.Response _saved(String id, bool archived) => http.Response(
  jsonEncode({
    'session': {'id': id, 'archived': archived},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// Real ApiClient transport fixture: no fake mutation methods or user writes.
class _ArchiveHttp {
  _ArchiveHttp({this.id = 'listed-tip', this.archived = false});

  final String id;
  bool archived;
  List<Map<String, dynamic>> messages = [];
  int reads = 0;
  final writes = <http.Request>[];
  Future<http.Response> Function(http.Request)? patch;
  Future<http.Response> Function(int)? read;

  late final client = ApiClient(
    baseUrl: 'https://fixture:8642',
    pathPrefix: '/mobile',
    apiKey: 'test-key',
    httpClient: MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer test-key');
      if (request.url.path.endsWith('/messages')) {
        expect(request.method, 'GET');
        return http.Response(jsonEncode({'data': messages}), 200);
      }
      expect(
        request.url.toString(),
        'https://fixture:8642/mobile/api/sessions/${Uri.encodeComponent(id)}',
      );
      if (request.method == 'GET') {
        reads++;
        if (read != null) return read!(reads);
        return _saved(id, archived);
      }
      expect(request.method, 'PATCH');
      expect(request.headers['content-type'], 'application/json');
      writes.add(request);
      if (patch != null) return patch!(request);
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload.keys, ['archived']);
      archived = payload['archived'] as bool;
      return _saved(id, archived);
    }),
  );
}

class _HydrationController extends GatewayTurnApplicationController {
  _HydrationController(this.pendingStore);

  final NormalGatewayPendingStore pendingStore;
  NormalGatewayApplicationSession? session;

  @override
  NormalGatewayApplicationSession normalSessionFor(
    SavedConnection connection, {
    NormalGatewayPromptSubmit? submit,
    NormalGatewaySteer? steer,
    NormalGatewayResume? resume,
    NormalGatewayHistory? history,
    TurnNotificationService? notifications,
  }) => session ??= NormalGatewayApplicationSession(
    connection: connection,
    scope: 'archive-hydration',
    pendingStore: pendingStore,
    submit: submit,
    steer: steer,
    resume: ({required localSessionId, required storedSessionId}) async =>
        const ResumedGatewaySession(
          runtimeSessionId: 'running-fixture',
          running: true,
        ),
    history: history,
    notifications: notifications,
  );

  @override
  Future<void> close() async {
    await session?.close();
    await super.close();
  }
}

Future<void> _mount(
  WidgetTester tester,
  _ArchiveHttp server, {
  Session session = _session,
  Future<void> Function(String, bool)? changed,
  TestRemotePromptSubmit? submit,
  TestDesktopConnectionHook? connectionHook,
  NormalGatewayResume? resume,
  GatewayTurnApplicationController? controller,
  Future<bool> Function(String, bool)? archiver,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'archive-test',
          label: 'Test',
          host: 'fixture',
          port: 8642,
          apiKey: 'test-key',
        ),
        session: session,
        testApiClient: server.client,
        testStoredSessionKey: (_) => server.id,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        onArchiveChanged: changed,
        sessionArchiver: archiver,
        testRemotePromptSubmit: submit,
        testDesktopConnectionHook: connectionHook,
        testNormalResume: resume,
        turnApplicationController: controller,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PopupMenuButton<String> _menu(WidgetTester tester) => tester
    .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>));

Future<void> _openMenu(WidgetTester tester, {bool busy = false}) async {
  await tester.tap(find.byTooltip('Chat actions'));
  if (busy) {
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
  } else {
    await tester.pumpAndSettle();
  }
}

PopupMenuItem<String> _item(WidgetTester tester, String label) =>
    tester.widget<PopupMenuItem<String>>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(PopupMenuItem<String>),
      ),
    );

Future<void> _choose(WidgetTester tester, String label) async {
  await _openMenu(tester);
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(kThemeAnimationDuration);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  for (final pendingTurn in [false, true]) {
    testWidgets(
      'cold archive waits for receipt hydration (pending: $pendingTurn)',
      (tester) async {
        final marker = const NormalGatewayPendingMarker(
          scope: 'archive-hydration',
          localSessionId: 'mobile-alias',
          storedSessionId: 'listed-tip',
          turnId: 'persisted-running-turn',
          rowFloor: 2,
          phase: 'emitted',
          createdAt: 1,
          updatedAt: 1,
        );
        SharedPreferences.setMockInitialValues({
          'verbose_mode': false,
          NormalGatewayPendingStore.preferenceKey: jsonEncode([
            if (pendingTurn) marker.toJson(),
          ]),
        });
        final preferences = await SharedPreferences.getInstance();
        final hydration = Completer<SharedPreferences>();
        final controller = _HydrationController(
          NormalGatewayPendingStore(preferences: () => hydration.future),
        );
        controller.setLifecycle(
          background: false,
          backgroundWorkEnabled: false,
        );
        addTearDown(controller.close);
        final server = _ArchiveHttp();
        await _mount(
          tester,
          server,
          controller: controller,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {},
        );
        final staleMenu = _menu(tester);
        await _openMenu(tester);
        expect(_item(tester, 'Archive chat').enabled, isFalse);
        staleMenu.onSelected!('archive');
        await tester.pump();
        expect(server.writes, isEmpty);
        Navigator.of(tester.element(find.text('Archive chat'))).pop();
        await tester.pumpAndSettle();

        hydration.complete(preferences);
        await tester.pump();
        await tester.pump(kThemeAnimationDuration);
        await controller.session!.ready;
        if (pendingTurn) {
          expect(find.byTooltip('Chat actions'), findsNothing);
          staleMenu.onSelected!('archive');
          await tester.pump();
          expect(server.writes, isEmpty);
          expect(controller.session!.hasActiveTurn, isTrue);
        } else {
          await _openMenu(tester);
          expect(_item(tester, 'Archive chat').enabled, isTrue);
        }
        await tester.pumpWidget(const SizedBox());
        await controller.close();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final storedId in ['listed-tip', 'durable-id']) {
    testWidgets('archive/unarchive verifies exact stored target $storedId', (
      tester,
    ) async {
      final server = _ArchiveHttp(id: storedId);
      final readback = Completer<http.Response>();
      final changes = <(String, bool)>[];
      server.read = (count) async => count == 2
          ? await readback.future
          : _saved(storedId, server.archived);
      await _mount(
        tester,
        server,
        changed: (id, archived) async {
          changes.add((id, archived));
        },
      );
      expect(server.reads, 1, reason: 'reopen reads current stored metadata');
      await tester.enterText(find.byType(TextField), 'Unsent composer draft');
      final staleMenu = _menu(tester);
      await _choose(tester, 'Archive chat');
      expect(server.writes, hasLength(1));
      expect(jsonDecode(server.writes.single.body), {'archived': true});
      expect(server.reads, 2);
      expect(changes, isEmpty, reason: 'PATCH alone is not confirmation');
      expect(
        find.byKey(const ValueKey('chat-archive-progress')),
        findsOneWidget,
      );

      // A queued/stale popup callback cannot duplicate or conflict with a save.
      staleMenu.onSelected!('archive');
      staleMenu.onSelected!('unarchive');
      staleMenu.onSelected!('rename');
      await tester.pump();
      expect(server.writes, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      await _openMenu(tester, busy: true);
      expect(_item(tester, 'Archive chat').enabled, isFalse);
      expect(_item(tester, 'Rename').enabled, isFalse);
      Navigator.of(tester.element(find.text('Archive chat'))).pop();
      await tester.pump(kThemeAnimationDuration);

      readback.complete(_saved(storedId, true));
      await tester.pumpAndSettle();
      expect(changes, [(storedId, true)]);
      expect(find.text('Unsent composer draft'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-archive-progress')), findsNothing);
      await _choose(tester, 'Unarchive chat');
      await tester.pumpAndSettle();
      expect(server.writes.map((r) => jsonDecode(r.body)), [
        {'archived': true},
        {'archived': false},
      ]);
      expect(server.reads, 3);
      expect(changes, [(storedId, true), (storedId, false)]);
      await _openMenu(tester);
      expect(_item(tester, 'Archive chat').enabled, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reopen trusts current server flag instead of stale navigation', (
    tester,
  ) async {
    final server = _ArchiveHttp(archived: true);
    await _mount(tester, server);
    await _choose(tester, 'Unarchive chat');
    await tester.pumpAndSettle();
    expect(jsonDecode(server.writes.single.body), {'archived': false});
    await tester.pumpWidget(const SizedBox());
    final reopened = _ArchiveHttp(archived: false);
    await _mount(tester, reopened, session: _session.withArchived(true));
    await _openMenu(tester);
    expect(_item(tester, 'Archive chat').enabled, isTrue);
    expect(find.text('Unarchive chat'), findsNothing);
    expect(reopened.reads, 1);
    expect(reopened.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'failed read-back keeps state and Retry repeats the same intent',
    (tester) async {
      final server = _ArchiveHttp();
      final changes = <bool>[];
      server.patch = (request) async {
        expect(jsonDecode(request.body), {'archived': true});
        if (server.writes.length > 1) server.archived = true;
        return _saved(server.id, true);
      };
      await _mount(
        tester,
        server,
        changed: (_, value) async {
          changes.add(value);
        },
      );
      await _choose(tester, 'Archive chat');
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(
        find.textContaining('Could not update chat archive:'),
        findsOneWidget,
      );
      expect(server.reads, 2);
      await _openMenu(tester);
      expect(_item(tester, 'Archive chat').enabled, isTrue);
      Navigator.of(tester.element(find.text('Archive chat'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(server.writes, hasLength(2));
      expect(server.reads, 3);
      expect(changes, [true]);
      await _openMenu(tester);
      expect(_item(tester, 'Unarchive chat').enabled, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late pre-write metadata cannot undo a confirmed menu state', (
    tester,
  ) async {
    final server = _ArchiveHttp();
    final oldRead = Completer<http.Response>();
    server.read = (count) async =>
        count == 1 ? await oldRead.future : _saved(server.id, server.archived);
    await _mount(tester, server);
    await _choose(tester, 'Archive chat');
    await tester.pumpAndSettle();
    oldRead.complete(_saved(server.id, false));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    expect(_item(tester, 'Unarchive chat').enabled, isTrue);
    expect(server.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('success waits for asynchronous owner reconciliation', (
    tester,
  ) async {
    final server = _ArchiveHttp(id: 'stored-owner', archived: true);
    final reconcile = Completer<void>();
    final changes = <(String, bool)>[];
    await _mount(
      tester,
      server,
      changed: (id, archived) {
        changes.add((id, archived));
        return reconcile.future;
      },
    );
    await _choose(tester, 'Unarchive chat');
    expect(server.reads, 2);
    expect(changes, [('stored-owner', false)]);
    expect(find.text('Chat unarchived'), findsNothing);
    expect(find.byKey(const ValueKey('chat-archive-progress')), findsOneWidget);
    reconcile.complete();
    await tester.pumpAndSettle();
    expect(find.text('Chat unarchived'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending archive completion is silent after route disposal', (
    tester,
  ) async {
    final server = _ArchiveHttp();
    final patch = Completer<http.Response>();
    final changes = <bool>[];
    server.patch = (_) => patch.future;
    await _mount(
      tester,
      server,
      changed: (_, value) async {
        changes.add(value);
      },
    );
    await _choose(tester, 'Archive chat');
    expect(server.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    server.archived = true;
    patch.complete(_saved(server.id, true));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsaved local draft cannot archive or issue a PATCH', (
    tester,
  ) async {
    final draft = Session(
      id: _session.id,
      title: 'Unsaved draft',
      model: 'test-model',
      source: 'mobile',
      messageCount: 0,
      isActive: false,
      preview: '',
      startedAt: 1,
      isLocalDraft: true,
    );
    final server = _ArchiveHttp();
    await _mount(tester, server, session: draft);
    final staleMenu = _menu(tester);
    await _openMenu(tester);
    expect(_item(tester, 'Archive chat').enabled, isFalse);
    staleMenu.onSelected!('archive');
    await tester.pump();
    expect(server.writes, isEmpty);
    expect(server.reads, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rename ownership disables archive before its PATCH starts', (
    tester,
  ) async {
    final server = _ArchiveHttp();
    await _mount(tester, server);
    final menu = _menu(tester);
    menu.onSelected!('rename');
    menu.onSelected!('archive');
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
    await tester.pumpAndSettle();
    expect(find.text('Rename chat'), findsOneWidget);
    expect(server.writes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    expect(_item(tester, 'Archive chat').enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('send, streaming and reattach reject stale archive callbacks', (
    tester,
  ) async {
    final server = _ArchiveHttp();
    final connectionHook = TestDesktopConnectionHook();
    final submission = Completer<void>();
    final resumeGate = Completer<ResumedGatewaySession>();
    final controller = GatewayTurnApplicationController();
    controller.setLifecycle(background: false, backgroundWorkEnabled: false);
    addTearDown(controller.close);
    await _mount(
      tester,
      server,
      controller: controller,
      connectionHook: connectionHook,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) {
            onSent();

            return submission.future;
          },
      resume: ({required localSessionId, required storedSessionId}) =>
          resumeGate.future,
    );
    final staleMenu = _menu(tester);
    connectionHook.handler!(DesktopConnectionState.connected);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Fixture prompt only');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(
      find.byTooltip('Chat actions'),
      findsNothing,
      reason: 'a running streamed reply owns the chat',
    );
    staleMenu.onSelected!('archive');
    await tester.pump();
    expect(server.writes, isEmpty);
    connectionHook.handler!(DesktopConnectionState.reconnecting);
    submission.completeError(
      JsonRpcError('prompt.submit', 'Desktop gateway connection closed'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    connectionHook.handler!(DesktopConnectionState.connected);
    await tester.pump();
    staleMenu.onSelected!('archive');
    await tester.pump();
    expect(server.writes, isEmpty);
    await _openMenu(tester, busy: true);
    expect(_item(tester, 'Archive chat').enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    server.messages = [
      {'id': 1, 'role': 'user', 'content': 'Fixture prompt only'},
      {'id': 2, 'role': 'assistant', 'content': 'Fixture completed reply'},
    ];
    resumeGate.complete(
      const ResumedGatewaySession(
        runtimeSessionId: 'fixture-runtime',
        running: false,
        status: 'completed',
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
