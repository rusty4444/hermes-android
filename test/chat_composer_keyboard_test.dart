import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/attachment_draft_tile.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

import 'support/fake_voice_composer_adapter.dart';

Future<void> _pumpChat(
  WidgetTester tester,
  double textScale, {
  TestDesktopAsyncEventHook? asyncHook,
  bool withAttachmentDrafts = true,
  bool verbose = false,
}) async {
  SharedPreferences.setMockInitialValues({'verbose_mode': verbose});
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(picker, (_) async => null);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null),
  );
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ChatScreen(
        connection: SavedConnection(
          id: 'keyboard-fixture',
          label: 'Keyboard fixture',
          host: 'fixture.invalid',
          port: 8000,
          apiKey: '',
        ),
        session: const Session(
          id: 'keyboard-session',
          title: 'Chat',
          model: 'fixture',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        initialAttachmentDrafts: withAttachmentDrafts
            ? List.generate(
                2,
                (index) => AttachmentDraft(
                  id: 'photo-$index',
                  cachedPath: '/fixture/photo-$index.png',
                  name: 'photo-$index.png',
                  byteLength: 100,
                  mediaType: 'image/png',
                  kind: AttachmentDraftKind.image,
                  sanitized: true,
                  // Uploaded fixtures need no filesystem access or image decoding.
                  status: AttachmentDraftStatus.attached,
                ),
              )
            : const [],
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testDesktopAsyncEventHook: asyncHook,
        testApiClient: ApiClient(
          baseUrl: 'https://fixture.invalid',
          apiKey: '',
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'data': []}), 200),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectVisibleCaret(WidgetTester tester, double keyboardTop) {
  final editor = tester.state<EditableTextState>(find.byType(EditableText));
  final render = editor.renderEditable;
  final caret = render.getLocalRectForCaret(
    editor.widget.controller.selection.extent,
  );
  expect(caret.top, greaterThanOrEqualTo(-2));
  expect(caret.bottom, lessThanOrEqualTo(render.size.height + 2));
  expect(
    render.localToGlobal(caret.bottomRight).dy,
    lessThanOrEqualTo(keyboardTop),
  );
}

void main() {
  for (final scenario in [
    (412.0, 740.0, 340.0, 1.0),
    (412.0, 860.0, 340.0, 1.8),
    (320.0, 860.0, 340.0, 2.0),
    (860.0, 412.0, 180.0, 1.0),
  ]) {
    final (width, height, keyboardHeight, textScale) = scenario;
    testWidgets('two photos and multiline text remain usable above IME '
        'at $width x $height, scale $textScale', (tester) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpChat(tester, textScale);
      final field = find.byKey(const Key('chat-message-composer'));
      await tester.enterText(
        field,
        List.generate(12, (index) => 'Caption line ${index + 1}').join('\n'),
      );
      await tester.pumpAndSettle();
      _expectVisibleCaret(tester, height);

      // Opening the keyboard must resize both drafts and editor. The caret
      // should keep following new input, rather than disappearing below it.
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      await tester.pumpAndSettle();
      await tester.enterText(
        field,
        List.generate(13, (index) => 'Caption line ${index + 1}').join('\n'),
      );
      await tester.pumpAndSettle();
      _expectVisibleCaret(tester, height - keyboardHeight);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byTooltip('Send')).bottom,
        lessThanOrEqualTo(height - keyboardHeight),
      );

      // Draft controls remain reachable even if the reduced list scrolls.
      final second = find.byWidgetPredicate(
        (widget) =>
            widget is AttachmentDraftTile && widget.draft.id == 'photo-1',
      );
      final moveUp = find.descendant(
        of: second,
        matching: find.byIcon(Icons.arrow_upward),
      );
      await tester.ensureVisible(find.byType(ListView).last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        moveUp,
        80,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(moveUp);
      await tester.pumpAndSettle();
      await tester.tap(moveUp);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(ListView).last);
      await tester.drag(find.byType(ListView).last, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AttachmentDraftTile>(find.byType(AttachmentDraftTile).first)
            .draft
            .id,
        'photo-1',
      );

      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      _expectVisibleCaret(tester, height);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('gateway notices leave the composer above the IME', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(860, 412);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asyncHook = TestDesktopAsyncEventHook();
    await _pumpChat(tester, 1, asyncHook: asyncHook, verbose: true);

    tester.view.viewInsets = const FakeViewPadding(bottom: 180);
    await tester.enterText(
      find.byKey(const Key('chat-message-composer')),
      List.generate(13, (index) => 'Caption line ${index + 1}').join('\n'),
    );
    asyncHook.handler?.call(
      StreamEvent(
        type: 'notification.show',
        data: const {
          'key': 'composer-layout',
          'level': 'warn',
          'text': 'A gateway notice that must not cover the composer.',
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('A gateway notice that must not cover the composer.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byTooltip('Send')).bottom,
      lessThanOrEqualTo(232),
    );
  });

  testWidgets('tiny IME viewport yields transcript space to controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(860, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpChat(tester, 1, withAttachmentDrafts: false);

    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byTooltip('Send')).bottom,
      lessThanOrEqualTo(160),
    );
  });
}
