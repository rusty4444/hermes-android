// Translation coverage for the issue-#232 strings.
//
// Every shipped catalogue must carry a real translation for each new key: the
// ARB value has to exist, render with its placeholders substituted, and — for
// non-English locales — differ from the English copy, so an untranslated
// fallback cannot slip through review.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';

const _sentinelPath = '/sentinel/path';
const _sentinelRoot = '/sentinel/root';
const _sentinelName = 'sentinel-name';
const _sentinelError = 'sentinel-error';

Map<String, String> _messages(AppLocalizations l10n) => {
  'projects_root_title': l10n.projects_root_title,
  'projects_root_more_subtitle': l10n.projects_root_more_subtitle,
  'projects_root_description': l10n.projects_root_description,
  'projects_root_label': l10n.projects_root_label,
  'projects_root_default_hint': l10n.projects_root_default_hint(_sentinelPath),
  'projects_root_locked_title': l10n.projects_root_locked_title,
  'projects_root_locked_explanation': l10n.projects_root_locked_explanation,
  'projects_root_saved': l10n.projects_root_saved,
  'projects_root_reset': l10n.projects_root_reset,
  'projects_root_invalid_empty': l10n.projects_root_invalid_empty,
  'projects_root_invalid_absolute': l10n.projects_root_invalid_absolute,
  'projects_root_invalid_segments': l10n.projects_root_invalid_segments,
  'projects_root_unsupported': l10n.projects_root_unsupported,
  'projects_root_unavailable': l10n.projects_root_unavailable,
  'adopt_folder_action': l10n.adopt_folder_action,
  'adopt_folder_description': l10n.adopt_folder_description(_sentinelRoot),
  'adopt_folder_registered': l10n.adopt_folder_registered(_sentinelName),
  'adopt_folder_none': l10n.adopt_folder_none,
  'adopt_folder_unsupported': l10n.adopt_folder_unsupported,
  'adopt_folder_failed': l10n.adopt_folder_failed(_sentinelError),
  'adopt_folder_manual_label': l10n.adopt_folder_manual_label,
  'adopt_folder_name_label': l10n.adopt_folder_name_label,
  'adopt_folder_add': l10n.adopt_folder_add,
  'adopt_folder_added': l10n.adopt_folder_added(_sentinelName, _sentinelPath),
  'adopt_folder_error': l10n.adopt_folder_error(_sentinelError),
  'adopt_folder_folderless': l10n.adopt_folder_folderless(_sentinelName),
};

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    final code = locale.toString();
    test('$code translates every #232 string, placeholders included', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final arb =
          jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync()) as Map;
      final english = _messages(
        await AppLocalizations.delegate.load(const Locale('en')),
      );
      final rendered = _messages(l10n);

      final keys = arb.keys.whereType<String>().where(
        (key) =>
            key.startsWith('projects_root_') || key.startsWith('adopt_folder_'),
      );
      expect(rendered.keys, unorderedEquals(keys));

      for (final entry in rendered.entries) {
        final translated = arb[entry.key] as String;
        expect(translated.trim(), isNotEmpty, reason: entry.key);
        expect(
          entry.value,
          translated
              .replaceAll('{path}', _sentinelPath)
              .replaceAll('{root}', _sentinelRoot)
              .replaceAll('{name}', _sentinelName)
              .replaceAll('{error}', _sentinelError),
          reason: entry.key,
        );
        if (locale.languageCode != 'en') {
          expect(
            entry.value,
            isNot(english[entry.key]),
            reason: '$code ${entry.key} must not fall back to English',
          );
        }
      }
    });
  }

  test('every shipped catalogue is covered by this test', () {
    final shipped =
        Directory('lib/l10n')
            .listSync()
            .map((entity) => entity.uri.pathSegments.last)
            .where((name) => name.startsWith('app_') && name.endsWith('.arb'))
            .map((name) => name.substring(4, name.length - 4))
            .toList()
          ..sort();
    final supported =
        AppLocalizations.supportedLocales
            .map((locale) => locale.toString())
            .toList()
          ..sort();
    expect(supported, shipped);
  });
}
