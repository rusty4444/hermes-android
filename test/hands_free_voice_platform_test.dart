import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/hands_free_voice_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('com.hermesagent.hermes_android/voice');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final caps = <String, Object?>{
    'androidApi': 36,
    'recordPermissionGranted': true,
    'sttAvailable': true,
    'onDeviceSttAvailable': true,
    'wakeAssetsPresent': true,
    'wakeSupportedAbi': true,
  };
  tearDown(() => messenger.setMockMethodCallHandler(methods, null));

  test(
    'exact frozen channels and nullable method maps, native acknowledgements',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return switch (call.method) {
          'capabilities' => caps,
          'requestRecordPermission' => true,
          _ => null,
        };
      });
      final platform = MethodChannelHandsFreeVoicePlatform();
      expect((await platform.capabilities()).wakeAssetsPresent, isTrue);
      expect(await platform.requestRecordPermission(), isTrue);
      await platform.armWake(ownerId: 'o', generation: 2, armId: 'a');
      await platform.recognizeOnce(
        ownerId: 'o',
        generation: 2,
        requestId: 'r',
        purpose: VoiceRecognitionPurpose.handsFreeFollowup,
        localeId: null,
        listenForMs: 30000,
        pauseForMs: 3000,
        noSpeechTimeoutMs: null,
      );
      await platform.finishRecognition(
        ownerId: 'o',
        generation: 2,
        requestId: 'r',
      );
      await platform.cancelRecognition(
        ownerId: 'o',
        generation: 2,
        requestId: 'r',
      );
      await platform.stop(ownerId: 'o', generation: 2, reason: 'user');
      expect(calls.map((call) => call.method), [
        'capabilities',
        'requestRecordPermission',
        'armWake',
        'recognizeOnce',
        'finishRecognition',
        'cancelRecognition',
        'stop',
      ]);
      expect(calls[3].arguments, {
        'ownerId': 'o',
        'generation': 2,
        'requestId': 'r',
        'purpose': 'handsFreeFollowup',
        'localeId': null,
        'listenForMs': 30000,
        'pauseForMs': 3000,
        'noSpeechTimeoutMs': null,
      });
    },
  );
  test(
    'method parsers reject malformed permission/capabilities/ack, never coerce',
    () async {
      messenger.setMockMethodCallHandler(methods, (_) async => 1);
      final platform = MethodChannelHandsFreeVoicePlatform();
      await expectLater(platform.capabilities(), throwsFormatException);
      await expectLater(
        platform.requestRecordPermission(),
        throwsFormatException,
      );
      await expectLater(
        platform.stop(ownerId: 'o', generation: 2, reason: 'user'),
        throwsFormatException,
      );
      for (final key in caps.keys) {
        final bad = {...caps}..remove(key);
        expect(
          () => VoiceCapabilities.parse(bad),
          throwsFormatException,
          reason: key,
        );
      }
    },
  );
  test(
    'every event payload is typed and unknown/malformed native finals fail closed',
    () {
      final base = <String, Object?>{
        'protocolVersion': 1,
        'ownerId': 'o',
        'generation': 1,
        'seq': 1,
        'operationId': 'r',
      };
      final events = <String, Map<String, Object?>>{
        'wakeArmed': {'keywordId': 'hey_hermes'},
        'wakeDetected': {'keywordId': 'hey_hermes', 'keyword': 'Hey_Hermes'},
        'recognitionReady': {'purpose': 'handsFreeInitial'},
        'speechStarted': {},
        'speechResult': {'transcript': 'words', 'isFinal': true},
        'recognitionEnded': {'reason': 'final', 'hadNativeFinal': true},
        'stopped': {'reason': 'user'},
        'error': {
          'code': 'recognizerAudio',
          'message': 'Unavailable',
          'fatal': true,
        },
      };
      for (final entry in events.entries) {
        final map = {...base, 'type': entry.key, ...entry.value};
        expect(VoicePlatformEvent.parse(map).type.name, entry.key);
        for (final key in [...base.keys, 'type', ...entry.value.keys]) {
          final bad = {...map}..remove(key);
          expect(
            () => VoicePlatformEvent.parse(bad),
            throwsFormatException,
            reason: '${entry.key}/$key',
          );
        }
      }
      for (final override in <Map<String, Object?>>[
        {'protocolVersion': 2},
        {'seq': '1'},
        {'seq': 0},
        {'generation': -1},
        {'ownerId': ''},
        {'isFinal': 'true'},
        {'type': 'unknown'},
      ]) {
        expect(
          () => VoicePlatformEvent.parse({
            ...base,
            'type': 'speechResult',
            'transcript': 'word',
            'isFinal': true,
            ...override,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => VoicePlatformEvent.parse({
          ...base,
          'type': 'recognitionEnded',
          'reason': 'final',
          'hadNativeFinal': false,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'actual EventChannel StandardMessageCodec stream parses valid and rejects invalid maps',
    () async {
      const eventName = 'com.hermesagent.hermes_android/voice/events';
      const control = MethodChannel(eventName);
      messenger.setMockMethodCallHandler(control, (_) async => null);
      final platform = MethodChannelHandsFreeVoicePlatform();
      final received = <VoicePlatformEvent>[];
      final errors = <Object>[];
      final subscription = platform.events.listen(
        received.add,
        onError: errors.add,
      );
      await Future<void>.value();
      Future<void> deliver(Object? event) async {
        final complete = Completer<void>();
        messenger.handlePlatformMessage(
          eventName,
          const StandardMethodCodec().encodeSuccessEnvelope(event),
          (_) => complete.complete(),
        );
        await complete.future;
      }

      await deliver({
        'protocolVersion': 1,
        'ownerId': 'o',
        'generation': 1,
        'seq': 1,
        'operationId': 'r',
        'type': 'speechResult',
        'transcript': 'draft',
        'isFinal': false,
      });
      await deliver({'type': 'speechResult', 'transcript': 'invalid'});
      await Future<void>.value();
      expect(received.single.isFinal, isFalse);
      expect(errors.single, isFormatException);
      await subscription.cancel();
      messenger.setMockMethodCallHandler(control, null);
    },
  );
}
