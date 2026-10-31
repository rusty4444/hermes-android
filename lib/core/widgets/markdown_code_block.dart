import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:highlight/highlight.dart' as syntax;

import '../theme/hermes_theme.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

/// Splits raw markdown into text segments and fenced code blocks.
///
/// Returns a list of [String] (regular markdown, rendered by MarkdownBody)
/// and [MarkdownCodeBlock] (rendered with copy/wrap controls). The fenced
/// blocks are removed from the surrounding markdown so they render once,
/// with full fidelity, instead of relying on flutter_markdown's `pre`
/// builder (which leaves its internal inline state unbalanced).
List<Object> splitMarkdownCodeBlocks(String content) {
  final result = <Object>[];
  final regex = RegExp(
    r'```([\w+-]*)[ \t]*\r?\n([\s\S]*?)```',
    multiLine: true,
  );
  var cursor = 0;

  for (final match in regex.allMatches(content)) {
    if (match.start > cursor) {
      result.add(content.substring(cursor, match.start));
    }
    result.add(
      MarkdownCodeBlock(
        code: match.group(2)!,
        language: match.group(1)?.isEmpty ?? true ? null : match.group(1),
      ),
    );
    cursor = match.end;
  }

  if (cursor < content.length) {
    result.add(content.substring(cursor));
  }
  return result;
}

/// Renders a fenced code block with a language label, copy, and wrap controls.
class MarkdownCodeBlock extends StatefulWidget {
  final String code;
  final String? language;

  const MarkdownCodeBlock({super.key, required this.code, this.language});

  @override
  State<MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<MarkdownCodeBlock> {
  bool _wrap = false;

  // Cache the parser tree, never its TextStyles: a live palette change must
  // recolour an already-mounted block without reparsing its source.
  late List<syntax.Node>? _nodes = _parseCode();

  List<syntax.Node>? _parseCode() {
    final language = widget.language;
    if (language == null || widget.code.length > 60000) return null;
    try {
      return syntax.highlight.parse(widget.code, language: language).nodes;
    } catch (_) {
      // Unknown fence languages and malformed snippets remain selectable.
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language) {
      _nodes = _parseCode();
    }
  }

  Color _readable(Color candidate, Color background) {
    if (contrastRatio(candidate, background) >= 4.5) return candidate;
    final foreground = foregroundFor(background);
    for (var step = 1; step <= 20; step++) {
      final adjusted = Color.lerp(candidate, foreground, step / 20)!;
      if (contrastRatio(adjusted, background) >= 4.5) return adjusted;
    }
    return foreground;
  }

  TextSpan _span(syntax.Node node, HermesTokens tokens, ColorScheme scheme) {
    final color = switch (node.className) {
      'comment' || 'quote' => tokens.muted,
      'keyword' || 'selector-tag' || 'built_in' => tokens.accent,
      'string' || 'regexp' => scheme.tertiary,
      'number' || 'literal' || 'symbol' || 'bullet' => scheme.secondary,
      'title' || 'section' || 'name' || 'attribute' || 'attr' => scheme.primary,
      'addition' => tokens.success,
      'deletion' => tokens.danger,
      _ => null,
    };
    return TextSpan(
      text: node.value,
      style: color == null
          ? null
          : TextStyle(color: _readable(color, tokens.raised)),
      children: node.children
          ?.map((child) => _span(child, tokens, scheme))
          .toList(),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.code_copied),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final code = SelectableText.rich(
      TextSpan(
        text: _nodes == null ? widget.code : null,
        children: _nodes?.map((node) => _span(node, tokens, scheme)).toList(),
      ),
      style: tokens.typography.mono.copyWith(
        fontSize: 13,
        height: 1.45,
        color: _readable(tokens.onSurface, tokens.raised),
      ),
    );
    final body = _wrap
        ? code
        : SingleChildScrollView(scrollDirection: Axis.horizontal, child: code);

    return Container(
      key: const Key('markdown-code-block'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: tokens.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            color: tokens.surface,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language ?? 'code',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.accent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_wrap)
                  Tooltip(
                    message: context.l10n.scroll_horizontally,
                    child: IconButton(
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      onPressed: () => setState(() => _wrap = false),
                      constraints: const BoxConstraints.tightFor(
                        width: 40,
                        height: 40,
                      ),
                    ),
                  ),
                Tooltip(
                  message: context.l10n.wrap_lines,
                  child: IconButton(
                    icon: const Icon(Icons.wrap_text, size: 18),
                    onPressed: () => setState(() => _wrap = true),
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
                Tooltip(
                  message: context.l10n.copy_code,
                  child: IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    onPressed: _copy,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: body,
          ),
        ],
      ),
    );
  }
}
