/// The **Upcoming** half of the Workspace Crons destination.
///
/// Issue #259: the Crons tab listed cron *session rows* — finished runs — so a
/// job an agent had just scheduled was invisible until it first fired, and a
/// tab full of completed one-offs looked like nothing was scheduled at all.
/// This pane reads the scheduler's own job definitions from the existing
/// dashboard route (`GET /api/cron/jobs`, the same read `CronScreen` uses) and
/// shows what *will* run. Run output stays in the History view, and all
/// creation/editing stays in `CronScreen` — no second cron implementation.
///
/// Four behaviours are deliberate:
///
/// 1. **Explicit timezones.** The next-run value is rendered in the zone the
///    server expressed it in, labelled with that zone, and labelled
///    "timezone unknown" when the payload carries no zone at all. See
///    `utils/cron_schedule.dart`.
/// 2. **Capability honesty.** An API-server-only connection has no dashboard
///    cron route; it gets a calm "needs a Dashboard connection" explanation
///    that can never be confused with "no scheduled jobs".
/// 3. **No gateway traffic while hidden.** Reads start when the pane becomes
///    visible — selected destination, selected Upcoming/History view, current
///    route, foregrounded app — and the periodic refresh stops when it is not.
/// 4. **No stale rows across connections.** Every read is fenced by a
///    generation that a connection change bumps, and the rows are dropped at
///    the moment the connection changes rather than when the new read lands.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/connection_manager.dart';
import '../theme/hermes_theme.dart';
import '../utils/cron_schedule.dart';
import 'cron_schedule_labels.dart';
import 'hermes_components.dart';
import 'hermes_shell.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Reads cron job definitions. Injectable so the pane can be driven without a
/// live dashboard; the production path is [DashboardClient.getCronJobs].
typedef CronJobsLoader = Future<List<Map<String, dynamic>>> Function();

const Key kCronUpcomingListKey = Key('cron-upcoming-list');

class CronUpcomingPane extends StatefulWidget {
  /// The connection whose schedule is shown. A different instance refences
  /// every read, so the previous connection's jobs can never be reused.
  final SavedConnection connection;

  /// Overrides the read. When null the pane owns a [DashboardClient] built
  /// from [connection], exactly as `CronScreen` does.
  final CronJobsLoader? loadJobs;

  /// Injects the dashboard transport in tests.
  final http.Client? testDashboardHttpClient;

  /// Whether the host considers this pane selected. Combined with the shell's
  /// pane visibility, the current route, and the app lifecycle.
  final bool active;

  /// Periodic refresh while visible. Null disables it (the default tests use).
  final Duration? refreshInterval;

  /// Opens the full cron manager (`CronScreen`), which owns all editing.
  final VoidCallback? onOpenManager;

  const CronUpcomingPane({
    required this.connection,
    this.loadJobs,
    this.testDashboardHttpClient,
    this.active = true,
    this.refreshInterval,
    this.onOpenManager,
    super.key,
  });

  @override
  State<CronUpcomingPane> createState() => CronUpcomingPaneState();
}

class CronUpcomingPaneState extends State<CronUpcomingPane>
    with WidgetsBindingObserver {
  /// The last successful read, or null until one lands.
  List<Map<String, dynamic>>? _jobs;

  /// Set when the most recent read failed. With [_jobs] it distinguishes
  /// stale-but-usable from nothing-to-show.
  CronScheduleFailure? _failure;

  bool _loading = false;
  Future<void>? _flight;
  Timer? _timer;
  bool _visible = false;

  /// Fences reads against connection replacement and disposal.
  int _generation = 0;

  /// Null when the dashboard client could not be constructed (a bad TLS
  /// identity, for instance); the pane then reports an unreachable dashboard
  /// rather than crashing on build.
  DashboardClient? _client;
  Object? _clientError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openClient();
  }

  /// Builds the dashboard client inside the same safe boundary as the read:
  /// construction itself can throw on a malformed certificate or origin.
  void _openClient() {
    if (widget.loadJobs != null) return;
    try {
      _client = DashboardClient.fromConnection(
        widget.connection,
        httpClient: widget.testDashboardHttpClient,
      );
      _clientError = null;
    } catch (error) {
      _client = null;
      _clientError = error;
    }
  }

  @override
  void didUpdateWidget(CronUpcomingPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.connection, widget.connection)) {
      // Drop the previous connection's rows now, not when the new read
      // lands: a slow new read must never leave another server's schedule on
      // screen, and the old read's late answer is fenced out by generation.
      ++_generation;
      _client?.close();
      _client = null;
      setState(() {
        _jobs = null;
        _failure = null;
        _loading = false;
      });
      _flight = null;
      _openClient();
      if (_visible) unawaited(_load());
    }
    _syncVisibility(
      resetTimer: oldWidget.refreshInterval != widget.refreshInterval,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _syncVisibility();

  @override
  void dispose() {
    ++_generation;
    _timer?.cancel();
    _client?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// True only while this pane is really on screen.
  bool _computeVisible() {
    if (!widget.active) return false;
    if (!HermesPaneVisibility.of(context)) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  /// Starts polling only while visible, and refreshes on becoming visible —
  /// which covers both switching to Upcoming and resuming the app.
  void _syncVisibility({bool resetTimer = false}) {
    final visible = _computeVisible();
    final becameVisible = visible && !_visible;
    if (visible == _visible && !resetTimer) return;
    _visible = visible;
    _timer?.cancel();
    _timer = null;
    if (!visible) return;
    if (becameVisible || _jobs == null) unawaited(_load());
    final interval = widget.refreshInterval;
    if (interval != null && interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) {
        if (_visible && !_loading) unawaited(_load());
      });
    }
  }

  /// Re-reads the schedule. Public so a host can refresh after the user edits
  /// a job in the cron manager.
  Future<void> refresh() => _load();

  Future<void> _load() {
    final active = _flight;
    if (active != null) return active;
    final future = _loadOnce();
    _flight = future;
    future.whenComplete(() {
      if (identical(_flight, future)) _flight = null;
    });
    return future;
  }

  Future<void> _loadOnce() async {
    final generation = _generation;
    final loader = widget.loadJobs;
    final client = _client;
    if (loader == null && client == null) {
      setState(() {
        _failure = classifyCronScheduleFailure(
          _clientError ?? const SocketException('No dashboard client'),
        );
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final jobs = await (loader ?? client!.getCronJobs)();
      if (!mounted || generation != _generation) return;
      setState(() {
        _jobs = jobs;
        _failure = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = classifyCronScheduleFailure(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    final failure = _failure;

    if (jobs == null) {
      if (failure != null) {
        final message = cronScheduleFailureMessage(context.l10n, failure);
        // Scrollable: a long explanation must never be clipped on a very
        // compact viewport, where a plain Column would overflow.
        return SingleChildScrollView(
          // An absent capability is not a crash, and must not be dressed as
          // one; a reachable dashboard that failed keeps a retry.
          child: isCronCapabilityFailure(failure)
              ? ErrorState.unsupported(
                  title: context.l10n.cron_upcoming_unavailable,
                  message: message,
                )
              : ErrorState(
                  title: context.l10n.cron_upcoming_unavailable,
                  message: message,
                  onRetry: () => unawaited(_load()),
                ),
        );
      }
      return const SingleChildScrollView(
        padding: EdgeInsets.only(top: HermesSpacing.lg),
        child: LoadingSkeleton(rows: 4),
      );
    }

    final split = partitionCronJobs(jobs);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: kCronUpcomingListKey,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: HermesSpacing.xxl),
        children: [
          if (failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                HermesSpacing.lg,
                HermesSpacing.md,
                HermesSpacing.lg,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(context.l10n.cron_upcoming_refresh_failed),
                  ),
                  TextButton(
                    onPressed: () => unawaited(_load()),
                    child: Text(context.l10n.retry),
                  ),
                ],
              ),
            ),
          if (jobs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: HermesSpacing.xl),
              child: EmptyState(
                icon: Icons.schedule_outlined,
                title: context.l10n.cron_upcoming_empty_title,
                message: context.l10n.cron_upcoming_empty_message,
                actionLabel: widget.onOpenManager == null
                    ? null
                    : context.l10n.cron_jobs,
                onAction: widget.onOpenManager,
              ),
            ),
          if (split.upcoming.isNotEmpty) ...[
            SectionHeader(
              title: context.l10n.crons_upcoming,
              count: split.upcoming.length,
            ),
            for (final job in split.upcoming) _row(job),
          ],
          // Paused jobs and finished one-offs are still real schedule
          // entries: grouping them is honest, hiding them would repeat the
          // defect this split exists to fix.
          if (split.inactive.isNotEmpty) ...[
            SectionHeader(
              title: context.l10n.cron_no_next_run,
              count: split.inactive.length,
            ),
            for (final job in split.inactive) _row(job),
          ],
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> job) {
    final tokens = HermesTokens.of(context);
    final paused = cronJobPaused(job);
    final name = cronJobName(job, fallback: context.l10n.untitled_session);
    final prompt = cronJobPromptPreview(job);
    final schedule = cronScheduleDisplay(job);
    final nextRun = cronNextRun(job);
    final lastRun = cronLastRun(job);
    final target = cronDeliveryTarget(job);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        HermesSpacing.lg,
        0,
        HermesSpacing.lg,
        HermesSpacing.md,
      ),
      child: HermesCard(
        onTap: widget.onOpenManager,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  paused ? Icons.pause_circle_outline : Icons.schedule,
                  size: 20,
                  color: paused ? tokens.warning : tokens.accent,
                ),
                const SizedBox(width: HermesSpacing.md),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(
                  status: paused ? HermesStatus.idle : HermesStatus.running,
                  label: paused
                      ? context.l10n.cron_status_paused
                      : context.l10n.cron_status_scheduled,
                ),
              ],
            ),
            if (prompt.isNotEmpty) ...[
              const SizedBox(height: HermesSpacing.xs),
              Text(
                prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tokens.typography.body.copyWith(color: tokens.muted),
              ),
            ],
            if (schedule.isNotEmpty) ...[
              const SizedBox(height: HermesSpacing.xs),
              Text(
                schedule,
                style: tokens.typography.label.copyWith(
                  color: tokens.muted,
                  fontFamily: 'monospace',
                ),
              ),
            ],
            const SizedBox(height: HermesSpacing.xs),
            Text(
              nextRun == null
                  ? context.l10n.cron_no_next_run
                  : context.l10n.next(
                      cronTimestampLabel(context.l10n, nextRun),
                    ),
              style: tokens.typography.label.copyWith(
                color: nextRun == null ? tokens.muted : tokens.onSurface,
              ),
            ),
            if (lastRun != null)
              Text(
                context.l10n.last(cronTimestampLabel(context.l10n, lastRun)),
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
            if (target != null)
              Text(
                context.l10n.cron_delivers_to(target),
                style: tokens.typography.label.copyWith(color: tokens.muted),
              ),
          ],
        ),
      ),
    );
  }
}
