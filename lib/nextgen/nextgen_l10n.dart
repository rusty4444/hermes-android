// Localized NextGen text.
//
// NextGen strings live in the app's ARB files under `ng_` keys. Data classes
// (connection checks, gateway states, input requests) build text outside any
// widget, so the current strings are kept here: the app root updates them
// whenever the locale changes, and English is used until then (and in tests).
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

AppLocalizations _current = lookupAppLocalizations(const Locale('en'));

/// The NextGen strings for the app's current language.
AppLocalizations get ngL => _current;

/// Keeps [ngL] in step with the app's locale. Placed in the app builder, so it
/// sits under the app's Localizations and above every NextGen route.
class NgLocalizationScope extends StatefulWidget {
  const NgLocalizationScope({super.key, required this.child});

  final Widget child;

  @override
  State<NgLocalizationScope> createState() => _NgLocalizationScopeState();
}

class _NgLocalizationScopeState extends State<NgLocalizationScope> {
  Locale? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final strings = AppLocalizations.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    if (strings == null || locale == _locale) return;
    final changed = _locale != null;
    _locale = locale;
    _current = strings;
    if (changed) {
      // Text read through [ngL] has no dependency on Localizations, so a
      // language change rebuilds the whole subtree once.
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
