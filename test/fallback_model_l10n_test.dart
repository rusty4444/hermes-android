import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/widgets/fallback_models.dart';

import 'support/fallback_model_fixture.dart';
import 'support/l10n_test_utils.dart';

Map<String, String> values(AppLocalizations l) => {
  'fallback_title': l.fallback_title,
  'fallback_notice': l.fallback_notice,
  'fallback_unavailable': l.fallback_unavailable,
  'fallback_discovery_unavailable': l.fallback_discovery_unavailable,
  'fallback_empty': l.fallback_empty,
  'fallback_incomplete': l.fallback_incomplete,
  'fallback_add': l.fallback_add,
  'fallback_save': l.fallback_save,
  'fallback_save_failed': l.fallback_save_failed,
  'fallback_saved': l.fallback_saved,
  'fallback_legacy_title': l.fallback_legacy_title,
  'fallback_legacy_notice': l.fallback_legacy_notice,
  'fallback_priority': l.fallback_priority('SENTINEL'),
  'fallback_move_up': l.fallback_move_up,
  'fallback_move_down': l.fallback_move_down,
  'fallback_routing_read_only': l.fallback_routing_read_only,
};
void main() {
  final english =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
  for (final locale in AppLocalizations.supportedLocales) {
    final id = [
      locale.languageCode,
      ?locale.scriptCode,
      ?locale.countryCode,
    ].join('_');
    test(
      'every fallback key has explicit, generated-matching translation in $id',
      () async {
        final arb =
            jsonDecode(File('lib/l10n/app_$id.arb').readAsStringSync()) as Map;
        final actual = values(await loadTestL10n(locale));
        expect(actual.length, 16);
        for (final entry in actual.entries) {
          expect(
            arb.containsKey(entry.key),
            isTrue,
            reason: '$id ${entry.key}',
          );
          final text = arb[entry.key] as String;
          expect(text.trim(), isNotEmpty);
          if (id != 'en') {
            expect(text, isNot(english[entry.key]), reason: '$id ${entry.key}');
          }
          expect(entry.value, text.replaceAll('{position}', 'SENTINEL'));
        }
        expect(arb['fallback_priority'], contains('{position}'));
      },
    );
    testWidgets(
      '$id unavailable/retry and legacy warnings render translated, without server secrets',
      (tester) async {
        final fixture = FallbackFixture()..configStatus = 404;
        addTearDown(fixture.client.close);
        final l10n = await loadTestL10n(locale);
        await tester.pumpWidget(
          testAppWithL10n(
            Scaffold(
              body: SingleChildScrollView(
                child: FallbackModels(client: fixture.client),
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.fallback_unavailable), findsOneWidget);
        expect(find.textContaining('never-show-server-secret'), findsNothing);
        fixture.configStatus = 200;
        fixture.config['fallback_model'] = {
          'provider': 'legacy',
          'model': 'old',
        };
        await tester.ensureVisible(
          find.byKey(const ValueKey('fallback-retry')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('fallback-retry')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.fallback_legacy_notice), findsOneWidget);
        expect(find.text(l10n.fallback_empty), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
