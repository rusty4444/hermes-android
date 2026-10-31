import 'package:flutter/widgets.dart';

import 'package:hermes_android/l10n/app_localizations.dart';

export 'package:hermes_android/l10n/app_localizations.dart' show AppLocalizations;

/// Convenience accessor for the generated [AppLocalizations].
///
/// Screens and widgets can read localized strings with `context.l10n.someKey`
/// instead of importing and resolving [AppLocalizations] everywhere.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

/// The app's supported locales with English first.
///
/// Flutter's built-in resolution falls back to the first supported locale for
/// device languages the app does not support. The generated list is ordered
/// alphabetically (German first), so pass this list to [MaterialApp] to make
/// English the fallback.
List<Locale> preferredSupportedLocales() => <Locale>[
      const Locale('en'),
      ...AppLocalizations.supportedLocales.where(
        (final Locale locale) => locale.languageCode != 'en',
      ),
    ];

/// Resolves the device's preferred locales to one the app can serve.
///
/// Mirrors Flutter's basic resolution order (exact match, then
/// language+script, language+country, and a generic language match) with two
/// deliberate differences:
///
/// * English is the fallback instead of the first supported locale.
/// * A locale variant without its own catalogue is never served another
///   variant's catalogue: Traditional Chinese (`zh-Hant`, `zh_TW`, `zh_HK`,
///   `zh_MO`) is not served the Simplified catalogue, and Portuguese outside
///   Brazil is not served the Brazilian catalogue. Those preferences are
///   skipped, so a secondary preference or English is used instead.
Locale resolvePreferredLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  if (preferredLocales != null) {
    for (final Locale locale in preferredLocales) {
      if (_isUntranslatedVariant(locale)) {
        continue;
      }
      // Exact match (language + script + country).
      for (final Locale supported in supportedLocales) {
        if (supported == locale) {
          return supported;
        }
      }
      // Language + script.
      if (locale.scriptCode != null) {
        for (final Locale supported in supportedLocales) {
          if (supported.languageCode == locale.languageCode &&
              supported.scriptCode == locale.scriptCode) {
            return supported;
          }
        }
      }
      // Language + country.
      if (locale.countryCode != null) {
        for (final Locale supported in supportedLocales) {
          if (supported.languageCode == locale.languageCode &&
              supported.countryCode == locale.countryCode) {
            return supported;
          }
        }
      }
      // Generic language match (a supported locale without script/country).
      for (final Locale supported in supportedLocales) {
        if (supported.languageCode == locale.languageCode &&
            supported.scriptCode == null &&
            supported.countryCode == null) {
          return supported;
        }
      }
    }
  }
  return const Locale('en');
}

/// Whether [locale] names a Chinese or Portuguese variant the app does not
/// translate, so it must not be served the Simplified/Brazilian catalogue.
bool _isUntranslatedVariant(Locale locale) {
  if (locale.languageCode == 'zh') {
    if (locale.scriptCode == 'Hans') {
      return false;
    }
    return locale.scriptCode == 'Hant' ||
        const <String>{'TW', 'HK', 'MO'}.contains(locale.countryCode);
  }
  if (locale.languageCode == 'pt') {
    return locale.countryCode != null && locale.countryCode != 'BR';
  }
  return false;
}
