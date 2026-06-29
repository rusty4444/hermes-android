// Settings screen for model selection, theme toggle, and app info.
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/connection_manager.dart';
import '../../main.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  final SavedConnection connection;
  const SettingsScreen({required this.connection, super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DashboardClient _client;
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
    _client = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? "",
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
    );
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
      final results = await Future.wait([
        _client.getModelInfo(),
        _client.getModelOptions(),
      ]);

      setState(() {
        _modelInfo = results[0];
        _modelOptions = results[1];
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
      if (p is! Map<String, dynamic>) continue;
      final pMap = p;
      // Provider key is 'slug', not 'id'
      final providerId =
          (pMap['slug'] as String?) ?? (pMap['id'] as String?) ?? '';
      final rawModels = pMap['models'] as List<dynamic>? ?? [];
      if (providerId.isEmpty || rawModels.isEmpty) continue;

      _providers.add(providerId);
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
      await _client.setModel('main', _selectedProvider, _selectedModel);
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
              Text(
                'Failed to load settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
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
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Current Model',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
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
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
            value:
                _selectedProvider.isNotEmpty &&
                    _providers.contains(_selectedProvider)
                ? _selectedProvider
                : null,
            items: _providers
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
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
        if (_selectedProvider.isNotEmpty &&
            _providerModels.containsKey(_selectedProvider)) ...[
          _buildDropdown<String>(
            label: 'Model',
            value: _selectedModel,
            items: _providerModels[_selectedProvider]!.map((m) {
              final id = m['id'] as String? ?? '';
              final name = m['name'] as String? ?? id;
              return DropdownMenuItem(value: id, child: Text(name));
            }).toList(),
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
              child: Text(
                _successMsg!,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        if (_error != null && _modelOptions != null)
          Card(
            color: Colors.red.shade900,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.white)),
            ),
          ),

        const SizedBox(height: 16),

        // ---- Section: Theme ----
        _buildSectionHeader('Appearance'),
        _ThemeToggle(),
        const SizedBox(height: 8),
        _VerboseToggle(),
        const SizedBox(height: 16),

        const SizedBox(height: 16),

        // ---- Section: Voice ----
        _buildSectionHeader('Voice'),
        _VoicePicker(),
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
        _AboutCard(),
      ],
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

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
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
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// About card that reads the real version from package_info_plus.
class _AboutCard extends StatefulWidget {
  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      setState(() => _version = 'unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hermes Agent for Android',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Version ${_version.isNotEmpty ? _version : '…'}'),
            const SizedBox(height: 8),
            const Text(
              'Browse and manage your Hermes Agent sessions from your phone. '
              'Connects to a Hermes dashboard running on your local network.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle for verbose mode — shows tool calls, thinking, and message metadata in chat.
class _VerboseToggle extends StatefulWidget {
  @override
  State<_VerboseToggle> createState() => _VerboseToggleState();
}

class _VerboseToggleState extends State<_VerboseToggle> {
  bool _verbose = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _verbose = prefs.getBool('verbose_mode') ?? false);
  }

  Future<void> _set(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('verbose_mode', value);
    setState(() => _verbose = value);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: const Text('Verbose Mode'),
        subtitle: const Text('Show tool calls, thinking, and message metadata'),
        secondary: const Icon(Icons.terminal),
        value: _verbose,
        onChanged: _set,
      ),
    );
  }
}

class _ThemeToggle extends StatefulWidget {
  @override
  State<_ThemeToggle> createState() => _ThemeToggleState();
}

class _ThemeToggleState extends State<_ThemeToggle> {
  String _mode = 'system';

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _mode = prefs.getString('theme_mode') ?? 'system');
  }

  Future<void> _setMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    if (!mounted) return;
    setState(() => _mode = mode);
    final rootCtx = context.findAncestorStateOfType<HermesAppState>();
    rootCtx?.setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'system',
            label: Text('System'),
            icon: Icon(Icons.brightness_auto, size: 18),
          ),
          ButtonSegment(
            value: 'dark',
            label: Text('Dark'),
            icon: Icon(Icons.dark_mode, size: 18),
          ),
          ButtonSegment(
            value: 'light',
            label: Text('Light'),
            icon: Icon(Icons.light_mode, size: 18),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => _setMode(s.first),
        style: ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }
}

class _VoicePicker extends StatefulWidget {
  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  final FlutterTts _tts = FlutterTts();
  final List<Map<String, String>> _voices = [];
  String? _selectedVoiceName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedVoiceName = prefs.getString('voice_name');

    try {
      final raw = await _tts.getVoices;
      if (raw is List && raw.isNotEmpty) {
        for (final item in raw) {
          if (item is Map) {
            final m = <String, String>{};
            m['name'] = (item['name'] ?? '').toString();
            m['locale'] = (item['locale'] ?? '').toString();
            if (m['name']!.isNotEmpty) _voices.add(m);
          }
        }
      }
    } catch (_) {}

    if (_voices.isEmpty) {
      try {
        final raw = await _tts.getLanguages;
        final seen = <String>{};
        if (raw is List) {
          for (final item in raw) {
            final lang = item.toString();
            if (lang.isNotEmpty && seen.add(lang)) {
              _voices.add({'name': lang, 'locale': lang});
            }
          }
        }
      } catch (_) {}
    }

    _voices.sort(
      (a, b) => (a['locale'] ?? '').compareTo(b['locale'] ?? ''),
    );

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _set(Map<String, String>? voice) async {
    final prefs = await SharedPreferences.getInstance();
    if (voice == null) {
      await prefs.remove('voice_name');
      await prefs.remove('voice_locale');
      setState(() => _selectedVoiceName = null);
    } else {
      final name = voice['name'] ?? '';
      final locale = voice['locale'] ?? '';
      await prefs.setString('voice_name', name);
      await prefs.setString('voice_locale', locale);
      setState(() => _selectedVoiceName = name);
    }
  }

  String _voiceLabel(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    if (name == locale) return locale;
    final gender = name.contains('male')
        ? '(male)'
        : name.contains('female')
            ? '(female)'
            : '';
    return '$locale $gender  [$name]';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_voices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No TTS voices found.\\n'
            'Install Google Text-to-Speech and download voice data.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final items = <DropdownMenuItem<Map<String, String>?>>[
      const DropdownMenuItem(
        value: null,
        child: Text('Auto (device default)'),
      ),
      ..._voices.map(
        (v) => DropdownMenuItem(
          value: v,
          child: Text(
            _voiceLabel(v),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    final current = _selectedVoiceName != null
        ? _voices.where((v) => v['name'] == _selectedVoiceName).firstOrNull
        : null;

    return DropdownButtonFormField<Map<String, String>?>(
      initialValue: current,
      decoration: const InputDecoration(
        labelText: 'Voice',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items,
      onChanged: _set,
    );
  }
}