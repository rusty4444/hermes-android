import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the foreground hands-free voice feature is offered at all.
///
/// Disabling it hides the composer start/stop control and the in-chat voice
/// controls, and stops any running hands-free session. This is a per-device
/// user preference; it never restores microphone consent by itself. Stored in
/// [SharedPreferences] so it survives restarts and never leaves the device.
final ValueNotifier<bool> handsFreeEnabled = ValueNotifier(true);

/// Loads and persists [handsFreeEnabled] on this device.
abstract final class HandsFreePreferenceStore {
  static const storageKey = 'hermes_hands_free_enabled';

  /// Reads the persisted value into [handsFreeEnabled]. Safe to call on every
  /// startup; a failed read keeps the default instead of blocking startup.
  static Future<void> load() async {
    try {
      final store = await SharedPreferences.getInstance();
      final value = store.getBool(storageKey);
      if (value != null) handsFreeEnabled.value = value;
    } catch (_) {
      // A failed read must never block startup; the default stays in place.
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    handsFreeEnabled.value = enabled;
    try {
      final store = await SharedPreferences.getInstance();
      await store.setBool(storageKey, enabled);
    } catch (_) {
      // The live value already changed; persistence can retry on a later write.
    }
  }
}
