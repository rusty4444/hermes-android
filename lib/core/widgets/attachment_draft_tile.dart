import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/hermes_theme.dart';

import '../models/attachment_draft.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class AttachmentDraftTile extends StatelessWidget {
  final AttachmentDraft draft;
  final int index;
  final int total;
  final bool busy;
  final VoidCallback onMovePrevious;
  final VoidCallback onMoveNext;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const AttachmentDraftTile({
    required this.draft,
    required this.index,
    required this.total,
    required this.busy,
    required this.onMovePrevious,
    required this.onMoveNext,
    required this.onRetry,
    required this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: context.l10n.attachment_of(index + 1, total),
      value: _statusLabel(context),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          minVerticalPadding: 4,
          leading: ExcludeSemantics(child: _leading(context)),
          title: ExcludeSemantics(
            child: Text(
              draft.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          subtitle: ExcludeSemantics(
            child: Text(
              draft.status == AttachmentDraftStatus.failed
                  ? context.l10n.upload_failed_tap_retry
                  : '${_formatFileSize(draft.byteLength)} • ${_statusLabel(context)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _semanticIconButton(
                icon: Icons.arrow_upward,
                label: context.l10n.move_attachment_previous,
                onPressed: busy || index == 0 ? null : onMovePrevious,
              ),
              _semanticIconButton(
                icon: Icons.arrow_downward,
                label: context.l10n.move_attachment_next,
                onPressed: busy || index == total - 1 ? null : onMoveNext,
              ),
              if (draft.status == AttachmentDraftStatus.failed)
                _semanticIconButton(
                  icon: Icons.refresh,
                  label: context.l10n.retry_upload,
                  onPressed: busy ? null : onRetry,
                )
              else
                _semanticIconButton(
                  icon: Icons.close,
                  label: context.l10n.remove_attachment,
                  onPressed: busy ? null : onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context) => switch (draft.status) {
    AttachmentDraftStatus.ready => context.l10n.ready_to_upload,
    AttachmentDraftStatus.uploading => context.l10n.upload_status_uploading,
    AttachmentDraftStatus.attached => context.l10n.upload_status_uploaded,
    AttachmentDraftStatus.failed => context.l10n.upload_failed,
  };

  Widget _leading(BuildContext context) {
    return switch (draft.status) {
      AttachmentDraftStatus.uploading => const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      AttachmentDraftStatus.attached => Icon(
        Icons.check_circle_outline,
        color: HermesTokens.of(context).success,
      ),
      AttachmentDraftStatus.failed => Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      AttachmentDraftStatus.ready when draft.isImage => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(draft.cachedPath),
          width: 44,
          height: 44,
          cacheWidth: 112,
          cacheHeight: 112,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      ),
      AttachmentDraftStatus.ready => const Icon(Icons.description_outlined),
    };
  }

  Widget _semanticIconButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: IconButton(
        icon: Icon(icon, size: 20),
        tooltip: label,
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
}
