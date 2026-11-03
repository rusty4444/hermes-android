import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

void main() {
  test(
    'production clients preserve prefix, password auth and profile on wire',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <Map<String, Object?>>[];
      final state = <String, dynamic>{
        'id': 'job-1',
        'model': 'old',
        'provider': 'old-provider',
        'base_url': 'https://old.invalid/v1',
      };
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        received.add({
          'path': request.uri.path,
          'profile': request.uri.queryParameters['profile'],
          'cookie': request.headers.value('cookie'),
          'authorization': request.headers.value('authorization'),
          'body': body,
        });
        Object response;
        if (request.uri.path.endsWith('/auth/password-login')) {
          request.response.headers.add(
            'set-cookie',
            'hermes_session_at=fixture-cookie; HttpOnly; Path=/',
          );
          response = {'ok': true};
        } else if (request.uri.path.endsWith('/model/options')) {
          response = {
            'providers': [
              {
                'slug': 'new-provider',
                'models': ['new-model'],
              },
            ],
          };
        } else if (request.method == 'PUT') {
          state.addAll(
            (jsonDecode(body)['updates'] as Map).cast<String, dynamic>(),
          );
          response = state;
        } else {
          response = state;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      final connection = SavedConnection(
        id: 'wire',
        label: 'Wire',
        host: 'wrong.invalid',
        port: 8642,
        apiKey: 'must-not-leak',
        desktopGatewayUrl: 'http://127.0.0.1:${server.port}/prefix',
        dashboardUsername: 'fixture-user',
        dashboardPassword: 'fixture-password',
        gatewayProfile: 'work',
      );
      final client = DashboardClient.fromConnection(connection);
      final fresh = DashboardClient.fromConnection(connection);
      try {
        await client.getModelOptions();
        await client.updateJob('job-1', {
          'model': 'new-model',
          'provider': 'new-provider',
          'base_url': null,
        });
        final saved = await fresh.getCronJob('job-1');
        expect(saved, containsPair('model', 'new-model'));
        expect(saved, containsPair('provider', 'new-provider'));
        expect(saved, containsPair('base_url', null));
        final api = received
            .where((r) => (r['path'] as String).contains('/api/'))
            .toList();
        expect(api, hasLength(3));
        expect(api.map((r) => r['path']), [
          '/prefix/api/model/options',
          '/prefix/api/cron/jobs/job-1',
          '/prefix/api/cron/jobs/job-1',
        ]);
        for (final request in api) {
          expect(request['profile'], 'work');
          expect(
            request['cookie'],
            contains('hermes_session_at=fixture-cookie'),
          );
          expect(request['authorization'], isNull);
        }
        expect(jsonDecode(api[1]['body'] as String), {
          'updates': {
            'model': 'new-model',
            'provider': 'new-provider',
            'base_url': null,
          },
        });
      } finally {
        client.close();
        fresh.close();
        await server.close(force: true);
      }
    },
  );
}
