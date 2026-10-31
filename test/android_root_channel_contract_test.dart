import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'activity installs battery settings beside push and existing intent/keepalive channels',
    () {
      final activity = File(
        'android/app/src/main/kotlin/com/hermesagent/hermes_android/MainActivity.kt',
      ).readAsStringSync();
      expect(
        activity,
        contains(
          'BackgroundWorkPlatform.install(this, flutterEngine.dartExecutor.binaryMessenger)',
        ),
      );
      expect(activity, contains('MobilePushPlugin.install(flutterEngine)'));
      expect(activity, contains('MobilePushBridge.captureTap(this, intent)'));
      // Mutation ownership now follows the engine, not a replaceable Activity.
      // The runtime held-write/sibling schedules live in the native lifecycle
      // suite; this static contract only verifies the consuming installation.
      expect(activity, isNot(contains('MobilePushBridge.detach()')));
      final pushPlugin = File(
        'android/app/src/main/kotlin/com/hermesagent/hermes_android/MobilePushPlugin.kt',
      ).readAsStringSync();
      expect(pushPlugin, contains('MobilePushBridge.attach(value, owner)'));
      expect(pushPlugin, contains('onDetachedFromEngine'));
      expect(pushPlugin, contains('MobilePushBridge.detachEngine(owner)'));
      expect(pushPlugin, contains('EngineScopedSecureStoragePlugin(owner)'));
      expect(pushPlugin, contains('EngineScopedPreferencesPlugin(owner)'));
      expect(activity, contains('shareChannelName'));
      expect(activity, contains('launchChannelName'));
      expect(activity, contains('keepAliveChannelName'));
      final battery = File(
        'android/app/src/main/kotlin/com/hermesagent/hermes_android/BackgroundWorkPlatform.kt',
      ).readAsStringSync();
      expect(
        battery,
        contains('com.hermesagent.hermes_android/background_work'),
      );
      expect(battery, contains('"openBatterySettings"'));
      expect(
        battery,
        contains(
          'Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)',
        ),
      );
      expect(
        battery,
        isNot(
          contains(
            'Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
          ),
        ),
      );
    },
  );
}
