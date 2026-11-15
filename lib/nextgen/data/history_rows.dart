// Decoding and slimming stored history rows off the UI thread.
//
// A page of 60 rows can carry megabytes of tool output (file reads, browser
// snapshots, logs). Decoding that JSON on the main isolate, then keeping it
// all, froze long chats into Android's "not responding" dialog. Large pages
// are decoded on a background isolate, and each row comes back holding only
// what the transcript shows.
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

/// Characters of a tool result, or of a call's arguments, kept per row.
const ngRowToolChars = 16000;

/// Characters of a prompt or reply kept per row.
const ngRowTextChars = 200000;

/// Bodies above this decode on a background isolate.
const ngIsolateDecodeBytes = 128 * 1024;

/// Decodes a `GET /api/sessions/{id}/messages` body into slimmed rows.
Future<List<Map<String, dynamic>>> ngDecodeHistory(Uint8List body) {
  if (body.length < ngIsolateDecodeBytes) {
    return Future.value(ngDecodeHistorySync(body));
  }
  return Isolate.run(() => ngDecodeHistorySync(body));
}

List<Map<String, dynamic>> ngDecodeHistorySync(Uint8List body) {
  final text = utf8.decode(body, allowMalformed: true).trim();
  if (text.isEmpty) return const [];
  final decoded = jsonDecode(text);
  final list = decoded is Map
      ? (decoded['messages'] ?? decoded['data'])
      : decoded;
  if (list is! List) return const [];
  return ngSlimHistoryRows(list);
}

String _cap(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max)}…';

Object? _capContent(Object? content, int max) {
  if (content is String) return _cap(content, max);
  if (content is List) {
    return [
      for (final part in content)
        if (part is String)
          _cap(part, max)
        else if (part is Map)
          {
            for (final e in part.entries)
              if (e.key == 'text' && e.value is String)
                'text': _cap(e.value as String, max)
              // Inline image data is never drawn from history.
              else if (e.key == 'image_url' || e.key == 'source')
                e.key.toString(): '[image]'
              else
                e.key.toString(): e.value,
          },
    ];
  }
  if (content is Map) {
    final text = content['text'];
    return text is String ? {'text': _cap(text, max)} : const {};
  }
  return content;
}

/// The rows as the transcript reads them, with oversized text capped and a
/// one-line preview of each tool call's arguments worked out before its
/// JSON is cut.
List<Map<String, dynamic>> ngSlimHistoryRows(List<dynamic> rows) {
  final out = <Map<String, dynamic>>[];
  for (final raw in rows) {
    if (raw is! Map) continue;
    final row = Map<String, dynamic>.from(raw);
    final isTool = row['role']?.toString() == 'tool';
    final max = isTool ? ngRowToolChars : ngRowTextChars;
    for (final key in const ['content', 'display_content']) {
      if (row.containsKey(key)) row[key] = _capContent(row[key], max);
    }
    for (final key in const ['reasoning', 'display_reasoning']) {
      final v = row[key];
      if (v is String) row[key] = _cap(v, ngRowToolChars);
    }
    // Reasoning details and other sidecars are not shown in NextGen.
    row.remove('reasoning_details');
    row.remove('codex_reasoning_items');
    final calls = row['tool_calls'];
    if (calls is List) {
      row['tool_calls'] = [
        for (final call in calls)
          if (call is Map) _slimCall(call),
      ];
    }
    out.add(row);
  }
  return out;
}

Map<String, dynamic> _slimCall(Map<dynamic, dynamic> call) {
  final slim = Map<String, dynamic>.from(call);
  final fn = call['function'];
  final args = fn is Map ? fn['arguments'] : call['arguments'];
  slim['ng_args_preview'] = ngArgsPreview(args);
  String? capped(Object? a) =>
      a == null ? null : _cap(a is String ? a : jsonEncode(a), ngRowToolChars);
  if (fn is Map) {
    slim['function'] = {
      ...Map<String, dynamic>.from(fn),
      'arguments': capped(fn['arguments']),
    };
  } else if (call.containsKey('arguments')) {
    slim['arguments'] = capped(call['arguments']);
  }
  return slim;
}

/// One line describing a tool call's arguments: its command, path, URL…
String? ngArgsPreview(Object? args) {
  Object? decoded = args;
  if (args is String) {
    try {
      decoded = jsonDecode(args);
    } catch (_) {
      return ngFirstLine(args);
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
      if (v is String && v.trim().isNotEmpty) return ngFirstLine(v);
    }
  }
  return null;
}

String? ngFirstLine(String? text) {
  if (text == null) return null;
  final trimmed = text.trimLeft();
  final end = trimmed.indexOf('\n');
  final line = (end < 0 ? trimmed : trimmed.substring(0, end)).trim();
  if (line.isEmpty) return null;
  return line.length > 140 ? '${line.substring(0, 140)}…' : line;
}
