import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:http/http.dart' as http;

class _StreamingClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  _StreamingClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  test('bounded download rejects Content-Length before buffering', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final dashboard = DashboardClient(
      host: 'fixture.test',
      proxied: true,
      httpClient: _StreamingClient(
        (request) async =>
            http.StreamedResponse(controller.stream, 200, contentLength: 6),
      ),
    );
    await expectLater(
      dashboard.apiGetBytes('fs/download', maxBytes: 4),
      throwsA(isA<DownloadSizeLimitException>()),
    );
    expect(cancelled, isTrue);
    await controller.close();
    dashboard.close();
  });

  test('bounded chunked download cancels at the actual byte budget', () async {
    var cancelled = false;
    var emitted = 0;
    Stream<List<int>> body() async* {
      try {
        for (var i = 0; i < 100; i++) {
          emitted++;
          yield [1, 2];
        }
      } finally {
        cancelled = true;
      }
    }

    final dashboard = DashboardClient(
      host: 'fixture.test',
      proxied: true,
      httpClient: _StreamingClient(
        (request) async => http.StreamedResponse(body(), 200),
      ),
    );
    await expectLater(
      dashboard.apiGetBytes('fs/download', maxBytes: 4),
      throwsA(isA<DownloadSizeLimitException>()),
    );
    expect(cancelled, isTrue);
    expect(emitted, 3);
    dashboard.close();
  });

  test(
    'exact-budget file preserves bytes, filename and source scope',
    () async {
      late Uri requested;
      final files = RemoteFilesClient.fromConnection(
        SavedConnection(
          id: 'fixture',
          label: 'Fixture',
          host: 'fixture.test',
          port: 8642,
          apiKey: 'not-a-real-key',
          dashboardProxied: true,
          useHttps: true,
          dashboardPrefix: '/prefix',
          dashboardPortOverride: 443,
          gatewayProfile: 'work',
        ),
        sessionId: 'stored-a',
        maxDownloadBytes: 4,
        httpClient: _StreamingClient((request) async {
          requested = request.url;
          return http.StreamedResponse(
            Stream.fromIterable([
              [1, 2],
              [3, 4],
            ]),
            200,
            headers: {
              'content-disposition': 'attachment; filename="report.pdf"',
            },
          );
        }),
      );
      final result = await files.download('/server/report.pdf');
      expect(result.bytes, [1, 2, 3, 4]);
      expect(result.filename, 'report.pdf');
      expect(requested.scheme, 'https');
      expect(requested.host, 'fixture.test');
      expect(requested.port, 443);
      expect(requested.path, '/prefix/api/fs/download');
      expect(requested.queryParameters, {
        'path': '/server/report.pdf',
        'profile': 'work',
        'session_id': 'stored-a',
      });
      files.close();
    },
  );

  test(
    'bounded auth retry retains the size limit and reauthenticates once',
    () async {
      var logins = 0;
      var gets = 0;
      final dashboard = DashboardClient(
        host: 'fixture.test',
        username: 'fixture',
        password: 'fixture-only',
        httpClient: _StreamingClient((request) async {
          if (request.url.path == '/auth/password-login') {
            logins++;
            return http.StreamedResponse(
              Stream.value(utf8.encode('{}')),
              200,
              headers: {
                'set-cookie': 'hermes_session_at=fixture-$logins; HttpOnly',
              },
            );
          }
          expect(
            request.headers['Cookie'],
            'hermes_session_at=fixture-$logins',
          );
          gets++;
          return gets == 1
              ? http.StreamedResponse(const Stream.empty(), 401)
              : http.StreamedResponse(
                  Stream.value([1, 2, 3, 4, 5]),
                  200,
                  contentLength: 5,
                );
        }),
      );
      await expectLater(
        dashboard.apiGetBytes('fs/download', maxBytes: 4),
        throwsA(isA<DownloadSizeLimitException>()),
      );
      expect(logins, 2);
      expect(gets, 2);
      dashboard.close();
    },
  );

  test('invalid budget makes no network call', () async {
    final dashboard = DashboardClient(
      host: 'fixture.test',
      proxied: true,
      httpClient: _StreamingClient(
        (_) async => throw StateError('must not call'),
      ),
    );
    await expectLater(
      dashboard.apiGetBytes('fs/download', maxBytes: 0),
      throwsArgumentError,
    );
    dashboard.close();
  });
}
