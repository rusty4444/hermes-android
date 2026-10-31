/// An inert [GatewayTurnApplicationSession] for widget tests.
///
/// Mounting `ChatScreen` builds a turn application session eagerly, so a test
/// that only cares about *which* controller a screen was handed still needs a
/// session that does nothing rather than one that throws. Every write path
/// throws [UnimplementedError] on purpose: a test that reaches one is asking
/// for behaviour this fake deliberately does not model.
library;

import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';

class InertTurnApplicationSession implements GatewayTurnApplicationSession {
  bool closed = false;

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
  Object setSessionBoundListener(
    String localSessionId,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();

  @override
  void removeSessionBoundListener(String localSessionId, Object registration) {}

  @override
  bool get hasActiveTurn => false;

  @override
  Object addTurnActivityListener(void Function() listener) => Object();

  @override
  void removeTurnActivityListener(Object token) {}

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) async => const <GatewayTurnRecoveryState>[];

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => throw UnimplementedError();

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
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) => throw UnimplementedError();
}
