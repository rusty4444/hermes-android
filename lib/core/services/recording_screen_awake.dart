import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

/// An Activity-window flag, held only during active microphone capture.
/// Each controller has its own owner so closing an old chat cannot release a
/// newer chat's recording. This does not change the device's screen timeout.
class RecordingScreenAwake {
  static const channel = MethodChannel(
    'com.hermesagent.hermes_android/recording_screen',
  );

  final String _owner = const Uuid().v4();
  bool _enabled = false;

  void setEnabled(bool enabled) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_enabled == enabled) return;
    _enabled = enabled;
    // MethodChannel preserves request order, including a release sent before
    // the preceding enable reply returns. Never let a platform failure stop
    // microphone finalization or lose a saved draft.
    unawaited(_send(enabled));
  }

  Future<void> _send(bool enabled) async {
    try {
      await channel.invokeMethod<void>('setEnabled', {
        'owner': _owner,
        'enabled': enabled,
      });
    } on MissingPluginException {
      // No Android Activity on unsupported hosts or in headless tests.
    } on PlatformException {
      // Recording/draft cleanup must still finish if the Activity is gone.
    }
  }
}
