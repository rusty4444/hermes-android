import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/notification_approval_fixture.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';

import 'support/recording_turn_notification_sink.dart';

/// Characterization tests for the notification behaviour Hermes Android ships
/// today. Phase 3 of the daily-driver roadmap replaces this single channel with
/// four prioritized channels, deep links, and notification actions. These tests
/// pin the current contract first so that rework is a deliberate change and not
/// an accidental regression.
void main() {
  late RecordingTurnNotificationSink sink;
  late TurnNotificationService service;

  setUp(() {
    sink = RecordingTurnNotificationSink();
    service = TurnNotificationService(sink: sink);
    notificationPrefs.value = NotificationPrefs.defaults;
  });

  group('initialization', () {
    test('is idempotent — the channel is only created once', () async {
      await service.ensureInitialized();
      await service.ensureInitialized();
      await service.ensureInitialized();

      expect(sink.initializeCount, 1);
    });

    test(
      'degrades to a no-op when the platform channel is unavailable',
      () async {
        sink.initializeError = StateError('no platform channel');

        await service.ensureInitialized();

        // Initialization must not rethrow: the app has to keep running on a
        // device where notifications are unavailable.
        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 'Done',
          turnId: 't-1',
        );
        expect(sink.shown, isEmpty);
      },
    );

    test('a failed initialization can be retried on the next call', () async {
      sink.initializeError = StateError('no platform channel');
      await service.ensureInitialized();
      expect(sink.initializeCount, 1);

      sink.initializeError = null;
      await service.ensureInitialized();

      expect(sink.initializeCount, 2);
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'Done',
        turnId: 't-1',
      );
      expect(sink.shown, hasLength(1));
    });
  });

  group('showTurnCompleted', () {
    test(
      'drops the notification when the service was never initialized',
      () async {
        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 'Done',
          turnId: 't-1',
        );

        expect(sink.shown, isEmpty);
      },
    );

    test(
      'posts the turn summary as the body under the Hermes turn channel',
      () async {
        await service.ensureInitialized();

        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 'Roadmap: Response ready',
          turnId: 'turn-42',
        );

        expect(sink.shown, hasLength(1));
        final posted = sink.shown.single;
        expect(posted.title, 'Ready');
        expect(posted.body, 'Roadmap: Response ready');
        // The payload is the deep-link seed Phase 3 will extend.
        expect(posted.payload, contains('turn-42'));
        expect(posted.channel.id, 'hermes_turn_notifications');
        expect(posted.channel.name, 'Hermes Turns');
        expect(
          posted.channel.description,
          'Notifications for completed background turns',
        );
      },
    );

    test(
      'replayed settlements for one turn are throttled and never stack',
      () async {
        await service.ensureInitialized();

        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 'first',
          turnId: 'turn-42',
        );
        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 'second',
          turnId: 'turn-42',
        );

        // The second call lands inside the 1s replay window: dropped, so a
        // replayed settlement cannot alert twice.
        expect(sink.shown, hasLength(1));
        expect(sink.shown.single.body, 'first');
      },
    );

    test('gives distinct turns distinct ids', () async {
      await service.ensureInitialized();

      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'a',
        turnId: 'turn-1',
      );
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'b',
        turnId: 'turn-2',
      );

      expect(sink.shown.map((n) => n.id).toSet(), hasLength(2));
    });

    test('same turn ids on different connections remain distinct', () async {
      await service.ensureInitialized();

      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'first profile',
        turnId: 'turn-1',
        sessionId: 'shared-session',
        connectionId: 'connection-a',
      );
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'second profile',
        turnId: 'turn-1',
        sessionId: 'shared-session',
        connectionId: 'connection-b',
      );

      expect(sink.shown, hasLength(2));
      expect(sink.shown.map((notice) => notice.id).toSet(), hasLength(2));
    });

    test('always produces a non-negative Android notification id', () async {
      await service.ensureInitialized();

      for (final turnId in [
        'turn-1',
        'client:9f3a-4d21',
        'a very long server issued turn identifier 0123456789',
        '',
      ]) {
        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 's',
          turnId: turnId,
        );
      }

      expect(sink.shown.map((n) => n.id), everyElement(isNonNegative));
    });
  });

  group('runtime permission', () {
    test(
      'initialization asks Android for the notification permission',
      () async {
        await service.ensureInitialized(requestPermission: true);

        // Android 13+ denies POST_NOTIFICATIONS by default even when the
        // manifest declares it. Never asking means every notification is
        // silently dropped by the OS.
        expect(sink.permissionRequestCount, 1);
      },
    );

    test('the permission is requested once, not on every call', () async {
      await service.ensureInitialized(requestPermission: true);
      await service.ensureInitialized(requestPermission: true);

      expect(sink.permissionRequestCount, 1);
    });

    test(
      'a denied permission is reported instead of silently dropping posts',
      () async {
        sink.permissionResult = false;

        await service.ensureInitialized(requestPermission: true);

        expect(service.permissionGranted, isFalse);
      },
    );

    test('a granted permission lets turn notifications through', () async {
      sink.permissionResult = true;

      await service.ensureInitialized(requestPermission: true);
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'done',
        turnId: 'turn-1',
      );

      expect(service.permissionGranted, isTrue);
      expect(sink.shown, hasLength(1));
    });

    test('a platform that needs no runtime permission stays usable', () async {
      // iOS and Android < 13 return null: no runtime gate to satisfy.
      sink.permissionResult = null;

      await service.ensureInitialized(requestPermission: true);
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'done',
        turnId: 'turn-1',
      );

      expect(service.permissionGranted, isTrue);
      expect(sink.shown, hasLength(1));
    });

    test(
      'a failing permission request does not break initialization',
      () async {
        sink.permissionError = StateError('no platform channel');

        await service.ensureInitialized(requestPermission: true);

        // The app must keep running; notifications degrade, they never crash.
        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 'done',
          turnId: 'turn-1',
        );
        expect(sink.shown, hasLength(1));
      },
    );
  });

  group('cancellation', () {
    test('cancels the exact id that was shown for that turn', () async {
      await service.ensureInitialized();
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'done',
        turnId: 'turn-42',
      );

      await service.cancelTurnCompleted('turn-42');

      expect(sink.cancelled, [sink.shown.single.id]);
    });

    test('is a no-op before initialization', () async {
      await service.cancelTurnCompleted('turn-42');
      await service.cancelAll();

      expect(sink.cancelled, isEmpty);
      expect(sink.cancelAllCount, 0);
    });

    test('cancelAll clears every Hermes turn notification', () async {
      await service.ensureInitialized();
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'a',
        turnId: 'turn-1',
      );
      await service.showTurnCompleted(
        title: 'Ready',
        turnSummary: 'b',
        turnId: 'turn-2',
      );

      await service.cancelAll();

      expect(sink.cancelAllCount, 1);
    });
  });

  group('desktop-parity kinds', () {
    test('approval posts on the attention channel with actions', () async {
      await service.ensureInitialized();
      final fired = await service.showKind(
        kind: HermesNotificationKind.approval,
        title: 'Approval needed — Roadmap',
        body: 'rm -rf build',
        eventId: 'req-1',
        sessionId: 'notif-session',
        actions: const [
          TurnNotificationAction(id: 'approve', label: 'Approve'),
          TurnNotificationAction(id: 'reject', label: 'Deny'),
        ],
        payload: '{"sessionId":"notif-session","requestId":"req-1"}',
      );

      expect(fired, isTrue);
      final posted = sink.shown.single;
      expect(posted.channel.id, 'hermes_attention');
      expect(posted.importance, TurnNotificationImportance.high);
      expect(posted.actions.map((a) => a.id), ['approve', 'reject']);
      expect(posted.payload, contains('req-1'));
    });

    test('each kind posts on its mapped channel', () async {
      await service.ensureInitialized();
      await service.showKind(
        kind: HermesNotificationKind.turnDone,
        title: 't',
        body: 'b',
        eventId: 'turn-1',
        sessionId: 's1',
      );
      await service.showKind(
        kind: HermesNotificationKind.backgroundDone,
        title: 't',
        body: 'b',
        eventId: 'task-1',
        sessionId: 's2',
      );
      await service.showKind(
        kind: HermesNotificationKind.credits,
        title: 't',
        body: 'b',
        eventId: 'credits-1',
        sessionId: 's3',
      );

      expect(sink.shown[0].channel.id, 'hermes_turn_notifications');
      expect(sink.shown[1].channel.id, 'hermes_background');
      expect(sink.shown[1].importance, TurnNotificationImportance.low);
      expect(sink.shown[2].channel.id, 'hermes_notices');
    });

    test('a disabled kind posts nothing', () async {
      await service.ensureInitialized();
      notificationPrefs.value = NotificationPrefs.defaults.copyWith(
        kind: HermesNotificationKind.plugin,
        kindValue: false,
      );

      final fired = await service.showKind(
        kind: HermesNotificationKind.plugin,
        title: 't',
        body: 'b',
        eventId: 'plugin-1',
        sessionId: 's',
      );

      expect(fired, isFalse);
      expect(sink.shown, isEmpty);
    });

    test('the master switch silences every kind', () async {
      await service.ensureInitialized();
      notificationPrefs.value = NotificationPrefs.defaults.copyWith(
        enabled: false,
      );

      final fired = await service.showKind(
        kind: HermesNotificationKind.approval,
        title: 't',
        body: 'b',
        eventId: 'req-1',
        sessionId: 's',
      );

      expect(fired, isFalse);
      expect(sink.shown, isEmpty);
    });

    test('replays of the same event are throttled', () async {
      await service.ensureInitialized();
      await service.showKind(
        kind: HermesNotificationKind.input,
        title: 't',
        body: 'first',
        eventId: 'request-1',
        sessionId: 's',
      );
      final second = await service.showKind(
        kind: HermesNotificationKind.input,
        title: 't',
        body: 'second',
        eventId: 'request-1',
        sessionId: 's',
      );

      expect(second, isFalse);
      expect(sink.shown, hasLength(1));
    });

    test('distinct same-session events both post with distinct ids', () async {
      await service.ensureInitialized();

      final first = await service.showKind(
        kind: HermesNotificationKind.approval,
        title: 'Approval',
        body: 'first',
        eventId: 'request-1',
        sessionId: 's',
        connectionId: 'connection-a',
      );
      final second = await service.showKind(
        kind: HermesNotificationKind.approval,
        title: 'Approval',
        body: 'second',
        eventId: 'request-2',
        sessionId: 's',
        connectionId: 'connection-a',
      );

      expect(first, isTrue);
      expect(second, isTrue);
      expect(sink.shown, hasLength(2));
      expect(sink.shown.map((notice) => notice.id).toSet(), hasLength(2));
    });

    test('different sessions keep distinct notification ids', () async {
      await service.ensureInitialized();
      await service.showKind(
        kind: HermesNotificationKind.credits,
        title: 't',
        body: 'a',
        eventId: 'credits',
        sessionId: 's',
      );
      await service.showKind(
        kind: HermesNotificationKind.credits,
        title: 't',
        body: 'b',
        eventId: 'credits',
        sessionId: 'other',
      );

      expect(sink.shown.map((n) => n.id).toSet(), hasLength(2));
    });

    test('showTurnFailed posts the failure on the turns channel', () async {
      await service.ensureInitialized();
      await service.showTurnFailed(
        title: 'Turn failed',
        turnSummary: 'Roadmap: oops',
        turnId: 'turn-9',
      );

      final posted = sink.shown.single;
      expect(posted.channel.id, 'hermes_turn_notifications');
      expect(posted.body, 'Roadmap: oops');
      expect(posted.payload, contains('turn-9'));
    });

    test(
      'the test notification bypasses the prefs and reports delivery',
      () async {
        notificationPrefs.value = NotificationPrefs.defaults.copyWith(
          enabled: false,
        );

        final ok = await service.sendTestNotification(
          title: 'Test',
          body: 'Body',
        );

        expect(ok, isTrue);
        expect(sink.shown.single.title, 'Test');
      },
    );
  });

  group('routing', () {
    test(
      'turn payloads carry session and connection for tap routing',
      () async {
        await service.ensureInitialized();
        await service.showTurnCompleted(
          title: 'Ready',
          turnSummary: 'Roadmap: done',
          turnId: 'turn-7',
          sessionId: 'notif-session',
          connectionId: 'conn-1',
        );

        final payload =
            jsonDecode(sink.shown.single.payload) as Map<String, dynamic>;
        expect(payload, {
          'turnId': 'turn-7',
          'sessionId': 'notif-session',
          'connectionId': 'conn-1',
        });
      },
    );

    test('a cold-start launch response is consumed exactly once', () async {
      sink.initialLaunchResponse = const NotificationResponse(
        id: 1,
        actionId: 'approve',
        payload: '{"sessionId":"s","connectionId":"c","requestId":"r"}',
        notificationResponseType: NotificationResponseType.selectedNotification,
      );

      final first = await service.takeInitialNotificationResponse();
      expect(first?.actionId, 'approve');

      final second = await service.takeInitialNotificationResponse();
      expect(second, isNull);
    });

    test('routes parse JSON payloads into routing fields', () {
      final route = NotificationRoute.fromResponse(
        const NotificationResponse(
          id: 1,
          actionId: 'reject',
          payload: '{"sessionId":"s1","connectionId":"c1","requestId":"r1"}',
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
      );

      expect(route.sessionId, 's1');
      expect(route.connectionId, 'c1');
      expect(route.requestId, 'r1');
      expect(route.actionId, 'reject');
      expect(route.approvalChoice, 'deny');
    });

    test('legacy plain-string payloads parse with no routing fields', () {
      final route = NotificationRoute.fromResponse(
        const NotificationResponse(
          id: 1,
          payload: 'turn-42',
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
      );

      expect(route.sessionId, isNull);
      expect(route.connectionId, isNull);
      expect(route.requestId, isNull);
      expect(route.approvalChoice, isNull);
    });

    test('only approve and reject map to approval choices', () {
      String? choiceFor(String? actionId) => NotificationRoute.fromResponse(
        NotificationResponse(
          id: 1,
          actionId: actionId,
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
      ).approvalChoice;

      expect(choiceFor('approve'), 'once');
      expect(choiceFor('reject'), 'deny');
      expect(choiceFor('other'), isNull);
      expect(choiceFor(null), isNull);
    });
  });

  group('pending notification approvals', () {
    setUp(() => pendingNotificationApprovals.value = const []);
    tearDown(() => pendingNotificationApprovals.value = const []);

    test('deduplicates by connection + session + request', () {
      final approval = PendingNotificationApproval(
        authority: fixtureApprovalAuthority(
          fixtureApprovalConnection('conn-a'),
        ),
        connectionId: 'conn-a',
        sessionId: 's1',
        requestId: 'r1',
        choice: 'once',
      );

      addPendingNotificationApproval(approval);
      addPendingNotificationApproval(approval);

      expect(pendingNotificationApprovals.value, hasLength(1));
    });

    test('keeps distinct requests and removes by identity', () {
      final first = PendingNotificationApproval(
        authority: fixtureApprovalAuthority(
          fixtureApprovalConnection('conn-a'),
        ),
        connectionId: 'conn-a',
        sessionId: 's1',
        requestId: 'r1',
        choice: 'once',
      );
      final second = PendingNotificationApproval(
        authority: fixtureApprovalAuthority(
          fixtureApprovalConnection('conn-a'),
        ),
        connectionId: 'conn-a',
        sessionId: 's1',
        requestId: 'r2',
        choice: 'deny',
      );

      addPendingNotificationApproval(first);
      addPendingNotificationApproval(second);
      expect(pendingNotificationApprovals.value, hasLength(2));

      removePendingNotificationApproval(first);
      expect(pendingNotificationApprovals.value, hasLength(1));
      expect(pendingNotificationApprovals.value.single.requestId, 'r2');
    });

    test('an identical session id on another connection is distinct', () {
      addPendingNotificationApproval(
        PendingNotificationApproval(
          authority: fixtureApprovalAuthority(
            fixtureApprovalConnection('conn-a'),
          ),
          connectionId: 'conn-a',
          sessionId: 's1',
          requestId: 'r1',
          choice: 'once',
        ),
      );
      addPendingNotificationApproval(
        PendingNotificationApproval(
          authority: fixtureApprovalAuthority(
            fixtureApprovalConnection('conn-b'),
          ),
          connectionId: 'conn-b',
          sessionId: 's1',
          requestId: 'r1',
          choice: 'once',
        ),
      );

      expect(pendingNotificationApprovals.value, hasLength(2));
    });
  });
}
