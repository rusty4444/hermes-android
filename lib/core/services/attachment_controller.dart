import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/media_tags.dart';
import 'connection_manager.dart' show DownloadSizeLimitException;
import 'remote_files_client.dart';

enum AttachmentFeedback {
  downloadedTooLarge,
  downloadFailed,
  saved,
  saveCancelled,
  saveFailed,
  shareFailed,
}

typedef AttachmentShareHandler =
    Future<void> Function({
      required Uint8List bytes,
      required MediaTagRef ref,
      required bool Function() isCurrent,
    });

/// One immutable remote-file ownership scope, shared by a card and its popup.
/// The factory must create a client owned by this scope, not a shared client.
/// A different source/ref gets a new controller; no pending action can borrow
/// the replacement's filename, cached bytes or credentials.
class AttachmentController extends ChangeNotifier {
  AttachmentController({
    required this.ref,
    required this.filesClient,
    AttachmentShareHandler? shareHandler,
  }) : _shareHandler = shareHandler ?? shareAttachmentBytes;

  final MediaTagRef ref;
  final RemoteFilesDataSource Function() filesClient;
  final AttachmentShareHandler _shareHandler;
  Uint8List? _bytes;
  Completer<Uint8List?>? _download;
  RemoteFilesClient? _activeClient;
  var _generation = 0;
  var _active = true;
  var _acting = false;
  AttachmentFeedback? _feedback;
  Object? lastError;

  Uint8List? get bytes => _bytes;
  bool get active => _active;
  bool get loading => _download != null;
  bool get acting => _acting;
  AttachmentFeedback? get feedback => _feedback;
  bool _current(int generation) => _active && generation == _generation;

  Future<Uint8List?> ensureBytes() {
    if (!_active) return Future.value();
    if (_bytes case final bytes?) return Future.value(bytes);
    if (_download case final download?) return download.future;
    final download = Completer<Uint8List?>();
    _download = download;
    _feedback = null;
    lastError = null;
    notifyListeners();
    // Start the transfer in the tap's stack, not after a route transition.
    unawaited(_fetch(_generation, download));
    return download.future;
  }

  Future<void> _fetch(int generation, Completer<Uint8List?> download) async {
    Uint8List? bytes;
    RemoteFilesDataSource? client;
    try {
      client = filesClient();
      if (client is RemoteFilesClient) _activeClient = client;
      final result = await client.download(ref.path);
      if (!_current(generation)) return;
      // The real client caps the streaming response. This second check also
      // protects previews/native rendering from custom data sources.
      if (result.bytes.length > maxAttachmentDownloadBytes) {
        _feedback = AttachmentFeedback.downloadedTooLarge;
      } else {
        bytes = _bytes = result.bytes;
      }
    } catch (error) {
      if (!_current(generation)) return;
      lastError = error;
      _feedback = error is DownloadSizeLimitException
          ? AttachmentFeedback.downloadedTooLarge
          : AttachmentFeedback.downloadFailed;
    } finally {
      if (client is RemoteFilesClient && identical(_activeClient, client)) {
        _activeClient = null;
        client.close();
      }
      if (_current(generation) && identical(_download, download)) {
        _download = null;
        notifyListeners();
      }
      if (!download.isCompleted) download.complete(bytes);
    }
  }

  Future<void> save({
    required String dialogTitle,
    bool Function()? isOwnerCurrent,
  }) async {
    if (!_active || _acting) return;
    final generation = _generation;
    bool current() => _current(generation) && (isOwnerCurrent?.call() ?? true);
    if (!current()) return;
    _acting = true;
    _feedback = null;
    notifyListeners();
    try {
      final bytes = await ensureBytes();
      if (!current() || bytes == null) return;
      // file_picker 10.3.3 writes these bytes (including on mobile). It is NOT
      // just a destination-path picker, and a null destination means Cancel.
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: ref.filename,
        type: FileType.any,
        bytes: bytes,
      );
      if (!current()) return;
      _feedback = destination == null || destination.isEmpty
          ? AttachmentFeedback.saveCancelled
          : AttachmentFeedback.saved;
    } catch (error) {
      if (!current()) return;
      lastError = error;
      _feedback = AttachmentFeedback.saveFailed;
    } finally {
      if (_current(generation)) {
        _acting = false;
        notifyListeners();
      }
    }
  }

  Future<void> share({bool Function()? isOwnerCurrent}) async {
    if (!_active || _acting) return;
    final generation = _generation;
    bool current() => _current(generation) && (isOwnerCurrent?.call() ?? true);
    if (!current()) return;
    _acting = true;
    _feedback = null;
    notifyListeners();
    try {
      final bytes = await ensureBytes();
      if (!_current(generation) || bytes == null) return;
      if (!current()) return;
      await _shareHandler(bytes: bytes, ref: ref, isCurrent: current);
      if (!current()) return;
    } catch (error) {
      if (!current()) return;
      lastError = error;
      _feedback = AttachmentFeedback.shareFailed;
    } finally {
      if (_current(generation)) {
        _acting = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (!_active) return;
    _active = false;
    _generation++;
    final client = _activeClient;
    _activeClient = null;
    client?.close();
    final download = _download;
    _download = null;
    if (download != null && !download.isCompleted) download.complete(null);
    _bytes = null;
    super.dispose();
  }
}

/// Share only downloaded bytes, never a gateway path on the phone filesystem.
/// Own a unique private directory; never prune another live share's files.
Future<void> shareAttachmentBytes({
  required Uint8List bytes,
  required MediaTagRef ref,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  final root = await getTemporaryDirectory();
  if (!isCurrent()) return;
  final directory = await root.createTemp('hermes-attachment-share-');
  try {
    if (!isCurrent()) return;
    final safeName = ref.filename.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
    final filename = safeName.isEmpty || safeName == '.' || safeName == '..'
        ? 'attachment'
        : safeName;
    final file = File('${directory.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    if (!isCurrent()) return;
    await SharePlus.instance.share(
      ShareParams(
        subject: ref.filename,
        files: [XFile(file.path, mimeType: attachmentMimeType(ref.extension))],
      ),
    );
    if (!isCurrent()) return;
  } finally {
    // Android share_plus copies the input into its own provider cache before
    // handing it to another app. Delete only our own staging directory.
    try {
      await directory.delete(recursive: true);
    } catch (_) {
      // Cache cleanup must not disguise an otherwise successful share.
    }
  }
}

// Leave unmapped formats to share_plus's filename-based MIME inference; forcing
// generic binary here would hide compatible image/audio share recipients.
String? attachmentMimeType(String extension) => switch (extension) {
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'bmp' => 'image/bmp',
  'tif' || 'tiff' => 'image/tiff',
  'svg' => 'image/svg+xml',
  'pdf' => 'application/pdf',
  'json' => 'application/json',
  'csv' => 'text/csv',
  'md' || 'markdown' => 'text/markdown',
  'txt' || 'log' => 'text/plain',
  'html' || 'htm' => 'text/html',
  'xml' => 'application/xml',
  'mp4' || 'm4v' => 'video/mp4',
  'mov' => 'video/quicktime',
  'webm' => 'video/webm',
  'mkv' => 'video/x-matroska',
  'avi' => 'video/x-msvideo',
  '3gp' => 'video/3gpp',
  'mp3' => 'audio/mpeg',
  'wav' => 'audio/wav',
  'ogg' => 'audio/ogg',
  'm4a' => 'audio/mp4',
  'zip' => 'application/zip',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'pptx' =>
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  _ => null,
};
