import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/background_report.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/utils/chat_conversation_projection.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

import 'support/cron_task_prompt_fixture.dart';

void main() {
  final fixtures = cronTaskPromptFixtures();
  for (final entry in fixtures.entries) {
    for (final projection in ['api', 'dashboard']) {
      test('${entry.key} is lossless in $projection and both chat modes', () {
        final row = Map<String, dynamic>.from(entry.value[projection] as Map);
        final before = jsonEncode(row);
        final report = BackgroundReport.fromMessage(row)!;
        expect(report.kind, BackgroundReportKind.task);
        expect(report.body, same(row['content']));
        expect(
          parseTaskTranscript([row]).single.backgroundReport!.body,
          report.body,
        );
        expect(buildChatDisplayItems(messages: [row]), hasLength(1));
        expect(buildConversationDisplayItems(messages: [row]), isEmpty);
        final sections = buildNormalChatDisplaySections(
          canonicalRows: [row],
          receivedRows: [Map<String, dynamic>.from(row)],
          receivedTimeline: ChatTimeline(),
        );
        expect(sections.map((section) => section.source), [
          ChatDisplaySource.canonical,
          ChatDisplaySource.received,
        ]);
        expect(jsonEncode(row), before);
        final crlf = (row['content'] as String).replaceAll('\n', '\r\n');
        expect(
          BackgroundReport.fromMessage({...row, 'content': crlf})!.body,
          crlf,
        );
      });
    }
  }

  test('current cron hints do not require an old-style run ID', () {
    for (final name in ['current_skills', 'current_plain']) {
      final row = Map<String, dynamic>.from(fixtures[name]!['api'] as Map);
      expect((row['session_id'] as String).startsWith('local-'), isTrue);
      row.remove('session_id');
      expect(BackgroundReport.fromMessage(row), isNotNull);
    }
  });

  test('legacy skill scaffolding requires the complete cron run identity', () {
    final row = Map<String, dynamic>.from(
      fixtures['legacy_skills']!['api'] as Map,
    );
    for (final id in [
      null,
      '',
      'cron_fixture',
      'local-fixture',
      'mob-fixture',
      'cron_fixture_20261014_213510-extra',
      'xcron_fixture_20261014_213510',
    ]) {
      expect(BackgroundReport.fromMessage({...row, 'session_id': id}), isNull);
    }
    for (final content in [
      '/fixture-one',
      'Please check the next build.',
      '[IMPORTANT: The user has invoked a skill]',
      (row['content'] as String).split('\n\n').first,
      '[IMPORTANT: The user has invoked the "" skill, indicating they want you to follow its instructions. The full skill content is loaded below.]\n\nbody',
    ]) {
      expect(
        BackgroundReport.fromMessage({...row, 'content': content}),
        isNull,
      );
    }
  });

  test('genuine skill instructions, quotes and code examples remain human', () {
    const marker =
        '\nThe user has provided the following instruction alongside the skill invocation: ';
    final current = Map<String, dynamic>.from(
      fixtures['current_skills']!['api'] as Map,
    );
    final content = current['content'] as String;
    final userSkill =
        '${content.substring(0, content.lastIndexOf(marker))}${marker}Explain the fixture.';
    for (final id in ['mob-fixture', 'cron_fixture_20261014_213510']) {
      expect(
        BackgroundReport.fromMessage({
          ...current,
          'session_id': id,
          'content': userSkill,
        }),
        isNull,
      );
    }
    for (final entry in fixtures.values) {
      final row = Map<String, dynamic>.from(entry['api'] as Map);
      final body = row['content'] as String;
      for (final quote in [
        '"$body"',
        '> ${body.replaceAll('\n', '\n> ')}',
        '```text\n$body\n```',
        'Why does this appear?\n$body',
      ]) {
        expect(
          BackgroundReport.fromMessage({...row, 'content': quote}),
          isNull,
        );
      }
    }
  });

  test('explicit public, human, hidden and merge precedence stays intact', () {
    for (final entry in fixtures.values) {
      final row = Map<String, dynamic>.from(entry['api'] as Map);
      for (final kind in ['steer', 'skill_invocation', 'hidden', 'unknown']) {
        expect(
          BackgroundReport.fromMessage({...row, 'display_kind': kind}),
          isNull,
        );
      }
      for (final public in [null, '', 'Actual user instruction']) {
        expect(
          BackgroundReport.fromMessage({...row, 'display_content': public}),
          isNull,
        );
      }
      expect(
        BackgroundReport.fromMessage({
          ...row,
          'display_metadata': {'model_only': true},
        }),
        isNull,
      );
      for (final witness in [
        '["human"]',
        ['human'],
      ]) {
        for (final key in ['absorbed_message_uids', '_absorbed_message_uids']) {
          expect(BackgroundReport.fromMessage({...row, key: witness}), isNull);
        }
      }
      expect(
        BackgroundReport.fromMessage({
          ...row,
          '_merged_turn_prefix': row['content'],
        }),
        isNull,
      );
      for (final role in ['assistant', 'agent', 'system', 'tool', null]) {
        expect(BackgroundReport.fromMessage({...row, 'role': role}), isNull);
      }
    }
  });

  test('scheduled setup cannot become a retry prompt, but a follow-up can', () {
    final task = Map<String, dynamic>.from(
      fixtures['legacy_skills']!['api'] as Map,
    );
    final answer = {
      'id': 1000,
      'role': 'assistant',
      'content': 'Answer',
      'finish_reason': 'stop',
    };
    for (final project in [
      buildChatDisplayItems,
      buildConversationDisplayItems,
    ]) {
      final setupOnly = project(messages: [task, answer]);
      expect((setupOnly.last as Map)['_retry_prompt'], isNull);
      final followup = {
        ...task,
        'id': 999,
        'content': 'Please explain the result.',
      };
      final items = project(messages: [task, followup, answer]);
      expect((items.last as Map)['_retry_prompt'], followup['content']);
    }
  });

  test('malformed large skill headers and partial cron hints fail open', () {
    final row = Map<String, dynamic>.from(
      fixtures['current_plain']!['api'] as Map,
    );
    final body = row['content'] as String;
    for (final malformed in [
      body.replaceFirst('DELIVERY:', 'A human asks about delivery:'),
      body.substring(0, body.indexOf('RECURSION:')),
      '[IMPORTANT: The user has invoked the "${'x' * 200000}',
      '[IMPORTANT: The user has invoked the "fixture" skill, ${'x' * 200000}',
    ]) {
      expect(
        BackgroundReport.fromMessage({...row, 'content': malformed}),
        isNull,
      );
    }
  });

  for (final projection in ['api', 'dashboard']) {
    test('legacy scheduled skill prompt is a task in $projection history', () {
      final row = Map<String, dynamic>.from(
        cronTaskPromptFixtures()['legacy_skills']![projection] as Map,
      );
      final before = jsonEncode(row);
      final report = BackgroundReport.fromMessage(row);
      expect(report, isNotNull);
      expect(report!.kind, BackgroundReportKind.task);
      expect(report.body, same(row['content']));
      final messages = [
        {'id': 0, 'role': 'user', 'content': 'Real question'},
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
      expect(quiet.map((item) => item['id']), [0, 1000]);
      expect(quiet.last['_retry_prompt'], 'Real question');
      expect(jsonEncode(row), before);
    });
  }
}
