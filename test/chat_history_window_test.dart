import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_history_window.dart';

Map<String, dynamic> row(int id, String role, String content) => {
  'id': id,
  'role': role,
  'content': content,
};

List<Map<String, dynamic>> latestPage(
  List<Map<String, dynamic>> rows,
  int offset,
) {
  final end = rows.length - offset;
  if (end <= 0) return [];
  final start = (end - ChatHistoryWindow.pageSize).clamp(0, end);
  return rows.sublist(start, end);
}

void main() {
  test(
    'cold reopen backfills >50 tool rows to the last visible turn',
    () async {
      final all = [
        row(1, 'user', 'Question'),
        row(2, 'assistant', 'Working'),
        for (var id = 3; id <= 124; id++) row(id, 'tool', 'output $id'),
      ];
      final offsets = <int>[];
      final window = ChatHistoryWindow();
      final batch = await window.fetchRecent((offset) async {
        offsets.add(offset);
        return latestPage(all, offset);
      });
      window.acceptRecent(batch);
      expect(offsets, [0, 50, 100]);
      expect(window.rows.first['content'], 'Question');
      expect(window.rows[1]['content'], 'Working');
      expect(window.rows.length, all.length);
      expect(window.hasOlder, isFalse);
    },
  );

  test(
    'bounded scan and manual older pages keep IDs across sliding refresh',
    () async {
      final all = [
        row(1, 'user', 'Old question'),
        row(2, 'assistant', 'Old reply'),
        for (var id = 3; id <= 812; id++) row(id, 'tool', 'output $id'),
      ];
      final window = ChatHistoryWindow();
      final offsets = <int>[];
      final batch = await window.fetchRecent((offset) async {
        offsets.add(offset);
        return latestPage(all, offset);
      });
      window.acceptRecent(batch);
      expect(offsets, [
        for (var offset = 0; offset < 600; offset += 50) offset,
      ]);
      expect(window.rows.length, 600);
      expect(window.hasOlder, isTrue);

      // A live turn inserts enough rows to slide the entire latest page.
      all.addAll([
        for (var id = 813; id <= 870; id++) row(id, 'tool', 'output $id'),
        row(871, 'assistant', 'Completed'),
      ]);
      window.acceptRecent(
        await window.fetchRecent((offset) async {
          expect(offset, 0);
          return latestPage(all, offset);
        }),
      );
      expect(window.rows.last['content'], 'Completed');
      expect(window.rows.any((item) => item['id'] == 213), isTrue);
      expect(
        window.rows.map((item) => item['id']).toSet().length,
        window.rows.length,
      );
      expect(window.olderOffset, 50); // The slipped nine-row gap is resumable.

      while (window.hasOlder) {
        window.acceptOlder(latestPage(all, window.olderOffset));
      }
      expect(window.rows.first['content'], 'Old question');
      expect(window.rows.last['content'], 'Completed');
      expect(
        window.rows.map((item) => item['id']).toSet().length,
        window.rows.length,
      );
    },
  );

  test(
    'short/empty recent refresh cannot erase loaded older durable bubbles',
    () async {
      final window = ChatHistoryWindow();
      window.acceptRecent(
        ChatHistoryPageBatch(
          [row(1, 'user', 'Question'), row(2, 'assistant', 'Reply')],
          2,
          false,
        ),
      );
      window.acceptRecent(const ChatHistoryPageBatch([], 0, false));
      expect(window.rows.map((message) => message['id']), [1, 2]);
      window.acceptRecent(
        ChatHistoryPageBatch([row(3, 'assistant', 'Final answer')], 1, false),
      );
      expect(window.rows.map((message) => message['content']), [
        'Question',
        'Reply',
        'Final answer',
      ]);
    },
  );

  test(
    'owner paging seed does not consume the first physical cold scan',
    () async {
      final all = [
        row(1, 'user', 'Question'),
        for (var id = 2; id < 124; id++) row(id, 'tool', 'Result $id'),
        row(124, 'assistant', 'Final answer'),
      ];
      final window = ChatHistoryWindow()
        ..acceptRecent(ChatHistoryPageBatch(latestPage(all, 0), 50, true));
      // A held first physical GET must not remove this usable older-page control.
      expect(window.hasOlder, isTrue);
      expect(window.olderOffset, 50);
      final offsets = <int>[];
      final batch = await window.fetchRecent((offset) async {
        offsets.add(offset);
        return latestPage(all, offset);
      }, forceColdScan: true);
      expect(offsets, [0, 50, 100]);
      expect(
        window.olderOffset,
        50,
        reason: 'fetch does not move the live cursor',
      );
      window.acceptRecent(batch);
      expect(window.rows.map((r) => r['id']), all.map((r) => r['id']));
      expect(window.rows.first['content'], 'Question');
      expect(window.rows.last['content'], 'Final answer');
    },
  );

  test('a latest page that jumps past the old window exposes its gap', () {
    final all = [
      for (var id = 1; id <= 90; id++) row(id, 'user', 'Prompt $id'),
    ];
    final window = ChatHistoryWindow()
      ..acceptRecent(ChatHistoryPageBatch(all.take(20).toList(), 20, false));
    window.acceptRecent(ChatHistoryPageBatch(latestPage(all, 0), 50, true));
    expect(window.olderOffset, 50);
    expect(window.hasOlder, isTrue);
    window.acceptOlder(latestPage(all, window.olderOffset));
    expect(window.rows.length, 90);
    expect(window.rows.first['id'], 1);
    expect(window.rows.last['id'], 90);
  });
}
