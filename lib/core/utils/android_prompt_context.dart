/// App-owned guidance carried by stock Hermes' ordinary user-text contract.
///
/// This is not system metadata: legacy gateways persist it with the user turn.
/// Only presentation removes the exact known note; raw history stays untouched.
class AndroidPromptContext {
  AndroidPromptContext._();

  static const localUserTextKey = '_android_plain_user_text';
  static const wireContentKey = '_android_model_user_content';
  static const header = '[Hermes Android client context v1]';

  // Keep a published version's exact bytes stable for saved-history decoding.
  static const suffix =
      '\n\n$header\n'
      'This turn is from the native Hermes Android app, not a terminal. '
      'Deliver generated files as `MEDIA:/absolute/host/path` '
      '(quote paths containing spaces) or absolute filesystem Markdown links. '
      'The app provides previews, Download and Share. '
      'Paths refer to the Hermes host, not the phone.\n'
      '[/Hermes Android client context v1]';

  static final _controlPunctuation = RegExp(
    r'''^[.,!?;:\s"']+|[.,!?;:\s"']+$''',
  );
  static const _bareControls = {
    'stop',
    'cancel',
    'pause',
    'quit',
    'exit',
    'stop talking',
    'stop listening',
    'stop voice chat',
    'end voice chat',
  };

  /// Call once at an outbound boundary, never on drafts or stored history.
  static String forModel(
    String text, {
    Iterable<String> stopPhrases = const [],
  }) {
    final trimmed = text.trim();
    final control = trimmed.toLowerCase().replaceAll(_controlPunctuation, '');
    if (trimmed.isEmpty ||
        trimmed.startsWith('/') ||
        _bareControls.contains(control) ||
        stopPhrases.any((phrase) => phrase.trim().toLowerCase() == control)) {
      return text;
    }
    return '$text$suffix';
  }

  /// An attachment-only turn still needs client context without inventing words.
  static String forAttachment(String text) =>
      text.trim().isEmpty ? '$text$suffix' : forModel(text);

  /// Remove one complete known suffix, preserving the user's exact text.
  static String userText(String text) =>
      !text.trimLeft().startsWith('/') && text.endsWith(suffix)
      ? text.substring(0, text.length - suffix.length)
      : text;

  /// Decode text parts only; retain image/file parts and the original payload.
  static dynamic userContent(dynamic content) {
    if (content is String) return userText(content);
    if (content is! List) return content;
    var changed = false;
    final parts = <dynamic>[];
    for (final part in content) {
      dynamic decoded = part;
      if (part is String) {
        decoded = userText(part);
      } else if (part is Map &&
          (part['type'] == null ||
              part['type'] == 'text' ||
              part['type'] == 'input_text') &&
          part['text'] is String) {
        final text = userText(part['text'] as String);
        if (text != part['text']) decoded = {...part, 'text': text};
      }
      changed = changed || !identical(decoded, part);
      parts.add(decoded);
    }
    return changed ? parts : content;
  }

  /// Locally composed rows are already plain; do not decode a literal example.
  static dynamic displayContent(
    Map<String, dynamic> message,
    dynamic publicContent,
  ) => message['role'] != 'user' || message[localUserTextKey] == true
      ? publicContent
      : userContent(publicContent);

  /// A bounded server preview can end part-way through the app's known note.
  /// Never infer an unknown version or use preview text as turn identity.
  static String sessionPreview(String preview) {
    // Slash inputs are never framed, so a matching note is the user's literal.
    if (preview.trimLeft().startsWith('/')) return preview;
    final start = preview.indexOf(header);
    if (start < 0) return preview;
    final whitespace = RegExp(r'\s+');
    final tail = preview
        .substring(start)
        .replaceAll(whitespace, ' ')
        .trimRight();
    final known = suffix.trimLeft().replaceAll(whitespace, ' ');
    return known.startsWith(tail)
        ? preview.substring(0, start).trimRight()
        : preview;
  }
}
