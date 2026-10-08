import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/remote_files_client.dart';
import '../utils/media_tags.dart';

/// Download a gateway path and hand it to the system share sheet. Shared by
/// [MediaArtifactCard] and inline `media-artifact://` markdown links.
Future<void> downloadAndShareMediaFile({
  required RemoteFilesDataSource Function() filesClient,
  required MediaTagRef ref,
}) async {
  final client = filesClient();
  final Uint8List bytes;
  try {
    bytes = (await client.download(ref.path)).bytes;
  } finally {
    if (client is RemoteFilesClient) client.close();
  }
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final safe = ref.filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${dir.path}/hermes-media-$stamp-$safe');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(subject: ref.filename, files: <XFile>[XFile(file.path)]),
  );
}

/// Renders one `MEDIA:` reference as a file card. The path is a
/// **gateway-host** path: bytes always come from the session's gateway
/// `fs/download` (never the local filesystem — a same-path local file on
/// the phone would be worse than a broken link).
class MediaArtifactCard extends StatefulWidget {
  final MediaTagRef ref;
  final RemoteFilesDataSource Function() filesClient;

  const MediaArtifactCard({
    super.key,
    required this.ref,
    required this.filesClient,
  });

  @override
  State<MediaArtifactCard> createState() => _MediaArtifactCardState();
}

class _MediaArtifactCardState extends State<MediaArtifactCard> {
  Uint8List? _bytes;
  Future<Uint8List?>? _inFlight;
  String? _error;

  @override
  void didUpdateWidget(MediaArtifactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Unkeyed list recycling and streaming ref growth can re-point this
    // State at a different ref; stale bytes would land under the wrong
    // filename (wrong file shared, wrong image previewed).
    if (oldWidget.ref.path != widget.ref.path) {
      _bytes = null;
      _inFlight = null;
      _error = null;
    }
  }

  /// Coalesces concurrent callers onto one download: a second tap while a
  /// fetch is in flight awaits the same future instead of getting null.
  Future<Uint8List?> _ensureBytes() {
    final cached = _bytes;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _download();
  }

  Future<Uint8List?> _download() async {
    setState(() => _error = null);
    try {
      final client = widget.filesClient();
      final Uint8List bytes;
      try {
        bytes = (await client.download(widget.ref.path)).bytes;
      } finally {
        if (client is RemoteFilesClient) client.close();
      }
      if (!mounted) return null;
      setState(() => _bytes = bytes);
      return bytes;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return null;
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _saveAndShare() async {
    final bytes = await _ensureBytes();
    if (bytes == null || !mounted) return;
    try {
      final dir = await getTemporaryDirectory();
      // Stale media shares from earlier taps are pruned here — the share
      // sheet gives no completion signal we can trust for deletion, so
      // the next share is the safe cleanup point (same pattern as
      // config_backup_io.dart). The unique stamp keeps two gateway paths
      // with the same basename from overwriting each other mid-share.
      try {
        for (final stale in dir.listSync().whereType<File>()) {
          if (stale.uri.pathSegments.last.startsWith('hermes-media-')) {
            try {
              stale.deleteSync();
            } catch (_) {
              // A file still held by an open share sheet stays; next round gets it.
            }
          }
        }
      } catch (_) {
        // Cleanup is best-effort; the share itself must not fail on it.
      }
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final safe = widget.ref.filename.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final file = File('${dir.path}/hermes-media-$stamp-$safe');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          subject: widget.ref.filename,
          files: <XFile>[XFile(file.path, mimeType: _mime)],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _showImagePreview() async {
    final bytes = await _ensureBytes();
    if (bytes == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 8,
                child: Center(child: Image.memory(bytes)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _imageExts = [
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'tiff',
  ];

  bool get _isImage => _imageExts.contains(widget.ref.extension);

  String? get _mime {
    switch (widget.ref.extension) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'm4a':
        return 'audio/mp4';
      case 'pdf':
        return 'application/pdf';
      case 'apk':
        return 'application/vnd.android.package-archive';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'txt':
      case 'md':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      default:
        return null;
    }
  }

  IconData get _icon {
    switch (widget.ref.extension) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'tiff':
      case 'svg':
        return Icons.image_outlined;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
      case '3gp':
        return Icons.movie_outlined;
      case 'mp3':
      case 'm2a':
      case 'wav':
      case 'ogg':
      case 'opus':
      case 'm4a':
      case 'flac':
        return Icons.audio_file_outlined;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'apk':
      case 'ipa':
        return Icons.android;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = _isImage;
    final l10n = context.l10n;
    final loading = _inFlight != null;

    return Material(
      // The chat bubble paints its background on a plain Container; without
      // its own Material the card's ListTile ink would paint underneath it.
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
            if (isImage && _bytes != null)
              InkWell(
                onTap: _showImagePreview,
                // Decode near-thumbnail resolution: a full-res photo
                // decoded for a ~208dp slot is tens of MB of RGBA per card.
                child: Image.memory(
                  _bytes!,
                  fit: BoxFit.cover,
                  cacheWidth: 1080,
                ),
              ),
            ListTile(
              dense: true,
              leading: loading
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
              subtitle: _error != null
                  ? Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis)
                  : Text(
                      _bytes == null ? l10n.media_card_tap_to_download : '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: IconButton(
                key: Key('media-card-download-${widget.ref.path}'),
                tooltip: l10n.media_card_download,
                icon: const Icon(Icons.download_outlined),
                onPressed: loading ? null : () => unawaited(_saveAndShare()),
              ),
              onTap: loading
                  ? null
                  : (isImage
                        ? _showImagePreview
                        : () => unawaited(_saveAndShare())),
            ),
          ],
        ),
      ),
    );
  }
}
