// Fresh schedules; reuses prior independent root fixture mechanics.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/widgets/gateway_activity_card.dart';
import 'package:hermes_android/core/widgets/gateway_insight_card.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/android_launch_intent_service.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';

import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart' show BindingServer;
import 'support/memory_turn_journal_store.dart';
import 'support/inert_turn_application_session.dart';
import 'package:hermes_android/core/services/notification_approval_authority.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';

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
  String expectedApiKey = 'fixture';
  Completer<void>? nextMessagesGate;
  Completer<void>? messagesEntered;
  Completer<void>? nextOlderGate;
  Completer<void>? olderEntered;
  final messageOffsets = <int>[];
  final childRequests = <HttpRequest>[];
  bool childFinal = false;
  Completer<void>? nextSessionListGate;
  Completer<void>? sessionListEntered;
  @override
  Future<void> handle(HttpRequest request) async {
    requests.add(request.uri.toString());
    if (request.uri.path.startsWith('/api/sessions/child-root')) {
      childRequests.add(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          request.uri.path.endsWith('/messages')
              ? {
                  'session_id': 'child-root',
                  'profile': 'root-profile',
                  'messages': [
                    {
                      'id': 1,
                      'role': 'assistant',
                      'content': childFinal
                          ? 'Child completed body'
                          : 'Child active body',
                    },
                  ],
                  'pagination': {
                    'limit': 50,
                    'offset': 0,
                    'order': 'latest',
                    'returned': 1,
                  },
                }
              : {
                  'id': 'child-root',
                  'source': 'subagent',
                  'profile': 'root-profile',
                },
        ),
      );
      await request.response.close();
      return;
    }
    if (request.uri.path.endsWith('/messages')) {
      final offset =
          int.tryParse(request.uri.queryParameters['offset'] ?? '0') ?? 0;
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '50') ?? 50;
      messageOffsets.add(offset);
      final end = (rows.length - offset).clamp(0, rows.length);
      final start = (end - limit).clamp(0, end);
      final captured = [
        for (final r in rows.sublist(start, end)) Map<String, dynamic>.from(r),
      ];
      final gate = offset > 0 ? nextOlderGate : nextMessagesGate;
      if (gate != null) {
        if (offset > 0) {
          nextOlderGate = null;
          olderEntered!.complete();
        } else {
          nextMessagesGate = null;
          messagesEntered!.complete();
        }
        await gate.future;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': captured}));
      await request.response.close();
      return;
    }
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
      // Old retained Home discovery and the replacement root lookup can both
      // read here. The original six controls still allow exactly fixture.
      expect(
        request.headers.value('authorization'),
        isIn({'Bearer fixture', 'Bearer $expectedApiKey'}),
      );
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
  _MemoryCredentials({Map<String, String>? physical}) : values = physical ?? {};
  final Map<String, String> values;
  final cache = <String, String>{};
  Completer<void>? writeEntered;
  Completer<void>? writeRelease;
  @override
  String? readCached(String key) => cache[key];
  @override
  Future<String?> read(String key) async {
    final value = values[key];
    if (value == null) {
      cache.remove(key);
    } else {
      cache[key] = value;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    if (writeRelease != null) {
      writeEntered!.complete();
      await writeRelease!.future;
      writeRelease = null;
    }
    values[key] = value;
    cache[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
    cache.remove(key);
  }
}

class _RootAliasFixture {
  final notifications = TurnNotificationService();
  _RootAliasFixture({GatewayTurnApplicationController? controller})
    : injectedController = controller != null,
      controller =
          controller ??
          GatewayTurnApplicationController(
            journalFactory: () =>
                GatewayTurnJournal(store: MemoryTurnJournalStore()),
          );
  final GatewayTurnApplicationController controller;
  final bool injectedController;
  final credentials = _MemoryCredentials();
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
  String? recordedSchedule;
  Completer<Map<String, dynamic>>? snapshotGate;
  Completer<void>? snapshotEntered;
  Completer<void>? eventGate;
  Completer<void>? eventEntered;
  int snapshots = 0;
  Future<void> initialize(WidgetTester tester) async {
    _lifecycle(tester, AppLifecycleState.resumed);
    server = (await tester.runAsync(_RootServer.start))!;
    manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: credentials,
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
          snapshots++;
          final gate = snapshotGate;
          if (gate != null) {
            snapshotGate = null;
            snapshotEntered!.complete();
            return gate.future;
          }
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
          final gate = eventGate;
          if (gate != null) {
            eventGate = null;
            eventEntered!.complete();
            await gate.future;
          }
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
        notifications: notifications,
        mobilePush: push,
        launchIntents: launch,
      ),
    );
    await widgetUntil(
      tester,
      () => find.byType(ChatScreen).evaluate().isNotEmpty,
    );
    if (!injectedController) {
      await widgetUntil(
        tester,
        () => find
            .byKey(const ValueKey('legacy-transport-notice'))
            .evaluate()
            .isNotEmpty,
      );
    }
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
    await tester.pump(const Duration(seconds: 21));
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(find.byType(HermesApp), findsNothing);
    expect(nativeRunning, isFalse);
    expect(ongoing, isEmpty);
    expect(
      prefs.getStringList(TurnNotificationService.ongoingIdsStorageKey) ??
          <String>[],
      isEmpty,
    );
    expect(pluginCalls.where((c) => c.method == 'cancelAll'), isEmpty);
    expect(pendingNotificationApprovals.value, isEmpty);
    if (recordedSchedule != null) {
      await tester.runAsync(
        () => File('review-evidence/cleanup-$recordedSchedule.json')
            .writeAsString(
              jsonEncode({
                'rootUnmounted': true,
                'nativeRunning': nativeRunning,
                'ongoingCount': ongoing.length,
                'durableOngoingIds': prefs.getStringList(
                  TurnNotificationService.ongoingIdsStorageKey,
                ),
                'keepaliveCommands': keepalive,
              }),
            ),
      );
    }
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

class _HeldApprovalSession extends InertTurnApplicationSession {
  final calls = <(String, String, String?)>[];
  Completer<bool>? held;
  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async {
    calls.add((sessionId, choice, requestId));
    return held == null ? false : await held!.future;
  }
}

NotificationResponse _approval(
  SavedConnection c, {
  bool scoped = true,
  String action = 'approve',
  String session = 'stored',
}) => NotificationResponse(
  actionId: action,
  payload: jsonEncode({
    'connectionId': c.id,
    'sessionId': session,
    'requestId': 'approval-reused',
    if (scoped) ...NotificationApprovalAuthority.origin(c),
  }),
  notificationResponseType: NotificationResponseType.selectedNotificationAction,
);

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

Future<String> _startSource(WidgetTester tester, _RootAliasFixture f) async {
  final id = tester.widget<ChatScreen>(find.byType(ChatScreen)).session.id;
  await tester.enterText(_chatComposer(), 'Independent source request');
  await tester.tap(find.byTooltip('Send'));
  await widgetUntil(tester, () => f.server.createEntered.isCompleted);
  return id;
}

Future<void> _cover(WidgetTester tester, State state) async {
  Navigator.of(state.context).push<void>(
    MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Independent retained cover')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await _drain(tester);
  expect(ModalRoute.of(state.context)!.isCurrent, isFalse);
}

Future<void> _record(
  WidgetTester tester,
  _RootAliasFixture f,
  String name,
  Map<String, dynamic> facts,
) async {
  f.recordedSchedule = name;
  final data = {
    'schedule': name,
    ...facts,
    'keepalive': f.keepalive,
    'native': f.nativeCalls
        .map((c) => {'method': c.method, 'arguments': c.arguments})
        .toList(),
    'plugin': f.pluginCalls
        .map((c) => {'method': c.method, 'arguments': c.arguments})
        .toList(),
    'pushURLs': f.pushRequests.map((r) => r.url.toString()).toList(),
    'httpPaths': f.server.requests,
    'wirePrompts': f.server.prompts,
    'mountedIds': tester
        .widgetList<ChatScreen>(find.byType(ChatScreen, skipOffstage: false))
        .map((c) => c.session.id)
        .toList(),
  };
  await tester.runAsync(
    () => File(
      'review-evidence/independent-$name.json',
    ).writeAsString(jsonEncode(data)),
  );
}

Finder _tools() => find.byType(GatewayActivityCard);
bool _toolExpanded(WidgetTester tester) => tester
    .widget<ExpansionTile>(
      find.descendant(of: _tools(), matching: find.byType(ExpansionTile)),
    )
    .controller!
    .isExpanded;
Finder _reason() => find.byWidgetPredicate(
  (w) =>
      w is GatewayReasoningCard &&
      w.text.contains('Independent donor reasoning'),
);
bool _reasonExpanded(WidgetTester tester) => tester
    .widget<ExpansionTile>(
      find.descendant(of: _reason(), matching: find.byType(ExpansionTile)),
    )
    .controller!
    .isExpanded;

Future<void> widgetUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 3000; i++) {
    await tester.pump();
    if (condition()) return;
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  fail('ROOT78 held-future condition did not arrive');
}

List<String> _currentBubbles(WidgetTester tester, State state) {
  final delegate =
      tester.widget<ListView>(find.byType(ListView).first).childrenDelegate
          as SliverChildBuilderDelegate;
  final result = <String>[];
  void visit(Widget w) {
    if (w is MessageBubble) result.add(w.content);
    if (w is KeyedSubtree) visit(w.child);
    if (w is Column) {
      for (final child in w.children) {
        visit(child);
      }
    }
  }

  for (var i = 0; i < delegate.childCount!; i++) {
    final w = delegate.builder(state.context, i);
    if (w != null) visit(w);
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Directory('review-evidence').create(recursive: true);
  });
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'verbose_mode': true,
      BackgroundWorkPrefsStore.storageKey: true,
    });
    backgroundWorkEnabled.value = true;
    notificationPrefs.value = NotificationPrefs.defaults;
    pendingNotificationApprovals.value = const [];
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() {
    HttpOverrides.global = previous;
    debugDefaultTargetPlatformOverride = null;
  });

  for (final width in [400.0, 1000.0]) {
    for (final viaPush in [false, true]) {
      testWidgets(
        'ROOT78-COMBINED retained C/R compact modal held paging alias pins width=$width push=$viaPush',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 1800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final f = _RootAliasFixture();
          final held = Completer<void>();
          final olderHeld = Completer<void>();
          await f.initialize(tester);
          try {
            final localId = await _startSource(tester, f);
            f.server.rows.addAll([
              for (var i = 1; i <= 60; i++)
                {
                  'id': i,
                  'role': i.isOdd ? 'user' : 'assistant',
                  'content': 'Canonical context $i',
                },
            ]);
            await f.canonicalTap(tester, viaPush: viaPush);
            final state = tester.state(find.byType(ChatScreen));
            final route = ModalRoute.of(state.context)!;
            final normal = f.controller.normalSessionFor(f.connection);
            final owner = normal.findChat('stored')!;
            final composer = tester
                .widget<TextField>(_chatComposer())
                .controller!;
            // A physical route latest read captures an old C page and is held.
            f.server.nextMessagesGate = held;
            f.server.messagesEntered = Completer<void>();
            await tester.tap(find.byTooltip('Chat actions'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));
            await tester.tap(find.text('Refresh'));
            await widgetUntil(
              tester,
              () => f.server.messagesEntered!.isCompleted,
            );
            await tester.enterText(
              _chatComposer(),
              'Combined explicit request',
            );
            await tester.tap(find.byTooltip('Send'));
            await widgetUntil(tester, () => f.server.prompts.length == 1);
            f.server.event('message.start', {}, turnId: 'wire-1');
            f.server.event('reasoning.delta', {
              'text': 'Independent donor reasoning',
              'verbose': true,
            }, turnId: 'wire-1');
            f.server.event('tool.start', {
              'tool': 'terminal',
              'detail': 'Received tool detail',
            }, turnId: 'wire-1');
            await widgetUntil(tester, () => owner.snapshot.tools.isNotEmpty);
            // Verbose message metadata and source headings take real sliver
            // space; reveal the received detail through the actual list.
            await tester.scrollUntilVisible(
              _reason(),
              500,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pump(const Duration(milliseconds: 350));
            await widgetUntil(
              tester,
              () =>
                  _reason().evaluate().isNotEmpty &&
                  _tools().evaluate().isNotEmpty,
            );
            expect(_reasonExpanded(tester), false);
            expect(_toolExpanded(tester), false);
            await _drain(tester);
            final innerReasonKey = tester.widget(_reason()).key;
            final reasonState = tester.state(_reason());
            final toolKey = tester.widget(_tools()).key;
            final toolState = tester.state(_tools());
            await tester.ensureVisible(_reason());
            await tester.tap(
              find.descendant(of: _reason(), matching: find.text('Reasoning')),
            );
            await tester.pump(const Duration(milliseconds: 350));
            if (_tools().evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                _tools(),
                200,
                scrollable: find.byType(Scrollable).first,
              );
            }
            await tester.ensureVisible(_tools());
            await tester.tap(find.text('Tool activity'));
            await tester.pump(const Duration(milliseconds: 350));
            await tester.enterText(_chatComposer(), 'Combined retained draft');
            composer.selection = const TextSelection(
              baseOffset: 2,
              extentOffset: 9,
            );
            final selection = composer.selection;
            final goal = List.filled(
              10,
              'Untruncated multiline delegated goal',
            ).join('\n');
            final detail = List.filled(
              12,
              'Complete task progress detail',
            ).join('\n');
            f.server.event('subagent.text', {
              'subagent_id': 'root78-child',
              'child_session_id': 'child-root',
              'goal': goal,
              'model': 'root78-model',
              'status': 'running',
              'text': detail,
            }, turnId: 'wire-1');
            await widgetUntil(
              tester,
              () => find.byType(GatewaySubagentCard).evaluate().isNotEmpty,
            );
            final taskCard = tester.widget<GatewaySubagentCard>(
              find.byType(GatewaySubagentCard),
            );
            expect(taskCard.activities.single.goal, goal);
            final taskSection = find.descendant(
              of: find.byType(GatewaySubagentCard),
              matching: find.byType(ExpansionTile),
            );
            bool taskExpanded() => tester
                .widget<Expansible>(
                  find.descendant(
                    of: taskSection,
                    matching: find.byType(Expansible),
                  ),
                )
                .controller
                .isExpanded;
            expect(taskExpanded(), false);
            await tester.ensureVisible(taskSection);
            await tester.tap(taskSection);
            await tester.pump(const Duration(milliseconds: 350));
            await tester.scrollUntilVisible(
              taskSection,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pump(const Duration(milliseconds: 350));
            expect(taskExpanded(), true);
            final tile = find.byKey(
              const ValueKey('delegated-task-root78-child'),
            );
            await tester.scrollUntilVisible(
              tile,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            final title = tester.widget<Text>(
              find.descendant(
                of: tile,
                matching: find.byWidgetPredicate(
                  (w) => w is Text && w.data == goal,
                ),
              ),
            );
            expect(title.maxLines, 1);
            expect(title.overflow, TextOverflow.ellipsis);
            expect(tester.getSize(tile).height, lessThan(150));
            expect(
              find.descendant(
                of: find.byType(GatewaySubagentCard),
                matching: find.text(detail),
              ),
              findsNothing,
            );
            final scroll = tester
                .widget<ListView>(find.byType(ListView).first)
                .controller!;
            await tester.drag(
              find.byType(ListView).first,
              const Offset(0, 400),
            );
            scroll.jumpTo(120);
            await _drain(tester);
            final before = scroll.position.pixels;
            taskCard.onOpenTask!(taskCard.activities.single);
            await widgetUntil(
              tester,
              () => find.byType(DelegatedTaskTimeline).evaluate().isNotEmpty,
            );
            await tester.pump(const Duration(milliseconds: 400));
            final viewer = tester.widget<DelegatedTaskTimeline>(
              find.byType(DelegatedTaskTimeline),
            );
            final viewerState = tester.state(
              find.byType(DelegatedTaskTimeline),
            );
            await widgetUntil(tester, () => viewer.controller.hasRead);
            expect(viewer.controller.error, isNull);
            expect(viewer.controller.task.detail, detail);
            expect(viewer.controller.task.livePreview, detail);
            final preview = find.byKey(
              const PageStorageKey('task-preview-root78-child'),
            );
            await tester.scrollUntilVisible(
              preview,
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(DelegatedTaskTimeline),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.tap(
              find.descendant(
                of: preview,
                matching: find.text('Live preview from parent events'),
              ),
            );
            await tester.pump(const Duration(milliseconds: 350));
            expect(
              find.descendant(
                of: find.byType(DelegatedTaskTimeline),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is SelectableText && w.data?.contains(detail) == true,
                ),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: find.byType(DelegatedTaskTimeline),
                matching: find.text(detail),
              ),
              findsNothing,
            );
            expect(
              find.descendant(
                of: find.byType(DelegatedTaskTimeline),
                matching: find.byType(TextField),
              ),
              findsNothing,
            );
            expect(
              find.descendant(
                of: find.byType(DelegatedTaskTimeline),
                matching: find.text(goal),
              ),
              findsOneWidget,
            );
            // Alias and live metadata arrive under the SAME actual modal/route.
            f.server.releaseCreate();
            await widgetUntil(
              tester,
              () => identical(
                normal.findChat(localId),
                normal.findChat('stored'),
              ),
            );
            f.server.event('tool.progress', {
              'tool': 'terminal',
              'tool_id': 'root78-late-tool',
              'detail': 'Updated tool detail',
            }, turnId: 'wire-1');
            f.server.event('reasoning.available', {
              'text': 'Independent donor reasoning updated',
              'verbose': true,
            }, turnId: 'wire-1');
            f.server.event('message.delta', {
              'text': 'Received final',
            }, turnId: 'wire-1');
            f.server.childFinal = true;
            f.server.event('subagent.progress', {
              'subagent_id': 'new-child-runtime',
              'child_session_id': 'child-root',
              'status': 'completed',
              'detail': detail,
              'live_preview': detail,
            }, turnId: 'wire-1');
            f.server.finish('Received final');
            await widgetUntil(
              tester,
              () =>
                  !owner.snapshot.hasActiveTurn &&
                  owner.snapshot.historyRows.any(
                    (r) => r['content'] == 'Received final',
                  ),
            );
            await widgetUntil(
              tester,
              () =>
                  viewer.controller.task.isComplete &&
                  viewer.controller.rows.any(
                    (r) => r['content'] == 'Child completed body',
                  ),
            );
            expect(
              tester.state(find.byType(DelegatedTaskTimeline)),
              same(viewerState),
            );
            expect(
              tester
                  .widget<DelegatedTaskTimeline>(
                    find.byType(DelegatedTaskTimeline),
                  )
                  .controller,
              same(viewer.controller),
            );
            expect(scroll.position.pixels, before);
            expect(composer.text, 'Combined retained draft');
            expect(composer.selection, selection);
            expect(
              f.server.childRequests.every((r) => r.method == 'GET'),
              true,
            );
            expect(
              f.server.childRequests
                  .where((r) => r.uri.path.endsWith('/messages'))
                  .every(
                    (r) => r.uri.queryParameters['include_compacted'] == 'true',
                  ),
              true,
            );
            held.complete();
            await _drain(tester);
            expect(
              owner.snapshot.historyRows.any(
                (r) => r['content'] == 'Received final',
              ),
              true,
            );
            expect(scroll.position.pixels, before);
            await tester.tap(find.widgetWithText(TextButton, 'Close'));
            await tester.pump(const Duration(milliseconds: 400));
            await _drain(tester);
            expect(tester.state(find.byType(ChatScreen)), same(state));
            expect(ModalRoute.of(state.context), same(route));
            expect(
              tester.widget<TextField>(_chatComposer()).controller,
              same(composer),
            );
            expect(composer.selection, selection);
            // Real older paging retains physical coverage, including the two
            // newly accepted settlement rows; it is not a count of R cells.
            scroll.jumpTo(0);
            await _drain(tester);
            debugPrint(
              'ROOT78-PAGING ${jsonEncode({'offsets': f.server.messageOffsets, 'pixels': scroll.position.pixels, 'ownerRows': owner.snapshot.historyRows.length, 'firstChild': ((tester.widget<ListView>(find.byType(ListView).first).childrenDelegate as SliverChildBuilderDelegate).builder(state.context, 0)).toString(), 'textButtons': tester.widgetList<TextButton>(find.byType(TextButton)).map((b) => b.child.toString()).toList()})}',
            );
            expect(find.byKey(const Key('chat-load-older')), findsOneWidget);
            f.server.nextOlderGate = olderHeld;
            f.server.olderEntered = Completer<void>();
            await tester.tap(find.byKey(const Key('chat-load-older')));
            await widgetUntil(tester, () => f.server.olderEntered!.isCompleted);
            expect(f.server.messageOffsets.where((o) => o > 0).toList(), [52]);
            // A controlled newer accepted physical Refresh fences the held older
            // page; its obsolete completion cannot advance the retry cursor.
            f.server.rows[59]['content'] = 'Canonical context 60 refreshed';
            await tester.tap(find.byTooltip('Chat actions'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 350));
            await tester.tap(find.text('Refresh'));
            await widgetUntil(
              tester,
              () => _currentBubbles(
                tester,
                state,
              ).contains('Canonical context 60 refreshed'),
            );
            olderHeld.complete();
            await widgetUntil(
              tester,
              () =>
                  tester
                      .widget<TextButton>(
                        find.byKey(const Key('chat-load-older')),
                      )
                      .onPressed !=
                  null,
            );
            expect(
              _currentBubbles(tester, state).first,
              'Canonical context 11',
            );
            await tester.tap(find.byKey(const Key('chat-load-older')));
            await widgetUntil(
              tester,
              () =>
                  _currentBubbles(tester, state).first == 'Canonical context 1',
            );
            expect(f.server.messageOffsets.where((o) => o > 0).toList(), [
              52,
              52,
            ]);
            final received = owner.snapshot.displayRows.where(
              (r) =>
                  r['role'] == 'assistant' && r['content'] == 'Received final',
            );
            expect(received.length, 1);
            expect(
              owner.snapshot.historyRows
                  .where((r) => r['content'] == 'Received final')
                  .length,
              1,
            );
            // Reveal through real sliver; inspect both sources without conflating them.
            await tester.scrollUntilVisible(
              _reason(),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            expect(_reasonExpanded(tester), true);
            expect(tester.widget(_reason()).key, innerReasonKey);
            // Removing the notice changes lazy viewport/cache boundaries. Reveal
            // the tool cell explicitly rather than assuming it is built with
            // the preceding reasoning card.
            await tester.scrollUntilVisible(
              _tools(),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            expect(_toolExpanded(tester), true);
            expect(tester.widget(_tools()).key, toolKey);
            // Prior lazy eviction may remount cards; unchanged no-eviction controller is
            // tested below across cover, rather than claiming an evicted State survives.
            final retainedReasonState = tester.state(_reason());
            final retainedToolState = tester.state(_tools());
            await _cover(tester, state);
            f.tap('stored');
            await widgetUntil(tester, () => route.isCurrent);
            await _drain(tester);
            expect(tester.state(find.byType(ChatScreen)), same(state));
            expect(tester.state(_reason()), same(retainedReasonState));
            expect(tester.state(_tools()), same(retainedToolState));
            expect(_reasonExpanded(tester), true);
            expect(_toolExpanded(tester), true);
            expect(composer.text, 'Combined retained draft');
            expect(composer.selection, selection);
            // Count every lazy source cell by building through the existing delegate.
            final list = tester.widget<ListView>(find.byType(ListView).first);
            final delegate =
                list.childrenDelegate as SliverChildBuilderDelegate;
            final built = [
              for (var i = 0; i < delegate.childCount!; i++)
                delegate.builder(state.context, i),
            ];
            int tasks = 0;
            final bubbles = <String>[];
            void visit(Widget w) {
              if (w is GatewaySubagentCard) tasks++;
              if (w is MessageBubble) bubbles.add(w.content);
              if (w is KeyedSubtree) visit(w.child);
              if (w is Column) {
                for (final c in w.children) {
                  visit(c);
                }
              }
            }

            for (final w in built.whereType<Widget>()) {
              visit(w);
            }
            expect(tasks, 1);
            expect(
              bubbles,
              [
                for (var id = 1; id < 60; id++) 'Canonical context $id',
                'Canonical context 60 refreshed',
                'Combined explicit request',
                'Received final',
                'Combined explicit request',
                'Received final',
              ],
              reason:
                  'Every loaded/paged C row in saved order, then R once; never guessed cross-source dedup or interleave',
            );
            expect(bubbles.where((s) => s == 'Received final').length, 2);
            expect(delegate.findChildIndexCallback, isNotNull);
            expect(f.server.prompts, hasLength(1));
            expect(
              f.server.prompts.single['text'],
              AndroidPromptContext.forModel('Combined explicit request'),
            );
            expect(
              f.server.prompts.single.keys.any(
                (k) => k.contains('source') || k.contains('projection'),
              ),
              false,
            );
            // True disposal resets BOTH manual choices while retaining the body/draft.
            debugPrint(
              'ROOT78-DISPOSE before ${jsonEncode({'current': route.isCurrent, 'internalPop': route.willHandlePopInternally})}',
            );
            Navigator.of(state.context).pop();
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            await _drain(tester);
            debugPrint(
              'ROOT78-DISPOSE after ${jsonEncode({'mounted': state.mounted, 'current': route.isCurrent, 'internalPop': route.willHandlePopInternally, 'chats': find.byType(ChatScreen, skipOffstage: false).evaluate().length})}',
            );
            expect(state.mounted, false);
            f.tap('stored');
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
            await tester.scrollUntilVisible(
              _reason(),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            expect(_reasonExpanded(tester), false);
            expect(tester.widget(_reason()).key, innerReasonKey);
            if (_tools().evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                _tools(),
                200,
                scrollable: find.byType(Scrollable).first,
              );
            }
            expect(_toolExpanded(tester), false);
            expect(
              tester.widget<TextField>(_chatComposer()).controller!.text,
              'Combined retained draft',
            );
            expect(f.server.prompts, hasLength(1));
            expect(tester.takeException(), isNull);
            await _record(tester, f, 'ROOT78-combined-$width-$viaPush', {
              'sameRetainedRoute': true,
              'scrollBefore': before,
              'scrollAfterModal': before,
              'taskAuxiliaryCount': tasks,
              'renderedCanonicalAndReceivedFinals': 2,
              'physicalOlderOffsets': f.server.messageOffsets
                  .where((o) => o > 0)
                  .toList(),
              'initialReasonStateIdentity': identityHashCode(reasonState),
              'initialToolStateIdentity': identityHashCode(toolState),
              'reasonKey': innerReasonKey.toString(),
            });
          } finally {
            if (!held.isCompleted) held.complete();
            if (!olderHeld.isCompleted) olderHeld.complete();
            await f.close(tester);
          }
        },
      );
    }
  }

  for (final oldGrant in [false, true]) {
    testWidgets(
      'ROOT78-AUTH resume demands trailing permission with retained live UI old=$oldGrant',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = _RootAliasFixture();
        await f.initialize(tester);
        final held = Completer<bool>();
        try {
          await _startSource(tester, f);
          f.server.releaseCreate();
          await widgetUntil(tester, () => f.server.prompts.length == 1);
          f.server.event('reasoning.delta', {
            'text': 'Independent donor reasoning',
            'verbose': true,
          }, turnId: 'wire-1');
          await widgetUntil(tester, () => _reason().evaluate().isNotEmpty);
          await tester.tap(
            find.descendant(of: _reason(), matching: find.text('Reasoning')),
          );
          await tester.pump(const Duration(milliseconds: 350));
          final state = tester.state(find.byType(ChatScreen));
          final innerKey = tester.widget(_reason()).key;
          final entered = Completer<void>();
          var checks = 0;
          var grant = oldGrant;
          var prompts = 0;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _RootAliasFixture.plugin,
            (call) async {
              f.pluginCalls.add(call);
              if (call.method == 'areNotificationsEnabled') {
                checks++;
                if (checks == 1) {
                  entered.complete();
                  return held.future;
                }
                return grant;
              }
              if (call.method == 'requestNotificationsPermission') prompts++;
              if (call.method == 'cancel') {
                f.live.remove((call.arguments as Map)['id']);
              }
              if (call.method == 'show') {
                final a = Map<String, dynamic>.from(call.arguments as Map);
                f.live[a['id'] as int] = a;
              }
              return call.method == 'getNotificationAppLaunchDetails'
                  ? null
                  : true;
            },
          );
          final read = f.notifications.refreshAuthorization();
          await widgetUntil(tester, () => entered.isCompleted);
          _lifecycle(tester, AppLifecycleState.paused);
          await _drain(tester);
          grant = !oldGrant;
          _lifecycle(tester, AppLifecycleState.resumed);
          await _drain(tester);
          held.complete(oldGrant);
          await tester.runAsync(() => read);
          await widgetUntil(
            tester,
            () => checks >= 2 && f.notifications.permissionGranted == !oldGrant,
          );
          expect(prompts, 0);
          expect(tester.state(find.byType(ChatScreen)), same(state));
          expect(tester.widget(_reason()).key, innerKey);
          expect(_reasonExpanded(tester), true);
          _lifecycle(tester, AppLifecycleState.paused);
          await _drain(tester);
          expect(f.ongoing.isNotEmpty, !oldGrant);
          f.server.finish('Authority final');
          await widgetUntil(tester, () => !f.controller.hasActiveTurn);
          await _drain(tester);
          expect(f.ongoing, isEmpty);
          expect(f.nativeRunning, false);
          expect(f.server.prompts, hasLength(1));
          expect(tester.takeException(), isNull);
          await _record(tester, f, 'ROOT78-auth-$oldGrant', {
            'oldPermission': oldGrant,
            'newPermission': !oldGrant,
            'physicalChecks': checks,
            'repeatPrompts': prompts,
            'sameViewManualReasoning': true,
          });
        } finally {
          if (!held.isCompleted) held.complete(oldGrant);
          await f.close(tester);
        }
      },
    );
  }
  testWidgets(
    'AUTHORITY real root scoped wire approval and stale raw deferral never answer replacement profile',
    (tester) async {
      final f = _RootAliasFixture();
      await f.initialize(tester);
      final frames = <({WebSocket socket, Map frame})>[];
      f.server.observeClientFrame = (socket, frame) =>
          frames.add((socket: socket, frame: frame));
      try {
        f.server.creates = 1;
        Future<
          ({
            NormalGatewayApplicationSession normal,
            NormalGatewayChatOwner chat,
            WebSocket socket,
          })
        >
        bind(SavedConnection c) async {
          final normal = f.controller.normalSessionFor(c);
          await normal.ready;
          final chat = normal.chatFor(
            'wire-local',
            storedSessionId: 'stored',
            title: 'Wire',
          );
          var bound = false;
          Object? failure;
          final connecting = normal.client!.ensureSession('wire-local');
          unawaited(
            connecting.then<void>(
              (_) {
                bound = true;
              },
              onError: (Object error, StackTrace stack) {
                failure = error;
                bound = true;
              },
            ),
          );
          await widgetUntil(tester, () => bound);
          expect(failure, isNull);
          await connecting;
          return (
            normal: normal,
            chat: chat,
            socket: frames
                .lastWhere((e) => e.frame['method'] == 'session.resume')
                .socket,
          );
        }

        void request(WebSocket socket) => socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 'approval-reused',
            'method': 'approval',
            'params': {
              'session_id': 'runtime',
              'command': 'fixture',
              'description': 'Fixture action',
            },
          }),
        );
        NotificationResponse response(
          SavedConnection c,
          String id,
          String choice,
        ) => NotificationResponse(
          actionId: choice,
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          payload: jsonEncode({
            'connectionId': c.id,
            'sessionId': 'stored',
            'requestId': id,
            ...NotificationApprovalAuthority.origin(c),
          }),
        );
        final old = await bind(f.connection);
        request(old.socket);
        await widgetUntil(
          tester,
          () => old.chat.snapshot.pendingInput.isNotEmpty,
        );
        final firstId =
            old.chat.snapshot.pendingInput.single.data['server_request_id']
                as String;
        // Simulated cold-origin stamp; exact current backend request and fresh
        // account authority are still required (not physical process-death proof).
        final coldPayload =
            jsonDecode(response(f.connection, firstId, 'approve').payload!)
                as Map<String, dynamic>;
        coldPayload['approvalMutation'] =
            '00000000-0000-4000-8000-000000000000:initial';
        notificationResponseHandler!(
          NotificationResponse(
            actionId: 'approve',
            payload: jsonEncode(coldPayload),
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        await widgetUntil(
          tester,
          () => frames.any(
            (e) =>
                e.frame['id'] == 'approval-reused' &&
                e.frame.containsKey('result'),
          ),
        );
        expect(
          frames
              .where((e) => e.frame['id'] == 'approval-reused')
              .single
              .frame['result'],
          {'choice': 'once'},
        );
        request(old.socket);
        await widgetUntil(
          tester,
          () => old.chat.snapshot.pendingInput.isNotEmpty,
        );
        final secondId =
            old.chat.snapshot.pendingInput.single.data['server_request_id']
                as String;
        expect(secondId, isNot(firstId));
        final rawOldAction = response(f.connection, secondId, 'approve');
        _lifecycle(tester, AppLifecycleState.paused);
        await _drain(tester);
        notificationResponseHandler!(rawOldAction);
        await f.manager.updateConnection(
          f.connection.id,
          f.connection.label,
          f.connection.host,
          f.connection.port,
          f.connection.apiKey,
          dashboardPort: f.connection.dashboardPort,
          dashboardProxied: true,
          gatewayProfile: 'replacement-profile',
        );
        final current = f.manager.getConnections().single;
        final replacement = await bind(current);
        expect(replacement.normal, isNot(same(old.normal)));
        request(replacement.socket);
        await widgetUntil(
          tester,
          () => replacement.chat.snapshot.pendingInput.isNotEmpty,
        );
        final newId =
            replacement
                    .chat
                    .snapshot
                    .pendingInput
                    .single
                    .data['server_request_id']
                as String;
        _lifecycle(tester, AppLifecycleState.resumed);
        await _drain(tester);
        final newResponses = frames.where(
          (e) =>
              identical(e.socket, replacement.socket) &&
              e.frame['id'] == 'approval-reused',
        );
        final revokedResponseCount = newResponses.length;
        expect(
          newResponses,
          isEmpty,
          reason: 'Old captured action must never answer on replacement socket',
        );
        expect(pendingNotificationApprovals.value, isEmpty);
        notificationResponseHandler!(response(current, newId, 'reject'));
        await widgetUntil(
          tester,
          () => frames.any(
            (e) =>
                identical(e.socket, replacement.socket) &&
                e.frame['id'] == 'approval-reused',
          ),
        );
        expect(
          frames
              .where(
                (e) =>
                    identical(e.socket, replacement.socket) &&
                    e.frame['id'] == 'approval-reused',
              )
              .single
              .frame['result'],
          {'choice': 'deny'},
        );
        expect(f.server.prompts, isEmpty);
        await _record(tester, f, 'AUTHORITY-wire', {
          'replacementResponsesBeforeFreshAction': revokedResponseCount,
          'replacementResponsesAfterFreshAction': frames
              .where(
                (e) =>
                    identical(e.socket, replacement.socket) &&
                    e.frame['id'] == 'approval-reused',
              )
              .length,
          'replacementChoice': frames
              .where(
                (e) =>
                    identical(e.socket, replacement.socket) &&
                    e.frame['id'] == 'approval-reused',
              )
              .single
              .frame['result'],
          'oldOwnerReplaced': !identical(replacement.normal, old.normal),
          'wirePrompts': f.server.prompts.length,
        });
        expect(tester.takeException(), isNull);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final mutation in ['credential', 'profile', 'aba', 'remove-recreate']) {
    testWidgets(
      'AUTHORITY raw background deferral is captured before real $mutation mutation',
      (tester) async {
        final sessions = <_HeldApprovalSession>[];
        final controller = GatewayTurnApplicationController(
          sessionFactory: (_) {
            final s = _HeldApprovalSession();
            sessions.add(s);
            return s;
          },
        );
        final f = _RootAliasFixture(controller: controller);
        await f.initialize(tester);
        try {
          final old = f.connection;
          final response = _approval(old);
          _lifecycle(tester, AppLifecycleState.paused);
          await _drain(tester);
          notificationResponseHandler!(response);
          if (mutation == 'profile') {
            await f.manager.updateConnection(
              old.id,
              old.label,
              old.host,
              old.port,
              old.apiKey,
              dashboardPort: old.dashboardPort,
              dashboardProxied: true,
              gatewayProfile: 'replacement-profile',
            );
          } else if (mutation == 'remove-recreate') {
            await f.manager.deleteConnection(old.id);
            await f.manager.importConnections([old], replaceExisting: false);
          } else {
            await f.manager.updateApiKey(old.id, 'replacement-fixture');
            if (mutation == 'aba') {
              await f.manager.updateApiKey(old.id, old.apiKey);
            }
          }
          _lifecycle(tester, AppLifecycleState.resumed);
          await _drain(tester);
          expect(pendingNotificationApprovals.value, isEmpty);
          expect(sessions.expand((s) => s.calls), isEmpty);
          final current = f.manager.getConnections().single;
          f.server.expectedApiKey = current.apiKey;
          notificationResponseHandler!(_approval(current, action: 'reject'));
          await widgetUntil(
            tester,
            () => pendingNotificationApprovals.value.isNotEmpty,
          );
          expect(pendingNotificationApprovals.value.single.choice, 'deny');
          expect(
            pendingNotificationApprovals.value.single.authority!.isCurrentFor(
              current,
            ),
            true,
          );
          expect(sessions.expand((s) => s.calls).single.$2, 'deny');
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  for (final mutate in [false, true]) {
    testWidgets(
      'AUTHORITY multiple deferred sessions and unrelated account survive targeted revocation=$mutate',
      (tester) async {
        final f = _RootAliasFixture();
        await f.initialize(tester);
        try {
          await f.manager.saveConnection(
            'Sibling',
            f.connection.host,
            f.connection.port,
            'fixture',
            dashboardPort: f.connection.dashboardPort,
            dashboardProxied: true,
            gatewayProfile: 'sibling-profile',
          );
          final sibling = f.manager.getConnections().singleWhere(
            (c) => c.id != f.connection.id,
          );
          _lifecycle(tester, AppLifecycleState.paused);
          await _drain(tester);
          notificationResponseHandler!(_approval(f.connection, session: 'one'));
          notificationResponseHandler!(_approval(f.connection, session: 'two'));
          notificationResponseHandler!(_approval(sibling));
          if (mutate) {
            await f.manager.updateConnection(
              f.connection.id,
              f.connection.label,
              f.connection.host,
              f.connection.port,
              f.connection.apiKey,
              dashboardPort: f.connection.dashboardPort,
              dashboardProxied: true,
              gatewayProfile: 'replacement-profile',
            );
          }
          _lifecycle(tester, AppLifecycleState.resumed);
          await widgetUntil(
            tester,
            () => pendingNotificationApprovals.value.length == (mutate ? 1 : 3),
          );
          expect(
            pendingNotificationApprovals.value.where(
              (a) => a.connectionId == sibling.id,
            ),
            hasLength(1),
          );
          if (!mutate) {
            expect(
              pendingNotificationApprovals.value
                  .where((a) => a.connectionId == f.connection.id)
                  .map((a) => a.sessionId)
                  .toSet(),
              {'one', 'two'},
            );
          }
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'AUTHORITY cold origin cannot borrow a different real managers stale credential cache',
    (tester) async {
      final session = _HeldApprovalSession();
      final f = _RootAliasFixture(
        controller: GatewayTurnApplicationController(
          sessionFactory: (_) => session,
        ),
      );
      await f.initialize(tester);
      try {
        final old = f.connection;
        final other = await ConnectionManager.create(
          f.manager.prefs,
          credentialStore: _MemoryCredentials(physical: f.credentials.values),
        );
        await other.updateApiKey(old.id, 'replacement-fixture');
        expect(
          f.manager.getConnections().single.apiKey,
          'fixture',
          reason: 'Root cache really is stale before physical authority read',
        );
        notificationResponseHandler!(
          NotificationResponse(
            actionId: 'approve',
            payload: jsonEncode({
              'connectionId': old.id,
              'sessionId': 'stored',
              'requestId': 'approval-reused',
              'approvalAccount': MobilePushService.binding(old),
              'approvalMutation':
                  '00000000-0000-4000-8000-000000000000:initial',
            }),
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
          ),
        );
        await widgetUntil(
          tester,
          () =>
              f.manager.getConnections().single.apiKey == 'replacement-fixture',
        );
        await _drain(tester);
        expect(session.calls, isEmpty);
        expect(pendingNotificationApprovals.value, isEmpty);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'AUTHORITY pending secure write revokes queue and denies gestures before commit',
    (tester) async {
      final f = _RootAliasFixture();
      await f.initialize(tester);
      final held = Completer<void>();
      Future<void>? mutation;
      try {
        notificationResponseHandler!(_approval(f.connection));
        await widgetUntil(
          tester,
          () => pendingNotificationApprovals.value.isNotEmpty,
        );
        final old = pendingNotificationApprovals.value.single;
        f.credentials.writeEntered = Completer<void>();
        f.credentials.writeRelease = held;
        mutation = f.manager.updateApiKey(
          f.connection.id,
          'replacement-fixture',
        );
        await widgetUntil(
          tester,
          () => f.credentials.writeEntered!.isCompleted,
        );
        expect(pendingNotificationApprovals.value, isEmpty);
        notificationResponseHandler!(_approval(f.connection));
        await _drain(tester);
        expect(pendingNotificationApprovals.value, isEmpty);
        held.complete();
        await mutation;
        expect(old.authority!.isCurrent, false);
        final current = f.manager.getConnections().single;
        f.server.expectedApiKey = current.apiKey;
        notificationResponseHandler!(_approval(current));
        await widgetUntil(
          tester,
          () => pendingNotificationApprovals.value.isNotEmpty,
        );
        expect(pendingNotificationApprovals.value.single, isNot(same(old)));
      } finally {
        if (!held.isCompleted) held.complete();
        await mutation;
        await f.close(tester);
      }
    },
  );

  for (final late in ['success', 'false', 'throw']) {
    testWidgets(
      'AUTHORITY held old direct $late cannot borrow new owner or clean fresh same IDs',
      (tester) async {
        final sessions = <_HeldApprovalSession>[];
        final held = Completer<bool>();
        final controller = GatewayTurnApplicationController(
          sessionFactory: (_) {
            final s = _HeldApprovalSession();
            sessions.add(s);
            return s;
          },
        );
        final f = _RootAliasFixture(controller: controller);
        await f.initialize(tester);
        try {
          final oldSession =
              controller.sessionFor(f.connection) as _HeldApprovalSession;
          oldSession.held = held;
          notificationResponseHandler!(_approval(f.connection));
          await widgetUntil(tester, () => oldSession.calls.isNotEmpty);
          notificationResponseHandler!(_approval(f.connection));
          await _drain(tester);
          expect(oldSession.calls, hasLength(1));
          await f.manager.updateApiKey(f.connection.id, 'replacement-fixture');
          final current = f.manager.getConnections().single;
          f.server.expectedApiKey = current.apiKey;
          notificationResponseHandler!(_approval(current, action: 'reject'));
          await widgetUntil(
            tester,
            () => pendingNotificationApprovals.value.isNotEmpty,
          );
          final fresh = pendingNotificationApprovals.value.single;
          if (late == 'throw') {
            held.completeError(StateError('Fixture failure'));
          } else {
            held.complete(late == 'success');
          }
          await _drain(tester);
          expect(pendingNotificationApprovals.value.single, same(fresh));
          expect(oldSession.calls, hasLength(1));
          expect(
            sessions
                .where((s) => !identical(s, oldSession))
                .expand((s) => s.calls)
                .single
                .$2,
            'deny',
          );
        } finally {
          if (!held.isCompleted) held.complete(false);
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'AUTHORITY same-root real manager replacement cannot lend old in-flight authority to a fresh same-ID action',
    (tester) async {
      final session = _HeldApprovalSession();
      final held = Completer<bool>();
      final f = _RootAliasFixture(
        controller: GatewayTurnApplicationController(
          sessionFactory: (_) => session,
        ),
      );
      await f.initialize(tester);
      try {
        final rootState = tester.state(find.byType(HermesApp));
        session.held = held;
        notificationResponseHandler!(_approval(f.connection));
        await widgetUntil(tester, () => session.calls.length == 1);
        final replacementManager = ConnectionManager(
          f.manager.prefs,
          credentialStore: f.credentials,
        );
        await tester.pumpWidget(
          HermesApp(
            connManager: replacementManager,
            turnApplicationController: f.controller,
            notifications: f.notifications,
            mobilePush: f.push,
            launchIntents: f.launch,
          ),
        );
        expect(tester.state(find.byType(HermesApp)), same(rootState));
        session.held = null;
        notificationResponseHandler!(_approval(f.connection, action: 'reject'));
        await widgetUntil(
          tester,
          () => pendingNotificationApprovals.value.isNotEmpty,
        );
        final fresh = pendingNotificationApprovals.value.single;
        held.complete(false);
        await _drain(tester);
        expect(pendingNotificationApprovals.value.single, same(fresh));
        expect(session.calls.map((c) => c.$2), ['once', 'deny']);
      } finally {
        if (!held.isCompleted) held.complete(false);
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'AUTHORITY root disposal revokes a held direct answer before late unresolved completion',
    (tester) async {
      final session = _HeldApprovalSession();
      final held = Completer<bool>();
      final f = _RootAliasFixture(
        controller: GatewayTurnApplicationController(
          sessionFactory: (_) => session,
        ),
      );
      var closed = false;
      await f.initialize(tester);
      try {
        session.held = held;
        notificationResponseHandler!(_approval(f.connection));
        await widgetUntil(tester, () => session.calls.isNotEmpty);
        await f.close(tester);
        closed = true;
        held.complete(false);
        await _drain(tester);
        expect(pendingNotificationApprovals.value, isEmpty);
        expect(session.calls, hasLength(1));
      } finally {
        if (!held.isCompleted) held.complete(false);
        if (!closed) await f.close(tester);
      }
    },
  );

  testWidgets(
    'AUTHORITY legacy action fails closed while legacy ordinary body navigation works',
    (tester) async {
      final session = _HeldApprovalSession();
      final f = _RootAliasFixture(
        controller: GatewayTurnApplicationController(
          sessionFactory: (_) => session,
        ),
      );
      await f.initialize(tester);
      try {
        notificationResponseHandler!(_approval(f.connection, scoped: false));
        await _drain(tester);
        expect(session.calls, isEmpty);
        expect(pendingNotificationApprovals.value, isEmpty);
        f.server.creates = 1;
        notificationResponseHandler!(
          NotificationResponse(
            payload: jsonEncode({'sessionId': 'stored'}),
            notificationResponseType:
                NotificationResponseType.selectedNotification,
          ),
        );
        await widgetUntil(
          tester,
          () => tester
              .widgetList<ChatScreen>(find.byType(ChatScreen))
              .any((w) => w.session.id == 'stored'),
        );
        expect(session.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final replacement in ['credential', 'profile']) {
    testWidgets(
      'ROOT78-STALE-ACTION queued approval loses authority on same-ID $replacement replacement',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final f = _RootAliasFixture();
        await f.initialize(tester);
        try {
          final oldConnection = f.connection;
          final oldOwner = f.controller.normalSessionFor(oldConnection);
          notificationResponseHandler!(
            NotificationResponse(
              actionId: 'approve',
              payload: jsonEncode({
                'connectionId': oldConnection.id,
                'sessionId': 'stored',
                'requestId': 'approval-reused',
                // A: scoped local-notification origin; same action/mutation/resume oracle.
                'approvalAccount': MobilePushService.binding(oldConnection),
                'approvalMutation':
                    '00000000-0000-4000-8000-000000000000:initial',
              }),
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
            ),
          );
          await widgetUntil(
            tester,
            () => pendingNotificationApprovals.value.length == 1,
          );
          final oldAction = pendingNotificationApprovals.value.single;
          expect(oldAction.choice, 'once');
          expect(oldAction.connectionId, oldConnection.id);
          expect(oldAction.sessionId, 'stored');
          _lifecycle(tester, AppLifecycleState.paused);
          await _drain(tester);
          if (replacement == 'credential') {
            await f.manager.updateApiKey(
              oldConnection.id,
              'replacement-fixture',
            );
          } else {
            await f.manager.updateConnection(
              oldConnection.id,
              oldConnection.label,
              oldConnection.host,
              oldConnection.port,
              oldConnection.apiKey,
              dashboardPort: oldConnection.dashboardPort,
              dashboardProxied: true,
              gatewayProfile: 'replacement-profile',
            );
          }
          final changed = f.manager.getConnections().single;
          expect(changed.id, oldConnection.id);
          expect(
            MobilePushService.binding(changed),
            isNot(MobilePushService.binding(oldConnection)),
          );
          _lifecycle(tester, AppLifecycleState.resumed);
          await _drain(tester);
          final currentOwner = f.controller.normalSessionFor(changed);
          expect(currentOwner, isNot(same(oldOwner)));
          await tester.runAsync(() => currentOwner.ready);
          await _drain(tester);
          final retained = pendingNotificationApprovals.value;
          await _record(tester, f, 'ROOT78-stale-action-$replacement', {
            'bindingChanged': true,
            'oldOwnerReplaced': true,
            'sameSavedId': true,
            'pendingActions': retained
                .map(
                  (a) => {
                    'connectionId': a.connectionId,
                    'sessionId': a.sessionId,
                    'requestId': a.requestId,
                    'choice': a.choice,
                  },
                )
                .toList(),
            'sameOldActionObjectRetained': retained.any(
              (a) => identical(a, oldAction),
            ),
          });
          expect(
            retained,
            isEmpty,
            reason:
                'Replacing the saved account/profile must revoke the old account queued approval intent, not lend it to a same-ID replacement',
          );
        } finally {
          await f.close(tester);
        }
      },
    );
  }
}
