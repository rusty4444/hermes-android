import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/chat_message_time.dart';

void main() {
  test('server seconds preserve fractions and override local observations', () {
    final row = <String, dynamic>{};
    ChatMessageTime.observe(
      row,
      source: ChatMessageTimeSource.received,
      at: DateTime.utc(2025),
    );
    ChatMessageTime.observe(
      row,
      source: ChatMessageTimeSource.received,
      at: DateTime.utc(2026),
    );
    expect(ChatMessageTime.fromRow(row)!.at, DateTime.utc(2025));
    ChatMessageTime.observe(
      row,
      source: ChatMessageTimeSource.received,
      serverTimestamp: 1718456700.125,
    );
    final recorded = ChatMessageTime.fromRow(row)!;
    expect(recorded.at.millisecondsSinceEpoch, 1718456700125);
    expect(recorded.source, ChatMessageTimeSource.recorded);
    ChatMessageTime.observe(
      row,
      source: ChatMessageTimeSource.received,
      serverTimestamp: 1718456799,
    );
    expect(ChatMessageTime.fromRow(row)!.at, recorded.at);
    final restored = jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
    expect(ChatMessageTime.fromRow(restored)!.at, recorded.at);
  });

  test(
    'only explicit valid numeric seconds or attributed observations qualify',
    () {
      for (final value in [
        null,
        '',
        '1718456700',
        '2024-06-15T13:05:00Z',
        1718456700000,
        0,
        -1,
        double.nan,
        double.negativeInfinity,
        1e100,
        true,
        [],
        {},
      ]) {
        final row = <String, dynamic>{'timestamp': value};
        expect(ChatMessageTime.fromRow(row), isNull);
        expect(row, {'timestamp': value});
      }
      expect(
        ChatMessageTime.fromRow({ChatMessageTime.observedAtKey: 1718456700000}),
        isNull,
      );
      expect(
        ChatMessageTime.fromRow({
          ChatMessageTime.observedAtKey: 1718456700000,
          ChatMessageTime.sourceKey: 'recorded',
        }),
        isNull,
      );
    },
  );
}
