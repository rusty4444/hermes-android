import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/hands_free_conversation_controller.dart';
import 'package:hermes_android/core/services/hands_free_voice_platform.dart';

import 'support/fake_hands_free_voice.dart';

class Rig {
  Rig() {
    controller = HandsFreeConversationController(
      platform: native,
      ownerId: 'screen',
      isAuthorityCurrent: (_) => current,
      canStart: (_) => admitted,
      prepareAudio: () async {
        await prepare?.future;
        return true;
      },
      submitHandsFreePrompt: (prompt) async {
        prompts.add(prompt);
        await admission?.future;
        return rejected
            ? null
            : HandsFreeSubmittedTurn(
                clientTurnId: 'turn',
                settled: turn.future,
              );
      },
      speakHandsFreeReply: (reply) async {
        expectSync(native.audio, 'none');
        replies.add(reply);
        return speaker.speak(reply.text, isCurrent: () => current);
      },
      cancelSpeech: speaker.stop,
      localeId: () => 'en_AU',
    );
  }
  final native = FakeHandsFreeVoicePlatform();
  final speaker = FakeVoiceReplySpeaker();
  final turn = Completer<HandsFreeTurnOutcome>();
  final prompts = <HandsFreePrompt>[];
  final replies = <HandsFreeReply>[];
  bool current = true;
  bool admitted = true;
  bool rejected = false;
  Completer<void>? admission;
  Completer<void>? prepare;
  late final HandsFreeConversationController controller;
  final authority = HandsFreeAuthority(
    routeToken: Object(),
    connectionId: 'account',
    connectionMutationEpoch: Object(),
    sessionId: 'chat',
    foregroundEpoch: 1,
    controllerGeneration: 1,
  );
  Future<bool> start([int seconds = 10]) => controller.start(
    authority: authority,
    followupTimeout: Duration(seconds: seconds),
  );
  Future<void> recording(WidgetTester tester) async {
    native.armed();
    native.wake();
    await tester.pump();
    native.ready();
    expect(controller.state, HandsFreeState.recording);
  }

  Future<void> waiting(WidgetTester tester) async {
    await recording(tester);
    native.finalAndEnd();
    await tester.pump();
    expect(controller.state, HandsFreeState.waiting);
    expect(prompts, hasLength(1));
    expect(native.audio, 'none');
  }

  void complete([
    HandsFreeTurnStatus status = HandsFreeTurnStatus.completed,
    String? text = 'public reply',
  ]) {
    turn.complete(
      HandsFreeTurnOutcome(
        clientTurnId: 'turn',
        status: status,
        publicFinalText: text,
      ),
    );
  }

  Future<void> close() async {
    await controller.stop(reason: HandsFreeStopReason.user);
    controller.dispose();
    await native.stream.close();
  }
}

void main() {
  testWidgets(
    'HF01 speechStarted extends followup only to bounded utterance final grace',
    (tester) async {
      final rig = Rig();
      await rig.start();
      await rig.waiting(tester);
      rig.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      rig.native.ready();
      await tester.pump(const Duration(seconds: 9));
      rig.native.emit('speechStarted');
      rig.native.emit('speechResult', {
        'transcript': 'partial only',
        'isFinal': false,
      });
      final finish = rig.native.holds['finishRecognition'] = Completer();
      await tester.pump(const Duration(seconds: 29));
      expect(rig.native.count('finishRecognition'), 0);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.native.count('finishRecognition'), 1);
      await tester.pump(const Duration(seconds: 2));
      expect(rig.controller.state, HandsFreeState.error);
      rig.native.finalAndEnd('too late');
      finish.complete();
      await rig.controller.settle();
      await tester.pump();
      expect(rig.prompts, hasLength(1));
      await rig.close();
    },
  );
  testWidgets(
    'HF02 genuine final inside finish grace still waits for native ended barrier',
    (tester) async {
      final rig = Rig();
      await rig.start();
      await rig.recording(tester);
      final finish = rig.native.holds['finishRecognition'] = Completer();
      await tester.pump(const Duration(seconds: 30));
      rig.native.emit('speechResult', {
        'transcript': 'native final',
        'isFinal': true,
      });
      expect(rig.prompts, isEmpty);
      rig.native.emit('recognitionEnded', {
        'reason': 'final',
        'hadNativeFinal': true,
      });
      finish.complete();
      await tester.pump();
      expect(rig.prompts, hasLength(1));
      await rig.close();
    },
  );
  testWidgets(
    'HF02 missing ready times out once without restart or partial promotion',
    (tester) async {
      final rig = Rig();
      await rig.start();
      rig.native.wake();
      await tester.pump();
      rig.native.emit('speechResult', {
        'transcript': 'partial',
        'isFinal': false,
      });
      await tester.pump(const Duration(seconds: 5));
      expect(rig.controller.state, HandsFreeState.error);
      expect(rig.prompts, isEmpty);
      expect(rig.native.count('recognizeOnce'), 1);
      await rig.close();
    },
  );
  testWidgets(
    'HF02 new explicit Start waits for prior native Stop acknowledgement',
    (tester) async {
      final rig = Rig();
      await rig.start();
      final stopped = rig.native.holds['stop'] = Completer();
      final stop = rig.controller.stop(reason: HandsFreeStopReason.user);
      final restart = rig.start();
      await tester.pump();
      expect(rig.native.count('armWake'), 1);
      stopped.complete();
      await stop;
      expect(await restart, isTrue);
      expect(rig.native.count('armWake'), 2);
      expect(
        rig.native.calls.last.args['generation'],
        rig.controller.generation,
      );
      await rig.close();
    },
  );
  testWidgets(
    'HF02 disposed held Start cannot emit or acquire after completion',
    (tester) async {
      final rig = Rig();
      final model = rig.native.holds['armWake'] = Completer();
      final started = rig.start();
      await tester.pump();
      rig.controller.dispose();
      model.complete();
      expect(await started, isFalse);
      await rig.controller.settle();
      expect(rig.controller.active, isFalse);
      expect(rig.native.audio, 'none');
      await rig.native.stream.close();
    },
  );
  for (final seconds in [0, 10, 30]) {
    testWidgets(
      'HF01 full wake/turn/playback/echo/followup, maximum $seconds',
      (tester) async {
        final rig = Rig();
        expect(rig.controller.state, HandsFreeState.idle);
        expect(rig.native.calls, isEmpty);
        expect(await rig.start(seconds), isTrue);
        expect(rig.native.audio, 'wake');
        await rig.waiting(tester);
        rig.speaker.held = Completer();
        rig.complete();
        await tester.pump();
        expect(rig.controller.state, HandsFreeState.speaking);
        expect(rig.native.audio, 'none');
        expect(rig.replies.single.text, 'public reply');
        rig.speaker.held!.complete(HandsFreeSpeechOutcome.completed);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 299));
        expect(rig.native.audio, 'none');
        await tester.pump(const Duration(milliseconds: 1));
        if (seconds == 0) {
          expect(rig.controller.state, HandsFreeState.listening);
          expect(rig.native.count('recognizeOnce'), 1);
        } else {
          expect(rig.controller.state, HandsFreeState.followup);
          rig.native.ready();
          await tester.pump(Duration(seconds: seconds));
          await tester.pump();
          expect(rig.controller.state, HandsFreeState.listening);
          expect(rig.native.count('cancelRecognition'), 1);
          expect(rig.native.count('recognizeOnce'), 2);
        }
        await rig.close();
      },
    );
  }
  testWidgets(
    'HF01 negative and over-maximum timeout rejected without capture',
    (tester) async {
      final rig = Rig();
      for (final seconds in [-1, 31]) {
        await expectLater(rig.start(seconds), throwsArgumentError);
      }
      expect(rig.native.calls, isEmpty);
      await rig.close();
    },
  );
  testWidgets(
    'HF02 partial never promoted; duplicates and old request finals cannot resend',
    (tester) async {
      final rig = Rig();
      await rig.start();
      await rig.recording(tester);
      final request = rig.native.operation;
      rig.native.emit('speechResult', {
        'transcript': 'partial',
        'isFinal': false,
      });
      expect(rig.controller.preview, 'partial');
      expect(rig.prompts, isEmpty);
      rig.native.emit('recognitionEnded', {
        'reason': 'deadline',
        'hadNativeFinal': false,
      });
      await tester.pump();
      expect(rig.prompts, isEmpty);
      final old = rig.native.event('speechResult', {
        'operationId': request,
        'transcript': 'late',
        'isFinal': true,
      });
      rig.native.stream.add(VoicePlatformEvent.parse(old));
      await tester.pump();
      expect(rig.prompts, isEmpty);
      await rig.waiting(tester);
      final duplicate = rig.native.event('recognitionEnded', {
        'reason': 'final',
        'hadNativeFinal': true,
      });
      rig.native.stream.add(VoicePlatformEvent.parse(duplicate));
      rig.native.stream.add(VoicePlatformEvent.parse(duplicate));
      await tester.pump();
      expect(rig.prompts, hasLength(1));
      await rig.close();
    },
  );
  testWidgets(
    'HF02 followup genuine final/ended without speechStarted is eligible',
    (tester) async {
      final rig = Rig();
      await rig.start();
      await rig.waiting(tester);
      rig.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      rig.native.ready();
      rig.native.finalAndEnd('followup');
      await tester.pump();
      expect(rig.prompts, hasLength(2));
      expect(rig.prompts.last.transcript, 'followup');
      await rig.close();
    },
  );
  for (final held in [
    'prepare',
    'capabilities',
    'permission',
    'armWake',
    'recognizeOnce',
    'finishRecognition',
    'cancelRecognition',
    'admission',
    'turn',
    'speech',
    'echo',
  ]) {
    testWidgets(
      'HF02 Stop joins/revokes held $held and late completion never restarts',
      (tester) async {
        final rig = Rig();
        final gate = Completer<void>();
        if (held == 'prepare') {
          rig.prepare = gate;
        } else if (held == 'permission') {
          rig.native.permission = false;
          rig.native.holds['permission'] = gate;
        } else if (['capabilities', 'armWake'].contains(held)) {
          rig.native.holds[held] = gate;
        }
        final start = rig.start();
        await tester.pump();
        if ([
          'prepare',
          'capabilities',
          'permission',
          'armWake',
        ].contains(held)) {
          rig.controller.revoke(HandsFreeStopReason.background);
          gate.complete();
          await start;
        } else {
          await start;
          if (['recognizeOnce', 'finishRecognition'].contains(held)) {
            rig.native.holds[held] = gate;
          }
          await rig.recording(tester);
          if (held == 'finishRecognition') {
            await tester.pump(const Duration(seconds: 30));
          }
          if (held == 'cancelRecognition') {
            rig.native.emit('recognitionEnded', {
              'reason': 'empty',
              'hadNativeFinal': false,
            });
            await tester.pump();
            await rig.recording(tester);
            rig.native.finalAndEnd();
            await tester.pump();
            rig.complete();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            rig.native.holds[held] = gate;
            rig.native.ready();
            await tester.pump(const Duration(seconds: 10));
          } else if (['admission', 'turn', 'speech', 'echo'].contains(held)) {
            if (held == 'admission') rig.admission = gate;
            rig.native.finalAndEnd();
            await tester.pump();
            if (held == 'speech') rig.speaker.held = Completer();
            if (held == 'speech' || held == 'echo') {
              rig.complete();
              await tester.pump();
            }
          }
          rig.controller.revoke(HandsFreeStopReason.routeChanged);
          if (!gate.isCompleted) gate.complete();
          if (!rig.turn.isCompleted) rig.complete();
        }
        await rig.controller.settle();
        final count = rig.native.count('armWake');
        await tester.pump(const Duration(minutes: 6));
        expect(rig.controller.state, HandsFreeState.idle);
        expect(rig.native.audio, 'none');
        expect(rig.native.count('armWake'), count);
        expect(rig.replies.length, lessThanOrEqualTo(1));
        await rig.close();
      },
    );
  }
  for (final status in [
    HandsFreeTurnStatus.failed,
    HandsFreeTurnStatus.interrupted,
    HandsFreeTurnStatus.unknown,
    HandsFreeTurnStatus.needsInput,
  ]) {
    testWidgets('HF04 $status is never spoken or retried', (tester) async {
      final rig = Rig();
      await rig.start();
      await rig.waiting(tester);
      rig.complete(status);
      await tester.pump();
      expect(rig.controller.state, HandsFreeState.error);
      expect(rig.replies, isEmpty);
      expect(rig.prompts, hasLength(1));
      expect(rig.native.audio, 'none');
      await rig.close();
    });
  }
  testWidgets('HF05 permission lifecycle loss never auto-starts on grant', (
    tester,
  ) async {
    final rig = Rig();
    rig.native.permission = false;
    final permission = rig.native.holds['permission'] = Completer();
    final started = rig.start();
    await tester.pump();
    rig.current = false;
    rig.controller.revoke(HandsFreeStopReason.background);
    rig.current = true;
    permission.complete();
    expect(await started, isFalse);
    await rig.controller.settle();
    expect(rig.native.count('armWake'), 0);
    expect(await rig.start(), isTrue);
    await rig.close();
  });
  testWidgets(
    'HF02 malformed platform stream, wrong generation and revoked authority fail closed',
    (tester) async {
      final rig = Rig();
      await rig.start();
      final stale = rig.native.event('wakeDetected', {
        'generation': 99,
        'keywordId': 'hey_hermes',
        'keyword': 'Hey_Hermes',
      });
      rig.native.stream.add(VoicePlatformEvent.parse(stale));
      expect(rig.native.count('recognizeOnce'), 0);
      rig.native.stream.addError(const FormatException('bad protocol'));
      await tester.pump();
      expect(rig.controller.state, HandsFreeState.error);
      await rig.close();
    },
  );
  testWidgets('HF06 canceled/unavailable/failed/deadline TTS never rearms', (
    tester,
  ) async {
    for (final outcome in HandsFreeSpeechOutcome.values.where(
      (v) => v != HandsFreeSpeechOutcome.completed,
    )) {
      final rig = Rig();
      await rig.start();
      await rig.waiting(tester);
      rig.speaker.held = Completer();
      rig.complete();
      await tester.pump();
      rig.speaker.held!.complete(outcome);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(rig.controller.state, HandsFreeState.error);
      expect(rig.native.count('armWake'), 1);
      await rig.close();
    }
  });
}
