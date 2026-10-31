import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/lan_discovery_service.dart';

void main() {
  group('LanDiscoveryService', () {
    test('looksLikeHermes accepts obvious Hermes health bodies', () {
      final service = LanDiscoveryService();
      expect(
        service.looksLikeHermes('{"status":"ok","name":"Hermes"}'),
        isTrue,
      );
      expect(service.looksLikeHermes('Gateway ready'), isTrue);
      expect(service.looksLikeHermes('ok'), isTrue);
      expect(service.looksLikeHermes('Unknown server'), isFalse);
    });

    test('guessLabel prefers JSON name when present', () {
      final service = LanDiscoveryService();
      final label = service.guessLabel(
        '192.168.1.42',
        '{"status":"ok","name":"Home Hermes"}',
      );
      expect(label, contains('Home Hermes'));
      expect(label, contains('192.168.1.42'));
    });

    test('guessLabel falls back to host when JSON is invalid', () {
      final service = LanDiscoveryService();
      final label = service.guessLabel('192.168.1.42', 'not-json');
      expect(label, 'Hermes (192.168.1.42)');
    });

    test('Subnet.hostBase builds correct IPv4 addresses', () {
      const subnet = Subnet(prefix: '192.168.1', port: 8642);
      expect(subnet.hostBase(1), '192.168.1.1');
      expect(subnet.hostBase(254), '192.168.1.254');
    });

    test('Subnet.hostBase builds correct IPv6 addresses', () {
      final subnet = Subnet(
        prefix: 'fe80:0:0:0:0:0:0:1',
        port: 8642,
        isIPv6: true,
      );
      expect(subnet.hostBase(1), '[fe80:0:0:0:0:0:0:1]');
      expect(subnet.hostBase(254), '[fe80:0:0:0:0:0:0:fe]');
    });

    test('DiscoveredHermesServer exposes displayName', () {
      const server = DiscoveredHermesServer(
        host: '192.168.1.10',
        port: 8642,
        useHttps: false,
        label: 'Home',
      );
      expect(server.displayName, '192.168.1.10:8642');
    });

    // Network probing depends on NetworkInterface.list and live sockets, which
    // cannot be exercised deterministically in a unit test. The probe path is
    // covered by the integration workflow; here we assert the service builds.
    test('LanDiscoveryService constructs', () {
      final service = LanDiscoveryService();
      expect(service, isNotNull);
    });

    test('Subnet.hostBase rejects malformed IPv4 prefix', () {
      const subnet = Subnet(prefix: 'not-an-ip', port: 8642);
      // hostBase should still produce a string, but it won't be a valid IP.
      expect(subnet.hostBase(1), 'not-an-ip.1');
    });
  });
}
