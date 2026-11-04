import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n.dart';

/// Only generated catalogues are selectable. Null follows the device preferences.
class LocalePreference {
  static const key = 'app_locale';
  static Locale? read(SharedPreferences preferences) {
    final tag = preferences.getString(key);
    for (final locale in AppLocalizations.supportedLocales) {
      if (locale.toLanguageTag() == tag) return locale;
    }
    return null;
  }

  static Future<void> save(
    SharedPreferences preferences,
    Locale? locale,
  ) async {
    if (locale == null) {
      await preferences.remove(key);
    } else if (AppLocalizations.supportedLocales.contains(locale)) {
      await preferences.setString(key, locale.toLanguageTag());
    } else {
      throw ArgumentError('Unsupported application language');
    }
  }

  static String name(Locale locale) => switch (locale.toLanguageTag()) {
    'uk' => 'Українська',
    'en' => 'English',
    'de' => 'Deutsch',
    'es' => 'Español',
    'fr' => 'Français',
    'ja' => '日本語',
    'ko' => '한국어',
    'pt' => 'Português',
    'pt-BR' => 'Português (Brasil)',
    'ru' => 'Русский',
    'zh' => '中文',
    'zh-Hans' => '中文（简体）',
    _ => locale.toLanguageTag(),
  };
}
