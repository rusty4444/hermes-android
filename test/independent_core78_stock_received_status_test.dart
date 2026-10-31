import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';
import 'support/unreconciled_policy.dart';

// Independent CORE SPEC schedules; real stock-shaped HTTP/WS + production
// Send/Refresh/export/ChatScreen, no injected owner event or private callback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? old;
  final exports = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    old = HttpOverrides.current;
    HttpOverrides.global = null;
    exports.clear();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        if (call.method == 'share') {
          exports.add((call.arguments as Map)['text'] as String);
        }
        return 'success';
      },
    );
  });
  tearDown(() {
    HttpOverrides.global = old;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      null,
    );
  });
  for (final width in [400.0, 1000.0]) {
    for (final check in ['canonical-controls', 'known-status']) {
      testWidgets(
        'CORE78-STOCK $check failed partial then successful identical-body receipt at $width',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 2600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final wire = (await tester.runAsync(_FailureServer.start))!;
          wire.creates = 1;
          wire.rows.add({
            'id': 1,
            'role': 'assistant',
            'content': 'Baseline context',
          });
          final controller = GatewayTurnApplicationController();
          final normal = controller.normalSessionFor(wire.connection);
          try {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: ChatScreen(
                  connection: wire.connection,
                  session: Session(
                    id: 'stored',
                    title: 'Independent receipts',
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
            final owner = normal.findChat('stored')!;
            await widgetUntil(
              tester,
              () =>
                  owner.snapshot.historyRows.isNotEmpty &&
                  find.byTooltip('Send').evaluate().isNotEmpty,
            );
            final state = tester.state(find.byType(ChatScreen));
            final scroll = tester
                .widget<ListView>(find.byType(ListView).first)
                .controller!;
            final composer = tester
                .widget<TextField>(find.byType(TextField))
                .controller!;
            await tester.enterText(
              find.byType(TextField),
              'First local prompt',
            );
            await tester.tap(find.byTooltip('Send'));
            await widgetUntil(tester, () => wire.prompts.length == 1);
            wire.event('message.start', {}, turnId: 'wire-1');
            wire.event('message.delta', {
              'text': 'Repeated received body',
            }, turnId: 'wire-1');
            wire.running = false;
            wire.failed = true;
            wire.event('message.complete', {
              'text': 'Repeated received body',
              'status': 'error',
              'error': 'Deterministic first-turn failure',
              'partial': true,
            });
            await widgetUntil(
              tester,
              () => owner.snapshot.phase == NormalGatewayTurnPhase.failed,
            );
            expect(
              owner.snapshot.error,
              contains('Deterministic first-turn failure'),
            );
            expect(wire.resumes, greaterThan(1));
            debugPrint(
              'CORE78-STOCK confirmed failure after physical resume; resumes=${wire.resumes} phase=${owner.snapshot.phase} error=${owner.snapshot.error}',
            );
            await tester.pumpAndSettle();
            await tester.pump(
              const Duration(seconds: 8),
            ); // expire only existing snackbar, not a race barrier
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField),
              'Second local prompt',
            );
            await tester.tap(find.byTooltip('Send'));
            await widgetUntil(tester, () => wire.prompts.length == 2);
            wire.finish('Repeated received body');
            await widgetUntil(
              tester,
              () => owner.snapshot.phase == NormalGatewayTurnPhase.completed,
            );
            await widgetUntil(
              tester,
              () => owner.snapshot.historyRows.any((r) => r['role'] == 'user'),
            );
            await tester.pump(const Duration(seconds: 1));
            scroll.jumpTo(0);
            await tester.pump();
            expect(tester.state(find.byType(ChatScreen)), same(state));
            expect(
              tester.widget<ListView>(find.byType(ListView).first).controller,
              same(scroll),
            );
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller,
              same(composer),
            );
            expect(
              owner.snapshot.displayRows.where(
                (r) =>
                    r['role'] == 'assistant' &&
                    r['content'] == 'Repeated received body',
              ),
              hasLength(2),
            );
            expect(
              inChatSource(
                find.text('Repeated received body'),
                ChatDisplaySource.received,
              ),
              findsNWidgets(2),
            );
            expect(
              inChatSource(
                find.text('Repeated received body'),
                ChatDisplaySource.canonical,
              ),
              findsOneWidget,
            );
            expect(wire.prompts.map((p) => p['text']), [
              'First local prompt',
              'Second local prompt',
            ]);
            await tester.tap(find.byTooltip('Chat actions').hitTestable());
            await tester.pumpAndSettle();
            await tester.tap(find.text('Export / share').hitTestable());
            await tester.pumpAndSettle();
            expect(exports, hasLength(1));
            final output = exports.single;
            expect(
              output,
              contains('Received output — match to saved history unconfirmed'),
            );
            expect(output.split('Repeated received body'), hasLength(4));
            final renderedText = tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
                .join('\n');
            debugPrint(
              'CORE78-STOCK observation width=$width check=$check phase=${owner.snapshot.phase} error=${owner.snapshot.error} rows=${owner.snapshot.displayRows} rendered=$renderedText export=$output',
            );
            if (check == 'known-status') {
              // Received text remains, but its known failure must remain attached
              // to that retained scope; an expired toast/latest success is not it.
              expect(
                renderedText,
                contains(
                  RegExp(r'failed|failure|interrupted', caseSensitive: false),
                ),
                reason:
                    'R must retain known failed status after the next successful turn; match-unconfirmed is persistence provenance, not lifecycle outcome',
              );
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(() async {
              await controller.close();
              await wire.close();
            });
            await tester.pump(const Duration(seconds: 16));
          }
        },
      );
    }
  }
}

// Stock ID-less terminal hint: known failure comes from a subsequent real
// session.resume response, not terminal self-correlation or an owner seam.
class _FailureServer extends BindingServer {
  _FailureServer(super.server);
  bool failed = false;
  static Future<_FailureServer> start() async {
    final s = _FailureServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    s.server.listen(s.handle);
    return s;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    if (request.uri.path != '/api/ws') return super.handle(request);
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'gateway.ready', 'payload': {}},
      }),
    );
    socket.listen((raw) {
      final frame = jsonDecode(raw as String) as Map;
      if (frame['method'] == null) return;
      final result = <String, dynamic>{'ok': true};
      if (frame['method'] == 'session.resume') {
        resumes++;
        result.addAll({
          'session_id': 'runtime',
          'stored_session_id': 'stored',
          'running': running,
          'status': failed
              ? 'error'
              : running
              ? 'running'
              : 'idle',
          if (failed)
            'inflight': {
              'status': 'error',
              'error': 'Deterministic first-turn failure',
            },
        });
      } else if (frame['method'] == 'prompt.submit') {
        prompts.add(Map<String, dynamic>.from(frame['params'] as Map));
        running = true;
        failed = false;
      }
      if (socket.readyState == WebSocket.open) {
        socket.add(
          jsonEncode({'jsonrpc': '2.0', 'id': frame['id'], 'result': result}),
        );
      }
    });
  }
}
