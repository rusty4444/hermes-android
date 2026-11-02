import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

void main() {
  setUp(mockChatImageRecovery);
  for (final profile in <String?>[null, 'secondary']) {
    for (final scenario in _Scenario.values) {
      final dashboard = scenario != _Scenario.apiOnly;
      testWidgets('stored send scenario=$scenario profile=$profile', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final previousOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = previousOverrides);
        final fixture = await tester.runAsync(_PrincipalGateway.start);
        final gateway = fixture!;
        gateway.scenario = scenario;
        final controller = GatewayTurnApplicationController();
        addTearDown(() async {
          await controller.close();
          await gateway.close();
        });
        final connection = SavedConnection(
          id: 'routing',
          label: 'Routing fixture',
          host: '127.0.0.1',
          port: gateway.server.port,
          apiKey: 'fixture-key',
          dashboardPortOverride: gateway.server.port,
          dashboardUsername: dashboard ? 'admin' : null,
          dashboardPassword: dashboard ? 'fixture-password' : null,
          gatewayProfile: profile,
        );
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChatScreen(
              connection: connection,
              session: const Session(
                id: 'S1',
                title: 'Stored dashboard chat',
                model: 'fixture',
                source: 'desktop',
                messageCount: 2,
                isActive: true,
                preview: '',
                startedAt: 1,
              ),
              turnApplicationController: controller,
              testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
            ),
          ),
        );
        await _flush(tester);
        await tester.enterText(find.byType(TextField), 'Routing probe');
        await tester.tap(find.byTooltip('Send'));
        await _flush(tester);
        expect(gateway.apiReads, isNotEmpty);
        if (dashboard) {
          expect(gateway.completions, isEmpty);
          expect(gateway.loginBodies, [
            {
              'provider': 'basic',
              'username': 'admin',
              'password': 'fixture-password',
            },
          ]);
          expect(gateway.ticketCookies, isNotEmpty);
          expect(
            gateway.ticketCookies,
            everyElement('hermes_session_at=fixture-cookie'),
          );
          final resumes = gateway.calls('session.resume');
          expect(resumes, isNotEmpty);
          for (final resume in resumes) {
            expect((resume['params'] as Map)['session_id'], 'S1');
          }
          final submits = gateway.calls('prompt.submit');
          expect(
            submits,
            hasLength(scenario == _Scenario.resumeDenied ? 0 : 1),
          );
          if (submits.isNotEmpty) {
            expect(
              (submits.single['params'] as Map)['session_id'],
              'runtime-S1',
            );
          }
          for (final frame in [...resumes, ...submits]) {
            expect((frame['params'] as Map)['profile'], profile);
          }
          expect(gateway.calls('session.create'), isEmpty);
          expect(gateway.calls('session.open'), isEmpty);
          expect(gateway.calls('turn.reconcile'), isEmpty);
          final snapshot = controller
              .normalSessionFor(connection)
              .findChat('S1')!
              .snapshot;
          if (scenario == _Scenario.deliveryUnknown ||
              scenario == _Scenario.submitDenied) {
            // Emitting a stock request is not proof of execution or completion.
            // No canonical post-turn rows are supplied by this routing fixture.
            expect(snapshot.phase, NormalGatewayTurnPhase.reconciledUnknown);
          } else if (scenario == _Scenario.resumeDenied) {
            expect(snapshot.phase, NormalGatewayTurnPhase.failed);
            expect(snapshot.error, contains('permission_denied'));
          }
        } else {
          expect(gateway.loginBodies, isEmpty);
          expect(gateway.ticketCookies, isEmpty);
          expect(gateway.requests, isEmpty);
          expect(gateway.completions, hasLength(1));
          expect(
            gateway.completions.single['authorization'],
            'Bearer fixture-key',
          );
          expect(find.textContaining('permission_denied'), findsWidgets);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(controller.close);
        await _flush(tester);
      });
    }
  }
}

enum _Scenario {
  apiOnly,
  dashboard,
  resumeDenied,
  submitDenied,
  deliveryUnknown,
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Replays the reporter's two principal-specific contracts, not backend ACLs.
/// The screen selects the actual HTTP/SSE or password/ticket/WebSocket route;
/// no submit, resume, history or transport callback is injected.
class _PrincipalGateway {
  _PrincipalGateway(this.server);
  final HttpServer server;
  final sockets = <WebSocket>[];
  final loginBodies = <Object?>[];
  final ticketCookies = <String?>[];
  final apiReads = <String>[];
  final completions = <Map<String, dynamic>>[];
  final requests = <Map<String, dynamic>>[];
  _Scenario scenario = _Scenario.dashboard;

  static Future<_PrincipalGateway> start() async {
    final gateway = _PrincipalGateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.server.listen(gateway.handle);
    return gateway;
  }

  List<Map<String, dynamic>> calls(String method) =>
      requests.where((frame) => frame['method'] == method).toList();

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/auth/password-login') {
      loginBodies.add(jsonDecode(await utf8.decoder.bind(request).join()));
      request.response.cookies.add(
        Cookie('hermes_session_at', 'fixture-cookie'),
      );
      request.response.write('{"ok":true}');
    } else if (path == '/api/auth/ws-ticket') {
      ticketCookies.add(request.headers.value('cookie'));
      request.response.write('{"ticket":"fixture-ticket"}');
    } else if (path == '/api/ws') {
      expect(request.uri.queryParameters['ticket'], 'fixture-ticket');
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'event',
          'params': {
            'type': 'gateway.ready',
            'payload': {
              'change_events': true,
              'heartbeat': true,
              'replay_epoch': 'fixture',
              'skin': <String, dynamic>{},
            },
          },
        }),
      );
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        requests.add(frame);
        final method = frame['method'];
        if (scenario == _Scenario.deliveryUnknown &&
            method == 'prompt.submit') {
          socket.close();
          return;
        }
        if (scenario == _Scenario.resumeDenied && method == 'session.resume' ||
            scenario == _Scenario.submitDenied && method == 'prompt.submit') {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': frame['id'],
              'error': {
                'code': 4001,
                'message': 'permission_denied',
                'data': {'reason': 'permission_denied'},
              },
            }),
          );
          return;
        }
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': frame['id'],
            'result': switch (method) {
              'session.resume' => {
                'session_id': 'runtime-S1',
                'resumed': 'S1',
                'running': false,
                'status': 'idle',
                'message_count': 2,
                'messages': <Object>[],
              },
              'config.get' => {'config': <String, dynamic>{}},
              'prompt.submit' => {'status': 'streaming'},
              _ => <String, dynamic>{},
            },
          }),
        );
        if (method == 'prompt.submit') {
          socket.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'method': 'event',
              'params': {
                'type': 'message.complete',
                'session_id': 'runtime-S1',
                'payload': {'text': 'Dashboard reply', 'status': 'complete'},
              },
            }),
          );
        }
      });
      return;
    } else if (path == '/v1/chat/completions') {
      completions.add({
        'authorization': request.headers.value('authorization'),
        'body': jsonDecode(await utf8.decoder.bind(request).join()),
      });
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n'
        'data: {"choices":[{"delta":{},"finish_reason":"error"}],'
        '"usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0},'
        '"error":{"message":"permission_denied","type":"RuntimeStoreError"}}\n\n'
        'data: [DONE]\n\n',
      );
    } else if (request.method == 'GET') {
      apiReads.add(path);
      request.response.write(
        jsonEncode({
          'object': 'list',
          'data': <Object>[],
          'session': {'id': 'S1', 'user_id': 'basic:admin', 'archived': false},
        }),
      );
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  Future<void> close() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  }
}
