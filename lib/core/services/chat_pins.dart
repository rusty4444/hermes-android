import '../models/session.dart';

/// Whether [session] belongs in the Pinned section. [Session.pinned] is the
/// server flag Hermes Desktop also uses; an archived chat is never shown as
/// pinned, matching Desktop, which clears the pin when archiving.
bool isPinnedChat(Session session) => session.pinned && !session.archived;

/// Pinned chats first, keeping the incoming (activity) order within each
/// group. The gateway back-fills pinned rows onto every page, so a row can
/// arrive twice; the first occurrence wins.
List<Session> orderPinnedChatsFirst(Iterable<Session> sessions) {
  final seen = <String>{};
  final rows = [
    for (final session in sessions)
      if (seen.add(session.id)) session,
  ];
  return [...rows.where(isPinnedChat), ...rows.where((s) => !isPinnedChat(s))];
}

typedef _ConfirmedPin = ({int revision, bool pinned, String? rootId});

/// Server-confirmed pin writes, for presentation reconciliation only.
///
/// A list read captures the caller's revision before its I/O. A write
/// confirmed after that point overrides the older read's flag, so a page
/// that was already in flight cannot undo the user's pin or unpin. Reads
/// that begin later stay authoritative, including pins changed on Hermes
/// Desktop or another device.
class ConfirmedChatPins {
  final _pins = <String, _ConfirmedPin>{};

  bool get isEmpty => _pins.isEmpty;

  static bool _matches(String id, _ConfirmedPin pin, Session row) =>
      row.id == id ||
      row.lineageRootId == id ||
      (pin.rootId != null &&
          (row.id == pin.rootId || row.lineageRootId == pin.rootId));

  /// Records [pinned] for [session]'s whole lineage at [revision].
  void record(Session session, bool pinned, int revision) {
    _pins.removeWhere((id, pin) => _matches(id, pin, session));
    _pins[session.id] = (
      revision: revision,
      pinned: pinned,
      rootId: session.lineageRootId,
    );
  }

  /// The newest confirmed flag for [row] written after [observedRevision].
  bool? pinnedAfter(Session row, int observedRevision) {
    _ConfirmedPin? latest;
    for (final entry in _pins.entries) {
      final pin = entry.value;
      if (pin.revision > observedRevision &&
          (latest == null || pin.revision > latest.revision) &&
          _matches(entry.key, pin, row)) {
        latest = pin;
      }
    }
    return latest?.pinned;
  }

  Session apply(Session row, int observedRevision) {
    final pinned = pinnedAfter(row, observedRevision);
    return pinned == null || pinned == row.pinned
        ? row
        : row.withPinned(pinned);
  }

  List<Session> applyAll(Iterable<Session> rows, int observedRevision) => [
    for (final row in rows) apply(row, observedRevision),
  ];
}
