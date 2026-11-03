import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';
import 'support/completed_stock_turn.dart';

const _composerKey = Key('chat-message-composer');

class _AttachmentFixture extends AttachmentDraftService {
  _AttachmentFixture({this.readResult});

  final Future<String>? readResult;

  @override
  Future<String> readDataUrl(AttachmentDraft draft) =>
      readResult ?? Future.value('data:text/plain;base64,Zml4dHVyZQ==');

  @override
  Future<void> removeCachedFile(AttachmentDraft draft) async {}
}

Future<void> _pumpChat(
  WidgetTester tester, {
  TestRemotePromptSubmit? remoteSubmit,
  Future<void> Function(String, String)? ensureProject,
  TestRemoteAttachmentUpload? upload,
  List<AttachmentDraft> attachments = const [],
  http.Client? httpClient,
  AttachmentDraftService? attachmentService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'composer-interaction',
          label: 'Fixture',
          host: 'fixture.invalid',
          port: 8642,
          apiKey: 'fixture-key',
        ),
        session: Session(
          id: 'composer-session',
          title: 'Chat',
          model: 'fixture',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
          isLocalDraft: ensureProject != null,
        ),
        projectWorkingDirectory: ensureProject == null ? null : '/project',
        initialAttachmentDrafts: attachments,
        testAttachmentDraftService: attachmentService ?? _AttachmentFixture(),
        testApiClient: ApiClient(
          baseUrl: 'http://fixture.invalid',
          apiKey: 'fixture-key',
          httpClient:
              httpClient ??
              MockClient((_) async => http.Response('{"data":[]}', 200)),
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testRemotePromptSubmit: completedStockTurn(remoteSubmit),
        testLegacyProjectSessionEnsure: ensureProject,
        testRemoteAttachmentUpload: upload,
      ),
    ),
  );
  await pumpChatUpdates(tester);
}

String _draft(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composerKey)).controller!.text;

void _expectEditable(WidgetTester tester) {
  final field = tester.widget<TextField>(find.byKey(_composerKey));
  expect(field.enabled, isNot(false));
  expect(field.readOnly, isFalse);
}

void main() {
  setUp(mockChatImageRecovery);
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  testWidgets('Enter inserts a newline; only the send button submits', (
    tester,
  ) async {
    final submitted = <String>[];
    await _pumpChat(
      tester,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            onSent();
            submitted.add(text);
          },
    );
    final composer = find.byKey(_composerKey);
    await tester.enterText(composer, 'First paragraph');
    expect(
      tester.widget<TextField>(composer).textInputAction,
      TextInputAction.newline,
    );
    expect(
      tester.testTextInput.setClientArgs!['inputAction'],
      'TextInputAction.newline',
    );
    // Android's IME inserts line breaks through editing updates, not raw keys.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'First paragraph\n',
        selection: TextSelection.collapsed(offset: 16),
      ),
    );
    await tester.pump();
    expect(_draft(tester), 'First paragraph\n');
    await tester.enterText(composer, 'First paragraph\nSecond paragraph');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();
    expect(submitted, isEmpty);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('Send'));
    await pumpChatUpdates(tester);
    expect(submitted, ['First paragraph\nSecond paragraph']);
    expect(_draft(tester), isEmpty);
  });

  testWidgets('typing during project setup survives submit and completion', (
    tester,
  ) async {
    final bind = Completer<void>();
    final turn = Completer<void>();
    final submitted = <String>[];
    await _pumpChat(
      tester,
      ensureProject: (_, _) => bind.future,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            onSent();
            submitted.add(text);
            await turn.future;
          },
    );
    await tester.enterText(find.byKey(_composerKey), 'Original prompt');
    // Keep the original callback to probe duplicate invocation while setup waits.
    final send = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
        .onPressed!;
    send();
    send();
    await tester.pump();
    expect(_draft(tester), isEmpty);
    _expectEditable(tester);
    await tester.enterText(
      find.byKey(_composerKey),
      'Follow-up\nkeep this draft',
    );
    bind.complete();
    await tester.pump();
    await tester.pump();
    expect(submitted, ['Original prompt']);
    expect(_draft(tester), 'Follow-up\nkeep this draft');
    _expectEditable(tester);
    expect(find.byTooltip('Stop response'), findsOneWidget);
    await tester.enterText(find.byKey(_composerKey), 'Updated follow-up');
    turn.complete();
    await pumpChatUpdates(tester);
    expect(_draft(tester), 'Updated follow-up');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      await ComposerDraftStore.read(
        connectionId: 'composer-interaction',
        sessionId: 'composer-session',
      ),
      'Updated follow-up',
    );
  });

  testWidgets('failed setup preserves newer typing', (tester) async {
    final bind = Completer<void>();
    var submits = 0;
    await _pumpChat(
      tester,
      ensureProject: (_, _) => bind.future,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) async {
            submits++;
          },
    );
    await tester.enterText(find.byKey(_composerKey), 'Original prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(_draft(tester), isEmpty);
    await tester.enterText(find.byKey(_composerKey), 'Newer note');
    bind.completeError(StateError('binding failed'));
    await pumpChatUpdates(tester);
    expect(submits, 0);
    expect(_draft(tester), 'Newer note');
    expect(
      await ComposerDraftStore.read(
        connectionId: 'composer-interaction',
        sessionId: 'composer-session',
      ),
      'Newer note',
    );
    _expectEditable(tester);
  });

  testWidgets('a late pre-wire rejection preserves the new draft', (
    tester,
  ) async {
    final turn = Completer<void>();
    await _pumpChat(
      tester,
      remoteSubmit:
          ({
            required sessionId,
            required text,
            required onEvent,
            required onSent,
          }) => turn.future,
    );
    await tester.enterText(find.byKey(_composerKey), 'Rejected prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    _expectEditable(tester);
    await tester.enterText(find.byKey(_composerKey), 'New draft');
    turn.completeError(StateError('not sent'));
    await pumpChatUpdates(tester);
    expect(_draft(tester), 'New draft');
  });

  testWidgets(
    'accepted wire send failure does not restore the original prompt',
    (tester) async {
      final turn = Completer<void>();
      await _pumpChat(
        tester,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) {
              onSent();
              return turn.future;
            },
      );
      await tester.enterText(find.byKey(_composerKey), 'Accepted prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      _expectEditable(tester);
      await tester.enterText(find.byKey(_composerKey), 'Keep new draft');
      turn.completeError(StateError('socket closed'));
      await tester.pump();
      await tester.pump();
      expect(_draft(tester), 'Keep new draft');
    },
  );

  for (final newerDraft in <String?>[null, 'New draft', '']) {
    testWidgets('leaving during setup preserves draft "$newerDraft"', (
      tester,
    ) async {
      final bind = Completer<void>();
      var submits = 0;
      await _pumpChat(
        tester,
        ensureProject: (_, _) => bind.future,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              submits++;
            },
      );
      await tester.enterText(find.byKey(_composerKey), 'Unsent prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(_draft(tester), isEmpty);
      if (newerDraft != null) {
        await tester.enterText(find.byKey(_composerKey), 'Intermediate edit');
        await tester.enterText(find.byKey(_composerKey), newerDraft);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      bind.complete();
      await tester.pump();
      expect(submits, 0);
      await _pumpChat(tester);
      expect(_draft(tester), newerDraft ?? 'Unsent prompt');
    });
  }

  testWidgets('leaving during REST image preparation keeps the unsent prompt', (
    tester,
  ) async {
    final read = Completer<String>();
    var submits = 0;
    await _pumpChat(
      tester,
      attachmentService: _AttachmentFixture(readResult: read.future),
      attachments: [
        AttachmentDraft(
          id: 'image',
          cachedPath: '/fixture/image.png',
          name: 'image.png',
          byteLength: 7,
          mediaType: 'image/png',
          kind: AttachmentDraftKind.image,
          sanitized: true,
        ),
      ],
      httpClient: MockClient((request) async {
        if (request.method == 'POST') submits++;
        return http.Response('{"data":[]}', 200);
      }),
    );
    await tester.enterText(find.byKey(_composerKey), 'Unsent image prompt');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    read.complete('data:image/png;base64,Zml4dHVyZQ==');
    await tester.pump();
    expect(submits, 0);
    await _pumpChat(tester);
    expect(_draft(tester), 'Unsent image prompt');
  });

  for (final newerDraft in ['', 'Rejected prompt']) {
    testWidgets('rejection respects intervening edits: "$newerDraft"', (
      tester,
    ) async {
      final turn = Completer<void>();
      await _pumpChat(
        tester,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) => turn.future,
      );
      await tester.enterText(find.byKey(_composerKey), 'Rejected prompt');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      await tester.enterText(find.byKey(_composerKey), 'Intermediate edit');
      await tester.enterText(find.byKey(_composerKey), newerDraft);
      turn.completeError(StateError('not sent'));
      await pumpChatUpdates(tester);
      expect(_draft(tester), newerDraft);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _pumpChat(tester);
      expect(_draft(tester), newerDraft);
    });
  }

  for (final rejected in [false, true]) {
    testWidgets(
      'REST image preparation preserves a newer draft (rejected=$rejected)',
      (tester) async {
        final read = Completer<String>();
        var submits = 0;
        await _pumpChat(
          tester,
          attachmentService: _AttachmentFixture(readResult: read.future),
          attachments: [
            AttachmentDraft(
              id: 'image',
              cachedPath: '/fixture/image.png',
              name: 'image.png',
              byteLength: 7,
              mediaType: 'image/png',
              kind: AttachmentDraftKind.image,
              sanitized: true,
            ),
          ],
          httpClient: MockClient((request) async {
            if (request.method == 'POST') {
              submits++;
              return http.Response(
                'data: {"choices":[{"delta":{"content":"Image reply"}}]}\n\n'
                'data: [DONE]\n\n',
                200,
              );
            }
            return http.Response('{"data":[]}', 200);
          }),
        );
        await tester.enterText(find.byKey(_composerKey), 'Image prompt');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        expect(_draft(tester), isEmpty);
        _expectEditable(tester);
        await tester.enterText(find.byKey(_composerKey), 'New image draft');
        if (rejected) {
          read.completeError(StateError('image read failed'));
        } else {
          read.complete('data:image/png;base64,Zml4dHVyZQ==');
        }
        await pumpChatUpdates(tester);
        expect(submits, rejected ? 0 : 1);
        expect(_draft(tester), 'New image draft');
        if (rejected) expect(find.text('image.png'), findsOneWidget);
      },
    );

    testWidgets(
      'typing during upload survives its result (rejected=$rejected)',
      (tester) async {
        final upload = Completer<AttachmentUploadReceipt>();
        final submitted = <String>[];
        final attachment = AttachmentDraft(
          id: 'file',
          cachedPath: '/fixture/file.txt',
          name: 'file.txt',
          byteLength: 7,
          mediaType: 'text/plain',
          kind: AttachmentDraftKind.genericFile,
        );
        await _pumpChat(
          tester,
          attachments: [attachment],
          upload: ({required draft, required dataUrl}) => upload.future,
          remoteSubmit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {
                onSent();
                submitted.add(text);
              },
        );
        await tester.enterText(find.byKey(_composerKey), 'File prompt');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        expect(attachment.status, AttachmentDraftStatus.uploading);
        expect(_draft(tester), isEmpty);
        _expectEditable(tester);
        await tester.enterText(find.byKey(_composerKey), 'New upload draft');
        if (rejected) {
          upload.completeError(StateError('upload failed'));
        } else {
          upload.complete(
            const AttachmentUploadReceipt(refText: '@file:fixture'),
          );
        }
        await pumpChatUpdates(tester);
        expect(
          submitted,
          rejected ? isEmpty : ['File prompt\n\n@file:fixture'],
        );
        expect(_draft(tester), 'New upload draft');
        if (rejected) expect(find.text('file.txt'), findsOneWidget);
      },
    );

    testWidgets(
      'REST composer stays editable while request waits (rejected=$rejected)',
      (tester) async {
        final response = Completer<http.Response>();
        var submits = 0;
        await _pumpChat(
          tester,
          httpClient: MockClient((request) async {
            if (request.method == 'POST') {
              submits++;
              return response.future;
            }
            return http.Response('{"data":[]}', 200);
          }),
        );
        await tester.enterText(find.byKey(_composerKey), 'REST prompt');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        _expectEditable(tester);
        expect(_draft(tester), isEmpty);
        await tester.enterText(find.byKey(_composerKey), 'REST follow-up');
        if (rejected) {
          response.complete(http.Response('unavailable', 503));
        } else {
          response.complete(
            http.Response(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': 'Reply'},
                  },
                ],
              })}\n\n'
              'data: [DONE]\n\n',
              200,
              headers: {'content-type': 'text/event-stream'},
            ),
          );
        }
        await pumpChatUpdates(tester);
        expect(submits, 1);
        expect(_draft(tester), 'REST follow-up');
      },
    );
  }
}
