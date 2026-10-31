import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_video_service.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _StagedFile implements AttachmentVideoFile {
  _StagedFile(this.number, this.log);
  final int number;
  final List<String> log;
  var closes = 0;

  @override
  File get file => File('/private/owned-video-$number/attachment.mp4');

  @override
  Future<void> close() async {
    closes++;
    log.add('file-close:$number');
  }
}

class _FileStore extends AttachmentVideoFileStore {
  _FileStore(this.log);
  final List<String> log;
  final staged = <_StagedFile>[];
  final payloads = <Uint8List>[];
  Completer<AttachmentVideoFile>? pending;

  @override
  Future<AttachmentVideoFile> stage(Uint8List bytes, String extension) async {
    payloads.add(Uint8List.fromList(bytes));
    if (pending != null) return pending!.future;
    final file = _StagedFile(staged.length + 1, log);
    staged.add(file);
    return file;
  }
}

class _Platform extends VideoPlayerPlatform {
  _Platform(this.log);
  final List<String> log;
  final sources = <DataSource>[];
  final streams = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  final disposed = <int>[];
  final created = Completer<void>();
  final listening = Completer<void>();
  Completer<void>? creationGate;
  Completer<void>? playGate;
  Completer<void>? seekGate;
  Completer<void>? disposeGate;
  Object? createError;
  var initializeAutomatically = true;
  var throwOnPause = false;
  var throwOnDispose = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    sources.add(options.dataSource);
    final id = sources.length;
    log.add('create:$id');
    if (!created.isCompleted) created.complete();
    await creationGate?.future;
    if (createError case final error?) throw error;
    streams[id] = StreamController<VideoEvent>();
    if (initializeAutomatically) {
      streams[id]!.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(640, 360),
        ),
      );
    }
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    if (!listening.isCompleted) listening.complete();
    return streams[playerId]!.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    log.add('dispose:$playerId');
    disposed.add(playerId);
    await disposeGate?.future;
    if (throwOnDispose) throw StateError('native dispose failed');
    await streams.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {
    log.add('play:$playerId');
    await playGate?.future;
  }

  @override
  Future<void> pause(int playerId) async {
    log.add('pause:$playerId');
    if (throwOnPause) throw StateError('native pause failed');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    log.add('seek:$playerId:${position.inMilliseconds}');
    await seekGate?.future;
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {
    log.add('volume:$playerId:$volume');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

Future<void> _drainMicrotasks() async {
  // Ordinary test() uses the real async zone, not widget fake async.
  for (var i = 0; i < 12; i++) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('video extensions are container candidates, not paths or playlists', () {
    for (final extension in [
      'mp4',
      'm4v',
      'mov',
      'webm',
      'mkv',
      'avi',
      '3gp',
      '3g2',
      'mpeg',
      'mpg',
      'm2ts',
      'ogv',
      'flv',
      'f4v',
      'MP4',
    ]) {
      expect(attachmentIsVideo(extension), isTrue, reason: extension);
    }
    for (final extension in [
      '',
      '.mp4',
      'movie.mp4',
      '../mp4',
      'mp4/../txt',
      'mp4\\txt',
      'mp4\u0000',
      'https://host/video.mp4',
      'm3u8',
      'mpd',
      'ts',
      'txt',
      'pdf',
      'wmv',
      'asf',
    ]) {
      expect(attachmentIsVideo(extension), isFalse, reason: extension);
    }
  });

  group('private staging with real I/O in ordinary tests', () {
    late Directory root;

    setUp(() async {
      final build = Directory('build/attachment-video-service-test');
      await build.create(recursive: true);
      root = await build.createTemp('case-');
    });
    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'exact bytes, generated names, unique ownership and idempotent close',
      () async {
        final unrelated = File('${root.path}/keep.txt');
        await unrelated.writeAsString('unrelated');
        final store = AttachmentVideoFileStore(
          temporaryDirectoryProvider: () async => root,
        );
        final bytes = Uint8List.fromList([0, 255, 128, 1, 2, 3]);
        final first = await store.stage(bytes, 'MP4');
        final second = await store.stage(bytes, 'mp4');
        expect(await first.file.readAsBytes(), bytes);
        expect(await second.file.readAsBytes(), bytes);
        expect(first.file.uri.pathSegments.last, 'attachment.mp4');
        expect(first.file.parent.parent.absolute.path, root.absolute.path);
        expect(first.file.parent.path, isNot(second.file.parent.path));
        final close = first.close();
        expect(identical(close, first.close()), isTrue);
        await close;
        expect(await first.file.parent.exists(), isFalse);
        expect(await second.file.exists(), isTrue);
        expect(await unrelated.readAsString(), 'unrelated');
        await second.close();
        expect(await second.file.parent.exists(), isFalse);
        expect(await unrelated.exists(), isTrue);
      },
    );

    test('snapshots mutable bytes before a held directory lookup', () async {
      final lookup = Completer<Directory>();
      final store = AttachmentVideoFileStore(
        temporaryDirectoryProvider: () => lookup.future,
      );
      final bytes = Uint8List.fromList([10, 20, 30]);
      final staging = store.stage(bytes, 'mov');
      bytes[0] = 99;
      lookup.complete(root);
      final staged = await staging;
      expect(await staged.file.readAsBytes(), [10, 20, 30]);
      await staged.close();
      expect(await staged.file.parent.exists(), isFalse);
    });

    test(
      'rejects empty, over-budget and unsafe names before any I/O',
      () async {
        var lookups = 0;
        final store = AttachmentVideoFileStore(
          temporaryDirectoryProvider: () async {
            lookups++;
            return root;
          },
        );
        await expectLater(
          store.stage(Uint8List(0), 'mp4'),
          throwsFormatException,
        );
        await expectLater(
          store.stage(Uint8List(maxAttachmentDownloadBytes + 1), 'mp4'),
          throwsFormatException,
        );
        for (final extension in [
          '../mp4',
          'mp4/../../victim',
          'movie.mp4',
          'm3u8',
          'mpd',
          'wmv',
          'asf',
        ]) {
          await expectLater(
            store.stage(Uint8List.fromList([1]), extension),
            throwsFormatException,
          );
        }
        expect(lookups, 0);
        expect(await root.list().toList(), isEmpty);
      },
    );

    test('accepts exactly the shared attachment byte budget', () async {
      final store = AttachmentVideoFileStore(
        temporaryDirectoryProvider: () async => root,
      );
      final bytes = Uint8List(maxAttachmentDownloadBytes);
      bytes[0] = 19;
      bytes[bytes.length - 1] = 71;
      final staged = await store.stage(bytes, 'webm');
      final result = await staged.file.readAsBytes();
      expect(result, bytes);
      await staged.close();
      expect(await staged.file.parent.exists(), isFalse);
    });

    test(
      'session closed during held private-directory preparation leaves no file',
      () async {
        final lookup = Completer<Directory>();
        final session = AttachmentVideoSession(
          fileStore: AttachmentVideoFileStore(
            temporaryDirectoryProvider: () => lookup.future,
          ),
        );
        final opening = session.open(Uint8List.fromList([1, 2, 3]), 'mp4');
        final closing = session.close();
        lookup.complete(root);
        expect(await opening, isFalse);
        await closing;
        expect(await root.list().toList(), isEmpty);
      },
    );

    test(
      'directory failure propagates without touching an unrelated sibling',
      () async {
        final sibling = File('${root.path}/keep')..writeAsStringSync('safe');
        final store = AttachmentVideoFileStore(
          temporaryDirectoryProvider: () async =>
              Directory('${root.path}/absent'),
        );
        await expectLater(
          store.stage(Uint8List.fromList([1]), 'mp4'),
          throwsA(isA<FileSystemException>()),
        );
        expect(await sibling.readAsString(), 'safe');
      },
    );
  });

  group('native session ownership', () {
    late VideoPlayerPlatform previousPlatform;
    late List<String> log;
    late _Platform platform;
    late _FileStore store;
    late AttachmentVideoSession session;

    setUp(() {
      previousPlatform = VideoPlayerPlatform.instance;
      log = [];
      platform = _Platform(log);
      VideoPlayerPlatform.instance = platform;
      store = _FileStore(log);
      session = AttachmentVideoSession(fileStore: store);
    });

    tearDown(() async {
      try {
        if (platform.createError != null) {
          // The pinned plugin's public dispose remains pending after failed
          // creation. Never turn that uncertainty into file-deletion authority.
          var settled = false;
          unawaited(session.close().then((_) => settled = true));
          await _drainMicrotasks();
          expect(settled, isFalse);
        } else if (platform.throwOnDispose) {
          await expectLater(session.close(), throwsA(isA<StateError>()));
        } else {
          await session.close();
        }
      } finally {
        // Failed-dispose fixtures intentionally retain a native handle.
        for (final stream in platform.streams.values) {
          await stream.close();
        }
        platform.streams.clear();
        VideoPlayerPlatform.instance = previousPlatform;
      }
    });

    Future<void> open() async {
      await session.setPlaybackAllowed(true);
      expect(await session.open(Uint8List.fromList([1, 2, 3]), 'mp4'), isTrue);
    }

    test(
      'uses only a header-free file player, never autoplays, deletes after dispose',
      () async {
        await open();
        final source = platform.sources.single;
        expect(source.sourceType, DataSourceType.file);
        expect(Uri.parse(source.uri!).scheme, 'file');
        expect(
          Uri.parse(source.uri!).toFilePath(),
          store.staged.single.file.absolute.path,
        );
        expect(source.httpHeaders, isEmpty);
        expect(log.where((entry) => entry.startsWith('play:')), isEmpty);
        await session.close();
        await session.close();
        expect(platform.disposed, [1]);
        expect(store.staged.single.closes, 1);
        expect(log.indexOf('dispose:1'), lessThan(log.indexOf('file-close:1')));
        expect(session.controller, isNull);
      },
    );

    test(
      'repeated open joins the first operation rather than staging twice',
      () async {
        final first = session.open(Uint8List.fromList([1]), 'mp4');
        final second = session.open(Uint8List.fromList([2]), 'mov');
        expect(identical(first, second), isTrue);
        expect(await first, isTrue);
        expect(store.payloads.single, [1]);
        expect(platform.sources, hasLength(1));
      },
    );

    test('close joins a held stage and never creates a late player', () async {
      final pending = store.pending = Completer<AttachmentVideoFile>();
      final file = _StagedFile(9, log);
      final opening = session.open(Uint8List.fromList([1]), 'mp4');
      final firstClose = session.close();
      expect(identical(firstClose, session.close()), isTrue);
      pending.complete(file);
      expect(await opening, isFalse);
      await firstClose;
      expect(file.closes, 1);
      expect(platform.sources, isEmpty);
      await expectLater(
        session.open(Uint8List.fromList([1]), 'mp4'),
        throwsStateError,
      );
    });

    test(
      'close joins held native creation without needing an initialized event',
      () async {
        platform.initializeAutomatically = false;
        final creation = platform.creationGate = Completer<void>();
        final opening = session.open(Uint8List.fromList([1]), 'mp4');
        await platform.created.future;
        var finished = false;
        final closing = session.close().then((_) => finished = true);
        await _drainMicrotasks();
        expect(finished, isFalse);
        expect(store.staged.single.closes, 0);
        creation.complete();
        await closing;
        expect(await opening, isFalse);
        expect(platform.disposed, [1]);
        expect(store.staged.single.closes, 1);
        expect(log.where((entry) => entry.startsWith('play:')), isEmpty);
      },
    );

    test(
      'disposes while initialization remains held, cancelling its event subscription',
      () async {
        platform.initializeAutomatically = false;
        final opening = session.open(Uint8List.fromList([1]), 'mp4');
        await platform.listening.future;
        await session.close();
        expect(await opening, isFalse);
        expect(platform.disposed, [1]);
        expect(platform.streams, isEmpty);
        expect(store.staged.single.closes, 1);
      },
    );

    test(
      'unsupported codec errors release the native player and exact staged file once',
      () async {
        platform.initializeAutomatically = false;
        final opening = session.open(Uint8List.fromList([1]), 'mp4');
        final assertion = expectLater(
          opening,
          throwsA(isA<PlatformException>()),
        );
        await platform.listening.future;
        platform.streams[1]!.addError(
          PlatformException(code: 'codec', message: 'unsupported codec'),
        );
        await assertion;
        await session.close();
        expect(platform.disposed, [1]);
        expect(store.staged.single.closes, 1);
      },
    );

    test(
      'native create failure surfaces promptly but retains until public disposal',
      () async {
        platform.createError = PlatformException(
          code: 'create',
          message: 'failed',
        );
        await expectLater(
          session.open(Uint8List.fromList([1]), 'mp4'),
          throwsA(isA<PlatformException>()),
        );
        var settled = false;
        unawaited(session.close().then((_) => settled = true));
        await _drainMicrotasks();
        expect(settled, isFalse);
        expect(platform.disposed, isEmpty);
        expect(store.staged.single.closes, 0);
      },
    );

    test(
      'close after a held create failure cannot invent disposal success',
      () async {
        final gate = platform.creationGate = Completer<void>();
        platform.createError = PlatformException(
          code: 'create',
          message: 'failed',
        );
        final opening = session.open(Uint8List.fromList([1]), 'mp4');
        await platform.created.future;
        final closing = session.close();
        var openingSettled = false;
        var closingSettled = false;
        unawaited(opening.then((_) => openingSettled = true));
        unawaited(closing.then((_) => closingSettled = true));
        gate.complete();
        await _drainMicrotasks();
        expect(openingSettled, isFalse);
        expect(closingSettled, isFalse);
        expect(platform.disposed, isEmpty);
        expect(store.staged.single.closes, 0);
      },
    );

    test('codec error is not masked by a rejected native release', () async {
      platform.initializeAutomatically = false;
      platform.throwOnDispose = true;
      final original = PlatformException(
        code: 'codec',
        message: 'original failure',
      );
      final opening = session.open(Uint8List.fromList([1]), 'mp4');
      final assertion = expectLater(opening, throwsA(same(original)));
      await platform.listening.future;
      platform.streams[1]!.addError(original);
      await assertion;
      await expectLater(session.close(), throwsA(isA<StateError>()));
      expect(store.staged.single.closes, 0);
      expect(platform.disposed, [1]);
    });

    test(
      'codec error surfaces while native disposal is held; close still joins',
      () async {
        platform.initializeAutomatically = false;
        final gate = platform.disposeGate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final original = PlatformException(
          code: 'codec',
          message: 'original failure',
        );
        final opening = session.open(Uint8List.fromList([1]), 'mp4');
        final assertion = expectLater(opening, throwsA(same(original)));
        await platform.listening.future;
        platform.streams[1]!.addError(original);
        await assertion;
        var settled = false;
        final closing = session.close().then((_) => settled = true);
        await _drainMicrotasks();
        expect(settled, isFalse);
        expect(store.staged.single.closes, 0);
        gate.complete();
        await closing;
        expect(store.staged.single.closes, 1);
        expect(log.indexOf('dispose:1'), lessThan(log.indexOf('file-close:1')));
      },
    );

    test(
      'close joins a held play before disposing and cannot leave a late timer',
      () async {
        await open();
        final gate = platform.playGate = Completer<void>();
        final playing = session.play();
        await _drainMicrotasks();
        expect(log, contains('play:1'));
        final closing = session.close();
        await _drainMicrotasks();
        expect(platform.disposed, isEmpty);
        expect(store.staged.single.closes, 0);
        gate.complete();
        await playing;
        await closing;
        expect(platform.disposed, [1]);
        expect(store.staged.single.closes, 1);
        expect(log.indexOf('play:1'), lessThan(log.lastIndexOf('pause:1')));
        expect(log.lastIndexOf('pause:1'), lessThan(log.indexOf('dispose:1')));
        final entries = log.length;
        await session.play();
        await session.seekTo(const Duration(seconds: 3));
        await session.setMuted(true);
        expect(log.length, entries);
      },
    );

    test(
      'suspending during a replay seek revokes playback even after foregrounding',
      () async {
        await open();
        final controller = session.controller!;
        controller.value = controller.value.copyWith(
          position: controller.value.duration,
          isCompleted: true,
        );
        final gate = platform.seekGate = Completer<void>();
        final replay = session.play();
        await _drainMicrotasks();
        expect(log, contains('seek:1:0'));
        final pause = session.setPlaybackAllowed(false);
        await session.setPlaybackAllowed(true);
        gate.complete();
        await replay;
        await pause;
        expect(log.where((entry) => entry.startsWith('play:')), isEmpty);
        platform.seekGate = null;
        await session.play();
        expect(log.where((entry) => entry.startsWith('play:')), ['play:1']);
      },
    );

    test(
      'a hidden tap cannot become playback after an immediate foreground change',
      () async {
        await open();
        await session.setPlaybackAllowed(false);
        final hiddenTap = session.play();
        await session.setPlaybackAllowed(true);
        await hiddenTap;
        expect(log.where((entry) => entry.startsWith('play:')), isEmpty);
        await session.play();
        await session.play();
        expect(log.where((entry) => entry.startsWith('play:')), ['play:1']);
      },
    );

    test('seek clamps and mute does not start playback', () async {
      await open();
      await session.seekTo(const Duration(seconds: 99));
      expect(session.controller!.value.position, const Duration(seconds: 10));
      await session.seekTo(const Duration(seconds: -1));
      expect(session.controller!.value.position, Duration.zero);
      await session.setMuted(true);
      expect(session.controller!.value.volume, 0);
      await session.setMuted(false);
      expect(session.controller!.value.volume, 1);
      expect(log.where((entry) => entry.startsWith('play:')), isEmpty);
    });

    test(
      'failed native disposal retains its source rather than deleting under a reader',
      () async {
        await open();
        platform.throwOnPause = true;
        platform.throwOnDispose = true;
        final closing = session.close();
        await expectLater(closing, throwsA(isA<StateError>()));
        await expectLater(session.close(), throwsA(isA<StateError>()));
        expect(platform.disposed, [1]);
        expect(store.staged.single.closes, 0);
        expect(
          platform.streams.containsKey(1),
          isTrue,
          reason: 'The failed native release leaves its reader owned.',
        );
        expect(session.controller, isNull);
      },
    );
  });
}
