import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/local_voice_recorder.dart';

void main() {
  test(
    'a corrupt join journal cannot consume or delete a file outside its draft',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'voice-owned-journal-',
      );
      addTearDown(() => root.delete(recursive: true));
      final recorder = LocalVoiceRecorder(
        'owned-fixture',
        supportDirectory: () async => root,
      );
      final path = await recorder.path;
      await File(path).writeAsBytes([1, 2, 3]);
      await File('$path.continue.m4a').writeAsBytes([4, 5]);
      await Directory('$path.escape').create();
      final unrelated = File('${root.path}/unrelated.joined.m4a');
      await unrelated.writeAsBytes([9, 9, 9]);
      await File('$path.join.json').writeAsString(
        jsonEncode({
          'output': '$path.escape/../../unrelated.joined.m4a',
          'part': '$path.continue.m4a',
          'hash': sha256.convert([9, 9, 9]).toString(),
        }),
      );
      expect(await recorder.restore(), isTrue);
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      await expectLater(recorder.prepareForSend(), throwsStateError);
      expect(await unrelated.readAsBytes(), [9, 9, 9]);
      await recorder.discard();
      expect(await unrelated.readAsBytes(), [9, 9, 9]);
      await recorder.close();
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hermesagent.hermes_android/voice_draft');
  test('two finalized fragments join once and retain exact order', () async {
    final root = await Directory.systemTemp.createTemp('voice-join-fixture-');
    addTearDown(() => root.delete(recursive: true));
    final recorder = LocalVoiceRecorder(
      'synthetic-chat',
      supportDirectory: () async => root,
    );
    final path = await recorder.path;
    await File(path).writeAsBytes([1, 2, 3]);
    await File('$path.continue.m4a').writeAsBytes([4, 5]);
    var joins = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'duration') return 1000;
          joins++;
          final args = call.arguments as Map;
          final paths = args['paths'] as List;
          expect(paths, [path, '$path.continue.m4a']);
          final bytes = <int>[];
          for (final p in paths) {
            bytes.addAll(await File(p as String).readAsBytes());
          }
          await File(args['output'] as String).writeAsBytes(bytes);
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(await recorder.restore(), isTrue);
    expect(await File(path).readAsBytes(), [1, 2, 3, 4, 5]);
    expect(await recorder.restore(), isTrue);
    expect(joins, 1);
    expect(await File('$path.continue.m4a').exists(), isFalse);
    expect(await File('$path.join.json').exists(), isFalse);
  });
  test(
    'crash after atomic replace cannot append the same fragment twice',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'voice-commit-fixture-',
      );
      addTearDown(() => root.delete(recursive: true));
      final recorder = LocalVoiceRecorder(
        'synthetic-chat',
        supportDirectory: () async => root,
      );
      final path = await recorder.path;
      final combined = [1, 2, 3, 4, 5];
      await File(path).writeAsBytes(combined);
      await File('$path.continue.m4a').writeAsBytes([4, 5]);
      final output = '$path.synthetic.joined.m4a';
      await File('$path.join.json').writeAsString(
        jsonEncode({
          'output': output,
          'part': '$path.continue.m4a',
          'hash': sha256.convert(combined).toString(),
        }),
      );
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            throw PlatformException(code: 'no-join-needed');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(await recorder.restore(), isTrue);
      expect(await File(path).readAsBytes(), combined);
      expect(calls, 0);
      expect(await File('$path.continue.m4a').exists(), isFalse);
    },
  );
  test(
    'failed join keeps both pieces and blocks sending only the old one',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'voice-failure-fixture-',
      );
      addTearDown(() => root.delete(recursive: true));
      final recorder = LocalVoiceRecorder(
        'synthetic-chat',
        supportDirectory: () async => root,
      );
      final path = await recorder.path;
      await File(path).writeAsBytes([1, 2, 3]);
      await File('$path.continue.m4a').writeAsBytes([4, 5]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'synthetic-failure');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(await recorder.restore(), isTrue);
      await expectLater(
        recorder.prepareForSend(),
        throwsA(isA<PlatformException>()),
      );
      expect(await File(path).readAsBytes(), [1, 2, 3]);
      expect(await File('$path.continue.m4a').readAsBytes(), [4, 5]);
    },
  );
}
