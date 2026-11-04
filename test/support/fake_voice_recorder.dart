import 'dart:async';
import 'package:hermes_android/core/services/local_voice_recorder.dart';

class FakeRecorder implements VoiceRecorder {
  bool draft = false;
  bool live = false;
  bool closed = false;
  int deleted = 0;
  int continuations = 0;
  @override
  Future<Duration> get duration async => Duration.zero;
  @override
  Future<void> resumeRecording() async {
    continuations++;
    live = true;
  }

  void Function()? completion;
  Completer<bool>? permissionGate;
  @override
  Future<String> get path async => '/synthetic/voice.m4a';
  @override
  Future<String> prepareForSend() => path;
  @override
  Future<bool> hasPermission({bool request = false}) async =>
      permissionGate == null ? true : await permissionGate!.future;
  @override
  Future<bool> restore() async => draft;
  @override
  Future<void> start() async {
    live = true;
  }

  @override
  Future<void> stop() async {
    if (live) draft = true;
    live = false;
  }

  @override
  Future<void> play(void Function() onComplete) async {
    completion = onComplete;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> discard() async {
    live = draft = false;
    deleted++;
  }

  @override
  Future<void> close() async {
    await stop();
    closed = true;
  }
}
