import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

import '../services/attachment_document_service.dart';

export '../services/attachment_document_service.dart' show attachmentIsDocument;

typedef AttachmentDocumentLoader =
    Future<AttachmentDocumentPreviewData> Function(
      Uint8List bytes,
      String extension,
    );

/// Bounded, offline, selectable Office text; never a layout/active-content
/// renderer. The owning dialog retains Save/Share for the original bytes.
class AttachmentDocumentPreview extends StatefulWidget {
  const AttachmentDocumentPreview({
    super.key,
    required this.bytes,
    required this.extension,
    this.loader = AttachmentDocumentService.preview,
  });

  final Uint8List bytes;
  final String extension;
  @visibleForTesting
  final AttachmentDocumentLoader loader;

  @override
  State<AttachmentDocumentPreview> createState() =>
      _AttachmentDocumentPreviewState();
}

class _AttachmentDocumentPreviewState extends State<AttachmentDocumentPreview> {
  AttachmentDocumentPreviewData? _content;
  var _generation = 0;
  var _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AttachmentDocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.bytes, widget.bytes) &&
        oldWidget.extension == widget.extension &&
        oldWidget.loader == widget.loader) {
      return;
    }
    _generation++;
    _content = null;
    // Coalesce rapid replacements rather than spawning parallel parsers. The
    // old worker is bounded; only the newest pending input will be started.
    if (!_running) unawaited(_load());
  }

  Future<void> _load() async {
    if (_running || !mounted) return;
    _running = true;
    final generation = _generation;
    final bytes = widget.bytes;
    final extension = widget.extension;
    final loader = widget.loader;
    AttachmentDocumentPreviewData result;
    try {
      result = await loader(bytes, extension);
    } catch (_) {
      result = const AttachmentDocumentPreviewData.failed();
    }
    if (!mounted) return;
    _running = false;
    if (generation != _generation) {
      unawaited(_load());
      return;
    }
    setState(() => _content = result);
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            l10n.attachment_document_text_notice,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (content?.truncated ?? false)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(l10n.attachment_text_truncated),
          ),
        Expanded(
          child: content == null
              ? Center(
                  child: Semantics(
                    label: l10n.attachment_loading,
                    child: const CircularProgressIndicator(),
                  ),
                )
              : content.failed || content.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      content.failed
                          ? l10n.attachment_document_failed
                          : l10n.attachment_document_empty,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    content.text,
                    key: const Key('attachment-document-preview'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurface,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
