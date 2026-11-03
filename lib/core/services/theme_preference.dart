import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/hermes_theme.dart';

/// Device-wide appearance preferences, independent of gateway profiles.
class ThemePreferenceStore {
  ThemePreferenceStore(this._preferences);

  static const paletteKey = 'theme_palette';
  static const modeKey = 'theme_mode';
  static final _writes = Expando<_ThemeWriteQueue>();

  final SharedPreferences _preferences;

  /// Unknown IDs and incorrectly typed backup values are read non-destructively.
  HermesPalette readPalette() {
    final value = _preferences.get(paletteKey);
    return HermesPalette.values.firstWhere(
      (palette) => palette.name == value,
      orElse: () => HermesPalette.gold,
    );
  }

  ThemeMode readMode() {
    return switch (_preferences.get(modeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> savePalette(HermesPalette palette) =>
      _save(paletteKey, palette.name);

  Future<void> saveMode(ThemeMode mode) => _save(modeKey, mode.name);

  Future<void> _save(String key, String value) {
    final queue = _writes[_preferences] ??= _ThemeWriteQueue();
    return queue.enqueue(() async {
      // Capture the baseline when this transaction starts, not when queued:
      // a failed older selection must never undo a newer confirmed selection.
      final previous = _preferences.get(key);
      try {
        if (!await _preferences.setString(key, value)) {
          throw StateError('Could not persist $key');
        }
      } catch (_) {
        // Legacy SharedPreferences changes its cache before awaiting storage.
        // These setters also restore that cache synchronously if storage is
        // still unavailable. Surface the original failure, not the rollback.
        try {
          await _restore(key, previous);
        } catch (_) {
          // The original save remains a failure; never announce it as saved.
        }
        rethrow;
      }
    });
  }

  Future<bool> _restore(String key, Object? value) => switch (value) {
    null => _preferences.remove(key),
    String value => _preferences.setString(key, value),
    bool value => _preferences.setBool(key, value),
    int value => _preferences.setInt(key, value),
    double value => _preferences.setDouble(key, value),
    List value => _preferences.setStringList(key, value.cast<String>()),
    _ => throw StateError('Unsupported preference value for $key'),
  };
}

/// Shared across short-lived stores for the same preferences instance.
class _ThemeWriteQueue {
  Future<void> _tail = Future<void>.value();

  Future<void> enqueue(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
