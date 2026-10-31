import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/services/memory_repository.dart';
import 'package:hermes_android/core/services/mobile_push_service.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mtls_fixture.dart';

SavedConnection connection(MutualTlsFixture fixture) => SavedConnection(
  id: 'loopback',
  label: 'loopback',
  host: '127.0.0.1',
  port: fixture.server.port,
  apiKey: 'synthetic-bearer',
  useHttps: true,
  gatewayPrefix: '/gateway',
  dashboardPortOverride: fixture.server.port,
  dashboardPrefix: '/dashboard',
  desktopGatewayUrl: '${fixture.origin}/dashboard',
  dashboardProxied: true,
  gatewayProfile: 'fixture-profile',
  clientCertificate: loopbackIdentity,
);

class _MemoryCredentials implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'stock owner uses the identity for its independent settled-history GET',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async {
        expect(request.uri.path, '/gateway/api/sessions/stored/messages');
        expect(
          request.headers.value('authorization'),
          'Bearer synthetic-bearer',
        );
        fixture.json(request, {
          'data': [
            {'id': 1, 'role': 'user', 'content': 'prompt'},
            {'id': 2, 'role': 'assistant', 'content': 'canonical'},
          ],
        });
        await request.response.close();
      });
      addTearDown(fixture.close);
      await withLoopbackTrust(() async {
        final hydrated = Completer<void>();
        NormalGatewayApplicationSession? session;
        session = NormalGatewayApplicationSession.fromConnection(
          connection(fixture),
          scope: 'mtls-transport',
          onActivityChanged: () {
            if (!hydrated.isCompleted &&
                session
                        ?.findChat('local')
                        ?.snapshot
                        .historyRows
                        .any((r) => r['content'] == 'canonical') ==
                    true) {
              hydrated.complete();
            }
          },
        );
        addTearDown(session.close);
        await session.ready;
        final owner = session.chatFor(
          'local',
          storedSessionId: 'stored',
          title: 'TLS',
        );
        owner.observeHistory([]);
        await owner.submitPrepared(
          reservation: owner.reserve()!,
          text: 'prompt',
          localContent: 'prompt',
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {
                onSent();
                onEvent(
                  StreamEvent(
                    type: 'message.delta',
                    turnId: 'wire-turn',
                    data: const {'text': 'received'},
                  ),
                );
                onEvent(
                  StreamEvent(
                    type: 'turn.end',
                    turnId: 'wire-turn',
                    data: const {'status': 'completed'},
                  ),
                );
              },
        );
        await hydrated.future.timeout(const Duration(seconds: 3));
        expect(fixture.requests, hasLength(1));
        expect(fixture.anonymousRequests, 0);
      });
    },
  );

  test(
    'delegated history wrapper retains the connection TLS identity',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async {
        expect(request.uri.queryParameters['profile'], 'fixture-profile');
        if (request.uri.path.endsWith('/messages')) {
          fixture.json(request, {
            'session_id': 'child',
            'profile': 'fixture-profile',
            'messages': [
              {'id': 1, 'role': 'assistant', 'content': 'child reply'},
            ],
            'pagination': {
              'limit': 50,
              'offset': 0,
              'order': 'latest',
              'returned': 1,
            },
          });
        } else {
          expect(request.uri.path, '/dashboard/api/sessions/child');
          fixture.json(request, {
            'id': 'child',
            'profile': 'fixture-profile',
            'source': 'subagent',
          });
        }
        await request.response.close();
      });
      addTearDown(fixture.close);
      await withLoopbackTrust(() async {
        final history = DashboardTaskHistory.fromConnection(
          connection(fixture),
        );
        addTearDown(history.close);
        final page = await history.fetch('child', 0);
        expect(page.rows.single['content'], 'child reply');
        expect(fixture.requests, hasLength(3));
        expect(fixture.anonymousRequests, 0);
      });
    },
  );

  test(
    'saved memory repository uses TLS without losing profile or facts',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async {
        expect(request.uri.path, '/dashboard/api/learning/graph');
        expect(request.uri.queryParameters['profile'], 'fixture-profile');
        fixture.json(request, {
          'memory': [
            {'source': 'memory', 'body': 'Saved fact over TLS'},
          ],
          'nodes': [
            {
              'kind': 'memory',
              'id': 'memory:memory:0:0123456789ab',
              'memorySource': 'memory',
            },
          ],
        });
        await request.response.close();
      });
      addTearDown(fixture.close);
      await withLoopbackTrust(() async {
        final repository = MemoryRepository.fromConnection(connection(fixture));
        addTearDown(repository.close);
        expect(
          (await repository.loadFacts()).single.content,
          'Saved fact over TLS',
        );
        expect(fixture.requests, hasLength(1));
        expect(fixture.anonymousRequests, 0);
      });
    },
  );

  test(
    'mobile push default client uses TLS before asking native permission',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async {
        expect(
          request.uri.path,
          '/dashboard/api/plugins/mobile-push/capabilities',
        );
        expect(request.uri.queryParameters['profile'], 'fixture-profile');
        fixture.json(request, {
          'schema': 1,
          'registration_fence': 1,
          'enabled': true,
          'transports': ['webpush'],
          'vapid_public_key': base64Url
              .encode([4, ...List.filled(64, 1)])
              .replaceAll('=', ''),
        });
        await request.response.close();
      });
      addTearDown(fixture.close);
      final prefs = await SharedPreferences.getInstance();
      final manager = await ConnectionManager.create(
        prefs,
        credentialStore: _MemoryCredentials(),
      );
      await manager.importConnections([
        connection(fixture),
      ], replaceExisting: false);
      const channel = MethodChannel('mtls-mobile-push-fixture');
      final nativeMethods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeMethods.add(call.method);
            if (call.method == 'permission') return false;
            return <String, dynamic>{'enabled': false};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await withLoopbackTrust(() async {
        final push = MobilePushService(channel: channel, supported: true);
        addTearDown(push.dispose);
        await push.initialize(manager);
        await expectLater(
          push.enable(manager.getConnections().single, 'fixture-distributor', [
            'stored',
          ]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              startsWith('Allow Android notifications'),
            ),
          ),
        );
        expect(nativeMethods, contains('permission'));
        expect(nativeMethods, isNot(contains('enable')));
        expect(fixture.requests, hasLength(1));
        expect(fixture.anonymousRequests, 0);
      });
    },
  );

  test(
    'REST list, SSE chat and WSS present a verified client certificate',
    () async {
      final fixture = MutualTlsFixture();
      await fixture.start((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          fixture.sockets.add(socket);
          socket.listen((raw) {
            final message = jsonDecode(raw as String) as Map<String, dynamic>;
            fixture.rpcRequests.add(message);
            if (message['id'] != null) {
              socket.add(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'id': message['id'],
                  'result': {'ok': true},
                }),
              );
            }
          });
        } else if (request.uri.path.endsWith('/v1/chat/completions')) {
          expect(
            request.headers.value('authorization'),
            'Bearer synthetic-bearer',
          );
          expect(request.headers.value('x-hermes-session-id'), 'stored');
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect((body['messages'] as List).last, {
            'role': 'user',
            'content': AndroidPromptContext.forModel('prompt'),
          });
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"content":"TLS reply"}}]}\n\ndata: [DONE]\n\n',
          );
          await request.response.close();
        } else {
          expect(request.uri.path, '/gateway/api/sessions');
          fixture.json(request, {'data': [], 'has_more': false});
          await request.response.close();
        }
      });
      addTearDown(fixture.close);
      await withLoopbackTrust(() async {
        final c = connection(fixture);
        final api = ApiClient(
          baseUrl: c.baseUrl,
          apiKey: c.apiKey,
          pathPrefix: c.gatewayPrefix!,
          clientCertificate: c.clientCertificate,
        );
        addTearDown(api.close);
        expect(await api.getSessions(), isEmpty);
        final tokens = <String>[];
        final errors = <String>[];
        var done = false;
        await GatewayChatClient(api).sendMessageStreaming(
          message: 'prompt',
          sessionId: 'stored',
          onToken: tokens.add,
          onDone: () => done = true,
          onError: errors.add,
        );
        expect(tokens.join(), 'TLS reply');
        expect(done, isTrue);
        expect(errors, isEmpty);
        final ws = WsClient(
          '${fixture.origin}/dashboard',
          ticket: 'fixture-ticket',
          clientCertificate: c.clientCertificate,
          heartbeatInterval: Duration.zero,
          heartbeatDeadline: Duration.zero,
        );
        addTearDown(ws.close);
        await ws.connect();
        expect(ws.isConnected, isTrue);
        expect((await ws.send('fixture.echo', {}))['result'], {'ok': true});
        expect(fixture.rpcRequests.single['method'], 'fixture.echo');
        expect(fixture.requests.map((r) => r.uri.path), [
          '/gateway/api/sessions',
          '/gateway/v1/chat/completions',
          '/dashboard/api/ws',
        ]);
        expect(fixture.anonymousRequests, 0);
      });
    },
  );
}
