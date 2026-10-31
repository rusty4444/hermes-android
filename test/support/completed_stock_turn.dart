import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/ws_client.dart';

/// These older fixtures model the entire completed transport operation, not a
/// bare RPC ack. Model a correlated lifecycle, not ambiguous ID-less terminal
/// evidence (which needs real resume/history and is covered by wire tests).
int _nextCompletedTurn = 0;

TestRemotePromptSubmit? completedStockTurn(TestRemotePromptSubmit? submit) {
  if (submit == null) return null;
  return ({
    required sessionId,
    required text,
    required onEvent,
    required onSent,
  }) async {
    final turn = 'completed-fixture-${_nextCompletedTurn++}';
    await submit(
      sessionId: sessionId,
      text: text,
      onEvent: onEvent,
      onSent: () {
        onSent();
        onEvent(
          StreamEvent(type: 'message.start', data: const {}, turnId: turn),
        );
      },
    );
    onEvent(
      StreamEvent(
        type: 'turn.end',
        data: const {'status': 'completed'},
        turnId: turn,
      ),
    );
  };
}
