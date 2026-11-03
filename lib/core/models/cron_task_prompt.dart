import '../utils/session_sources.dart';

/// Display compatibility for scheduled-job setup persisted as an ordinary user
/// row. This is not provenance/authentication: explicit display metadata and
/// human/merged rows must be handled by the caller before these text fallbacks.
abstract final class CronTaskPrompt {
  static bool matches(String body, {Object? sessionId}) {
    final text = body.replaceAll('\r\n', '\n');
    if (text.startsWith(_cronHint)) return true;

    final skillBody = _skillBodyStart(text);
    if (skillBody == null) return false;
    final instruction = text.lastIndexOf(_instruction);
    if (instruction >= skillBody) {
      // Current scheduler assembly appends its entire cron hint at this exact
      // boundary. A normal /skill instruction must remain human input.
      return text.startsWith(_cronHint, instruction + _instruction.length);
    }
    // Older scheduled runs embedded skills followed directly by the job prompt,
    // without the hint or instruction marker. Never infer this from the skill
    // header alone: genuine slash-skill commands use the identical scaffold.
    return sessionId is String && isLegacyCronSessionId(sessionId);
  }

  static int? _skillBodyStart(String text) {
    if (!text.startsWith(_skillPrefix)) return null;
    final nameEnd = text.indexOf('"', _skillPrefix.length);
    if (nameEnd <= _skillPrefix.length) return null;
    final name = text.substring(_skillPrefix.length, nameEnd);
    if (name.contains('\n') || name.contains('[') || name.contains(']')) {
      return null;
    }
    if (!text.startsWith(_skillSuffix, nameEnd)) return null;
    final start = nameEnd + _skillSuffix.length;
    return text.substring(start).trim().isNotEmpty ? start : null;
  }

  static const _skillPrefix = '[IMPORTANT: The user has invoked the "';
  static const _skillSuffix =
      '" skill, indicating they want you to follow its instructions. '
      'The full skill content is loaded below.]\n\n';
  static const _instruction =
      '\nThe user has provided the following instruction alongside the skill invocation: ';

  // cron/scheduler_prompt.py::_CRON_HINT. Match the complete, fixed envelope,
  // not a loose cron phrase or a hint quoted anywhere inside a skill document.
  static const _cronHint =
      '[IMPORTANT: You are running as a scheduled cron job. '
      'DELIVERY: Your final response will be automatically delivered '
      'to the user — do NOT use send_message or try to deliver '
      'the output yourself. Just produce your report/output as your '
      'final response and the system handles the rest. '
      'SILENT: If there is genuinely nothing new to report, respond '
      'with exactly "[SILENT]" (nothing else) to suppress delivery. '
      '[SILENT] is a literal ASCII control token — never translate or '
      'rephrase it, whatever language the rest of your answer uses. '
      'Never combine [SILENT] with content — either report your '
      'findings normally, or say [SILENT] and nothing more. '
      'FAILURE: If a delegated child fails and this cron run must be '
      'recorded as failed, put [CRON_FAILURE] on the first line by itself, '
      'then explain the child failure on following lines. '
      'RECURSION: This is a run of an EXISTING scheduled job — execute '
      'the task now. NEVER create or update a cron job because of '
      'recurring or future-schedule language in the task prompt below; '
      'treat phrasing like "each Monday" or "every day at 9" as '
      'context for this run, not as a request to schedule another job.]\n\n';
}
