import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/delegated_task_controller.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/delegated_task_timeline.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'delegated_task_history_test.dart' show FakeHistory, task;

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');
const _apkUrl =
    'https://github.com/rusty4444/hermes-android/releases/download/'
    'v3.0.0-rc.1/hermes-arm64-v8a.apk';
const _releaseUrl =
    'https://github.com/rusty4444/hermes-android/releases/tag/v3.0.0-rc.1';

Widget _app(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: hermesTheme(brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

Widget _taskOpener(DelegatedTaskController controller) => Builder(
  builder: (context) => TextButton(
    onPressed: () => unawaited(showDelegatedTaskTimeline(context, controller)),
    child: const Text('Open task'),
  ),
);

class _DownloadProbe implements RemoteFilesDataSource {
  final paths = <String>[];

  @override
  Future<RemoteFileDownload> download(String path) async {
    paths.add(path);
    // Stop at the gateway boundary; sharing is covered by the media tests.
    throw StateError('Download rejected by test gateway.');
  }

  @override
  Future<RemoteDirectory> defaultDirectory() => throw UnimplementedError();

  @override
  Future<List<RemoteFileEntry>> listDirectory(String path) =>
      throw UnimplementedError();

  @override
  Future<RemoteTextPreview> readText(String path) => throw UnimplementedError();
}

void main() {
  final launches = <MethodCall>[];
  Future<bool> Function() launch = () async => true;

  setUp(() {
    launches.clear();
    launch = () async => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, (call) async {
          if (call.method != 'launch') {
            throw StateError('Unexpected launcher call: ${call.method}');
          }
          launches.add(call);
          return launch();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_launcher, null);
  });

  for (final (isUser, hasFilesClient) in [
    (false, false),
    (false, true),
    (true, true),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('$isUser/$hasFilesClient $brightness links open externally', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            MessageBubble(
              content:
                  '- [Download ARM64 APK]($_apkUrl)\n'
                  '- [Release page]($_releaseUrl)',
              isUser: isUser,
              mediaFilesClient: hasFilesClient
                  ? () => throw StateError('Web links must not fetch files.')
                  : null,
            ),
            brightness: brightness,
          ),
        );
        expect(launches, isEmpty, reason: 'Rendering must not open a URL.');

        await tester.tap(find.text('Download ARM64 APK', findRichText: true));
        await tester.pump();
        await tester.tap(find.text('Release page', findRichText: true));
        await tester.pump();

        expect(launches.map((call) => call.arguments['url']), [
          _apkUrl,
          _releaseUrl,
        ]);
        for (final call in launches) {
          expect(call.arguments['useWebView'], false);
          expect(call.arguments['useSafariVC'], false);
          expect(call.arguments['headers'], isEmpty);
        }
        expect(find.text('Message actions'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final (source, label, url) in [
    (
      'https://example.com/search?q=hermes&version=3#downloads',
      'https://example.com/search?q=hermes&version=3#downloads',
      'https://example.com/search?q=hermes&version=3#downloads',
    ),
    (
      '<http://192.168.68.164:8188/>',
      'http://192.168.68.164:8188/',
      'http://192.168.68.164:8188/',
    ),
    (
      '[Documentation][docs]\n\n[docs]: https://example.com/docs',
      'Documentation',
      'https://example.com/docs',
    ),
    (
      '**[Documentation](https://example.com/docs)**',
      'Documentation',
      'https://example.com/docs',
    ),
  ]) {
    testWidgets('autolinks and formatted links are tappable: $source', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(MessageBubble(content: source, isUser: false)),
      );
      // A long URL wraps: tap a glyph rather than blank space at its box centre.
      await tester.tapAt(
        tester.getTopLeft(find.text(label, findRichText: true)) +
            const Offset(8, 8),
      );
      await tester.pump();
      expect(launches, hasLength(1));
      expect(launches.single.arguments['url'], url);
    });
  }

  test('link failure feedback resolves in every shipped locale', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.could_not_open_link, isNotEmpty, reason: '$locale');
      if (locale.languageCode != 'en') {
        expect(l10n.could_not_open_link, isNot('Could not open this link.'));
      }
    }
  });

  testWidgets('mixed web and MEDIA links retain separate destinations', (
    tester,
  ) async {
    final files = _DownloadProbe();
    await tester.pumpWidget(
      _app(
        MessageBubble(
          content:
              '- [Release page]($_releaseUrl)\n'
              '- MEDIA:"/srv/my report.pdf"',
          isUser: false,
          mediaFilesClient: () => files,
        ),
      ),
    );
    await tester.tap(find.text('Release page', findRichText: true));
    await tester.pump();
    expect(launches.single.arguments['url'], _releaseUrl);
    expect(files.paths, isEmpty);
    await tester.tap(find.text('my report.pdf', findRichText: true));
    await tester.pump();
    expect(files.paths, ['/srv/my report.pdf']);
    expect(launches, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('links still work after selecting message text', (tester) async {
    await tester.pumpWidget(
      _app(
        const MessageBubble(
          content: '[Release page]($_releaseUrl)',
          isUser: false,
        ),
      ),
    );
    await tester.longPress(find.byKey(const Key('message-bubble')));
    await tester.pumpAndSettle();
    expect(launches, isEmpty, reason: 'Long press only opens message actions.');
    await tester.tap(find.byTooltip('Select text'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsWidgets);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Release page'),
      ),
    );
    await tester.pump();
    expect(launches.single.arguments['url'], _releaseUrl);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  for (final throws in [false, true]) {
    testWidgets('launcher failure shows feedback (throws: $throws)', (
      tester,
    ) async {
      launch = () async {
        if (throws) throw PlatformException(code: 'NO_BROWSER');
        return false;
      };
      await tester.pumpWidget(
        _app(
          const MessageBubble(
            content: '[Release page]($_releaseUrl)',
            isUser: false,
          ),
        ),
      );
      await tester.tap(find.text('Release page', findRichText: true));
      await tester.pump();
      expect(find.text('Could not open this link.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late launch failure is harmless after the bubble is disposed', (
    tester,
  ) async {
    final result = Completer<bool>();
    launch = () => result.future;
    await tester.pumpWidget(
      _app(
        const MessageBubble(
          content: '[Release page]($_releaseUrl)',
          isUser: false,
        ),
      ),
    );
    await tester.tap(find.text('Release page', findRichText: true));
    await tester.pump();
    expect(launches, hasLength(1));
    await tester.pumpWidget(_app(const SizedBox()));
    result.complete(false);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported, relative, malformed and artifact URLs stay inert', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MessageBubble(
          content: '[Link](https://example.com)',
          isUser: false,
        ),
      ),
    );
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    for (final href in <String?>[
      null,
      '',
      '#section',
      '/gateway/private-file',
      '//example.com/path',
      'file:///sdcard/private.txt',
      'javascript:alert(1)',
      'data:text/html,example',
      'intent://example.com#Intent;scheme=https;end',
      'mailto:person@example.com',
      'media-artifact:///srv/output.pdf',
      'https://',
      'https://[broken',
    ]) {
      markdown.onTapLink?.call('Link', href, '');
      await tester.pump();
      expect(launches, isEmpty, reason: '$href');
      expect(tester.takeException(), isNull, reason: '$href');
    }
  });

  for (final source in [
    '`[Release page]($_releaseUrl)`',
    '```markdown\n[Release page]($_releaseUrl)\n```',
  ]) {
    testWidgets('URLs in code examples do not open: $source', (tester) async {
      await tester.pumpWidget(
        _app(MessageBubble(content: source, isUser: false)),
      );
      await tester.tap(find.textContaining('Release page', findRichText: true));
      await tester.pump();
      expect(launches, isEmpty);
    });
  }

  for (final width in [430.0, 1000.0]) {
    for (final throws in [false, true]) {
      testWidgets(
        'failure stays visible above the $width task modal ($throws)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          launch = () async {
            if (throws) throw PlatformException(code: 'NO_BROWSER');
            return false;
          };
          final history = FakeHistory()
            ..data = [
              {
                'id': 1,
                'role': 'assistant',
                'content': '[Release page]($_releaseUrl)',
              },
            ];
          final controller = DelegatedTaskController(
            task: task,
            history: history,
          );
          await tester.pumpWidget(_app(_taskOpener(controller)));
          await tester.tap(find.text('Open task'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Release page'));
          await tester.pumpAndSettle();

          expect(
            find.text('Could not open this link.').hitTestable(),
            findsOneWidget,
          );
          expect(find.byType(DelegatedTaskTimeline), findsOneWidget);
          expect(launches.single.arguments['url'], _releaseUrl);
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Close'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Release page').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final surface in ['selection', 'task']) {
    for (final width in [430.0, 1000.0]) {
      for (final throws in [false, true]) {
        testWidgets(
          'popping $width $surface suppresses failure before unmount ($throws)',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(width, 800);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final result = Completer<bool>();
            launch = () => result.future;
            if (surface == 'selection') {
              await tester.pumpWidget(
                _app(
                  const MessageBubble(
                    content: '[Release page]($_releaseUrl)',
                    isUser: false,
                  ),
                ),
              );
              await tester.longPress(find.byKey(const Key('message-bubble')));
              await tester.pumpAndSettle();
              await tester.tap(find.byTooltip('Select text'));
            } else {
              final history = FakeHistory()
                ..data = [
                  {
                    'id': 1,
                    'role': 'assistant',
                    'content': '[Release page]($_releaseUrl)',
                  },
                ];
              final controller = DelegatedTaskController(
                task: task,
                history: history,
              );
              await tester.pumpWidget(_app(_taskOpener(controller)));
              await tester.tap(find.text('Open task'));
            }
            await tester.pumpAndSettle();
            final link = find.text('Release page').hitTestable();
            final originContext = tester.element(link);
            final originRoute = ModalRoute.of(originContext)!;
            await tester.tap(link);
            await tester.pump();
            expect(launches, hasLength(1));
            expect(originRoute.isActive, isTrue);
            await tester.tap(find.text('Close').hitTestable());
            // Pop revokes the route before its reverse animation unmounts it.
            expect(originRoute.isActive, isFalse);
            expect(originContext.mounted, isTrue);
            if (throws) {
              result.completeError(PlatformException(code: 'NO_BROWSER'));
            } else {
              result.complete(false);
            }
            await tester.pump();
            expect(originContext.mounted, isTrue);
            expect(find.text('Could not open this link.'), findsNothing);
            await tester.pumpAndSettle();
            expect(originContext.mounted, isFalse);
            expect(find.text('Could not open this link.'), findsNothing);
            expect(find.byType(AlertDialog), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'delegated transcript links open without fetching history again',
    (tester) async {
      final history = FakeHistory()
        ..data = [
          {
            'id': 1,
            'role': 'assistant',
            'content': '[Release page]($_releaseUrl)',
          },
        ];
      final controller = DelegatedTaskController(task: task, history: history);
      await tester.pumpWidget(
        _app(DelegatedTaskTimeline(controller: controller)),
      );
      await tester.pump();
      final reads = history.offsets.length;
      await tester.tap(find.text('Release page'));
      await tester.pump();
      expect(launches.single.arguments['url'], _releaseUrl);
      expect(history.offsets, hasLength(reads));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
