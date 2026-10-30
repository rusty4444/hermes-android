// Generic provider screen for the Hermes Android app.
//
// Reusable surface for ChatGPT, Claude, DeepSeek, and any future
// provider-backed analytics. Shows models filtered by provider,
// plus a locally-stored API key form.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/connection_manager.dart';
import '../theme/hermes_theme.dart';

class ProviderScreen extends StatefulWidget {
  final SavedConnection connection;
  final String providerId;
  final String title;
  final String apiKeyPref;
  final String hintText;
  final IconData icon;

  const ProviderScreen({
    required this.connection,
    required this.providerId,
    required this.title,
    required this.apiKeyPref,
    required this.hintText,
    this.icon = Icons.public,
    super.key,
  });

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  late final DashboardClient _client;
  bool _loading = true;
  String? _error;
  String? _successMsg;
  List<Map<String, dynamic>> _providerRows = const [];
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
    setState(() => _apiKey = prefs.getString(widget.apiKeyPref));
  }

  Future<void> _saveApiKey(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(widget.apiKeyPref);
    } else {
      await prefs.setString(widget.apiKeyPref, value.trim());
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
      final rows = _extractProviderRows(modelsAnalytics, modelOptions);
      setState(() {
        _providerRows = rows;
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

  List<Map<String, dynamic>> _extractProviderRows(
    Map<String, dynamic> modelsAnalytics,
    Map<String, dynamic> modelOptions,
  ) {
    final rows = <Map<String, dynamic>>[];
    final byModel = <String, Map<String, dynamic>>{};
    final target = widget.providerId.toLowerCase();
    final modelsList = modelsAnalytics['models'] as List<dynamic>? ?? [];
    for (final m in modelsList) {
      if (m is! Map<String, dynamic>) continue;
      final provider = (m['provider'] as String? ?? '').toLowerCase();
      if (provider != target) continue;
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
      if (providerId != target) continue;
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
            'provider': target,
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _providerRows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text('Failed to load ${widget.title} data',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!,
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
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
        _buildSectionHeader(theme, '${widget.title} models'),
        _buildModelsCard(theme),
        const SizedBox(height: 16),
        _buildSectionHeader(theme, '${widget.title} API key'),
        _buildApiDetailsCard(theme),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildModelsCard(ThemeData theme) {
    final rows = _providerRows;
    if (rows.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No ${widget.title} model data available.'),
        ),
      );
    }

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

  Widget _buildApiDetailsCard(ThemeData theme) {
    final controller = TextEditingController(text: _apiKey ?? '');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.title} API key',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Stored locally on this device. Used for direct ${widget.title} API calls '
              'when the gateway does not supply one.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: widget.hintText,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    final key = controller.text.trim();
                    await _saveApiKey(key.isEmpty ? null : key);
                    if (!mounted) return;
                    setState(() {
                      _successMsg = key.isEmpty
                          ? '${widget.title} API key removed.'
                          : '${widget.title} API key saved.';
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
