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

import 'package:markdown/markdown.dart' as md;

/// Extensions the gateway treats as deliverable media. Kept in sync with
/// `MEDIA_DELIVERY_EXTS` in the gateway's `gateway/platforms/base.py` —
/// currently all 58 entries; a drift here silently drops cards for whole
/// categories (archives, geo, presentations) that the gateway will deliver.
const List<String> kMediaDeliveryExts = [
  // images
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'tiff', 'svg',
  // video
  'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp',
  // audio
  'mp3', 'm2a', 'wav', 'ogg', 'opus', 'm4a', 'flac',
  // documents
  'pdf', 'docx', 'doc', 'odt', 'rtf', 'txt', 'md', 'epub',
  // spreadsheets/data
  'xlsx', 'xls', 'ods', 'csv', 'tsv', 'json', 'xml', 'yaml', 'yml',
  // geospatial / GIS
  'kmz', 'kml', 'geojson', 'gpx',
  // presentations
  'pptx', 'ppt', 'odp', 'key',
  // archives
  'zip', 'tar', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar', 'apk', 'ipa',
  // web / rendered output
  'html', 'htm',
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
  caseSensitive: false,
);

const String _trailingPunctuation = '.,;:!?';
const String _quoteCharacters = '"\'`';

// A path ending in a known deliverable extension — the streaming guard's
// "this token is complete" test. Case-insensitive to match _mediaTagPattern.
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
  // A one-character capture such as a streaming `MEDIA:'` has no closing
  // quote. Requiring two characters prevents substring(1, 0).
  if (trimmed.length >= 2 &&
      quote == trimmed[trimmed.length - 1] &&
      _quoteCharacters.contains(quote)) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  // A trailing backtick or double-quote left in the value is formatting
  // residue, not part of the path. Apostrophes are not (`john's.md`).
  final last = trimmed[trimmed.length - 1];
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

/// Parser-only nodes correlate a candidate with its untouched source match.
class _MediaCandidate extends md.Element {
  _MediaCandidate(this.index) : super.empty('media-candidate');

  final int index;
}

class _MediaCandidateSyntax extends md.InlineSyntax {
  _MediaCandidateSyntax(String prefix, {required this.isFinal})
    : super(
        _mediaTagPattern.pattern
            .replaceFirst('MEDIA:', '$prefix([0-9]+):')
            .replaceAll('MEDIA:', '$prefix[0-9]+:'),
        caseSensitive: false,
      );

  final bool isFinal;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    // CommonMark treats an unmatched inline backtick as prose. While streaming
    // it can still become code, so keep that paragraph's tail non-actionable.
    if (isFinal || !_unclosedInlineCodeBefore(parser.source, match.start)) {
      parser.addNode(_MediaCandidate(int.parse(match[1]!)));
    }
    return true;
  }
}

int _backtickRunLength(String text, int offset) {
  var end = offset;
  while (end < text.length && text[end] == '`') {
    end += 1;
  }
  return end - offset;
}

bool _unclosedInlineCodeBefore(String text, int offset) {
  var cursor = 0;
  while (cursor < offset) {
    final opening = text.indexOf('`', cursor);
    if (opening == -1 || opening >= offset) return false;
    final length = _backtickRunLength(text, opening);
    var candidate = opening + length;
    int? closingEnd;
    while (candidate < text.length) {
      final next = text.indexOf('`', candidate);
      if (next == -1) break;
      final nextLength = _backtickRunLength(text, next);
      if (nextLength == length) {
        closingEnd = next + nextLength;
        break;
      }
      candidate = next + nextLength;
    }
    if (closingEnd == null) return true;
    cursor = closingEnd;
  }
  return false;
}

/// Use the renderer's Markdown grammar for nested lists, code and lazy quotes.
///
/// Markdown has no source spans. Tag only each candidate's ordinary word marker
/// in a parser-only copy, using a collision-free prefix with no Markdown syntax.
/// Typed inline nodes then identify eligible occurrences outside code/quotes;
/// fence metadata and other non-prose syntax never produce an eligible node.
/// All paths, quoting and rendering offsets still come from the original text,
/// not normalized AST text (which strips container prefixes and encodes HTML).
List<RegExpMatch> _deliveryMatches(String text, {required bool isFinal}) {
  final matches = _mediaTagPattern.allMatches(text).toList();
  if (matches.isEmpty) return const [];

  var prefix = 'HERMESMEDIA';
  while (text.toUpperCase().contains(prefix)) {
    prefix = '${prefix}X';
  }
  final tagged = StringBuffer();
  var cursor = 0;
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    tagged
      ..write(text.substring(cursor, match.start))
      ..write('$prefix$index:');
    cursor = match.start + 'MEDIA:'.length;
  }
  tagged.write(text.substring(cursor));

  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    inlineSyntaxes: [_MediaCandidateSyntax(prefix, isFinal: isFinal)],
  ).parse(tagged.toString());
  final eligible = <int>{};
  void collect(md.Node node) {
    if (node is _MediaCandidate) {
      eligible.add(node.index);
    } else if (node is md.Element &&
        node.tag != 'code' &&
        node.tag != 'pre' &&
        node.tag != 'blockquote') {
      node.children?.forEach(collect);
    }
  }

  nodes.forEach(collect);
  return [
    for (var index = 0; index < matches.length; index++)
      if (eligible.contains(index)) matches[index],
  ];
}

/// One `MEDIA:` reference extracted from assistant text.
class MediaTagRef {
  /// The gateway-host path to fetch (never a local path — always resolve
  /// through the session's gateway `fs/download`).
  final String path;

  /// True when the capture was quoted: quotes are the escape hatch for odd
  /// names, so trailing punctuation inside them is part of the path.
  final bool quoted;

  /// Optional producer-provided name for image URLs without a file extension.
  final String? suggestedFilename;

  const MediaTagRef({
    required this.path,
    this.quoted = false,
    this.suggestedFilename,
  });

  String get filename {
    if (suggestedFilename case final name?) return name;
    final uri = Uri.tryParse(path);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      return uri.pathSegments.where((part) => part.isNotEmpty).lastOrNull ??
          'attachment';
    }
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

  /// True for refs that sat alone on their line: safe to splice as a block
  /// between markdown documents. Inline refs must stay in the prose (as a
  /// markdown link) so they don't fragment a list item, table row, or
  /// emphasis span.
  final bool standalone;

  const MediaTextSegment.prose(this.text) : media = null, standalone = false;
  const MediaTextSegment.mediaRef(this.media, {this.standalone = false})
    : text = '';

  bool get isMedia => media != null;
}

class _ParsedMediaTag {
  final MediaTagRef ref;
  final String punctuation;

  const _ParsedMediaTag(this.ref, this.punctuation);
}

_ParsedMediaTag? _parseMediaTag(
  RegExpMatch match, {
  required int textLength,
  required bool isFinal,
}) {
  final raw = match.group(0)!.substring('MEDIA:'.length);
  final trimmedRaw = raw.trim();
  if (trimmedRaw.isEmpty) return null;
  final quote = trimmedRaw[0];
  final quoted =
      trimmedRaw.length >= 2 &&
      quote == trimmedRaw[trimmedRaw.length - 1] &&
      _quoteCharacters.contains(quote);
  // An unmatched leading quote is a streaming fragment or malformed prose,
  // never a gateway path. Apostrophes remain legal away from the first byte.
  if (!quoted && _quoteCharacters.contains(quote)) return null;
  final bare = quoted
      ? (path: _unquoteMediaPath(trimmedRaw), punctuation: '')
      : _splitTrailingPunctuation(_unquoteMediaPath(trimmedRaw));
  // At the live stream edge, an unknown-extension bare token may still grow.
  // A terminal message is authoritative, and a closed quoted token or known
  // delivery extension already provides its own boundary.
  if (!isFinal &&
      !quoted &&
      match.end == textLength &&
      !_completeExtPattern.hasMatch(bare.path)) {
    return null;
  }
  if (!_isPlausibleMediaPath(bare.path)) return null;
  return _ParsedMediaTag(
    MediaTagRef(path: bare.path, quoted: quoted),
    bare.punctuation,
  );
}

String _mediaMarkdownLabel(String path) {
  final segments = path.split(RegExp(r'[/\\]'));
  final filename = segments.isEmpty ? path : segments.last;
  return filename
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
}

String _mediaArtifactHref(String path) {
  // Keep slash separators readable/triple-slash-compatible while encoding
  // every reserved character inside a path segment (`#`, `?`, `%`, spaces).
  final encoded = path.split('/').map(Uri.encodeComponent).join('/');
  return 'media-artifact://$encoded';
}

/// Decode one app-owned artifact link. Malformed or pathless crafted links are
/// inert instead of throwing from a Markdown tap callback.
String? mediaPathFromArtifactHref(String href) {
  const prefix = 'media-artifact://';
  if (!href.startsWith(prefix)) return null;
  try {
    final path = Uri.decodeComponent(href.substring(prefix.length));
    return _isPlausibleMediaPath(path) ? path : null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// Extract all explicit `MEDIA:` refs from final text, including inline refs.
///
/// Shares the rendering parser's quoting, punctuation and Markdown-code rules.
/// Keeps source order and repeated occurrences; consumers can dedupe by their
/// own session/path identity. Paths are never decoded or normalised.
List<MediaTagRef> extractMediaTagRefs(String text, {bool isFinal = true}) {
  final refs = <MediaTagRef>[];
  for (final match in _deliveryMatches(text, isFinal: isFinal)) {
    final parsed = _parseMediaTag(
      match,
      textLength: text.length,
      isFinal: isFinal,
    );
    if (parsed != null) refs.add(parsed.ref);
  }
  return refs;
}

/// Rewrite inline (mid-line) `MEDIA:` refs as markdown links so prose
/// rendering keeps them in context; standalone-line refs are left for
/// [splitMediaTags] card splicing. Code spans/blocks stay verbatim.
String inlineMediaTagsAsLinks(String text, {bool isFinal = true}) {
  final output = StringBuffer();
  var cursor = 0;
  for (final match in _deliveryMatches(text, isFinal: isFinal)) {
    final parsed = _parseMediaTag(
      match,
      textLength: text.length,
      isFinal: isFinal,
    );
    if (parsed == null) continue;
    output
      ..write(text.substring(cursor, match.start))
      ..write(
        '[${_mediaMarkdownLabel(parsed.ref.path)}]'
        '(${_mediaArtifactHref(parsed.ref.path)})'
        '${parsed.punctuation}',
      );
    cursor = match.end;
  }
  if (cursor == 0) return text;
  output.write(text.substring(cursor));
  return output.toString();
}

/// Split [text] into prose and media-reference segments. Degenerate captures
/// (`MEDIA:...`, bare words with no path separator or extension) stay prose.
///
/// [isFinal] distinguishes an authoritative terminal message from a growing
/// stream edge. Final absolute paths with an extension unknown to this client,
/// or no extension at all, remain actionable because the gateway has already
/// validated the delivery.
List<MediaTextSegment> splitMediaTags(String text, {bool isFinal = true}) {
  final segments = <MediaTextSegment>[];
  var cursor = 0;
  for (final match in _deliveryMatches(text, isFinal: isFinal)) {
    final parsed = _parseMediaTag(
      match,
      textLength: text.length,
      isFinal: isFinal,
    );
    if (parsed == null) continue;

    // A card is a block widget, so it may only replace a tag that occupies its
    // own line (the gateway's canonical delivery form). A mid-line tag stays
    // in prose and is rewritten by [inlineMediaTagsAsLinks].
    final lineStart = match.start == 0
        ? 0
        : text.lastIndexOf('\n', match.start - 1) + 1;
    final nlAfter = text.indexOf('\n', match.end);
    final lineEnd = nlAfter == -1 ? text.length : nlAfter;
    final standalone =
        text.substring(lineStart, match.start).trim().isEmpty &&
        text.substring(match.end, lineEnd).trim().isEmpty;
    if (!standalone) continue;

    if (lineStart > cursor) {
      segments.add(MediaTextSegment.prose(text.substring(cursor, lineStart)));
    }
    segments.add(MediaTextSegment.mediaRef(parsed.ref, standalone: true));
    if (parsed.punctuation.isNotEmpty) {
      segments.add(MediaTextSegment.prose(parsed.punctuation));
    }
    cursor = nlAfter == -1 ? text.length : nlAfter + 1;
  }
  if (segments.isEmpty) return [MediaTextSegment.prose(text)];
  if (cursor < text.length) {
    segments.add(MediaTextSegment.prose(text.substring(cursor)));
  }
  return segments;
}
