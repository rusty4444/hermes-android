import 'package:markdown/markdown.dart' as md;

import 'media_tags.dart';

/// A Markdown file destination, never an arbitrary path found in prose.
///
/// Markdown encodes its destinations once. MEDIA paths use their own literal
/// contract and are decoded only by [mediaPathFromArtifactHref]. Web URLs,
/// relative documentation links and phone-local URI schemes are not files.
String? deliveredFilePathFromHref(String href) {
  final artifact = mediaPathFromArtifactHref(href);
  if (artifact != null) return artifact;
  try {
    final decoded = Uri.decodeComponent(href);
    if (decoded.contains(RegExp(r'[\x00-\x1f\x7f]'))) return null;
    if (decoded.startsWith('~/') ||
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(decoded)) {
      return decoded;
    }
    if (decoded.startsWith('/') && !decoded.startsWith('//')) return decoded;
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.scheme != 'file' ||
        (uri.host.isNotEmpty && uri.host != 'localhost') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final path = uri.toFilePath(windows: false);
    return path.startsWith('/') && path.length > 1 ? path : null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  } on UnsupportedError {
    return null;
  }
}

/// Explicit file links and image destinations outside code and quotations.
///
/// Wait for an authoritative answer before indexing Markdown links: an
/// incomplete streaming fence or destination can still become an example.
/// No URL is fetched or converted to an authenticated file request here.
List<MediaTagRef> extractMarkdownFileRefs(String text, {bool isFinal = true}) {
  if (!isFinal) return const [];
  final refs = <MediaTagRef>[];
  void collect(md.Node node) {
    if (node is! md.Element ||
        const {'code', 'pre', 'blockquote'}.contains(node.tag)) {
      return;
    }
    final href = switch (node.tag) {
      'a' => node.attributes['href'],
      'img' => node.attributes['src'],
      _ => null,
    };
    final path = href == null ? null : deliveredFilePathFromHref(href);
    if (path != null) refs.add(MediaTagRef(path: path));
    node.children?.forEach(collect);
  }

  md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parse(_protectLazyQuoteLinks(text)).forEach(collect);
  return refs;
}

/// markdown 7.3 treats a link-led lazy continuation as a possible reference
/// definition and detaches it from its quotation. Make only that continuation
/// explicit in the parser copy; rendering text and destinations stay exact.
String _protectLazyQuoteLinks(String text) {
  var quoteParagraph = false;
  final lines = text.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final quote = RegExp(
      r'^\s*(?:[-+*]|\d+[.)])?\s*>\s*(.*)$',
    ).firstMatch(line);
    if (quote != null) {
      final body = quote[1]!.replaceFirst(RegExp(r'^(?:>\s*)+'), '');
      quoteParagraph =
          body.trim().isNotEmpty &&
          !RegExp(r'^(?:`{3,}|~{3,}|#{1,6}\s)').hasMatch(body);
    } else if (line.trim().isEmpty ||
        RegExp(
          r'^\s*(?:`{3,}|~{3,}|#{1,6}\s|[-+*]\s|\d+[.)]\s)',
        ).hasMatch(line)) {
      quoteParagraph = false;
    } else if (quoteParagraph && RegExp(r'^\s*!?\[').hasMatch(line)) {
      final indentation = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
      lines[index] = '$indentation> ${line.substring(indentation.length)}';
    }
  }
  return lines.join('\n');
}

/// Shared timeline/Assets delivery policy. Dedupe by the exact owning-host
/// path; do not normalise filesystem names or collapse across conversations.
List<MediaTagRef> extractDeliveredFileRefs(String text, {bool isFinal = true}) {
  final refs = <String, MediaTagRef>{};
  for (final ref in [
    ...extractMediaTagRefs(text, isFinal: isFinal),
    ...extractMarkdownFileRefs(text, isFinal: isFinal),
  ]) {
    refs.putIfAbsent(ref.path, () => ref);
  }
  return refs.values.toList();
}

/// Canonical MEDIA markers need rewriting; ordinary file links already retain
/// their Markdown label/layout and are routed by [deliveredFilePathFromHref].
String inlineDeliveredFilesAsLinks(String text, {bool isFinal = true}) =>
    inlineMediaTagsAsLinks(text, isFinal: isFinal);
