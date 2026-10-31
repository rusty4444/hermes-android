/// Read-only Hermes usage, not provider account balance or model pricing.
library;

import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';

/// Preserve all recorded usage, including models no longer in the catalogue.
List<Map<String, dynamic>> providerUsageRows(
  Map<String, dynamic> analytics,
  String providerId,
) {
  final models = analytics['models'];
  if (models is! List) throw const FormatException('Missing models analytics');
  return models.whereType<Map<String, dynamic>>().where((row) {
    return row['provider'] is String &&
        (row['provider'] as String).toLowerCase() == providerId.toLowerCase();
  }).toList();
}

class ProviderUsageScreen extends StatefulWidget {
  final SavedConnection connection;
  final String providerId;
  final String title;
  final DashboardClient? dashboardClient;
  const ProviderUsageScreen({
    required this.connection,
    required this.providerId,
    required this.title,
    this.dashboardClient,
    super.key,
  });

  @override
  State<ProviderUsageScreen> createState() => _ProviderUsageScreenState();
}

class _ProviderUsageScreenState extends State<ProviderUsageScreen> {
  DashboardClient? _client;
  int _generation = 0;
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProviderUsageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection ||
        oldWidget.dashboardClient != widget.dashboardClient ||
        oldWidget.providerId != widget.providerId) {
      if (oldWidget.dashboardClient == null) _client?.close();
      _client = null;
      _rows = const [];
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    if (widget.dashboardClient == null) _client?.close();
    super.dispose();
  }

  DashboardClient _connect() {
    final origin = Uri.parse(
      DesktopGatewayClient.normalizedGatewayBaseUrl(widget.connection),
    );
    return widget.dashboardClient ??
        DashboardClient(
          host: origin.host,
          port: origin.port,
          useHttps: origin.scheme == 'https',
          pathPrefix: origin.path == '/' ? '' : origin.path,
          proxied: widget.connection.dashboardProxied,
          username: widget.connection.dashboardUsername,
          password: widget.connection.dashboardPassword,
          gatewayProfile: widget.connection.gatewayProfile,
          clientCertificate: widget.connection.clientCertificate,
        );
  }

  Future<void> _load() async {
    if (_loading && _client != null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      // Certificate parsing may fail synchronously; never fall back to a
      // client without the selected profile's identity.
      final client = _client ??= _connect();
      final analytics = await client.getModelsAnalytics();
      if (!mounted || generation != _generation) return;
      final rows = providerUsageRows(analytics, widget.providerId);
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _count(dynamic value) => value is num ? '$value' : '—';
  String _cost(dynamic value) =>
      value is num && value.isFinite ? '\$${value.toStringAsFixed(4)}' : '—';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.provider_usage_notice),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_failed) ...[
            Text(l10n.provider_usage_failed),
            TextButton(onPressed: _load, child: Text(l10n.retry)),
          ],
          if (!_loading && !_failed && _rows.isEmpty)
            Text(l10n.provider_usage_empty),
          for (final row in _rows)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row['model'] is String ? row['model'] as String : '—'),
                    Text(
                      l10n.provider_usage_counts(
                        _count(row['sessions']),
                        _count(row['input_tokens']),
                        _count(row['output_tokens']),
                      ),
                    ),
                    Text(
                      l10n.provider_usage_costs(
                        _cost(row['estimated_cost']),
                        _cost(row['actual_cost']),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
