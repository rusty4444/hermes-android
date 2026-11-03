import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

typedef DiscoveryAddressResolver = Future<List<InternetAddress>> Function();

/// Explicit, unauthenticated discovery only. Never runs during app startup.
///
/// Probe at most four private IPv4 /24 neighbourhoods, not entire interface
/// networks (dart:io does not expose their netmasks). IPv6 has no practical
/// equivalent sweep: only the interface's exact address is probed; never invent
/// neighbours by replacing the suffix of a compressed or scoped address.
class LanDiscoveryService {
  LanDiscoveryService({
    DiscoveryAddressResolver? resolveAddresses,
    http.Client Function()? clientFactory,
    this.port = 8642,
    this.concurrency = 64,
    this.maxHosts = 1016,
    this.probeTimeout = const Duration(seconds: 2),
    this.scanTimeout = const Duration(seconds: 30),
  }) : _resolveAddresses = resolveAddresses ?? _localAddresses,
       _clientFactory = clientFactory ?? http.Client.new {
    if (port < 1 ||
        port > 65535 ||
        concurrency < 1 ||
        concurrency > 64 ||
        maxHosts < 1 ||
        maxHosts > 1016 ||
        probeTimeout <= Duration.zero ||
        scanTimeout <= Duration.zero) {
      throw ArgumentError('Invalid discovery limits');
    }
  }

  final DiscoveryAddressResolver _resolveAddresses;
  final http.Client Function() _clientFactory;
  final int port;
  final int concurrency;
  final int maxHosts;
  final Duration probeTimeout;
  final Duration scanTimeout;
  _DiscoveryRun? _run;

  /// Stops active requests and prevents queued hosts/fallbacks from starting.
  void cancel() => _run?.cancel();

  Future<List<DiscoveredHermesServer>> discover() async {
    if (_run != null) throw StateError('Discovery is already running');
    final run = _DiscoveryRun();
    _run = run;
    var timedOut = false;
    final timer = Timer(scanTimeout, () {
      timedOut = true;
      run.cancel();
    });
    final found = <DiscoveredHermesServer>[];
    try {
      final addresses = await Future.any<List<InternetAddress>>([
        _resolveAddresses(),
        run.cancelled.future.then((_) => <InternetAddress>[]),
      ]);
      final hosts = candidateHosts(addresses).iterator;
      Future<void> worker() async {
        while (!run.isCancelled && hosts.moveNext()) {
          final server = await _probeHost(hosts.current, run);
          if (!run.isCancelled && server != null) found.add(server);
        }
      }

      await Future.wait(List.generate(concurrency, (_) => worker()));
      if (timedOut) throw TimeoutException('LAN discovery timed out');
      found.sort((a, b) => a.host.compareTo(b.host));
      return run.isCancelled ? [] : found;
    } finally {
      timer.cancel();
      run.cancel();
      _run = null;
    }
  }

  /// Stable, deduplicated and bounded before any network request is made.
  List<String> candidateHosts(List<InternetAddress> addresses) {
    final hosts = <String>{};
    final prefixes = <String>{};
    for (final address in addresses) {
      if (address.isLoopback || address.isMulticast) continue;
      final bytes = address.rawAddress;
      if (address.type == InternetAddressType.IPv4) {
        final private =
            bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 169 && bytes[1] == 254);
        if (!private) continue;
        final prefix = bytes.take(3).join('.');
        if (!prefixes.add(prefix)) continue;
        for (var i = 1; i < 255 && hosts.length < maxHosts; i++) {
          hosts.add('$prefix.$i');
        }
      } else if (address.type == InternetAddressType.IPv6 &&
          bytes.any((b) => b != 0)) {
        // Store raw hosts, not URI bracket syntax; Uri handles IPv6 brackets.
        hosts.add(address.address);
      }
      if (hosts.length >= maxHosts) break;
    }
    return hosts.toList();
  }

  Future<DiscoveredHermesServer?> _probeHost(
    String host,
    _DiscoveryRun run,
  ) async {
    for (final scheme in ['http', 'https']) {
      if (run.isCancelled) return null;
      final client = _clientFactory();
      run.clients.add(client);
      final expired = Completer<String?>();
      final probeTimer = Timer(probeTimeout, () => expired.complete(null));
      try {
        final uri = Uri(
          scheme: scheme,
          host: host,
          port: port,
          path: '/health',
        );
        final body = await Future.any<String?>([
          _readHealth(client, uri),
          expired.future,
          run.cancelled.future.then((_) => null),
        ]);
        if (body != null && looksLikeHermes(body)) {
          return DiscoveredHermesServer(
            host: host,
            port: port,
            useHttps: scheme == 'https',
            label: guessLabel(host, body),
          );
        }
      } on Exception catch (_) {
        // Includes offline hosts, malformed responses and TLS verification
        // failures. Default client trust is retained; never bypass TLS checks.
      } finally {
        probeTimer.cancel();
        run.clients.remove(client);
        client.close();
      }
    }
    return null;
  }

  Future<String?> _readHealth(http.Client client, Uri uri) async {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    final response = await client.send(request);
    if (response.statusCode != 200) return null;
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 16384) return null;
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  bool looksLikeHermes(String body) {
    try {
      final data = jsonDecode(body);
      // gateway/platforms/api_server.py: APIServerAdapter._handle_health
      // returns {status: 'ok', platform: 'hermes-agent', version: ...}.
      // Identity + health are required; version is deliberately extensible.
      return data is Map<String, dynamic> &&
          data['status'] == 'ok' &&
          data['platform'] == 'hermes-agent';
    } on FormatException {
      return false;
    }
  }

  String guessLabel(String host, String body) {
    try {
      final data = jsonDecode(body);
      final name = data is Map<String, dynamic> ? data['name'] : null;
      if (name is String && name.trim().isNotEmpty) return '$name ($host)';
    } on FormatException {
      // Optional label; never assume a JSON object's shape.
    }
    return 'Hermes ($host)';
  }

  static Future<List<InternetAddress>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      return interfaces.expand((iface) => iface.addresses).toList();
    } on SocketException {
      return [];
    } on OSError {
      return [];
    }
  }
}

class _DiscoveryRun {
  final cancelled = Completer<void>();
  final clients = <http.Client>{};
  bool get isCancelled => cancelled.isCompleted;

  void cancel() {
    if (isCancelled) return;
    cancelled.complete();
    for (final client in clients.toList()) {
      client.close();
    }
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

  String get connectionUrl => Uri(
    scheme: useHttps ? 'https' : 'http',
    host: host,
    port: port,
  ).toString();

  String get displayName => Uri(
    scheme: useHttps ? 'https' : 'http',
    host: host,
    port: port,
  ).authority;
}
