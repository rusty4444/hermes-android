import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_asset.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/services/attachment_pdf_service.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/utils/attachment_types.dart';
import 'package:hermes_android/core/widgets/attachment_preview_dialog.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:image/image.dart' as image;

class _Files extends Fake implements RemoteFilesDataSource {
  _Files(this.bytes);
  final List<int> bytes;
  final paths = <String>[];
  Completer<RemoteFileDownload>? pending;
  @override
  Future<RemoteFileDownload> download(String path) async {
    paths.add(path);
    if (pending != null) return pending!.future;
    return RemoteFileDownload(filename: 'ignored-server-name', bytes: bytes);
  }
}

class _Picker extends FilePicker {
  final names = <String?>[];
  final payloads = <Uint8List?>[];
  final types = <FileType>[];
  String? result = 'content://saved/file';
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
    names.add(fileName);
    payloads.add(bytes);
    types.add(type);
    if (error case final error?) throw error;
    if (pending != null) return pending!.future;
    return result;
  }
}

Widget _host(
  RemoteFilesDataSource Function() factory, {
  String path = '/gateway/report.txt',
  Object? sourceIdentity,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.purple,
      brightness: brightness,
    ),
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 500,
        child: MediaArtifactCard(
          key: const ValueKey('same-card-state'),
          ref: MediaTagRef(path: path),
          filesClient: factory,
          sourceIdentity: sourceIdentity,
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Picker picker;
  final png = image.encodePng(image.Image(width: 2, height: 2));
  setUp(() {
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() {
    FilePicker.platform = FilePickerIO();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AttachmentPdfDocument.channel, null);
  });

  test(
    'image helper itself accepts mixed case without caller normalization',
    () {
      for (final extension in [
        'PNG',
        'JpG',
        'JPEG',
        'GIF',
        'WebP',
        'BMP',
        'TIF',
        'TIFF',
        'AVIF',
        'HEIC',
      ]) {
        expect(attachmentIsImage(extension), isTrue, reason: extension);
      }
      for (final extension in [
        'SVG',
        '.png',
        'file.png',
        '../png',
        'png/../txt',
        'https://host/a.png',
      ]) {
        expect(attachmentIsImage(extension), isFalse, reason: extension);
      }
    },
  );

  testWidgets(
    'asset kind, card icon and viewer candidates share the video set',
    (tester) async {
      const session = Session(
        id: 's',
        title: '',
        model: '',
        source: 'mobile',
        messageCount: 0,
        isActive: false,
        preview: '',
        startedAt: 1,
      );
      for (final extension in ['flv', 'f4v', 'ogv', 'm2ts', '3gpp', '3g2']) {
        final ref = MediaTagRef(
          path: '/gateway/test.${extension.toUpperCase()}',
        );
        expect(
          ChatAsset(session: session, ref: ref, timestamp: 0).kind,
          ChatAssetKind.video,
        );
        expect(attachmentIsVideo(extension.toUpperCase()), isTrue);
        final files = _Files([1]);
        await tester.pumpWidget(_host(() => files, path: ref.path));
        expect(
          find.byIcon(Icons.movie_outlined),
          findsOneWidget,
          reason: extension,
        );
        expect(files.paths, isEmpty);
      }
    },
  );

  testWidgets('SVG remains an image asset but previews only inert source text', (
    tester,
  ) async {
    final files = _Files(
      utf8.encode(
        '<svg onload="fetch(\'https://external.invalid\')"><script>active()</script></svg>',
      ),
    );
    await tester.pumpWidget(_host(() => files, path: '/gateway/diagram.SVG'));
    expect(attachmentIsImageAsset('SVG'), isTrue);
    expect(attachmentIsImage('SVG'), isFalse);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    await tester.tap(find.text('diagram.SVG'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-text-preview')), findsOneWidget);
    expect(find.byKey(const Key('attachment-image-preview')), findsNothing);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const Key('attachment-text-preview')),
          )
          .data,
      contains('<script>active()</script>'),
    );
    expect(files.paths, ['/gateway/diagram.SVG']);
  });

  testWidgets('render does not create a client, download or open a preview', (
    tester,
  ) async {
    var factories = 0;
    final files = _Files(utf8.encode('hello'));
    await tester.pumpWidget(
      _host(() {
        factories++;
        return files;
      }),
    );
    await tester.pumpAndSettle();
    expect(factories, 0);
    expect(files.paths, isEmpty);
    expect(find.byType(Dialog), findsNothing);
    expect(picker.names, isEmpty);
    expect(
      find.byKey(const Key('media-card-download-/gateway/report.txt')),
      findsOneWidget,
    );
    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
  });

  testWidgets(
    'card Save writes exact bytes/name with any type and no share or popup',
    (tester) async {
      final files = _Files([65, 66, 67]);
      await tester.pumpWidget(_host(() => files));
      await tester.tap(
        find.byKey(const Key('media-card-download-/gateway/report.txt')),
      );
      await tester.pumpAndSettle();
      expect(files.paths, ['/gateway/report.txt']);
      expect(picker.names, ['report.txt']);
      expect(picker.payloads.single, [65, 66, 67]);
      expect(picker.types.single, FileType.any);
      expect(find.text('File saved'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'text and Markdown are selectable inert text and popup Save reuses bytes',
    (tester) async {
      const source =
          '# Report\n![remote](https://example.invalid/private.png)\n<script>fetch("https://example.invalid")</script>';
      final files = _Files(utf8.encode(source));
      await tester.pumpWidget(_host(() => files, path: '/gateway/report.md'));
      await tester.tap(find.text('report.md'));
      await tester.pumpAndSettle();
      final text = tester.widget<SelectableText>(
        find.byKey(const Key('attachment-text-preview')),
      );
      expect(text.data, source);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('attachment-preview-save')));
      await tester.pumpAndSettle();
      expect(picker.names, ['report.md']);
      expect(picker.payloads.single, utf8.encode(source));
      expect(files.paths.length, 1);
      expect(find.byKey(const Key('attachment-preview-share')), findsOneWidget);
      await tester.tap(find.byKey(const Key('attachment-preview-close')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'image opens zoom preview and keeps the existing cinema exception',
    (tester) async {
      final files = _Files(png);
      await tester.pumpWidget(_host(() => files, path: '/gateway/picture.png'));
      await tester.tap(find.text('picture.png'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attachment-image-preview')), findsOneWidget);
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .maxScale,
        8,
      );
      expect(
        tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
        Colors.black,
      );
      expect(picker.names, isEmpty);
      await tester.tap(find.byKey(const Key('attachment-preview-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('image decode failure is visible and Save remains available', (
    tester,
  ) async {
    final files = _Files([1, 2, 3]);
    await tester.pumpWidget(_host(() => files, path: '/gateway/broken.png'));
    await tester.tap(find.text('broken.png'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This image could not be decoded'),
      findsWidgets,
    );
    await tester.tap(find.byKey(const Key('attachment-preview-save')));
    await tester.pumpAndSettle();
    expect(picker.payloads.single, [1, 2, 3]);
    expect(tester.takeException(), isNull);
  });

  for (final extension in ['doc', 'xls', 'ppt', 'zip', 'bin']) {
    testWidgets(
      '$extension opens honest themed fallback, not an executable viewer',
      (tester) async {
        final files = _Files([1, 2, 3]);
        await tester.pumpWidget(
          _host(
            () => files,
            path: '/gateway/file.$extension',
            brightness: Brightness.dark,
          ),
        );
        await tester.tap(find.text('file.$extension'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('No inline preview is available'),
          findsOneWidget,
        );
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(
          find.byKey(const Key('attachment-preview-save')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('attachment-preview-share')),
          findsOneWidget,
        );
        final dialogContext = tester.element(find.byType(Dialog));
        expect(
          tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
          Theme.of(dialogContext).colorScheme.surface,
        );
      },
    );
  }

  testWidgets(
    'cancel and failed Save are visible but never reported as saved',
    (tester) async {
      final files = _Files([65]);
      picker.result = null;
      await tester.pumpWidget(_host(() => files));
      final save = find.byKey(
        const Key('media-card-download-/gateway/report.txt'),
      );
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Save cancelled'), findsOneWidget);
      expect(find.text('File saved'), findsNothing);
      picker.error = PlatformException(code: 'write_failed');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save this file'), findsOneWidget);
      expect(find.text('File saved'), findsNothing);
      expect(files.paths.length, 1);
    },
  );

  testWidgets('double preview taps coalesce before the route exists', (
    tester,
  ) async {
    final files = _Files([65])..pending = Completer<RemoteFileDownload>();
    await tester.pumpWidget(_host(() => files));
    await tester.tap(find.text('report.txt'));
    await tester.tap(find.text('report.txt'));
    expect(files.paths.length, 1);
    files.pending!.complete(
      RemoteFileDownload(filename: 'report.txt', bytes: [65]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets(
    'same-path factory/source replacement fences old fetch before Save',
    (tester) async {
      final old = _Files([1])..pending = Completer<RemoteFileDownload>();
      final newer = _Files([2]);
      await tester.pumpWidget(_host(() => old));
      await tester.tap(
        find.byKey(const Key('media-card-download-/gateway/report.txt')),
      );
      await tester.pump();
      await tester.pumpWidget(_host(() => newer));
      old.pending!.complete(
        RemoteFileDownload(filename: 'wrong.txt', bytes: [1]),
      );
      await tester.pumpAndSettle();
      expect(picker.names, isEmpty);
      await tester.tap(
        find.byKey(const Key('media-card-download-/gateway/report.txt')),
      );
      await tester.pumpAndSettle();
      expect(picker.names, ['report.txt']);
      expect(picker.payloads.single, [2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stable authority preserves a held fetch across new factory closures',
    (tester) async {
      final files = _Files([65])..pending = Completer<RemoteFileDownload>();
      await tester.pumpWidget(
        _host(
          () => files,
          sourceIdentity: ('connection', 'profile', 'session'),
        ),
      );
      await tester.tap(find.text('report.txt'));
      await tester.pump();
      await tester.pumpWidget(
        _host(
          () => files,
          sourceIdentity: ('connection', 'profile', 'session'),
        ),
      );
      files.pending!.complete(
        RemoteFileDownload(filename: 'report.txt', bytes: [65]),
      );
      await tester.pumpAndSettle();
      expect(files.paths.length, 1);
      expect(find.byType(Dialog), findsOneWidget);
    },
  );

  testWidgets(
    'ref replacement while picker is open cannot relabel an old save',
    (tester) async {
      final old = _Files([1]);
      picker.pending = Completer<String?>();
      await tester.pumpWidget(_host(() => old, path: '/old.txt'));
      await tester.tap(find.byKey(const Key('media-card-download-/old.txt')));
      await tester.pump();
      expect(picker.names, ['old.txt']);
      await tester.pumpWidget(_host(() => _Files([2]), path: '/new.txt'));
      picker.pending!.complete('content://saved/old');
      await tester.pumpAndSettle();
      expect(picker.names, ['old.txt']);
      expect(find.text('File saved'), findsNothing);
      expect(find.text('new.txt'), findsOneWidget);
    },
  );

  testWidgets(
    'disposing while a download is held never invokes a native save later',
    (tester) async {
      final files = _Files([65])..pending = Completer<RemoteFileDownload>();
      await tester.pumpWidget(_host(() => files));
      await tester.tap(
        find.byKey(const Key('media-card-download-/gateway/report.txt')),
      );
      await tester.pumpWidget(const SizedBox());
      files.pending!.complete(
        RemoteFileDownload(filename: 'report.txt', bytes: [65]),
      );
      await tester.pumpAndSettle();
      expect(picker.names, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PDF renders real channel pages, pages forward and closes exact native handle',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AttachmentPdfDocument.channel,
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'open' => {'id': 'owned-pdf', 'pageCount': 2},
            'render' => {
              'bytes': Uint8List.fromList(png),
              'width': 2,
              'height': 2,
            },
            _ => null,
          };
        },
      );
      final files = _Files(utf8.encode('%PDF-fixture'));
      await tester.pumpWidget(_host(() => files, path: '/gateway/report.pdf'));
      expect(calls, isEmpty);
      await tester.tap(find.text('report.pdf'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attachment-pdf-preview')), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(calls.first.arguments['bytes'], utf8.encode('%PDF-fixture'));
      await tester.tap(find.byKey(const Key('attachment-pdf-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(
        calls
            .where((c) => c.method == 'render')
            .map((c) => c.arguments['page']),
        [0, 1],
      );
      await tester.tap(find.byKey(const Key('attachment-preview-save')));
      await tester.pumpAndSettle();
      expect(picker.payloads.single, utf8.encode('%PDF-fixture'));
      expect(files.paths.length, 1);
      await tester.tap(find.byKey(const Key('attachment-preview-close')));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'close').single.arguments, {
        'id': 'owned-pdf',
      });
    },
  );

  testWidgets('PDF error is honest and does not remove Save', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AttachmentPdfDocument.channel,
      (_) async => throw PlatformException(code: 'invalid_pdf'),
    );
    await tester.pumpWidget(_host(() => _Files([1, 2]), path: '/report.pdf'));
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This PDF could not be previewed'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('attachment-preview-save')));
    await tester.pumpAndSettle();
    expect(picker.names, ['report.pdf']);
  });

  testWidgets('PDF opened after popup disposal is closed, never rendered', (
    tester,
  ) async {
    final open = Completer<Map<String, dynamic>>();
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AttachmentPdfDocument.channel,
      (call) async {
        calls.add(call);
        return call.method == 'open' ? open.future : null;
      },
    );
    await tester.pumpWidget(_host(() => _Files([1]), path: '/report.pdf'));
    await tester.tap(find.text('report.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls.where((c) => c.method == 'open').length, 1);
    await tester.tap(find.byKey(const Key('attachment-preview-close')));
    await tester.pumpAndSettle();
    open.complete({'id': 'late-owned-pdf', 'pageCount': 1});
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'render'), isEmpty);
    expect(calls.where((c) => c.method == 'close').single.arguments, {
      'id': 'late-owned-pdf',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('ref replacement dismisses only its old popup', (tester) async {
    final files = _Files([65]);
    await tester.pumpWidget(_host(() => files));
    await tester.tap(find.text('report.txt'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.pumpWidget(_host(() => _Files([66]), path: '/new.txt'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('new.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline preview opens once and starts its download on first tap',
    (tester) async {
      final files = _Files([65])..pending = Completer<RemoteFileDownload>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  unawaited(
                    openMediaFilePreview(
                      context: context,
                      filesClient: () => files,
                      ref: const MediaTagRef(path: '/inline.txt'),
                    ),
                  );
                  unawaited(
                    openMediaFilePreview(
                      context: context,
                      filesClient: () => files,
                      ref: const MediaTagRef(path: '/inline.txt'),
                    ),
                  );
                },
                child: const Text('Open inline'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open inline'));
      expect(files.paths, ['/inline.txt']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('attachment-preview-close')));
      await tester.pumpAndSettle();
      files.pending!.complete(
        RemoteFileDownload(filename: 'inline.txt', bytes: [65]),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(picker.names, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source replacement before popup entry never listens to a disposed controller',
    (tester) async {
      await tester.pumpWidget(_host(() => _Files([65])));
      await tester.tap(find.text('report.txt'));
      // Replace immediately, before pumping the popup's first build.
      await tester.pumpWidget(_host(() => _Files([66]), path: '/new.txt'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'binary-looking text has an honest fallback instead of a text viewer',
    (tester) async {
      await tester.pumpWidget(_host(() => _Files([65, 0, 66])));
      await tester.tap(find.text('report.txt'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attachment-text-preview')), findsNothing);
      expect(
        find.textContaining('could not be displayed as text'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('attachment-preview-save')), findsOneWidget);
    },
  );

  testWidgets(
    'long text shows a bounded preview and a visible truncation notice',
    (tester) async {
      await tester.pumpWidget(
        _host(
          () => _Files(List.filled(AttachmentTextContent.maxBytes + 1, 65)),
        ),
      );
      await tester.tap(find.text('report.txt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Preview shortened.'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('attachment-text-preview')),
            )
            .data!
            .length,
        AttachmentTextContent.maxBytes,
      );
    },
  );

  testWidgets(
    'non-Android PDF fallback does not call a missing native renderer',
    (tester) async {
      var nativeCalls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AttachmentPdfDocument.channel,
        (_) async {
          nativeCalls++;
          return null;
        },
      );
      await tester.pumpWidget(_host(() => _Files([1]), path: '/report.pdf'));
      await tester.tap(find.text('report.pdf'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('PDF previews are available on Android'),
        findsOneWidget,
      );
      expect(nativeCalls, 0);
      expect(find.byKey(const Key('attachment-preview-save')), findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets(
    'closing a PDF while its page render is held closes exactly once',
    (tester) async {
      final render = Completer<Map<String, dynamic>>();
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AttachmentPdfDocument.channel,
        (call) async {
          calls.add(call);
          return switch (call.method) {
            'open' => {'id': 'rendering-pdf', 'pageCount': 1},
            'render' => render.future,
            _ => null,
          };
        },
      );
      await tester.pumpWidget(_host(() => _Files([1]), path: '/report.pdf'));
      await tester.tap(find.text('report.pdf'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.where((call) => call.method == 'render').length, 1);
      await tester.tap(find.byKey(const Key('attachment-preview-close')));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'close').length, 1);
      render.complete({
        'bytes': Uint8List.fromList(png),
        'width': 2,
        'height': 2,
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attachment-pdf-preview')), findsNothing);
      expect(calls.where((call) => call.method == 'close').length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'bounded text prefix preserves plain Unicode and rejects binary payloads',
    () {
      final content = AttachmentTextContent(
        Uint8List.fromList(utf8.encode('日本語\nhello')),
      );
      expect(content.text, '日本語\nhello');
      expect(content.truncated, isFalse);
      expect(
        AttachmentTextContent(Uint8List.fromList([65, 0, 66])).text,
        isNull,
      );
      final large = AttachmentTextContent(
        Uint8List.fromList(
          List.filled(AttachmentTextContent.maxBytes + 10, 65),
        ),
      );
      expect(large.truncated, isTrue);
      expect(large.text!.length, AttachmentTextContent.maxBytes);
    },
  );
}
