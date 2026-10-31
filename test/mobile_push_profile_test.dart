import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object> capabilities() => {
  'schema': 1,
  'registration_fence': 1,
  'enabled': true,
  'transports': ['webpush'],
  'vapid_public_key': base64Url
      .encode([4, ...List<int>.filled(64, 1)])
      .replaceAll('=', ''),
};

Future<void> allOperations(MobilePushApi api) async {
  await api.capabilities();
  await api.register({
    'installation': 'installation',
    'nonce': 'registration_nonce_012345',
    'revision': 7,
    'endpoint': 'https://push.example.test/path',
    'keys': {'p256dh': 'test', 'auth': 'test'},
    'sessions': ['same-session-id'],
  });
  await api.confirm('installation', 1, 'encrypted-proof');
  await api.revoke('installation');
  await api.events('19');
}

void main() {
  for (final retry in [false, true]) {
    for (final profile in <String?>['selected-work-profile', null]) {
      test(
        'every push operation scopes profile=$profile with retry=$retry',
        () async {
          final requests = <http.Request>[];
          final attempts = <String, int>{};
          final client = DashboardClient(
            host: 'fixture.invalid',
            gatewayProfile: profile,
            proxied: true,
            httpClient: MockClient((request) async {
              requests.add(request);
              final key = '${request.method} ${request.url.path}';
              attempts[key] = (attempts[key] ?? 0) + 1;
              if (retry && attempts[key] == 1) return http.Response('{}', 401);
              return http.Response(
                jsonEncode(
                  request.url.path.endsWith('/capabilities')
                      ? capabilities()
                      : {},
                ),
                200,
              );
            }),
          );
          addTearDown(client.close);
          await allOperations(MobilePushApi(client));
          expect(attempts, hasLength(5));
          expect(attempts.values, everyElement(retry ? 2 : 1));
          expect(
            requests.map((r) => r.url.queryParameters['profile']),
            everyElement(profile),
          );
          for (final request in requests.where(
            (r) => r.url.path.endsWith('/events'),
          )) {
            expect(request.url.queryParameters['after'], '19');
            expect(request.url.queryParameters['limit'], '100');
          }
        },
      );
    }
  }

  test(
    'overlapping selected clients never borrow the other request profile',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final requests = <http.Request>[];
      DashboardClient client(String profile) => DashboardClient(
        host: 'fixture.invalid',
        gatewayProfile: profile,
        proxied: true,
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.url.queryParameters['profile'], profile);
          if (profile == 'held-profile' &&
              request.url.path.endsWith('/capabilities')) {
            entered.complete();
            await release.future;
          }
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('/capabilities') ? capabilities() : {},
            ),
            200,
          );
        }),
      );
      final held = client('held-profile');
      final other = client('selected-work-profile');
      addTearDown(held.close);
      addTearDown(other.close);
      final flight = allOperations(MobilePushApi(held));
      await entered.future;
      await allOperations(MobilePushApi(other));
      release.complete();
      await flight;
      expect(requests, hasLength(10));
    },
  );
}
