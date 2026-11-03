import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StreamClient extends http.BaseClient {
  _StreamClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() => closes++;
}

RemoteFilesClient _client(http.Client urls, {int limit = 4}) =>
    RemoteFilesClient(
      dashboard: DashboardClient(
        host: 'gateway.example',
        proxied: true,
        httpClient: MockClient(
          (request) async =>
              throw StateError('URL delivery must never contact Dashboard'),
        ),
      ),
      profile: 'work',
      sessionId: 'stored-session',
      maxDownloadBytes: limit,
      urlHttpClient: urls,
    );

void main() {
  test(
    'URL-only image fetch sends no gateway credentials or cookies',
    () async {
      final requests = <http.BaseRequest>[];
      final urls = _StreamClient((request) async {
        requests.add(request);
        expect(request.headers, isEmpty);
        expect(request.followRedirects, isFalse);
        return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
      });
      final files = _client(urls);
      final result = await files.download(
        'https://cdn.example/chart.png?signature=example',
      );
      expect(
        requests.single.url.toString(),
        'https://cdn.example/chart.png?signature=example',
      );
      expect(result.filename, 'chart.png');
      expect(result.bytes, [1, 2, 3]);
      files.close();
      files.close();
      expect(urls.closes, 1);
    },
  );

  test('validates every redirect and never sends an HTTP downgrade', () async {
    final requests = <Uri>[];
    final files = _client(
      _StreamClient((request) async {
        requests.add(request.url);
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'http://untrusted.example/image.png'},
        );
      }),
    );
    addTearDown(files.close);
    await expectLater(
      files.download('https://cdn.example/image.png'),
      throwsFormatException,
    );
    expect(requests.map((uri) => uri.scheme), ['https']);
  });

  test('follows bounded HTTPS redirects without authentication', () async {
    final paths = <String>[];
    final files = _client(
      _StreamClient((request) async {
        expect(request.headers, isEmpty);
        paths.add(request.url.path);
        return request.url.path == '/original.png'
            ? http.StreamedResponse(
                const Stream.empty(),
                307,
                headers: {'location': '/final.png'},
              )
            : http.StreamedResponse(Stream.value([8]), 200);
      }),
    );
    addTearDown(files.close);
    final result = await files.download('https://cdn.example/original.png');
    expect(paths, ['/original.png', '/final.png']);
    expect(result.filename, 'original.png');
    expect(result.bytes, [8]);
  });

  test('redirect loops have a fixed request budget', () async {
    var requests = 0;
    final files = _client(
      _StreamClient((request) async {
        requests++;
        return http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': '/loop.png'},
        );
      }),
    );
    addTearDown(files.close);
    await expectLater(
      files.download('https://cdn.example/loop.png'),
      throwsFormatException,
    );
    expect(requests, 4);
  });

  test(
    'rejects plaintext or embedded URL credentials before request',
    () async {
      var requests = 0;
      final files = _client(
        _StreamClient((request) async {
          requests++;
          throw StateError('should not send');
        }),
      );
      addTearDown(files.close);
      for (final url in [
        'http://cdn.example/image.png',
        'https://user:password@cdn.example/image.png',
      ]) {
        await expectLater(files.download(url), throwsFormatException);
      }
      expect(requests, 0);
    },
  );

  test('enforces the streaming budget without a Content-Length', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final files = _client(
      _StreamClient((_) async => http.StreamedResponse(body.stream, 200)),
    );
    addTearDown(files.close);
    final download = files.download('https://cdn.example/large.png');
    final assertion = expectLater(
      download,
      throwsA(isA<DownloadSizeLimitException>()),
    );
    body.add([1, 2, 3]);
    body.add([4, 5]);
    await assertion;
    expect(cancelled, isTrue);
    await body.close();
  });

  test('rejects oversize announced length before consuming bytes', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final files = _client(
      _StreamClient(
        (_) async => http.StreamedResponse(body.stream, 200, contentLength: 5),
      ),
    );
    addTearDown(files.close);
    await expectLater(
      files.download('https://cdn.example/large.png'),
      throwsA(isA<DownloadSizeLimitException>()),
    );
    expect(cancelled, isTrue);
    await body.close();
  });

  test('failed status does not consume unbounded error bodies', () async {
    final body = StreamController<List<int>>();
    final files = _client(
      _StreamClient((_) async => http.StreamedResponse(body.stream, 404)),
    );
    addTearDown(files.close);
    await expectLater(
      files.download('https://cdn.example/missing.png'),
      throwsA(isA<http.ClientException>()),
    );
    await body.close();
  });

  test('cannot start URL requests after its owning client closes', () async {
    var requests = 0;
    final files = _client(
      _StreamClient((_) async {
        requests++;
        return http.StreamedResponse(const Stream.empty(), 200);
      }),
    );
    files.close();
    await expectLater(
      files.download('https://cdn.example/image.png'),
      throwsStateError,
    );
    expect(requests, 0);
  });
}
