// Localization coverage for the Crons Upcoming/History split (issue #259).
//
// Generated getters can silently fall back to English when a non-English ARB
// omits a key, so every shipped locale is checked for real, distinct copy —
// including the regional/script variants (pt_BR, zh_Hans) — and placeholders
// are checked to survive substitution.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_test_utils.dart';

const _shippedLocales = [
  'de',
  'es',
  'fr',
  'ja',
  'ko',
  'pt',
  'pt_BR',
  'ru',
  'uk',
  'zh',
  'zh_Hans',
];

// `crons` itself is deliberately not here: the destination label predates
// this change and is still English in the non-English catalogues, because the
// navigation bar enforces a very short one-line label at 1.3x text scale
// (see hermes_shell_test) and the natural translations do not fit.
const _newKeys = [
  'cron_schedule_timezone',
  'crons_upcoming',
  'crons_history',
  'cron_time_with_zone',
  'cron_time_zone_unknown',
  'cron_no_next_run',
  'cron_status_scheduled',
  'cron_status_paused',
  'cron_delivers_to',
  'cron_upcoming_empty_title',
  'cron_upcoming_empty_message',
  'cron_upcoming_unavailable',
  'cron_upcoming_needs_dashboard',
  'cron_upcoming_needs_dashboard_auth',
  'cron_upcoming_dashboard_unreachable',
  'cron_upcoming_load_failed',
  'cron_upcoming_refresh_failed',
];

/// Keys whose value is punctuation around placeholders, so matching the
/// English template is correct rather than an untranslated copy. CJK
/// catalogues still localize it (full-width brackets), which the generated
/// accessor tests below exercise.
const _formatOnlyKeys = {'cron_time_with_zone'};

Locale _localeFor(String code) {
  final parts = code.split('_');
  if (parts.length != 2) return Locale(code);
  final subtag = parts[1];
  return subtag.length == 4
      ? Locale.fromSubtags(languageCode: parts[0], scriptCode: subtag)
      : Locale.fromSubtags(languageCode: parts[0], countryCode: subtag);
}

Map<String, Object?> _arb(String code) {
  final file = File('lib/l10n/app_$code.arb');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

void main() {
  test('every shipped ARB carries the new cron keys with placeholders', () {
    final english = _arb('en');
    for (final code in ['en', ..._shippedLocales]) {
      final catalogue = _arb(code);
      for (final key in _newKeys) {
        final value = catalogue[key];
        expect(
          value,
          isA<String>(),
          reason: '$key is missing from app_$code.arb',
        );
        expect(
          (value as String).trim(),
          isNotEmpty,
          reason: '$key is empty in app_$code.arb',
        );
        // Placeholders must survive translation or the generated accessor
        // drops the value it was given.
        for (final placeholder in RegExp(
          r'\{(\w+)\}',
        ).allMatches(english[key] as String).map((m) => m.group(0)!)) {
          expect(
            value,
            contains(placeholder),
            reason: '$key lost $placeholder in app_$code.arb',
          );
        }
        if (code != 'en' && !_formatOnlyKeys.contains(key)) {
          expect(
            value,
            isNot(english[key]),
            reason: '$key is an untranslated English copy in app_$code.arb',
          );
        }
      }
    }
  });

  group('generated accessors', () {
    for (final code in _shippedLocales) {
      test('$code renders the cron schedule copy translated', () async {
        final l10n = await loadTestL10n(_localeFor(code));
        final en = await loadTestL10n(const Locale('en'));

        expect(l10n.crons_upcoming, isNotEmpty);
        expect(l10n.crons_upcoming, isNot(en.crons_upcoming));
        expect(l10n.crons_history, isNot(en.crons_history));
        expect(l10n.cron_no_next_run, isNot(en.cron_no_next_run));
        expect(
          l10n.cron_upcoming_needs_dashboard,
          isNot(en.cron_upcoming_needs_dashboard),
        );
        expect(
          l10n.cron_upcoming_empty_title,
          isNot(en.cron_upcoming_empty_title),
        );

        final zoned = l10n.cron_time_with_zone('2026-11-09 09:00', 'UTC+11:00');
        expect(zoned, contains('2026-11-09 09:00'));
        expect(zoned, contains('UTC+11:00'));

        final unknown = l10n.cron_time_zone_unknown('2026-11-09 09:00');
        expect(unknown, contains('2026-11-09 09:00'));
        expect(
          unknown,
          isNot(en.cron_time_zone_unknown('2026-11-09 09:00')),
          reason: 'the unknown-zone notice must be translated',
        );

        final target = l10n.cron_delivers_to('telegram:42');
        expect(target, contains('telegram:42'));
      });
    }
  });
}
