// The agent's plan (todo list) and the session's automation (goal, loop,
// heartbeat), as Kyllene reads them from the gateway: `todo.updated` events
// and `session.resume`'s `todo_state` for the plan; `session.control.read`,
// `session.control` and `session.control.update` events for the rest
// (tui_gateway/methods_session_control.py). Parsed leniently: a malformed
// part is dropped on its own, numbers may arrive as int or float.

enum NgTodoStatus { pending, inProgress, completed, cancelled }

class NgTodoItem {
  const NgTodoItem(this.id, this.content, this.status, [this.parent]);
  final String id;
  final String content;
  final NgTodoStatus status;
  final String? parent;
}

class NgTodoList {
  const NgTodoList(this.items, this.revision);
  final List<NgTodoItem> items;
  final int revision;

  /// Cancelled steps count on neither side, as on Desktop.
  int get done => items.where((i) => i.status == NgTodoStatus.completed).length;
  int get total =>
      items.where((i) => i.status != NgTodoStatus.cancelled).length;

  /// Something is still to do.
  bool get active => items.any(
    (i) =>
        i.status == NgTodoStatus.pending || i.status == NgTodoStatus.inProgress,
  );

  NgTodoItem? get current =>
      items.where((i) => i.status == NgTodoStatus.inProgress).firstOrNull;

  /// Items in reading order with their nesting depth.
  List<(NgTodoItem, int)> tree() {
    final ids = {for (final i in items) i.id};
    final children = <String, List<NgTodoItem>>{};
    for (final i in items) {
      if (i.parent != null && ids.contains(i.parent)) {
        children.putIfAbsent(i.parent!, () => []).add(i);
      }
    }
    final out = <(NgTodoItem, int)>[];
    final seen = <String>{};
    void visit(NgTodoItem item, int depth) {
      if (!seen.add(item.id)) return;
      out.add((item, depth));
      for (final child in children[item.id] ?? const <NgTodoItem>[]) {
        visit(child, depth + 1);
      }
    }

    for (final i in items) {
      if (i.parent == null || !ids.contains(i.parent)) visit(i, 0);
    }
    // A parent cycle leaves items unvisited; show them flat.
    for (final i in items) {
      if (!seen.contains(i.id)) visit(i, 0);
    }
    return out;
  }

  /// A `todo.updated` payload or `todo_state` snapshot; null when malformed
  /// or the empty list of an agent that never planned.
  static NgTodoList? parse(Object? snapshot) {
    if (snapshot is! Map) return null;
    final todos = snapshot['todos'];
    if (todos is! List) return null;
    final revision = _int(snapshot['revision']) ?? 0;
    final items = <NgTodoItem>[];
    for (final raw in todos) {
      if (raw is! Map) continue;
      final status = switch (raw['status']) {
        'pending' => NgTodoStatus.pending,
        'in_progress' => NgTodoStatus.inProgress,
        'completed' => NgTodoStatus.completed,
        'cancelled' => NgTodoStatus.cancelled,
        _ => null,
      };
      final id = _text(raw['id']);
      final content = _text(raw['content']);
      if (status == null || id == null || content == null) continue;
      final parent = _text(raw['parent']);
      items.add(NgTodoItem(id, content, status, parent == id ? null : parent));
    }
    if (items.isEmpty && revision == 0) return null;
    return NgTodoList(items, revision);
  }
}

enum NgGoalPhase { active, paused, waiting, blocked, done }

class NgGoalContract {
  const NgGoalContract({
    this.outcome = '',
    this.verification = '',
    this.constraints = '',
    this.boundaries = '',
    this.stopWhen = '',
  });
  final String outcome;
  final String verification;
  final String constraints;
  final String boundaries;
  final String stopWhen;

  bool get isEmpty =>
      outcome.isEmpty &&
      verification.isEmpty &&
      constraints.isEmpty &&
      boundaries.isEmpty &&
      stopWhen.isEmpty;

  static NgGoalContract parse(Object? json) {
    if (json is! Map) return const NgGoalContract();
    return NgGoalContract(
      outcome: _str(json['outcome']) ?? '',
      verification: _str(json['verification']) ?? '',
      constraints: _str(json['constraints']) ?? '',
      boundaries: _str(json['boundaries']) ?? '',
      stopWhen: _str(json['stop_when']) ?? '',
    );
  }
}

/// A shell check the goal's judge runs; [attempts] 0 means not yet.
class NgGoalGate {
  const NgGoalGate(
    this.command, {
    this.maxRetries = 0,
    this.attempts = 0,
    this.lastExitCode,
  });
  final String command;
  final int maxRetries;
  final int attempts;
  final int? lastExitCode;

  static NgGoalGate? parse(Object? json) {
    if (json is! Map) return null;
    final command = _str(json['command']);
    if (command == null) return null;
    return NgGoalGate(
      command,
      maxRetries: _int(json['max_retries']) ?? 0,
      attempts: _int(json['attempts']) ?? 0,
      lastExitCode: _int(json['last_exit_code']),
    );
  }
}

/// What a waiting goal is parked on: a time, another chat or a process.
class NgWaitBarrier {
  const NgWaitBarrier(this.type, this.reason, {this.untilAt, this.target});
  final String type;
  final String reason;
  final double? untilAt;
  final String? target;

  static NgWaitBarrier? parse(Object? json) {
    if (json is! Map) return null;
    final reason = _str(json['reason']) ?? '';
    return switch (json['type']) {
      'until' when _double(json['until_at']) != null => NgWaitBarrier(
        'until',
        reason,
        untilAt: _double(json['until_at']),
      ),
      'session' when _str(json['target']) != null => NgWaitBarrier(
        'session',
        reason,
        target: _str(json['target']),
      ),
      'pid' when _double(json['target']) != null => NgWaitBarrier(
        'pid',
        reason,
        target: _double(json['target'])!.toInt().toString(),
      ),
      _ => null,
    };
  }
}

class NgGoal {
  const NgGoal({
    required this.title,
    this.status = 'active',
    this.turnsUsed = 0,
    this.maxTurns = 0,
    this.contract = const NgGoalContract(),
    this.subgoals = const [],
    this.gates = const [],
    this.pausedReason,
    this.lastVerdict,
    this.lastReason,
    this.waitBarrier,
  });
  final String title;
  final String status;
  final int turnsUsed;

  /// 0: no limit.
  final int maxTurns;
  final NgGoalContract contract;
  final List<String> subgoals;
  final List<NgGoalGate> gates;
  final String? pausedReason;
  final String? lastVerdict;
  final String? lastReason;
  final NgWaitBarrier? waitBarrier;

  /// Blocked wins, then waiting, paused, done, active (Desktop's order).
  NgGoalPhase get phase {
    if (lastVerdict == 'blocked') return NgGoalPhase.blocked;
    if (waitBarrier != null) return NgGoalPhase.waiting;
    if (status == 'paused') return NgGoalPhase.paused;
    if (status == 'done') return NgGoalPhase.done;
    return NgGoalPhase.active;
  }

  static NgGoal? parse(Object? json) {
    if (json is! Map) return null;
    final title = _str(json['title']);
    if (title == null) return null;
    final subgoals = json['subgoals'];
    final gates = json['gates'];
    return NgGoal(
      title: title,
      status: _str(json['status']) ?? 'active',
      turnsUsed: _int(json['turns_used']) ?? 0,
      maxTurns: _int(json['max_turns']) ?? 0,
      contract: NgGoalContract.parse(json['contract']),
      subgoals: subgoals is List
          ? [
              for (final s in subgoals)
                if (s is String || s is num) '$s',
            ]
          : const [],
      gates: gates is List
          ? [for (final g in gates) ?NgGoalGate.parse(g)]
          : const [],
      pausedReason: _str(json['paused_reason']),
      lastVerdict: _str(json['last_verdict']),
      lastReason: _str(json['last_reason']),
      waitBarrier: NgWaitBarrier.parse(json['wait_barrier']),
    );
  }
}

/// A prompt that fires on an interval (or self-paced).
class NgLoop {
  const NgLoop({
    required this.prompt,
    this.status = 'active',
    this.selfPaced = false,
    this.intervalSeconds = 0,
    this.times = 0,
    this.until = '',
    this.ticksFired = 0,
    this.nextDueAt = 0,
    this.awaitingResponse = false,
    this.deferredByGoal = false,
    this.pausedReason,
    this.lastStopReason,
  });
  final String prompt;
  final String status;
  final bool selfPaced;
  final double intervalSeconds;
  final int times;
  final String until;
  final int ticksFired;
  final double nextDueAt;
  final bool awaitingResponse;
  final bool deferredByGoal;
  final String? pausedReason;
  final String? lastStopReason;

  static NgLoop? parse(Object? json) {
    if (json is! Map) return null;
    final prompt = _str(json['prompt']);
    if (prompt == null) return null;
    return NgLoop(
      prompt: prompt,
      status: _str(json['status']) ?? 'active',
      selfPaced: json['mode'] == 'self_paced',
      intervalSeconds: _double(json['interval_seconds']) ?? 0,
      times: _int(json['times']) ?? 0,
      until: _str(json['until']) ?? '',
      ticksFired: _int(json['ticks_fired']) ?? 0,
      nextDueAt: _double(json['next_due_at']) ?? 0,
      awaitingResponse: json['awaiting_response'] == true,
      deferredByGoal: json['deferred_by_goal'] == true,
      pausedReason: _str(json['paused_reason']),
      lastStopReason: _str(json['last_stop_reason']),
    );
  }
}

/// A prompt that fires every [intervalSeconds].
class NgHeartbeat {
  const NgHeartbeat({
    required this.prompt,
    this.status = 'active',
    this.intervalSeconds = 0,
    this.lastFiredAt = 0,
    this.fireCount = 0,
  });
  final String prompt;
  final String status;
  final int intervalSeconds;
  final double lastFiredAt;
  final int fireCount;

  static NgHeartbeat? parse(Object? json) {
    if (json is! Map) return null;
    final prompt = _str(json['prompt']);
    if (prompt == null) return null;
    return NgHeartbeat(
      prompt: prompt,
      status: _str(json['status']) ?? 'active',
      intervalSeconds: (_double(json['interval_seconds']) ?? 0).toInt(),
      lastFiredAt: _double(json['last_fired_at']) ?? 0,
      fireCount: _int(json['fire_count']) ?? 0,
    );
  }
}

class NgSessionControl {
  const NgSessionControl({
    this.goal,
    this.loop,
    this.heartbeat,
    this.revision = '',
  });
  final NgGoal? goal;
  final NgLoop? loop;
  final NgHeartbeat? heartbeat;

  /// The gateway's hash of the visible state.
  final String revision;

  /// Null when the session has none of the three.
  static NgSessionControl? parse(Object? json) {
    if (json is! Map) return null;
    final goal = NgGoal.parse(json['goal']);
    final loop = NgLoop.parse(json['loop']);
    final heartbeat = NgHeartbeat.parse(json['heartbeat']);
    if (goal == null && loop == null && heartbeat == null) return null;
    return NgSessionControl(
      goal: goal,
      loop: loop,
      heartbeat: heartbeat,
      revision: _str(json['revision']) ?? '',
    );
  }
}

/// The `session.control` actions, by the wire string the gateway takes.
enum NgControlAction {
  goalPause('goal.pause'),
  goalResume('goal.resume'),
  goalClear('goal.clear'),
  goalUnwait('goal.unwait'),
  loopPause('loop.pause'),
  loopResume('loop.resume'),
  loopStop('loop.stop'),
  heartbeatPause('heartbeat.pause'),
  heartbeatResume('heartbeat.resume'),
  heartbeatClear('heartbeat.clear'),
  subgoalAdd('subgoal.add'),
  subgoalRemove('subgoal.remove'),
  subgoalClear('subgoal.clear');

  const NgControlAction(this.wire);
  final String wire;
}

String? _str(Object? v) {
  if (v is! String) return null;
  return v;
}

String? _text(Object? v) {
  if (v is! String && v is! num) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

int? _int(Object? v) => v is num ? v.toInt() : null;
double? _double(Object? v) => v is num ? v.toDouble() : null;

enum NgSubagentStatus {
  queued,
  running,
  done,
  failed,
  interrupted;

  bool get live => this == queued || this == running;
}

/// A delegated child agent, as its relayed `subagent.*` events describe it.
class NgSubagent {
  NgSubagent(this.id, {this.parentId, this.goal = '', DateTime? startedAt})
    : startedAt = startedAt ?? DateTime.now();

  final String id;
  String? parentId;
  String goal;
  NgSubagentStatus status = NgSubagentStatus.running;
  int taskIndex = 0;
  String? model;
  int? toolCount;

  /// Its tool calls, oldest first (the latest few).
  final List<String> activity = [];

  /// Its latest thinking line while it runs.
  String? thinking;
  String? summary;
  double? durationSeconds;
  final DateTime startedAt;
  DateTime? finishedAt;

  /// What it's doing right now, for the one-line glance.
  String? get current => thinking ?? activity.lastOrNull;

  static const maxActivity = 24;

  static NgSubagentStatus eventStatus(
    Object? status, {
    required bool terminal,
  }) => switch (status) {
    'completed' || 'ok' => NgSubagentStatus.done,
    'failed' || 'error' || 'timeout' => NgSubagentStatus.failed,
    'interrupted' || 'cancelled' || 'canceled' => NgSubagentStatus.interrupted,
    'queued' => terminal ? NgSubagentStatus.failed : NgSubagentStatus.queued,
    _ => terminal ? NgSubagentStatus.failed : NgSubagentStatus.running,
  };
}

/// Folds one `subagent.*` event into [list]; returns the subagent touched.
NgSubagent? ngApplySubagentEvent(
  List<NgSubagent> list,
  String type,
  Map<String, dynamic> p,
) {
  String? str(String key) {
    final v = p[key];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  final id =
      str('subagent_id') ??
      '${str('parent_id') ?? 'root'}:${p['task_index'] ?? 0}:${str('goal') ?? ''}';
  var agent = list.where((a) => a.id == id).firstOrNull;
  final terminal = type == 'subagent.complete';
  if (agent == null) {
    agent = NgSubagent(id, parentId: str('parent_id'));
    list.add(agent);
  }
  agent.parentId = str('parent_id') ?? agent.parentId;
  final goal = str('goal');
  if (goal != null) {
    agent.goal = goal;
  } else if (agent.goal.isEmpty &&
      (type == 'subagent.spawn_requested' || type == 'subagent.start')) {
    agent.goal = str('text') ?? '';
  }
  agent.status = type == 'subagent.spawn_requested'
      ? (agent.status == NgSubagentStatus.running && agent.activity.isNotEmpty
            ? agent.status
            : NgSubagentStatus.queued)
      : NgSubagent.eventStatus(p['status'], terminal: terminal);
  if (p['task_index'] is num) {
    agent.taskIndex = (p['task_index'] as num).toInt();
  }
  agent.model = str('model') ?? agent.model;
  if (p['tool_count'] is num) {
    agent.toolCount = (p['tool_count'] as num).toInt();
  }
  if (type == 'subagent.tool') {
    final name = str('tool_name');
    if (name != null) {
      final preview = (str('tool_preview') ?? str('text') ?? '').replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      final line = preview.isEmpty ? name : '$name: $preview';
      if (agent.activity.lastOrNull != line) agent.activity.add(line);
      if (agent.activity.length > NgSubagent.maxActivity) {
        agent.activity.removeAt(0);
      }
    }
  }
  if (agent.activity.isEmpty && p['output_tail'] is List) {
    for (final tail in p['output_tail'] as List) {
      if (tail is Map && tail['tool'] != null) {
        agent.activity.add('${tail['tool']}');
      }
    }
  }
  agent.thinking = switch (type) {
    'subagent.thinking' =>
      (str('text')?.replaceAll(RegExp(r'\s+'), ' ')) ?? agent.thinking,
    'subagent.tool' || 'subagent.complete' => null,
    _ => agent.thinking,
  };
  if (terminal) {
    agent.summary = str('summary') ?? agent.summary;
    agent.finishedAt = DateTime.now();
  }
  if (p['duration_seconds'] is num) {
    agent.durationSeconds = (p['duration_seconds'] as num).toDouble();
  }
  return agent;
}

/// `subagent.list` snapshots, for children already running on attach.
void ngApplySubagentSnapshots(List<NgSubagent> list, Object? snapshots) {
  if (snapshots is! List) return;
  for (final s in snapshots) {
    if (s is! Map) continue;
    final id = s['subagent_id']?.toString().trim() ?? '';
    if (id.isEmpty) continue;
    var agent = list.where((a) => a.id == id).firstOrNull;
    if (agent == null) {
      agent = NgSubagent(id);
      list.add(agent);
    }
    agent.parentId = s['parent_id']?.toString() ?? agent.parentId;
    final goal = s['goal']?.toString().trim() ?? '';
    if (goal.isNotEmpty) agent.goal = goal;
    if (s['status'] != null) {
      agent.status = NgSubagent.eventStatus(s['status'], terminal: false);
    }
    agent.model = s['model']?.toString() ?? agent.model;
    if (s['tool_count'] is num) {
      agent.toolCount = (s['tool_count'] as num).toInt();
    }
    final last = s['last_tool']?.toString().trim() ?? '';
    if (agent.activity.isEmpty && last.isNotEmpty) agent.activity.add(last);
  }
}
