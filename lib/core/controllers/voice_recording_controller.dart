import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/local_voice_recorder.dart';

enum VoiceRecordingFailure {
  microphonePermission,
  start,
  stop,
  empty,
  durationLimit,
  resume,
  playback,
  discard,
  submissionUnconfirmed,
  submission,
}

/// One recording draft per chat. Only an accepted prompt deletes the draft.
class VoiceRecordingController extends ChangeNotifier {
  final VoiceRecorder recorder;
  bool recording = false;
  bool hasDraft = false;
  bool busy = false;
  bool playing = false;
  VoiceRecordingFailure? error;
  bool _disposed = false;
  bool _backgrounded = false;
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  late final Future<void> ready = _restore();

  VoiceRecordingController(this.recorder);

  Duration _savedDuration = Duration.zero;
  Duration get elapsed => _savedDuration + _clock.elapsed;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _restore() async {
    try {
      hasDraft = await recorder.restore();
      if (hasDraft) _savedDuration = await recorder.duration;
    } catch (_) {
      /* No platform in headless tests. */
    }
    _notify();
  }

  Future<void> start() async {
    await ready;
    if (_disposed || _backgrounded || busy || recording || hasDraft) return;
    busy = true;
    error = null;
    _notify();
    try {
      if (!await recorder.hasPermission(request: true)) {
        error = VoiceRecordingFailure.microphonePermission;
        return;
      }
      if (_disposed || _backgrounded) return;
      await recorder.start();
      if (_disposed || _backgrounded) {
        await recorder.stop();
        return;
      }
      recording = true;
      _savedDuration = Duration.zero;
      _clock
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (elapsed >= const Duration(minutes: 10)) {
          unawaited(stop());
        } else {
          _notify();
        }
      });
    } catch (_) {
      error = VoiceRecordingFailure.start;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stop() async {
    if (!recording || busy) return;
    busy = true;
    _timer?.cancel();
    _clock.stop();
    _notify();
    try {
      await recorder.stop();
      final captured = elapsed;
      hasDraft = await recorder.restore();
      _savedDuration = captured;
      _clock.reset();
      if (!hasDraft) error = VoiceRecordingFailure.empty;
    } catch (_) {
      error = VoiceRecordingFailure.stop;
    } finally {
      recording = false;
      busy = false;
      _notify();
    }
  }

  Future<void> resumeRecording() async {
    await ready;
    if (_disposed || _backgrounded || busy || recording || !hasDraft) return;
    if (elapsed >= const Duration(minutes: 10)) {
      error = VoiceRecordingFailure.durationLimit;
      _notify();
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      await recorder.pause();
      playing = false;
      if (!await recorder.hasPermission(request: true)) {
        error = VoiceRecordingFailure.microphonePermission;
        return;
      }
      if (_disposed || _backgrounded) return;
      await recorder.resumeRecording();
      if (_disposed || _backgrounded) {
        await recorder.stop();
        return;
      }
      _savedDuration = elapsed;
      _clock
        ..reset()
        ..start();
      recording = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (elapsed >= const Duration(minutes: 10)) {
          unawaited(stop());
        } else {
          _notify();
        }
      });
    } catch (e) {
      error = VoiceRecordingFailure.resume;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> togglePlayback() async {
    if (!hasDraft || busy || recording) return;
    try {
      if (playing) {
        await recorder.pause();
        playing = false;
      } else {
        playing = true;
        await recorder.play(() {
          playing = false;
          _notify();
        });
      }
    } catch (_) {
      playing = false;
      error = VoiceRecordingFailure.playback;
    }
    _notify();
  }

  Future<void> discard() async {
    if (busy) return;
    busy = true;
    _timer?.cancel();
    _clock.stop();
    _notify();
    try {
      await recorder.discard();
      hasDraft = recording = playing = false;
      _savedDuration = Duration.zero;
      _clock.reset();
      error = null;
    } catch (_) {
      error = VoiceRecordingFailure.discard;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> send({
    required Future<void> Function(String, VoidCallback) submit,
  }) async {
    if (!hasDraft || busy || recording || _disposed) return;
    busy = true;
    error = null;
    _notify();
    var accepted = false;
    var acceptingReceipt = true;
    Future<void>? cleanup;
    try {
      await recorder.pause();
      playing = false;
      final path = await recorder.prepareForSend();
      if (_disposed) return;
      await submit(path, () {
        if (accepted || _disposed || !acceptingReceipt) return;
        accepted = true;
        cleanup = recorder.discard().catchError((Object _) {});
        hasDraft = false;
        // The UI becomes the response's Stop button as soon as it is accepted.
        _notify();
      });
      if (!accepted && !_disposed) {
        error = VoiceRecordingFailure.submissionUnconfirmed;
      }
    } catch (failure) {
      if (!accepted) {
        error = VoiceRecordingFailure.submission;
      }
    } finally {
      acceptingReceipt = false;
      if (accepted) {
        try {
          await cleanup;
        } catch (_) {
          /* Draft cleanup can be retried on opening. */
        }
      }
      busy = false;
      _notify();
    }
  }

  void foreground() {
    _backgrounded = false;
  }

  Future<void> background() async {
    _backgrounded = true;
    await stop();
    try {
      await recorder.pause();
    } catch (_) {
      playing = false;
    }
    playing = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _clock.stop();
    // File survives leaving the screen, until Send or Delete.
    unawaited(recorder.close().catchError((Object _) {}));
    super.dispose();
  }
}
