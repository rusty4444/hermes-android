import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_presentation_state.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'chat_draft_lifecycle_test.dart' as fixture;

class PrewireRemote extends fixture.Remote {
  @override
  Future<void> submit({
    required String sessionId,
    required String text,
    required StreamCallback onEvent,
    required void Function() onSent,
  }) {
    submissions++;
    return rpc.future;
  }
}

String keyFor(
  String connection,
  String id, [
  String prefix = 'composer_draft',
]) =>
    'flutter.$prefix.${base64Url.encode(utf8.encode('$connection\u0000$id')).replaceAll('=', '')}';

class ControlledStore extends InMemorySharedPreferencesStore {
  ControlledStore(super.data) : super.withData();
  String? rejectKey;
  String? holdKey;
  final started = Completer<void>();
  final release = Completer<bool>();
  final writes = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add(key);
    if (key == rejectKey) return false;
    if (key == holdKey) {
      holdKey = null;
      started.complete();
      if (!await release.future) return false;
    }
    return super.setValue(valueType, key, value);
  }
}

Future<String?> read(String id, {String connection = 'connection'}) =>
    ComposerDraftStore.read(connectionId: connection, sessionId: id);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'verbose_mode': false}));

  for (final latest in [null, 'canonical edit', '']) {
    for (final sibling in [false, true]) {
      testWidgets(
        'completed empty composer adopts receipt migration without reclaiming $latest sibling=$sibling',
        (tester) async {
          final seed = GatewayTurnApplicationController();
          final remote = fixture.Remote();
          final seedSession = seed.normalSessionFor(
            fixture.connection,
            submit: remote.submit,
          );
          await seedSession.ready;
          await ComposerDraftStore.save(
            connectionId: fixture.connection.id,
            sessionId: 'local',
            text: 'local next instruction',
          );
          await NormalGatewayPendingStore().put(
            NormalGatewayPendingMarker(
              scope: seedSession.scope,
              localSessionId: 'local',
              storedSessionId: 'stored',
              turnId: 'emitted-before-restart',
              rowFloor: 0,
              phase: 'emitted',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
          await seed.close();
          final prefs = await SharedPreferences.getInstance();
          final receiptRead = Completer<SharedPreferences>();
          final barrier = NormalGatewayPendingStore(
            preferences: () => receiptRead.future,
          ).load('barrier-only');
          final controller = GatewayTurnApplicationController();
          addTearDown(controller.close);
          await fixture.open(tester, controller, remote, id: 'stored');
          final oldComposer = tester
              .widget<TextField>(find.byType(TextField))
              .controller!;
          expect(oldComposer.text, '');
          // Initial empty hydration has drained; receipt restoration is still
          // deliberately blocked on its separate write-ahead queue.
          expect(
            await read('stored', connection: fixture.connection.id),
            isNull,
          );
          if (sibling) {
            await fixture.open(
              tester,
              controller,
              remote,
              id: 'stored',
              push: true,
            );
          }
          if (latest != null) {
            await tester.enterText(
              find.byType(TextField),
              'explicit intermediate edit',
            );
            await tester.enterText(find.byType(TextField), latest);
          }
          receiptRead.complete(prefs);
          await barrier;
          await controller.normalSessionFor(fixture.connection).ready;
          for (var i = 0; i < 8; i++) {
            await tester.pump();
          }
          final expected = latest ?? 'local next instruction';
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            expected,
          );
          if (sibling) expect(oldComposer.text, '');
          final registry = controller.presentationFor(fixture.connection);
          expect(
            identical(registry.chatFor('local'), registry.chatFor('stored')),
            isTrue,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await controller.close();
          await prefs.reload();
          for (final id in ['local', 'stored']) {
            expect(
              await read(id, connection: fixture.connection.id),
              expected.isEmpty ? isNull : expected,
            );
          }
          expect(remote.submissions, 0);
        },
      );
    }
  }

  for (final latest in ['Newer canonical instruction', '']) {
    testWidgets(
      'real routes: local prewire rejection cannot replace B intent "$latest"',
      (tester) async {
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final remote = PrewireRemote();
        await fixture.open(tester, controller, remote, draft: true);
        await tester.enterText(find.byType(TextField), 'Rejected old prompt');
        await tester.tap(find.byTooltip('Send'));
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }
        expect(remote.submissions, 1);
        await fixture.open(
          tester,
          controller,
          remote,
          id: 'stored',
          push: true,
        );
        expect(find.byType(TextField, skipOffstage: false), findsNWidgets(2));
        await tester.enterText(find.byType(TextField), 'intermediate new edit');
        await tester.enterText(find.byType(TextField), latest);
        Navigator.of(tester.element(find.byType(TextField))).pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        remote.rpc.completeError(StateError('prewire rejection'));
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final expected = latest.isEmpty ? isNull : latest;
        expect(
          await read('stored', connection: fixture.connection.id),
          expected,
        );
        expect(
          await read('local', connection: fixture.connection.id),
          expected,
        );
        await fixture.open(tester, controller, remote, id: 'stored');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          latest,
        );
        expect(remote.submissions, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }

  testWidgets('real routes: held B hydration does not reclaim A explicit edit', (
    tester,
  ) async {
    final controller = GatewayTurnApplicationController();
    addTearDown(controller.close);
    final remote = fixture.Remote();
    await fixture.open(tester, controller, remote, id: 'stored');
    final oldControl = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    final held = Completer<String?>();
    await fixture.open(
      tester,
      controller,
      remote,
      id: 'stored',
      push: true,
      reader: ({required connectionId, required sessionId}) => held.future,
    );
    // Explicit input delivered to the still-mounted A writer, not its save API.
    oldControl.text = 'A explicit latest edit';
    held.complete('B obsolete hydration');
    await tester.pump();
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(
      await read('stored', connection: fixture.connection.id),
      'A explicit latest edit',
    );
    expect(remote.submissions, 0);
  });

  testWidgets(
    'canonical cold-open joins a local-only durable draft from pending receipt',
    (tester) async {
      final remote = fixture.Remote();
      final seed = GatewayTurnApplicationController();
      final session = seed.normalSessionFor(
        fixture.connection,
        submit: remote.submit,
      );
      await session.ready;
      await ComposerDraftStore.save(
        connectionId: fixture.connection.id,
        sessionId: 'local',
        text: 'Next instruction before process loss',
      );
      await NormalGatewayPendingStore().put(
        NormalGatewayPendingMarker(
          scope: session.scope,
          localSessionId: 'local',
          storedSessionId: 'stored',
          turnId: 'already-emitted',
          rowFloor: 0,
          phase: 'emitted',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await seed.close();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      await fixture.open(tester, controller, remote, id: 'stored');
      await controller.normalSessionFor(fixture.connection).ready;
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      final registry = controller.presentationFor(fixture.connection);
      final visible = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      debugPrint(
        'canonical cold-open visible="$visible" local=${await read('local', connection: fixture.connection.id)} stored=${await read('stored', connection: fixture.connection.id)} samePresentation=${identical(registry.chatFor('local'), registry.chatFor('stored'))}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.close();
      expect(remote.submissions, 0);
      expect(visible, 'Next instruction before process loss');
      expect(
        await read('stored', connection: fixture.connection.id),
        'Next instruction before process loss',
      );
    },
  );

  testWidgets(
    'receipt restoration before canonical mounting migrates the same draft',
    (tester) async {
      final remote = fixture.Remote();
      final seed = GatewayTurnApplicationController();
      final seedSession = seed.normalSessionFor(
        fixture.connection,
        submit: remote.submit,
      );
      await seedSession.ready;
      await ComposerDraftStore.save(
        connectionId: fixture.connection.id,
        sessionId: 'local',
        text: 'Next instruction before process loss',
      );
      await NormalGatewayPendingStore().put(
        NormalGatewayPendingMarker(
          scope: seedSession.scope,
          localSessionId: 'local',
          storedSessionId: 'stored',
          turnId: 'already-emitted',
          rowFloor: 0,
          phase: 'emitted',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await seed.close();
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      await controller
          .normalSessionFor(
            fixture.connection,
            submit: remote.submit,
            resume:
                ({required localSessionId, required storedSessionId}) async =>
                    const ResumedGatewaySession(
                      runtimeSessionId: 'runtime',
                      running: true,
                    ),
          )
          .ready;
      await fixture.open(tester, controller, remote, id: 'stored');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Next instruction before process loss',
      );
      expect(
        await read('stored', connection: fixture.connection.id),
        'Next instruction before process loss',
      );
      expect(remote.submissions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.close();
    },
  );

  for (final point in ['composer_draft', 'composer_draft_alias']) {
    for (final revoke in [false, true]) {
      test(
        'held $point migration and scope ${revoke ? 'revoke' : 'replacement'} preserve new canonical clear',
        () async {
          final c = fixture.connection;
          await ComposerDraftStore.save(
            connectionId: c.id,
            sessionId: 'local',
            text: 'old local',
          );
          final original = SharedPreferencesStorePlatform.instance;
          final store = ControlledStore(await original.getAll())
            ..holdKey = keyFor(
              c.id,
              point == 'composer_draft' ? 'stored' : 'local',
              point,
            );
          SharedPreferencesStorePlatform.instance = store;
          addTearDown(() => SharedPreferencesStorePlatform.instance = original);
          final controller = GatewayTurnApplicationController();
          addTearDown(controller.close);
          final oldRegistry = controller.presentationFor(c);
          final old = oldRegistry.chatFor('local').openWriter();
          oldRegistry.bind('local', 'stored');
          await store.started.future;
          if (revoke) controller.revokeConnection(c.id);
          final replacement = controller.presentationFor(
            SavedConnection(
              id: c.id,
              label: c.label,
              host: c.host,
              port: c.port,
              apiKey: 'new-fixture-credential',
            ),
          );
          final current = replacement.chatFor('stored').openWriter()..edit('');
          final newWrite = current.flush();
          store.release.complete(true);
          await newWrite;
          old.edit('must not reclaim');
          await old.save('must not save');
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          expect(old.isCurrent, isFalse);
          expect(await read('stored', connection: c.id), isNull);
          expect(current.isCurrent, isTrue);
        },
      );
    }
  }

  test(
    'failed alias publication can be retried in the same cache and survive restart',
    () async {
      await ComposerDraftStore.save(
        connectionId: 'connection',
        sessionId: 'local',
        text: 'legacy',
      );
      final original = SharedPreferencesStorePlatform.instance;
      final store = ControlledStore(await original.getAll())
        ..rejectKey = keyFor('connection', 'local', 'composer_draft_alias');
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      await ComposerDraftStore.bind(
        connectionId: 'connection',
        localSessionId: 'local',
        storedSessionId: 'stored',
      );
      store.rejectKey = null;
      await ComposerDraftStore.bind(
        connectionId: 'connection',
        localSessionId: 'local',
        storedSessionId: 'stored',
      );
      await ComposerDraftStore.save(
        connectionId: 'connection',
        sessionId: 'local',
        text: 'newer after retry',
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      debugPrint(
        'alias retry durable local=${await read('local')} stored=${await read('stored')} physicalAlias=${(await store.getAll())[keyFor('connection', 'local', 'composer_draft_alias')]}',
      );
      expect(await read('local'), 'newer after retry');
      expect(await read('stored'), 'newer after retry');
    },
  );

  for (final revoke in [false, true]) {
    test(
      'scope ${revoke ? 'revoke' : 'replacement'} while old physical write held preserves replacement edit',
      () async {
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final c = fixture.connection;
        final oldRegistry = controller.presentationFor(c);
        final old = oldRegistry.chatFor('stored').openWriter()
          ..edit('old scope');
        final original = SharedPreferencesStorePlatform.instance;
        final store = ControlledStore(await original.getAll())
          ..holdKey = keyFor(c.id, 'stored');
        SharedPreferencesStorePlatform.instance = store;
        addTearDown(() => SharedPreferencesStorePlatform.instance = original);
        final oldWrite = old.flush();
        await store.started.future;
        if (revoke) controller.revokeConnection(c.id);
        final replacement = controller.presentationFor(
          SavedConnection(
            id: c.id,
            label: c.label,
            host: c.host,
            port: c.port,
            apiKey: 'new-test-credential',
          ),
        );
        final current = replacement.chatFor('stored').openWriter()
          ..edit('replacement authority');
        final newWrite = current.flush();
        old.edit('must never reclaim');
        store.release.complete(true);
        await Future.wait([oldWrite, newWrite, old.close()]);
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(old.isCurrent, isFalse);
        expect(await read('stored', connection: c.id), 'replacement authority');
        replacement.close();
      },
    );
  }

  for (final latest in ['canonical newest', '']) {
    test('held migration serializes with canonical edit "$latest"', () async {
      await ComposerDraftStore.save(
        connectionId: 'connection',
        sessionId: 'local',
        text: 'legacy',
      );
      final original = SharedPreferencesStorePlatform.instance;
      final store = ControlledStore(await original.getAll())
        ..holdKey = keyFor('connection', 'stored');
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      final registry = ChatPresentationRegistry('connection');
      final local = registry.chatFor('local').openWriter();
      registry.bind('local', 'stored');
      await store.started.future;
      final current = registry.chatFor('stored').openWriter()..edit(latest);
      final save = current.flush();
      store.release.complete(true);
      await save;
      await local.close();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(await read('local'), latest.isEmpty ? isNull : latest);
      expect(await read('stored'), latest.isEmpty ? isNull : latest);
      registry.close();
    });
  }
}
