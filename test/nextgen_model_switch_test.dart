import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/chat_view.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedConnection _connection() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
  dashboardProxied: true,
);

class _RecordedCall {
  final String method;
  final Map<String, dynamic> params;
  const _RecordedCall(this.method, this.params);
}

class _FakeGateway extends NextGenGateway {
  _FakeGateway(
    super.connection, {
    super.dashboard,
    required this.onCall,
    Map<String, dynamic>? ready,
  }) {
    readyFrame = ready;
  }

  final Future<Map<String, dynamic>> Function(
    String method,
    Map<String, dynamic> params,
  )
  onCall;

  final List<_RecordedCall> calls = [];
  final WsClient _dummySocket = WsClient('http://10.0.0.5:9119');

  @override
  Future<WsClient> connected({
    Duration timeout = const Duration(seconds: 20),
  }) async => _dummySocket;

  @override
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    calls.add(_RecordedCall(method, Map<String, dynamic>.from(params)));
    return onCall(method, params);
  }
}

MockClient _mockHttp() => MockClient((request) async {
  if (request.url.path.endsWith('/model/options')) {
    return http.Response(
      jsonEncode({
        'providers': [
          {
            'slug': 'openai',
            'name': 'OpenAI',
            'models': ['gpt-5-mini'],
          },
          {
            'slug': 'anthropic',
            'name': 'Anthropic',
            'models': ['claude-sonnet-4', 'claude-opus-4'],
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  if (request.url.path.contains('/messages')) {
    return http.Response(
      jsonEncode({'messages': const <Object>[]}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response(
    jsonEncode({'model': 'gpt-5-mini', 'provider': 'openai'}),
    200,
    headers: {'content-type': 'application/json'},
  );
});

Widget _app(
  NgChatController chat,
  NextGenGateway gateway,
  ConnectionManager connections,
) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: nextGenTheme(Brightness.dark, NextGenLook.instance),
  home: NgScope(
    connManager: connections,
    gateway: gateway,
    connections: [gateway.connection],
    switchTo: (_) async {},
    addGateway: () async {},
    signOut: (_) async {},
    reload: () async {},
    signInAgain: () async {},
    child: Scaffold(
      body: NgChatView(chat: chat, onOpenSidebar: () {}, onNewChat: () {}),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NextGenLook.instance
      ..themeMode = ThemeMode.dark
      ..accent = NgAccent.blue
      ..pureBlack = false
      ..glow = true;
  });

  test('new chat sends picked model and reasoning in session.create', () async {
    final gateway = _FakeGateway(
      _connection(),
      ready: const {
        'params': {
          'type': 'gateway.ready',
          'payload': {'session_authority': true},
        },
      },
      onCall: (method, params) async {
        if (method == 'session.create') {
          return {
            'session_id': 'rt-new',
            'stored_session_id': 'stored-new',
            'revision': 1,
            'execution_generation': 0,
            'info': {
              'model': params['model'],
              'provider': params['provider'],
              'reasoning_effort': params['reasoning'],
            },
          };
        }
        if (method == 'prompt.submit') {
          return {'status': 'started'};
        }
        return const {};
      },
    );
    final chat = NgChatController(gateway);
    addTearDown(() {
      chat.dispose();
      gateway.dispose();
    });

    final pick = await chat.setModel(
      provider: 'anthropic',
      model: 'claude-sonnet-4',
    );
    expect(pick, isA<NgModelSwitchDone>());
    await chat.setReasoning('high');
    expect(gateway.calls, isEmpty);

    final sent = await chat.send('Hello');
    expect(sent, isTrue);

    final create = gateway.calls.singleWhere(
      (c) => c.method == 'session.create',
    );
    expect(create.params['model'], 'claude-sonnet-4');
    expect(create.params['provider'], 'anthropic');
    expect(create.params['reasoning'], 'high');
    expect(gateway.calls.where((c) => c.method == 'config.set'), isEmpty);
  });

  test(
    'new chat reports error if gateway ignores picked model on create',
    () async {
      final gateway = _FakeGateway(
        _connection(),
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          if (method == 'session.create') {
            return {
              'session_id': 'rt-new',
              'stored_session_id': 'stored-new',
              'revision': 1,
              'execution_generation': 0,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          return const {};
        },
      );
      final chat = NgChatController(gateway);
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      await chat.setModel(provider: 'anthropic', model: 'claude-sonnet-4');
      final sent = await chat.send('Hello');
      expect(sent, isFalse);
      expect(chat.model, 'gpt-5-mini');
      expect(chat.error, contains('gpt-5-mini'));
      expect(gateway.calls.where((c) => c.method == 'prompt.submit'), isEmpty);
    },
  );

  test(
    'existing chat on session-authority gateway sends session.mutate',
    () async {
      final gateway = _FakeGateway(
        _connection(),
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          if (method == 'session.resume') {
            return {
              'session_id': 'rt-1',
              'revision': 4,
              'execution_generation': 2,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          if (method == 'session.mutate') {
            return {
              'session_id': 'rt-1',
              'revision': 5,
              'execution_generation': 2,
              'status': 'applied',
            };
          }
          return const {};
        },
      );
      final chat = NgChatController(gateway, sessionId: 'stored-1');
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      final outcome = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-sonnet-4',
      );
      expect(outcome, isA<NgModelSwitchDone>());
      expect(chat.model, 'claude-sonnet-4');
      expect(chat.provider, 'anthropic');

      final mutate = gateway.calls.singleWhere(
        (c) => c.method == 'session.mutate',
      );
      expect(mutate.params['session_id'], 'rt-1');
      expect(mutate.params['expected_revision'], 4);
      expect(mutate.params['expected_generation'], 2);
      expect(mutate.params['operation'], 'model');
      expect(mutate.params['payload'], {
        'model': 'claude-sonnet-4',
        'provider': 'anthropic',
      });
    },
  );

  test(
    'confirmation_required rolls label back until confirmed with token',
    () async {
      final gateway = _FakeGateway(
        _connection(),
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          if (method == 'session.resume') {
            return {
              'session_id': 'rt-1',
              'revision': 4,
              'execution_generation': 2,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          if (method == 'session.mutate') {
            final payload = Map<String, dynamic>.from(params['payload'] as Map);
            if (payload['confirm'] == 'tok-expensive') {
              return {
                'session_id': 'rt-1',
                'revision': 5,
                'execution_generation': 2,
                'status': 'applied',
              };
            }
            return {
              'session_id': 'rt-1',
              'status': 'confirmation_required',
              'confirm': 'tok-expensive',
              'confirm_message': 'Costs more',
            };
          }
          return const {};
        },
      );
      final chat = NgChatController(gateway, sessionId: 'stored-1');
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      final first = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
      );
      expect(first, isA<NgModelSwitchNeedsConfirmation>());
      expect((first as NgModelSwitchNeedsConfirmation).message, 'Costs more');
      expect(chat.model, 'gpt-5-mini');
      expect(chat.provider, 'openai');

      // An unconfirmed re-pick must never auto-confirm.
      final unconfirmed = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
      );
      expect(unconfirmed, isA<NgModelSwitchNeedsConfirmation>());
      expect(chat.model, 'gpt-5-mini');

      final confirmed = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
        confirm: true,
      );
      expect(confirmed, isA<NgModelSwitchDone>());
      expect(chat.model, 'claude-opus-4');
      expect(chat.provider, 'anthropic');

      final mutates = gateway.calls
          .where((c) => c.method == 'session.mutate')
          .toList();
      expect(mutates, hasLength(3));
      expect((mutates[0].params['payload'] as Map)['confirm'], isNull);
      expect((mutates[1].params['payload'] as Map)['confirm'], isNull);
      expect((mutates[2].params['payload'] as Map)['confirm'], 'tok-expensive');
    },
  );

  test(
    'revision_conflict adopts fresh revision and retries once with new request_id',
    () async {
      var mutateCalls = 0;
      final gateway = _FakeGateway(
        _connection(),
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          if (method == 'session.resume') {
            return {
              'session_id': 'rt-1',
              'revision': 4,
              'execution_generation': 2,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          if (method == 'session.mutate') {
            mutateCalls++;
            if (mutateCalls == 1) {
              throw JsonRpcError(
                'session.mutate',
                'Revision conflict',
                reason: 'revision_conflict',
                data: const {'reason': 'revision_conflict', 'revision': 7},
              );
            }
            return {
              'session_id': 'rt-1',
              'revision': 8,
              'execution_generation': 2,
              'status': 'applied',
            };
          }
          return const {};
        },
      );
      final chat = NgChatController(gateway, sessionId: 'stored-1');
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      final outcome = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-sonnet-4',
      );
      expect(outcome, isA<NgModelSwitchDone>());
      expect(chat.model, 'claude-sonnet-4');

      final mutates = gateway.calls
          .where((c) => c.method == 'session.mutate')
          .toList();
      expect(mutates, hasLength(2));
      expect(mutates[0].params['expected_revision'], 4);
      expect(mutates[1].params['expected_revision'], 7);
      expect(
        mutates[1].params['request_id'],
        isNot(equals(mutates[0].params['request_id'])),
      );
    },
  );

  test(
    'transport failure retains request_id and sent confirmation token for exact retry',
    () async {
      var confirmedAttempts = 0;
      final gateway = _FakeGateway(
        _connection(),
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          if (method == 'session.resume') {
            return {
              'session_id': 'rt-1',
              'revision': 4,
              'execution_generation': 2,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          if (method == 'session.mutate') {
            final payload = Map<String, dynamic>.from(params['payload'] as Map);
            if (payload['confirm'] == 'tok-keep') {
              confirmedAttempts++;
              if (confirmedAttempts == 1) {
                throw StateError('Connection lost mid-reply');
              }
              return {
                'session_id': 'rt-1',
                'revision': 5,
                'execution_generation': 2,
                'status': 'applied',
              };
            }
            return {
              'session_id': 'rt-1',
              'status': 'confirmation_required',
              'confirm': 'tok-keep',
              'confirm_message': 'Costs more',
            };
          }
          return const {};
        },
      );
      final chat = NgChatController(gateway, sessionId: 'stored-1');
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      final ask = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
      );
      expect(ask, isA<NgModelSwitchNeedsConfirmation>());

      final lost = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
        confirm: true,
      );
      expect(lost, isA<NgModelSwitchFailed>());
      expect(chat.model, 'gpt-5-mini');

      final retried = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
      );
      expect(retried, isA<NgModelSwitchDone>());
      expect(chat.model, 'claude-opus-4');

      final mutates = gateway.calls
          .where((c) => c.method == 'session.mutate')
          .toList();
      expect(mutates, hasLength(3));
      expect(mutates[2].params['request_id'], mutates[1].params['request_id']);
      expect((mutates[2].params['payload'] as Map)['confirm'], 'tok-keep');
    },
  );

  test(
    'legacy gateway falls back to session.mutate on use_session_mutation_model and rolls back on failure',
    () async {
      var failMutate = false;
      final gateway = _FakeGateway(
        _connection(),
        onCall: (method, params) async {
          if (method == 'session.resume') {
            return {
              'session_id': 'rt-1',
              'revision': 3,
              'execution_generation': 1,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          if (method == 'config.set') {
            throw JsonRpcError(
              'config.set',
              'use_session_mutation_model',
              reason: 'use_session_mutation_model',
            );
          }
          if (method == 'session.mutate') {
            if (failMutate) {
              throw JsonRpcError(
                'session.mutate',
                'Unknown model',
                reason: 'model_resolution_failed',
              );
            }
            return {
              'session_id': 'rt-1',
              'revision': 4,
              'execution_generation': 1,
              'status': 'applied',
            };
          }
          return const {};
        },
      );
      final chat = NgChatController(gateway, sessionId: 'stored-1');
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      final fallback = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-sonnet-4',
      );
      expect(fallback, isA<NgModelSwitchDone>());
      expect(chat.model, 'claude-sonnet-4');
      expect(gateway.calls.any((c) => c.method == 'config.set'), isTrue);
      expect(gateway.calls.any((c) => c.method == 'session.mutate'), isTrue);

      failMutate = true;
      final failed = await chat.setModel(
        provider: 'openai',
        model: 'nonexistent-model',
      );
      expect(failed, isA<NgModelSwitchFailed>());
      expect(chat.model, 'claude-sonnet-4');
      expect(chat.provider, 'anthropic');
      expect(chat.error, contains('Unknown model'));
    },
  );

  test(
    'pick while stored chat is still attaching waits for attach and mutates',
    () async {
      final resumeGate = Completer<Map<String, dynamic>>();
      final gateway = _FakeGateway(
        _connection(),
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          if (method == 'session.resume') {
            return resumeGate.future;
          }
          if (method == 'session.mutate') {
            return {
              'session_id': 'rt-attached',
              'revision': 10,
              'execution_generation': 3,
              'status': 'applied',
            };
          }
          return const {};
        },
      );
      final httpClient = _mockHttp();
      final dashboard = DashboardClient(
        host: '10.0.0.5',
        proxied: true,
        httpClient: httpClient,
      );
      final gatewayWithHttp = _FakeGateway(
        _connection(),
        dashboard: dashboard,
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: gateway.onCall,
      );
      final chat = NgChatController(gatewayWithHttp, sessionId: 'stored-1');
      addTearDown(() {
        chat.dispose();
        gatewayWithHttp.dispose();
        gateway.dispose();
        httpClient.close();
      });

      final openFuture = chat.open();
      await Future<void>.delayed(Duration.zero);
      expect(chat.runtimeId, isNull);

      final switchFuture = chat.setModel(
        provider: 'anthropic',
        model: 'claude-sonnet-4',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        gatewayWithHttp.calls.where((c) => c.method == 'session.mutate'),
        isEmpty,
      );

      resumeGate.complete({
        'session_id': 'rt-attached',
        'revision': 9,
        'execution_generation': 3,
        'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
      });

      final outcome = await switchFuture;
      await openFuture;
      expect(outcome, isA<NgModelSwitchDone>());
      expect(chat.model, 'claude-sonnet-4');
      final mutate = gatewayWithHttp.calls.singleWhere(
        (c) => c.method == 'session.mutate',
      );
      expect(mutate.params['session_id'], 'rt-attached');
      expect(mutate.params['expected_revision'], 9);
      expect(mutate.params['expected_generation'], 3);
    },
  );

  testWidgets(
    'model sheet handles confirmation dialog, cancel, and deferred toast',
    (tester) async {
      final httpClient = _mockHttp();
      final dashboard = DashboardClient(
        host: '10.0.0.5',
        proxied: true,
        httpClient: httpClient,
      );
      final gateway = _FakeGateway(
        _connection(),
        dashboard: dashboard,
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          if (method == 'session.resume') {
            return {
              'session_id': 'rt-ui',
              'revision': 2,
              'execution_generation': 1,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          if (method == 'session.mutate') {
            final payload = Map<String, dynamic>.from(params['payload'] as Map);
            if (payload['model'] == 'claude-opus-4') {
              if (payload['confirm'] == 'tok-ui') {
                return {
                  'session_id': 'rt-ui',
                  'revision': 3,
                  'execution_generation': 1,
                  'status': 'applied',
                };
              }
              return {
                'session_id': 'rt-ui',
                'status': 'confirmation_required',
                'confirm': 'tok-ui',
                'confirm_message': 'High cost model',
              };
            }
            return {
              'session_id': 'rt-ui',
              'revision': 4,
              'execution_generation': 1,
              'status': 'deferred',
            };
          }
          return const {};
        },
      );
      final prefs = await SharedPreferences.getInstance();
      final chat = NgChatController(gateway, sessionId: 'stored-ui');
      await chat.open();
      await tester.pumpWidget(_app(chat, gateway, ConnectionManager(prefs)));
      await tester.pumpAndSettle();
      expect(chat.model, 'gpt-5-mini');

      // Open model sheet, pick guarded model, cancel confirmation.
      await tester.tap(find.byKey(const ValueKey('ng-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ng-model-provider-anthropic')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('claude-opus-4', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('claude-opus-4'));
      await tester.pumpAndSettle();
      expect(find.text('Switch model?'), findsOneWidget);
      expect(find.text('High cost model'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(chat.model, 'gpt-5-mini');

      // Pick guarded model again and confirm.
      await tester.ensureVisible(
        find.text('claude-opus-4', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('claude-opus-4'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ng-confirm-model-switch')));
      await tester.pumpAndSettle();
      expect(chat.model, 'claude-opus-4');

      // Pick another model whose switch is deferred while a turn is running.
      await tester.tap(find.byKey(const ValueKey('ng-model-picker')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('ng-model-provider-anthropic')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('claude-sonnet-4', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('claude-sonnet-4'));
      await tester.pumpAndSettle();
      expect(chat.model, 'claude-sonnet-4');
      expect(
        find.text('Switches to claude-sonnet-4 at the next turn.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      chat.dispose();
      gateway.dispose();
      httpClient.close();
    },
  );

  test(
    'session.updated rolls back deferred pick on boundary confirmation or refusal',
    () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final gateway = _FakeGateway(
        _connection(),
        ready: const {
          'params': {
            'type': 'gateway.ready',
            'payload': {'session_authority': true},
          },
        },
        onCall: (method, params) async {
          calls.add((method, Map<String, dynamic>.from(params)));
          if (method == 'session.resume') {
            return {
              'session_id': 'rt-def',
              'revision': 2,
              'execution_generation': 1,
              'running': true,
              'info': {'model': 'gpt-5-mini', 'provider': 'openai'},
            };
          }
          if (method == 'session.mutate') {
            final payload = params['payload'] as Map;
            if (payload['confirm'] == 'boundary-tok') {
              return {
                'revision': 5,
                'status': 'applied',
                'model': 'claude-opus-4',
                'info': {'model': 'claude-opus-4', 'provider': 'anthropic'},
              };
            }
            return {'revision': 3, 'status': 'deferred'};
          }
          return const {};
        },
      );
      final chat = NgChatController(gateway, sessionId: 'stored-def');
      await chat.open();

      final deferred = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
      );
      expect(deferred, isA<NgModelSwitchDeferred>());
      expect(chat.model, 'claude-opus-4');

      // At the turn boundary, the guarded deferred pick asks for confirmation
      // and restores the committed model until confirmed.
      gateway.debugEmit(
        StreamEvent(
          type: 'session.updated',
          sessionId: 'rt-def',
          data: const {
            'revision': 4,
            'operation': 'model',
            'status': 'confirmation_required',
            'confirm': 'boundary-tok',
            'confirm_message': 'Expensive model',
            'payload': {'model': 'claude-opus-4', 'provider': 'anthropic'},
            'committed_model': 'gpt-5-mini',
            'committed_provider': 'openai',
          },
        ),
      );
      await pumpEventQueue();
      expect(chat.model, 'gpt-5-mini');
      expect(chat.provider, 'openai');
      expect(chat.error, 'Expensive model');

      // Confirming uses the boundary token.
      final confirmed = await chat.setModel(
        provider: 'anthropic',
        model: 'claude-opus-4',
        confirm: true,
      );
      expect(confirmed, isA<NgModelSwitchDone>());
      expect(chat.model, 'claude-opus-4');
      final lastMutate = calls.last.$2;
      expect((lastMutate['payload'] as Map)['confirm'], 'boundary-tok');

      // A later deferred pick that is refused at the boundary rolls back too.
      await chat.setModel(provider: 'openai', model: 'o3-pro');
      expect(chat.model, 'o3-pro');
      gateway.debugEmit(
        StreamEvent(
          type: 'session.updated',
          sessionId: 'rt-def',
          data: const {
            'revision': 6,
            'operation': 'model',
            'status': 'refused',
            'reason': 'model_unavailable',
            'target_model': 'o3-pro',
            'model': 'claude-opus-4',
            'provider': 'anthropic',
          },
        ),
      );
      await pumpEventQueue();
      expect(chat.model, 'claude-opus-4');
      expect(chat.provider, 'anthropic');
      expect(chat.error, 'model_unavailable');

      chat.dispose();
      gateway.dispose();
    },
  );
}
