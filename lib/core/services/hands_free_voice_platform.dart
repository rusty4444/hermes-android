import 'dart:async';

import 'package:flutter/services.dart';

enum VoiceRecognitionPurpose { manual, handsFreeInitial, handsFreeFollowup }

enum VoicePlatformEventType {
  wakeArmed,
  wakeDetected,
  recognitionReady,
  speechStarted,
  speechResult,
  recognitionEnded,
  stopped,
  error,
}

const voiceErrorCodes = {
  'permissionDenied',
  'notForeground',
  'staleOwner',
  'audioBusy',
  'captureSilenced',
  'unsupportedAbi',
  'assetMissing',
  'assetHashMismatch',
  'engineLoadFailed',
  'recognizerUnavailable',
  'recognizerNetwork',
  'recognizerAudio',
  'recognizerBusy',
  'recognizerDeadline',
  'ttsUnavailable',
  'ttsCanceled',
  'ttsError',
  'ttsDeadline',
  'submissionRejected',
  'turnFailed',
  'turnUnknown',
  'turnNeedsInput',
};

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid voice protocol map');
  }
  return value.cast<String, Object?>();
}

T _field<T>(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! T) throw const FormatException('Invalid voice protocol field');
  return value;
}

String _id(Map<String, Object?> map, String key) {
  final value = _field<String>(map, key);
  if (value.isEmpty) throw const FormatException('Empty voice identity');
  return value;
}

class VoiceCapabilities {
  const VoiceCapabilities({
    required this.androidApi,
    required this.recordPermissionGranted,
    required this.sttAvailable,
    required this.onDeviceSttAvailable,
    required this.wakeAssetsPresent,
    required this.wakeSupportedAbi,
  });
  final int androidApi;
  final bool recordPermissionGranted;
  final bool sttAvailable;
  final bool? onDeviceSttAvailable;
  final bool wakeAssetsPresent;
  final bool wakeSupportedAbi;

  factory VoiceCapabilities.parse(Object? value) {
    final map = _map(value);
    final api = _field<int>(map, 'androidApi');
    if (api < 21 ||
        !map.containsKey('onDeviceSttAvailable') ||
        (api < 31
            ? (map['onDeviceSttAvailable'] != null &&
                  map['onDeviceSttAvailable'] is! bool)
            : map['onDeviceSttAvailable'] is! bool)) {
      throw const FormatException('Invalid voice capabilities');
    }
    return VoiceCapabilities(
      androidApi: api,
      recordPermissionGranted: _field<bool>(map, 'recordPermissionGranted'),
      sttAvailable: _field<bool>(map, 'sttAvailable'),
      onDeviceSttAvailable: map['onDeviceSttAvailable'] as bool?,
      wakeAssetsPresent: _field<bool>(map, 'wakeAssetsPresent'),
      wakeSupportedAbi: _field<bool>(map, 'wakeSupportedAbi'),
    );
  }
}

/// Only native onResults can set isFinal; ended proves recognizer destruction.
/// Invalid messages are stream errors, never coerced into final/ready signals.
class VoicePlatformEvent {
  const VoicePlatformEvent({
    required this.ownerId,
    required this.generation,
    required this.seq,
    required this.operationId,
    required this.type,
    this.purpose,
    this.transcript,
    this.isFinal,
    this.reason,
    this.hadNativeFinal,
    this.code,
  });
  final String ownerId;
  final int generation;
  final int seq;
  final String operationId;
  final VoicePlatformEventType type;
  final VoiceRecognitionPurpose? purpose;
  final String? transcript;
  final bool? isFinal;
  final String? reason;
  final bool? hadNativeFinal;
  final String? code;

  factory VoicePlatformEvent.parse(Object? value) {
    final map = _map(value);
    if (_field<int>(map, 'protocolVersion') != 1) {
      throw const FormatException('Unsupported voice protocol');
    }
    final owner = _id(map, 'ownerId');
    final operation = _id(map, 'operationId');
    final generation = _field<int>(map, 'generation');
    final seq = _field<int>(map, 'seq');
    if (generation < 1 || seq < 1) {
      throw const FormatException('Invalid voice sequence');
    }
    final typeName = _field<String>(map, 'type');
    final type = VoicePlatformEventType.values
        .where((v) => v.name == typeName)
        .firstOrNull;
    if (type == null) throw const FormatException('Unknown voice event');
    VoiceRecognitionPurpose? purpose;
    String? transcript, reason, code;
    bool? isFinal, hadNativeFinal;
    switch (type) {
      case VoicePlatformEventType.wakeArmed:
      case VoicePlatformEventType.wakeDetected:
        if (_field<String>(map, 'keywordId') != 'hey_hermes' ||
            (type == VoicePlatformEventType.wakeDetected &&
                _field<String>(map, 'keyword') != 'Hey_Hermes')) {
          throw const FormatException('Unknown wake keyword');
        }
      case VoicePlatformEventType.recognitionReady:
        final name = _field<String>(map, 'purpose');
        purpose = VoiceRecognitionPurpose.values
            .where((v) => v.name == name)
            .firstOrNull;
        if (purpose == null) {
          throw const FormatException('Invalid speech purpose');
        }
      case VoicePlatformEventType.speechResult:
        transcript = _field<String>(map, 'transcript');
        isFinal = _field<bool>(map, 'isFinal');
      case VoicePlatformEventType.recognitionEnded:
        reason = _field<String>(map, 'reason');
        hadNativeFinal = _field<bool>(map, 'hadNativeFinal');
        if (!const {
              'final',
              'empty',
              'noSpeech',
              'error',
              'canceled',
              'deadline',
            }.contains(reason) ||
            (reason == 'final' && !hadNativeFinal)) {
          throw const FormatException('Invalid speech terminal');
        }
      case VoicePlatformEventType.stopped:
        reason = _id(map, 'reason');
      case VoicePlatformEventType.error:
        code = _field<String>(map, 'code');
        _field<String>(map, 'message'); // Never log/display provider payloads.
        if (!voiceErrorCodes.contains(code) ||
            _field<bool>(map, 'fatal') != true) {
          throw const FormatException('Invalid voice error');
        }
      case VoicePlatformEventType.speechStarted:
        break;
    }
    return VoicePlatformEvent(
      ownerId: owner,
      generation: generation,
      seq: seq,
      operationId: operation,
      type: type,
      purpose: purpose,
      transcript: transcript,
      isFinal: isFinal,
      reason: reason,
      hadNativeFinal: hadNativeFinal,
      code: code,
    );
  }
}

abstract interface class HandsFreeVoicePlatform {
  Stream<VoicePlatformEvent> get events;
  Future<VoiceCapabilities> capabilities();
  Future<bool> requestRecordPermission();
  Future<void> armWake({
    required String ownerId,
    required int generation,
    required String armId,
  });
  Future<void> recognizeOnce({
    required String ownerId,
    required int generation,
    required String requestId,
    required VoiceRecognitionPurpose purpose,
    required String? localeId,
    required int listenForMs,
    required int pauseForMs,
    required int? noSpeechTimeoutMs,
  });
  Future<void> finishRecognition({
    required String ownerId,
    required int generation,
    required String requestId,
  });
  Future<void> cancelRecognition({
    required String ownerId,
    required int generation,
    required String requestId,
  });
  Future<void> stop({
    required String ownerId,
    required int generation,
    required String reason,
  });
}

class MethodChannelHandsFreeVoicePlatform implements HandsFreeVoicePlatform {
  MethodChannelHandsFreeVoicePlatform({
    MethodChannel? methods,
    EventChannel? events,
  }) : _methods =
           methods ??
           const MethodChannel('com.hermesagent.hermes_android/voice'),
       _events =
           events ??
           const EventChannel('com.hermesagent.hermes_android/voice/events');
  static final shared = MethodChannelHandsFreeVoicePlatform();
  final MethodChannel _methods;
  final EventChannel _events;
  Stream<VoicePlatformEvent>? _stream;
  @override
  Stream<VoicePlatformEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map(VoicePlatformEvent.parse)
      .asBroadcastStream();
  @override
  Future<VoiceCapabilities> capabilities() async => VoiceCapabilities.parse(
    await _methods.invokeMethod<Object?>('capabilities', <String, Object?>{}),
  );
  @override
  Future<bool> requestRecordPermission() async {
    final result = await _methods.invokeMethod<Object?>(
      'requestRecordPermission',
      <String, Object?>{},
    );
    if (result is! bool) {
      throw const FormatException('Invalid permission reply');
    }
    return result;
  }

  Future<void> _invoke(String method, Map<String, Object?> arguments) async {
    if (await _methods.invokeMethod<Object?>(method, arguments) != null) {
      throw const FormatException('Invalid voice acknowledgement');
    }
  }

  @override
  Future<void> armWake({
    required String ownerId,
    required int generation,
    required String armId,
  }) => _invoke('armWake', {
    'ownerId': ownerId,
    'generation': generation,
    'armId': armId,
  });
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
  }) => _invoke('recognizeOnce', {
    'ownerId': ownerId,
    'generation': generation,
    'requestId': requestId,
    'purpose': purpose.name,
    'localeId': localeId,
    'listenForMs': listenForMs,
    'pauseForMs': pauseForMs,
    'noSpeechTimeoutMs': noSpeechTimeoutMs,
  });
  @override
  Future<void> finishRecognition({
    required String ownerId,
    required int generation,
    required String requestId,
  }) => _invoke('finishRecognition', {
    'ownerId': ownerId,
    'generation': generation,
    'requestId': requestId,
  });
  @override
  Future<void> cancelRecognition({
    required String ownerId,
    required int generation,
    required String requestId,
  }) => _invoke('cancelRecognition', {
    'ownerId': ownerId,
    'generation': generation,
    'requestId': requestId,
  });
  @override
  Future<void> stop({
    required String ownerId,
    required int generation,
    required String reason,
  }) => _invoke('stop', {
    'ownerId': ownerId,
    'generation': generation,
    'reason': reason,
  });
}
