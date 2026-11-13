import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/hermes_sign_in.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/main.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/model_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedConnection _singleLogin() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  dashboardPortOverride: 9119,
  singleLogin: true,
  signInMethod: 'none',
);

NgServerRequest _request(String method, Map<String, dynamic> params) =>
    NgServerRequest(
      GatewayServerRequest.forTesting(id: 'r1', method: method, params: params),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HermesSignInVault.resetForTesting(MemorySignInSecretStore());
  });

  group('SavedConnection single login', () {
    test('round-trips and authenticates the dashboard', () {
      final conn = _singleLogin();
      final restored = SavedConnection.fromMap(conn.toMap());
      expect(restored.singleLogin, isTrue);
      expect(restored.signInMethod, 'none');
      expect(restored.singleLoginUrl, 'http://10.0.0.5:9119');
      expect(restored.hasDashboardAuth, isTrue);
      expect(restored.usesBrowserSignIn, isFalse);
      expect(
        restored.copyWith(signInMethod: 'browser').usesBrowserSignIn,
        isTrue,
      );
    });

    test('ApiClient.forConnection reads chats from the dashboard', () {
      final api = ApiClient.forConnection(_singleLogin());
      expect(api.baseUrl, 'http://10.0.0.5:9119');
    });
  });

  group('NgInputRequest', () {
    test('approval offers once, session, always and deny in order', () {
      final parsed = NgInputRequest.parse(
        _request('approval', {
          'session_id': 's',
          'command': 'rm -rf build',
          'description': 'Clean the build',
        }),
      )!;
      expect(parsed.kind, NgRequestKind.approval);
      expect(parsed.choices, ['once', 'session', 'always', 'deny']);
      expect(parsed.command, 'rm -rf build');
      expect(parsed.body, 'Clean the build');
    });

    test('smart-denied approval only allows once or deny', () {
      final parsed = NgInputRequest.parse(
        _request('approval', {'smart_denied': true}),
      )!;
      expect(parsed.choices, ['once', 'deny']);
    });

    test('clarify reads a question batch', () {
      final parsed = NgInputRequest.parse(
        _request('clarify', {
          'questions': [
            {
              'qid': 'a',
              'question': 'Which branch?',
              'choices': ['main', 'dev'],
            },
            {'qid': 'b', 'question': 'Why?'},
          ],
        }),
      )!;
      expect(parsed.kind, NgRequestKind.clarify);
      expect(parsed.questions, hasLength(2));
      expect(parsed.questions.first.choices, ['main', 'dev']);
    });

    test('sudo and vault prompts are secrets', () {
      expect(
        NgInputRequest.parse(_request('sudo', {}))!.kind,
        NgRequestKind.secret,
      );
      final code = NgInputRequest.parse(
        _request('vault.code', {'site': 'github.com'}),
      )!;
      expect(code.masked, isFalse);
      expect(
        NgInputRequest.parse(_request('vault.save_login', {}))!.kind,
        NgRequestKind.saveLogin,
      );
      expect(NgInputRequest.parse(_request('unknown', {})), isNull);
    });
  });

  test('NgUsage reads the gateway usage fields', () {
    final u = NgUsage.parse({
      'input_tokens': 1200,
      'output_tokens': 300,
      'estimated_cost_usd': 0.0123,
      'context_used': 5000,
      'context_max': 200000,
      'api_calls': 2,
    })!;
    expect(u.input, 1200);
    expect(u.output, 300);
    expect(u.cost, closeTo(0.0123, 1e-9));
    expect(u.contextMax, 200000);
    expect(u.calls, 2);
    expect(NgUsage.parse('nope'), isNull);
  });

  test('parseModelOptions drops unavailable models and empty providers', () {
    final providers = parseModelOptions({
      'providers': [
        {
          'slug': 'openrouter',
          'name': 'OpenRouter',
          'models': ['a/b', 'c/d', 'a/b'],
          'unavailable_models': ['c/d'],
        },
        {'slug': 'empty', 'models': []},
        {
          'slug': 'anthropic',
          'models': [
            {'id': 'claude-x'},
          ],
        },
      ],
    });
    expect(providers.map((p) => p.slug), ['openrouter', 'anthropic']);
    expect(providers.first.models, ['a/b']);
    expect(providers.last.name, 'anthropic');
    expect(ngEffortLabel('xhigh'), 'Extra high');
    expect(ngEffortLabel(null), 'Default');
  });

  group('NgChatController', () {
    late NextGenGateway gateway;
    late NgChatController chat;

    setUp(() {
      gateway = NextGenGateway(_singleLogin());
      chat = NgChatController(gateway, sessionId: 'stored');
      chat.runtimeId = 'rt';
    });

    tearDown(() {
      chat.dispose();
      gateway.dispose();
    });

    StreamEvent ev(String type, [Map<String, dynamic> data = const {}]) =>
        StreamEvent(type: type, data: data, sessionId: 'rt');

    test('streams a reply with reasoning and a tool call', () async {
      gateway.debugEmit(ev('message.start'));
      gateway.debugEmit(ev('reasoning.delta', {'text': 'Thinking '}));
      gateway.debugEmit(
        ev('tool.start', {
          'tool_id': 't1',
          'name': 'terminal',
          'context': 'ls -la',
        }),
      );
      gateway.debugEmit(ev('status.update', {'text': 'running ls'}));
      await pumpEventQueue();
      expect(chat.running, isTrue);
      expect(chat.status, 'running ls');
      final reply = chat.items.single as NgAssistantItem;
      expect(reply.reasoning, 'Thinking ');
      expect(reply.tools.single.running, isTrue);
      expect(reply.tools.single.detail, 'ls -la');

      gateway.debugEmit(
        ev('tool.complete', {
          'tool_id': 't1',
          'duration_s': 0.4,
          'result': 'two files',
        }),
      );
      gateway.debugEmit(ev('message.delta', {'text': 'Done '}));
      gateway.debugEmit(ev('message.delta', {'text': 'here.'}));
      gateway.debugEmit(
        ev('message.complete', {
          'usage': {'input_tokens': 10, 'output_tokens': 4},
        }),
      );
      await pumpEventQueue();
      expect(reply.text, 'Done here.');
      expect(reply.tools.single.running, isFalse);
      expect(reply.tools.single.output, 'two files');
      expect(reply.tools.single.durationSeconds, 0.4);
      expect(reply.outputTokens, 4);
      expect(chat.running, isFalse);
      expect(reply.open, isFalse);
    });

    test('ignores events for other sessions', () async {
      gateway.debugEmit(
        StreamEvent(
          type: 'message.delta',
          data: const {'text': 'x'},
          sessionId: 'someone-else',
        ),
      );
      await pumpEventQueue();
      expect(chat.items, isEmpty);
    });

    test('routes an approval to the chat and answers it', () async {
      Map<String, dynamic>? answered;
      gateway.debugRequest(
        GatewayServerRequest.forTesting(
          id: 'ap1',
          method: 'approval',
          params: {'session_id': 'rt', 'command': 'git push'},
          respond: (result) {
            answered = result;
            return true;
          },
        ),
      );
      await pumpEventQueue();
      expect(chat.request?.kind, NgRequestKind.approval);
      expect(gateway.needsYou, contains('rt'));
      expect(chat.answerApproval('session'), isTrue);
      expect(answered, {'choice': 'session'});
      expect(chat.request, isNull);
      expect(gateway.openRequests, isEmpty);
    });

    test('a turn error ends the turn and keeps queued prompts', () async {
      gateway.debugEmit(ev('message.start'));
      await pumpEventQueue();
      chat.enqueue('next one');
      expect(chat.queued.single.text, 'next one');
      gateway.debugEmit(ev('turn.error', {'message': 'Provider down'}));
      await pumpEventQueue();
      expect(chat.running, isFalse);
      expect(chat.error, 'Provider down');
    });
  });

  test('NextGenPreferences persist look and interface choice', () async {
    final prefs = await SharedPreferences.getInstance();
    await NextGenPreferences.setEnabled(prefs, true);
    await NextGenPreferences.setAccent(prefs, NgAccent.green);
    await NextGenPreferences.setThemeMode(prefs, ThemeMode.dark);
    await NextGenPreferences.pushRecentModel(prefs, 'a/b');
    await NextGenPreferences.pushRecentModel(prefs, 'c/d');
    await NextGenPreferences.pushRecentModel(prefs, 'a/b');
    nextGenEnabled.value = false;
    NextGenPreferences.load(prefs);
    expect(nextGenEnabled.value, isTrue);
    expect(NextGenLook.instance.accent, NgAccent.green);
    expect(NextGenLook.instance.themeMode, ThemeMode.dark);
    expect(NextGenPreferences.recentModels(prefs), ['a/b', 'c/d']);
    await NextGenPreferences.setEnabled(prefs, false);
    await NextGenPreferences.setAccent(prefs, NgAccent.blue);
    await NextGenPreferences.setThemeMode(prefs, ThemeMode.system);
  });

  test('nextGenTheme keeps the classic tokens and adds NgColors', () {
    final theme = nextGenTheme(Brightness.dark, NextGenLook.instance);
    expect(theme.extension<NgColors>(), isNotNull);
    expect(theme.extensions.length, greaterThan(1));
  });

  testWidgets('the NextGen switch swaps the whole interface', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    nextGenEnabled.value = false;
    addTearDown(() => nextGenEnabled.value = false);
    await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Hermes'), findsNothing);

    await NextGenPreferences.setEnabled(prefs, true);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Hermes'), findsOneWidget);
    expect(find.text('Dashboard address'), findsOneWidget);
    expect(find.text('Find on my network'), findsOneWidget);

    await tester.tap(find.text('Use the classic interface instead'));
    await tester.pumpAndSettle();
    expect(nextGenEnabled.value, isFalse);
    expect(find.text('Welcome to Hermes'), findsNothing);
    expect(prefs.getBool(NextGenPreferences.enabledKey), isFalse);
  });

  testWidgets('connect screen explains an unreachable address', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await NextGenPreferences.setEnabled(prefs, true);
    addTearDown(() => nextGenEnabled.value = false);
    await tester.pumpWidget(HermesApp(connManager: ConnectionManager(prefs)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ftp://nope');
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('must start with http:// or https://'),
      findsOneWidget,
    );
    unawaited(NextGenPreferences.setEnabled(prefs, false));
    await tester.pumpAndSettle();
  });
}
