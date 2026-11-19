// Read-aloud playback for the NextGen transcript (#288).
//
// Classic offers Read aloud on every assistant reply; NextGen had no TTS at
// all. This controller owns one engine per chat view: starting a reply stops
// whichever reply was being read, and the reading reply's action row shows
// Stop. Voice selection mirrors Classic (`voice_name`/`voice_locale` prefs,
// rate 0.48). Android playback uses the same completion-correlated speaker
// as Classic hands-free, so long replies are chunked to the engine's input
// limit and Stop is a real playback barrier; other platforms use the
// engine's completion/cancel side channels, guarded by generation so a
// stop's late cancel cannot clear the reply that replaced it.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/controllers/hands_free_conversation_controller.dart'
    show HandsFreeSpeechOutcome;
import '../../core/services/hands_free_speech.dart';

class NgReadAloud extends ChangeNotifier {
  NgReadAloud({
    FlutterTts? tts,
    VoiceReplySpeaker? speaker,
    Future<SharedPreferences> Function()? prefs,
    bool? android,
  }) : _tts = tts ?? FlutterTts(),
       _prefs = prefs ?? SharedPreferences.getInstance,
       _android =
           android ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    _speaker = speaker ?? (_android ? FlutterVoiceReplySpeaker(_tts) : null);
    if (_speaker == null) {
      _tts.setCompletionHandler(
        () => _terminal(HandsFreeSpeechOutcome.completed),
      );
      _tts.setCancelHandler(() => _terminal(HandsFreeSpeechOutcome.canceled));
      _tts.setErrorHandler((_) => _terminal(HandsFreeSpeechOutcome.failed));
    }
  }

  final FlutterTts _tts;
  final Future<SharedPreferences> Function() _prefs;
  final bool _android;
  late final VoiceReplySpeaker? _speaker;
  bool _prepared = false;
  bool _disposed = false;
  int _generation = 0;
  int _speakingGeneration = -1;
  String? _readingKey;
  Future<void>? _claiming;

  /// The side channels cannot name utterances: a stop's cancel can arrive
  /// after the replacement already speaks. Swallow exactly one such late
  /// cancel; a genuine cancel of the new utterance only comes from a later
  /// stop(), whose generation bump the terminal guard already catches.
  bool _swallowNextCancel = false;

  /// Set by the view to surface playback failures as a toast.
  void Function()? onUnavailable;

  /// The key of the reply currently being read, if any.
  String? get readingKey => _readingKey;

  bool isReading(String key) => _readingKey == key;

  /// Reads [text] for the reply identified by [key], stopping any other
  /// reply first. Empty text is a no-op.
  Future<void> read(String key, String text) async {
    final spoken = text.trim();
    if (spoken.isEmpty || _disposed) return;
    final intent = await _claim(key);
    if (intent == null || _disposed) return;
    HandsFreeSpeechOutcome? outcome;
    try {
      await _configureVoice();
      if (_disposed || intent != _generation) return;
      outcome = await _speak(spoken, intent);
    } catch (_) {
      outcome = HandsFreeSpeechOutcome.failed;
    }
    // A null outcome means the side-channel handlers own the terminal state.
    if (outcome == null || _disposed || intent != _generation) return;
    _readingKey = null;
    notifyListeners();
    if (outcome != HandsFreeSpeechOutcome.completed &&
        outcome != HandsFreeSpeechOutcome.canceled) {
      onUnavailable?.call();
    }
  }

  /// Stops playback and clears the reading state.
  Future<void> stop() async {
    _generation++;
    final had = _readingKey;
    _readingKey = null;
    if (had != null && !_disposed) notifyListeners();
    try {
      final speaker = _speaker;
      if (speaker != null) {
        await speaker.stop();
      } else {
        if (had != null) _swallowNextCancel = true;
        await _tts.stop();
      }
    } catch (_) {
      // A failed stop must not block the next read.
    }
  }

  /// Serializes the stop/claim section: two quick taps on different replies
  /// cannot interleave, so the second tap always stops what the first
  /// started before claiming its own reply.
  Future<int?> _claim(String key) async {
    final previous = _claiming;
    final done = Completer<void>();
    _claiming = done.future;
    try {
      if (previous != null) await previous;
      await stop();
      if (_disposed) return null;
      final intent = ++_generation;
      _readingKey = key;
      notifyListeners();
      return intent;
    } finally {
      done.complete();
      if (identical(_claiming, done.future)) _claiming = null;
    }
  }

  Future<HandsFreeSpeechOutcome?> _speak(String text, int intent) async {
    final speaker = _speaker;
    if (speaker != null) {
      if (!_prepared) {
        _prepared = await speaker.prepare();
        if (!_prepared) return HandsFreeSpeechOutcome.unavailable;
      }
      return speaker.speak(
        text,
        isCurrent: () => !_disposed && intent == _generation,
      );
    }
    await _tts.stop();
    if (_disposed || intent != _generation) {
      return HandsFreeSpeechOutcome.canceled;
    }
    _speakingGeneration = intent;
    final result = await _tts.speak(text);
    if (result != 1) return HandsFreeSpeechOutcome.failed;
    return null;
  }

  void _terminal(HandsFreeSpeechOutcome outcome) {
    if (_disposed || _readingKey == null) return;
    if (_speakingGeneration != _generation) return;
    if (outcome == HandsFreeSpeechOutcome.canceled && _swallowNextCancel) {
      _swallowNextCancel = false;
      return;
    }
    _swallowNextCancel = false;
    _generation++;
    _readingKey = null;
    notifyListeners();
    if (outcome == HandsFreeSpeechOutcome.failed) onUnavailable?.call();
  }

  /// Applies Classic's selected reply voice; best effort, so a missing voice
  /// degrades to the engine default instead of blocking read aloud.
  Future<void> _configureVoice() async {
    try {
      final prefs = await _prefs();
      final voiceName = prefs.getString('voice_name');
      final voiceLocale = prefs.getString('voice_locale');
      if (voiceName != null && voiceName.isNotEmpty) {
        if (voiceName == voiceLocale) {
          await _tts.setLanguage(voiceName);
        } else {
          await _tts.setVoice({'name': voiceName, 'locale': voiceLocale ?? ''});
        }
      }
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // Keep the engine default voice.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _readingKey = null;
    final speaker = _speaker;
    final stopping = speaker != null ? speaker.stop() : _tts.stop();
    unawaited(stopping.catchError((Object _) {}));
    super.dispose();
  }
}
