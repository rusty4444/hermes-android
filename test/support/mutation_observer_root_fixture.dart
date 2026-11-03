// Narrow reuse of the independently exercised ROOT37 fixture: real root,
// default session factories, real manager and loopback transport. Channels and
// credentials are fake; no device/provider or stock corruption-generation claim.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/android_launch_intent_service.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/notification_approval_authority.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mobile_push_service_test.dart' show MemorySecrets;
import '../normal_gateway_alias_handoff_wire_test.dart' show BindingServer;
import 'memory_turn_journal_store.dart';

class _Server extends BindingServer {
  _Server(super.server);
  static Future<_Server> start() async {
    final owner = _Server(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    owner.server.listen(owner.handle);
    return owner;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (request.uri.path == '/api/sessions') {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"data":[],"has_more":false}');
      await request.response.close();
      return;
    }
    await super.handle(request);
  }
}

class MutationObserverRootFixture {
  final credentials = MemorySecrets();
  final controller = GatewayTurnApplicationController(
    journalFactory: () => GatewayTurnJournal(store: MemoryTurnJournalStore()),
  );
  final notifications = TurnNotificationService();
  final launch = AndroidLaunchIntentService();
  final pushChannel = const MethodChannel('test/mutation-observer-root');
  final plugin = const MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  late final MobilePushService push;
  late final ConnectionManager manager;
  late final SavedConnection connection;
  late final BindingServer server;

  Future<void> initialize(WidgetTester tester) async {
    lifecycle(tester, AppLifecycleState.resumed);
    server = (await tester.runAsync(_Server.start))!;
    manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: credentials,
    );
    await manager.saveConnection(
      'Queued B',
      '127.0.0.1',
      server.server.port,
      'fixture',
      dashboardPort: server.server.port,
      dashboardProxied: true,
      gatewayProfile: 'root-profile',
    );
    connection = manager.getConnections().single;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => 1,
    );
    messenger.setMockMethodCallHandler(
      plugin,
      (call) async =>
          call.method == 'getNotificationAppLaunchDetails' ? null : true,
    );
    messenger.setMockMethodCallHandler(
      ConnectionKeepAliveService.channel,
      (_) async => true,
    );
    messenger.setMockMethodCallHandler(pushChannel, (call) async {
      if (call.method == 'takeTap') return null;
      return <String, dynamic>{'enabled': false};
    });
    push = MobilePushService(supported: true, channel: pushChannel);
    launch.pendingQuickChat.value = true;
    await tester.pumpWidget(
      HermesApp(
        connManager: manager,
        turnApplicationController: controller,
        notifications: notifications,
        mobilePush: push,
        launchIntents: launch,
      ),
    );
    await until(tester, () => find.byType(ChatScreen).evaluate().isNotEmpty);
    await until(
      tester,
      () => find
          .byKey(const ValueKey('legacy-transport-notice'))
          .evaluate()
          .isNotEmpty,
    );
    await drain(tester);
  }

  Future<PendingNotificationApproval> queueAndPause(WidgetTester tester) async {
    notificationResponseHandler!(
      NotificationResponse(
        actionId: 'approve',
        payload: jsonEncode({
          'connectionId': connection.id,
          'sessionId': 'stored',
          'requestId': 'approval-reused',
          ...NotificationApprovalAuthority.origin(connection),
        }),
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
      ),
    );
    await until(tester, () => pendingNotificationApprovals.value.length == 1);
    final queued = pendingNotificationApprovals.value.single;
    lifecycle(tester, AppLifecycleState.paused);
    await drain(tester);
    return queued;
  }

  Future<void> close(WidgetTester tester) async {
    lifecycle(tester, AppLifecycleState.resumed);
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await drain(tester);
    await controller.close();
    await tester.runAsync(server.close);
    // Inherited fixture-only recovery timeout drain, not a product timeout.
    await tester.pump(const Duration(seconds: 21));
    expect(pendingNotificationApprovals.value, isEmpty);
    push.dispose();
    launch.dispose();
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in [
      plugin,
      pushChannel,
      ConnectionKeepAliveService.channel,
      const MethodChannel('plugins.flutter.io/image_picker'),
      const MethodChannel('flutter_tts'),
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    debugDefaultTargetPlatformOverride = null;
  }

  static Future<void> until(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 3000; i++) {
      await tester.pump();
      if (condition()) return;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    fail('Root condition did not arrive');
  }

  static Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  static void lifecycle(WidgetTester tester, AppLifecycleState target) {
    if (tester.binding.lifecycleState == target) return;
    if (target == AppLifecycleState.paused) {
      if (tester.binding.lifecycleState == AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
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
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  }
}
