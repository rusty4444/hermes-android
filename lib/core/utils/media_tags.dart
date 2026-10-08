/// Parsing of the gateway's `MEDIA:/path` file-delivery contract out of
/// assistant message text.
///
/// Mirrors the desktop client's `apps/desktop/src/lib/chat-messages/parts.ts`
/// (which itself mirrors the gateway's `MEDIA_DELIVERY_EXTS` in
/// `gateway/platforms/base.py`) so all three surfaces agree on which
/// `MEDIA:` paths are real deliverables. A `MEDIA:` mention of a non-path
/// (`MEDIA:...`, a bare word) stays prose — a dead download card for a
/// non-path is worse than no card.
library;

/// Extensions the gateway treats as deliverable media. Kept in sync with
/// `MEDIA_DELIVERY_EXTS` in the gateway's `gateway/platforms/base.py`.
const List<String> kMediaDeliveryExts = [
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tiff',
  'svg',
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  '3gp',
  'mp3',
  'm2a',
  'wav',
  'ogg',
  'opus',
  'm4a',
  'flac',
  'pdf',
  'docx',
  'doc',
  'odt',
  'rtf',
  'txt',
  'md',
  'epub',
  'xlsx',
  'xls',
  'ods',
  'csv',
  'tsv',
  'json',
  'rar',
  'apk',
  'ipa',
  'html',
  'htm',
];

// Longest-first so the alternation never matches a shorter ext as a prefix
// of a longer one.
final String _extAlternation = (() {
  final sorted = [...kMediaDeliveryExts]
    ..sort((a, b) => b.length.compareTo(a.length));
  return sorted.join('|');
})();

// Unquoted path branch: anchored start (`~/`, `/`, `X:\` or `X:/`), interior
// whitespace allowed, end anchored on a known deliverable extension followed
// by a boundary. Mirrors `_MEDIA_PATH_ANCHORED`. The bare fallback stops
// before backtick/double-quote so inline-code closers are not swallowed;
// apostrophes stay legal inside paths.
final RegExp _mediaTagPattern = RegExp(
  'MEDIA:\\s*(?:`[^`\\n]+`|"[^"\\n]+"|\'[^\'\\n]+\'|'
  '(?:~/|/|[A-Za-z]:[/\\\\])\\S+?(?:[^\\S\\n]+\\S+?)*?\\.(?:'
  '$_extAlternation'
  ')(?=[\\s`"\'*_,;:)\\]}]|MEDIA:|\$)|[^\\s`"]+)',
);

const String _trailingPunctuation = '.,;:!?';

// A path ending in a known deliverable extension — the streaming guard's
// "this token is complete" test.
final RegExp _completeExtPattern = RegExp(
  '\\.(?:$_extAlternation)\$',
  caseSensitive: false,
);

bool _isPlausibleMediaPath(String value) {
  return value.contains('/') ||
      value.contains(r'\') ||
      RegExp(r'\.[^.]').hasMatch(value);
}

String _unquoteMediaPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  final quote = trimmed[0];
  if (quote == trimmed.substring(trimmed.length - 1) &&
      (quote == '"' || quote == "'" || quote == '`')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  // A trailing backtick or double-quote left in the value is formatting
  // residue, not part of the path. Apostrophes are not (`john's.md`).
  final last = trimmed.substring(trimmed.length - 1);
  return (last == '`' || last == '"')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

({String path, String punctuation}) _splitTrailingPunctuation(String value) {
  var end = value.length;
  while (end > 0 && _trailingPunctuation.contains(value[end - 1])) {
    if (!_isPlausibleMediaPath(value.substring(0, end - 1))) break;
    end -= 1;
  }
  return (path: value.substring(0, end), punctuation: value.substring(end));
}

/// One `MEDIA:` reference extracted from assistant text.
class MediaTagRef {
  /// The gateway-host path to fetch (never a local path — always resolve
  /// through the session's gateway `fs/download`).
  final String path;

  /// True when the capture was quoted: quotes are the escape hatch for odd
  /// names, so trailing punctuation inside them is part of the path.
  final bool quoted;

  const MediaTagRef({required this.path, this.quoted = false});

  String get filename {
    final segments = path.split(RegExp(r'[/\\]'));
    return segments.isEmpty ? path : segments.last;
  }

  String get extension =>
      filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
}

/// A segment of assistant text after `MEDIA:` extraction: either prose or a
/// media reference. Prose segments keep everything between refs (including
/// the sentence punctuation a bare ref shed) so the message reads intact.
class MediaTextSegment {
  final String text;
  final MediaTagRef? media;

  const MediaTextSegment.prose(this.text) : media = null;
  const MediaTextSegment.mediaRef(this.media) : text = '';

  bool get isMedia => media != null;
}

/// Split [text] into prose and media-reference segments. Degenerate captures
/// (`MEDIA:...`, bare words with no path separator or extension) stay prose.
List<MediaTextSegment> splitMediaTags(String text) {
  final segments = <MediaTextSegment>[];
  var cursor = 0;
  for (final match in _mediaTagPattern.allMatches(text)) {
    final raw = match.group(0)!.substring('MEDIA:'.length);
    final trimmedRaw = raw.trim();
    final quote = trimmedRaw.isEmpty ? '' : trimmedRaw[0];
    final quoted =
        quote.isNotEmpty &&
        quote == trimmedRaw.substring(trimmedRaw.length - 1) &&
        (quote == '"' || quote == "'" || quote == '`');
    final bare = quoted
        ? (path: _unquoteMediaPath(trimmedRaw), punctuation: '')
        : _splitTrailingPunctuation(_unquoteMediaPath(trimmedRaw));
    // Streaming guard: a tag whose token runs to the very end of the text
    // may still be mid-token (the next delta could extend the path). Only
    // accept it once the path ends on a known deliverable extension;
    // otherwise leave it prose and it converts on the next token.
    if (match.end == text.length && !_completeExtPattern.hasMatch(bare.path)) {
      continue;
    }
    if (!_isPlausibleMediaPath(bare.path)) continue;

    if (match.start > cursor) {
      segments.add(MediaTextSegment.prose(text.substring(cursor, match.start)));
    }
    // A bare capture's trailing sentence punctuation belongs to the prose,
    // not the path — re-emit it after the card so "Here it is." still reads.
    segments.add(
      MediaTextSegment.mediaRef(MediaTagRef(path: bare.path, quoted: quoted)),
    );
    if (bare.punctuation.isNotEmpty) {
      segments.add(MediaTextSegment.prose(bare.punctuation));
    }
    cursor = match.end;
  }
  if (segments.isEmpty) return [MediaTextSegment.prose(text)];
  if (cursor < text.length) {
    segments.add(MediaTextSegment.prose(text.substring(cursor)));
  }
  return segments;
}
