// NextGen read aloud and one-tap code-block copy (#288): every completed
// assistant reply offers Read aloud/Stop through one shared engine, and a
// fenced block's labelled Copy button copies just that block's source.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/hands_free_conversation_controller.dart'
    show HandsFreeSpeechOutcome;
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/hands_free_speech.dart';
import 'package:hermes_android/core/services/ws_client.dart' show StreamEvent;
import 'package:hermes_android/core/widgets/markdown_code_block.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/data/read_aloud.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/chat_view.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Playback boundary double: gated mode holds each utterance open until the
/// test completes it, so reading/stop/switch state is observable.
class _FakeSpeaker implements VoiceReplySpeaker {
  final spoken = <String>[];
  int stops = 0;
  int prepares = 0;
  bool prepareResult = true;
  bool gated = false;
  Completer<HandsFreeSpeechOutcome>? gate;
  HandsFreeSpeechOutcome outcome = HandsFreeSpeechOutcome.completed;

  @override
  Future<bool> prepare() async {
    prepares++;
    return prepareResult;
  }

  @override
  Future<HandsFreeSpeechOutcome> speak(
    String text, {
    required bool Function() isCurrent,
  }) {
    spoken.add(text);
    if (!isCurrent()) return Future.value(HandsFreeSpeechOutcome.canceled);
    if (gated) {
      final c = gate = Completer<HandsFreeSpeechOutcome>();
      return c.future;
    }
    return Future.value(outcome);
  }

  @override
  Future<void> stop() async {
    stops++;
    final c = gate;
    gate = null;
    if (c != null && !c.isCompleted) {
      c.complete(HandsFreeSpeechOutcome.canceled);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ttsChannel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> ttsCalls;

  setUp(() {
    ttsCalls = [];
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(ttsChannel, (call) async {
      ttsCalls.add(call);
      return switch (call.method) {
        'getMaxSpeechInputLength' => 4000,
        _ => 1,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(ttsChannel, null));

  Future<void> emitTtsEvent(String method) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method),
    );
    await messenger.handlePlatformMessage('flutter_tts', data, (_) {});
  }

  group('NgReadAloud controller', () {
    test('read claims the reply, speaks trimmed text, clears on done', () async {
      final fake = _FakeSpeaker()..gated = true;
      final controller = NgReadAloud(speaker: fake);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;

      final reading = controller.read('a', '  Hello world  ');
      await pumpEventQueue();
      expect(controller.readingKey, 'a');
      expect(controller.isReading('a'), isTrue);
      expect(controller.isReading('b'), isFalse);
      expect(fake.spoken, ['Hello world']);

      fake.gate!.complete(HandsFreeSpeechOutcome.completed);
      await reading;
      expect(controller.readingKey, isNull);
      expect(unavailable, 0);
    });

    test('stop cancels playback and clears the reading reply', () async {
      final fake = _FakeSpeaker()..gated = true;
      final controller = NgReadAloud(speaker: fake);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;

      final reading = controller.read('a', 'one');
      await pumpEventQueue();
      expect(controller.readingKey, 'a');
      await controller.stop();
      expect(controller.readingKey, isNull);
      await reading;
      expect(unavailable, 0);
      expect(fake.stops, greaterThanOrEqualTo(1));
    });

    test('reading another reply stops the first', () async {
      final fake = _FakeSpeaker()..gated = true;
      final controller = NgReadAloud(speaker: fake);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;

      final first = controller.read('a', 'one');
      await pumpEventQueue();
      final second = controller.read('b', 'two');
      await pumpEventQueue();
      expect(controller.readingKey, 'b');
      expect(fake.spoken, ['one', 'two']);
      await first; // canceled by the switch, not a failure
      expect(unavailable, 0);
      fake.gate!.complete(HandsFreeSpeechOutcome.completed);
      await second;
      expect(controller.readingKey, isNull);
    });

    test('failed playback surfaces unavailable and clears state', () async {
      final fake = _FakeSpeaker()
        ..outcome = HandsFreeSpeechOutcome.failed;
      final controller = NgReadAloud(speaker: fake);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;

      await controller.read('a', 'text');
      expect(controller.readingKey, isNull);
      expect(unavailable, 1);
    });

    test('prepare failure is unavailable, not a crash', () async {
      final fake = _FakeSpeaker()..prepareResult = false;
      final controller = NgReadAloud(speaker: fake);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;

      await controller.read('a', 'text');
      expect(controller.readingKey, isNull);
      expect(fake.spoken, isEmpty);
      expect(unavailable, 1);
    });

    test('empty text is a no-op', () async {
      final fake = _FakeSpeaker();
      final controller = NgReadAloud(speaker: fake);
      addTearDown(controller.dispose);
      await controller.read('a', '   ');
      expect(fake.spoken, isEmpty);
      expect(controller.readingKey, isNull);
    });

    test('voice selection mirrors Classic prefs (language)', () async {
      SharedPreferences.setMockInitialValues({
        'voice_name': 'en-US',
        'voice_locale': 'en-US',
      });
      final controller = NgReadAloud(speaker: _FakeSpeaker());
      addTearDown(controller.dispose);
      await controller.read('a', 'hi');
      final language = ttsCalls.firstWhere(
        (c) => c.method == 'setLanguage',
      );
      expect(language.arguments, 'en-US');
      expect(
        ttsCalls.any(
          (c) => c.method == 'setSpeechRate' && c.arguments == 0.48,
        ),
        isTrue,
      );
    });

    test('voice selection mirrors Classic prefs (named voice)', () async {
      SharedPreferences.setMockInitialValues({
        'voice_name': 'Karen',
        'voice_locale': 'en-AU',
      });
      final controller = NgReadAloud(speaker: _FakeSpeaker());
      addTearDown(controller.dispose);
      await controller.read('a', 'hi');
      final voice = ttsCalls.firstWhere((c) => c.method == 'setVoice');
      expect(voice.arguments, {'name': 'Karen', 'locale': 'en-AU'});
    });

    test('dispose stops playback', () async {
      final fake = _FakeSpeaker()..gated = true;
      final controller = NgReadAloud(speaker: fake);
      final reading = controller.read('a', 'one');
      await pumpEventQueue();
      controller.dispose();
      expect(fake.stops, greaterThanOrEqualTo(1));
      await reading;
    });

    test('non-Android reads via the engine side channels', () async {
      final controller = NgReadAloud(android: false);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;

      final reading = controller.read('a', 'hello');
      await pumpEventQueue();
      expect(controller.readingKey, 'a');
      // flutter_tts sends a plain string off Android, a {text, focus} map on it.
      expect(
        ttsCalls.any((c) {
          if (c.method != 'speak') return false;
          final args = c.arguments;
          final text = args is Map ? args['text'] : args;
          return text == 'hello';
        }),
        isTrue,
      );
      await reading; // the native callback owns the terminal state
      expect(controller.readingKey, 'a');
      await emitTtsEvent('speak.onComplete');
      expect(controller.readingKey, isNull);
      expect(unavailable, 0);
    });

    test('a late cancel after stop is a no-op; error surfaces', () async {
      final controller = NgReadAloud(android: false);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;

      final reading = controller.read('a', 'one');
      await pumpEventQueue();
      await controller.stop();
      await reading;
      await emitTtsEvent('speak.onCancel');
      expect(controller.readingKey, isNull);
      expect(unavailable, 0);

      final second = controller.read('b', 'two');
      await pumpEventQueue();
      expect(controller.readingKey, 'b');
      await emitTtsEvent('speak.onError');
      await second;
      expect(controller.readingKey, isNull);
      expect(unavailable, 1);
    });
    test('a late cancel after the replacement speaks is swallowed once', () async {
      final controller = NgReadAloud(android: false);
      addTearDown(controller.dispose);
      final first = controller.read('a', 'one');
      await pumpEventQueue();
      await controller.stop();
      await first;
      final second = controller.read('b', 'two');
      await pumpEventQueue();
      expect(controller.readingKey, 'b');
      // The stopped utterance's cancel lands after 'b' already speaks.
      await emitTtsEvent('speak.onCancel');
      expect(controller.readingKey, 'b');
      await emitTtsEvent('speak.onComplete');
      await second;
      expect(controller.readingKey, isNull);
    });

    test('prepare failure recovers on the next read', () async {
      final fake = _FakeSpeaker()..prepareResult = false;
      final controller = NgReadAloud(speaker: fake);
      addTearDown(controller.dispose);
      var unavailable = 0;
      controller.onUnavailable = () => unavailable++;
      await controller.read('a', 'one');
      expect(unavailable, 1);
      expect(fake.spoken, isEmpty);
      fake.prepareResult = true;
      await controller.read('a', 'one');
      expect(fake.spoken, ['one']);
      expect(unavailable, 1);
      expect(controller.readingKey, isNull);
    });
  });

  group('NextGen transcript read aloud', () {
    late List<String> clipboard;

    setUp(() {
      clipboard = [];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String,
          );
        }
        return null;
      });
    });
    tearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    Future<
      (NgChatController, NextGenGateway, _FakeSpeaker, NgReadAloud)
    > pumpChat(
      WidgetTester tester, {
      required List<Map<String, dynamic>> history,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      final conn = SavedConnection(
        id: 'c1',
        label: 'Home',
        host: '10.0.0.5',
        port: 9119,
        apiKey: '',
        desktopGatewayUrl: 'http://10.0.0.5:9119',
        singleLogin: true,
        signInMethod: 'none',
      );
      final gateway = NextGenGateway(conn);
      final chat = NgChatController(gateway, sessionId: 'stored')
        ..runtimeId = 'stored';
      chat.debugApplyHistory(history);
      final fake = _FakeSpeaker()..gated = true;
      final controller = NgReadAloud(speaker: fake);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nextGenTheme(Brightness.light, NextGenLook.instance),
          home: NgScope(
            connManager: ConnectionManager(prefs),
            gateway: gateway,
            connections: [conn],
            switchTo: (_) async {},
            addGateway: () async {},
            signOut: (_) async {},
            reload: () async {},
            signInAgain: () async {},
            child: Scaffold(
              body: NgChatView(
                chat: chat,
                onOpenSidebar: () {},
                onNewChat: () {},
                readAloudFactory: () => controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return (chat, gateway, fake, controller);
    }

    Future<void> teardownChat(
      WidgetTester tester,
      NgChatController chat,
      NextGenGateway gateway,
    ) async {
      // Unmounting disposes the view-owned read-aloud controller.
      await tester.pumpWidget(const SizedBox());
      chat.dispose();
      gateway.dispose();
    }

    testWidgets('every completed assistant reply offers Read aloud', (
      tester,
    ) async {
      final (chat, gateway, fake, _) = await pumpChat(
        tester,
        history: [
          {'role': 'user', 'content': 'Q1'},
          {'role': 'assistant', 'content': 'A1'},
          {'role': 'user', 'content': 'Q2'},
          {'role': 'assistant', 'content': 'A2'},
        ],
      );
      expect(find.byTooltip('Read aloud'), findsNWidgets(2));
      expect(find.byTooltip('Stop'), findsNothing);
      expect(fake.spoken, isEmpty);
      await teardownChat(tester, chat, gateway);
    });

    testWidgets('tap reads the reply and shows Stop; Stop ends playback', (
      tester,
    ) async {
      final (chat, gateway, fake, controller) = await pumpChat(
        tester,
        history: [
          {'role': 'user', 'content': 'Q1'},
          {'role': 'assistant', 'content': 'A1'},
        ],
      );
      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pump();
      await tester.pump();
      expect(fake.spoken, ['A1']);
      expect(controller.readingKey, isNotNull);
      expect(find.byTooltip('Stop'), findsOneWidget);
      expect(find.byTooltip('Read aloud'), findsNothing);

      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
      await tester.pump();
      expect(controller.readingKey, isNull);
      expect(find.byTooltip('Read aloud'), findsOneWidget);
      expect(find.byTooltip('Stop'), findsNothing);
      await teardownChat(tester, chat, gateway);
    });

    testWidgets('reading switches between replies, one Stop at a time', (
      tester,
    ) async {
      final (chat, gateway, fake, controller) = await pumpChat(
        tester,
        history: [
          {'role': 'user', 'content': 'Q1'},
          {'role': 'assistant', 'content': 'A1'},
          {'role': 'user', 'content': 'Q2'},
          {'role': 'assistant', 'content': 'A2'},
        ],
      );
      await tester.tap(find.byTooltip('Read aloud').first);
      await tester.pump();
      await tester.pump();
      final firstText = fake.spoken.single;
      expect(find.byTooltip('Stop'), findsOneWidget);

      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pump();
      await tester.pump();
      expect(fake.spoken, hasLength(2));
      expect(fake.spoken[1], isNot(firstText));
      expect(controller.readingKey, isNotNull);
      expect(find.byTooltip('Stop'), findsOneWidget);
      expect(find.byTooltip('Read aloud'), findsOneWidget);

      fake.gate!.complete(HandsFreeSpeechOutcome.completed);
      await tester.pump();
      await tester.pump();
      expect(controller.readingKey, isNull);
      expect(find.byTooltip('Read aloud'), findsNWidgets(2));
      await teardownChat(tester, chat, gateway);
    });

    testWidgets('a streaming reply has no read aloud until it is final', (
      tester,
    ) async {
      final (chat, gateway, fake, _) = await pumpChat(tester, history: []);
      gateway.debugEmit(
        StreamEvent(type: 'message.start', data: const {}, sessionId: 'stored'),
      );
      gateway.debugEmit(
        StreamEvent(
          type: 'message.delta',
          data: const {'text': 'live reply'},
          sessionId: 'stored',
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final live = chat.items.whereType<NgAssistantItem>().single;
      expect(live.open, isTrue);
      expect(find.byTooltip('Read aloud'), findsNothing);

      gateway.debugEmit(
        StreamEvent(type: 'turn.end', data: const {}, sessionId: 'stored'),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byTooltip('Read aloud'), findsOneWidget);
      expect(fake.spoken, isEmpty);
      await teardownChat(tester, chat, gateway);
    });

    testWidgets('code blocks show a labelled one-tap Copy of just the block', (
      tester,
    ) async {
      final (chat, gateway, _, _) = await pumpChat(
        tester,
        history: [
          {
            'role': 'assistant',
            'content':
                'Two examples:\n\n```dart\nfinal answer = 42;\n```\n\n'
                '```text\nsecond block\n```',
          },
        ],
      );
      expect(find.byKey(const Key('markdown-code-block')), findsNWidgets(2));
      expect(find.text('Copy code'), findsNWidgets(2));

      await tester.tap(
        find.byKey(const Key('markdown-code-block-copy')).first,
      );
      await tester.pump();
      expect(clipboard, ['final answer = 42;\n']);

      await tester.tap(
        find.byKey(const Key('markdown-code-block-copy')).last,
      );
      await tester.pump();
      expect(clipboard, ['final answer = 42;\n', 'second block\n']);
      // The whole-reply Copy action is still present alongside Read aloud.
      expect(find.byTooltip('Copy'), findsOneWidget);
      expect(find.byTooltip('Read aloud'), findsOneWidget);
      await teardownChat(tester, chat, gateway);
    });

    testWidgets('switching chats stops playback', (tester) async {
      final (chat, gateway, fake, controller) = await pumpChat(
        tester,
        history: [
          {'role': 'user', 'content': 'Q1'},
          {'role': 'assistant', 'content': 'A1'},
        ],
      );
      await tester.tap(find.byTooltip('Read aloud'));
      await tester.pump();
      await tester.pump();
      expect(controller.readingKey, isNotNull);
      final stopsBefore = fake.stops;

      final prefs = await SharedPreferences.getInstance();
      final conn2 = SavedConnection(
        id: 'c2',
        label: 'Work',
        host: '10.0.0.6',
        port: 9119,
        apiKey: '',
        desktopGatewayUrl: 'http://10.0.0.6:9119',
        singleLogin: true,
        signInMethod: 'none',
      );
      final gateway2 = NextGenGateway(conn2);
      final chat2 = NgChatController(gateway2, sessionId: 'stored2')
        ..runtimeId = 'stored2';
      chat2.debugApplyHistory([
        {'role': 'assistant', 'content': 'Other chat'},
      ]);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nextGenTheme(Brightness.light, NextGenLook.instance),
          home: NgScope(
            connManager: ConnectionManager(prefs),
            gateway: gateway2,
            connections: [conn2],
            switchTo: (_) async {},
            addGateway: () async {},
            signOut: (_) async {},
            reload: () async {},
            signInAgain: () async {},
            child: Scaffold(
              body: NgChatView(
                chat: chat2,
                onOpenSidebar: () {},
                onNewChat: () {},
                readAloudFactory: () => controller,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.readingKey, isNull);
      expect(fake.stops, greaterThan(stopsBefore));
      await tester.pumpWidget(const SizedBox());
      chat.dispose();
      gateway.dispose();
      chat2.dispose();
      gateway2.dispose();
    });
  });

  testWidgets('labelled copy survives narrow width and large text', (
    tester,
  ) async {
    final writes = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add(
          (call.arguments as Map<Object?, Object?>)['text'] as String,
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
            child: const Center(
              child: SizedBox(
                width: 280,
                child: MarkdownCodeBlock(
                  code: 'x = 1\n',
                  language: 'python',
                  showCopyLabel: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('markdown-code-block-copy')));
    await tester.pump();
    expect(writes, ['x = 1\n']);
  });

  testWidgets('Classic code blocks keep the icon-only copy control', (
    tester,
  ) async {
    final writes = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        writes.add(
          (call.arguments as Map<Object?, Object?>)['text'] as String,
        );
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MarkdownCodeBlock(code: 'plain block\n', language: 'text'),
        ),
      ),
    );
    expect(find.text('Copy code'), findsNothing);
    expect(find.byTooltip('Copy code'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy code'));
    await tester.pump();
    expect(writes, ['plain block\n']);
  });
}
