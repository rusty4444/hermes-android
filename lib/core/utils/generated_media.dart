import 'dart:convert';

import 'media_tags.dart';

/// Only the audited image_generate producer contract is recognised here. This
/// is not a path/attachment scanner for arbitrary tool output or arguments.
class GeneratedMediaResult {
  const GeneratedMediaResult({
    this.deliveredFiles = const [],
    this.isFailure = false,
  });

  final List<MediaTagRef> deliveredFiles;
  final bool isFailure;
}

const _emptyResult = GeneratedMediaResult();
const _failedResult = GeneratedMediaResult(isFailure: true);

/// Bound JSON decoding independently of a transport's message-size budget.
const maxGeneratedMediaResultCodeUnits = 256 * 1024;
const _maxReferenceCodeUnits = 16 * 1024;
const _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tiff',
  'svg',
};

/// Decode one real tool result, either already parsed or its stored JSON text.
///
/// Producer names are exact: labels, namespaced lookalikes and source strings
/// embedded in untrusted output cannot opt another tool into this contract.
/// Host paths are preferred over image, and agent_visible_image is never used.
GeneratedMediaResult generatedMediaFromToolResult(
  String toolName,
  Object? result,
) {
  if (toolName != 'image_generate') return _emptyResult;
  final payload = _decodeJson(result);
  if (payload is! Map) return _emptyResult;
  if (payload['success'] == false || payload['error'] != null) {
    return _failedResult;
  }
  if (payload['success'] != true) return _emptyResult;

  for (final key in const ['host_image', 'image']) {
    final path = payload[key];
    if (path is String && _isDeliveredImageReference(path)) {
      return GeneratedMediaResult(
        deliveredFiles: List.unmodifiable([
          MediaTagRef(
            path: path,
            suggestedFilename:
                Uri.tryParse(path)?.scheme.toLowerCase() == 'https' &&
                    !_imageExtensions.contains(
                      MediaTagRef(path: path).extension,
                    )
                ? 'generated-image.png'
                : null,
          ),
        ]),
      );
    }
  }
  return _emptyResult;
}

Object? _decodeJson(Object? value) {
  if (value is! String) return value;
  if (value.length > maxGeneratedMediaResultCodeUnits) return null;
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

bool _isDeliveredImageReference(String path) {
  if (path.isEmpty ||
      path.length > _maxReferenceCodeUnits ||
      path.trim() != path ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
    return false;
  }
  // Preserve the exact reference. Do not expand ~, decode escapes, map sandbox
  // paths, normalise Windows separators, or send HTTPS URLs to fs/download.
  final uri = Uri.tryParse(path);
  if (uri?.scheme.toLowerCase() == 'https') {
    return uri!.hasAuthority && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }
  if (path.startsWith('//')) return false; // Not a protocol-relative URL.
  final absolute =
      path.startsWith('/') ||
      path.startsWith('~/') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(path);
  if (!absolute) return false;
  return _imageExtensions.contains(MediaTagRef(path: path).extension);
}

/// Server public-content presence is authoritative even for null/empty values.
Object? publicDeliveryContent(Map<String, dynamic> message) =>
    message.containsKey('display_content')
    ? message['display_content']
    : message['content'];

/// Only public text parts can explicitly deliver files. Do not stringify
/// reasoning, tool parts, image/upload sidecars, or unknown provider objects.
String publicDeliveryText(Map<String, dynamic> message) =>
    _deliveryTextContent(publicDeliveryContent(message));

String _deliveryTextContent(Object? content) {
  if (content is String) return content;
  if (content is! List) return '';
  return content
      .map((part) {
        if (part is String) return part;
        if (part is Map &&
            const {
              'text',
              'input_text',
              'output_text',
            }.contains(part['type']) &&
            part['text'] is String) {
          return part['text'] as String;
        }
        return '';
      })
      .join('\n');
}

/// Shared exclusion rules for timeline discovery and durable Assets indexing.
/// Real compacted rows remain eligible; synthetic context carriers do not.
bool isPublicDeliveryMessage(Map<String, dynamic> message) {
  if (const {
    'hidden',
    'compaction',
    'compaction_summary',
    'compression_summary',
    'context_summary',
  }.contains(message['display_kind'])) {
    return false;
  }
  final metadata = message['display_metadata'];
  if (metadata is Map && metadata['model_only'] == true) return false;
  if (message.containsKey('display_content')) return true;
  if (message['_compressed_summary'] == true ||
      message['_compressed_summary'] == 1) {
    return false;
  }
  final text = publicDeliveryText(message).trimLeft();
  return !text.startsWith('[CONTEXT COMPACTION — REFERENCE ONLY]') &&
      !text.startsWith('[CONTEXT SUMMARY]:') &&
      !text.startsWith(
        '[PRIOR CONTEXT — for reference only; not a new message]',
      );
}

/// Resolve missing tool-row names only through actual assistant function calls.
/// A conflicting/reused call id is ambiguous and deliberately not attributed.
Map<String, String> generatedMediaToolCallNames(
  Iterable<Map<String, dynamic>> messages,
) {
  final names = <String, String?>{};
  for (final message in messages) {
    if ((message['role'] != 'assistant' && message['role'] != 'agent') ||
        !isPublicDeliveryMessage(message)) {
      continue;
    }
    final calls = _decodeJson(message['tool_calls']);
    if (calls is! List) continue;
    for (final call in calls) {
      if (call is! Map ||
          (call['type'] != null && call['type'] != 'function')) {
        continue;
      }
      final id = call['id'];
      final function = call['function'];
      final name = function is Map ? function['name'] : null;
      if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
        continue;
      }
      if (!names.containsKey(id)) {
        names[id] = name;
      } else if (names[id] != name) {
        names[id] = null;
      }
    }
  }
  return Map.unmodifiable({
    for (final entry in names.entries)
      if (entry.value != null) entry.key: entry.value!,
  });
}

/// Extract only an audited, successful raw stored tool result. Never inspect
/// assistant reasoning, tool-call arguments, uploads, or arbitrary MEDIA text.
List<MediaTagRef> generatedMediaFromToolMessage(
  Map<String, dynamic> message, {
  Map<String, String> toolNamesById = const {},
}) => generatedMediaResultFromToolMessage(
  message,
  toolNamesById: toolNamesById,
).deliveredFiles;

GeneratedMediaResult generatedMediaResultFromToolMessage(
  Map<String, dynamic> message, {
  Map<String, String> toolNamesById = const {},
}) {
  if (message['role'] != 'tool' || !isPublicDeliveryMessage(message)) {
    return _emptyResult;
  }
  String? name;
  for (final key in const ['name', 'tool_name', 'toolCallName']) {
    final candidate = message[key];
    if (candidate is! String || candidate.isEmpty) continue;
    if (name != null && name != candidate) return _emptyResult;
    name = candidate;
  }
  final id = message['tool_call_id'] ?? message['toolCallId'];
  final correlatedName = id is String ? toolNamesById[id] : null;
  if (name != null && correlatedName != null && name != correlatedName) {
    return _emptyResult;
  }
  name ??= correlatedName;
  if (name == null) return _emptyResult;
  if (message['error'] != null ||
      message['status'] == 'failed' ||
      message['status'] == 'error') {
    return _failedResult;
  }
  return generatedMediaFromToolResult(name, publicDeliveryContent(message));
}
