import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() => HttpOverrides.global = previous);

  test(
    'rejected binding rolls back transport maps and send fence rejects a lost admission',
    () async {
      final server = await BindingServer.start();
      final client = DesktopGatewayClient.fromConnection(server.connection);
      addTearDown(() async {
        client.close();
        await server.close();
      });
      var reject = true;
      client.setSessionBoundListener((_, _) {
        if (reject) throw StateError('Rejected binding');
      });
      final ensuring = client.ensureSession('local');
      ensuring.ignore();
      await server.createEntered.future;
      server.releaseCreate();
      await expectLater(ensuring, throwsStateError);
      expect(client.storedSessionKeyFor('local'), isNull);
      reject = false;
      // Once the application accepts the known durable id, retry attaches. It
      // must not reuse a half-committed runtime or create another stored chat.
      client.bindStoredSession('local', 'stored');
      await client.ensureSession('local');
      expect(server.resumes, 2);
      await expectLater(
        client.submitPrompt(
          sessionId: 'local',
          text: 'Never on wire',
          onEvent: (_) {},
          onSent: () => fail('revoked admission emitted'),
          maySend: () => false,
        ),
        throwsStateError,
      );
      expect(server.prompts, isEmpty);
      expect(server.creates, 1);
    },
  );

  for (final before in [false, true]) {
    test(
      'canonical before create reply=$before converges; retained owners send and settle',
      () async {
        final server = await BindingServer.start();
        final controller = GatewayTurnApplicationController();
        addTearDown(() async {
          await controller.close();
          await server.close();
        });
        final session = controller.normalSessionFor(server.connection);
        await session.ready;
        final local = session.chatFor('local', title: 'Original');
        final ensuring = session.client!.ensureSession('local');
        ensuring.ignore();
        await server.createEntered.future;
        final early = before
            ? session.chatFor(
                'stored',
                storedSessionId: 'stored',
                title: 'List route',
              )
            : null;
        final snapshots = <NormalGatewayChatSnapshot>[];
        early?.subscribe(snapshots.add);
        server.releaseCreate();
        await ensuring;
        final canonical = session.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Canonical',
        );
        expect(local.storedSessionId, 'stored');
        expect(session.client!.storedSessionKeyFor('local'), 'stored');
        expect(identical(local, canonical), isTrue);
        expect(server.prompts, isEmpty);
        final first = send(local, 'First explicit send');
        await server.untilPrompts(1);
        expect(local.snapshot.rowFloor, 0);
        expect(
          (await session.pendingStore.load(session.scope)).single.turnId,
          local.turnId,
        );
        expect((early ?? canonical).reserve(), isNull);
        server.finish('First answer');
        await first;
        await until(() => !local.snapshot.hasActiveTurn);
        expect(local.phase, NormalGatewayTurnPhase.completed);
        if (early != null) {
          expect(snapshots.any((s) => s.wireEmitted), isTrue);
          expect(snapshots.last.phase, NormalGatewayTurnPhase.completed);
        }
        final second = send(early ?? canonical, 'Second explicit send');
        await server.untilPrompts(2);
        server.finish('Second answer');
        await second;
        await until(() => !local.snapshot.hasActiveTurn);
        expect(await session.pendingStore.load(session.scope), isEmpty);
        expect(server.prompts.map((p) => p['text']), [
          AndroidPromptContext.forModel('First explicit send'),
          AndroidPromptContext.forModel('Second explicit send'),
        ]);
        expect(server.creates, 1);
      },
    );
  }

  for (final known in [false, true]) {
    test(
      'pending local admission survives idle canonical, known source floor=$known',
      () async {
        final server = await BindingServer.start();
        final controller = GatewayTurnApplicationController();
        addTearDown(() async {
          await controller.close();
          await server.close();
        });
        final session = controller.normalSessionFor(server.connection);
        await session.ready;
        final local = session.chatFor('local', title: 'Pending');
        if (known) {
          local.observeHistory([
            {
              'id': 37,
              'role': 'assistant',
              'content': 'Known before admission',
            },
          ]);
        }
        final first = send(local, 'Pending original');
        first.ignore();
        await server.createEntered.future;
        final canonical = session.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Idle',
        );
        canonical.observeHistory([
          {'id': 99, 'role': 'assistant', 'content': 'Other route observation'},
        ]);
        final snapshots = <NormalGatewayChatSnapshot>[];
        final subscription = canonical.subscribe(snapshots.add);
        server.releaseCreate();
        await server.untilPrompts(1);
        expect(session.chats, hasLength(1));
        expect(canonical.snapshot.turnId, local.turnId);
        expect(canonical.reserve(), isNull);
        // Canonical latest history arrived after the source's older context
        // and allocation snapshot, before any write-ahead receipt or emission.
        expect(local.snapshot.rowFloor, 99);
        expect(
          (await session.pendingStore.load(session.scope)).single.rowFloor,
          99,
        );
        server.finish('Only original answer');
        await first;
        await until(() => !local.snapshot.hasActiveTurn);
        expect(snapshots.any((s) => s.wireEmitted), isTrue);
        canonical.unsubscribe(subscription);
        final count = snapshots.length;
        final retry = send(canonical, 'Explicit old canonical reference');
        await server.untilPrompts(2);
        server.finish('Second answer');
        await retry;
        await until(() => !local.snapshot.hasActiveTurn);
        expect(snapshots, hasLength(count));
        expect(await session.pendingStore.load(session.scope), isEmpty);
      },
    );
  }

  for (final wire in [false, true]) {
    test(
      'canonical ${wire ? 'wire' : 'prewire'} admission rejects pending local; explicit local retry works',
      () async {
        final server = await BindingServer.start();
        server.historyUnavailable = true;
        final controller = GatewayTurnApplicationController();
        addTearDown(() async {
          await controller.close();
          await server.close();
        });
        final session = controller.normalSessionFor(server.connection);
        await session.ready;
        final local = session.chatFor('local', title: 'Original');
        final snapshots = <NormalGatewayChatSnapshot>[];
        local.subscribe((snapshot) {
          snapshots.add(snapshot);
          if (snapshot.phase == NormalGatewayTurnPhase.failed) {
            expect(
              local.reserve(),
              isNull,
              reason:
                  'rejection callbacks already follow shared admission authority',
            );
          }
        });
        Object? error;
        final original = send(local, 'Unsent original').then<void>(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        await server.createEntered.future;
        final canonical = session.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Admitted',
        );
        final reservation = canonical.reserve()!;
        final admittedTurn = canonical.turnId;
        Future<void>? flight;
        if (wire) {
          flight = send(
            canonical,
            'Canonical admitted',
            reservation: reservation,
          );
          flight.ignore();
          await server.untilPrompts(1);
          expect(canonical.snapshot.rowFloor, isNull);
        }
        server.releaseCreate();
        await original;
        expect(error, isA<StateError>());
        expect(error.toString(), contains('not sent'));
        await until(
          () => snapshots.any((s) => s.phase == NormalGatewayTurnPhase.failed),
        );
        expect(
          snapshots.any(
            (s) => s.phase == NormalGatewayTurnPhase.failed && !s.wireEmitted,
          ),
          isTrue,
          reason:
              'rejection projection: ${snapshots.map((s) => '${s.phase}/${s.wireEmitted}').toList()}',
        );
        expect(
          identical(session.findChat('local'), session.findChat('stored')),
          isTrue,
        );
        expect(session.client!.storedSessionKeyFor('local'), 'stored');
        expect(local.snapshot.turnId, admittedTurn);
        expect(local.reserve(), isNull);
        if (!wire) {
          flight = send(
            canonical,
            'Canonical admitted',
            reservation: reservation,
          );
          flight.ignore();
          await server.untilPrompts(1);
        }
        expect(
          canonical.snapshot.rowFloor,
          isNull,
          reason: 'late empty-create proof must not seed canonical admission',
        );
        expect(
          (await session.pendingStore.load(session.scope)).single.turnId,
          admittedTurn,
        );
        expect(
          server.prompts.single['text'],
          AndroidPromptContext.forModel('Canonical admitted'),
        );
        server.finish('Canonical answer');
        await flight;
        await until(() => !canonical.snapshot.hasActiveTurn);
        expect(await session.pendingStore.load(session.scope), isEmpty);
        expect(
          server.prompts,
          hasLength(1),
          reason: 'never auto-replay the original',
        );
        server.historyUnavailable = false;
        final retry = send(local, 'Explicit local retry');
        await server.untilPrompts(2);
        server.finish('Retried answer');
        await retry;
        await until(() => !canonical.snapshot.hasActiveTurn);
        expect(server.prompts.map((p) => p['text']), [
          AndroidPromptContext.forModel('Canonical admitted'),
          AndroidPromptContext.forModel('Explicit local retry'),
        ]);
        expect(await session.pendingStore.load(session.scope), isEmpty);
      },
    );
  }

  test(
    'detached rejected local draft survives migration without a newer composer lease',
    () async {
      final server = await BindingServer.start();
      final controller = GatewayTurnApplicationController();
      addTearDown(() async {
        await controller.close();
        await server.close();
      });
      final session = controller.normalSessionFor(server.connection);
      await session.ready;
      final writer =
          controller
              .presentationFor(server.connection)
              .chatFor('local')
              .openWriter()
            ..edit('Unsent original');
      await writer.save('');
      await writer.close();
      final local = session.chatFor('local', title: 'Detached original');
      Object? error;
      final original = local
          .submitPrepared(
            reservation: local.reserve()!,
            text: 'Unsent original',
            localContent: 'Unsent original',
            rawDraftText: 'Unsent original',
            canRestoreDraft: true,
            draftHandle: writer.draftHandle,
          )
          .then<void>(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      await server.createEntered.future;
      final canonical = session.chatFor(
        'stored',
        storedSessionId: 'stored',
        title: 'Independent admission',
      );
      final reservation = canonical.reserve()!;
      server.releaseCreate();
      await original;
      expect(error, isA<StateError>());
      for (var i = 0; i < 8; i++) {
        await ComposerDraftStore.read(
          connectionId: server.connection.id,
          sessionId: 'stored',
        );
      }
      await (await SharedPreferences.getInstance()).reload();
      final replacement = controller
          .presentationFor(server.connection)
          .chatFor('stored')
          .openWriter();
      expect(await replacement.read(), 'Unsent original');
      expect(
        await ComposerDraftStore.read(
          connectionId: server.connection.id,
          sessionId: 'stored',
        ),
        'Unsent original',
      );
      await replacement.close();
      canonical.cancelPreparation(reservation);
      expect(server.prompts, isEmpty);
    },
  );

  test('converged receipt reloads canonical-first without replay', () async {
    final server = await BindingServer.start();
    final first = GatewayTurnApplicationController();
    final second = GatewayTurnApplicationController();
    addTearDown(() async {
      await first.close();
      await second.close();
      await server.close();
    });
    final session = first.normalSessionFor(server.connection);
    await session.ready;
    final local = session.chatFor('local', title: 'Original');
    final sending = send(local, 'Survive process replacement');
    sending.ignore();
    await server.createEntered.future;
    session.chatFor(
      'stored',
      storedSessionId: 'stored',
      title: 'Before binding',
    );
    server.releaseCreate();
    await server.untilPrompts(1);
    final turn = local.turnId;
    await first.close();
    await sending;
    await (await SharedPreferences.getInstance()).reload();
    final restored = second.normalSessionFor(server.connection);
    final canonical = restored.chatFor(
      'stored',
      storedSessionId: 'stored',
      title: 'Before receipt',
    );
    await restored.ready;
    await until(() => server.resumes >= 2);
    expect(restored.chats, hasLength(1));
    expect(identical(restored.findChat('local'), canonical), isTrue);
    expect(canonical.turnId, turn);
    expect(canonical.reserve(), isNull);
    expect(server.prompts, hasLength(1));
    server.finish('Recovered answer');
    canonical.requestRecovery();
    await until(() => !canonical.snapshot.hasActiveTurn);
    expect(await restored.pendingStore.load(restored.scope), isEmpty);
    expect(canonical.phase, NormalGatewayTurnPhase.completed);
    expect(server.prompts, hasLength(1));
  });

  for (final active in [false, true]) {
    testWidgets(
      'real routes canonical active=$active converge, pop and reopen',
      (tester) async {
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
        await tester.binding.setSurfaceSize(const Size(1000, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final server = (await tester.runAsync(BindingServer.start))!;
        final controller = GatewayTurnApplicationController();
        addTearDown(() async {
          await controller.close();
          await server.close();
        });
        Widget screen(String id, {bool draft = false}) => ChatScreen(
          key: UniqueKey(),
          connection: server.connection,
          session: Session(
            id: id,
            title: 'Alias handoff',
            model: 'fixture',
            source: 'test',
            messageCount: 0,
            isActive: false,
            preview: '',
            startedAt: 1,
            isLocalDraft: draft,
          ),
          projectWorkingDirectory: draft ? '/project' : null,
          turnApplicationController: controller,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        );
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: screen('local', draft: true),
          ),
        );
        await tester.pump();
        await tester.pump();
        final session = controller.normalSessionFor(server.connection);
        final local = session.findChat('local')!;
        await tester.enterText(find.byType(TextField), 'Original local draft');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        await widgetUntil(tester, () => server.createEntered.isCompleted);
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(builder: (_) => screen('stored')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        if (active) {
          await tester.enterText(find.byType(TextField), 'Canonical admitted');
          await tester.tap(find.byTooltip('Send'));
          await widgetUntil(tester, () => server.prompts.length == 1);
          await tester.enterText(
            find.byType(TextField),
            'Newer canonical next draft',
          );
        }
        server.releaseCreate();
        await widgetUntil(
          tester,
          () =>
              identical(session.findChat('local'), session.findChat('stored')),
        );
        expect(find.byType(ChatScreen, skipOffstage: false), findsNWidgets(2));
        if (!active) {
          await widgetUntil(tester, () => server.prompts.length == 1);
        }
        server.event('message.delta', {
          'text': 'Shared live answer',
        }, turnId: 'wire-1');
        await widgetUntil(
          tester,
          () => local.snapshot.displayRows.any(
            (r) => r['content'] == 'Shared live answer',
          ),
        );
        expect(find.text('Shared live answer'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Shared live answer'), findsOneWidget);
        server.finish('Final canonical answer');
        await widgetUntil(tester, () => !local.snapshot.hasActiveTurn);
        expect(server.prompts, hasLength(1));
        expect(
          server.prompts.single['text'],
          AndroidPromptContext.forModel(
            active ? 'Canonical admitted' : 'Original local draft',
          ),
        );
        if (active) {
          expect(
            await tester.runAsync(
              () => ComposerDraftStore.read(
                connectionId: server.connection.id,
                sessionId: 'stored',
              ),
            ),
            'Newer canonical next draft',
          );
        }
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(builder: (_) => screen('stored')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await widgetUntil(
          tester,
          () => find.text('Final canonical answer').evaluate().isNotEmpty,
        );
        expect(find.text('Final canonical answer'), findsOneWidget);
        expect(server.prompts, hasLength(1));
        if (active) {
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'Newer canonical next draft',
          );
        }
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.enterText(find.byType(TextField), 'Explicit route retry');
        await tester.tap(find.byTooltip('Send'));
        await widgetUntil(tester, () => server.prompts.length == 2);
        server.finish('Explicit route answer');
        await widgetUntil(tester, () => !local.snapshot.hasActiveTurn);
        expect(
          server.prompts.last['text'],
          AndroidPromptContext.forModel('Explicit route retry'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await controller.close();
        await tester.runAsync(server.close);
        await tester.pump(const Duration(seconds: 16));
      },
    );
  }
}

Future<void> send(
  NormalGatewayChatOwner owner,
  String text, {
  Object? reservation,
}) => owner.submitPrepared(
  reservation: reservation ?? owner.reserve()!,
  text: text,
  localContent: text,
);
Future<void> until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Wire fixture condition did not arrive');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> widgetUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump();
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  fail('Widget/wire fixture condition did not arrive');
}

class BindingServer {
  final HttpServer server;
  void Function(WebSocket socket, Map frame)? observeClientFrame;
  final sockets = <WebSocket>[];
  final createEntered = Completer<void>();
  late void Function() releaseCreate;
  final prompts = <Map<String, dynamic>>[];
  final rows = <Map<String, dynamic>>[];
  int creates = 0;
  int resumes = 0;
  bool historyUnavailable = false;
  bool running = false;
  bool _closed = false;
  BindingServer(this.server);
  SavedConnection get connection => SavedConnection(
    id: 'quality-binding-wire',
    label: 'Fixture',
    host: '127.0.0.1',
    port: server.port,
    apiKey: 'fixture',
    dashboardPortOverride: server.port,
    dashboardProxied: true,
  );
  static Future<BindingServer> start() async {
    final owner = BindingServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    owner.server.listen(owner.handle);
    return owner;
  }

  Future<void> untilPrompts(int count) => until(() => prompts.length >= count);
  Future<void> handle(HttpRequest request) async {
    if (request.uri.path == '/api/auth/ws-ticket') {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ticket":"fixture"}');
      await request.response.close();
      return;
    }
    if (request.uri.path.endsWith('/messages')) {
      request.response.headers.contentType = ContentType.json;
      if (historyUnavailable) request.response.statusCode = 404;
      request.response.write(jsonEncode({'data': rows}));
      await request.response.close();
      return;
    }
    if (request.uri.path != '/api/ws') {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'gateway.ready', 'payload': {}},
      }),
    );
    socket.listen((raw) {
      if (_closed) return;
      final frame = jsonDecode(raw as String) as Map;
      observeClientFrame?.call(socket, frame);
      final method = frame['method'];
      if (method == null) return;
      final result = <String, dynamic>{'jsonrpc': '2.0', 'id': frame['id']};
      if (method == 'config.get' && frame['params']['key'] == 'full') {
        result['result'] = {'config': <String, dynamic>{}};
      } else if (method == 'session.resume') {
        resumes++;
        if (creates == 0) {
          result['error'] = {'code': 4007, 'message': 'session not found'};
        } else {
          result['result'] = {
            'session_id': 'runtime',
            'stored_session_id': 'stored',
            'running': running,
            'status': running
                ? 'running'
                : rows.isEmpty
                ? 'idle'
                : 'completed',
          };
        }
      } else if (method == 'session.create') {
        creates++;
        result['result'] = {
          'session_id': 'runtime',
          'stored_session_id': 'stored',
          'message_count': 0,
          'messages': [],
        };
        final encoded = jsonEncode(result);
        releaseCreate = () => socket.add(encoded);
        createEntered.complete();
        return;
      } else {
        if (method == 'prompt.submit') {
          prompts.add(Map<String, dynamic>.from(frame['params'] as Map));
          running = true;
        }
        result['result'] = {'ok': true};
      }
      if (socket.readyState == WebSocket.open) socket.add(jsonEncode(result));
    });
  }

  void event(String type, Map<String, dynamic> payload, {String? turnId}) =>
      sockets.last.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': type,
            'session_id': 'runtime',
            'turn_id': ?turnId,
            'payload': payload,
          },
        }),
      );
  void finish(String answer) {
    running = false;
    rows.addAll([
      {'id': rows.length + 1, 'role': 'user', 'content': prompts.last['text']},
      {'id': rows.length + 2, 'role': 'assistant', 'content': answer},
    ]);
    final id = 'wire-${prompts.length}';
    event('message.start', {}, turnId: id);
    event('message.complete', {'text': answer}, turnId: id);
    event('turn.end', {}, turnId: id);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
