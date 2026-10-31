/// Read-only gateway Portal status and profile-wide recorded analytics.
/// These endpoints do not expose a Portal balance, pricing or subscription plan.
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../services/connection_manager.dart';

class NousPortalScreen extends StatefulWidget {
  final SavedConnection connection;
  @visibleForTesting
  final http.Client? testHttpClient;

  const NousPortalScreen({
    required this.connection,
    this.testHttpClient,
    super.key,
  });

  @override
  State<NousPortalScreen> createState() => _NousPortalScreenState();
}

class _NousPortalScreenState extends State<NousPortalScreen> {
  late DashboardClient _client;
  int _generation = 0;
  bool _loading = false;
  final _data = <String, Map<String, dynamic>>{};
  final _failed = <String>{};

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(covariant NousPortalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection ||
        oldWidget.testHttpClient != widget.testHttpClient) {
      _generation++;
      _client.close();
      _connect();
    }
  }

  void _connect() {
    final connection = widget.connection;
    _client = DashboardClient(
      host: connection.host,
      port: connection.dashboardPort,
      pathPrefix: connection.dashboardPrefix ?? '',
      proxied: connection.dashboardProxied,
      useHttps: connection.useHttps,
      username: connection.dashboardUsername,
      password: connection.dashboardPassword,
      gatewayProfile: connection.gatewayProfile,
      clientCertificate: connection.clientCertificate,
      httpClient: widget.testHttpClient,
    );
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final client = _client;
    setState(() {
      _loading = true;
      // Do not present stale status as current after a failed refresh.
      _data.clear();
      _failed.clear();
    });
    Future<void> read(
      String section,
      Future<Map<String, dynamic>> Function() fetch,
    ) async {
      try {
        final data = await fetch();
        if (!mounted || generation != _generation) return;
        setState(() => _data[section] = data);
      } catch (_) {
        if (!mounted || generation != _generation) return;
        // Raw response/error text is not safe UI (may include host or auth data).
        setState(() => _failed.add(section));
      }
    }

    await Future.wait([
      read('portal', client.getPortal),
      read('usage', client.getAnalytics),
      read('models', client.getModelsAnalytics),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() => _loading = false);
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map<String, dynamic> ? value : const {};

  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : const [];

  String _text(dynamic value) =>
      value is String && value.isNotEmpty ? value : '—';

  String _number(dynamic value) =>
      value is num && value.isFinite ? '$value' : '—';

  String _cost(dynamic value) =>
      value is num && value.isFinite ? 'USD ${value.toStringAsFixed(4)}' : '—';

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text('$label: $value'),
  );

  Widget _section(
    String id,
    String title,
    List<Widget> Function(Map<String, dynamic>) content,
  ) {
    final data = _data[id];
    return Card(
      key: ValueKey('portal-$id'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_failed.contains(id))
              Text(context.l10n.portal_unavailable)
            else if (data == null)
              const LinearProgressIndicator()
            else
              ...content(data),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nous_portal),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!_loading) await _load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.portal_read_only),
            const SizedBox(height: 8),
            _section(
              'portal',
              l10n.portal_status,
              (data) => [
                Text(
                  data['free_tier'] == true
                      ? l10n.portal_free_tier
                      : data['logged_in'] == true
                      ? l10n.portal_signed_in
                      : data['logged_in'] == false
                      ? l10n.portal_signed_out
                      : l10n.portal_unavailable,
                ),
                _row(l10n.provider, _text(data['provider'])),
                _row(l10n.portal_account_tier, _text(data['account_tier'])),
                for (final feature in _rows(data['features']))
                  _row(_text(feature['label']), _text(feature['state'])),
              ],
            ),
            _section('usage', l10n.portal_recorded_usage, (data) {
              final totals = _map(data['totals']);
              return [
                Text(l10n.portal_all_providers),
                Text(l10n.portal_period(_number(data['period_days']))),
                _row(l10n.portal_sessions, _number(totals['total_sessions'])),
                _row(l10n.portal_input, _number(totals['total_input'])),
                _row(l10n.portal_output, _number(totals['total_output'])),
                _row(
                  l10n.portal_estimated,
                  _cost(totals['total_estimated_cost']),
                ),
                _row(l10n.portal_actual, _cost(totals['total_actual_cost'])),
              ];
            }),
            _section('models', l10n.portal_recorded_models, (data) {
              final models = _rows(data['models']);
              return [
                Text(l10n.portal_all_providers),
                Text(l10n.portal_period(_number(data['period_days']))),
                if (models.isEmpty) Text(l10n.portal_no_models),
                for (final model in models) ...[
                  const Divider(),
                  Text(
                    _text(model['model']),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  _row(l10n.provider, _text(model['provider'])),
                  _row(l10n.portal_sessions, _number(model['sessions'])),
                  _row(l10n.portal_input, _number(model['input_tokens'])),
                  _row(l10n.portal_output, _number(model['output_tokens'])),
                  _row(l10n.portal_estimated, _cost(model['estimated_cost'])),
                  _row(l10n.portal_actual, _cost(model['actual_cost'])),
                ],
              ];
            }),
            if (_failed.isNotEmpty)
              TextButton(
                onPressed: _loading ? null : _load,
                child: Text(l10n.retry),
              ),
          ],
        ),
      ),
    );
  }
}
