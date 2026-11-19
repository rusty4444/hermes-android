// One open NextGen chat: the transcript from the dashboard's REST history,
// then the live session over `/api/ws` (tui_gateway/contracts/events.py).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random, max;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/models/attachment_draft.dart';
import '../../core/models/background_report.dart';
import '../../core/models/legacy_lcm_summary.dart';
import '../../core/services/attachment_draft_service.dart';
import '../../core/services/ws_client.dart';
import 'history_rows.dart';
import 'nextgen_gateway.dart';
import 'session_control.dart';
import '../nextgen_l10n.dart';

/// The gateway outcome for a per-chat model pick.
sealed class NgModelSwitchResult {
  const NgModelSwitchResult();
}

class NgModelSwitchDone extends NgModelSwitchResult {
  final String? resolvedModel;
  final Map<String, dynamic>? info;
  const NgModelSwitchDone({this.resolvedModel, this.info});
}

class NgModelSwitchDeferred extends NgModelSwitchResult {
  final String? resolvedModel;
  final Map<String, dynamic>? info;
  const NgModelSwitchDeferred({this.resolvedModel, this.info});
}

class NgModelSwitchNeedsConfirmation extends NgModelSwitchResult {
  final String message;
  const NgModelSwitchNeedsConfirmation(this.message);
}

class NgModelSwitchFailed extends NgModelSwitchResult {
  final String message;
  final bool clearConfirmation;
  const NgModelSwitchFailed(this.message, {this.clearConfirmation = true});
}

/// One tool call inside a reply.
class NgTool {
  final String id;
  String name;
  String? detail;
  bool running;
  String? summary;
  double? durationSeconds;
  String? input;
  String? output;
  bool failed;

  /// When the call started and finished, for the row's timestamp.
  DateTime? startedAt;
  DateTime? finishedAt;

  NgTool({
    required this.id,
    required this.name,
    this.detail,
    this.running = false,
    this.summary,
    this.durationSeconds,
    this.input,
    this.output,
    this.failed = false,
    this.startedAt,
    this.finishedAt,
  });
}

/// Kyllene's inline limit: anything larger than this goes over HTTP to the
/// gateway's upload instead of inside one WebSocket message.
const ngMaxInlineAttachmentBytes = 12 * 1000 * 1000;

/// The folder under the managed files' home that uploads wait in.
const ngUploadsFolder = '.ares-uploads';

/// [name] as one path segment the gateway finds again: no folders, no `..`,
/// no characters `file.attach` expands or its path checks turn down.
String ngSafeUploadName(String name) {
  final base = name.split('/').last.split(r'\').last;
  var cleaned = base
      .split('')
      .where((c) {
        final unit = c.codeUnitAt(0);
        return unit >= 0x20 && unit != 0x7f && !'<>:"|?*\$%'.contains(c);
      })
      .join()
      .replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  if (cleaned.isEmpty) cleaned = 'attachment';
  if (cleaned.length > 200) {
    cleaned = cleaned.substring(0, 200).replaceAll(RegExp(r'[ .]+$'), '');
  }
  const devices = {'CON', 'PRN', 'AUX', 'NUL'};
  final stem = cleaned.split('.').first.toUpperCase();
  final device =
      devices.contains(stem) || RegExp(r'^(COM|LPT)[1-9]$').hasMatch(stem);
  return device ? '_$cleaned' : cleaned;
}

/// Separates a prompt's `@file:` attachment lines from its text.
(String, List<String>) splitFileRefs(String text) {
  final files = <String>[];
  final kept = <String>[];
  for (final line in text.split('\n')) {
    final match = RegExp(r'^\s*@file:(\S.*)$').firstMatch(line);
    if (match == null) {
      kept.add(line);
      continue;
    }
    var ref = match.group(1)!.trim();
    if (ref.length > 1 && ref.startsWith('`') && ref.endsWith('`')) {
      ref = ref.substring(1, ref.length - 1);
    }
    files.add(ref.split('/').last);
  }
  return (kept.join('\n').trim(), files);
}

/// Rows per history page, as Kyllene's `HISTORY_PAGE`.
const ngHistoryPage = 60;

/// Tool input/output kept per call; the view shows 4000 characters, so
/// multi-megabyte outputs need not sit in memory.
const ngStoredToolChars = 16000;

String? ngCapStored(String? text) =>
    text == null || text.length <= ngStoredToolChars
    ? text
    : '${text.substring(0, ngStoredToolChars)}…';

/// Bounds JSON serialization: compact-encode first, and only pretty-print
/// when the result fits the cap. Avoids formatting multi-MB maps on the UI
/// thread just to immediately truncate them.
String? ngBoundedToolJson(String? text, Object? value) {
  if (text != null) return text;
  if (value == null) return null;
  final compact = jsonEncode(value);
  if (compact.length > ngStoredToolChars) return compact;
  return const JsonEncoder.withIndent('  ').convert(value);
}

/// A full page starts mid-turn more often than not: drop the rows before its
/// first prompt so the turn shows whole once the next page brings them.
/// A page that is all one turn stays as it is.
List<Map<String, dynamic>> ngFromFirstTurn(List<Map<String, dynamic>> page) {
  final first = page.indexWhere((r) => r['role']?.toString() == 'user');
  return first <= 0 ? page : page.sublist(first);
}

sealed class NgItem {
  final String key;
  NgItem(this.key);
}

class NgUserItem extends NgItem {
  String text;
  final DateTime? time;

  /// Sent while the agent worked: steered into the running turn.
  final bool steered;

  /// Sent but the gateway hasn't confirmed it yet / refused it.
  bool pending;
  String? failure;

  /// Files sent with the prompt (kept until it is accepted, for Retry).
  final List<AttachmentDraft> attachments;

  /// Names of files a stored prompt referenced (`@file:` lines).
  final List<String> files;

  /// Client-generated UUID for `prompt.submit` idempotency on modern gateways.
  final String? submissionId;

  NgUserItem(
    super.key,
    this.text, {
    this.time,
    this.steered = false,
    this.pending = false,
    this.attachments = const [],
    this.files = const [],
    this.submissionId,
  });
}

class NgAssistantItem extends NgItem {
  String text = '';
  String reasoning = '';
  final List<NgTool> tools = [];
  bool open;
  DateTime? time;
  int? inputTokens;
  int? outputTokens;

  NgAssistantItem(super.key, {this.open = true, this.time});

  bool get isEmpty => text.isEmpty && reasoning.isEmpty && tools.isEmpty;
}

class NgNoticeItem extends NgItem {
  final String text;
  final bool error;
  DateTime? time;
  NgNoticeItem(super.key, this.text, {this.error = false, this.time});
}

/// What a collapsed system card is about.
enum NgSystemKind { task, process, note, summary }

/// Background results and runtime notices the agent receives as messages:
/// a finished background process, a delegated-task batch, a model fallback.
/// They are long and meant for the model, so they show collapsed.
class NgSystemItem extends NgItem {
  final NgSystemKind kind;
  final String body;
  final String? summary;
  final bool hasIssues;
  bool expanded = false;
  DateTime? time;
  NgSystemItem(
    super.key, {
    required this.kind,
    required this.body,
    this.summary,
    this.hasIssues = false,
  });

  /// One line for the collapsed card: the server's summary, else the first
  /// line of the body without its bracketed label.
  String get preview {
    final given = summary?.trim() ?? '';
    if (given.isNotEmpty) return given;
    for (final raw in body.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      line = line
          .replaceFirst(RegExp(r'^\[+'), '')
          .replaceFirst(RegExp(r'\]+$'), '')
          .replaceFirst(RegExp(r'^(IMPORTANT|System|SYSTEM|NOTE)\s*:\s*'), '')
          .trim();
      if (line.isEmpty) continue;
      return line.length > 160 ? '${line.substring(0, 160)}…' : line;
    }
    return '';
  }
}

/// Classifies a history row (or a live notice) that the agent, not the
/// person, wrote: a collapsed card, or null when it is ordinary text.
NgSystemItem? ngSystemItemFor(String key, Map<String, dynamic> row) {
  final report = BackgroundReport.fromMessage(row);
  if (report != null) {
    // LCM context summaries get their own collapsed "Summary" card.
    final isLcm =
        report.kind == BackgroundReportKind.task &&
        LegacyLcmSummary.matches(report.body);
    return NgSystemItem(
      key,
      kind: isLcm
          ? NgSystemKind.summary
          : report.kind == BackgroundReportKind.process
          ? NgSystemKind.process
          : NgSystemKind.task,
      body: report.body,
      summary: report.summary,
      hasIssues: report.hasIssues,
    );
  }
  return null;
}

/// Short notices stay a centred line; long or multi-line ones collapse.
bool ngNoticeIsLong(String text) =>
    text.length > 160 || text.trim().contains('\n');

/// A queued prompt, sent when the running turn ends.
class NgQueued {
  final String key;
  final String text;
  NgQueued(this.key, this.text);
}

enum NgRequestKind { approval, clarify, secret, saveLogin }

class NgClarifyQuestion {
  final String? qid;
  final String question;
  final List<String> choices;
  final bool multiSelect;
  const NgClarifyQuestion(
    this.qid,
    this.question,
    this.choices,
    this.multiSelect,
  );
}

/// Something the agent is blocked on until the user answers.
class NgInputRequest {
  final NgServerRequest request;
  final NgRequestKind kind;
  final String title;
  final String body;
  final String? command;
  final List<String> choices;
  final List<NgClarifyQuestion> questions;
  final bool masked;

  NgInputRequest._(
    this.request, {
    required this.kind,
    required this.title,
    this.body = '',
    this.command,
    this.choices = const [],
    this.questions = const [],
    this.masked = true,
  });

  static List<String> _strings(Object? value) => value is List
      ? value
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList()
      : const [];

  static NgInputRequest? parse(NgServerRequest request) {
    final p = request.params;
    String s(String key) => p[key]?.toString() ?? '';
    switch (request.method) {
      case 'approval':
        final offered = _strings(p['choices']);
        final choices = <String>{'once'};
        if (offered.isNotEmpty) {
          choices.addAll(offered);
        } else if (p['smart_denied'] != true && p['allow_session'] != false) {
          choices.add('session');
          if (p['allow_permanent'] != false) choices.add('always');
        }
        choices.add('deny');
        const order = ['once', 'session', 'always', 'deny'];
        return NgInputRequest._(
          request,
          kind: NgRequestKind.approval,
          title: ngL.ng_allow_this_command,
          body: s('description').isNotEmpty
              ? s('description')
              : s('tool_name').isNotEmpty
              ? ngL.ng_hermes_wants_to_run_this_with(s('tool_name'))
              : ngL.ng_hermes_wants_to_run_this,
          command: s('command'),
          choices: order.where(choices.contains).toList(),
        );
      case 'clarify':
        final batch = <NgClarifyQuestion>[];
        final raw = p['questions'];
        if (raw is List) {
          for (final q in raw) {
            if (q is! Map || q['qid'] == null) continue;
            batch.add(
              NgClarifyQuestion(
                q['qid'].toString(),
                q['question']?.toString() ?? '',
                _strings(q['choices']),
                q['multi_select'] == true,
              ),
            );
          }
        }
        if (batch.isEmpty && s('question').isNotEmpty) {
          batch.add(
            NgClarifyQuestion(
              null,
              s('question'),
              _strings(p['choices']),
              p['multi_select'] == true,
            ),
          );
        }
        if (batch.isEmpty) return null;
        return NgInputRequest._(
          request,
          kind: NgRequestKind.clarify,
          title: batch.length == 1
              ? ngL.ng_hermes_has_a_question
              : ngL.ng_hermes_has_questions,
          questions: batch,
        );
      case 'sudo':
        return NgInputRequest._(
          request,
          kind: NgRequestKind.secret,
          title: ngL.ng_password_for_sudo,
          body: ngL.ng_hermes_needs_your_sudo_password_to,
          command: s('command'),
        );
      case 'secret':
        return NgInputRequest._(
          request,
          kind: NgRequestKind.secret,
          title: s('env_var').isNotEmpty ? s('env_var') : ngL.ng_a_secret_value,
          body: s('prompt').isNotEmpty
              ? s('prompt')
              : ngL.ng_value_for(s('env_var')),
        );
      case 'vault.unlock_prompt':
        final name = s('display_name').isNotEmpty
            ? s('display_name')
            : s('backend').isNotEmpty
            ? s('backend')
            : ngL.ng_your_password_manager;
        return NgInputRequest._(
          request,
          kind: NgRequestKind.secret,
          title: ngL.ng_unlock(name),
          body: ngL.ng_hermes_needs_unlocked_to_sign_in(name),
        );
      case 'vault.code':
        final site = s('site');
        return NgInputRequest._(
          request,
          kind: NgRequestKind.secret,
          title: ngL.ng_sign_in_code,
          body: [
            site.isEmpty
                ? ngL.ng_enter_the_sign_in_code
                : ngL.ng_enter_the_sign_in_code_for(site),
            if (s('hint').isNotEmpty) s('hint'),
          ].join(' '),
          masked: false,
        );
      case 'vault.save_login':
        final site = s('site').isNotEmpty ? s('site') : s('origin');
        return NgInputRequest._(
          request,
          kind: NgRequestKind.saveLogin,
          title: site.isEmpty
              ? ngL.ng_save_a_login
              : ngL.ng_save_your_login(site),
          body: s('origin'),
        );
    }
    return null;
  }
}

/// Usage and cost for the chat (`session.usage`).
class NgUsage {
  final int input;
  final int output;
  final int reasoning;
  final int cacheRead;
  final double? cost;
  final int? contextUsed;
  final int? contextMax;
  final int calls;
  const NgUsage({
    this.input = 0,
    this.output = 0,
    this.reasoning = 0,
    this.cacheRead = 0,
    this.cost,
    this.contextUsed,
    this.contextMax,
    this.calls = 0,
  });

  static int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static NgUsage? parse(Object? raw) {
    if (raw is! Map) return null;
    final cost = raw['estimated_cost_usd'] ?? raw['cost_usd'] ?? raw['cost'];
    return NgUsage(
      input: _i(raw['input_tokens'] ?? raw['input']),
      output: _i(raw['output_tokens'] ?? raw['output']),
      reasoning: _i(raw['reasoning_tokens'] ?? raw['reasoning']),
      cacheRead: _i(raw['cache_read_tokens'] ?? raw['cache_read']),
      cost: cost is num ? cost.toDouble() : double.tryParse('$cost'),
      contextUsed: raw['context_used'] is num
          ? (raw['context_used'] as num).toInt()
          : raw['context_tokens'] is num
          ? (raw['context_tokens'] as num).toInt()
          : null,
      contextMax: raw['context_max'] is num
          ? (raw['context_max'] as num).toInt()
          : raw['context_length'] is num
          ? (raw['context_length'] as num).toInt()
          : null,
      calls: _i(raw['api_calls'] ?? raw['calls']),
    );
  }
}

class NgChatController extends ChangeNotifier {
  NgChatController(
    this.gateway, {
    String? sessionId,
    this.title = '',
    this.workingDirectory,
    this.onCreated,
    this.onTurnFinished,
    AttachmentDraftService? attachmentService,
  }) : storedId = sessionId,
       attachmentService = attachmentService ?? AttachmentDraftService() {
    _subs.add(gateway.events.listen(_onEvent));
    _subs.add(gateway.serverRequests.listen(_onServerRequest));
    _subs.add(gateway.reconnected.listen((_) => unawaited(_reattach())));
  }

  final NextGenGateway gateway;
  final String? workingDirectory;

  /// Prepares and caches composer attachments (shared with classic chat).
  final AttachmentDraftService attachmentService;

  /// The stored session id (`/api/sessions`), null until the first send.
  String? storedId;

  /// The live session id on the current socket.
  String? runtimeId;

  String title;
  final List<NgItem> items = [];
  final List<NgQueued> queued = [];
  bool running = false;
  bool loadingHistory = false;

  /// Earlier rows remain on the gateway; [loadOlder] fetches the next page.
  bool hasOlder = false;
  bool loadingOlder = false;

  /// Ids of the stored rows behind the transcript, oldest first; their
  /// count is the baseline offset (from the newest) of the next older page,
  /// raised by [_olderShift] for rows a page re-served. Only ids are kept:
  /// the rows themselves can be megabytes of tool output.
  final List<String?> _rowIds = [];

  /// A live turn's rows are stored by now, but the transcript shows that
  /// turn as the aggregate it streamed into. [_adoptPersistedIds] walks the
  /// newest pages after the turn ends and adopts the ids at the tail, so
  /// paging treats those rows as shown instead of re-inserting them as
  /// older items.
  bool _adopting = false;

  /// Rows a page re-served because a live turn appended rows after the
  /// window was built. A live turn persists rows while the reader is
  /// scrolled back, moving the newest end under [_rowIds.length]; carrying
  /// the overlap forward keeps every next offset behind the oldest row of
  /// the last page, so paging advances a full page per fetch and an
  /// all-known page cannot occur from growth alone. Reset with the window.
  int _olderShift = 0;

  Future<List<Map<String, dynamic>>> _fetchRows(
    String id, {
    required int limit,
    int offset = 0,
  }) async => ngDecodeHistory(
    await gateway.api.getMessagesBytes(
      id,
      limit: limit,
      offset: offset,
      latest: true,
    ),
  );
  String? historyError;
  String? status;
  String? thinkingFrame;
  String? error;
  NgInputRequest? request;
  String? model;
  String? provider;
  String? reasoningEffort;
  NgUsage? usage;
  DateTime? turnStartedAt;

  /// The agent's plan, shown above the composer (Kyllene's task list).
  NgTodoList? todos;

  /// [todos] was written by the turn running now, not kept from an earlier
  /// one; a past plan shows folded as "Last plan".
  bool todosLive = false;

  /// The session's goal, loop and heartbeat (Kyllene's control strip).
  NgSessionControl? control;

  /// The control action in flight, and the last one's failure.
  NgControlAction? controlBusy;
  String? controlError;

  /// Delegated child agents this chat has seen (Kyllene's subagent dock).
  final List<NgSubagent> subagents = [];

  /// When the current batch of subagents started: the dock lists those
  /// since, so one delegation's finished siblings stay beside its live ones.
  DateTime? subagentBatchStart;

  /// The subagents the dock shows while any of them is still live.
  List<NgSubagent> get dockSubagents {
    final start = subagentBatchStart;
    if (start == null || !subagents.any((a) => a.status.live)) return const [];
    return [
      for (final a in subagents)
        if (a.status.live || !a.startedAt.isBefore(start)) a,
    ];
  }

  bool _controlUnsupported = false;

  final void Function(String storedId)? onCreated;
  final void Function()? onTurnFinished;

  final List<StreamSubscription<dynamic>> _subs = [];
  int _seq = 0;
  bool _disposed = false;
  bool _attaching = false;
  Completer<void>? _attachCompleter;
  int? _revision;
  int? _executionGeneration;

  String _key(String prefix) => '$prefix-${_seq++}';

  /// Coalesces high-frequency streaming deltas to one notification per frame.
  /// Terminal events (turn end, errors, requests) use [_changedNow] instead.
  bool _framePending = false;
  void _changed() {
    if (_disposed || _framePending) return;
    _framePending = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _framePending = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Immediate notification for terminal/lifecycle events.
  void _changedNow() {
    if (_disposed) return;
    _framePending = false;
    notifyListeners();
  }

  bool get isNew => storedId == null;

  /// Loads the transcript, then attaches to the live session.
  Future<void> open() async {
    final id = storedId;
    if (id == null) {
      unawaited(_ensureInfo());
      return;
    }
    loadingHistory = true;
    historyError = null;
    _changed();
    try {
      final messages = await _fetchRows(id, limit: ngHistoryPage);
      if (_disposed) return;
      _setRows(messages, ngHistoryPage);
      // A page of hidden or tool-only rows shows nothing: reach back a few
      // pages for something to show rather than an empty chat.
      for (var i = 0; i < 4 && items.isEmpty && hasOlder && !_disposed; i++) {
        loadingHistory = false;
        await loadOlder();
        loadingHistory = true;
      }
    } catch (e) {
      historyError = ngL.ng_couldn_t_load_this_chat(e);
    } finally {
      loadingHistory = false;
      _changed();
    }
    await _attach();
  }

  Future<void> _ensureInfo() async {
    try {
      final info = await gateway.dashboard.getModelInfo();
      model ??= info['model']?.toString();
      provider ??= info['provider']?.toString();
      _changed();
    } catch (_) {
      // The model chip shows "Default" until a session reports one.
    }
  }

  Future<void> _attach() async {
    final id = storedId;
    if (id == null || _disposed) return;
    if (_attaching) {
      await _attachCompleter?.future;
      return;
    }
    _attaching = true;
    final attaching = Completer<void>();
    _attachCompleter = attaching;
    try {
      await gateway.connected();
      final result = await gateway.call('session.resume', {
        'session_id': id,
        'source': 'desktop',
        'omit_messages': true,
        'defer_history': true,
        // The canonical resume model forbids inline_images (#291).
        if (!gateway.sessionAuthority) 'inline_images': false,
      });
      _withAuthority(result);
      runtimeId = result['session_id']?.toString() ?? runtimeId;
      if (runtimeId != null) gateway.bindRuntime(runtimeId!, id);
      final wasRunning = running;
      running = result['running'] == true;
      if (running && !wasRunning) turnStartedAt ??= DateTime.now();
      _withInfo(result['info']);
      _withTodos(NgTodoList.parse(result['todo_state']));
      _attachedOnce = true;
      unawaited(refreshControl());
      unawaited(refreshSubagents());
      final open = result['open_requests'];
      if (open is List && open.isNotEmpty) {
        gateway.socket?.deliverOpenRequests(open);
      }
      // Requests that arrived before this chat bound its runtime id.
      for (final pending in gateway.openRequests.values) {
        _onServerRequest(pending);
      }
      _changed();
    } catch (e) {
      if (!_disposed) {
        error = ngL.ng_live_updates_are_unavailable(_clean(e));
        _changed();
      }
    } finally {
      _attaching = false;
      if (!attaching.isCompleted) attaching.complete();
      _attachCompleter = null;
    }
  }

  static int? _authorityInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _withAuthority(Map<String, dynamic> raw) {
    _adoptRevision(raw['revision']);
    _adoptExecutionGeneration(raw['execution_generation']);
  }

  void _adoptRevision(Object? value, {bool authoritative = false}) {
    final next = _authorityInt(value);
    if (next == null) return;
    if (authoritative || _revision == null || next > _revision!) {
      _revision = next;
    }
    final retained = _retainedModelMutation;
    final expected = _authorityInt(retained?['expected_revision']);
    if (retained != null && expected != null && expected < next) {
      final payload = retained['payload'];
      final sentToken = payload is Map ? payload['confirm']?.toString() : null;
      _clearRetainedModelMutation();
      if (sentToken != null && sentToken == _modelConfirmationToken) {
        _clearModelConfirmation();
      }
    }
  }

  void _adoptExecutionGeneration(Object? value) {
    final next = _authorityInt(value);
    if (next == null) return;
    if (_executionGeneration == null || next > _executionGeneration!) {
      _executionGeneration = next;
    }
  }

  static String _clean(Object e) => e
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '')
      .replaceFirst(RegExp(r'^JsonRpcError\([^)]*\): '), '');

  void _withInfo(Object? raw) {
    if (raw is! Map) return;
    final m = raw['model']?.toString();
    if (m != null && m.isNotEmpty) model = m;
    final p = raw['provider']?.toString();
    if (p != null && p.isNotEmpty) provider = p;
    if (raw.containsKey('reasoning_effort')) {
      final r = raw['reasoning_effort']?.toString() ?? '';
      reasoningEffort = r.isEmpty ? null : r;
    }
    final t = raw['title']?.toString();
    if (t != null && t.trim().isNotEmpty) title = t;
    usage = NgUsage.parse(raw['usage']) ?? usage;
  }

  // ── History ─────────────────────────────────────────────────────────

  static String _plain(Object? content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) {
            if (part is String) return part;
            if (part is Map) {
              final type = part['type']?.toString() ?? '';
              if (type.contains('image')) return '[image]';
              // Only plain text: a structured `text` value (Kyllene #419)
              // is skipped rather than shown as a Dart map.
              final text = part['text'];
              return text is String ? text : '';
            }
            return '';
          })
          .where((t) => t.isNotEmpty)
          .join('\n');
    }
    if (content is Map) {
      final text = content['text'];
      return text is String ? text : '';
    }
    return '';
  }

  static DateTime? _time(Object? ts) {
    if (ts is num && ts > 0) {
      return DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    }
    return null;
  }

  /// A runtime notice: a centred line when short, else a collapsed card.
  void _addNotice(String text, {DateTime? time, List<NgItem>? into}) {
    final items = into ?? this.items;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final at = time ?? DateTime.now();
    final report = ngSystemItemFor(_key('s'), {
      'role': 'user',
      'content': trimmed,
    });
    if (report != null) {
      items.add(report..time = at);
    } else if (ngNoticeIsLong(trimmed)) {
      items.add(
        NgSystemItem(_key('s'), kind: NgSystemKind.note, body: trimmed)
          ..time = at,
      );
    } else {
      items.add(NgNoticeItem(_key('n'), trimmed, time: at));
    }
  }

  @visibleForTesting
  void debugApplyHistory(
    List<Map<String, dynamic>> messages, {
    int? pageLimit,
  }) => _setRows(messages, pageLimit ?? messages.length + 1);

  /// Shows [page] (the newest rows, asked for with [limit]) as the whole
  /// transcript.
  void _setRows(List<Map<String, dynamic>> page, int limit) {
    final full = page.length >= limit;
    final rows = full ? ngFromFirstTurn(page) : page;
    hasOlder = full;
    _olderShift = 0;
    _rowIds
      ..clear()
      ..addAll(rows.map((r) => r['id']?.toString()));
    items
      ..clear()
      ..addAll(_itemsFrom(rows));
  }

  /// Loads the page of rows before the oldest one shown, as Kyllene does
  /// when the transcript is scrolled near its top.
  Future<void> loadOlder() async {
    final id = storedId;
    if (id == null || !hasOlder || loadingOlder || loadingHistory) return;
    loadingOlder = true;
    _changed();
    try {
      final offset = _rowIds.length + _olderShift;
      final guardLength = _rowIds.length;
      final guardShift = _olderShift;
      final page = await _fetchRows(id, limit: ngHistoryPage, offset: offset);
      if (_disposed) return;
      // Adoption or a window rebuild during the fetch moved the accounting
      // this page's offset was computed from. Applying it would double-count
      // the adopted rows in the shift; drop it and let the next scroll retry
      // against the current window.
      if (_rowIds.length != guardLength || _olderShift != guardShift) return;
      final full = page.length >= ngHistoryPage;
      final known = _rowIds.whereType<String>().toSet();
      // Rows already shown come again when the chat grew since.
      // Drop rows already shown before trimming: a partially-known page's
      // unseen rows can be the tail of a long turn with no prompt in them,
      // and trimming first would cut exactly those and let the shift
      // advance a whole page past them.
      final unknown = page
          .where((r) => r['id'] == null || !known.contains('${r['id']}'))
          .toList();
      final fresh = full ? ngFromFirstTurn(unknown) : unknown;
      hasOlder = full;
      // Carry the overlap forward: the re-served rows are ones a live turn
      // appended after the window was built, so the next offset must skip
      // them on top of the shown rows instead of pointing back into them.
      // Rows trimmed away below count as neither known nor shown, so the
      // next page re-reads exactly them.
      _olderShift += page.length - unknown.length;
      if (fresh.isNotEmpty) {
        _rowIds.insertAll(0, fresh.map((r) => r['id']?.toString()));
        items.insertAll(0, _itemsFrom(fresh));
      }
    } catch (_) {
      // Scrolling to the top again retries.
    } finally {
      loadingOlder = false;
      _changed();
    }
  }

  /// Adopts the stored ids a finished live turn appended at the newest end.
  /// The transcript already shows the turn as the aggregate it streamed
  /// into, but [_rowIds] never learned those rows, so without this a page
  /// reaching them would re-insert them as older duplicates. Walks newest
  /// pages while the tail is unknown, adopting only the unknown run after
  /// the last known row — unknown rows below it are older history, not yet
  /// shown. The walk has no page cap: it stops at the first known row or a
  /// short page, so a turn of any length is fully adopted. Adopted rows were
  /// being carried by [_olderShift] as unlearned growth, so the shift shrinks
  /// by the adopted count to keep the next offset on real coverage. Best
  /// effort: a window rebuild mid-fetch aborts, and rows that persist between
  /// a fetch and its adopt stay covered by [_olderShift].
  Future<void> _adoptPersistedIds() async {
    final id = storedId;
    if (id == null || _disposed || _adopting) return;
    // An empty trimmed window shows nothing to reconcile against; adopting
    // would mark unseen history as shown. A resync rebuilds the window.
    if (_rowIds.isEmpty) return;
    _adopting = true;
    try {
      var baseline = _rowIds.length;
      for (var page = 0; ; page++) {
        final rows = await _fetchRows(
          id,
          limit: ngHistoryPage,
          offset: page * ngHistoryPage,
        );
        if (_disposed || storedId != id || _rowIds.length != baseline) return;
        final known = _rowIds.whereType<String>().toSet();
        var cut = rows.length;
        while (cut > 0) {
          final rid = rows[cut - 1]['id']?.toString();
          if (rid != null && known.contains(rid)) break;
          cut--;
        }
        if (cut == rows.length) return;
        final adopted = rows.length - cut;
        _rowIds.addAll([
          for (final r in rows.sublist(cut)) r['id']?.toString(),
        ]);
        // The shift was carrying these same rows as unlearned growth; now
        // that they are shown ids, drop them from the shift so the next
        // offset does not overshoot real coverage.
        _olderShift -= adopted;
        if (_olderShift < 0) _olderShift = 0;
        baseline = _rowIds.length;
        if (cut > 0 || rows.length < ngHistoryPage) return;
      }
    } catch (_) {
      // The next turn end or resync tries again; the shift covers the gap.
    } finally {
      _adopting = false;
    }
  }

  List<NgItem> _itemsFrom(List<Map<String, dynamic>> messages) {
    final items = <NgItem>[];
    NgAssistantItem? reply;
    final toolsById = <String, NgTool>{};
    for (final m in messages) {
      final role = m['role']?.toString();
      final displayKind = m['display_kind']?.toString();
      final text = _plain(m['display_content'] ?? m['content']);
      final metadata = m['display_metadata'];
      if (displayKind == 'hidden' ||
          (metadata is Map && metadata['model_only'] == true)) {
        continue;
      }
      // Background results, delegated-task batches, model switches and
      // other runtime notices arrive as rows; show them collapsed.
      final system = ngSystemItemFor(_key('s'), m);
      if (system != null) {
        // A user-role row ends the reply before it, so the card sits where
        // it happened and the next answer starts a new block.
        reply?.open = false;
        reply = null;
        items.add(system..time = _time(m['timestamp']));
        continue;
      }
      // Merged rows: a summary envelope absorbed into an assistant turn.
      // Collapse the envelope; keep the tail as a visible assistant reply.
      if (role == 'assistant' || role == 'agent' || role == 'user') {
        final split = LegacyLcmSummary.splitEnvelope(text);
        if (split != null) {
          reply?.open = false;
          reply = null;
          items.add(
            NgSystemItem(_key('s'), kind: NgSystemKind.summary, body: split.$1)
              ..time = _time(m['timestamp']),
          );
          // The tail is the assistant's real answer; render it normally.
          if (role == 'user') {
            final (body, files) = splitFileRefs(split.$2);
            items.add(
              NgUserItem(
                _key('u'),
                body,
                time: _time(m['timestamp']),
                files: files,
              ),
            );
          } else {
            reply = NgAssistantItem(_key('a'), open: false);
            reply.text = split.$2;
            items.add(reply);
          }
          continue;
        }
      }
      if (role == 'user') {
        if (displayKind != null &&
            displayKind.isNotEmpty &&
            displayKind != 'steer') {
          reply?.open = false;
          reply = null;
          _addNotice(text, time: _time(m['timestamp']), into: items);
          continue;
        }
        if (text.startsWith('[System:')) continue;
        reply?.open = false;
        reply = null;
        final (body, files) = splitFileRefs(text);
        items.add(
          NgUserItem(
            _key('u'),
            body,
            time: _time(m['timestamp']),
            steered: displayKind == 'steer',
            files: files,
          ),
        );
      } else if (role == 'assistant') {
        reply ??= () {
          final r = NgAssistantItem(_key('a'), open: false);
          items.add(r);
          return r;
        }();
        final reasoning =
            (m['display_reasoning'] ?? m['reasoning'])?.toString() ?? '';
        if (reasoning.trim().isNotEmpty) {
          reply.reasoning = reply.reasoning.isEmpty
              ? reasoning
              : '${reply.reasoning}\n\n$reasoning';
        }
        if (text.trim().isNotEmpty) {
          reply.text = reply.text.isEmpty ? text : '${reply.text}\n\n$text';
        }
        reply.time = _time(m['timestamp']) ?? reply.time;
        final calls = m['tool_calls'];
        if (calls is List) {
          for (final call in calls) {
            if (call is! Map) continue;
            final fn = call['function'];
            final id = call['id']?.toString() ?? _key('t');
            final name =
                (fn is Map ? fn['name'] : call['name'])?.toString() ?? 'tool';
            final args = fn is Map ? fn['arguments'] : call['arguments'];
            final tool = NgTool(
              id: id,
              name: name,
              detail:
                  call['label']?.toString() ??
                  (call.containsKey('ng_args_preview')
                      ? call['ng_args_preview']?.toString()
                      : ngArgsPreview(args)),
              input: ngCapStored(
                args is String
                    ? args
                    : (args == null ? null : jsonEncode(args)),
              ),
              startedAt: _time(m['timestamp']),
            );
            toolsById[id] = tool;
            reply.tools.add(tool);
          }
        }
      } else if (role == 'tool') {
        final id = m['tool_call_id']?.toString();
        final tool = id == null ? null : toolsById[id];
        if (tool != null) {
          tool.output = ngCapStored(text);
          tool.summary = _firstLine(text);
          tool.finishedAt = _time(m['timestamp']);
        }
      }
    }
    return items;
  }

  static String? _firstLine(String? text) => ngFirstLine(text);

  // ── Live events ─────────────────────────────────────────────────────

  NgAssistantItem _openReply() {
    final last = items.isNotEmpty ? items.last : null;
    if (last is NgAssistantItem && last.open) return last;
    final reply = NgAssistantItem(_key('a'));
    items.add(reply);
    return reply;
  }

  bool _isMine(StreamEvent event) {
    final id = event.sessionId;
    if (id == null) return false;
    return id == runtimeId || id == storedId;
  }

  // ── Catch-up (Kyllene's ChatSession.catchUp) ──────────────────────────

  /// The last live event applied (`seq`), and the gateway process it was
  /// counted in (`replay_epoch`).
  int? _lastSeq;
  String? _seqEpoch;

  /// Live events held while a catch-up fills a gap, applied after it.
  List<StreamEvent>? _held;

  /// Whether the last turn ended in an error or was stopped, for its
  /// notification.
  bool lastTurnFailed = false;
  bool lastTurnInterrupted = false;

  String? _readyEpoch() {
    final frame = gateway.readyFrame;
    if (frame == null) return null;
    Object? find(Object? m) {
      if (m is! Map) return null;
      return m['replay_epoch'] ?? find(m['payload']) ?? find(m['params']);
    }

    return find(frame)?.toString();
  }

  void _onEvent(StreamEvent event) {
    if (_disposed || !_isMine(event)) return;
    _deliver(event);
  }

  /// Applies a live event in order: one already applied is skipped, and one
  /// past a gap waits, with those after it, while [_catchUp] fills the gap.
  void _deliver(StreamEvent event) {
    final held = _held;
    if (held != null) {
      held.add(event);
      return;
    }
    final seq = event.seq;
    final last = _lastSeq;
    if (seq != null && last != null) {
      if (_seqEpoch != null && _readyEpoch() != _seqEpoch) {
        // The gateway restarted and counts anew: reload rather than trust.
        _held = [event];
        unawaited(_catchUp());
        return;
      }
      if (seq <= last) return;
      if (seq > last + 1) {
        _held = [event];
        unawaited(_catchUp());
        return;
      }
    }
    _applyEvent(event);
  }

  /// Catches the open chat up after the app was away: a backgrounded phone
  /// misses live events, and a socket that never reported a drop stays
  /// "connected", so nothing else would fetch what was missed.
  void resync() {
    if (_disposed || runtimeId == null || storedId == null) return;
    if (_held != null || _attaching) return;
    if (!(gateway.socket?.isConnected ?? false)) return;
    _held = [];
    unawaited(_catchUp(foreground: true));
  }

  /// Re-attaches after the socket came back, then fills what was missed.
  Future<void> _reattach() async {
    if (_disposed) return;
    // The first connect is the chat opening, which reads everything anyway.
    if (!_attachedOnce) {
      await _attach();
      return;
    }
    _held ??= [];
    await _attach();
    await _catchUp();
  }

  bool _attachedOnce = false;

  /// Replays the events after [_lastSeq] from the gateway's ring
  /// (`session.events.since`), then lets held live events through. When the
  /// ring can't (an older gateway, too long away, a restart) the transcript
  /// is read again; a turn that ended meanwhile still finishes here, so its
  /// reply notifies.
  Future<void> _catchUp({bool foreground = false}) async {
    final rt = runtimeId;
    final from = _lastSeq;
    List<StreamEvent>? missed;
    if (rt != null && from != null && _seqEpoch == _readyEpoch()) {
      try {
        final reply = await gateway.call('session.events.since', {
          'session_id': rt,
          'last_seen': from,
        });
        missed = ngParseReplay(reply, rt, from, _seqEpoch);
        final open = reply['open_requests'];
        if (open is List && open.isNotEmpty) {
          gateway.socket?.deliverOpenRequests(open);
        }
      } catch (_) {
        missed = null; // older gateway, or the link went again
      }
    }
    if (_disposed) return;
    if (missed != null) {
      for (final e in missed) {
        _applyEvent(e);
      }
    } else {
      final wasRunning = running;
      // Back mid-turn with nothing to replay: keep the running reply as it
      // shows rather than laying the stale copy over a fresh transcript.
      final keep = foreground && running;
      if (!keep) await _reloadForCatchUp(wasRunning: wasRunning);
      _lastSeq = null;
    }
    if (_disposed) return;
    final held = _held ?? const <StreamEvent>[];
    _held = null;
    for (final e in held) {
      _deliver(e);
    }
    _changed();
  }

  Future<void> _reloadForCatchUp({required bool wasRunning}) async {
    final id = storedId;
    final rt = runtimeId;
    if (id == null) return;
    try {
      // Whether the turn still runs, as the gateway has it now.
      if (rt != null) {
        final result = await gateway.call('session.resume', {
          'session_id': id,
          'source': 'desktop',
          'omit_messages': true,
          'defer_history': true,
          // The canonical resume model forbids inline_images (#291).
          if (!gateway.sessionAuthority) 'inline_images': false,
        });
        _withAuthority(result);
        runtimeId = result['session_id']?.toString() ?? runtimeId;
        running = result['running'] == true;
      }
      // The same window as shown, so a long scroll back isn't lost.
      final limit = max(ngHistoryPage, _rowIds.length).clamp(1, 500);
      final messages = await _fetchRows(id, limit: limit);
      if (_disposed) return;
      final keepQueued = List.of(queued);
      _setRows(messages, limit);
      queued
        ..clear()
        ..addAll(keepQueued);
      if (running) {
        _openReply();
      } else if (wasRunning) {
        // It ended while the app was away.
        lastTurnFailed = false;
        lastTurnInterrupted = false;
        _finishTurn();
      }
    } catch (_) {
      // Live events still come; the next resync tries again.
    }
  }

  void _applyEvent(StreamEvent event) {
    if (event.seq != null) {
      _lastSeq = event.seq;
      _seqEpoch = _readyEpoch();
    }
    final p = event.data;
    _adoptExecutionGeneration(
      event.envelope['execution_generation'] ?? p['execution_generation'],
    );
    String? s(String key) {
      final v = p[key];
      return v?.toString();
    }

    switch (event.type) {
      case 'message.start':
        // A new turn hasn't planned yet; the last plan is from before.
        todosLive = todosLive && running;
        running = true;
        error = null;
        turnStartedAt ??= DateTime.now();
        for (final item in items.whereType<NgUserItem>()) {
          item.pending = false;
        }
        _openReply();
      case 'message.delta':
        final chunk = s('text');
        if (chunk != null && chunk.isNotEmpty) {
          _openReply().text += chunk;
          running = true;
          thinkingFrame = null;
        }
      case 'message.interim':
        if (p['already_streamed'] != true) {
          final chunk = s('text');
          if (chunk != null && chunk.isNotEmpty) {
            _openReply().text += '$chunk\n\n';
          }
        }
      case 'reasoning.delta' || 'reasoning.available':
        final chunk = s('text');
        if (chunk != null) _openReply().reasoning += chunk;
      case 'thinking.delta':
        final frame = s('text')?.trim();
        if (frame != null && frame.isNotEmpty) thinkingFrame = frame;
      case 'tool.start':
        final id = s('tool_id');
        if (id == null) return;
        final reply = _openReply();
        reply.tools.removeWhere((t) => t.id == id);
        reply.tools.add(
          NgTool(
            id: id,
            name: s('name') ?? 'tool',
            detail: s('context') ?? s('preview') ?? ngArgsPreview(p['args']),
            running: true,
            input: ngCapStored(ngBoundedToolJson(s('args_text'), p['args'])),
            startedAt: DateTime.now(),
          ),
        );
        running = true;
        thinkingFrame = null;
      case 'tool.generating':
        final name = s('name');
        if (name != null) thinkingFrame = ngL.ng_preparing(name);
      case 'tool.complete':
        final id = s('tool_id');
        if (id == null) return;
        NgTool? tool;
        for (final item in items.reversed) {
          if (item is NgAssistantItem) {
            for (final t in item.tools) {
              if (t.id == id) tool = t;
            }
            if (tool != null) break;
          }
        }
        tool ??= () {
          final t = NgTool(id: id, name: s('name') ?? 'tool');
          _openReply().tools.add(t);
          return t;
        }();
        tool.running = false;
        tool.finishedAt = DateTime.now();
        tool.summary = s('summary') ?? tool.summary;
        final d = p['duration_s'];
        tool.durationSeconds = d is num ? d.toDouble() : tool.durationSeconds;
        final result = p['result'];
        tool.output = ngCapStored(
          ngBoundedToolJson(
                s('result_text'),
                result is String ? null : result,
              ) ??
              (result is String ? result : tool.output),
        );
        tool.failed =
            result is Map &&
            (result['success'] == false || result['error'] != null);
      case 'status.update':
        final text = s('text');
        status = text == null || text.trim().isEmpty ? null : text;
      case 'session.usage':
        usage = NgUsage.parse(p['usage']) ?? usage;
      case 'todo.updated':
        _withTodos(NgTodoList.parse(p));
      case 'subagent.spawn_requested' ||
          'subagent.start' ||
          'subagent.progress' ||
          'subagent.thinking' ||
          'subagent.tool' ||
          'subagent.complete':
        final wasLive = subagents.any((a) => a.status.live);
        final agent = ngApplySubagentEvent(subagents, event.type, p);
        if (!wasLive && agent != null && agent.status.live) {
          subagentBatchStart = agent.startedAt;
        }
        _trimSubagents();
      case 'session.control.update':
        if (p.containsKey('control')) {
          _withControl(NgSessionControl.parse(p['control']));
        }
      case 'session.updated':
        _adoptRevision(p['revision']);
        if (p['operation'] == 'model' &&
            p['status'] == 'confirmation_required') {
          final committedModel = _nonEmptyString(p['committed_model']);
          if (committedModel != null) model = committedModel;
          final committedProvider = _nonEmptyString(p['committed_provider']);
          if (committedProvider != null) provider = committedProvider;
          final confirmMsg =
              _nonEmptyString(p['confirm_message']) ??
              _nonEmptyString(p['warning']);
          if (confirmMsg != null) error = confirmMsg;
          final token = p['confirm']?.toString();
          final payload = p['payload'];
          final targetModel = payload is Map
              ? payload['model']?.toString()
              : null;
          final targetProvider = payload is Map
              ? payload['provider']?.toString() ?? ''
              : '';
          if (token != null &&
              token.isNotEmpty &&
              targetModel != null &&
              targetModel.isNotEmpty) {
            _modelConfirmationKey = '$targetProvider/$targetModel';
            _modelConfirmationToken = token;
            _modelConfirmationSent = false;
          }
        } else if (p['operation'] == 'model' && p['status'] == 'refused') {
          final committedModel = _nonEmptyString(p['model']);
          if (committedModel != null) model = committedModel;
          final committedProvider = _nonEmptyString(p['provider']);
          if (committedProvider != null) provider = committedProvider;
          final reason =
              _nonEmptyString(p['message']) ?? _nonEmptyString(p['reason']);
          if (reason != null) error = reason;
        } else {
          _withInfo(p['info']);
          final updatedModel = _nonEmptyString(p['model']);
          if (updatedModel != null) model = updatedModel;
          final updatedProvider = _nonEmptyString(p['provider']);
          if (updatedProvider != null) provider = updatedProvider;
        }
      case 'session.info':
        _adoptRevision(p['revision'], authoritative: true);
        _withInfo(p);
      case 'session.title':
        final t = s('title');
        if (t != null && t.trim().isNotEmpty) title = t;
      case 'notice':
        final message = s('message')?.trim();
        if (message != null && message.isNotEmpty) _addNotice(message);
      case 'error':
        error = s('message') ?? ngL.ng_the_turn_failed;
        _finishTurn(failed: true);
      case 'message.complete' || 'turn.end':
        final reply = _openReply();
        final text = s('text');
        if (reply.text.isEmpty && text != null) reply.text = text;
        final u = NgUsage.parse(p['usage']);
        if (u != null) {
          reply.inputTokens = u.input;
          reply.outputTokens = u.output;
        }
        reply.time = DateTime.now();
        final outcome = s('status');
        lastTurnFailed = outcome == 'error';
        lastTurnInterrupted = outcome == 'interrupted';
        _finishTurn(failed: lastTurnFailed);
        unawaited(_adoptPersistedIds());
      case 'turn.error':
        error = s('message') ?? ngL.ng_the_turn_failed;
        lastTurnFailed = true;
        lastTurnInterrupted = false;
        _finishTurn(failed: true);
        unawaited(_adoptPersistedIds());
      case 'request.cancel':
        final id = s('id') ?? s('request_id');
        if (id != null) {
          gateway.forgetRequest(id);
          if (request?.request.id == id) request = null;
        }
      default:
        return;
    }
    // Terminal/lifecycle events notify immediately; streaming deltas coalesce.
    switch (event.type) {
      case 'message.complete' ||
          'turn.end' ||
          'error' ||
          'turn.error' ||
          'request.cancel' ||
          'message.start' ||
          'session.updated' ||
          'session.info' ||
          'session.title' ||
          'notice':
        _changedNow();
      default:
        _changed();
    }
  }

  /// Takes a plan snapshot unless an older one arrived late.
  void _withTodos(NgTodoList? list) {
    if (list == null) return;
    final current = todos;
    if (current != null && list.revision < current.revision) return;
    todos = list.items.isEmpty ? null : list;
    todosLive = running;
  }

  /// Takes a control snapshot; an unchanged revision changes nothing.
  void _withControl(NgSessionControl? next) {
    final current = control;
    if (next != null &&
        current != null &&
        next.revision.isNotEmpty &&
        next.revision == current.revision) {
      return;
    }
    control = next;
  }

  /// Reads the session's goal, loop and heartbeat once, since
  /// `session.resume` doesn't carry them; later changes arrive as
  /// `session.control.update` events. A gateway without the method hides it.
  Future<void> refreshControl() async {
    final id = runtimeId;
    if (id == null || _controlUnsupported || _disposed) return;
    final before = control;
    try {
      final result = await gateway.call('session.control.read', {
        'session_id': id,
      });
      if (_disposed || !identical(control, before)) return;
      if (result.containsKey('control')) {
        _withControl(NgSessionControl.parse(result['control']));
        _changed();
      }
    } on JsonRpcError catch (e) {
      if (e.code == -32601) _controlUnsupported = true;
    } catch (_) {
      // Best effort: the strip stays as it was.
    }
  }

  /// Finished subagents beyond the newest 100 go; live ones stay.
  void _trimSubagents() {
    var finished = subagents.where((a) => !a.status.live).length;
    while (finished > 100) {
      subagents.remove(subagents.firstWhere((a) => !a.status.live));
      finished--;
    }
  }

  /// Subagents already running when this chat attached; their events only
  /// cover what comes next.
  Future<void> refreshSubagents() async {
    final id = runtimeId;
    if (id == null || _disposed) return;
    try {
      final result = await gateway.call('subagent.list', {'session_id': id});
      if (_disposed) return;
      final wasLive = subagents.any((a) => a.status.live);
      ngApplySubagentSnapshots(subagents, result['subagents']);
      if (!wasLive && subagents.any((a) => a.status.live)) {
        subagentBatchStart = subagents
            .where((a) => a.status.live)
            .map((a) => a.startedAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
      }
      _changed();
    } catch (_) {
      // Best effort: older gateways have no list; events still arrive.
    }
  }

  /// Stops one running subagent (`subagent.interrupt`).
  Future<void> stopSubagent(NgSubagent agent) async {
    final id = runtimeId;
    if (id == null) return;
    try {
      await gateway.call('subagent.interrupt', {
        'session_id': id,
        'subagent_id': agent.id,
      });
    } catch (e) {
      error = ngL.ng_couldn_t_stop(_clean(e));
      _changed();
    }
  }

  /// Runs one `session.control` action (pause a goal, add a sub-goal, ...)
  /// and applies the snapshot it returns. A resumed goal's kickoff goes out
  /// as a prompt, queued behind a running turn. Returns whether it worked;
  /// on failure [controlError] says why.
  Future<bool> runControl(
    NgControlAction action, {
    String? text,
    int? index,
  }) async {
    if (controlBusy != null) return false;
    controlBusy = action;
    controlError = null;
    _changed();
    try {
      await _ensureSession();
      final before = control;
      final result = await gateway.call('session.control', {
        'session_id': runtimeId,
        'action': action.wire,
        if (text != null)
          'args': {'text': text}
        else if (index != null)
          'args': {'index': index},
      });
      if (identical(control, before) && result.containsKey('control')) {
        _withControl(NgSessionControl.parse(result['control']));
      }
      final dispatch = result['dispatch'];
      if (dispatch is Map && dispatch['type'] == 'send') {
        final message = dispatch['message']?.toString().trim() ?? '';
        if (message.isNotEmpty) {
          if (running) {
            enqueue(message);
          } else {
            unawaited(send(message));
          }
        }
      }
      return true;
    } catch (e) {
      controlError = _clean(e);
      return false;
    } finally {
      controlBusy = null;
      _changed();
    }
  }

  /// Ends the turn. After a failure, queued prompts wait for the user rather
  /// than being sent into the same error.
  void _finishTurn({bool failed = false}) {
    for (final item in items) {
      if (item is NgAssistantItem) {
        if (item.open) item.time ??= DateTime.now();
        item.open = false;
        for (final t in item.tools) {
          t.running = false;
        }
      }
    }
    // Drop the empty reply a cancelled turn leaves behind.
    if (items.isNotEmpty) {
      final last = items.last;
      if (last is NgAssistantItem && last.isEmpty) items.removeLast();
    }
    running = false;
    todosLive = false;
    status = null;
    thinkingFrame = null;
    turnStartedAt = null;
    request = null;
    onTurnFinished?.call();
    // The goal's judge runs after the turn; pick up its verdict.
    if (control?.goal != null) unawaited(refreshControl());
    if (queued.isNotEmpty && !failed) {
      final next = queued.removeAt(0);
      scheduleMicrotask(() => unawaited(send(next.text)));
    }
  }

  /// Drops the request [id] once it was answered elsewhere (a notification).
  void forgetRequest(String id) {
    if (request?.request.id != id) return;
    request = null;
    _changed();
  }

  void _onServerRequest(NgServerRequest req) {
    if (_disposed) return;
    final id = req.sessionId;
    if (id == null || (id != runtimeId && id != storedId)) return;
    final parsed = NgInputRequest.parse(req);
    if (parsed == null) return;
    request = parsed;
    _changedNow();
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _ensureSession() async {
    if (runtimeId != null && storedId != null) return;
    await gateway.connected();
    final pickedModel = _pickedModel;
    final pickedProvider = _pickedProvider;
    final pickedEffort = _pickedEffort;
    final result = await gateway.call('session.create', {
      // CanonicalCreateParams.source refuses the legacy 'desktop' hint on
      // the authority route; 'gui' is the canonical graphical surface (#291).
      'source': gateway.sessionAuthority ? 'gui' : 'desktop',
      if (workingDirectory != null && workingDirectory!.trim().isNotEmpty)
        'cwd': workingDirectory,
      'model': ?pickedModel,
      if (pickedProvider != null && pickedProvider.trim().isNotEmpty)
        'provider': pickedProvider,
      if (pickedEffort != null)
        if (gateway.sessionAuthority)
          'reasoning': pickedEffort
        else
          'reasoning_effort': pickedEffort,
    });
    _withAuthority(result);
    runtimeId = result['session_id']?.toString();
    storedId = result['stored_session_id']?.toString() ?? runtimeId;
    if (runtimeId != null) gateway.bindRuntime(runtimeId!, storedId!);
    _withInfo(result['info']);
    if (storedId != null) onCreated?.call(storedId!);
    _pickedModel = null;
    _pickedProvider = null;
    _pickedEffort = null;
    if (pickedModel != null) {
      final info = result['info'];
      final actualModel = info is Map ? info['model']?.toString() : null;
      if (actualModel != null && actualModel != pickedModel) {
        final message = ngL.ng_gateway_kept_default_model(actualModel);
        error = message;
        _changed();
        throw StateError(message);
      }
    }
  }

  String? _pickedModel;
  String? _pickedProvider;
  String? _pickedEffort;

  /// Attaches one draft the way Kyllene does and returns the `@file`
  /// reference the prompt must carry, or null for an image, which the
  /// gateway queues onto the next prompt itself:
  ///
  /// * an image up to [ngMaxInlineAttachmentBytes] goes inline with
  ///   `image.attach_bytes`, so the model sees it as an image;
  /// * any other file up to that size goes inline with `file.attach`;
  /// * anything larger streams over HTTP to `/api/files/upload-stream` (up
  ///   to 100 MB) and is attached by its path there, then removed.
  Future<String?> _upload(AttachmentDraft draft, List<String> queued) async {
    draft.status = AttachmentDraftStatus.uploading;
    draft.error = null;
    _changed();
    try {
      if (draft.byteLength > ngMaxInlineAttachmentBytes) {
        final ref = await _uploadStaged(draft);
        draft
          ..status = AttachmentDraftStatus.attached
          ..refText = ref;
        return ref;
      }
      if (draft.isImage) {
        final bytes = await File(draft.cachedPath).readAsBytes();
        final result = await gateway.call('image.attach_bytes', {
          'session_id': runtimeId,
          'content_base64': base64Encode(bytes),
          'filename': draft.name,
        }, timeout: const Duration(minutes: 2));
        if (result['attached'] != true) {
          throw StateError(
            result['message']?.toString() ??
                'The gateway did not attach ${draft.name}.',
          );
        }
        final path = result['path']?.toString();
        if (path != null && path.isNotEmpty) queued.add(path);
        draft.status = AttachmentDraftStatus.attached;
        return null;
      }
      final dataUrl = await attachmentService.readDataUrl(draft);
      final result = await gateway.call('file.attach', {
        'session_id': runtimeId,
        'name': draft.name,
        'path': '',
        'data_url': dataUrl,
      }, timeout: const Duration(minutes: 2));
      final ref = result['ref_text']?.toString() ?? '';
      if (result['attached'] != true || ref.isEmpty) {
        throw StateError('The gateway did not attach ${draft.name}.');
      }
      draft
        ..status = AttachmentDraftStatus.attached
        ..refText = ref;
      return ref;
    } catch (e) {
      draft
        ..status = AttachmentDraftStatus.failed
        ..error = _clean(e);
      rethrow;
    } finally {
      draft.uploadProgress = null;
      _changed();
    }
  }

  /// Puts a file too large for one WebSocket message on the gateway over
  /// HTTP in a folder of its own under the managed files' default folder,
  /// attaches it by that path, then removes the folder (unless `file.attach`
  /// used it in place, which the prompt then refers to).
  Future<String> _uploadStaged(AttachmentDraft draft) async {
    final dashboard = gateway.dashboard;
    final tooLarge = ngL.ng_attachment_too_large_for_gateway(draft.name);
    final listing = await dashboard.apiRequest('GET', 'files');
    if (listing.statusCode == 404 || listing.statusCode == 405) {
      throw StateError(tooLarge);
    }
    String home;
    try {
      home = (jsonDecode(listing.body) as Map)['path']?.toString() ?? '';
    } catch (_) {
      // Not JSON: a gateway from before the managed files.
      throw StateError(tooLarge);
    }
    if (listing.statusCode != 200 || home.isEmpty) {
      throw StateError(ngL.ng_couldn_t_upload(draft.name));
    }
    final sep = !home.contains('/') && home.contains(r'\') ? r'\' : '/';
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    final base = home.replaceFirst(RegExp(r'[/\\]+$'), '');
    final folder = '$base$sep$ngUploadsFolder$sep$id';
    final target = '$folder$sep${ngSafeUploadName(draft.name)}';
    Future<void> removeFolder() async {
      try {
        await dashboard.apiRequest(
          'DELETE',
          'files',
          body: {'path': folder, 'recursive': true},
        );
      } catch (_) {
        // Best effort: a leftover is only a file in the uploads folder.
      }
    }

    var shown = -1;
    final http.Response res;
    try {
      res = await dashboard.apiUploadStream(
        File(draft.cachedPath),
        targetPath: target,
        filename: draft.name,
        mimeType: draft.mediaType,
        onProgress: (sent, total) {
          final percent = total <= 0 ? 0 : (sent * 100 ~/ total);
          if (percent == shown) return;
          shown = percent;
          draft.uploadProgress = percent / 100;
          _changed();
        },
      );
    } catch (_) {
      await removeFolder();
      rethrow;
    }
    if (res.statusCode == 404 || res.statusCode == 405) {
      throw StateError(tooLarge);
    }
    if (res.statusCode != 200) {
      await removeFolder();
      var detail = 'HTTP ${res.statusCode}';
      try {
        detail = (jsonDecode(res.body) as Map)['detail']?.toString() ?? detail;
      } catch (_) {}
      throw StateError('${ngL.ng_couldn_t_upload(draft.name)} $detail');
    }
    var staged = target;
    try {
      final path = (jsonDecode(res.body) as Map)['path']?.toString();
      if (path != null && path.isNotEmpty) staged = path;
    } catch (_) {}
    var usedInPlace = false;
    try {
      final result = await gateway.call('file.attach', {
        'session_id': runtimeId,
        'path': staged,
        'name': draft.name,
      }, timeout: const Duration(minutes: 5));
      final uploaded = result['uploaded'];
      usedInPlace = uploaded is bool
          ? !uploaded
          : result['path']?.toString() == staged;
      final ref = result['ref_text']?.toString() ?? '';
      if (result['attached'] != true || ref.isEmpty) {
        throw StateError('The gateway did not attach ${draft.name}.');
      }
      return ref;
    } finally {
      if (!usedInPlace) await removeFolder();
    }
  }

  /// An image queued on a session that was then un-queued must go up again.
  void _resetQueuedImages(List<AttachmentDraft> drafts) {
    for (final draft in drafts) {
      if (draft.isImage &&
          draft.refText == null &&
          draft.status == AttachmentDraftStatus.attached) {
        draft.status = AttachmentDraftStatus.ready;
      }
    }
  }

  /// Best effort: un-queues images after a send that failed part-way.
  Future<void> _detach(List<String> paths) async {
    for (final path in paths) {
      try {
        await gateway.call('image.detach', {
          'session_id': runtimeId,
          'path': path,
        });
      } catch (_) {
        return; // the socket is likely gone, and the queue with it
      }
    }
  }

  /// Sends [text] (and any [attachments]) as a new prompt. Returns whether
  /// the gateway accepted it; on failure the attachments stay with the
  /// message so Retry can send them again.
  Future<bool> send(
    String text, {
    List<AttachmentDraft> attachments = const [],
    String? submissionId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return false;
    final effectiveSubmissionId = submissionId ?? const Uuid().v4();
    final item = NgUserItem(
      _key('u'),
      trimmed,
      time: DateTime.now(),
      pending: true,
      attachments: List.of(attachments),
      submissionId: effectiveSubmissionId,
    );
    items.add(item);
    error = null;
    running = true;
    turnStartedAt = DateTime.now();
    _changed();
    final queued = <String>[];
    try {
      await _ensureSession();
      final refs = <String>[];
      try {
        for (final draft in item.attachments) {
          final ref = draft.refText ?? await _upload(draft, queued);
          if (ref != null) refs.add(ref);
        }
      } catch (_) {
        await _detach(queued);
        _resetQueuedImages(item.attachments);
        rethrow;
      }
      // Like Desktop and Kyllene: the file references first, then the text.
      final prompt = [
        refs.join('\n'),
        trimmed,
      ].where((part) => part.trim().isNotEmpty).join('\n\n');
      _clearRetainedModelMutation();
      final result = await _submitPromptWithCompatibility({
        'session_id': runtimeId,
        'text': prompt,
      }, submissionId: effectiveSubmissionId);
      item.pending = false;
      final status = result['status']?.toString();
      if (status == 'queued') item.text = trimmed;
      _changed();
      if (item.attachments.isNotEmpty) {
        unawaited(attachmentService.removeAll(item.attachments));
      }
      return true;
    } catch (e) {
      item.pending = false;
      item.failure = _clean(e);
      running = false;
      turnStartedAt = null;
      _changed();
      return false;
    }
  }

  /// Steers the running turn at its next safe boundary.
  Future<void> steer(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || runtimeId == null) return;
    final item = NgUserItem(
      _key('u'),
      trimmed,
      time: DateTime.now(),
      steered: true,
      pending: true,
    );
    items.add(item);
    _changed();
    try {
      await gateway.call('session.steer', {
        'session_id': runtimeId,
        'text': trimmed,
      });
      item.pending = false;
    } catch (e) {
      item.pending = false;
      item.failure = _clean(e);
    }
    _changed();
  }

  /// Queues [text] to send once the running turn ends.
  void enqueue(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    queued.add(NgQueued(_key('q'), trimmed));
    _changed();
  }

  void unqueue(NgQueued item) {
    queued.remove(item);
    _changed();
  }

  /// Stops the running turn.
  Future<void> stop() async {
    final id = runtimeId;
    if (id == null) return;
    try {
      await gateway.call('session.interrupt', {'session_id': id});
    } catch (e) {
      error = ngL.ng_couldn_t_stop(_clean(e));
      _changed();
    }
  }

  /// Stops the running turn, then sends [text].
  Future<void> stopAndSend(String text) async {
    queued.insert(0, NgQueued(_key('q'), text.trim()));
    await stop();
  }

  Future<Map<String, dynamic>> _submitPromptWithCompatibility(
    Map<String, dynamic> baseParams, {
    required String submissionId,
  }) async {
    try {
      return await gateway.call('prompt.submit', {
        ...baseParams,
        'submission_id': submissionId,
      }, timeout: const Duration(seconds: 60));
    } on JsonRpcError catch (e) {
      if (!isRejectedSubmissionIdError(e)) rethrow;
      return gateway.call(
        'prompt.submit',
        baseParams,
        timeout: const Duration(seconds: 60),
      );
    }
  }

  /// Sends the last prompt again.
  Future<void> retryLast() async {
    final last = items.whereType<NgUserItem>().lastOrNull;
    if (last == null) return;
    if (last.failure != null) {
      items.remove(last);
    }
    await send(
      last.text,
      attachments: last.failure != null ? last.attachments : const [],
      submissionId: last.failure != null ? last.submissionId : null,
    );
  }

  bool _answer(Map<String, dynamic> result) {
    final current = request;
    if (current == null) return false;
    final ok = current.request.raw.respond(result);
    gateway.forgetRequest(current.request.id);
    request = null;
    _changed();
    return ok;
  }

  bool answerApproval(String choice) => _answer({'choice': choice});

  bool answerClarify(List<List<String>> answers) {
    final current = request;
    if (current == null) return false;
    final texts = answers
        .map(
          (picked) => switch (picked.length) {
            0 => '',
            1 => picked.single,
            _ => jsonEncode(picked),
          },
        )
        .toList();
    final batch = current.questions.any((q) => q.qid != null);
    return _answer(
      batch
          ? {
              'answers': {
                for (var i = 0; i < current.questions.length; i++)
                  current.questions[i].qid ?? '$i': i < texts.length
                      ? texts[i]
                      : '',
              },
            }
          : {'answer': texts.isEmpty ? '' : texts.first},
    );
  }

  bool cancelClarify() => _answer(const {});

  bool answerValue(String value) => _answer({'value': value});

  bool answerSaveLogin(String identifier, String password) => _answer({
    'value': password.isEmpty
        ? ''
        : jsonEncode({'identifier': identifier, 'password': password}),
  });

  String? _modelConfirmationToken;
  String? _modelConfirmationKey;
  bool _modelConfirmationSent = false;
  String? _retainedModelKey;
  Map<String, dynamic>? _retainedModelMutation;

  /// Switches this chat's model (and provider) without showing an unconfirmed
  /// choice as though it were active.
  Future<NgModelSwitchResult> setModel({
    required String provider,
    required String model,
    bool confirm = false,
  }) async {
    final previousModel = this.model;
    final previousProvider = this.provider;
    final key = '$provider/$model';
    if (_retainedModelKey != null && _retainedModelKey != key) {
      _clearRetainedModelMutation();
      _clearModelConfirmation();
    } else if (!confirm &&
        (_modelConfirmationKey != key || !_modelConfirmationSent)) {
      _clearModelConfirmation();
    }
    if (runtimeId == null && storedId == null) {
      _pickedModel = model;
      _pickedProvider = provider;
      this.model = model;
      this.provider = provider;
      _changed();
      return const NgModelSwitchDone();
    }
    if (runtimeId == null) await _attach();
    final id = runtimeId;
    if (id == null) {
      return _finishModelSwitch(
        NgModelSwitchFailed(
          ngL.ng_model_switch_not_connected,
          clearConfirmation: false,
        ),
        previousModel,
        previousProvider,
        provider,
        model,
      );
    }
    final result = await _sendModelSwitch(
      id,
      provider: provider,
      model: model,
      confirm: confirm,
      confirmationKey: key,
    );
    return _finishModelSwitch(
      result,
      previousModel,
      previousProvider,
      provider,
      model,
    );
  }

  NgModelSwitchResult _finishModelSwitch(
    NgModelSwitchResult result,
    String? previousModel,
    String? previousProvider,
    String provider,
    String model,
  ) {
    switch (result) {
      case NgModelSwitchDone(:final resolvedModel, :final info) ||
          NgModelSwitchDeferred(:final resolvedModel, :final info):
        this.model = resolvedModel ?? model;
        this.provider = provider;
        if (info != null) _withInfo(info);
        _clearModelConfirmation();
      case NgModelSwitchNeedsConfirmation():
        this.model = previousModel ?? this.model;
        this.provider = previousProvider ?? this.provider;
      case NgModelSwitchFailed(:final message, :final clearConfirmation):
        this.model = previousModel ?? this.model;
        this.provider = previousProvider ?? this.provider;
        error = message;
        if (clearConfirmation) _clearModelConfirmation();
    }
    _changed();
    return result;
  }

  static Map<String, dynamic>? _infoMap(Object? raw) =>
      raw is Map<String, dynamic>
      ? raw
      : raw is Map
      ? Map<String, dynamic>.from(raw)
      : null;

  static String? _nonEmptyString(Object? raw) {
    final value = raw is String ? raw : null;
    return value == null || value.isEmpty ? null : value;
  }

  Future<NgModelSwitchResult> _sendModelSwitch(
    String id, {
    required String provider,
    required String model,
    required bool confirm,
    required String confirmationKey,
  }) async {
    if (gateway.sessionAuthority) {
      return _mutateModel(
        id,
        provider: provider,
        model: model,
        confirm: confirm,
        confirmationKey: confirmationKey,
      );
    }
    try {
      final result = await gateway.call('config.set', {
        'session_id': id,
        'key': 'model',
        'value': WsClient.buildSessionModelValue(
          provider: provider,
          model: model,
        ),
        if (confirm) 'confirm_expensive_model': true,
      });
      if (result['confirm_required'] == true) {
        return NgModelSwitchNeedsConfirmation(
          result['confirm_message']?.toString() ??
              result['warning']?.toString() ??
              ngL.ng_model_confirmation_required,
        );
      }
      final info = _infoMap(result['info']);
      final resolved = _nonEmptyString(result['model']);
      if (result['status']?.toString() == 'deferred') {
        return NgModelSwitchDeferred(resolvedModel: resolved, info: info);
      }
      return NgModelSwitchDone(resolvedModel: resolved, info: info);
    } on JsonRpcError catch (e) {
      if (_modelErrorIs(e, 'use_session_mutation_model')) {
        return _mutateModel(
          id,
          provider: provider,
          model: model,
          confirm: confirm,
          confirmationKey: confirmationKey,
        );
      }
      return NgModelSwitchFailed(_clean(e));
    } catch (e) {
      return NgModelSwitchFailed(_clean(e), clearConfirmation: false);
    }
  }

  static bool _modelErrorIs(JsonRpcError error, String reason) =>
      error.reason == reason || error.message == reason;

  Future<NgModelSwitchResult> _mutateModel(
    String id, {
    required String provider,
    required String model,
    required bool confirm,
    required String confirmationKey,
  }) async {
    if (_revision == null || _executionGeneration == null) await _attach();
    if (_revision == null || _executionGeneration == null) {
      return NgModelSwitchFailed(
        ngL.ng_model_switch_not_connected,
        clearConfirmation: false,
      );
    }
    var retried = false;
    while (true) {
      final useToken =
          _modelConfirmationKey == confirmationKey &&
          _modelConfirmationToken != null &&
          _modelConfirmationToken!.isNotEmpty &&
          (confirm || _modelConfirmationSent);
      if (useToken) _modelConfirmationSent = true;
      final token = useToken ? _modelConfirmationToken : null;
      final retained = _retainedModelKey == confirmationKey
          ? _retainedModelMutation
          : null;
      final retainedPayload = retained?['payload'];
      final retainedToken = retainedPayload is Map
          ? retainedPayload['confirm']?.toString()
          : null;
      final params =
          retained != null &&
              retained['session_id'] == id &&
              retainedToken == token
          ? retained
          : <String, dynamic>{
              'session_id': id,
              'request_id': const Uuid().v4(),
              'expected_revision': _revision,
              'expected_generation': _executionGeneration,
              'operation': 'model',
              'payload': <String, dynamic>{
                'model': model,
                'provider': provider,
                'confirm': ?token,
              },
            };
      _retainedModelKey = confirmationKey;
      _retainedModelMutation = params;
      try {
        final result = await gateway.call('session.mutate', params);
        _clearRetainedModelMutation();
        if (useToken) _clearModelConfirmation();
        _withAuthority(result);
        final status = result['status']?.toString();
        if (status == 'confirmation_required') {
          _modelConfirmationKey = confirmationKey;
          _modelConfirmationToken = result['confirm']?.toString();
          _modelConfirmationSent = false;
          return NgModelSwitchNeedsConfirmation(
            result['confirm_message']?.toString() ??
                result['warning']?.toString() ??
                ngL.ng_model_confirmation_required,
          );
        }
        final info = _infoMap(result['info']);
        final resolved = _nonEmptyString(result['model']);
        if (status == 'deferred') {
          return NgModelSwitchDeferred(resolvedModel: resolved, info: info);
        }
        return NgModelSwitchDone(resolvedModel: resolved, info: info);
      } on JsonRpcError catch (e) {
        final fence =
            _modelErrorIs(e, 'revision_conflict') ||
            _modelErrorIs(e, 'stale_generation');
        if (fence && !retried) {
          final sentRev = params['expected_revision'];
          final sentGen = params['expected_generation'];
          _clearRetainedModelMutation();
          _withAuthority(e.data);
          retried = true;
          if (_revision != null &&
              _executionGeneration != null &&
              (_revision != sentRev || _executionGeneration != sentGen)) {
            continue;
          }
        }
        final settledByOwner = e.reason != null;
        if (settledByOwner) _clearRetainedModelMutation();
        return NgModelSwitchFailed(
          _clean(e),
          clearConfirmation: settledByOwner,
        );
      } catch (e) {
        return NgModelSwitchFailed(_clean(e), clearConfirmation: false);
      }
    }
  }

  void _clearRetainedModelMutation() {
    _retainedModelKey = null;
    _retainedModelMutation = null;
  }

  void _clearModelConfirmation() {
    _modelConfirmationToken = null;
    _modelConfirmationKey = null;
    _modelConfirmationSent = false;
  }

  /// Switches this chat's thinking level.
  Future<void> setReasoning(String effort) async {
    final previous = reasoningEffort;
    reasoningEffort = effort;
    _changed();
    if (runtimeId == null && storedId == null) {
      _pickedEffort = effort;
      return;
    }
    if (runtimeId == null) await _attach();
    if (runtimeId == null) {
      reasoningEffort = previous;
      _changed();
      throw StateError(ngL.ng_model_switch_not_connected);
    }
    try {
      await gateway.call('config.set', {
        'session_id': runtimeId,
        'key': 'reasoning',
        'value': effort,
      });
    } catch (_) {
      reasoningEffort = previous;
      _changed();
      rethrow;
    }
  }

  /// Renames the chat.
  Future<void> rename(String newTitle) async {
    final id = storedId;
    if (id == null) return;
    final saved = await gateway.api.renameSession(
      sessionId: id,
      title: newTitle,
    );
    title = saved;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}

/// The events after [from] for [runtimeId], oldest first, when the replay
/// proves none is missing; null when the gap can't be trusted and the chat
/// must be read again (Kyllene's EventReplay): truncated, another or missing
/// epoch, `latest_seq` below [from], an incomplete replay, a hole in the seqs
/// or another session's event.
List<StreamEvent>? ngParseReplay(
  Map<String, dynamic> reply,
  String runtimeId,
  int from,
  String? epoch,
) {
  final latest = reply['latest_seq'];
  final events = reply['events'];
  if (latest is! num || events is! List) return null;
  if (reply['truncated'] != false) return null;
  final replyEpoch = reply['epoch']?.toString();
  if (epoch != null && replyEpoch != epoch) return null;
  if (latest < from) return null;
  var cursor = from;
  final missed = <StreamEvent>[];
  for (final raw in events) {
    if (raw is! Map) return null;
    final frame = Map<String, dynamic>.from(raw);
    if (frame['session_id'] != runtimeId) return null;
    final seq = frame['seq'];
    if (seq is! int) return null;
    if (seq <= cursor) continue;
    if (seq != cursor + 1) return null;
    cursor = seq;
    final event = WsClient.parseGatewayEvent(frame);
    if (event == null) return null;
    missed.add(event);
  }
  // A syntactically valid prefix is still incomplete when the server says it
  // had later events. Reload rather than silently advancing over missing work.
  if (cursor != latest) return null;
  return missed;
}
