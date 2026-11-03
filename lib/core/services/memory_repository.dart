import 'package:http/http.dart' as http;

import '../models/memory_fact.dart';
import 'connection_manager.dart';
import 'desktop_gateway_client.dart';

/// Read-only access to the dashboard's profile-scoped built-in memory facts.
/// Owns its HTTP client; no settings, files or external memories are mutated.
class MemoryRepository {
  final DashboardClient _client;
  final String? _profile;

  MemoryRepository._(this._client, this._profile);

  factory MemoryRepository.fromConnection(
    SavedConnection connection, {
    http.Client? httpClient,
  }) {
    final origin = Uri.parse(
      DesktopGatewayClient.normalizedGatewayBaseUrl(connection),
    );
    final profile = connection.gatewayProfile?.trim();
    return MemoryRepository._(
      DashboardClient(
        host: origin.host,
        port: origin.port,
        useHttps: origin.scheme == 'https',
        pathPrefix: origin.path == '/' ? '' : origin.path,
        proxied: connection.dashboardProxied,
        username: connection.dashboardUsername,
        password: connection.dashboardPassword,
        clientCertificate: connection.clientCertificate,
        httpClient: httpClient,
      ),
      profile == null || profile.isEmpty ? null : profile,
    );
  }

  Map<String, String> _query([Map<String, String> values = const {}]) => {
    ...values,
    'profile': ?_profile,
  };

  Future<List<MemoryFact>> loadFacts() async {
    final graph = await _client.apiGet(
      'learning/graph',
      queryParameters: _query(),
    );
    return MemoryFact.parseGraph(graph);
  }

  Future<String> loadFullFact(MemoryFact fact) async {
    if (!fact.hasStableIdentity) {
      throw const FormatException(
        'Full memory reads require fingerprinted IDs',
      );
    }
    final detail = await _client.apiGet(
      'learning/node',
      queryParameters: _query({'id': fact.id}),
    );
    final content = detail['content'];
    if (detail['ok'] != true ||
        detail['kind'] != 'memory' ||
        detail['id'] != fact.id ||
        content is! String ||
        content.trim().isEmpty ||
        !content.startsWith(fact.content)) {
      throw const FormatException(
        'Expected full content for the requested fact',
      );
    }
    return content;
  }

  void close() => _client.close();
}
