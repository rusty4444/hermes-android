import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'chat_draft_lifecycle_test.dart' as fixture;
import 'support/draft_read_outage_preferences.dart';
import 'support/fifo_shared_preferences.dart' show draftPreferenceKey;

String _key(String id) =>
    draftPreferenceKey(id, connection: fixture.connection.id);
String _marker(String id) => _key(
  id,
).replaceFirst('flutter.composer_draft.', 'flutter.composer_draft_written.');
String _alias(String id) => _key(
  id,
).replaceFirst('flutter.composer_draft.', 'flutter.composer_draft_alias.');

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 24; i++) {
    await tester.pump();
  }
}

class _Routes {
  _Routes(this.tester) {
    SharedPreferences.setMockInitialValues({'verbose_mode': false});
    addTearDown(controller.close);
  }

  final WidgetTester tester;
  final controller = GatewayTurnApplicationController();
  final remote = fixture.Remote();
  late DraftReadOutagePreferences platform;

  String get visible =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  Future<void> open([String id = 'local']) async {
    // The production reader is intentional: the outage is at physical getAll.
    await fixture.open(
      tester,
      controller,
      remote,
      id: id,
      draft: id == 'local',
    );
    await _drain(tester);
  }

  Future<void> edit(String text) async {
    // Ensure an explicit empty edit is a real change, not an untouched field.
    await tester.enterText(find.byType(TextField), 'explicit precursor');
    await tester.enterText(find.byType(TextField), text);
    expect(visible, text);
  }

  Future<void> closeRoute() async {
    final route = tester.state(find.byType(ChatScreen));
    await tester.pumpWidget(const SizedBox.shrink());
    await _drain(tester);
    expect(route.mounted, isFalse);
  }

  Future<void> seed(String text, [String id = 'local']) async {
    await open(id);
    await edit(text);
    await closeRoute();
  }

  Future<void> installOutagePlatform() async {
    final original = SharedPreferencesStorePlatform.instance;
    platform = DraftReadOutagePreferences(await original.getAll());
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() async {
      if (!platform.releaseRead.isCompleted) platform.releaseRead.complete();
      await platform.tail;
      SharedPreferencesStorePlatform.instance = original;
    });
  }

  Future<void> expectPhysical(String id, String text) async {
    final disk = await platform.disk();
    expect(disk[_key(id)], text.isEmpty ? null : text);
    expect(disk[_marker(id)], isTrue);
  }

  Future<void> bind(String expected) async {
    final session = controller.normalSessionFor(fixture.connection);
    session.findChat('local')!.bindStoredSession('stored');
    await _drain(tester);
    expect(
      identical(session.findChat('local'), session.findChat('stored')),
      isTrue,
    );
    final presentation = controller.presentationFor(fixture.connection);
    expect(
      identical(presentation.chatFor('local'), presentation.chatFor('stored')),
      isTrue,
    );
    expect(visible, expected);
    await expectPhysical('stored', expected);
    expect((await platform.disk())[_alias('local')], 'stored');
  }

  Future<String> expectRestart(String expected) async {
    final physical = await platform.disk();
    await controller.close();
    await _drain(tester);
    platform.expectDrainedFifo();
    SharedPreferences.setMockInitialValues({
      for (final entry in physical.entries)
        entry.key.replaceFirst('flutter.', ''): entry.value,
    });
    final restarted = GatewayTurnApplicationController();
    addTearDown(restarted.close);
    await fixture.open(tester, restarted, remote, id: 'stored');
    await _drain(tester);
    final restartedVisible = visible;
    expect(restartedVisible, expected);
    await closeRoute();
    await restarted.close();
    await _drain(tester);
    expect(remote.submissions, 0);
    expect(tester.takeException(), isNull);
    return restartedVisible;
  }

  Future<String> expectRecoveryAndBinding(String expected) async {
    await open();
    expect(visible, expected);
    await bind(expected);
    await closeRoute();
    await expectPhysical('stored', expected);
    return expectRestart(expected);
  }
}

void main() {
  for (final failRead in [false, true]) {
    for (final saved in ['last successfully saved draft', '']) {
      testWidgets(
        'retained untouched close preserves physical intent through hydration outage: '
        'failRead=$failRead saved="$saved"',
        (tester) async {
          final routes = _Routes(tester);
          await routes.seed(saved);
          await routes.installOutagePlatform();
          await routes.expectPhysical('local', saved);
          routes.platform.failNextRead = failRead;
          await routes.open();
          final visibleDuringRead = routes.visible;
          expect(visibleDuringRead, failRead ? '' : saved);
          expect(routes.platform.failures, failRead ? 1 : 0);
          // Background checkpoints and disposal are not fresh explicit edits.
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await _drain(tester);
          await routes.expectPhysical('local', saved);
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
          await _drain(tester);
          await routes.closeRoute();
          await routes.expectPhysical('local', saved);
          if (failRead) expect(routes.platform.draftMutations, isEmpty);
          final restartedVisible = await routes.expectRecoveryAndBinding(saved);
          // ignore: avoid_print
          print(
            jsonEncode({
              'boundary': 'retainedHydrationOutage',
              'failRead': failRead,
              'saved': saved,
              'observed': {
                'visibleDuringFailure': visibleDuringRead,
                'restartedVisible': restartedVisible,
              },
              'fifoTrace': routes.platform.trace,
            }),
          );
        },
      );
    }
  }

  for (final latest in ['new explicit text after failed hydration', '']) {
    testWidgets(
      'explicit text/clear after failed hydration remains authoritative: "$latest"',
      (tester) async {
        final routes = _Routes(tester);
        await routes.seed('previous saved draft');
        await routes.installOutagePlatform();
        routes.platform.failNextRead = true;
        await routes.open();
        expect(routes.visible, '');
        expect(routes.platform.failures, 1);
        await routes.expectPhysical('local', 'previous saved draft');
        await routes.edit(latest);
        await routes.closeRoute();
        await routes.expectPhysical('local', latest);
        await routes.expectRecoveryAndBinding(latest);
      },
    );
  }

  for (final latest in ['replacement intent after held failed read', '']) {
    testWidgets(
      'held failed hydration cannot borrow revoked root or replacement lease: "$latest"',
      (tester) async {
        final routes = _Routes(tester);
        await routes.seed('prior saved draft');
        final revokedRegistry = routes.controller.presentationFor(
          fixture.connection,
        );
        await routes.installOutagePlatform();
        routes.platform
          ..holdNextRead = true
          ..failNextRead = true;
        await routes.open();
        expect(routes.platform.readEntered.isCompleted, isTrue);
        expect(routes.visible, '');
        routes.controller.revokeConnection(fixture.connection.id);
        expect(revokedRegistry.isClosed, isTrue);
        await routes.closeRoute();
        await routes.open();
        await routes.edit(latest);
        final replacement = routes.controller.presentationFor(
          fixture.connection,
        );
        expect(identical(revokedRegistry, replacement), isFalse);
        await routes.closeRoute();
        routes.platform.releaseRead.complete();
        await _drain(tester);
        expect(routes.platform.failures, 1);
        await routes.expectPhysical('local', latest);
        await routes.expectRecoveryAndBinding(latest);
      },
    );
  }

  for (final localNewer in [false, true]) {
    for (final latest in ['newest alias intent despite read outage', '']) {
      testWidgets(
        'alias convergence retains explicit chronology after failed hydration: '
        'localNewer=$localNewer latest="$latest"',
        (tester) async {
          final routes = _Routes(tester);
          if (localNewer) {
            await routes.seed('older canonical draft', 'stored');
            await routes.seed(latest);
          } else {
            await routes.seed('older local draft');
            await routes.seed(latest, 'stored');
          }
          await routes.installOutagePlatform();
          // A stored route first repeats its normal-owner binding baseline;
          // fail its subsequent composer hydration, not that earlier read.
          routes.platform.failingReads.add(localNewer ? 1 : 2);
          await routes.open(localNewer ? 'local' : 'stored');
          expect(routes.visible, '');
          expect(routes.platform.failures, 1);
          // No repairing read or explicit input before the actual owner binding.
          await routes.bind(latest);
          await routes.closeRoute();
          await routes.expectPhysical('stored', latest);
          await routes.expectRestart(latest);
        },
      );
    }
  }

  for (final failRead in [false, true]) {
    testWidgets(
      'normal-owner alias baseline outage retains source and recovers: failRead=$failRead',
      (tester) async {
        final routes = _Routes(tester);
        await routes.seed('saved before alias');
        await routes.open();
        await routes.installOutagePlatform();
        routes.platform.failNextRead = failRead;
        await routes.bind('saved before alias');
        expect(routes.platform.failures, failRead ? 1 : 0);
        await routes.expectPhysical('local', 'saved before alias');
        await routes.closeRoute();
        await routes.expectPhysical('stored', 'saved before alias');
        await routes.expectRestart('saved before alias');
      },
    );
  }

  for (final saved in ['saved across hydration and alias outages', '']) {
    testWidgets(
      'unavailable hydration plus both alias baselines cannot manufacture source clear: "$saved"',
      (tester) async {
        final routes = _Routes(tester);
        await routes.seed(saved);
        await routes.installOutagePlatform();
        routes.platform.failNextRead = true;
        await routes.open();
        expect(routes.visible, '');
        expect(routes.platform.failures, 1);
        // Normal owner and presentation each attempt the physical migration.
        routes.platform.failingReads.addAll({2, 3});
        routes.controller
            .normalSessionFor(fixture.connection)
            .findChat('local')!
            .bindStoredSession('stored');
        await _drain(tester);
        expect(routes.platform.failures, 3);
        await routes.expectPhysical('local', saved);
        final unavailableAlias = await routes.platform.disk();
        expect(unavailableAlias[_alias('local')], isNull);
        expect(unavailableAlias[_key('stored')], isNull);
        expect(unavailableAlias[_marker('stored')], isNull);
        // A recovered hydration must follow this writer's physical alias, not
        // read an uncommitted logical destination as authoritative absence.
        final visibleAfterAliasFailure = routes.visible;
        await routes.closeRoute();
        await routes.expectPhysical('local', saved);
        expect(visibleAfterAliasFailure, saved);
        // Opening by stored ID repeats the normal owner's physical binding;
        // bindStoredSession with its already-known ID intentionally does not.
        await routes.open('stored');
        expect(routes.visible, saved);
        await routes.bind(saved);
        await routes.closeRoute();
        await routes.expectRestart(saved);
      },
    );
  }

  for (final asynchronous in [false, true]) {
    testWidgets(
      'legacy reader failure is contained without empty authority: async=$asynchronous',
      (tester) async {
        final routes = _Routes(tester);
        await routes.seed('saved before legacy reader failure');
        await routes.installOutagePlatform();
        await fixture.open(
          tester,
          routes.controller,
          routes.remote,
          draft: true,
          reader: ({required connectionId, required sessionId}) {
            final error = StateError('Fixture private legacy reader detail');
            if (asynchronous) return Future<String?>.error(error);
            throw error;
          },
        );
        await _drain(tester);
        expect(routes.visible, '');
        expect(tester.takeException(), isNull);
        await routes.closeRoute();
        expect(routes.platform.draftMutations, isEmpty);
        await routes.expectPhysical(
          'local',
          'saved before legacy reader failure',
        );
        await routes.expectRecoveryAndBinding(
          'saved before legacy reader failure',
        );
      },
    );
  }
}
