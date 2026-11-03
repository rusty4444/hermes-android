import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/background_report.dart';
import 'package:hermes_android/core/models/chat_timeline.dart';
import 'package:hermes_android/core/services/delegated_task_history.dart';
import 'package:hermes_android/core/utils/chat_conversation_projection.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';

import 'support/lcm_summary_fixture.dart';

void main() {
  final fixtures = lcmSummaryFixtures();
  for (final entry in fixtures.entries) {
    for (final source in ['api', 'dashboard']) {
      test('LCM ${entry.key} $source is a lossless background task', () {
        final row = Map<String, dynamic>.from(entry.value[source] as Map);
        final before = jsonEncode(row);
        final report = BackgroundReport.fromMessage(row);
        expect(report, isNotNull);
        expect(report!.kind, BackgroundReportKind.task);
        expect(report.body, same(row['content']));
        expect(report.hasIssues, isFalse);
        final messages = [
          {'id': 0, 'role': 'user', 'content': 'Actual question'},
          row,
          {
            'id': 1000,
            'role': 'assistant',
            'content': 'Actual answer',
            'finish_reason': 'stop',
          },
        ];
        final detailed = buildChatDisplayItems(messages: messages);
        expect(detailed, hasLength(3));
        expect((detailed[1] as Map)['content'], row['content']);
        expect((detailed.last as Map)['_retry_prompt'], 'Actual question');
        final quiet = buildConversationDisplayItems(messages: messages);
        expect(quiet.map((item) => item['content']), [
          'Actual question',
          'Actual answer',
        ]);
        expect(quiet.last['_retry_prompt'], 'Actual question');
        final sections = buildNormalChatDisplaySections(
          canonicalRows: [row],
          receivedRows: [
            {...row},
          ],
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
      });
    }
  }

  final arc = Map<String, dynamic>.from(fixtures['session_arc']!['api'] as Map);
  final body = arc['content'] as String;
  test('LF, CRLF and agent aliases preserve the original body', () {
    for (final role in ['user', 'assistant', 'agent']) {
      for (final text in [body, body.replaceAll('\n', '\r\n')]) {
        final row = {...arc, 'role': role, 'content': text};
        expect(BackgroundReport.fromMessage(row)!.body, same(text));
      }
    }
  });

  test(
    'ordinary long answers, quoted summaries and human tails stay prose',
    () {
      for (final role in ['user', 'assistant']) {
        for (final text in [
          'A long ordinary reply.\n' * 2000,
          'Please explain this:\n$body',
          '> ${body.replaceAll('\n', '\n> ')}',
          '```text\n$body\n```',
          '"$body"',
          ' $body',
          '$body\nWhat does this mean?',
          '$body\n\n---\n\nPlease continue with this human request.',
          '[Session Arc Summary (d1, node 410)]',
          '[Session Arc Summary (d1, node 410)]\nNo complete expansion footer.',
          body.replaceFirst('Session Arc', 'Durable'),
          body.replaceFirst('node ', 'node -'),
          body.replaceFirst('(d1,', '(d01,'),
          body.replaceFirst('[Expand for details:', '[Some other footer:'),
        ]) {
          expect(
            BackgroundReport.fromMessage({
              ...arc,
              'role': role,
              'content': text,
            }),
            isNull,
            reason: text.length > 200 ? text.substring(0, 200) : text,
          );
        }
      }
    },
  );

  test('public projections, explicit human kinds and merge witnesses win', () {
    for (final kind in [
      'steer',
      'skill_invocation',
      'unknown',
      'failed_turn',
    ]) {
      expect(
        BackgroundReport.fromMessage({...arc, 'display_kind': kind}),
        isNull,
      );
    }
    for (final role in ['system', 'tool', null]) {
      expect(BackgroundReport.fromMessage({...arc, 'role': role}), isNull);
    }
    for (final projection in [null, '', 'Public human text', body]) {
      expect(
        BackgroundReport.fromMessage({...arc, 'display_content': projection}),
        isNull,
      );
    }
    for (final witness in [
      {'absorbed_message_uids': '["human-followup"]'},
      {
        '_absorbed_message_uids': ['human-followup'],
      },
      {'_merged_turn_prefix': body},
    ]) {
      expect(BackgroundReport.fromMessage({...arc, ...witness}), isNull);
    }
    expect(
      BackgroundReport.fromMessage({...arc, 'display_kind': 'hidden'}),
      isNull,
    );
    expect(
      BackgroundReport.fromMessage({
        ...arc,
        'display_metadata': {'model_only': true},
      }),
      isNull,
    );
  });

  test('malformed large headers and footer lookalikes are bounded', () {
    for (final text in [
      '[Depth-${'1' * 40000} Summary (d1, node 1)]\nbody\n[Expand for details: ]',
      '[Session Arc Summary (d${'1' * 40000}, node 1)]\nbody\n[Expand for details: ]',
      '[Session Arc Summary (d1, node ${'1' * 40000}',
      '[Session Arc Summary (d1, node 410)]\n${'[Expand for details: no close\n' * 4000}',
    ]) {
      expect(BackgroundReport.fromMessage({...arc, 'content': text}), isNull);
    }
  });
}
