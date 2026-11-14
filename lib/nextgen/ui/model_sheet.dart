// Model and thinking-level picker (Kyllene's model sheet): thinking levels,
// search, starred and recent models, then every configured provider.
import 'package:flutter/material.dart';

import '../../core/screens/model_management_screen.dart';

import '../data/chat_controller.dart';
import '../nextgen_preferences.dart';
import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';
import '../nextgen_l10n.dart';

/// Reasoning levels, weakest first, as `config.set reasoning` takes them.
List<(String, String)> get ngEfforts => [
  ('none', ngL.ng_off),
  ('minimal', ngL.ng_minimal),
  ('low', ngL.ng_low),
  ('medium', ngL.ng_medium),
  ('high', ngL.ng_high),
  ('xhigh', ngL.ng_extra_high),
  ('max', ngL.ng_max),
  ('ultra', ngL.ng_ultra),
];

String ngEffortLabel(String? wire) =>
    ngEfforts.where((e) => e.$1 == wire).firstOrNull?.$2 ?? ngL.ng_default;

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

/// Opens the picker and carries the current scope into either a nested or root
/// navigator's bottom sheet.
Future<void> showNgModelSheet(BuildContext context, NgChatController chat) {
  final scope = NgScope.of(context);
  return showNgSheet<void>(
    context,
    builder: (_) => NgScope(
      connManager: scope.connManager,
      gateway: scope.gateway,
      connections: scope.connections,
      switchTo: scope.switchTo,
      addGateway: scope.addGateway,
      signOut: scope.signOut,
      reload: scope.reload,
      signInAgain: scope.signInAgain,
      child: _ModelSheet(chat: chat),
    ),
  );
}

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
  String? _providerFilter;

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
      widget.chat.error = ngL.ng_couldn_t_switch_model(e);
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
    final visibleProviders = [
      for (final p in providers ?? const <NgProviderModels>[])
        if (_providerFilter == null || p.slug == _providerFilter) p,
    ];
    final all = <String, NgModelChoice>{
      for (final p in visibleProviders)
        for (final m in p.models)
          '${p.slug}/$m': NgModelChoice(p.slug, p.name, m),
    };
    final starred = NextGenPreferences.starredModels(prefs);
    final recent = NextGenPreferences.recentModels(prefs);
    final q = _query.toLowerCase();
    bool matches(NgModelChoice m) =>
        q.isEmpty ||
        m.model.toLowerCase().contains(q) ||
        m.providerName.toLowerCase().contains(q) ||
        m.provider.toLowerCase().contains(q);

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
            child: Text(
              ngL.ng_model,
              style: NgType.title.copyWith(color: c.text),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: NgRow(
              key: const ValueKey('ng-model-sheet-management'),
              icon: Icons.tune,
              title: ngL.ng_model_management,
              subtitle: ngL.ng_default_fallback_and_auxiliary_models,
              onTap: () {
                final scope = NgScope.of(context);
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => ModelManagementScreen(
                      connection: scope.connection,
                      dashboardClient: scope.gateway.dashboard,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: NgSectionLabel(ngL.ng_thinking_2),
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
              key: const ValueKey('ng-model-search'),
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.input,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: ngL.ng_search_models,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NgRadii.full),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (providers != null && providers.length > 1)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: const ValueKey('ng-model-provider-all'),
                      label: Text(ngL.ng_all),
                      selected: _providerFilter == null,
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      onSelected: (_) => setState(() => _providerFilter = null),
                    ),
                  ),
                  for (final p in providers)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        key: ValueKey('ng-model-provider-${p.slug}'),
                        label: Text(p.name),
                        selected: _providerFilter == p.slug,
                        showCheckmark: false,
                        shape: const StadiumBorder(),
                        onSelected: (_) => setState(() {
                          _providerFilter = _providerFilter == p.slug
                              ? null
                              : p.slug;
                        }),
                      ),
                    ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                ngL.ng_couldn_t_load_models(_error ?? ''),
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
                ngL.ng_no_providers_are_set_up_on,
                style: NgType.bodySmall.copyWith(color: c.text3),
              ),
            )
          else ...[
            if (q.isEmpty) ...[
              if (starred.any(all.containsKey)) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: NgSectionLabel(ngL.ng_starred),
                ),
                for (final k in starred)
                  if (all[k] != null) modelTile(all[k]!),
              ],
              if (recent.any(
                (k) => all.containsKey(k) && !starred.contains(k),
              )) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: NgSectionLabel(ngL.ng_recent),
                ),
                for (final k in recent)
                  if (all[k] != null && !starred.contains(k))
                    modelTile(all[k]!),
              ],
            ],
            if (!all.values.any(matches))
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  ngL.ng_no_models_match,
                  style: NgType.bodySmall.copyWith(color: c.text3),
                ),
              ),
            for (final p in visibleProviders)
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
