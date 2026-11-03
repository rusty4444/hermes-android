import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/background_report.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/utils/chat_conversation_projection.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';

import 'support/internal_background_message_fixture.dart';

const _modelSwitch =
    '[System: The active model for this chat has changed to gpt-6-sol-900k '
    'via provider openai-codex. From this point forward, use this runtime '
    'metadata when answering questions about what model/provider is active.]';

void main() {
  for (final entry in mergedInternalBackgroundMessageFixtures().entries) {
    test('actual merged ${entry.key} preserves human input and retry', () {
      for (final source in ['api', 'dashboard']) {
        final row = Map<String, dynamic>.from(entry.value[source] as Map);
        final before = jsonEncode(row);
        expect(row['display_kind'], isNull);
        expect(row['absorbed_message_uids'], isNotEmpty);
        expect(BackgroundReport.fromMessage(row), isNull);
        final messages = <Map<String, dynamic>>[
          {'id': 0, 'role': 'user', 'content': 'Unrelated older question'},
          row,
          {
            'id': 1000,
            'role': 'assistant',
            'content': 'Answer',
            'finish_reason': 'stop',
          },
        ];
        for (final items in [
          buildChatDisplayItems(messages: messages),
          buildConversationDisplayItems(messages: messages),
        ]) {
          expect((items.last as Map)['_retry_prompt'], row['content']);
        }
        expect(parseTaskTranscript([row]).single.backgroundReport, isNull);
        expect(parseTaskTranscript([row]).single.text, row['content']);
        expect(jsonEncode(row), before);
      }
    });
  }

  test('merge witnesses veto only untyped standalone heuristics', () {
    final row = Map<String, dynamic>.from(
      internalBackgroundMessageFixtures()['legacy_auto_continue']!['row']
          as Map,
    );
    for (final key in ['absorbed_message_uids', '_absorbed_message_uids']) {
      for (final witness in [
        '["human-message"]',
        ['human-message'],
      ]) {
        final merged = {...row, key: witness};
        expect(BackgroundReport.fromMessage(merged), isNull);
        expect(
          BackgroundReport.fromMessage({
            ...merged,
            'display_kind': 'auto_continue',
          }),
          isNotNull,
        );
        expect(
          BackgroundReport.fromMessage({
            ...merged,
            'display_content': 'Public human input',
          }),
          isNull,
        );
      }
      for (final empty in [null, '', '[]', <String>[]]) {
        expect(BackgroundReport.fromMessage({...row, key: empty}), isNotNull);
      }
    }
    expect(
      BackgroundReport.fromMessage({
        ...row,
        '_merged_turn_prefix': row['content'],
      }),
      isNull,
    );
  });

  test(
    'human comments cannot replace fixed-domain numeric producer fields',
    () {
      final fixtures = internalBackgroundMessageFixtures();
      for (final entry in <String, List<String>>{
        'watch_overflow_released': [
          'resumed. ',
          'resumed. Why were these suppressed? ',
        ],
        'watch_overflow_tripped': [
          '>10 notifications',
          '>Why 10 notifications',
        ],
        'continuation_prompt_gate_failed_template': [
          'attempt 1/3',
          'attempt why 1/3',
        ],
        'wakeup_prompt_template': ['wakeup #2', 'wakeup #Why 2'],
        'kanban_recovery': ['attempt 1/3', 'attempt why 1/3'],
        'legacy_delegation_batch': ['TASK 1/1', 'TASK why 1/1'],
      }.entries) {
        final body = fixtures[entry.key]!['row']['content'] as String;
        final human = body.replaceFirst(entry.value[0], entry.value[1]);
        expect(human, isNot(body));
        expect(
          BackgroundReport.fromMessage({'role': 'user', 'content': human}),
          isNull,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'merged notices never consume bracketed human or Android follow-ups',
    () {
      final fixtures = internalBackgroundMessageFixtures();
      for (final name in [
        'legacy_personality_set',
        'legacy_process_complete',
        'legacy_process_watch',
      ]) {
        final original = fixtures[name]!['row'] as Map;
        for (final human in [
          'Return [yes/no]',
          AndroidPromptContext.forModel('Explain the change'),
        ]) {
          final body = '${original['content']}\n\n$human';
          final row = <String, dynamic>{
            'id': 2,
            'role': 'user',
            'content': body,
          };
          expect(
            BackgroundReport.fromMessage(row),
            isNull,
            reason: '$name: $human',
          );
          final messages = [
            {'id': 1, 'role': 'user', 'content': 'Unrelated older question'},
            row,
            {
              'id': 3,
              'role': 'assistant',
              'content': 'Answer',
              'finish_reason': 'stop',
            },
          ];
          for (final items in [
            buildChatDisplayItems(messages: messages),
            buildConversationDisplayItems(messages: messages),
          ]) {
            final answer = items.last as Map;
            expect(
              answer['_retry_prompt'],
              contains(
                human.startsWith('Return')
                    ? 'Return [yes/no]'
                    : 'Explain the change',
              ),
            );
            expect(answer['_retry_prompt'], isNot('Unrelated older question'));
          }
        }
      }
    },
  );

  test('malformed MCP, process and goal walls are bounded literal scans', () {
    for (final body in [
      '[IMPORTANT: MCP servers have been reloaded. ${'1' * 40000}',
      '[IMPORTANT: Background process fixture completed normally (exit code 0).\nCommand: ${'fixture-command\nOutput:\n' * 5000}',
      '[Continuing toward your standing goal]\nGoal: ${'Goal\n\nCompletion contract:\n' * 5000}',
    ]) {
      expect(
        BackgroundReport.fromMessage({'role': 'user', 'content': body}),
        isNull,
      );
    }
  });

  for (final entry in internalBackgroundMessageFixtures().entries) {
    test('backend-produced ${entry.key} is background in every projection', () {
      final fixture = entry.value;
      final row = Map<String, dynamic>.from(fixture['row'] as Map);
      final before = jsonEncode(row);
      final report = BackgroundReport.fromMessage(row);
      expect(report, isNotNull, reason: row['content'] as String);
      expect(report!.kind.name, fixture['expected']);
      expect(report.body, same(row['content']));
      final messages = [
        {'id': 1, 'role': 'user', 'content': 'Real question'},
        row,
        {
          'id': 1000,
          'role': 'assistant',
          'content': 'Completed answer',
          'finish_reason': 'stop',
        },
      ];
      final detailed = buildChatDisplayItems(messages: messages);
      expect(detailed, hasLength(3));
      expect((detailed.last as Map)['_retry_prompt'], 'Real question');
      final quiet = buildConversationDisplayItems(messages: messages);
      expect(quiet.map((item) => item['id']), [1, 1000]);
      expect(quiet.last['_retry_prompt'], 'Real question');
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [row],
        receivedRows: [Map<String, dynamic>.from(row)],
        receivedTimeline: ChatTimeline(),
      );
      expect(sections.map((section) => section.source), [
        ChatDisplaySource.canonical,
        ChatDisplaySource.received,
      ]);
      expect(sections.every((section) => section.items.length == 1), isTrue);
      expect(
        parseTaskTranscript([row]).single.backgroundReport!.body,
        report.body,
      );
      expect(jsonEncode(row), before);

      // Remove metadata for the legacy-negative checks; explicit server kinds
      // intentionally classify arbitrary bodies and are not text heuristics.
      final content = row['content'] as String;
      for (final quoted in [
        '"$content"',
        '> ${content.replaceAll('\n', '\n> ')}',
        '```text\n$content\n```',
        'Why does this appear?\n$content',
      ]) {
        expect(
          BackgroundReport.fromMessage({'role': 'user', 'content': quoted}),
          isNull,
          reason: '${entry.key}: $quoted',
        );
      }
      if (fixture['sealed'] == true) {
        expect(
          BackgroundReport.fromMessage({
            'role': 'user',
            'content': '$content\n\nNew human question',
          }),
          isNull,
        );
      }
      if (row['display_kind'] == null) {
        expect(
          BackgroundReport.fromMessage({
            ...row,
            'content': content.replaceAll('\n', '\r\n'),
          })!.body,
          content.replaceAll('\n', '\r\n'),
        );
      }
    });
  }

  test('hidden/model-only and public projections outrank compatibility', () {
    for (final kind in [null, 'model_switch', 'internal_notification']) {
      final row = <String, dynamic>{
        'role': 'user',
        'content': _modelSwitch,
        'display_kind': kind,
      };
      final hidden = {...row, 'display_kind': 'hidden'};
      final modelOnly = {
        ...row,
        'display_metadata': {'model_only': true},
      };
      for (final suppressed in [hidden, modelOnly]) {
        expect(BackgroundReport.fromMessage(suppressed), isNull);
        expect(buildChatDisplayItems(messages: [suppressed]), isEmpty);
        expect(
          parseTaskTranscript([
            {'id': 1, ...suppressed},
          ]),
          isEmpty,
        );
      }
      for (final projection in [null, '', 'Actual public text']) {
        final projected = {...row, 'display_content': projection};
        if (projection == null || projection == '') {
          expect(
            parseTaskTranscript([
              {'id': 1, ...projected},
            ]),
            isEmpty,
          );
        }
        final report = BackgroundReport.fromMessage(projected);
        if (kind != null && projection == 'Actual public text') {
          expect(report!.body, projection);
        } else {
          expect(report, isNull);
        }
        final items = buildChatDisplayItems(messages: [projected]);
        expect(
          items.whereType<Map>().any(
            (item) => item['_display_content'] == _modelSwitch,
          ),
          isFalse,
        );
      }
    }
  });

  test('large malformed delegation fields avoid wildcard backtracking', () {
    final fixture =
        internalBackgroundMessageFixtures()['legacy_delegation_single']!;
    final body = (fixture['row'] as Map)['content'] as String;
    final intro = body.substring(0, body.indexOf('Original goal: '));
    final malformed =
        '$intro${'Original goal: fixture\nRole: leaf   Model: fixture\nStatus: invalid\n' * 1000}';
    expect(
      BackgroundReport.fromMessage({'role': 'user', 'content': malformed}),
      isNull,
    );
  });

  test(
    'annotations classify arbitrary internal text but never human controls',
    () {
      for (final kind in [
        'model_switch',
        'personality_switch',
        'auto_continue',
        'internal_notification',
      ]) {
        final report = BackgroundReport.fromMessage({
          'role': 'user',
          'display_kind': kind,
          'content': 'Arbitrary future producer wording',
        });
        expect(report!.kind, BackgroundReportKind.task);
      }
      for (final role in ['assistant', 'agent', 'tool', 'system', null]) {
        expect(
          BackgroundReport.fromMessage({'role': role, 'content': _modelSwitch}),
          isNull,
        );
      }
    },
  );

  for (final kind in ['model_switch', null, '']) {
    test('model switch uses a background task with display_kind=$kind', () {
      final row = <String, dynamic>{
        'id': 2,
        'role': 'user',
        'content': _modelSwitch,
        'display_kind': ?kind,
      };
      final before = jsonEncode(row);
      final report = BackgroundReport.fromMessage(row);
      expect(report, isNotNull);
      expect(report!.kind, BackgroundReportKind.task);
      expect(report.body, _modelSwitch);
      expect(report.hasIssues, isFalse);
      final messages = [
        {'id': 1, 'role': 'user', 'content': 'Real question'},
        row,
        {
          'id': 3,
          'role': 'assistant',
          'content': 'Completed answer',
          'finish_reason': 'stop',
        },
      ];
      final detailed = buildChatDisplayItems(messages: messages);
      expect(detailed, hasLength(3));
      expect((detailed.last as Map)['_retry_prompt'], 'Real question');
      final quiet = buildConversationDisplayItems(messages: messages);
      expect(quiet.map((item) => item['id']), [1, 3]);
      expect(quiet.last['_retry_prompt'], 'Real question');
      expect(jsonEncode(row), before);
    });
  }

  test('human quotes and explicitly human rows are not background tasks', () {
    for (final content in [
      '"$_modelSwitch"',
      '> $_modelSwitch',
      '```text\n$_modelSwitch\n```',
      'Why does this appear?\n$_modelSwitch',
      '$_modelSwitch\nWhy does this appear?',
      '[System: a label I typed, not a runtime notice]',
    ]) {
      expect(
        BackgroundReport.fromMessage({'role': 'user', 'content': content}),
        isNull,
        reason: content,
      );
    }
    for (final kind in ['steer', 'skill_invocation', 'hidden', 'unknown']) {
      expect(
        BackgroundReport.fromMessage({
          'role': 'user',
          'content': _modelSwitch,
          'display_kind': kind,
        }),
        isNull,
        reason: kind,
      );
    }
  });
}
