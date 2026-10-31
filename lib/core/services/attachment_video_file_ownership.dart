import 'dart:convert';
import 'dart:io';

/// Process-owned cache protocol. A native reader may outlive its Dart widget:
/// retain the OS lock (and its descriptor) until confirmed native disposal, or
/// process death. Never infer reader death from a directory's age or a PID.
class AttachmentVideoDirectoryOwner {
  AttachmentVideoDirectoryOwner._(this.directory, this._marker);

  static const _markerName = '.owner-v1';
  static final _name = RegExp(r'^hermes-video-v1-([1-9][0-9]*)-');

  // A failed native release must not lose its lock when its widget/session is
  // garbage collected. The OS releases these descriptors at process death.
  static final _liveMarkers = <RandomAccessFile>{};

  final Directory directory;
  final RandomAccessFile _marker;
  Future<void>? _closing;

  static Future<AttachmentVideoDirectoryOwner> create(Directory root) async {
    final directory = await root.createTemp('hermes-video-v1-$pid-');
    RandomAccessFile? marker;
    try {
      marker = await File(
        '${directory.path}/$_markerName',
      ).open(mode: FileMode.append);
      await marker.lock(FileLock.exclusive);
      await marker.writeString('hermes-video-v1:$pid\n');
      await marker.flush();
      _liveMarkers.add(marker);
      return AttachmentVideoDirectoryOwner._(directory, marker);
    } catch (_) {
      // No bytes have been staged or given to a native player yet.
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        // A partial/unknown marker is deliberately not eligible for reaping.
      }
      try {
        await marker?.close();
      } catch (_) {
        // Preserve the original acquisition failure.
      }
      rethrow;
    }
  }

  /// Reap only versioned, unlocked owners from other processes, on the next
  /// video preparation. Unknown/legacy paths and symlinks fail closed.
  static Future<void> sweep(Directory root) async {
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final match = _name.firstMatch(name);
        if (match == null) continue;
        final ownerPid = int.tryParse(match[1]!);
        // POSIX fcntl locks are process-wide, not isolate/descriptor-wide.
        // Even opening/closing a second descriptor can release our own lock.
        // Skip this PID BEFORE opening the marker, including reused PIDs.
        if (ownerPid == null || ownerPid == pid) continue;
        final markerFile = File('${entity.path}/$_markerName');
        if (await FileSystemEntity.type(markerFile.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        RandomAccessFile? marker;
        try {
          marker = await markerFile.open(mode: FileMode.append);
          // Nonblocking. A live (even very old) owner is never a stale owner.
          await marker.lock(FileLock.exclusive);
          if (await marker.length() > 64) continue;
          await marker.setPosition(0);
          final contents = utf8.decode(await marker.read(64));
          if (contents != 'hermes-video-v1:$ownerPid\n') continue;
          await entity.delete(recursive: true);
        } on FileSystemException {
          // Busy owner, disappeared path, or rejected deletion: retain it.
        } on FormatException {
          // Unknown/corrupt ownership is not evidence of a dead native reader.
        } finally {
          await marker?.close();
        }
      }
    } on FileSystemException {
      // Cache cleanup is optional; it must not mask staging/codec errors.
    }
  }

  /// Call only after native disposal succeeds (or before native acquisition).
  Future<void> close() => _closing ??= _delete();

  Future<void> _delete() async {
    if (await directory.exists()) await directory.delete(recursive: true);
    await _marker.close();
    _liveMarkers.remove(_marker);
  }
}
