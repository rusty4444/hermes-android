import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

import '../services/attachment_controller.dart';
import '../services/attachment_pdf_service.dart';
import '../utils/attachment_types.dart';
import 'attachment_document_preview.dart';
import 'attachment_video_preview.dart';
import 'hermes_system_ui.dart';

export '../utils/attachment_types.dart' show attachmentIsImage;

bool attachmentIsText(String extension) => const {
  'txt',
  'md',
  'markdown',
  'json',
  'csv',
  'tsv',
  'log',
  'yaml',
  'yml',
  'xml',
  'svg',
  'html',
  'htm',
  'css',
  'js',
  'ts',
  'dart',
  'py',
  'sh',
  'sql',
  'ini',
  'toml',
  'conf',
  'config',
  'rst',
  'tex',
  'c',
  'h',
  'cpp',
  'rs',
  'java',
  'kt',
  'go',
  'rb',
}.contains(extension.toLowerCase());

/// Inert, bounded UTF-8, never Markdown/HTML/SVG execution or network loading.
class AttachmentTextContent {
  static const maxBytes = 64 * 1024;
  final String? text;
  final bool truncated;
  AttachmentTextContent(Uint8List bytes)
    : truncated = bytes.length > maxBytes,
      text = _decode(bytes);

  static String? _decode(Uint8List bytes) {
    final prefix = Uint8List.sublistView(
      bytes,
      0,
      bytes.length > maxBytes ? maxBytes : bytes.length,
    );
    var controls = 0;
    for (final byte in prefix) {
      if (byte == 0) return null;
      if (byte < 32 && byte != 9 && byte != 10 && byte != 13) controls++;
    }
    if (controls > prefix.length ~/ 10) return null;
    return utf8.decode(prefix, allowMalformed: true);
  }
}

String? attachmentFeedbackText(
  BuildContext context,
  AttachmentFeedback? feedback,
) => switch (feedback) {
  AttachmentFeedback.downloadedTooLarge => context.l10n.assets_file_too_large,
  AttachmentFeedback.downloadFailed => context.l10n.attachment_download_failed,
  AttachmentFeedback.saved => context.l10n.attachment_saved,
  AttachmentFeedback.saveCancelled => context.l10n.attachment_save_cancelled,
  AttachmentFeedback.saveFailed => context.l10n.attachment_save_failed,
  AttachmentFeedback.shareFailed => context.l10n.attachment_share_failed,
  null => null,
};

/// Shared by the timeline and the popup, so Save/Share are single-flight even
/// when one surface is obscured by the other. A picker cancellation is not a
/// successful save. No file I/O is performed by rendering this widget.
class AttachmentActions extends StatelessWidget {
  const AttachmentActions({
    super.key,
    required this.controller,
    this.card = false,
  });
  final AttachmentController controller;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.active && !controller.acting;
    final l10n = context.l10n;
    void save() => unawaited(
      controller.save(
        dialogTitle: l10n.save_2(controller.ref.filename),
        isOwnerCurrent: () => context.mounted,
      ),
    );
    void share() =>
        unawaited(controller.share(isOwnerCurrent: () => context.mounted));
    if (card) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('media-card-download-${controller.ref.path}'),
            tooltip: l10n.download,
            icon: const Icon(Icons.download_outlined),
            onPressed: enabled ? save : null,
          ),
          IconButton(
            key: Key('media-card-share-${controller.ref.path}'),
            tooltip: l10n.attachment_share,
            icon: const Icon(Icons.share_outlined),
            onPressed: enabled ? share : null,
          ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const Key('attachment-preview-share'),
          onPressed: enabled ? share : null,
          icon: const Icon(Icons.share_outlined),
          label: Text(l10n.attachment_share),
        ),
        FilledButton.icon(
          key: const Key('attachment-preview-save'),
          onPressed: enabled ? save : null,
          icon: controller.acting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: Text(l10n.download),
        ),
      ],
    );
  }
}

/// Return the exact route to its owner so reference replacement can remove
/// only this popup, never a different route (e.g. a native picker above it).
DialogRoute<void> attachmentPreviewRoute({
  required BuildContext context,
  required AttachmentController controller,
}) => DialogRoute<void>(
  context: context,
  builder: (_) => controller.active
      ? AttachmentPreviewDialog(controller: controller)
      : const SizedBox.shrink(),
);

class AttachmentPreviewDialog extends StatelessWidget {
  const AttachmentPreviewDialog({super.key, required this.controller});
  final AttachmentController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final l10n = context.l10n;
      final image = attachmentIsImage(controller.ref.extension);
      final scheme = Theme.of(context).colorScheme;
      final feedback = attachmentFeedbackText(context, controller.feedback);
      // Preserve the existing cinema exception for images. Text, PDF and
      // unsupported types use the active application palette throughout.
      final foreground = image ? Colors.white : scheme.onSurface;
      return HermesSystemUi(
        cinema: image,
        child: Dialog.fullscreen(
          key: const Key('attachment-preview-dialog'),
          backgroundColor: image ? Colors.black : scheme.surface,
          child: SafeArea(
            child: Theme(
              data: image
                  ? Theme.of(context).copyWith(
                      colorScheme: ColorScheme.fromSeed(
                        seedColor: scheme.primary,
                        brightness: Brightness.dark,
                      ),
                    )
                  : Theme.of(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            controller.ref.filename,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: foreground),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          key: const Key('attachment-preview-close'),
                          tooltip: l10n.attachment_close,
                          color: foreground,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _content(context)),
                  if (feedback != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        feedback,
                        style: TextStyle(color: foreground),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: AttachmentActions(controller: controller),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _content(BuildContext context) {
    final bytes = controller.bytes;
    if (bytes == null) {
      if (controller.loading) {
        return Center(
          child: Semantics(
            label: context.l10n.attachment_loading,
            child: const CircularProgressIndicator(),
          ),
        );
      }
      return Center(
        child: TextButton.icon(
          onPressed: () => unawaited(controller.ensureBytes()),
          icon: const Icon(Icons.refresh),
          label: Text(context.l10n.attachment_retry),
        ),
      );
    }
    final extension = controller.ref.extension;
    if (attachmentIsImage(extension)) {
      return InteractiveViewer(
        key: const Key('attachment-image-preview'),
        minScale: 0.5,
        maxScale: 8,
        child: Center(child: attachmentImage(context, bytes)),
      );
    }
    if (attachmentIsVideo(extension)) {
      return AttachmentVideoPreview(
        key: ObjectKey(controller),
        bytes: bytes,
        extension: extension,
      );
    }
    if (attachmentIsDocument(extension)) {
      return AttachmentDocumentPreview(
        key: ObjectKey(controller),
        bytes: bytes,
        extension: extension,
      );
    }
    if (extension == 'pdf') {
      if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
        return _AttachmentInfo(
          message: context.l10n.attachment_pdf_unavailable,
        );
      }
      return _AttachmentPdfPreview(bytes: bytes);
    }
    if (attachmentIsText(extension)) {
      final content = AttachmentTextContent(bytes);
      if (content.text == null) {
        return _AttachmentInfo(
          message: context.l10n.attachment_text_unavailable,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (content.truncated)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.l10n.attachment_text_truncated),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                content.text!,
                key: const Key('attachment-text-preview'),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      );
    }
    return _AttachmentInfo(message: context.l10n.attachment_no_inline_preview);
  }
}

Widget attachmentImage(
  BuildContext context,
  Uint8List bytes, {
  bool thumbnail = false,
}) => Image(
  // Both dimensions are bounded, including pathological aspect ratios. Fit
  // preserves aspect ratio without allocating a full-resolution RGBA image.
  image: ResizeImage(
    MemoryImage(bytes),
    width: thumbnail ? 1080 : 2048,
    height: thumbnail ? 1080 : 2048,
    policy: ResizeImagePolicy.fit,
  ),
  fit: BoxFit.contain,
  errorBuilder: (context, error, stackTrace) =>
      _AttachmentInfo(message: context.l10n.attachment_image_failed),
);

class _AttachmentInfo extends StatelessWidget {
  const _AttachmentInfo({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AttachmentPdfPreview extends StatefulWidget {
  const _AttachmentPdfPreview({required this.bytes});
  final Uint8List bytes;
  @override
  State<_AttachmentPdfPreview> createState() => _AttachmentPdfPreviewState();
}

class _AttachmentPdfPreviewState extends State<_AttachmentPdfPreview> {
  AttachmentPdfDocument? _document;
  Uint8List? _pageBytes;
  var _page = 0;
  var _generation = 0;
  var _loading = true;
  var _failed = false;
  var _rendering = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final generation = _generation;
    try {
      final document = await AttachmentPdfDocument.open(widget.bytes);
      if (!mounted || generation != _generation) {
        await _close(document);
        return;
      }
      _document = document;
      await _render(0);
      if (!mounted || generation != _generation) return;
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _render(int page) async {
    final document = _document;
    if (document == null || _rendering) return;
    _rendering = true;
    final generation = _generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final bytes = await document.render(page);
      if (!mounted ||
          generation != _generation ||
          !identical(document, _document)) {
        return;
      }
      setState(() {
        _page = page;
        _pageBytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    } finally {
      if (mounted && generation == _generation) _rendering = false;
    }
  }

  static Future<void> _close(AttachmentPdfDocument document) async {
    try {
      await document.close();
    } catch (_) {
      /* Native teardown may have already closed it. */
    }
  }

  @override
  void dispose() {
    _generation++;
    final document = _document;
    _document = null;
    if (document != null) unawaited(_close(document));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final l10n = context.l10n;
    return Column(
      children: [
        Expanded(
          child: _loading
              ? Center(
                  child: Semantics(
                    label: l10n.attachment_loading,
                    child: const CircularProgressIndicator(),
                  ),
                )
              : _failed
              ? _AttachmentInfo(message: l10n.attachment_pdf_failed)
              : InteractiveViewer(
                  key: const Key('attachment-pdf-preview'),
                  maxScale: 5,
                  child: Center(
                    child: Image.memory(
                      _pageBytes!,
                      gaplessPlayback: true,
                      errorBuilder: (_, error, stackTrace) =>
                          _AttachmentInfo(message: l10n.attachment_pdf_failed),
                    ),
                  ),
                ),
        ),
        if (document != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('attachment-pdf-previous'),
                tooltip: l10n.attachment_previous_page,
                onPressed: !_loading && _page > 0
                    ? () => unawaited(_render(_page - 1))
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  l10n.attachment_pdf_page(_page + 1, document.pageCount),
                ),
              ),
              IconButton(
                key: const Key('attachment-pdf-next'),
                tooltip: l10n.attachment_next_page,
                onPressed: !_loading && _page + 1 < document.pageCount
                    ? () => unawaited(_render(_page + 1))
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
      ],
    );
  }
}
