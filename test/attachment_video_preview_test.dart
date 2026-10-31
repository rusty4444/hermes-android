import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_video_service.dart';
import 'package:hermes_android/core/widgets/attachment_video_preview.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as platform;

class _File implements AttachmentVideoFile {
  _File(this.id, this.log);
  final int id;
  final List<String> log;
  var closes = 0;

  @override
  File get file => File('/private/widget-video-$id/attachment.mp4');

  @override
  Future<void> close() async {
    closes++;
    log.add('file-close:$id');
  }
}

class _Store extends AttachmentVideoFileStore {
  _Store(this.log);
  final List<String> log;
  final bytes = <Uint8List>[];
  final extensions = <String>[];
  final files = <_File>[];
  Completer<AttachmentVideoFile>? stageGate;
  Object? error;

  _File newFile() {
    final file = _File(files.length + 1, log);
    files.add(file);
    return file;
  }

  @override
  Future<AttachmentVideoFile> stage(Uint8List data, String extension) async {
    log.add('stage:${bytes.length + 1}');
    bytes.add(Uint8List.fromList(data));
    extensions.add(extension);
    if (error case final error?) throw error;
    final gate = stageGate;
    stageGate = null;
    if (gate != null) return gate.future;
    return newFile();
  }
}

class _Platform extends platform.VideoPlayerPlatform {
  _Platform(this.log);
  final List<String> log;
  final sources = <platform.DataSource>[];
  final streams = <int, StreamController<platform.VideoEvent>>{};
  final disposed = <int>[];
  final plays = <int>[];
  final pauses = <int>[];
  final seeks = <Duration>[];
  final volumes = <double>[];
  final positions = <int, Duration>{};
  Completer<void>? createGate;
  Completer<void>? disposeGate;
  Completer<void>? playGate;
  Object? createError;
  var initializeAutomatically = true;
  var size = const Size(640, 360);

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(platform.VideoCreationOptions options) async {
    sources.add(options.dataSource);
    final id = sources.length;
    final initialize = initializeAutomatically;
    log.add('create:$id');
    final gate = createGate;
    createGate = null;
    await gate?.future;
    if (createError case final error?) throw error;
    streams[id] = StreamController<platform.VideoEvent>();
    if (initialize) {
      streams[id]!.add(
        platform.VideoEvent(
          eventType: platform.VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: size,
        ),
      );
    }
    return id;
  }

  @override
  Stream<platform.VideoEvent> videoEventsFor(int playerId) =>
      streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    log.add('dispose:$playerId');
    disposed.add(playerId);
    final gate = disposeGate;
    disposeGate = null;
    await gate?.future;
    await streams.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {
    log.add('play:$playerId');
    plays.add(playerId);
    await playGate?.future;
  }

  @override
  Future<void> pause(int playerId) async {
    log.add('pause:$playerId');
    pauses.add(playerId);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildViewWithOptions(platform.VideoViewOptions options) =>
      SizedBox(key: ValueKey('native-video-${options.playerId}'));
}

Widget _host(
  Uint8List bytes,
  _Store store, {
  String extension = 'mp4',
  GlobalKey<NavigatorState>? navigatorKey,
  double width = 500,
  double height = 400,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: brightness,
    ),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: height,
        child: AttachmentVideoPreview(
          key: const ValueKey('stable-video-state'),
          bytes: bytes,
          extension: extension,
          fileStore: store,
        ),
      ),
    ),
  ),
);

Future<void> _flush(WidgetTester tester) async {
  // Force frames too: paused lifecycle disables ordinary frame scheduling.
  for (var i = 0; i < 4; i++) {
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    // StreamSubscription.cancel() can settle in the root zone. Drain its
    // event-loop turn before asserting native disposal and file cleanup.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _flush(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late platform.VideoPlayerPlatform previousPlatform;
  late _Platform native;
  late _Store store;
  late List<String> log;

  setUp(() {
    previousPlatform = platform.VideoPlayerPlatform.instance;
    log = [];
    native = _Platform(log);
    platform.VideoPlayerPlatform.instance = native;
    store = _Store(log);
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    platform.VideoPlayerPlatform.instance = previousPlatform;
  });

  testWidgets(
    'header-free file playback requires Play; seek, mute, pause and replay work',
    (tester) async {
      final data = Uint8List.fromList([1, 255, 4]);
      await tester.pumpWidget(_host(data, store));
      await _flush(tester);
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(store.bytes.single, data);
      expect(store.extensions, ['mp4']);
      expect(native.sources.single.sourceType, platform.DataSourceType.file);
      expect(native.sources.single.httpHeaders, isEmpty);
      expect(
        Uri.parse(native.sources.single.uri!).toFilePath(),
        store.files.single.file.absolute.path,
      );
      expect(native.plays, isEmpty);
      expect(find.byTooltip('Play'), findsOneWidget);
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(controller.value.isPlaying, isFalse);

      final slider = tester.widget<Slider>(
        find.byKey(const Key('attachment-video-seek')),
      );
      slider.onChanged!(0.5);
      await _flush(tester);
      expect(native.seeks.last, const Duration(seconds: 5));
      expect(find.text('0:05 / 0:10'), findsOneWidget);
      expect(native.plays, isEmpty);
      await tester.tap(find.byTooltip('Mute'));
      await _flush(tester);
      expect(native.volumes.last, 0);
      expect(find.byTooltip('Unmute'), findsOneWidget);
      await tester.tap(find.byTooltip('Unmute'));
      await _flush(tester);
      expect(native.volumes.last, 1);

      await tester.tap(find.byTooltip('Play'));
      await _flush(tester);
      expect(native.plays, [1]);
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await _flush(tester);
      expect(controller.value.isPlaying, isFalse);

      native.streams[1]!.add(
        platform.VideoEvent(eventType: platform.VideoEventType.completed),
      );
      await _flush(tester);
      expect(find.byIcon(Icons.replay), findsOneWidget);
      await tester.tap(find.byTooltip('Play'));
      await _flush(tester);
      expect(native.seeks.last, Duration.zero);
      expect(native.plays, [1, 1]);
      await _unmount(tester);
      expect(native.disposed, [1]);
      expect(store.files.single.closes, 1);
      expect(log.indexOf('dispose:1'), lessThan(log.indexOf('file-close:1')));
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '$brightness uses the active palette and the actual video aspect ratio',
      (tester) async {
        native.size = const Size(360, 640);
        await tester.pumpWidget(
          _host(Uint8List.fromList([1]), store, brightness: brightness),
        );
        await _flush(tester);
        final video = find.byKey(const Key('attachment-video-preview'));
        final aspect = tester.widget<AspectRatio>(
          find.ancestor(of: video, matching: find.byType(AspectRatio)).first,
        );
        expect(aspect.aspectRatio, 360 / 640);
        final context = tester.element(find.byType(AttachmentVideoPreview));
        final scheme = Theme.of(context).colorScheme;
        final backdrop = tester.widget<ColoredBox>(
          find.ancestor(of: video, matching: find.byType(ColoredBox)).first,
        );
        expect(backdrop.color, scheme.surfaceContainerHighest);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.play_arrow)).color,
          scheme.onSurface,
        );
        await _unmount(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'narrow and short viewports tolerate large text without overflow',
    (tester) async {
      await tester.pumpWidget(
        _host(
          Uint8List.fromList([1]),
          store,
          width: 180,
          height: 160,
          textScale: 3.5,
        ),
      );
      await _flush(tester);
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(
        find.byKey(const Key('attachment-video-play-pause')),
        findsOneWidget,
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stable parent rebuilds do not restage, recreate or reset playback',
    (tester) async {
      final data = Uint8List.fromList([1, 2]);
      await tester.pumpWidget(_host(data, store));
      await _flush(tester);
      await tester.tap(find.byTooltip('Mute'));
      await _flush(tester);
      final oldController = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      await tester.pumpWidget(_host(data, store, brightness: Brightness.dark));
      await _flush(tester);
      expect(store.bytes, hasLength(1));
      expect(native.sources, hasLength(1));
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(oldController),
      );
      expect(find.byTooltip('Unmute'), findsOneWidget);
      expect(native.disposed, isEmpty);
      await _unmount(tester);
      expect(store.files.single.closes, 1);
    },
  );

  testWidgets(
    'replacing bytes disposes and deletes only the old session before staging new bytes',
    (tester) async {
      final data = Uint8List.fromList([1]);
      final newer = Uint8List.fromList([2, 3]);
      await tester.pumpWidget(_host(data, store));
      await _flush(tester);
      await tester.tap(find.byTooltip('Play'));
      await _flush(tester);
      await tester.pumpWidget(_host(newer, store, extension: 'mov'));
      await _flush(tester);
      expect(store.bytes, [data, newer]);
      expect(store.extensions, ['mp4', 'mov']);
      expect(native.disposed, [1]);
      expect(store.files[0].closes, 1);
      expect(store.files[1].closes, 0);
      expect(log.indexOf('file-close:1'), lessThan(log.indexOf('stage:2')));
      expect(native.plays, [1]);
      await _unmount(tester);
      expect(native.disposed, [1, 2]);
      expect(store.files.map((file) => file.closes), [1, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a held stage after disposal is cleaned once without ever creating a player',
    (tester) async {
      final gate = store.stageGate = Completer<AttachmentVideoFile>();
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      expect(store.bytes, hasLength(1));
      expect(native.sources, isEmpty);
      await _unmount(tester);
      final lateFile = store.newFile();
      gate.complete(lateFile);
      await _flush(tester);
      expect(lateFile.closes, 1);
      expect(native.sources, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement joins a held stage and its cleanup before preparing the new video',
    (tester) async {
      final gate = store.stageGate = Completer<AttachmentVideoFile>();
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      await tester.pumpWidget(_host(Uint8List.fromList([2]), store));
      await _flush(tester);
      expect(store.bytes, hasLength(1));
      final lateFile = store.newFile();
      gate.complete(lateFile);
      await _flush(tester);
      expect(lateFile.closes, 1);
      expect(store.bytes, [
        [1],
        [2],
      ]);
      expect(native.sources, hasLength(1));
      expect(log.indexOf('file-close:1'), lessThan(log.indexOf('stage:2')));
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(native.plays, isEmpty);
      await _unmount(tester);
      expect(store.files.map((file) => file.closes), [1, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposal while native initialization is held does not wait for a video event',
    (tester) async {
      native.initializeAutomatically = false;
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      expect(native.sources, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(VideoPlayer), findsNothing);
      await _unmount(tester);
      expect(native.disposed, [1]);
      expect(native.streams, isEmpty);
      expect(store.files.single.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement joins a late native create before allowing the new file/player',
    (tester) async {
      final gate = native.createGate = Completer<void>();
      native.initializeAutomatically = false;
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      expect(native.sources, hasLength(1));
      native.initializeAutomatically = true;
      await tester.pumpWidget(_host(Uint8List.fromList([2]), store));
      await _flush(tester);
      expect(store.bytes, hasLength(1));
      expect(native.disposed, isEmpty);
      gate.complete();
      await _flush(tester);
      expect(native.disposed, [1]);
      expect(store.files[0].closes, 1);
      expect(native.sources, hasLength(2));
      expect(store.bytes, [
        [1],
        [2],
      ]);
      expect(log.indexOf('file-close:1'), lessThan(log.indexOf('create:2')));
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(native.plays, isEmpty);
      await _unmount(tester);
      expect(native.disposed, [1, 2]);
      expect(store.files.map((file) => file.closes), [1, 1]);
    },
  );

  testWidgets(
    'replacement cannot delete a file until held native disposal finishes',
    (tester) async {
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      final gate = native.disposeGate = Completer<void>();
      await tester.pumpWidget(_host(Uint8List.fromList([2]), store));
      await _flush(tester);
      expect(native.disposed, [1]);
      expect(store.files.single.closes, 0);
      expect(store.bytes, hasLength(1));
      gate.complete();
      await _flush(tester);
      expect(store.files[0].closes, 1);
      expect(store.files[1].closes, 0);
      expect(find.byType(VideoPlayer), findsOneWidget);
      await _unmount(tester);
      expect(store.files.map((file) => file.closes), [1, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inactive/background pauses; resuming never auto-restarts', (
    tester,
  ) async {
    await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
    await _flush(tester);
    await tester.tap(find.byTooltip('Play'));
    await _flush(tester);
    expect(native.plays, [1]);
    final controller = tester
        .widget<VideoPlayer>(find.byType(VideoPlayer))
        .controller;
    final beforePause = native.pauses.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _flush(tester);
    expect(native.pauses.length, greaterThan(beforePause));
    expect(controller.value.isPlaying, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(native.plays, [1]);
    expect(controller.value.isPlaying, isFalse);
    await tester.tap(find.byTooltip('Play'));
    await _flush(tester);
    expect(native.plays, [1, 1]);
    await _unmount(tester);
    expect(store.files.single.closes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a preview mounted already paused cannot play until a new foreground tap',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      expect(find.byType(VideoPlayer), findsOneWidget);
      tester
          .widget<IconButton>(
            find.byKey(const Key('attachment-video-play-pause')),
          )
          .onPressed!();
      await _flush(tester);
      expect(native.plays, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flush(tester);
      expect(native.plays, isEmpty);
      await tester.tap(find.byTooltip('Play'));
      await _flush(tester);
      expect(native.plays, [1]);
      await _unmount(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a covering PopupRoute pauses, and popping it does not resume', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _host(Uint8List.fromList([1]), store, navigatorKey: navigator),
    );
    await _flush(tester);
    await tester.tap(find.byTooltip('Play'));
    await _flush(tester);
    final controller = tester
        .widget<VideoPlayer>(find.byType(VideoPlayer))
        .controller;
    final covered = navigator.currentState!.push<void>(
      DialogRoute<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Covering dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.value.isPlaying, isFalse);
    expect(native.plays, [1]);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await covered;
    expect(controller.value.isPlaying, isFalse);
    expect(native.plays, [1]);
    await tester.tap(find.byTooltip('Play'));
    await _flush(tester);
    expect(native.plays, [1, 1]);
    await _unmount(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'held play completing after backgrounding is joined and paused before cleanup',
    (tester) async {
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      final gate = native.playGate = Completer<void>();
      await tester.tap(find.byTooltip('Play'));
      await _flush(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _unmount(tester);
      expect(native.disposed, isEmpty);
      expect(store.files.single.closes, 0);
      gate.complete();
      await _flush(tester);
      expect(native.disposed, [1]);
      expect(store.files.single.closes, 1);
      expect(log.lastIndexOf('pause:1'), lessThan(log.indexOf('dispose:1')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flush(tester);
      expect(native.plays, [1]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final duringInitialization in [true, false]) {
    testWidgets(
      'codec failure (initializing: $duringInitialization) is honest and cleans up once',
      (tester) async {
        native.initializeAutomatically = !duringInitialization;
        await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
        await _flush(tester);
        native.streams[1]!.addError(
          PlatformException(code: 'codec', message: 'Unsupported codec'),
        );
        await _flush(tester);
        expect(
          find.text(
            'This video could not be played. Its format or codec may not be supported. Save or share the original file.',
          ),
          findsOneWidget,
        );
        expect(find.byType(VideoPlayer), findsNothing);
        expect(native.disposed, [1]);
        expect(store.files.single.closes, 1);
        await _unmount(tester);
        expect(native.disposed, [1]);
        expect(store.files.single.closes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'native create failure shows fallback while unconfirmed public release retains source',
    (tester) async {
      native.createError = PlatformException(code: 'create', message: 'Failed');
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      expect(find.byKey(const Key('attachment-video-error')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(native.disposed, isEmpty);
      expect(store.files.single.closes, 0);
      await _unmount(tester);
      expect(store.files.single.closes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two retained preview routes pause the covered player and release '
    'each source only after its own native disposal',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _host(Uint8List.fromList([1]), store, navigatorKey: navigator),
      );
      await _flush(tester);
      await tester.tap(find.byTooltip('Play'));
      await _flush(tester);
      final firstController = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      final secondStore = _Store(log);
      final route = navigator.currentState!.push<void>(
        DialogRoute<void>(
          context: navigator.currentContext!,
          builder: (_) => Dialog.fullscreen(
            child: AttachmentVideoPreview(
              bytes: Uint8List.fromList([2]),
              extension: 'mp4',
              fileStore: secondStore,
            ),
          ),
        ),
      );
      await _flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(native.sources, hasLength(2));
      expect(native.streams.keys, containsAll([1, 2]));
      expect(native.disposed, isEmpty);
      expect(firstController.value.isPlaying, isFalse);
      expect(store.files.single.closes, 0);
      expect(secondStore.files.single.closes, 0);
      expect(native.plays, [1]);
      await tester.tap(find.byTooltip('Play').last);
      await _flush(tester);
      expect(native.plays, [1, 2]);
      final gate = native.disposeGate = Completer<void>();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await route;
      await _flush(tester);
      expect(native.disposed, [2]);
      expect(secondStore.files.single.closes, 0);
      expect(store.files.single.closes, 0);
      expect(native.plays, [1, 2], reason: 'Uncovering must not auto-resume.');
      expect(firstController.value.isPlaying, isFalse);
      gate.complete();
      await _flush(tester);
      expect(secondStore.files.single.closes, 1);
      expect(native.streams.keys, [1]);
      await _unmount(tester);
      expect(native.disposed, [2, 1]);
      expect(store.files.single.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'staging failure is localized and never creates a native player',
    (tester) async {
      store.error = FileSystemException('Staging failed');
      await tester.pumpWidget(_host(Uint8List.fromList([1]), store));
      await _flush(tester);
      expect(find.byKey(const Key('attachment-video-error')), findsOneWidget);
      expect(native.sources, isEmpty);
      expect(store.files, isEmpty);
      await _unmount(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
