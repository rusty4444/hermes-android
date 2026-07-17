/// Convert Hermes/OpenAI message content into displayable text.
///
/// Legacy messages carry a String. Multimodal messages carry a list of typed
/// parts such as `{type: text, text: ...}` and `{type: image_url, ...}`.
/// Keep rendering resilient when the gateway adds new part types.
String messageContentToText(dynamic content) {
  if (content == null) return '';
  if (content is String) return normaliseDisplayText(content);

  if (content is List) {
    return normaliseDisplayText(
      content
          .map(_contentPartToText)
          .where((part) => part.isNotEmpty)
          .join('\n\n'),
    );
  }

  return normaliseDisplayText(_contentPartToText(content));
}

/// Normalise common JSON-escaped line endings that can survive one decode layer.
///
/// Hermes tool result payloads may contain nested JSON strings, so the outer
/// `jsonDecode` leaves literal two-character `\\n` sequences in the message
/// content. Markdown needs real newline characters to render paragraphs, lists,
/// and headings correctly.
String normaliseDisplayText(String text) {
  if (!text.contains(r'\n') && !text.contains(r'\r')) return text;
  return text
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\n');
}

/// True when a stored message is a tool result rather than user-visible chat.
bool isToolResultMessage(Map<String, dynamic> message) {
  final role = (message['role']?.toString() ?? '').trim().toLowerCase();
  if (role == 'tool' ||
      role == 'tool_result' ||
      role == 'tool-result' ||
      role == 'function' ||
      role.contains('tool')) {
    return true;
  }

  return looksLikeToolResultText(messageContentToText(message['content']));
}

/// True when message text contains Hermes' raw tool-result wrapper.
bool looksLikeToolResultText(String text) {
  final trimmed = text.trimLeft();
  return trimmed.startsWith('<untrusted_tool_result') ||
      trimmed.contains('<untrusted_tool_result') ||
      trimmed.startsWith('{"tool_call_id"') ||
      trimmed.startsWith('{"toolCallId"');
}

/// Remove embedded raw tool-result blocks from assistant text.
///
/// If the whole message is tool output, this returns an empty string so the chat
/// screen can suppress the bubble and show only the compact tool progress card.
String stripToolResultText(String text) {
  final normalised = normaliseDisplayText(text);
  final stripped = normalised
      .replaceAll(
        RegExp(
          r'<untrusted_tool_result\b[^>]*>[\s\S]*?</untrusted_tool_result>',
          multiLine: true,
        ),
        '',
      )
      .trim();

  if (looksLikeToolResultText(stripped)) return '';
  return stripped;
}

String _contentPartToText(dynamic part) {
  if (part == null) return '';
  if (part is String) return normaliseDisplayText(part);
  if (part is! Map) return part.toString();

  final text = part['text'];
  if (text is String && text.isNotEmpty) return normaliseDisplayText(text);

  final type = part['type']?.toString() ?? 'unknown';
  if (type.contains('image') || part.containsKey('image_url')) {
    return '[Image]';
  }
  if (type.contains('file') || part.containsKey('file')) {
    return '[File]';
  }

  return '[Unsupported content: $type]';
}
