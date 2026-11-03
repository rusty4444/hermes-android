import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;

import 'remote_files_client.dart' show maxAttachmentDownloadBytes;

/// A native renderer handle, not a filesystem path. Android owns its cache
/// file and descriptor, and serialises open/render/close off the UI thread.
class AttachmentPdfDocument {
  AttachmentPdfDocument._(this.id, this.pageCount);

  static const channel = MethodChannel(
    'com.hermesagent.hermes_android/attachment_pdf',
  );
  static const maxPageDimension = 2048;
  static const maxPagePixels = 4 * 1024 * 1024;
  static const maxPages = 1000;
  final String id;
  final int pageCount;
  var _closed = false;

  static Future<AttachmentPdfDocument> open(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxAttachmentDownloadBytes) {
      throw const FormatException('PDF exceeds preview bounds');
    }
    final result = await channel.invokeMapMethod<String, dynamic>('open', {
      'bytes': bytes,
    });
    final id = result?['id'];
    final pages = result?['pageCount'];
    if (id is! String ||
        id.isEmpty ||
        pages is! int ||
        pages < 1 ||
        pages > maxPages) {
      if (id is String && id.isNotEmpty) {
        await channel.invokeMethod<void>('close', {'id': id});
      }
      throw const FormatException('Invalid PDF preview handle');
    }
    return AttachmentPdfDocument._(id, pages);
  }

  Future<Uint8List> render(int page) async {
    if (_closed || page < 0 || page >= pageCount) {
      throw StateError('PDF preview is closed or page is out of range');
    }
    final result = await channel.invokeMapMethod<String, dynamic>('render', {
      'id': id,
      'page': page,
      'maxWidth': 1536,
      'maxHeight': maxPageDimension,
    });
    if (_closed) throw StateError('PDF preview closed during render');
    final bytes = result?['bytes'];
    final width = result?['width'];
    final height = result?['height'];
    if (bytes is! Uint8List ||
        bytes.isEmpty ||
        bytes.length > 16 * 1024 * 1024 ||
        width is! int ||
        height is! int ||
        width < 1 ||
        height < 1 ||
        width > maxPageDimension ||
        height > maxPageDimension ||
        width * height > maxPagePixels) {
      throw const FormatException('Invalid rendered PDF page');
    }
    return bytes;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await channel.invokeMethod<void>('close', {'id': id});
  }
}
