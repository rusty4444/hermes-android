import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/gateway_turn_ui_projection.dart';

const _clientTurnId = '123e4567-e89b-42d3-a456-426614174000';
const _turnId = 'turn-authoritative';
const _messageId = 'assistant-message';
const _manifestDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test(
    'recovery replay stays untimed; only live owner observations project',
    () {
      const event = GatewayTurnEvent(
        turnId: _turnId,
        seq: 1,
        messageId: _messageId,
        type: 'message.start',
        payload: {},
      );
      final replayed = _acceptedState().applyEvent(event);
      expect(GatewayTurnUiProjection.fromState(replayed).receivedAt, isNull);
      final observed = DateTime.utc(2024, 6, 15, 13, 5);
      final live = replayed.observeLiveMessage(_messageId, observed);
      final duplicate = live
          .applyEvent(event)
          .observeLiveMessage(_messageId, DateTime.utc(2026));
      expect(GatewayTurnUiProjection.fromState(duplicate).receivedAt, observed);
      final rehydrated = GatewayTurnRecoveryState.rehydrate(
        clientTurnId: duplicate.clientTurnId,
        turnId: duplicate.turnId,
        status: duplicate.status,
        lastSeq: duplicate.lastSeq,
        ackUncertain: false,
      );
      expect(rehydrated.liveReceivedAt, isNull);
      expect(GatewayTurnUiProjection.fromState(rehydrated).receivedAt, isNull);
    },
  );

  test('event projection is deterministic under duplicate replay', () {
    var state = _acceptedState();
    final events = <GatewayTurnEvent>[
      const GatewayTurnEvent(
        turnId: _turnId,
        seq: 1,
        messageId: _messageId,
        type: 'message.start',
        payload: {},
      ),
      const GatewayTurnEvent(
        turnId: _turnId,
        seq: 2,
        messageId: _messageId,
        type: 'message.delta',
        payload: {'text': 'Hello '},
      ),
      const GatewayTurnEvent(
        turnId: _turnId,
        seq: 3,
        messageId: _messageId,
        type: 'message.delta',
        payload: {'text': 'world'},
      ),
    ];
    for (final event in events) {
      state = state.applyEvent(event);
    }
    final beforeDuplicate = state;
    state = state.applyEvent(events.last);

    final first = GatewayTurnUiProjection.fromState(beforeDuplicate);
    final replayed = GatewayTurnUiProjection.fromState(state);
    expect(identical(beforeDuplicate, state), isTrue);
    expect(replayed.assistantText, 'Hello world');
    expect(replayed.messageId, _messageId);
    expect(replayed.lastSeq, 3);
    expect(replayed.isActive, isTrue);
    expect(replayed.assistantText, first.assistantText);
  });

  test('terminal snapshot replaces partial events authoritatively', () {
    var state = _acceptedState().applyEvent(
      const GatewayTurnEvent(
        turnId: _turnId,
        seq: 1,
        messageId: _messageId,
        type: 'message.start',
        payload: {},
      ),
    );
    final page = GatewayTurnReconcilePage.fromWire(
      {
        'automatic_resubmit': false,
        'mode': 'snapshot',
        'earliest_seq': 5,
        'last_seq': 8,
        'next_after_seq': 8,
        'has_more': false,
        'snapshot': {
          'turn_id': _turnId,
          'client_turn_id': _clientTurnId,
          'status': 'completed',
          'last_seq': 8,
          'assistant': {
            'message_id': _messageId,
            'text': 'Authoritative final answer',
            'complete': true,
          },
          'attachment_manifest_digest': _manifestDigest,
          'final_message_ref': 42,
        },
      },
      expectedAfterSeq: 1,
      expectedTurnId: _turnId,
      expectedClientTurnId: _clientTurnId,
    );
    expect(page, isNotNull);

    state = state.applyReconcilePage(page!);
    final projection = GatewayTurnUiProjection.fromState(state);

    expect(projection.assistantText, 'Authoritative final answer');
    expect(projection.isTerminal, isTrue);
    expect(projection.lastSeq, 8);
    expect(projection.finalMessageRef, 42);
    expect(projection.attachmentManifestDigest, _manifestDigest);
  });

  test('rehydrated terminal result projects after process recreation', () {
    final state = GatewayTurnRecoveryState.rehydrate(
      clientTurnId: _clientTurnId,
      turnId: _turnId,
      status: GatewayRecoveryTurnStatus.completed,
      lastSeq: 8,
      ackUncertain: false,
      terminalEventRecorded: true,
      terminalResult: GatewayTurnTerminalResult(
        messageId: _messageId,
        assistantText: 'Recovered from encrypted journal',
      ),
    );

    final projection = GatewayTurnUiProjection.fromState(state);
    expect(projection.messageId, _messageId);
    expect(projection.assistantText, 'Recovered from encrypted journal');
    expect(projection.isTerminal, isTrue);
  });
}

GatewayTurnRecoveryState _acceptedState() =>
    GatewayTurnRecoveryState.initial(
      clientTurnId: _clientTurnId,
    ).markSubmissionStarted().applyAck(
      const GatewayTurnAck(
        clientTurnId: _clientTurnId,
        turnId: _turnId,
        status: GatewayRecoveryTurnStatus.accepted,
        lastSeq: 0,
        created: true,
      ),
    );
