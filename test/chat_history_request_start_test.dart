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
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
  });
  tearDown(() {
    HttpOverrides.global = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        );
  });
  for (final result in [
    'appended',
    'empty',
    'lower',
    'unidentified',
    'failed',
  ]) {
    for (final oldFails in [false, true]) {
      testWidgets('READ actual Refresh $result oldFails=$oldFails', (
        tester,
      ) async {
        final f = await _Fixture.mount(tester);
        try {
          // Refresh is the real hit-testable production menu and HTTP caller.
          f.wire.rows
            ..clear()
            ..add(_row(101, 'Held obsolete snapshot'));
          final held = f.wire.holdNext(status: oldFails ? 503 : 200);
          await tester.tap(find.byTooltip('Chat actions').hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Refresh').hitTestable());
          await widgetUntil(tester, () => held.entered.isCompleted);
          final newer = switch (result) {
            'empty' => <Map<String, dynamic>>[],
            'lower' => [_row(1, 'Compressed latest')],
            'unidentified' => [
              {'role': 'assistant', 'content': 'No durable ID'},
            ],
            _ => [_row(100, 'Old answer'), _row(103, 'New latest')],
          };
          f.wire.rows
            ..clear()
            ..addAll(newer);
          if (result == 'failed') {
            f.wire.failNext = true;
            await tester.runAsync(() async {
              await expectLater(
                f.other.getMessages('stored', latest: true),
                throwsA(isA<Exception>()),
              );
            });
          } else {
            final rows = (await tester.runAsync(
              () => f.other.getMessages('stored', latest: true),
            ))!;
            f.owner.observeHistory(rows);
            expect(f.owner.snapshot.historyRows, newer);
          }
          held.release();
          await widgetUntil(
            tester,
            () =>
                held.delivered.isCompleted && f.api.completed == f.api.started,
          );
          await tester.pump();
          if (result == 'failed') {
            expect(f.owner.snapshot.historyRows, [
              _row(
                oldFails ? 100 : 101,
                oldFails ? 'Old answer' : 'Held obsolete snapshot',
              ),
            ]);
            if (oldFails) {
              expect(find.byType(MaterialBanner), findsOneWidget);
            } else {
              expect(find.byType(MaterialBanner), findsNothing);
            }
          } else {
            expect(f.owner.snapshot.historyRows, newer);
            expect(
              find.text('Held obsolete snapshot', findRichText: true),
              findsNothing,
              reason: 'a rejected read cannot mutate the actual route window',
            );
            expect(
              find.byType(MaterialBanner),
              findsNothing,
              reason:
                  'a superseded physical error cannot publish an error banner',
            );
          }
          expect(tester.state(find.byType(ChatScreen)), same(f.state));
          expect(find.byType(CircularProgressIndicator), findsNothing);
        } finally {
          await f.close(tester);
        }
      });
    }
  }

  for (final oldFails in [false, true]) {
    testWidgets('READ actual deferred refresh superseded oldFails=$oldFails', (
      tester,
    ) async {
      // Read authority uses raw, untyped history, not quiet-mode finality.
      SharedPreferences.setMockInitialValues({'verbose_mode': true});
      final f = await _Fixture.mount(tester);
      try {
        final first = f.wire.holdNext();
        await tester.tap(find.byTooltip('Chat actions').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refresh').hitTestable());
        await widgetUntil(tester, () => first.entered.isCompleted);
        final reservation = f.owner.reserve()!;
        f.owner.cancelPreparation(reservation);
        f.wire.rows
          ..clear()
          ..add(_row(101, 'Deferred obsolete snapshot'));
        final deferred = f.wire.holdNext(status: oldFails ? 503 : 200);
        first.release();
        await widgetUntil(tester, () => deferred.entered.isCompleted);
        f.wire.rows
          ..clear()
          ..add(_row(103, 'Deferred newer success'));
        final fresh = (await tester.runAsync(
          () => f.other.getMessages('stored', latest: true),
        ))!;
        f.owner.observeHistory(fresh);
        expect(f.owner.snapshot.historyRows, fresh);
        deferred.release();
        await widgetUntil(
          tester,
          () =>
              deferred.delivered.isCompleted &&
              f.api.completed == f.api.started,
        );
        await tester.pump();
        expect(f.owner.snapshot.historyRows, fresh);
        expect(
          find.text('Deferred obsolete snapshot', findRichText: true),
          findsNothing,
        );
        expect(
          find.text('Deferred newer success', findRichText: true),
          findsOneWidget,
        );
        expect(find.byType(MaterialBanner), findsNothing);
      } finally {
        await f.close(tester);
      }
    });
  }

  for (final oldFails in [false, true]) {
    testWidgets(
      'READ two actual Refreshes later failure preserves older ownership oldFails=$oldFails',
      (tester) async {
        final f = await _Fixture.mount(tester);
        try {
          f.wire.rows
            ..clear()
            ..add(_row(101, 'Still owned older success'));
          final held = f.wire.holdNext(status: oldFails ? 503 : 200);
          await tester.tap(find.byTooltip('Chat actions').hitTestable());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Refresh').hitTestable());
          await widgetUntil(tester, () => held.entered.isCompleted);
          f.wire.failNext = true;
          await tester.tap(find.byTooltip('Chat actions').hitTestable());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('Refresh').hitTestable());
          await widgetUntil(
            tester,
            () => f.api.started >= 3 && f.api.completed == f.api.started - 1,
          );
          await tester.pump();
          expect(find.byType(MaterialBanner), findsOneWidget);
          held.release();
          await widgetUntil(
            tester,
            () =>
                held.delivered.isCompleted && f.api.completed == f.api.started,
          );
          await tester.pump();
          expect(f.owner.snapshot.historyRows.last['id'], oldFails ? 100 : 101);
          expect(
            find.byType(MaterialBanner),
            oldFails ? findsOneWidget : findsNothing,
          );
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  for (final boundary in [
    'close',
    'binding',
    'redirect',
    'admission',
    'dispose',
    'account',
    'route-session',
  ]) {
    for (final oldFails in [false, true]) {
      testWidgets(
        'READ actual held Refresh fenced by $boundary oldFails=$oldFails',
        (tester) async {
          final f = await _Fixture.mount(
            tester,
            localDraft: boundary == 'binding',
          );
          try {
            f.wire.rows
              ..clear()
              ..add(_row(101, 'Departed read must not appear'));
            final held = f.wire.holdNext(status: oldFails ? 503 : 200);
            await tester.tap(find.byTooltip('Chat actions').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Refresh').hitTestable());
            await widgetUntil(tester, () => held.entered.isCompleted);
            final session = f.controller.normalSessionFor(f.wire.connection);
            switch (boundary) {
              case 'close':
                await tester.runAsync(session.close);
              case 'binding':
                f.owner.bindStoredSession('replacement');
              case 'redirect':
                final winner = session.chatFor('alias', title: 'Winner');
                winner.bindStoredSession('stored');
                expect(session.findChat('stored'), same(winner));
              case 'admission':
                final reservation = f.owner.reserve()!;
                f.owner.cancelPreparation(reservation);
                // A generation change requests a fresh trailing read. Keep it
                // unknown so the old result itself cannot masquerade as fresh.
                f.wire.failNext = true;
              case 'dispose':
                await tester.pumpWidget(const SizedBox.shrink());
              case 'account':
              case 'route-session':
                final previous = tester.widget<ChatScreen>(
                  find.byType(ChatScreen),
                );
                final c = f.wire.connection;
                final replacement = SavedConnection(
                  id: c.id,
                  label: c.label,
                  host: c.host,
                  port: c.port,
                  apiKey: boundary == 'account' ? 'replacement' : c.apiKey,
                  dashboardPortOverride: c.dashboardPortOverride,
                  dashboardProxied: c.dashboardProxied,
                );
                await tester.pumpWidget(
                  MaterialApp(
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: ChatScreen(
                      connection: replacement,
                      testApiClient: f.api,
                      session: boundary == 'route-session'
                          ? const Session(
                              id: 'different',
                              title: 'Different',
                              model: 'fixture',
                              source: 'test',
                              messageCount: 1,
                              isActive: false,
                              preview: '',
                              startedAt: 1,
                            )
                          : previous.session,
                      turnApplicationController: f.controller,
                      testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
                    ),
                  ),
                );
                expect(tester.state(find.byType(ChatScreen)), same(f.state));
            }
            held.release();
            await widgetUntil(
              tester,
              () =>
                  held.delivered.isCompleted &&
                  f.api.completed == f.api.started,
            );
            await tester.pump();
            expect(
              f.owner.snapshot.historyRows.map((r) => r['content']),
              isNot(contains('Departed read must not appear')),
            );
            expect(
              find.text('Departed read must not appear', findRichText: true),
              findsNothing,
            );
            expect(find.byType(MaterialBanner), findsNothing);
          } finally {
            await f.close(tester);
          }
        },
      );
    }
  }

  testWidgets(
    'READ typed physical start accepts older success after newer failure',
    (tester) async {
      final f = await _Fixture.mount(tester);
      try {
        final read = f.owner.beginHistoryRead('stored');
        final held = f.wire.holdNext();
        final old = f.other.getMessages('stored', latest: true);
        List<Map<String, dynamic>>? oldRows;
        old.then((rows) => oldRows = rows);
        await widgetUntil(tester, () => held.entered.isCompleted);
        final later = f.owner.beginHistoryRead('stored');
        f.wire.failNext = true;
        await tester.runAsync(() async {
          await expectLater(
            f.api.getMessages('stored', latest: true),
            throwsException,
          );
        });
        expect(later.isCurrent, isTrue);
        expect(read.isCurrent, isTrue);
        held.release();
        await widgetUntil(tester, () => oldRows != null);
        final rows = oldRows!;
        expect(f.owner.observeHistory(rows, read: read), isTrue);
        expect(f.owner.snapshot.historyRows, rows);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'READ token cannot cross account, admission, alias or synchronous close',
    (tester) async {
      final f = await _Fixture.mount(tester);
      final otherController = GatewayTurnApplicationController();
      try {
        final read = f.owner.beginHistoryRead('stored');
        final other = otherController.normalSessionFor(f.wire.connection);
        await tester.runAsync(() => other.ready);
        final otherOwner = other.chatFor(
          'stored',
          storedSessionId: 'stored',
          title: 'Other scope',
        );
        expect(
          otherOwner.observeHistory([_row(400, 'Wrong account')], read: read),
          isFalse,
        );
        expect(otherOwner.snapshot.historyRows, isEmpty);
        final r = f.owner.reserve()!;
        expect(read.isCurrent, isFalse);
        f.owner.cancelPreparation(r);
        expect(read.isCurrent, isFalse);
        final closing = f.owner.beginHistoryRead('stored');
        final close = f.controller.normalSessionFor(f.wire.connection).close();
        expect(closing.isCurrent, isFalse);
        expect(
          f.owner.observeHistory([_row(500, 'After close')], read: closing),
          isFalse,
        );
        await tester.runAsync(() => close);
      } finally {
        await tester.runAsync(otherController.close);
        await f.close(tester);
      }
    },
  );

  for (final oldFails in [false, true]) {
    testWidgets(
      'READ SSE history vs retained Refresh callback oldFails=$oldFails',
      (tester) async {
        final wire = (await tester.runAsync(_ReadServer.start))!;
        final connection = SavedConnection(
          id: 'rest-read',
          label: 'REST',
          host: '127.0.0.1',
          port: wire.server.port,
          apiKey: 'fixture',
        );
        final api = _PhysicalApi(connection);
        final controller = GatewayTurnApplicationController();
        try {
          wire.rows.add(_row(100, 'REST old context'));
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ChatScreen(
                connection: connection,
                testApiClient: api,
                session: const Session(
                  id: 'stored',
                  title: 'REST',
                  model: 'fixture',
                  source: 'test',
                  messageCount: 1,
                  isActive: false,
                  preview: '',
                  startedAt: 1,
                ),
                turnApplicationController: controller,
                testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
              ),
            ),
          );
          await widgetUntil(
            tester,
            () => api.started > 0 && api.completed == api.started,
          );
          // Widened callback seam: ordinary UI hides this menu while streaming.
          // Retain the production callback, not a second route or a live-user claim.
          final refresh = tester
              .widget<PopupMenuButton<String>>(
                find.byType(PopupMenuButton<String>),
              )
              .onSelected!;
          await tester.enterText(find.byType(TextField), 'REST prompt');
          await tester.tap(find.byTooltip('Send').hitTestable());
          await widgetUntil(tester, () => wire.sseEntered.isCompleted);
          wire.rows
            ..clear()
            ..add(_row(101, 'Obsolete REST completion'));
          final held = wire.holdNext(status: oldFails ? 503 : 200);
          wire.finishSse();
          await widgetUntil(tester, () => held.entered.isCompleted);
          wire.rows
            ..clear()
            ..add(_row(103, 'New REST latest'));
          refresh('refresh');
          await widgetUntil(
            tester,
            () => api.completed == api.started - 1 && api.started >= 3,
          );
          expect(api.successfulHistories.last, [_row(103, 'New REST latest')]);
          held.release();
          await widgetUntil(
            tester,
            () => held.delivered.isCompleted && api.completed == api.started,
          );
          await tester.pump();
          expect(
            find.text('Obsolete REST completion', findRichText: true),
            findsNothing,
          );
          expect(
            find.text('New REST latest', findRichText: true),
            findsNothing,
          );
          // A fresh GET is not a receipt-to-row match: this SSE response has
          // no durable ID, so retain its completed received transcript.
          expect(
            find.text('REST wire reply', findRichText: true),
            findsOneWidget,
          );
          expect(find.text('REST prompt', findRichText: true), findsOneWidget);
          expect(find.byType(MaterialBanner), findsNothing);
          await tester.enterText(find.byType(TextField), 'Next REST prompt');
          await tester.pump();
          expect(
            find.byTooltip('Send').hitTestable(),
            findsOneWidget,
            reason:
                'discarding an obsolete history GET cannot strand the completed REST stream',
          );
          expect(
            tester
                .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
                .onPressed,
            isNotNull,
          );
        } finally {
          wire.finishSse();
          for (final held in wire.holds) {
            held.release();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            api.close();
            await controller.close();
            await wire.close();
          });
          await tester.pump(const Duration(seconds: 16));
        }
      },
    );
  }

  testWidgets(
    'READ reentrant accepted callback cannot apply obsolete route window',
    (tester) async {
      final f = await _Fixture.mount(tester);
      Object? subscription;
      try {
        var armed = false;
        subscription = f.owner.subscribe((snapshot) {
          if (!armed) return;
          armed = false;
          f.owner.observeHistory([_row(200, 'Reentrant newer success')]);
        });
        f.wire.rows
          ..clear()
          ..add(_row(101, 'Obsolete inside callback'));
        final held = f.wire.holdNext();
        await tester.tap(find.byTooltip('Chat actions').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refresh').hitTestable());
        await widgetUntil(tester, () => held.entered.isCompleted);
        armed = true;
        held.release();
        await widgetUntil(
          tester,
          () => held.delivered.isCompleted && f.api.completed == f.api.started,
        );
        await tester.pump();
        expect(f.owner.snapshot.historyRows, [
          _row(200, 'Reentrant newer success'),
        ]);
        expect(
          find.text('Obsolete inside callback', findRichText: true),
          findsNothing,
        );
      } finally {
        if (subscription != null) f.owner.unsubscribe(subscription);
        await f.close(tester);
      }
    },
  );

  testWidgets('READ cold multi-page batch uses offset-zero authority only', (
    tester,
  ) async {
    // This case verifies retained raw pagination, including non-final trace rows.
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    final rows = [
      {'id': 1, 'role': 'user', 'content': 'Older user'},
      _row(2, 'Older answer'),
      for (var id = 3; id <= 52; id++)
        {'id': id, 'role': 'tool', 'content': 'tool context'},
    ];
    final f = await _Fixture.mount(tester, initialRows: rows);
    try {
      expect(f.wire.offsets, [0, 50]);
      expect(
        f.owner.snapshot.historyRows.map((r) => r['id']),
        orderedEquals(List.generate(50, (i) => i + 3)),
      );
      expect(find.text('Older answer', findRichText: true), findsOneWidget);
    } finally {
      await f.close(tester);
    }
  });

  for (final supersede in [false, true]) {
    testWidgets(
      'READ actual older paging preserves cursor, never latest supersede=$supersede',
      (tester) async {
        final rows = [
          for (var id = 1; id <= 100; id++)
            {
              'id': id,
              'role': id.isOdd ? 'user' : 'assistant',
              'content': 'Page row $id',
            },
        ];
        final f = await _Fixture.mount(tester, initialRows: rows);
        try {
          await tester.pumpAndSettle();
          final list = find.byType(ListView).first;
          final scroll = tester.state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          );
          scroll.position.jumpTo(0);
          await tester.pump();
          final held = f.wire.holdNext();
          await tester.tap(find.text('Load more…').hitTestable());
          await widgetUntil(tester, () => held.entered.isCompleted);
          expect(f.wire.offsets.last, 50);
          if (supersede) {
            f.owner.observeHistory([_row(150, 'New latest during paging')]);
          }
          held.release();
          await widgetUntil(
            tester,
            () =>
                held.delivered.isCompleted && f.api.completed == f.api.started,
          );
          await tester.pump();
          expect(
            f.owner.snapshot.historyRows.map((r) => r['id']),
            supersede ? [150] : orderedEquals(List.generate(50, (i) => i + 51)),
          );
          if (!supersede) {
            expect(
              scroll.position.pixels,
              greaterThan(0),
              reason: 'insertion above retains the visible anchor',
            );
          } else {
            scroll.position.jumpTo(0);
            await tester.pump();
            await tester.tap(find.text('Load more…').hitTestable());
            await widgetUntil(tester, () => f.api.completed == f.api.started);
            expect(
              f.wire.offsets.last,
              50,
              reason: 'discarded old page cannot advance the cursor',
            );
          }
        } finally {
          await f.close(tester);
        }
      },
    );
  }
}

Map<String, dynamic> _row(int id, String text) => {
  'id': id,
  'role': 'assistant',
  'content': text,
};

class _Fixture {
  _Fixture(this.wire, this.controller, this.api, this.other);
  final _ReadServer wire;
  final GatewayTurnApplicationController controller;
  final _PhysicalApi api;
  final ApiClient other;
  late NormalGatewayChatOwner owner;
  late State state;
  static Future<_Fixture> mount(
    WidgetTester tester, {
    List<Map<String, dynamic>>? initialRows,
    bool localDraft = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    final wire = (await tester.runAsync(_ReadServer.start))!;
    wire.rows.addAll(initialRows ?? [_row(100, 'Old answer')]);
    final controller = GatewayTurnApplicationController();
    final api = _PhysicalApi(wire.connection);
    final f = _Fixture(
      wire,
      controller,
      api,
      ApiClient(baseUrl: wire.connection.baseUrl, apiKey: 'fixture'),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChatScreen(
          connection: wire.connection,
          testApiClient: api,
          session: Session(
            id: localDraft ? 'local' : 'stored',
            title: 'Read authority',
            model: 'fixture',
            source: 'test',
            messageCount: 1,
            isActive: false,
            preview: '',
            startedAt: 1,
            isLocalDraft: localDraft,
          ),
          projectWorkingDirectory: localDraft ? '/project' : null,
          turnApplicationController: controller,
          testVoiceComposerAdapter: FakeVoiceComposerAdapter(),
        ),
      ),
    );
    f.owner = controller
        .normalSessionFor(wire.connection)
        .findChat(localDraft ? 'local' : 'stored')!;
    await widgetUntil(
      tester,
      () =>
          f.owner.snapshot.historyRows.isNotEmpty &&
          api.completed == api.started,
    );
    f.state = tester.state(find.byType(ChatScreen));
    return f;
  }

  Future<void> close(WidgetTester tester) async {
    for (final hold in wire.holds) {
      hold.release();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await controller.close();
      api.close();
      other.close();
      await wire.close();
    });
    await tester.pump(const Duration(seconds: 16));
    await tester.binding.setSurfaceSize(null);
  }
}

class _Hold {
  _Hold(this.status);
  final int status;
  final entered = Completer<void>();
  final gate = Completer<void>();
  final delivered = Completer<void>();
  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}

class _ReadServer extends BindingServer {
  _ReadServer(super.server);
  final holds = <_Hold>[];
  _Hold? next;
  bool failNext = false;
  final offsets = <int>[];
  final sseEntered = Completer<void>();
  final _sseFinish = Completer<void>();
  void finishSse() {
    if (!_sseFinish.isCompleted) _sseFinish.complete();
  }

  static Future<_ReadServer> start() async {
    final f = _ReadServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    f.server.listen(f.handle);
    return f;
  }

  _Hold holdNext({int status = 200}) {
    final h = _Hold(status);
    holds.add(h);
    next = h;
    return h;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (request.method == 'POST' &&
        request.uri.path == '/v1/chat/completions') {
      await request.drain<void>();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'REST wire reply'},
            },
          ],
        })}\n\n',
      );
      await request.response.flush();
      sseEntered.complete();
      await _sseFinish.future;
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
      return;
    }
    if (request.uri.path.endsWith('/messages')) {
      offsets.add(int.parse(request.uri.queryParameters['offset'] ?? '0'));
      final hold = next;
      next = null;
      final offset = int.parse(request.uri.queryParameters['offset'] ?? '0');
      final limit = int.parse(request.uri.queryParameters['limit'] ?? '50');
      final end = (rows.length - offset).clamp(0, rows.length);
      final start = (end - limit).clamp(0, end);
      final captured = jsonEncode({'data': rows.sublist(start, end)});
      if (hold != null) {
        hold.entered.complete();
        await hold.gate.future;
        request.response.statusCode = hold.status;
      } else if (failNext) {
        failNext = false;
        request.response.statusCode = 503;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(captured);
      await request.response.close();
      hold?.delivered.complete();
      return;
    }
    return super.handle(request);
  }
}

class _PhysicalApi extends ApiClient {
  _PhysicalApi(SavedConnection c)
    : super(baseUrl: c.baseUrl, apiKey: 'fixture');
  int started = 0;
  int completed = 0;
  final successfulHistories = <List<Map<String, dynamic>>>[];
  @override
  Future<List<Map<String, dynamic>>> getMessages(
    String sessionId, {
    int? limit,
    int offset = 0,
    bool latest = false,
  }) {
    started++;
    final f = super.getMessages(
      sessionId,
      limit: limit,
      offset: offset,
      latest: latest,
    );
    f.then<void>(
      (rows) {
        successfulHistories.add(rows);
        completed++;
      },
      onError: (Object _) {
        completed++;
      },
    );
    return f;
  }
}
