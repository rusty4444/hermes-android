// UNRECONCILED POLICY (second adaptation layer; original case IDs retained).
// Raw: p2a-unreconciled-_flkt2h9/raw/base.tar::test/normal_gateway_unknown_floor_lifecycle_test.dart
// Base 4a53e32 blob 883a7ca67cf2a1fac29f291086b79ecc79acad43; SHA256 dbb855e7206154c03e5748b1981f4eb26cb7c71f1b9b829f9623e64f60b1c688.
// See docs/unreconciled-output/ORACLE_MIGRATION.md; unchanged safety remains binding.
import 'dart:async';
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
import 'package:hermes_android/core/utils/android_prompt_context.dart';

void main() {
  for (final mode in [
    'create',
    'create-missing-fields',
    'create-nonempty-history',
    'create-malformed-count',
    'create-malformed-messages',
    'resume-held-history',
    'resume-unavailable-history',
  ]) {
    testWidgets('real $mode renders the received and canonical turn once', (
      tester,
    ) async {
      // Unknown admission floors do not prove saved-row completion. Verbose
      // keeps both independent sources inspectable without relabelling rows.
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
      final gateway = _Gateway(mode);
      await tester.runAsync(gateway.start);
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      addTearDown(gateway.close);
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final connection = gateway.connection;
      final normal = controller.normalSessionFor(connection);
      List<int?>? floorsAtWire;
      gateway.onSubmit = () async {
        floorsAtWire = (await normal.pendingStore.load(
          normal.scope,
        )).map((marker) => marker.rowFloor).toList();
      };
      Widget chat() => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(
          connection: connection,
          session: Session(
            id: gateway.existing ? 'stored-first' : 'local-first',
            title: 'First chat',
            model: 'fixture',
            source: 'test',
            messageCount: 0,
            isActive: false,
            preview: '',
            startedAt: 1,
            isLocalDraft: !gateway.existing,
          ),
          projectWorkingDirectory: '/fixture-project',
          turnApplicationController: controller,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      );
      await tester.pumpWidget(chat());
      await _until(tester, () => gateway.messages.isNotEmpty);
      await tester.enterText(find.byType(TextField), 'First prompt');
      await tester.tap(find.byTooltip('Send'));
      // The held HTTP future is still pending at the actual wire boundary.
      await _until(tester, () => floorsAtWire != null);
      final owner = normal.findChat('stored-first')!;
      expect(owner.snapshot.storedSessionId, 'stored-first');
      expect(owner.snapshot.wireEmitted, isTrue);
      expect(owner.snapshot.rowFloor, gateway.provesEmpty ? 0 : isNull);
      expect(floorsAtWire, [gateway.provesEmpty ? 0 : null]);
      if (mode == 'resume-held-history') {
        expect(gateway.initialHistory.isCompleted, isFalse);
      }
      gateway.event('turn.start', {});
      gateway.event('message.delta', {'text': 'First answer'});
      await _until(
        tester,
        () => owner.snapshot.displayRows.last['content'] == 'First answer',
      );
      gateway.persisted = true;
      gateway.event('message.complete', {'text': 'First answer'});
      gateway.event('turn.end', {'status': 'completed'});
      await _until(
        tester,
        () =>
            owner.phase == NormalGatewayTurnPhase.completed &&
            owner.snapshot.historyRows.length == 2,
      );
      if (!gateway.initialHistory.isCompleted) {
        gateway.initialHistory.complete();
      }
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      void exactlyOnce() {
        for (final source in [
          ChatDisplaySource.canonical,
          ChatDisplaySource.received,
        ]) {
          final bubbles = tester.widgetList<MessageBubble>(
            inChatSource(find.byType(MessageBubble), source),
          );
          expect(
            bubbles.where((b) => b.isUser && b.content == 'First prompt'),
            hasLength(1),
          );
          expect(
            bubbles.where((b) => !b.isUser && b.content == 'First answer'),
            hasLength(1),
          );
        }
      }

      exactlyOnce();
      expect(owner.snapshot.historyRows, _canonical);
      expect(owner.snapshot.displayRows, hasLength(2));
      expect(owner.snapshot.historyRows, _canonical);
      expect(owner.snapshot.timeline.runs, isNotEmpty);
      // A replacement actual route must keep the same conservative view.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final reads = gateway.messages.length;
      await tester.pumpWidget(chat());
      await _until(tester, () => gateway.messages.length > reads);
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      exactlyOnce();
      final creates = gateway.requests
          .where((r) => r['method'] == 'session.create')
          .toList();
      expect(creates, hasLength(gateway.existing ? 0 : 1));
      if (!gateway.existing) {
        expect(creates.single['params'], {
          'source': 'desktop',
          'cwd': '/fixture-project',
        });
      }
      final submits = gateway.requests.where(
        (r) => r['method'] == 'prompt.submit',
      );
      expect(submits, hasLength(1));
      expect(submits.single['params'], {
        'session_id': 'runtime-first',
        'text': AndroidPromptContext.forModel('First prompt'),
        'title_preview': 'First prompt',
      });
      expect(await normal.pendingStore.load(normal.scope), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.close();
      await tester.runAsync(gateway.close);
      await tester.pump(const Duration(seconds: 16));
    });
  }
}

const _canonical = [
  {'id': 1, 'role': 'user', 'content': 'First prompt'},
  {'id': 2, 'role': 'assistant', 'content': 'First answer'},
];

Future<void> _until(WidgetTester tester, bool Function() ready) async {
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
  _Gateway(this.mode);
  final String mode;
  bool get existing => mode.startsWith('resume-');
  bool get provesEmpty => mode == 'create';
  late HttpServer server;
  WebSocket? socket;
  final sockets = <WebSocket>[];
  final requests = <Map<String, dynamic>>[];
  final messages = <Map<String, dynamic>>[];
  final initialHistory = Completer<void>();
  Future<void> Function()? onSubmit;
  bool created = false;
  bool persisted = false;
  bool _closed = false;
  SavedConnection get connection => SavedConnection(
    id: 'unknown-floor-wire-$mode',
    label: 'Wire fixture',
    host: '127.0.0.1',
    port: server.port,
    apiKey: 'fixture',
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
        final first = messages.isEmpty;
        final captured = persisted;
        messages.add({
          'path': request.uri.toString(),
          'created': created,
          'persisted': captured,
        });
        if (first && mode == 'resume-held-history') await initialHistory.future;
        if (_closed) return;
        request.response.headers.contentType = ContentType.json;
        if (!persisted && !provesEmpty && (created || existing)) {
          request.response.statusCode = 503;
          request.response.write('{"error":"history unavailable"}');
        } else if (!created && !existing) {
          request.response.statusCode = 404;
          request.response.write('{"error":"not found"}');
        } else {
          request.response.write(
            jsonEncode({'data': captured ? _canonical : []}),
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
        ws.listen((raw) async {
          final frame = Map<String, dynamic>.from(
            jsonDecode(raw as String) as Map,
          );
          if (frame['method'] == null) return;
          requests.add(frame);
          final method = frame['method'];
          if (method == 'session.create') created = true;
          if (method == 'prompt.submit') await onSubmit?.call();
          ws.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': frame['id'],
              if (method == 'session.resume' && !created && !existing)
                'error': {'code': 4007, 'message': 'session not found'}
              else
                'result': method == 'session.create'
                    ? {
                        'session_id': 'runtime-first',
                        'stored_session_id': 'stored-first',
                        if (mode != 'create-missing-fields') ...{
                          'message_count': mode == 'create-malformed-count'
                              ? '0'
                              : mode == 'create-nonempty-history'
                              ? 2
                              : 0,
                          'messages': mode == 'create-malformed-messages'
                              ? <String, dynamic>{}
                              : mode == 'create-nonempty-history'
                              ? _canonical
                              : [],
                        },
                      }
                    : method == 'session.resume'
                    ? {
                        'session_id': 'runtime-first',
                        'running': false,
                        'status': 'completed',
                      }
                    : method == 'projects.list'
                    ? {'projects': []}
                    : method == 'config.get' && frame['params']['key'] == 'full'
                    ? {'config': <String, dynamic>{}}
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
        'turn_id': 'owned-first',
        'session_id': 'runtime-first',
        'payload': payload,
      },
    }),
  );
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!initialHistory.isCompleted) initialHistory.complete();
    for (final ws in sockets) {
      await ws.close();
    }
    await server.close(force: true);
  }
}
