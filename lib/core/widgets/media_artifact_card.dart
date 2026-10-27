import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

import '../services/attachment_controller.dart';
import '../services/remote_files_client.dart';
import '../utils/attachment_types.dart';
import '../utils/media_tags.dart';
import 'attachment_preview_dialog.dart';

/// Compatibility API for callers that explicitly request the share sheet.
/// New inline links should use [openMediaFilePreview] instead.
Future<void> downloadAndShareMediaFile({
  required RemoteFilesDataSource Function() filesClient,
  required MediaTagRef ref,
}) async {
  final controller = AttachmentController(ref: ref, filesClient: filesClient);
  try {
    await controller.share();
    if (controller.feedback != null) {
      throw controller.lastError ?? StateError('Could not share attachment');
    }
  } finally {
    controller.dispose();
  }
}

final _inlinePreviews = Expando<Future<void>>();

/// Open a gateway-only preview from an inline link. The popup owns the client
/// and cancels its download when closed. Repeated taps cannot stack popups.
Future<void> openMediaFilePreview({
  required BuildContext context,
  required RemoteFilesDataSource Function() filesClient,
  required MediaTagRef ref,
  Object? sourceIdentity,
  InlineMediaPreviewOwner? owner,
}) async {
  if (!context.mounted) return;
  owner ??= InlineMediaPreviewScope.ownerOf(context);
  if (owner != null && !owner.accepts(filesClient, sourceIdentity, ref)) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final existing = _inlinePreviews[navigator];
  if (existing != null) return existing;
  final completion = Completer<void>();
  _inlinePreviews[navigator] = completion.future;
  final controller = AttachmentController(ref: ref, filesClient: filesClient);
  final route = attachmentPreviewRoute(
    context: context,
    controller: controller,
  );
  owner?.attach(controller, route);
  try {
    // Begin before pushing the route: a first tap starts cancellation-aware
    // I/O immediately, without waiting for its entry animation or build.
    unawaited(controller.ensureBytes());
    await navigator.push(route);
  } finally {
    owner?.detach(controller);
    controller.dispose();
    _inlinePreviews[navigator] = null;
    completion.complete();
  }
}

/// Keeps inline-link popups owned by the originating bubble, not the root
/// Navigator. Replacing its authority/reference or evicting it revokes actions
/// immediately and removes only the captured popup after the build frame.
class InlineMediaPreviewScope extends StatefulWidget {
  const InlineMediaPreviewScope({
    super.key,
    required this.filesClient,
    required this.references,
    required this.builder,
    this.sourceIdentity,
  });

  final RemoteFilesDataSource Function()? filesClient;
  final Object? sourceIdentity;
  final List<MediaTagRef> references;
  final WidgetBuilder builder;

  @override
  State<InlineMediaPreviewScope> createState() => InlineMediaPreviewOwner();

  static InlineMediaPreviewOwner? ownerOf(BuildContext context) =>
      context.findAncestorStateOfType<InlineMediaPreviewOwner>();
}

class InlineMediaPreviewOwner extends State<InlineMediaPreviewScope> {
  AttachmentController? _controller;
  DialogRoute<void>? _route;

  bool _contains(MediaTagRef ref) => widget.references.any(
    (current) => current.path == ref.path && current.filename == ref.filename,
  );

  bool accepts(
    RemoteFilesDataSource Function() filesClient,
    Object? sourceIdentity,
    MediaTagRef ref,
  ) =>
      mounted &&
      (widget.sourceIdentity != null || sourceIdentity != null
          ? widget.sourceIdentity == sourceIdentity
          : widget.filesClient == filesClient) &&
      widget.filesClient != null &&
      _contains(ref);

  void attach(AttachmentController controller, DialogRoute<void> route) {
    _controller = controller;
    _route = route;
  }

  void detach(AttachmentController controller) {
    if (!identical(controller, _controller)) return;
    _controller = null;
    _route = null;
  }

  void _release() {
    _controller?.dispose();
    _controller = null;
    final route = _route;
    _route = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  void didUpdateWidget(InlineMediaPreviewScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        widget.sourceIdentity != null || oldWidget.sourceIdentity != null
        ? oldWidget.sourceIdentity != widget.sourceIdentity
        : oldWidget.filesClient != widget.filesClient;
    if (sourceChanged ||
        widget.filesClient == null ||
        (_controller != null && !_contains(_controller!.ref))) {
      _release();
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Builder(builder: widget.builder);
}

/// A gateway-host reference, never a phone-local filesystem path. Rendering a
/// card does not instantiate a client or fetch any bytes.
class MediaArtifactCard extends StatefulWidget {
  final MediaTagRef ref;
  final RemoteFilesDataSource Function() filesClient;

  /// Stable authority identity (e.g. connection/profile/session tuple) when
  /// callers recreate their factory closure on ordinary parent rebuilds.
  /// Without one, replacing the factory is conservatively a new source.
  final Object? sourceIdentity;

  const MediaArtifactCard({
    super.key,
    required this.ref,
    required this.filesClient,
    this.sourceIdentity,
  });

  @override
  State<MediaArtifactCard> createState() => _MediaArtifactCardState();
}

class _MediaArtifactCardState extends State<MediaArtifactCard> {
  late AttachmentController _controller;
  var _openingPreview = false;
  DialogRoute<void>? _previewRoute;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = AttachmentController(
      ref: widget.ref,
      filesClient: widget.filesClient,
    );
    _controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _releaseController() {
    _controller.removeListener(_changed);
    _controller.dispose();
    final route = _previewRoute;
    _previewRoute = null;
    if (route != null) {
      // didUpdateWidget/dispose can occur during the build phase. Remove the
      // captured old route after that frame, never pop an unrelated route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final navigator = route.navigator;
        if (navigator != null && navigator.mounted && route.isActive) {
          navigator.removeRoute(route);
        }
      });
    }
  }

  @override
  void didUpdateWidget(MediaArtifactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        widget.sourceIdentity != null || oldWidget.sourceIdentity != null
        ? oldWidget.sourceIdentity != widget.sourceIdentity
        : oldWidget.filesClient != widget.filesClient;
    if (oldWidget.ref.path != widget.ref.path ||
        oldWidget.ref.filename != widget.ref.filename ||
        sourceChanged) {
      _releaseController();
      _openingPreview = false;
      _createController();
    }
  }

  @override
  void dispose() {
    _releaseController();
    super.dispose();
  }

  Future<void> _openPreview() async {
    if (_openingPreview) return;
    final controller = _controller;
    setState(() => _openingPreview = true);
    try {
      final bytes = await controller.ensureBytes();
      if (!mounted ||
          !identical(controller, _controller) ||
          !controller.active ||
          bytes == null) {
        return;
      }
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = attachmentPreviewRoute(
        context: context,
        controller: controller,
      );
      _previewRoute = route;
      await navigator.push(route);
      if (!mounted ||
          !identical(controller, _controller) ||
          !controller.active) {
        return;
      }
      _previewRoute = null;
    } finally {
      if (mounted && identical(controller, _controller) && controller.active) {
        setState(() => _openingPreview = false);
      }
    }
  }

  IconData get _icon {
    final extension = widget.ref.extension;
    if (attachmentIsImageAsset(extension)) return Icons.image_outlined;
    if (attachmentIsVideo(extension)) return Icons.movie_outlined;
    if (attachmentIsAudio(extension)) return Icons.audio_file_outlined;
    return extension == 'pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final bytes = controller.bytes;
    final feedback = attachmentFeedbackText(context, controller.feedback);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: Key('media-card-${widget.ref.path}'),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachmentIsImage(widget.ref.extension) && bytes != null)
              InkWell(
                onTap: _openingPreview ? null : () => unawaited(_openPreview()),
                child: SizedBox(
                  height: 208,
                  child: attachmentImage(context, bytes, thumbnail: true),
                ),
              ),
            // The ListTile ink needs its own transparent Material even when
            // the card is inside an opaque chat-bubble decoration.
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                leading: controller.loading || controller.acting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_icon, color: theme.colorScheme.primary),
                title: Text(
                  widget.ref.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  feedback ??
                      (bytes == null
                          ? context.l10n.media_card_tap_to_download
                          : context.l10n.attachment_tap_to_preview),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: AttachmentActions(controller: controller, card: true),
                onTap: _openingPreview ? null : () => unawaited(_openPreview()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
