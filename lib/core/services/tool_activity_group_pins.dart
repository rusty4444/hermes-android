/// Remembers, per logical tool-activity group, whether the user opened or
/// closed its card.
///
/// The card cannot keep this in its own `State`. The chat list is a
/// `ListView.builder`: while a turn streams, assistant text is inserted ahead
/// of the trailing tool card, so the card is rebuilt at a different index, and
/// rows that scroll out of the viewport are evicted altogether. Either way the
/// `State` — and with it the tap — is discarded, and the card falls back to its
/// default expansion in the middle of the run the user wanted closed.
///
/// Keyed by the group id from `ChatToolActivityGroup`, the choice follows the
/// group instead of the slot it occupies.
class ToolActivityGroupPins {
  static const maxPins = 100;
  final Map<String, bool> _pins = <String, bool>{};
  final Map<String, String> _aliases = <String, String>{};

  /// The choice this user made for [groupId], or `null` if they never touched
  /// that card.
  bool? operator [](String groupId) => _pins[groupId];

  void pin(String groupId, bool expanded) {
    _pins.remove(groupId);
    _pins[groupId] = expanded;
    final alias = _aliases[groupId];
    if (alias != null) _put(alias, expanded);
    _trim();
  }

  /// Link an initially id-less activity to its later durable tool id. The
  /// alias is retained so a tap after the merge also follows history refresh.
  void alias(String groupId, String durableId) {
    if (groupId == durableId) return;
    _aliases.remove(groupId);
    _aliases[groupId] = durableId;
    final choice = _pins[groupId];
    if (choice != null && !_pins.containsKey(durableId)) {
      _put(durableId, choice);
    }
    _trim();
  }

  void _put(String id, bool expanded) {
    _pins.remove(id);
    _pins[id] = expanded;
  }

  void _trim() {
    while (_pins.length > maxPins) {
      _pins.remove(_pins.keys.first);
    }
    while (_aliases.length > maxPins) {
      _aliases.remove(_aliases.keys.first);
    }
  }

  void mergeMissingFrom(ToolActivityGroupPins other) {
    for (final entry in other._pins.entries) {
      _pins.putIfAbsent(entry.key, () => entry.value);
    }
    for (final entry in other._aliases.entries) {
      _aliases.putIfAbsent(entry.key, () => entry.value);
    }
    _trim();
  }

  /// Share identity with another visit without importing its manual choices.
  void inheritAliasesFrom(ToolActivityGroupPins other) {
    for (final entry in other._aliases.entries) {
      alias(entry.key, entry.value);
    }
  }

  /// Forgets every choice, for when the conversation itself is replaced.
  void clear() {
    _pins.clear();
    _aliases.clear();
  }

  int get length => _pins.length;
}
