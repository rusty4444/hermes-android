import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/android_launch_intent_service.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, widgetUntil;
import 'support/memory_turn_journal_store.dart';

Finder _chatComposer() => find.descendant(
  of: find.byType(ChatScreen),
  matching: find.byType(TextField),
);

class _RootServer extends BindingServer {
  _RootServer(super.server);
  static Future<_RootServer> start() async {
    final owner = _RootServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    owner.server.listen(owner.handle);
    return owner;
  }

  final requests = <String>[];
  Completer<void>? nextSessionListGate;
  Completer<void>? sessionListEntered;
  @override
  Future<void> handle(HttpRequest request) async {
    requests.add(request.uri.toString());
    if (request.uri.path == '/api/sessions' &&
        request.uri.queryParameters['archived'] == 'only') {
      // Consolidated Chats owns an independent Dashboard archive read. It uses
      // this fixture's trusted proxy, never the API-server Bearer credential.
      expect(request.headers.value('authorization'), isNull);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'sessions': [], 'total': 0}));
      await request.response.close();
      return;
    }
    if (request.uri.path == '/api/sessions') {
      expect(request.headers.value('authorization'), 'Bearer fixture');
      final gate = nextSessionListGate;
      if (gate != null) {
        nextSessionListGate = null;
        sessionListEntered!.complete();
        await gate.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'data': [
            if (creates > 0)
              {
                'id': 'stored',
                'title': 'Verified canonical',
                'model': 'fixture',
                'source': 'mobile',
                'message_count': rows.length,
                'started_at': 1,
              },
          ],
          'has_more': false,
        }),
      );
      await request.response.close();
      return;
    }
    await super.handle(request);
  }

  // Home/Workspace and recovery discovery may own independent control sockets.
  // Deliver a server session event on each open fixture socket; production
  // client runtime maps, not whichever socket was created last, admit it.
  @override
  void event(String type, Map<String, dynamic> payload, {String? turnId}) {
    for (final socket in sockets) {
      if (socket.readyState != WebSocket.open) continue;
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': type,
            'session_id': 'runtime',
            'turn_id': ?turnId,
            'payload': payload,
          },
        }),
      );
    }
  }

  void failTurn() {
    running = false;
    final id = 'wire-${prompts.length}';
    event('message.start', {}, turnId: id);
    event('turn.error', {'message': 'Fixture terminal failure'}, turnId: id);
  }
}

class _MemoryCredentials implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _RootAliasFixture {
  final controller = GatewayTurnApplicationController(
    journalFactory: () => GatewayTurnJournal(store: MemoryTurnJournalStore()),
  );
  final native = <String, dynamic>{'enabled': false};
  final nativeCalls = <MethodCall>[];
  final pluginCalls = <MethodCall>[];
  final live = <int, Map<String, dynamic>>{};
  final keepalive = <String>[];
  final pushRequests = <http.Request>[];
  final channel = const MethodChannel('test/spec-root-alias-push');
  static const plugin = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final launch = AndroidLaunchIntentService();
  late _RootServer server;
  late ConnectionManager manager;
  late SavedConnection connection;
  late MobilePushService push;
  List<Map<String, dynamic>> feed = [];
  bool nativeRunning = false;
  Future<void> initialize(WidgetTester tester) async {
    _lifecycle(tester, AppLifecycleState.resumed);
    server = (await tester.runAsync(_RootServer.start))!;
    manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: _MemoryCredentials(),
    );
    await manager.saveConnection(
      'Root loopback',
      '127.0.0.1',
      server.server.port,
      'fixture',
      dashboardPort: server.server.port,
      dashboardProxied: true,
      gatewayProfile: 'root-profile',
    );
    connection = manager.getConnections().single;
    final messenger = tester.binding.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => 1,
    );
    messenger.setMockMethodCallHandler(plugin, (call) async {
      pluginCalls.add(call);
      if (call.method == 'show') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        live[args['id'] as int] = args;
      } else if (call.method == 'cancel') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        live.remove(args['id']);
      }
      return call.method == 'getNotificationAppLaunchDetails' ? null : true;
    });
    messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
      call,
    ) async {
      keepalive.add(call.method);
      if (call.method == 'start') {
        nativeRunning = true;
      }
      if (call.method == 'stop') nativeRunning = false;
      return true;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call);
      switch (call.method) {
        case 'snapshot':
          return Map<String, dynamic>.from(native);
        case 'preferences':
          native.addAll(Map<String, dynamic>.from(call.arguments as Map));
          return Map<String, dynamic>.from(native);
        case 'takeTap':
          return native.remove('tap');
        case 'disable':
          native['enabled'] = false;
          native['active'] = false;
          native.remove('tap');
          return Map<String, dynamic>.from(native);
        default:
          throw StateError('Unexpected native command ${call.method}');
      }
    });
    push = MobilePushService(
      supported: true,
      channel: channel,
      clientFactory: (c) => DashboardClient(
        host: c.host,
        port: c.dashboardPort,
        proxied: c.dashboardProxied,
        gatewayProfile: c.gatewayProfile,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          expect(request.method, 'GET');
          expect(request.url.path, '/api/plugins/mobile-push/events');
          expect(request.url.queryParameters['profile'], 'root-profile');
          return http.Response(
            jsonEncode({'events': feed, 'has_more': false, 'next_cursor': '1'}),
            200,
          );
        }),
      ),
    );
    launch.pendingQuickChat.value =
        true; // Fixture-owned launcher input, production Home/Workspace navigation.
    await tester.pumpWidget(
      HermesApp(
        connManager: manager,
        turnApplicationController: controller,
        mobilePush: push,
        launchIntents: launch,
      ),
    );
    await widgetUntil(
      tester,
      () => find.byType(ChatScreen).evaluate().isNotEmpty,
    );
    await widgetUntil(
      tester,
      () => find
          .byKey(const ValueKey('legacy-transport-notice'))
          .evaluate()
          .isNotEmpty,
    );
    await _drain(tester);
    expect(find.byType(HermesApp), findsOneWidget);
    expect(find.byType(WorkspaceScreen, skipOffstage: false), findsOneWidget);
    expect(
      tester
          .widget<WorkspaceScreen>(
            find.byType(WorkspaceScreen, skipOffstage: false),
          )
          .turnApplicationController,
      same(controller),
    );
  }

  Future<void> canonicalTap(
    WidgetTester tester, {
    required bool viaPush,
    int mountedChats = 2,
  }) async {
    if (viaPush) {
      final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      native.addAll({
        'enabled': true,
        'active': true,
        'connection': connection.id,
        'binding': MobilePushService.binding(connection),
        'installation': 'root-spec-installation',
        'nonce': 'root-spec-nonce',
        'generation': 7,
        'revision': 1,
        'endpoint': 'https://push.invalid/opaque',
        'sessions': ['stored'],
        'tap': {
          'nonce': 'root-spec-nonce',
          'generation': 7,
          'revision': 1,
          'event_id': 'root-spec-event',
          'expires_at': expiry,
        },
      });
      feed = [
        {
          'event_id': 'root-spec-event',
          'session_id': 'stored',
          'kind': 'input',
          'expires_at': expiry,
        },
      ];
      await tester.runAsync(push.refresh);
    } else {
      tap('stored');
    }
    await widgetUntil(
      tester,
      () =>
          find.byType(ChatScreen, skipOffstage: false).evaluate().length ==
          mountedChats,
    );
    await tester.pump(const Duration(seconds: 1));
    await _drain(tester);
  }

  void tap(String id) {
    notificationResponseHandler!(
      NotificationResponse(
        payload: jsonEncode({'connectionId': connection.id, 'sessionId': id}),
        notificationResponseType: NotificationResponseType.selectedNotification,
      ),
    );
  }

  Iterable<Map<String, dynamic>> get ongoing => live.values.where(
    (n) => (n['platformSpecifics'] as Map?)?['ongoing'] == true,
  );
  Iterable<Map<String, dynamic>> get terminals => pluginCalls
      .where((c) => c.method == 'show')
      .map((c) => Map<String, dynamic>.from(c.arguments as Map))
      .where(
        (n) =>
            (n['title'] == 'Hermes response ready' ||
            n['title'] == 'Hermes turn failed'),
      );
  Future<void> close(WidgetTester tester) async {
    _lifecycle(tester, AppLifecycleState.resumed);
    await _drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _drain(tester);
    await controller.close();
    await tester.runAsync(server.close);
    await tester.pump(const Duration(seconds: 16));
    push.dispose();
    launch.dispose();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(
      ConnectionKeepAliveService.channel,
      null,
    );
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

void _lifecycle(WidgetTester tester, AppLifecycleState target) {
  if (tester.binding.lifecycleState == target) return;
  if (target == AppLifecycleState.paused) {
    if (tester.binding.lifecycleState == AppLifecycleState.resumed) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    if (tester.binding.lifecycleState == AppLifecycleState.inactive) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  } else {
    if (tester.binding.lifecycleState == AppLifecycleState.paused) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'verbose_mode': true,
      BackgroundWorkPrefsStore.storageKey: true,
    });
    backgroundWorkEnabled.value = true;
    notificationPrefs.value = NotificationPrefs.defaults;
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
    pendingNotificationApprovals.value = const [];
  });
  tearDown(() {
    HttpOverrides.global = previous;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'alias convergence during real detail lookup raises the retained canonical State',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final f = _RootAliasFixture();
      await f.initialize(tester);
      final detailGate = Completer<void>();
      try {
        final sourceId = tester
            .widget<ChatScreen>(find.byType(ChatScreen))
            .session
            .id;
        final normal = f.controller.normalSessionFor(f.connection);
        await tester.enterText(_chatComposer(), 'One held source prompt');
        await tester.tap(find.byTooltip('Send'));
        await widgetUntil(tester, () => f.server.createEntered.isCompleted);
        await f.canonicalTap(tester, viaPush: false);
        final canonicalState = tester.state(find.byType(ChatScreen));
        final nav = Navigator.of(canonicalState.context);
        nav.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Held lookup cover')),
          ),
        );
        await _drain(tester);
        f.server.nextSessionListGate = detailGate;
        f.server.sessionListEntered = Completer<void>();
        f.tap(sourceId);
        await widgetUntil(
          tester,
          () => f.server.sessionListEntered!.isCompleted,
        );
        expect(find.text('Held lookup cover'), findsOneWidget);
        f.server.releaseCreate();
        await widgetUntil(
          tester,
          () =>
              identical(normal.findChat(sourceId), normal.findChat('stored')) &&
              f.server.prompts.length == 1,
        );
        detailGate.complete();
        await widgetUntil(
          tester,
          () => ModalRoute.of(canonicalState.context)!.isCurrent,
        );
        await tester.pump(const Duration(seconds: 1));
        await _drain(tester);
        expect(find.text('Held lookup cover'), findsNothing);
        expect(tester.state(find.byType(ChatScreen)), same(canonicalState));
        expect(ModalRoute.of(canonicalState.context)!.isCurrent, isTrue);
        expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));
        _lifecycle(tester, AppLifecycleState.paused);
        await _drain(tester);
        f.server.finish('One result after lookup');
        await widgetUntil(tester, () => !f.controller.hasActiveTurn);
        await _drain(tester);
        expect(f.terminals, hasLength(1));
        expect(f.ongoing, isEmpty);
        expect(f.nativeRunning, isFalse);
        expect(f.server.prompts, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        if (!detailGate.isCompleted) detailGate.complete();
        await f.close(tester);
      }
    },
  );

  for (final localAliasFirst in [false, true]) {
    testWidgets(
      'converged root routes retain the canonical State and independent disposal; local alias first=$localAliasFirst',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = _RootAliasFixture();
        await f.initialize(tester);
        try {
          final sourceId = tester
              .widget<ChatScreen>(find.byType(ChatScreen))
              .session
              .id;
          final normal = f.controller.normalSessionFor(f.connection);
          await tester.enterText(_chatComposer(), 'One source prompt');
          await tester.tap(find.byTooltip('Send'));
          await widgetUntil(tester, () => f.server.createEntered.isCompleted);

          // Both notification routes are legitimate before the create reply
          // proves they are aliases. Register the local route first on purpose.
          f.tap(sourceId);
          await widgetUntil(
            tester,
            () =>
                find
                    .byType(ChatScreen, skipOffstage: false)
                    .evaluate()
                    .length ==
                2,
          );
          await tester.pump(const Duration(seconds: 1));
          await _drain(tester);
          final localRouteState = tester.state(find.byType(ChatScreen));
          await f.canonicalTap(tester, viaPush: false, mountedChats: 3);
          final canonicalState = tester.state(find.byType(ChatScreen));
          final canonicalRoute = ModalRoute.of(canonicalState.context)!;
          expect(canonicalState, isNot(same(localRouteState)));

          _lifecycle(tester, AppLifecycleState.paused);
          await _drain(tester);
          f.server.releaseCreate();
          await widgetUntil(
            tester,
            () =>
                identical(
                  normal.findChat(sourceId),
                  normal.findChat('stored'),
                ) &&
                f.server.prompts.length == 1,
          );
          _lifecycle(tester, AppLifecycleState.resumed);
          await _drain(tester);
          final nav = Navigator.of(canonicalState.context);
          final aliases = localAliasFirst
              ? [sourceId, 'stored']
              : ['stored', sourceId];
          for (final alias in aliases) {
            nav.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Alias cover')),
              ),
            );
            await _drain(tester);
            expect(canonicalRoute.isCurrent, isFalse);
            f.tap(alias);
            await _drain(tester);
            await tester.pump(const Duration(seconds: 1));
            await _drain(tester);
            expect(find.text('Alias cover'), findsNothing);
            expect(canonicalRoute.isCurrent, isTrue);
            expect(tester.state(find.byType(ChatScreen)), same(canonicalState));
            expect(
              find.byType(ChatScreen, skipOffstage: false),
              findsNWidgets(3),
            );
          }

          // Disposing one converged route must not erase its retained sibling.
          nav.pop();
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await _drain(tester);
          expect(canonicalState.mounted, isFalse);
          expect(tester.state(find.byType(ChatScreen)), same(localRouteState));
          nav.push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(body: Text('Remaining alias cover')),
            ),
          );
          await _drain(tester);
          f.tap('stored');
          await _drain(tester);
          await tester.pump(const Duration(seconds: 1));
          await _drain(tester);
          expect(find.text('Remaining alias cover'), findsNothing);
          expect(tester.state(find.byType(ChatScreen)), same(localRouteState));
          expect(
            find.byType(ChatScreen, skipOffstage: false),
            findsNWidgets(2),
          );
          expect(f.controller.activeChatActivities, hasLength(1));
          _lifecycle(tester, AppLifecycleState.paused);
          await _drain(tester);
          f.server.finish('Only result');
          await widgetUntil(tester, () => !f.controller.hasActiveTurn);
          await _drain(tester);
          expect(f.terminals, hasLength(1));
          expect(f.ongoing, isEmpty);
          expect(f.nativeRunning, isFalse);
          expect(f.server.prompts, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  for (final verifyFocus in [false, true]) {
    for (final canonicalActive in [false, true]) {
      for (final failure in [false, true]) {
        testWidgets(
          'real root late alias focus=$verifyFocus active=$canonicalActive failure=$failure preserves work and exact terminal',
          (tester) async {
            await tester.binding.setSurfaceSize(const Size(1000, 1600));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final f = _RootAliasFixture();
            await f.initialize(tester);
            final routeObservations = <String, dynamic>{};
            try {
              final sourceScreen = tester.widget<ChatScreen>(
                find.byType(ChatScreen),
              );
              final sourceId = sourceScreen.session.id;
              final session = f.controller.normalSessionFor(f.connection);
              final local = session.findChat(sourceId)!;
              final sourceSnapshots = <NormalGatewayChatSnapshot>[];
              final token = local.subscribe(sourceSnapshots.add);
              await tester.enterText(_chatComposer(), 'Original root prompt');
              await tester.tap(find.byTooltip('Send'));
              await widgetUntil(
                tester,
                () => f.server.createEntered.isCompleted,
              );
              final originalTurn = local.turnId;
              await f.canonicalTap(tester, viaPush: failure);
              final canonicalState = tester.state(find.byType(ChatScreen));
              if (canonicalActive) {
                await tester.enterText(
                  _chatComposer(),
                  'Canonical winning prompt',
                );
                await tester.tap(find.byTooltip('Send'));
                await widgetUntil(tester, () => f.server.prompts.length == 1);
                await tester.enterText(_chatComposer(), 'Canonical next draft');
              }
              final canonical = session.findChat('stored')!;
              final winnerTurn = canonicalActive
                  ? canonical.turnId
                  : originalTurn;
              _lifecycle(tester, AppLifecycleState.paused);
              await _drain(tester);
              expect(f.nativeRunning, isTrue);
              final starts = f.keepalive.where((x) => x == 'start').length;
              final stops = f.keepalive.where((x) => x == 'stop').length;
              expect(
                starts,
                1,
                reason: 'One service start for real unresolved root work',
              );
              f.server.releaseCreate();
              await widgetUntil(
                tester,
                () =>
                    identical(
                      session.findChat(sourceId),
                      session.findChat('stored'),
                    ) &&
                    f.server.prompts.length == 1,
              );
              await _drain(tester);
              expect(session.chats, hasLength(1));
              expect(f.controller.activeChatActivities, hasLength(1));
              expect(
                f.controller.activeChatActivities.single.turnId,
                winnerTurn,
              );
              expect(local.snapshot.turnId, winnerTurn);
              expect(f.keepalive.where((x) => x == 'start'), hasLength(starts));
              expect(f.keepalive.where((x) => x == 'stop'), hasLength(stops));
              expect(f.nativeRunning, isTrue);
              expect(f.ongoing, hasLength(1));
              final n = f.ongoing.single;
              final payload = jsonDecode(n['payload'] as String) as Map;
              expect(payload['sessionId'], 'stored');
              expect(payload['connectionId'], f.connection.id);
              expect(payload['turnId'], winnerTurn);
              final ongoingId = n['id'];
              expect(
                ongoingId,
                TurnNotificationService.ongoingChatNotificationIdFor(
                  connectionId: f.connection.id,
                  localSessionId: local.localSessionId,
                ),
              );
              expect(n.toString(), isNot(contains('root-spec-nonce')));
              expect(
                f.terminals,
                isEmpty,
                reason: 'Retiring prewire rejection is not a server failure',
              );
              if (canonicalActive) {
                expect(
                  sourceSnapshots.any(
                    (s) =>
                        s.phase == NormalGatewayTurnPhase.failed &&
                        !s.wireEmitted &&
                        s.turnId == originalTurn,
                  ),
                  isTrue,
                );
              }
              // Cover a still-mounted matching route, resume, then tap: root must
              // pop back to its exact canonical route, not keep the cover or clone it.
              final nav = Navigator.of(tester.element(find.byType(ChatScreen)));
              if (verifyFocus) {
                nav.push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        const Scaffold(body: Text('Cover authority probe')),
                  ),
                );
                _lifecycle(tester, AppLifecycleState.resumed);
                await _drain(tester);
                expect(find.text('Cover authority probe'), findsOneWidget);
                expect(f.nativeRunning, isFalse);
                expect(f.ongoing, isEmpty);
                final before = find
                    .byType(ChatScreen, skipOffstage: false)
                    .evaluate()
                    .length;
                routeObservations['allMountedBeforeRefocus'] = before;
                routeObservations['canonicalCurrentUnderCover'] = ModalRoute.of(
                  canonicalState.context,
                )!.isCurrent;
                await f.canonicalTap(tester, viaPush: failure);
                await _drain(tester);
                await widgetUntil(
                  tester,
                  () => find.byType(ChatScreen).evaluate().isNotEmpty,
                );
                await tester.pump(const Duration(seconds: 1));
                await _drain(tester);
                expect(find.text('Cover authority probe'), findsNothing);
                expect(
                  find.byType(ChatScreen, skipOffstage: false),
                  findsNWidgets(before),
                  reason:
                      'Late alias must not strand the canonical route under a stale root identity key',
                );
                expect(
                  tester.state(find.byType(ChatScreen)),
                  same(canonicalState),
                );
                routeObservations['allMountedAfterRefocus'] = find
                    .byType(ChatScreen, skipOffstage: false)
                    .evaluate()
                    .length;
                routeObservations['exactCanonicalStateRaised'] = identical(
                  tester.state(find.byType(ChatScreen)),
                  canonicalState,
                );
                expect(
                  ModalRoute.of(canonicalState.context)!.isCurrent,
                  isTrue,
                );
                _lifecycle(tester, AppLifecycleState.paused);
                await _drain(tester);
                expect(f.ongoing.single['id'], ongoingId);
              }
              if (failure) {
                f.server.failTurn();
              } else {
                f.server.finish('Root final answer');
              }
              await widgetUntil(tester, () => !f.controller.hasActiveTurn);
              await _drain(tester);
              expect(f.nativeRunning, isFalse);
              expect(f.ongoing, isEmpty);
              expect(f.terminals, hasLength(1));
              expect(
                f.terminals.single['title'],
                failure ? 'Hermes turn failed' : 'Hermes response ready',
              );
              expect(jsonDecode(f.terminals.single['payload'] as String), {
                'sessionId': 'stored',
                'connectionId': f.connection.id,
                'turnId': winnerTurn,
              });
              expect(
                f.server.prompts.single['text'],
                AndroidPromptContext.forModel(
                  canonicalActive
                      ? 'Canonical winning prompt'
                      : 'Original root prompt',
                ),
              );
              final prefs = await SharedPreferences.getInstance();
              await prefs.reload();
              expect(
                prefs.getStringList(
                  TurnNotificationService.ongoingIdsStorageKey,
                ),
                isEmpty,
              );
              expect(
                f.pluginCalls.where((c) => c.method == 'cancelAll'),
                isEmpty,
              );
              // Remove the canonical view: the original route and its transferred
              // listener still own the winning result, never an automatic replay.
              _lifecycle(tester, AppLifecycleState.resumed);
              await _drain(tester);
              nav.pop();
              await tester.pump();
              await tester.pump(const Duration(seconds: 1));
              await _drain(tester);
              expect(canonicalState.mounted, isFalse);
              expect(find.byType(ChatScreen), findsOneWidget);
              expect(
                find.byType(ChatScreen, skipOffstage: false),
                findsOneWidget,
              );
              expect(
                sourceSnapshots.last.phase,
                failure
                    ? NormalGatewayTurnPhase.failed
                    : NormalGatewayTurnPhase.completed,
              );
              local.unsubscribe(token);
              if (canonicalActive) {
                expect(
                  await tester.runAsync(
                    () => ComposerDraftStore.read(
                      connectionId: f.connection.id,
                      sessionId: 'stored',
                    ),
                  ),
                  'Canonical next draft',
                );
              }
              expect(f.server.prompts, hasLength(1));
              expect(tester.takeException(), isNull);
            } finally {
              final observed = {
                'focus': verifyFocus,
                'canonicalActive': canonicalActive,
                'failure': failure,
                'routes': routeObservations,
                'keepaliveCommands': f.keepalive,
                'notificationCommands': f.pluginCalls
                    .map((c) => {'method': c.method, 'arguments': c.arguments})
                    .toList(),
                'pushCommands': f.nativeCalls
                    .map((c) => {'method': c.method, 'arguments': c.arguments})
                    .toList(),
                'pushRequestPaths': f.pushRequests
                    .map((r) => r.url.toString())
                    .toList(),
                'wirePrompts': f.server.prompts,
                'mountedChatSessionIds': tester
                    .widgetList<ChatScreen>(
                      find.byType(ChatScreen, skipOffstage: false),
                    )
                    .map((c) => c.session.id)
                    .toList(),
              };
              final observations =
                  Platform.environment['HERMES_ROOT_ALIAS_OBSERVATIONS'];
              if (observations != null) {
                await tester.runAsync(
                  () => File(
                    '$observations/root-alias-fix-observed-$verifyFocus-$canonicalActive-$failure.json',
                  ).writeAsString(jsonEncode(observed)),
                );
              }
              await f.close(tester);
            }
          },
        );
      }
    }
  }
}
