import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';

import 'mobile_push_service_test.dart' as fixture;

class _HeldFailureStore extends fixture.MemorySecrets {
  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<void> write(String key, String value) async {
    final gate = release;
    if (gate != null) {
      release = null;
      entered!.complete();
      await gate.future;
      throw PlatformException(code: 'synthetic-provider-secret-do-not-surface');
    }
    await super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'faulted observers preserve sanitized transaction failure, native END acknowledgement and queued successor ownership',
    () async {
      final f = fixture.Fixture();
      await f.setup();
      final store = _HeldFailureStore();
      final manager = ConnectionManager(
        f.manager.prefs,
        credentialStore: store,
        nativePushSupported: true,
      );
      await manager.saveConnection('A', 'a.invalid', 443, 'original-fixture');
      final a = manager.getConnections().singleWhere((c) => c.label == 'A');
      f.methods.clear();
      final writeEntered = Completer<void>();
      final writeRelease = Completer<void>();
      final endEntered = Completer<void>();
      final endRelease = Completer<void>();
      store.entered = writeEntered;
      store.release = writeRelease;
      var holdEnd = true;
      f.afterCommand = (method, args) async {
        if (method == 'endConnectionChange' && holdEnd) {
          holdEnd = false;
          endEntered.complete();
          await endRelease.future;
        }
      };
      var healthyDeliveries = 0;
      void failing() =>
          throw StateError('synthetic-observer-secret-do-not-surface');
      void healthy() => healthyDeliveries++;
      ConnectionMutationBarrier.addListener(failing);
      ConnectionMutationBarrier.addListener(healthy);
      Future<Object?>? first;
      Future<void>? successor;
      try {
        first = manager
            .updateApiKey(a.id, 'failed-fixture')
            .then<Object?>((_) => null, onError: (Object error) => error);
        await writeEntered.future;
        successor = manager.updateApiKey(a.id, 'successor-fixture');
        final queuedEpoch = ConnectionMutationBarrier.capture(a.id);
        expect(ConnectionMutationBarrier.isCurrent(a.id, queuedEpoch), isFalse);
        expect(
          f.methods.where((m) => m == 'beginConnectionChange'),
          hasLength(1),
        );
        writeRelease.complete();
        await endEntered.future;
        expect(
          f.connectionChanges,
          isEmpty,
          reason: 'Physical END ran, but acknowledgement is deliberately held',
        );
        expect(ConnectionMutationBarrier.isPending(a.id), isTrue);
        expect(
          f.methods.where((m) => m == 'beginConnectionChange'),
          hasLength(1),
        );
        endRelease.complete();
        final failure = await first;
        expect(failure, isA<CredentialStorageException>());
        expect(
          failure.toString(),
          'Connection credentials could not be saved safely.',
        );
        await successor;
        expect(healthyDeliveries, 4);
        expect(
          (await manager.loadConnectionsWithSecrets())
              .singleWhere((c) => c.id == a.id)
              .apiKey,
          'successor-fixture',
        );
        expect(ConnectionMutationBarrier.isPending(a.id), isFalse);
        expect(
          ConnectionMutationBarrier.isCurrent(
            a.id,
            ConnectionMutationBarrier.capture(a.id),
          ),
          isTrue,
        );
        expect(ConnectionMutationBarrier.isCurrent(a.id, queuedEpoch), isFalse);
        expect(f.methods, [
          'beginConnectionChange',
          'endConnectionChange',
          'beginConnectionChange',
          'endConnectionChange',
        ]);
        expect(f.connectionChanges, isEmpty);
        // The fresh physical export owns a further empty-ID list lease.
        expect(healthyDeliveries, 5);
      } finally {
        if (!writeRelease.isCompleted) writeRelease.complete();
        if (!endRelease.isCompleted) endRelease.complete();
        await first;
        await successor;
        ConnectionMutationBarrier.removeListener(failing);
        ConnectionMutationBarrier.removeListener(healthy);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(f.channel, null);
        f.service.dispose();
      }
    },
  );
}
