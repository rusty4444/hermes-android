/// The Activity destination pane.
///
/// Draws the operational timeline produced by [buildActivityFeed]: what needs
/// the user, what is running, what failed, what finished — in that order. The
/// grouping rules live in the pure helper; this file owns only the
/// presentation and the four states Phase 1 acceptance requires (loading,
/// empty, offline, error).
///
/// Two behaviours are deliberate rather than incidental, and match [HomePane]
/// on purpose so the two screens never disagree about the same failure:
///
/// 1. **A later failure never blanks Activity.** Once a read has succeeded, a
///    failing refresh keeps the last known timeline behind an offline notice.
///    Only a *first* read with nothing to show becomes an error screen.
/// 2. **Nothing is silently hidden.** A group capped by
///    [kActivityGroupLimit] says how many rows it hid, and an untitled turn
///    still draws a row — the journal is the truth about work, so a turn whose
///    chat is missing from the session list is still real.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/hermes_theme.dart';
import '../utils/activity_feed.dart';
import 'hermes_components.dart';
import 'hermes_shell.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Reads the timeline. Injectable so the pane can be tested — and later
/// re-pointed at a cache or a gateway feed — without reaching for a journal.
typedef ActivityFeedLoader = Future<ActivityFeed> Function();

/// Supplies "now", so the elapsed-time labels stay assertable.
typedef ActivityClock = DateTime Function();

class ActivityPane extends StatefulWidget {
  final ActivityFeedLoader loadFeed;

  /// When true, this pane becomes the action Inbox: only blocked and failed
  /// work is shown. Running and completed work remain available in Activity.
  final bool actionableOnly;

  /// Called when the user taps a row. When null, rows are drawn inert rather
  /// than looking tappable and doing nothing.
  final ValueChanged<ActivityItem>? onOpenItem;

  final ActivityClock? clock;
  final Duration? refreshInterval;

  /// Standalone hosts may suppress polling without disposing retained state.
  final bool active;

  const ActivityPane({
    required this.loadFeed,
    this.actionableOnly = false,
    this.onOpenItem,
    this.clock,
    this.refreshInterval,
    this.active = true,
    super.key,
  });

  @override
  State<ActivityPane> createState() => ActivityPaneState();
}

class ActivityPaneState extends State<ActivityPane>
    with WidgetsBindingObserver {
  /// The last successful read. `null` until one lands, which is exactly the
  /// condition for showing the skeleton.
  ActivityFeed? _feed;

  /// Set when the most recent read failed. Combined with [_feed] it tells
  /// stale-but-usable apart from nothing-to-show.
  Object? _error;

  bool _loading = false;
  Future<void>? _flight;
  ActivityFeedLoader? _queuedLoader;
  bool _queuedFullRefresh = false;
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Re-reads the timeline.
  ///
  /// Public so a host can refresh Activity after the user acts elsewhere —
  /// coming back from a chat to a row that still claims the turn is blocked
  /// would be worse than a spinner.
  Future<void> refresh({ActivityFeedLoader? loader}) {
    // Local observer updates are automatic; manual refresh remains explicit.
    if (loader != null && !_visible) return Future<void>.value();
    return _load(loader: loader);
  }

  void _syncVisibility({bool resetTimer = false}) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final visible =
        widget.active &&
        HermesPaneVisibility.of(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    final becameVisible = visible && !_visible;
    if (visible == _visible && !resetTimer) return;
    _visible = visible;
    _timer?.cancel();
    _timer = null;
    if (!visible) {
      // A queued automatic read must not start underneath another destination.
      _queuedLoader = null;
      _queuedFullRefresh = false;
      return;
    }
    if (becameVisible) unawaited(_load());
    final interval = widget.refreshInterval;
    if (interval != null && interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) {
        if (_visible && !_loading) unawaited(_load());
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncVisibility();

  @override
  void didUpdateWidget(ActivityPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVisibility(
      resetTimer: oldWidget.refreshInterval != widget.refreshInterval,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({ActivityFeedLoader? loader}) {
    final active = _flight;
    if (active != null) {
      if (loader == null) {
        _queuedFullRefresh = true;
        _queuedLoader = widget.loadFeed;
      } else if (!_queuedFullRefresh) {
        _queuedLoader = loader;
      }
      return active;
    }
    final future = _drain(loader ?? widget.loadFeed);
    _flight = future;
    future.whenComplete(() {
      if (identical(_flight, future)) _flight = null;
    });
    return future;
  }

  Future<void> _drain(ActivityFeedLoader loader) async {
    setState(() => _loading = true);
    do {
      _queuedLoader = null;
      _queuedFullRefresh = false;
      try {
        final feed = await loader();
        if (!mounted) return;
        setState(() {
          _feed = feed;
          _error = null;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = error);
      }
      loader = _queuedLoader ?? loader;
    } while (mounted && _queuedLoader != null);
    if (mounted) setState(() => _loading = false);
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final feed = _feed;

    if (feed == null) {
      if (_error != null) {
        return ErrorState(
          title: context.l10n.could_not_read_activity,
          message: context.l10n.activity_read_error,
          onRetry: _load,
        );
      }
      return const Padding(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    final unavailable = _error != null || feed.isStale;
    final groups = widget.actionableOnly
        ? feed.groups
              .where(
                (group) =>
                    group.kind == ActivityGroupKind.needsYou ||
                    group.kind == ActivityGroupKind.failed,
              )
              .toList(growable: false)
        : feed.groups;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: HermesSpacing.xxl),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (unavailable) const _OfflineBanner(),
          if (feed.isPartial)
            Padding(
              padding: const EdgeInsets.all(HermesSpacing.lg),
              child: Text(context.l10n.activity_partial_detail),
            ),
          if (groups.isEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.sizeOf(context).height * 0.12,
              ),
              child: EmptyState(
                icon: widget.actionableOnly
                    ? Icons.inbox_outlined
                    : Icons.bolt_outlined,
                title: unavailable
                    ? context.l10n.could_not_read_activity
                    : feed.isPartial
                    ? context.l10n.activity_partial_title
                    : widget.actionableOnly
                    ? context.l10n.inbox_is_clear
                    : context.l10n.activity_empty_title,
                message: unavailable
                    ? context.l10n.activity_read_error
                    : feed.isPartial
                    ? context.l10n.activity_partial_detail
                    : widget.actionableOnly
                    ? context.l10n.no_turn_needs_your_input_or_has_failed
                    : context.l10n.activity_empty_detail,
              ),
            )
          else
            for (final group in groups)
              ..._group(group, partial: feed.isPartial),
        ],
      ),
    );
  }

  List<Widget> _group(ActivityGroup group, {required bool partial}) {
    return [
      SectionHeader(
        title: group.title(context.l10n),
        count: partial && group.kind == ActivityGroupKind.recentlyUpdated
            ? null
            : group.totalCount,
      ),
      for (final item in group.items)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            HermesSpacing.lg,
            0,
            HermesSpacing.lg,
            HermesSpacing.md,
          ),
          child: _ActivityItemCard(
            item: item,
            now: _now,
            onTap: widget.onOpenItem == null
                ? null
                : () => widget.onOpenItem!(item),
          ),
        ),
      if (group.overflow > 0) _OverflowNote(count: group.overflow),
    ];
  }
}

/// Says how many rows a cap hid, so Activity never quietly loses work.
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

class _ActivityItemCard extends StatelessWidget {
  final ActivityItem item;
  final DateTime now;
  final VoidCallback? onTap;

  const _ActivityItemCard({required this.item, required this.now, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final title = item.title?.trim();

    return HermesCard(
      onTap: onTap,
      // Only work that needs the user or broke is tinted: tinting every row
      // would make none of them read as urgent.
      status:
          item.status == HermesStatus.blocked ||
              item.status == HermesStatus.failed
          ? item.status
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title == null || title.isEmpty
                      ? context.l10n.untitled_chat
                      : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.section.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: HermesSpacing.sm),
              StatusChip(status: item.status, label: item.statusLabel),
            ],
          ),
          const SizedBox(height: HermesSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typography.body.copyWith(
                    color: tokens.colorForStatus(item.status),
                  ),
                ),
              ),
              const SizedBox(width: HermesSpacing.sm),
              Text(
                formatActivityAge(context.l10n, item.updatedAt, now),
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// How long ago [updatedAt] happened, in the compact form a timeline row uses.
///
/// A blocked row without an elapsed time is not actionable, so this is a
/// first-class part of the presentation rather than a decoration. A timestamp
/// ahead of [now] — a skewed device clock — reads as `now` rather than as a
/// negative duration.
String formatActivityAge(
  AppLocalizations l10n,
  DateTime updatedAt,
  DateTime now,
) {
  final elapsed = now.difference(updatedAt);
  if (elapsed.isNegative || elapsed.inMinutes < 1) return l10n.now_label;
  if (elapsed.inMinutes < 60) return l10n.minutes_ago(elapsed.inMinutes);
  if (elapsed.inHours < 24) return l10n.hours_ago(elapsed.inHours);
  return l10n.days_ago(elapsed.inDays);
}
