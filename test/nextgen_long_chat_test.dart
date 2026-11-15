import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_api_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/history_rows.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/chat_view.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

SavedConnection _conn() => SavedConnection(
  id: 'c1',
  label: 'Home',
  host: '10.0.0.5',
  port: 9119,
  apiKey: '',
  desktopGatewayUrl: 'http://10.0.0.5:9119',
  singleLogin: true,
  signInMethod: 'none',
);

/// Serves [rows] (oldest first) newest-first by offset, as the dashboard's
/// `order=latest` paging does.
class _PagedApi extends DashboardApiClient {
  _PagedApi(super.dashboard, this.rows) : super.withDashboard();
  final List<Map<String, dynamic>> rows;
  final calls = <(int?, int)>[];

  @override
  Future<Uint8List> getMessagesBytes(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
  }) async {
    calls.add((limit, offset));
    final end = (rows.length - offset).clamp(0, rows.length);
    final start = (end - (limit ?? rows.length)).clamp(0, end);
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'messages': rows.sublist(start, end)})),
    );
  }
}

/// [turns] turns of a prompt, a tool call, its result and a reply.
List<Map<String, dynamic>> _turns(int turns, {int toolChars = 50000}) => [
  for (var t = 0; t < turns; t++) ...[
    {'id': 't$t-u', 'role': 'user', 'content': 'Prompt $t'},
    {
      'id': 't$t-a1',
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'id': 'call$t',
          'function': {'name': 'terminal', 'arguments': '{"command":"ls"}'},
        },
      ],
    },
    {
      'id': 't$t-tool',
      'role': 'tool',
      'tool_call_id': 'call$t',
      'content': 'x' * toolChars,
    },
    {'id': 't$t-a2', 'role': 'assistant', 'content': 'Reply $t'},
  ],
];

/// Waits (in real time: large pages decode on an isolate) until [done].
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Markdown chunks', () {
    test('short text stays whole', () {
      expect(ngMarkdownChunks('one\n\ntwo'), ['one\n\ntwo']);
    });

    test('long text splits at paragraphs and rejoins exactly', () {
      final text = List.generate(
        40,
        (i) => 'Paragraph $i ${'w' * 200}',
      ).join('\n\n');
      final chunks = ngMarkdownChunks(text);
      expect(chunks.length, greaterThan(2));
      expect(chunks.join('\n\n'), text);
    });

    test('never splits before an indented continuation', () {
      final text = List.generate(
        30,
        (i) => '- item $i ${'w' * 200}\n\n    continued $i',
      ).join('\n\n');
      for (final chunk in ngMarkdownChunks(text)) {
        expect(chunk.startsWith(' '), isFalse);
      }
    });
  });

  test('a full page drops the partial turn at its start', () {
    final page = [
      {'role': 'tool', 'content': 'tail of an older turn'},
      {'role': 'assistant', 'content': 'older reply'},
      {'role': 'user', 'content': 'Prompt'},
      {'role': 'assistant', 'content': 'Reply'},
    ];
    expect(ngFromFirstTurn(page).first['content'], 'Prompt');
    final oneTurn = [
      {'role': 'assistant', 'content': 'a'},
      {'role': 'tool', 'content': 'b'},
    ];
    expect(ngFromFirstTurn(oneTurn), oneTurn);
  });

  test('structured text parts are skipped, keeping readable ones', () {
    final gateway = NextGenGateway(_conn());
    final chat = NgChatController(gateway, sessionId: 'stored');
    chat.debugApplyHistory([
      {
        'role': 'user',
        'content': [
          {'text': 'Hello'},
          {
            'text': {'value': 'unsupported'},
          },
        ],
      },
      {
        'role': 'assistant',
        'content': 'Raw',
        'display_content': [
          {'text': []},
          {'text': 'Welcome'},
        ],
      },
    ]);
    expect(chat.items.whereType<NgUserItem>().single.text, 'Hello');
    expect(chat.items.whereType<NgAssistantItem>().single.text, 'Welcome');
    chat.dispose();
    gateway.dispose();
  });

  group('slim rows', () {
    test('tool output and arguments are capped, previews kept', () {
      final rows = ngSlimHistoryRows([
        {
          'role': 'assistant',
          'content': 'ok',
          'reasoning_details': [
            {'text': 'x' * 100000},
          ],
          'tool_calls': [
            {
              'id': 'c',
              'function': {
                'name': 'write_file',
                'arguments': jsonEncode({
                  'path': '/tmp/big.txt',
                  'content': 'y' * 100000,
                }),
              },
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c', 'content': 'z' * 100000},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'look'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,${'A' * 100000}'},
            },
          ],
        },
      ]);
      final call = (rows[0]['tool_calls'] as List).single as Map;
      expect(call['ng_args_preview'], '/tmp/big.txt');
      expect(
        ((call['function'] as Map)['arguments'] as String).length,
        lessThanOrEqualTo(ngRowToolChars + 1),
      );
      expect(rows[0].containsKey('reasoning_details'), isFalse);
      expect(
        (rows[1]['content'] as String).length,
        lessThanOrEqualTo(ngRowToolChars + 1),
      );
      expect(jsonEncode(rows[2]).length, lessThan(1000));
    });

    test('a large page decodes on a background isolate', () async {
      final body = Uint8List.fromList(
        utf8.encode(jsonEncode({'messages': _turns(10)})),
      );
      expect(body.length, greaterThan(ngIsolateDecodeBytes));
      final rows = await ngDecodeHistory(body);
      expect(rows, hasLength(40));
      expect(
        (rows[2]['content'] as String).length,
        lessThanOrEqualTo(ngRowToolChars + 1),
      );
    });
  });

  group('history paging', () {
    late NextGenGateway gateway;
    late NgChatController chat;
    late _PagedApi api;

    setUp(() {
      gateway = NextGenGateway(_conn());
      api = _PagedApi(gateway.dashboard, _turns(40)); // 160 rows
      gateway.api = api;
      chat = NgChatController(gateway, sessionId: 'stored');
    });
    tearDown(() {
      chat.dispose();
      gateway.dispose();
    });

    List<String> prompts() => [
      for (final i in chat.items)
        if (i is NgUserItem) i.text,
    ];

    test(
      'opens on the latest page and pages back to the first prompt',
      () async {
        unawaited(chat.open());
        await _until(() => chat.items.isNotEmpty);
        expect(api.calls.first, (ngHistoryPage, 0));
        expect(chat.hasOlder, isTrue);
        expect(prompts().first, 'Prompt 25', reason: '60 rows = 15 turns');
        expect(prompts().last, 'Prompt 39');

        var pages = 0;
        while (chat.hasOlder && pages < 10) {
          await chat.loadOlder();
          pages++;
        }
        expect(chat.hasOlder, isFalse);
        expect(prompts(), [for (var t = 0; t < 40; t++) 'Prompt $t']);
        // Every turn whole: one prompt, one reply with its tool.
        final replies = chat.items.whereType<NgAssistantItem>().toList();
        expect(replies, hasLength(40));
        expect(replies.every((r) => r.tools.length == 1), isTrue);
        expect(replies.first.text, 'Reply 0');
      },
    );

    test('a latest page with nothing to show reaches back, a few pages at '
        'most', () async {
      api.rows
        ..clear()
        ..addAll([
          {'id': 'u', 'role': 'user', 'content': 'Start'},
          {'id': 'a', 'role': 'assistant', 'content': 'On it'},
          for (var i = 0; i < 1000; i++)
            {
              'id': 'h$i',
              'role': 'assistant',
              'content': 'x',
              'display_kind': 'hidden',
            },
        ]);
      unawaited(chat.open());
      await _settle();
      await _settle();
      expect(chat.items, isEmpty, reason: '1000 hidden rows, 5 pages read');
      expect(api.calls, hasLength(5));
      expect(chat.loadingHistory, isFalse);
    });

    test('keeps only so much of a huge tool output in memory', () async {
      unawaited(chat.open());
      await _until(() => chat.items.isNotEmpty);
      final tool = chat.items.whereType<NgAssistantItem>().first.tools.single;
      expect(tool.output!.length, lessThanOrEqualTo(ngStoredToolChars + 1));
    });

    testWidgets('scrolling to the top of a long chat loads the page before', (
      tester,
    ) async {
      // Small rows: fake-async widget tests can't wait on an isolate.
      api = _PagedApi(gateway.dashboard, _turns(40, toolChars: 100));
      gateway.api = api;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final rows = api.rows;
      chat.debugApplyHistory(
        rows.sublist(rows.length - ngHistoryPage),
        pageLimit: ngHistoryPage,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: nextGenTheme(Brightness.light, NextGenLook.instance),
          home: NgScope(
            connManager: ConnectionManager(prefs),
            gateway: gateway,
            connections: [gateway.connection],
            switchTo: (_) async {},
            addGateway: () async {},
            signOut: (_) async {},
            reload: () async {},
            signInAgain: () async {},
            child: Scaffold(
              body: NgChatView(
                chat: chat,
                onOpenSidebar: () {},
                onNewChat: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final before = api.calls.length;
      await tester.drag(
        find.byKey(const ValueKey('ng-transcript')),
        const Offset(0, 20000),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.calls.length, greaterThan(before));
      expect(api.calls.last.$2, greaterThan(0), reason: 'an older offset');

      // Typing in the composer reuses the parsed replies.
      final first = tester
          .widgetList<MarkdownBody>(find.byType(MarkdownBody))
          .toList();
      await tester.enterText(find.byType(TextField).last, 'hello');
      await tester.pump();
      final after = tester
          .widgetList<MarkdownBody>(find.byType(MarkdownBody))
          .toList();
      expect(after, isNotEmpty);
      for (final widget in after) {
        expect(first.any((w) => identical(w, widget)), isTrue);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
