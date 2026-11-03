import 'android_prompt_context.dart';

/// Pure history and scroll rules shared by [ChatScreen] and its tests.
List<Map<String, dynamic>> buildRestChatHistory(
  Iterable<Map<String, dynamic>> messages,
) {
  return [
    for (final message in messages)
      {
        'role': message['role'] ?? 'user',
        // A local SSE bubble holds plain text while the history reload is
        // pending. Reuse the actual prior request, not its display projection.
        'content':
            message['role'] == 'user' &&
                message.containsKey(AndroidPromptContext.wireContentKey)
            ? message[AndroidPromptContext.wireContentKey]
            : message['content'] ?? '',
      },
  ];
}

/// A request to align the chat with its current end.
class ChatScrollTarget {
  const ChatScrollTarget.end();
}

/// Owns one-shot opening alignment and sticky streaming auto-follow.
///
/// Opening a chat deliberately has no saved-offset path. The screen may run
/// the returned end alignment over several bounded layout frames, but refresh
/// and completion cannot arm it again.
class ChatScrollCoordinator {
  final double nearEndThreshold;
  bool _initialEndAlignmentConsumed = false;
  bool _streaming = false;
  bool _followStreaming = false;

  ChatScrollCoordinator({this.nearEndThreshold = 200});

  bool get initialEndAlignmentConsumed => _initialEndAlignmentConsumed;
  bool get shouldFollowStreaming => _streaming && _followStreaming;

  bool isNearEnd({required double pixels, required double maxScrollExtent}) {
    return pixels >= maxScrollExtent - nearEndThreshold;
  }

  /// Arms normal opening-at-end exactly once for this screen instance.
  ChatScrollTarget? consumeInitialEndAlignment() {
    if (_initialEndAlignmentConsumed) return null;
    _initialEndAlignmentConsumed = true;
    return const ChatScrollTarget.end();
  }

  void beginStreaming({required bool isNearEnd}) {
    _streaming = true;
    _followStreaming = isNearEnd;
  }

  /// Only direct user scrolling changes the sticky streaming-follow choice.
  void updateFromUserScroll({required bool isNearEnd}) {
    if (!_streaming) return;
    _followStreaming = isNearEnd;
  }

  ChatScrollTarget? streamingContentChanged() {
    return shouldFollowStreaming ? const ChatScrollTarget.end() : null;
  }

  /// Completes streaming without consulting any historical position.
  ChatScrollTarget? endStreaming() {
    final target = shouldFollowStreaming ? const ChatScrollTarget.end() : null;
    _streaming = false;
    _followStreaming = false;
    return target;
  }

  void cancelStreaming() {
    _streaming = false;
    _followStreaming = false;
  }
}

/// State for the floating end affordance and its new-message indicator.
///
/// The affordance has a generous visibility threshold, while unread state is
/// cleared only at the actual end (within [endTolerance]). Merely requesting a
/// jump never clears the indicator; the subsequent position update does.
class ChatEndAffordanceController {
  final double showThreshold;
  final double endTolerance;
  bool _isAtEnd = true;
  bool _isVisible = false;
  int _newMessageCount = 0;

  ChatEndAffordanceController({
    this.showThreshold = 200,
    this.endTolerance = 1,
  });

  bool get isAtEnd => _isAtEnd;
  bool get isVisible => _isVisible;
  int get newMessageCount => _newMessageCount;

  /// Returns whether observable affordance state changed.
  bool updatePosition({
    required double pixels,
    required double maxScrollExtent,
    bool clearUnreadAtEnd = true,
  }) {
    final previousAtEnd = _isAtEnd;
    final previousVisible = _isVisible;
    final previousCount = _newMessageCount;
    final distance = (maxScrollExtent - pixels).clamp(0, double.infinity);

    _isAtEnd = distance <= endTolerance;
    _isVisible = distance > showThreshold;
    if (_isAtEnd && clearUnreadAtEnd) _newMessageCount = 0;

    return previousAtEnd != _isAtEnd ||
        previousVisible != _isVisible ||
        previousCount != _newMessageCount;
  }

  /// Registers one newly materialized message, never individual stream deltas.
  ///
  /// Content that is already being followed will reach the end immediately and
  /// therefore does not briefly create unread state.
  bool registerMaterializedMessage({required bool willFollow}) {
    if (willFollow) return false;
    _newMessageCount += 1;
    return true;
  }
}
