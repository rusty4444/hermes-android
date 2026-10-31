import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/mobile_push_api.dart';
import 'package:hermes_android/core/services/notification_prefs.dart';
import 'package:http/http.dart' as http;

import 'mobile_push_service_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Fixture f;
  setUp(() async {
    notificationPrefs.value = NotificationPrefs.defaults;
    f = fixture.Fixture();
    await f.setup();
  });
  tearDown(() => f.close());

  void authorized({bool active = true}) {
    f.seed(active: active);
    f.native.addAll({'session_scope': 'authorized', 'sessions': <String>[]});
  }

  test(
    'automatic uses authorized scope and default transport; explicit override preserved',
    () async {
      await f.service.initialize(f.manager);
      await f.service.enableAutomatic(f.connection);
      expect(f.native['sessions'], isEmpty);
      expect(f.native['session_scope'], 'authorized');
      expect(f.native['distributor'], 'automatic');
      expect(f.service.active, isFalse); // presence is not endpoint/activation
      await f.service.disable();
      await f.service.enableAutomatic(
        f.connection,
        distributor: 'test.distributor',
      );
      expect(f.native['distributor'], 'test.distributor');
    },
  );

  for (final modes in <List<String>?>[
    null,
    [],
    ['explicit'],
  ]) {
    test('automatic needs advertised authorized capability: $modes', () async {
      f.scopeModes = modes;
      await f.service.initialize(f.manager);
      await expectLater(
        f.service.enableAutomatic(f.connection),
        throwsFormatException,
      );
      expect(f.methods, isNot(contains('permission')));
      expect(f.methods, isNot(contains('enable')));
    });
  }

  test(
    'authorized PUT omits IDs and retains nonce/revision; event query binds authority/profile',
    () async {
      authorized(active: false);
      f.onPut = (request) async {
        final body = jsonDecode(request.body) as Map;
        expect(body['session_scope'], 'authorized');
        expect(body.containsKey('session_ids'), isFalse);
        expect(body['registration_nonce'], f.native['nonce']);
        expect(body['registration_revision'], f.native['revision']);
        f.challenge();
        return f.pending();
      };
      f.feed = [f.event('valid', session: 'new-durable-session')];
      await f.service.initialize(f.manager);
      expect(f.service.active, isTrue);
      expect(f.service.events.single['session_id'], 'new-durable-session');
      final request = f.requests.singleWhere(
        (r) => r.url.path.endsWith('/events'),
      );
      expect(
        request.url.queryParameters['installation_id'],
        f.native['installation'],
      );
      expect(request.url.queryParameters['generation'], '7');
      expect(
        request.url.queryParameters['profile'],
        f.connection.gatewayProfile,
      );
    },
  );

  for (final malformed in [
    {'session_scope': 'unknown', 'sessions': <String>[]},
    {
      'session_scope': 'authorized',
      'sessions': ['a'],
    },
  ]) {
    test(
      'API rejects malformed sealed scope before HTTP: $malformed',
      () async {
        f.seed();
        f.native.addAll(malformed);
        final client = f.clientFactory(f.connection);
        addTearDown(client.close);
        await expectLater(
          MobilePushApi(client).register(f.native),
          throwsFormatException,
        );
        expect(f.requests, isEmpty);
      },
    );
  }

  for (final mismatch in [
    'installation_id',
    'generation',
    'coerced generation',
    'session_scope',
    'missing',
  ]) {
    for (final page in [0, 1]) {
      test(
        'authorized events reject $mismatch on page $page without accepting partial events',
        () async {
          authorized();
          f.feed = [f.event('formerly-valid')];
          await f.service.initialize(f.manager);
          var calls = 0;
          f.onEvents = (_) async {
            final echo = <String, dynamic>{
              'installation_id': f.native['installation'],
              'generation': 7,
              'session_scope': 'authorized',
              'events': [f.event('page-$calls')],
              'has_more': calls == 0,
              'next_cursor': '1',
            };
            if (calls++ == page) {
              if (mismatch == 'missing') {
                echo.remove('installation_id');
              } else if (mismatch == 'coerced generation') {
                echo['generation'] = '7';
              } else {
                echo[mismatch] = mismatch == 'generation' ? 8 : 'wrong';
              }
            }
            return http.Response(jsonEncode(echo), 200);
          };
          await f.service.refresh();
          expect(f.service.status, 'Error');
          expect(f.service.events, isEmpty);
          expect(await f.service.takePendingNotificationRoute(), isNull);
        },
      );
    }
  }

  test(
    'authorized routing accepts only durable authenticated live kinds and IDs',
    () async {
      authorized();
      f.feed = [
        f.event('valid', session: 'not-an-explicit-id'),
        f.event('url', session: 'https://evil.invalid/session'),
        f.event('whitespace', session: ' session'),
        f.event('', session: 'a'),
        f.event('bad-kind', kind: 'approve'),
        f.event('old', expires: 1),
      ];
      f.tap('url');
      await f.service.initialize(f.manager);
      expect(f.service.events.map((e) => e['event_id']), ['valid']);
      expect(await f.service.takePendingNotificationRoute(), isNull);
      f.tap('valid');
      await f.service.refresh();
      final route = await f.service.takePendingNotificationRoute();
      expect(route?.sessionId, 'not-an-explicit-id');
      await f.service.disable();
      expect(await f.service.isRouteCurrent(route!), isFalse);
    },
  );

  test(
    'disable during authorized event HTTP discards late bound page',
    () async {
      authorized();
      await f.service.initialize(f.manager);
      final entered = Completer<void>();
      final release = Completer<http.Response>();
      f.onEvents = (_) {
        entered.complete();
        return release.future;
      };
      final refresh = f.service.refresh();
      await entered.future;
      final disable = f.service.disable();
      release.complete(
        http.Response(
          jsonEncode({
            'installation_id': 'fixture-installation',
            'generation': 7,
            'session_scope': 'authorized',
            'events': [f.event('late')],
            'has_more': false,
          }),
          200,
        ),
      );
      await refresh;
      await disable;
      expect(f.service.events, isEmpty);
      expect(f.service.enabled, isFalse);
    },
  );
  test(
    'unconsumed authenticated tap survives another successful reconciliation',
    () async {
      authorized();
      f.feed = [f.event('valid')];
      f.tap('valid');
      await f.service.initialize(f.manager);
      expect(f.service.hasPendingTap, isTrue);
      await f.service.refresh();
      expect(
        (await f.service.takePendingNotificationRoute())?.eventId,
        'valid',
      );
    },
  );
}
