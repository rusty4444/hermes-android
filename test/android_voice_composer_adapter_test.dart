import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/voice_composer_controller.dart';
import 'package:hermes_android/core/services/android_voice_composer_adapter.dart';

import 'support/fake_hands_free_voice.dart';

void main() {
  testWidgets(
    'HF03 Android manual range replacement and Stop final remain draft-only',
    (tester) async {
      final native = FakeHandsFreeVoicePlatform();
      final adapter = AndroidVoiceComposerAdapter(
        platform: native,
        ownerId: 'manual',
      );
      final text = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'prefix suffix',
          selection: TextSelection(baseOffset: 7, extentOffset: 13),
        ),
      );
      final composer = VoiceComposerController(
        textController: text,
        adapter: adapter,
      );
      expect(await composer.start(localeId: 'en_AU'), isTrue);
      native.ready();
      native.emit('speechResult', {'transcript': 'partial', 'isFinal': false});
      expect(text.text, 'prefix partial');
      final stopGate = native.holds['finishRecognition'] = Completer();
      final stop = composer.stop();
      await tester.pump();
      native.emit('speechResult', {
        'transcript': 'genuine final',
        'isFinal': true,
      });
      native.emit('recognitionEnded', {
        'reason': 'final',
        'hadNativeFinal': true,
      });
      stopGate.complete();
      await stop;
      expect(text.text, 'prefix genuine final');
      expect(composer.listening, isFalse);
      expect(
        native.calls
            .where((call) => call.method == 'recognizeOnce')
            .single
            .args,
        containsPair('purpose', 'manual'),
      );
      expect(native.count('armWake'), 0);
      composer.dispose();
      text.dispose();
      await tester.pump();
      await native.stream.close();
    },
  );
  testWidgets(
    'HF03 Cancel exact snapshot rejects native late results and joins held start',
    (tester) async {
      final native = FakeHandsFreeVoicePlatform();
      final adapter = AndroidVoiceComposerAdapter(
        platform: native,
        ownerId: 'manual',
      );
      const snapshot = TextEditingValue(
        text: 'keep exact',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
      );
      final text = TextEditingController.fromValue(snapshot);
      final composer = VoiceComposerController(
        textController: text,
        adapter: adapter,
      );
      final startedGate = native.holds['recognizeOnce'] = Completer();
      final start = composer.start();
      await tester.pump();
      final cancel = composer.cancel();
      native.emit('speechResult', {'transcript': 'late', 'isFinal': true});
      startedGate.complete();
      await start;
      await cancel;
      await adapter.settle();
      expect(text.value, snapshot);
      expect(native.audio, 'none');
      expect(native.count('stop'), 1);
      expect(composer.listening, isFalse);
      composer.dispose();
      text.dispose();
      await tester.pump();
      await native.stream.close();
    },
  );
  testWidgets(
    'HF03 pending permission canceled before grant cannot start Android recognition',
    (tester) async {
      final native = FakeHandsFreeVoicePlatform()..permission = false;
      final permission = native.holds['permission'] = Completer();
      final adapter = AndroidVoiceComposerAdapter(
        platform: native,
        ownerId: 'manual',
      );
      final text = TextEditingController(text: 'manual');
      final composer = VoiceComposerController(
        textController: text,
        adapter: adapter,
      );
      final start = composer.start();
      await tester.pump();
      final cancel = composer.cancel();
      permission.complete();
      expect(await start, isFalse);
      await cancel;
      expect(native.count('recognizeOnce'), 0);
      expect(text.text, 'manual');
      composer.dispose();
      text.dispose();
      await tester.pump();
      await native.stream.close();
    },
  );
  testWidgets(
    'HF03 failed native release prevents another manual acquisition',
    (tester) async {
      final native = FakeHandsFreeVoicePlatform();
      final adapter = AndroidVoiceComposerAdapter(
        platform: native,
        ownerId: 'manual',
      );
      await adapter.initialize(onStatus: (_) {}, onError: (_) {});
      await adapter.listen(
        onResult: ({required transcript, required isFinal}) {},
      );
      final barrier = native.holds['stop'] = Completer();
      final canceled = adapter.cancel();
      barrier.completeError(StateError('stop unconfirmed'));
      await expectLater(canceled, throwsStateError);
      await expectLater(
        adapter.listen(onResult: ({required transcript, required isFinal}) {}),
        throwsStateError,
      );
      // Release the fixture for teardown; production remains admission-fenced.
      native.holds.remove('stop');
      adapter.dispose();
      await tester.pump();
      await native.stream.close();
    },
  );
}
