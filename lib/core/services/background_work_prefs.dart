import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local policy, independent of optional notification preferences.
final ValueNotifier<bool> backgroundWorkEnabled = ValueNotifier(true);

/// Deliberately excluded from configuration backups, like notification consent.
/// This controls phone resource use, never the server's execution of a turn.
abstract final class BackgroundWorkPrefsStore {
  static const storageKey = 'hermes_background_work_enabled';
  static Future<void>? _writeTail;
  static int _revision = 0;
  static bool _confirmedEnabled = true;

  /// Last successfully read or written value, never the optimistic UI choice.
  /// Callers must establish readiness through a successful load or write.
  static bool get confirmedEnabled => _confirmedEnabled;

  /// Successful durable choices can establish policy even if startup hydration
  /// failed. Optimistic notifier changes alone must never grant that authority.
  static final _confirmedChanges = ValueNotifier<int>(0);
  static ValueListenable<int> get confirmedChanges => _confirmedChanges;
  static final _pendingChoice = ValueNotifier<bool>(false);

  /// A new enabled choice cannot grant protection until its own save settles.
  /// Separate from UI changes, including when the requested value is unchanged.
  static ValueListenable<bool> get pendingChoice => _pendingChoice;

  static Future<void> load() {
    final revision = _revision;
    return _enqueue(() async {
      // Let the root distinguish an unavailable store from a fresh install.
      // It catches this failure without blocking startup and remains disabled.
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.get(storageKey);
      _confirmedEnabled = raw is bool ? raw : true;
      if (revision == _revision) {
        backgroundWorkEnabled.value = _confirmedEnabled;
      }
    });
  }

  static Future<void> setEnabled(bool enabled) {
    final revision = ++_revision;
    _pendingChoice.value = true;
    backgroundWorkEnabled.value = enabled;
    return _enqueue(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setBool(storageKey, enabled)) {
          throw StateError('Background work preference was not saved');
        }
        _confirmedEnabled = enabled;
        if (revision == _revision) _pendingChoice.value = false;
        // Every committed value changes durable authority, even when a newer
        // optimistic choice is queued behind it. Observers must use the
        // confirmed value, not treat this signal as a grant for that choice.
        _confirmedChanges.value++;
      } catch (_) {
        // Restore confirmed state, never a sibling's failed optimism.
        if (revision == _revision) {
          _pendingChoice.value = false;
          backgroundWorkEnabled.value = _confirmedEnabled;
        }
        rethrow;
      }
    });
  }

  static Future<void> _enqueue(Future<void> Function() operation) {
    final previous = _writeTail;
    final result = previous == null
        ? operation()
        : previous.then((_) => operation());
    late final Future<void> tail;
    void release() {
      // Release idle tails, including their creation zone and old owner.
      if (identical(_writeTail, tail)) _writeTail = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object _, StackTrace _) => release(),
    );
    _writeTail = tail;
    return result;
  }
}

/// Activity-only Android affordance. Opening settings is not an exemption and
/// does not imply that Android will keep a connection alive through Doze.
abstract final class BackgroundWorkPlatform {
  static const channel = MethodChannel(
    'com.hermesagent.hermes_android/background_work',
  );

  static Future<bool> openBatterySettings() async {
    try {
      return await channel.invokeMethod<bool>('openBatterySettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
