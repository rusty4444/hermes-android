import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide chat layout density, stored independently of profiles.
///
/// Bubble geometry lives on the enum so the chat list and the settings copy
/// read one source of truth: [ChatDensity.compact] drops the sender label and
/// tightens every inset that separates consecutive messages, which is what a
/// phone screen actually runs out of.
enum ChatDensity {
  comfortable('comfortable'),
  compact('compact');

  const ChatDensity(this.storageValue);

  static const preferenceKey = 'chat_density';

  final String storageValue;

  bool get isCompact => this == ChatDensity.compact;

  /// Alignment and bubble colour already identify the speaker, so the
  /// "You"/"Hermes" header only costs vertical space in compact mode.
  bool get showsSenderLabel => !isCompact;

  EdgeInsets get bubbleMargin => isCompact
      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 2)
      : const EdgeInsets.symmetric(horizontal: 16, vertical: 4);

  EdgeInsets get bubblePadding => isCompact
      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
      : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  double get bubbleRadius => isCompact ? 14 : 18;

  /// Horizontal room left free so consecutive bubbles stay visually distinct
  /// instead of spanning the full width.
  double get maxWidthInset => isCompact ? 48 : 80;

  /// Gap between the sender label and the message body.
  double get senderLabelGap => isCompact ? 0 : 6;

  /// Trailing gap inside the bubble, below the message body.
  double get bodyBottomGap => isCompact ? 0 : 4;

  /// Bottom padding of the message list itself.
  double get listEndPadding => isCompact ? 0 : 4;

  static ChatDensity fromStorage(String? value) {
    return ChatDensity.values.firstWhere(
      (density) => density.storageValue == value,
      orElse: () => ChatDensity.comfortable,
    );
  }
}

/// Current selection, broadcast so a chat that is already on screen re-lays out
/// the moment Settings changes it instead of waiting for the route to be
/// reopened.
final ValueNotifier<ChatDensity> chatDensitySelection = ValueNotifier(
  ChatDensity.comfortable,
);

/// Reads and writes [ChatDensity] in [SharedPreferences]. Both directions keep
/// [chatDensitySelection] in sync, so the store is the only thing callers need.
class ChatDensityStore {
  ChatDensityStore(this._preferences);

  final SharedPreferences _preferences;

  ChatDensity read() {
    final density = ChatDensity.fromStorage(
      _preferences.getString(ChatDensity.preferenceKey),
    );
    chatDensitySelection.value = density;
    return density;
  }

  Future<void> save(ChatDensity density) async {
    await _preferences.setString(
      ChatDensity.preferenceKey,
      density.storageValue,
    );
    chatDensitySelection.value = density;
  }
}
