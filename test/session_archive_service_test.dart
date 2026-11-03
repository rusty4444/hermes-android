import 'dart:async';
import 'dart:convert';

// fake_async is supplied by the existing flutter_test SDK dependency.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sessionId = 'stored-session';

ApiClient _api(
  Future<http.Response> Function(http.Request) handler, {
  String baseUrl = 'https://gateway.example:9443',
  String pathPrefix = '',
}) {
  final client = MockClient(handler);
  addTearDown(client.close);
  return ApiClient(
    baseUrl: baseUrl,
    pathPrefix: pathPrefix,
    apiKey: 'dummy-archive-test-key',
    httpClient: client,
  );
}

http.Response _confirmed(
  bool archived, {
  String sessionId = _sessionId,
  int status = 200,
}) => http.Response(
  jsonEncode({
    'session': {'id': sessionId, 'archived': archived},
  }),
  status,
  headers: const {'content-type': 'application/json'},
);

/// Both the mutation acknowledgement and detail read must identify the exact
/// stored session and carry an explicit JSON boolean, including for unarchive.
Map<String, String> _invalidBodies(bool archived) => {
  'invalid JSON': '{not-json',
  'empty body': '',
  'null document': 'null',
  'list document': '[]',
  'boolean document': 'true',
  'number document': '1',
  'string document': '"not metadata"',
  'empty object': '{}',
  'error JSON with HTTP success': jsonEncode({
    'error': {'code': 'archive_failed', 'message': 'not saved'},
  }),
  'wrong wrapper': jsonEncode({
    'data': {'id': _sessionId, 'archived': archived},
  }),
  'null session': '{"session":null}',
  'list session': '{"session":[]}',
  'string session': '{"session":"stored-session"}',
  'empty session': '{"session":{}}',
  'missing id': jsonEncode({
    'session': {'archived': archived},
  }),
  'null id': jsonEncode({
    'session': {'id': null, 'archived': archived},
  }),
  'numeric id': jsonEncode({
    'session': {'id': 123, 'archived': archived},
  }),
  'different id': jsonEncode({
    'session': {'id': 'another-session', 'archived': archived},
  }),
  'padded id is not the exact requested id': jsonEncode({
    'session': {'id': ' $_sessionId ', 'archived': archived},
  }),
  'lineage alias is not the exact requested id': jsonEncode({
    'session': {
      'id': 'compressed-tip',
      '_lineage_root_id': _sessionId,
      'archived': archived,
    },
  }),
  'missing archived': jsonEncode({
    'session': {'id': _sessionId},
  }),
  'null archived': jsonEncode({
    'session': {'id': _sessionId, 'archived': null},
  }),
  'opposite archived': jsonEncode({
    'session': {'id': _sessionId, 'archived': !archived},
  }),
  'string archived': jsonEncode({
    'session': {'id': _sessionId, 'archived': '$archived'},
  }),
  'numeric archived': jsonEncode({
    'session': {'id': _sessionId, 'archived': archived ? 1 : 0},
  }),
  'list archived': jsonEncode({
    'session': {
      'id': _sessionId,
      'archived': [archived],
    },
  }),
  'object archived': jsonEncode({
    'session': {
      'id': _sessionId,
      'archived': {'value': archived},
    },
  }),
};

void main() {
  group('ApiClient.setSessionArchived', () {
    for (final archived in [true, false]) {
      final action = archived ? 'archive' : 'unarchive';

      test(
        '$action sends only the explicit flag and authenticates both calls',
        () async {
          const id = ' session/a ?#%+é雪 ';
          const expectedUrl =
              'https://gateway.example:9443/root/edge%20proxy/team%2Falpha/'
              'api/sessions/'
              '%20session%2Fa%20%3F%23%25%2B%C3%A9%E9%9B%AA%20';
          final requests = <http.Request>[];
          final api = _api(
            (request) async {
              requests.add(request);
              return _confirmed(archived, sessionId: id);
            },
            baseUrl: 'https://gateway.example:9443/root/',
            pathPrefix: '/edge%20proxy/team%2Falpha/',
          );

          expect(
            await api.setSessionArchived(sessionId: id, archived: archived),
            archived,
          );

          expect(requests.map((request) => request.method), ['PATCH', 'GET']);
          for (final request in requests) {
            expect(request.url.toString(), expectedUrl);
            expect(request.url.query, isEmpty);
            expect(request.url.fragment, isEmpty);
            expect(
              request.headers['authorization'],
              'Bearer dummy-archive-test-key',
            );
            expect(
              request.headers['content-type'],
              startsWith('application/json'),
            );
          }
          expect(jsonDecode(requests.first.body), {'archived': archived});
          expect(requests.last.body, isEmpty);
        },
      );

      for (final id in ['', ' ', '\t\r\n']) {
        test('$action rejects blank id ${jsonEncode(id)} before I/O', () async {
          final requests = <http.Request>[];
          final api = _api((request) async {
            requests.add(request);
            return _confirmed(archived);
          });

          await expectLater(
            api.setSessionArchived(sessionId: id, archived: archived),
            throwsArgumentError,
          );
          expect(requests, isEmpty);
        });
      }

      for (final status in [200, 201, 202, 206, 299]) {
        test(
          '$action accepts PATCH $status only after exact read-back',
          () async {
            final requests = <http.Request>[];
            final api = _api((request) async {
              requests.add(request);
              return _confirmed(
                archived,
                status: request.method == 'PATCH' ? status : 200,
              );
            });

            expect(
              await api.setSessionArchived(
                sessionId: _sessionId,
                archived: archived,
              ),
              archived,
            );
            expect(requests.map((request) => request.method), ['PATCH', 'GET']);
            expect(
              requests.map((request) => request.url.toString()),
              everyElement(
                'https://gateway.example:9443/api/sessions/$_sessionId',
              ),
            );
          },
        );
      }

      for (final status in [
        199,
        300,
        302,
        400,
        401,
        403,
        404,
        409,
        422,
        500,
        503,
      ]) {
        test(
          '$action rejects PATCH $status even with a matching body',
          () async {
            final requests = <http.Request>[];
            final api = _api((request) async {
              requests.add(request);
              return _confirmed(archived, status: status);
            });

            await expectLater(
              api.setSessionArchived(sessionId: _sessionId, archived: archived),
              throwsA(
                isA<Exception>().having(
                  (error) => error.toString(),
                  'message',
                  contains('HTTP $status'),
                ),
              ),
            );
            expect(requests.map((request) => request.method), ['PATCH']);
          },
        );
      }

      for (final invalid in _invalidBodies(archived).entries) {
        test(
          '$action rejects PATCH ${invalid.key} without a read-back',
          () async {
            final requests = <http.Request>[];
            final api = _api((request) async {
              requests.add(request);
              return http.Response(invalid.value, 200);
            });

            await expectLater(
              api.setSessionArchived(sessionId: _sessionId, archived: archived),
              throwsFormatException,
            );
            expect(requests.map((request) => request.method), ['PATCH']);
          },
        );

        test('$action rejects read-back ${invalid.key}', () async {
          final requests = <http.Request>[];
          final api = _api((request) async {
            requests.add(request);
            return request.method == 'PATCH'
                ? _confirmed(archived)
                : http.Response(invalid.value, 200);
          });

          // apiGet currently rejects non-object top-level JSON by cast. Keep
          // those implementation-specific failures distinct from a malformed
          // session object or a failed exact-ID/archive-state verification.
          final nonObjectDocument = const {
            'null document',
            'list document',
            'boolean document',
            'number document',
            'string document',
          }.contains(invalid.key);
          await expectLater(
            api.setSessionArchived(sessionId: _sessionId, archived: archived),
            nonObjectDocument
                ? throwsA(isA<TypeError>())
                : throwsFormatException,
          );
          expect(requests.map((request) => request.method), ['PATCH', 'GET']);
        });
      }

      for (final status in [204, 301, 401, 404, 409, 500, 503]) {
        test(
          '$action rejects read-back HTTP $status after a valid PATCH',
          () async {
            final requests = <http.Request>[];
            final api = _api((request) async {
              requests.add(request);
              return _confirmed(
                archived,
                status: request.method == 'PATCH' ? 200 : status,
              );
            });

            await expectLater(
              api.setSessionArchived(sessionId: _sessionId, archived: archived),
              throwsA(
                isA<Exception>().having(
                  (error) => error.toString(),
                  'message',
                  contains('HTTP $status'),
                ),
              ),
            );
            expect(requests.map((request) => request.method), ['PATCH', 'GET']);
          },
        );
      }

      for (final failingMethod in ['PATCH', 'GET']) {
        test('$action propagates $failingMethod transport errors', () async {
          final error = http.ClientException('dummy transport failure');
          final requests = <http.Request>[];
          final api = _api((request) async {
            requests.add(request);
            if (request.method == failingMethod) throw error;
            return _confirmed(archived);
          });

          await expectLater(
            api.setSessionArchived(sessionId: _sessionId, archived: archived),
            throwsA(same(error)),
          );
          expect(
            requests.map((request) => request.method),
            failingMethod == 'PATCH' ? ['PATCH'] : ['PATCH', 'GET'],
          );
        });
      }

      test('$action does not return while exact read-back is held', () async {
        final readStarted = Completer<void>();
        final readBack = Completer<http.Response>();
        final requests = <http.Request>[];
        final api = _api((request) async {
          requests.add(request);
          if (request.method == 'PATCH') return _confirmed(archived);
          readStarted.complete();
          return readBack.future;
        });
        var completed = false;
        final operation = api
            .setSessionArchived(sessionId: _sessionId, archived: archived)
            .then((value) {
              completed = true;
              return value;
            });
        final verified = expectLater(operation, completion(archived));

        await readStarted.future;
        expect(requests.map((request) => request.method), ['PATCH', 'GET']);
        expect(completed, isFalse);

        readBack.complete(_confirmed(archived));
        await verified;
        expect(completed, isTrue);
      });

      test(
        '$action does not start verification before PATCH completes',
        () async {
          final patchStarted = Completer<void>();
          final patchReply = Completer<http.Response>();
          final requests = <http.Request>[];
          final api = _api((request) async {
            requests.add(request);
            if (request.method == 'PATCH') {
              patchStarted.complete();
              return patchReply.future;
            }
            return _confirmed(archived);
          });
          final operation = api.setSessionArchived(
            sessionId: _sessionId,
            archived: archived,
          );
          final verified = expectLater(operation, completion(archived));

          await patchStarted.future;
          expect(requests.map((request) => request.method), ['PATCH']);
          patchReply.complete(_confirmed(archived));
          await verified;
          expect(requests.map((request) => request.method), ['PATCH', 'GET']);
        },
      );

      for (final heldMethod in ['PATCH', 'GET']) {
        test('$action bounds a held $heldMethod to 20 seconds', () {
          fakeAsync((clock) {
            final heldReply = Completer<http.Response>();
            final methods = <String>[];
            final api = _api((request) async {
              methods.add(request.method);
              return request.method == heldMethod
                  ? heldReply.future
                  : _confirmed(archived);
            });
            var completed = false;
            bool? value;
            Object? error;
            api
                .setSessionArchived(sessionId: _sessionId, archived: archived)
                .then<void>(
                  (result) {
                    completed = true;
                    value = result;
                  },
                  onError: (Object failure, StackTrace stack) {
                    completed = true;
                    error = failure;
                  },
                );
            clock.flushMicrotasks();

            expect(ApiClient.requestTimeout, const Duration(seconds: 20));
            final expectedMethods = heldMethod == 'PATCH'
                ? ['PATCH']
                : ['PATCH', 'GET'];
            expect(methods, expectedMethods);
            clock.elapse(const Duration(milliseconds: 19999));
            expect(completed, isFalse);
            clock.elapse(const Duration(milliseconds: 1));
            clock.flushMicrotasks();
            expect(completed, isTrue);
            expect(error, isA<TimeoutException>());
            expect(value, isNull);

            // A late success cannot turn timeout into success or trigger a
            // follow-on verification after the mutation already failed.
            heldReply.complete(_confirmed(archived));
            clock.flushMicrotasks();
            expect(error, isA<TimeoutException>());
            expect(value, isNull);
            expect(methods, expectedMethods);
            expect(clock.pendingTimers, isEmpty);
          });
        });
      }
    }
  });
}
