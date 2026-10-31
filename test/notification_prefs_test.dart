import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notificationPrefs.value = NotificationPrefs.defaults;
  });

  test('defaults enable every kind', () {
    final prefs = NotificationPrefs.defaults;
    expect(prefs.enabled, isTrue);
    for (final kind in HermesNotificationKind.values) {
      expect(prefs.kindEnabled(kind), isTrue, reason: kind.name);
    }
  });

  test('the master switch gates every kind', () {
    final prefs = NotificationPrefs.defaults.copyWith(enabled: false);
    for (final kind in HermesNotificationKind.values) {
      expect(prefs.kindEnabled(kind), isFalse, reason: kind.name);
    }
  });

  test('a single kind can be disabled without touching the others', () {
    final prefs = NotificationPrefs.defaults.copyWith(
      kind: HermesNotificationKind.plugin,
      kindValue: false,
    );
    expect(prefs.kindEnabled(HermesNotificationKind.plugin), isFalse);
    expect(prefs.kindEnabled(HermesNotificationKind.approval), isTrue);
  });

  test('json round-trips the master switch and every kind', () {
    final original = NotificationPrefs.defaults.copyWith(
      enabled: true,
      kind: HermesNotificationKind.credits,
      kindValue: false,
    );
    final restored = NotificationPrefs.fromJson(original.toJson());
    expect(restored.enabled, original.enabled);
    expect(restored.kinds, original.kinds);
  });

  test('a corrupt stored value keeps the defaults', () {
    final restored = NotificationPrefs.fromJson({
      'enabled': 'yes please',
      'kinds': {'approval': 'nope', 42: true},
    });
    expect(restored.enabled, isTrue);
    expect(restored.kindEnabled(HermesNotificationKind.approval), isTrue);
  });

  test('the store persists and reloads the live value', () async {
    await NotificationPrefsStore.setEnabled(false);
    await NotificationPrefsStore.setKind(HermesNotificationKind.plugin, false);

    // Wipe the live value, then load what was persisted.
    notificationPrefs.value = NotificationPrefs.defaults;
    await NotificationPrefsStore.load();

    expect(notificationPrefs.value.enabled, isFalse);
    expect(
      notificationPrefs.value.kindEnabled(HermesNotificationKind.plugin),
      isFalse,
    );
  });

  test('load() tolerates a corrupt persisted string', () async {
    SharedPreferences.setMockInitialValues({
      NotificationPrefsStore.storageKey: '{not json',
    });
    await NotificationPrefsStore.load();
    expect(notificationPrefs.value.enabled, isTrue);
  });
}
