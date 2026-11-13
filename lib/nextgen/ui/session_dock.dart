// What sits above the composer, as in Kyllene: the session's goal, loop and
// heartbeat as a tappable strip (opening a sheet to manage them), and the
// agent's plan as a task list that ticks off while the turn runs and folds to
// "Last plan" afterwards.
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/chat_controller.dart';
import '../data/session_control.dart';
import '../nextgen_l10n.dart';
import '../theme/nextgen_theme.dart';
import 'widgets.dart';

/// Panels shown above the composer: goal strip, then the task list.
class NgSessionDock extends StatelessWidget {
  const NgSessionDock({super.key, required this.chat});
  final NgChatController chat;

  @override
  Widget build(BuildContext context) {
    final control = chat.control;
    final todos = chat.todos;
    // Never more than about half the screen, so the transcript stays usable
    // on a small phone at large text; the dock scrolls beyond that.
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.45,
        ),
        child: SingleChildScrollView(
          reverse: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (control != null)
                NgControlStrip(
                  key: const ValueKey('ng-control-strip'),
                  control: control,
                  onOpen: () => showNgSheet<void>(
                    context,
                    builder: (_) => NgControlSheet(chat: chat),
                  ),
                ),
              if (todos != null && todos.items.isNotEmpty)
                NgTodoPanel(
                  key: ValueKey('ng-todo-panel-${chat.todosLive}'),
                  todos: todos,
                  live: chat.todosLive,
                ),
              if (chat.dockSubagents.isNotEmpty)
                NgSubagentPanel(
                  key: const ValueKey('ng-subagent-panel'),
                  agents: chat.dockSubagents,
                  onStop: chat.stopSubagent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration(NgColors c) => BoxDecoration(
  color: c.surface,
  borderRadius: BorderRadius.circular(NgRadii.lg),
  border: Border.all(color: c.strokeStrong),
);

// ---- Labels -------------------------------------------------------------

String ngGoalPhaseLabel(NgGoalPhase phase) => switch (phase) {
  NgGoalPhase.active => ngL.ng_goal_working,
  NgGoalPhase.paused => ngL.ng_paused,
  NgGoalPhase.waiting => ngL.ng_goal_waiting,
  NgGoalPhase.blocked => ngL.ng_goal_blocked,
  NgGoalPhase.done => ngL.ng_goal_done,
};

String? ngTurnsLabel(int used, int max) {
  if (used <= 0) return null;
  return max > 0 ? ngL.ng_goal_turns_of(used, max) : ngL.ng_goal_turn(used);
}

String? ngRunsLabel(int fired, int times) {
  if (fired <= 0) return null;
  return times > 0
      ? ngL.ng_loop_runs_of(fired, times)
      : ngL.ng_loop_runs(fired);
}

String? ngEveryLabel(double intervalSeconds) {
  final s = intervalSeconds.toInt();
  if (s <= 0) return null;
  if (s < 60) return ngL.ng_every_seconds(s);
  if (s < 3600) return ngL.ng_every_minutes(s ~/ 60);
  if (s % 3600 == 0) return ngL.ng_every_hours(s ~/ 3600);
  return ngL.ng_every_hours_minutes(s ~/ 3600, (s % 3600) ~/ 60);
}

String ngLoopStateLabel(NgLoop loop) {
  if (loop.deferredByGoal && loop.status == 'active') return ngL.ng_loop_held;
  if (loop.status == 'paused') return ngL.ng_paused;
  if (loop.status == 'done') return ngL.ng_loop_finished;
  return ngL.ng_loop_running;
}

String _clock(BuildContext context, double epochSeconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(
    (epochSeconds * 1000).round(),
  );
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(time),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

String _waitLabel(BuildContext context, NgWaitBarrier barrier) {
  final label = switch (barrier.type) {
    'until'
        when barrier.untilAt! * 1000 > DateTime.now().millisecondsSinceEpoch =>
      ngL.ng_wait_until(_clock(context, barrier.untilAt!)),
    'until' => ngL.ng_wait_resume,
    'session' => ngL.ng_wait_other_chat,
    _ => ngL.ng_wait_process(barrier.target ?? ''),
  };
  return barrier.reason.isEmpty ? label : '$label: ${barrier.reason}';
}

/// A plain user pause says `user-paused`; the Paused label says that.
String? _pausedReason(String? reason) {
  final r = reason?.trim();
  return r == null || r.isEmpty || r == 'user-paused' ? null : r;
}

Color _phaseTint(NgColors c, NgGoalPhase phase) => switch (phase) {
  NgGoalPhase.active => c.accentText,
  NgGoalPhase.paused || NgGoalPhase.waiting => c.warning,
  NgGoalPhase.blocked => c.danger,
  NgGoalPhase.done => c.textMuted,
};

// ---- Strip --------------------------------------------------------------

/// One line per goal/loop/heartbeat present; tap to manage them.
class NgControlStrip extends StatelessWidget {
  const NgControlStrip({
    super.key,
    required this.control,
    required this.onOpen,
  });
  final NgSessionControl control;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final rows = <(IconData, Color, String, String)>[
      if (control.goal case final goal?)
        (
          Icons.track_changes,
          _phaseTint(c, goal.phase),
          [
            ngL.ng_goal,
            ngGoalPhaseLabel(goal.phase),
            ?ngTurnsLabel(goal.turnsUsed, goal.maxTurns),
          ].join(' · '),
          goal.title,
        ),
      if (control.loop case final loop?)
        (
          Icons.repeat,
          loop.status == 'active' && !loop.deferredByGoal
              ? c.accentText
              : c.text2,
          [
            ngL.ng_loop,
            ngLoopStateLabel(loop),
            ?ngRunsLabel(loop.ticksFired, loop.times),
            if (loop.status == 'active' &&
                !loop.deferredByGoal &&
                loop.nextDueAt > 0)
              loop.nextDueAt * 1000 <= DateTime.now().millisecondsSinceEpoch
                  ? ngL.ng_loop_due_now
                  : ngL.ng_loop_next(_clock(context, loop.nextDueAt)),
          ].join(' · '),
          loop.prompt,
        ),
      if (control.heartbeat case final hb?)
        (
          Icons.monitor_heart_outlined,
          hb.status == 'paused' ? c.text2 : c.accentText,
          (hb.status == 'paused'
                  ? [ngL.ng_heartbeat, ngL.ng_paused]
                  : [
                      ngL.ng_heartbeat,
                      ?ngEveryLabel(hb.intervalSeconds.toDouble()),
                      if (hb.fireCount > 0)
                        ngL.ng_heartbeat_fired(hb.fireCount),
                    ])
              .join(' · '),
          hb.prompt,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Semantics(
        button: true,
        label: ngL.ng_control_open,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(NgRadii.lg),
            onTap: onOpen,
            child: Ink(
              decoration: _panelDecoration(c),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (icon, tint, line, title) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          Icon(icon, size: 15, color: tint),
                          const SizedBox(width: 8),
                          Flexible(
                            flex: 3,
                            child: Text(
                              line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NgType.label.copyWith(color: c.text2),
                            ),
                          ),
                          if (title.trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NgType.bodySmall.copyWith(
                                  color: c.text3,
                                ),
                              ),
                            ),
                          ] else
                            const Spacer(),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Task list -----------------------------------------------------------

/// The agent's plan: open while its turn runs, folded afterwards.
class NgTodoPanel extends StatefulWidget {
  const NgTodoPanel({super.key, required this.todos, required this.live});
  final NgTodoList todos;
  final bool live;

  @override
  State<NgTodoPanel> createState() => _NgTodoPanelState();
}

class _NgTodoPanelState extends State<NgTodoPanel> {
  late bool _expanded = widget.live;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final todos = widget.todos;
    final live = widget.live;
    final current = todos.current;
    final fraction = todos.total == 0 ? 0.0 : todos.done / todos.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        decoration: _panelDecoration(c),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const ValueKey('ng-todo-header'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.checklist, size: 17, color: c.text2),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.55,
                          ),
                          child: Text(
                            live
                                ? ngL.ng_tasks_count(todos.done, todos.total)
                                : ngL.ng_last_plan_count(
                                    todos.done,
                                    todos.total,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NgType.label.copyWith(
                              color: live ? c.text : c.text2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: !_expanded && live && current != null
                              ? Text(
                                  current.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NgType.bodySmall.copyWith(
                                    color: c.text2,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Icon(
                          _expanded ? Icons.expand_more : Icons.expand_less,
                          size: 18,
                          color: c.text3,
                          semanticLabel: _expanded
                              ? ngL.ng_hide_tasks
                              : ngL.ng_show_tasks,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(NgRadii.full),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: fraction),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 4,
                          backgroundColor: c.surface3,
                          color: live ? c.accent : c.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  children: [
                    for (final (item, depth) in todos.tree())
                      _TodoRow(item: item, depth: depth, live: live),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.item, required this.depth, required this.live});
  final NgTodoItem item;
  final int depth;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final Widget icon = switch (item.status) {
      // A past plan's step isn't still running, whatever it was marked.
      NgTodoStatus.inProgress when live => SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.accentText),
      ),
      NgTodoStatus.inProgress => Icon(
        Icons.timelapse,
        size: 15,
        color: c.text3,
      ),
      NgTodoStatus.pending => Icon(
        Icons.radio_button_unchecked,
        size: 15,
        color: c.text3,
      ),
      NgTodoStatus.completed => Icon(
        Icons.check_circle,
        size: 15,
        color: c.success,
      ),
      NgTodoStatus.cancelled => Icon(Icons.block, size: 15, color: c.text3),
    };
    final color = switch (item.status) {
      NgTodoStatus.inProgress => c.text,
      NgTodoStatus.pending => c.text2,
      _ => c.text3,
    };
    return Padding(
      padding: EdgeInsets.only(left: depth * 20.0, top: 3, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, height: 18, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.content,
              style: NgType.bodySmall.copyWith(
                color: color,
                decoration: item.status == NgTodoStatus.cancelled
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Subagents ----------------------------------------------------------

/// Delegated child agents while any is live: "Subagents · 1 of 3 done" with
/// a dot per child, then a row each with what it's doing and a stop button.
class NgSubagentPanel extends StatefulWidget {
  const NgSubagentPanel({
    super.key,
    required this.agents,
    required this.onStop,
  });
  final List<NgSubagent> agents;
  final Future<void> Function(NgSubagent agent) onStop;

  @override
  State<NgSubagentPanel> createState() => _NgSubagentPanelState();
}

class _NgSubagentPanelState extends State<NgSubagentPanel> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final agents = widget.agents;
    final done = agents.where((a) => !a.status.live).length;
    final current = agents.where((a) => a.status.live).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        decoration: _panelDecoration(c),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              key: const ValueKey('ng-subagent-header'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 17, color: c.text2),
                    const SizedBox(width: 10),
                    Flexible(
                      flex: 3,
                      child: Text(
                        ngL.ng_subagents_count(done, agents.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NgType.label.copyWith(color: c.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TeamDots(agents: agents),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: !_expanded && current != null
                          ? Text(
                              current.goal,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NgType.bodySmall.copyWith(color: c.text2),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Icon(
                      _expanded ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                      color: c.text3,
                      semanticLabel: _expanded
                          ? ngL.ng_hide_subagents
                          : ngL.ng_show_subagents,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
                  children: [
                    for (final a in agents)
                      _SubagentRow(
                        key: ValueKey('ng-subagent-${a.id}'),
                        agent: a,
                        onStop: () => widget.onStop(a),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _subagentColor(NgColors c, NgSubagentStatus s) => switch (s) {
  NgSubagentStatus.queued => c.textMuted,
  NgSubagentStatus.running => c.accent,
  NgSubagentStatus.done => c.success,
  NgSubagentStatus.failed => c.danger,
  NgSubagentStatus.interrupted => c.warning,
};

class _TeamDots extends StatelessWidget {
  const _TeamDots({required this.agents});
  final List<NgSubagent> agents;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    const max = 4;
    final extra = agents.length - max;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in agents.take(max))
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _subagentColor(c, a.status),
            ),
          ),
        if (extra > 0)
          Text('+$extra', style: NgType.caption.copyWith(color: c.text3)),
      ],
    );
  }
}

class _SubagentRow extends StatefulWidget {
  const _SubagentRow({super.key, required this.agent, required this.onStop});
  final NgSubagent agent;
  final Future<void> Function() onStop;

  @override
  State<_SubagentRow> createState() => _SubagentRowState();
}

class _SubagentRowState extends State<_SubagentRow> {
  bool _stopping = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.agent.status.live) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _elapsed(NgSubagent a) {
    final seconds =
        a.durationSeconds?.round() ??
        (a.finishedAt ?? DateTime.now()).difference(a.startedAt).inSeconds;
    final s = seconds < 0 ? 0 : seconds;
    return s >= 60 ? '${s ~/ 60}m ${s % 60}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final a = widget.agent;
    final Widget icon = switch (a.status) {
      NgSubagentStatus.running => SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 2, color: c.accentText),
      ),
      NgSubagentStatus.queued => Icon(Icons.schedule, size: 15, color: c.text3),
      NgSubagentStatus.done => Icon(
        Icons.check_circle,
        size: 15,
        color: c.success,
      ),
      NgSubagentStatus.failed => Icon(
        Icons.error_outline,
        size: 15,
        color: c.danger,
      ),
      NgSubagentStatus.interrupted => Icon(
        Icons.stop_circle_outlined,
        size: 15,
        color: c.warning,
      ),
    };
    final line = switch (a.status) {
      NgSubagentStatus.queued => ngL.ng_subagent_queued,
      NgSubagentStatus.running => a.current ?? ngL.ng_subagent_starting,
      _ => a.summary ?? a.current ?? ngSubagentStatusLabel(a.status),
    };
    final meta = [
      if (a.model != null) a.model!,
      if ((a.toolCount ?? 0) > 0) ngL.ng_subagent_tools(a.toolCount!),
      _elapsed(a),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 16, height: 20, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.goal.isEmpty ? ngL.ng_subagent : a.goal,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NgType.bodySmall.copyWith(
                    color: a.status.live ? c.text : c.text2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgType.caption.copyWith(color: c.text2),
                ),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NgType.caption.copyWith(color: c.text3),
                ),
              ],
            ),
          ),
          if (a.status.live)
            IconButton(
              key: ValueKey('ng-subagent-stop-${a.id}'),
              tooltip: ngL.ng_subagent_stop,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: c.text2,
              onPressed: _stopping
                  ? null
                  : () async {
                      setState(() => _stopping = true);
                      await widget.onStop();
                      if (mounted) setState(() => _stopping = false);
                    },
              icon: const Icon(Icons.stop_circle_outlined),
            ),
        ],
      ),
    );
  }
}

String ngSubagentStatusLabel(NgSubagentStatus s) => switch (s) {
  NgSubagentStatus.queued => ngL.ng_subagent_queued,
  NgSubagentStatus.running => ngL.ng_subagent_running,
  NgSubagentStatus.done => ngL.ng_subagent_done,
  NgSubagentStatus.failed => ngL.ng_subagent_failed,
  NgSubagentStatus.interrupted => ngL.ng_subagent_stopped,
};

// ---- Sheet ---------------------------------------------------------------

/// Manage the goal, loop and heartbeat: what they are, how far they've got,
/// and pause/resume/clear, plus the goal's sub-goals.
class NgControlSheet extends StatefulWidget {
  const NgControlSheet({super.key, required this.chat});
  final NgChatController chat;

  @override
  State<NgControlSheet> createState() => _NgControlSheetState();
}

class _NgControlSheetState extends State<NgControlSheet> {
  final _subgoal = TextEditingController();
  String? _submitted;

  NgChatController get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    chat.addListener(_changed);
  }

  @override
  void dispose() {
    chat.removeListener(_changed);
    _subgoal.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // A confirmed sub-goal clears the field; a failed add loses nothing.
    final submitted = _submitted;
    if (submitted != null &&
        (chat.control?.goal?.subgoals.contains(submitted) ?? false)) {
      _submitted = null;
      _subgoal.clear();
    }
    if (chat.control == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  Future<void> _run(NgControlAction action, {String? text, int? index}) =>
      chat.runControl(action, text: text, index: index);

  Future<void> _confirm(
    String title,
    String body,
    String confirm,
    Future<void> Function() then,
  ) async {
    if (await ngConfirm(context, title: title, body: body, confirm: confirm)) {
      await then();
    }
  }

  void _addSubgoal() {
    if (chat.controlBusy != null) return;
    final text = _subgoal.text.trim();
    if (text.isEmpty) return;
    _submitted = text;
    unawaited(_run(NgControlAction.subgoalAdd, text: text));
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final control = chat.control;
    if (control == null) return const SizedBox(height: 120);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Text(
                ngL.ng_control_title,
                style: NgType.title.copyWith(color: c.text),
              ),
              const SizedBox(height: 4),
              Text(
                ngL.ng_control_subtitle,
                style: NgType.bodySmall.copyWith(color: c.text3),
              ),
              const SizedBox(height: 12),
              if (control.goal case final goal?) _goal(c, goal),
              if (control.loop case final loop?) _loop(c, loop),
              if (control.heartbeat case final hb?) _heartbeat(c, hb),
              if (chat.controlError case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: NgType.bodySmall.copyWith(color: c.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(NgColors c, String header, List<Widget> children) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(NgRadii.lg),
          border: Border.all(color: c.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              header.toUpperCase(),
              style: NgType.eyebrow.copyWith(color: c.text3),
            ),
            const SizedBox(height: 8),
            for (final child in children) ...[child, const SizedBox(height: 8)],
          ],
        ),
      );

  Widget _detail(NgColors c, String text) =>
      SelectableText(text, style: NgType.bodySmall.copyWith(color: c.text3));

  Widget _button(
    String label,
    IconData icon,
    NgControlAction action, {
    VoidCallback? onPressed,
    bool outline = false,
  }) {
    final busy = chat.controlBusy;
    final onTap = busy != null
        ? null
        : onPressed ?? () => unawaited(_run(action));
    final iconWidget = busy == action
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 16);
    return outline
        ? OutlinedButton.icon(
            onPressed: onTap,
            icon: iconWidget,
            label: Text(label),
          )
        : FilledButton.tonalIcon(
            onPressed: onTap,
            icon: iconWidget,
            label: Text(label),
          );
  }

  Widget _goal(NgColors c, NgGoal goal) {
    final phase = goal.phase;
    final pausedReason = _pausedReason(goal.pausedReason);
    final relevant = goal.waitBarrier != null
        ? _waitLabel(context, goal.waitBarrier!)
        : pausedReason ??
              (goal.lastReason?.trim().isNotEmpty == true
                  ? goal.lastReason
                  : null);
    final contract = goal.contract;
    final resumable = goal.status == 'paused';
    return _section(c, ngL.ng_goal, [
      SelectableText(
        goal.title,
        style: NgType.body.copyWith(color: c.text, fontWeight: FontWeight.w500),
      ),
      Text(
        [
          ngGoalPhaseLabel(phase),
          ?ngTurnsLabel(goal.turnsUsed, goal.maxTurns),
        ].join(' · '),
        style: NgType.label.copyWith(color: _phaseTint(c, phase)),
      ),
      if (goal.maxTurns > 0)
        ClipRRect(
          borderRadius: BorderRadius.circular(NgRadii.full),
          child: LinearProgressIndicator(
            value: (goal.turnsUsed / goal.maxTurns).clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: c.surface3,
            color: c.accent,
          ),
        ),
      if (relevant != null) _detail(c, relevant),
      if (!contract.isEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (name, value, code) in [
              (ngL.ng_contract_outcome, contract.outcome, false),
              (ngL.ng_contract_verification, contract.verification, true),
              (ngL.ng_contract_constraints, contract.constraints, false),
              (ngL.ng_contract_boundaries, contract.boundaries, false),
              (ngL.ng_contract_stop_when, contract.stopWhen, false),
            ])
              if (value.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: NgType.eyebrow.copyWith(color: c.text3),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        value,
                        style: (code ? NgType.code : NgType.bodySmall).copyWith(
                          color: c.text2,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ..._subgoals(c, goal),
      if (goal.gates.isNotEmpty) ...[
        Text(
          ngL.ng_goal_checks.toUpperCase(),
          style: NgType.eyebrow.copyWith(color: c.text3),
        ),
        for (final gate in goal.gates)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                gate.command,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: NgType.code.copyWith(color: c.text2, fontSize: 12),
              ),
              Text(
                gate.attempts <= 0
                    ? ngL.ng_gate_not_run
                    : [
                        ngL.ng_gate_attempts(
                          gate.attempts,
                          gate.maxRetries + 1,
                        ),
                        if (gate.lastExitCode != null)
                          ngL.ng_gate_exit(gate.lastExitCode!),
                      ].join(' · '),
                style: NgType.caption.copyWith(color: c.textMuted),
              ),
            ],
          ),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ...switch (phase) {
            NgGoalPhase.active || NgGoalPhase.blocked =>
              resumable
                  ? [
                      _button(
                        ngL.ng_resume,
                        Icons.play_arrow,
                        NgControlAction.goalResume,
                      ),
                    ]
                  : [
                      _button(
                        ngL.ng_pause,
                        Icons.pause,
                        NgControlAction.goalPause,
                      ),
                    ],
            NgGoalPhase.paused => [
              _button(
                ngL.ng_resume,
                Icons.play_arrow,
                NgControlAction.goalResume,
              ),
            ],
            NgGoalPhase.waiting => [
              _button(
                ngL.ng_resume_now,
                Icons.play_arrow,
                NgControlAction.goalUnwait,
              ),
              _button(ngL.ng_pause, Icons.pause, NgControlAction.goalPause),
            ],
            NgGoalPhase.done => const <Widget>[],
          },
          _button(
            ngL.ng_goal_clear,
            Icons.delete_outline,
            NgControlAction.goalClear,
            outline: true,
            onPressed: () => _confirm(
              ngL.ng_goal_clear_title,
              ngL.ng_goal_clear_message,
              ngL.ng_goal_clear,
              () => _run(NgControlAction.goalClear),
            ),
          ),
        ],
      ),
    ]);
  }

  List<Widget> _subgoals(NgColors c, NgGoal goal) => [
    if (goal.subgoals.isNotEmpty)
      Row(
        children: [
          Expanded(
            child: Text(
              ngL.ng_subgoals.toUpperCase(),
              style: NgType.eyebrow.copyWith(color: c.text3),
            ),
          ),
          if (goal.subgoals.length > 1)
            TextButton(
              onPressed: chat.controlBusy != null
                  ? null
                  : () => _confirm(
                      ngL.ng_subgoals_clear_title,
                      ngL.ng_subgoals_clear_message,
                      ngL.ng_clear_all,
                      () => _run(NgControlAction.subgoalClear),
                    ),
              child: Text(ngL.ng_clear_all),
            ),
        ],
      ),
    for (final text in goal.subgoals)
      Row(
        children: [
          Expanded(
            child: Text(text, style: NgType.bodySmall.copyWith(color: c.text2)),
          ),
          IconButton(
            tooltip: ngL.ng_subgoal_remove,
            icon: Icon(Icons.close, size: 16, color: c.text3),
            onPressed: chat.controlBusy != null
                ? null
                : () => _confirm(
                    ngL.ng_subgoal_remove_title,
                    ngL.ng_subgoal_remove_message(text),
                    ngL.ng_remove,
                    () async {
                      // Resolve against the live list; it may have changed.
                      final index =
                          chat.control?.goal?.subgoals.indexOf(text) ?? -1;
                      if (index >= 0) {
                        await _run(
                          NgControlAction.subgoalRemove,
                          index: index + 1,
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    if (goal.phase != NgGoalPhase.done)
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ng-subgoal-field'),
              controller: _subgoal,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addSubgoal(),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                hintText: ngL.ng_subgoal_add_placeholder,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed:
                chat.controlBusy == null && _subgoal.text.trim().isNotEmpty
                ? _addSubgoal
                : null,
            child: chat.controlBusy == NgControlAction.subgoalAdd
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(ngL.ng_add),
          ),
        ],
      ),
  ];

  Widget _loop(NgColors c, NgLoop loop) {
    final cadence = loop.selfPaced
        ? ngL.ng_loop_self_paced
        : ngEveryLabel(loop.intervalSeconds);
    return _section(c, ngL.ng_loop, [
      if (loop.prompt.trim().isNotEmpty) _detail(c, loop.prompt),
      Text(
        [
          ngLoopStateLabel(loop),
          ?cadence,
          ?ngRunsLabel(loop.ticksFired, loop.times),
        ].join(' · '),
        style: NgType.label.copyWith(color: c.text2),
      ),
      if (loop.status == 'active' && !loop.deferredByGoal && loop.nextDueAt > 0)
        _detail(
          c,
          loop.nextDueAt * 1000 <= DateTime.now().millisecondsSinceEpoch
              ? ngL.ng_loop_due_now
              : ngL.ng_loop_next(_clock(context, loop.nextDueAt)),
        ),
      if (loop.until.trim().isNotEmpty)
        _detail(c, ngL.ng_loop_until(loop.until)),
      if (loop.deferredByGoal) _detail(c, ngL.ng_loop_waits_for_goal),
      if (loop.awaitingResponse) _detail(c, ngL.ng_loop_awaiting_reply),
      if (_pausedReason(loop.pausedReason) case final r?) _detail(c, r),
      if (loop.lastStopReason?.trim().isNotEmpty == true)
        _detail(c, ngL.ng_loop_stopped_reason(loop.lastStopReason!)),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (loop.status == 'active')
            _button(ngL.ng_pause, Icons.pause, NgControlAction.loopPause),
          if (loop.status == 'paused')
            _button(
              ngL.ng_resume,
              Icons.play_arrow,
              NgControlAction.loopResume,
            ),
          if (loop.status == 'done')
            _button(ngL.ng_dismiss, Icons.close, NgControlAction.loopStop)
          else
            _button(
              ngL.ng_stop,
              Icons.stop,
              NgControlAction.loopStop,
              outline: true,
              onPressed: () => _confirm(
                ngL.ng_loop_stop_title,
                ngL.ng_wont_fire_again,
                ngL.ng_stop,
                () => _run(NgControlAction.loopStop),
              ),
            ),
        ],
      ),
    ]);
  }

  Widget _heartbeat(NgColors c, NgHeartbeat hb) {
    final paused = hb.status == 'paused';
    return _section(c, ngL.ng_heartbeat, [
      if (hb.prompt.trim().isNotEmpty) _detail(c, hb.prompt),
      Text(
        paused
            ? ngL.ng_paused
            : [
                ?ngEveryLabel(hb.intervalSeconds.toDouble()),
                if (hb.fireCount > 0) ngL.ng_heartbeat_fired(hb.fireCount),
              ].join(' · '),
        style: NgType.label.copyWith(color: c.text2),
      ),
      if (hb.lastFiredAt > 0)
        _detail(
          c,
          ngL.ng_heartbeat_last_fired(_clock(context, hb.lastFiredAt)),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (paused)
            _button(
              ngL.ng_resume,
              Icons.play_arrow,
              NgControlAction.heartbeatResume,
            )
          else
            _button(ngL.ng_pause, Icons.pause, NgControlAction.heartbeatPause),
          _button(
            ngL.ng_clear,
            Icons.delete_outline,
            NgControlAction.heartbeatClear,
            outline: true,
            onPressed: () => _confirm(
              ngL.ng_heartbeat_clear_title,
              ngL.ng_wont_fire_again,
              ngL.ng_clear,
              () => _run(NgControlAction.heartbeatClear),
            ),
          ),
        ],
      ),
    ]);
  }
}
