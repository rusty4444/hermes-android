import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// Platform boundary shared by recording, private draft storage and preview.
abstract class VoiceRecorder {
  Future<bool> hasPermission({bool request = false});
  Future<bool> restore();
  Future<void> start();
  Future<void> stop();
  Future<void> resumeRecording();
  Future<Duration> get duration;
  Future<String> prepareForSend();
  Future<void> play(void Function() onComplete);
  Future<void> pause();
  Future<void> discard();
  Future<String> get path;
  Future<void> close();
}

class LocalVoiceRecorder implements VoiceRecorder {
  final String identity;
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  StreamSubscription<void>? _completion;
  Future<String>? _path;
  bool _recording = false;
  String? _activePath;
  static const _media = MethodChannel(
    'com.hermesagent.hermes_android/voice_draft',
  );

  final Future<Directory> Function() _supportDirectory;
  LocalVoiceRecorder(
    this.identity, {
    Future<Directory> Function()? supportDirectory,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static final Map<String, Future<void>> _operations = {};
  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _operations[identity];
    final done = Completer<void>();
    _operations[identity] = done.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      done.complete();
      if (identical(_operations[identity], done.future)) {
        _operations.remove(identity);
      }
    }
  }

  @override
  Future<String> get path => _path ??= () async {
    final root = await _supportDirectory();
    final directory = Directory('${root.path}/voice_drafts');
    await directory.create(recursive: true);
    final name = sha256.convert(utf8.encode(identity));
    return '${directory.path}/$name.m4a';
  }();

  @override
  Future<bool> hasPermission({bool request = false}) =>
      (_recorder ??= AudioRecorder()).hasPermission(request: request);

  @override
  Future<bool> restore() => _serial(_restore);

  Future<bool> _restore() async {
    try {
      await _recoverContinuation();
    } catch (_) {
      final original = File(await path);
      if (await original.exists() && await original.length() > 0) return true;
      rethrow;
    }
    final file = File(await path);
    return await file.exists() && await file.length() > 0;
  }

  @override
  Future<void> start() => _serial(_start);

  Future<void> _start() async {
    if (_activePath == null && await restoreFileExists()) {
      throw StateError('A voice draft already exists.');
    }
    await (_recorder ??= AudioRecorder()).start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
      ),
      path: _activePath ??= await path,
    );
    _recording = true;
  }

  @override
  Future<void> stop() => _serial(_stop);

  Future<void> _stop() async {
    if (_recording) await _recorder?.stop();
    _recording = false;
    _activePath = null;
    await _recoverContinuation();
  }

  @override
  Future<Duration> get duration async {
    if (!await File(await path).exists()) return Duration.zero;
    try {
      return Duration(
        milliseconds:
            await _media.invokeMethod<int>('duration', {'path': await path}) ??
            0,
      );
    } on MissingPluginException {
      return Duration.zero;
    }
  }

  Future<String> _fileHash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  bool _ownsJoinedPath(String base, String output) =>
      output.startsWith('$base.') &&
      output.endsWith('.joined.m4a') &&
      File(output).parent.path == File(base).parent.path;

  Future<void> _recoverContinuation() async {
    if (_recording) return;
    final base = await path;
    final next = File('$base.continue.m4a');
    final journal = File('$base.join.json');
    if (await journal.exists()) {
      final entry = jsonDecode(await journal.readAsString()) as Map;
      final output = entry['output'] as String;
      if (!_ownsJoinedPath(base, output) ||
          await FileSystemEntity.isLink(output) ||
          entry['part'] != next.path) {
        throw StateError('Invalid voice draft journal; fragments retained.');
      }
      final joined = File(output);
      if (await joined.exists()) {
        if (await _fileHash(joined) != entry['hash']) {
          throw StateError('Voice draft join could not be verified.');
        }
        await joined.rename(base);
      }
      if (!await File(base).exists() ||
          await _fileHash(File(base)) != entry['hash']) {
        throw StateError('Voice draft join could not be verified.');
      }
      if (await next.exists()) await next.delete();
      await journal.delete();
      return;
    }
    if (!await next.exists()) return;
    final current = File(base);
    if (!await current.exists() || await current.length() == 0) {
      await next.rename(base);
      return;
    }
    final output = '$base.${const Uuid().v4()}.joined.m4a';
    try {
      final ok = await _media.invokeMethod<bool>('join', {
        'paths': [base, next.path],
        'output': output,
      });
      final joined = File(output);
      if (ok != true || !await joined.exists() || await joined.length() == 0) {
        throw StateError(
          'Voice fragments could not be joined; fragments retained.',
        );
      }
      final temporary = File('${journal.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'output': output,
          'part': next.path,
          'hash': await _fileHash(joined),
        }),
        flush: true,
      );
      await temporary.rename(journal.path);
      await _recoverContinuation();
    } finally {
      // A journalled output belongs to recovery, even after a crash/error.
      if (!await journal.exists()) {
        final temp = File(output);
        if (await temp.exists()) await temp.delete();
      }
    }
  }

  @override
  Future<void> resumeRecording() => _serial(_resumeRecording);

  Future<void> _resumeRecording() async {
    if (_recording) return;
    await _player?.stop();
    await _recoverContinuation();
    if (await duration >= const Duration(minutes: 10)) {
      throw StateError('Voice recording has reached its duration limit.');
    }
    _activePath = '${await path}.continue.m4a';
    await _start();
  }

  Future<bool> restoreFileExists() async =>
      await File(await path).exists() && await File(await path).length() > 0;
  @override
  Future<String> prepareForSend() => _serial(() async {
    await _stop();
    return await path;
  });

  @override
  Future<void> play(void Function() onComplete) async {
    _player ??= AudioPlayer();
    await _completion?.cancel();
    _completion = _player!.onPlayerComplete.listen((_) => onComplete());
    await _player!.play(DeviceFileSource(await prepareForSend()));
  }

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> discard() => _serial(_discard);

  Future<void> _discard() async {
    try {
      if (_recording) await _recorder?.stop();
      _recording = false;
      _activePath = null;
      await _player?.stop();
    } finally {
      final file = File(await path);
      if (await file.exists()) await file.delete();
      final journal = File('${await path}.join.json');
      if (await journal.exists()) {
        final data = jsonDecode(await journal.readAsString()) as Map;
        final output = data['output'];
        if (output is String && _ownsJoinedPath(await path, output)) {
          final joined = File(output);
          if (await joined.exists()) await joined.delete();
        }
        await journal.delete();
      }
      final next = File('${await path}.continue.m4a');
      if (await next.exists()) await next.delete();
    }
  }

  @override
  Future<void> close() => _serial(_close);

  Future<void> _close() async {
    // Leaving the chat retains its draft but never keeps the microphone open.
    try {
      await _stop();
    } finally {
      await _completion?.cancel();
      await _player?.dispose();
      await _recorder?.dispose();
    }
  }
}
