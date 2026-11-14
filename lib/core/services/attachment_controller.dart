import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/media_tags.dart';
import 'connection_manager.dart' show DownloadSizeLimitException;
import 'remote_files_client.dart';

enum AttachmentFeedback {
  /// Over the in-memory preview budget; Save/Share can still stream it.
  downloadedTooLarge,

  /// Over [maxLargeAttachmentBytes] (1 GiB); only the dashboard can fetch it.
  overPhoneLimit,
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

typedef AttachmentFileShareHandler =
    Future<void> Function({
      required File file,
      required MediaTagRef ref,
      required bool Function() isCurrent,
    });

typedef AttachmentFileSaveHandler =
    Future<String?> Function({required File file, required MediaTagRef ref});

/// One immutable remote-file ownership scope, shared by a card and its popup.
/// The factory must create a client owned by this scope, not a shared client.
/// A different source/ref gets a new controller; no pending action can borrow
/// the replacement's filename, cached bytes or credentials.
class AttachmentController extends ChangeNotifier {
  AttachmentController({
    required this.ref,
    required this.filesClient,
    AttachmentShareHandler? shareHandler,
    AttachmentFileShareHandler? fileShareHandler,
    AttachmentFileSaveHandler? fileSaveHandler,
  }) : _shareHandler = shareHandler ?? shareAttachmentBytes,
       _fileShareHandler = fileShareHandler ?? shareAttachmentFile,
       _fileSaveHandler = fileSaveHandler ?? saveAttachmentFile;

  final MediaTagRef ref;
  final RemoteFilesDataSource Function() filesClient;
  final AttachmentShareHandler _shareHandler;
  final AttachmentFileShareHandler _fileShareHandler;
  final AttachmentFileSaveHandler _fileSaveHandler;
  Uint8List? _bytes;
  // Deliveries over the in-memory preview budget stream to this cache file
  // (up to [maxLargeAttachmentBytes]) for Save and Share.
  File? _largeFile;
  Directory? _largeDirectory;
  Future<File?>? _largeDownload;
  int? _largeReceived;
  int? _largeTotal;
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

  /// 0..1 while a large delivery streams to disk with a known length.
  double? get largeProgress {
    final received = _largeReceived, total = _largeTotal;
    if (_largeDownload == null || received == null) return null;
    if (total == null || total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }

  /// Bytes received so far by a large delivery, for an unknown-length label.
  int? get largeReceived => _largeDownload == null ? null : _largeReceived;
  bool get streamingLarge => _largeDownload != null;
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

  /// The in-memory budget refused this delivery, but the source can stream it.
  bool _shouldStreamLarge() =>
      _bytes == null &&
      _feedback == AttachmentFeedback.downloadedTooLarge &&
      lastError is DownloadSizeLimitException;

  Future<File?> _ensureLargeFile(int generation) {
    if (_largeFile case final file?) return Future.value(file);
    return _largeDownload ??= _streamLarge(generation);
  }

  Future<File?> _streamLarge(int generation) async {
    RemoteFilesDataSource? client;
    Directory? directory;
    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      client = filesClient();
      if (client is! RemoteFileStreamingSource) return null;
      final root = await getTemporaryDirectory();
      if (!_current(generation)) return null;
      directory = await root.createTemp('hermes-attachment-large-');
      final file = File('${directory.path}/${_safeFilename(ref.filename)}');
      _largeReceived = 0;
      _largeTotal = null;
      _feedback = null;
      lastError = null;
      notifyListeners();
      final name = await (client as RemoteFileStreamingSource).downloadToFile(
        ref.path,
        file,
        isCancelled: () => !_current(generation),
        onProgress: (received, total) {
          if (!_current(generation)) return;
          _largeReceived = received;
          _largeTotal = total;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds >= 200) {
            lastNotify = now;
            notifyListeners();
          }
        },
      );
      if (!_current(generation) || name == null) {
        await _deleteDirectory(directory);
        return null;
      }
      _largeDirectory = directory;
      return _largeFile = file;
    } catch (error) {
      if (directory != null) await _deleteDirectory(directory);
      if (!_current(generation)) return null;
      lastError = error;
      _feedback = error is DownloadSizeLimitException
          ? AttachmentFeedback.overPhoneLimit
          : AttachmentFeedback.downloadFailed;
      return null;
    } finally {
      if (client is RemoteFilesClient) client.close();
      if (_current(generation)) {
        _largeDownload = null;
        _largeReceived = null;
        _largeTotal = null;
        notifyListeners();
      }
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
      if (!current()) return;
      if (bytes == null) {
        if (!_shouldStreamLarge()) return;
        final file = await _ensureLargeFile(generation);
        if (!current() || file == null) return;
        final destination = await _fileSaveHandler(file: file, ref: ref);
        if (!current()) return;
        _feedback = destination == null || destination.isEmpty
            ? AttachmentFeedback.saveCancelled
            : AttachmentFeedback.saved;
        return;
      }
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
      if (!current()) return;
      if (bytes == null) {
        if (!_shouldStreamLarge()) return;
        final file = await _ensureLargeFile(generation);
        if (!current() || file == null) return;
        await _fileShareHandler(file: file, ref: ref, isCurrent: current);
        return;
      }
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
    _largeFile = null;
    _largeDownload = null;
    final directory = _largeDirectory;
    _largeDirectory = null;
    if (directory != null) unawaited(_deleteDirectory(directory));
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
    final file = File('${directory.path}/${_safeFilename(ref.filename)}');
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

String _safeFilename(String name) {
  final safeName = name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
  return safeName.isEmpty || safeName == '.' || safeName == '..'
      ? 'attachment'
      : safeName;
}

Future<void> _deleteDirectory(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {
    // Cache cleanup is best effort; the OS also trims the cache directory.
  }
}

/// Share a large delivery already streamed to this app's cache.
Future<void> shareAttachmentFile({
  required File file,
  required MediaTagRef ref,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  await SharePlus.instance.share(
    ShareParams(
      subject: ref.filename,
      files: [XFile(file.path, mimeType: attachmentMimeType(ref.extension))],
    ),
  );
}

const _attachmentSaveChannel = MethodChannel(
  'com.hermesagent.hermes_android/attachment_save',
);

/// Ask Android for a destination and stream-copy the cached file into it,
/// so a 1 GB delivery is never held in memory. Null means Cancel.
Future<String?> saveAttachmentFile({
  required File file,
  required MediaTagRef ref,
}) => _attachmentSaveChannel.invokeMethod<String>('saveFile', {
  'path': file.path,
  'filename': ref.filename,
  'mimeType': attachmentMimeType(ref.extension) ?? 'application/octet-stream',
});

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
