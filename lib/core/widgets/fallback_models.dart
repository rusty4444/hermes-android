import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../models/fallback_config.dart';
import '../services/connection_manager.dart';

/// Draft-only editor. Saving replaces the complete ordered primary chain after
/// validation; legacy fallbacks remain separately visible and untouched.
class FallbackModels extends StatefulWidget {
  final DashboardClient client;
  final bool enabled;
  final int refreshToken;
  final int authorityToken;
  final ValueChanged<bool>? onSavingChanged;
  const FallbackModels({
    required this.client,
    this.enabled = true,
    this.refreshToken = 0,
    this.authorityToken = 0,
    this.onSavingChanged,
    super.key,
  });
  @override
  State<FallbackModels> createState() => _FallbackModelsState();
}

class _FallbackModelsState extends State<FallbackModels> {
  FallbackConfig? _config;
  List<FallbackEntry> _rows = [];
  Map<String, List<String>> _models = {};
  bool _loading = true;
  bool _optionsLoading = true;
  bool _loadFailed = false;
  bool _optionsFailed = false;
  bool _saveFailed = false;
  bool _saved = false;
  bool _saving = false;
  int _generation = 0;
  int _configRequest = 0;
  int _optionsRequest = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant FallbackModels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.client, widget.client) ||
        oldWidget.authorityToken != widget.authorityToken) {
      _generation++;
      _config = null;
      _rows = [];
      _models = {};
      _saving = false;
      _reload();
    } else if (oldWidget.refreshToken != widget.refreshToken && !_saving) {
      _reload();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool get _editable =>
      widget.enabled && !_loading && !_saving && _config != null;
  bool _current(int generation) => mounted && generation == _generation;
  void _reload() {
    _loadConfig();
    _loadOptions();
  }

  Future<void> _loadConfig() async {
    if (_saving) return;
    final generation = _generation;
    final request = ++_configRequest;
    final client = widget.client;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _saveFailed = false;
      _saved = false;
    });
    try {
      final config = await client.getFallbackConfig();
      if (!_current(generation) || request != _configRequest) return;
      setState(() {
        _config = config;
        _rows = config.entries.toList();
        _loading = false;
      });
    } catch (_) {
      if (!_current(generation) || request != _configRequest) return;
      setState(() {
        // Malformed persisted input must not leave a partially writable chain.
        _config = null;
        _rows = [];
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadOptions() async {
    if (_saving) return;
    final generation = _generation;
    final request = ++_optionsRequest;
    final client = widget.client;
    setState(() {
      _optionsLoading = true;
      _optionsFailed = false;
    });
    try {
      final data = await client.getModelOptions();
      if (!_current(generation) || request != _optionsRequest) return;
      final providers = data['providers'];
      if (providers is! List) throw const FormatException('Missing discovery');
      final models = <String, List<String>>{};
      for (final provider in providers.whereType<Map>()) {
        final slug = provider['slug'] ?? provider['id'];
        final raw = provider['models'];
        if (slug is! String ||
            slug.isEmpty ||
            raw is! List ||
            {'auto', 'custom', 'local'}.contains(slug) ||
            provider['is_user_defined'] == true ||
            (provider['api_url'] ?? '') != '' ||
            (provider['base_url'] ?? '') != '') {
          continue;
        }
        final ids = raw
            .map(
              (m) => m is String
                  ? m
                  : m is Map
                  ? m['id']
                  : null,
            )
            .whereType<String>()
            .where((m) => m.trim().isNotEmpty)
            .toSet()
            .toList();
        if (ids.isNotEmpty) models[slug] = ids;
      }
      if (models.isEmpty) {
        throw const FormatException('No standard model options');
      }
      setState(() {
        _models = models;
        _optionsLoading = false;
      });
    } catch (_) {
      if (!_current(generation) || request != _optionsRequest) return;
      setState(() {
        _models = {};
        _optionsLoading = false;
        _optionsFailed = true;
      });
    }
  }

  void _edit(VoidCallback change) {
    if (!_editable) return;
    setState(() {
      change();
      _saveFailed = false;
      _saved = false;
    });
  }

  Future<void> _save() async {
    if (!_editable || _optionsLoading || _rows.any((e) => !e.complete)) return;
    final generation = _generation;
    final client = widget.client;
    final before = _config!;
    final expected = List<FallbackEntry>.of(_rows);
    setState(() {
      _saving = true;
      _saveFailed = false;
      _saved = false;
    });
    widget.onSavingChanged?.call(true);
    try {
      final accepted = await client.setFallbackProviders(expected);
      if (!_current(generation)) return;
      if (!accepted) throw const FormatException('Fallback save rejected');
      final actual = await client.getFallbackConfig();
      if (!_current(generation)) return;
      if (!actual.confirms(expected, before)) {
        throw const FormatException('Fallback readback mismatch');
      }
      setState(() {
        _config = actual;
        _rows = actual.entries.toList();
        _saving = false;
        _saved = true;
      });
    } catch (_) {
      if (!_current(generation)) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
    if (_current(generation)) widget.onSavingChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      key: const ValueKey('fallback-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.fallback_title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Text(l10n.fallback_notice),
        if (_loading || _saving) const LinearProgressIndicator(),
        if (_loadFailed) ...[
          Text(l10n.fallback_unavailable),
          TextButton(
            key: const ValueKey('fallback-retry'),
            onPressed: widget.enabled && !_saving ? _loadConfig : null,
            child: Text(l10n.retry),
          ),
        ],
        if (_config != null && !_loading) ...[
          if (_optionsLoading) const LinearProgressIndicator(),
          if (_optionsFailed) ...[
            Text(l10n.fallback_discovery_unavailable),
            TextButton(
              key: const ValueKey('fallback-discovery-retry'),
              onPressed: _editable ? _loadOptions : null,
              child: Text(l10n.retry),
            ),
          ],
          if (_rows.isEmpty) Text(l10n.fallback_empty),
          for (var i = 0; i < _rows.length; i++) _row(i),
          if (_rows.any((e) => !e.complete)) Text(l10n.fallback_incomplete),
          OutlinedButton.icon(
            key: const ValueKey('fallback-add'),
            onPressed: _editable
                ? () => _edit(() => _rows.add(FallbackEntry.blank()))
                : null,
            icon: const Icon(Icons.add),
            label: Text(l10n.fallback_add),
          ),
          FilledButton.icon(
            key: const ValueKey('fallback-save'),
            onPressed:
                _editable && !_optionsLoading && _rows.every((e) => e.complete)
                ? _save
                : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(l10n.fallback_save),
          ),
          if (_saveFailed) Text(l10n.fallback_save_failed),
          if (_saved) Text(l10n.fallback_saved),
          if (_config!.legacyEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.fallback_legacy_title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(l10n.fallback_legacy_notice),
            for (final entry in _config!.legacyEntries)
              Text('${entry.provider} / ${entry.model}'),
          ],
        ],
      ],
    );
  }

  Widget _row(int index) {
    final entry = _rows[index];
    final l10n = context.l10n;
    final readOnly =
        entry.hasMetadata ||
        (entry.provider.isNotEmpty && !_models.containsKey(entry.provider));
    final pick = _editable && !_optionsLoading && !_optionsFailed && !readOnly;
    final providers = <String>{
      ..._models.keys,
      if (entry.provider.isNotEmpty) entry.provider,
    };
    final models = <String>{
      ...?_models[entry.provider],
      if (entry.model.isNotEmpty) entry.model,
    };
    return Card(
      key: ValueKey('fallback-row-$index'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.fallback_priority('${index + 1}')),
            if (readOnly) ...[
              Text('${entry.provider} / ${entry.model}'),
              Text(l10n.fallback_routing_read_only),
            ] else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('fallback-provider-$index:${entry.provider}'),
                initialValue: entry.provider.isEmpty ? null : entry.provider,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.provider),
                items: providers
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(p, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: pick
                    ? (p) {
                        if (p != null) {
                          _edit(() => _rows[index] = entry.select(p, ''));
                        }
                      }
                    : null,
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'fallback-model-$index:${entry.provider}:${entry.model}',
                ),
                initialValue: entry.model.isEmpty ? null : entry.model,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.model),
                items: models
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: pick && entry.provider.isNotEmpty
                    ? (m) {
                        if (m != null) {
                          _edit(
                            () =>
                                _rows[index] = entry.select(entry.provider, m),
                          );
                        }
                      }
                    : null,
              ),
            ],
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                IconButton(
                  key: ValueKey('fallback-up-$index'),
                  tooltip: l10n.fallback_move_up,
                  onPressed: _editable && index > 0
                      ? () => _edit(() {
                          _rows.removeAt(index);
                          _rows.insert(index - 1, entry);
                        })
                      : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: ValueKey('fallback-down-$index'),
                  tooltip: l10n.fallback_move_down,
                  onPressed: _editable && index < _rows.length - 1
                      ? () => _edit(() {
                          _rows.removeAt(index);
                          _rows.insert(index + 1, entry);
                        })
                      : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  key: ValueKey('fallback-delete-$index'),
                  tooltip: l10n.delete,
                  onPressed: _editable
                      ? () => _edit(() => _rows.removeAt(index))
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
