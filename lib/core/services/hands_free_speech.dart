import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../controllers/hands_free_conversation_controller.dart';

/// Injectable playback boundary; production uses ChatScreen's existing instance
/// with its selected voice/rate, not another plugin channel-handler owner.
abstract interface class VoiceReplySpeaker {
  Future<bool> prepare();
  Future<HandsFreeSpeechOutcome> speak(
    String text, {
    required bool Function() isCurrent,
  });
  Future<void> stop();
}

class FlutterVoiceReplySpeaker implements VoiceReplySpeaker {
  FlutterVoiceReplySpeaker(this.tts, {VoiceTimerFactory? timerFactory})
    : _timerFactory =
          timerFactory ?? ((duration, fire) => Timer(duration, fire)) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      tts.setCancelHandler(() => _end(HandsFreeSpeechOutcome.canceled));
      tts.setErrorHandler((_) => _end(HandsFreeSpeechOutcome.failed));
    }
    // Android's pinned native patch correlates the awaitSpeakCompletion reply
    // with its utterance/epoch/result identity. The upstream 4.2.5 Future alone
    // is not that guarantee. All Android terminal outcomes use that owned reply;
    // uncorrelated callbacks cannot complete OR cancel a replacement operation.
    // Other platforms retain their existing cancellation/error side channels.
  }
  final FlutterTts tts;
  final VoiceTimerFactory _timerFactory;
  Completer<HandsFreeSpeechOutcome>? _interrupted;
  Future<void>? _flight;
  Future<void>? _stopping;
  int _generation = 0;
  void _end(HandsFreeSpeechOutcome outcome) {
    final interrupted = _interrupted;
    if (interrupted != null && !interrupted.isCompleted) {
      interrupted.complete(outcome);
    }
  }

  @override
  Future<bool> prepare() async {
    if (_flight != null) return false;
    try {
      if (await tts.awaitSpeakCompletion(true) != 1) return false;
      if (await tts.setQueueMode(0) != 1) return false;
      final maximum = await tts.getMaxSpeechInputLength;
      return maximum != null && maximum >= 2;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HandsFreeSpeechOutcome> speak(
    String text, {
    required bool Function() isCurrent,
  }) async {
    if (_flight != null || !isCurrent() || text.trim().isEmpty) {
      return HandsFreeSpeechOutcome.unavailable;
    }
    final generation = ++_generation;
    final interrupted = _interrupted = Completer<HandsFreeSpeechOutcome>();
    final deadline = _timerFactory(
      const Duration(minutes: 5),
      () => _end(HandsFreeSpeechOutcome.deadline),
    );
    bool current() =>
        generation == _generation && isCurrent() && !interrupted.isCompleted;
    final done = Completer<void>();
    _flight = done.future;
    Future<HandsFreeSpeechOutcome?> step(
      Future<dynamic> operation, {
      bool successCode = true,
    }) async {
      final result = await Future.any<Object?>([
        operation.then<Object?>(
          (value) => value,
          onError: (Object _) => HandsFreeSpeechOutcome.failed,
        ),
        interrupted.future,
      ]);
      if (result is HandsFreeSpeechOutcome) return result;
      if (!current()) return HandsFreeSpeechOutcome.canceled;
      return successCode && result != 1 ? HandsFreeSpeechOutcome.failed : null;
    }

    HandsFreeSpeechOutcome result = HandsFreeSpeechOutcome.failed;
    try {
      await _stopping;
      if (!current()) return HandsFreeSpeechOutcome.canceled;
      var failure = await step(tts.awaitSpeakCompletion(true));
      if (failure != null) return result = failure;
      failure = await step(tts.setQueueMode(0));
      if (failure != null) return result = failure;
      final maximum = await Future.any<Object?>([
        tts.getMaxSpeechInputLength,
        interrupted.future,
      ]);
      if (maximum is HandsFreeSpeechOutcome) return result = maximum;
      if (!current()) return result = HandsFreeSpeechOutcome.canceled;
      if (maximum is! int || maximum < 2) {
        return result = HandsFreeSpeechOutcome.unavailable;
      }
      for (final chunk in splitSpeechInput(text.trim(), maximum)) {
        if (!current()) return result = HandsFreeSpeechOutcome.canceled;
        failure = await step(tts.speak(chunk, focus: true));
        if (failure != null) return result = failure;
      }
      return result = HandsFreeSpeechOutcome.completed;
    } catch (_) {
      return result = HandsFreeSpeechOutcome.failed;
    } finally {
      deadline.cancel();
      try {
        if (result != HandsFreeSpeechOutcome.completed) {
          // stop is a native playback barrier, not evidence of successful speech.
          await _stopNative();
        }
      } finally {
        if (identical(_interrupted, interrupted)) _interrupted = null;
        _flight = null;
        done.complete();
      }
    }
  }

  Future<void> _stopNative() {
    return _stopping ??= () async {
      try {
        if (await tts.stop() != 1) {
          throw StateError('Playback stop unconfirmed');
        }
      } finally {
        _stopping = null;
      }
    }();
  }

  @override
  Future<void> stop() async {
    ++_generation;
    _end(HandsFreeSpeechOutcome.canceled);
    final flight = _flight;
    await _stopNative();
    await flight;
  }
}

/// Split UTF-16 strings without cutting surrogate pairs, respecting Android's
/// maximum input length. Prefer a whitespace boundary without dropping text.
List<String> splitSpeechInput(String text, int maximum) {
  if (maximum < 2) throw ArgumentError.value(maximum, 'maximum');
  final chunks = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + maximum).clamp(0, text.length);
    if (end < text.length) {
      final last = text.codeUnitAt(end - 1);
      if (last >= 0xd800 && last <= 0xdbff) end--;
      final space = text.lastIndexOf(RegExp(r'\s'), end - 1);
      if (space > start + maximum ~/ 2) end = space + 1;
    }
    chunks.add(text.substring(start, end));
    start = end;
  }
  return chunks;
}
