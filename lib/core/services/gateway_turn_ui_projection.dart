import '../models/gateway_turn_contract.dart';
import 'gateway_turn_recovery.dart';

/// Idempotent presentation projection of one authoritative recovery state.
///
/// The UI can recompute this value for duplicate callbacks, replay pages, or a
/// terminal snapshot. No reducer cursor or payload is persisted here.
class GatewayTurnUiProjection {
  final String clientTurnId;
  final String? turnId;
  final String? messageId;
  final String assistantText;
  final GatewayRecoveryTurnStatus? status;
  final GatewayTurnRecoveryFailure? failure;
  final int lastSeq;
  final int? finalMessageRef;
  final String? attachmentManifestDigest;
  final DateTime? receivedAt;

  const GatewayTurnUiProjection({
    required this.clientTurnId,
    required this.turnId,
    required this.messageId,
    required this.assistantText,
    required this.status,
    required this.failure,
    required this.lastSeq,
    required this.finalMessageRef,
    required this.attachmentManifestDigest,
    this.receivedAt,
  });

  bool get isTerminal => status?.isTerminal == true;

  bool get isFailClosed => failure != null;

  bool get isActive => !isTerminal && !isFailClosed;

  bool get hasAssistantMaterial => messageId != null;

  static GatewayTurnUiProjection fromState(GatewayTurnRecoveryState state) {
    final snapshot = state.snapshot;
    if (snapshot != null) {
      return GatewayTurnUiProjection(
        clientTurnId: state.clientTurnId,
        turnId: snapshot.turnId,
        messageId: snapshot.assistant.messageId,
        receivedAt: state.liveMessageId == snapshot.assistant.messageId
            ? state.liveReceivedAt
            : null,
        assistantText: snapshot.assistant.text,
        status: snapshot.status,
        failure: state.failure,
        lastSeq: snapshot.lastSeq,
        finalMessageRef: snapshot.finalMessageRef,
        attachmentManifestDigest: snapshot.attachmentManifestDigest,
      );
    }

    final terminalResult = state.terminalResult;
    if (terminalResult != null) {
      return GatewayTurnUiProjection(
        clientTurnId: state.clientTurnId,
        turnId: state.turnId,
        messageId: terminalResult.messageId,
        receivedAt: state.liveMessageId == terminalResult.messageId
            ? state.liveReceivedAt
            : null,
        assistantText: terminalResult.assistantText,
        status: state.status,
        failure: state.failure,
        lastSeq: state.lastSeq,
        finalMessageRef: null,
        attachmentManifestDigest: null,
      );
    }

    String? messageId;
    var assistantText = '';
    for (final event in state.events) {
      switch (event.type) {
        case 'message.start':
          if (messageId != event.messageId) assistantText = '';
          messageId = event.messageId;
          break;
        case 'message.delta':
          if (messageId != event.messageId) {
            messageId = event.messageId;
            assistantText = '';
          }
          assistantText += event.payload['text'] as String;
          break;
        case 'message.complete':
          messageId = event.messageId;
          assistantText = event.payload['text'] as String;
          break;
        case 'turn.status':
          break;
      }
    }
    return GatewayTurnUiProjection(
      clientTurnId: state.clientTurnId,
      turnId: state.turnId,
      messageId: messageId,
      receivedAt: state.liveMessageId == messageId
          ? state.liveReceivedAt
          : null,
      assistantText: assistantText,
      status: state.status,
      failure: state.failure,
      lastSeq: state.lastSeq,
      finalMessageRef: null,
      attachmentManifestDigest: null,
    );
  }
}
