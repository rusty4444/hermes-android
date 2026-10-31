// The Nous Portal screen for the Hermes Android app.
//
// Shows Nous Portal login status, subscription info, usage/credits,
// per-model costs from analytics, and a form to enter Nous API details.
//
// NOTE: The local API key entry below is retained for manual entry but is
// NOT currently consumed by any backend call in this build. It is stored in
// SharedPreferences only; if a future gateway/client starts reading it, the
// stored value will be available under the `nous_api_key` preference key.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/connection_manager.dart';
import '../theme/hermes_theme.dart';

const _kNousApiKeyPref = 'nous_api_key';

class NousPortalScreen extends StatefulWidget {
  final SavedConnection connection;
  const NousPortalScreen({required this.connection, super.key});

  @override
  State<NousPortalScreen> createState() => _NousPortalScreenState();
}

class _NousPortalScreenState extends State<NousPortalScreen> {
  late final DashboardClient _client;
  Map<String, dynamic>? _portal;
  Map<String, dynamic>? _analytics;
  bool _loading = true;
  String? _error;
  String? _successMsg;
  List<Map<String, dynamic>> _modelRows = const [];
  String? _nousApiKey;

  @override
  void initState() {
    super.initState();
    _client = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? '',
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
    );
    _loadData();
    _loadApiKey();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _nousApiKey = prefs.getString(_kNousApiKeyPref));
  }

  Future<void> _saveApiKey(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_kNousApiKeyPref);
    } else {
      await prefs.setString(_kNousApiKeyPref, value.trim());
    }
    if (!mounted) return;
    setState(() => _nousApiKey = value?.trim());
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _client.getPortal(),
        _client.getAnalytics(),
        _client.getModelsAnalytics(),
        _client.getModelOptions(),
      ]);
      if (!mounted) return;
      final portal = results[0];
      final analytics = results[1];
      final modelsAnalytics = results[2];
      final modelOptions = results[3];
      final modelRows = _extractModelRows(modelsAnalytics, modelOptions);
      setState(() {
        _portal = portal;
        _analytics = analytics;
        _modelRows = modelRows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _extractModelRows(
    Map<String, dynamic> modelsAnalytics,
    Map<String, dynamic> modelOptions,
  ) {
    final rows = <Map<String, dynamic>>[];
    final byModel = <String, Map<String, dynamic>>{};
    final modelsList = modelsAnalytics['models'] as List<dynamic>? ?? [];
    for (final m in modelsList) {
      if (m is! Map<String, dynamic>) continue;
      final id = (m['model'] as String?)?.trim();
      if (id == null || id.isEmpty) continue;
      byModel[id.toLowerCase()] = {
        'model': id,
        'sessions': m['sessions'] ?? m['session_count'] ?? 0,
        'input_tokens': m['input_tokens'] ?? 0,
        'output_tokens': m['output_tokens'] ?? 0,
        'cost': m['cost'] ?? m['estimated_cost'] ?? 0,
      };
    }
    final providers = modelOptions['providers'] as List<dynamic>? ?? [];
    for (final p in providers) {
      if (p is! Map<String, dynamic>) continue;
      final rawModels = p['models'] as List<dynamic>? ?? [];
      for (final m in rawModels) {
        String id;
        if (m is String) {
          id = m;
        } else if (m is Map<String, dynamic>) {
          id = (m['id'] as String?) ?? (m['name'] as String?) ?? '';
        } else {
          continue;
        }
        final existing = byModel[id.toLowerCase()];
        if (existing != null) {
          rows.add(existing);
        } else {
          rows.add({
            'model': id,
            'sessions': 0,
            'input_tokens': 0,
            'output_tokens': 0,
            'cost': 0,
          });
        }
      }
    }
    if (rows.isEmpty && byModel.isNotEmpty) {
      rows.addAll(byModel.values);
    }
    rows.sort((a, b) {
      final costA = (a['cost'] as num?)?.toDouble() ?? 0.0;
      final costB = (b['cost'] as num?)?.toDouble() ?? 0.0;
      return costB.compareTo(costA);
    });
    return rows;
  }

  String _formatCost(dynamic value) {
    final num? n = value is num ? value : num.tryParse('$value');
    if (n == null) return '—';
    final dollars = n.toDouble();
    if (dollars == 0) return 'Free';
    return '\$${dollars.toStringAsFixed(4)}';
  }

  String _formatTokens(dynamic value) {
    final num? n = value is num ? value : num.tryParse('$value');
    if (n == null) return '—';
    final v = n.toDouble();
    if (v >= 1_000_000) return '${(v / 1_000_000).toStringAsFixed(1)}M';
    if (v >= 1_000) return '${(v / 1_000).toStringAsFixed(1)}K';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nous Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(tokens),
    );
  }

  Widget _buildBody(HermesTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _portal == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Failed to load Nous Portal',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: HermesSpacing.xl),
      children: [
        _buildSectionHeader('Subscription & status'),
        _buildStatusCard(tokens),
        const SizedBox(height: 16),

        _buildSectionHeader('Usage & credits'),
        _buildAnalyticsCard(tokens),
        const SizedBox(height: 16),

        _buildSectionHeader('Models & costs'),
        _buildModelsCard(tokens),
        const SizedBox(height: 16),

        _buildSectionHeader('Nous API details'),
        _buildApiDetailsCard(tokens),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _buildStatusCard(HermesTokens tokens) {
    final theme = Theme.of(context);
    final portal = _portal;
    final auth = portal is Map<String, dynamic> ? portal['auth'] : null;
    final loggedIn = auth is Map && (auth['logged_in'] == true || auth['loggedIn'] == true);
    final provider = portal is Map<String, dynamic> ? portal['provider'] : null;
    final toolGateway = portal is Map<String, dynamic> ? portal['tool_gateway'] : null;
    final subscription = portal is Map<String, dynamic> ? portal['subscription'] : null;
    final plan = subscription is Map ? subscription['plan'] : null;
    final status = subscription is Map ? subscription['status'] : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  loggedIn ? Icons.check_circle : Icons.error_outline,
                  color: loggedIn ? theme.colorScheme.tertiary : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  loggedIn ? 'Logged in' : 'Not logged in',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (provider != null)
              _infoRow('Inference provider', '$provider'),
            if (plan != null) _infoRow('Plan', '$plan'),
            if (status != null) _infoRow('Status', '$status'),
            if (toolGateway is Map) ...[
              const SizedBox(height: 4),
              Text('Tool Gateway',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 4),
              ..._toolGatewayRows(toolGateway as Map<String, dynamic>),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _toolGatewayRows(Map<String, dynamic> toolGateway) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    final entries = toolGateway.entries.toList();
    for (final entry in entries) {
      final enabled = entry.value == true || entry.value == 'enabled';
      rows.add(
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Row(
            children: [
              Icon(
                enabled ? Icons.check : Icons.remove,
                size: 16,
                color: enabled ? theme.colorScheme.tertiary : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(_prettyTool(entry.key))),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  String _prettyTool(String key) {
    switch (key) {
      case 'web':
        return 'Web search & extract';
      case 'image_gen':
        return 'Image generation';
      case 'tts':
        return 'Text-to-speech';
      case 'browser':
        return 'Cloud browser';
      case 'cloud_terminal':
        return 'Cloud terminal';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  Widget _buildAnalyticsCard(HermesTokens tokens) {
    final analytics = _analytics;
    if (analytics == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No analytics data available.'),
        ),
      );
    }

    final totals = analytics['totals'] as Map<String, dynamic>? ?? analytics;
    final inputTokens = totals['input_tokens'] ?? totals['inputTokens'] ?? 0;
    final outputTokens = totals['output_tokens'] ?? totals['outputTokens'] ?? 0;
    final totalTokens = totals['total_tokens'] ?? totals['totalTokens'] ?? 0;
    final cost = totals['cost'] ?? totals['estimated_cost'] ?? 0;
    final sessions = totals['sessions'] ?? totals['session_count'] ?? 0;
    final days = totals['days'] ?? analytics['days'] ?? 30;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last $days days',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _statChip(
                    label: 'Sessions',
                    value: '$sessions',
                    icon: Icons.chat_bubble_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statChip(
                    label: 'Total tokens',
                    value: _formatTokens(totalTokens),
                    icon: Icons.token,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statChip(
                    label: 'Input tokens',
                    value: _formatTokens(inputTokens),
                    icon: Icons.arrow_downward,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statChip(
                    label: 'Output tokens',
                    value: _formatTokens(outputTokens),
                    icon: Icons.arrow_upward,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _statChip(
              label: 'Estimated cost',
              value: _formatCost(cost),
              icon: Icons.attach_money,
              wide: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip({
    required String label,
    required String value,
    required IconData icon,
    bool wide = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor)),
                Text(value,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelsCard(HermesTokens tokens) {
    final rows = _modelRows;
    if (rows.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No model data available.'),
        ),
      );
    }

    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor),
        itemBuilder: (context, index) {
          final row = rows[index];
          final model = row['model'] as String? ?? 'unknown';
          final sessions = row['sessions'] ?? 0;
          final inputTokens = row['input_tokens'] ?? 0;
          final outputTokens = row['output_tokens'] ?? 0;
          final cost = row['cost'] ?? 0;
          final isFree = (cost is num ? cost.toDouble() : double.tryParse('$cost') ?? 0.0) == 0;

          return ListTile(
            dense: true,
            leading: Icon(
              isFree ? Icons.free_cancellation : Icons.payments,
              color: isFree ? theme.colorScheme.tertiary : theme.colorScheme.primary,
              size: 20,
            ),
            title: Text(model,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontFamily: 'monospace')),
            subtitle: Text(
              '${_formatTokens(sessions)} sessions · '
              'in ${_formatTokens(inputTokens)} · '
              'out ${_formatTokens(outputTokens)}',
            ),
            trailing: Text(
              _formatCost(cost),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isFree ? theme.colorScheme.tertiary : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildApiDetailsCard(HermesTokens tokens) {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: _nousApiKey ?? '');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Nous API key (unsupported)',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Stored locally on this device. This key is not currently used by '
              'any active backend consumer in this build; it is retained for '
              'future use when a gateway or client starts reading the '
              '`nous_api_key` preference.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: 'Nous Portal / OpenRouter-style API key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    final key = controller.text.trim();
                    await _saveApiKey(key.isEmpty ? null : key);
                    if (!mounted) return;
                    setState(() {
                      _successMsg = key.isEmpty
                          ? 'Nous API key removed.'
                          : 'Nous API key saved.';
                    });
                    await Future.delayed(const Duration(seconds: 2));
                    if (!mounted) return;
                    setState(() => _successMsg = null);
                  },
                  tooltip: 'Save API key',
                ),
              ),
              obscureText: true,
              onChanged: (_) {},
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _nousApiKey != null && _nousApiKey!.isNotEmpty
                      ? Icons.check_circle
                      : Icons.remove_circle_outline,
                  size: 18,
                  color: _nousApiKey != null && _nousApiKey!.isNotEmpty
                      ? theme.colorScheme.tertiary
                      : theme.hintColor,
                ),
                const SizedBox(width: 8),
                Text(
                  _nousApiKey != null && _nousApiKey!.isNotEmpty
                      ? 'API key is set'
                      : 'No API key set',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (_successMsg != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.tertiary),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_successMsg!)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontWeight: FontWeight.w500,
                    )),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
