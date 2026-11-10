import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Foldables present two very different chat layouts: the narrow cover
/// display (about 344 dp wide) and the near-square inner display (about
/// 700 dp wide). The composer pill and the send control must survive both,
/// with and without the on-screen keyboard.
Future<void> _pumpChat(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'verbose_mode': false});
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
      home: ChatScreen(
        connection: SavedConnection(
          id: 'fold-fixture',
          label: 'Fold fixture',
          host: 'fixture.invalid',
          port: 8000,
          apiKey: '',
        ),
        session: const Session(
          id: 'fold-session',
          title: 'Chat',
          model: 'fixture',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectComposerFits(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final pill = find.byKey(const Key('chat-composer-pill'));
  final field = find.byKey(const Key('chat-message-composer'));
  final send = find.byKey(const Key('chat-send-message'));
  expect(pill, findsOneWidget);
  expect(field, findsOneWidget);
  expect(send, findsOneWidget);

  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  final pillRect = tester.getRect(pill);
  final fieldRect = tester.getRect(field);
  final sendRect = tester.getRect(send);

  // The pill stays on screen and keeps its rounded dock inside the edges.
  expect(pillRect.left, greaterThanOrEqualTo(0));
  expect(pillRect.right, lessThanOrEqualTo(screen.width));
  expect(pillRect.top, greaterThan(0));
  expect(pillRect.bottom, lessThanOrEqualTo(screen.height));

  // Send stays reachable and never overlaps the text field at either width.
  expect(sendRect.width, greaterThanOrEqualTo(44));
  expect(sendRect.height, greaterThanOrEqualTo(44));
  expect(fieldRect.overlaps(sendRect), isFalse);
  expect(fieldRect.right, lessThanOrEqualTo(sendRect.left + 0.5));
}

void main() {
  for (final (name, size) in [
    ('cover display 344x841', const Size(344, 841)),
    ('inner display 700x640', const Size(700, 640)),
    ('unfolded wide 1000x700', const Size(1000, 700)),
  ]) {
    testWidgets('composer fits the $name', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await _pumpChat(tester);
      _expectComposerFits(tester);
    });
  }

  testWidgets('composer fits the cover display with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(344, 841) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpChat(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
    await tester.pumpAndSettle();
    _expectComposerFits(tester);
    // The editor keeps a usable width above a 300 dp keyboard.
    expect(
      tester.getSize(find.byKey(const Key('chat-message-composer'))).width,
      greaterThan(80),
    );
  });

  testWidgets('inner display centres the transcript at the tablet width cap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 700) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pumpChat(tester);
    final pill = tester.getRect(find.byKey(const Key('chat-composer-pill')));
    // ConstrainedBox caps the chat column at 800 dp and centres it.
    expect(pill.width, lessThanOrEqualTo(800));
    expect(pill.center.dx, closeTo(500, 1));
  });
}
