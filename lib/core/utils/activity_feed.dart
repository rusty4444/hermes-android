/// The global Activity timeline.
///
/// Phase 1 of `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` asks for a global
/// operational timeline: what is running, what is blocked, what failed, what
/// finished. This file owns the *decision* half of that screen as a pure
/// function, so the grouping rules are testable without pumping a widget and
/// stay stable when the visuals are reworked.
///
/// Its source is the durable turn recovery journal — the same store
/// [buildHomeTurnSignals] reads. That is deliberate: the journal already
/// survives process death, already knows what every turn was doing, and
/// requires **no new gateway contract**, so a legacy REST connection keeps
/// working (it simply has no journal scope and reports nothing).
///
/// Four rules drive the shape, and each differs from Home on purpose:
///
/// 1. **One row per turn, not per chat.** Home deduplicates to a single row
///    per session because it ranks *chats*. Activity is a timeline of *work*,
///    so a chat that ran three jobs reports three rows.
/// 2. **Never silently lose work.** Home drops a stale running turn because
///    drawing it as live would be a lie. Activity cannot drop it — it reports
///    it as stalled, which is the honest statement.
/// 3. **A recovery failure outranks the server's status.** A turn the server
///    completed but the client could not reconcile leaves the composer
///    blocked; filing it under Completed would tell the user the opposite of
///    the truth.
/// 4. **Never invent a row or a title.** Entries with no binding, and bindings
///    from another connection or endpoint, are ignored; a turn whose chat is
///    absent from the session list keeps its row but has no title.
library;

import '../models/gateway_turn_contract.dart';
import '../services/gateway_turn_journal.dart';
import '../theme/hermes_theme.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// How long a running turn may go without a journal update before Activity
/// reports it as stalled instead of live.
///
/// Intentionally the same budget Home uses to hide a zombie turn: the two
/// screens must agree on what "still running" means, and only differ in what
/// they do about it.
const Duration kActivityRunningStaleAfter = Duration(minutes: 15);

/// How long finished work stays on the timeline.
const Duration kActivityCompletedWindow = Duration(days: 7);

/// How many rows a group shows before reporting an overflow.
const int kActivityGroupLimit = 20;

/// An Activity group, declared in descending attention rank.
enum ActivityGroupKind {
  /// Hermes cannot continue without the user.
  needsYou,

  /// A turn believed to still be progressing.
  running,

  /// Work that ended in an error, could not be recovered, or went silent.
  failed,

  /// Work that finished or was stopped by the user.
  completed,

  /// The transport is recovering, or a terminal outcome could not be proven.
  unconfirmed,

  /// Server session metadata proves activity, not a running/finished turn.
  recentlyUpdated;

  String title(AppLocalizations l10n) {
    switch (this) {
      case ActivityGroupKind.needsYou:
        return l10n.needs_you;
      case ActivityGroupKind.running:
        return l10n.running_now;
      case ActivityGroupKind.failed:
        return l10n.status_failed;
      case ActivityGroupKind.completed:
        return l10n.status_completed;
      case ActivityGroupKind.unconfirmed:
        return l10n.activity_status_unconfirmed;
      case ActivityGroupKind.recentlyUpdated:
        return l10n.activity_recently_updated;
    }
  }
}

/// One turn as Activity presents it.
class ActivityItem {
  /// The local chat this turn belongs to, so a row can open it.
  final String sessionId;

  /// The chat's title when the caller knows it, `null` otherwise. Never
  /// invented: the journal stores no prose.
  final String? title;

  /// The client-generated turn id. Stable across process death, so it is the
  /// honest key for a list row.
  final String clientTurnId;

  /// The gateway's turn id once it has acknowledged the submit.
  final String? turnId;

  /// What this turn is doing, in the user's words.
  final String label;

  final HermesStatus status;

  /// Metadata-only rows cannot honestly claim to be Idle or Running.
  final String? statusLabel;

  /// When the journal last heard about this turn.
  final DateTime updatedAt;

  const ActivityItem({
    required this.sessionId,
    required this.clientTurnId,
    required this.label,
    required this.status,
    required this.updatedAt,
    this.title,
    this.turnId,
    this.statusLabel,
  });
}

/// One ranked group of [ActivityItem]s.
class ActivityGroup {
  final ActivityGroupKind kind;

  /// The visible items, already capped.
  final List<ActivityItem> items;

  /// How many turns matched in total, before the cap.
  final int totalCount;

  const ActivityGroup({
    required this.kind,
    required this.items,
    required this.totalCount,
  });

  String title(AppLocalizations l10n) => kind.title(l10n);

  /// How many rows the cap hid.
  int get overflow => totalCount - items.length;
}

/// The whole Activity screen's data.
class ActivityFeed {
  final List<ActivityGroup> groups;

  /// How many turns need the user, ignoring any cap. Drives the shell badge.
  final int blockedCount;

  /// How many turns are believed live, ignoring any cap.
  final int runningCount;

  final bool isStale;

  /// The bounded server metadata scan cannot prove exhaustive absence/totals.
  final bool isPartial;

  const ActivityFeed({
    required this.groups,
    required this.blockedCount,
    required this.runningCount,
    this.isStale = false,
    this.isPartial = false,
  });

  bool get isEmpty => groups.isEmpty;
}

/// How Activity classifies one journal entry.
class _Classification {
  final ActivityGroupKind kind;
  final String label;
  final HermesStatus status;

  const _Classification(this.kind, this.label, this.status);
}

/// Builds the Activity feed from a journal [snapshot].
///
/// When [connectionId] and [endpointDigest] are supplied, only turns recorded
/// for that exact gateway scope are reported: a saved connection re-pointed at
/// a different endpoint must not resurrect the previous endpoint's work.
/// Passing `null` for either reads every scope, which is what a diagnostics
/// view wants.
///
/// [sessionTitles] maps a local session id to its chat title. Missing ids are
/// left untitled rather than given a placeholder, so the screen can decide how
/// to present work whose chat it has not loaded.
ActivityFeed buildActivityFeed({
  required GatewayTurnJournalSnapshot snapshot,
  required DateTime now,
  String? connectionId,
  String? endpointDigest,
  Map<String, String> sessionTitles = const {},
  Duration runningStaleAfter = kActivityRunningStaleAfter,
  Duration completedWindow = kActivityCompletedWindow,
  int groupLimit = kActivityGroupLimit,
}) {
  if (groupLimit <= 0) {
    throw ArgumentError.value(
      groupLimit,
      'groupLimit',
      'An Activity group must be allowed to show at least one item',
    );
  }

  final sessionForBinding = <String, String>{};
  for (final binding in snapshot.bindings) {
    if (connectionId != null && binding.connectionId != connectionId) continue;
    if (endpointDigest != null && binding.endpointDigest != endpointDigest) {
      continue;
    }
    sessionForBinding[binding.bindingIdentity] = binding.localSessionId;
  }
  if (sessionForBinding.isEmpty) {
    return const ActivityFeed(groups: [], blockedCount: 0, runningCount: 0);
  }

  final nowMs = now.millisecondsSinceEpoch;
  final staleMs = runningStaleAfter.inMilliseconds;
  final completedFloorMs = nowMs - completedWindow.inMilliseconds;

  final buckets = <ActivityGroupKind, List<ActivityItem>>{
    for (final kind in ActivityGroupKind.values) kind: <ActivityItem>[],
  };

  for (final entry in snapshot.entries) {
    final sessionId = sessionForBinding[entry.bindingIdentity];
    if (sessionId == null) continue;

    final classification = _classify(
      entry,
      ageMs: nowMs - entry.updatedAtEpochMs,
      staleMs: staleMs,
    );

    // Blocked work is never aged out — being stuck for a week is the strongest
    // possible reason to show a row. Everything else respects the window.
    if (classification.kind != ActivityGroupKind.needsYou &&
        entry.updatedAtEpochMs < completedFloorMs) {
      continue;
    }

    buckets[classification.kind]!.add(
      ActivityItem(
        sessionId: sessionId,
        title: sessionTitles[sessionId],
        clientTurnId: entry.clientTurnId,
        turnId: entry.turnId,
        label: classification.label,
        status: classification.status,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(entry.updatedAtEpochMs),
      ),
    );
  }

  final groups = <ActivityGroup>[];
  for (final kind in ActivityGroupKind.values) {
    final items = buckets[kind]!;
    if (items.isEmpty) continue;
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    groups.add(
      ActivityGroup(
        kind: kind,
        items: List.unmodifiable(
          items.length <= groupLimit ? items : items.sublist(0, groupLimit),
        ),
        totalCount: items.length,
      ),
    );
  }

  return ActivityFeed(
    groups: List.unmodifiable(groups),
    // Counted from the uncapped buckets: a badge must state how much work is
    // blocked, not how much of it happens to fit on screen.
    blockedCount: buckets[ActivityGroupKind.needsYou]!.length,
    runningCount: buckets[ActivityGroupKind.running]!.length,
  );
}

/// Where one journal entry belongs, and what the row says.
_Classification _classify(
  GatewayTurnJournalEntry entry, {
  required int ageMs,
  required int staleMs,
}) {
  // A recovery failure outranks the reported status: the turn may well have
  // completed server-side, but the client could not reconcile it and the
  // composer stays blocked, which is what the timeline must state.
  if (entry.failure != null) {
    return const _Classification(
      ActivityGroupKind.failed,
      'Turn recovery failed',
      HermesStatus.failed,
    );
  }

  switch (entry.status) {
    case GatewayRecoveryTurnStatus.waitingInput:
      return const _Classification(
        ActivityGroupKind.needsYou,
        'Waiting for your input',
        HermesStatus.blocked,
      );
    case GatewayRecoveryTurnStatus.failed:
      return const _Classification(
        ActivityGroupKind.failed,
        'The turn failed',
        HermesStatus.failed,
      );
    case GatewayRecoveryTurnStatus.completed:
      return const _Classification(
        ActivityGroupKind.completed,
        'Completed',
        HermesStatus.completed,
      );
    case GatewayRecoveryTurnStatus.interrupted:
      return const _Classification(
        ActivityGroupKind.completed,
        'Stopped',
        HermesStatus.idle,
      );
    case null:
    case GatewayRecoveryTurnStatus.accepted:
    case GatewayRecoveryTurnStatus.running:
      // A negative age means the device clock is behind the journal; trust the
      // journal rather than converting live work into a fabricated failure.
      if (ageMs > staleMs) {
        return const _Classification(
          ActivityGroupKind.failed,
          'Stalled — no update from Hermes',
          HermesStatus.failed,
        );
      }
      // A null status is deliberately in flight: the submit was written ahead
      // but the gateway has not answered yet, so the work is outstanding.
      return _Classification(
        ActivityGroupKind.running,
        entry.status == null ? 'Submitted, waiting for Hermes' : 'Running',
        HermesStatus.running,
      );
  }
}

/// Reads [journal] and builds the feed for one connection scope.
///
/// A journal that cannot be read degrades to an empty feed instead of
/// throwing: on a device where secure storage is unavailable, losing the
/// timeline is acceptable, crashing the screen is not.
Future<ActivityFeed> readActivityFeed({
  required GatewayTurnJournal journal,
  required String? connectionId,
  required String? endpointDigest,
  Map<String, String> sessionTitles = const {},
  DateTime? now,
  Duration runningStaleAfter = kActivityRunningStaleAfter,
  Duration completedWindow = kActivityCompletedWindow,
  int groupLimit = kActivityGroupLimit,
}) async {
  try {
    final snapshot = await journal.loadSnapshot();
    return buildActivityFeed(
      snapshot: snapshot,
      now: now ?? DateTime.now(),
      connectionId: connectionId,
      endpointDigest: endpointDigest,
      sessionTitles: sessionTitles,
      runningStaleAfter: runningStaleAfter,
      completedWindow: completedWindow,
      groupLimit: groupLimit,
    );
  } catch (_) {
    return const ActivityFeed(groups: [], blockedCount: 0, runningCount: 0);
  }
}
