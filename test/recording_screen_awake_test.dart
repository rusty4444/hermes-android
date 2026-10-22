import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/voice_recording_controller.dart';
import 'package:hermes_android/core/services/recording_screen_awake.dart';

import 'support/fake_voice_recorder.dart';

class _DeniedRecorder extends FakeRecorder {
  @override
  Future<bool> hasPermission({bool request = false}) async => false;
}

class _FailedStartRecorder extends FakeRecorder {
  @override
  Future<void> start() async => throw StateError('synthetic start failure');
}

class _FailedStopRecorder extends FakeRecorder {
  @override
  Future<void> stop() async {
    await super.stop();
    throw StateError('synthetic stop failure');
  }
}

class _DelayedRecorder extends FakeRecorder {
  final started = Completer<void>();
  @override
  Future<void> start() async {
    await started.future;
    await super.start();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Set<String> owners;
  final controllers = <VoiceRecordingController>[];

  VoiceRecordingController controller([FakeRecorder? recorder]) {
    final value = VoiceRecordingController(recorder ?? FakeRecorder());
    controllers.add(value);
    return value;
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);
  List<bool> getStates() => [
    for (final call in calls) (call.arguments as Map)['enabled'] as bool,
  ];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    owners = {};
    messenger.setMockMethodCallHandler(RecordingScreenAwake.channel, (
      call,
    ) async {
      calls.add(call);
      final args = call.arguments as Map;
      final owner = args['owner'] as String;
      if (args['enabled'] == true) {
        owners.add(owner);
      } else {
        owners.remove(owner);
      }
      return null;
    });
  });

  tearDown(() async {
    for (final value in controllers) {
      value.dispose();
    }
    controllers.clear();
    await flush();
    messenger.setMockMethodCallHandler(RecordingScreenAwake.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'only active capture holds screen; pause, preview and send release it',
    () async {
      final voice = controller();
      await voice.ready;
      expect(calls, isEmpty);
      await voice.start();
      await flush();
      expect(getStates(), [true]);
      expect(owners, hasLength(1));
      await voice.stop();
      await voice.togglePlayback();
      await flush();
      expect(getStates(), [true, false]);
      expect(owners, isEmpty);
      await voice.resumeRecording();
      await flush();
      expect(getStates(), [true, false, true]);
      await voice.stop();
      await voice.send(submit: (_, accepted) async => accepted());
      await flush();
      expect(getStates(), [true, false, true, false]);
      expect(owners, isEmpty);
    },
  );

  test(
    'manual lock/background pauses capture, retains draft and releases screen',
    () async {
      final recorder = FakeRecorder();
      final voice = controller(recorder);
      await voice.start();
      await voice.background();
      await flush();
      expect(owners, isEmpty);
      expect(recorder.live, isFalse);
      expect(voice.hasDraft, isTrue);
      expect(recorder.deleted, 0);
      voice.foreground();
      await flush();
      expect(getStates(), [true, false]);
      await voice.resumeRecording();
      await voice.discard();
      await flush();
      expect(getStates(), [true, false, true, false]);
    },
  );

  test('denied permission and failed start never hold the screen', () async {
    await controller(_DeniedRecorder()).start();
    await controller(_FailedStartRecorder()).start();
    await flush();
    expect(calls, isEmpty);
  });

  test(
    'background during microphone start cannot acquire screen afterwards',
    () async {
      final recorder = _DelayedRecorder();
      final voice = controller(recorder);
      final starting = voice.start();
      await flush();
      await voice.background();
      recorder.started.complete();
      await starting;
      await flush();
      expect(voice.recording, isFalse);
      expect(recorder.live, isFalse);
      expect(calls, isEmpty);
    },
  );

  test(
    'failed stop releases screen and reports the recording failure',
    () async {
      final voice = controller(_FailedStopRecorder());
      await voice.start();
      await voice.stop();
      await flush();
      expect(voice.error, isNotNull);
      expect(getStates(), [true, false]);
      expect(owners, isEmpty);
    },
  );

  test('disposing an old chat cannot release another recorder owner', () async {
    final first = controller();
    final second = controller();
    await first.start();
    await second.start();
    await flush();
    expect(owners, hasLength(2));
    first.dispose();
    controllers.remove(first);
    await flush();
    expect(owners, hasLength(1));
    expect(second.recording, isTrue);
    await second.stop();
    await flush();
    expect(owners, isEmpty);
  });

  test(
    'a release is sent even while the native enable reply is pending',
    () async {
      final enableReply = Completer<void>();
      messenger.setMockMethodCallHandler(RecordingScreenAwake.channel, (
        call,
      ) async {
        calls.add(call);
        if ((call.arguments as Map)['enabled'] == true) {
          await enableReply.future;
        }
        return null;
      });
      final voice = controller();
      await voice.start();
      await voice.background();
      await flush();
      expect(getStates(), [true, false]);
      enableReply.complete();
      await flush();
      expect(getStates(), [true, false]);
    },
  );

  test(
    'platform failure cannot prevent capture finalization or retain a timer',
    () async {
      messenger.setMockMethodCallHandler(RecordingScreenAwake.channel, (
        _,
      ) async {
        throw PlatformException(code: 'activity_gone');
      });
      final recorder = FakeRecorder();
      final voice = controller(recorder);
      await voice.start();
      await voice.stop();
      await flush();
      expect(recorder.live, isFalse);
      expect(voice.recording, isFalse);
      expect(voice.hasDraft, isTrue);
    },
  );

  testWidgets('timer updates do not repeatedly acquire the screen', (
    tester,
  ) async {
    final voice = controller();
    await voice.start();
    await tester.pump(const Duration(seconds: 3));
    expect(voice.recording, isTrue);
    expect(getStates(), [true]);
    expect(owners, hasLength(1));
    await voice.background();
    await tester.pump();
    expect(getStates(), [true, false]);
    expect(owners, isEmpty);
    voice.dispose();
    controllers.remove(voice);
    debugDefaultTargetPlatformOverride = null;
  });

  test('non-Android hosts do not access the Android window channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final voice = controller();
    await voice.start();
    await voice.stop();
    await flush();
    expect(calls, isEmpty);
  });
}
