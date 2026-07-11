/// Convert Hermes/OpenAI message content into displayable text.
///
/// Legacy messages carry a String. Multimodal messages carry a list of typed
/// parts such as `{type: text, text: ...}` and `{type: image_url, ...}`.
/// Keep rendering resilient when the gateway adds new part types.
String messageContentToText(dynamic content) {
  if (content == null) return '';
  if (content is String) return content;

  if (content is List) {
    return content
        .map(_contentPartToText)
        .where((part) => part.isNotEmpty)
        .join('\n\n');
  }

  return _contentPartToText(content);
}

String _contentPartToText(dynamic part) {
  if (part == null) return '';
  if (part is String) return part;
  if (part is! Map) return part.toString();

  final text = part['text'];
  if (text is String && text.isNotEmpty) return text;

  final type = part['type']?.toString() ?? 'unknown';
  if (type.contains('image') || part.containsKey('image_url')) {
    return '[Image]';
  }
  if (type.contains('file') || part.containsKey('file')) {
    return '[File]';
  }

  return '[Unsupported content: $type]';
}
