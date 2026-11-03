import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:http/http.dart' as http;

import 'mobile_push_service_test.dart' as fixture;

/// Stateful server contract: PUT requires a fresh nonce; confirm consumes its
/// encrypted proof exactly once. Responses may disappear AFTER these commits.
/// This intentionally does not make either endpoint idempotent for the client.
class ConsumingServer {
  ConsumingServer(this.f);
  final fixture.Fixture f;
  final nonces = <String>{};
  int generation = 0;
  int revision = 0;
  String? nonce;
  bool active = false;
  bool losePut = false;
  bool loseConfirm = false;
  bool deliverChallenge = true;
  bool markDirtyOnPut = false;
  String? proof;

  void install() {
    f.onPut = (request) async {
      final body = jsonDecode(request.body) as Map;
      final nextRevision = body['registration_revision'];
      final nextNonce = body['registration_nonce'];
      if (nextRevision is! int ||
          nextRevision <= revision ||
          !nonces.add(nextNonce as String)) {
        return http.Response('{}', 409);
      }
      revision = nextRevision;
      nonce = nextNonce;
      generation++;
      active = false;
      proof = 'encrypted-proof-$generation';
      if (deliverChallenge) {
        f.challenge(generation: generation);
        (f.native['challenges'] as List).single['challenge'] = proof;
      }
      if (markDirtyOnPut) unawaited(f.service.refresh());
      if (losePut) {
        losePut = false;
        throw http.ClientException('fixture lost committed PUT response');
      }
      return http.Response(
        jsonEncode({
          'generation': generation,
          'status': 'pending',
          'registration_nonce': nonce,
          'registration_revision':
              (jsonDecode(request.body) as Map)['registration_revision'],
        }),
        200,
      );
    };
    f.onConfirm = (request) async {
      final body = jsonDecode(request.body) as Map;
      if (active ||
          body['generation'] != generation ||
          body['challenge'] != proof) {
        return http.Response('{}', 409);
      }
      active = true;
      proof = null;
      if (loseConfirm) {
        loseConfirm = false;
        throw http.ClientException('fixture lost committed confirm response');
      }
      return http.Response(
        jsonEncode({'status': 'active', 'generation': generation}),
        200,
      );
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Fixture f;
  setUp(() async {
    notificationPrefs.value = NotificationPrefs.defaults;
    f = fixture.Fixture();
    await f.setup();
  });
  tearDown(() => f.close());

  for (final replacement in ['restart', 'endpoint']) {
    test(
      'precommit old PUT cannot overwrite $replacement activation, retry or restart',
      () async {
        f.seed();
        final server = ConsumingServer(f)..install();
        final commit = f.onPut!;
        final entered = Completer<void>();
        final release = Completer<void>();
        var first = true;
        f.onPut = (request) async {
          if (first) {
            first = false;
            entered.complete();
            await release.future; // BEFORE server generation/revision writes
          }
          return commit(request);
        };
        final oldOwner = f.service.initialize(f.manager);
        await entered.future;
        expect(server.generation, 0);
        if (replacement == 'endpoint') {
          f.native.addAll({
            'nonce': 'renewed-endpoint-nonce',
            'revision': 2,
            'generation': 0,
            'active': false,
            'endpoint': 'https://renewed.invalid/new',
          });
          f.native.remove('registration_attempt');
        }
        f.restart();
        await f.service.initialize(f.manager);
        expect(f.service.active, isTrue);
        expect(server.active, isTrue);
        expect(server.generation, 1);
        expect(server.revision, f.native['revision']);
        expect(server.nonce, f.native['nonce']);
        final durable = f.clone(f.native);
        release.complete();
        await oldOwner;
        expect(f.native, durable);
        expect(server.generation, 1);
        expect(server.active, isTrue);
        expect(server.nonce, f.native['nonce']);
        await f.service.retry();
        f.restart();
        await f.service.initialize(f.manager);
        expect(f.service.status, 'Active');
        expect(server.generation, 1);
        expect(server.active, isTrue);
        expect(f.requests.where((r) => r.method == 'PUT'), hasLength(2));
        expect(f.methods, isNot(contains('permission')));
        expect(f.methods, isNot(contains('enable')));
      },
    );
  }

  for (final loss in [
    'PUT response',
    'PUT native commit',
    'confirm response',
    'confirm native commit',
  ]) {
    test(
      '$loss lost after server commit recovers across controller restart',
      () async {
        f.seed();
        final server = ConsumingServer(f)
          ..losePut = loss == 'PUT response'
          ..loseConfirm = loss == 'confirm response'
          ..install();
        f.failCommand = switch (loss) {
          'PUT native commit' => 'generation',
          'confirm native commit' => 'activate',
          _ => null,
        };
        await f.service.initialize(f.manager);
        expect(f.service.active, isFalse);
        expect(server.generation, 1);
        final oldNonce = f.native['nonce'];
        final oldRevision = f.native['revision'];
        expect(
          f.native['registration_attempt'] == true ||
              f.native['confirmation_attempt'] == true,
          isTrue,
        );
        f.restart();
        await f.service.initialize(f.manager);
        expect(f.service.active, isTrue);
        expect(server.active, isTrue);
        expect(server.generation, 2);
        expect(f.native['nonce'], isNot(oldNonce));
        expect(f.native['revision'], greaterThan(oldRevision as int));
        expect(f.native['generation'], 2);
        expect(
          f.methods.where((m) => m == 'recoverRegistration'),
          hasLength(1),
        );
        expect(f.methods, isNot(contains('permission')));
        expect(f.methods, isNot(contains('enable')));
        expect(f.methods, isNot(contains('retryDistributor')));
        expect(f.native['sessions'], ['durable-session']);
        await f.service.refresh();
        expect(server.generation, 2); // active refresh never spins/rotates
      },
    );
  }

  for (final boundary in ['PUT', 'confirm']) {
    test(
      'process replacement during held committed $boundary fences the old acknowledgement',
      () async {
        f.seed();
        final server = ConsumingServer(f)..install();
        final entered = Completer<void>();
        final acknowledgement = Completer<http.Response>();
        http.Response? committed;
        var held = false;
        final operation = boundary == 'PUT' ? f.onPut! : f.onConfirm!;
        Future<http.Response> intercept(http.Request request) async {
          final response = await operation(
            request,
          ); // real fixture commit first
          if (!held) {
            held = true;
            committed = response;
            entered.complete();
            return acknowledgement.future;
          }
          return response;
        }

        if (boundary == 'PUT') {
          f.onPut = intercept;
        } else {
          f.onConfirm = intercept;
        }
        final deadOwner = f.service.initialize(f.manager);
        await entered.future;
        expect(server.generation, 1);
        expect(f.native['active'], isFalse);
        f.restart();
        await f.service.initialize(f.manager);
        expect(f.service.active, isTrue);
        expect(server.generation, 2);
        final newAuthority = f.clone(f.native);
        acknowledgement.complete(committed!);
        await deadOwner;
        expect(f.native, newAuthority);
        expect(
          f.methods.where((m) => m == 'recoverRegistration'),
          hasLength(1),
        );
      },
    );
  }

  test(
    'expired pending encrypted proof renews on startup, never confirms stale proof',
    () async {
      f.seed();
      f.native['generation'] = 1;
      f.native['pending_until'] = 1;
      f.challenge(generation: 1);
      (f.native['challenges'] as List).single['expires_at'] = 1;
      final server = ConsumingServer(f)..generation = 1;
      server.nonces.add(f.native['nonce'] as String);
      server.install();
      await f.service.initialize(f.manager);
      expect(f.service.active, isTrue);
      expect(server.generation, 2);
      final confirmations = f.requests.where(
        (r) => r.url.path.endsWith('/confirm'),
      );
      expect(confirmations, hasLength(1));
      expect(
        jsonDecode(confirmations.single.body)['challenge'],
        'encrypted-proof-2',
      );
    },
  );

  test(
    'missing proof has a durable bounded wait, not infinite pending after restart',
    () async {
      f.seed();
      final server = ConsumingServer(f)..deliverChallenge = false;
      server.install();
      await f.service.initialize(f.manager);
      expect(f.native['pending_until'], isA<int>());
      expect(f.service.active, isFalse);
      await f.service.refresh();
      expect(server.generation, 1); // do not rotate on every snapshot
      f.native['pending_until'] = 1;
      server.deliverChallenge = true;
      f.restart();
      await f.service.initialize(f.manager);
      expect(server.generation, 2);
      expect(f.service.active, isTrue);
    },
  );

  test(
    'legacy pending snapshot without journal or proof gets one secure renewal',
    () async {
      f.seed();
      f.native['generation'] = 1;
      final server = ConsumingServer(f)..generation = 1;
      server.install();
      await f.service.initialize(f.manager);
      expect(server.generation, 2);
      expect(f.service.active, isTrue);
    },
  );

  test(
    'repeat network failure rotates only once per explicit retry, no dirty-tail spin',
    () async {
      f.seed();
      final server = ConsumingServer(f)
        ..losePut = true
        ..markDirtyOnPut = true;
      server.install();
      await f.service.initialize(f.manager);
      expect(server.generation, 1);
      server.losePut = true;
      await f.service.retry();
      expect(server.generation, 2);
      expect(f.methods.where((m) => m == 'recoverRegistration'), hasLength(1));
      await f.service.retry();
      expect(server.generation, 3);
      expect(f.service.active, isTrue);
    },
  );

  test(
    'concurrent retry shares the recovery PUT and cannot rotate away its challenge',
    () async {
      f.seed();
      f.native['registration_attempt'] = true;
      final entered = Completer<void>();
      final response = Completer<http.Response>();
      f.onPut = (_) {
        entered.complete();
        return response.future;
      };
      final initializing = f.service.initialize(f.manager);
      await entered.future;
      final a = f.service.retry();
      final b = f.service.refresh();
      f.challenge();
      response.complete(f.pending());
      await Future.wait([initializing, a, b]);
      expect(f.service.active, isTrue);
      expect(f.requests.where((r) => r.method == 'PUT'), hasLength(1));
      expect(f.methods.where((m) => m == 'recoverRegistration'), hasLength(1));
    },
  );

  test(
    'endpoint renewal queued behind failed PUT hands off without rotating new authority',
    () async {
      f.seed();
      final server = ConsumingServer(f)..install();
      final normalPut = f.onPut!;
      var first = true;
      f.onPut = (request) async {
        if (first) {
          first = false;
          f.native.addAll({
            'nonce': 'renewed-nonce',
            'revision': 2,
            'generation': 0,
            'active': false,
          });
          for (final key in [
            'registration_attempt',
            'confirmation_attempt',
            'pending_until',
            'challenges',
          ]) {
            f.native.remove(key);
          }
          unawaited(f.service.refresh());
          throw http.ClientException(
            'old endpoint failed after native renewal',
          );
        }
        return normalPut(request);
      };
      await f.service.initialize(f.manager);
      expect(f.service.active, isTrue);
      expect(f.native['nonce'], 'renewed-nonce');
      expect(server.generation, 1);
      expect(f.methods, isNot(contains('recoverRegistration')));
      expect(f.requests.where((r) => r.method == 'PUT'), hasLength(2));
    },
  );

  test(
    'confirmation must acknowledge the exact generation before native activation',
    () async {
      f.seed();
      final server = ConsumingServer(f)..install();
      f.onConfirm = (_) async =>
          http.Response('{"status":"active","generation":999}', 200);
      await f.service.initialize(f.manager);
      expect(f.service.active, isFalse);
      expect(f.native['confirmation_attempt'], isTrue);
      expect(f.methods, isNot(contains('activate')));
      server.install();
      f.restart();
      await f.service.initialize(f.manager);
      expect(f.service.active, isTrue);
      expect(server.generation, 2);
    },
  );

  test(
    'legacy gen-zero lost PUT without journal converges after conflict and retry',
    () async {
      f.seed();
      final server = ConsumingServer(f)..generation = 1;
      server.nonces.add(f.native['nonce'] as String);
      server.install();
      await f.service.initialize(f.manager);
      expect(f.service.active, isFalse);
      expect(f.native['registration_attempt'], isTrue);
      await f.service.retry();
      expect(server.generation, 2);
      expect(f.service.active, isTrue);
    },
  );

  for (final ids in [
    List.generate(129, (i) => 'session-$i'),
    ['x' * 201],
    ['invalid/session'],
    ['non-ascii-é'],
    ['valid', ''],
    [' leading-space'],
    ['trailing-newline\n'],
  ]) {
    test(
      'invalid scope fails before permission, native enable or HTTP: ${ids.length}/${ids.first.length}',
      () async {
        await f.service.initialize(f.manager);
        await expectLater(
          f.service.enable(f.connection, 'test.distributor', ids),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'actionable scope error',
              contains('128'),
            ),
          ),
        );
        expect(f.service.error, contains('1–128'));
        expect(f.service.error, contains('1–200 ASCII'));
        expect(f.requests, isEmpty);
        expect(f.methods, isNot(contains('permission')));
        expect(f.methods, isNot(contains('enable')));
      },
    );
  }

  test(
    '128 IDs, 200 ASCII characters and all allowed punctuation preserve exact scope',
    () async {
      await f.service.initialize(f.manager);
      final ids = [
        'x' * 200,
        'AZaz09_.:@-',
        ...List.generate(126, (i) => 's$i'),
      ];
      await f.service.enable(f.connection, 'test.distributor', ids);
      expect(f.native['sessions'], ids);
      expect(f.methods.where((m) => m == 'permission'), hasLength(1));
    },
  );
}
