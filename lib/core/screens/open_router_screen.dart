// The OpenRouter screen for the Hermes Android app.
//
// Shows OpenRouter usage, credits, and model costs filtered from the
// Hermes analytics endpoints, plus a form to enter an OpenRouter API key.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/connection_manager.dart';
import '../theme/hermes_theme.dart';

const _kOpenRouterApiKeyPref = 'openrouter_api_key';

class OpenRouterScreen extends StatefulWidget {
  final SavedConnection connection;
  const OpenRouterScreen({required this.connection, super.key});

  @override
  State<OpenRouterScreen> createState() => _OpenRouterScreenState();
}

class _OpenRouterScreenState extends State<OpenRouterScreen> {
  late final DashboardClient _client;
  Map<String, dynamic>? _modelsAnalytics;
  bool _loading = true;
  String? _error;
  String? _successMsg;
  List<Map<String, dynamic>> _openRouterRows = const [];
  String? _apiKey;

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
    setState(() => _apiKey = prefs.getString(_kOpenRouterApiKeyPref));
  }

  Future<void> _saveApiKey(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_kOpenRouterApiKeyPref);
    } else {
      await prefs.setString(_kOpenRouterApiKeyPref, value.trim());
    }
    if (!mounted) return;
    setState(() => _apiKey = value?.trim());
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _client.getAnalytics(),
        _client.getModelsAnalytics(),
        _client.getModelOptions(),
      ]);
      if (!mounted) return;
      final modelsAnalytics = results[1];
      final modelOptions = results[2];
      final rows = _extractOpenRouterRows(modelsAnalytics, modelOptions);
      setState(() {
        _modelsAnalytics = modelsAnalytics;
        _openRouterRows = rows;
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

  List<Map<String, dynamic>> _extractOpenRouterRows(
    Map<String, dynamic> modelsAnalytics,
    Map<String, dynamic> modelOptions,
  ) {
    final rows = <Map<String, dynamic>>[];
    final byModel = <String, Map<String, dynamic>>{};
    final modelsList = modelsAnalytics['models'] as List<dynamic>? ?? [];
    for (final m in modelsList) {
      if (m is! Map<String, dynamic>) continue;
      final provider = (m['provider'] as String? ?? '').toLowerCase();
      if (provider != 'openrouter') continue;
      final id = (m['model'] as String?)?.trim();
      if (id == null || id.isEmpty) continue;
      byModel[id.toLowerCase()] = {
        'model': id,
        'provider': provider,
        'sessions': m['sessions'] ?? m['session_count'] ?? 0,
        'input_tokens': m['input_tokens'] ?? 0,
        'output_tokens': m['output_tokens'] ?? 0,
        'cost': m['cost'] ?? m['estimated_cost'] ?? 0,
      };
    }
    final providers = modelOptions['providers'] as List<dynamic>? ?? [];
    for (final p in providers) {
      if (p is! Map<String, dynamic>) continue;
      final providerId = (p['id'] as String? ?? '').toLowerCase();
      if (providerId != 'openrouter') continue;
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
            'provider': 'openrouter',
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
        title: const Text('OpenRouter'),
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

    if (_error != null && _modelsAnalytics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text('Failed to load OpenRouter data',
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
        _buildSectionHeader('OpenRouter models'),
        _buildModelsCard(tokens),
        const SizedBox(height: 16),
        _buildSectionHeader('OpenRouter API key'),
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

  Widget _buildModelsCard(HermesTokens tokens) {
    final rows = _openRouterRows;
    if (rows.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No OpenRouter model data available.'),
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
              color: isFree ? Colors.green : theme.colorScheme.primary,
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
                color: isFree ? Colors.green : null,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildApiDetailsCard(HermesTokens tokens) {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: _apiKey ?? '');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OpenRouter API key',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Stored locally on this device. Used for direct OpenRouter API calls '
              'when the gateway does not supply one.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: 'sk-or-v1-...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    final key = controller.text.trim();
                    await _saveApiKey(key.isEmpty ? null : key);
                    if (!mounted) return;
                    setState(() {
                      _successMsg = key.isEmpty
                          ? 'OpenRouter API key removed.'
                          : 'OpenRouter API key saved.';
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
                  _apiKey != null && _apiKey!.isNotEmpty
                      ? Icons.check_circle
                      : Icons.remove_circle_outline,
                  size: 18,
                  color: _apiKey != null && _apiKey!.isNotEmpty
                      ? Colors.green
                      : theme.hintColor,
                ),
                const SizedBox(width: 8),
                Text(
                  _apiKey != null && _apiKey!.isNotEmpty
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
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: Colors.green),
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
}
