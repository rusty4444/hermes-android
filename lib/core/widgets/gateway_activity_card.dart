import 'package:flutter/material.dart';

import '../models/gateway_activity.dart';
import '../services/chat_detail_visibility.dart';
import '../theme/hermes_theme.dart';
import 'hermes_components.dart';

class GatewayActivityCard extends StatefulWidget {
  final List<GatewayToolActivity> activities;
  final bool verbose;
  final ChatDetailVisibility visibility;

  const GatewayActivityCard({
    required this.activities,
    this.verbose = false,
    this.visibility = ChatDetailVisibility.automatic,
    super.key,
  });

  @override
  State<GatewayActivityCard> createState() => _GatewayActivityCardState();
}

class _GatewayActivityCardState extends State<GatewayActivityCard> {
  late bool _expanded;

  bool get _initiallyExpanded => widget.visibility.initiallyExpanded(
    automatic:
        widget.activities.any((activity) => !activity.isTerminal) ||
        widget.verbose,
  );

  @override
  void initState() {
    super.initState();
    _expanded = _initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final activities = widget.activities;
    final active = activities.any((activity) => !activity.isTerminal);
    final failures = activities.where((activity) => activity.isFailed).length;
    final subtitle = active
        ? 'Hermes is using ${activities.length == 1 ? 'a tool' : '${activities.length} tools'}'
        : failures > 0
        ? '$failures failed • ${activities.length} total'
        : '${activities.length} completed';

    final cardStatus = active
        ? HermesStatus.running
        : failures > 0
        ? HermesStatus.failed
        : HermesStatus.completed;

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
              key: PageStorageKey<String>(
                'gateway-activity-${activities.map((item) => item.toolId ?? item.name).join('-')}',
              ),
              initiallyExpanded: _initiallyExpanded,
              onExpansionChanged: (expanded) =>
                  setState(() => _expanded = expanded),
              leading: active
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      failures > 0
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: failures > 0
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
              title: const Text('Tool activity'),
              subtitle: Text(subtitle),
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
    final color = activity.isFailed
        ? Theme.of(context).colorScheme.error
        : activity.isTerminal
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.secondary;

    return Semantics(
      label: '${activity.displayName}: ${activity.statusLabel}',
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
