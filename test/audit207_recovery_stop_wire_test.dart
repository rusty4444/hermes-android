import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

const _mobileId = '11111111-1111-4111-8111-111111111111';
const _clientId = '33333333-3333-4333-8333-333333333333';
const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _send = Key('chat-send-message');
const _stop = Key('chat-stop-response');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        );
  });

  for (final stopBeforeAck in [false, true]) {
    testWidgets(
      '${stopBeforeAck ? 'M3' : 'H1'} real v2 wire keeps one submit, routes Stop '
      'to turn.interrupt and waits through running reconcile for terminal',
      (tester) async {
        final fixture = await tester.runAsync(_WireGateway.start);
        final gateway = fixture!;
        final store = _MemoryJournal();
        final journal = GatewayTurnJournal(store: store);
        var uuidIndex = 0;
        final coordinator = GatewayTurnCoordinator(
          connectionId: 'audit207-wire',
          endpointDigest: _digest,
          localSessionId: 'local-wire',
          journal: journal,
          clock: DateTime.now,
          freshSocketFactory: () async => WsClient(gateway.baseUrl),
          uuidFactory: () => uuidIndex++ == 0 ? _mobileId : _clientId,
        );
        final ioZone = await tester.runAsync(() async => Zone.current);
        final session = _CoordinatorSession(coordinator, ioZone!);
        final owner = GatewayTurnApplicationController();
        addTearDown(() async {
          if (!gateway.submitAck.isCompleted) gateway.submitAck.complete();
          await tester.runAsync(() async {
            await coordinator.close();
            await gateway.close();
          });
          await owner.close();
        });
        await _mount(tester, session, owner);
        await _until(tester, () => session.recovered.isCompleted);
        await _pump(tester);
        await tester.enterText(
          find.byKey(const Key('chat-message-composer')),
          'One wire prompt',
        );
        await tester.tap(find.byKey(_send));
        await _pump(tester);
        await tester.runAsync(
          () => gateway.submitSeen.future.timeout(const Duration(seconds: 5)),
        );
        if (!stopBeforeAck) {
          gateway.submitAck.complete();
          await _until(tester, () => session.firstState.isCompleted);
          await _pump(tester);
        }
        await tester.tap(find.byKey(_stop));
        await _pump(tester);
        if (stopBeforeAck) {
          expect(
            gateway.requests.where((r) => r['method'] == 'turn.interrupt'),
            isEmpty,
          );
          // The queued stop must not fake local terminality before the submit
          // acknowledgement supplies the coordinator-owned identity.
          expect(find.byKey(_stop), findsOneWidget);
          gateway.submitAck.complete();
        }
        await _until(tester, () => gateway.interruptSeen.isCompleted);
        await _until(tester, () => session.interruptReturned.isCompleted);
        await _pump(tester);
        expect(session.stopState!.isTerminal, isFalse);
        expect(session.stopState!.isFailClosed, isFalse);
        expect(session.stopState!.status?.wireValue, 'running');
        expect(find.byKey(_stop), findsOneWidget);
        final outstanding = await tester.runAsync(() => journal.loadSnapshot());
        expect(outstanding!.entries.single.isTerminal, isFalse);

        // Continue emitting while the interruption winds down. Only this real
        // identified lifecycle terminal is allowed to release the composer.
        gateway.emit('message.delta', 2, {'text': ' during wind-down'});
        await tester.runAsync(() => coordinator.waitForIdle());
        gateway.emit('message.complete', 3, {
          'text': 'Authoritative stopped text',
          'status': 'interrupted',
        });
        await _until(tester, () => session.terminal.isCompleted);
        await _pump(tester);
        expect(find.byKey(_stop), findsNothing);
        expect(
          tester.widget<IconButton>(find.byKey(_send)).onPressed,
          isNotNull,
        );
        final settled = await tester.runAsync(() => journal.loadSnapshot());
        expect(settled!.entries.single.status?.wireValue, 'interrupted');
        expect(
          gateway.requests.where((r) => r['method'] == 'prompt.submit'),
          hasLength(1),
        );
        expect(
          gateway.requests.where((r) => r['method'] == 'prompt.interrupt'),
          isEmpty,
        );
        final interrupt = gateway.requests.singleWhere(
          (r) => r['method'] == 'turn.interrupt',
        );
        expect(interrupt['params'], {
          'session_id': 'runtime-wire',
          'turn_id': 'turn-wire',
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester);
      },
    );
  }
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await _pump(tester);
  }
  expect(ready(), isTrue, reason: 'The controlled wire barrier must complete.');
}

Future<void> _mount(
  WidgetTester tester,
  _CoordinatorSession session,
  GatewayTurnApplicationController owner,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'audit207-wire',
          label: 'Wire fixture',
          host: 'fixture.invalid',
          port: 8642,
          apiKey: 'synthetic',
        ),
        session: const Session(
          id: 'local-wire',
          title: 'Wire chat',
          model: 'fixture',
          source: 'mobile',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
          isLocalDraft: true,
        ),
        turnApplicationController: owner,
        testTurnApplicationSession: session,
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testApiClient: ApiClient(
          baseUrl: 'http://fixture.invalid',
          apiKey: 'synthetic',
          httpClient: MockClient(
            (_) async => http.Response('{"data":[]}', 200),
          ),
        ),
      ),
    ),
  );
  await _pump(tester);
}

class _CoordinatorSession extends Fake
    implements GatewayTurnApplicationSession {
  _CoordinatorSession(this.coordinator, this.ioZone);
  final GatewayTurnCoordinator coordinator;
  final Zone ioZone;
  final recovered = Completer<void>();
  final firstState = Completer<void>();
  final terminal = Completer<void>();
  final interruptReturned = Completer<void>();
  GatewayTurnRecoveryState? stopState;

  GatewayTurnStateCallback? _observe(GatewayTurnStateCallback? listener) =>
      (state) {
        listener?.call(state);
        if (!firstState.isCompleted) firstState.complete();
        if (state.isTerminal && !terminal.isCompleted) terminal.complete();
      };

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String id, {
    GatewayTurnStateCallback? onState,
  }) async {
    final result = await ioZone.run(
      () => coordinator.recoverPending(onState: _observe(onState)),
    );
    if (!recovered.isCompleted) recovered.complete();
    return result;
  }

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) => ioZone.run(
    () => coordinator.submit(
      text: text,
      attachments: attachments,
      onState: _observe(onState),
    ),
  );
  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) async {
    stopState = await ioZone.run(() => coordinator.interrupt(clientTurnId));
    if (!interruptReturned.isCompleted) interruptReturned.complete();
    return stopState!;
  }

  @override
  Object setAsyncEventListener(String id, DesktopAsyncEventCallback listener) =>
      Object();
  @override
  Object setTurnSettledListener(
    String id,
    GatewayTurnSettledCallback listener,
  ) => Object();
  @override
  Object setSessionBoundListener(
    String id,
    GatewayTurnSessionBoundCallback listener,
  ) => Object();
  @override
  void removeAsyncEventListener(String id, Object registration) {}
  @override
  void removeTurnSettledListener(String id, Object registration) {}
  @override
  void removeSessionBoundListener(String id, Object registration) {}
}

class _MemoryJournal implements GatewayTurnJournalStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async => value = text;
  @override
  Future<void> delete() async => value = null;
  @override
  Future<String?> readLegacy() async => null;
  @override
  Future<void> deleteLegacy() async {}
}

class _WireGateway {
  _WireGateway(this.server);
  final HttpServer server;
  final requests = <Map<String, dynamic>>[];
  final submitAck = Completer<void>();
  final submitSeen = Completer<void>();
  final interruptSeen = Completer<void>();
  final sockets = <WebSocket>[];
  late StreamSubscription<HttpRequest> subscription;
  String get baseUrl => 'http://127.0.0.1:${server.port}';

  static Future<_WireGateway> start() async {
    final fixture = _WireGateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.subscription = fixture.server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      fixture.sockets.add(socket);
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': 'gateway.ready',
            'payload': {
              'protocol': {'name': 'hermes-jsonrpc', 'major': 2},
              'capabilities': {'turn_recovery': _capability},
            },
          },
        }),
      );
      socket.listen((raw) async {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (frame['method'] == 'client.capabilities') return;
        fixture.requests.add(frame);
        final params = frame['params'] as Map<String, dynamic>;
        final Map<String, dynamic> result;
        switch (frame['method']) {
          case 'session.open':
            result = {
              'runtime_session_id': 'runtime-wire',
              'stored_session_id': 'stored-wire',
              'mobile_session_id': params['mobile_session_id'],
              'binding_version': 1,
              'turn_recovery': true,
              'automatic_resubmit': false,
              'capabilities': {'turn_recovery': _capability},
            };
          case 'prompt.submit':
            fixture.submitSeen.complete();
            await fixture.submitAck.future;
            result = {
              'accepted': true,
              'automatic_resubmit': false,
              'client_turn_id': params['client_turn_id'],
              'turn_id': 'turn-wire',
              'status': 'accepted',
              'last_seq': 0,
              'created': true,
            };
          case 'turn.interrupt':
            fixture.interruptSeen.complete();
            result = {
              'automatic_resubmit': false,
              'client_turn_id': _clientId,
              'turn_id': 'turn-wire',
              'status': 'running',
              'last_seq': 0,
            };
          case 'turn.reconcile':
            result = {
              'automatic_resubmit': false,
              'mode': 'events',
              'turn_id': 'turn-wire',
              'status': 'running',
              'earliest_seq': 1,
              'last_seq': 1,
              'next_after_seq': 1,
              'has_more': false,
              'events': [
                {
                  'turn_id': 'turn-wire',
                  'seq': 1,
                  'message_id': 'message-wire',
                  'type': 'message.delta',
                  'payload': {'text': 'Still winding down'},
                },
              ],
            };
          default:
            throw StateError('Unexpected wire request: ${frame['method']}');
        }
        socket.add(
          jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
        );
      });
    });
    return fixture;
  }

  void emit(String type, int seq, Map<String, dynamic> payload) {
    sockets.single.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {
          'type': type,
          'session_id': 'runtime-wire',
          'turn_id': 'turn-wire',
          'seq': seq,
          'message_id': 'message-wire',
          'payload': payload,
        },
      }),
    );
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await subscription.cancel();
    await server.close(force: true);
  }
}

const _capability = {
  'version': 2,
  'shadow_only': false,
  'methods': ['session.open', 'turn.reconcile', 'turn.interrupt'],
  'prompt_submit_version': 2,
  'applies_to': [
    'session.open',
    'prompt.submit@2',
    'turn.reconcile',
    'turn.interrupt',
  ],
  'automatic_resubmit': false,
  'execution_route': 'single_process_in_process',
  'event_retention_seconds': 86400,
  'turn_retention_seconds': 604800,
  'max_event_bytes': 65536,
  'max_turn_bytes': 4194304,
  'terminal_event_reserve_bytes': 1024,
  'max_prompt_bytes': 65536,
  'mobile_session_id_format': 'canonical_lowercase_uuid',
  'client_turn_id_format': 'canonical_lowercase_uuid',
  'reconcile_max_events': 256,
  'reconcile_max_page_bytes': 524288,
};
