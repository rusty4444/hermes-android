import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';

import '../models/attachment_draft.dart';

/// Maximum number of mixed image/file drafts in a Remote Gateway composer.
const maxRemoteAttachmentDrafts = 10;

/// Aggregate Remote Gateway draft budget: exactly 64 MiB (67,108,864 bytes).
const maxRemoteAttachmentDraftBytes = 64 * 1024 * 1024;

/// Existing per-item limit for generic files: exactly 16 MiB.
const maxGenericAttachmentBytes = 16 * 1024 * 1024;

/// The legacy REST transport remains single-image and proxy-budgeted.
const maxRestImageBytes = 680 * 1024;

final _mediaTypePattern = RegExp(
  r'^[a-zA-Z0-9][a-zA-Z0-9!#$&^_.+-]*/[a-zA-Z0-9][a-zA-Z0-9!#$&^_.+-]*$',
);

String _safeMediaType(String value) {
  final normalized = value.trim().toLowerCase();
  return _mediaTypePattern.hasMatch(normalized)
      ? normalized
      : 'application/octet-stream';
}

enum AttachmentDraftMode { remoteGateway, rest }

bool allowsMultipleImageSelection(AttachmentDraftMode mode) =>
    mode == AttachmentDraftMode.remoteGateway;

typedef AttachmentCacheDirectoryProvider = Future<Directory> Function();
typedef AttachmentCacheFileWriter =
    Future<void> Function(File destination, List<int> bytes);
typedef AttachmentUploadCallback =
    Future<AttachmentUploadReceipt> Function({
      required AttachmentDraft draft,
      required String dataUrl,
    });
typedef AttachmentDraftChanged = void Function(AttachmentDraft draft);
typedef AttachmentPromptSubmit = Future<void> Function(List<String> refTexts);

class AttachmentUploadReceipt {
  final String refText;
  final bool? atlasIntakeAccepted;

  const AttachmentUploadReceipt({
    required this.refText,
    this.atlasIntakeAccepted,
  });
}

class AttachmentDraftException implements Exception {
  final String message;

  const AttachmentDraftException(this.message);

  @override
  String toString() => message;
}

/// Testable boundary between ordered attachment upload and the single prompt
/// submission that follows it. Individual retry deliberately lives on a
/// separate method with no prompt callback.
class AttachmentDraftSendCoordinator {
  final AttachmentDraftService draftService;

  const AttachmentDraftSendCoordinator(this.draftService);

  Future<void> uploadThenSubmit({
    required Iterable<AttachmentDraft> drafts,
    required AttachmentUploadCallback upload,
    required AttachmentPromptSubmit submitPrompt,
    AttachmentDraftChanged? onChanged,
  }) async {
    final snapshot = drafts.toList(growable: false);
    await draftService.uploadSequential(
      drafts: snapshot,
      upload: upload,
      onChanged: onChanged,
    );
    final refs = snapshot
        .map((draft) => draft.refText)
        .whereType<String>()
        .where((ref) => ref.isNotEmpty)
        .toList(growable: false);
    if (refs.length != snapshot.length) {
      throw const AttachmentDraftException(
        'Every attachment must have a gateway reference before prompt submit.',
      );
    }
    await submitPrompt(refs);
  }

  Future<AttachmentUploadReceipt> retryFailed({
    required AttachmentDraft draft,
    required AttachmentUploadCallback upload,
    AttachmentDraftChanged? onChanged,
  }) {
    return draftService.retryFailed(
      draft: draft,
      upload: upload,
      onChanged: onChanged,
    );
  }
}

/// Owns attachment cache I/O, image metadata sanitization, policy checks, and
/// sequential uploads. UI code only retains small [AttachmentDraft] records.
class AttachmentDraftService {
  final AttachmentCacheDirectoryProvider _cacheDirectoryProvider;
  final AttachmentCacheFileWriter _cacheFileWriter;
  final DateTime Function() _clock;
  int _sequence = 0;

  AttachmentDraftService({
    AttachmentCacheDirectoryProvider? cacheDirectoryProvider,
    AttachmentCacheFileWriter? cacheFileWriter,
    DateTime Function()? clock,
  }) : _cacheDirectoryProvider =
           cacheDirectoryProvider ?? _defaultCacheDirectory,
       _cacheFileWriter = cacheFileWriter ?? _defaultCacheFileWriter,
       _clock = clock ?? DateTime.now;

  static Future<void> _defaultCacheFileWriter(
    File destination,
    List<int> bytes,
  ) async {
    await destination.writeAsBytes(bytes, flush: true);
  }

  static Future<Directory> _defaultCacheDirectory() async {
    final root = await getTemporaryDirectory();
    return Directory('${root.path}${Platform.pathSeparator}attachment_drafts');
  }

  Future<AttachmentDraft> prepareImage({
    required String sourcePath,
    required String displayName,
    required Iterable<AttachmentDraft> existingDrafts,
    required AttachmentDraftMode mode,
  }) async {
    final source = File(sourcePath);
    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw const AttachmentDraftException(
        'The selected image is empty or unreadable.',
      );
    }
    if (stat.size > maxRemoteAttachmentDraftBytes) {
      throw const AttachmentDraftException(
        'The selected image exceeds the 64 MiB draft budget.',
      );
    }
    if (mode == AttachmentDraftMode.remoteGateway) {
      _ensureRemoteSlot(existingDrafts);
    }

    Uint8List? sourceBytes;
    image_lib.Image? decoded;
    File? destination;
    var committed = false;
    try {
      sourceBytes = await source.readAsBytes();
      final format = _detectImageFormat(sourceBytes);
      if (format == null) {
        throw const AttachmentDraftException(
          'Unsupported image format. Choose a JPEG, PNG, or WebP image.',
        );
      }
      decoded = image_lib.decodeImage(sourceBytes);
      sourceBytes = null;
      if (decoded == null) {
        throw const AttachmentDraftException(
          'The selected JPEG, PNG, or WebP image could not be decoded safely.',
        );
      }

      var sanitized = image_lib.bakeOrientation(decoded);
      decoded = null;
      sanitized
        ..exif.clear()
        ..iccProfile = null
        ..textData = null;

      final outputIsJpeg = format == AttachmentImageFormat.jpeg;
      Uint8List? outputBytes = outputIsJpeg
          ? image_lib.encodeJpg(sanitized, quality: 85)
          : image_lib.encodePng(sanitized, level: 6);
      sanitized = image_lib.Image(width: 1, height: 1);

      final outputLength = outputBytes.length;
      if (mode == AttachmentDraftMode.rest &&
          outputLength > maxRestImageBytes) {
        throw const AttachmentDraftException(
          'The sanitized image is too large for the legacy REST limit.',
        );
      }
      if (mode == AttachmentDraftMode.remoteGateway) {
        _ensureRemoteAggregate(existingDrafts, outputLength);
      }

      final extension = outputIsJpeg ? 'jpg' : 'png';
      final outputName = _replaceExtension(displayName, extension);
      destination = await _newCacheFile(extension);
      await _cacheFileWriter(destination, outputBytes);
      outputBytes = null;
      final outputStat = await destination.stat();
      committed = true;
      return AttachmentDraft(
        id: _draftId(destination.path),
        cachedPath: destination.path,
        name: outputName,
        byteLength: outputStat.size,
        mediaType: outputIsJpeg ? 'image/jpeg' : 'image/png',
        kind: AttachmentDraftKind.image,
        sourceImageFormat: format,
        sanitized: true,
      );
    } on AttachmentDraftException {
      rethrow;
    } catch (_) {
      throw const AttachmentDraftException(
        'Unable to sanitize this image. Choose a valid JPEG, PNG, or WebP image.',
      );
    } finally {
      sourceBytes = null;
      decoded = null;
      if (!committed && destination != null) {
        await _deleteIfPresent(destination);
      }
    }
  }

  Future<AttachmentDraft> prepareGenericFile({
    required String sourcePath,
    required String displayName,
    String mediaType = 'application/octet-stream',
    required Iterable<AttachmentDraft> existingDrafts,
  }) async {
    _ensureRemoteSlot(existingDrafts);
    if (isSensitiveFileName(displayName)) {
      throw const AttachmentDraftException(
        'This filename is blocked because it may contain credentials.',
      );
    }
    final source = File(sourcePath);
    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw const AttachmentDraftException(
        'The selected file is empty or unreadable.',
      );
    }
    if (stat.size > maxGenericAttachmentBytes) {
      throw const AttachmentDraftException(
        'Generic files are limited to 16 MiB each.',
      );
    }
    _ensureRemoteAggregate(existingDrafts, stat.size);

    final destination = await _newCacheFile('bin');
    try {
      await source.openRead().pipe(destination.openWrite());
      final copiedSize = await destination.length();
      if (copiedSize != stat.size) {
        throw const AttachmentDraftException(
          'The selected file could not be copied completely.',
        );
      }
      return AttachmentDraft(
        id: _draftId(destination.path),
        cachedPath: destination.path,
        name: displayName,
        byteLength: copiedSize,
        mediaType: _safeMediaType(mediaType),
        kind: AttachmentDraftKind.genericFile,
      );
    } catch (_) {
      await _deleteIfPresent(destination);
      rethrow;
    }
  }

  /// Stage a paste exactly as UTF-8, without trimming or normalising newlines.
  Future<AttachmentDraft> preparePastedText({
    required String text,
    required Iterable<AttachmentDraft> existingDrafts,
  }) async {
    final existing = existingDrafts.toList(growable: false);
    _ensureRemoteSlot(existing);
    // UTF-8 uses at least one byte per valid UTF-16 code unit. Reject an
    // obviously oversized paste before allocating its encoded representation.
    if (text.isEmpty || text.length > maxGenericAttachmentBytes) {
      throw const AttachmentDraftException(
        'Paste exceeds the text file limit.',
      );
    }
    final bytes = utf8.encode(text);
    if (bytes.length > maxGenericAttachmentBytes) {
      throw const AttachmentDraftException(
        'Paste exceeds the text file limit.',
      );
    }
    _ensureRemoteAggregate(existing, bytes.length);
    final names = existing.map((draft) => draft.name).toSet();
    var name = 'paste.txt';
    for (var index = 2; names.contains(name); index++) {
      name = 'paste-$index.txt';
    }
    final destination = await _newCacheFile('txt');
    try {
      await _cacheFileWriter(destination, bytes);
      if (await destination.length() != bytes.length) {
        throw const AttachmentDraftException(
          'Paste could not be saved completely.',
        );
      }
      return AttachmentDraft(
        id: _draftId(destination.path),
        cachedPath: destination.path,
        name: name,
        byteLength: bytes.length,
        mediaType: 'text/plain',
        kind: AttachmentDraftKind.genericFile,
      );
    } catch (_) {
      await _deleteIfPresent(destination);
      rethrow;
    }
  }

  void validateRemoteDrafts(Iterable<AttachmentDraft> drafts) {
    final snapshot = drafts.toList(growable: false);
    if (snapshot.length > maxRemoteAttachmentDrafts) {
      throw const AttachmentDraftException(
        'You can attach up to 10 items to one Remote Gateway draft.',
      );
    }
    final total = snapshot.fold<int>(0, (sum, draft) => sum + draft.byteLength);
    if (total > maxRemoteAttachmentDraftBytes) {
      throw const AttachmentDraftException(
        'Attachments are limited to 64 MiB total per draft.',
      );
    }
    for (final draft in snapshot) {
      if (draft.kind == AttachmentDraftKind.genericFile &&
          draft.byteLength > maxGenericAttachmentBytes) {
        throw const AttachmentDraftException(
          'Generic files are limited to 16 MiB each.',
        );
      }
      if (draft.isImage && !draft.sanitized) {
        throw const AttachmentDraftException(
          'Remote images must be sanitized before upload.',
        );
      }
    }
  }

  void validateRestDrafts(Iterable<AttachmentDraft> drafts) {
    final snapshot = drafts.toList(growable: false);
    if (snapshot.length > 1 ||
        snapshot.any((draft) => !draft.isImage || !draft.sanitized)) {
      throw const AttachmentDraftException(
        'Legacy REST accepts exactly one sanitized image at most.',
      );
    }
    if (snapshot.isNotEmpty && snapshot.single.byteLength > maxRestImageBytes) {
      throw const AttachmentDraftException(
        'The sanitized image exceeds the legacy REST limit.',
      );
    }
  }

  bool moveDraft(
    List<AttachmentDraft> drafts, {
    required int fromIndex,
    required int offset,
  }) {
    final toIndex = fromIndex + offset;
    if (fromIndex < 0 ||
        fromIndex >= drafts.length ||
        toIndex < 0 ||
        toIndex >= drafts.length ||
        offset == 0) {
      return false;
    }
    final draft = drafts.removeAt(fromIndex);
    drafts.insert(toIndex, draft);
    return true;
  }

  Future<String> readDataUrl(AttachmentDraft draft) async {
    final bytes = await File(draft.cachedPath).readAsBytes();
    try {
      return 'data:${draft.mediaType};base64,${base64Encode(bytes)}';
    } finally {
      // The byte array is scoped to this one file and is never stored in the
      // draft model. The returned Base64 value is handed directly to transport.
    }
  }

  Future<List<AttachmentUploadReceipt>> uploadSequential({
    required Iterable<AttachmentDraft> drafts,
    required AttachmentUploadCallback upload,
    AttachmentDraftChanged? onChanged,
  }) async {
    final snapshot = drafts.toList(growable: false);
    validateRemoteDrafts(snapshot);
    final receipts = <AttachmentUploadReceipt>[];
    for (final draft in snapshot) {
      if (draft.status == AttachmentDraftStatus.attached &&
          draft.refText?.isNotEmpty == true) {
        receipts.add(
          AttachmentUploadReceipt(
            refText: draft.refText!,
            atlasIntakeAccepted: draft.atlasIntakeAccepted,
          ),
        );
        continue;
      }
      receipts.add(
        await _uploadOne(draft, upload: upload, onChanged: onChanged),
      );
    }
    return receipts;
  }

  /// Retries one failed `file.attach` only. This service has no prompt API, so
  /// retry cannot submit or replay the user's prompt.
  Future<AttachmentUploadReceipt> retryFailed({
    required AttachmentDraft draft,
    required AttachmentUploadCallback upload,
    AttachmentDraftChanged? onChanged,
  }) async {
    if (draft.status != AttachmentDraftStatus.failed) {
      throw const AttachmentDraftException(
        'Only a failed attachment can be retried.',
      );
    }
    return _uploadOne(draft, upload: upload, onChanged: onChanged);
  }

  Future<AttachmentUploadReceipt> _uploadOne(
    AttachmentDraft draft, {
    required AttachmentUploadCallback upload,
    AttachmentDraftChanged? onChanged,
  }) async {
    draft
      ..status = AttachmentDraftStatus.uploading
      ..error = null;
    onChanged?.call(draft);
    String? dataUrl;
    try {
      dataUrl = await readDataUrl(draft);
      final receipt = await upload(draft: draft, dataUrl: dataUrl);
      draft
        ..status = AttachmentDraftStatus.attached
        ..refText = receipt.refText
        ..atlasIntakeAccepted = receipt.atlasIntakeAccepted;
      dataUrl = null;
      await removeCachedFile(draft);
      onChanged?.call(draft);
      return receipt;
    } catch (error) {
      dataUrl = null;
      draft
        ..status = AttachmentDraftStatus.failed
        ..error = error.toString();
      onChanged?.call(draft);
      rethrow;
    }
  }

  Future<void> removeCachedFile(AttachmentDraft draft) async {
    await _deleteIfPresent(File(draft.cachedPath));
  }

  Future<void> removeAll(Iterable<AttachmentDraft> drafts) async {
    for (final draft in drafts) {
      await removeCachedFile(draft);
    }
  }

  static bool isSensitiveFileName(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.isEmpty) return true;
    if (lower == '.env' ||
        (lower.startsWith('.env.') &&
            !const {
              'dist',
              'example',
              'sample',
              'template',
            }.contains(lower.substring('.env.'.length)))) {
      return true;
    }
    if (lower == '.npmrc' || lower == '.netrc' || lower == '.pypirc') {
      return true;
    }
    if (lower.endsWith('.kdbx') ||
        lower.endsWith('.p12') ||
        lower.endsWith('.pem') ||
        lower.endsWith('.pfx')) {
      return true;
    }
    return RegExp(r'^id_(rsa|dsa|ecdsa|ed25519)(?:\..+)?$').hasMatch(lower);
  }

  void _ensureRemoteSlot(Iterable<AttachmentDraft> drafts) {
    if (drafts.length >= maxRemoteAttachmentDrafts) {
      throw const AttachmentDraftException(
        'You can attach up to 10 items to one Remote Gateway draft.',
      );
    }
  }

  void _ensureRemoteAggregate(
    Iterable<AttachmentDraft> drafts,
    int candidateBytes,
  ) {
    final current = drafts.fold<int>(0, (sum, draft) => sum + draft.byteLength);
    if (current + candidateBytes > maxRemoteAttachmentDraftBytes) {
      throw const AttachmentDraftException(
        'Attachments are limited to 64 MiB total per draft.',
      );
    }
  }

  AttachmentImageFormat? _detectImageFormat(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return AttachmentImageFormat.jpeg;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return AttachmentImageFormat.png;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return AttachmentImageFormat.webp;
    }
    return null;
  }

  Future<File> _newCacheFile(String extension) async {
    final directory = await _cacheDirectoryProvider();
    await directory.create(recursive: true);
    final id = '${_clock().microsecondsSinceEpoch}-${_sequence++}';
    return File(
      '${directory.path}${Platform.pathSeparator}draft-$id.$extension',
    );
  }

  String _draftId(String path) {
    final separator = Platform.pathSeparator;
    return path.substring(path.lastIndexOf(separator) + 1);
  }

  String _replaceExtension(String name, String extension) {
    final normalized = name.trim().isEmpty ? 'image' : name.trim();
    final dot = normalized.lastIndexOf('.');
    final base = dot > 0 ? normalized.substring(0, dot) : normalized;
    return '$base.$extension';
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Upload state must not be rewound after the gateway accepted the file.
      // The app-private OS cache remains bounded by platform cache eviction.
    }
  }
}
