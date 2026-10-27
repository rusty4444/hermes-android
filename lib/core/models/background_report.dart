import 'dart:math' as math;

import 'legacy_background_message.dart';
import 'legacy_lcm_summary.dart';

enum BackgroundReportKind { task, process }

typedef _TaskListCandidate = ({
  String status,
  bool hasActiveTask,
  int contentLength,
});

/// Display-only background report, never a change to the model/request history.
/// Prefer server annotations; old standalone runtime notices and todo snapshots
/// need conservative compatibility matching because they lack durable metadata.
/// Quoted headers and mixed human messages are not classified by prefix alone.
class BackgroundReport {
  const BackgroundReport._({
    required this.kind,
    required this.body,
    required this.summary,
    required this.hasIssues,
  });

  final BackgroundReportKind kind;
  final String body;
  final String? summary;
  final bool hasIssues;

  static BackgroundReport? fromMessage(Map<String, dynamic> message) {
    final metadata = message['display_metadata'];
    final fields = metadata is Map ? metadata : const {};
    if (fields['model_only'] == true || message['display_kind'] == 'hidden') {
      return null;
    }
    var kind = switch (message['display_kind']) {
      'async_delegation_complete' => BackgroundReportKind.task,
      'process_complete' => BackgroundReportKind.process,
      'model_switch' ||
      'personality_switch' ||
      'auto_continue' ||
      'internal_notification' when message['role'] == 'user' =>
        BackgroundReportKind.task,
      _ => null,
    };
    // A public replacement (including null/empty) must not expose the private
    // carrier. Keep the raw row untouched and classify its public text only.
    final hasProjection = message.containsKey('display_content');
    final body = hasProjection
        ? message['display_content']
        : message['content'];
    if (body is! String || body.isEmpty) return null;
    if (kind == null) {
      // Explicit unknown/human kinds and public projections outrank heuristics.
      // A backend user-row merge can deliberately drop a notice's kind. Its
      // absorbed identity/prefix means the body is no longer standalone: an
      // open result envelope must not consume the appended human request.
      if (hasProjection ||
          _isMergedMessage(message) ||
          (message['display_kind'] != null && message['display_kind'] != '')) {
        return null;
      }
      final role = message['role'];
      // LCM alternates its synthetic summary role around the leading context
      // anchor. Neither assistant nor user means this is a conversation turn.
      if ((role == 'assistant' || role == 'agent' || role == 'user') &&
          LegacyLcmSummary.matches(body)) {
        kind = BackgroundReportKind.task;
      } else if (role != 'user') {
        return null;
      } else if (_isPreservedTaskList(body) ||
          LegacyBackgroundMessage.isTask(body)) {
        kind = BackgroundReportKind.task;
      } else if (LegacyBackgroundMessage.isProcess(body)) {
        kind = BackgroundReportKind.process;
      } else {
        return null;
      }
    }

    final displayText = fields['display_text'];
    // Bound only the preview, never the original body (including whitespace,
    // literal escapes and tool-looking markup).
    final preview = displayText is String
        ? String.fromCharCodes(displayText.runes.take(240)).trim()
        : '';
    final failed = fields['failed_count'];
    final total = fields['task_count'];
    final completed = fields['completed_count'];
    return BackgroundReport._(
      kind: kind,
      body: body,
      summary: preview.isEmpty ? null : preview,
      hasIssues:
          fields['has_issues'] == true ||
          (failed is int && failed > 0) ||
          (total is int &&
              total > 0 &&
              completed is int &&
              completed >= 0 &&
              completed < total),
    );
  }

  static bool _isMergedMessage(Map<String, dynamic> message) {
    final prefix = message['_merged_turn_prefix'];
    if (prefix is String && prefix.isNotEmpty) return true;
    for (final key in ['absorbed_message_uids', '_absorbed_message_uids']) {
      final witness = message[key];
      // SessionDB exposes JSON text; live message identity uses a list. Treat
      // any nonempty encoded witness conservatively without parsing its IDs.
      if (witness is List && witness.isNotEmpty ||
          witness is String && witness.isNotEmpty && witness != '[]') {
        return true;
      }
    }
    return false;
  }

  static const _taskListHeader =
      '[Your active task list was preserved across context compression]';
  static const _skillReloadHeader =
      '[Skills pruned during compression — reload before acting on these tasks]';
  static final _taskPrefix = RegExp(
    r'^(?:  )*- \[([ >x~])\] [^\r\n]+?\. (?=\S)',
  );
  static final _skillReloadNotice = RegExp(
    '^${RegExp.escape(_skillReloadHeader)}\n'
    r'The task list above crossed the compression boundary verbatim, but '
    r'the skill instructions that governed it were pruned\. Before '
    r'executing any preserved task that depends on these skills, reload '
    r"them first: skill_view\(name='[^'\r\n]+'\)"
    r"(?:; skill_view\(name='[^'\r\n]+'\))*\. After reloading, re-check that each pending "
    r'task is still justified — findings recorded before the boundary may have invalidated it\.$',
  );

  static bool _isPreservedTaskList(String body) {
    if (!body.startsWith('$_taskListHeader\n') &&
        !body.startsWith('$_taskListHeader\r\n')) {
      return false;
    }
    // Parse a copy only. The complete original body stays available on expansion.
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    final noticeIndex = lines.lastIndexOf(_skillReloadHeader);
    if (noticeIndex >= 3 &&
        lines[noticeIndex - 1].isEmpty &&
        _skillReloadNotice.hasMatch(lines.skip(noticeIndex).join('\n'))) {
      lines.removeRange(noticeIndex - 1, lines.length);
    }
    var candidates = <_TaskListCandidate>{};
    var lastLine = '';
    bool completeItem(_TaskListCandidate candidate) {
      final suffix = ' (${candidate.status})';
      return lastLine.endsWith(suffix) &&
          candidate.contentLength > suffix.length;
    }

    for (var index = 1; index < lines.length; index++) {
      final line = lines[index];
      final completed = candidates.where(completeItem).toList();
      // A checkbox-shaped line may be description text, even after a status-like
      // suffix. Keep both readings until the entire snapshot validates. Lengths
      // saturate just beyond each suffix, bounding the candidate set.
      candidates = {
        for (final candidate in candidates)
          (
            status: candidate.status,
            hasActiveTask: candidate.hasActiveTask,
            contentLength: math.min(
              candidate.contentLength + line.length + 1,
              ' (${candidate.status})'.length + 1,
            ),
          ),
      };
      final prefix = _taskPrefix.firstMatch(line);
      if (prefix != null && (index == 1 || completed.isNotEmpty)) {
        final status = switch (prefix.group(1)) {
          '>' => 'in_progress',
          ' ' => 'pending',
          'x' => 'completed',
          _ => 'cancelled',
        };
        candidates.add((
          status: status,
          hasActiveTask:
              status == 'pending' ||
              status == 'in_progress' ||
              completed.any((candidate) => candidate.hasActiveTask),
          contentLength: math.min(
            line.length - prefix.end,
            ' ($status)'.length + 1,
          ),
        ));
      }
      lastLine = line;
    }
    return candidates.any(
      (candidate) => candidate.hasActiveTask && completeItem(candidate),
    );
  }
}
