import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/background_report.dart';

/// A read-only report, separate from both human bubbles and live task viewers.
class BackgroundReportCard extends StatefulWidget {
  const BackgroundReportCard({
    required this.report,
    this.initiallyExpanded = false,
    required this.onExpansionChanged,
    super.key,
  });

  final BackgroundReport report;
  final bool initiallyExpanded;
  final ValueChanged<bool> onExpansionChanged;

  @override
  State<BackgroundReportCard> createState() => _BackgroundReportCardState();
}

class _BackgroundReportCardState extends State<BackgroundReportCard> {
  final _controller = ExpansibleController();
  late bool _expanded = widget.initiallyExpanded;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final report = widget.report;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: colors.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        controller: _controller,
        initiallyExpanded: _expanded,
        textColor: colors.onSurface,
        collapsedTextColor: colors.onSurface,
        iconColor: colors.onSurfaceVariant,
        collapsedIconColor: colors.onSurfaceVariant,
        onExpansionChanged: (expanded) {
          setState(() => _expanded = expanded);
          widget.onExpansionChanged(expanded);
        },
        leading: Icon(
          report.hasIssues
              ? Icons.warning_amber_outlined
              : Icons.article_outlined,
          color: report.hasIssues ? colors.error : colors.onSurfaceVariant,
        ),
        title: Text(
          report.kind == BackgroundReportKind.task
              ? context.l10n.background_task_report
              : context.l10n.background_process_report,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (report.summary case final summary?)
              Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (report.hasIssues) Text(context.l10n.background_report_issues),
            Text(
              _expanded
                  ? context.l10n.background_report_collapse
                  : context.l10n.background_report_expand,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        // Do not construct or lay out the potentially huge body while closed.
        children: [
          if (_expanded) ...[
            const Divider(height: 1),
            SelectionArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(report.body),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
