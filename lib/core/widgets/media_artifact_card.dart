import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/remote_files_client.dart';
import '../utils/media_tags.dart';

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
  bool _loading = false;
  String? _error;

  Future<Uint8List?> _ensureBytes() async {
    if (_bytes != null || _loading) return _bytes;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = widget.filesClient();
      final Uint8List bytes;
      try {
        bytes = (await client.download(widget.ref.path)).bytes;
      } finally {
        if (client is RemoteFilesClient) client.close();
      }
      if (!mounted) return null;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
      return _bytes;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
      return null;
    }
  }

  Future<void> _saveAndShare() async {
    final bytes = await _ensureBytes();
    if (bytes == null || !mounted) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${widget.ref.filename}');
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        subject: widget.ref.filename,
        files: <XFile>[XFile(file.path)],
      ),
    );
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
    final isImage = const [
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'bmp',
      'tiff',
    ].contains(widget.ref.extension);
    final l10n = context.l10n;

    return Material(
      // The chat bubble paints its background on a plain Container; without
      // its own Material the card's ListTile ink would paint underneath it.
      type: MaterialType.transparency,
      child: Container(
        key: Key('media-card-${widget.ref.filename}'),
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
                child: Image.memory(_bytes!, fit: BoxFit.cover),
              ),
            ListTile(
              dense: true,
              leading: _loading
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
                key: Key('media-card-download-${widget.ref.filename}'),
                tooltip: l10n.media_card_download,
                icon: const Icon(Icons.download_outlined),
                onPressed: _loading ? null : () => unawaited(_saveAndShare()),
              ),
              onTap: _loading
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
