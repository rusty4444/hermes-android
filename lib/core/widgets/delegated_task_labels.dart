import '../l10n/l10n.dart';
import '../models/gateway_insight.dart';
import '../services/delegated_task_history.dart';

String taskHistoryProblemLabel(
  AppLocalizations l10n,
  TaskHistoryProblem problem,
) => switch (problem) {
  TaskHistoryProblem.invalidReference => l10n.task_invalid_reference,
  TaskHistoryProblem.authRequired => l10n.task_auth_required,
  TaskHistoryProblem.authRejected => l10n.task_auth_rejected,
  TaskHistoryProblem.incompatible => l10n.task_incompatible_history,
  TaskHistoryProblem.identityUnproven => l10n.task_identity_unproven,
  TaskHistoryProblem.partialCompression => l10n.task_partial_compression,
  TaskHistoryProblem.partialAncestors => l10n.task_partial_ancestors,
  TaskHistoryProblem.missingReference => l10n.task_missing_reference,
  TaskHistoryProblem.missingRowIdentity => l10n.task_missing_row_identity,
  TaskHistoryProblem.notReady => l10n.task_history_not_ready,
  TaskHistoryProblem.refreshFailed => l10n.task_refresh_failed,
};

String delegatedTaskGoal(AppLocalizations l10n, GatewaySubagentActivity task) =>
    task.goal.isEmpty ? l10n.task_default_goal : task.goal;

String delegatedTaskStatus(
  AppLocalizations l10n,
  GatewaySubagentActivity task,
) => switch (task.status ?? task.phase.name) {
  'completed' => l10n.status_completed,
  'failed' || 'error' => l10n.status_failed,
  'interrupted' => l10n.task_status_interrupted,
  'cancelled' => l10n.task_status_cancelled,
  'requested' => l10n.task_status_requested,
  'thinking' => l10n.task_status_thinking,
  'tool' => l10n.task_status_tool,
  'pending' => l10n.task_status_pending,
  'dispatched' => l10n.task_status_dispatched,
  'running' => l10n.status_running,
  final status => l10n.task_status_unknown(status),
};

String taskTranscriptRole(AppLocalizations l10n, String role) => switch (role) {
  'assistant' => l10n.task_role_assistant,
  'user' => l10n.task_role_user,
  'tool' => l10n.task_role_tool,
  'system' => l10n.system,
  _ => role,
};
