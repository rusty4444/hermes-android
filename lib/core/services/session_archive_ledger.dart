import '../models/session.dart';

/// Whether two listed IDs represent the same compression lineage.
bool sameSessionLineage(Session a, Session b) =>
    a.id == b.id ||
    a.lineageRootId == b.id ||
    b.lineageRootId == a.id ||
    (a.lineageRootId != null && a.lineageRootId == b.lineageRootId);

class ConfirmedSessionArchive {
  final int revision;
  final Session session;
  final bool archived;

  const ConfirmedSessionArchive(this.revision, this.session, this.archived);
}

/// Presentation reconciliation only; entries are recorded after server read-back.
/// A physical read captures [revision] before I/O. Older snapshots cannot undo
/// a confirmed mutation, while later snapshots remain authoritative (including
/// edits from another device).
class SessionArchiveLedger {
  int revision = 0;
  final _changes = <String, ConfirmedSessionArchive>{};
  final _aliases = <String, String>{};

  String _identity(String id) {
    final parent = _aliases[id];
    if (parent == null || parent == id) return id;
    return _aliases[id] = _identity(parent);
  }

  void _rememberIdentity(Session session) {
    final root = session.lineageRootId;
    if (root != null) _aliases[_identity(session.id)] = _identity(root);
  }

  bool sameConversation(Session a, Session b) {
    _rememberIdentity(a);
    _rememberIdentity(b);
    return _identity(a.id) == _identity(b.id);
  }

  Iterable<ConfirmedSessionArchive> changesSince(int observedRevision) {
    final latest = <String, ConfirmedSessionArchive>{};
    for (final change in _changes.values) {
      final key = _identity(change.session.id);
      if ((latest[key]?.revision ?? -1) < change.revision) latest[key] = change;
    }
    return latest.values.where((change) => change.revision > observedRevision);
  }

  void record(Session session, bool archived) {
    _rememberIdentity(session);
    final key = _identity(session.id);
    _changes.removeWhere((_, old) => _identity(old.session.id) == key);
    _changes[key] = ConfirmedSessionArchive(++revision, session, archived);
  }

  List<Session> apply(
    Iterable<Session> sessions,
    int observedRevision, {
    bool includeMissing = false,
  }) {
    final incoming = sessions.toList();
    for (final session in incoming) {
      _rememberIdentity(session);
    }
    final changes = changesSince(observedRevision).toList();
    final rows = <String, Session>{};
    for (var session in incoming) {
      final key = _identity(session.id);
      for (final change in changes) {
        if (key == _identity(change.session.id)) {
          session = session.withArchived(change.archived);
        }
      }
      final old = rows[key];
      if (old == null || old.id == session.id) {
        rows[key] = session;
      } else {
        // Independent transports can straddle compression. Keep one newest
        // continuation, not two actionable copies of the same conversation.
        final oldIsRoot =
            old.lineageRootId == null || old.id == old.lineageRootId;
        final newIsRoot =
            session.lineageRootId == null ||
            session.id == session.lineageRootId;
        final preferNew = oldIsRoot != newIsRoot
            ? oldIsRoot
            : session.startedAt != old.startedAt
            ? session.startedAt > old.startedAt
            : session.lastActive >= old.lastActive;
        rows[key] = (preferNew ? session : old).withArchived(
          old.archived || session.archived,
        );
      }
    }
    if (includeMissing) {
      for (final change in changes) {
        rows.putIfAbsent(
          _identity(change.session.id),
          () => change.session.withArchived(change.archived),
        );
      }
    }
    return rows.values.toList();
  }
}
