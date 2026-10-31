import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/l10n/l10n.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/models/provider_account_usage.dart';
import 'package:hermes_android/core/screens/provider_usage_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/l10n_test_utils.dart';

final connection = SavedConnection(
  id: 'quota-test',
  label: 'Test',
  host: 'example.test',
  port: 8642,
  apiKey: '',
);

Map<String, dynamic> window(
  dynamic used, {
  String label = 'Weekly',
  String scope = 'account',
  dynamic reset = '2026-11-08T03:00:00Z',
}) => {
  'label': label,
  'scope': scope,
  'used_percent': used,
  'resets_at': reset,
};

Map<String, dynamic> options(
  Map<String, dynamic> usage, {
  String slug = 'openai-codex',
}) => {
  'providers': [
    {'slug': slug, 'usage': usage},
  ],
};

class QuotaDashboard extends DashboardClient {
  QuotaDashboard() : super(host: 'example.test', proxied: true);
  Map<String, dynamic> inventory = options({
    'windows': [window(25)],
  });
  Map<String, dynamic> analytics = {
    'models': [
      {'provider': 'openai', 'model': 'api-model'},
      {'provider': 'openai-codex', 'model': 'codex-model'},
      {'provider': 'anthropic', 'model': 'claude-model'},
      {'provider': 'openai-codex-other', 'model': 'wrong-model'},
    ],
  };
  bool failAnalytics = false;
  bool failQuota = false;
  int analyticsReads = 0;
  int quotaReads = 0;
  int closes = 0;
  Completer<Map<String, dynamic>>? heldAnalytics;
  Completer<Map<String, dynamic>>? heldQuota;

  @override
  Future<Map<String, dynamic>> getModelsAnalytics({int days = 30}) async {
    analyticsReads++;
    if (heldAnalytics != null) return heldAnalytics!.future;
    if (failAnalytics) throw StateError('private analytics detail');
    return analytics;
  }

  @override
  Future<Map<String, dynamic>> getModelOptions() async {
    quotaReads++;
    if (heldQuota != null) return heldQuota!.future;
    if (failQuota) throw StateError('private quota detail');
    return inventory;
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

Widget screen(
  QuotaDashboard client, {
  String provider = 'openai',
  SavedConnection? selected,
}) => testAppWithL10n(
  ProviderUsageScreen(
    connection: selected ?? connection,
    providerId: provider,
    title: 'Usage',
    dashboardClient: client,
  ),
);

void main() {
  group('provider subscription contract', () {
    test('exact subscription slug, never paid API usage or fuzzy aliases', () {
      final api = options({
        'windows': [window(1)],
      }, slug: 'openai');
      expect(ProviderSubscriptionUsage.fromModelOptions(api, 'openai'), isNull);
      for (final slug in ['OpenAI-Codex', 'codex', 'openai-codex-other']) {
        expect(
          ProviderSubscriptionUsage.fromModelOptions(
            options({
              'windows': [window(1)],
            }, slug: slug),
            'openai',
          ),
          isNull,
        );
      }
      final inventory = options({
        'windows': [window(25)],
      });
      for (final id in ['openai', 'openai-codex']) {
        final quota = ProviderSubscriptionUsage.fromModelOptions(
          inventory,
          id,
        )!;
        expect(quota.provider, 'openai-codex');
        expect(quota.windows.single.remainingPercent, 75);
      }
      expect(subscriptionUsageProvider('claude'), isNull);
      expect(
        ProviderSubscriptionUsage.fromModelOptions(inventory, 'anthropic'),
        isNull,
      );
    });

    test(
      'weekly-only Claude preserves labels and model scope without inventing windows',
      () {
        final quota = ProviderSubscriptionUsage.fromModelOptions(
          options({
            'windows': [window(100, label: 'Opus week', scope: 'model')],
          }, slug: 'anthropic'),
          'anthropic',
        )!;
        expect(quota.windows.single.label, 'Opus week');
        expect(quota.windows.single.scope, 'model');
        expect(quota.windows.single.remainingPercent, 0);
        expect(quota.accounts, isEmpty);
        expect(quota.windows.single.resetsAt, DateTime.utc(2026, 11, 8, 3));
      },
    );

    test(
      'unknown and non-finite percentages stay unknown, finite values clamp',
      () {
        for (final value in [
          null,
          '25',
          true,
          double.nan,
          double.infinity,
          double.negativeInfinity,
        ]) {
          final parsed = ProviderUsageWindow.parse(window(value))!;
          expect(parsed.usedPercent, isNull);
          expect(parsed.remainingPercent, isNull);
          expect(parsed.resetsAt, isNotNull);
        }
        expect(ProviderUsageWindow.parse(window(-10))!.remainingPercent, 100);
        expect(ProviderUsageWindow.parse(window(120))!.remainingPercent, 0);
        expect(ProviderUsageWindow.parse(window(0))!.usedPercent, 0);
        expect(ProviderUsageWindow.parse(window(12.5))!.remainingPercent, 87.5);
        expect(ProviderUsageWindow.parse({'used_percent': 0}), isNull);
      },
    );

    test('invalid resets do not hide valid percentages', () {
      for (final reset in [
        null,
        1700000000,
        'bad',
        '2026-11-08',
        '2026-02-30T03:00:00Z',
        '2026-13-08T03:00:00Z',
        '2026-11-08T27:00:00Z',
        '2026-11-08T03:00:00+25:00',
        '2026-11-08T03:00:00+02:70',
      ]) {
        final parsed = ProviderUsageWindow.parse(window(25, reset: reset))!;
        expect(parsed.remainingPercent, 75);
        expect(parsed.resetsAt, isNull);
      }
      expect(
        ProviderUsageWindow.parse(
          window(25, reset: '2026-11-08T05:00:00+02:00'),
        )!.resetsAt,
        DateTime.utc(2026, 11, 8, 3),
      );
    });

    test('accounts take precedence without averaging or outer windows', () {
      final quota = ProviderSubscriptionUsage.fromModelOptions(
        options({
          'windows': [window(50)],
          'accounts': [
            {
              'id': 'a',
              'label': 'Work',
              'state': 'ready',
              'windows': [window(10)],
            },
            {
              'id': 'b',
              'label': 'Personal',
              'state': 'limited',
              'resets_at': '2026-11-08T03:00:00Z',
              'windows': [window(100, scope: 'model', label: 'Opus week')],
            },
            {'id': 'c', 'state': 'unavailable'},
          ],
        }),
        'openai',
      )!;
      expect(quota.hasAccounts, isTrue);
      expect(quota.windows, isEmpty);
      expect(quota.accounts.map((a) => a.id), ['a', 'b', 'c']);
      expect(quota.accounts.first.state, 'ready');
      expect(quota.accounts[1].windows.single.usedPercent, 100);
      expect(quota.accounts[1].resetsAt, isNotNull);
      expect(quota.accounts.last.windows, isEmpty);
      for (final raw in [[], 'invalid', null]) {
        final empty = ProviderSubscriptionUsage.fromModelOptions(
          options({
            'accounts': raw,
            'windows': [window(50)],
          }),
          'openai',
        )!;
        expect(empty.accounts, isEmpty);
        expect(empty.windows, isEmpty);
      }
    });

    test('missing and malformed inventory never synthesize allowance', () {
      for (final raw in <Map<String, dynamic>>[
        {},
        {'providers': null},
        {'providers': {}},
        {
          'providers': [
            {'slug': 'openai-codex', 'usage': null},
          ],
        },
      ]) {
        expect(
          ProviderSubscriptionUsage.fromModelOptions(raw, 'openai'),
          isNull,
        );
      }
      for (final raw in [
        null,
        {},
        'bad',
        [null, {}, 3],
      ]) {
        final quota = ProviderSubscriptionUsage.fromModelOptions(
          options({'windows': raw}),
          'openai',
        )!;
        expect(quota.windows, isEmpty);
      }
    });

    test(
      'analytics include exact API and Codex rows but not fuzzy aliases',
      () {
        final rows = providerUsageRows(QuotaDashboard().analytics, 'openai');
        expect(rows.map((r) => r['model']), ['api-model', 'codex-model']);
        expect(
          providerUsageRows({
            'models': [
              {'provider': 'openai', 'model': 'api'},
            ],
          }, 'openai-codex'),
          isEmpty,
        );
      },
    );
  });

  testWidgets('quota and API analytics are separate; refresh is manual only', (
    tester,
  ) async {
    // Keep both independent sections built despite the explanatory copy.
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = QuotaDashboard();
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(find.text('25.0% used · 75.0% remaining'), findsOneWidget);
    expect(
      find.textContaining('five-hour session and weekly limits'),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp('daily', caseSensitive: false)),
      findsNothing,
    );
    expect(find.text('api-model'), findsOneWidget);
    expect(find.text('codex-model'), findsOneWidget);
    expect(find.text('OpenAI API recorded usage'), findsOneWidget);
    expect(find.text('wrong-model'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.pump(const Duration(minutes: 5));
    expect(client.quotaReads, 1);
    expect(client.analyticsReads, 1);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(client.quotaReads, 2);
    await tester.pumpWidget(const SizedBox());
    expect(client.closes, 0);
    client.close();
  });

  test('subscription copy describes supported windows in every locale', () async {
    // Exact translated copy protects five-hour/weekly semantics without
    // requiring English words in non-English locales or accepting fallback.
    const expected = <String, (String, String)>{
      "en": (
        "Codex and Claude subscriptions use five-hour session and weekly limits. Only provider-reported windows are shown; missing limits and reset times remain unavailable. Weekly limits may apply to the account or specific models.",
        "5-hour session",
      ),
      "de": (
        "Für Codex- und Claude-Abonnements gelten Limits pro Fünf-Stunden-Sitzung und pro Woche. Es werden nur vom Anbieter gemeldete Zeiträume angezeigt; fehlende Limits und Rücksetzzeiten bleiben nicht verfügbar. Wochenlimits können für das Konto oder bestimmte Modelle gelten.",
        "5-Stunden-Sitzung",
      ),
      "es": (
        "Las suscripciones a Codex y Claude tienen límites por sesión de cinco horas y por semana. Solo se muestran los periodos informados por el proveedor; los límites y las horas de restablecimiento no informados siguen sin estar disponibles. Los límites semanales pueden aplicarse a la cuenta o a modelos específicos.",
        "Sesión de 5 horas",
      ),
      "fr": (
        "Les abonnements Codex et Claude ont des limites par session de cinq heures et par semaine. Seules les périodes indiquées par le fournisseur sont affichées ; les limites et les heures de réinitialisation non communiquées restent indisponibles. Les limites hebdomadaires peuvent s’appliquer au compte ou à certains modèles.",
        "Session de 5 heures",
      ),
      "ja": (
        "Codex と Claude のサブスクリプションには、5時間のセッション単位と週単位の上限があります。プロバイダーが報告した利用枠のみを表示し、報告されていない上限やリセット時刻は表示できません。週単位の上限は、アカウント全体または特定のモデルに適用される場合があります。",
        "5時間のセッション",
      ),
      "ko": (
        "Codex 및 Claude 구독에는 5시간 세션별 한도와 주간 한도가 있습니다. 제공업체가 보고한 구간만 표시되며, 보고되지 않은 한도와 초기화 시간은 확인할 수 없습니다. 주간 한도는 계정 전체 또는 특정 모델에 적용될 수 있습니다.",
        "5시간 세션",
      ),
      "pt": (
        "As subscrições do Codex e do Claude têm limites por sessão de cinco horas e por semana. Apenas são apresentados os períodos comunicados pelo fornecedor; os limites e as horas de reposição não comunicados continuam indisponíveis. Os limites semanais podem aplicar-se à conta ou a modelos específicos.",
        "Sessão de 5 horas",
      ),
      "pt_BR": (
        "As assinaturas do Codex e do Claude têm limites por sessão de cinco horas e por semana. Apenas os períodos informados pelo provedor são exibidos; os limites e os horários de redefinição não informados continuam indisponíveis. Os limites semanais podem se aplicar à conta ou a modelos específicos.",
        "Sessão de 5 horas",
      ),
      "ru": (
        "Для подписок Codex и Claude действуют лимиты на пятичасовой сеанс и на неделю. Отображаются только периоды, указанные провайдером; отсутствующие лимиты и время сброса остаются недоступными. Недельные лимиты могут относиться ко всему аккаунту или к отдельным моделям.",
        "5-часовой сеанс",
      ),
      "zh": (
        "Codex 和 Claude 订阅设有五小时会话限额和每周限额。仅显示提供商报告的周期；未报告的限额和重置时间仍不可用。每周限额可能适用于整个账户或特定模型。",
        "5小时会话",
      ),
      "zh_Hans": (
        "Codex 和 Claude 订阅设有五小时会话限额和每周限额。仅显示提供商报告的周期；未报告的限额和重置时间仍不可用。每周限额可能适用于整个账户或特定模型。",
        "5小时会话",
      ),
    };
    expect(
      AppLocalizations.supportedLocales.map((locale) => locale.toString()),
      unorderedEquals(expected.keys),
    );
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await loadTestL10n(locale);
      final copy = expected[locale.toString()]!;
      expect(l10n.provider_quota_windows_notice, isNotEmpty);
      expect(l10n.provider_quota_windows_notice, copy.$1);
      expect(l10n.provider_quota_five_hour_session, isNotEmpty);
      expect(l10n.provider_quota_five_hour_session, copy.$2);
    }
  });

  test('all shipped ARBs explicitly translate every quota key', () {
    final english =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final keys = english.keys.where((key) => key.startsWith('provider_quota_'));
    for (final locale in AppLocalizations.supportedLocales) {
      final arb =
          jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final key in keys) {
        final value = arb[key];
        expect(value, isA<String>(), reason: '$locale: $key');
        expect((value as String).trim(), isNotEmpty, reason: '$locale: $key');
        if (locale.languageCode != 'en') {
          expect(value, isNot(english[key]), reason: '$locale: $key fallback');
        }
        final placeholders = RegExp(r'\{([^{}]+)\}');
        expect(
          placeholders.allMatches(value).map((match) => match[1]),
          unorderedEquals(
            placeholders
                .allMatches(english[key] as String)
                .map((match) => match[1]),
          ),
          reason: '$locale: $key placeholders',
        );
        if (english.containsKey('@$key')) {
          expect(
            arb['@$key'],
            english['@$key'],
            reason: '$locale: $key metadata',
          );
        }
      }
    }
  });

  for (final provider in ['openai-codex', 'anthropic']) {
    final sessionLabel = provider == 'openai-codex'
        ? 'Session'
        : 'Current session';
    final weeklyLabel = provider == 'openai-codex' ? 'Weekly' : 'Current week';
    testWidgets('$provider shows confirmed five-hour and weekly windows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = QuotaDashboard()
        ..inventory = options({
          'windows': [
            window(25, label: sessionLabel, reset: null),
            window(50, label: weeklyLabel),
            window(100, label: 'Opus week', scope: 'model'),
          ],
        }, slug: provider);
      await tester.pumpWidget(screen(client, provider: provider));
      await tester.pumpAndSettle();
      expect(find.text('5-hour session'), findsOneWidget);
      expect(find.text(sessionLabel), findsNothing);
      expect(find.text(weeklyLabel), findsOneWidget);
      expect(find.text('Opus week'), findsOneWidget);
      expect(find.text('Scope: model'), findsOneWidget);
      expect(find.text('Reset time unavailable.'), findsOneWidget);
      expect(
        find.textContaining('Resets: 2026-11-08T03:00:00.000Z'),
        findsNWidgets(2),
      );
      expect(
        find.textContaining(RegExp('daily', caseSensitive: false)),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      client.close();
    });

    testWidgets(
      '$provider preserves unknown and other-provider session labels',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final otherSession = provider == 'openai-codex'
            ? 'Current session'
            : 'Session';
        final client = QuotaDashboard()
          ..inventory = options({
            'windows': [
              window(20, label: 'Custom rolling window', reset: null),
              window(30, label: otherSession, reset: null),
              window(40, label: 'session', reset: null),
            ],
          }, slug: provider);
        await tester.pumpWidget(screen(client, provider: provider));
        await tester.pumpAndSettle();
        expect(find.text('Custom rolling window'), findsOneWidget);
        expect(find.text(otherSession), findsOneWidget);
        expect(find.text('session'), findsOneWidget);
        expect(find.text('5-hour session'), findsNothing);
        expect(find.text('Reset time unavailable.'), findsNWidgets(3));
        expect(find.textContaining('Resets:'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        client.close();
      },
    );

    testWidgets('$provider weekly-only data never invents a session window', (
      tester,
    ) async {
      final client = QuotaDashboard()
        ..inventory = options({
          'windows': [window(15, label: weeklyLabel, reset: null)],
        }, slug: provider);
      await tester.pumpWidget(screen(client, provider: provider));
      await tester.pumpAndSettle();
      expect(find.text(weeklyLabel), findsOneWidget);
      expect(find.text('5-hour session'), findsNothing);
      expect(find.text('15.0% used · 85.0% remaining'), findsOneWidget);
      expect(find.text('Reset time unavailable.'), findsOneWidget);
      expect(find.textContaining('Resets:'), findsNothing);
      expect(
        find.textContaining(RegExp('daily', caseSensitive: false)),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      client.close();
    });
  }

  testWidgets('cache-empty inventory is populated on explicit refresh', (
    tester,
  ) async {
    final client = QuotaDashboard()..inventory = options({});
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(find.text('Subscription allowance unavailable.'), findsOneWidget);
    expect(find.textContaining('% remaining'), findsNothing);
    expect(find.text('5-hour session'), findsNothing);
    expect(find.textContaining('Resets:'), findsNothing);
    client.inventory = options({
      'windows': [window(0)],
    });
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('0.0% used · 100.0% remaining'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('quota displays while analytics fails and conversely', (
    tester,
  ) async {
    final client = QuotaDashboard()..failAnalytics = true;
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    expect(find.text('25.0% used · 75.0% remaining'), findsOneWidget);
    expect(find.text('Could not load recorded usage.'), findsOneWidget);
    client.failAnalytics = false;
    client.failQuota = true;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('api-model'), findsOneWidget);
    expect(
      find.textContaining('Could not refresh subscription'),
      findsOneWidget,
    );
    expect(find.text('25.0% used · 75.0% remaining'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
    'initial quota failure does not hide analytics or report full allowance',
    (tester) async {
      final client = QuotaDashboard()..failQuota = true;
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      expect(find.text('api-model'), findsOneWidget);
      expect(find.textContaining('% remaining'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets('held analytics does not block subscription rendering', (
    tester,
  ) async {
    final client = QuotaDashboard()..heldAnalytics = Completer();
    await tester.pumpWidget(screen(client));
    await tester.pump();
    await tester.pump();
    expect(find.text('25.0% used · 75.0% remaining'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    client.heldAnalytics!.complete({'models': []});
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('held subscription does not block analytics rendering', (
    tester,
  ) async {
    final client = QuotaDashboard()..heldQuota = Completer();
    await tester.pumpWidget(screen(client));
    await tester.pump();
    await tester.pump();
    expect(find.text('api-model'), findsOneWidget);
    client.heldQuota!.complete(
      options({
        'windows': [window(25)],
      }),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('both failures retain previously loaded analytics and quota', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = QuotaDashboard();
    await tester.pumpWidget(screen(client));
    await tester.pumpAndSettle();
    client.failAnalytics = true;
    client.failQuota = true;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('api-model'), findsOneWidget);
    expect(find.text('25.0% used · 75.0% remaining'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
    'profile and provider replacement reject stale analytics and quota',
    (tester) async {
      final old = QuotaDashboard()
        ..heldQuota = Completer()
        ..heldAnalytics = Completer();
      final fresh = QuotaDashboard()
        ..inventory = options({
          'windows': [window(12, label: 'Current week')],
        }, slug: 'anthropic');
      await tester.pumpWidget(screen(old));
      await tester.pump();
      await tester.pumpWidget(
        screen(
          fresh,
          provider: 'anthropic',
          selected: connection.copyWith(gatewayProfile: 'other'),
        ),
      );
      await tester.pumpAndSettle();
      old.heldQuota!.complete(
        options({
          'windows': [window(99, label: 'Stale')],
        }),
      );
      old.heldAnalytics!.complete({
        'models': [
          {'provider': 'anthropic', 'model': 'stale-model'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Current week'), findsOneWidget);
      expect(find.text('12.0% used · 88.0% remaining'), findsOneWidget);
      expect(find.text('Stale'), findsNothing);
      expect(find.text('stale-model'), findsNothing);
      expect(find.text('api-model'), findsNothing);
      expect(find.text('claude-model'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(old.closes, 0);
      expect(fresh.closes, 0);
      old.close();
      fresh.close();
    },
  );

  testWidgets(
    'late quota and analytics completion after disposal are ignored',
    (tester) async {
      final client = QuotaDashboard()
        ..heldQuota = Completer()
        ..heldAnalytics = Completer();
      await tester.pumpWidget(screen(client));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      client.heldQuota!.completeError(StateError('private error'));
      client.heldAnalytics!.complete({'models': []});
      await tester.pump();
      expect(tester.takeException(), isNull);
      client.close();
    },
  );

  testWidgets(
    'multi-account windows preserve model scope and explicit account state',
    (tester) async {
      final client = QuotaDashboard()
        ..inventory = options({
          'windows': [window(50, label: 'Wrong aggregate')],
          'accounts': [
            {
              'id': 'a',
              'label': 'Work',
              'state': 'ready',
              'windows': [window(100, scope: 'model', label: 'Opus week')],
            },
            {
              'id': 'b',
              'label': 'Personal',
              'state': 'limited',
              'windows': [window(10, label: 'Current session')],
            },
          ],
        }, slug: 'anthropic');
      await tester.pumpWidget(screen(client, provider: 'anthropic'));
      await tester.pumpAndSettle();
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Account state: ready'), findsOneWidget);
      expect(find.text('Account state: limited'), findsOneWidget);
      expect(find.text('Scope: model'), findsOneWidget);
      expect(find.text('100.0% used · 0.0% remaining'), findsOneWidget);
      expect(find.text('10.0% used · 90.0% remaining'), findsOneWidget);
      expect(find.text('5-hour session'), findsOneWidget);
      expect(find.text('Opus week'), findsOneWidget);
      expect(find.text('Wrong aggregate'), findsNothing);
      expect(find.textContaining('50.0% used'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets(
    'invalid percent and reset render independently without fake zero',
    (tester) async {
      final client = QuotaDashboard()
        ..inventory = options({
          'windows': [
            window(null, label: 'Session'),
            window(15, reset: 'invalid'),
          ],
        });
      await tester.pumpWidget(screen(client));
      await tester.pumpAndSettle();
      expect(find.text('Subscription allowance unavailable.'), findsOneWidget);
      expect(find.textContaining('Resets: 2026'), findsOneWidget);
      expect(find.text('Reset time unavailable.'), findsOneWidget);
      expect(find.text('15.0% used · 85.0% remaining'), findsOneWidget);
      expect(find.textContaining('100.0% remaining'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );

  testWidgets('translated quota fits narrow large text in Japanese', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = QuotaDashboard();
    await tester.pumpWidget(
      testAppWithL10n(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ProviderUsageScreen(
            connection: connection,
            providerId: 'openai',
            title: 'Usage',
            dashboardClient: client,
          ),
        ),
        locale: const Locale('ja'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('invalid mTLS identity fails closed and safely retries quota', (
    tester,
  ) async {
    final invalid = connection.copyWith(
      useHttps: true,
      clientCertificate: const ClientCertificateConfig(
        label: 'Synthetic',
        certificatePemPath: 'test/fixtures/nonexistent-quota-cert.pem',
        privateKeyPemPath: 'test/fixtures/nonexistent-quota-key.pem',
      ),
    );
    await tester.pumpWidget(
      testAppWithL10n(
        ProviderUsageScreen(
          connection: invalid,
          providerId: 'openai',
          title: 'Usage',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('% remaining'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('nonexistent'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'inventory and analytics share selected-profile prefixed transport',
    () async {
      final requests = <http.Request>[];
      final client = DashboardClient(
        host: 'example.test',
        port: 9443,
        useHttps: true,
        pathPrefix: '/selected',
        gatewayProfile: 'research & development',
        proxied: true,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'providers': [], 'models': []}),
            200,
          );
        }),
      );
      await client.getModelOptions();
      await client.getModelsAnalytics();
      expect(requests.map((r) => r.url.path), [
        '/selected/api/model/options',
        '/selected/api/analytics/models',
      ]);
      expect(
        requests.every(
          (r) => r.url.queryParameters['profile'] == 'research & development',
        ),
        isTrue,
      );
      expect(
        requests.every((r) => !r.headers.containsKey('authorization')),
        isTrue,
      );
      client.close();
    },
  );
}
