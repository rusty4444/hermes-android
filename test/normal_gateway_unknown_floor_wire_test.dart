// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_unknown_floor_wire_test.dart
// Base 4a53e32 blob b008a01bdd2faf51f20a120326fde3828d32340a; SHA256 af075a452b8e1bcf612b7a1aed63c6ca92c2f00d2ca8a49740a20359dd040f5d.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/unreconciled_policy.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

void main() {
  testWidgets(
    'real local create and bind does not duplicate first canonical turn',
    (tester) async {
      // Keep the wire/source oracle independent of quiet classification: a
      // saved metadata-free reply is inspectable in Verbose, not proven final.
      SharedPreferences.setMockInitialValues({'verbose_mode': true});
      const picker = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          picker,
          null,
        ),
      );
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = previous);
      final gateway = _Gateway();
      await tester.runAsync(gateway.start);
      final controller = GatewayTurnApplicationController();
      addTearDown(() async {
        await controller.close();
        await gateway.close();
      });
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connection = gateway.connection;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatScreen(
            connection: connection,
            session: const Session(
              id: 'local-first',
              title: 'First chat',
              model: 'fixture',
              source: 'test',
              messageCount: 0,
              isActive: false,
              preview: '',
              startedAt: 1,
              isLocalDraft: true,
            ),
            projectWorkingDirectory: '/fixture-project',
            turnApplicationController: controller,
            testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
          ),
        ),
      );
      await until(tester, () => gateway.messages.isNotEmpty);
      await tester.enterText(find.byType(TextField), 'First prompt');
      await tester.tap(find.byTooltip('Send'));
      await until(
        tester,
        () => gateway.requests.any((r) => r['method'] == 'prompt.submit'),
      );
      final owner = controller
          .normalSessionFor(connection)
          .findChat('stored-first')!;
      expect(owner.snapshot.storedSessionId, 'stored-first');
      expect(owner.snapshot.wireEmitted, isTrue);
      gateway.event('message.delta', {'text': 'First answer'});
      await until(
        tester,
        () => owner.snapshot.displayRows.last['content'] == 'First answer',
      );
      gateway.persisted = true;
      gateway.event('message.complete', {'text': 'First answer'});
      await until(
        tester,
        () =>
            owner.phase == NormalGatewayTurnPhase.completed &&
            owner.snapshot.historyRows.length == 2,
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(owner.snapshot.historyRows.map((row) => row['content']), [
        'First prompt',
        'First answer',
      ]);
      expect(
        tester
            .widgetList<MessageBubble>(
              inChatSource(
                find.byType(MessageBubble),
                ChatDisplaySource.canonical,
              ),
            )
            .map((b) => b.content),
        ['First prompt', 'First answer'],
      );
      final bubbles = tester
          .widgetList<MessageBubble>(
            inChatSource(
              find.byType(MessageBubble),
              ChatDisplaySource.received,
            ),
          )
          .map(
            (b) => {
              'role': b.isUser ? 'user' : 'assistant',
              'content': b.content,
            },
          )
          .toList();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        gateway.requests.where((r) => r['method'] == 'session.create'),
        hasLength(1),
      );
      expect(
        gateway.requests.where((r) => r['method'] == 'prompt.submit'),
        hasLength(1),
      );
      expect(
        bubbles.where(
          (b) => b['role'] == 'user' && b['content'] == 'First prompt',
        ),
        hasLength(1),
      );
      expect(
        bubbles.where(
          (b) => b['role'] == 'assistant' && b['content'] == 'First answer',
        ),
        hasLength(1),
      );
      await controller.close();
      await tester.runAsync(gateway.close);
      await tester.pump(const Duration(seconds: 16));
    },
  );
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250; i++) {
    await tester.pump();
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Fixture condition not reached');
}

class _Gateway {
  late HttpServer server;
  WebSocket? socket;
  final sockets = <WebSocket>[];
  final requests = <Map<String, dynamic>>[];
  final messages = <Map<String, dynamic>>[];
  bool created = false;
  bool persisted = false;
  bool _closed = false;
  SavedConnection get connection => SavedConnection(
    id: 'independent-unknown-floor-wire',
    label: 'Wire fixture',
    host: '127.0.0.1',
    port: server.port,
    apiKey: 'fixture-key',
    dashboardPortOverride: server.port,
    dashboardProxied: true,
  );
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/api/auth/ws-ticket') {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ticket":"fixture-ticket"}');
        await request.response.close();
      } else if (request.uri.path.endsWith('/messages')) {
        messages.add({
          'path': request.uri.toString(),
          'created': created,
          'persisted': persisted,
        });
        request.response.headers.contentType = ContentType.json;
        if (!created) {
          request.response.statusCode = 404;
          request.response.write('{"error":"not found"}');
        } else {
          request.response.write(
            jsonEncode({
              'data': persisted
                  ? [
                      {'id': 1, 'role': 'user', 'content': 'First prompt'},
                      {'id': 2, 'role': 'assistant', 'content': 'First answer'},
                    ]
                  : [],
            }),
          );
        }
        await request.response.close();
      } else if (request.uri.path == '/api/ws') {
        final ws = await WebSocketTransformer.upgrade(request);
        socket = ws;
        sockets.add(ws);
        ws.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {
              'type': 'gateway.ready',
              'payload': {'server_requests': true},
            },
          }),
        );
        ws.listen((raw) {
          final frame = Map<String, dynamic>.from(
            jsonDecode(raw as String) as Map,
          );
          if (frame['method'] == null) return;
          requests.add(frame);
          final method = frame['method'];
          if (method == 'session.create') created = true;
          ws.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': frame['id'],
              if (method == 'session.resume' && !created)
                'error': {'code': 4007, 'message': 'session not found'}
              else
                'result': method == 'session.create'
                    ? {
                        'session_id': 'runtime-first',
                        'stored_session_id': 'stored-first',
                      }
                    : method == 'session.resume'
                    ? {
                        'session_id': 'runtime-first',
                        'running': false,
                        'status': 'completed',
                      }
                    : method == 'projects.list'
                    ? {'projects': []}
                    : {'ok': true},
            }),
          );
        });
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
  }

  void event(String type, Map<String, dynamic> payload) => socket!.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {
        'type': type,
        'session_id': 'runtime-first',
        'payload': payload,
      },
    }),
  );
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final ws in sockets) {
      await ws.close();
    }
    await server.close(force: true);
  }
}
