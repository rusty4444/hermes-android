import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/background_report.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

import 'support/preserved_task_list_fixture.dart';

void main() {
  final snapshots = preservedTaskListFixtures();
  for (final entry in snapshots.entries) {
    test('legacy todo snapshot ${entry.key} uses a task card losslessly', () {
      final row = entry.value;
      final before = jsonEncode(row);
      final report = BackgroundReport.fromMessage(row)!;
      expect(report.kind, BackgroundReportKind.task);
      expect(report.body, row['content']);
      expect(report.summary, isNull);
      expect(report.hasIssues, isFalse);
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [row],
        receivedRows: [Map<String, dynamic>.from(row)],
        receivedTimeline: ChatTimeline(),
      );
      expect(sections.map((section) => section.source), [
        ChatDisplaySource.canonical,
        ChatDisplaySource.received,
      ]);
      for (final section in sections) {
        final projected = section.items.single as Map;
        expect(projected, row);
        expect(projected['role'], 'user');
        expect(projected['content'], same(row['content']));
      }
      expect(jsonEncode(row), before);
    });
  }

  test('legacy todo snapshots support CRLF without rewriting the body', () {
    final row = {
      ...snapshots['reported']!,
      'content': (snapshots['reported']!['content'] as String).replaceAll(
        '\n',
        '\r\n',
      ),
    };
    expect(BackgroundReport.fromMessage(row)!.body, row['content']);
  });

  test('quotes, mixed human text and malformed todo lists stay human', () {
    final body = snapshots['reported']!['content'] as String;
    final header = body.split('\n').first;
    for (final content in [
      'I am getting this reminder:\n$body',
      '"$body"',
      '> ${body.replaceAll('\n', '\n> ')}',
      '```text\n$body\n```',
      '$body\nWhy is this appearing?',
      ' $body',
      header,
      '$header\nThis is not a task list.',
      '$header\n- [>] implementation. Work (pending)',
      '$header\n- [ ] implementation. (pending)',
      '$header\n- [ ] implementation.  (pending)',
      '$header\n- [x] implementation. Finished (completed)',
      '$header\n- [ ] missing status',
      '$header\n- [ ] implementation. Work (pending)\n\n'
          '[Skills pruned during compression — reload before acting on these tasks]\n'
          'Arbitrary user prose',
    ]) {
      expect(
        BackgroundReport.fromMessage({'role': 'user', 'content': content}),
        isNull,
        reason: content,
      );
    }
    for (final role in ['assistant', 'agent', 'tool', 'system', null]) {
      expect(
        BackgroundReport.fromMessage({'role': role, 'content': body}),
        isNull,
      );
    }
    for (final kind in ['hidden', 'steer', 'unknown', false, []]) {
      expect(
        BackgroundReport.fromMessage({
          'role': 'user',
          'content': body,
          'display_kind': kind,
        }),
        isNull,
      );
    }
  });

  test('a todo snapshot does not replace the real retry prompt', () {
    final items = buildChatDisplayItems(
      messages: [
        {'id': 1, 'role': 'user', 'content': 'Real user prompt'},
        snapshots['reported']!,
        {'id': 3, 'role': 'assistant', 'content': 'Answer'},
      ],
    );
    expect((items.last as Map)['_retry_prompt'], 'Real user prompt');
  });

  for (final kind in ['async_delegation_complete', 'process_complete']) {
    test(
      'only exact server kind $kind classifies, without changing raw row',
      () {
        final row = <String, dynamic>{
          'id': 17,
          'role': 'user',
          'content':
              ' \r\n<untrusted_tool_result>full body</untrusted_tool_result>'
              '\n literal \\n FINAL_MARKER \n ',
          'display_kind': kind,
          'display_metadata': {
            'display_text': 'Short preview',
            'failed_count': 1,
          },
          'unrelated': {
            'retain': [1, 2],
          },
        };
        final before = jsonEncode(row);
        final report = BackgroundReport.fromMessage(row)!;
        expect(report.body, row['content']);
        expect(report.summary, 'Short preview');
        expect(report.hasIssues, isTrue);
        expect(
          report.kind,
          kind == 'process_complete'
              ? BackgroundReportKind.process
              : BackgroundReportKind.task,
        );
        final projected = buildChatDisplayItems(messages: [row]).single as Map;
        expect(projected, row);
        expect(identical(projected['content'], row['content']), isTrue);
        expect(jsonEncode(row), before);
      },
    );
  }

  test('human headers, unknown and malformed kinds are not authority', () {
    for (final kind in [
      null,
      '',
      'PROCESS_COMPLETE',
      'process_complete ',
      'unknown',
      ['process_complete'],
      {'display_kind': 'process_complete'},
    ]) {
      final row = <String, dynamic>{
        'role': 'user',
        'content':
            '[ASYNC DELEGATION COMPLETE] Quoted by a human.\n'
            '[IMPORTANT: Background process finished]',
        'display_kind': kind,
      };
      expect(BackgroundReport.fromMessage(row), isNull);
      final projected = buildChatDisplayItems(messages: [row]).single as Map;
      expect(projected['_display_content'], row['content']);
    }
    expect(
      BackgroundReport.fromMessage({
        'content': ['not the supported report body'],
        'display_kind': 'process_complete',
      }),
      isNull,
    );
  });

  test(
    'malformed or nested metadata is ignored, never coerced or recursed',
    () {
      for (final metadata in [
        null,
        'serialized JSON is not an object',
        [],
        42,
        {
          'display_text': {'text': 'not a summary'},
          'failed_count': '1',
          'has_issues': 'true',
          'nested': {'has_issues': true},
        },
        {'task_count': [], 'completed_count': {}, 'failed_count': -1},
      ]) {
        final report = BackgroundReport.fromMessage({
          'display_kind': 'process_complete',
          'content': 'failed timeout prose is not status authority',
          'display_metadata': metadata,
        })!;
        expect(report.summary, isNull);
        expect(report.hasIssues, isFalse);
      }
    },
  );

  test(
    'existing issue/count metadata flags issues without claiming success',
    () {
      for (final metadata in [
        {'has_issues': true},
        {'failed_count': 2},
        {'task_count': 3, 'completed_count': 1},
      ]) {
        expect(
          BackgroundReport.fromMessage({
            'display_kind': 'async_delegation_complete',
            'content': 'Report',
            'display_metadata': metadata,
          })!.hasIssues,
          isTrue,
        );
      }
    },
  );

  test(
    'only the summary is bounded; canonical and received are not merged',
    () {
      final row = <String, dynamic>{
        'id': 7,
        'role': 'user',
        'content': '${'full report\n' * 300}FINAL_MARKER',
        'display_kind': 'process_complete',
        'display_metadata': {'display_text': '🙂' * 500},
      };
      final report = BackgroundReport.fromMessage(row)!;
      expect(report.summary!.runes.length, 240);
      expect(report.body, row['content']);
      final sections = buildNormalChatDisplaySections(
        canonicalRows: [row],
        receivedRows: [
          {...row},
        ],
        receivedTimeline: ChatTimeline(),
      );
      expect(sections.map((s) => s.source), [
        ChatDisplaySource.canonical,
        ChatDisplaySource.received,
      ]);
      expect(sections.map((s) => s.items.length), [1, 1]);
      expect(sections.map((s) => (s.items.single as Map)['content']), [
        row['content'],
        row['content'],
      ]);
    },
  );
}
