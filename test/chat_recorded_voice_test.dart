import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'support/inert_turn_application_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/fake_voice_recorder.dart';
import 'support/l10n_test_utils.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        ),
  );

  for (final mode in [
    'rest',
    'rest-typed-during-transcription',
    'legacy',
    'transcription-failure',
    'submit-rejection',
    'stream-rejection',
    'canonical',
    'old-canonical',
    'recovery',
    'recovery-uncertain',
  ]) {
    testWidgets('voice pause/resume and safe submission: $mode', (
      tester,
    ) async {
      final recorder = FakeRecorder();
      final stream = StreamController<List<int>>();
      final remoteDone = Completer<void>();
      StreamCallback? remoteEvent;
      var recognitionCalls = 0;
      final transcriptionGate = Completer<void>();
      final prompts = <String>[];
      final api = ApiClient(
        baseUrl: 'https://fixture.invalid',
        apiKey: '',
        httpClient: MockClient.streaming((request, bytes) async {
          if (request.method == 'POST' &&
              request.url.path == '/v1/chat/completions') {
            final value = jsonDecode(utf8.decode(await bytes.toBytes())) as Map;
            final messages = value['messages'] as List;
            prompts.add((messages.last as Map)['content'] as String);
            if (mode == 'submit-rejection') {
              return http.StreamedResponse(
                Stream.value(utf8.encode('{}')),
                503,
              );
            }
            if (mode == 'stream-rejection') {
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    'data: {"error":{"message":"Synthetic rejection"}}\n\n',
                  ),
                ),
                200,
                headers: {'content-type': 'text/event-stream'},
              );
            }
            if (mode == 'canonical' || mode == 'old-canonical') {
              return http.StreamedResponse(
                const Stream.empty(),
                200,
                headers: {'content-type': 'text/event-stream'},
              );
            }
            return http.StreamedResponse(
              stream.stream,
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }
          if ((mode == 'canonical' && prompts.isNotEmpty) ||
              mode == 'old-canonical') {
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  '{"data":[{"id":1,"role":"user","content":"Recognized voice"}]}',
                ),
              ),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"data":[]}')),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        testAppWithL10n(
          ChatScreen(
            connection: SavedConnection(
              id: 'voice-fixture',
              label: 'Fixture',
              host: 'fixture.invalid',
              port: 443,
              useHttps: true,
              apiKey: '',
            ),
            session: const Session(
              id: 'voice-fixture-chat',
              title: 'Fixture',
              model: 'fixture',
              source: 'test',
              messageCount: 0,
              isActive: true,
              preview: '',
              startedAt: 1,
            ),
            initialAttachmentDrafts: [
              AttachmentDraft(
                id: 'existing-photo',
                cachedPath: '/fixture/photo.png',
                name: 'existing.png',
                byteLength: 100,
                mediaType: 'image/png',
                kind: AttachmentDraftKind.image,
                sanitized: true,
                status: AttachmentDraftStatus.attached,
              ),
            ],
            testApiClient: api,
            testTurnApplicationSession: mode.startsWith('recovery')
                ? _RecoveryVoiceSession(
                    prompts,
                    uncertain: mode == 'recovery-uncertain',
                  )
                : null,
            testVoiceRecorder: recorder,
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            testVoiceTranscription: (_) async {
              recognitionCalls++;
              if (mode == 'rest-typed-during-transcription') {
                await transcriptionGate.future;
              }
              if (mode == 'transcription-failure') {
                throw StateError('Synthetic transcription failure');
              }
              return 'Recognized voice';
            },
            testRemotePromptSubmit: mode == 'legacy'
                ? ({
                    required sessionId,
                    required text,
                    required onEvent,
                    required onSent,
                  }) async {
                    prompts.add(text);
                    remoteEvent = onEvent;
                    onSent(); // A socket write is deliberately NOT an acceptance receipt.
                    await remoteDone.future;
                  }
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('chat-message-composer')),
        'Unsent typed draft',
      );
      await tester.tap(find.byTooltip('Chat actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record voice message'));
      await tester.pump();
      await tester.pump();
      expect(recorder.live, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('chat-message-composer')))
            .enabled,
        isTrue,
        reason: 'Recording preserves upstream editable-composer behavior',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Send',
              ),
            )
            .onPressed,
        isNull,
        reason: 'Typed Send is disabled while the microphone owns the input',
      );
      expect(recognitionCalls, 0, reason: 'Recording stays local until Send');
      await tester.tap(find.byKey(const Key('voice-recording-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voice-recording-play')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voice-recording-resume')));
      await tester.pump();
      expect(recorder.continuations, 1);
      expect(recorder.deleted, 0);
      await tester.tap(find.byKey(const Key('voice-recording-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voice-recording-send')));
      if (mode == 'rest-typed-during-transcription') {
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('chat-message-composer')),
          'Edited during transcription',
        );
        transcriptionGate.complete();
      }
      for (
        var i = 0;
        i < 20 && prompts.isEmpty && mode != 'transcription-failure';
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();
      expect(recognitionCalls, 1);
      final composer = tester.widget<TextField>(
        find.byKey(const Key('chat-message-composer')),
      );
      expect(
        composer.controller!.text,
        mode == 'rest-typed-during-transcription'
            ? 'Edited during transcription'
            : 'Unsent typed draft',
      );
      expect(
        find.text('existing.png'),
        findsOneWidget,
        reason: 'Voice never consumes unrelated attachments',
      );
      if (mode.startsWith('recovery')) {
        await tester.pump();
        await tester.pump();
        expect(prompts, ['Recognized voice']);
        expect(recorder.deleted, mode == 'recovery-uncertain' ? 0 : 1);
        expect(recorder.draft, mode == 'recovery-uncertain');
      } else if (mode == 'transcription-failure' ||
          mode == 'submit-rejection' ||
          mode == 'stream-rejection' ||
          mode == 'old-canonical') {
        await tester.pumpAndSettle();
        expect(recorder.draft, isTrue);
        expect(recorder.deleted, 0);
        expect(
          prompts,
          mode == 'transcription-failure' ? isEmpty : ['Recognized voice'],
        );
      } else if (mode == 'canonical') {
        await tester.pumpAndSettle();
        expect(prompts, ['Recognized voice']);
        expect(
          recorder.deleted,
          1,
          reason:
              'A new canonical user row proves acceptance even without tokens',
        );
      } else {
        expect(prompts, ['Recognized voice']);
        expect(
          recorder.deleted,
          0,
          reason:
              'Neither HTTP headers nor a socket write prove voice acceptance',
        );
        if (mode == 'legacy') {
          remoteEvent!(
            StreamEvent(type: 'message.delta', data: {'text': 'Answer'}),
          );
        } else {
          stream.add(
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"Answer"}}]}\n\n',
            ),
          );
        }
        await tester.pump();
        await tester.pump();
        expect(recorder.deleted, 1);
        if (mode == 'legacy') {
          remoteDone.complete();
        } else {
          unawaited(stream.close());
        }
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (!stream.isClosed) unawaited(stream.close());
    });
  }
}

class _RecoveryVoiceSession extends InertTurnApplicationSession {
  final List<String> prompts;
  final bool uncertain;
  _RecoveryVoiceSession(this.prompts, {required this.uncertain});

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) async {
    prompts.add(text);
    expect(attachments, isEmpty);
    const id = '123e4567-e89b-42d3-a456-426614174000';
    var state = GatewayTurnRecoveryState.initial(
      clientTurnId: id,
    ).markSubmissionStarted();
    if (!uncertain) {
      state = state.applyAck(
        const GatewayTurnAck(
          clientTurnId: id,
          turnId: 'voice-accepted-turn',
          status: GatewayRecoveryTurnStatus.accepted,
          lastSeq: 0,
          created: true,
        ),
      );
    }
    onState?.call(state);
    return state;
  }
}
