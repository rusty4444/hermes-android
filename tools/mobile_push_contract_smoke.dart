// Opt-in TCP consumer. Run through test_dart_contract_smoke.py, not test/ discovery.
// No native bridge, device, GMS or installed authentication provider is exercised.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/mobile_push_api.dart';
import 'package:http/http.dart' as http;

void main() {
  final encoded = Platform.environment['MOBILE_PUSH_SMOKE_SPEC'];
  test(
    'production Dart automatic push consumes real Python router over TCP',
    () async {
      final spec = jsonDecode(encoded!) as Map<String, dynamic>;
      final control = http.Client();
      final client = DashboardClient(
        host: '127.0.0.1',
        port: spec['port'] as int,
        username: 'alice',
        password: spec['password'] as String,
        gatewayProfile: 'contract-profile',
      );
      addTearDown(control.close);
      addTearDown(client.close);
      final api = MobilePushApi(client);
      Future<Map<String, dynamic>> fixture(
        String action, [
        Map<String, dynamic> args = const {},
      ]) async {
        final response = await control.post(
          Uri.parse('http://127.0.0.1:${spec['port']}/__smoke/$action'),
          headers: {
            'Content-Type': 'application/json',
            'X-Smoke-Secret': spec['secret'] as String,
          },
          body: jsonEncode(args),
        );
        expect(response.statusCode, 200, reason: response.body);
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      Future<void> rejected(
        Future<Object?> operation,
        int status,
      ) => expectLater(
        operation,
        throwsA(
          predicate<Object>(
            (e) => e is DashboardHttpException
                ? e.statusCode == status
                : e.toString() == 'Exception: HTTP $status',
            'HTTP $status (GET uses typed exception; PUT/POST use generic exception)',
          ),
        ),
      );
      final state = <String, dynamic>{
        'installation': 'dart-contract-phone',
        'endpoint': spec['endpoint'],
        'keys': spec['keys'],
        'nonce': 'dart_contract_nonce_0123456789',
        'revision': 1,
        'session_scope': 'authorized',
        'sessions': <String>[],
      };
      expect(
        (await api.capabilities(authorized: true))['session_scope_modes'],
        contains('authorized'),
      );
      final first = await api.register(state);
      expect(first['status'], 'pending');
      expect(first['registration_revision'], 1);
      final proof1 = await fixture(
        'proof',
      ); // Real TLS sender + independent subscriber decrypt/VAPID verify.
      expect(proof1['registration_nonce'], state['nonce']);
      expect(proof1['generation'], first['generation']);
      expect(
        (await api.confirm(
          state['installation'] as String,
          first['generation'] as int,
          proof1['challenge'] as String,
        ))['status'],
        'active',
      );
      await fixture(
        'future-events',
      ); // Session does not exist at registration time.
      state['generation'] = first['generation'];
      final page1 = await api.events('0', state: state);
      expect(page1['has_more'], isTrue);
      expect(page1['events'], hasLength(100));
      final cursor = '${page1['next_cursor']}';
      final page2 = await api.events(cursor, state: state);
      expect(page2['has_more'], isFalse);
      expect(page2['events'], hasLength(1));
      final events = [...page1['events'] as List, ...page2['events'] as List];
      expect(events.map((e) => e['event_id']).toSet(), hasLength(101));
      expect(events.every((e) => e['session_id'] == 'future-session'), isTrue);
      // Corrupt only real second-page authority echoes; production parser must fail closed.
      for (final field in [
        'installation_id',
        'generation',
        'session_scope',
        'missing',
        'string_generation',
      ]) {
        await fixture('mismatch', {'field': field});
        await expectLater(
          api.events(cursor, state: state),
          throwsFormatException,
        );
      }
      // Re-enrolment advances the production server fence; old binding/proof must fail.
      state.addAll({
        'revision': 2,
        'nonce': 'dart_contract_recovery_0123456789',
      });
      final second = await api.register(state);
      expect(second['generation'], greaterThan(first['generation'] as int));
      await rejected(api.events('0', state: state), 409);
      await rejected(
        api.confirm(
          state['installation'] as String,
          first['generation'] as int,
          proof1['challenge'] as String,
        ),
        409,
      );
      final proof2 = await fixture('proof');
      expect(proof2['challenge'], isNot(proof1['challenge']));
      expect(
        (await api.confirm(
          state['installation'] as String,
          second['generation'] as int,
          proof2['challenge'] as String,
        ))['status'],
        'active',
      );
      state['generation'] = second['generation'];
      await api.events('0', state: state);
      await fixture('deny');
      await rejected(
        api.events('0', state: state),
        401,
      ); // Bounded retry, not infinite re-login.
      await fixture('allow');
      await api.revoke(state['installation'] as String);
      await rejected(api.events('0', state: state), 409);
      await rejected(
        api.confirm(
          state['installation'] as String,
          second['generation'] as int,
          proof2['challenge'] as String,
        ),
        409,
      );
      await rejected(api.register(state), 409);
      final report = await fixture('report');
      expect(report['revoked'], isTrue);
      expect(report['future_event_count'], 101);
      expect(report['forced_401_operations'], 5);
      // Machine-readable completion marker consumed by the Python orchestrator.
      // ignore: avoid_print
      print('DART_PYTHON_PUSH_CONTRACT_OK ${jsonEncode(report)}');
    },
    skip: encoded == null
        ? 'Run opt-in Python orchestrator; no external server implied.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
