// One open NextGen chat: the transcript from the dashboard's REST history,
// then the live session over `/api/ws` (tui_gateway/contracts/events.py).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/models/attachment_draft.dart';
import '../../core/services/attachment_draft_service.dart';
import '../../core/services/ws_client.dart';
import 'nextgen_gateway.dart';
import '../nextgen_l10n.dart';

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
  });
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

  NgUserItem(
    super.key,
    this.text, {
    this.time,
    this.steered = false,
    this.pending = false,
    this.attachments = const [],
    this.files = const [],
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
  NgNoticeItem(super.key, this.text, {this.error = false});
}

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
    _subs.add(gateway.reconnected.listen((_) => unawaited(_attach())));
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

  final void Function(String storedId)? onCreated;
  final void Function()? onTurnFinished;

  final List<StreamSubscription<dynamic>> _subs = [];
  int _seq = 0;
  bool _disposed = false;
  bool _attaching = false;

  String _key(String prefix) => '$prefix-${_seq++}';

  void _changed() {
    if (!_disposed) notifyListeners();
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
      final messages = await gateway.api.getMessages(
        id,
        limit: 300,
        latest: true,
      );
      _applyHistory(messages);
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
    if (id == null || _attaching || _disposed) return;
    _attaching = true;
    try {
      await gateway.connected();
      final result = await gateway.call('session.resume', {
        'session_id': id,
        'source': 'desktop',
        'omit_messages': true,
        'defer_history': true,
        'inline_images': false,
      });
      runtimeId = result['session_id']?.toString() ?? runtimeId;
      if (runtimeId != null) gateway.bindRuntime(runtimeId!, id);
      final wasRunning = running;
      running = result['running'] == true;
      if (running && !wasRunning) turnStartedAt ??= DateTime.now();
      _withInfo(result['info']);
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
              return part['text']?.toString() ?? '';
            }
            return '';
          })
          .where((t) => t.isNotEmpty)
          .join('\n');
    }
    if (content is Map) return content['text']?.toString() ?? '';
    return '';
  }

  static DateTime? _time(Object? ts) {
    if (ts is num && ts > 0) {
      return DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    }
    return null;
  }

  void _applyHistory(List<Map<String, dynamic>> messages) {
    items.clear();
    NgAssistantItem? reply;
    final toolsById = <String, NgTool>{};
    for (final m in messages) {
      final role = m['role']?.toString();
      final displayKind = m['display_kind']?.toString();
      final text = _plain(m['display_content'] ?? m['content']);
      if (role == 'user') {
        if (displayKind != null &&
            displayKind.isNotEmpty &&
            displayKind != 'steer') {
          if (text.trim().isNotEmpty) {
            items.add(NgNoticeItem(_key('n'), text.trim()));
          }
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
              detail: call['label']?.toString() ?? _argsPreview(args),
              input: args is String
                  ? args
                  : (args == null ? null : jsonEncode(args)),
            );
            toolsById[id] = tool;
            reply.tools.add(tool);
          }
        }
      } else if (role == 'tool') {
        final id = m['tool_call_id']?.toString();
        final tool = id == null ? null : toolsById[id];
        if (tool != null) {
          tool.output = text;
          tool.summary = _firstLine(text);
        }
      }
    }
  }

  static String? _argsPreview(Object? args) {
    Object? decoded = args;
    if (args is String) {
      try {
        decoded = jsonDecode(args);
      } catch (_) {
        return _firstLine(args);
      }
    }
    if (decoded is Map) {
      for (final key in const [
        'command',
        'path',
        'file_path',
        'url',
        'query',
        'pattern',
        'goal',
        'name',
      ]) {
        final v = decoded[key];
        if (v is String && v.trim().isNotEmpty) return _firstLine(v);
      }
    }
    return null;
  }

  static String? _firstLine(String? text) {
    if (text == null) return null;
    final line = text.trim().split('\n').first.trim();
    if (line.isEmpty) return null;
    return line.length > 140 ? '${line.substring(0, 140)}…' : line;
  }

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

  void _onEvent(StreamEvent event) {
    if (_disposed || !_isMine(event)) return;
    final p = event.data;
    String? s(String key) {
      final v = p[key];
      return v?.toString();
    }

    switch (event.type) {
      case 'message.start':
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
            detail: s('context') ?? s('preview') ?? _argsPreview(p['args']),
            running: true,
            input:
                s('args_text') ??
                (p['args'] == null
                    ? null
                    : const JsonEncoder.withIndent('  ').convert(p['args'])),
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
        tool.summary = s('summary') ?? tool.summary;
        final d = p['duration_s'];
        tool.durationSeconds = d is num ? d.toDouble() : tool.durationSeconds;
        final result = p['result'];
        tool.output =
            s('result_text') ??
            (result is String
                ? result
                : result == null
                ? tool.output
                : const JsonEncoder.withIndent('  ').convert(result));
        tool.failed =
            result is Map &&
            (result['success'] == false || result['error'] != null);
      case 'status.update':
        final text = s('text');
        status = text == null || text.trim().isEmpty ? null : text;
      case 'session.usage':
        usage = NgUsage.parse(p['usage']) ?? usage;
      case 'session.info':
        _withInfo(p);
      case 'session.title':
        final t = s('title');
        if (t != null && t.trim().isNotEmpty) title = t;
      case 'notice':
        final message = s('message')?.trim();
        if (message != null && message.isNotEmpty) {
          items.add(NgNoticeItem(_key('n'), message));
        }
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
        _finishTurn();
      case 'turn.error':
        error = s('message') ?? ngL.ng_the_turn_failed;
        _finishTurn(failed: true);
      case 'request.cancel':
        final id = s('id') ?? s('request_id');
        if (id != null) {
          gateway.forgetRequest(id);
          if (request?.request.id == id) request = null;
        }
      default:
        return;
    }
    _changed();
  }

  /// Ends the turn. After a failure, queued prompts wait for the user rather
  /// than being sent into the same error.
  void _finishTurn({bool failed = false}) {
    for (final item in items) {
      if (item is NgAssistantItem) {
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
    status = null;
    thinkingFrame = null;
    turnStartedAt = null;
    request = null;
    onTurnFinished?.call();
    if (queued.isNotEmpty && !failed) {
      final next = queued.removeAt(0);
      scheduleMicrotask(() => unawaited(send(next.text)));
    }
  }

  void _onServerRequest(NgServerRequest req) {
    if (_disposed) return;
    final id = req.sessionId;
    if (id == null || (id != runtimeId && id != storedId)) return;
    final parsed = NgInputRequest.parse(req);
    if (parsed == null) return;
    request = parsed;
    _changed();
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _ensureSession() async {
    if (runtimeId != null && storedId != null) return;
    await gateway.connected();
    final result = await gateway.call('session.create', {
      'source': 'desktop',
      if (workingDirectory != null && workingDirectory!.trim().isNotEmpty)
        'cwd': workingDirectory,
    });
    runtimeId = result['session_id']?.toString();
    storedId = result['stored_session_id']?.toString() ?? runtimeId;
    if (runtimeId != null) gateway.bindRuntime(runtimeId!, storedId!);
    _withInfo(result['info']);
    if (storedId != null) onCreated?.call(storedId!);
    final pending = _pendingModelValue;
    if (pending != null && runtimeId != null) {
      _pendingModelValue = null;
      try {
        await gateway.call('config.set', {
          'session_id': runtimeId,
          'key': 'model',
          'value': pending,
        });
      } catch (_) {
        // The chat keeps the profile default.
      }
    }
    final effort = _pendingEffort;
    if (effort != null && runtimeId != null) {
      _pendingEffort = null;
      try {
        await gateway.call('config.set', {
          'session_id': runtimeId,
          'key': 'reasoning',
          'value': effort,
        });
      } catch (_) {
        // Keeps the profile's effort.
      }
    }
  }

  String? _pendingModelValue;
  String? _pendingEffort;

  /// Uploads one attachment with `file.attach` and returns its `@file`
  /// reference, which the prompt must carry.
  Future<String> _upload(AttachmentDraft draft) async {
    draft.status = AttachmentDraftStatus.uploading;
    draft.error = null;
    _changed();
    try {
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
      _changed();
    }
  }

  /// Sends [text] (and any [attachments]) as a new prompt. Returns whether
  /// the gateway accepted it; on failure the attachments stay with the
  /// message so Retry can send them again.
  Future<bool> send(
    String text, {
    List<AttachmentDraft> attachments = const [],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return false;
    final item = NgUserItem(
      _key('u'),
      trimmed,
      time: DateTime.now(),
      pending: true,
      attachments: List.of(attachments),
    );
    items.add(item);
    error = null;
    running = true;
    turnStartedAt = DateTime.now();
    _changed();
    try {
      await _ensureSession();
      final refs = <String>[];
      for (final draft in item.attachments) {
        refs.add(draft.refText ?? await _upload(draft));
      }
      final prompt = [
        trimmed,
        refs.join('\n'),
      ].where((part) => part.trim().isNotEmpty).join('\n\n');
      final result = await gateway.call('prompt.submit', {
        'session_id': runtimeId,
        'text': prompt,
      }, timeout: const Duration(seconds: 60));
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

  /// Switches this chat's model (and provider).
  Future<void> setModel({
    required String provider,
    required String model,
  }) async {
    final value = WsClient.buildSessionModelValue(
      provider: provider,
      model: model,
    );
    this.model = model;
    this.provider = provider;
    _changed();
    if (runtimeId == null) {
      _pendingModelValue = value;
      return;
    }
    await gateway.call('config.set', {
      'session_id': runtimeId,
      'key': 'model',
      'value': value,
    });
  }

  /// Switches this chat's thinking level.
  Future<void> setReasoning(String effort) async {
    reasoningEffort = effort;
    _changed();
    if (runtimeId == null) {
      _pendingEffort = effort;
      return;
    }
    await gateway.call('config.set', {
      'session_id': runtimeId,
      'key': 'reasoning',
      'value': effort,
    });
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
