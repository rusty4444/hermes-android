import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/services/client_certificate_service.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mtls_fixture.dart';

class _Secrets implements CredentialStore {
  final values = <String, String>{};
  @override
  String? readCached(String key) => values[key];
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hermesagent.hermes_android/mobile_push');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory support;
  late ClientCertificateService files;
  late ConnectionManager manager;
  late Future<Object?> Function(MethodCall) native;
  final begins = <String>[];
  final ends = <String>[];
  final active = <String>{};

  Future<ClientCertificateConfig> identity(String label) async => files.commit(
    await files.importPemPair(
      certificateBytes: await File(
        loopbackIdentity.certificatePemPath,
      ).readAsBytes(),
      privateKeyBytes: await File(
        loopbackIdentity.privateKeyPemPath,
      ).readAsBytes(),
      label: label,
    ),
  );
  void exists(ClientCertificateConfig config, bool expected) {
    expect(File(config.certificatePemPath).existsSync(), expected);
    expect(File(config.privateKeyPemPath).existsSync(), expected);
  }

  Future<void> fails(Future<void> work) =>
      expectLater(work, throwsA(isA<CredentialStorageException>()));

  setUp(() async {
    begins.clear();
    ends.clear();
    active.clear();
    support = await Directory.systemTemp.createTemp('pending-end-concurrency-');
    files = ClientCertificateService(supportDirectory: () async => support);
    SharedPreferences.setMockInitialValues({});
    manager = ConnectionManager(
      await SharedPreferences.getInstance(),
      credentialStore: _Secrets(),
      certificateFiles: files,
      nativePushSupported: true,
    );
    native = (_) async => null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final token = (call.arguments as Map)['mutation'] as String;
      if (call.method == 'beginConnectionChange') {
        begins.add(token);
        active.add(token);
      } else {
        ends.add(token);
      }
      return native(call);
    });
  });
  tearDown(() async {
    native = (call) async {
      if (call.method == 'endConnectionChange') {
        active.remove((call.arguments as Map)['mutation']);
      }
      return null;
    };
    await manager.finishPendingMobilePushChanges();
    messenger.setMockMethodCallHandler(channel, null);
    await support.delete(recursive: true);
  });

  test(
    'concurrent drains share token flights across zones without stale snapshot resurrection',
    () async {
      final x = await identity('X'),
          y = await identity('Y'),
          unrelated = await identity('unrelated');
      final ownerX = ClientCertificateFileLease()..retainIdentity(x);
      final ownerY = ClientCertificateFileLease()..retainIdentity(y);
      final foreign = ClientCertificateFileLease()..retainIdentity(unrelated);
      final bothBegun = Completer<void>();
      native = (call) async {
        if (call.method == 'beginConnectionChange') {
          if (begins.length == 2) bothBegun.complete();
          await bothBegun.future;
        } else {
          throw PlatformException(code: 'END lost before native effect');
        }
        return null;
      };
      await Future.wait([
        fails(ownerX.run(() => manager.clearDashboardNativeTokens('X'))),
        fails(ownerY.run(() => manager.clearDashboardNativeTokens('Y'))),
      ]);
      await ownerX.close();
      await ownerY.close();
      await files.deleteUnreferenced([]);
      exists(x, true);
      exists(y, true);
      final entered = Completer<void>(), release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var retries = 0;
      native = (call) async {
        if (call.method == 'endConnectionChange') {
          retries++;
          if (retries == 1) {
            entered.complete();
            await release.future;
          }
          active.remove((call.arguments as Map)['mutation']);
        }
        return null;
      };
      final a = foreign.run(manager.finishPendingMobilePushChanges);
      await entered.future;
      var bFinished = false;
      final b = manager.finishPendingMobilePushChanges().then(
        (_) => bFinished = true,
      );
      // A bounded event-loop turn is not the ordering gate: entered/release are.
      await Future<void>.delayed(Duration.zero);
      expect(
        bFinished,
        false,
        reason:
            'B must join A\'s in-flight X, not complete Y behind A\'s stale snapshot',
      );
      expect(retries, 1);
      release.complete();
      await Future.wait([a, b]);
      expect(retries, 2);
      expect(active, isEmpty);
      await foreign.close();
      await files.deleteUnreferenced([]);
      exists(x, false);
      exists(y, false);
      exists(unrelated, false);
      final before = ends.length;
      await manager.finishPendingMobilePushChanges();
      expect(ends.length, before);
    },
  );

  test(
    'repeated pre-BEGIN drain failures create no END obligations or unrelated pins',
    () async {
      final x = await identity('X');
      final owner = ClientCertificateFileLease()..retainIdentity(x);
      native = (call) async {
        if (call.method == 'endConnectionChange') {
          throw PlatformException(code: 'END before effect');
        }
        return null;
      };
      await fails(owner.run(() => manager.clearDashboardNativeTokens('X')));
      await owner.close();
      final originalToken = begins.single;
      for (var i = 0; i < 3; i++) {
        final unrelated = await identity('attempt-$i');
        final foreign = ClientCertificateFileLease()..retainIdentity(unrelated);
        await fails(
          foreign.run(() => manager.clearDashboardNativeTokens('new-$i')),
        );
        await foreign.close();
        expect(ConnectionMutationBarrier.isPending('new-$i'), false);
        await files.deleteUnreferenced([]);
        exists(x, true);
        exists(unrelated, false);
        expect(begins, [originalToken]);
        expect(ends.toSet(), {originalToken});
      }
      native = (call) async {
        active.remove((call.arguments as Map)['mutation']);
        return null;
      };
      await manager.finishPendingMobilePushChanges();
      await files.deleteUnreferenced([]);
      exists(x, false);
      expect(active, isEmpty);
    },
  );

  test(
    'concurrent failed END is shared, propagates to both drains and stays retryable',
    () async {
      final x = await identity('shared-error');
      final owner = ClientCertificateFileLease()..retainIdentity(x);
      native = (call) async {
        if (call.method == 'endConnectionChange') {
          throw PlatformException(code: 'initial loss');
        }
        return null;
      };
      await fails(
        owner.run(() => manager.clearDashboardNativeTokens('shared-error')),
      );
      await owner.close();
      final entered = Completer<void>(), release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var attempts = 0;
      native = (call) async {
        attempts++;
        entered.complete();
        await release.future;
        throw PlatformException(code: 'shared failure');
      };
      final a = expectLater(
        manager.finishPendingMobilePushChanges(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'shared failure',
          ),
        ),
      );
      await entered.future;
      final b = expectLater(
        manager.finishPendingMobilePushChanges(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'shared failure',
          ),
        ),
      );
      release.complete();
      await Future.wait([a, b]);
      expect(attempts, 1);
      await files.deleteUnreferenced([]);
      exists(x, true);
      native = (call) async {
        active.remove((call.arguments as Map)['mutation']);
        return null;
      };
      await manager.finishPendingMobilePushChanges();
      await files.deleteUnreferenced([]);
      exists(x, false);
      expect(active, isEmpty);
    },
  );

  test(
    'uncertain BEGIN still registers recovery and retains exact files until END succeeds',
    () async {
      final x = await identity('uncertain-BEGIN');
      final owner = ClientCertificateFileLease()..retainIdentity(x);
      native = (call) async =>
          throw PlatformException(code: 'lost native reply');
      await fails(
        owner.run(() => manager.clearDashboardNativeTokens('uncertain')),
      );
      await owner.close();
      expect(begins, hasLength(1));
      expect(ends, [begins.single]);
      expect(active, {begins.single});
      expect(ConnectionMutationBarrier.isPending('uncertain'), false);
      await files.deleteUnreferenced([]);
      exists(x, true);
      native = (call) async {
        active.remove((call.arguments as Map)['mutation']);
        return null;
      };
      await manager.finishPendingMobilePushChanges();
      expect(ends, [begins.single, begins.single]);
      await files.deleteUnreferenced([]);
      exists(x, false);
      expect(active, isEmpty);
    },
  );
}
