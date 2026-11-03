import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_turn_notification_sink.dart';

class _Activities extends GatewayTurnApplicationController {
  List<NormalGatewayChatActivity> activities = [];
  final listeners = <Object, void Function()>{};
  @override
  bool get hasActiveTurn => activities.isNotEmpty;
  @override
  Iterable<NormalGatewayChatActivity> get activeChatActivities => activities;
  @override
  Object addTurnActivityListener(void Function() listener) {
    final token = Object();
    listeners[token] = listener;
    return token;
  }

  @override
  void removeTurnActivityListener(Object token) => listeners.remove(token);
  void replace(List<NormalGatewayChatActivity> value) {
    activities = value;
    for (final listener in listeners.values.toList()) {
      listener();
    }
  }
}

class _FaultSink extends RecordingTurnNotificationSink {
  String? failLocal;
  bool failAfterShow = false;
  final failingCancels = <int>{};
  final cancelAttempts = <int>[];
  final live = <int, TurnNotification>{};
  final attempts = <String>[];
  Completer<void>? showGate;
  @override
  Future<void> show(TurnNotification notification) async {
    final local = notification.ongoing
        ? (jsonDecode(notification.payload) as Map)['localSessionId'] as String
        : '';
    attempts.add(local);
    if (local == failLocal && !failAfterShow) {
      throw PlatformException(code: 'notification_unavailable');
    }
    await showGate?.future;
    await super.show(notification);
    live[notification.id] = notification;
    if (local == failLocal && failAfterShow) {
      throw PlatformException(code: 'notification_reply_lost');
    }
  }

  @override
  Future<void> cancel(int id) async {
    cancelAttempts.add(id);
    if (failingCancels.contains(id)) {
      throw PlatformException(code: 'notification_cancel_unavailable');
    }
    await super.cancel(id);
    live.remove(id);
  }
}

NormalGatewayChatActivity activity(String local) => NormalGatewayChatActivity(
  connectionId: 'c',
  localSessionId: local,
  storedSessionId: 'stored-$local',
  title: 'Chat $local',
  turnId: 'turn-$local',
  status: 'running',
);

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
  }
}

Future<MobilePushService> _mountBackground(
  WidgetTester tester,
  _Activities owner,
  _FaultSink sink,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final prefs = await SharedPreferences.getInstance();
  final push = MobilePushService(supported: false);
  await tester.pumpWidget(
    HermesApp(
      connManager: ConnectionManager(prefs),
      turnApplicationController: owner,
      notifications: TurnNotificationService(sink: sink),
      mobilePush: push,
    ),
  );
  await drain(tester);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await drain(tester);
  return push;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backgroundWorkEnabled.value = true;
    notificationPrefs.value = NotificationPrefs.defaults;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          ConnectionKeepAliveService.channel,
          (_) async => true,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ConnectionKeepAliveService.channel, null);
  });

  for (final failAfterShow in [false, true]) {
    testWidgets(
      'item show failures preserve sibling progress and stale cleanup; posted=$failAfterShow',
      (tester) async {
        final owner = _Activities()..activities = [activity('stale')];
        final sink = _FaultSink();
        final push = await _mountBackground(tester, owner, sink);
        expect(sink.live.values.single.title, 'Chat stale');
        sink
          ..failLocal = 'b'
          ..failAfterShow = failAfterShow;
        owner.replace([activity('a'), activity('b'), activity('c')]);
        await drain(tester);
        expect(sink.live.values.map((n) => n.title).toSet(), {
          'Chat a',
          if (failAfterShow) 'Chat b',
          'Chat c',
        });
        if (!failAfterShow) {
          // Retry the exact same desired signature after a platform recovery.
          sink.failLocal = null;
          owner.replace(owner.activities);
          await drain(tester);
          expect(sink.live.values.map((n) => n.title).toSet(), {
            'Chat a',
            'Chat b',
            'Chat c',
          });
        }
        owner.replace([]);
        await drain(tester);
        expect(sink.live, isEmpty);
        expect(sink.cancelAllCount, 0);
        await tester.pumpWidget(const SizedBox());
        await drain(tester);
        push.dispose();
      },
    );
  }

  for (final retryViaDispose in [false, true]) {
    testWidgets(
      'failed cancellation remains owned and does not block sibling; dispose=$retryViaDispose',
      (tester) async {
        final owner = _Activities()
          ..activities = [activity('a'), activity('b')];
        final sink = _FaultSink();
        final push = await _mountBackground(tester, owner, sink);
        final first = TurnNotificationService.ongoingChatNotificationIdFor(
          connectionId: 'c',
          localSessionId: 'a',
        );
        final second = TurnNotificationService.ongoingChatNotificationIdFor(
          connectionId: 'c',
          localSessionId: 'b',
        );
        sink.failingCancels.add(first);
        owner.replace([]);
        await drain(tester);
        expect(sink.live.keys, [first]);
        expect(sink.cancelAttempts, containsAll([first, second]));
        sink.failingCancels.clear();
        if (!retryViaDispose) {
          owner.replace([]); // An unchanged desired state must retry failure.
          await drain(tester);
          expect(sink.live, isEmpty);
        }
        final root = tester.state(find.byType(HermesApp));
        // A paused binding does not schedule ordinary frames. Force the frame
        // so this case actually disposes the root rather than awaiting resume.
        tester.binding.scheduleForcedFrame();
        await tester.pumpWidget(const SizedBox());
        await drain(tester);
        expect(root.mounted, isFalse);
        expect(sink.live, isEmpty);
        expect(sink.cancelAllCount, 0);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getStringList(TurnNotificationService.ongoingIdsStorageKey),
          isEmpty,
        );
        push.dispose();
      },
    );
  }

  testWidgets(
    'QUALITY partial show failure must not lose first-chat cleanup ownership',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final prefs = await SharedPreferences.getInstance();
      final owner = _Activities()..activities = [activity('a'), activity('b')];
      final sink = _FaultSink()..failLocal = 'b';
      final notifications = TurnNotificationService(sink: sink);
      final push = MobilePushService(supported: false);
      await tester.pumpWidget(
        HermesApp(
          connManager: ConnectionManager(prefs),
          turnApplicationController: owner,
          notifications: notifications,
          mobilePush: push,
        ),
      );
      await drain(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await drain(tester);
      expect(sink.attempts, containsAllInOrder(['a', 'b']));
      expect(sink.live.values.map((n) => n.title), ['Chat a']);
      owner.replace([]); // Both actual turns settle; foreground service stops.
      await drain(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await drain(tester);
      await tester.pumpWidget(const SizedBox());
      await drain(tester);
      push.dispose();
      expect(sink.cancelAllCount, 0);
      expect(
        sink.live,
        isEmpty,
        reason:
            'A successful show must remain owned even if sibling B throws; settlement, resume and dispose must clean A',
      );
    },
  );
}
