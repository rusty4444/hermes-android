import 'package:flutter/material.dart';

import '../models/gateway_insight.dart';

class GatewayReasoningCard extends StatelessWidget {
  final String text;
  final bool initiallyExpanded;

  const GatewayReasoningCard({
    required this.text,
    this.initiallyExpanded = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey<String>('gateway-reasoning-${text.hashCode}'),
        initiallyExpanded: initiallyExpanded,
        leading: const Icon(Icons.psychology_outlined),
        title: const Text('Reasoning'),
        subtitle: const Text('Hermes reasoning details'),
        children: [
          const Divider(height: 1),
          SelectionArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(alignment: Alignment.centerLeft, child: Text(text)),
            ),
          ),
        ],
      ),
    );
  }
}

class GatewayNoticeCard extends StatelessWidget {
  final GatewayNotice notice;

  const GatewayNoticeCard({required this.notice, super.key});

  @override
  Widget build(BuildContext context) {
    final isBackground = notice.kind == GatewayNoticeKind.background;
    if (isBackground) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ExpansionTile(
          key: PageStorageKey<String>('gateway-background-${notice.identity}'),
          initiallyExpanded: false,
          leading: const Icon(Icons.task_alt_outlined, size: 21),
          title: Text(notice.title),
          subtitle: const Text('Background task details'),
          children: [
            const Divider(height: 1),
            SelectionArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(notice.text),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fact_check_outlined, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(notice.text),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GatewaySubagentCard extends StatelessWidget {
  final List<GatewaySubagentActivity> activities;

  const GatewaySubagentCard({required this.activities, super.key});

  @override
  Widget build(BuildContext context) {
    final complete = activities.every((activity) => activity.isComplete);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: !complete,
        leading: Icon(
          complete ? Icons.hub_outlined : Icons.account_tree_outlined,
        ),
        title: Text(
          complete
              ? '${activities.length} delegated task(s) completed'
              : '${activities.where((item) => !item.isComplete).length} delegated task(s) active',
        ),
        children: [
          for (final activity in activities)
            ListTile(
              dense: true,
              leading: activity.isComplete
                  ? const Icon(Icons.check_circle_outline, color: Colors.green)
                  : const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
              title: Text(activity.goal),
              subtitle: Text(
                [
                  activity.phase.name,
                  if (activity.model != null) activity.model!,
                  if (activity.detail != null) activity.detail!,
                ].join(' • '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
