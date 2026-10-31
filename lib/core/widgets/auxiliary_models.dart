import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../services/connection_manager.dart';

/// Dashboard-owned assignments. No local provider credentials or API-server RPCs.
class AuxiliaryModels extends StatefulWidget {
  final DashboardClient client;
  const AuxiliaryModels({required this.client, super.key});
  @override
  State<AuxiliaryModels> createState() => _AuxiliaryModelsState();
}

class _AuxiliaryModelsState extends State<AuxiliaryModels> {
  List<Map<String, dynamic>> _tasks = [];
  Map<String, List<String>> _models = {};
  bool _busy = true;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final data = await Future.wait([
        widget.client.getAuxiliaryModels(),
        widget.client.getModelOptions(),
      ]);
      if (!mounted || generation != _generation) return;
      final tasks = data[0]['tasks'];
      final providers = data[1]['providers'];
      if (tasks is! List || providers is! List) {
        throw const FormatException('Invalid auxiliary model options');
      }
      final models = <String, List<String>>{};
      for (final provider in providers.whereType<Map>()) {
        final slug = provider['slug'] ?? provider['id'];
        final raw = provider['models'];
        if (slug is! String ||
            raw is! List ||
            slug == 'auto' ||
            slug == 'custom' ||
            slug == 'local' ||
            provider['base_url'] != null && provider['base_url'] != '') {
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
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (ids.isNotEmpty) models[slug] = ids;
      }
      setState(() {
        _tasks = tasks
            .whereType<Map<String, dynamic>>()
            .where(
              (t) => t['task'] is String && (t['task'] as String).isNotEmpty,
            )
            .toList();
        _models = models;
        _busy = false;
      });
    } on Exception {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  Future<void> _apply(String task, String provider, String model) async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      // The backend may return HTTP 200 with ok:false for expensive-model
      // confirmation. Do not bypass that guard or claim it was saved.
      final result = await widget.client.setAuxiliaryModel(
        task: task,
        provider: provider,
        model: model,
      );
      if (!mounted || generation != _generation) return;
      if (result['ok'] != true) {
        throw const FormatException('Assignment not confirmed');
      }
      final data = await widget.client.getAuxiliaryModels();
      if (!mounted || generation != _generation) return;
      final tasks = data['tasks'];
      if (tasks is! List ||
          !tasks.whereType<Map>().any(
            (t) =>
                t['task'] == task &&
                t['provider'] == provider &&
                t['model'] == model,
          )) {
        throw const FormatException('Assignment read-back did not match');
      }
      setState(() {
        _tasks = tasks.whereType<Map<String, dynamic>>().toList();
        _busy = false;
      });
    } on Exception {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.auxiliary_models,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      Text(context.l10n.auxiliary_notice),
      if (_busy) const LinearProgressIndicator(),
      if (_failed) ...[
        Text(context.l10n.auxiliary_unavailable),
        TextButton(
          onPressed: _busy ? null : _load,
          child: Text(context.l10n.retry),
        ),
      ],
      for (final task in _tasks)
        _AuxiliaryTask(
          key: ValueKey(task['task']),
          task: task,
          models: _models,
          busy: _busy,
          onApply: _apply,
        ),
    ],
  );
}

class _AuxiliaryTask extends StatefulWidget {
  final Map<String, dynamic> task;
  final Map<String, List<String>> models;
  final bool busy;
  final Future<void> Function(String, String, String) onApply;
  const _AuxiliaryTask({
    required this.task,
    required this.models,
    required this.busy,
    required this.onApply,
    super.key,
  });
  @override
  State<_AuxiliaryTask> createState() => _AuxiliaryTaskState();
}

class _AuxiliaryTaskState extends State<_AuxiliaryTask> {
  late String _provider;
  late String _model;
  void _reset() {
    _provider = widget.task['provider'] is String
        ? widget.task['provider'] as String
        : 'auto';
    _model = widget.task['model'] is String
        ? widget.task['model'] as String
        : '';
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant _AuxiliaryTask oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.task, oldWidget.task)) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final custom =
        (widget.task['base_url'] ?? '') != '' ||
        _provider == 'custom' ||
        _provider == 'local';
    final providers = <String>{
      'auto',
      ...widget.models.keys,
      _provider,
    }.toList();
    final models = <String>{
      ...widget.models[_provider] ?? [],
      if (_model.isNotEmpty) _model,
    }.toList();
    // Unsupported custom endpoints remain read-only; changing a dropdown must
    // not silently clear a stored endpoint or select an arbitrary catalogue model.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.task['label'] is String
                  ? widget.task['label'] as String
                  : widget.task['task'] as String,
            ),
            Text('${widget.task['provider']} / ${widget.task['model']}'),
            if (custom)
              Text(context.l10n.auxiliary_notice)
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('provider:$_provider'),
                initialValue: _provider,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.l10n.provider),
                items: providers
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          p == 'auto' ? context.l10n.auxiliary_inherit : p,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: widget.busy
                    ? null
                    : (p) {
                        if (p != null) {
                          setState(() {
                            _provider = p;
                            _model = '';
                          });
                        }
                      },
              ),
              if (_provider != 'auto')
                DropdownButtonFormField<String>(
                  key: ValueKey('model:$_provider:$_model'),
                  initialValue: _model.isEmpty ? null : _model,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.l10n.model),
                  items: models
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(m, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: widget.busy
                      ? null
                      : (m) {
                          if (m != null) setState(() => _model = m);
                        },
                ),
              FilledButton(
                onPressed:
                    widget.busy || (_provider != 'auto' && _model.isEmpty)
                    ? null
                    : () => widget.onApply(
                        widget.task['task'] as String,
                        _provider,
                        _model,
                      ),
                child: Text(context.l10n.save),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
