import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/screens/workspace_screen.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/recording_turn_notification_sink.dart';

class _FailedReloadStore extends InMemorySharedPreferencesStore {
  _FailedReloadStore() : super.empty();
  @override
  Future<Map<String, Object>> getAll() async =>
      throw StateError('Held policy store unavailable');
}

class _Secrets implements CredentialStore {
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

class _HeldRoutePush extends MobilePushService {
  _HeldRoutePush(this.delegate) : super(supported: false);
  final MobilePushService delegate;
  final route = Completer<MobilePushRoute?>();
  int takes = 0;
  @override
  Future<MobilePushRoute?> takePendingNotificationRoute() {
    return ++takes == 1 ? route.future : Future.value();
  }

  @override
  Future<bool> isRouteCurrent(MobilePushRoute route) =>
      delegate.isRouteCurrent(route);
}

class _HeldReloadAndWriteStore extends InMemorySharedPreferencesStore {
  _HeldReloadAndWriteStore(this.reloadValues) : super.withData(reloadValues);
  final Map<String, Object> reloadValues;
  final reloadGate = Completer<void>();
  final writeGate = Completer<bool>();
  int reads = 0;
  int policyWrites = 0;
  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    await reloadGate.future;
    return reloadValues;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key == 'flutter.${BackgroundWorkPrefsStore.storageKey}') {
      policyWrites++;
      return writeGate.future;
    }
    return super.setValue(valueType, key, value);
  }
}

class _HeldPolicyWritesStore extends InMemorySharedPreferencesStore {
  _HeldPolicyWritesStore(super.data) : super.withData();

  final writes = <Completer<bool>>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.${BackgroundWorkPrefsStore.storageKey}') {
      final gate = Completer<bool>();
      writes.add(gate);
      if (!await gate.future) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

class _HeldSink extends RecordingTurnNotificationSink {
  String? failOngoingLocal;
  @override
  Future<void> show(TurnNotification notification) async {
    if (notification.ongoing &&
        (jsonDecode(notification.payload) as Map)['localSessionId'] ==
            failOngoingLocal) {
      throw PlatformException(code: 'notification_unavailable');
    }
    await super.show(notification);
  }

  Completer<void>? initialization;
  Completer<void>? permissionCheck;
  int checks = 0;
  @override
  Future<bool?> checkPermission() async {
    final result = await super.checkPermission();
    checks++;
    await permissionCheck?.future;
    return result;
  }

  Completer<NotificationResponse?>? launch;
  @override
  Future<NotificationResponse?> takeInitialLaunchResponse() =>
      launch?.future ?? super.takeInitialLaunchResponse();
  @override
  Future<void> initialize() async {
    await super.initialize();
    await initialization?.future;
  }
}

class _RootFixture {
  final sink = _HeldSink();
  late final notifications = TurnNotificationService(sink: sink);
  final controller = GatewayTurnApplicationController();
  late ConnectionManager manager;
  late SavedConnection connection;
  late MobilePushService push;
  final channel = const MethodChannel('test/root/mobile_push');
  final native = <String, dynamic>{'enabled': false};
  final nativeCalls = <String>[];
  final pushRequests = <http.Request>[];
  final lookups = <http.Request>[];
  final keepalive = <String>[];
  List<Map<String, dynamic>> feed = [];
  Completer<http.Response>? detail;
  Completer<Map<String, dynamic>>? snapshot;
  final rpc = Completer<void>();
  int submissions = 0;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    manager = ConnectionManager(prefs, credentialStore: _Secrets());
    await manager.saveConnection(
      'Root fixture',
      'https://root.invalid',
      443,
      'root-api-key',
      gatewayPrefix: '/gateway',
      dashboardPrefix: '/dash',
      dashboardUsername: 'test-user',
      dashboardPassword: 'test-password',
      gatewayProfile: 'test-profile',
    );
    connection = manager.getConnections().single;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
          call,
        ) async {
          keepalive.add(call.method);
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call.method);
          switch (call.method) {
            case 'snapshot':
              if (snapshot != null) return snapshot!.future;
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
              throw StateError('Unexpected native mutation ${call.method}');
          }
        });
    push = MobilePushService(
      supported: true,
      channel: channel,
      clientFactory: (c) => DashboardClient(
        host: c.host,
        port: c.dashboardPort,
        useHttps: c.useHttps,
        pathPrefix: c.dashboardPrefix!,
        username: c.dashboardUsername,
        password: c.dashboardPassword,
        gatewayProfile: c.gatewayProfile,
        httpClient: MockClient((request) async {
          pushRequests.add(request);
          if (request.url.path == '/dash/auth/password-login') {
            return http.Response(
              '{}',
              200,
              headers: {
                'set-cookie': 'hermes_session_at=root-cookie; HttpOnly',
              },
            );
          }
          expectSync(request.method, 'GET');
          expectSync(
            request.headers['Cookie'],
            'hermes_session_at=root-cookie',
          );
          expectSync(request.url.path, '/dash/api/plugins/mobile-push/events');
          return http.Response(
            jsonEncode({'events': feed, 'has_more': false, 'next_cursor': '1'}),
            200,
          );
        }),
      ),
    );
  }

  ApiClient client(SavedConnection c) => ApiClient(
    baseUrl: c.baseUrl,
    apiKey: c.apiKey,
    pathPrefix: c.gatewayPrefix!,
    httpClient: MockClient((request) async {
      lookups.add(request);
      expectSync(request.method, 'GET');
      expectSync(request.headers['Authorization'], 'Bearer ${c.apiKey}');
      expectSync(request.url.path, '/gateway/api/sessions');
      if (request.url.queryParameters['offset'] != '0') {
        return http.Response('{"data":[]}', 200);
      }
      return detail?.future ?? response();
    }),
  );

  void expectLookupOffsets(List<int> offsets) => expect(
    lookups.map((request) => int.parse(request.url.queryParameters['offset']!)),
    offsets,
    reason: 'one owned lookup includes its terminal exhaustion probe',
  );

  http.Response response({String id = 'stored'}) => http.Response(
    jsonEncode({
      'data': [
        {
          'id': id,
          'title': 'Verified root chat',
          'model': '',
          'message_count': 2,
          'started_at': 1,
          'source': 'mobile',
        },
      ],
      'has_more': false,
    }),
    200,
  );

  NotificationResponse tap({String id = 'stored'}) => NotificationResponse(
    payload: jsonEncode({'connectionId': connection.id, 'sessionId': id}),
    notificationResponseType: NotificationResponseType.selectedNotification,
  );

  void seedPush({String id = 'stored', String kind = 'input'}) {
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    native.addAll({
      'enabled': true,
      'active': true,
      'connection': connection.id,
      'binding': MobilePushService.binding(connection),
      'installation': 'root-installation',
      'nonce': 'root-nonce',
      'generation': 7,
      'revision': 1,
      'endpoint': 'https://push.invalid/opaque',
      'sessions': [id],
      'tap': {
        'nonce': 'root-nonce',
        'generation': 7,
        'revision': 1,
        'event_id': 'event-1',
        'expires_at': expiry,
      },
    });
    feed = [
      {
        'event_id': 'event-1',
        'session_id': id,
        'kind': kind,
        'expires_at': expiry,
      },
    ];
  }

  HermesApp app({
    Future<void> Function()? loadPolicy,
    GatewayTurnApplicationController? owner,
    MobilePushService? routingPush,
  }) => HermesApp(
    connManager: manager,
    notifications: notifications,
    mobilePush: routingPush ?? push,
    turnApplicationController: owner ?? controller,
    notificationClientFactory: client,
    loadBackgroundPolicy: loadPolicy,
  );

  Future<NormalGatewayApplicationSession> normal() async {
    final normal = controller.normalSessionFor(
      connection,
      notifications: notifications,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            submissions++;
            onSent();
            await rpc.future;
          },
      resume: ({required localSessionId, required storedSessionId}) async =>
          ResumedGatewaySession(runtimeSessionId: 'runtime', running: true),
      history: (_) async => [],
    );
    await normal.ready;
    normal.chatFor('local', storedSessionId: 'stored', title: 'Owned chat');
    return normal;
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await pumps(tester);
    await controller.close();
    if (!rpc.isCompleted) rpc.complete();
    await pumps(tester);
    push.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ConnectionKeepAliveService.channel, null);
  }
}

Future<void> pumps(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
}

class _HeldStore extends NormalGatewayPendingStore {
  final gate = Completer<List<NormalGatewayPendingMarker>>();
  @override
  Future<List<NormalGatewayPendingMarker>> load(String scope) => gate.future;
}

class _HeldOwner extends GatewayTurnApplicationController {
  late final NormalGatewayApplicationSession normal;
  _HeldOwner(SavedConnection c, _HeldStore store, TurnNotificationService n) {
    normal = NormalGatewayApplicationSession(
      connection: c,
      scope: 'held',
      pendingStore: store,
      notifications: n,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async => throw StateError('Must never submit'),
      resume: ({required localSessionId, required storedSessionId}) async =>
          throw StateError('Must never resume'),
      history: (_) async => [],
    );
  }
  @override
  NormalGatewayApplicationSession normalSessionFor(
    SavedConnection c, {
    NormalGatewayPromptSubmit? submit,
    NormalGatewaySteer? steer,
    NormalGatewayResume? resume,
    NormalGatewayHistory? history,
    TurnNotificationService? notifications,
  }) => normal;
  @override
  Future<void> close() async {
    await normal.close();
    await super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notificationPrefs.value = NotificationPrefs.defaults;
    backgroundWorkEnabled.value = true;
    pendingNotificationApprovals.value = const [];
  });
  tearDown(() {
    notificationResponseHandler = null;
    pendingNotificationApprovals.value = const [];
  });

  for (final initiallyGranted in [false, true]) {
    testWidgets(
      'RECHECK fresh trailing permission observation resyncs background ongoing $initiallyGranted',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        final normal = await f.normal();
        final chat = normal.findChat('local')!;
        final turn = chat.submitPrepared(
          reservation: chat.reserve()!,
          text: 'test',
          localContent: 'test',
        );
        turn.ignore();
        final oldRead = Completer<void>();
        final freshRead = Completer<void>();
        f.sink.permissionResult = initiallyGranted;
        f.sink.permissionCheck = oldRead;
        await tester.pumpWidget(f.app());
        await pumps(tester);
        expect(f.sink.checks, 1);
        expect(f.controller.hasActiveTurn, isTrue);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await pumps(tester);
        f.sink.permissionResult = !initiallyGranted;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumps(tester);
        var sentReturned = false;
        final explicitSend = f.notifications
            .sendTestNotification(title: 'test', body: 'test')
            .then((value) {
              sentReturned = true;
              return value;
            });
        await pumps(tester);
        f.sink.permissionCheck = freshRead;
        oldRead.complete();
        await pumps(tester);
        expect(f.sink.checks, 2);
        expect(
          sentReturned,
          isFalse,
          reason:
              'A stale read cannot finish Send test before the trailing observation',
        );
        expect(f.notifications.permissionGranted, initiallyGranted);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await pumps(tester);
        final showsBeforeFresh = f.sink.shown.length;
        final cancelsBeforeFresh = f.sink.cancelled.length;
        freshRead.complete();
        await pumps(tester);
        expect(await explicitSend, !initiallyGranted);
        expect(f.notifications.permissionGranted, !initiallyGranted);
        expect(f.sink.permissionRequestCount, 1);
        expect(f.sink.checks, 2);
        final ongoingId = TurnNotificationService.ongoingChatNotificationIdFor(
          connectionId: f.connection.id,
          localSessionId: 'local',
        );
        if (initiallyGranted) {
          expect(f.sink.shown.length, showsBeforeFresh);
          expect(
            f.sink.cancelled.skip(cancelsBeforeFresh),
            contains(ongoingId),
          );
        } else {
          expect(
            f.sink.shown
                .skip(showsBeforeFresh)
                .where((n) => n.ongoing)
                .map((n) => n.id),
            contains(ongoingId),
          );
        }
        expect(f.submissions, 1);
        await f.close(tester);
        await turn;
      },
    );
  }

  testWidgets(
    'RECHECK stored false retry permits protection only after held true save succeeds',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      final chat = normal.findChat('local')!;
      final turn = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'test',
        localContent: 'test',
      );
      turn.ignore();
      await f.manager.prefs.setBool(BackgroundWorkPrefsStore.storageKey, false);
      var loads = 0;
      await tester.pumpWidget(
        f.app(
          loadPolicy: () async {
            if (++loads == 1) throw StateError('initial load unavailable');
            await BackgroundWorkPrefsStore.load();
          },
        ),
      );
      await pumps(tester);
      final original = SharedPreferencesStorePlatform.instance;
      final held = _HeldReloadAndWriteStore({
        for (final key in f.manager.prefs.getKeys())
          'flutter.$key': f.manager.prefs.get(key)!,
      });
      SharedPreferencesStorePlatform.instance = held;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumps(tester);
      expect(held.reads, 1);
      final saving = BackgroundWorkPrefsStore.setEnabled(true);
      held.reloadGate.complete();
      await pumps(tester);
      expect(held.policyWrites, 1);
      expect(BackgroundWorkPrefsStore.confirmedEnabled, isFalse);
      expect(backgroundWorkEnabled.value, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), isEmpty);
      held.writeGate.complete(true);
      await saving;
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), hasLength(1));
      expect(BackgroundWorkPrefsStore.pendingChoice.value, isFalse);
      expect(BackgroundWorkPrefsStore.confirmedEnabled, isTrue);
      SharedPreferencesStorePlatform.instance = original;
      await f.close(tester);
      await turn;
    },
  );

  testWidgets(
    'RECHECK same-value enabled intent notifies root while its save is held',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      final chat = normal.findChat('local')!;
      final turn = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'test',
        localContent: 'test',
      );
      turn.ignore();
      await tester.pumpWidget(f.app());
      await pumps(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumps(tester);
      expect(backgroundWorkEnabled.value, isTrue);
      expect(f.keepalive.where((m) => m == 'start'), hasLength(1));
      f.keepalive.clear();
      final original = SharedPreferencesStorePlatform.instance;
      final held = _HeldPolicyWritesStore({
        for (final key in f.manager.prefs.getKeys())
          'flutter.$key': f.manager.prefs.get(key)!,
      });
      SharedPreferencesStorePlatform.instance = held;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      final saving = BackgroundWorkPrefsStore.setEnabled(true);
      await pumps(tester);
      expect(backgroundWorkEnabled.value, isTrue);
      expect(BackgroundWorkPrefsStore.pendingChoice.value, isTrue);
      expect(f.keepalive, contains('stop'));
      expect(f.keepalive.where((m) => m == 'start'), isEmpty);
      expect(held.writes, hasLength(1));
      held.writes.single.complete(true);
      await saving;
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), hasLength(1));
      expect(BackgroundWorkPrefsStore.pendingChoice.value, isFalse);
      SharedPreferencesStorePlatform.instance = original;
      await f.close(tester);
      await turn;
    },
  );

  testWidgets(
    'RECHECK failed first explicit writes never establish unknown root authority',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      final chat = normal.findChat('local')!;
      final turn = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'test',
        localContent: 'test',
      );
      turn.ignore();
      await tester.pumpWidget(
        f.app(
          loadPolicy: () async {
            throw StateError('unavailable');
          },
        ),
      );
      await pumps(tester);
      final original = SharedPreferencesStorePlatform.instance;
      final held = _HeldPolicyWritesStore({
        for (final key in f.manager.prefs.getKeys())
          'flutter.$key': f.manager.prefs.get(key)!,
      });
      SharedPreferencesStorePlatform.instance = held;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final revision = BackgroundWorkPrefsStore.confirmedChanges.value;
      for (final desired in [false, true]) {
        final saving = BackgroundWorkPrefsStore.setEnabled(
          desired,
        ).then((_) => true, onError: (Object _) => false);
        await pumps(tester);
        expect(f.keepalive.where((m) => m == 'start'), isEmpty);
        held.writes.last.complete(false);
        expect(await saving, isFalse);
        await pumps(tester);
        expect(BackgroundWorkPrefsStore.pendingChoice.value, isFalse);
        expect(BackgroundWorkPrefsStore.confirmedChanges.value, revision);
        expect(f.keepalive.where((m) => m == 'start'), isEmpty);
      }
      SharedPreferencesStorePlatform.instance = original;
      await f.close(tester);
      await turn;
    },
  );

  testWidgets(
    'QUALITY real owners retain cleanup for a successful show before a sibling fails',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      final first = normal.findChat('local')!;
      final second = normal.chatFor(
        'sibling',
        storedSessionId: 'stored-sibling',
        title: 'Sibling',
      );
      await tester.pumpWidget(f.app());
      await pumps(tester);
      for (final chat in [first, second]) {
        chat
            .submitPrepared(
              reservation: chat.reserve()!,
              text: 'test',
              localContent: 'test',
            )
            .ignore();
      }
      await pumps(tester);
      expect(f.controller.activeChatActivities, hasLength(2));
      f.sink.failOngoingLocal = 'sibling';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumps(tester);
      final firstId = TurnNotificationService.ongoingChatNotificationIdFor(
        connectionId: f.connection.id,
        localSessionId: 'local',
      );
      expect(
        f.sink.shown.where((n) => n.ongoing).map((n) => n.id),
        contains(firstId),
      );
      await BackgroundWorkPrefsStore.setEnabled(false);
      await pumps(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumps(tester);
      await f.close(tester);
      expect(f.sink.cancelled, contains(firstId));
      expect(f.sink.cancelAllCount, 0);
    },
  );

  testWidgets(
    'REGRESSION retried stored false load must not authorize a held optimistic true write',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      final chat = normal.findChat('local')!;
      final turn = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'test',
        localContent: 'test',
      );
      turn.ignore();
      await f.manager.prefs.setBool(BackgroundWorkPrefsStore.storageKey, false);
      var loads = 0;
      await tester.pumpWidget(
        f.app(
          loadPolicy: () async {
            if (++loads == 1) throw StateError('initial hydration unavailable');
            await BackgroundWorkPrefsStore.load();
          },
        ),
      );
      await pumps(tester);
      final original = SharedPreferencesStorePlatform.instance;
      final values = <String, Object>{
        for (final key in f.manager.prefs.getKeys())
          'flutter.$key': f.manager.prefs.get(key)!,
      };
      final held = _HeldReloadAndWriteStore(values);
      SharedPreferencesStorePlatform.instance = held;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumps(tester);
      expect(held.reads, 1);
      final saving = BackgroundWorkPrefsStore.setEnabled(true);
      final savingOutcome = saving.then(
        (_) => true,
        onError: (Object _) => false,
      );
      held.reloadGate.complete();
      await pumps(tester);
      expect(held.policyWrites, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumps(tester);
      final startsBeforeWriteSuccess = f.keepalive
          .where((m) => m == 'start')
          .length;
      held.writeGate.complete(false);
      expect(await savingOutcome, isFalse);
      SharedPreferencesStorePlatform.instance = original;
      await f.close(tester);
      await turn;
      expect(
        startsBeforeWriteSuccess,
        0,
        reason:
            'Known stored false plus a still-unconfirmed true choice is not enabled authority',
      );
    },
  );

  for (final latestSaveSucceeds in [false, true]) {
    testWidgets(
      'queued policy choices remain disabled until latest save settles $latestSaveSucceeds',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        final normal = await f.normal();
        final chat = normal.findChat('local')!;
        final turn = chat.submitPrepared(
          reservation: chat.reserve()!,
          text: 'test',
          localContent: 'test',
        );
        turn.ignore();
        await tester.pumpWidget(f.app());
        await pumps(tester);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await pumps(tester);
        expect(f.keepalive.where((m) => m == 'start'), hasLength(1));
        f.keepalive.clear();
        final original = SharedPreferencesStorePlatform.instance;
        final held = _HeldPolicyWritesStore({
          for (final key in f.manager.prefs.getKeys())
            'flutter.$key': f.manager.prefs.get(key)!,
        });
        SharedPreferencesStorePlatform.instance = held;
        addTearDown(() {
          for (final gate in held.writes) {
            if (!gate.isCompleted) gate.complete(false);
          }
          SharedPreferencesStorePlatform.instance = original;
        });
        final disabling = BackgroundWorkPrefsStore.setEnabled(false);
        await pumps(tester);
        expect(held.writes, hasLength(1));
        final enabling = BackgroundWorkPrefsStore.setEnabled(
          true,
        ).then((_) => true, onError: (Object _) => false);
        await pumps(tester);
        expect(f.keepalive.where((m) => m == 'start'), isEmpty);
        held.writes[0].complete(true);
        await disabling;
        await pumps(tester);
        expect(held.writes, hasLength(2));
        expect(BackgroundWorkPrefsStore.confirmedEnabled, isFalse);
        expect(backgroundWorkEnabled.value, isTrue);
        expect(BackgroundWorkPrefsStore.pendingChoice.value, isTrue);
        expect(f.keepalive.where((m) => m == 'start'), isEmpty);
        held.writes[1].complete(latestSaveSucceeds);
        expect(await enabling, latestSaveSucceeds);
        await pumps(tester);
        expect(BackgroundWorkPrefsStore.pendingChoice.value, isFalse);
        expect(BackgroundWorkPrefsStore.confirmedEnabled, latestSaveSucceeds);
        expect(backgroundWorkEnabled.value, latestSaveSucceeds);
        expect(
          f.keepalive.where((m) => m == 'start'),
          hasLength(latestSaveSucceeds ? 1 : 0),
        );
        SharedPreferencesStorePlatform.instance = original;
        await f.close(tester);
        await turn;
      },
    );
  }

  for (final initiallyGranted in [false, true]) {
    testWidgets(
      'REGRESSION new resume refresh does not reuse a pre-pause permission observation $initiallyGranted',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        f.sink.permissionResult = initiallyGranted;
        f.sink.permissionCheck = Completer<void>();
        await tester.pumpWidget(f.app());
        await pumps(tester);
        expect(f.sink.checks, 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        f.sink.permissionResult = !initiallyGranted;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumps(tester);
        final explicitSend = f.notifications.sendTestNotification(
          title: 'test',
          body: 'test',
        );
        await pumps(tester);
        f.sink.permissionCheck!.complete();
        await pumps(tester);
        final sent = await explicitSend;
        final observed = f.notifications.permissionGranted;
        final promptCount = f.sink.permissionRequestCount;
        await f.close(tester);
        expect(promptCount, 1);
        expect(
          (observed, sent),
          (!initiallyGranted, !initiallyGranted),
          reason:
              'Resume and explicit Send test must observe the external OS change, not a stale read started before pause',
        );
      },
    );
  }

  for (final push in [false, true]) {
    testWidgets(
      'REGRESSION CONTROL held ${push ? 'push' : 'normal'} lookup completes after pause and resume once',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        await f.normal();
        if (push) f.seedPush();
        f.detail = Completer<http.Response>();
        await tester.pumpWidget(f.app());
        if (!push) notificationResponseHandler!(f.tap());
        await pumps(tester);
        f.expectLookupOffsets([0]);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumps(tester);
        f.expectLookupOffsets([0]);
        f.detail!.complete(f.response());
        await pumps(tester);
        expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
        await pumps(tester);
        f.expectLookupOffsets([0, 50]);
        expect(f.submissions, 0);
        await f.close(tester);
      },
    );
  }

  testWidgets(
    'REGRESSION CONTROL root rejects credential replacement during initial native authority',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.seedPush();
      await f.push.initialize(f.manager);
      final route = await f.push.takePendingNotificationRoute();
      expect(route, isNotNull);
      final held = _HeldRoutePush(f.push);
      held.route.complete(route);
      f.snapshot = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(f.app(routingPush: held));
      await pumps(tester);
      expect(f.lookups, isEmpty);
      await f.manager.updateApiKey(
        f.connection.id,
        'changed-before-native-answer',
      );
      f.snapshot!.complete(Map<String, dynamic>.from(f.native));
      await pumps(tester);
      expect(f.lookups, isEmpty);
      expect(find.byType(ChatScreen, skipOffstage: false), findsNothing);
      await f.close(tester);
      held.dispose();
    },
  );

  testWidgets('SPEC A-B-A taps reuse the earlier canonical route', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    final normal = await f.normal();
    normal.chatFor('local-b', storedSessionId: 'stored-b', title: 'Chat B');
    await tester.pumpWidget(f.app());
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
    final originalContext = tester.element(find.byType(ChatScreen));
    final originalRoute = ModalRoute.of(originalContext)!;
    f.detail = Completer<http.Response>()..complete(f.response(id: 'stored-b'));
    notificationResponseHandler!(f.tap(id: 'stored-b'));
    await pumps(tester);
    expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));
    f.detail = null;
    notificationResponseHandler!(f.tap(id: 'local'));
    await pumps(tester);
    final count = find
        .byType(ChatScreen, skipOffstage: false)
        .evaluate()
        .length;
    expect(originalContext.mounted, isTrue);
    expect(originalRoute.isCurrent, isTrue);
    expect(ModalRoute.of(originalContext), same(originalRoute));
    await f.close(tester);
    expect(
      count,
      2,
      reason: 'A route must be raised, not constructed a second time',
    );
  });

  testWidgets('SPEC tap raises an active chat hidden behind another route', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    await tester.pumpWidget(f.app());
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    final chatContext = tester.element(find.byType(ChatScreen));
    Navigator.of(chatContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Other page')),
      ),
    );
    await pumps(tester);
    expect(find.text('Other page'), findsOneWidget);
    notificationResponseHandler!(f.tap(id: 'local'));
    await pumps(tester);
    final current = ModalRoute.of(chatContext)!.isCurrent;
    await f.close(tester);
    expect(
      current,
      isTrue,
      reason: 'isActive does not mean this chat is the visible route',
    );
  });

  testWidgets('SPEC connection edit fences every detail page', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    f.detail = Completer<http.Response>();
    await tester.pumpWidget(f.app());
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    f.expectLookupOffsets([0]);
    await f.manager.updateApiKey(f.connection.id, 'replacement-key');
    final held = f.detail!;
    f.detail = null;
    held.complete(
      http.Response(
        jsonEncode({
          'data': [
            {
              'id': 'unrelated',
              'title': 'Other',
              'message_count': 2,
              'started_at': 1,
            },
          ],
          'has_more': true,
        }),
        200,
      ),
    );
    await pumps(tester);
    final requests = f.lookups.toList();
    await f.close(tester);
    expect(
      requests,
      hasLength(1),
      reason: 'No second request may use the revoked saved-account credentials',
    );
  });

  for (final push in [false, true]) {
    testWidgets(
      'SPEC ${push ? 'push' : 'normal'} tap finishing paused survives resume',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        await f.normal();
        if (push) f.seedPush();
        f.detail = Completer<http.Response>();
        await tester.pumpWidget(f.app());
        if (!push) notificationResponseHandler!(f.tap());
        await pumps(tester);
        f.expectLookupOffsets([0]);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        f.detail!.complete(f.response());
        await pumps(tester);
        expect(find.byType(ChatScreen), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumps(tester);
        final count = find.byType(ChatScreen).evaluate().length;
        await f.close(tester);
        expect(
          count,
          1,
          reason:
              'Consumed validated tap must wait for foreground, not be lost',
        );
      },
    );
  }

  testWidgets('SPEC failed policy hydration does not enable protection', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    final normal = await f.normal();
    final chat = normal.findChat('local')!;
    final turn = chat.submitPrepared(
      reservation: chat.reserve()!,
      text: 'test',
      localContent: 'test',
    );
    turn.ignore();
    await pumps(tester);
    await f.manager.prefs.setBool(BackgroundWorkPrefsStore.storageKey, false);
    final originalStore = SharedPreferencesStorePlatform.instance;
    var loadCalled = false;
    final loadDone = Completer<void>();
    await tester.pumpWidget(
      f.app(
        loadPolicy: () async {
          loadCalled = true;
          SharedPreferencesStorePlatform.instance = _FailedReloadStore();
          try {
            await BackgroundWorkPrefsStore.load();
          } finally {
            SharedPreferencesStorePlatform.instance = originalStore;
            loadDone.complete();
          }
        },
      ),
    );
    await pumps(tester);
    expect(loadCalled, isTrue);
    expect(loadDone.isCompleted, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await pumps(tester);
    final starts = f.keepalive.where((m) => m == 'start').length;
    await f.close(tester);
    await turn;
    expect(starts, 0, reason: 'No successful load established enabled policy');
  });

  testWidgets('SPEC OS permission granted after denial is observed on resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    f.sink.permissionResult = false;
    await tester.pumpWidget(f.app());
    await pumps(tester);
    expect(f.notifications.permissionGranted, isFalse);
    f.sink.permissionResult = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumps(tester);
    final sent = await f.notifications.sendTestNotification(
      title: 'Test',
      body: 'Test',
    );
    expect(f.sink.permissionRequestCount, 1);
    expect(f.sink.permissionCheckCount, greaterThanOrEqualTo(2));
    await f.close(tester);
    expect(sent, isTrue);
  });

  for (final push in [false, true]) {
    testWidgets(
      'deferred ${push ? 'push' : 'normal'} tap rejects credential edit on resume',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        await f.normal();
        if (push) f.seedPush();
        f.detail = Completer<http.Response>();
        await tester.pumpWidget(f.app());
        if (!push) notificationResponseHandler!(f.tap());
        await pumps(tester);
        f.expectLookupOffsets([0]);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        f.detail!.complete(f.response());
        await pumps(tester);
        await f.manager.updateApiKey(f.connection.id, 'revoked-while-paused');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumps(tester);
        expect(find.byType(ChatScreen, skipOffstage: false), findsNothing);
        expect(find.byType(WorkspaceScreen), findsNothing);
        f.expectLookupOffsets([0]);
        expect(f.submissions, 0);
        await f.close(tester);
      },
    );
  }

  testWidgets('deferred push tap revalidates revoked consent on resume', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    f.seedPush();
    f.detail = Completer<http.Response>();
    await tester.pumpWidget(f.app());
    await pumps(tester);
    f.expectLookupOffsets([0]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    f.detail!.complete(f.response());
    await pumps(tester);
    await f.push.disable();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumps(tester);
    expect(find.byType(ChatScreen, skipOffstage: false), findsNothing);
    f.expectLookupOffsets([0]);
    await f.close(tester);
  });

  testWidgets(
    'push consumed during held route resolution is retained before background check',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.seedPush();
      await f.push.initialize(f.manager);
      final route = await f.push.takePendingNotificationRoute();
      expect(route, isNotNull);
      final held = _HeldRoutePush(f.push);
      await tester.pumpWidget(f.app(routingPush: held));
      await pumps(tester);
      expect(held.takes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      held.route.complete(route);
      await pumps(tester);
      expect(f.lookups, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumps(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      f.expectLookupOffsets([0, 50]);
      final takes = held.takes;
      await pumps(tester);
      expect(
        held.takes,
        takes,
        reason: 'No drain spin after the tap is consumed',
      );
      await f.close(tester);
      held.dispose();
    },
  );

  testWidgets(
    'newer normal intent replaces deferred navigation without a duplicate open',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.detail = Completer<http.Response>();
      await tester.pumpWidget(f.app());
      notificationResponseHandler!(f.tap());
      await pumps(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      f.detail!.complete(f.response());
      await pumps(tester);
      f.detail = Completer<http.Response>()..complete(f.response(id: 'newer'));
      notificationResponseHandler!(f.tap(id: 'newer'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumps(tester);
      expect(
        tester.widget<ChatScreen>(find.byType(ChatScreen)).session.id,
        'newer',
      );
      expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
      f.expectLookupOffsets([0, 0, 50]);
      await pumps(tester);
      f.expectLookupOffsets([0, 0, 50]);
      await f.close(tester);
    },
  );

  for (final revoke in [false, true]) {
    testWidgets(
      'push pagination stops before another request after ${revoke ? 'revocation' : 'credential edit'}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        await f.normal();
        f.seedPush();
        f.detail = Completer<http.Response>();
        await tester.pumpWidget(f.app());
        await pumps(tester);
        f.expectLookupOffsets([0]);
        if (revoke) {
          await f.push.disable();
        } else {
          await f.manager.updateApiKey(f.connection.id, 'replacement-key');
        }
        f.detail!.complete(
          http.Response(
            jsonEncode({
              'data': [
                {
                  'id': 'unrelated',
                  'title': 'Other',
                  'message_count': 2,
                  'started_at': 1,
                },
              ],
              'has_more': true,
            }),
            200,
          ),
        );
        await pumps(tester);
        f.expectLookupOffsets([0]);
        expect(find.byType(ChatScreen), findsNothing);
        await f.close(tester);
      },
    );
  }

  testWidgets('popped canonical routes are removed and can be opened again', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    await tester.pumpWidget(f.app());
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    final context = tester.element(find.byType(ChatScreen));
    final firstRoute = ModalRoute.of(context)!;
    Navigator.of(context).pop();
    await pumps(tester);
    await tester.pump();
    notificationResponseHandler!(f.tap(id: 'local'));
    await pumps(tester);
    final nextRoute = ModalRoute.of(tester.element(find.byType(ChatScreen)))!;
    expect(nextRoute, isNot(same(firstRoute)));
    f.expectLookupOffsets([0, 50, 0, 50]);
    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
    await f.close(tester);
  });

  testWidgets('credential edit cannot focus an old canonical route', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    await tester.pumpWidget(f.app());
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    final firstRoute = ModalRoute.of(tester.element(find.byType(ChatScreen)))!;
    await f.manager.updateApiKey(f.connection.id, 'replacement-key');
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    final currentFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ChatScreen && widget.connection.apiKey == 'replacement-key',
    );
    final current = tester.widget<ChatScreen>(currentFinder);
    expect(current.connection.apiKey, 'replacement-key');
    expect(
      ModalRoute.of(tester.element(currentFinder)),
      isNot(same(firstRoute)),
    );
    f.expectLookupOffsets([0, 50, 0, 50]);
    await f.close(tester);
  });

  testWidgets(
    'explicit durable user choice establishes policy after failed hydration',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      final chat = normal.findChat('local')!;
      final turn = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'test',
        localContent: 'test',
      );
      turn.ignore();
      await tester.pumpWidget(
        f.app(loadPolicy: () async => throw StateError('unavailable')),
      );
      await pumps(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), isEmpty);
      await BackgroundWorkPrefsStore.setEnabled(true);
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), hasLength(1));
      await f.close(tester);
      await turn;
    },
  );

  for (final cold in [true, false]) {
    for (final ongoing in [true, false]) {
      testWidgets(
        '${cold ? 'cold' : 'warm'} ${ongoing ? 'ongoing' : 'completion'} tap opens authenticated chat from fresh connection objects',
        (tester) async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          final f = _RootFixture();
          await f.initialize();
          final normal = await f.normal();
          expect(
            identical(
              f.manager.getConnections().single,
              f.manager.getConnections().single,
            ),
            isFalse,
          );
          if (ongoing) {
            await f.notifications.showOngoingChat(
              connectionId: f.connection.id,
              localSessionId: 'local',
              title: 'Owned chat',
              turnId: 'turn',
              status: 'running',
            );
          } else {
            await f.notifications.ensureInitialized();
            await f.notifications.showKind(
              kind: HermesNotificationKind.turnDone,
              title: 'Response ready',
              body: 'Owned chat',
              eventId: 'turn',
              sessionId: 'stored',
              connectionId: f.connection.id,
              payload: f.tap().payload,
            );
          }
          final tap = NotificationResponse(
            payload: f.sink.shown.single.payload,
            notificationResponseType:
                NotificationResponseType.selectedNotification,
          );
          if (cold) f.sink.initialLaunchResponse = tap;
          await tester.pumpWidget(f.app());
          if (!cold) notificationResponseHandler!(tap);
          await pumps(tester);
          f.expectLookupOffsets([0, 50]);
          final chat = tester.widget<ChatScreen>(find.byType(ChatScreen));
          expect(chat.session.id, 'stored');
          expect(
            normal.findChat(chat.session.id),
            same(normal.findChat('local')),
          );
          expect(f.submissions, 0);
          // Both alias forms, including the other transport, reuse this route.
          notificationResponseHandler!(f.tap(id: 'local'));
          notificationResponseHandler!(f.tap());
          await pumps(tester);
          expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
          f.expectLookupOffsets([0, 50]);
          await f.close(tester);
        },
      );
    }
  }

  for (final removed in [false, true]) {
    testWidgets(
      'connection ${removed ? 'removed' : 'edited'} during authenticated lookup cannot route',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final f = _RootFixture();
        await f.initialize();
        await f.normal();
        f.detail = Completer<http.Response>();
        await tester.pumpWidget(f.app());
        notificationResponseHandler!(f.tap());
        await pumps(tester);
        f.expectLookupOffsets([0]);
        if (removed) {
          await f.manager.deleteConnection(f.connection.id);
        } else {
          await f.manager.updateApiKey(f.connection.id, 'replacement-key');
        }
        f.detail!.complete(f.response());
        await pumps(tester);
        expect(find.byType(ChatScreen), findsNothing);
        expect(find.byType(WorkspaceScreen), findsNothing);
        expect(f.manager.prefs.getString('last_connection_id'), isNull);
        await f.close(tester);
      },
    );
  }

  testWidgets('connection edit during normal.ready prevents even the lookup', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    final store = _HeldStore();
    final owner = _HeldOwner(f.connection, store, f.notifications);
    await tester.pumpWidget(f.app(owner: owner));
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    expect(f.lookups, isEmpty);
    await f.manager.updateApiKey(f.connection.id, 'edited-before-ready');
    store.gate.complete([]);
    await pumps(tester);
    expect(f.lookups, isEmpty);
    expect(find.byType(ChatScreen), findsNothing);
    await f.close(tester);
  });

  testWidgets('push input tap is consumed once and never approves or submits', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    f.seedPush();
    await tester.pumpWidget(f.app());
    await pumps(tester);
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).session.id,
      'stored',
    );
    f.expectLookupOffsets([0, 50]);
    expect(f.nativeCalls.where((m) => m == 'takeTap'), hasLength(1));
    expect(pendingNotificationApprovals.value, isEmpty);
    expect(f.submissions, 0);
    expect(
      f.pushRequests.where(
        (r) => r.method != 'GET' && !r.url.path.endsWith('/password-login'),
      ),
      isEmpty,
    );
    await f.push.refresh();
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    f.expectLookupOffsets([0, 50]);
    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
    await f.close(tester);
  });

  testWidgets(
    'revoked push consent while detail is pending rejects navigation',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.seedPush();
      f.detail = Completer<http.Response>();
      await tester.pumpWidget(f.app());
      await pumps(tester);
      f.expectLookupOffsets([0]);
      await f.push.disable();
      f.detail!.complete(f.response());
      await pumps(tester);
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(WorkspaceScreen), findsNothing);
      expect(pendingNotificationApprovals.value, isEmpty);
      expect(f.submissions, 0);
      await f.close(tester);
    },
  );

  testWidgets(
    'connection edit during push authority await is fenced after validation',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.seedPush();
      f.detail = Completer<http.Response>();
      await tester.pumpWidget(f.app());
      await pumps(tester);
      f.expectLookupOffsets([0]);
      f.snapshot = Completer<Map<String, dynamic>>();
      f.detail!.complete(f.response());
      await pumps(tester);
      await f.manager.updateApiKey(
        f.connection.id,
        'changed-during-native-read',
      );
      f.snapshot!.complete(Map<String, dynamic>.from(f.native));
      await pumps(tester);
      expect(find.byType(ChatScreen), findsNothing);
      await f.close(tester);
    },
  );

  testWidgets(
    'already paused root holds disabled persisted policy before protection',
    (tester) async {
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      final chat = normal.findChat('local')!;
      final turn = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'test',
        localContent: 'test',
      );
      turn.ignore();
      await pumps(tester);
      expect(f.controller.hasActiveTurn, isTrue);
      await f.manager.prefs.setBool(BackgroundWorkPrefsStore.storageKey, false);
      final policy = Completer<void>();
      var policyEntered = false;
      var policyLoaded = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(
        f.app(
          loadPolicy: () async {
            policyEntered = true;
            await policy.future;
            await BackgroundWorkPrefsStore.load();
            policyLoaded = true;
          },
        ),
      );
      // A paused binding suppresses ordinary frame scheduling. Force the
      // mount to exercise an initial lifecycle state, not a later transition.
      tester.binding.scheduleForcedFrame();
      await tester.pump();
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), isEmpty);
      expect(f.sink.shown.where((n) => n.ongoing), isEmpty);
      expect(f.sink.permissionRequestCount, 0);
      policy.complete();
      await pumps(tester);
      expect(policyEntered, isTrue);
      expect(policyLoaded, isTrue);
      expect(backgroundWorkEnabled.value, isFalse);
      expect(f.keepalive.where((m) => m == 'start'), isEmpty);
      expect(f.sink.shown.where((n) => n.ongoing), isEmpty);
      await BackgroundWorkPrefsStore.setEnabled(true);
      await pumps(tester);
      expect(f.keepalive.where((m) => m == 'start'), hasLength(1));
      expect(f.sink.shown.where((n) => n.ongoing), isNotEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumps(tester);
      expect(f.sink.permissionRequestCount, 1);
      expect(f.sink.cancelAllCount, 0);
      await f.close(tester);
      await turn;
    },
  );

  testWidgets(
    'ordinary taps single-flight but push re-owns the same canonical chat',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.detail = Completer<http.Response>();
      await tester.pumpWidget(f.app());
      notificationResponseHandler!(f.tap(id: 'local'));
      await pumps(tester);
      notificationResponseHandler!(f.tap(id: 'local'));
      await pumps(tester);
      f.expectLookupOffsets([0]);
      f.seedPush();
      await f.push.refresh();
      await pumps(tester);
      // Same target is not equivalent authority: the newer push must validate
      // its own proof instead of inheriting the ordinary worker's authority.
      f.expectLookupOffsets([0, 0]);
      f.detail!.complete(f.response());
      await pumps(tester);
      expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
      expect(f.submissions, 0);
      expect(pendingNotificationApprovals.value, isEmpty);
      await f.close(tester);
    },
  );

  testWidgets('late cold launch response cannot override a newer warm tap', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    f.sink.launch = Completer<NotificationResponse?>();
    await tester.pumpWidget(f.app());
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    f.sink.launch!.complete(f.tap(id: 'older-cold-session'));
    await pumps(tester);
    f.expectLookupOffsets([0, 50]);
    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
    expect(find.byType(WorkspaceScreen), findsNothing);
    await f.close(tester);
  });

  testWidgets('tap on the open chat cancels a different older pending route', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final f = _RootFixture();
    await f.initialize();
    await f.normal();
    await tester.pumpWidget(f.app());
    notificationResponseHandler!(f.tap());
    await pumps(tester);
    f.detail = Completer<http.Response>();
    notificationResponseHandler!(f.tap(id: 'other-session'));
    await pumps(tester);
    f.expectLookupOffsets([0, 50, 0]);
    notificationResponseHandler!(f.tap(id: 'local'));
    f.detail!.complete(f.response(id: 'other-session'));
    await pumps(tester);
    expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).session.id,
      'stored',
    );
    await f.close(tester);
  });

  testWidgets(
    'held optional push initialization never delays the first root frame',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      f.snapshot = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(f.app());
      await pumps(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(f.sink.permissionRequestCount, 1);
      expect(f.nativeCalls, contains('snapshot'));
      expect(f.nativeCalls, isNot(contains('permission')));
      expect(f.nativeCalls, isNot(contains('enable')));
      expect(f.pushRequests, isEmpty);
      f.snapshot!.complete(Map<String, dynamic>.from(f.native));
      await pumps(tester);
      await f.close(tester);
    },
  );

  testWidgets(
    'a newer push tap supersedes pending lookup without stranding its singleflight',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.seedPush();
      final oldDetail = Completer<http.Response>();
      f.detail = oldDetail;
      await tester.pumpWidget(f.app());
      await pumps(tester);
      f.expectLookupOffsets([0]);
      f.seedPush();
      (f.native['tap'] as Map)['event_id'] = 'event-2';
      f.feed.single['event_id'] = 'event-2';
      await f.push.refresh();
      await pumps(tester);
      f.detail = null;
      oldDetail.complete(f.response());
      await pumps(tester);
      f.expectLookupOffsets([0, 0, 50]);
      expect(find.byType(ChatScreen, skipOffstage: false), findsOneWidget);
      expect(f.submissions, 0);
      await f.close(tester);
    },
  );

  testWidgets(
    'startup orphan cleanup cannot cancel a new notification queued during initialization',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final orphan = TurnNotificationService.ongoingChatNotificationIdFor(
        connectionId: 'removed',
        localSessionId: 'old',
      );
      await f.manager.prefs.setStringList(
        TurnNotificationService.ongoingIdsStorageKey,
        [orphan.toString()],
      );
      f.sink.initialization = Completer<void>();
      await tester.pumpWidget(f.app());
      final showing = f.notifications.showOngoingChat(
        connectionId: f.connection.id,
        localSessionId: 'new',
        title: 'New work',
        turnId: 'new-turn',
        status: 'running',
      );
      f.sink.initialization!.complete();
      await pumps(tester);
      await showing;
      final fresh = f.sink.shown.single;
      expect(f.sink.cancelled, contains(orphan));
      expect(f.sink.cancelled, isNot(contains(fresh.id)));
      expect(f.sink.cancelAllCount, 0);
      await f.close(tester);
      expect(f.sink.cancelled, isNot(contains(fresh.id)));
    },
  );

  testWidgets(
    'lookup finishing after root disposal cannot navigate or leak a handler',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await f.normal();
      f.detail = Completer<http.Response>();
      await tester.pumpWidget(f.app());
      notificationResponseHandler!(f.tap());
      await pumps(tester);
      f.expectLookupOffsets([0]);
      await tester.pumpWidget(const SizedBox());
      expect(notificationResponseHandler, isNull);
      f.detail!.complete(f.response());
      await pumps(tester);
      expect(find.byType(ChatScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await f.close(tester);
    },
  );

  testWidgets(
    'notification master changes resync unchanged active work and terminal survives cleanup',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      final normal = await f.normal();
      await tester.pumpWidget(f.app());
      await pumps(tester);
      final chat = normal.findChat('local')!;
      final turn = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'test',
        localContent: 'test',
      );
      turn.ignore();
      await pumps(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pumps(tester);
      final ongoing = f.sink.shown.lastWhere((n) => n.ongoing);
      await NotificationPrefsStore.setEnabled(false);
      await pumps(tester);
      expect(f.sink.cancelled, contains(ongoing.id));
      final before = f.sink.shown.length;
      await NotificationPrefsStore.setEnabled(true);
      await pumps(tester);
      expect(f.sink.shown.length, greaterThan(before));
      // Model an owned lifecycle terminal, not stock's uncorrelated completion
      // bookend (which must reconcile before declaring success).
      normal.receiveEvent(
        'local',
        StreamEvent(type: 'message.start', data: const {}, turnId: 'root-turn'),
      );
      normal.receiveEvent(
        'local',
        StreamEvent(
          type: 'turn.end',
          data: {'status': 'completed'},
          turnId: 'root-turn',
        ),
      );
      f.rpc.complete();
      await pumps(tester);
      final terminal = f.sink.shown.lastWhere((n) => !n.ongoing);
      expect(f.controller.hasActiveTurn, isFalse);
      expect(f.sink.cancelled, isNot(contains(terminal.id)));
      expect(f.sink.cancelAllCount, 0);
      expect(f.keepalive.last, 'stop');
      await f.close(tester);
      await turn;
    },
  );

  testWidgets(
    'foreground permission waits for init, hidden root defers permission and tap',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      f.sink.initialization = Completer<void>();
      await tester.pumpWidget(f.app());
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(f.sink.permissionRequestCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      notificationResponseHandler!(f.tap());
      f.sink.initialization!.complete();
      await pumps(tester);
      expect(f.sink.permissionRequestCount, 0);
      expect(f.lookups, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumps(tester);
      expect(f.sink.permissionRequestCount, 1);
      expect(find.byType(ChatScreen), findsOneWidget);
      await f.close(tester);
    },
  );

  testWidgets(
    'root remount retains process push singleton and detaches old handler',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final f = _RootFixture();
      await f.initialize();
      await tester.pumpWidget(f.app());
      await pumps(tester);
      await tester.pumpWidget(const SizedBox());
      await pumps(tester);
      expect(notificationResponseHandler, isNull);
      f.seedPush();
      await f.push.refresh();
      final replacement = GatewayTurnApplicationController();
      await tester.pumpWidget(f.app(owner: replacement));
      await pumps(tester);
      expect(find.byType(ChatScreen), findsOneWidget);
      f.expectLookupOffsets([0, 50]);
      expect(pendingNotificationApprovals.value, isEmpty);
      await f.close(tester);
    },
  );
}
