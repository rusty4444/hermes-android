import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../utils/attachment_types.dart';
import 'attachment_video_file_ownership.dart';
import 'remote_files_client.dart' show maxAttachmentDownloadBytes;

export '../utils/attachment_types.dart' show attachmentIsVideo;

/// The one file/directory owned by a preview. Implementations must make close
/// idempotent; a fake can provide an inert File without doing widget-test I/O.
abstract interface class AttachmentVideoFile {
  File get file;
  Future<void> close();
}

/// Stages already-authorised, bounded bytes in app-private temporary storage.
/// No gateway path, original filename, URL or credentials enter this boundary.
class AttachmentVideoFileStore {
  const AttachmentVideoFileStore({
    this.temporaryDirectoryProvider = getTemporaryDirectory,
  });

  final Future<Directory> Function() temporaryDirectoryProvider;

  Future<AttachmentVideoFile> stage(Uint8List bytes, String extension) async {
    if (bytes.isEmpty || bytes.length > maxAttachmentDownloadBytes) {
      throw const FormatException('Video exceeds preview bounds');
    }
    if (!attachmentIsVideo(extension)) {
      throw const FormatException('Unsupported video container');
    }
    // Snapshot before any await: callers cannot change a pending file write.
    final snapshot = Uint8List.fromList(bytes);
    final root = await temporaryDirectoryProvider();
    await AttachmentVideoDirectoryOwner.sweep(root);
    final owner = await AttachmentVideoDirectoryOwner.create(root);
    final owned = _OwnedAttachmentVideoFile(
      owner,
      File('${owner.directory.path}/attachment.${extension.toLowerCase()}'),
    );
    try {
      await owned.file.writeAsBytes(snapshot, flush: true);
      return owned;
    } catch (_) {
      try {
        await owned.close();
      } catch (_) {
        // Preserve the staging error; never widen cleanup to the cache root.
      }
      rethrow;
    }
  }
}

class _OwnedAttachmentVideoFile implements AttachmentVideoFile {
  _OwnedAttachmentVideoFile(this._owner, this.file);

  final AttachmentVideoDirectoryOwner _owner;
  @override
  final File file;
  Future<void>? _closing;

  @override
  Future<void> close() => _closing ??= _delete();

  Future<void> _delete() => _owner.close();
}

/// Single-use ownership of staging, native creation, commands and teardown.
/// Close revokes commands synchronously, then joins outstanding writes/commands
/// before disposing the player and deleting only its owned temporary directory.
class AttachmentVideoSession {
  AttachmentVideoSession({this.fileStore = const AttachmentVideoFileStore()});

  final AttachmentVideoFileStore fileStore;
  AttachmentVideoFile? _file;
  VideoPlayerController? _controller;
  Future<bool>? _opening;
  Future<void>? _initializing;
  Future<void>? _closing;
  Future<void>? _releasing;
  Future<void> _commands = Future<void>.value();
  final _cancelOpening = Completer<void>();
  var _closed = false;
  var _ready = false;
  var _playbackAllowed = false;
  var _playbackEpoch = 0;

  VideoPlayerController? get controller => _closed ? null : _controller;

  Future<bool> open(Uint8List bytes, String extension) {
    if (_closed) {
      return Future<bool>.error(StateError('Video preview is closed'));
    }
    return _opening ??= _prepare(bytes, extension);
  }

  Future<bool> _prepare(Uint8List bytes, String extension) async {
    var failed = false;
    try {
      _file = await fileStore.stage(bytes, extension);
      if (_closed) return false;
      final controller = _controller = VideoPlayerController.file(
        _file!.file,
        httpHeaders: const <String, String>{},
        // We own lifecycle gating, including inactive/covered routes. The
        // plugin's lifecycle observer automatically resumes on foregrounding,
        // which would violate explicit-play-only playback. In 2.11.1 this
        // option suppresses that observer; it does not start background audio.
        videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: true),
      );
      _initializing = controller.initialize();
      await Future.any<void>([_initializing!, _cancelOpening.future]);
      if (_closed) return false;
      if (!controller.value.isInitialized || controller.value.hasError) {
        throw const FormatException('Video could not be initialized');
      }
      _ready = true;
      return true;
    } catch (_) {
      failed = true;
      _revoke();
      rethrow;
    } finally {
      if (_closed) {
        final releasing = _releaseResources();
        if (failed) {
          // The opening caller owns the original codec/staging failure. Cleanup
          // can fail or remain pending; close still joins its exact outcome.
          unawaited(
            releasing.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
          );
        } else {
          await releasing;
        }
      }
    }
  }

  /// Re-enabling never resumes playback. Suspending also revokes a play/replay
  /// accepted before a held seek or native play command finished.
  Future<void> setPlaybackAllowed(bool allowed) {
    if (_closed || allowed == _playbackAllowed) return Future<void>.value();
    _playbackAllowed = allowed;
    if (allowed) return Future<void>.value();
    _playbackEpoch++;
    return pause();
  }

  Future<void> play() {
    // A tap accepted while hidden must not become playable merely because a
    // queued command starts after a later foreground transition.
    if (_closed || !_ready || !_playbackAllowed) return Future<void>.value();
    final epoch = _playbackEpoch;
    return _enqueue(() async {
      final controller = _controller!;
      if (!_canPlay(epoch) || controller.value.duration <= Duration.zero) {
        return;
      }
      if (controller.value.isCompleted ||
          controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
        if (!_canPlay(epoch)) return;
      }
      // Do not enter video_player's own asynchronous auto-replay seek: it
      // cannot be revoked if the route/app is suspended during that await.
      if (controller.value.position >= controller.value.duration ||
          controller.value.isPlaying) {
        return;
      }
      await controller.play();
      // video_player can finish a held play after suspension. Join and pause
      // it before close can dispose its timer/native player.
      if (!_canPlay(epoch)) await controller.pause();
    });
  }

  bool _canPlay(int epoch) =>
      !_closed && _playbackAllowed && epoch == _playbackEpoch;

  Future<void> pause() => _enqueue(() => _controller!.pause());

  Future<void> seekTo(Duration position) =>
      _enqueue(() => _controller!.seekTo(position));

  Future<void> setMuted(bool muted) =>
      _enqueue(() => _controller!.setVolume(muted ? 0 : 1));

  Future<void> _enqueue(Future<void> Function() action) {
    if (_closed || !_ready) return Future<void>.value();
    final command = _commands.then((_) async {
      if (_closed) return;
      await action();
    });
    // Keep teardown joinable even when the UI handles a failed command.
    _commands = command.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return command;
  }

  void _revoke() {
    _closed = true;
    _ready = false;
    _playbackAllowed = false;
    _playbackEpoch++;
    if (!_cancelOpening.isCompleted) _cancelOpening.complete();
  }

  Future<void> close() {
    _revoke();
    return _closing ??= _finishClose();
  }

  Future<void> _finishClose() async {
    try {
      await _opening;
    } catch (_) {
      // The opening caller owns its playback/staging error.
    }
    await _releaseResources();
  }

  Future<void> _releaseResources() => _releasing ??= _release();

  Future<void> _release() async {
    await _commands;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        await controller.pause();
      } catch (_) {
        // Still dispose when a native pause fails.
      }
      // If native disposal fails, retain the source: the OS may still own a
      // reader. A rejected release is not proof that deleting it is safe.
      await _disposePlayer(controller);
    }
    final file = _file;
    _file = null;
    await file?.close();
  }

  Future<void> _disposePlayer(VideoPlayerController controller) async {
    // Do not await initialize here: native creation may succeed without ever
    // sending an initialized event. dispose joins creation, not initialization.
    // Only public disposal success proves release. In video_player 2.11.1 a
    // failed create can leave this pending: show the original error promptly,
    // but retain the locked source until process death rather than consulting
    // the plugin's testing-only playerId/private creation state.
    await controller.dispose();
  }
}
