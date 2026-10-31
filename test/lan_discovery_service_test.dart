import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/lan_discovery_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const health = '{"status":"ok","platform":"hermes-agent","version":"test"}';

class TrackingClient extends http.BaseClient {
  TrackingClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  int closes = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() {
    closes++;
  }
}

Future<List<InternetAddress>> local() async => [InternetAddress('192.168.1.5')];

void main() {
  test('recognises actual Hermes health identity, not incidental words', () {
    final service = LanDiscoveryService();
    expect(service.looksLikeHermes(health), isTrue);
    for (final body in [
      'ok',
      'Gateway ready',
      '<html>Hermes status ok</html>',
      '{"status":"ok"}',
      '{"status":"ok","name":"Hermes"}',
      '{"status":"failed","platform":"hermes-agent"}',
      '{"status":"ok","platform":"other-gateway"}',
      '[]',
      'null',
      '42',
      '"hermes"',
      '{"status":true}',
    ]) {
      expect(service.looksLikeHermes(body), isFalse, reason: body);
    }
    for (final body in ['[]', 'null', '42', '{"name":42}', 'invalid']) {
      expect(service.guessLabel('host', body), 'Hermes (host)');
    }
    expect(service.guessLabel('host', '{"name":"Home"}'), 'Home (host)');
  });

  test(
    'bounds and deduplicates private IPv4 neighbourhoods; no public sweep',
    () {
      final service = LanDiscoveryService(maxHosts: 300);
      final hosts = service.candidateHosts([
        InternetAddress('127.0.0.1'),
        InternetAddress('0.0.0.0'),
        InternetAddress('8.8.8.8'),
        InternetAddress('224.0.0.1'),
        InternetAddress('192.168.1.5'),
        InternetAddress('192.168.1.8'),
        InternetAddress('10.0.0.7'),
        InternetAddress('172.16.2.3'),
      ]);
      expect(hosts, hasLength(300));
      expect(hosts.toSet(), hasLength(300));
      expect(hosts.first, '192.168.1.1');
      expect(hosts[253], '192.168.1.254');
      expect(hosts.last, '10.0.0.46');
    },
  );

  test(
    'IPv6 uses exact compressed/scoped hosts, with URI-only brackets',
    () async {
      final requests = <Uri>[];
      final addresses = [
        InternetAddress('fd00::abcd'),
        InternetAddress('fe80::1%en0'),
      ];
      final service = LanDiscoveryService(
        resolveAddresses: () async => addresses,
        clientFactory: () => MockClient((request) async {
          requests.add(request.url);
          return http.Response(health, 200);
        }),
      );
      final servers = await service.discover();
      expect(servers.map((s) => s.host).toSet(), {'fd00::abcd', 'fe80::1%en0'});
      expect(requests.map((u) => u.path), everyElement('/health'));
      expect(
        requests.map((u) => u.toString()),
        contains('http://[fd00::abcd]:8642/health'),
      );
      expect(servers.first.displayName, '[fd00::abcd]:8642');
      expect(
        service.candidateHosts([InternetAddress('::'), InternetAddress('::1')]),
        isEmpty,
      );
    },
  );

  test(
    'probes hosts concurrently within cap; exact GET path; no HTTPS after match',
    () async {
      final held = <Completer<http.Response>>[];
      final requests = <http.Request>[];
      var active = 0;
      var peak = 0;
      final service = LanDiscoveryService(
        resolveAddresses: local,
        maxHosts: 7,
        concurrency: 3,
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          active++;
          if (active > peak) peak = active;
          final done = Completer<http.Response>();
          held.add(done);
          final response = await done.future;
          active--;
          return response;
        }),
      );
      final result = service.discover();
      await pumpEventQueue();
      expect(requests, hasLength(3));
      expect(peak, 3);
      while (held.any((c) => !c.isCompleted)) {
        for (final c in held.toList()) {
          if (!c.isCompleted) c.complete(http.Response(health, 200));
        }
        await pumpEventQueue();
      }
      final servers = await result;
      expect(servers, hasLength(7));
      expect(requests, hasLength(7));
      expect(peak, 3);
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.url.path, '/health');
        expect(request.url.scheme, 'http');
        expect(request.followRedirects, isFalse);
        expect(request.headers['Accept'], 'application/json');
      }
      expect(
        servers.map((s) => s.host),
        orderedEquals(servers.map((s) => s.host).toList()..sort()),
      );
    },
  );

  test(
    'HTTPS fallback preserves protocol and ignores HTTP impostors/errors',
    () async {
      final requests = <Uri>[];
      final clients = <TrackingClient>[];
      final service = LanDiscoveryService(
        resolveAddresses: local,
        maxHosts: 3,
        clientFactory: () {
          final client = TrackingClient((request) async {
            requests.add(request.url);
            if (request.url.scheme == 'http') {
              if (request.url.host.endsWith('.1')) {
                throw const SocketException('offline');
              }
              return http.StreamedResponse(
                Stream.value(utf8.encode('ok')),
                200,
              );
            }
            return http.StreamedResponse(
              Stream.value(utf8.encode(health)),
              request.url.host.endsWith('.3') ? 401 : 200,
            );
          });
          clients.add(client);
          return client;
        },
      );
      final servers = await service.discover();
      expect(servers, hasLength(2));
      expect(servers.every((s) => s.useHttps), isTrue);
      expect(requests, hasLength(6));
      expect(clients.every((c) => c.closes > 0), isTrue);
    },
  );

  test(
    'probe timeout closes silent clients and permits bounded fallback',
    () async {
      final clients = <TrackingClient>[];
      final service = LanDiscoveryService(
        resolveAddresses: local,
        maxHosts: 2,
        concurrency: 2,
        probeTimeout: const Duration(milliseconds: 10),
        clientFactory: () {
          final c = TrackingClient(
            (_) => Completer<http.StreamedResponse>().future,
          );
          clients.add(c);
          return c;
        },
      );
      expect(await service.discover(), isEmpty);
      expect(clients, hasLength(4));
      expect(clients.every((c) => c.closes > 0), isTrue);
    },
  );

  test(
    'cancel closes active clients, stops queue/fallback, allows fresh scan',
    () async {
      final clients = <TrackingClient>[];
      var respond = false;
      final service = LanDiscoveryService(
        resolveAddresses: local,
        maxHosts: 20,
        concurrency: 2,
        clientFactory: () {
          final c = TrackingClient((_) async {
            if (respond) {
              return http.StreamedResponse(
                Stream.value(utf8.encode(health)),
                200,
              );
            }
            return Completer<http.StreamedResponse>().future;
          });
          clients.add(c);
          return c;
        },
      );
      final result = service.discover();
      await pumpEventQueue();
      await expectLater(service.discover(), throwsStateError);
      expect(clients, hasLength(2));
      service.cancel();
      expect(await result, isEmpty);
      expect(clients, hasLength(2));
      expect(clients.every((c) => c.closes > 0), isTrue);
      respond = true;
      expect(await service.discover(), hasLength(20));
    },
  );

  test(
    'cancel during interface resolution does not start network probes',
    () async {
      final resolver = Completer<List<InternetAddress>>();
      final service = LanDiscoveryService(
        resolveAddresses: () => resolver.future,
        clientFactory: () => throw StateError('must not probe'),
      );
      final result = service.discover();
      service.cancel();
      expect(await result, isEmpty);
      resolver.complete(await local());
      await pumpEventQueue();
    },
  );

  test(
    'overall deadline bounds even stalled resolution, and resets busy state',
    () async {
      final service = LanDiscoveryService(
        resolveAddresses: () => Completer<List<InternetAddress>>().future,
        scanTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(service.discover(), throwsA(isA<TimeoutException>()));
      await expectLater(service.discover(), throwsA(isA<TimeoutException>()));
    },
  );

  test(
    'overall deadline closes active probes without starting queued hosts',
    () async {
      final clients = <TrackingClient>[];
      final service = LanDiscoveryService(
        resolveAddresses: local,
        maxHosts: 20,
        concurrency: 2,
        scanTimeout: const Duration(milliseconds: 20),
        clientFactory: () {
          final client = TrackingClient(
            (_) => Completer<http.StreamedResponse>().future,
          );
          clients.add(client);
          return client;
        },
      );
      await expectLater(service.discover(), throwsA(isA<TimeoutException>()));
      expect(clients, hasLength(2));
      expect(clients.every((client) => client.closes > 0), isTrue);
    },
  );

  test(
    'probe deadline bounds stalled streams and tolerates late transport errors',
    () async {
      final streams = <StreamController<List<int>>>[];
      var cancelled = 0;
      final service = LanDiscoveryService(
        resolveAddresses: local,
        maxHosts: 1,
        probeTimeout: const Duration(milliseconds: 10),
        clientFactory: () => TrackingClient((_) async {
          final stream = StreamController<List<int>>(
            onCancel: () => cancelled++,
          );
          streams.add(stream);
          return http.StreamedResponse(stream.stream, 200);
        }),
      );
      expect(await service.discover(), isEmpty);
      // Closing the transport ends its response stream. Model that late close
      // explicitly to verify the losing read future cannot surface errors.
      for (final stream in streams) {
        stream.addError(const SocketException('closed after timeout'));
        await stream.close();
      }
      await pumpEventQueue();
      expect(streams, hasLength(2));
      expect(cancelled, 2);
    },
  );

  test(
    'caps response body, rejects redirects and malformed UTF8/JSON',
    () async {
      var count = 0;
      final service = LanDiscoveryService(
        resolveAddresses: local,
        maxHosts: 4,
        clientFactory: () => TrackingClient((request) async {
          count++;
          final last = request.url.host.split('.').last;
          final bytes = switch (last) {
            '1' => utf8.encode('x' * 16385),
            '2' => [255],
            '3' => utf8.encode('[]'),
            _ => utf8.encode(health),
          };
          return http.StreamedResponse(
            Stream.value(bytes),
            last == '4' ? 302 : 200,
          );
        }),
      );
      expect(await service.discover(), isEmpty);
      expect(count, 8);
    },
  );

  test(
    'no eligible interfaces means no clients; resolver errors release busy state',
    () async {
      final service = LanDiscoveryService(
        resolveAddresses: () async => [],
        clientFactory: () => throw StateError('must not probe'),
      );
      expect(await service.discover(), isEmpty);
      final failing = LanDiscoveryService(
        resolveAddresses: () async => throw StateError('resolver'),
      );
      await expectLater(failing.discover(), throwsStateError);
      await expectLater(failing.discover(), throwsStateError);
      expect(() => LanDiscoveryService(concurrency: 0), throwsArgumentError);
      expect(() => LanDiscoveryService(maxHosts: 1017), throwsArgumentError);
    },
  );
}
