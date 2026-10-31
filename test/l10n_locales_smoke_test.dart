// Smoke coverage for the additional locale catalogs (zh_Hans/ko/es/fr/de/pt_BR/ru)
// added on top of the en/ja baseline.
//
// Each added locale must render a normal message (translated, non-empty, not
// the English fallback) and a placeholder message whose values are substituted
// and whose copy differs from both the English and the Japanese catalogs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

import 'support/l10n_test_utils.dart';

const _addedLocales = ['zh_Hans', 'ko', 'es', 'fr', 'de', 'pt_BR', 'ru'];

/// Builds the [Locale] for a catalogue code (`zh_Hans` carries a script code,
/// `pt_BR` a country code).
Locale _localeFor(String code) {
  final parts = code.split('_');
  if (parts.length != 2) {
    return Locale(code);
  }
  final subtag = parts[1];
  return subtag.length == 4
      ? Locale.fromSubtags(languageCode: parts[0], scriptCode: subtag)
      : Locale.fromSubtags(languageCode: parts[0], countryCode: subtag);
}

void main() {
  group('additional locales', () {
    for (final code in _addedLocales) {
      final locale = _localeFor(code);

      test('$code renders normal messages translated (non-empty, not English)',
          () async {
        final l10n = await loadTestL10n(locale);
        final en = await loadTestL10n(const Locale('en'));

        expect(l10n.cancel, isNotEmpty);
        expect(l10n.cancel, isNot(en.cancel));
        expect(l10n.delete, isNotEmpty);
        expect(l10n.delete, isNot(en.delete));
        expect(l10n.settings, isNotEmpty);
        expect(l10n.settings, isNot(en.settings));
      });

      test(
          '$code renders placeholder messages with substituted values '
          'that differ from the en/ja fallbacks', () async {
        final l10n = await loadTestL10n(locale);
        final en = await loadTestL10n(const Locale('en'));
        final ja = await loadTestL10n(const Locale('ja'));

        final rendered = l10n.connection_address_key('10.0.2.2:8642', '✓');
        expect(rendered, contains('10.0.2.2:8642'));
        expect(rendered, contains('✓'));
        expect(rendered,
            isNot(en.connection_address_key('10.0.2.2:8642', '✓')));
        expect(rendered,
            isNot(ja.connection_address_key('10.0.2.2:8642', '✓')));
      });
    }

    test('all added locales are registered in supportedLocales', () {
      for (final code in _addedLocales) {
        expect(AppLocalizations.supportedLocales, contains(_localeFor(code)));
      }
    });

    test('count messages use locale-aware ICU plural categories', () async {
      final en = await loadTestL10n(const Locale('en'));
      expect(en.chats_count(1), '1 chat');
      expect(en.chats_count(2), '2 chats');

      final ru = await loadTestL10n(const Locale('ru'));
      expect(ru.chats_count(1), '1 чат');
      expect(ru.chats_count(2), '2 чата');
      expect(ru.chats_count(5), '5 чатов');
      expect(ru.chats_count(21), '21 чат');
      expect(ru.chats_count(22), '22 чата');
      expect(ru.new_messages(3), '3 новых сообщения');
      expect(ru.new_messages(5), '5 новых сообщений');
    });

    testWidgets('pumps widgets under every added locale with the app delegates',
        (tester) async {
      for (final code in _addedLocales) {
        final l10n = await loadTestL10n(_localeFor(code));

        await tester.pumpWidget(
          testAppWithL10n(
            Builder(
              builder: (context) => Column(
                children: [
                  Text(context.l10n.cancel),
                  Text(context.l10n.connection_address_key('10.0.2.2:8642', '✓')),
                ],
              ),
            ),
            locale: _localeFor(code),
          ),
        );

        expect(find.text(l10n.cancel), findsOneWidget);
        expect(
          find.text(l10n.connection_address_key('10.0.2.2:8642', '✓')),
          findsOneWidget,
        );
      }
    });
  });
}
