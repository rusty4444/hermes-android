import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/operational_activity_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'chat_draft_lifecycle_test.dart' as fixture;
import 'support/fifo_shared_preferences.dart';

String draftKey(String id) =>
    draftPreferenceKey(id, connection: fixture.connection.id);

Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump();
  }
}

void main() {
  for (final racing in [false, true]) {
    for (final latest in ['newest route draft', '']) {
      testWidgets(
        'real ChatScreen retains draft through FIFO Activity reload: racing=$racing latest="$latest"',
        (tester) async {
          SharedPreferences.setMockInitialValues({'verbose_mode': false});
          final controller = GatewayTurnApplicationController();
          addTearDown(controller.close);
          final remote = fixture.Remote();
          await fixture.open(tester, controller, remote, draft: true);
          await tester.enterText(
            find.byType(TextField),
            'obsolete instruction',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await drain(tester);
          await fixture.open(tester, controller, remote, draft: true);
          await drain(tester);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'obsolete instruction',
          );
          final retainedState = tester.state(find.byType(ChatScreen));
          final original = SharedPreferencesStorePlatform.instance;
          final platform = FifoPreferences(await original.getAll())
            ..watchedKey = draftKey('local');
          SharedPreferencesStorePlatform.instance = platform;
          addTearDown(() async {
            if (!platform.releaseRead.isCompleted) {
              platform.releaseRead.complete();
            }
            await platform.tail;
            SharedPreferencesStorePlatform.instance = original;
          });
          Future<List<OperationalActivityRecord>>? reading;
          if (racing) {
            platform.holdRead = true;
            reading = OperationalActivityStore().load('another-chat');
            await tester.pump();
            expect(platform.readEntered.isCompleted, isTrue);
          }
          await tester.enterText(find.byType(TextField), latest);
          await tester.pumpWidget(const SizedBox.shrink());
          await drain(tester);
          expect(retainedState.mounted, isFalse);
          expect(platform.writeQueued.isCompleted, isTrue);
          if (racing) {
            platform.releaseRead.complete();
            await drain(tester);
            await reading;
          }
          await drain(tester);
          expect(
            (await platform.disk())[draftKey('local')],
            latest.isEmpty ? null : latest,
            reason: 'Real route disposal physically saved the new draft/clear.',
          );
          await fixture.open(tester, controller, remote, draft: true);
          await drain(tester);
          final reopened = tester
              .widget<TextField>(find.byType(TextField))
              .controller!
              .text;
          // Use the actual normal-owner binding, not just the low-level store.
          controller
              .normalSessionFor(fixture.connection)
              .findChat('local')!
              .bindStoredSession('stored');
          await drain(tester);
          await ComposerDraftStore.read(
            connectionId: fixture.connection.id,
            sessionId: 'stored',
          );
          await drain(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await drain(tester);
          final canonical = (await platform.disk())[draftKey('stored')];
          await controller.close();
          await drain(tester);
          expect(remote.submissions, 0);
          final observed = {
            'visibleReopenedComposer': reopened,
            'physicalCanonical': canonical,
          };
          platform.expectDrainedFifo();
          // Machine-readable FIFO evidence for the regression runner.
          // ignore: avoid_print
          print(
            jsonEncode({
              'racing': racing,
              'latest': latest,
              'observed': observed,
              'fifoTrace': platform.trace,
            }),
          );
          expect(observed, {
            'visibleReopenedComposer': latest,
            'physicalCanonical': latest.isEmpty ? null : latest,
          });
        },
      );
    }
  }
}
