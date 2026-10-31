import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/background_work_prefs.dart';
import 'package:hermes_android/core/services/config_backup_service.dart';
import 'package:hermes_android/core/services/connection_keepalive_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingPreferences extends InMemorySharedPreferencesStore {
  _FailingPreferences() : super.empty();
  @override
  Future<Map<String, Object>> getAll() async => throw StateError('unavailable');
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backgroundWorkEnabled.value = true;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(
      ConnectionKeepAliveService.channel,
      null,
    );
    messenger.setMockMethodCallHandler(BackgroundWorkPlatform.channel, null);
  });

  test(
    'background protection defaults to true and stays device-local',
    () async {
      backgroundWorkEnabled.value = false;
      await BackgroundWorkPrefsStore.load();
      expect(backgroundWorkEnabled.value, isTrue);
      expect(
        ConfigBackupService.isBackedUpKey(BackgroundWorkPrefsStore.storageKey),
        isFalse,
      );
    },
  );

  test(
    'setting survives reload, with writes serialized in intent order',
    () async {
      final writes = [
        BackgroundWorkPrefsStore.setEnabled(false),
        BackgroundWorkPrefsStore.setEnabled(true),
        BackgroundWorkPrefsStore.setEnabled(false),
      ];
      await Future.wait(writes);
      backgroundWorkEnabled.value = true;
      await BackgroundWorkPrefsStore.load();
      expect(backgroundWorkEnabled.value, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(BackgroundWorkPrefsStore.storageKey), isFalse);
    },
  );

  test('an older startup load cannot overwrite a newer user choice', () async {
    SharedPreferences.setMockInitialValues({
      BackgroundWorkPrefsStore.storageKey: true,
    });
    final loading = BackgroundWorkPrefsStore.load();
    final saving = BackgroundWorkPrefsStore.setEnabled(false);
    await Future.wait([loading, saving]);
    expect(backgroundWorkEnabled.value, isFalse);
    await BackgroundWorkPrefsStore.load();
    expect(backgroundWorkEnabled.value, isFalse);
  });

  test('a malformed saved policy falls back to enabled', () async {
    SharedPreferences.setMockInitialValues({
      BackgroundWorkPrefsStore.storageKey: 'bad',
    });
    backgroundWorkEnabled.value = false;
    await BackgroundWorkPrefsStore.load();
    expect(backgroundWorkEnabled.value, isTrue);
  });

  test(
    'unavailable policy load reports failure instead of establishing a default',
    () async {
      await SharedPreferences.getInstance();
      final original = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _FailingPreferences();
      addTearDown(() => SharedPreferencesStorePlatform.instance = original);
      await expectLater(BackgroundWorkPrefsStore.load(), throwsStateError);
    },
  );

  test('failed explicit write does not establish policy authority', () async {
    await BackgroundWorkPrefsStore.load();
    final confirmed = BackgroundWorkPrefsStore.confirmedChanges.value;
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = _FailingPreferences();
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    await expectLater(
      BackgroundWorkPrefsStore.setEnabled(false),
      throwsStateError,
    );
    expect(BackgroundWorkPrefsStore.confirmedChanges.value, confirmed);
    expect(backgroundWorkEnabled.value, isTrue);
  });

  test('disabled policy refuses direct and lifecycle starts', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
      call,
    ) async {
      calls.add(call.method);
      return true;
    });
    final service = ConnectionKeepAliveService();
    service.onPolicyChanged(false);
    await pumpEventQueue();
    calls.clear();
    await service.start();
    service.onAppLifecycleState(
      AppLifecycleState.inactive,
      hasActiveTurn: true,
    );
    service.onAppLifecycleState(AppLifecycleState.hidden, hasActiveTurn: true);
    service.onAppLifecycleState(AppLifecycleState.paused, hasActiveTurn: true);
    service.onTurnActivityChanged(true);
    await pumpEventQueue();
    expect(calls, isEmpty);
    expect(service.isActive, isFalse);
  });

  test('disabling during native start compensates a late success', () async {
    final gate = Completer<bool>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'start' ? gate.future : true;
    });
    final service = ConnectionKeepAliveService();
    service.onAppLifecycleState(
      AppLifecycleState.inactive,
      hasActiveTurn: true,
    );
    await pumpEventQueue();
    service.onPolicyChanged(false);
    await pumpEventQueue();
    gate.complete(true);
    await pumpEventQueue();
    expect(calls, ['start', 'stop', 'stop']);
    expect(service.isActive, isFalse);
  });

  test('reenabling restores only unresolved background work', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
      call,
    ) async {
      calls.add(call.method);
      return true;
    });
    final service = ConnectionKeepAliveService();
    service.onPolicyChanged(false);
    service.onAppLifecycleState(AppLifecycleState.paused, hasActiveTurn: false);
    await pumpEventQueue();
    calls.clear();
    service.onPolicyChanged(true);
    await pumpEventQueue();
    expect(calls, isEmpty); // idle connections do not count
    service.onPolicyChanged(false);
    service.onTurnActivityChanged(true);
    await pumpEventQueue();
    calls.clear();
    service.onPolicyChanged(true);
    await pumpEventQueue();
    expect(calls, ['start']);
    service.onPolicyChanged(false);
    service.onTurnActivityChanged(false); // work settles while disabled
    await pumpEventQueue();
    calls.clear();
    service.onPolicyChanged(true);
    await pumpEventQueue();
    expect(calls, isEmpty);
    expect(service.isActive, isFalse);
  });

  test('reenabling in the foreground does not start a service', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
      call,
    ) async {
      calls.add(call.method);
      return true;
    });
    final service = ConnectionKeepAliveService();
    service.onPolicyChanged(false);
    service.onTurnActivityChanged(true);
    await pumpEventQueue();
    calls.clear();
    service.onPolicyChanged(true);
    await pumpEventQueue();
    expect(calls, isEmpty);
    service.onAppLifecycleState(
      AppLifecycleState.inactive,
      hasActiveTurn: true,
    );
    await pumpEventQueue();
    expect(calls, ['start']);
  });

  test(
    'disable-reenable while start pending follows latest policy once',
    () async {
      final first = Completer<bool>();
      var starts = 0;
      messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
        call,
      ) async {
        if (call.method == 'start' && ++starts == 1) return first.future;
        return true;
      });
      final service = ConnectionKeepAliveService();
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      service.onPolicyChanged(false);
      service.onPolicyChanged(true);
      service.onAppLifecycleState(
        AppLifecycleState.hidden,
        hasActiveTurn: true,
      );
      service.onAppLifecycleState(
        AppLifecycleState.paused,
        hasActiveTurn: true,
      );
      first.complete(true);
      await pumpEventQueue();
      expect(starts, 2);
      expect(service.isActive, isTrue);
    },
  );

  test(
    'new start waits for a held compensating stop, and is not killed by it',
    () async {
      final first = Completer<bool>();
      final compensation = Completer<bool>();
      var starts = 0;
      var stops = 0;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'start' && ++starts == 1) return first.future;
        if (call.method == 'stop' && ++stops == 2) return compensation.future;
        return true;
      });
      final service = ConnectionKeepAliveService();
      service.onAppLifecycleState(
        AppLifecycleState.inactive,
        hasActiveTurn: true,
      );
      await pumpEventQueue();
      service.onPolicyChanged(false);
      await pumpEventQueue();
      first.complete(true);
      await pumpEventQueue();
      expect(calls, ['start', 'stop', 'stop']);
      service.onPolicyChanged(true);
      await pumpEventQueue();
      expect(starts, 1);
      compensation.complete(true);
      await pumpEventQueue();
      expect(starts, 2);
      expect(service.isActive, isTrue);
    },
  );

  test(
    'start drains stops added while an older stop is still pending',
    () async {
      final firstStop = Completer<bool>();
      final secondStop = Completer<bool>();
      var stops = 0;
      var starts = 0;
      messenger.setMockMethodCallHandler(ConnectionKeepAliveService.channel, (
        call,
      ) async {
        if (call.method == 'start') {
          starts++;
          return true;
        }
        return ++stops == 1 ? firstStop.future : secondStop.future;
      });
      final service = ConnectionKeepAliveService();
      final stoppingFirst = service.stop();
      await pumpEventQueue();
      final starting = service.start();
      await pumpEventQueue();
      final stoppingSecond = service.stop();
      final latestStart = service.start();
      await pumpEventQueue();
      firstStop.complete(true);
      await pumpEventQueue();
      expect(starts, 0);
      secondStop.complete(true);
      await Future.wait([stoppingFirst, starting, stoppingSecond, latestStart]);
      expect(starts, 1);
      expect(service.isActive, isTrue);
    },
  );

  test(
    'battery navigation reports missing plugin and platform refusal honestly',
    () async {
      expect(await BackgroundWorkPlatform.openBatterySettings(), isFalse);
      messenger.setMockMethodCallHandler(BackgroundWorkPlatform.channel, (
        call,
      ) async {
        expectSync(call.method, 'openBatterySettings');
        throw PlatformException(code: 'unavailable');
      });
      expect(await BackgroundWorkPlatform.openBatterySettings(), isFalse);
      messenger.setMockMethodCallHandler(
        BackgroundWorkPlatform.channel,
        (call) async => true,
      );
      expect(await BackgroundWorkPlatform.openBatterySettings(), isTrue);
    },
  );
}
