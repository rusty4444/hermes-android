import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The native-notification kinds, mirroring the desktop app's seven toggles.
///
/// [approval] and [input] are "attention" kinds: they exist so a blocking
/// prompt cannot be missed while the app is away. The rest describe work that
/// finished in the background.
enum HermesNotificationKind {
  approval,
  input,
  turnDone,
  turnError,
  backgroundDone,
  credits,
  plugin,
}

/// Per-device notification preferences: one master switch and a toggle per
/// kind. Stored in [SharedPreferences] so they survive restarts and never
/// leave the device.
@immutable
class NotificationPrefs {
  final bool enabled;
  final Map<HermesNotificationKind, bool> kinds;

  const NotificationPrefs({required this.enabled, required this.kinds});

  static const defaults = NotificationPrefs(
    enabled: true,
    kinds: {
      HermesNotificationKind.approval: true,
      HermesNotificationKind.input: true,
      HermesNotificationKind.turnDone: true,
      HermesNotificationKind.turnError: true,
      HermesNotificationKind.backgroundDone: true,
      HermesNotificationKind.credits: true,
      HermesNotificationKind.plugin: true,
    },
  );

  /// Whether [kind] may post: the master switch gates every kind.
  bool kindEnabled(HermesNotificationKind kind) =>
      enabled && kinds[kind] == true;

  NotificationPrefs copyWith({
    bool? enabled,
    HermesNotificationKind? kind,
    bool? kindValue,
  }) {
    final nextKinds = Map<HermesNotificationKind, bool>.from(kinds);
    if (kind != null && kindValue != null) {
      nextKinds[kind] = kindValue;
    }
    return NotificationPrefs(
      enabled: enabled ?? this.enabled,
      kinds: nextKinds,
    );
  }

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) {
    final kinds = Map<HermesNotificationKind, bool>.from(defaults.kinds);
    final rawKinds = json['kinds'];
    if (rawKinds is Map) {
      for (final kind in HermesNotificationKind.values) {
        final value = rawKinds[kind.name];
        if (value is bool) {
          kinds[kind] = value;
        }
      }
    }
    return NotificationPrefs(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      kinds: kinds,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'kinds': {for (final entry in kinds.entries) entry.key.name: entry.value},
  };
}

/// The live value every dispatcher reads synchronously; the settings screen
/// writes through [NotificationPrefsStore] so the change persists per device.
final ValueNotifier<NotificationPrefs> notificationPrefs = ValueNotifier(
  NotificationPrefs.defaults,
);

/// Convenience for dispatchers: may [kind] post right now?
bool notificationKindEnabled(HermesNotificationKind kind) =>
    notificationPrefs.value.kindEnabled(kind);

/// Loads and persists [notificationPrefs] on this device.
abstract final class NotificationPrefsStore {
  static const storageKey = 'hermes_notification_prefs';

  /// Reads the persisted value into [notificationPrefs]. Safe to call on every
  /// startup; a corrupt value keeps the defaults instead of throwing.
  static Future<void> load() async {
    try {
      final store = await SharedPreferences.getInstance();
      final raw = store.getString(storageKey);
      if (raw == null) return;
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        notificationPrefs.value = NotificationPrefs.fromJson(parsed);
      }
    } catch (_) {
      // A corrupt value must never block startup; defaults stay in place.
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    final next = notificationPrefs.value.copyWith(enabled: enabled);
    notificationPrefs.value = next;
    await _persist(next);
  }

  static Future<void> setKind(HermesNotificationKind kind, bool value) async {
    final next = notificationPrefs.value.copyWith(kind: kind, kindValue: value);
    notificationPrefs.value = next;
    await _persist(next);
  }

  static Future<void> _persist(NotificationPrefs prefs) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(storageKey, jsonEncode(prefs.toJson()));
    } catch (_) {
      // Persistence is best-effort: the live value already changed.
    }
  }
}
