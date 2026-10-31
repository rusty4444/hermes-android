import 'dart:async';

import 'package:hermes_android/core/controllers/hands_free_conversation_controller.dart';
import 'package:hermes_android/core/services/hands_free_voice_platform.dart';
import 'package:hermes_android/core/services/hands_free_speech.dart';

class FakeHandsFreeVoicePlatform implements HandsFreeVoicePlatform {
  final stream = StreamController<VoicePlatformEvent>.broadcast(sync: true);
  final calls = <({String method, Map<String, Object?> args})>[];
  final holds = <String, Completer<void>>{};
  bool permission = true;
  bool sttAvailable = true;
  bool assets = true;
  bool supported = true;
  String? owner;
  int generation = 0;
  int seq = 0;
  String? operation;
  VoiceRecognitionPurpose? purpose;
  String audio = 'none';
  final revoked = <String>{};
  int count(String method) =>
      calls.where((call) => call.method == method).length;
  Future<void> _call(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    calls.add((method: method, args: args));
    await holds[method]?.future;
  }

  @override
  Stream<VoicePlatformEvent> get events => stream.stream;
  @override
  Future<VoiceCapabilities> capabilities() async {
    await _call('capabilities');
    return VoiceCapabilities(
      androidApi: 36,
      recordPermissionGranted: permission,
      sttAvailable: sttAvailable,
      onDeviceSttAvailable: true,
      wakeAssetsPresent: assets,
      wakeSupportedAbi: supported,
    );
  }

  @override
  Future<bool> requestRecordPermission() async {
    await _call('permission');
    permission = true;
    return true;
  }

  bool _revoked(String ownerId, int generation) =>
      revoked.contains('$ownerId:$generation');
  void _own(String ownerId, int nextGeneration, String id) {
    if (owner != ownerId || generation != nextGeneration) seq = 0;
    owner = ownerId;
    generation = nextGeneration;
    operation = id;
  }

  @override
  Future<void> armWake({
    required String ownerId,
    required int generation,
    required String armId,
  }) async {
    _own(ownerId, generation, armId);
    await _call('armWake', {
      'ownerId': ownerId,
      'generation': generation,
      'armId': armId,
    });
    if (!_revoked(ownerId, generation)) audio = 'wake';
  }

  @override
  Future<void> recognizeOnce({
    required String ownerId,
    required int generation,
    required String requestId,
    required VoiceRecognitionPurpose purpose,
    required String? localeId,
    required int listenForMs,
    required int pauseForMs,
    required int? noSpeechTimeoutMs,
  }) async {
    _own(ownerId, generation, requestId);
    this.purpose = purpose;
    await _call('recognizeOnce', {
      'ownerId': ownerId,
      'generation': generation,
      'requestId': requestId,
      'purpose': purpose.name,
      'localeId': localeId,
      'listenForMs': listenForMs,
      'pauseForMs': pauseForMs,
      'noSpeechTimeoutMs': noSpeechTimeoutMs,
    });
    if (!_revoked(ownerId, generation)) audio = 'speech';
  }

  @override
  Future<void> finishRecognition({
    required String ownerId,
    required int generation,
    required String requestId,
  }) async {
    await _call('finishRecognition', {
      'ownerId': ownerId,
      'generation': generation,
      'requestId': requestId,
    });
    audio = 'none';
  }

  @override
  Future<void> cancelRecognition({
    required String ownerId,
    required int generation,
    required String requestId,
  }) async {
    await _call('cancelRecognition', {
      'ownerId': ownerId,
      'generation': generation,
      'requestId': requestId,
    });
    audio = 'none';
  }

  @override
  Future<void> stop({
    required String ownerId,
    required int generation,
    required String reason,
  }) async {
    revoked.add('$ownerId:$generation');
    await _call('stop', {
      'ownerId': ownerId,
      'generation': generation,
      'reason': reason,
    });
    if (owner == ownerId && this.generation == generation) audio = 'none';
  }

  Map<String, Object?> event(
    String type, [
    Map<String, Object?> payload = const {},
  ]) => {
    'protocolVersion': 1,
    'ownerId': owner,
    'generation': generation,
    'seq': ++seq,
    'operationId': operation,
    'type': type,
    ...payload,
  };
  void emit(String type, [Map<String, Object?> payload = const {}]) {
    if (type == 'wakeDetected' ||
        type == 'recognitionEnded' ||
        type == 'error') {
      audio = 'none';
    }
    stream.add(VoicePlatformEvent.parse(event(type, payload)));
  }

  void armed() => emit('wakeArmed', {'keywordId': 'hey_hermes'});
  void wake() => emit('wakeDetected', {
    'keywordId': 'hey_hermes',
    'keyword': 'Hey_Hermes',
  });
  void ready() => emit('recognitionReady', {'purpose': purpose!.name});
  void finalAndEnd([String text = 'voice prompt']) {
    emit('speechResult', {'transcript': text, 'isFinal': true});
    emit('recognitionEnded', {
      'reason': text.isEmpty ? 'empty' : 'final',
      'hadNativeFinal': true,
    });
  }
}

class FakeVoiceReplySpeaker implements VoiceReplySpeaker {
  final texts = <String>[];
  Completer<HandsFreeSpeechOutcome>? held;
  bool playing = false;
  @override
  Future<bool> prepare() async => true;
  int stops = 0;
  @override
  Future<HandsFreeSpeechOutcome> speak(
    String text, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return HandsFreeSpeechOutcome.canceled;
    texts.add(text);
    playing = true;
    try {
      return await (held?.future ??
          Future.value(HandsFreeSpeechOutcome.completed));
    } finally {
      playing = false;
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    playing = false;
    if (held != null && !held!.isCompleted) {
      held!.complete(HandsFreeSpeechOutcome.canceled);
    }
  }
}
