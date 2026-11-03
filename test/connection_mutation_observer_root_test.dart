import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets(
    'ROOT37-1 unrelated B observer fault releases failed A and preserves B through fresh A successor',
    (tester) async {
      final f = MutationObserverRootFixture();
      await f.initialize(tester);
      List<String>? saved;
      try {
        await f.manager.saveConnection(
          'Mutation A',
          f.connection.host,
          f.connection.port,
          'fixture',
          dashboardPort: f.connection.dashboardPort,
          dashboardProxied: true,
          gatewayProfile: 'target-profile',
        );
        final a = f.manager.getConnections().singleWhere(
          (c) => c.id != f.connection.id,
        );
        final queuedB = await f.queueAndPause(tester);
        final epoch = ConnectionMutationBarrier.capture(a.id);
        saved = List<String>.from(
          f.manager.prefs.getStringList('saved_connections')!,
        );
        await f.manager.prefs.setStringList('saved_connections', ['{']);
        await expectLater(
          f.manager.updateApiKey(a.id, 'not-committed'),
          throwsA(
            isA<CredentialStorageException>().having(
              (e) => e.toString(),
              'sanitized error',
              'Saved connection metadata could not be read safely.',
            ),
          ),
        );
        final pendingAfterFault = ConnectionMutationBarrier.isPending(a.id);
        final bAfterFault = pendingNotificationApprovals.value.single;
        await f.manager.prefs.setStringList('saved_connections', saved);
        expect(
          f.manager.getConnections().singleWhere((c) => c.id == a.id).apiKey,
          'fixture',
        );
        await f.manager.updateApiKey(a.id, 'successor-fixture');
        final current = f.manager.getConnections().singleWhere(
          (c) => c.id == a.id,
        );
        expect(current.apiKey, 'successor-fixture');
        expect(pendingAfterFault, isFalse);
        expect(ConnectionMutationBarrier.isPending(a.id), isFalse);
        expect(ConnectionMutationBarrier.isCurrent(a.id, epoch), isFalse);
        expect(
          ConnectionMutationBarrier.isCurrent(
            a.id,
            ConnectionMutationBarrier.capture(a.id),
          ),
          isTrue,
        );
        expect(bAfterFault, same(queuedB));
        expect(pendingNotificationApprovals.value.single, same(queuedB));
        expect(queuedB.authority!.isCurrentFor(f.connection), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        if (saved != null) {
          await f.manager.prefs.setStringList('saved_connections', saved);
        }
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'ROOT37-1 real queued B observer cannot prevent supported corrupt saved-key reset',
    (tester) async {
      final f = MutationObserverRootFixture();
      await f.initialize(tester);
      List<String>? saved;
      try {
        await f.queueAndPause(tester);
        saved = List<String>.from(
          f.manager.prefs.getStringList('saved_connections')!,
        );
        await f.manager.prefs.setStringList('saved_connections', ['{']);
        await f.manager.resetConnections();
        await f.manager.prefs.reload();
        expect(f.manager.prefs.containsKey('saved_connections'), isFalse);
        expect(f.manager.getConnections(), isEmpty);
        expect(ConnectionMutationBarrier.isPending(f.connection.id), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        if (saved != null) {
          await f.manager.prefs.setStringList('saved_connections', saved);
        }
        await f.close(tester);
      }
    },
  );
}
