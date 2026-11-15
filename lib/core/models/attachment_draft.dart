enum AttachmentDraftKind { image, genericFile }

enum AttachmentDraftStatus { ready, uploading, attached, failed }

enum AttachmentImageFormat { jpeg, png, webp }

/// A composer attachment backed by an app-private cache file.
///
/// Payload bytes and Base64 are intentionally absent. The upload service reads
/// and encodes only one [cachedPath] at a time.
class AttachmentDraft {
  final String id;
  final String cachedPath;
  final String name;
  final int byteLength;
  final String mediaType;
  final AttachmentDraftKind kind;
  final AttachmentImageFormat? sourceImageFormat;
  final bool sanitized;

  AttachmentDraftStatus status;
  String? refText;
  String? error;
  bool? atlasIntakeAccepted;

  /// 0..1 while a large file streams to the gateway's upload (NextGen).
  double? uploadProgress;

  AttachmentDraft({
    required this.id,
    required this.cachedPath,
    required this.name,
    required this.byteLength,
    required this.mediaType,
    required this.kind,
    this.sourceImageFormat,
    this.sanitized = false,
    this.status = AttachmentDraftStatus.ready,
    this.refText,
    this.error,
    this.atlasIntakeAccepted,
  });

  bool get isImage => kind == AttachmentDraftKind.image;
}
