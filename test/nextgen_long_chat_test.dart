import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/dashboard_api_client.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:hermes_android/nextgen/data/chat_controller.dart';
import 'package:hermes_android/nextgen/data/history_rows.dart';
import 'package:hermes_android/nextgen/data/nextgen_gateway.dart';
import 'package:hermes_android/nextgen/nextgen_preferences.dart';
import 'package:hermes_android/nextgen/theme/nextgen_theme.dart';
import 'package:hermes_android/nextgen/ui/chat_view.dart';
import 'package:hermes_android/nextgen/ui/nextgen_scope.dart';
import 'package:http/http.dart' as http;
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

/// A [_PagedApi] whose Nth call (zero-based) can be held open until released,
/// so adoption can run while a page fetch is in flight.
class _HeldPagedApi extends _PagedApi {
  _HeldPagedApi(super.dashboard, super.rows);
  final gates = <int, Completer<void>>{};

  @override
  Future<Uint8List> getMessagesBytes(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
  }) async {
    final gate = gates[calls.length];
    if (gate != null) await gate.future;
    return super.getMessagesBytes(
      sessionId,
      limit: limit,
      offset: offset,
      latest: latest,
    );
  }
}

/// Captures the query params a [DashboardApiClient] builds, bypassing auth.
class _CapturingDashboard extends DashboardClient {
  _CapturingDashboard() : super(host: 'fixture.local');
  Map<String, String>? lastQuery;

  @override
  Future<http.Response> apiRequest(
    String method,
    String endpoint, {
    Object? body,
    Map<String, String>? queryParameters,
    Duration timeout = ApiClient.requestTimeout,
    bool retried = false,
  }) async {
    lastQuery = queryParameters;
    return http.Response('{"messages": []}', 200);
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

/// Re-tags row (and tool-call) ids so appended rows never collide with the
/// base fixture's ids — the real gateway never reuses a row id.
List<Map<String, dynamic>> _shift(
  List<Map<String, dynamic>> rows,
  String tag,
) => [
  for (final r in rows)
    {
      ...r,
      'id': '$tag-${r['id']}',
      if (r['tool_calls'] != null)
        'tool_calls': [
          for (final c
              in (r['tool_calls'] as List).cast<Map<String, dynamic>>())
            {...c, 'id': '$tag-${c['id']}'},
        ],
      if (r['tool_call_id'] != null)
        'tool_call_id': '$tag-${r['tool_call_id']}',
    },
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

  group('Paging across live growth', () {
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

    test('a live turn growing the chat does not end pagination', () async {
      unawaited(chat.open());
      await _until(() => chat.items.isNotEmpty);
      expect(prompts().first, 'Prompt 25');
      // A running turn persists a full page of rows while the reader is
      // scrolled back: the newest end moves under the paging offset, so
      // the next page is entirely rows already shown.
      api.rows.addAll(_shift(_turns(15), 'g')); // 60 rows, exactly one page
      await chat.loadOlder();
      expect(
        chat.hasOlder,
        isTrue,
        reason: 'an all-known page must not latch pagination off',
      );
      await chat.loadOlder();
      expect(
        prompts().first,
        'Prompt 10',
        reason: 'paging continues past the shifted window',
      );
    });

    test('growth beside a tool-heavy turn loses no stored rows', () async {
      // 15 short turns, one 80-row turn (39 tool calls), 15 short turns.
      final long = <Map<String, dynamic>>[
        {'id': 'L-u', 'role': 'user', 'content': 'Prompt long'},
        for (var i = 0; i < 39; i++) ...[
          {
            'id': 'L-a$i',
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'L-call$i',
                'function': {
                  'name': 'terminal',
                  'arguments': '{"command":"step $i"}',
                },
              },
            ],
          },
          {
            'id': 'L-tool$i',
            'role': 'tool',
            'tool_call_id': 'L-call$i',
            'content': 'ok',
          },
        ],
        {'id': 'L-end', 'role': 'assistant', 'content': 'Reply long'},
      ];
      api.rows
        ..clear()
        ..addAll(_shift(_turns(15, toolChars: 10), 'early'))
        ..addAll(long)
        ..addAll(_shift(_turns(15, toolChars: 10), 'late'));
      unawaited(chat.open());
      await _until(() => chat.items.isNotEmpty);
      // Three short turns run after the chat was opened: 12 rows.
      api.rows.addAll(_shift(_turns(3, toolChars: 10), 'g'));
      for (var i = 0; i < 20 && chat.hasOlder; i++) {
        await chat.loadOlder();
      }
      final replies = [
        for (final i in chat.items)
          if (i is NgAssistantItem && i.text.isNotEmpty) i.text,
      ];
      final longTools = [
        for (final i in chat.items)
          if (i is NgAssistantItem)
            ...i.tools.where((t) => (t.input ?? '').contains('step')),
      ];
      expect(chat.hasOlder, isFalse);
      expect(replies, contains('Reply long'));
      expect(longTools, hasLength(39));
    });

    test('a growth burst never re-fetches an offset', () async {
      api.rows
        ..clear()
        ..addAll(_turns(50)); // 200 rows; the newest page shows 60.
      unawaited(chat.open());
      await _until(() => chat.items.isNotEmpty);
      // A live turn persists exactly one page of rows while the reader is
      // scrolled back. The overlap then repeats on every page: the floor
      // design fetched offsets 0, 60, 120, 120, 180, 180, 240 — one
      // redundant fetch of shown rows per page of new rows.
      api.rows.addAll(_shift(_turns(15), 'g'));
      for (var i = 0; i < 10 && chat.hasOlder; i++) {
        await chat.loadOlder();
      }
      expect(chat.hasOlder, isFalse);
      expect(prompts().first, 'Prompt 0', reason: 'paging must reach the end');
      final offsets = [for (final c in api.calls) c.$2];
      for (var i = 1; i < offsets.length; i++) {
        expect(
          offsets[i],
          greaterThan(offsets[i - 1]),
          reason: 'paging must never re-fetch an offset: $offsets',
        );
      }
    });

    test(
      'a live turn does not re-insert its stored rows as older items',
      () async {
        api.rows
          ..clear()
          ..addAll(_turns(50)); // 200 rows; the newest page shows 60.
        unawaited(chat.open());
        await _until(() => chat.items.isNotEmpty);
        // A running turn persists two pages of rows while the reader is back
        // in history — more than the shown window. The live aggregate already
        // shows the turn; paging must treat its stored rows as shown, not
        // re-insert them as older duplicates.
        api.rows.addAll(
          _shift(_turns(30), 'g'),
        ); // 120 rows > the 60-row window
        gateway.debugEmit(
          StreamEvent(
            type: 'message.start',
            data: const {},
            sessionId: 'stored',
          ),
        );
        gateway.debugEmit(
          StreamEvent(
            type: 'message.delta',
            data: const {'text': 'live reply'},
            sessionId: 'stored',
          ),
        );
        final beforeAdopt = api.calls.length;
        gateway.debugEmit(
          StreamEvent(type: 'turn.end', data: const {}, sessionId: 'stored'),
        );
        // The adopt walks newest pages until it reaches a known row: two
        // pages of live rows plus the window page that stops it. Without the
        // adopt no extra fetch ever happens and this wait just times out.
        await _until(() => api.calls.length >= beforeAdopt + 3);
        for (var i = 0; i < 12 && chat.hasOlder; i++) {
          await chat.loadOlder();
        }
        expect(chat.hasOlder, isFalse);
        expect(
          prompts().first,
          'Prompt 0',
          reason: 'paging must reach the end',
        );
        // The burst re-tags ids only, so its prompts repeat the base fixture's
        // text: a stored live row paging back in shows up as a duplicate
        // prompt. The live turn streamed as one reply — none of its stored
        // rows may re-insert as older items.
        final ps = prompts();
        expect(
          ps.toSet().length,
          ps.length,
          reason: 'live-persisted rows must not page back in: $ps',
        );
      },
    );

    test('paging across a turn end skips no stored rows', () async {
      api.rows
        ..clear()
        ..addAll(_turns(50)); // 200 rows; the newest page shows 60.
      unawaited(chat.open());
      await _until(() => chat.items.isNotEmpty);
      // A live turn persists one page while the reader pages back: the
      // first page is all-known (shift carries the growth), the second
      // fetches fresh older rows.
      api.rows.addAll(_shift(_turns(15), 'g')); // 60 rows
      await chat.loadOlder();
      await chat.loadOlder();
      expect(prompts().first, 'Prompt 20');
      // The turn ends: adoption learns the 60 live rows. The shift was
      // carrying exactly those rows, so it must shrink by the adopted
      // count — otherwise the next offset overshoots real coverage.
      final beforeAdopt = api.calls.length;
      gateway.debugEmit(
        StreamEvent(type: 'turn.end', data: const {}, sessionId: 'stored'),
      );
      await _until(() => api.calls.length >= beforeAdopt + 2);
      await _settle();
      for (var i = 0; i < 12 && chat.hasOlder; i++) {
        await chat.loadOlder();
      }
      expect(chat.hasOlder, isFalse);
      final ps = prompts();
      expect(
        ps,
        containsAll([for (var i = 0; i < 50; i++) 'Prompt $i']),
        reason: 'paging after adoption must skip no stored rows: $ps',
      );
      expect(ps.toSet().length, ps.length, reason: 'no duplicates: $ps');
    });

    test('adoption during an in-flight page does not overshoot', () async {
      final held = _HeldPagedApi(gateway.dashboard, _turns(50));
      api = held;
      gateway.api = held;
      unawaited(chat.open());
      await _until(() => chat.items.isNotEmpty);
      // Two pages of growth: the first loadOlder inserts one page of live
      // rows; the second (held) targets the shown window while adoption
      // learns the remaining live rows mid-fetch.
      held.rows.addAll(_shift(_turns(30), 'g')); // 120 rows
      await chat.loadOlder();
      final gate = Completer<void>();
      held.gates[held.calls.length] = gate;
      final inFlight = chat.loadOlder();
      await _settle();
      final beforeAdopt = held.calls.length;
      gateway.debugEmit(
        StreamEvent(type: 'turn.end', data: const {}, sessionId: 'stored'),
      );
      await _until(() => held.calls.length >= beforeAdopt + 2);
      await _settle();
      gate.complete();
      await inFlight;
      for (var i = 0; i < 12 && chat.hasOlder; i++) {
        await chat.loadOlder();
      }
      expect(chat.hasOlder, isFalse);
      final ps = prompts();
      expect(
        ps,
        containsAll([for (var i = 0; i < 50; i++) 'Prompt $i']),
        reason: 'a mid-fetch adoption must not overshoot the next offset: $ps',
      );
    });

    test('a turn longer than five pages adopts all its stored rows', () async {
      // Two extra rows put the newest page boundary mid-turn, so the shown
      // window trims below a full page.
      api.rows
        ..clear()
        ..addAll(_turns(50))
        ..addAll([
          {'id': 'x-a', 'role': 'assistant', 'content': 'partial'},
          {'id': 'x-t', 'role': 'tool', 'tool_call_id': 'x-a', 'content': 'ok'},
        ]);
      unawaited(chat.open());
      await _until(() => chat.items.isNotEmpty);
      // One live turn persists 360 rows — more than the old five-page
      // adoption cap. Its oldest rows (including its prompt) must be
      // adopted too, or they page back in as older items.
      final long = <Map<String, dynamic>>[
        {'id': 'L-u', 'role': 'user', 'content': 'Prompt long'},
        for (var i = 0; i < 179; i++) ...[
          {
            'id': 'L-a$i',
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'L-call$i',
                'function': {'name': 'terminal', 'arguments': '{}'},
              },
            ],
          },
          {
            'id': 'L-tool$i',
            'role': 'tool',
            'tool_call_id': 'L-call$i',
            'content': 'ok',
          },
        ],
        {'id': 'L-end', 'role': 'assistant', 'content': 'Reply long'},
      ];
      api.rows.addAll(long); // 360 rows
      gateway.debugEmit(
        StreamEvent(type: 'message.start', data: const {}, sessionId: 'stored'),
      );
      gateway.debugEmit(
        StreamEvent(
          type: 'message.delta',
          data: const {'text': 'live reply'},
          sessionId: 'stored',
        ),
      );
      final beforeAdopt = api.calls.length;
      gateway.debugEmit(
        StreamEvent(type: 'turn.end', data: const {}, sessionId: 'stored'),
      );
      // Six pages of live rows plus the known window page that stops the
      // walk; the capped walk stopped after five.
      await _until(() => api.calls.length >= beforeAdopt + 7);
      await _settle();
      for (var i = 0; i < 16 && chat.hasOlder; i++) {
        await chat.loadOlder();
      }
      expect(chat.hasOlder, isFalse);
      final ps = prompts();
      expect(ps.first, 'Prompt 0', reason: 'paging must reach the end');
      expect(
        ps,
        containsAll([for (var i = 0; i < 50; i++) 'Prompt $i']),
        reason: 'no stored rows skipped: $ps',
      );
      expect(
        ps.where((p) => p == 'Prompt long'),
        isEmpty,
        reason: 'the live turn\'s stored rows must not page back in: $ps',
      );
    });
  });

  group('History wire params', () {
    test('transcript pages ask the gateway to skip inline images', () async {
      final dash = _CapturingDashboard();
      final api = DashboardApiClient.withDashboard(dash);
      await api.getMessagesBytes('s1', limit: 60, latest: true);
      expect(
        dash.lastQuery!['inline_images'],
        'false',
        reason: 'stored data-URI images must not cross the wire to NextGen',
      );
    });
  });
}
