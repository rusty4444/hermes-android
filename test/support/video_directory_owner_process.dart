import 'dart:convert';
import 'dart:io';

import 'package:hermes_android/core/services/attachment_video_file_ownership.dart';

Future<void> main(List<String> args) async {
  if (args.first == 'own') {
    final owner = await AttachmentVideoDirectoryOwner.create(
      Directory(args[1]),
    );
    await File(
      '${owner.directory.path}/attachment.mp4',
    ).writeAsBytes([1, 2, 3]);
    stdout.writeln(jsonEncode({'path': owner.directory.path, 'pid': pid}));
    // Retain the real process lock until the parent kills this process.
    await stdin.drain<void>();
  } else if (args.first == 'sweep') {
    await AttachmentVideoDirectoryOwner.sweep(Directory(args[1]));
    stdout.writeln('swept');
  } else if (args.first == 'probe') {
    final marker = await File(args[1]).open(mode: FileMode.append);
    try {
      await marker.lock(FileLock.exclusive);
      stdout.writeln('unlocked');
    } on FileSystemException {
      stdout.writeln('locked');
    } finally {
      await marker.close();
    }
  } else {
    throw ArgumentError('Unknown probe');
  }
}
