import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class LanDiscoveryService {
  static const _defaultPort = 8642;
  static const _healthPath = '/health';
  static const _probeTimeout = Duration(seconds: 2);
  static const _concurrency = 64;

  Future<List<DiscoveredHermesServer>> discover() async {
    final subnets = await _localSubnets();
    if (subnets.isEmpty) return [];

    final discovered = <DiscoveredHermesServer>[];
    final pending = <Completer<void>>[];
    int active = 0;

    for (final subnet in subnets) {
      while (active >= _concurrency) {
        await Future.any(pending.map((c) => c.future));
        pending.removeWhere((c) => c.isCompleted);
        active = pending.length;
      }

      final lock = Completer<void>();
      pending.add(lock);
      active++;

      unawaited(
        _probeSubnet(subnet, discovered).whenComplete(() {
          lock.complete();
          pending.remove(lock);
          active--;
        }),
      );
    }

    await Future.wait(pending.map((c) => c.future));
    discovered.sort((a, b) => a.host.compareTo(b.host));
    return discovered;
  }

  Future<void> _probeSubnet(
    Subnet subnet,
    List<DiscoveredHermesServer> discovered,
  ) async {
    for (var i = 1; i < 255; i++) {
      final host = subnet.hostBase(i);
      final httpUrl = Uri.parse('http://$host:${subnet.port}/$_healthPath');
      final httpsUrl = Uri.parse('https://$host:${subnet.port}/$_healthPath');

      http.Client? client;
      try {
        client = http.Client();
        final response = await client
            .get(httpUrl, headers: const {'Accept': 'application/json'})
            .timeout(_probeTimeout);
        if (response.statusCode == 200 &&
            looksLikeHermes(response.body)) {
          discovered.add(DiscoveredHermesServer(
            host: host,
            port: subnet.port,
            useHttps: false,
            label: guessLabel(host, response.body),
          ));
          continue;
        }
      } on SocketException catch (_) {
        // host offline, try https
      } on TimeoutException catch (_) {
        // host silent, try https
      } catch (_) {
        // ignore probe failures
      } finally {
        client?.close();
      }

      try {
        client = http.Client();
        final response = await client
            .get(httpsUrl, headers: const {'Accept': 'application/json'})
            .timeout(_probeTimeout);
        if (response.statusCode == 200 &&
            looksLikeHermes(response.body)) {
          discovered.add(DiscoveredHermesServer(
            host: host,
            port: subnet.port,
            useHttps: true,
            label: guessLabel(host, response.body),
          ));
        }
      } on SocketException catch (_) {
        // host offline, skip
      } on TimeoutException catch (_) {
        // host silent, skip
      } catch (_) {
        // ignore probe failures
      } finally {
        client?.close();
      }
    }
  }

  bool looksLikeHermes(String body) {
    final lowered = body.toLowerCase();
    return lowered.contains('hermes') ||
        lowered.contains('gateway') ||
        lowered.contains('ok') ||
        lowered.contains('status');
  }

  String guessLabel(String host, String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>?;
      final name = data?['name'] as String?;
      if (name != null && name.isNotEmpty) return '$name ($host)';
    } on FormatException catch (_) {
      // not json
    }
    return 'Hermes ($host)';
  }

  Future<List<Subnet>> _localSubnets() async {
    final subnets = <Subnet>[];
    try {
      // IPv4 interfaces
      final interfaces4 = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces4) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final hostBase = '${parts[0]}.${parts[1]}.${parts[2]}';
            subnets.add(Subnet(prefix: hostBase, port: _defaultPort));
          }
        }
      }

      // IPv6 interfaces
      final interfaces6 = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv6,
      );
      for (final iface in interfaces6) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split(':');
          if (parts.length >= 3) {
            subnets.add(Subnet(
              prefix: addr.address,
              port: _defaultPort,
              isIPv6: true,
            ));
          }
        }
      }
    } on SocketException catch (_) {
      // no interfaces available
    } on OSError catch (_) {
      // permission or platform issue
    }
    return subnets;
  }
}

class Subnet {
  final String prefix;
  final int port;
  final bool isIPv6;

  const Subnet({
    required this.prefix,
    required this.port,
    this.isIPv6 = false,
  });

  String hostBase(int lastOctet) {
    if (isIPv6) {
      final parts = prefix.split(':');
      parts[parts.length - 1] = lastOctet.toRadixString(16);
      return '[${parts.join(':')}]';
    }
    return '$prefix.$lastOctet';
  }
}

class DiscoveredHermesServer {
  final String host;
  final int port;
  final bool useHttps;
  final String label;

  const DiscoveredHermesServer({
    required this.host,
    required this.port,
    required this.useHttps,
    required this.label,
  });

  String get displayName => '$host:$port';
}
