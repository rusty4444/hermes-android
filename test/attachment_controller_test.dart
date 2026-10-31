import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_controller.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
// Exercise the installed path-provider and share plugin boundaries.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _SaveCall {
  final String? filename;
  final Uint8List? bytes;
  final FileType type;
  _SaveCall(this.filename, this.bytes, this.type);
}

class _Picker extends FilePicker {
  final calls = <_SaveCall>[];
  String? result = 'content://saved/result';
  Object? error;
  Completer<String?>? pending;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls.add(_SaveCall(fileName, bytes, type));
    if (error case final error?) throw error;
    if (pending != null) return pending!.future;
    return result;
  }
}

class _Files implements RemoteFilesDataSource {
  final pending = Completer<RemoteFileDownload>();
  final paths = <String>[];
  @override
  Future<RemoteFileDownload> download(String path) {
    paths.add(path);
    return pending.future;
  }

  @override
  Future<RemoteDirectory> defaultDirectory() => throw UnimplementedError();
  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) =>
      throw UnimplementedError();
  @override
  Future<RemoteTextPreview> readText(String path) => throw UnimplementedError();
}

class _OwnedClient extends RemoteFilesClient {
  _OwnedClient()
    : super(dashboard: DashboardClient(host: 'unused.test', proxied: true));
  final pending = Completer<RemoteFileDownload>();
  var closes = 0;
  var downloads = 0;
  @override
  Future<RemoteFileDownload> download(String path) {
    downloads++;
    return pending.future;
  }

  @override
  void close() {
    closes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  setUp(() {
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() {
    FilePicker.platform = FilePickerIO();
  });

  test(
    'Download and default native Share are distinct actions with exact bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'attachment-share-test-',
      );
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final shares = <MethodCall>[];
      final sharedBytes = <List<int>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            shares.add(call);
            final paths = (call.arguments as Map)['paths'] as List;
            sharedBytes.add(await File(paths.single as String).readAsBytes());
            return 'selected.share.target';
          });
      addTearDown(() async {
        PathProviderPlatform.instance = originalPaths;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      final files = _Files();
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/gateway/generated.png'),
        filesClient: () => files,
      );
      addTearDown(controller.dispose);
      files.pending.complete(
        RemoteFileDownload(filename: 'ignored', bytes: [1, 2, 3]),
      );

      await controller.save(dialogTitle: 'Download');
      expect(picker.calls.single.filename, 'generated.png');
      expect(picker.calls.single.bytes, [1, 2, 3]);
      expect(
        shares,
        isEmpty,
        reason: 'Download must not open the share sheet.',
      );

      await controller.share();
      expect(shares.single.method, 'share');
      expect((shares.single.arguments as Map)['subject'], 'generated.png');
      expect((shares.single.arguments as Map)['mimeTypes'], ['image/png']);
      expect(sharedBytes.single, [1, 2, 3]);
      expect(
        picker.calls,
        hasLength(1),
        reason: 'Share must not open the save picker.',
      );
      expect(files.paths, ['/gateway/generated.png']);
      expect(
        await directory.list().toList(),
        isEmpty,
        reason: 'Share staging files must be cleaned.',
      );
    },
  );

  test(
    'native Share infers image and audio MIME for unmapped formats',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'share-mime-test-',
      );
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths(directory.path);
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final calls = <MethodCall>[];
      final bytes = <List<int>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            final paths = (call.arguments as Map)['paths'] as List;
            bytes.add(await File(paths.single as String).readAsBytes());
            return 'selected.share.target';
          });
      addTearDown(() async {
        PathProviderPlatform.instance = originalPaths;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      // These are the installed mime package's actual filename-inference values.
      for (final entry in {
        'avif': 'image/avif',
        'heic': 'image/heic',
        'flac': 'audio/x-flac',
      }.entries) {
        final files = _Files();
        final controller = AttachmentController(
          ref: MediaTagRef(path: '/gateway/generated.${entry.key}'),
          filesClient: () => files,
        );
        addTearDown(controller.dispose);
        files.pending.complete(
          RemoteFileDownload(filename: 'ignored', bytes: [4, 5, 6]),
        );
        await controller.share();
        expect((calls.last.arguments as Map)['mimeTypes'], [entry.value]);
        expect(bytes.last, [4, 5, 6]);
        expect(controller.feedback, isNull);
      }
      expect(calls, hasLength(3));
      expect(picker.calls, isEmpty);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'save passes exact immutable reference name, bytes and any type to picker',
    () async {
      final files = _Files();
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/gateway/日本語 report.csv'),
        filesClient: () => files,
      );
      final action = controller.save(dialogTitle: 'Save file');
      files.pending.complete(
        RemoteFileDownload(
          filename: 'server-must-not-rename.bin',
          bytes: [1, 2, 3],
        ),
      );
      await action;
      expect(files.paths, ['/gateway/日本語 report.csv']);
      expect(picker.calls.single.filename, '日本語 report.csv');
      expect(picker.calls.single.bytes, [1, 2, 3]);
      expect(identical(picker.calls.single.bytes, controller.bytes), isTrue);
      expect(picker.calls.single.type, FileType.any);
      expect(controller.feedback, AttachmentFeedback.saved);
      controller.dispose();
    },
  );

  test(
    'preview/save/share coalesce onto one fetch and reuse its bytes',
    () async {
      final files = _Files();
      Uint8List? shared;
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/gateway/report.txt'),
        filesClient: () => files,
        shareHandler:
            ({required bytes, required ref, required isCurrent}) async {
              expect(isCurrent(), isTrue);
              shared = bytes;
            },
      );
      final preview = controller.ensureBytes();
      expect(identical(preview, controller.ensureBytes()), isTrue);
      final save = controller.save(dialogTitle: 'Save');
      files.pending.complete(
        RemoteFileDownload(filename: 'report.txt', bytes: [65]),
      );
      await Future.wait([preview, save]);
      await controller.share();
      expect(files.paths, ['/gateway/report.txt']);
      expect(identical(shared, controller.bytes), isTrue);
      expect(identical(picker.calls.single.bytes, controller.bytes), isTrue);
      controller.dispose();
    },
  );

  test(
    'concurrent saves and share do not start duplicate native operations',
    () async {
      final files = _Files();
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/a.txt'),
        filesClient: () => files,
      );
      picker.pending = Completer<String?>();
      final first = controller.save(dialogTitle: 'Save');
      await controller.save(dialogTitle: 'Save again');
      await controller.share();
      expect(files.paths.length, 1);
      files.pending.complete(
        RemoteFileDownload(filename: 'a.txt', bytes: [65]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(picker.calls.length, 1);
      expect(controller.acting, isTrue);
      picker.pending!.complete('content://saved/a');
      await first;
      expect(controller.acting, isFalse);
      controller.dispose();
    },
  );

  test(
    'cancel is not success and a failed save remains retryable without refetch',
    () async {
      final files = _Files();
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/a.txt'),
        filesClient: () => files,
      );
      files.pending.complete(
        RemoteFileDownload(filename: 'a.txt', bytes: [65]),
      );
      picker.result = null;
      await controller.save(dialogTitle: 'Save');
      expect(controller.feedback, AttachmentFeedback.saveCancelled);
      picker.error = StateError('picker failed');
      await controller.save(dialogTitle: 'Save');
      expect(controller.feedback, AttachmentFeedback.saveFailed);
      picker.error = null;
      picker.result = 'content://saved/a';
      await controller.save(dialogTitle: 'Save');
      expect(controller.feedback, AttachmentFeedback.saved);
      expect(files.paths.length, 1);
      controller.dispose();
    },
  );

  test(
    'disposing during fetch completes waiters, closes once and never opens picker',
    () async {
      final client = _OwnedClient();
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/old.txt'),
        filesClient: () => client,
      );
      final save = controller.save(dialogTitle: 'Save old');
      controller.dispose();
      await save;
      expect(client.closes, 1);
      client.pending.complete(
        RemoteFileDownload(filename: 'old.txt', bytes: [1]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.closes, 1);
      expect(picker.calls, isEmpty);
    },
  );

  test('successful owned downloads close once, not again on dispose', () async {
    final client = _OwnedClient();
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/a.txt'),
      filesClient: () => client,
    );
    final download = controller.ensureBytes();
    client.pending.complete(RemoteFileDownload(filename: 'a.txt', bytes: [1]));
    expect(await download, [1]);
    expect(client.closes, 1);
    controller.dispose();
    expect(client.closes, 1);
  });

  test('failed owned downloads close once and expose no bytes', () async {
    final client = _OwnedClient();
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/a.txt'),
      filesClient: () => client,
    );
    final download = controller.ensureBytes();
    client.pending.completeError(StateError('server failed'));
    expect(await download, isNull);
    expect(controller.feedback, AttachmentFeedback.downloadFailed);
    expect(client.closes, 1);
    controller.dispose();
    expect(client.closes, 1);
  });

  test('custom source cannot bypass the attachment byte cap', () async {
    final files = _Files();
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/large.bin'),
      filesClient: () => files,
    );
    final save = controller.save(dialogTitle: 'Save');
    files.pending.complete(
      RemoteFileDownload(
        filename: 'large.bin',
        bytes: Uint8List(maxAttachmentDownloadBytes + 1),
      ),
    );
    await save;
    expect(controller.bytes, isNull);
    expect(controller.feedback, AttachmentFeedback.downloadedTooLarge);
    expect(picker.calls, isEmpty);
    controller.dispose();
  });

  test('late picker result is fenced after disposal', () async {
    final files = _Files();
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/old.txt'),
      filesClient: () => files,
    );
    picker.pending = Completer<String?>();
    files.pending.complete(RemoteFileDownload(filename: 'old.txt', bytes: [1]));
    final save = controller.save(dialogTitle: 'Save old');
    await Future<void>.delayed(Duration.zero);
    expect(picker.calls.single.filename, 'old.txt');
    controller.dispose();
    picker.pending!.complete('content://saved/old');
    await save;
    expect(controller.feedback, isNull);
  });

  test('share failure is visible and releases the action lock', () async {
    final files = _Files();
    final controller = AttachmentController(
      ref: const MediaTagRef(path: '/a.txt'),
      filesClient: () => files,
      shareHandler: ({required bytes, required ref, required isCurrent}) async {
        throw StateError('native share failed');
      },
    );
    files.pending.complete(RemoteFileDownload(filename: 'a.txt', bytes: [65]));
    await controller.share();
    expect(controller.feedback, AttachmentFeedback.shareFailed);
    expect(controller.acting, isFalse);
    await controller.save(dialogTitle: 'Save');
    expect(controller.feedback, AttachmentFeedback.saved);
    expect(files.paths.length, 1);
    controller.dispose();
  });

  test(
    'disposed action owner cannot save late bytes in a still-live card scope',
    () async {
      final files = _Files();
      var ownerCurrent = true;
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/a.txt'),
        filesClient: () => files,
      );
      final action = controller.save(
        dialogTitle: 'Save',
        isOwnerCurrent: () => ownerCurrent,
      );
      ownerCurrent = false;
      files.pending.complete(
        RemoteFileDownload(filename: 'a.txt', bytes: [65]),
      );
      await action;
      expect(controller.active, isTrue);
      expect(controller.acting, isFalse);
      expect(picker.calls, isEmpty);
      controller.dispose();
    },
  );

  test(
    'late picker success from a closed popup is not reported on the card',
    () async {
      final files = _Files();
      var ownerCurrent = true;
      final controller = AttachmentController(
        ref: const MediaTagRef(path: '/a.txt'),
        filesClient: () => files,
      );
      files.pending.complete(
        RemoteFileDownload(filename: 'a.txt', bytes: [65]),
      );
      picker.pending = Completer<String?>();
      final action = controller.save(
        dialogTitle: 'Save',
        isOwnerCurrent: () => ownerCurrent,
      );
      await Future<void>.delayed(Duration.zero);
      expect(picker.calls.length, 1);
      ownerCurrent = false;
      picker.pending!.complete('content://saved/a');
      await action;
      expect(controller.feedback, isNull);
      expect(controller.acting, isFalse);
      controller.dispose();
    },
  );

  test('share receives the original ref and a live ownership fence', () async {
    final files = _Files();
    final held = Completer<void>();
    bool Function()? fence;
    const ref = MediaTagRef(path: '/old.txt');
    final controller = AttachmentController(
      ref: ref,
      filesClient: () => files,
      shareHandler: ({required bytes, required ref, required isCurrent}) async {
        expect(ref.path, '/old.txt');
        fence = isCurrent;
        await held.future;
        expect(isCurrent(), isFalse);
      },
    );
    files.pending.complete(RemoteFileDownload(filename: 'old.txt', bytes: [1]));
    final share = controller.share();
    await Future<void>.delayed(Duration.zero);
    expect(fence!(), isTrue);
    controller.dispose();
    held.complete();
    await share;
    expect(controller.feedback, isNull);
  });
}
