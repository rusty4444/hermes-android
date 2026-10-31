import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/provider_oauth.dart';
import 'package:hermes_android/core/screens/provider_oauth_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/more_pane.dart';

import 'provider_oauth_test.dart' show OAuthDashboard, connection;

Map<String, String> messages(AppLocalizations l10n) => {
  'provider_oauth_title': l10n.provider_oauth_title,
  'provider_oauth_more_subtitle': l10n.provider_oauth_more_subtitle,
  'provider_oauth_settings_subtitle': l10n.provider_oauth_settings_subtitle,
  'provider_oauth_intro': l10n.provider_oauth_intro,
  'provider_oauth_defaults_notice': l10n.provider_oauth_defaults_notice,
  'provider_oauth_transport_init_failed':
      l10n.provider_oauth_transport_init_failed,
  'provider_oauth_https_required': l10n.provider_oauth_https_required,
  'provider_oauth_auth_required': l10n.provider_oauth_auth_required,
  'provider_oauth_catalog_failed': l10n.provider_oauth_catalog_failed,
  'provider_oauth_expired': l10n.provider_oauth_expired,
  'provider_oauth_start_failed': l10n.provider_oauth_start_failed,
  'provider_oauth_checking_account': l10n.provider_oauth_checking_account,
  'provider_oauth_verification_unavailable':
      l10n.provider_oauth_verification_unavailable,
  'provider_oauth_verified_account': l10n.provider_oauth_verified_account(
    'sentinel-email',
  ),
  'provider_oauth_credentials_unverified':
      l10n.provider_oauth_credentials_unverified,
  'provider_oauth_account_status_unknown':
      l10n.provider_oauth_account_status_unknown,
  'provider_oauth_denied': l10n.provider_oauth_denied,
  'provider_oauth_cancelled': l10n.provider_oauth_cancelled,
  'provider_oauth_host_failed': l10n.provider_oauth_host_failed,
  'provider_oauth_poll_failed': l10n.provider_oauth_poll_failed,
  'provider_oauth_cancellation_unconfirmed': l10n
      .provider_oauth_cancellation_unconfirmed('sentinel-message'),
  'provider_oauth_browser_failed': l10n.provider_oauth_browser_failed,
  'provider_oauth_retry': l10n.provider_oauth_retry,
  'provider_oauth_complete': l10n.provider_oauth_complete('sentinel-provider'),
  'provider_oauth_code_instruction': l10n.provider_oauth_code_instruction,
  'provider_oauth_waiting': l10n.provider_oauth_waiting,
  'provider_oauth_open_browser': l10n.provider_oauth_open_browser,
  'provider_oauth_cancel': l10n.provider_oauth_cancel,

  'provider_oauth_signed_out': l10n.provider_oauth_signed_out,
  'provider_oauth_sign_in_again': l10n.provider_oauth_sign_in_again,
  'provider_oauth_sign_in': l10n.provider_oauth_sign_in,
  'provider_oauth_cli_required': l10n.provider_oauth_cli_required,
};

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    final code = locale.toString();
    test(
      '$code has every actual OAuth translation, including placeholders',
      () async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final arb =
            jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync())
                as Map;
        final english = messages(
          await AppLocalizations.delegate.load(const Locale('en')),
        );
        final rendered = messages(l10n);
        final keys = arb.keys.whereType<String>().where(
          (key) => key.startsWith('provider_oauth_'),
        );
        expect(rendered.keys, unorderedEquals(keys));
        for (final entry in rendered.entries) {
          final translated = arb[entry.key] as String;
          expect(translated.trim(), isNotEmpty, reason: entry.key);
          expect(
            entry.value,
            translated
                .replaceAll('{provider}', 'sentinel-provider')
                .replaceAll('{email}', 'sentinel-email')
                .replaceAll('{message}', 'sentinel-message'),
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
        final entry = buildMoreSections(dashboardReachable: true, l10n: l10n)
            .expand((section) => section.entries)
            .singleWhere((entry) => entry.id == 'provider-sign-in');
        expect(entry.title, l10n.provider_oauth_title);
        expect(entry.subtitle, l10n.provider_oauth_more_subtitle);
      },
    );

    testWidgets(
      '$code renders consent, CLI explanation, session and safe failures',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final client = OAuthDashboard();
        final l10n = await AppLocalizations.delegate.load(locale);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProviderOAuthScreen(
              connection: connection,
              dashboardClient: client,
              openBrowser: (_) async => false,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.provider_oauth_title), findsOneWidget);
        expect(find.text(l10n.provider_oauth_intro), findsOneWidget);
        expect(find.text(l10n.provider_oauth_defaults_notice), findsOneWidget);
        expect(find.text(l10n.provider_oauth_cli_required), findsOneWidget);
        client.failStart = true;
        await tester.tap(find.text(l10n.provider_oauth_sign_in).first);
        await tester.pumpAndSettle();
        expect(find.text(l10n.provider_oauth_start_failed), findsOneWidget);
        expect(find.textContaining('secret start'), findsNothing);
        client.failStart = false;
        await tester.tap(find.text(l10n.provider_oauth_sign_in).first);
        await tester.pump();
        expect(
          find.text(l10n.provider_oauth_complete('Codex')),
          findsOneWidget,
        );
        expect(find.text(l10n.provider_oauth_code_instruction), findsOneWidget);
        expect(find.text(l10n.provider_oauth_waiting), findsOneWidget);
        await tester.tap(find.text(l10n.provider_oauth_open_browser));
        await tester.pump();
        expect(find.text(l10n.provider_oauth_browser_failed), findsOneWidget);
        client.failCancel = true;
        await tester.tap(find.text(l10n.provider_oauth_cancel));
        await tester.pumpAndSettle();
        expect(
          find.text(
            l10n.provider_oauth_cancellation_unconfirmed(
              l10n.provider_oauth_cancelled,
            ),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('secret cancel'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );

    for (final providerId in ['nous', 'openai-codex']) {
      testWidgets(
        '$code renders unverified $providerId approval in the selected locale',
        (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final client = OAuthDashboard()
            ..providerId = providerId
            ..status = 'approved'
            ..accountEmail = 'account@example.test'
            ..readbackEmail = 'account@example.test'
            ..heldCatalog = null;
          final l10n = await AppLocalizations.delegate.load(locale);
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ProviderOAuthScreen(
                connection: connection,
                dashboardClient: client,
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.provider_oauth_sign_in).first);
          await tester.pump();
          client.loggedIn = true;
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
          expect(
            find.text(l10n.provider_oauth_verification_unavailable),
            findsOneWidget,
          );
          expect(
            find.text(l10n.provider_oauth_credentials_unverified),
            findsOneWidget,
          );
          expect(
            find.text(
              l10n.provider_oauth_verified_account('account@example.test'),
            ),
            findsNothing,
          );
          expect(find.textContaining('account@example.test'), findsNothing);
          expect(client.polls, 1);
          expect(client.cancels, 0);
          expect(client.inventories, 0);
          expect(client.usages, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          client.close();
        },
      );
    }

    for (final reason in OAuthTransportUnavailableReason.values) {
      testWidgets('$code localises transport reason ${reason.name}', (
        tester,
      ) async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final client = DashboardClient(
          host: 'remote.test',
          useHttps:
              reason == OAuthTransportUnavailableReason.authenticationRequired,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProviderOAuthScreen(
              connection: connection,
              dashboardClient: client,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            reason == OAuthTransportUnavailableReason.httpsRequired
                ? l10n.provider_oauth_https_required
                : l10n.provider_oauth_auth_required,
          ),
          findsOneWidget,
        );
        expect(find.text(l10n.provider_oauth_retry), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        client.close();
      });
    }
  }
}
