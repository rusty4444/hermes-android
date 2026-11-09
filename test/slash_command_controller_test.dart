import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/slash_command_controller.dart';
import 'package:hermes_android/core/models/slash_command.dart';
import 'package:hermes_android/core/widgets/slash_command_dropdown.dart';
import 'package:hermes_android/l10n/app_localizations.dart';

SlashCommandCatalog _catalog({Set<String>? executable}) =>
    SlashCommandCatalog.fromResult({
      'commands': [
        {'name': 'status', 'description': 'Show the session status'},
        {'name': 'model', 'description': 'Choose a model', 'category': 'app'},
        {'name': 'help'},
        {'name': 'steer'},
        {'name': 'nostalgia'},
      ],
      if (executable != null) 'executable': executable.toList(),
    });

void main() {
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

    test('an argument ends the command token', () {
      expect(slashCommandQuery('/model gpt'), isNull);
      expect(slashCommandQuery('/status '), isNull);
    });

    test('a newline ends the command token', () {
      expect(slashCommandQuery('/status\nmore'), isNull);
    });

    test('text without a leading slash does not trigger', () {
      expect(slashCommandQuery(''), isNull);
      expect(slashCommandQuery('status'), isNull);
    });
  });

  group('local filtering', () {
    late SlashCommandController controller;

    setUp(() {
      controller = SlashCommandController(loadCatalog: () async => _catalog());
    });

    tearDown(() => controller.dispose());

    test('the whole catalogue is offered for a lone slash', () async {
      controller.updateText('/');
      await controller.ensureCatalog();
      expect(controller.isOpen, isTrue);
      expect(controller.matches.map((command) => command.name), [
        'status',
        'model',
        'help',
        'steer',
        'nostalgia',
      ]);
    });

    test('prefix matches rank before substring matches', () async {
      controller.updateText('/st');
      await controller.ensureCatalog();
      expect(controller.matches.map((command) => command.name), [
        'status',
        'steer',
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
          'commands': [
            for (var i = 0; i < 12; i++) {'name': 'command$i'},
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
      expect(controller.isExecutable('status'), isFalse);

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

    test('a command that needs the catalogue is never executable', () {
      final controller = SlashCommandController(
        loadCatalog: () async => _catalog(),
      );
      addTearDown(controller.dispose);
      expect(controller.isExecutable('status'), isFalse);
    });
  });

  group('execution set', () {
    test('falls back to the reviewed server set', () async {
      final controller = SlashCommandController(
        loadCatalog: () async => _catalog(),
      );
      addTearDown(controller.dispose);
      await controller.ensureCatalog();

      expect(controller.isExecutable('status'), isTrue);
      expect(controller.isExecutable('cron'), isTrue);
      expect(controller.isExecutable('skills'), isTrue);
      expect(controller.isExecutable('model'), isFalse);
      expect(controller.isExecutable('steer'), isFalse);
    });

    test('a catalogue-provided set replaces the fallback', () async {
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
      expect(find.text('/steer'), findsOneWidget);
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

  group('wire shapes', () {
    test('a bare list of names parses', () {
      final catalog = SlashCommandCatalog.fromResult(['/status', 'help']);
      expect(catalog.commands.map((command) => command.name), [
        'status',
        'help',
      ]);
    });

    test('descriptions and categories are preserved', () {
      final catalog = SlashCommandCatalog.fromResult({
        'commands': [
          {'command': '/status', 'summary': 'Show status', 'group': 'reads'},
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
        'commands': ['', 'with space', 42, null],
      });
      expect(catalog.commands, isEmpty);
    });

    test('exec results carry output', () {
      final result = SlashCommandResult.fromResult({
        'type': 'exec',
        'output': '/status\nok',
      });
      expect(result.kind, SlashCommandResultKind.exec);
      expect(result.isExecuted, isTrue);
      expect(result.text, '/status\nok');
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

    test('unsupported and malformed results stay non-executable', () {
      expect(
        SlashCommandResult.fromResult({'type': 'unsupported_command'}).kind,
        SlashCommandResultKind.unsupported,
      );
      expect(
        SlashCommandResult.fromResult({'type': 'skill', 'message': '  '}).kind,
        SlashCommandResultKind.unsupported,
      );
      expect(
        SlashCommandResult.fromResult(null).kind,
        SlashCommandResultKind.unsupported,
      );
    });
  });
}
