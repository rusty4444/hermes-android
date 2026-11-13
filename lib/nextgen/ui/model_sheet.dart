// Model and thinking-level picker (Kyllene's model sheet): thinking levels,
// search, starred and recent models, then every configured provider.
import 'package:flutter/material.dart';

import '../data/chat_controller.dart';
import '../nextgen_preferences.dart';
import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';

/// Reasoning levels, weakest first, as `config.set reasoning` takes them.
const ngEfforts = <(String, String)>[
  ('none', 'Off'),
  ('minimal', 'Minimal'),
  ('low', 'Low'),
  ('medium', 'Medium'),
  ('high', 'High'),
  ('xhigh', 'Extra high'),
  ('max', 'Max'),
  ('ultra', 'Ultra'),
];

String ngEffortLabel(String? wire) =>
    ngEfforts.where((e) => e.$1 == wire).firstOrNull?.$2 ?? 'Default';

class NgModelChoice {
  final String provider;
  final String providerName;
  final String model;
  const NgModelChoice(this.provider, this.providerName, this.model);
  String get key => '$provider/$model';
}

class NgProviderModels {
  final String slug;
  final String name;
  final List<String> models;
  const NgProviderModels(this.slug, this.name, this.models);
}

List<NgProviderModels> parseModelOptions(Map<String, dynamic> data) {
  final out = <NgProviderModels>[];
  final seen = <String>{};
  for (final row in (data['providers'] as List? ?? const [])) {
    if (row is! Map) continue;
    final slug = row['slug']?.toString() ?? row['id']?.toString();
    if (slug == null || slug.isEmpty || !seen.add(slug)) continue;
    final unavailable = {
      for (final m in (row['unavailable_models'] as List? ?? const [])) '$m',
    };
    final models = <String>[];
    for (final m in (row['models'] as List? ?? const [])) {
      final id = m is Map ? (m['id'] ?? m['name'])?.toString() : m?.toString();
      if (id == null || id.isEmpty || unavailable.contains(id)) continue;
      if (!models.contains(id)) models.add(id);
    }
    if (models.isEmpty) continue;
    final name = row['name']?.toString();
    out.add(
      NgProviderModels(
        slug,
        name == null || name.isEmpty ? slug : name,
        models,
      ),
    );
  }
  return out;
}

/// Opens the picker. NextGen's routes live in a nested navigator under
/// [NgScope], so the sheet sees the scope too.
Future<void> showNgModelSheet(BuildContext context, NgChatController chat) =>
    showNgSheet<void>(context, builder: (_) => _ModelSheet(chat: chat));

class _ModelSheet extends StatefulWidget {
  const _ModelSheet({required this.chat});
  final NgChatController chat;

  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  List<NgProviderModels>? _providers;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await NgScope.of(
        context,
      ).gateway.dashboard.getModelOptions();
      if (mounted) setState(() => _providers = parseModelOptions(data));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pick(NgModelChoice choice) async {
    final prefs = NgScope.of(context).prefs;
    Navigator.pop(context);
    await NextGenPreferences.pushRecentModel(prefs, choice.key);
    try {
      await widget.chat.setModel(
        provider: choice.provider,
        model: choice.model,
      );
    } catch (e) {
      widget.chat.error = 'Couldn\'t switch model: $e';
    }
  }

  Future<void> _toggleStar(String key) async {
    final prefs = NgScope.of(context).prefs;
    final starred = [...NextGenPreferences.starredModels(prefs)];
    starred.contains(key) ? starred.remove(key) : starred.insert(0, key);
    await NextGenPreferences.setStarredModels(prefs, starred);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final prefs = NgScope.of(context).prefs;
    final chat = widget.chat;
    final providers = _providers;
    final all = <String, NgModelChoice>{
      for (final p in providers ?? const <NgProviderModels>[])
        for (final m in p.models)
          '${p.slug}/$m': NgModelChoice(p.slug, p.name, m),
    };
    final starred = NextGenPreferences.starredModels(prefs);
    final recent = NextGenPreferences.recentModels(prefs);
    final q = _query.toLowerCase();
    bool matches(NgModelChoice m) =>
        q.isEmpty ||
        m.model.toLowerCase().contains(q) ||
        m.providerName.toLowerCase().contains(q);

    Widget modelTile(NgModelChoice m) {
      final current =
          m.model == chat.model &&
          (chat.provider == null || chat.provider == m.provider);
      final isStarred = starred.contains(m.key);
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: Icon(
          current ? Icons.check_circle : Icons.circle_outlined,
          size: 20,
          color: current ? c.accent : c.text3,
        ),
        title: Text(m.model, style: NgType.label.copyWith(color: c.text)),
        subtitle: Text(
          m.providerName,
          style: NgType.caption.copyWith(color: c.text3),
        ),
        trailing: IconButton(
          icon: Icon(
            isStarred ? Icons.star : Icons.star_border,
            color: isStarred ? c.warning : c.text3,
            size: 20,
          ),
          onPressed: () => _toggleStar(m.key),
        ),
        onTap: () => _pick(m),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Model', style: NgType.title.copyWith(color: c.text)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: NgSectionLabel('Thinking'),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              children: [
                for (final (wire, label) in ngEfforts.skip(2))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: chat.reasoningEffort == wire,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (_) async {
                        await chat.setReasoning(wire);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.input,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Search models',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NgRadii.full),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Couldn\'t load models: $_error',
                style: NgType.bodySmall.copyWith(color: c.danger),
              ),
            )
          else if (providers == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (providers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No providers are set up on this gateway yet.',
                style: NgType.bodySmall.copyWith(color: c.text3),
              ),
            )
          else ...[
            if (q.isEmpty) ...[
              if (starred.any(all.containsKey)) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: NgSectionLabel('Starred'),
                ),
                for (final k in starred)
                  if (all[k] != null) modelTile(all[k]!),
              ],
              if (recent.any(
                (k) => all.containsKey(k) && !starred.contains(k),
              )) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: NgSectionLabel('Recent'),
                ),
                for (final k in recent)
                  if (all[k] != null && !starred.contains(k))
                    modelTile(all[k]!),
              ],
            ],
            for (final p in providers)
              if (p.models.any(
                (m) => matches(NgModelChoice(p.slug, p.name, m)),
              )) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: NgSectionLabel(p.name),
                ),
                for (final m in p.models)
                  if (matches(NgModelChoice(p.slug, p.name, m)))
                    modelTile(NgModelChoice(p.slug, p.name, m)),
              ],
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
