import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_video_file_ownership.dart';
import 'package:hermes_android/core/services/attachment_video_service.dart';

const _child = 'test/support/video_directory_owner_process.dart';

Future<ProcessResult> _run(String mode, String path) =>
    Process.run('dart', [_child, mode, path]);

void main() {
  late Directory root;
  setUp(() async {
    final build = await Directory(
      'build/attachment-video-ownership-test',
    ).create(recursive: true);
    root = await build.createTemp('case-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('real live process lock defeats age and a different-process sweep; '
      'process death permits restart cleanup', () async {
    final child = await Process.start('dart', [_child, 'own', root.path]);
    addTearDown(() async {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    });
    final line = await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final record = jsonDecode(line) as Map;
    expect(record['pid'], isNot(pid));
    final directory = Directory(record['path'] as String);
    final source = File('${directory.path}/attachment.mp4');
    final marker = File('${directory.path}/.owner-v1');
    await marker.setLastModified(DateTime.utc(2000));
    await AttachmentVideoDirectoryOwner.sweep(root);
    expect(await source.readAsBytes(), [1, 2, 3]);
    final concurrent = await _run('sweep', root.path);
    expect(concurrent.exitCode, 0, reason: '${concurrent.stderr}');
    expect(await source.readAsBytes(), [1, 2, 3]);
    child.kill(ProcessSignal.sigkill);
    await child.exitCode;
    // The next real video stage in a different process must perform cleanup,
    // not merely expose an unused reaping helper.
    final staged = await AttachmentVideoFileStore(
      temporaryDirectoryProvider: () async => root,
    ).stage(Uint8List.fromList([4, 5]), 'mp4');
    expect(await directory.exists(), isFalse);
    expect(await staged.file.readAsBytes(), [4, 5]);
    await staged.close();
  });

  test(
    'same-process sweep never opens its markers or releases POSIX locks',
    () async {
      final owner = await AttachmentVideoDirectoryOwner.create(root);
      addTearDown(owner.close);
      final marker = '${owner.directory.path}/.owner-v1';
      expect((await _run('probe', marker)).stdout.toString().trim(), 'locked');
      await AttachmentVideoDirectoryOwner.sweep(root);
      expect(await owner.directory.exists(), isTrue);
      expect((await _run('probe', marker)).stdout.toString().trim(), 'locked');
      final closing = owner.close();
      expect(identical(closing, owner.close()), isTrue);
      await closing;
      expect(await owner.directory.exists(), isFalse);
    },
  );

  test('unknown, missing, corrupt and symlink ownership fail closed', () async {
    final outside = await root.parent.absolute.createTemp('outside-');
    addTearDown(() => outside.delete(recursive: true));
    final sentinel = File('${outside.path}/keep')..writeAsStringSync('safe');
    final oldPid = pid + 1000000;
    final legacy = Directory('${root.path}/hermes-video-legacy')..createSync();
    final missing = Directory('${root.path}/hermes-video-v1-$oldPid-missing')
      ..createSync();
    final corrupt = Directory('${root.path}/hermes-video-v1-$oldPid-corrupt')
      ..createSync();
    File('${corrupt.path}/.owner-v1').writeAsStringSync('unknown');
    final mismatch = Directory('${root.path}/hermes-video-v1-$oldPid-mismatch')
      ..createSync();
    File(
      '${mismatch.path}/.owner-v1',
    ).writeAsStringSync('hermes-video-v1:${oldPid + 1}\n');
    final linkedMarker = Directory(
      '${root.path}/hermes-video-v1-$oldPid-marker',
    )..createSync();
    Link('${linkedMarker.path}/.owner-v1').createSync(sentinel.path);
    final linkedDirectory = Link('${root.path}/hermes-video-v1-$oldPid-link')
      ..createSync(outside.path);
    final unrelated = Directory('${root.path}/keep')..createSync();
    await AttachmentVideoDirectoryOwner.sweep(root);
    for (final directory in [
      legacy,
      missing,
      corrupt,
      mismatch,
      linkedMarker,
      unrelated,
    ]) {
      expect(await directory.exists(), isTrue, reason: directory.path);
    }
    expect(await linkedDirectory.exists(), isTrue);
    expect(await sentinel.readAsString(), 'safe');
  });
}
