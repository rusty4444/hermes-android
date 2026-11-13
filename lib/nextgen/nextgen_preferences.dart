// Device preferences for the NextGen interface.
//
// NextGen and the classic interface share every saved connection, chat and
// sign-in. Only how the app looks and which connection NextGen opens on launch
// are kept here.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app runs the NextGen interface. Toggled from Settings in either
/// interface; the root rebuilds when it changes.
final ValueNotifier<bool> nextGenEnabled = ValueNotifier(false);

/// A chat a notification tap asked NextGen to open.
typedef NgOpenRequest = ({String connectionId, String sessionId});

/// Set by the app root when a notification is tapped while NextGen runs.
/// NextGen switches to the connection, opens the chat and clears it.
final ValueNotifier<NgOpenRequest?> nextGenOpenRequest = ValueNotifier(null);

/// Routes a notification tap to NextGen. Returns false when NextGen is off
/// or the payload names no chat, so the classic routing handles it.
bool routeNotificationToNextGen(String? connectionId, String? sessionId) {
  if (!nextGenEnabled.value) return false;
  if (connectionId == null || connectionId.isEmpty) return false;
  if (sessionId == null || sessionId.isEmpty) return false;
  nextGenOpenRequest.value = (connectionId: connectionId, sessionId: sessionId);
  return true;
}

/// The accents NextGen offers (Kyllene's palette: one blue, five others).
enum NgAccent { blue, violet, green, orange, pink, teal }

/// Look-and-feel settings for NextGen, observed by its theme.
class NextGenLook extends ChangeNotifier {
  NextGenLook._();
  static final NextGenLook instance = NextGenLook._();

  ThemeMode themeMode = ThemeMode.system;
  NgAccent accent = NgAccent.blue;
  bool pureBlack = false;

  /// Soft coloured light behind the top of each screen.
  bool glow = true;

  void _apply(void Function() change) {
    change();
    notifyListeners();
  }
}

abstract final class NextGenPreferences {
  static const enabledKey = 'nextgen_enabled';
  static const currentConnectionKey = 'nextgen_current_connection';
  static const themeModeKey = 'nextgen_theme_mode';
  static const accentKey = 'nextgen_accent';
  static const pureBlackKey = 'nextgen_pure_black';
  static const glowKey = 'nextgen_glow';
  static const starredModelsKey = 'nextgen_starred_models';
  static const recentModelsKey = 'nextgen_recent_models';
  static const lastSessionKeyPrefix = 'nextgen_last_session.';

  /// Reads every NextGen preference into memory. Synchronous: the shared
  /// [SharedPreferences] instance is already loaded at startup.
  static void load(SharedPreferences prefs) {
    nextGenEnabled.value = prefs.getBool(enabledKey) ?? false;
    final look = NextGenLook.instance;
    look.themeMode = switch (prefs.getString(themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    look.accent = NgAccent.values.firstWhere(
      (a) => a.name == prefs.getString(accentKey),
      orElse: () => NgAccent.blue,
    );
    look.pureBlack = prefs.getBool(pureBlackKey) ?? false;
    look.glow = prefs.getBool(glowKey) ?? true;
  }

  static Future<void> setEnabled(SharedPreferences prefs, bool enabled) async {
    nextGenEnabled.value = enabled;
    await prefs.setBool(enabledKey, enabled);
  }

  static String? currentConnectionId(SharedPreferences prefs) =>
      prefs.getString(currentConnectionKey);

  static Future<void> setCurrentConnectionId(
    SharedPreferences prefs,
    String? id,
  ) => id == null
      ? prefs.remove(currentConnectionKey)
      : prefs.setString(currentConnectionKey, id);

  static Future<void> setThemeMode(
    SharedPreferences prefs,
    ThemeMode mode,
  ) async {
    NextGenLook.instance._apply(() => NextGenLook.instance.themeMode = mode);
    await prefs.setString(themeModeKey, mode.name);
  }

  static Future<void> setAccent(
    SharedPreferences prefs,
    NgAccent accent,
  ) async {
    NextGenLook.instance._apply(() => NextGenLook.instance.accent = accent);
    await prefs.setString(accentKey, accent.name);
  }

  static Future<void> setPureBlack(SharedPreferences prefs, bool value) async {
    NextGenLook.instance._apply(() => NextGenLook.instance.pureBlack = value);
    await prefs.setBool(pureBlackKey, value);
  }

  static Future<void> setGlow(SharedPreferences prefs, bool value) async {
    NextGenLook.instance._apply(() => NextGenLook.instance.glow = value);
    await prefs.setBool(glowKey, value);
  }

  static List<String> starredModels(SharedPreferences prefs) =>
      prefs.getStringList(starredModelsKey) ?? const [];

  static Future<void> setStarredModels(
    SharedPreferences prefs,
    List<String> keys,
  ) => prefs.setStringList(starredModelsKey, keys);

  static List<String> recentModels(SharedPreferences prefs) =>
      prefs.getStringList(recentModelsKey) ?? const [];

  static Future<void> pushRecentModel(SharedPreferences prefs, String key) {
    final next = [key, ...recentModels(prefs).where((k) => k != key)];
    return prefs.setStringList(recentModelsKey, next.take(6).toList());
  }

  /// The chat NextGen last had open on [connectionId], reopened on launch.
  static String? lastSession(SharedPreferences prefs, String connectionId) =>
      prefs.getString('$lastSessionKeyPrefix$connectionId');

  static Future<void> setLastSession(
    SharedPreferences prefs,
    String connectionId,
    String? sessionId,
  ) => sessionId == null
      ? prefs.remove('$lastSessionKeyPrefix$connectionId')
      : prefs.setString('$lastSessionKeyPrefix$connectionId', sessionId);
}
