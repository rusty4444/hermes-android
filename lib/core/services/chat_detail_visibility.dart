import 'package:shared_preferences/shared_preferences.dart';

/// How a secondary chat detail card (tool activity, reasoning) is shown.
///
/// [automatic] keeps the historical behavior: cards open while work is
/// running or when verbose output is requested. [collapsed] always starts the
/// card closed, and [hidden] removes it from the transcript display. None of
/// these choices alters the stored conversation; they only change rendering.
enum ChatDetailVisibility {
  automatic('auto', 'Auto'),
  collapsed('collapsed', 'Collapsed'),
  hidden('hidden', 'Hidden');

  const ChatDetailVisibility(this.storageValue, this.label);

  final String storageValue;
  final String label;

  bool get isHidden => this == ChatDetailVisibility.hidden;

  /// Initial expansion for a visible card, given what automatic mode would do.
  bool initiallyExpanded({required bool automatic}) =>
      this == ChatDetailVisibility.automatic && automatic;

  static ChatDetailVisibility fromStorage(String? value) {
    return ChatDetailVisibility.values.firstWhere(
      (visibility) => visibility.storageValue == value,
      orElse: () => ChatDetailVisibility.automatic,
    );
  }
}

/// App-wide display preferences for chat detail cards.
class ChatDetailVisibilityStore {
  ChatDetailVisibilityStore(this._preferences);

  static const toolActivityKey = 'chat_tool_activity_visibility';
  static const reasoningKey = 'chat_reasoning_visibility';

  final SharedPreferences _preferences;

  ChatDetailVisibility readToolActivity() =>
      ChatDetailVisibility.fromStorage(_preferences.getString(toolActivityKey));

  ChatDetailVisibility readReasoning() =>
      ChatDetailVisibility.fromStorage(_preferences.getString(reasoningKey));

  Future<void> saveToolActivity(ChatDetailVisibility visibility) =>
      _preferences.setString(toolActivityKey, visibility.storageValue);

  Future<void> saveReasoning(ChatDetailVisibility visibility) =>
      _preferences.setString(reasoningKey, visibility.storageValue);
}
