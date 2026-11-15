// Regression tests for the 4.0.1 multi-chat performance fixes and summary box.
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/legacy_lcm_summary.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/hermes_sign_in.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HermesSignInVault.resetForTesting(MemorySignInSecretStore());
  });

  group('summary box', () {
    late NextGenGateway gateway;
    late NgChatController chat;

    setUp(() {
      gateway = NextGenGateway(
        SavedConnection(
          id: 'c1',
          label: 'Test',
          host: '10.0.0.5',
          port: 9119,
          apiKey: '',
          desktopGatewayUrl: 'http://10.0.0.5:9119',
          singleLogin: true,
          signInMethod: 'none',
        ),
      );
      chat = NgChatController(gateway, sessionId: 'stored')..runtimeId = 'rt';
    });
    tearDown(() {
      chat.dispose();
      gateway.dispose();
    });

    test('LCM summary rows become NgSystemKind.summary cards', () {
      const body =
          '[Recent Summary (d0, node 12)]\n'
          'Earlier details about the conversation.\n'
          '[Expand for details: hint-12]';
      chat.debugApplyHistory([
        {'role': 'user', 'content': 'Question'},
        {'role': 'assistant', 'content': body},
        {'role': 'assistant', 'content': 'Answer'},
      ]);
      final cards = chat.items.whereType<NgSystemItem>().toList();
      expect(cards, hasLength(1));
      expect(cards.single.kind, NgSystemKind.summary);
      expect(cards.single.expanded, isFalse);
      expect(cards.single.body, body);
      // The card sits between the question and the answer.
      expect(chat.items[0], isA<NgUserItem>());
      expect(chat.items[1], isA<NgSystemItem>());
      expect(chat.items[2], isA<NgAssistantItem>());
    });

    test('stacked LCM frames collapse into one summary card', () {
      const body =
          '[Session Arc Summary (d1, node 11)]\n'
          'Arc-level context.\n'
          '[Expand for details: arc-hint]\n'
          '\n---\n\n'
          '[Recent Summary (d0, node 10)]\n'
          'Recent context.\n'
          '[Expand for details: recent-hint]';
      chat.debugApplyHistory([
        {'role': 'user', 'content': body},
      ]);
      final cards = chat.items.whereType<NgSystemItem>().toList();
      expect(cards, hasLength(1));
      expect(cards.single.kind, NgSystemKind.summary);
      expect(cards.single.body, body);
    });

    test('objective-prefixed LCM summary is recognised', () {
      const body =
          '[Current user objective preserved from compacted history]\n'
          'Build the app.\n'
          '\n---\n\n'
          '[Recent Summary (d0, node 10)]\n'
          'Recent context.\n'
          '[Expand for details: hint]';
      chat.debugApplyHistory([
        {'role': 'assistant', 'content': body},
      ]);
      final cards = chat.items.whereType<NgSystemItem>().toList();
      expect(cards, hasLength(1));
      expect(cards.single.kind, NgSystemKind.summary);
    });

    test('ordinary assistant text is NOT a summary card', () {
      chat.debugApplyHistory([
        {'role': 'user', 'content': 'Hello'},
        {'role': 'assistant', 'content': 'Hi there! How can I help?'},
      ]);
      expect(chat.items.whereType<NgSystemItem>(), isEmpty);
      expect(chat.items.whereType<NgAssistantItem>(), hasLength(1));
    });

    test('non-LCM background task stays NgSystemKind.task', () {
      chat.debugApplyHistory([
        {
          'role': 'user',
          'content': 'A background fan-out unit finished.\nResult: success.',
          'display_kind': 'async_delegation_complete',
        },
      ]);
      final cards = chat.items.whereType<NgSystemItem>().toList();
      expect(cards, hasLength(1));
      expect(cards.single.kind, NgSystemKind.task);
    });

    test('LegacyLcmSummary.matches rejects incomplete envelopes', () {
      expect(
        LegacyLcmSummary.matches('[Recent Summary (d0, node 1)]'),
        isFalse,
      );
      expect(
        LegacyLcmSummary.matches(
          '[Recent Summary (d0, node 1)]\nContent without closer',
        ),
        isFalse,
      );
      expect(LegacyLcmSummary.matches('Just a normal message'), isFalse);
    });
  });

  group('bounded tool JSON', () {
    test('small maps are pretty-printed', () {
      final result = ngBoundedToolJson(null, {'key': 'value'});
      expect(result, contains('\n'));
      expect(result, contains('"key"'));
    });

    test('large maps are compact-encoded and capped', () {
      final big = {'data': 'x' * (ngStoredToolChars + 1000)};
      final result = ngBoundedToolJson(null, big);
      expect(result, isNotNull);
      // Compact JSON has no indentation newlines.
      expect(result!.contains('\n'), isFalse);
      expect(result.length, greaterThan(ngStoredToolChars));
      // ngCapStored will trim it.
      final capped = ngCapStored(result);
      expect(capped!.length, ngStoredToolChars + 1); // +1 for ellipsis
    });

    test('explicit text passthrough', () {
      expect(ngBoundedToolJson('raw text', {'ignored': true}), 'raw text');
    });

    test('null value returns null', () {
      expect(ngBoundedToolJson(null, null), isNull);
    });
  });

  group('coalesced notifications', () {
    test('streaming deltas do not notify synchronously', () async {
      final gateway = NextGenGateway(
        SavedConnection(
          id: 'c1',
          label: 'Test',
          host: '10.0.0.5',
          port: 9119,
          apiKey: '',
          desktopGatewayUrl: 'http://10.0.0.5:9119',
          singleLogin: true,
          signInMethod: 'none',
        ),
      );
      final chat = NgChatController(gateway, sessionId: 's')..runtimeId = 'rt';
      addTearDown(() {
        chat.dispose();
        gateway.dispose();
      });

      var notifications = 0;
      chat.addListener(() => notifications++);

      // Emit several deltas rapidly.
      for (var i = 0; i < 10; i++) {
        gateway.debugEmit(
          StreamEvent(
            type: 'message.delta',
            data: {'text': 'chunk$i'},
            sessionId: 'rt',
            seq: i + 1,
          ),
        );
      }
      // Before the frame callback fires, notifications should be coalesced.
      // At most 1 notification from the first _changed() scheduling.
      expect(notifications, lessThanOrEqualTo(1));
    });
  });
}
