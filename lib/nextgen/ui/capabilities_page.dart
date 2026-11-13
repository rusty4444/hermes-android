// Capabilities: turn skills, toolsets and MCP servers on or off for the
// profile this gateway talks to.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/services/dashboard_api_client.dart';
import '../data/nextgen_gateway.dart';
import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';

class _Item {
  final String name;
  final String label;
  final String description;
  bool enabled;
  _Item(this.name, this.label, this.description, this.enabled);
}

enum _Kind { skills, toolsets, mcp }

class NgCapabilitiesPage extends StatefulWidget {
  const NgCapabilitiesPage({super.key});

  @override
  State<NgCapabilitiesPage> createState() => _NgCapabilitiesPageState();
}

class _NgCapabilitiesPageState extends State<NgCapabilitiesPage> {
  _Kind _kind = _Kind.skills;
  final Map<_Kind, List<_Item>> _items = {};
  final Map<_Kind, String> _errors = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(_kind));
  }

  Map<String, String>? _profileQuery(NextGenGateway g) =>
      g.profile == null ? null : {'profile': g.profile!};

  Future<void> _load(_Kind kind) async {
    final g = NgScope.of(context).gateway;
    final endpoint = switch (kind) {
      _Kind.skills => 'skills',
      _Kind.toolsets => 'tools/toolsets',
      _Kind.mcp => 'mcp/servers',
    };
    try {
      final res = await g.dashboard.apiRequest(
        'GET',
        endpoint,
        queryParameters: _profileQuery(g),
      );
      if (res.statusCode != 200) {
        throw DashboardRequestException(
          res.statusCode,
          dashboardErrorMessage(res),
        );
      }
      final decoded = jsonDecode(res.body);
      final rows = decoded is List
          ? decoded
          : decoded is Map
          ? (decoded['servers'] ?? decoded['skills'] ?? decoded['toolsets'])
                    as List? ??
                const []
          : const [];
      final items = <_Item>[
        for (final r in rows.whereType<Map>())
          _Item(
            '${r['name']}',
            '${r['label'] ?? r['name']}',
            '${r['description'] ?? r['url'] ?? r['command'] ?? ''}',
            r['enabled'] != false,
          ),
      ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      if (mounted) {
        setState(() {
          _items[kind] = items;
          _errors.remove(kind);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errors[kind] = '$e');
    }
  }

  Future<void> _toggle(_Kind kind, _Item item, bool enabled) async {
    final g = NgScope.of(context).gateway;
    setState(() => item.enabled = enabled);
    final (endpoint, body) = switch (kind) {
      _Kind.skills => (
        'skills/toggle',
        {'name': item.name, 'enabled': enabled},
      ),
      _Kind.toolsets => (
        'tools/toolsets/${Uri.encodeComponent(item.name)}',
        {'enabled': enabled},
      ),
      _Kind.mcp => (
        'mcp/servers/${Uri.encodeComponent(item.name)}/enabled',
        {'enabled': enabled},
      ),
    };
    try {
      final res = await g.dashboard.apiRequest(
        'PUT',
        endpoint,
        body: body,
        queryParameters: _profileQuery(g),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw DashboardRequestException(
          res.statusCode,
          dashboardErrorMessage(res),
        );
      }
      if (mounted && kind != _Kind.skills) {
        ngToast(context, 'Applies to new chats');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => item.enabled = !enabled);
      ngToast(context, 'Couldn\'t change ${item.label}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final items = _items[_kind];
    final error = _errors[_kind];
    final q = _query.toLowerCase();
    final shown = items
        ?.where(
          (i) =>
              q.isEmpty ||
              i.label.toLowerCase().contains(q) ||
              i.description.toLowerCase().contains(q),
        )
        .toList();
    return NgPage(
      title: 'Capabilities',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: NgSegmented<_Kind>(
              values: _Kind.values,
              selected: _kind,
              labelOf: (k) => switch (k) {
                _Kind.skills => 'Skills',
                _Kind.toolsets => 'Toolsets',
                _Kind.mcp => 'MCP',
              },
              onChanged: (k) {
                setState(() => _kind = k);
                if (_items[k] == null) _load(k);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.input,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Search',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NgRadii.full),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: error != null
                ? NgEmpty(
                    icon: Icons.extension_off_outlined,
                    title: 'Couldn\'t load',
                    body: error,
                    action: TextButton(
                      onPressed: () => _load(_kind),
                      child: const Text('Try again'),
                    ),
                  )
                : shown == null
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                ? NgEmpty(
                    icon: Icons.extension_outlined,
                    title: switch (_kind) {
                      _Kind.skills => 'No skills',
                      _Kind.toolsets => 'No toolsets',
                      _Kind.mcp => 'No MCP servers',
                    },
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(_kind),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final item = shown[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: NgCard(
                            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                item.label,
                                style: NgType.label.copyWith(color: c.text),
                              ),
                              subtitle: item.description.isEmpty
                                  ? null
                                  : Text(
                                      item.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: NgType.caption.copyWith(
                                        color: c.text3,
                                      ),
                                    ),
                              value: item.enabled,
                              onChanged: (v) => _toggle(_kind, item, v),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
