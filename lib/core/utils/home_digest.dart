/// The Home attention digest.
///
/// Phase 1 of `docs/ANDROID_DAILY_DRIVER_ROADMAP.md` replaces the flat session
/// list with an attention-first Home. This file owns the *decision* half of
/// that screen — which session belongs in which section, in what order, and
/// what got hidden — as a pure function, so the ranking rules are testable
/// without pumping a widget and stay stable when the visuals are reworked.
///
/// Two rules drive the shape:
///
/// 1. **Attention outranks everything.** A session that needs the user is
///    never also reported as merely running: it appears once, at the top.
/// 2. **Never silently swallow work.** A capped section reports its overflow
///    and its true total, so Home can say "and 5 more" instead of pretending
///    the rest does not exist.
library;

import 'package:hermes_android/core/l10n/l10n.dart';
import '../models/session.dart';
import '../theme/hermes_theme.dart';

/// A Home section, declared in descending attention rank.
enum HomeSectionKind {
  /// Hermes cannot continue without the user: approval, clarification,
  /// secret, sudo, or a blocked workflow.
  needsYou,

  /// A turn, subagent, or background job is actively progressing.
  running,

  /// Recently active durable conversations worth resuming.
  continueWorking,

  /// Work that finished inside the recent window.
  completedRecently;

  String title(AppLocalizations l10n) {
    switch (this) {
      case HomeSectionKind.needsYou:
        return l10n.needs_you;
      case HomeSectionKind.running:
        return l10n.running_now;
      case HomeSectionKind.continueWorking:
        return l10n.continue_working;
      case HomeSectionKind.completedRecently:
        return l10n.recently_completed;
    }
  }
}

/// One session as Home presents it.
class HomeItem {
  final Session session;
  final HermesStatus status;

  /// Why this session is blocked, when it is. `null` for every other status,
  /// so the UI never invents a reason.
  final String? attentionLabel;

  /// The owning project's name, when the session belongs to one.
  final String? projectName;

  /// The moment this session last did something: its end time when finished,
  /// otherwise its last activity (falling back to start time for older rows).
  final double activityAt;

  /// Recent server activity is not proof of a live turn. Home labels this
  /// separately from the journal-backed [HermesStatus.running] state.
  final bool recentlyActive;

  const HomeItem({
    required this.session,
    required this.status,
    required this.activityAt,
    this.recentlyActive = false,
    this.attentionLabel,
    this.projectName,
  });
}

/// One ranked group of [HomeItem]s.
class HomeSection {
  final HomeSectionKind kind;

  /// The visible items, already capped.
  final List<HomeItem> items;

  /// How many matching sessions exist in total, before the cap.
  final int totalCount;

  const HomeSection({
    required this.kind,
    required this.items,
    required this.totalCount,
  });

  String title(AppLocalizations l10n) => kind.title(l10n);

  /// How many matching sessions the cap hid.
  int get overflow => totalCount - items.length;
}

/// The whole Home screen's data.
class HomeDigest {
  final List<HomeSection> sections;

  /// How many sessions need the user, ignoring any section cap. Drives the
  /// shell's attention badge.
  final int blockedCount;

  const HomeDigest({required this.sections, required this.blockedCount});

  bool get isEmpty => sections.isEmpty;

  bool get needsAttention => blockedCount > 0;
}

/// How long an untouched unfinished session still counts as resumable.
const Duration kHomeContinueWindow = Duration(days: 14);

/// A recency hint, not a live-turn signal. Matches the API's five-minute
/// `is_active` heuristic without treating it as authoritative Running.
const Duration kHomeRecentlyActiveWindow = Duration(minutes: 5);

/// How long finished work stays on Home.
const Duration kHomeCompletedWindow = Duration(days: 7);

/// How many items a Home section shows before reporting an overflow.
const int kHomeSectionLimit = 5;

/// Builds the Home digest.
///
/// [attention] maps a session id to the reason it is blocked; [running] holds
/// the ids with journal-observed live work. The API's `is_active` only means
/// recent activity and cannot establish that a turn is currently running;
/// `session.active_list` is scoped to one gateway and misses other clients.
/// Ids that match no session are ignored rather than invented, so a stale
/// event can never conjure a phantom row.
///
/// [archived] holds the ids that have left the resumable views — in practice
/// the Quick chats past their 72 h deadline, per
/// [QuickChatState.archivedAt]. They are dropped from `Continue working` and
/// `Recently completed` only: a chat that is blocked or running is still
/// live work, and hiding it would suppress exactly what Home exists to
/// surface. Nothing is deleted; the chat remains readable in Archived.
HomeDigest buildHomeDigest({
  required Iterable<Session> sessions,
  required DateTime now,
  Map<String, String> attention = const {},
  Set<String> running = const {},
  Set<String> archived = const {},
  Map<String, String> projectNames = const {},
  Duration continueWindow = kHomeContinueWindow,
  Duration completedWindow = kHomeCompletedWindow,
  int sectionLimit = kHomeSectionLimit,
}) {
  if (sectionLimit <= 0) {
    throw ArgumentError.value(
      sectionLimit,
      'sectionLimit',
      'A Home section must be allowed to show at least one item',
    );
  }

  final nowSeconds = now.millisecondsSinceEpoch / 1000.0;
  final continueFloor = nowSeconds - continueWindow.inMilliseconds / 1000.0;
  final completedFloor = nowSeconds - completedWindow.inMilliseconds / 1000.0;

  final buckets = <HomeSectionKind, List<HomeItem>>{
    for (final kind in HomeSectionKind.values) kind: <HomeItem>[],
  };
  var blockedCount = 0;

  for (final session in sessions) {
    // Explicit server archiving is a deliberate user choice, unlike local
    // Quick Chat expiry (which still exempts blocked/running work below).
    if (session.archived || session.isUntitledCronShell) continue;
    final endedAt = session.endedAt;
    final finished = endedAt != null;
    final activityAt =
        endedAt ??
        (session.lastActive > 0 ? session.lastActive : session.startedAt);
    final reason = attention[session.id];

    if (reason != null) {
      // Blocked work is never aged out: it is the whole point of Home.
      blockedCount++;
      buckets[HomeSectionKind.needsYou]!.add(
        HomeItem(
          session: session,
          status: HermesStatus.blocked,
          activityAt: activityAt,
          attentionLabel: reason,
          projectName: projectNames[session.id],
        ),
      );
      continue;
    }

    if (running.contains(session.id)) {
      buckets[HomeSectionKind.running]!.add(
        HomeItem(
          session: session,
          status: HermesStatus.running,
          activityAt: activityAt,
          projectName: projectNames[session.id],
        ),
      );
      continue;
    }

    if (finished) {
      // An archived quick chat has left the resumable views by design.
      if (archived.contains(session.id)) continue;
      if (activityAt < completedFloor) continue;
      buckets[HomeSectionKind.completedRecently]!.add(
        HomeItem(
          session: session,
          status: HermesStatus.completed,
          activityAt: activityAt,
          projectName: projectNames[session.id],
        ),
      );
      continue;
    }

    if (archived.contains(session.id)) continue;
    if (activityAt < continueFloor) continue;
    buckets[HomeSectionKind.continueWorking]!.add(
      HomeItem(
        session: session,
        status: HermesStatus.idle,
        activityAt: activityAt,
        recentlyActive:
            activityAt <= nowSeconds &&
            activityAt >=
                nowSeconds - kHomeRecentlyActiveWindow.inMilliseconds / 1000.0,
        projectName: projectNames[session.id],
      ),
    );
  }

  final sections = <HomeSection>[];
  for (final kind in HomeSectionKind.values) {
    final items = buckets[kind]!;
    if (items.isEmpty) continue;
    items.sort((a, b) => b.activityAt.compareTo(a.activityAt));
    final total = items.length;
    sections.add(
      HomeSection(
        kind: kind,
        items: List.unmodifiable(
          items.length <= sectionLimit ? items : items.sublist(0, sectionLimit),
        ),
        totalCount: total,
      ),
    );
  }

  return HomeDigest(
    sections: List.unmodifiable(sections),
    blockedCount: blockedCount,
  );
}
