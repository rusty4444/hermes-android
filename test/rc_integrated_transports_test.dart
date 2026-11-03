import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_assets_client.dart';
import 'package:hermes_android/core/services/connection_manager.dart';

import 'support/mtls_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final withIdentity in [true, false]) {
    test(
      'Assets physical HTTPS list and message reads retain TLS identity=$withIdentity',
      () async {
        final fixture = MutualTlsFixture();
        await fixture.start((request) async {
          expect(request.uri.queryParameters['profile'], 'fixture-profile');
          if (request.uri.path.endsWith('/messages')) {
            expect(
              request.uri.path,
              '/dashboard/api/sessions/source-session/messages',
            );
            expect(request.uri.queryParameters['include_compacted'], 'true');
            expect(request.uri.queryParameters['inline_images'], 'false');
            fixture.json(request, {
              'session_id': 'source-session',
              'profile': 'fixture-profile',
              'messages': [
                {
                  'id': 1,
                  'role': 'assistant',
                  'content': 'MEDIA:`/out/雪 #%?.png`',
                },
              ],
              'pagination': {
                'limit': 100,
                'offset': 0,
                'order': 'latest',
                'returned': 1,
              },
            });
          } else {
            expect(request.uri.path, '/dashboard/api/sessions');
            expect(request.uri.queryParameters['archived'], 'include');
            fixture.json(request, {
              'profile': 'fixture-profile',
              'sessions': [
                {
                  'id': 'source-session',
                  'title': 'Source',
                  'source': 'desktop',
                },
              ],
              'total': 1,
            });
          }
          await request.response.close();
        });
        addTearDown(fixture.close);
        final connection = SavedConnection(
          id: 'tls-assets',
          label: 'TLS Assets',
          host: '127.0.0.1',
          port: fixture.server.port,
          apiKey: 'synthetic-api',
          useHttps: true,
          desktopGatewayUrl: '${fixture.origin}/dashboard',
          dashboardProxied: true,
          dashboardPrefix: '/dashboard',
          gatewayProfile: 'fixture-profile',
          clientCertificate: withIdentity ? loopbackIdentity : null,
        );
        await withLoopbackTrust(() async {
          final assets = ChatAssetsClient.fromConnection(connection);
          addTearDown(assets.close);
          if (!withIdentity) {
            await expectLater(
              assets.listSessions(),
              throwsA(
                isA<DashboardHttpException>().having(
                  (error) => error.statusCode,
                  'statusCode',
                  403,
                ),
              ),
            );
            expect(fixture.requests, isEmpty);
            expect(fixture.anonymousRequests, 1);
            return;
          }
          final source = (await assets.listSessions()).sessions.single;
          final page = await assets.getMessages(source);
          expect(
            chatAssetsFromMessages(source, page.messages).single.ref.path,
            '/out/雪 #%?.png',
          );
          expect(fixture.requests, hasLength(2));
          expect(fixture.anonymousRequests, 0);
        });
      },
    );
  }
}
