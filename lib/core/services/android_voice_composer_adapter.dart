import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'hands_free_voice_platform.dart';
import 'voice_composer_adapter.dart';

VoiceComposerAdapter createVoiceComposerAdapter({
  HandsFreeVoicePlatform? platform,
}) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android
    ? AndroidVoiceComposerAdapter(
        platform: platform ?? MethodChannelHandsFreeVoicePlatform.shared,
      )
    : SpeechToTextVoiceComposerAdapter();

/// Manual dictation uses the same native mutex/release barriers as wake/STT.
/// It intentionally has no submit callback or access to conversation turns.
class AndroidVoiceComposerAdapter implements VoiceComposerAdapter {
  AndroidVoiceComposerAdapter({required this.platform, String? ownerId})
    : ownerId = ownerId ?? 'manual-${const Uuid().v4()}';
  void _listenEvents() {
    _subscription ??= platform.events.listen(
      _event,
      onError: (Object _) {
        if (_requestId != null) {
          _onError?.call('Speech recognition is unavailable');
          unawaited(cancel().catchError((Object _) {}));
        }
      },
    );
  }

  final HandsFreeVoicePlatform platform;
  final String ownerId;
  StreamSubscription<VoicePlatformEvent>? _subscription;
  VoiceStatusCallback? _onStatus;
  VoiceErrorCallback? _onError;
  VoiceResultCallback? _onResult;
  int _intent = 0;
  int _generation = 0;
  int _seq = 0;
  String? _requestId;
  bool _disposed = false;
  bool _acceptResults = false;
  bool _releaseFailed = false;
  Future<void>? _pendingStart;
  Future<void>? _cleanup;

  @override
  Future<bool> get hasPermission async =>
      !_disposed && (await platform.capabilities()).recordPermissionGranted;
  @override
  Future<bool> initialize({
    required VoiceStatusCallback onStatus,
    required VoiceErrorCallback onError,
  }) async {
    final intent = _intent;
    if (_disposed || _releaseFailed) return false;
    _onStatus = onStatus;
    _onError = onError;
    var caps = await platform.capabilities();
    if (_disposed || intent != _intent) return false;
    if (!caps.recordPermissionGranted) {
      if (!await platform.requestRecordPermission()) return false;
      if (_disposed || intent != _intent) return false;
      caps = await platform.capabilities();
    }
    return !_disposed &&
        intent == _intent &&
        caps.recordPermissionGranted &&
        caps.sttAvailable;
  }

  @override
  Future<void> listen({
    required VoiceResultCallback onResult,
    String? localeId,
  }) {
    if (_disposed ||
        _releaseFailed ||
        _requestId != null ||
        _pendingStart != null) {
      return Future.error(StateError('Manual speech owner is not settled'));
    }
    _listenEvents();
    final intent = _intent;
    final generation = ++_generation;
    final request = 'manual-$generation';
    _requestId = request;
    _onResult = onResult;
    _acceptResults = true;
    _seq = 0;
    final flight = _listen(intent, generation, request, localeId);
    _pendingStart = flight;
    return flight.whenComplete(() {
      if (identical(_pendingStart, flight)) _pendingStart = null;
    });
  }

  Future<void> _listen(
    int intent,
    int generation,
    String request,
    String? locale,
  ) async {
    await _cleanup;
    if (_disposed || intent != _intent || _releaseFailed) return;
    await platform.recognizeOnce(
      ownerId: ownerId,
      generation: generation,
      requestId: request,
      purpose: VoiceRecognitionPurpose.manual,
      localeId: locale,
      listenForMs: 60000,
      pauseForMs: 3000,
      noSpeechTimeoutMs: null,
    );
  }

  void _event(VoicePlatformEvent event) {
    if (_disposed ||
        !_acceptResults ||
        event.ownerId != ownerId ||
        event.generation != _generation ||
        event.seq <= _seq ||
        (event.operationId != _requestId && event.operationId != 'session')) {
      return;
    }
    _seq = event.seq;
    switch (event.type) {
      case VoicePlatformEventType.recognitionReady:
        if (event.purpose == VoiceRecognitionPurpose.manual) {
          _onStatus?.call('listening');
        }
      case VoicePlatformEventType.speechResult:
        _onResult?.call(transcript: event.transcript!, isFinal: event.isFinal!);
      case VoicePlatformEventType.recognitionEnded:
        _acceptResults = false;
        _requestId = null;
        _onStatus?.call('done');
      case VoicePlatformEventType.stopped:
        _acceptResults = false;
        _requestId = null;
        _onStatus?.call('notListening');
      case VoicePlatformEventType.error:
        _acceptResults = false;
        _requestId = null;
        _onError?.call('Speech recognition is unavailable');
      default:
        break;
    }
  }

  @override
  Future<void> stop() async {
    final request = _requestId;
    final start = _pendingStart;
    final intent = _intent;
    await start;
    if (_disposed || intent != _intent) return;
    if (request != null) {
      // Native waits for onResults/onError plus destroy before acknowledging.
      await platform.finishRecognition(
        ownerId: ownerId,
        generation: _generation,
        requestId: request,
      );
    }
    _acceptResults = false;
    _requestId = null;
  }

  @override
  Future<void> cancel() {
    ++_intent;
    _acceptResults = false;
    _onResult = null;
    _requestId = null;
    final generation = _generation;
    final start = _pendingStart;
    final previous = _cleanup;
    final stop = generation == 0
        ? Future<void>.value()
        : platform.stop(
            ownerId: ownerId,
            generation: generation,
            reason: 'manualDictation',
          );
    return _cleanup = () async {
      try {
        await Future.wait([
          ?previous,
          stop,
          if (start != null) start.catchError((Object _) {}),
        ]);
      } catch (_) {
        _releaseFailed = true;
        rethrow;
      }
    }();
  }

  Future<void> settle() async {
    await _cleanup;
    await _pendingStart;
    if (_releaseFailed) {
      throw StateError('Manual speech release is unconfirmed');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(cancel().catchError((Object _) {}));
    unawaited(_subscription?.cancel());
  }
}
