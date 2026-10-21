import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/voice_recording_controller.dart';
import 'support/fake_voice_recorder.dart';

void main() {
  test(
    'late acceptance cannot delete a draft after submission returns uncertain',
    () async {
      final recorder = FakeRecorder()..draft = true;
      final controller = VoiceRecordingController(recorder);
      await controller.ready;
      late void Function() lateReceipt;
      await controller.send(
        submit: (_, accepted) async => lateReceipt = accepted,
      );
      lateReceipt();
      expect(recorder.deleted, 0);
      expect(recorder.draft, isTrue);
      controller.dispose();
    },
  );

  test(
    'a receipt after leaving the screen cannot delete a reopened draft',
    () async {
      final recorder = FakeRecorder()..draft = true;
      final controller = VoiceRecordingController(recorder);
      await controller.ready;
      final gate = Completer<void>();
      late void Function() lateReceipt;
      final sending = controller.send(
        submit: (_, accepted) async {
          lateReceipt = accepted;
          await gate.future;
        },
      );
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      lateReceipt();
      gate.complete();
      await sending;
      expect(recorder.deleted, 0);
      expect(recorder.draft, isTrue);
    },
  );

  test(
    'background stops capture, preview finishes, failure retains draft, acceptance deletes once',
    () async {
      final recorder = FakeRecorder();
      final controller = VoiceRecordingController(recorder);
      await controller.start();
      expect(controller.recording, isTrue);
      await controller.background();
      expect(recorder.live, isFalse);
      expect(controller.hasDraft, isTrue);
      await controller.togglePlayback();
      expect(controller.playing, isTrue);
      recorder.completion!();
      expect(controller.playing, isFalse);
      await controller.send(
        submit: (_, _) async => throw StateError('Offline'),
      );
      expect(controller.hasDraft, isTrue);
      expect(recorder.deleted, 0);
      var submissions = 0;
      await controller.send(
        submit: (path, accepted) async {
          expect(path, '/synthetic/voice.m4a');
          submissions++;
        },
      );
      expect(controller.hasDraft, isTrue);
      await controller.send(
        submit: (path, accepted) async {
          submissions++;
          accepted();
          accepted();
        },
      );
      expect(submissions, 2);
      expect(recorder.deleted, 1);
      expect(controller.hasDraft, isFalse);
      controller.dispose();
    },
  );

  test(
    'stopped draft can resume after preview without deleting old audio',
    () async {
      final recorder = FakeRecorder();
      final controller = VoiceRecordingController(recorder);
      await controller.start();
      await controller.stop();
      expect(controller.hasDraft, isTrue);
      await controller.togglePlayback();
      await controller.resumeRecording();
      expect(controller.recording, isTrue);
      expect(controller.playing, isFalse);
      expect(recorder.continuations, 1);
      expect(recorder.deleted, 0);
      await controller.stop();
      expect(controller.hasDraft, isTrue);
      await controller.send(submit: (path, accepted) async => accepted());
      expect(recorder.deleted, 1);
      expect(controller.hasDraft, isFalse);
      controller.dispose();
    },
  );

  test(
    'backgrounding during the permission prompt cannot start the microphone',
    () async {
      final recorder = FakeRecorder()..permissionGate = Completer<bool>();
      final controller = VoiceRecordingController(recorder);
      final starting = controller.start();
      await Future<void>.delayed(Duration.zero);
      await controller.background();
      recorder.permissionGate!.complete(true);
      await starting;
      expect(recorder.live, isFalse);
      expect(controller.recording, isFalse);
      controller.dispose();
    },
  );

  test(
    'double tap cannot submit twice, dispose keeps an unaccepted draft',
    () async {
      final recorder = FakeRecorder()..draft = true;
      final controller = VoiceRecordingController(recorder);
      await controller.ready;
      final completion = Completer<void>();
      var submissions = 0;
      Future<void> submit(String _, void Function() accepted) async {
        submissions++;
        await completion.future;
      }

      final first = controller.send(submit: submit);
      await Future<void>.delayed(Duration.zero);
      await controller.send(submit: submit);
      expect(submissions, 1);
      controller.dispose();
      completion.complete();
      await first;
      expect(recorder.draft, isTrue);
    },
  );
}
