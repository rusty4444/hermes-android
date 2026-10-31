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
import 'package:hermes_android/core/utils/chat_display_items.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'normal_gateway_alias_handoff_wire_test.dart'
    show BindingServer, widgetUntil;
import 'support/fake_voice_composer_adapter.dart';
import 'support/unreconciled_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? old;
  setUp(() {
    SharedPreferences.setMockInitialValues({'verbose_mode': true});
    old = HttpOverrides.current;
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          (_) async => null,
        );
  });
  tearDown(() {
    HttpOverrides.global = old;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/image_picker'),
          null,
        );
  });
  for (final width in [400.0, 1000.0]) {
    for (final shape in ['empty', 'lower', 'unidentified']) {
      for (final staleError in [false, true]) {
        testWidgets(
          'CORE78 failed receipt survives physically superseded Refresh $shape staleError=$staleError width=$width',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 2200));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final wire = (await tester.runAsync(_Server.start))!;
            wire.creates = 1;
            wire.rows.add({
              'id': 37,
              'role': 'assistant',
              'content': 'Loaded canonical base',
            });
            final controller = GatewayTurnApplicationController();
            final routeApi = _PhysicalApi(wire.connection);
            final api = ApiClient(
              baseUrl: wire.connection.baseUrl,
              apiKey: wire.connection.apiKey,
            );
            try {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: ChatScreen(
                    connection: wire.connection,
                    testApiClient: routeApi,
                    session: Session(
                      id: 'stored',
                      title: 'Physical freshness',
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
              final owner = controller
                  .normalSessionFor(wire.connection)
                  .findChat('stored')!;
              await widgetUntil(
                tester,
                () => owner.snapshot.historyRows.isNotEmpty,
              );
              await tester.enterText(
                find.byType(TextField),
                'Failed receipt prompt',
              );
              await tester.tap(find.byTooltip('Send'));
              await widgetUntil(tester, () => wire.prompts.length == 1);
              wire.event('message.start', {}, turnId: 'wire-1');
              wire.event('message.delta', {
                'text': 'Retained failed output',
              }, turnId: 'wire-1');
              wire.running = false;
              wire.event('turn.error', {
                'message': 'fixture failure',
              }, turnId: 'wire-1');
              await widgetUntil(
                tester,
                () => owner.snapshot.phase == NormalGatewayTurnPhase.failed,
              );
              await tester.pumpAndSettle();
              await tester.pump(const Duration(seconds: 8));
              await tester.pumpAndSettle();
              // Establish completion of all settlement reads by a successful
              // independent physical observation; no token is minted at arrival.
              final baseline = owner.beginHistoryRead('stored');
              final rows = (await tester.runAsync(
                () => api.getMessages('stored', latest: true),
              ))!;
              expect(owner.observeHistory(rows, read: baseline), isTrue);
              final state = tester.state(find.byType(ChatScreen));
              final scroll = tester
                  .widget<ListView>(find.byType(ListView).first)
                  .controller;
              final ids = owner.snapshot.displayRows
                  .map((r) => r['_normal_projection_id'])
                  .toList();
              wire.hold = _Hold(staleError ? 503 : 200);
              wire.rows.add({
                'id': 99,
                'role': 'assistant',
                'content': 'Never accepted stale canonical',
              });
              await tester.tap(find.byTooltip('Chat actions').hitTestable());
              await tester.pumpAndSettle();
              await tester.tap(find.text('Refresh').hitTestable());
              await widgetUntil(tester, () => wire.hold!.entered.isCompleted);
              final latest = switch (shape) {
                'empty' => <Map<String, dynamic>>[],
                'lower' => [
                  {
                    'id': 1,
                    'role': 'assistant',
                    'content': 'New compressed canonical',
                  },
                ],
                _ => [
                  {'role': 'assistant', 'content': 'New anonymous canonical'},
                ],
              };
              wire.rows
                ..clear()
                ..addAll(latest);
              final token = owner.beginHistoryRead('stored');
              final fresh = (await tester.runAsync(
                () => api.getMessages('stored', latest: true),
              ))!;
              expect(owner.observeHistory(fresh, read: token), isTrue);
              wire.hold!.gate.complete();
              await widgetUntil(
                tester,
                () =>
                    wire.hold!.delivered.isCompleted &&
                    routeApi.started == routeApi.completed,
              );
              await tester.pumpAndSettle();
              final position = scroll!;
              position.jumpTo(0);
              await tester.pump();
              expect(owner.snapshot.historyRows, latest);
              expect(
                owner.snapshot.displayRows.map(
                  (r) => r['_normal_projection_id'],
                ),
                ids,
              );
              expect(tester.state(find.byType(ChatScreen)), same(state));
              expect(
                tester.widget<ListView>(find.byType(ListView).first).controller,
                same(scroll),
              );
              expect(find.text('Never accepted stale canonical'), findsNothing);
              expect(
                inChatSource(
                  find.text('Loaded canonical base'),
                  ChatDisplaySource.canonical,
                ),
                findsOneWidget,
              );
              expect(
                inChatSource(
                  find.text('Retained failed output'),
                  ChatDisplaySource.received,
                ),
                findsOneWidget,
              );
              if (shape != 'empty') {
                expect(
                  inChatSource(
                    find.text(
                      shape == 'lower'
                          ? 'New compressed canonical'
                          : 'New anonymous canonical',
                    ),
                    ChatDisplaySource.canonical,
                  ),
                  findsOneWidget,
                );
              }
              expect(find.byType(MaterialBanner), findsNothing);
              expect(find.byType(LinearProgressIndicator), findsNothing);
              expect(wire.prompts, hasLength(1));
              expect(tester.takeException(), isNull);
            } finally {
              if (wire.hold != null && !wire.hold!.gate.isCompleted) {
                wire.hold!.gate.complete();
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.runAsync(() async {
                api.close();
                routeApi.close();
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
}

class _Hold {
  _Hold(this.status);
  final int status;
  final entered = Completer<void>();
  final gate = Completer<void>();
  final delivered = Completer<void>();
}

class _PhysicalApi extends ApiClient {
  _PhysicalApi(SavedConnection c) : super(baseUrl: c.baseUrl, apiKey: c.apiKey);
  int started = 0;
  int completed = 0;
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
    f.then((_) => completed++, onError: (Object _) => completed++);
    return f;
  }
}

class _Server extends BindingServer {
  _Server(super.server);
  _Hold? hold;
  static Future<_Server> start() async {
    final s = _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s.server.listen(s.handle);
    return s;
  }

  @override
  Future<void> handle(HttpRequest request) async {
    final current = hold;
    if (request.uri.path.endsWith('/messages') &&
        current != null &&
        !current.entered.isCompleted) {
      final captured = jsonEncode({'data': rows});
      current.entered.complete();
      await current.gate.future;
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = current.status;
      request.response.write(captured);
      await request.response.close();
      current.delivered.complete();
      return;
    }
    return super.handle(request);
  }
}
