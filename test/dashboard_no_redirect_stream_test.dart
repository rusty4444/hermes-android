import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/dashboard_native_auth_store.dart';
import 'package:http/http.dart' as http;

class _StreamClient extends http.BaseClient {
  _StreamClient(this.body);
  final Stream<List<int>> body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.followRedirects, isFalse);
    return http.StreamedResponse(body, 200);
  }
}

void main() {
  test(
    'idle body cancellation reaches source and awaits its cleanup',
    () async {
      final cancelling = Completer<void>();
      final cleanup = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelling.complete();
          return cleanup.future;
        },
      );
      final client = DashboardNoRedirectClient(_StreamClient(body.stream));
      addTearDown(client.close);
      final response = await client.send(
        http.Request('GET', Uri.https('fixture.test')),
      );
      final subscription = response.stream.listen(
        (_) => fail('unexpected bytes'),
      );
      var cancelled = false;
      final cancellation = subscription.cancel().then((_) => cancelled = true);
      await cancelling.future.timeout(const Duration(seconds: 1));
      expect(cancelled, isFalse);
      cleanup.complete();
      await cancellation.timeout(const Duration(seconds: 1));
      expect(cancelled, isTrue);
      await body.close();
    },
  );

  test('failed chunk fence terminates and cancels an idle source', () async {
    var revoked = false;
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final client = DashboardNoRedirectClient(
      _StreamClient(body.stream),
      checkBinding: () {
        if (revoked) throw StateError('revoked');
      },
    );
    addTearDown(client.close);
    final response = await client.send(
      http.Request('GET', Uri.https('fixture.test')),
    );
    final done = Completer<void>();
    final errors = <Object>[];
    final subscription = response.stream.listen(
      (_) => fail('revoked bytes were delivered'),
      onError: (Object error) => errors.add(error),
      onDone: done.complete,
    );
    addTearDown(subscription.cancel);
    revoked = true;
    body.add([1]);
    await done.future.timeout(const Duration(seconds: 1));
    expect(errors, hasLength(1));
    expect(errors.single, isStateError);
    expect(cancelled, isTrue);
    await body.close();
  });

  for (final empty in [false, true]) {
    test(
      'response epoch fences ${empty ? 'empty completion' : 'body chunks'}',
      () async {
        var epoch = 0;
        final body = StreamController<List<int>>();
        final client = DashboardNoRedirectClient(
          _StreamClient(body.stream),
          captureFence: () {
            final captured = epoch;
            return () {
              if (captured != epoch) throw StateError('stale response');
            };
          },
        );
        addTearDown(client.close);
        final response = await client.send(
          http.Request('GET', Uri.https('fixture.test')),
        );
        final rejected = expectLater(
          response.stream.toBytes(),
          throwsStateError,
        );
        epoch++;
        if (!empty) body.add([1, 2, 3]);
        final closed = body.close();
        await rejected;
        await closed;
      },
    );
  }
}
