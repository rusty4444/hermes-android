import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/slash_command_controller.dart';
import 'package:hermes_android/core/models/slash_command.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/widgets/slash_command_dropdown.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/completed_stock_turn.dart';
import 'support/fake_voice_composer_adapter.dart';
import 'support/pump_chat_updates.dart';

const _composerKey = Key('chat-message-composer');

/// The real `commands.catalog` shape (`CommandsCatalogResult`): ordered
/// `pairs`, a DICT of per-command metadata, display `categories`, skills and
/// plugin commands. A realistic slice of a stock gateway profile.
Map<String, Object?> _wireCatalog({Set<String>? executable}) => {
  'pairs': [
    ['/help', 'Show help'],
    ['/status', 'Show the session status'],
    ['/plan', 'Draft a plan before acting'],
    ['/model', 'Choose a model'],
    ['/title', 'Set the chat title'],
    ['/yolo', 'Toggle YOLO mode'],
    ['/cron', 'Manage cron jobs'],
    ['/review', 'Review the working tree'],
    ['/nostalgia', 'Recall an old session'],
    ['/skill:review', 'Review the working tree'],
    ['/logs', 'Show recent gateway log lines'],
  ],
  'sub': {
    'cron': ['list', 'run', 'add'],
  },
  'canon': {'/h': '/help', '/yolo': '/yolo'},
  'commands': {
    '/help': {'argument_mode': 'text', 'desktop': null},
    '/title': {'argument_mode': 'text'},
    '/model': {'argument_mode': 'options', 'desktop': 'model-picker'},
    '/cron': {
      'argument_mode': 'mixed',
      'desktop': null,
      'desktop_subcommands': ['list', 'run'],
    },
  },
  'categories': [
    {
      'name': 'Session',
      'pairs': [
        ['/status', 'Show the session status'],
        ['/title', 'Set the chat title'],
      ],
    },
    {
      'name': 'Config',
      'pairs': [
        ['/yolo', 'Toggle YOLO mode'],
        ['/model', 'Choose a model'],
      ],
    },
    {
      'name': 'TUI',
      'pairs': [
        ['/logs', 'Show recent gateway log lines'],
      ],
    },
  ],
  'skills': {
    '/skill:review': {'usage': 3, 'origin': 'local'},
    // Collides with nothing in `pairs`: no `/<name>` row, no description.
    '/skill:orphan': {'usage': 0, 'origin': 'bundled'},
  },
  'skill_count': 2,
  'warning': '',
  'plugin_commands': {'deploy': 'Deploy the current build'},
  'executable': ?executable?.toList(),
};

/// The real `SlashExecResult` worker/plugin form: `output` (+ `warning`), no
/// `type`. `type` is only set when slash.exec rerouted to command.dispatch.
Map<String, Object?> _workerOutput(String output, {String? warning}) => {
  'output': output,
  'warning': ?warning,
};

SlashCommandCatalog _catalog({Set<String>? executable}) =>
    SlashCommandCatalog.fromResult(_wireCatalog(executable: executable));

/// Slash RPC double: no socket, no gateway process.
class _FakeSlashGateway implements SlashCommandGateway {
  _FakeSlashGateway({
    SlashCommandCatalog? catalog,
    this.result = const SlashCommandResult.exec('ok'),
    this.error,
  }) : catalog = catalog ?? _catalog();

  final SlashCommandCatalog? catalog;
  final SlashCommandResult result;
  final Object? error;
  final List<String> commands = [];
  var catalogLoads = 0;

  @override
  bool get slashCommandsSupported => true;

  @override
  Future<SlashCommandCatalog> fetchSlashCommands({String? sessionId}) async {
    catalogLoads += 1;
    final cached = catalog;
    if (cached == null) throw StateError('gateway offline');
    return cached;
  }

  @override
  Future<SlashCommandResult> runSlashCommand({
    required String sessionId,
    required String command,
    void Function()? onSent,
  }) async {
    commands.add(command);
    onSent?.call();
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(_composerKey)).controller!.text;

/// Notices are stored per connection+session for the process, so every screen
/// test needs its own session identity.
var _pumpedSessions = 0;

Future<void> _pumpChat(
  WidgetTester tester, {
  required SlashCommandGateway slashGateway,
  TestRemotePromptSubmit? remoteSubmit,
  String? sessionId,
}) async {
  final id = sessionId ?? 'slash-session-${_pumpedSessions++}';
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChatScreen(
        connection: SavedConnection(
          id: 'slash-fixture',
          label: 'Slash fixture',
          host: 'slash.invalid',
          port: 8642,
          apiKey: 'fixture-key',
        ),
        session: Session(
          id: id,
          title: 'Slash chat',
          model: 'fixture-model',
          source: 'test',
          messageCount: 0,
          isActive: true,
          preview: '',
          startedAt: 1,
        ),
        testApiClient: ApiClient(
          baseUrl: 'http://slash.invalid',
          apiKey: 'fixture-key',
          httpClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
        ),
        testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        testSlashGateway: slashGateway,
        testRemotePromptSubmit: completedStockTurn(remoteSubmit),
      ),
    ),
  );
  await pumpChatUpdates(tester);
}

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Send'));
  await tester.pump();
  await pumpChatUpdates(tester);
}

void main() {
  setUp(mockChatImageRecovery);
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
  });

  group('trigger detection', () {
    test('lone slash opens an empty query', () {
      expect(slashCommandQuery('/'), '');
    });

    test('leading token is the query', () {
      expect(slashCommandQuery('/mod'), 'mod');
      expect(slashCommandQuery('/status'), 'status');
    });

    test('slash inside prose does not trigger', () {
      expect(slashCommandQuery('please run /status for me'), isNull);
    });

    test('a URL does not trigger', () {
      expect(slashCommandQuery('https://x'), isNull);
      expect(slashCommandQuery('see https://x/y'), isNull);
    });

    test('an argument ends the dropdown token', () {
      expect(slashCommandQuery('/model gpt'), isNull);
      expect(slashCommandQuery('/status '), isNull);
    });

    test('a newline ends the dropdown token', () {
      expect(slashCommandQuery('/status\nmore'), isNull);
    });

    test('text without a leading slash does not trigger', () {
      expect(slashCommandQuery(''), isNull);
      expect(slashCommandQuery('status'), isNull);
    });

    test('the send gate keeps the full invocation', () {
      expect(slashCommandName('/status'), 'status');
      expect(slashCommandName('/yolo on'), 'yolo');
      expect(slashCommandName('/title A B'), 'title');
      expect(slashCommandName('/cron list'), 'cron');
      expect(slashCommandName('/status\nmore'), 'status');
    });

    test('a lone slash is not a command', () {
      expect(slashCommandName('/'), isNull);
      expect(slashCommandName('/ '), isNull);
    });

    test('prose and URLs are not commands', () {
      expect(slashCommandName(''), isNull);
      expect(slashCommandName('status'), isNull);
      expect(slashCommandName('please /status'), isNull);
      expect(slashCommandName('https://x/y'), isNull);
    });
  });

  group('local filtering', () {
    late SlashCommandController controller;

    setUp(() {
      controller = SlashCommandController(
        loadCatalog: () async => _catalog(),
        limit: 20,
      );
    });

    tearDown(() => controller.dispose());

    test('the whole catalogue is offered in gateway order', () async {
      controller.updateText('/');
      await controller.ensureCatalog();
      expect(controller.isOpen, isTrue);
      expect(controller.matches.map((command) => command.name), [
        'help',
        'status',
        'plan',
        'model',
        'title',
        'yolo',
        'cron',
        'review',
        'nostalgia',
        'skill:review',
        'logs',
        'deploy',
        'skill:orphan',
      ]);
    });

    test('prefix matches rank before substring matches', () async {
      controller.updateText('/st');
      await controller.ensureCatalog();
      expect(controller.matches.map((command) => command.name), [
        'status',
        'nostalgia',
      ]);
    });

    test('filtering narrows on every keystroke', () async {
      controller.updateText('/m');
      await controller.ensureCatalog();
      expect(controller.matches.map((command) => command.name), ['model']);

      controller.updateText('/mo');
      expect(controller.matches.map((command) => command.name), ['model']);

      controller.updateText('/moz');
      expect(controller.matches, isEmpty);
      expect(controller.isOpen, isTrue);
    });

    test('closing keeps the draft untouched', () async {
      controller.updateText('/sta');
      await controller.ensureCatalog();
      controller.close();
      expect(controller.isOpen, isFalse);
      expect(controller.query, isEmpty);
    });

    test('leaving the trigger closes the dropdown', () async {
      controller.updateText('/sta');
      await controller.ensureCatalog();
      expect(controller.updateText('/status now'), isFalse);
      expect(controller.isOpen, isFalse);
    });

    test('the visible list is capped', () async {
      final capped = SlashCommandController(
        loadCatalog: () async => SlashCommandCatalog.fromResult({
          'pairs': [
            for (var i = 0; i < 12; i++) ['/command$i', 'Command $i'],
          ],
        }),
        limit: 5,
      );
      addTearDown(capped.dispose);
      capped.updateText('/');
      await capped.ensureCatalog();
      expect(capped.matches, hasLength(5));
    });
  });

  group('catalogue cache', () {
    test('fetches once and reuses the cached catalogue', () async {
      var loads = 0;
      final controller = SlashCommandController(
        loadCatalog: () async {
          loads += 1;
          return _catalog();
        },
      );
      addTearDown(controller.dispose);

      controller.updateText('/');
      await controller.ensureCatalog();
      controller.updateText('/s');
      await controller.ensureCatalog();
      controller.updateText('/st');
      expect(await controller.ensureCatalog(), isTrue);
      expect(loads, 1);
    });

    test('concurrent ensureCatalog calls share one request', () async {
      var loads = 0;
      final controller = SlashCommandController(
        loadCatalog: () async {
          loads += 1;
          return _catalog();
        },
      );
      addTearDown(controller.dispose);

      await Future.wait([
        controller.ensureCatalog(),
        controller.ensureCatalog(),
        controller.ensureCatalog(),
      ]);
      expect(loads, 1);
    });

    test('invalidate refetches on the next request', () async {
      var loads = 0;
      final controller = SlashCommandController(
        loadCatalog: () async {
          loads += 1;
          return _catalog();
        },
      );
      addTearDown(controller.dispose);

      await controller.ensureCatalog();
      expect(loads, 1);
      controller.invalidate();
      expect(controller.catalogLoaded, isFalse);
      await controller.ensureCatalog();
      expect(loads, 2);
    });

    test('a scope change invalidates the cache', () async {
      var loads = 0;
      final controller = SlashCommandController(
        cacheScope: 'connection-a',
        loadCatalog: () async {
          loads += 1;
          return _catalog();
        },
      );
      addTearDown(controller.dispose);

      await controller.ensureCatalog();
      controller.updateScope('connection-a');
      await controller.ensureCatalog();
      expect(loads, 1);

      controller.updateScope('connection-b');
      await controller.ensureCatalog();
      expect(loads, 2);
    });
  });

  group('gateway failure', () {
    test('a failed catalogue disables the dropdown without throwing', () async {
      var loads = 0;
      final controller = SlashCommandController(
        loadCatalog: () async {
          loads += 1;
          throw StateError('gateway offline');
        },
      );
      addTearDown(controller.dispose);

      controller.updateText('/status');
      expect(await controller.ensureCatalog(), isFalse);
      expect(controller.isOpen, isFalse);
      expect(controller.catalogUnavailable, isTrue);
      expect(controller.matches, isEmpty);

      // No retry per keystroke: the composer keeps working, the feature stays
      // off until an explicit invalidation.
      controller.updateText('/sta');
      await controller.ensureCatalog();
      expect(loads, 1);

      controller.invalidate();
      expect(controller.catalogUnavailable, isFalse);
      expect(await controller.ensureCatalog(), isFalse);
      expect(loads, 2);
    });

    test('without a catalogue only the reviewed set is a hint', () {
      final controller = SlashCommandController(
        loadCatalog: () async => _catalog(),
      );
      addTearDown(controller.dispose);
      expect(controller.catalogLoaded, isFalse);
      // Last resort while the catalogue has not answered...
      expect(controller.isExecutable('status'), isTrue);
      // ...and never a claim about a name the reviewed set does not know.
      expect(controller.isExecutable('model'), isFalse);
    });
  });

  group('catalogue execution set', () {
    test('a loaded catalogue is the authority', () async {
      final controller = SlashCommandController(
        loadCatalog: () async => _catalog(),
      );
      addTearDown(controller.dispose);
      await controller.ensureCatalog();

      expect(controller.isExecutable('status'), isTrue);
      expect(controller.isExecutable('cron'), isTrue);
      expect(controller.isExecutable('model'), isTrue);
      expect(controller.isExecutable('deploy'), isTrue);
      expect(controller.isExecutable('/title'), isTrue);
      // In the reviewed fallback but absent from this profile: not executable.
      expect(controller.isExecutable('skills'), isFalse);
      expect(controller.isExecutable('steer'), isFalse);
    });

    test('a legacy explicit set still wins when advertised', () async {
      final controller = SlashCommandController(
        loadCatalog: () async => _catalog(executable: {'model'}),
      );
      addTearDown(controller.dispose);
      await controller.ensureCatalog();

      expect(controller.isExecutable('model'), isTrue);
      expect(controller.isExecutable('status'), isFalse);
    });
  });

  group('dropdown', () {
    testWidgets('lists the filtered commands and reports a choice', (
      tester,
    ) async {
      final controller = SlashCommandController(
        loadCatalog: () async => _catalog(),
      );
      addTearDown(controller.dispose);
      controller.updateText('/st');
      await controller.ensureCatalog();

      SlashCommand? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SlashCommandDropdown(
              controller: controller,
              onSelected: (command) => selected = command,
            ),
          ),
        ),
      );

      expect(find.text('/status'), findsOneWidget);
      expect(find.text('/nostalgia'), findsOneWidget);
      expect(find.text('/model'), findsNothing);

      await tester.tap(find.text('/status'));
      expect(selected?.name, 'status');
    });

    testWidgets('explains an empty result instead of collapsing', (
      tester,
    ) async {
      final controller = SlashCommandController(
        loadCatalog: () async => _catalog(),
      );
      addTearDown(controller.dispose);
      controller.updateText('/zzz');
      await controller.ensureCatalog();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SlashCommandDropdown(
              controller: controller,
              onSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('No matching commands'), findsOneWidget);
      expect(find.text('/status'), findsNothing);
    });
  });

  group('catalogue wire shape', () {
    test('pairs, categories, plugin commands and skills build the list', () {
      final catalog = _catalog();

      expect(catalog.commands.map((command) => command.name), [
        'help',
        'status',
        'plan',
        'model',
        'title',
        'yolo',
        'cron',
        'review',
        'nostalgia',
        'skill:review',
        'logs',
        'deploy',
        'skill:orphan',
      ]);
      expect(catalog.canExecute('title'), isTrue);
      expect(catalog.canExecute('/TITLE'), isTrue);
      expect(catalog.canExecute('not-a-command'), isFalse);
    });

    test('categories label the rows they group', () {
      final byName = {
        for (final command in _catalog().commands) command.name: command,
      };
      expect(byName['status']!.category, 'Session');
      expect(byName['title']!.category, 'Session');
      expect(byName['model']!.category, 'Config');
      expect(byName['logs']!.category, 'TUI');
      expect(byName['help']!.category, isEmpty);
      expect(byName['deploy']!.category, 'Plugin commands');
      expect(byName['skill:orphan']!.category, 'Skills');
    });

    test('plugin commands carry a slash and their description', () {
      final deploy = _catalog().commands
          .firstWhere((command) => command.name == 'deploy');
      expect(deploy.invocation, '/deploy');
      expect(deploy.description, 'Deploy the current build');
    });

    test('a skill without a pairs row keeps an empty description', () {
      final orphan = _catalog().commands
          .firstWhere((command) => command.name == 'skill:orphan');
      expect(orphan.description, isEmpty);
      expect(orphan.invocation, '/skill:orphan');
    });

    test('duplicate names dedupe on their canonical key', () {
      final catalog = SlashCommandCatalog.fromResult({
        'pairs': [
          ['/logs', 'Show recent gateway log lines'],
        ],
        'categories': [
          {
            'name': 'TUI',
            'pairs': [
              ['/logs', 'Show recent gateway log lines'],
            ],
          },
        ],
        // A display row hides this one, but it is still a plugin command.
        'plugin_commands': {'logs': 'Plugin copy'},
      });
      expect(catalog.commands.map((command) => command.name), ['logs']);
      expect(catalog.commands.single.description, 'Show recent gateway log lines');
      expect(catalog.commands.single.category, 'TUI');
    });

    test('aliases resolve to their canonical command', () {
      final catalog = SlashCommandCatalog.fromResult({
        'pairs': [
          ['/help', 'Show help'],
          ['/h', 'alias row'],
        ],
        'canon': {'/h': '/help'},
      });
      expect(catalog.commands.map((command) => command.name), ['help']);
      expect(catalog.canExecute('/h'), isTrue);
      expect(catalog.canExecute('h'), isTrue);
    });

    test('argument_mode attaches from the commands dict', () {
      final byName = {
        for (final command in _catalog().commands) command.name: command,
      };
      expect(byName['help']!.argumentMode, 'text');
      expect(byName['title']!.argumentMode, 'text');
      expect(byName['model']!.argumentMode, 'options');
      expect(byName['cron']!.argumentMode, 'mixed');
      expect(byName['status']!.argumentMode, isNull);
      expect(byName['deploy']!.argumentMode, isNull);
    });

    test('an unknown argument_mode is ignored', () {
      final catalog = SlashCommandCatalog.fromResult({
        'pairs': [
          ['/odd', 'Odd mode'],
        ],
        'commands': {
          '/odd': {'argument_mode': 'freetext'},
        },
      });
      expect(catalog.commands.single.argumentMode, isNull);
    });

    test('a bare list of names still parses', () {
      final catalog = SlashCommandCatalog.fromResult(['/status', 'help']);
      expect(catalog.commands.map((command) => command.name), [
        'status',
        'help',
      ]);
    });

    test('legacy command maps in an entries envelope still parse', () {
      final catalog = SlashCommandCatalog.fromResult({
        'entries': [
          {'name': '/status', 'summary': 'Show status', 'group': 'reads'},
        ],
      });
      final command = catalog.commands.single;
      expect(command.name, 'status');
      expect(command.invocation, '/status');
      expect(command.description, 'Show status');
      expect(command.category, 'reads');
    });

    test('invalid entries are dropped', () {
      final catalog = SlashCommandCatalog.fromResult({
        'pairs': [
          ['', 'empty'],
          ['with space', 'not a command'],
          [42, 'number'],
          [null, 'null'],
        ],
        'plugin_commands': {'': 'empty', ' ok ': 'trimmed'},
      });
      expect(catalog.commands.map((command) => command.name), ['ok']);
    });
  });

  group('slash.exec result shape', () {
    test('typeless output is an exec notice', () {
      final result = SlashCommandResult.fromResult(
        _workerOutput('/status\nok'),
      );
      expect(result.kind, SlashCommandResultKind.exec);
      expect(result.isExecuted, isTrue);
      expect(result.text, '/status\nok');
    });

    test('a warning is appended to the output', () {
      final result = SlashCommandResult.fromResult(
        _workerOutput('/status\nok', warning: 'Session mirror failed'),
      );
      expect(result.kind, SlashCommandResultKind.exec);
      expect(result.text, '/status\nok\n\nSession mirror failed');
      expect(result.text, contains('Session mirror failed'));
    });

    test('a warning alone is still shown', () {
      final result = SlashCommandResult.fromResult({
        'output': '',
        'warning': 'Side effects not mirrored',
      });
      expect(result.kind, SlashCommandResultKind.exec);
      expect(result.text, 'Side effects not mirrored');
    });

    test('output wins over a missing or unknown type', () {
      for (final type in [null, 'exec', 'plugin', 'mystery']) {
        final result = SlashCommandResult.fromResult({
          'type': ?type,
          'output': 'done',
        });
        expect(result.kind, SlashCommandResultKind.exec, reason: '$type');
        expect(result.text, 'done');
      }
    });

    test('skill and send directives become prompts', () {
      for (final type in ['skill', 'send']) {
        final result = SlashCommandResult.fromResult({
          'type': type,
          'message': 'Summarize the repo',
        });
        expect(result.kind, SlashCommandResultKind.prompt);
        expect(result.isPrompt, isTrue);
        expect(result.text, 'Summarize the repo');
      }
    });

    test('a prefill directive fills the composer instead of sending', () {
      final result = SlashCommandResult.fromResult({
        'type': 'prefill',
        'message': 'Explain the diff',
        'display': 'Prefilled',
      });
      expect(result.kind, SlashCommandResultKind.prefill);
      expect(result.isPrefill, isTrue);
      expect(result.text, 'Explain the diff');
    });

    test('an alias directive never re-sends and shows what it named', () {
      expect(
        SlashCommandResult.fromResult({
          'type': 'alias',
          'target': '/status',
          'display': 'Alias for /status',
        }).text,
        'Alias for /status',
      );
      expect(
        SlashCommandResult.fromResult({
          'type': 'alias',
          'target': 'status',
        }).text,
        '/status',
      );
    });

    test('a directive without its payload is a no-output notice', () {
      for (final result in [
        SlashCommandResult.fromResult({'type': 'skill', 'message': '  '}),
        SlashCommandResult.fromResult({'type': 'prefill'}),
        SlashCommandResult.fromResult({'type': 'exec'}),
        SlashCommandResult.fromResult(null),
        SlashCommandResult.fromResult(const <String, Object?>{}),
      ]) {
        expect(result.kind, SlashCommandResultKind.exec);
        expect(result.text, isEmpty);
      }
    });
  });

  group('screen dispatch', () {
    testWidgets("a command with arguments dispatches the full line", (
      tester,
    ) async {
      final gateway = _FakeSlashGateway(
        result: SlashCommandResult.fromResult(
          _workerOutput('YOLO mode enabled'),
        ),
      );
      await _pumpChat(tester, slashGateway: gateway);

      await tester.enterText(find.byKey(_composerKey), '/yolo on');
      await tester.pump();
      await _send(tester);

      expect(gateway.commands, ['/yolo on']);
      // Exec output is a local notice, never a prompt.
      expect(find.byKey(const Key('slash-command-notice')), findsOneWidget);
      expect(find.text('YOLO mode enabled'), findsOneWidget);
      expect(_composerText(tester), isEmpty);
    });

    testWidgets('/title A B keeps its arguments in the RPC', (tester) async {
      final gateway = _FakeSlashGateway(
        result: SlashCommandResult.fromResult(_workerOutput('title set')),
      );
      await _pumpChat(tester, slashGateway: gateway);

      await tester.enterText(find.byKey(_composerKey), '/title A B');
      await tester.pump();
      await _send(tester);

      expect(gateway.commands, ['/title A B']);
    });

    testWidgets('a picked command is persisted as the draft', (tester) async {
      final gateway = _FakeSlashGateway();
      await _pumpChat(
        tester,
        slashGateway: gateway,
        sessionId: 'slash-draft-session',
      );

      await tester.enterText(find.byKey(_composerKey), '/st');
      await tester.pump();
      await tester.tap(find.text('/status'));
      await tester.pump();
      expect(_composerText(tester), '/status ');

      // Leaving the chat persists exactly what typing would have; reopening
      // restores it without any send.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await _pumpChat(
        tester,
        slashGateway: gateway,
        sessionId: 'slash-draft-session',
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('/status '), findsOneWidget);
      expect(gateway.commands, isEmpty);
    });

    testWidgets('a prefill directive fills the composer without sending', (
      tester,
    ) async {
      final gateway = _FakeSlashGateway(
        result: SlashCommandResult.fromResult({
          'type': 'prefill',
          'message': 'Explain the diff',
        }),
      );
      await _pumpChat(tester, slashGateway: gateway);

      await tester.enterText(find.byKey(_composerKey), '/plan');
      await tester.pump();
      await _send(tester);

      expect(gateway.commands, ['/plan']);
      expect(_composerText(tester), 'Explain the diff');
      expect(find.byKey(const Key('slash-command-notice')), findsNothing);
    });

    testWidgets('a send timeout keeps the draft and never submits prose', (
      tester,
    ) async {
      final submitted = <String>[];
      final gateway = _FakeSlashGateway(
        error: JsonRpcError('slash.exec', 'Timeout'),
      );
      await _pumpChat(
        tester,
        slashGateway: gateway,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              submitted.add(text);
            },
      );

      await tester.enterText(find.byKey(_composerKey), '/review');
      await tester.pump();
      await _send(tester);

      expect(gateway.commands, ['/review']);
      expect(submitted, isEmpty);
      expect(_composerText(tester), '/review');
      expect(find.byKey(const Key('slash-command-notice')), findsNothing);
      expect(
        find.textContaining('may still be running on the gateway'),
        findsOneWidget,
      );
    });

    testWidgets('a post-write disconnect is handled as delivery unknown', (
      tester,
    ) async {
      final submitted = <String>[];
      final gateway = _FakeSlashGateway(
        error: JsonRpcError(
          'slash.exec',
          'Desktop gateway connection closed',
          reason: 'connection_closed',
        ),
      );
      await _pumpChat(
        tester,
        slashGateway: gateway,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              submitted.add(text);
            },
      );

      await tester.enterText(find.byKey(_composerKey), '/cron run');
      await tester.pump();
      await _send(tester);

      expect(submitted, isEmpty);
      expect(_composerText(tester), '/cron run');
      expect(
        find.textContaining('may still be running on the gateway'),
        findsOneWidget,
      );
    });

    testWidgets('an unsupported command falls back to the plain send', (
      tester,
    ) async {
      final submitted = <String>[];
      final gateway = _FakeSlashGateway(
        error: JsonRpcError(
          'slash.exec',
          'not a quick/plugin/bundle/skill command: /status',
          code: 4018,
        ),
      );
      await _pumpChat(
        tester,
        slashGateway: gateway,
        remoteSubmit:
            ({
              required sessionId,
              required text,
              required onEvent,
              required onSent,
            }) async {
              onSent();
              submitted.add(text);
            },
      );

      await tester.enterText(find.byKey(_composerKey), '/status');
      await tester.pump();
      await _send(tester);

      expect(gateway.commands, ['/status']);
      expect(submitted, ['/status']);
      expect(_composerText(tester), isEmpty);
    });
  });
}
