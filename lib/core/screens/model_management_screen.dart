// Selected-profile main and auxiliary model assignments.
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../services/connection_manager.dart';
import '../services/main_model_route.dart';
import '../theme/hermes_theme.dart';
import '../widgets/auxiliary_models.dart';

class ModelManagementScreen extends StatefulWidget {
  final SavedConnection connection;
  final DashboardClient? dashboardClient;
  const ModelManagementScreen({
    required this.connection,
    this.dashboardClient,
    super.key,
  });

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
  DashboardClient? _client;
  Map<String, dynamic>? _modelInfo;
  Map<String, dynamic>? _modelOptions;
  bool _loading = true;
  bool _failed = false;
  String? _savedModel;
  int _generation = 0;
  bool _saving = false;
  bool _auxSaving = false;
  bool _routeVerified = false;
  bool _endpointRoute = false;

  // Selected values
  String _selectedProvider = '';
  String _selectedModel = '';
  List<String> _providers = [];
  Map<String, List<Map<String, dynamic>>> _providerModels = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant ModelManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection ||
        !identical(oldWidget.dashboardClient, widget.dashboardClient)) {
      _generation++;
      if (oldWidget.dashboardClient == null) _client?.close();
      _client = null;
      _modelInfo = null;
      _modelOptions = null;
      _selectedProvider = '';
      _selectedModel = '';
      _providers = [];
      _providerModels = {};
      _savedModel = null;
      _saving = false;
      _auxSaving = false;
      _loadData();
    }
  }

  @override
  void dispose() {
    _generation++;
    if (widget.dashboardClient == null) _client?.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_saving || _auxSaving) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _routeVerified = false;
    });

    try {
      final client = _client ??=
          widget.dashboardClient ??
          DashboardClient.fromConnection(widget.connection);
      final results = await Future.wait([
        client.getModelInfo(),
        client.getModelOptions(),
        _readRoute(client),
      ]);

      if (!mounted || generation != _generation) return;
      setState(() {
        _modelInfo = results[0];
        _modelOptions = results[1];
        _acceptRoute(results[2]);
        _loading = false;
        _parseModelOptions();
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _parseModelOptions() {
    if (_modelOptions == null) return;

    final providers = _modelOptions!['providers'] as List<dynamic>? ?? [];
    _providers = [];
    _providerModels = {};

    for (final p in providers) {
      if (p is! Map<String, dynamic>) continue;
      final pMap = p;
      // Provider key is 'slug', not 'id'
      final providerId =
          (pMap['slug'] as String?) ?? (pMap['id'] as String?) ?? '';
      final rawModels = pMap['models'] as List<dynamic>? ?? [];
      if (providerId.isEmpty ||
          rawModels.isEmpty ||
          const {'custom', 'local'}.contains(providerId) ||
          pMap['is_user_defined'] == true ||
          (pMap['api_url'] ?? '') != '' ||
          (pMap['base_url'] ?? '') != '') {
        continue;
      }

      if (!_providers.contains(providerId)) _providers.add(providerId);
      // Models are strings (model IDs), not dicts
      // Convert to list of {'id': modelId, 'name': modelId} maps for dropdown
      _providerModels[providerId] = rawModels
          .map((m) {
            if (m is String) {
              return {'id': m, 'name': m};
            } else if (m is Map<String, dynamic>) {
              return m;
            }
            return <String, dynamic>{};
          })
          .where((m) => m['id'] != null && (m['id'] as String).isNotEmpty)
          .toList();
      final seen = <String>{};
      _providerModels[providerId]!.removeWhere(
        (m) => !seen.add(m['id'] as String),
      );
    }

    // Keep an assignment absent from discovery visible without changing it.
    final currentProvider = _modelInfo?['provider'];
    final currentModel = _modelInfo?['model'];
    if (currentProvider is String &&
        currentProvider.isNotEmpty &&
        currentModel is String &&
        currentModel.isNotEmpty) {
      if (!_providers.contains(currentProvider)) {
        _providers.add(currentProvider);
      }
      final models = _providerModels.putIfAbsent(currentProvider, () => []);
      if (!models.any((m) => m['id'] == currentModel)) {
        models.add({'id': currentModel, 'name': currentModel});
      }
    }

    // Set initial selections from current model
    if (_modelInfo != null) {
      _selectedProvider = (_modelInfo!['provider'] as String?) ?? '';
      _selectedModel = (_modelInfo!['model'] as String?) ?? '';
    }
  }

  // An omitted endpoint in model/info is not evidence of an endpoint-free
  // assignment. Only the matching selected-profile route projection proves it.
  Future<Map<String, dynamic>> _readRoute(DashboardClient client) async {
    try {
      final route = await client.getMainModelRoute();
      return {
        'provider': route.provider,
        'model': route.model,
        'hasEndpoint': route.hasEndpoint,
      };
    } catch (_) {
      return {};
    }
  }

  void _acceptRoute(Map<String, dynamic> route) {
    _routeVerified =
        route['hasEndpoint'] is bool &&
        route['provider'] == _modelInfo?['provider'] &&
        route['model'] == _modelInfo?['model'];
    _endpointRoute = route['hasEndpoint'] == true;
    if (!_routeVerified) _failed = true;
  }

  bool get _customRoute =>
      !_routeVerified ||
      _endpointRoute ||
      mainModelUsesCustomEndpoint(
        _modelInfo?['provider'] as String? ?? '',
        _modelInfo?['base_url'] as String? ?? '',
      );

  Future<void> _applyModel() async {
    if (_customRoute ||
        _loading ||
        _saving ||
        _auxSaving ||
        _selectedProvider.isEmpty ||
        _selectedModel.isEmpty) {
      return;
    }
    final generation = ++_generation;
    final client = _client;
    if (client == null) return;
    final provider = _selectedProvider;
    final model = _selectedModel;
    setState(() {
      _failed = false;
      _savedModel = null;
      _saving = true;
    });
    try {
      final result = await client.setModel('main', provider, model);
      if (!mounted || generation != _generation) return;
      if (result['ok'] != true) {
        throw const FormatException('Assignment not confirmed');
      }
      final readback = await Future.wait([
        client.getModelInfo(),
        _readRoute(client),
      ]);
      if (!mounted || generation != _generation) return;
      final info = readback[0];
      if (info['provider'] != provider || info['model'] != model) {
        throw const FormatException('Assignment read-back did not match');
      }
      setState(() {
        _modelInfo = info;
        _acceptRoute(readback[1]);
        if (_customRoute) _failed = true;
        _saving = false;
        _savedModel = _routeVerified && !_customRoute ? model : null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.model),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _saving || _auxSaving ? null : _loadData,
            tooltip: context.l10n.refresh,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_failed && _modelOptions == null)
          _buildModelLoadError()
        else ...[
          // ---- Section: Model ----
          _buildSectionHeader(context.l10n.profile_default_model),
          Text(
            context.l10n.changes_the_default_for_use_the_selector_in_a_chat(
              widget.connection.label,
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_modelInfo != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.smart_toy,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.current_profile_default,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.model_via_provider(
                        _modelInfo!['model'] ?? '???',
                        _modelInfo!['provider'] ?? '???',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_modelInfo!['effective_context_length'] != null &&
                        _modelInfo!['effective_context_length'] != 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          context.l10n.context_tokens(
                            _modelInfo!['effective_context_length'],
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: HermesTokens.of(context).muted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),

          if (_customRoute && _routeVerified)
            Text(context.l10n.auxiliary_notice),

          // Provider picker
          if (!_customRoute && _providers.isNotEmpty) ...[
            _buildDropdown<String>(
              label: context.l10n.provider,
              value:
                  _selectedProvider.isNotEmpty &&
                      _providers.contains(_selectedProvider)
                  ? _selectedProvider
                  : null,
              items: _providers
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(p, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() {
                  _selectedProvider = val!;
                  // Reset model when switching providers
                  final models = _providerModels[val];
                  if (models != null && models.isNotEmpty) {
                    _selectedModel = models.first['id'] as String? ?? '';
                  } else {
                    _selectedModel = '';
                  }
                });
              },
            ),
            const SizedBox(height: 12),
          ],

          // Model picker
          if (!_customRoute &&
              _selectedProvider.isNotEmpty &&
              _providerModels.containsKey(_selectedProvider)) ...[
            _buildDropdown<String>(
              label: context.l10n.model,
              value: _selectedModel,
              items: _providerModels[_selectedProvider]!.map((m) {
                final id = m['id'] as String? ?? '';
                final name = m['name'] as String? ?? id;
                return DropdownMenuItem(
                  value: id,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedModel = val!);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _auxSaving ? null : _applyModel,
                icon: const Icon(Icons.check),
                label: Text(context.l10n.set_profile_default),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Success/error messages
          if (_savedModel != null)
            Card(
              color: HermesTokens.of(context).success,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.l10n
                      .profile_default_set_to_chats_with_their_own_model_keep(
                        _savedModel!,
                      ),
                  style: TextStyle(
                    color: foregroundFor(HermesTokens.of(context).success),
                  ),
                ),
              ),
            ),
          if (_failed && _modelOptions != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  context.l10n.model_management_unavailable,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),
        ],
        if (_client case final client?)
          AuxiliaryModels(
            client: client,
            enabled: !_saving,
            onSavingChanged: (saving) => setState(() => _auxSaving = saving),
          ),
        const SizedBox(height: 16),
      ],
    ),
  );

  Widget _buildModelLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: HermesTokens.of(context).warning,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.model_management_unavailable,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadData,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey('main:$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items: items,
      onChanged: _saving || _auxSaving ? null : onChanged,
    );
  }
}
