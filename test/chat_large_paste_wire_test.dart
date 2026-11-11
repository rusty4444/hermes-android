import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/widgets/attachment_draft_tile.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

class _PasteGateway {
  final HttpServer server;
  final bool existing;
  final sockets = <WebSocket>[];
  final socketCompletions = <Future<void>>[];
  final frames = <Map<String, dynamic>>[];
  bool created = false;
  bool closed = false;
  bool _disposed = false;

  _PasteGateway(this.server, this.existing);

  SavedConnection get connection => SavedConnection(
    id: 'paste-wire',
    label: 'Loopback',
    host: '127.0.0.1',
    port: server.port,
    apiKey: 'fixture',
    dashboardPortOverride: server.port,
    dashboardProxied: true,
  );

  static Future<_PasteGateway> start(bool existing) async {
    final fixture = _PasteGateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      existing,
    );
    fixture.server.listen(fixture.handle);
    return fixture;
  }

  Future<void> handle(HttpRequest request) async {
    if (request.uri.path == '/api/ws') {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {'type': 'gateway.ready', 'payload': {}},
        }),
      );
      final messages = socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        frames.add(frame);
        final method = frame['method'];
        if (method == null) return;
        final response = <String, dynamic>{'jsonrpc': '2.0', 'id': frame['id']};
        switch (method) {
          case 'session.resume':
            if (!existing && !created) {
              response['error'] = {'code': 4007, 'message': 'not found'};
            } else {
              response['result'] = {
                'session_id': 'runtime-paste',
                'stored_session_id': 'stored-paste',
                'running': false,
                'status': 'idle',
              };
            }
          case 'session.create':
            created = true;
            response['result'] = {
              'session_id': 'runtime-paste',
              'stored_session_id': 'stored-paste',
              'message_count': 0,
              'messages': [],
            };
          case 'config.get':
            response['result'] = {'config': <String, dynamic>{}};
          case 'file.attach':
            response['result'] = {
              'attached': true,
              'name': 'paste.txt',
              'path': '/gateway/project/paste-server.txt',
              'ref_path': '/gateway/project/paste-server.txt',
              'ref_text': '@file:/gateway/project/paste-server.txt',
              'uploaded': true,
            };
          case 'prompt.submit':
            // A definite pre-wire/RPC rejection completes the fixture without
            // pretending that an acknowledgement is a completed model turn.
            response['error'] = {
              'code': 4001,
              'message': 'fixture rejects prompt',
            };
          default:
            response['result'] = <String, dynamic>{};
        }
        if (!closed) socket.add(jsonEncode(response));
      });
      socketCompletions.add(messages.asFuture<void>());
      return;
    }
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/api/auth/ws-ticket') {
      request.response.write('{"ticket":"fixture"}');
    } else if (request.uri.path.endsWith('/messages')) {
      if (!existing && !created) request.response.statusCode = 404;
      request.response.write('{"data":[]}');
    } else {
      request.response.write('{}');
    }
    await request.response.close();
  }

  Future<void> close() async {
    if (_disposed) return;
    closed = true;
    await _withCleanup(
      () async {
        await Future.wait([
          for (final socket in sockets) socket.close(),
          // Join incoming termination as well as the outgoing sinks. Dart can
          // terminate after its five-second close timeout; this is not proof
          // that the peer acknowledged the close frame.
          ...socketCompletions,
        ]).timeout(const Duration(seconds: 10));
      },
      () async {
        await server.close(force: true).timeout(const Duration(seconds: 10));
      },
    );
    // Keep replies disabled after a failure, but allow cleanup to be retried.
    _disposed = true;
  }
}

// Always attempt the next cleanup, without replacing an earlier failure or
// its stack trace with a secondary cleanup error.
Future<void> _withCleanup(
  Future<void> Function() action,
  Future<void> Function() cleanup,
) async {
  var failed = false;
  try {
    await action();
  } catch (_) {
    failed = true;
    rethrow;
  } finally {
    try {
      await cleanup();
    } catch (_) {
      if (!failed) rethrow;
    }
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(mockChatImageRecovery);
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = previous);

  for (final existing in [false, true]) {
    testWidgets(
      'real paste upload targets the ${existing ? 'resumed' : 'new Project'} session and submits once',
      (tester) async {
        final server = (await tester.runAsync(
          () => _PasteGateway.start(existing),
        ))!;
        final sandbox = (await tester.runAsync(() async {
          final root = await Directory(
            'build/paste-wire-tests',
          ).create(recursive: true);
          return root.createTemp('paste-');
        }))!;
        final owner = GatewayTurnApplicationController();
        Future<void> closeFixture() => _withCleanup(
          server.close,
          () => _withCleanup(
            () => owner.close().timeout(const Duration(seconds: 10)),
            () async {
              if (await sandbox.exists()) await sandbox.delete(recursive: true);
            },
          ),
        );
        addTearDown(closeFixture);
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatScreen(
              connection: server.connection,
              session: Session(
                id: existing ? 'stored-paste' : 'local-paste',
                title: 'Wire paste',
                model: '',
                source: 'test',
                messageCount: 0,
                isActive: true,
                preview: '',
                startedAt: 1,
                isLocalDraft: !existing,
              ),
              projectWorkingDirectory: '/gateway/project',
              turnApplicationController: owner,
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
              testAttachmentDraftService: AttachmentDraftService(
                cacheDirectoryProvider: () async => sandbox,
              ),
            ),
          ),
        );
        // A new Project draft may defer session allocation until Send. Wait
        // for the real connection, not for a speculative session.create.
        await _until(tester, () => server.frames.isNotEmpty);
        const composer = Key('chat-message-composer');
        final text = '  日本語 😀\r\n' * 350;
        await tester.showKeyboard(find.byKey(composer));
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await _until(
          tester,
          () => find.byType(AttachmentDraftTile).evaluate().isNotEmpty,
        );
        final draft = tester
            .widget<AttachmentDraftTile>(find.byType(AttachmentDraftTile))
            .draft;
        expect(draft.kind, AttachmentDraftKind.genericFile);
        expect(
          await tester.runAsync(() => File(draft.cachedPath).readAsBytes()),
          utf8.encode(text),
        );
        final send = tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed!;
        send();
        send();
        await _until(
          tester,
          () =>
              server.frames.any((frame) => frame['method'] == 'prompt.submit'),
        );
        final methods = server.frames.map((frame) => frame['method']).toList();
        final uploads = server.frames
            .where((frame) => frame['method'] == 'file.attach')
            .toList();
        final prompts = server.frames
            .where((frame) => frame['method'] == 'prompt.submit')
            .toList();
        expect(uploads, hasLength(1));
        expect(prompts, hasLength(1));
        final attachment = uploads.single['params'] as Map;
        expect(attachment['session_id'], 'runtime-paste');
        expect(attachment['name'], 'paste.txt');
        expect(
          attachment['data_url'],
          'data:text/plain;base64,${base64Encode(utf8.encode(text))}',
        );
        expect(prompts.single['params']['session_id'], 'runtime-paste');
        expect(
          prompts.single['params']['text'],
          contains('@file:/gateway/project/paste-server.txt'),
        );
        expect(prompts.single['params']['text'], isNot(contains(text)));
        expect(
          methods.indexOf('file.attach'),
          lessThan(methods.indexOf('prompt.submit')),
        );
        final creates = server.frames
            .where((frame) => frame['method'] == 'session.create')
            .toList();
        if (existing) {
          expect(creates, isEmpty);
          expect(
            server.frames.firstWhere(
              (frame) => frame['method'] == 'session.resume',
            )['params']['session_id'],
            'stored-paste',
          );
        } else {
          expect(creates, hasLength(1));
          expect(creates.single['params']['cwd'], '/gateway/project');
          expect(creates.single['params'], isNot(contains('session_id')));
          expect(
            methods.indexOf('session.create'),
            lessThan(methods.indexOf('file.attach')),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(closeFixture);
        await tester.pump();
      },
    );
  }
}
