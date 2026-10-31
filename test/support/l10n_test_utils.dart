import 'package:flutter/material.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

/// Loads the generated localizations for tests.
///
/// English is the app's template locale, so tests that assert on copy see the
/// same strings the source used before localization.
Future<AppLocalizations> loadTestL10n([Locale locale = const Locale('en')]) {
  return AppLocalizations.delegate.load(locale);
}

/// Wraps [child] in a [MaterialApp] with the Hermes localization delegates so
/// `context.l10n` resolves inside pumped widgets.
Widget testAppWithL10n(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: preferredSupportedLocales(),
    localeListResolutionCallback: resolvePreferredLocale,
    home: child,
  );
}
