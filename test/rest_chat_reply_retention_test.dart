import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/rest_chat_reply_retention.dart';

Map<String, dynamic> row(
  int id,
  String role,
  String text, {
  Map<String, dynamic> extra = const {},
}) => {'id': id, 'role': role, 'content': text, ...extra};

void main() {
  final previous = [
    row(10, 'user', 'Same question'),
    row(11, 'assistant', 'Same answer', extra: {'status': 'completed'}),
  ];
  final localUser = <String, dynamic>{
    'role': 'user',
    'content': 'Same question',
  };
  final localAnswer = <String, dynamic>{
    'role': 'assistant',
    'content': 'Same answer',
    '_chat_response_complete': true,
    '_gateway_pending_response': false,
  };
  final local = [...previous, localUser, localAnswer];

  test(
    'empty, old and user-only history cannot discard the received answer',
    () {
      final retention = RestChatReplyRetention.admit(
        previous,
        historyKnown: true,
      )..complete(local);
      for (final history in [
        <Map<String, dynamic>>[],
        previous,
        [...previous, row(12, 'user', 'Same question')],
      ]) {
        expect(retention.reconcile(history), local);
        expect(retention.hasRetainedReply, true);
      }
      expect(identical(retention.reconcile(previous).last, localAnswer), true);
    },
  );

  for (final metadata in <Map<String, dynamic>>[
    {},
    {'partial': true},
    {'status': 'interrupted'},
    {'interim': true},
    {
      'tool_calls': [{}],
    },
    {'status': 'completed'},
    {'finish_reason': 'stop'},
    {'completed': true},
    {'success': true},
    {'_chat_response_complete': true},
  ]) {
    test('a post-floor row is not a match, even if final: $metadata', () {
      final retention = RestChatReplyRetention.admit(
        previous,
        historyKnown: true,
      )..complete(local);
      final canonical = [
        ...previous,
        row(12, 'user', 'Same question'),
        row(13, 'assistant', 'Same answer', extra: metadata),
      ];
      expect(retention.admissionFloor, 11);
      expect(retention.reconcile(canonical), local);
      expect(retention.hasRetainedReply, true);
      expect(retention.reconcile(canonical).last, same(localAnswer));
    });
  }

  test('known empty floor zero does not establish first-response identity', () {
    final retention = RestChatReplyRetention.admit([], historyKnown: true)
      ..complete([localUser, localAnswer]);
    final canonical = [
      row(1, 'user', 'Same question'),
      row(2, 'assistant', 'Same answer', extra: {'status': 'completed'}),
    ];
    expect(retention.admissionFloor, 0);
    expect(retention.reconcile(canonical), [localUser, localAnswer]);
    expect(retention.hasRetainedReply, true);
  });

  test(
    'unknown admission floor never guesses identity from repeated answer text',
    () {
      for (final history in [
        <Map<String, dynamic>>[],
        [localUser, localAnswer],
      ]) {
        final retention = RestChatReplyRetention.admit(
          history,
          historyKnown: false,
        )..complete(local);
        expect(retention.admissionFloor, isNull);
        expect(retention.reconcile(previous), local);
      }
      final retention = RestChatReplyRetention.admit(local, historyKnown: true)
        ..complete(local);
      expect(retention.admissionFloor, isNull);
      expect(retention.reconcile(previous), local);
    },
  );

  test(
    'late prior partial, commentary and unrelated final cannot hand over',
    () {
      final retention = RestChatReplyRetention.admit(
        previous,
        historyKnown: true,
      )..complete(local);
      final delayed = [
        ...previous,
        row(12, 'user', 'Prior unknown turn'),
        row(13, 'assistant', 'Delayed prior partial'),
        row(14, 'assistant', 'Inspecting the result', extra: {'interim': true}),
        row(15, 'tool', 'Tool result'),
        row(16, 'user', 'Unrelated prompt'),
        row(17, 'assistant', 'Unrelated final', extra: {'status': 'completed'}),
      ];
      expect(retention.reconcile(delayed), local);
      expect(retention.hasRetainedReply, true);
    },
  );

  for (final historyKnown in [false, true]) {
    for (final metadata in <Map<String, dynamic>>[
      {'_chat_response_complete': true},
      {'status': 'completed'},
      {'status': 'success'},
      {'finish_reason': 'stop'},
      {'finish_reason': 'end_turn'},
      {'completed': true},
      {'success': true},
    ]) {
      test(
        'exact current durable ID hands over once: known=$historyKnown $metadata',
        () {
          final identified = {...localAnswer, 'id': 13};
          final retained = [...previous, localUser, identified];
          final retention = RestChatReplyRetention.admit(
            previous,
            historyKnown: historyKnown,
          )..complete(retained);
          final canonical = [
            ...previous,
            row(12, 'user', 'Different server-side prompt rendering'),
            row(13, 'assistant', 'Different canonical prose', extra: metadata),
            row(14, 'assistant', 'Unconfirmed commentary after final'),
            row(15, 'tool', 'Later tool detail'),
          ];
          expect(retention.reconcile(canonical), canonical);
          expect(retention.hasRetainedReply, false);
          // Retirement is final. A subsequent older-only page is returned as
          // canonical, not used to resurrect an already handed-over receipt.
          expect(retention.reconcile(previous), previous);
          expect(retention.hasRetainedReply, false);
        },
      );
    }
  }

  for (final metadata in <Map<String, dynamic>>[
    {},
    {'_gateway_pending_response': false},
    {'status': 'completed', 'partial': true},
    {'status': 'completed', 'failed': true},
    {'status': 'completed', 'success': false},
    {'status': 'interrupted'},
    {'status': 'completed', 'error': 'Failed later'},
    {'_chat_response_complete': true, 'interim': true},
    {'_chat_response_complete': true, '_gateway_interim': true},
    {'_chat_response_complete': true, '_gateway_pending_response': true},
    {
      'status': 'completed',
      'tool_calls': [{}],
    },
    {'finish_reason': 'tool_calls'},
  ]) {
    test(
      'matching ID without a successful local final is insufficient: $metadata',
      () {
        final identified = {...localAnswer, 'id': 13};
        final retained = [...previous, localUser, identified];
        final retention = RestChatReplyRetention.admit(
          previous,
          historyKnown: true,
        )..complete(retained);
        final canonical = [
          ...previous,
          row(12, 'user', 'Same question'),
          row(13, 'assistant', 'Same answer', extra: metadata),
        ];
        expect(retention.reconcile(canonical), retained);
        expect(retention.hasRetainedReply, true);
        expect(retention.reconcile(canonical).last, same(identified));
      },
    );
  }

  for (final localMetadata in <Map<String, dynamic>>[
    {},
    {'status': 'completed'},
    {'_chat_response_complete': true, 'interim': true},
    {'_chat_response_complete': true, 'partial': true},
  ]) {
    test('current receipt must itself be a selected final: $localMetadata', () {
      final unconfirmed = <String, dynamic>{
        'id': 13,
        'role': 'assistant',
        'content': 'Current unconfirmed receipt',
        ...localMetadata,
      };
      final retained = [...previous, localUser, unconfirmed];
      final retention = RestChatReplyRetention.admit(
        previous,
        historyKnown: true,
      )..complete(retained);
      final canonical = [
        ...previous,
        row(12, 'user', 'Same question'),
        row(
          13,
          'assistant',
          'Successful saved final',
          extra: {'completed': true},
        ),
      ];
      expect(retention.reconcile(canonical), retained);
      expect(retention.hasRetainedReply, true);
    });
  }

  test('successful wrong ID never replaces a current identified receipt', () {
    final identified = {...localAnswer, 'id': 13};
    final retained = [...previous, localUser, identified];
    final retention = RestChatReplyRetention.admit(previous, historyKnown: true)
      ..complete(retained);
    final canonical = [
      ...previous,
      row(12, 'user', 'Same question'),
      row(14, 'assistant', 'Same answer', extra: {'status': 'completed'}),
    ];
    expect(retention.reconcile(canonical), retained);
    expect(retention.hasRetainedReply, true);
  });

  test(
    'a matched prior final cannot retire the current unidentified final',
    () {
      final priorFinal = {...previous.last, '_chat_response_complete': true};
      final retained = [previous.first, priorFinal, localUser, localAnswer];
      final retention = RestChatReplyRetention.admit(
        previous,
        historyKnown: true,
      )..complete(retained);
      expect(retention.reconcile(previous), retained);
      expect(retention.hasRetainedReply, true);
      expect(retention.reconcile(previous).last, same(localAnswer));
    },
  );

  test('loading older rows preserves local identity and receipt scopes', () {
    final retention = RestChatReplyRetention.admit(previous, historyKnown: true)
      ..complete(local);
    final older = row(9, 'user', 'Earlier');
    expect(retention.reconcile([older, ...previous]), [older, ...local]);
    expect(retention.reconcile([older, ...previous]).last, same(localAnswer));
    expect(retention.hasRetainedReply, true);
  });
}
