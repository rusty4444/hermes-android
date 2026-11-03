/// Read-only provider subscription allowance and recorded Hermes usage.
library;

import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../models/provider_account_usage.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';

/// Preserve recorded retired models; Codex and API rows remain distinguishable.
List<Map<String, dynamic>> providerUsageRows(
  Map<String, dynamic> analytics,
  String providerId,
) {
  final models = analytics['models'];
  if (models is! List) throw const FormatException('Missing models analytics');
  return models.whereType<Map<String, dynamic>>().where((row) {
    final provider = row['provider'];
    return provider is String &&
        (provider.toLowerCase() == providerId.toLowerCase() ||
            (providerId == 'openai' && provider == 'openai-codex'));
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
  bool _quotaLoading = false;
  bool _quotaFailed = false;
  ProviderSubscriptionUsage? _quota;
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
      _quota = null;
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
    if ((_loading || _quotaLoading) && _client != null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _quotaLoading = subscriptionUsageProvider(widget.providerId) != null;
      _quotaFailed = false;
    });
    DashboardClient client;
    try {
      // Certificate parsing may fail synchronously; never fall back to a
      // client without the selected profile's identity.
      client = _client ??= _connect();
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
        _quotaFailed = _quotaLoading;
        _quotaLoading = false;
      });
      return;
    }
    // Independent reads: neither failed nor held response hides the other.
    // Only initial load and explicit refresh read inventory; no polling.
    await Future.wait([
      _loadAnalytics(client, generation),
      if (_quotaLoading) _loadQuota(client, generation),
    ]);
  }

  Future<void> _loadAnalytics(DashboardClient client, int generation) async {
    try {
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

  Future<void> _loadQuota(DashboardClient client, int generation) async {
    try {
      final options = await client.getModelOptions();
      if (!mounted || generation != _generation) return;
      setState(() {
        _quota = ProviderSubscriptionUsage.fromModelOptions(
          options,
          widget.providerId,
        );
        _quotaLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _quotaFailed = true;
        _quotaLoading = false;
      });
    }
  }

  String _count(dynamic value) => value is num ? '$value' : '—';
  String _cost(dynamic value) =>
      value is num && value.isFinite ? '\$${value.toStringAsFixed(4)}' : '—';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _loading || _quotaLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: busy ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (subscriptionUsageProvider(widget.providerId) != null) ...[
            Text(
              widget.providerId == 'anthropic'
                  ? l10n.provider_quota_claude
                  : l10n.provider_quota_codex,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(l10n.provider_quota_notice),
            Text(l10n.provider_quota_windows_notice),
            if (_quotaLoading) const LinearProgressIndicator(),
            if (_quotaFailed) Text(l10n.provider_quota_failed),
            if (!_quotaLoading && _quota == null && !_quotaFailed)
              Text(l10n.provider_quota_unavailable),
            if (_quota case final quota?) ...[
              if (quota.hasAccounts && quota.accounts.isEmpty)
                Text(l10n.provider_quota_unavailable),
              if (!quota.hasAccounts) ..._windowWidgets(quota.windows),
              for (final account in quota.accounts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.label ??
                              account.id ??
                              l10n.provider_quota_account,
                        ),
                        Text(
                          l10n.provider_quota_state(
                            account.state ?? l10n.provider_quota_unknown,
                          ),
                        ),
                        if (account.resetsAt case final reset?)
                          Text(l10n.provider_quota_reset(_resetText(reset))),
                        ..._windowWidgets(account.windows),
                      ],
                    ),
                  ),
                ),
            ],
            if (_quotaFailed)
              TextButton(
                onPressed: busy ? null : _load,
                child: Text(l10n.retry),
              ),
            const SizedBox(height: 24),
          ],
          Text(l10n.provider_usage_notice),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_failed) ...[
            Text(l10n.provider_usage_failed),
            if (!_quotaFailed)
              TextButton(
                onPressed: busy ? null : _load,
                child: Text(l10n.retry),
              ),
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
                    if (widget.providerId == 'openai')
                      Text(
                        row['provider'] == 'openai-codex'
                            ? l10n.provider_quota_codex
                            : l10n.provider_quota_openai_api,
                      ),
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

  String _resetText(DateTime reset) => reset.toUtc().toIso8601String();

  String _windowLabel(ProviderUsageWindow window) {
    // Only exact provider-confirmed session labels identify five-hour windows.
    // Preserve weekly/model-specific and unfamiliar labels without guessing.
    if ((_quota?.provider == 'openai-codex' && window.label == 'Session') ||
        (_quota?.provider == 'anthropic' &&
            window.label == 'Current session')) {
      return context.l10n.provider_quota_five_hour_session;
    }
    return window.label;
  }

  Iterable<Widget> _windowWidgets(List<ProviderUsageWindow> windows) sync* {
    final l10n = context.l10n;
    if (windows.isEmpty) yield Text(l10n.provider_quota_unavailable);
    for (final window in windows) {
      yield Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_windowLabel(window)),
            if (window.scope case final scope?)
              Text(l10n.provider_quota_scope(scope)),
            if (window.usedPercent case final used?) ...[
              Text(
                l10n.provider_quota_percent(
                  used.toStringAsFixed(1),
                  window.remainingPercent!.toStringAsFixed(1),
                ),
              ),
              LinearProgressIndicator(value: used / 100),
            ] else
              Text(l10n.provider_quota_unavailable),
            if (window.resetsAt case final reset?)
              Text(l10n.provider_quota_reset(_resetText(reset)))
            else
              Text(l10n.provider_quota_reset_unknown),
          ],
        ),
      );
    }
  }
}
