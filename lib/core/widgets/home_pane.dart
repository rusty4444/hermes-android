/// The Home destination pane.
///
/// Draws the attention digest produced by [buildHomeDigest]: what needs the
/// user, what is running, what is worth resuming, what just finished — in that
/// order. The ranking rules live in the pure helper; this file owns only the
/// presentation and the four states Phase 1 acceptance requires (loading,
/// empty, offline, error).
///
/// Two behaviours are deliberate rather than incidental:
///
/// 1. **A later failure never blanks Home.** Once a read has succeeded, a
///    failing refresh keeps the last known digest behind an offline notice.
///    Only a *first* read with nothing to show is allowed to become an error
///    screen, because there is genuinely nothing else to draw.
/// 2. **Nothing is silently hidden.** A section capped by
///    [kHomeSectionLimit] says how many rows it hid.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/session_archive_ledger.dart';
import '../theme/hermes_theme.dart';
import '../utils/home_digest.dart';
import 'hermes_components.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Reads the sessions Home ranks. Injectable so the pane can be tested — and
/// later re-pointed at a cache — without reaching for a transport.
typedef HomeSessionsLoader = Future<List<Session>> Function();

/// Delivers a fast first slice, then replaces it with the complete scan.
/// A null update means the background scan failed; the first slice stays.
typedef HomeProgressiveSessionsLoader =
    Future<List<Session>> Function(
      void Function(List<Session>? sessions) onUpdate,
    );

/// Supplies "now". Injectable so window boundaries stay assertable.
typedef HomeClock = DateTime Function();

class HomePane extends StatefulWidget {
  final HomeSessionsLoader loadSessions;
  final HomeProgressiveSessionsLoader? loadProgressiveSessions;

  /// Session id to the reason it is blocked.
  final Map<String, String> attention;

  /// Session ids with work observed by this device's turn journal. Server
  /// recency is presented separately, never passed here as proof of Running.
  final Set<String> running;

  /// Session ids that have left the resumable views — the Quick chats past
  /// their retention deadline. Blocked and running work is exempt inside
  /// [buildHomeDigest], so this can never hide something that needs the user.
  final Set<String> archived;

  /// Session id to its owning project's name.
  final Map<String, String> projectNames;

  final ValueChanged<Session>? onOpenSession;

  final HomeClock? clock;

  const HomePane({
    required this.loadSessions,
    this.loadProgressiveSessions,
    this.attention = const {},
    this.running = const {},
    this.archived = const {},
    this.projectNames = const {},
    this.onOpenSession,
    this.clock,
    super.key,
  });

  @override
  State<HomePane> createState() => HomePaneState();
}

class HomePaneState extends State<HomePane> {
  /// The last successful read. `null` until one lands, which is exactly the
  /// condition for showing the skeleton.
  List<Session>? _sessions;
  final _archiveChanges = SessionArchiveLedger();

  /// Set when the most recent read failed. Combined with [_sessions] it tells
  /// stale-but-usable apart from nothing-to-show.
  Object? _error;

  bool _scanning = false;
  bool _scanFailed = false;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Re-reads the ranked sessions.
  ///
  /// Public so a host can refresh Home after the user acts elsewhere — coming
  /// back from a chat to a digest that still lists the work as blocked would
  /// be worse than a spinner.
  Future<void> refresh() => _load();

  /// Applies a confirmed menu action without waiting for another list scan.
  void reconcileArchive(Session session, bool archived) {
    if (!mounted) return;
    final before = _archiveChanges.revision;
    _archiveChanges.record(session, archived);
    setState(() {
      _sessions = _archiveChanges.apply(
        _sessions ?? const [],
        before,
        includeMissing: !archived,
      );
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final archiveRevision = _archiveChanges.revision;
    setState(() {
      _scanning = false;
      _scanFailed = false;
    });
    try {
      final progressive = widget.loadProgressiveSessions;
      final sessions = await (progressive == null
          ? widget.loadSessions()
          : progressive((updated) {
              if (!mounted || generation != _generation) return;
              setState(() {
                _scanning = false;
                _scanFailed = updated == null;
                if (updated != null) {
                  _sessions = _archiveChanges.apply(
                    updated,
                    archiveRevision,
                    includeMissing: true,
                  );
                }
              });
            }));
      if (!mounted || generation != _generation) return;
      setState(() {
        // A refresh must not briefly erase older blocked/running rows while
        // its first five are ready but the rest of the scan is still pending.
        final previous = _sessions;
        _sessions = progressive == null || previous == null
            ? _archiveChanges.apply(
                sessions,
                archiveRevision,
                includeMissing: true,
              )
            : _archiveChanges.apply(
                [
                  ...sessions,
                  ...previous.where(
                    (old) => !sessions.any((recent) => recent.id == old.id),
                  ),
                ],
                archiveRevision,
                includeMissing: true,
              );
        _error = null;
        _scanning = progressive != null;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
      });
    }
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;

    if (sessions == null) {
      if (_error != null) {
        return ErrorState(
          title: context.l10n.could_not_reach_hermes,
          message: context
              .l10n
              .home_needs_your_recent_chats_to_know_what_deserves_your,
          onRetry: _load,
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    final digest = buildHomeDigest(
      sessions: sessions,
      now: _now,
      attention: widget.attention,
      running: widget.running,
      archived: widget.archived,
      projectNames: widget.projectNames,
    );

    if (digest.isEmpty && _scanFailed) {
      return ErrorState(
        title: context.l10n.could_not_reach_hermes,
        message: context
            .l10n
            .home_needs_your_recent_chats_to_know_what_deserves_your,
        onRetry: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: HermesSpacing.xxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_error != null) const _OfflineBanner(),
          if (_scanning)
            Padding(
              padding: const EdgeInsets.all(HermesSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.loading),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          if (_scanFailed)
            Padding(
              padding: const EdgeInsets.all(HermesSpacing.lg),
              child: Text(context.l10n.could_not_reach_hermes),
            ),
          if (digest.isEmpty && !_scanning)
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.sizeOf(context).height * 0.12,
              ),
              child: EmptyState(
                icon: Icons.check_circle_outline,
                title: context.l10n.nothing_needs_you,
                message: context
                    .l10n
                    .no_chat_is_blocked_running_or_waiting_to_be_resumed,
              ),
            ),
          if (!digest.isEmpty)
            for (final section in digest.sections) ..._section(section),
        ],
      ),
    );
  }

  List<Widget> _section(HomeSection section) {
    return [
      SectionHeader(
        title: section.title(context.l10n),
        count: section.totalCount,
      ),
      for (final item in section.items)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            0,
            HermesSpacing.lg,
            HermesSpacing.md,
          ),
          child: _HomeItemCard(
            item: item,
            onTap: widget.onOpenSession == null
                ? null
                : () => widget.onOpenSession!(item.session),
          ),
        ),
      if (section.overflow > 0) _OverflowNote(count: section.overflow),
    ];
  }
}

/// Says how many rows a cap hid, so Home never quietly loses work.
class _OverflowNote extends StatelessWidget {
  final int count;

  const _OverflowNote({required this.count});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        0,
        HermesSpacing.lg,
        HermesSpacing.lg,
      ),
      child: Text(
        context.l10n.and_more(count),
        style: tokens.typography.label.copyWith(color: tokens.muted),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        HermesSpacing.lg,
        HermesSpacing.lg,
        0,
      ),
      child: HermesCard(
        status: HermesStatus.idle,
        padding: const EdgeInsets.all(HermesSpacing.md),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: tokens.muted),
            const SizedBox(width: HermesSpacing.sm),
            Expanded(
              child: Text(
                context.l10n.offline_showing_the_last_known_activity,
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeItemCard extends StatelessWidget {
  final HomeItem item;
  final VoidCallback? onTap;

  const _HomeItemCard({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final title = item.session.title.trim().isEmpty
        ? context.l10n.untitled_chat
        : item.session.title;
    final project = item.projectName;
    final reason = item.attentionLabel;

    return HermesCard(
      onTap: onTap,
      // Only blocked work is tinted: tinting every row would make none of
      // them read as urgent.
      status: item.status == HermesStatus.blocked ? item.status : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: HermesSpacing.sm),
              StatusChip(
                status: item.status,
                label: item.recentlyActive
                    ? context.l10n.recently_active
                    : null,
              ),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: HermesSpacing.xs),
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.body.copyWith(
                color: tokens.colorForStatus(HermesStatus.blocked),
              ),
            ),
          ],
          if (project != null) ...[
            const SizedBox(height: HermesSpacing.xs),
            Text(
              project,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.typography.label.copyWith(color: tokens.muted),
            ),
          ],
        ],
      ),
    );
  }
}
