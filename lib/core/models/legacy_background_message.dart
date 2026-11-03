/// Presentation-only compatibility for old untyped machine messages.
/// Prefer backend display kinds; text matching never authenticates authorship.
/// Use bounded field scans and fixed template boundaries, not wildcard regexes.
abstract final class LegacyBackgroundMessage {
  static bool isTask(String body) {
    final text = body.replaceAll('\r\n', '\n');
    return _fixedTasks.contains(text) ||
        _isModelSwitch(text) ||
        _isPersonalitySwitch(text) ||
        _isMcpReload(text) ||
        _isDeliveryMirror(text) ||
        _isDelegationResult(text) ||
        _taskTemplates.any((template) => template.matches(text));
  }

  static bool isProcess(String body) {
    final text = body.replaceAll('\r\n', '\n');
    if (!_singleBracketFrame(text)) return false;
    if (_processNotices.any((template) => template.matches(text))) return true;
    final newline = text.indexOf('\n');
    if (newline < 0) return false;
    final header = text.substring(0, newline);
    String outputLabel;
    if (_isProcessCompletionHeader(header)) {
      outputLabel = '\nOutput:\n';
    } else if (_isWatchHeader(header)) {
      outputLabel = '\nMatched output:\n';
    } else if (_isProcessHeartbeatHeader(header)) {
      outputLabel = '\nOutput since last heartbeat:\n';
    } else {
      return false;
    }
    var command = newline + 1;
    if (!text.startsWith('Command: ', command)) {
      final attribution = text.substring(command);
      if (!attribution.startsWith('Started by subagent sa-') &&
          !attribution.startsWith(
            'Handed off to you by a subagent before it finished. Purpose: ',
          )) {
        return false;
      }
      final boundary = text.indexOf('\nCommand: ', command);
      if (boundary < 0) return false;
      command = boundary + 1;
    }
    final output = text.indexOf(outputLabel, command + 'Command: '.length);
    return output > command + 'Command: '.length;
  }

  // Stop at the FIRST complete outer frame. A later human message/Android
  // context footer must not make a greedy match swallow the real request.
  // Ambiguous old output with unbalanced brackets requires server metadata.
  static bool _singleBracketFrame(String text) {
    if (!text.startsWith('[') || !text.endsWith(']')) return false;
    var depth = 0;
    for (var index = 0; index < text.length; index++) {
      switch (text.codeUnitAt(index)) {
        case 91:
          depth++;
        case 93:
          depth--;
          if (depth == 0) return index == text.length - 1;
          if (depth < 0) return false;
      }
    }
    return false;
  }

  static bool _digits(String text) =>
      text.isNotEmpty &&
      text.codeUnits.every((unit) => unit >= 48 && unit <= 57);

  static bool _singleLine(String text) =>
      !text.contains('\n') && !text.contains('\r');
  static bool _headerField(String text) =>
      _singleLine(text) && !text.contains('[') && !text.contains(']');
  static bool _token(String text) => _singleLine(text) && !text.contains(' ');
  static bool _signedInteger(String text) =>
      _digits(text.startsWith('-') ? text.substring(1) : text);
  static bool _attempt(String text) {
    final parts = text.split('/');
    return parts.length == 2 && parts.every(_digits);
  }

  static bool _loopTick(String text) {
    var end = 0;
    while (end < text.length &&
        text.codeUnitAt(end) >= 48 &&
        text.codeUnitAt(end) <= 57) {
      end++;
    }
    return end > 0 && _headerField(text);
  }

  static bool _isModelSwitch(String text) {
    const prefix = '[System: The active model for this chat has changed to ';
    const suffix =
        '. From this point forward, use this runtime metadata when '
        'answering questions about what model/provider is active.]';
    if (!_TextEnvelope(prefix, suffix).matches(text)) return false;
    final name = text.substring(prefix.length, text.length - suffix.length);
    return !name.contains('\n') && !name.contains('[') && !name.contains(']');
  }

  static bool _isPersonalitySwitch(String text) =>
      const _TextEnvelope(
        "[System: The user has changed the assistant's personality. From this "
            'point forward, adopt the following persona and respond accordingly: ',
        ']',
      ).matches(text) &&
      _singleBracketFrame(text);

  static bool _isMcpReload(String text) {
    const prefix = '[IMPORTANT: MCP servers have been reloaded. ';
    const suffix =
        '. The tool list for this conversation has been updated accordingly.]';
    if (!_TextEnvelope(prefix, suffix).matches(text) ||
        !_singleBracketFrame(text)) {
      return false;
    }
    final body = text.substring(prefix.length, text.length - suffix.length);
    if (body.contains('\n')) return false;
    final boundary = body.lastIndexOf('. ');
    final value = boundary < 0 ? body : body.substring(boundary + 2);
    if (value == 'No MCP tools available') return true;
    const tools = ' MCP tool(s) now available';
    return value.endsWith(tools) &&
        _digits(value.substring(0, value.length - tools.length));
  }

  static bool _isDeliveryMirror(String text) {
    for (final prefix in ['[Cron delivery: ', '[Webhook delivery: ']) {
      if (!text.startsWith(prefix)) continue;
      final boundary = text.indexOf(']\n', prefix.length);
      if (boundary <= prefix.length || boundary + 2 >= text.length) {
        return false;
      }
      final name = text.substring(prefix.length, boundary);
      return !name.contains('\n') && !name.contains('[') && !name.contains(']');
    }
    return false;
  }

  static bool _isProcessCompletionHeader(String header) {
    const prefix = '[IMPORTANT: Background process ';
    if (!header.startsWith(prefix) || !header.endsWith(').')) return false;
    final idEnd = header.indexOf(' ', prefix.length);
    if (idEnd <= prefix.length) return false;
    final exit = header.lastIndexOf(' (exit code ');
    if (exit <= idEnd + 1) return false;
    final status = header.substring(idEnd + 1, exit);
    if (!const {
          'completed normally',
          'exited',
          'marked lost because the process backend disappeared',
          'failed to start',
        }.contains(status) &&
        !(status.startsWith('terminated by ') &&
            status.length > 'terminated by '.length)) {
      return false;
    }
    var code = header.substring(
      exit + ' (exit code '.length,
      header.length - 2,
    );
    if (code.endsWith(', SIGTERM')) {
      code = code.substring(0, code.length - ', SIGTERM'.length);
    }
    return code == '?' ||
        _digits(code.startsWith('-') ? code.substring(1) : code);
  }

  static bool _isWatchHeader(String header) {
    const prefix = '[IMPORTANT: Background process ';
    if (!header.startsWith(prefix) || !header.endsWith('".')) return false;
    final idEnd = header.indexOf(' ', prefix.length);
    return idEnd > prefix.length &&
        header.startsWith(' matched watch pattern "', idEnd) &&
        header.length > idEnd + ' matched watch pattern "'.length + 2;
  }

  static bool _isProcessHeartbeatHeader(String header) {
    const prefix = '[Background process ';
    const suffix =
        's when there is new output; you will also be told when it exits).';
    if (!header.startsWith(prefix) || !header.endsWith(suffix)) return false;
    final idEnd = header.indexOf(' ', prefix.length);
    if (idEnd <= prefix.length || !header.startsWith(' heartbeat #', idEnd)) {
      return false;
    }
    final sequenceStart = idEnd + ' heartbeat #'.length;
    final age = header.indexOf(' — still running after ', sequenceStart);
    final interval = header.lastIndexOf(' (next in ');
    return age > sequenceStart &&
        _digits(header.substring(sequenceStart, age)) &&
        interval > age + ' — still running after '.length &&
        _digits(
          header.substring(
            interval + ' (next in '.length,
            header.length - suffix.length,
          ),
        );
  }

  static bool _header(String line, String kind) {
    final prefix = '[ASYNC DELEGATION $kind — ';
    if (!line.startsWith(prefix) || !line.endsWith(']')) return false;
    final id = line.substring(prefix.length, line.length - 1);
    return id.isNotEmpty && !id.contains('[') && !id.contains(']');
  }

  static bool _isDelegationResult(String text) {
    if (!text.startsWith('[ASYNC DELEGATION ')) return false;
    final lines = text.split('\n');
    if (lines.length < 3) return false;
    if (_header(lines.first, 'TASK FAILED')) return _isDelegationFailure(lines);
    if (_header(lines.first, 'COMPLETE')) {
      if (lines[1] != _singleDelegationIntro) return false;
      var hasGoal = false;
      var hasRole = false;
      for (var index = 2; index < lines.length - 1; index++) {
        final line = lines[index];
        if (line.startsWith('Original goal: ')) hasGoal = true;
        if (hasGoal && _isDelegationRole(line)) hasRole = true;
        // A literal delimiter can occur inside the goal/context. Inspect every
        // candidate once and accept only one following the complete preamble.
        if (hasRole && line == '--- RESULT ---') {
          final status = lines[index - 1];
          if (status.startsWith('Status: ') &&
              status.contains('   API calls: ') &&
              status.contains('   Duration: ')) {
            return true;
          }
        }
      }
      return false;
    }
    if (!_header(lines.first, 'BATCH COMPLETE') ||
        !_TextEnvelope(
          _batchIntroPrefix,
          _batchIntroSuffix,
        ).matches(lines[1])) {
      return false;
    }
    var hasRole = false;
    var hasTaskHeader = false;
    for (var index = 2; index < lines.length - 1; index++) {
      final line = lines[index];
      if (_isDelegationRole(line, batch: true)) hasRole = true;
      if (!hasRole) continue;
      if (line == '--- ERROR ---') return true;
      if (_batchTaskStart(line)) {
        hasTaskHeader = true;
      }
      if (hasTaskHeader &&
          line.contains('  (status=') &&
          line.endsWith(') ---')) {
        return true;
      }
    }
    return false;
  }

  static bool _isDelegationRole(String line, {bool batch = false}) {
    if (!line.startsWith('Role: ')) return false;
    const modelLabel = '   Model: ';
    final model = line.indexOf(modelLabel, 6);
    if (model <= 6 || model + modelLabel.length >= line.length) return false;
    if (!batch) return true;
    const durationLabel = '   Total duration: ';
    final duration = line.indexOf(durationLabel, model + modelLabel.length);
    return duration > model + modelLabel.length &&
        duration + durationLabel.length < line.length - 1 &&
        line.endsWith('s');
  }

  static bool _batchTaskStart(String line) {
    for (final prefix in ['--- ✓ TASK ', '--- ✗ TASK ', '--- ⚠ TASK ']) {
      if (!line.startsWith(prefix)) continue;
      final colon = line.indexOf(': ', prefix.length);
      return colon > prefix.length &&
          _attempt(line.substring(prefix.length, colon));
    }
    return false;
  }

  static bool _isDelegationFailure(List<String> lines) {
    if (lines[1] != _failedDelegationIntro) return false;
    final address = lines.first.substring(0, lines.first.length - 1);
    final task = address.lastIndexOf(', task ');
    if (task < 0) return false;
    final numbers = address.substring(task + ', task '.length).split('/');
    if (numbers.length != 2 || !numbers.every(_digits)) return false;
    var status = -1;
    for (var index = 2; index < lines.length; index++) {
      if (lines[index].startsWith('Status: ') &&
          lines[index].contains('   Duration: ') &&
          lines[index].endsWith('s')) {
        status = index;
      }
    }
    if (status < 2 || status > 2 && !lines[2].startsWith('Task: ')) {
      return false;
    }
    var tail = status + 1;
    if (tail < lines.length && lines[tail].startsWith('Error: ')) tail++;
    if (tail < lines.length && lines[tail].startsWith('Live transcript: ')) {
      tail++;
    }
    return tail == lines.length;
  }

  static const _singleDelegationIntro =
      'A background subagent you dispatched earlier has finished. You may '
      'have moved on since dispatching it; the full task source is below so '
      'you can act on the result or re-dispatch if things have changed.';
  static const _batchIntroPrefix =
      'A background fan-out unit you dispatched earlier — ';
  static const _batchIntroSuffix =
      ' — has finished; its consolidated results are below. '
      'Any other units from the same delegate_task call report separately as they finish. '
      'You may have moved on since dispatching — act on these or re-dispatch if things have '
      'changed. If you are still waiting on siblings, end your turn after acting on this one.';
  static const _failedDelegationIntro =
      'One subagent in a background fan-out you dispatched has failed while its '
      "siblings are still running. The batch's consolidated results will still arrive "
      'when the last sibling finishes; this is an early warning so you can '
      're-dispatch or investigate now instead of then.';

  static const _fixedTasks = {
    '[System: The previous response was cut off by a network error mid-stream — '
        'a transport interruption, NOT a change in your capabilities. Your tools '
        'are still fully available; call them as normal and ignore any earlier '
        'claim that you lack tool access. Continue the task from where you left '
        'off. Do not restart or repeat prior text.]',
    '[System: The previous response was cut off by a network error mid-stream. '
        'Continue exactly where you left off. Do not restart or repeat prior '
        'text. Finish the answer directly.]',
    '[System: Your previous response was truncated by the output length limit. '
        'Continue exactly where you left off. Do not restart or repeat prior '
        'text. Finish the answer directly.]',
    '[System: Your previous response contained only internal reasoning and never '
        'produced a visible answer or tool call. Do not keep thinking. Produce '
        'your final answer as plain text now (or make the tool call you were '
        'planning).]',
    '[System: Continue now. Execute the required tool calls and only send your '
        'final answer after completing the task.]',
    '[System: Your previous message ended the turn with a fragment that is not '
        'a usable answer. If the task is unfinished, continue it and then give '
        'the complete answer. If that fragment WAS your complete answer, send '
        'it again exactly as before.]',
    'Your previous turn indicated a tool call but none was included. Do not '
        'narrate a plan or restate intent — issue the actual tool call now to '
        'continue the task.',
    'You just executed tool calls but returned an empty response. Please process '
        'the tool results above and continue with the task.',
    'Continue from the compressed conversation context above. This marker '
        'exists because no human user turn was available.',
    'Continue from the compressed conversation context above. This marker '
        'exists because the compacted transcript contained no preserved user turn.',
    "You've reached the maximum number of tool-calling iterations allowed. "
        'Please provide a final response summarizing what you\'ve found and '
        'accomplished so far, without calling any more tools.',
    '(imported conversation begins with an assistant reply)',
    '[System: The user has cleared the personality overlay. From this point '
        'forward, respond in your normal default style.]',
    // hermes_cli/cli_commands_mixin.py: /browser connect and disconnect notices.
    '[System note: The user invoked /browser connect and connected your browser '
        'tools to a Chromium-family dev/debug browser via Chrome DevTools '
        'Protocol. Your browser_navigate, browser_snapshot, browser_click, and '
        'other browser tools now control that CDP browser. The command itself '
        'is a signal that using browser tools for their current browser-related '
        'request is expected; do not wait for separate permission just because '
        'CDP is connected. This is typically a Hermes-managed isolated debug '
        "profile, not the user's main everyday browser. It is still user-visible "
        'and may contain pages, logged-in sessions, or cookies in that debug '
        'profile, so avoid destructive actions, closing tabs, or navigating away '
        "unless the user's task calls for it.]",
    '[System note: The user has disconnected the browser tools from their live '
        'Chromium-family browser. Browser tools are back to default mode '
        '(headless local browser or cloud provider).]',
  };
  // Source-defined literal templates; a fixed number of indexOf scans makes
  // malformed large messages linear. See the backend fixture capture tool.
  static const _taskTemplates = <_TextEnvelope>[
    // dropped_large_tool
    _TextEnvelope(
      "[System: Your previous tool call (",
      ") was too large and the stream timed out before it could be delivered. Do NOT retry "
          "the same tool call with the same large content. Instead, break the content into "
          "multiple smaller tool calls (e.g. use multiple patch calls or write smaller files). "
          "Each tool call's arguments must be under ~8K tokens to avoid stream timeouts. The "
          "cut was a transport interruption, not a capability change — your tools remain fully "
          "available.]",
      validators: {0: _singleLine},
    ),
    // legacy_auto_continue
    _TextEnvelope(
      "[System note: Your previous turn was interrupted mid-run — the app or its backend "
          "process stopped before the turn could finish. Some of the work may already be "
          "complete; check the current state before redoing anything, then finish the task. The"
          " interrupted request was:]\n\n",
      "",
    ),
    // heartbeat
    _TextEnvelope(
      "[Heartbeat — recurring instruction, fires every ",
      "\n\nIf there is nothing meaningful to do or report for this instruction right now, "
          "reply briefly that nothing has changed and stop — do not invent work.",
      between: ["]\n"],
      validators: {0: _headerField},
    ),
    // continuation_prompt_template
    _TextEnvelope(
      "[Continuing toward your standing goal]\nGoal: ",
      "\n\nContinue working toward this goal. Take the next concrete step. If you believe the"
          " goal is complete, state so explicitly and stop. If you are blocked and need input "
          "from the user, say so clearly and stop.",
    ),
    // continuation_prompt_with_contract_template
    _TextEnvelope(
      "[Continuing toward your standing goal]\nGoal: ",
      "\n\nContinue working toward the outcome above. Take the next concrete step. Stay "
          "within the stated boundaries and do not violate the constraints. Before claiming the"
          " goal is done, satisfy the Verification criterion and show the concrete evidence "
          "(command output, file contents, test result). If you hit the stated stop condition "
          "or are otherwise blocked and need user input, say so clearly and stop.",
      between: ["\n\nCompletion contract:\n"],
    ),
    // continuation_prompt_with_subgoals_template
    _TextEnvelope(
      "[Continuing toward your standing goal]\nGoal: ",
      "\n\nContinue working toward the goal AND all additional criteria. Take the next "
          "concrete step. If you believe the goal and every additional criterion are complete, "
          "state so explicitly and stop. If you are blocked and need input from the user, say "
          "so clearly and stop.",
      between: ["\n\nAdditional criteria the user added mid-loop:\n"],
    ),
    // continuation_prompt_gate_failed_template
    _TextEnvelope(
      "[Continuing toward your standing goal — a quality gate failed]\nGoal: ",
      "\n```\n\nFix the underlying problem so this gate passes, then re-run it to confirm. Do "
          "not declare the goal complete while any gate fails. If the gate itself is wrong or "
          "cannot pass, say so clearly and stop.",
      between: [
        "\n\nThe quality gate command below must pass before this goal can be declared done, "
            "and it just failed (attempt ",
        "):\n  \$ ",
        "\nExit code: ",
        "\nOutput (tail):\n```\n",
      ],
      allowEmptyLastField: true,
      validators: {1: _attempt, 2: _singleLine, 3: _signedInteger},
    ),
    // wakeup_prompt_template
    _TextEnvelope(
      "[/loop wakeup #",
      "\n\nThis is an automatic wakeup from the /loop the user set. Perform the task now "
          "against the CURRENT state (re-check files, processes, or services fresh — do not "
          "assume anything from earlier iterations still holds). Report concisely what you "
          "found or did this iteration.\nIf the task is now complete, no longer applicable, or "
          "the thing you were watching has finished, say so and end your reply with "
          "LOOP_COMPLETE on its own line — that stops the loop.",
      between: ["]\nRecurring task: "],
      validators: {0: _loopTick},
    ),
    // wakeup_prompt_with_until_template
    _TextEnvelope(
      "[/loop wakeup #",
      "\n\nThis is an automatic wakeup from the /loop the user set. Perform the task now "
          "against the CURRENT state (re-check files, processes, or services fresh — do not "
          "assume anything from earlier iterations still holds). Report concisely what you "
          "found or did this iteration, and show concrete evidence of the stop condition's "
          "status.\nIf the stop condition is met, or the task is no longer applicable, say so "
          "and end your reply with LOOP_COMPLETE on its own line — that stops the loop.",
      between: ["]\nRecurring task: ", "\n\nStop condition: "],
      validators: {0: _loopTick},
    ),
    // output_contract_retry
    _TextEnvelope(
      "Your previous final response was rejected by the output contract validator. "
          "Validation errors:\n- ",
      "\n\nReply with ONLY the corrected JSON object matching the OUTPUT CONTRACT schema from"
          " your task context. No prose, no explanations.",
    ),
    // late_lsp_diagnostics
    _TextEnvelope(
      "[System note: the language server reported problems in files you edited this turn, "
          "after those tool results had returned. Fix them if they are real, then give your "
          "final answer.]\n\n",
      "",
    ),
    // kanban_recovery
    _TextEnvelope(
      "[System: the previous turn ended UNFINISHED — the API call failed after all retries "
          "and the turn was interrupted (recovery attempt ",
      "` is still `running`. This is the SAME session, with your full context — nothing you"
          " already read, wrote, or computed is lost. Do NOT start over.\n\nDo this immediately:\n"
          "1. If the interrupted turn was mid tool-call, re-check the on-disk state of whatever"
          " it was writing before continuing (the action may not have executed).\n2. Continue "
          "the task from where it stopped and finish any remaining deliverable.\n3. End with a "
          "terminal `kanban_complete(summary=..., artifacts=[...])` if the work is done, or "
          "`kanban_block(reason=...)` if you are blocked.]",
      between: ["). Error: ", ".\n\nTask `"],
      validators: {0: _attempt, 1: _singleLine, 2: _singleLine},
    ),
  ];

  static const _processNotices = <_TextEnvelope>[
    // watch_disabled
    _TextEnvelope(
      "[IMPORTANT: Watch patterns disabled for process ",
      "Falling back to notify_on_complete semantics; you'll get exactly one notification "
          "when the process exits.]",
      between: [" — "],
      validators: {0: _token, 1: _singleLine},
    ),
    // watch_overflow_tripped
    _TextEnvelope(
      "[IMPORTANT: Watch-pattern overflow: >",
      "s.]",
      between: [
        " notifications in ",
        "s across all processes. Suppressing further watch_match events for ",
      ],
      validators: {0: _digits, 1: _digits, 2: _digits},
    ),
    // watch_overflow_released
    _TextEnvelope(
      "[IMPORTANT: Watch-pattern notifications resumed. ",
      " match event(s) were suppressed during the flood.]",
      validators: {0: _digits},
    ),
  ];
}

class _TextEnvelope {
  const _TextEnvelope(
    this.prefix,
    this.suffix, {
    this.between = const [],
    this.allowEmptyLastField = false,
    this.validators = const {},
  });
  final String prefix;
  final String suffix;
  final List<String> between;
  final bool allowEmptyLastField;
  final Map<int, bool Function(String)> validators;

  bool matches(String text) {
    if (!text.startsWith(prefix) || !text.endsWith(suffix)) return false;
    final end = text.length - suffix.length;
    var cursor = prefix.length;
    var field = 0;
    for (final literal in between) {
      final next = text.indexOf(literal, cursor);
      if (next <= cursor || next + literal.length > end) return false;
      if (!_validField(field++, text.substring(cursor, next))) return false;
      cursor = next + literal.length;
    }
    if (!(allowEmptyLastField ? cursor <= end : cursor < end)) return false;
    return _validField(field, text.substring(cursor, end));
  }

  bool _validField(int index, String value) =>
      validators[index]?.call(value) ?? true;
}
