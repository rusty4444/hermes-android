import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_turn_journal_store.dart';

class _HeldList {
  final entered = Completer<void>();
  final release = Completer<void>();
  void complete() {
    if (!release.isCompleted) release.complete();
  }
}

class _NavigationServer {
  _NavigationServer(this.http);
  final HttpServer http;
  final sockets = <WebSocket>[];
  final lists = <_HeldList>[];
  final methods = <String>[];
  List<Map<String, dynamic>> events = [];
  int listRequests = 0;
  int listReplies = 0;
  final listOffsets = <int>[];

  static Future<_NavigationServer> start() async {
    final server = _NavigationServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server.http.listen(server.handle);
    return server;
  }

  _HeldList holdNextList() {
    final held = _HeldList();
    lists.add(held);
    return held;
  }

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/api/ws') {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': 'gateway.ready', 'payload': {}},
        }),
      );
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map;
        final method = frame['method'] as String?;
        if (method == null) return;
        methods.add(method);
        final params = frame['params'] as Map? ?? {};
        final id = params['session_id'];
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': frame['id'],
            'result': method == 'session.resume'
                ? {
                    'session_id': 'runtime-$id',
                    'stored_session_id': id,
                    'running': false,
                    'status': 'idle',
                  }
                : {'ok': true},
          }),
        );
      });
      return;
    }
    if (path.startsWith('/api/sessions')) {
      expect(request.headers.value('authorization'), 'Bearer fixture-key');
    }
    request.response.headers.contentType = ContentType.json;
    if (path == '/api/plugins/mobile-push/events') {
      expect(request.uri.queryParameters['profile'], 'root-profile');
      request.response.write(
        jsonEncode({'events': events, 'has_more': false, 'next_cursor': '1'}),
      );
    } else if (path == '/api/sessions') {
      listRequests++;
      final offset = int.parse(request.uri.queryParameters['offset']!);
      listOffsets.add(offset);
      if (lists.isNotEmpty) {
        final held = lists.removeAt(0);
        held.entered.complete();
        await held.release.future;
      }
      listReplies++;
      request.response.write(
        jsonEncode({
          'data': [
            for (final id in offset == 0 ? ['shared', 'other'] : <String>[])
              {
                'id': id,
                'title': 'Navigation $id',
                'model': 'fixture',
                'source': 'mobile',
                'message_count': 0,
                'started_at': 1,
              },
          ],
          'has_more': false,
        }),
      );
    } else if (path.endsWith('/messages')) {
      request.response.write('{"data":[]}');
    } else if (path == '/api/auth/ws-ticket') {
      request.response.write('{"ticket":"fixture"}');
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  Future<void> close() async {
    for (final held in lists) {
      held.complete();
    }
    for (final socket in sockets) {
      await socket.close();
    }
    await http.close(force: true);
  }
}

class _Credentials implements CredentialStore {
  final entries = <String, String>{};
  @override
  String? readCached(String key) => entries[key];
  @override
  Future<String?> read(String key) async => entries[key];
  @override
  Future<void> write(String key, String value) async => entries[key] = value;
  @override
  Future<void> delete(String key) async => entries.remove(key);
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  for (var i = 0; i < 400; i++) {
    await tester.pump();
    if (predicate()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Navigation boundary did not arrive');
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

class _Root {
  static const nativeChannel = MethodChannel('test/root-navigation-authority');
  static const plugin = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  static const tts = MethodChannel('flutter_tts');
  static const picker = MethodChannel('plugins.flutter.io/image_picker');
  final push = MobilePushService(supported: true, channel: nativeChannel);
  final native = <String, dynamic>{'enabled': false};
  final controller = GatewayTurnApplicationController(
    journalFactory: () => GatewayTurnJournal(store: MemoryTurnJournalStore()),
  );
  late _NavigationServer server;
  late ConnectionManager manager;
  late SavedConnection connection;

  Future<void> mount(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    server = (await tester.runAsync(_NavigationServer.start))!;
    manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: _Credentials(),
    );
    await manager.saveConnection(
      'Loopback',
      '127.0.0.1',
      server.http.port,
      'fixture-key',
      dashboardPort: server.http.port,
      dashboardProxied: true,
      gatewayProfile: 'root-profile',
    );
    connection = manager.getConnections().single;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nativeChannel, (call) async {
      if (call.method == 'preferences') {
        native.addAll(Map<String, dynamic>.from(call.arguments as Map));
      }
      if (call.method == 'takeTap') return native.remove('tap');
      if (call.method == 'disable') {
        native['enabled'] = false;
        native['active'] = false;
        native.remove('tap');
      }
      return Map<String, dynamic>.from(native);
    });
    messenger.setMockMethodCallHandler(tts, (_) async => 1);
    messenger.setMockMethodCallHandler(picker, (_) async => null);
    messenger.setMockMethodCallHandler(
      plugin,
      (call) async =>
          call.method == 'getNotificationAppLaunchDetails' ? null : true,
    );
    messenger.setMockMethodCallHandler(
      ConnectionKeepAliveService.channel,
      (_) async => true,
    );
    await tester.pumpWidget(
      HermesApp(
        connManager: manager,
        turnApplicationController: controller,
        mobilePush: push,
      ),
    );
    await _drain(tester);
    expect(find.byType(ChatScreen, skipOffstage: false), findsNothing);
  }

  void tap([String id = 'shared']) => notificationResponseHandler!(
    NotificationResponse(
      payload: jsonEncode({'connectionId': connection.id, 'sessionId': id}),
      notificationResponseType: NotificationResponseType.selectedNotification,
    ),
  );

  Future<void> pushTap(
    WidgetTester tester, {
    num? expiry,
    int revision = 1,
  }) async {
    expiry ??= DateTime.now().millisecondsSinceEpoch / 1000 + 3600;
    native.addAll({
      'enabled': true,
      'active': true,
      'connection': connection.id,
      'binding': MobilePushService.binding(connection),
      'installation': 'fixture-installation',
      'nonce': 'fixture-nonce',
      'generation': 2,
      'revision': revision,
      'endpoint': 'https://push.invalid/opaque',
      'sessions': ['shared'],
      'tap': {
        'nonce': 'fixture-nonce',
        'generation': 2,
        'revision': revision,
        'event_id': 'event-$revision',
        'expires_at': expiry,
      },
    });
    server.events = [
      {
        'event_id': 'event-$revision',
        'session_id': 'shared',
        'kind': 'input',
        'expires_at': expiry,
      },
    ];
    await tester.runAsync(push.refresh);
  }

  void expectChat(WidgetTester tester, String? id) {
    final finder = find.byType(ChatScreen, skipOffstage: false);
    if (id == null) {
      expect(finder, findsNothing);
    } else {
      expect(finder, findsOneWidget);
      final screen = tester.widget<ChatScreen>(finder);
      expect(screen.session.id, id);
      expect(screen.connection.id, connection.id);
      expect(ModalRoute.of(tester.state(finder).context)!.isCurrent, isTrue);
    }
    expect(server.methods.where((m) => m == 'prompt.submit'), isEmpty);
  }

  Future<void> close(WidgetTester tester) async {
    if (tester.binding.lifecycleState == AppLifecycleState.paused) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await _drain(tester);
    expect(find.byType(HermesApp), findsNothing);
    await controller.close();
    await tester.runAsync(server.close);
    await tester.pump(const Duration(seconds: 16));
    push.dispose();
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in [
      nativeChannel,
      plugin,
      tts,
      picker,
      ConnectionKeepAliveService.channel,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'verbose_mode': false,
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

  for (final replacement in [
    'none',
    'other',
    'before-disable',
    'after-disable',
  ]) {
    testWidgets(
      'ordinary $replacement is independent of held push revocation',
      (tester) async {
        final f = _Root();
        await f.mount(tester);
        final held = f.server.holdNextList();
        try {
          await f.pushTap(tester);
          await _until(tester, () => held.entered.isCompleted);
          expect(f.push.active, isTrue);
          if (replacement == 'before-disable') f.tap();
          await tester.runAsync(f.push.disable);
          expect(f.push.enabled, isFalse);
          if (replacement == 'after-disable') f.tap();
          if (replacement == 'other') f.tap('other');
          held.complete();
          await _until(tester, () => f.server.listReplies > 0);
          for (var i = 0; i < 4; i++) {
            await _drain(tester);
          }
          f.expectChat(
            tester,
            replacement == 'none'
                ? null
                : replacement == 'other'
                ? 'other'
                : 'shared',
          );
        } finally {
          held.complete();
          await f.close(tester);
        }
      },
    );
  }

  for (final ordinary in [false, true]) {
    testWidgets(
      'wall-clock push expiry does not authorise push or discard ordinary=$ordinary',
      (tester) async {
        final f = _Root();
        await f.mount(tester);
        final held = f.server.holdNextList();
        try {
          final expiry = DateTime.now().millisecondsSinceEpoch / 1000 + 0.5;
          await f.pushTap(tester, expiry: expiry);
          await _until(tester, () => held.entered.isCompleted);
          // Flutter pump time is not the production expiry clock.
          await tester.runAsync(() async {
            while (DateTime.now().millisecondsSinceEpoch / 1000 <= expiry) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          if (ordinary) f.tap();
          held.complete();
          await _until(tester, () => f.server.listReplies > 0);
          for (var i = 0; i < 4; i++) {
            await _drain(tester);
          }
          f.expectChat(tester, ordinary ? 'shared' : null);
        } finally {
          held.complete();
          await f.close(tester);
        }
      },
    );
  }

  testWidgets('equivalent ordinary taps share one held lookup and one route', (
    tester,
  ) async {
    final f = _Root();
    await f.mount(tester);
    final held = f.server.holdNextList();
    try {
      f.tap();
      await _until(tester, () => held.entered.isCompleted);
      for (var i = 0; i < 8; i++) {
        f.tap();
        await tester.pump();
      }
      expect(f.server.listRequests, 1);
      held.complete();
      await _until(tester, () => f.server.listReplies == 1);
      await _drain(tester);
      f.expectChat(tester, 'shared');
      expect(f.server.listOffsets, [0, 50]);
    } finally {
      held.complete();
      await f.close(tester);
    }
  });

  testWidgets('old push finalizer cannot clear newer ordinary single-flight', (
    tester,
  ) async {
    final f = _Root();
    await f.mount(tester);
    final old = f.server.holdNextList();
    _HeldList? newer;
    try {
      await f.pushTap(tester);
      await _until(tester, () => old.entered.isCompleted);
      newer = f.server.holdNextList();
      f.tap();
      await _until(tester, () => newer!.entered.isCompleted);
      await tester.runAsync(f.push.disable);
      old.complete();
      await _until(tester, () => f.server.listReplies == 1);
      await _drain(tester);
      for (var i = 0; i < 4; i++) {
        f.tap();
        await tester.pump();
      }
      expect(f.server.listRequests, 2);
      f.expectChat(tester, null);
      newer.complete();
      await _until(tester, () => f.server.listReplies == 2);
      await _drain(tester);
      f.expectChat(tester, 'shared');
    } finally {
      old.complete();
      newer?.complete();
      await f.close(tester);
    }
  });

  for (final boundary in ['other', 'account', 'dispose', 'pause']) {
    testWidgets(
      'replacement ordinary retains latest/account/lifecycle fence at $boundary',
      (tester) async {
        final f = _Root();
        await f.mount(tester);
        final old = f.server.holdNextList();
        _HeldList? ordinary;
        try {
          await f.pushTap(tester);
          await _until(tester, () => old.entered.isCompleted);
          ordinary = f.server.holdNextList();
          f.tap();
          await _until(tester, () => ordinary!.entered.isCompleted);
          await tester.runAsync(f.push.disable);
          if (boundary == 'other') {
            f.tap('other');
          } else if (boundary == 'account') {
            await f.manager.updateConnection(
              f.connection.id,
              'Replaced',
              '127.0.0.1',
              f.server.http.port,
              'replacement-fixture-key',
              dashboardPort: f.server.http.port,
              dashboardProxied: true,
              gatewayProfile: 'root-profile',
            );
          } else if (boundary == 'dispose') {
            await tester.pumpWidget(const SizedBox());
            expect(find.byType(HermesApp), findsNothing);
          } else {
            for (final state in [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
          }
          old.complete();
          ordinary.complete();
          await _until(tester, () => f.server.listReplies >= 2);
          for (var i = 0; i < 4; i++) {
            await _drain(tester);
          }
          f.expectChat(tester, boundary == 'other' ? 'other' : null);
          if (boundary == 'pause') {
            for (final state in [
              AppLifecycleState.hidden,
              AppLifecycleState.inactive,
              AppLifecycleState.resumed,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
            await _until(
              tester,
              () => find.byType(ChatScreen).evaluate().isNotEmpty,
            );
            await _drain(tester);
            f.expectChat(tester, 'shared');
            expect(f.server.listOffsets, [0, 0, 0, 50]);
          }
        } finally {
          old.complete();
          ordinary?.complete();
          await f.close(tester);
        }
      },
    );
  }

  for (final revoke in [false, true]) {
    testWidgets(
      'new push proof supersedes same-chat ordinary without borrowing authority revoke=$revoke',
      (tester) async {
        final f = _Root();
        await f.mount(tester);
        final ordinary = f.server.holdNextList();
        _HeldList? push;
        try {
          f.tap();
          await _until(tester, () => ordinary.entered.isCompleted);
          push = f.server.holdNextList();
          await f.pushTap(tester, revision: 2);
          await _until(tester, () => push!.entered.isCompleted);
          ordinary.complete();
          await _until(tester, () => f.server.listReplies == 1);
          await _drain(tester);
          f.expectChat(tester, null);
          if (revoke) await tester.runAsync(f.push.disable);
          push.complete();
          await _until(tester, () => f.server.listReplies == 2);
          for (var i = 0; i < 4; i++) {
            await _drain(tester);
          }
          f.expectChat(tester, revoke ? null : 'shared');
        } finally {
          ordinary.complete();
          push?.complete();
          await f.close(tester);
        }
      },
    );
  }
}
