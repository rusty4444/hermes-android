// Independent adverse-order review regressions, reproduced on cd3fd37.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, (_) async => null);
  });
  tearDown(() {
    HttpOverrides.global = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null);
  });

  testWidgets(
    'review: identical real prompts/replies stay distinct after cold reopen',
    (tester) async {
      final h = await _Harness.open(tester);
      await h.send('Repeat exactly', 1);
      h.server.finishReceipt('Repeat exactly', 'Identical answer', firstId: 3);
      await h.untilRetired();
      await h.send('Repeat exactly', 2);
      h.server.finishReceipt('Repeat exactly', 'Identical answer', firstId: 5);
      await h.untilRetired();
      await tester.pumpAndSettle();
      final expected = [
        'Prior prompt',
        'Prior answer',
        'Repeat exactly',
        'Identical answer',
        'Repeat exactly',
        'Identical answer',
      ];
      expect(_bubbles(tester), expected);
      expect(h.server.prompts, hasLength(2));
      // Replace both route and app controller: this is a process-like cold read,
      // not only a second route backed by the same retained owner.
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await h.controller.close();
      h.controller = GatewayTurnApplicationController();
      h.push();
      await widgetUntil(
        tester,
        () => _bubbles(tester).length == expected.length,
      );
      await tester.pumpAndSettle();
      expect(_bubbles(tester), expected);
      expect(h.server.prompts, hasLength(2));
      expect(h.owner.snapshot.displayRows, isEmpty);
      await h.close();
    },
  );

  testWidgets(
    'review: lag and HTTP read error preserve real received answer until retry',
    (tester) async {
      final h = await _Harness.open(tester);
      await h.send('Lagging prompt', 1);
      h.server.finishReceipt(
        'Lagging prompt',
        'Received answer',
        firstId: 3,
        publish: false,
      );
      await widgetUntil(tester, () => !h.owner.snapshot.hasActiveTurn);
      await tester.pumpAndSettle();
      expect(h.owner.snapshot.displayRows, isNotEmpty);
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Lagging prompt',
        'Received answer',
      ]);
      h.server.failHistory = true;
      final failedBefore = h.server.reads.length;
      await h.refresh();
      await widgetUntil(tester, () => h.server.reads.length > failedBefore);
      await tester.pumpAndSettle();
      expect(h.owner.snapshot.displayRows, isNotEmpty);
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Lagging prompt',
        'Received answer',
      ]);
      h.server.failHistory = false;
      h.server.rows.addAll(h.server.unpublished);
      await h.refresh();
      await h.untilRetired();
      await tester.pumpAndSettle();
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Lagging prompt',
        'Received answer',
      ]);
      expect(h.server.prompts, hasLength(1));
      await h.close();
    },
  );

  testWidgets(
    'held route Refresh cannot revive a newer alias presentation veto',
    (tester) async {
      final h = await _Harness.open(tester);
      await h.send('Current prompt', 1);
      h.server.finishReceipt('Current prompt', 'Saved answer', firstId: 3);
      await h.untilRetired();
      await tester.pumpAndSettle();
      final olderLatest = h.owner.snapshot.historyRows.last;
      final reservation = h.owner.reserve()!;
      h.server.holdNextOffset = 0;
      await tester.tap(find.byTooltip('Chat actions').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Refresh').hitTestable());
      await widgetUntil(tester, () => h.server.held != null);
      final held = h.server.held!;
      final alias = h.controller
          .normalSessionFor(h.server.connection)
          .chatFor('local-alias', title: 'Local alias');
      final newerVeto = {...olderLatest, 'partial': true};
      expect(alias.observeHistory([newerVeto]), isTrue);
      alias.bindStoredSession('stored');
      h.owner.cancelPreparation(reservation);
      await tester.pumpAndSettle();
      expect(h.owner.snapshot.historyRows.last, olderLatest);
      expect(h.owner.snapshot.historyPresentationRows.last, newerVeto);
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Current prompt',
      ]);
      held.release.complete(false);
      await widgetUntil(tester, () => held.finished.isCompleted);
      await tester.pumpAndSettle();
      expect(h.owner.snapshot.historyPresentationRows.last, newerVeto);
      expect(
        _bubbles(tester),
        ['Prior prompt', 'Prior answer', 'Current prompt'],
        reason:
            'physical latest authority must not overwrite newer alias context',
      );
      // A genuinely newer physical observation may replace the alias veto.
      final readsBeforeRetry = h.server.reads.length;
      await h.refresh();
      await widgetUntil(tester, () => h.server.reads.length > readsBeforeRetry);
      await tester.pumpAndSettle();
      expect(h.owner.snapshot.historyPresentationRows.last, olderLatest);
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Current prompt',
        'Saved answer',
      ]);
      expect(h.server.prompts, hasLength(1));
      await h.close();
    },
  );

  testWidgets(
    'newer alias presentation veto survives the older admission snapshot',
    (tester) async {
      final h = await _Harness.open(tester);
      await h.send('Current prompt', 1);
      h.server.finishReceipt(
        'Current prompt',
        'Long answer',
        firstId: 3,
        tools: 65,
      );
      await h.untilRetired();
      await tester.pumpAndSettle();
      expect(_bubbles(tester), contains('Long answer'));
      final olderLatest = h.owner.snapshot.historyRows.last;
      final newerVeto = {...olderLatest, 'partial': true};
      // A never-bound local owner can converge on the existing stored owner;
      // replacing an already durable wire binding would be an invalid fixture.
      final alias = h.controller
          .normalSessionFor(h.server.connection)
          .chatFor('local-alias', title: 'Local alias');
      expect(alias.observeHistory([newerVeto]), isTrue);
      final reservation = h.owner.reserve()!;
      alias.bindStoredSession('stored');
      h.owner.cancelPreparation(reservation);
      await tester.pumpAndSettle();
      expect(h.owner.snapshot.historyRows.last, olderLatest);
      expect(h.owner.snapshot.historyPresentationRows.last, newerVeto);
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Current prompt',
      ]);
      expect(h.server.prompts, hasLength(1));
      await h.close();
    },
  );

  for (final oldReadFails in [false, true]) {
    for (final newSettlesBeforeRead in [false, true]) {
      testWidgets(
        'review: new turn fences held context error=$oldReadFails settledBeforeRelease=$newSettlesBeforeRead',
        (tester) async {
          final h = await _Harness.open(tester);
          await h.send('Old prompt', 1);
          h.server.holdNextOffset = 50;
          h.server.finishReceipt(
            'Old prompt',
            'Old answer',
            firstId: 3,
            tools: 65,
          );
          await widgetUntil(tester, () => h.server.held != null);
          final held = h.server.held!;
          expect(h.owner.snapshot.hasActiveTurn, isFalse);
          expect(h.owner.snapshot.displayRows, isNotEmpty);
          await h.send('New prompt', 2);
          h.server.event('message.start', {}, turnId: 'wire-2');
          h.server.event('message.delta', {
            'text': 'New live partial',
          }, turnId: 'wire-2');
          await widgetUntil(
            tester,
            () => h.owner.snapshot.displayRows.any(
              (r) => r['content'] == 'New live partial',
            ),
          );
          final newerTurn = h.owner.snapshot.turnId;
          if (newSettlesBeforeRead) {
            h.server.finishReceipt('New prompt', 'New answer', firstId: 70);
            await widgetUntil(tester, () => !h.owner.snapshot.hasActiveTurn);
            await tester.pumpAndSettle();
          }
          held.release.complete(oldReadFails);
          await widgetUntil(tester, () => held.finished.isCompleted);
          await tester.pump();
          expect(h.owner.snapshot.turnId, newerTurn);
          if (!newSettlesBeforeRead) {
            expect(h.owner.snapshot.hasActiveTurn, isTrue);
            expect(h.owner.snapshot.responseFailure, isNull);
            expect(
              h.owner.snapshot.displayRows.any(
                (r) => r['content'] == 'New live partial',
              ),
              isTrue,
            );
            // Completing the new owner must close only its own lifecycle and allow
            // a trailing fresh read to reconcile the old retained owner safely.
            h.server.finishReceipt('New prompt', 'New answer', firstId: 70);
          }
          await h.untilRetired();
          await tester.pumpAndSettle();
          expect(_bubbles(tester), [
            'Prior prompt',
            'Prior answer',
            'Old prompt',
            'Old answer',
            'New prompt',
            'New answer',
          ]);
          expect(h.server.prompts, hasLength(2));
          expect(h.owner.snapshot.responseFailure, isNull);
          await h.close();
        },
      );
    }
  }

  testWidgets(
    'review: manual Refresh recovers interrupted automatic context without resubmitting',
    (tester) async {
      final h = await _Harness.open(tester);
      await h.send('Old prompt', 1);
      h.server.holdNextOffset = 50;
      h.server.finishReceipt('Old prompt', 'Old answer', firstId: 3, tools: 65);
      await widgetUntil(tester, () => h.server.held != null);
      final held = h.server.held!;
      await h.send('New prompt', 2);
      h.server.event('message.start', {}, turnId: 'wire-2');
      h.server.event('message.delta', {
        'text': 'New live partial',
      }, turnId: 'wire-2');
      await widgetUntil(
        tester,
        () => h.owner.snapshot.displayRows.any(
          (r) => r['content'] == 'New live partial',
        ),
      );
      held.release.complete(true);
      await widgetUntil(tester, () => held.finished.isCompleted);
      h.server.finishReceipt('New prompt', 'New answer', firstId: 70);
      await widgetUntil(
        tester,
        () =>
            !h.owner.snapshot.hasActiveTurn &&
            h.owner.snapshot.historyRows.any((r) => r['id'] == 71),
      );
      await tester.pumpAndSettle();
      await h.refresh();
      await h.untilRetired();
      await tester.pumpAndSettle();
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Old prompt',
        'Old answer',
        'New prompt',
        'New answer',
      ]);
      expect(h.server.prompts, hasLength(2));
      await h.close();
    },
  );

  testWidgets(
    'review: failed automatic context is bounded and manual Refresh retries',
    (tester) async {
      final h = await _Harness.open(tester);
      await h.send('Long prompt', 1);
      h.server.failContext = true;
      h.server.finishReceipt(
        'Long prompt',
        'Long answer',
        firstId: 3,
        tools: 65,
      );
      await widgetUntil(
        tester,
        () => h.server.reads.any((r) => r.offset == 50),
      );
      await tester.pumpAndSettle();
      expect(h.owner.snapshot.displayRows, isNotEmpty);
      final afterFailure = h.server.reads.length;
      // Fake time advancing exercises any accidental retry timer without a sleep.
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(
        h.server.reads.length,
        afterFailure,
        reason: 'automatic context must not spin after an older page error',
      );
      h.server.failContext = false;
      await h.refresh();
      await h.untilRetired();
      await tester.pumpAndSettle();
      expect(_bubbles(tester), [
        'Prior prompt',
        'Prior answer',
        'Long prompt',
        'Long answer',
      ]);
      expect(h.server.reads.where((r) => r.offset == 50), hasLength(2));
      expect(h.server.prompts, hasLength(1));
      await h.close();
    },
  );
}

List<String> _bubbles(WidgetTester tester) => tester
    .widgetList<MessageBubble>(find.byType(MessageBubble))
    .map((b) => b.content)
    .toList();

class _Harness {
  _Harness(this.tester, this.server);
  final WidgetTester tester;
  final _ReviewServer server;
  GatewayTurnApplicationController controller =
      GatewayTurnApplicationController();
  final navigator = GlobalKey<NavigatorState>();
  bool closed = false;
  NormalGatewayChatOwner get owner =>
      controller.normalSessionFor(server.connection).findChat('stored')!;

  static Future<_Harness> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final h = _Harness(tester, (await tester.runAsync(_ReviewServer.start))!);
    addTearDown(() async {
      await h.controller.close();
      await tester.runAsync(h.server.close);
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: h.navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Chats')),
      ),
    );
    h.push();
    await widgetUntil(tester, () => _bubbles(tester).contains('Prior answer'));
    await tester.pumpAndSettle();
    return h;
  }

  void push() => unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          connection: server.connection,
          session: Session(
            id: 'stored',
            title: 'Independent review',
            model: 'fixture',
            source: 'test',
            messageCount: server.rows.length,
            isActive: false,
            preview: '',
            startedAt: 1,
          ),
          turnApplicationController: controller,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      ),
    ),
  );

  Future<void> send(String prompt, int count) async {
    await tester.enterText(find.byType(TextField), prompt);
    await widgetUntil(
      tester,
      () =>
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
              .onPressed !=
          null,
    );
    await tester.tap(find.byTooltip('Send').hitTestable());
    await widgetUntil(tester, () => server.prompts.length == count);
  }

  Future<void> refresh() async {
    await tester.tap(find.byTooltip('Chat actions').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh').hitTestable());
  }

  Future<void> untilRetired() async {
    try {
      await widgetUntil(
        tester,
        () =>
            !owner.snapshot.hasActiveTurn && owner.snapshot.displayRows.isEmpty,
      );
    } catch (_) {
      debugPrint(
        'REVIEW_DIAGNOSTIC phase=${owner.snapshot.phase} '
        'received=${owner.snapshot.displayRows.map((r) => r["content"]).toList()} '
        'canonical=${owner.snapshot.historyRows.map((r) => r["id"]).toList()} '
        'contextKey=${owner.persistedTurnContextKey(owner.snapshot.historyRows)} '
        'offsets=${server.reads.map((r) => r.offset).toList()} '
        'bubbles=${_bubbles(tester)}',
      );
      rethrow;
    }
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
    await tester.runAsync(server.close);
    await tester.pump(const Duration(seconds: 16));
  }
}

class _Read {
  _Read(this.offset);
  final int offset;
}

class _HeldRead {
  final release = Completer<bool>();
  final finished = Completer<void>();
}

class _ReviewServer extends BindingServer {
  _ReviewServer(super.server) {
    creates = 1;
    rows.addAll([
      {'id': 1, 'role': 'user', 'content': 'Prior prompt'},
      {
        'id': 2,
        'role': 'assistant',
        'content': 'Prior answer',
        'status': 'completed',
      },
    ]);
  }
  final reads = <_Read>[];
  final unpublished = <Map<String, dynamic>>[];
  bool failHistory = false;
  bool failContext = false;
  int? holdNextOffset;
  _HeldRead? held;
  static Future<_ReviewServer> start() async {
    final f = _ReviewServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    f.server.listen(f.handle);
    return f;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (!request.uri.path.endsWith('/messages')) return super.handle(request);
    final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
    final limit = int.parse(request.uri.queryParameters['limit'] ?? '50');
    reads.add(_Read(offset));
    final end = (rows.length - offset).clamp(0, rows.length);
    final start = (end - limit).clamp(0, end);
    final captured = rows
        .sublist(start, end)
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    var fail = failHistory || (offset != 0 && failContext);
    _HeldRead? holding;
    if (holdNextOffset == offset) {
      holdNextOffset = null;
      holding = held = _HeldRead();
      fail = await holding.release.future;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.statusCode = fail ? 503 : 200;
    request.response.write(
      jsonEncode(
        fail ? {'error': 'review read unavailable'} : {'data': captured},
      ),
    );
    await request.response.close();
    holding?.finished.complete();
  }

  void finishReceipt(
    String prompt,
    String answer, {
    required int firstId,
    int tools = 0,
    bool publish = true,
  }) {
    final finalId = firstId + tools + 1;
    final committed = <Map<String, dynamic>>[
      {'id': firstId, 'role': 'user', 'content': prompt},
      for (var i = 0; i < tools; i++)
        {
          'id': firstId + 1 + i,
          'role': 'tool',
          'tool_call_id': 'review-$i',
          'tool_name': 'terminal',
          'content': 'Result $i',
        },
      {
        'id': finalId,
        'role': 'assistant',
        'content': answer,
        'status': 'completed',
      },
    ];
    (publish ? rows : unpublished).addAll(committed);
    running = false;
    final turn = 'wire-${prompts.length}';
    event('message.start', {}, turnId: turn);
    event('message.complete', {
      'text': answer,
      'status': 'complete',
      'persisted_turn': {
        'row_ids': committed.map((r) => r['id']).toList(),
        'complete': true,
        'user_row_id': firstId,
        'user_row_ids': [firstId],
        'final_assistant_row_id': finalId,
      },
    }, turnId: turn);
    event('turn.end', {'status': 'completed'}, turnId: turn);
  }

  @override
  Future<void> close() async {
    final h = held;
    if (h != null && !h.release.isCompleted) h.release.complete(true);
    await super.close();
  }
}
