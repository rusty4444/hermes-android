import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:video_player/video_player.dart';

import '../services/attachment_video_service.dart';

/// Plays only the bytes already fetched by an explicit attachment tap. This
/// widget cannot fetch a remote URL, read a gateway path or access credentials.
class AttachmentVideoPreview extends StatefulWidget {
  const AttachmentVideoPreview({
    super.key,
    required this.bytes,
    required this.extension,
    this.fileStore = const AttachmentVideoFileStore(),
  });

  final Uint8List bytes;
  final String extension;

  /// Per-instance staging seam; widget tests never need real filesystem I/O.
  final AttachmentVideoFileStore fileStore;

  @override
  State<AttachmentVideoPreview> createState() => _AttachmentVideoPreviewState();
}

class _AttachmentVideoPreviewState extends State<AttachmentVideoPreview>
    with WidgetsBindingObserver {
  AttachmentVideoSession? _session;
  VideoPlayerController? _listening;
  Future<void> _cleanup = Future<void>.value();
  var _generation = 0;
  var _loading = true;
  var _failed = false;
  var _foreground = true;
  var _routeCurrent = true;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    _foreground =
        binding.lifecycleState == null ||
        binding.lifecycleState == AppLifecycleState.resumed;
    _start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Unlike a global RouteObserver, this also follows PopupRoutes above the
    // preview without requiring changes to the app's Navigator configuration.
    _routeCurrent = ModalRoute.isCurrentOf(context) ?? true;
    _syncPlaybackPermission();
  }

  @override
  void didUpdateWidget(covariant AttachmentVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.extension != widget.extension ||
        !identical(oldWidget.fileStore, widget.fileStore)) {
      _retire();
      _start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncPlaybackPermission();
  }

  void _syncPlaybackPermission() {
    final session = _session;
    if (session == null) return;
    unawaited(
      _command(
        session,
        () => session.setPlaybackAllowed(_foreground && _routeCurrent),
      ),
    );
  }

  void _start() {
    final session = _session = AttachmentVideoSession(
      fileStore: widget.fileStore,
    );
    _loading = true;
    _failed = false;
    unawaited(
      _open(session, _generation, widget.bytes, widget.extension, _cleanup),
    );
    _syncPlaybackPermission();
  }

  bool _current(AttachmentVideoSession session, int generation) =>
      mounted && generation == _generation && identical(session, _session);

  Future<void> _open(
    AttachmentVideoSession session,
    int generation,
    Uint8List bytes,
    String extension,
    Future<void> previousCleanup,
  ) async {
    try {
      // A late write/creation from a retired preview must be released before
      // the replacement starts staging, not merely ignored after completion.
      await previousCleanup;
      if (!_current(session, generation)) {
        await _closeQuietly(session);
        return;
      }
      final ready = await session.open(bytes, extension);
      if (!_current(session, generation)) {
        await _closeQuietly(session);
        return;
      }
      if (!ready) return;
      final controller = session.controller!;
      _listening = controller;
      controller.addListener(_videoChanged);
      setState(() => _loading = false);
      _videoChanged();
    } catch (_) {
      _fail(session, generation);
    }
  }

  void _videoChanged() {
    if (!mounted || _failed) return;
    final session = _session;
    final controller = session?.controller;
    if (session == null || controller == null) return;
    if (controller.value.hasError) {
      _fail(session, _generation);
      return;
    }
    setState(() {});
  }

  Future<void> _command(
    AttachmentVideoSession session,
    Future<void> Function() action,
  ) async {
    final generation = _generation;
    try {
      await action();
    } catch (_) {
      _fail(session, generation);
    }
  }

  void _stopListening() {
    _listening?.removeListener(_videoChanged);
    _listening = null;
  }

  void _fail(AttachmentVideoSession session, int generation) {
    if (!_current(session, generation) || _failed) return;
    _stopListening();
    setState(() {
      _loading = false;
      _failed = true;
    });
    _joinCleanup(session);
  }

  void _joinCleanup(AttachmentVideoSession session) {
    // Invoke close now to revoke accepted commands synchronously; only the
    // asynchronous resource join waits for earlier teardown.
    final closing = _closeQuietly(session);
    _cleanup = Future.wait<void>([_cleanup, closing]).then<void>((_) {});
  }

  static Future<void> _closeQuietly(AttachmentVideoSession session) async {
    try {
      await session.close();
    } catch (_) {
      // Teardown remains best-effort when the OS rejects removal. No fallback
      // may delete the shared app cache or another preview's resources.
    }
  }

  void _retire() {
    _generation++;
    _stopListening();
    final session = _session;
    _session = null;
    if (session != null) _joinCleanup(session);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_failed) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.attachment_video_failed,
            key: const Key('attachment-video-error'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
    }
    final session = _session;
    final controller = session?.controller;
    if (_loading || session == null || controller == null) {
      return Center(
        child: Semantics(
          label: l10n.attachment_loading,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    final value = controller.value;
    final aspectRatio = value.aspectRatio.isFinite && value.aspectRatio > 0
        ? value.aspectRatio
        : 1.0;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 360.0;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              Expanded(
                child: ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: VideoPlayer(
                        controller,
                        key: const Key('attachment-video-preview'),
                      ),
                    ),
                  ),
                ),
              ),
              // Controls wrap at narrow widths and scroll independently at
              // short heights/large text scales rather than overflowing.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: height / 2),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          IconButton(
                            key: const Key('attachment-video-play-pause'),
                            tooltip: value.isPlaying
                                ? l10n.attachment_video_pause
                                : l10n.attachment_video_play,
                            onPressed: () => unawaited(
                              _command(
                                session,
                                value.isPlaying ? session.pause : session.play,
                              ),
                            ),
                            icon: Icon(
                              value.isPlaying
                                  ? Icons.pause
                                  : value.isCompleted ||
                                        value.position >= value.duration
                                  ? Icons.replay
                                  : Icons.play_arrow,
                              color: scheme.onSurface,
                            ),
                          ),
                          IconButton(
                            key: const Key('attachment-video-mute'),
                            tooltip: value.volume == 0
                                ? l10n.attachment_video_unmute
                                : l10n.attachment_video_mute,
                            onPressed: () => unawaited(
                              _command(
                                session,
                                () => session.setMuted(value.volume != 0),
                              ),
                            ),
                            icon: Icon(
                              value.volume == 0
                                  ? Icons.volume_off
                                  : Icons.volume_up,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      Semantics(
                        label: l10n.attachment_video_seek,
                        child: Slider(
                          key: const Key('attachment-video-seek'),
                          value: value.duration.inMilliseconds > 0
                              ? (value.position.inMilliseconds /
                                        value.duration.inMilliseconds)
                                    .clamp(0.0, 1.0)
                              : 0,
                          onChanged: value.duration.inMilliseconds > 0
                              ? (position) => unawaited(
                                  _command(
                                    session,
                                    () => session.seekTo(
                                      Duration(
                                        milliseconds:
                                            (position *
                                                    value
                                                        .duration
                                                        .inMilliseconds)
                                                .round(),
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      Text(
                        '${_timestamp(value.position)} / '
                        '${_timestamp(value.duration)}',
                        key: const Key('attachment-video-position'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _timestamp(Duration duration) {
    final seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds ~/ 60) % 60;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$remainder';
    }
    return '${seconds ~/ 60}:$remainder';
  }
}
