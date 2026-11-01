import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/connection_manager.dart';

/// A per-job pin, never a mutation of the profile's model configuration.
/// Keep the original route even when it is absent from discovery (custom routes,
/// retired models, or a temporarily unavailable provider).
class CronModelPicker extends StatefulWidget {
  const CronModelPicker({
    required this.client,
    required this.model,
    required this.provider,
    required this.baseUrl,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final DashboardClient client;
  final String model;
  final String provider;
  final String baseUrl;
  final bool enabled;
  final void Function(String model, String provider) onChanged;

  @override
  State<CronModelPicker> createState() => _CronModelPickerState();
}

class _CronModelPickerState extends State<CronModelPicker> {
  late Future<Map<String, dynamic>> _options;

  @override
  void initState() {
    super.initState();
    _options = widget.client.getModelOptions();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _options,
    builder: (context, snapshot) {
      final selected = jsonEncode([
        widget.provider,
        widget.model,
        widget.baseUrl,
      ]);
      final defaultValue = jsonEncode(['', '', '']);
      final choices = <String, String>{
        defaultValue: context.l10n.cron_model_default,
      };
      final providers = snapshot.data?['providers'];
      if (providers is List) {
        for (final provider in providers.whereType<Map>()) {
          final slug = provider['slug'] ?? provider['id'];
          final models = provider['models'];
          if (slug is! String || slug.isEmpty || models is! List) continue;
          for (final entry in models) {
            final model = entry is String
                ? entry
                : (entry is Map ? entry['id'] : null);
            if (model is! String || model.isEmpty) continue;
            choices[jsonEncode([slug, model, ''])] = '$model · $slug';
          }
        }
      }
      // Endpoint-only pins are not default, and a discovered pair without an
      // endpoint is a distinct choice from the same pair with a custom URL.
      choices.putIfAbsent(
        selected,
        () => [
          if (widget.model.isNotEmpty || widget.provider.isNotEmpty)
            '${widget.model} · ${widget.provider}',
          if (widget.baseUrl.isNotEmpty)
            '${context.l10n.base_url}: ${widget.baseUrl}',
        ].join(' · '),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(selected),
            initialValue: selected,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.l10n.model),
            items: [
              for (final choice in choices.entries)
                DropdownMenuItem(
                  value: choice.key,
                  child: Text(choice.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: !widget.enabled
                ? null
                : (value) {
                    if (value == null || value == selected) return;
                    final route = (jsonDecode(value) as List).cast<String>();
                    widget.onChanged(route[1], route[0]);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.cron_model_notice,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (snapshot.connectionState != ConnectionState.done)
            const LinearProgressIndicator(),
          if (snapshot.hasError) ...[
            Text(
              context.l10n.could_not_load_models_for_this_profile(
                snapshot.error!,
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _options = widget.client.getModelOptions();
                });
              },
              child: Text(context.l10n.retry),
            ),
          ],
        ],
      );
    },
  );
}
