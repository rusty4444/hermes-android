import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/widgets/voice_composer_controls.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/attachment_draft_tile.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/completed_stock_turn.dart';
import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

const _composer = Key('chat-message-composer');
final _longText = 'pasted line\r\n' * 251;

class _PasteFiles extends AttachmentDraftService {
  Completer<void>? gate;
  Completer<void>? removeGate;
  bool fail = false;
  final texts = <String, String>{};
  final removed = <String>[];
  int calls = 0;

  @override
  Future<AttachmentDraft> preparePastedText({
    required String text,
    required Iterable<AttachmentDraft> existingDrafts,
  }) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('test write failed');
    final id = 'paste-$calls';
    texts[id] = text;
    final draft = AttachmentDraft(
      id: id,
      cachedPath: '/fixture/$id.txt',
      name: existingDrafts.isEmpty
          ? 'paste.txt'
          : 'paste-${existingDrafts.length + 1}.txt',
      byteLength: utf8.encode(text).length,
      mediaType: 'text/plain',
      kind: AttachmentDraftKind.genericFile,
    );
    validateRemoteDrafts([...existingDrafts, draft]);
    return draft;
  }

  @override
  Future<String> readDataUrl(AttachmentDraft draft) async =>
      'data:text/plain;base64,${base64Encode(utf8.encode(texts[draft.id]!))}';

  @override
  Future<void> removeCachedFile(AttachmentDraft draft) async {
    removed.add(draft.id);
    await removeGate?.future;
  }
}

Future<void> _pumpChat(
  WidgetTester tester,
  _PasteFiles files, {
  bool remote = true,
  String? initialText,
  TestRemoteAttachmentUpload? upload,
  TestRemotePromptSubmit? submit,
  GatewayTurnApplicationController? controller,
  FakeVoiceComposerAdapter? voice,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'paste-test',
          label: 'Fixture',
          host: 'fixture.invalid',
          port: 8642,
          apiKey: 'fixture',
        ),
        session: const Session(
          id: 'paste-session',
          title: 'Paste chat',
          model: 'fixture',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        initialComposerText: initialText,
        turnApplicationController: controller,
        testApiClient: ApiClient(
          baseUrl: 'http://fixture.invalid',
          apiKey: 'fixture',
          httpClient: MockClient(
            (_) async => http.Response('{"data":[]}', 200),
          ),
        ),
        testVoiceComposerAdapter: voice ?? FakeVoiceComposerAdapter(),
        testAttachmentDraftService: files,
        testRemotePromptSubmit: remote
            ? completedStockTurn(
                submit ??
                    ({
                      required sessionId,
                      required text,
                      required onEvent,
                      required onSent,
                    }) async {
                      onSent();
                    },
              )
            : null,
        testRemoteAttachmentUpload:
            upload ??
            ({required draft, required dataUrl}) async =>
                AttachmentUploadReceipt(
                  refText: '@file:/attachments/${draft.name}',
                ),
      ),
    ),
  );
  await pumpChatUpdates(tester);
}

TextEditingController _controller(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composer).last).controller!;

Future<void> _paste(WidgetTester tester, String text) async {
  await tester.showKeyboard(find.byKey(_composer).last);
  await Clipboard.setData(ClipboardData(text: text));
  await tester
      .state<EditableTextState>(find.byType(EditableText).last)
      .pasteText(SelectionChangedCause.toolbar);
  await tester.pump();
}

Future<String?> _savedDraft(WidgetTester tester) async {
  final observer =
      tester.state(find.byType(ChatScreen)) as WidgetsBindingObserver;
  observer.didChangeAppLifecycleState(AppLifecycleState.paused);
  final saved = await ComposerDraftStore.read(
    connectionId: 'paste-test',
    sessionId: 'paste-session',
  );
  observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
  return saved;
}

Future<NavigatorState> _pushSibling(
  WidgetTester tester,
  GatewayTurnApplicationController owner,
) async {
  final original = tester.widget<ChatScreen>(find.byType(ChatScreen));
  final navigator = Navigator.of(tester.element(find.byType(ChatScreen)));
  unawaited(
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          connection: original.connection,
          session: original.session,
          turnApplicationController: owner,
          testApiClient: ApiClient(
            baseUrl: 'http://fixture.invalid',
            apiKey: 'fixture',
            httpClient: MockClient(
              (_) async => http.Response('{"data":[]}', 200),
            ),
          ),
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          testRemotePromptSubmit: original.testRemotePromptSubmit,
          testAttachmentDraftService: _PasteFiles(),
        ),
      ),
    ),
  );
  await pumpChatUpdates(tester);
  return navigator;
}

void main() {
  setUp(mockChatImageRecovery);
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    String? clipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboard};
          }
          if (call.method == 'Clipboard.hasStrings') {
            return {'value': clipboard?.isNotEmpty == true};
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  testWidgets(
    'toolbar paste stages exact text, keeps instructions and uploads before one submit',
    (tester) async {
      final files = _PasteFiles();
      final operations = <String>[];
      await _pumpChat(
        tester,
        files,
        initialText: 'Explain  please',
        upload: ({required draft, required dataUrl}) async {
          operations.add('upload:${draft.name}');
          expectSync(
            utf8.decode(base64Decode(dataUrl.split(',').last)),
            _longText,
          );
          expectSync(draft.mediaType, 'text/plain');
          return const AttachmentUploadReceipt(
            refText: '@file:/server/paste-7.txt',
          );
        },
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              operations.add(text);
            },
      );
      _controller(tester).selection = const TextSelection.collapsed(offset: 8);
      await _paste(tester, _longText);
      await pumpChatUpdates(tester);
      expect(files.texts.values.single, _longText);
      expect(find.text('paste.txt'), findsOneWidget);
      expect(_controller(tester).text, 'Explain  please');
      expect(operations, isEmpty);
      await tester.tap(find.byTooltip('Send'));
      await pumpChatUpdates(tester);
      expect(operations, [
        'upload:paste.txt',
        'Explain  please\n\n@file:/server/paste-7.txt',
      ]);
      expect(await _savedDraft(tester), isNull);
    },
  );

  testWidgets('short and exactly 3000-character pastes remain inline', (
    tester,
  ) async {
    final files = _PasteFiles();
    await _pumpChat(tester, files);
    await _paste(tester, 'x' * 3000);
    await pumpChatUpdates(tester);
    expect(files.calls, 0);
    expect(_controller(tester).text, 'x' * 3000);
    expect(find.byType(AttachmentDraftTile), findsNothing);
  });

  testWidgets('repeated large pastes become separate removable attachments', (
    tester,
  ) async {
    final files = _PasteFiles();
    await _pumpChat(tester, files);
    await _paste(tester, _longText);
    await pumpChatUpdates(tester);
    await _paste(tester, 'other line\n' * 300);
    await pumpChatUpdates(tester);
    expect(find.text('paste.txt'), findsOneWidget);
    expect(find.text('paste-2.txt'), findsOneWidget);
    expect(_controller(tester).text, isEmpty);
    await tester.tap(find.byTooltip('Remove attachment').first);
    await pumpChatUpdates(tester);
    expect(find.text('paste.txt'), findsNothing);
    expect((await _savedDraft(tester))!, isNot(contains(_longText)));
    expect(files.removed, contains('paste-1'));
  });

  testWidgets(
    'preparation failure keeps all pasted text inline and reports fallback',
    (tester) async {
      final files = _PasteFiles()..fail = true;
      await _pumpChat(tester, files, initialText: 'Notes: ');
      await _paste(tester, _longText);
      await pumpChatUpdates(tester);
      expect(_controller(tester).text, 'Notes: $_longText');
      expect(find.byType(AttachmentDraftTile), findsNothing);
      expect(
        find.text(
          'Could not attach the paste. The text was kept in the message.',
        ),
        findsOneWidget,
      );
      expect(await _savedDraft(tester), 'Notes: $_longText');
    },
  );

  for (final newer in ['Newer draft', '']) {
    testWidgets('a newer edit wins while cache preparation waits: "$newer"', (
      tester,
    ) async {
      final files = _PasteFiles()..gate = Completer<void>();
      await _pumpChat(tester, files);
      final oldSend = tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed!;
      await _paste(tester, _longText);
      expect(_controller(tester).text, _longText);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed,
        isNull,
      );
      oldSend();
      await tester.enterText(find.byKey(_composer).last, newer);
      files.gate!.complete();
      await pumpChatUpdates(tester);
      expect(_controller(tester).text, newer);
      expect(find.byType(AttachmentDraftTile), findsNothing);
      expect(files.removed, ['paste-1']);
      expect(await _savedDraft(tester) ?? '', newer);
    });
  }

  testWidgets(
    'leaving during preparation retains inline text and cleans late file',
    (tester) async {
      final files = _PasteFiles()..gate = Completer<void>();
      await _pumpChat(tester, files);
      await _paste(tester, _longText);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      files.gate!.complete();
      await tester.pump();
      expect(files.removed, ['paste-1']);
      await _pumpChat(tester, _PasteFiles());
      expect(_controller(tester).text, _longText);
    },
  );

  testWidgets(
    'unsent attachment content is recoverable inline on chat reopen',
    (tester) async {
      final files = _PasteFiles();
      await _pumpChat(tester, files, initialText: 'Explain this');
      await _paste(tester, _longText);
      await pumpChatUpdates(tester);
      await tester.enterText(
        find.byKey(_composer).last,
        'Keep this instruction',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpChat(tester, _PasteFiles());
      expect(_controller(tester).text, 'Keep this instruction\n\n$_longText');
      expect(find.byType(AttachmentDraftTile), findsNothing);
    },
  );

  testWidgets(
    'Android keyboard editing update replaces only the selected text',
    (tester) async {
      final files = _PasteFiles();
      await _pumpChat(tester, files, initialText: 'Before replace after');
      await tester.showKeyboard(find.byKey(_composer).last);
      _controller(tester).selection = const TextSelection(
        baseOffset: 14,
        extentOffset: 7,
      );
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: 'Before $_longText after',
          selection: TextSelection.collapsed(offset: 7 + _longText.length),
        ),
      );
      await pumpChatUpdates(tester);
      expect(files.texts.values.single, _longText);
      expect(_controller(tester).text, 'Before  after');
      expect(find.text('paste.txt'), findsOneWidget);
    },
  );

  testWidgets('retyping identical text revokes an older conversion', (
    tester,
  ) async {
    final files = _PasteFiles()..gate = Completer<void>();
    await _pumpChat(tester, files);
    await _paste(tester, _longText);
    await tester.enterText(find.byKey(_composer).last, 'Intermediate edit');
    await tester.enterText(find.byKey(_composer).last, _longText);
    files.gate!.complete();
    await pumpChatUpdates(tester);
    expect(_controller(tester).text, _longText);
    expect(find.byType(AttachmentDraftTile), findsNothing);
    expect(files.removed, ['paste-1']);
  });

  testWidgets('failed upload retains the paste and does not submit a prompt', (
    tester,
  ) async {
    final files = _PasteFiles();
    var submits = 0;
    await _pumpChat(
      tester,
      files,
      upload: ({required draft, required dataUrl}) async {
        throw StateError('test upload failed');
      },
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            submits++;
          },
    );
    await _paste(tester, _longText);
    await pumpChatUpdates(tester);
    await tester.tap(find.byTooltip('Send'));
    await pumpChatUpdates(tester);
    expect(submits, 0);
    expect(files.removed, isEmpty);
    expect(find.text('paste.txt'), findsOneWidget);
    expect(await _savedDraft(tester), _longText);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _pumpChat(tester, _PasteFiles());
    expect(_controller(tester).text, _longText);
  });

  testWidgets('leaving during upload preserves the unsent paste inline', (
    tester,
  ) async {
    final files = _PasteFiles();
    final upload = Completer<AttachmentUploadReceipt>();
    var submits = 0;
    await _pumpChat(
      tester,
      files,
      upload: ({required draft, required dataUrl}) => upload.future,
      submit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            submits++;
          },
    );
    await _paste(tester, _longText);
    await pumpChatUpdates(tester);
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    upload.complete(
      const AttachmentUploadReceipt(refText: '@file:/server/paste.txt'),
    );
    await tester.pump();
    expect(submits, 0);
    await _pumpChat(tester, _PasteFiles());
    expect(_controller(tester).text, _longText);
  });

  for (final instruction in ['', 'Explain this']) {
    testWidgets(
      'detached pre-wire rejection recovers paste with instruction length ${instruction.length}',
      (tester) async {
        final owner = GatewayTurnApplicationController();
        addTearDown(owner.close);
        final gate = Completer<void>();
        var attempts = 0;
        await _pumpChat(
          tester,
          _PasteFiles(),
          controller: owner,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) {
                attempts++;
                return gate.future;
              },
        );
        if (instruction.isNotEmpty) {
          await tester.enterText(find.byKey(_composer).last, instruction);
        }
        await _paste(tester, _longText);
        await pumpChatUpdates(tester);
        await tester.tap(find.byTooltip('Send'));
        await pumpChatUpdates(tester);
        expect(attempts, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gate.completeError(StateError('rejected before wire emission'));
        await pumpChatUpdates(tester);
        final expected = [
          instruction,
          _longText,
        ].where((part) => part.isNotEmpty).join('\n\n');
        expect(
          await ComposerDraftStore.read(
            connectionId: 'paste-test',
            sessionId: 'paste-session',
          ),
          expected,
        );
        await _pumpChat(tester, _PasteFiles(), controller: owner);
        expect(_controller(tester).text, expected);
        expect(find.byType(AttachmentDraftTile), findsNothing);
        expect(attempts, 1);
      },
    );
  }

  testWidgets(
    'mounted pre-wire rejection restores paste inline without a duplicate attachment',
    (tester) async {
      final gate = Completer<void>();
      await _pumpChat(
        tester,
        _PasteFiles(),
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) => gate.future,
      );
      await _paste(tester, _longText);
      await pumpChatUpdates(tester);
      await tester.tap(find.byTooltip('Send'));
      await pumpChatUpdates(tester);
      gate.completeError(StateError('not emitted'));
      await pumpChatUpdates(tester);
      expect(_controller(tester).text, _longText);
      expect(find.byType(AttachmentDraftTile), findsNothing);
      expect(await _savedDraft(tester), _longText);
    },
  );

  for (final newer in ['New sibling draft', '']) {
    testWidgets(
      'held removal cannot reclaim a sibling writer (clear=${newer.isEmpty})',
      (tester) async {
        final owner = GatewayTurnApplicationController();
        addTearDown(owner.close);
        final files = _PasteFiles();
        await _pumpChat(
          tester,
          files,
          controller: owner,
          initialText: 'Old route instructions',
        );
        await _paste(tester, _longText);
        await pumpChatUpdates(tester);
        files.removeGate = Completer<void>();
        tester
            .widget<AttachmentDraftTile>(find.byType(AttachmentDraftTile))
            .onRemove();
        await tester.pump();
        final navigator = await _pushSibling(tester, owner);
        expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));
        await tester.enterText(
          find.byKey(_composer).last,
          'Intermediate sibling edit',
        );
        await tester.enterText(find.byKey(_composer).last, newer);
        files.removeGate!.complete();
        await pumpChatUpdates(tester);
        expect(_controller(tester).text, newer);
        navigator.pop();
        await pumpChatUpdates(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          await ComposerDraftStore.read(
                connectionId: 'paste-test',
                sessionId: 'paste-session',
              ) ??
              '',
          newer,
        );
        await _pumpChat(tester, _PasteFiles(), controller: owner);
        expect(_controller(tester).text, newer);
      },
    );
  }

  testWidgets('voice start is unavailable throughout held paste preparation', (
    tester,
  ) async {
    final voice = FakeVoiceComposerAdapter();
    final files = _PasteFiles()..gate = Completer<void>();
    await _pumpChat(tester, files, voice: voice);
    final staleStart = tester
        .widget<VoiceComposerStartButton>(find.byType(VoiceComposerStartButton))
        .onPressed;
    await _paste(tester, _longText);
    expect(
      tester
          .widget<VoiceComposerStartButton>(
            find.byType(VoiceComposerStartButton),
          )
          .enabled,
      isFalse,
    );
    staleStart();
    await tester.pump();
    expect(voice.listenCount, 0);
    files.gate!.complete();
    await pumpChatUpdates(tester);
    expect(_controller(tester).text, '');
    expect(find.text('paste.txt'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Start voice input'));
    await tester.pump();
    await tester.tap(find.byKey(VoiceComposerIndicator.cancelKey));
    await pumpChatUpdates(tester);
    expect(_controller(tester).text, '');
    expect(find.text('paste.txt'), findsOneWidget);
  });

  for (final newer in ['New draft after send', '']) {
    testWidgets(
      'detached rejection cannot resurrect paste over a newer draft (clear=${newer.isEmpty})',
      (tester) async {
        final owner = GatewayTurnApplicationController();
        addTearDown(owner.close);
        final gate = Completer<void>();
        await _pumpChat(
          tester,
          _PasteFiles(),
          controller: owner,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) => gate.future,
        );
        await _paste(tester, _longText);
        await pumpChatUpdates(tester);
        await tester.tap(find.byTooltip('Send'));
        await pumpChatUpdates(tester);
        await tester.enterText(find.byKey(_composer).last, 'Intermediate edit');
        await tester.enterText(find.byKey(_composer).last, newer);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gate.completeError(StateError('not emitted'));
        await pumpChatUpdates(tester);
        expect(
          await ComposerDraftStore.read(
                connectionId: 'paste-test',
                sessionId: 'paste-session',
              ) ??
              '',
          newer,
        );
        await _pumpChat(tester, _PasteFiles(), controller: owner);
        expect(_controller(tester).text, newer);
      },
    );

    testWidgets(
      'pre-wire rejection respects a still-mounted sibling writer (clear=${newer.isEmpty})',
      (tester) async {
        final owner = GatewayTurnApplicationController();
        addTearDown(owner.close);
        final gate = Completer<void>();
        await _pumpChat(
          tester,
          _PasteFiles(),
          controller: owner,
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) => gate.future,
        );
        await _paste(tester, _longText);
        await pumpChatUpdates(tester);
        await tester.tap(find.byTooltip('Send'));
        await pumpChatUpdates(tester);
        final navigator = await _pushSibling(tester, owner);
        expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));
        await tester.enterText(
          find.byKey(_composer).last,
          'Intermediate sibling edit',
        );
        await tester.enterText(find.byKey(_composer).last, newer);
        gate.completeError(StateError('not emitted'));
        await pumpChatUpdates(tester);
        expect(_controller(tester).text, newer);
        navigator.pop();
        await pumpChatUpdates(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          await ComposerDraftStore.read(
                connectionId: 'paste-test',
                sessionId: 'paste-session',
              ) ??
              '',
          newer,
        );
      },
    );
  }

  testWidgets(
    'post-wire failure never restores or automatically resubmits a paste',
    (tester) async {
      final gate = Completer<void>();
      var submits = 0;
      await _pumpChat(
        tester,
        _PasteFiles(),
        submit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              submits++;
              onSent();
              return gate.future;
            },
      );
      await _paste(tester, _longText);
      await pumpChatUpdates(tester);
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      gate.completeError(StateError('socket closed after send'));
      await pumpChatUpdates(tester);
      expect(submits, 1);
      expect(_controller(tester).text, '');
      expect(find.byType(AttachmentDraftTile), findsNothing);
      expect(await _savedDraft(tester), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpChatUpdates(tester);
      expect(submits, 1);
    },
  );

  for (final whitespace in [' ' * 3001, '\r\n' * 1501]) {
    testWidgets(
      'whitespace-only paste survives durable reopen (${whitespace.codeUnitAt(0)})',
      (tester) async {
        await _pumpChat(tester, _PasteFiles());
        await _paste(tester, whitespace);
        await pumpChatUpdates(tester);
        expect(find.text('paste.txt'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          await ComposerDraftStore.read(
            connectionId: 'paste-test',
            sessionId: 'paste-session',
          ),
          whitespace,
        );
        await _pumpChat(tester, _PasteFiles());
        expect(_controller(tester).text, whitespace);
        await tester.enterText(find.byKey(_composer).last, '');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(
          await ComposerDraftStore.read(
            connectionId: 'paste-test',
            sessionId: 'paste-session',
          ),
          isNull,
        );
      },
    );
  }

  testWidgets('REST and programmatic draft hydration never stage a paste', (
    tester,
  ) async {
    final rest = _PasteFiles();
    await _pumpChat(tester, rest, remote: false);
    await _paste(tester, _longText);
    await pumpChatUpdates(tester);
    expect(rest.calls, 0);
    expect(_controller(tester).text, _longText);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final remote = _PasteFiles();
    await _pumpChat(tester, remote);
    expect(_controller(tester).text, _longText);
    expect(remote.calls, 0);
  });
}
