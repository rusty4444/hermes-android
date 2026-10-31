/// Combines observed turn outcomes with honest server activity hints.
library;

import '../l10n/l10n.dart';
import '../models/session.dart';
import '../services/operational_activity_store.dart';
import '../theme/hermes_theme.dart';
import 'activity_feed.dart';

/// Shared metadata authority for Home scans and Activity polling.
///
/// Allocate a read before starting I/O (not when subscribing to an existing
/// scan). Older responses may enrich unrelated lineages, but cannot overwrite
/// a newer title or resurrect an obsolete continuation. Missing OFFSET rows
/// never evict a chat or a locally observed turn.
class ActivitySessionCache {
  int _nextRead = 0;
  final _lineages = <String, ({Session session, int read})>{};
  final _rootsById = <String, String>{};

  int beginRead() => ++_nextRead;

  void merge(Iterable<Session> sessions, {required int read}) {
    final rows = sessions.toList(growable: false);
    for (final row in rows) {
      _rootsById[row.id] = row.lineageRootId ?? _rootsById[row.id] ?? row.id;
    }
    for (final entry in _canonicalSessions(rows).entries) {
      final previous = _lineages[entry.key];
      if (previous != null && previous.read > read) continue;
      final candidate = entry.value;
      // A root can be back-filled by pins or an older gateway. Once a
      // continuation is known, returning the root alone cannot undo it.
      final keepTip =
          previous != null &&
          previous.session.id != entry.key &&
          candidate.id == entry.key;
      _lineages[entry.key] = (
        session: keepTip ? previous.session : candidate,
        read: read,
      );
    }
  }

  Iterable<Session> get sessions => _lineages.values.map((row) => row.session);

  Map<String, String> get lineageRoots => Map.unmodifiable({
    for (final entry in _rootsById.entries)
      if (entry.key != entry.value) entry.key: entry.value,
  });

  Session? operator [](String id) => _lineages[_rootsById[id] ?? id]?.session;

  Map<String, String> get aliases => {
    for (final entry in _lineages.entries) entry.key: entry.value.session.id,
    for (final entry in _rootsById.entries)
      if (_lineages[entry.value] case final lineage?)
        entry.key: lineage.session.id,
  };

  Map<String, String> get titles {
    final byId = {for (final row in sessions) row.id: row.title.trim()};
    return Map.unmodifiable({
      for (final entry in aliases.entries)
        if (byId[entry.value] case final title? when title.isNotEmpty)
          entry.key: title,
    });
  }
}

/// Collapse before counting or suppressing server hints, independent of input
/// order. A continuation beats its obsolete root; competing tips from one
/// snapshot use activity then creation time and a deterministic id tie-break.
Map<String, Session> _canonicalSessions(Iterable<Session> sessions) {
  final result = <String, Session>{};
  for (final row in sessions) {
    final root = row.lineageRootId ?? row.id;
    final previous = result[root];
    if (previous == null || _compareSessionTips(row, previous, root) > 0) {
      result[root] = row;
    }
  }
  return result;
}

int _compareSessionTips(Session a, Session b, String root) {
  final continuation = (a.id != root ? 1 : 0).compareTo(b.id != root ? 1 : 0);
  if (continuation != 0) return continuation;
  double activity(Session row) {
    final value = row.lastActive > 0 ? row.lastActive : row.startedAt;
    return value.isFinite ? value : 0;
  }

  final recent = activity(a).compareTo(activity(b));
  if (recent != 0) return recent;
  final created = a.startedAt.compareTo(b.startedAt);
  return created != 0 ? created : a.id.compareTo(b.id);
}

ActivityFeed buildOperationalActivityFeed({
  required ActivityFeed journalFeed,
  required Iterable<OperationalActivityRecord> records,
  required Iterable<Session> sessions,
  required DateTime now,
  required AppLocalizations l10n,
  int groupLimit = kActivityGroupLimit,
  Map<String, String> journalSessionAliases = const {},
  Map<String, String> sessionAliases = const {},
  bool isPartial = false,
}) {
  if (groupLimit <= 0) throw ArgumentError.value(groupLimit, 'groupLimit');
  final buckets = <ActivityGroupKind, List<ActivityItem>>{
    for (final kind in ActivityGroupKind.values) kind: [],
  };
  final knownSessions = <String>{};
  final knownTurns = <String>{};
  final allSessionRows = sessions.toList(growable: false);
  final canonical = _canonicalSessions(allSessionRows);
  final sessionRows = canonical.values.toList(growable: false);
  final byId = <String, Session>{
    ...canonical,
    for (final session in allSessionRows)
      session.id: canonical[session.lineageRootId ?? session.id]!,
  };
  Session? resolve(String? id) => byId[sessionAliases[id] ?? id];
  for (final group in journalFeed.groups) {
    for (final item in group.items) {
      final storedId = journalSessionAliases[item.sessionId];
      final session = resolve(storedId) ?? resolve(item.sessionId);
      final sessionId = session?.id ?? storedId ?? item.sessionId;
      buckets[group.kind]!.add(
        ActivityItem(
          sessionId: sessionId,
          clientTurnId: item.clientTurnId,
          turnId: item.turnId,
          title: session?.title ?? item.title,
          label: item.label,
          status: item.status,
          statusLabel: item.statusLabel,
          updatedAt: item.updatedAt,
        ),
      );
      knownSessions.addAll([item.sessionId, sessionId, ?storedId]);
      knownTurns.add(item.clientTurnId);
      if (item.turnId != null) knownTurns.add(item.turnId!);
    }
  }
  final floor = now.subtract(kActivityCompletedWindow).millisecondsSinceEpoch;
  for (final record in records) {
    if (knownTurns.contains(record.turnId)) continue;
    // Unresolved work must remain discoverable, even after a long outage.
    final unresolved = const {
      OperationalActivityState.submitted,
      OperationalActivityState.running,
      OperationalActivityState.needsInput,
      OperationalActivityState.reconciling,
    }.contains(record.state);
    if (!unresolved && record.updatedAtEpochMs < floor) continue;
    final session =
        resolve(record.storedSessionId) ??
        resolve(record.lineageRootId) ??
        resolve(record.localSessionId);
    final sessionId =
        session?.id ??
        record.lineageRootId ??
        record.storedSessionId ??
        record.localSessionId;
    knownSessions.addAll([
      sessionId,
      record.localSessionId,
      if (record.storedSessionId != null) record.storedSessionId!,
    ]);
    knownTurns.add(record.turnId);
    var (kind, status, label) = switch (record.state) {
      OperationalActivityState.submitted => (
        ActivityGroupKind.running,
        HermesStatus.running,
        l10n.submitted_waiting_for_hermes,
      ),
      OperationalActivityState.running => (
        ActivityGroupKind.running,
        HermesStatus.running,
        l10n.status_running,
      ),
      OperationalActivityState.needsInput => (
        ActivityGroupKind.needsYou,
        HermesStatus.blocked,
        l10n.waiting_for_your_input,
      ),
      OperationalActivityState.reconciling => (
        ActivityGroupKind.unconfirmed,
        HermesStatus.idle,
        l10n.activity_reconnecting,
      ),
      OperationalActivityState.unknown => (
        ActivityGroupKind.unconfirmed,
        HermesStatus.idle,
        l10n.activity_outcome_unknown,
      ),
      OperationalActivityState.completed => (
        ActivityGroupKind.completed,
        HermesStatus.completed,
        l10n.status_completed,
      ),
      OperationalActivityState.failed => (
        ActivityGroupKind.failed,
        HermesStatus.failed,
        l10n.the_turn_failed,
      ),
    };
    // An old local running receipt is not proof the server is still running.
    if ((record.state == OperationalActivityState.running ||
            record.state == OperationalActivityState.submitted) &&
        now.millisecondsSinceEpoch - record.updatedAtEpochMs >
            kActivityRunningStaleAfter.inMilliseconds) {
      kind = ActivityGroupKind.unconfirmed;
      status = HermesStatus.idle;
      label = l10n.activity_outcome_unknown;
    }
    buckets[kind]!.add(
      ActivityItem(
        sessionId: sessionId,
        clientTurnId: record.turnId,
        turnId: record.turnId,
        title: session?.title,
        label: label,
        status: status,
        statusLabel: kind == ActivityGroupKind.unconfirmed
            ? l10n.activity_status_unconfirmed
            : null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(record.updatedAtEpochMs),
      ),
    );
  }
  for (final session in sessionRows) {
    if (session.isLocalDraft ||
        session.messageCount <= 0 ||
        knownSessions.contains(session.id) ||
        knownSessions.contains(session.lineageRootId)) {
      continue;
    }
    final seconds = session.lastActive > 0
        ? session.lastActive
        : session.startedAt;
    if (!seconds.isFinite || seconds <= 0) continue;
    final at = (seconds * 1000).round();
    if (at < floor) continue;
    knownSessions.add(session.id);
    buckets[ActivityGroupKind.recentlyUpdated]!.add(
      ActivityItem(
        sessionId: session.id,
        clientTurnId: 'session-update:${session.id}',
        title: session.title,
        label: l10n.activity_chat_updated_detail,
        status: HermesStatus.idle,
        statusLabel: l10n.activity_updated,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(at),
      ),
    );
  }
  final groups = <ActivityGroup>[];
  for (final kind in ActivityGroupKind.values) {
    final items = buckets[kind]!;
    if (items.isEmpty) continue;
    items.sort((a, b) {
      final time = b.updatedAt.compareTo(a.updatedAt);
      return time != 0 ? time : a.clientTurnId.compareTo(b.clientTurnId);
    });
    groups.add(
      ActivityGroup(
        kind: kind,
        items: List.unmodifiable(items.take(groupLimit)),
        totalCount: items.length,
      ),
    );
  }
  return ActivityFeed(
    groups: List.unmodifiable(groups),
    blockedCount: buckets[ActivityGroupKind.needsYou]!.length,
    runningCount: buckets[ActivityGroupKind.running]!.length,
    isPartial: isPartial || journalFeed.isPartial,
  );
}
