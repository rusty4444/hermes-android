import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/client_certificate.dart';
import 'package:hermes_android/core/screens/open_router_screen.dart';
import 'package:hermes_android/core/screens/provider_usage_screen.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/widgets/more_pane.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/l10n_test_utils.dart';

final connection = SavedConnection(
  id: 'provider-test',
  label: 'Test',
  host: 'example.test',
  port: 8642,
  apiKey: 'test',
);

class FakeDashboard extends DashboardClient {
  FakeDashboard() : super(host: 'example.test', proxied: true);
  Completer<Map<String, dynamic>>? heldUsage;
  bool fail = false;
  int closes = 0;
  @override
  void close() {
    closes++;
    super.close();
  }

  @override
  Future<Map<String, dynamic>> getModelsAnalytics({int days = 30}) async {
    if (heldUsage != null) return heldUsage!.future;
    if (fail) throw Exception('private backend details');
    return {
      'models': [
        {
          'provider': 'openrouter',
          'model': 'retired/model',
          'sessions': 2,
          'input_tokens': 17,
          'output_tokens': 4,
          'estimated_cost': 0,
          'actual_cost': null,
        },
        {'provider': 'openai', 'model': 'other-model', 'estimated_cost': 3},
      ],
    };
  }
}

void main() {
  test(
    'usage uses exact provider and retains retired model and unknown costs',
    () {
      final rows = providerUsageRows({
        'models': [
          {'provider': 'openrouter', 'model': 'Retired', 'actual_cost': null},
          {'provider': 'openai', 'model': 'Retired'},
        ],
      }, 'openrouter');
      expect(rows.single['model'], 'Retired');
      expect(rows.single['actual_cost'], isNull);
      expect(() => providerUsageRows({}, 'openrouter'), throwsFormatException);
    },
  );

  test(
    'More discovery includes supported providers only and preserves offline reason',
    () async {
      final l10n = await loadTestL10n();
      final sections = buildMoreSections(
        dashboardReachable: false,
        l10n: l10n,
        providerIds: {
          'openrouter',
          'openai',
          'anthropic',
          'deepseek',
          'unsupported',
        },
      );
      final entries = sections
          .expand((s) => s.entries)
          .where((e) => providerTitles.containsKey(e.id));
      expect(entries, hasLength(1));
      expect(entries.single.id, 'openrouter');
      expect(
        entries.every((e) => !e.isSelectable && e.unavailableReason != null),
        isTrue,
      );
      expect(
        buildMoreSections(
          dashboardReachable: true,
          l10n: l10n,
        ).expand((s) => s.entries).any((e) => providerTitles.containsKey(e.id)),
        isFalse,
      );
    },
  );

  testWidgets(
    'OpenRouter shows measured zero not free, has no credential entry',
    (tester) async {
      final client = FakeDashboard();
      await tester.pumpWidget(
        testAppWithL10n(
          OpenRouterScreen(connection: connection, dashboardClient: client),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('retired/model'), findsOneWidget);
      expect(find.text('other-model'), findsNothing);
      expect(find.textContaining('Estimated: \$0.0000'), findsOneWidget);
      expect(find.textContaining('Reported: —'), findsOneWidget);
      expect(find.text('Free'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(client.closes, 0);
      client.close();
    },
  );

  testWidgets('refresh failure retains rows and retry; no raw backend error', (
    tester,
  ) async {
    final client = FakeDashboard();
    await tester.pumpWidget(
      testAppWithL10n(
        OpenRouterScreen(connection: connection, dashboardClient: client),
      ),
    );
    await tester.pumpAndSettle();
    client.fail = true;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('retired/model'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('private backend'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets('late usage completion after dispose is ignored', (tester) async {
    final client = FakeDashboard()..heldUsage = Completer();
    await tester.pumpWidget(
      testAppWithL10n(
        OpenRouterScreen(connection: connection, dashboardClient: client),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    client.heldUsage!.complete({'models': []});
    await tester.pump();
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets('usage fits narrow large text and Japanese locale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FakeDashboard();
    await tester.pumpWidget(
      testAppWithL10n(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: OpenRouterScreen(
            connection: connection,
            dashboardClient: client,
          ),
        ),
        locale: const Locale('ja'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('過去30日間'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.close();
  });

  testWidgets(
    'provider certificate construction failure is safe to retry and dispose',
    (tester) async {
      final invalid = connection.copyWith(
        useHttps: true,
        clientCertificate: const ClientCertificateConfig(
          label: 'Missing synthetic fixture',
          certificatePemPath: 'test/fixtures/nonexistent-provider-cert.pem',
          privateKeyPemPath: 'test/fixtures/nonexistent-provider-key.pem',
        ),
      );
      await tester.pumpWidget(
        testAppWithL10n(OpenRouterScreen(connection: invalid)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('nonexistent-provider'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider connection replacement rejects held old analytics', (
    tester,
  ) async {
    final old = FakeDashboard()..heldUsage = Completer();
    final fresh = FakeDashboard();
    await tester.pumpWidget(
      testAppWithL10n(
        ProviderUsageScreen(
          connection: connection,
          providerId: 'openrouter',
          title: 'Old',
          dashboardClient: old,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      testAppWithL10n(
        ProviderUsageScreen(
          connection: connection.copyWith(gatewayProfile: 'other'),
          providerId: 'openai',
          title: 'New',
          dashboardClient: fresh,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('other-model'), findsOneWidget);
    old.heldUsage!.complete({
      'models': [
        {'provider': 'openai', 'model': 'stale-model'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('other-model'), findsOneWidget);
    expect(find.text('stale-model'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(old.closes, 0);
    expect(fresh.closes, 0);
    old.close();
    fresh.close();
  });

  test(
    'dashboard-only wire uses prefix and omits credential/endpoint override fields',
    () async {
      final requests = <http.Request>[];
      final client = DashboardClient(
        host: 'example.test',
        port: 9443,
        useHttps: true,
        pathPrefix: '/profile/test',
        gatewayProfile: 'research & development',
        proxied: true,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'ok': true, 'tasks': [], 'models': []}),
            200,
          );
        }),
      );
      await client.getModelsAnalytics();
      expect(requests.map((r) => r.url.path), [
        '/profile/test/api/analytics/models',
      ]);
      expect(requests.first.url.queryParameters, {
        'days': '30',
        'profile': 'research & development',
      });
      expect(
        requests.every((r) => !r.headers.containsKey('authorization')),
        isTrue,
      );
      client.close();
    },
  );
}
