import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('usage reports may take as long as the gateway needs to build them', () {
    expect(DashboardClient.analyticsWait(7), const Duration(seconds: 25));
    expect(DashboardClient.analyticsWait(30), const Duration(seconds: 45));
    expect(DashboardClient.analyticsWait(90), const Duration(seconds: 100));
  });

  test('a 30-day report that takes 40 seconds still arrives', () {
    fakeAsync((async) {
      Uri? asked;
      final client = DashboardClient(
        host: 'gw',
        proxied: true,
        httpClient: MockClient((request) async {
          asked = request.url;
          await Future<void>.delayed(const Duration(seconds: 40));
          return http.Response(
            jsonEncode({
              'totals': {'total_sessions': 3},
            }),
            200,
          );
        }),
      );
      Map<String, dynamic>? report;
      Object? failure;
      client
          .getAnalytics(days: 30)
          .then<void>((r) => report = r)
          .catchError((Object e) => failure = e);
      async.elapse(const Duration(seconds: 41));
      expect(failure, isNull);
      expect((report!['totals'] as Map)['total_sessions'], 3);
      expect(asked!.path, '/api/analytics/usage');
      expect(asked!.queryParameters['days'], '30');
    });
  });
}
