import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hermes_android/core/controllers/hands_free_conversation_controller.dart';
import 'package:hermes_android/core/services/hands_free_speech.dart';

import 'support/fake_hands_free_voice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  Completer<Object?>? gate;
  String? held;
  Object? speakResult;
  int? maximum;
  setUp(() {
    calls = [];
    gate = null;
    held = null;
    speakResult = 1;
    maximum = 12;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == held) return gate!.future;
      return switch (call.method) {
        'getMaxSpeechInputLength' => maximum,
        'speak' => speakResult,
        _ => 1,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  testWidgets('Q142 native-correlated B remains mic-off beyond echo guard', (
    tester,
  ) async {
    // Native FlutterTtsCorrelationTest proves this held reply cannot be settled
    // by A's queued/late callbacks. Here exercise the actual Dart consumer.
    final tts = FlutterTts();
    final speaker = FlutterVoiceReplySpeaker(tts);
    held = 'speak';
    gate = Completer();
    final oldSpeech = speaker.speak('A', isCurrent: () => true);
    await tester.pump();
    await speaker.stop();
    expect(await oldSpeech, HandsFreeSpeechOutcome.canceled);
    final oldResult = gate!;
    gate = Completer();
    maximum = 100;
    final native = FakeHandsFreeVoicePlatform();
    final turn = Completer<HandsFreeTurnOutcome>();
    final controller = HandsFreeConversationController(
      platform: native,
      ownerId: 'screen',
      isAuthorityCurrent: (_) => true,
      canStart: (_) => true,
      prepareAudio: speaker.prepare,
      submitHandsFreePrompt: (_) async =>
          HandsFreeSubmittedTurn(clientTurnId: 'B', settled: turn.future),
      speakHandsFreeReply: (reply) =>
          speaker.speak(reply.text, isCurrent: () => true),
      cancelSpeech: speaker.stop,
      localeId: () => 'en_AU',
    );
    final authority = HandsFreeAuthority(
      routeToken: Object(),
      connectionId: 'account',
      connectionMutationEpoch: Object(),
      sessionId: 'chat',
      foregroundEpoch: 1,
      controllerGeneration: 1,
    );
    expect(
      await controller.start(
        authority: authority,
        followupTimeout: const Duration(seconds: 10),
      ),
      isTrue,
    );
    native.armed();
    native.wake();
    await tester.pump();
    native.ready();
    native.finalAndEnd();
    await tester.pump();
    turn.complete(
      const HandsFreeTurnOutcome(
        clientTurnId: 'B',
        status: HandsFreeTurnStatus.completed,
        publicFinalText: 'B',
      ),
    );
    await tester.pump();
    expect(controller.state, HandsFreeState.speaking);
    oldResult.complete(0);
    await tts.platformCallHandler(const MethodCall('speak.onComplete', true));
    await tts.platformCallHandler(const MethodCall('speak.onCancel', true));
    await tts.platformCallHandler(
      const MethodCall('speak.onError', 'sanitized'),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(native.audio, 'none');
    expect(controller.state, HandsFreeState.speaking);
    expect(native.count('recognizeOnce'), 1);
    gate!.complete(1); // only B's genuine native terminal (native-tested).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(native.audio, 'none');
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.state, HandsFreeState.followup);
    expect(native.audio, 'speech');
    await controller.stop(reason: HandsFreeStopReason.user);
    controller.dispose();
    await native.stream.close();
  });
  String spoken(MethodCall call) => call.arguments is Map
      ? call.arguments['text'] as String
      : call.arguments as String;
  testWidgets(
    'HF06 real plugin awaits each chunk and configures completion/queue',
    (tester) async {
      held = 'speak';
      gate = Completer();
      final speaker = FlutterVoiceReplySpeaker(FlutterTts());
      const text = 'A long reply with emoji 🙂 and more words.';
      final speech = speaker.speak(text, isCurrent: () => true);
      await tester.pump();
      expect(calls[0].method, 'awaitSpeakCompletion');
      expect(calls[0].arguments, true);
      expect(calls[1].method, 'setQueueMode');
      expect(calls[1].arguments, 0);
      expect(calls.where((call) => call.method == 'speak'), hasLength(1));
      final first = gate!;
      held = null;
      first.complete(1);
      expect(await speech, HandsFreeSpeechOutcome.completed);
      final chunks = calls
          .where((call) => call.method == 'speak')
          .map(spoken)
          .toList();
      expect(chunks.join(), text);
      expect(chunks.every((text) => text.length <= 12), isTrue);
      expect(chunks.any((text) => text.contains('🙂')), isTrue);
      expect(calls.where((call) => call.method == 'stop'), isEmpty);
    },
  );
  for (final stage in [
    'awaitSpeakCompletion',
    'setQueueMode',
    'getMaxSpeechInputLength',
    'speak',
  ]) {
    testWidgets('HF06 Stop while $stage held never starts a later chunk', (
      tester,
    ) async {
      held = stage;
      gate = Completer();
      final speaker = FlutterVoiceReplySpeaker(FlutterTts());
      final speech = speaker.speak(
        'Long public reply to be canceled.',
        isCurrent: () => true,
      );
      await tester.pump();
      final stop = speaker.stop();
      await tester.pump();
      await stop;
      expect(await speech, HandsFreeSpeechOutcome.canceled);
      final count = calls.where((call) => call.method == 'speak').length;
      held = null;
      gate!.complete(stage == 'getMaxSpeechInputLength' ? 12 : 1);
      await tester.pump();
      expect(calls.where((call) => call.method == 'speak'), hasLength(count));
    });
  }
  testWidgets(
    'HF06 a missing native speak completion expires after five minutes',
    (tester) async {
      held = 'speak';
      gate = Completer();
      final speaker = FlutterVoiceReplySpeaker(FlutterTts());
      final speech = speaker.speak('Reply', isCurrent: () => true);
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));
      expect(await speech, HandsFreeSpeechOutcome.deadline);
      expect(calls.where((call) => call.method == 'stop'), isNotEmpty);
      gate!.complete(1);
      await tester.pump();
    },
  );
  for (final event in ['speak.onCancel', 'speak.onError']) {
    testWidgets('Q142 Android stale $event cannot cancel replacement B', (
      tester,
    ) async {
      held = 'speak';
      gate = Completer();
      final tts = FlutterTts();
      final speaker = FlutterVoiceReplySpeaker(tts);
      final first = speaker.speak('A', isCurrent: () => true);
      await tester.pump();
      await speaker.stop();
      expect(await first, HandsFreeSpeechOutcome.canceled);
      gate!.complete(0);
      gate = Completer();
      final second = speaker.speak('B', isCurrent: () => true);
      HandsFreeSpeechOutcome? settled;
      unawaited(
        second.then((value) {
          settled = value;
        }),
      );
      await tester.pump();
      try {
        // Native Stop replies before its legacy uncorrelated onCancel event.
        // onError also cannot supply an operation identity to this consumer.
        await tts.platformCallHandler(MethodCall(event, 'sanitized'));
        await tester.pump();
        expect(settled, isNull);
        gate!.complete(1);
        await tester.pump();
        expect(await second, HandsFreeSpeechOutcome.completed);
      } finally {
        if (!gate!.isCompleted) gate!.complete(0);
        await speaker.stop();
        await tester.pump();
      }
    });
  }
  for (final event in ['speak.onCancel', 'speak.onError']) {
    testWidgets('HF06 $event resolves held plugin Future without rearm', (
      tester,
    ) async {
      // The unchanged non-Android plugin still uses these legacy callbacks.
      held = 'speak';
      gate = Completer();
      final tts = FlutterTts();
      final previousPlatform = debugDefaultTargetPlatformOverride;
      late final FlutterVoiceReplySpeaker speaker;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        speaker = FlutterVoiceReplySpeaker(tts);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
      final speech = speaker.speak('Reply', isCurrent: () => true);
      await tester.pump();
      await tts.platformCallHandler(MethodCall(event, 'sanitized failure'));
      await tester.pump();
      expect(
        await speech,
        event == 'speak.onCancel'
            ? HandsFreeSpeechOutcome.canceled
            : HandsFreeSpeechOutcome.failed,
      );
      gate!.complete(1);
      await tester.pump();
    });
  }
  testWidgets(
    'HF06 non-1 and unavailable input length never count as completion',
    (tester) async {
      final speaker = FlutterVoiceReplySpeaker(FlutterTts());
      for (final result in [0, null, false]) {
        speakResult = result;
        expect(
          await speaker.speak('Reply', isCurrent: () => true),
          HandsFreeSpeechOutcome.failed,
        );
      }
      maximum = null;
      expect(
        await speaker.speak('Reply', isCurrent: () => true),
        HandsFreeSpeechOutcome.unavailable,
      );
    },
  );
  test(
    'HF06 UTF16 chunks retain exact text and never split a surrogate pair',
    () {
      const text = '🙂🙂 hello こんにちは 🙂 end';
      for (final length in [2, 3, 4, 7, 12]) {
        final chunks = splitSpeechInput(text, length);
        expect(chunks.join(), text);
        expect(chunks.every((chunk) => chunk.length <= length), isTrue);
        expect(
          chunks.every(
            (chunk) =>
                !(chunk.codeUnitAt(0) >= 0xdc00 &&
                    chunk.codeUnitAt(0) <= 0xdfff),
          ),
          isTrue,
        );
      }
    },
  );
}
