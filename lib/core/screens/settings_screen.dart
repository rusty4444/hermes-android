/// Settings screen for model selection, theme toggle, and app info.
import 'package:flutter/material.dart';
import '../services/connection_manager.dart';

class SettingsScreen extends StatefulWidget {
  final SavedConnection connection;
  const SettingsScreen({required this.connection, super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ApiClient _client;
  Map<String, dynamic>? _modelInfo;
  Map<String, dynamic>? _modelOptions;
  bool _loading = true;
  String? _error;
  String? _successMsg;

  // Selected values
  String _selectedProvider = '';
  String _selectedModel = '';
  List<String> _providers = [];
  Map<String, List<Map<String, dynamic>>> _providerModels = {};

  @override
  void initState() {
    super.initState();
    _client = ApiClient();
    _loadData();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final baseUrl = widget.connection.baseUrl;
      final results = await Future.wait([
        _client.getModelInfo(baseUrl),
        _client.getModelOptions(baseUrl),
      ]);

      setState(() {
        _modelInfo = results[0] as Map<String, dynamic>;
        _modelOptions = results[1] as Map<String, dynamic>;
        _loading = false;
        _parseModelOptions();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
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
      final pMap = p as Map<String, dynamic>;
      final providerId = pMap['id'] as String? ?? '';
      final models = (pMap['models'] as List<dynamic>?)
              ?.map((m) => m as Map<String, dynamic>)
              .toList() ??
          [];
      if (providerId.isNotEmpty && models.isNotEmpty) {
        _providers.add(providerId);
        _providerModels[providerId] = models;
      }
    }

    // Set initial selections from current model
    if (_modelInfo != null) {
      _selectedProvider = (_modelInfo!['provider'] as String?) ?? '';
      _selectedModel = (_modelInfo!['model'] as String?) ?? '';
    }
  }

  Future<void> _applyModel() async {
    if (_selectedProvider.isEmpty || _selectedModel.isEmpty) return;

    setState(() {
      _error = null;
      _successMsg = null;
    });

    try {
      await _client.setModel(
        widget.connection.baseUrl,
        _selectedProvider,
        _selectedModel,
      );
      setState(() {
        _successMsg = 'Model set to $_selectedModel — applies to new sessions';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _modelOptions == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text('Failed to load settings',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Section: Model ----
        _buildSectionHeader('Model Selection'),
        if (_modelInfo != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.smart_toy, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Current Model',
                        style: Theme.of(context).textTheme.titleSmall),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '${_modelInfo!['model'] ?? '???'}  \nvia `${_modelInfo!['provider'] ?? '???'}`',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_modelInfo!['effective_context_length'] != null &&
                      _modelInfo!['effective_context_length'] != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Context: ${_modelInfo!['effective_context_length']} tokens',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // Provider picker
        if (_providers.isNotEmpty) ...[
          _buildDropdown<String>(
            label: 'Provider',
            value: _selectedProvider.isNotEmpty &&
                    _providers.contains(_selectedProvider)
                ? _selectedProvider
                : null,
            items: _providers.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
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
        if (_selectedProvider.isNotEmpty &&
            _providerModels.containsKey(_selectedProvider)) ...[
          _buildDropdown<String>(
            label: 'Model',
            value: _selectedModel,
            items: _providerModels[_selectedProvider]!
                .map((m) {
                  final id = m['id'] as String? ?? '';
                  final name = m['name'] as String? ?? id;
                  return DropdownMenuItem(value: id, child: Text(name));
                })
                .toList(),
            onChanged: (val) {
              setState(() => _selectedModel = val!);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _applyModel,
              icon: const Icon(Icons.check),
              label: const Text('Apply Model'),
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Success/error messages
        if (_successMsg != null)
          Card(
            color: Colors.green.shade900,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_successMsg!,
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        if (_error != null && _modelOptions != null)
          Card(
            color: Colors.red.shade900,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.white)),
            ),
          ),

        const SizedBox(height: 16),

        // ---- Section: Theme ----
        _buildSectionHeader('Appearance'),
        SwitchListTile(
          title: const Text('Dark Mode'),
          subtitle: const Text('Follow system theme'),
          value: Theme.of(context).brightness == Brightness.dark,
          onChanged: (_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dark mode follows system setting')),
            );
          },
        ),
        const SizedBox(height: 16),

        // ---- Section: Connection ----
        _buildSectionHeader('Connection'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Label', widget.connection.label),
                const SizedBox(height: 4),
                _infoRow('Host', widget.connection.host),
                const SizedBox(height: 4),
                _infoRow('Port', '${widget.connection.port}'),
                const SizedBox(height: 4),
                _infoRow('Base URL', widget.connection.baseUrl),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Section: About ----
        _buildSectionHeader('About'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hermes Agent for Android',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Version 0.0.3'),
                SizedBox(height: 8),
                Text(
                  'Browse and manage your Hermes Agent sessions from your phone. '
                  'Connects to a Hermes dashboard running on your local network.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w500, color: Colors.grey)),
        ),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
