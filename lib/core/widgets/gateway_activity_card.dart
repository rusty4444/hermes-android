import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../l10n/l10n.dart';
import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

String _localClockTime(DateTime instant) {
  final local = instant.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _lastActivityTimeLabel(BuildContext context, GatewayToolActivity? item) {
  final at = item?.lastActivityAt;
  if (at == null) return context.l10n.tool_time_unavailable;
  final time = _localClockTime(at);
  return item!.lastActivityTimeSource == GatewayToolTimeSource.storedResult
      ? context.l10n.tool_result_recorded(time)
      : context.l10n.tool_last_observed(time);
}

class GatewayActivityCard extends StatefulWidget {
  final List<GatewayToolActivity> activities;
  final bool verbose;

  /// The choice this card should open with, owned by the caller so it survives
  /// this widget being rebuilt at another list index or evicted and rebuilt
  /// from scratch. `null` means the user has not overruled the automatic
  /// behaviour.
  final bool? pinnedExpansion;

  /// Reported on every tap, so the caller can remember it for [pinnedExpansion]
  /// the next time this card is created.
  final ValueChanged<bool>? onPinChanged;

  const GatewayActivityCard({
    required this.activities,
    this.verbose = false,
    this.pinnedExpansion,
    this.onPinChanged,
    super.key,
  });

  @override
  State<GatewayActivityCard> createState() => _GatewayActivityCardState();
}

class _GatewayActivityCardState extends State<GatewayActivityCard> {
  final ExpansibleController _tileController = ExpansibleController();

  /// A manual choice lasts for this chat visit; running tools never force the
  /// list open. The caller retains it across lazy-list eviction, not chat exits.
  bool? _userExpanded;

  @override
  void initState() {
    super.initState();
    _userExpanded = widget.pinnedExpansion;
  }

  /// Set while this widget drives the controller, so the resulting
  /// `onExpansionChanged` is not mistaken for a tap by the user.
  bool _syncingExpansion = false;

  bool get _hasRunningActivity =>
      widget.activities.any((activity) => !activity.isTerminal);

  // Verbose controls visibility, never automatic expansion. In-flight tools
  // and gateway hints must not open a section the reader has not requested.
  bool get _autoExpanded => false;

  GatewayToolActivity? get _previewActivity {
    // Prefer work still in flight, even when a parallel call finished later.
    for (final activity in widget.activities.reversed) {
      if (!activity.isTerminal) return activity;
    }
    return widget.activities.lastOrNull;
  }

  /// What a freshly built tile opens to: a remembered choice beats the
  /// automatic behaviour, which is what carries a pin across a remount.
  bool get _initialExpanded => _userExpanded ?? _autoExpanded;

  /// Whether the body rows render at full length. Reads intent rather than the
  /// tile controller so the first frame (before the tile exists) is not wrong.
  bool get _expanded => _userExpanded ?? _autoExpanded;

  @override
  void didUpdateWidget(GatewayActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pinnedExpansion != oldWidget.pinnedExpansion) {
      _userExpanded = widget.pinnedExpansion;
    }
    // A tap pins the card: new tool calls arriving must not reopen it.
    if (_userExpanded != null) return;
    if (_autoExpanded == _tileController.isExpanded) return;
    _syncingExpansion = true;
    if (_autoExpanded) {
      _tileController.expand();
    } else {
      _tileController.collapse();
    }
    _syncingExpansion = false;
  }

  @override
  void dispose() {
    _tileController.dispose();
    super.dispose();
  }

  void _handleExpansionChanged(bool expanded) {
    if (_syncingExpansion) return;
    if (_userExpanded == expanded) return;
    widget.onPinChanged?.call(expanded);
    setState(() => _userExpanded = expanded);
  }

  @override
  Widget build(BuildContext context) {
    final activities = widget.activities;
    final tokens = HermesTokens.of(context);
    final preview = _previewActivity;
    final active = _hasRunningActivity;
    final failures = activities.where((activity) => activity.isFailed).length;
    final subtitle = active
        ? (activities.length == 1
              ? context.l10n.hermes_is_using_a_tool
              : context.l10n.hermes_is_using_tools(activities.length))
        : failures > 0
        ? context.l10n.activity_failed_summary(failures, activities.length)
        : context.l10n.activity_completed_summary(activities.length);

    final cardStatus = active
        ? HermesStatus.running
        : failures > 0
        ? HermesStatus.failed
        : HermesStatus.completed;
    final latestTime = _lastActivityTimeLabel(
      context,
      latestKnownToolActivity(activities),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HermesSpacing.lg,
        vertical: HermesSpacing.xs,
      ),
      child: HermesCard(
        status: cardStatus,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: HermesRadius.card,
          child: Material(
            color: Colors.transparent,
            child: ExpansionTile(
              controller: _tileController,
              // No PageStorageKey: the previous key was derived from the
              // activity list, so every new tool call produced a new key and
              // with it a fresh ExpansionTile — which re-expanded the card the
              // user had just collapsed. Expansion state belongs to this State.
              initiallyExpanded: _initialExpanded,
              onExpansionChanged: _handleExpansionChanged,
              leading: active
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.running,
                      ),
                    )
                  : Icon(
                      failures > 0
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: failures > 0 ? tokens.danger : tokens.success,
                    ),
              title: Text(context.l10n.tool_activity),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle),
                  if (!_expanded && preview != null)
                    Text(
                      context.l10n.activity_name_status(
                        preview.displayName,
                        preview.statusLabel,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    latestTime,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              children: [
                const Divider(height: 1),
                for (final activity in activities)
                  _GatewayActivityRow(activity: activity, expanded: _expanded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GatewayActivityRow extends StatelessWidget {
  final GatewayToolActivity activity;
  final bool expanded;

  const _GatewayActivityRow({required this.activity, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final color = activity.isFailed
        ? tokens.danger
        : activity.isTerminal
        ? tokens.success
        : tokens.running;
    final timeLabel = _lastActivityTimeLabel(context, activity);
    final startLabel = activity.startedAt == null
        ? null
        : context.l10n.tool_start_observed(
            _localClockTime(activity.startedAt!),
          );

    return Semantics(
      label: [
        context.l10n.activity_name_status(
          activity.displayName,
          activity.statusLabel,
        ),
        ?startLabel,
        timeLabel,
      ].join(', '),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: activity.isTerminal
                  ? Icon(
                      activity.isFailed
                          ? Icons.error_outline
                          : Icons.check_rounded,
                      size: 19,
                      color: color,
                    )
                  : SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${activity.emoji ?? _emojiFor(activity.name)} '
                    '${activity.displayName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activity.statusLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: color),
                  ),
                  if (startLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      startLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  Text(timeLabel, style: Theme.of(context).textTheme.bodySmall),
                  if (activity.detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      activity.detail!,
                      maxLines: expanded ? null : 3,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _emojiFor(String name) {
    switch (name.toLowerCase()) {
      case 'browser_navigate':
      case 'browser_console':
      case 'browser':
        return '🌐';
      case 'read_file':
      case 'read':
        return '📄';
      case 'write_file':
      case 'write':
      case 'patch':
        return '✏️';
      case 'search':
      case 'search_files':
      case 'google_search':
        return '🔍';
      case 'execute':
      case 'shell':
      case 'terminal':
        return '💻';
      case 'think':
      case 'reasoning':
        return '🧠';
      default:
        return '🔧';
    }
  }
}
