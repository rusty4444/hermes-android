import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';

void main() {
  test('retains one session across screen remounts until app close', () async {
    final created = <_FakeApplicationSession>[];
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) {
        final session = _FakeApplicationSession();
        created.add(session);
        return session;
      },
    );
    final connection = _connection();

    final firstScreenLease = controller.sessionFor(connection);
    final remountedScreenLease = controller.sessionFor(_connection());

    expect(identical(firstScreenLease, remountedScreenLease), isTrue);
    expect(controller.retainedSessionCount, 1);
    expect(created, hasLength(1));
    expect(created.single.closeCount, 0);

    await controller.close();
    await controller.close();
    expect(created.single.closeCount, 1);
    expect(controller.retainedSessionCount, 0);
    expect(() => controller.sessionFor(connection), throwsStateError);
  });

  test('changed credentials create a distinct application scope', () async {
    final created = <_FakeApplicationSession>[];
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) {
        final session = _FakeApplicationSession();
        created.add(session);
        return session;
      },
    );

    final original = controller.sessionFor(_connection());
    final changed = controller.sessionFor(_connection(apiKey: 'rotated-key'));

    expect(identical(original, changed), isFalse);
    expect(controller.retainedSessionCount, 2);
    await controller.close();
    expect(created.map((session) => session.closeCount), everyElement(1));
  });

  test(
    'aggregates active turns and forwards activity across sessions',
    () async {
      final created = <_FakeApplicationSession>[];
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) {
          final session = _FakeApplicationSession();
          created.add(session);
          return session;
        },
      );
      // A session created before the app-level listener must still forward.
      final early =
          controller.sessionFor(_connection()) as _FakeApplicationSession;
      var notifications = 0;
      final token = controller.addTurnActivityListener(() => notifications++);

      early.activeTurn = true;
      early.fireActivity();
      expect(controller.hasActiveTurn, isTrue);
      expect(notifications, 1);

      early.activeTurn = false;
      early.fireActivity();
      expect(controller.hasActiveTurn, isFalse);
      expect(notifications, 2);

      // A session created after the listener must forward too.
      final late =
          controller.sessionFor(_connection(apiKey: 'other'))
              as _FakeApplicationSession;
      late.activeTurn = true;
      late.fireActivity();
      expect(controller.hasActiveTurn, isTrue);
      expect(notifications, 3);

      controller.removeTurnActivityListener(token);
      late.activeTurn = false;
      late.fireActivity();
      expect(notifications, 3);
      expect(controller.hasActiveTurn, isFalse);

      // Re-adding must not double-register the sessions' forwarders: one
      // session firing must yield exactly one app-level notification.
      var readded = 0;
      final token2 = controller.addTurnActivityListener(() => readded++);
      late.activeTurn = true;
      late.fireActivity();
      expect(readded, 1);
      controller.removeTurnActivityListener(token2);
      await controller.close();
    },
  );

  test(
    'close notifies a false aggregate with legacy and recovery turns',
    () async {
      final controller = GatewayTurnApplicationController(
        sessionFactory: (_) => _FakeApplicationSession(),
      );
      final recovery =
          controller.sessionFor(_connection()) as _FakeApplicationSession;
      recovery.activeTurn = true;
      final legacy = controller.beginLegacyTurn();
      final observed = <bool>[];
      controller.addTurnActivityListener(
        () => observed.add(controller.hasActiveTurn),
      );

      await controller.close();
      expect(observed, [false]);
      expect(controller.hasActiveTurn, isFalse);
      controller.endLegacyTurn(legacy);
      expect(observed, [false]);
    },
  );

  test('activity notifications carry the app-wide aggregate, not the '
      'firing session', () async {
    // Pins the main.dart closure contract: the keep-alive recomputes
    // controller.hasActiveTurn inside the listener. If a regression wired
    // the per-session value instead, session A settling would read false
    // while session B still streams — stopping the service mid-turn.
    final controller = GatewayTurnApplicationController(
      sessionFactory: (_) => _FakeApplicationSession(),
    );
    final sessionA =
        controller.sessionFor(_connection()) as _FakeApplicationSession;
    final sessionB =
        controller.sessionFor(_connection(apiKey: 'second-key'))
            as _FakeApplicationSession;
    sessionA.activeTurn = true;
    sessionB.activeTurn = true;

    final seen = <bool>[];
    controller.addTurnActivityListener(
      () => seen.add(controller.hasActiveTurn),
    );

    sessionA.activeTurn = false;
    sessionA.fireActivity();
    expect(seen, [true]); // B still unresolved: aggregate stays active

    sessionB.activeTurn = false;
    sessionB.fireActivity();
    expect(seen, [true, false]);
    await controller.close();
  });
}

SavedConnection _connection({String apiKey = 'secret'}) => SavedConnection(
  id: 'remote-profile',
  label: 'Remote',
  host: '127.0.0.1',
  port: 8642,
  apiKey: apiKey,
  desktopGatewayUrl: 'ws://127.0.0.1:8643/ws',
  dashboardUsername: 'operator',
  dashboardPassword: 'dashboard-secret',
);

class _FakeApplicationSession implements GatewayTurnApplicationSession {
  int closeCount = 0;
  bool activeTurn = false;
  final List<void Function()> activityListeners = [];

  @override
  bool get hasActiveTurn => activeTurn;

  @override
  Object addTurnActivityListener(void Function() listener) {
    activityListeners.add(listener);
    return listener;
  }

  @override
  void removeTurnActivityListener(Object token) =>
      activityListeners.remove(token);

  void fireActivity() {
    for (final listener in activityListeners.toList()) {
      listener();
    }
  }

  @override
  Object setAsyncEventListener(
    String localSessionId,
    DesktopAsyncEventCallback listener,
  ) => Object();

  @override
  void removeAsyncEventListener(String localSessionId, Object registration) {}

  @override
  Object setTurnSettledListener(
    String localSessionId,
    GatewayTurnSettledCallback listener,
  ) => Object();

  @override
  void removeTurnSettledListener(String localSessionId, Object registration) {}

  @override
  bool ownsApprovalRequest({
    required String sessionId,
    required String requestId,
  }) => false;

  @override
  Future<bool> tryRespondToApproval({
    required String sessionId,
    required String choice,
    String? requestId,
  }) async => false;

  @override
  Future<bool> tryRespondToClarify({
    required String requestId,
    required String answer,
    String? questionId,
  }) async => false;

  @override
  Future<bool> tryRespondToSudo({
    required String requestId,
    required String password,
  }) async => false;

  @override
  Future<bool> tryRespondToSecret({
    required String requestId,
    required String value,
  }) async => false;

  @override
  Future<void> close() async => closeCount++;

  @override
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {}

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) => throw UnimplementedError();

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) => throw UnimplementedError();

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();
}
