// Rehosts ROOT-ED8-1's real no-observer-fault schedule. These are permanent
// regressions derived from that probe, not fresh independent SPEC evidence.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/screens/chat_screen.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/composer_draft_store.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/notification_approval_authority.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:hermes_android/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_turn_journal_store.dart';
import 'support/mutation_observer_root_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides? previous;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'verbose_mode': true,
      BackgroundWorkPrefsStore.storageKey: true,
    });
    backgroundWorkEnabled.value = true;
    notificationPrefs.value = NotificationPrefs.defaults;
    pendingNotificationApprovals.value = const [];
    previous = HttpOverrides.current;
    HttpOverrides.global = null;
  });
  tearDown(() {
    HttpOverrides.global = previous;
    debugDefaultTargetPlatformOverride = null;
  });

  for (final replaceRoot in [false, true]) {
    testWidgets(
      'ROOT-ED8-1 same-value owner replacement completes retained cleanup; newer root=$replaceRoot',
      (tester) async {
        final f = MutationObserverRootFixture();
        GatewayTurnApplicationController? newerController;
        var closed = false;
        await f.initialize(tester);
        try {
          final root = tester.state<HermesAppState>(find.byType(HermesApp));
          final chat = tester.state(find.byType(ChatScreen));
          final screen = tester.widget<ChatScreen>(find.byType(ChatScreen));
          final field = find.byKey(const Key('chat-message-composer'));
          final composer = tester.widget<TextField>(field).controller!;
          final scroll = tester
              .widget<ListView>(
                find
                    .descendant(
                      of: find.byType(ChatScreen),
                      matching: find.byType(ListView),
                    )
                    .first,
              )
              .controller!;
          await tester.enterText(
            field,
            'Retained draft survives owner cleanup',
          );
          final oldOwner = f.controller.sessionFor(f.connection);
          final oldHandler = notificationResponseHandler;
          final oldOrigin = NotificationApprovalAuthority.origin(f.connection);
          final old = await f.queueAndPause(tester);
          final oldEpoch = ConnectionMutationBarrier.capture(f.connection.id);
          final mutation = f.manager.updateApiKey(
            f.connection.id,
            f.connection.apiKey,
          );
          expect(ConnectionMutationBarrier.isPending(f.connection.id), isTrue);
          expect(old.authority!.isCurrent, isFalse);
          expect(pendingNotificationApprovals.value, isEmpty);
          await mutation;
          final current = f.manager.getConnections().single;
          expect(current.apiKey, f.connection.apiKey);
          expect(ConnectionMutationBarrier.isPending(current.id), isFalse);
          expect(
            ConnectionMutationBarrier.isCurrent(current.id, oldEpoch),
            isFalse,
          );
          MutationObserverRootFixture.lifecycle(
            tester,
            AppLifecycleState.resumed,
          );
          await MutationObserverRootFixture.drain(tester);
          NotificationResponse response(Map<String, String> origin) =>
              NotificationResponse(
                actionId: 'reject',
                payload: jsonEncode({
                  'connectionId': current.id,
                  'sessionId': 'stored',
                  'requestId': 'approval-reused',
                  ...origin,
                }),
                notificationResponseType:
                    NotificationResponseType.selectedNotificationAction,
              );
          notificationResponseHandler!(response(oldOrigin));
          await MutationObserverRootFixture.drain(tester);
          expect(pendingNotificationApprovals.value, isEmpty);
          notificationResponseHandler!(
            response(NotificationApprovalAuthority.origin(current)),
          );
          await MutationObserverRootFixture.until(
            tester,
            () => pendingNotificationApprovals.value.length == 1,
          );
          final fresh = pendingNotificationApprovals.value.single;
          expect(fresh, isNot(same(old)));
          expect(fresh.choice, 'deny');
          expect(fresh.authority!.isCurrentFor(current), isTrue);
          expect(f.controller.sessionFor(current), isNot(same(oldOwner)));
          expect(
            () => oldOwner.setAsyncEventListener(screen.session.id, (_, _) {}),
            throwsStateError,
          );

          if (replaceRoot) {
            newerController = GatewayTurnApplicationController(
              journalFactory: () =>
                  GatewayTurnJournal(store: MemoryTurnJournalStore()),
            );
            // New initState installs its real handler before old tree finalization.
            // Old dispose must not clear a callback now owned by this newer root.
            await tester.pumpWidget(
              HermesApp(
                key: UniqueKey(),
                connManager: f.manager,
                turnApplicationController: newerController,
                notifications: f.notifications,
                mobilePush: f.push,
                launchIntents: f.launch,
              ),
            );
            await MutationObserverRootFixture.drain(tester);
            expect(
              tester.state<HermesAppState>(find.byType(HermesApp)).mounted,
              isTrue,
            );
            expect(notificationResponseHandler, isNotNull);
            expect(notificationResponseHandler, isNot(same(oldHandler)));
          } else {
            await tester.pumpWidget(const SizedBox.shrink());
            await MutationObserverRootFixture.drain(tester);
            expect(notificationResponseHandler, isNull);
          }
          expect(root.mounted, isFalse);
          expect(chat.mounted, isFalse);
          // These are after all three exact-owner unsubscribe calls and visit/
          // draft cleanup in ChatScreen.dispose; super.dispose completed too.
          expect(() => composer.addListener(() {}), throwsFlutterError);
          expect(() => scroll.addListener(() {}), throwsFlutterError);
          expect(() => f.controller.sessionFor(current), throwsStateError);
          expect(
            await ComposerDraftStore.read(
              connectionId: current.id,
              sessionId: screen.session.id,
            ),
            'Retained draft survives owner cleanup',
          );
          expect(tester.takeException(), isNull);
          await f.close(tester);
          closed = true;
          await newerController?.close();
          expect(notificationResponseHandler, isNull);
          expect(pendingNotificationApprovals.value, isEmpty);
          await f.manager.updateApiKey(current.id, current.apiKey);
          expect(ConnectionMutationBarrier.isPending(current.id), isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          if (!closed) await f.close(tester);
          await newerController?.close();
        }
      },
    );
  }
}
