import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../controllers/delegated_task_controller.dart';
import '../services/delegated_task_history.dart';
import '../l10n/l10n.dart';
import 'background_report_card.dart';
import 'delegated_task_labels.dart';
import 'markdown_link_handler.dart';

/// A modal route keeps the parent chat, composer and scroll controller mounted.
Future<void> showDelegatedTaskTimeline(
  BuildContext context,
  DelegatedTaskController controller,
) {
  if (MediaQuery.sizeOf(context).width >= 700) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 840,
          height: MediaQuery.sizeOf(dialogContext).height * .9,
          child: DelegatedTaskTimeline(controller: controller),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .9,
      child: DelegatedTaskTimeline(controller: controller),
    ),
  );
}

class DelegatedTaskTimeline extends StatefulWidget {
  const DelegatedTaskTimeline({required this.controller, super.key});
  final DelegatedTaskController controller;
  @override
  State<DelegatedTaskTimeline> createState() => _DelegatedTaskTimelineState();
}

class _DelegatedTaskTimelineState extends State<DelegatedTaskTimeline>
    with WidgetsBindingObserver {
  DelegatedTaskController get controller => widget.controller;
  final _scrollController = ScrollController();
  final _backgroundReportExpansions = <int, bool>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    controller.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    controller.start();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DelegatedTaskTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, controller)) return;
    oldWidget.controller.removeListener(_changed);
    oldWidget.controller.dispose();
    _backgroundReportExpansions.clear();
    controller.addListener(_changed);
    controller.setForeground(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      controller.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = controller.task;
    final transcript = parseTaskTranscript(controller.rows);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.task_timeline,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.task_refresh_history,
                  onPressed:
                      controller.loading ||
                          controller.loadingOlder ||
                          task.childSessionId == null
                      ? null
                      : () => unawaited(controller.refresh()),
                  icon: const Icon(Icons.refresh),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: Text(context.l10n.close),
                ),
              ],
            ),
          ),

          if (controller.loading || controller.loadingOlder)
            const LinearProgressIndicator(),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: _scrollController,
              key: PageStorageKey(('task-timeline-scroll', controller)),
              padding: const EdgeInsets.all(12),
              children: [
                _identity(context),
                if (task.livePreview != null)
                  Card(
                    child: ExpansionTile(
                      key: PageStorageKey('task-preview-${task.id}'),
                      title: Text(context.l10n.task_live_preview),
                      subtitle: Text(context.l10n.task_preview_explanation),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            '${task.previewKind ?? context.l10n.task_preview}\n${task.livePreview}',
                            key: PageStorageKey('task-preview-text-${task.id}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(context.l10n.task_recorded_history),
                ),
                if (controller.limitation != null)
                  _notice(
                    taskHistoryProblemLabel(
                      context.l10n,
                      controller.limitation!,
                    ),
                  ),
                if (controller.unavailable != null)
                  _notice(
                    taskHistoryProblemLabel(
                      context.l10n,
                      controller.unavailable!,
                    ),
                  ),
                if (controller.error != null)
                  _notice(
                    taskHistoryProblemLabel(context.l10n, controller.error!),
                  ),
                if (controller.unavailable != null || controller.error != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: controller.loading
                          ? null
                          : () => unawaited(controller.refresh()),
                      child: Text(context.l10n.retry),
                    ),
                  ),
                if (!controller.hasRead && controller.loading)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.l10n.task_loading_history),
                  ),
                if (controller.hasRead &&
                    transcript.isEmpty &&
                    controller.limitation == null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.l10n.task_empty_history),
                  ),
                if (controller.hasOlder)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: controller.loading || controller.loadingOlder
                          ? null
                          : () => unawaited(controller.loadOlder()),
                      child: Text(context.l10n.task_load_older),
                    ),
                  ),
                for (final row in transcript)
                  if (row.backgroundReport case final report?)
                    BackgroundReportCard(
                      // Expansion's bool must not share the list's double
                      // scroll-offset PageStorage entry during lazy eviction.
                      key: PageStorageKey('task-background-${row.id}'),
                      report: report,
                      initiallyExpanded:
                          _backgroundReportExpansions[row.id] ?? false,
                      onExpansionChanged: (expanded) {
                        _backgroundReportExpansions.remove(row.id);
                        _backgroundReportExpansions[row.id] = expanded;
                        if (_backgroundReportExpansions.length > 128) {
                          _backgroundReportExpansions.remove(
                            _backgroundReportExpansions.keys.first,
                          );
                        }
                      },
                    )
                  else
                    _TranscriptRow(
                      key: ValueKey('task-row-${row.id}'),
                      row: row,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text) =>
      Padding(padding: const EdgeInsets.all(12), child: SelectableText(text));

  // Keep unabridged opaque identities inside the scrollable, not in a fixed
  // header that can overflow a small phone or a large accessibility text size.
  Widget _identity(BuildContext context) {
    final task = controller.task;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              delegatedTaskGoal(context.l10n, task),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              context.l10n.task_status(delegatedTaskStatus(context.l10n, task)),
            ),
            if (task.model != null) Text(task.model!),
            if (task.detail != null && task.detail != task.livePreview)
              Text(task.detail!),
            Text(context.l10n.task_identity(task.id)),
            if (task.childSessionId != null)
              Text(
                context.l10n.task_stored_session(
                  controller.canonicalSessionId ?? task.childSessionId!,
                ),
              ),
            if (task.delegationId != null)
              Text(context.l10n.task_delegation(task.delegationId!)),
            Text(context.l10n.task_read_only_notice),
          ],
        ),
      ),
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  const _TranscriptRow({required this.row, super.key});
  final TaskTranscriptRow row;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.task_row_label(
                row.id,
                taskTranscriptRole(context.l10n, row.role),
              ),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            for (var i = 0; i < row.reasoning.length; i++)
              _detail(
                'reasoning:${row.id}:${row.reasoningKeys[i]}',
                context.l10n.reasoning,
                row.reasoning[i],
              ),
            if (row.role != 'tool' && row.text.trim().isNotEmpty)
              MarkdownBody(
                data: row.text,
                selectable: true,
                onTapLink: (_, href, _) =>
                    unawaited(openMarkdownWebLink(context, href)),
                sizedImageBuilder: (config) =>
                    Text(config.alt ?? context.l10n.task_image_placeholder),
              ),
            for (var i = 0; i < row.calls.length; i++)
              _detail(
                'call:${row.id}:${row.calls[i].id ?? i}',
                context.l10n.task_tool_call(row.calls[i].name),
                context.l10n.task_call_details(
                  row.calls[i].id ?? context.l10n.task_not_supplied,
                  row.calls[i].arguments ?? context.l10n.task_missing_arguments,
                ),
              ),
            if (row.role == 'tool')
              _detail(
                'result:${row.id}',
                context.l10n.task_tool_result(
                  row.toolName ?? context.l10n.task_role_tool,
                ),
                context.l10n.task_result_details(
                  row.toolId ?? context.l10n.task_not_supplied,
                  row.text,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String identity, String title, String text) => ExpansionTile(
    key: PageStorageKey(identity),
    maintainState: true,
    title: Text(title),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(text, key: PageStorageKey('$identity-text')),
        ),
      ),
    ],
  );
}
