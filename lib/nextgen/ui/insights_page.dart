// Insights (`/api/analytics/usage`): totals, daily tokens and the busiest
// models, skills and tools over 7, 30 or 90 days.
import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';
import '../nextgen_l10n.dart';

class NgInsightsPage extends StatefulWidget {
  const NgInsightsPage({super.key});

  @override
  State<NgInsightsPage> createState() => _NgInsightsPageState();
}

class _NgInsightsPageState extends State<NgInsightsPage> {
  int _days = 30;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  int _generation = 0;

  Future<void> _load() async {
    final generation = ++_generation;
    bool current() => mounted && generation == _generation;
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final data = await NgScope.of(
        context,
      ).gateway.dashboard.getAnalytics(days: _days);
      if (current()) setState(() => _data = data);
    } on TimeoutException {
      if (current()) setState(() => _error = ngL.ng_insights_timed_out);
    } catch (e) {
      if (current()) {
        setState(
          () => _error = '$e'
              .replaceFirst('Exception: ', '')
              .replaceFirst('DashboardHttpException', 'HTTP'),
        );
      }
    }
  }

  static num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final data = _data;
    return NgPage(
      title: ngL.ng_insights,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          NgSegmented<int>(
            values: const [7, 30, 90],
            selected: _days,
            labelOf: (d) => '$d days',
            onChanged: (d) {
              setState(() => _days = d);
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (_error != null)
            NgEmpty(
              icon: Icons.insights_outlined,
              title: ngL.ng_couldn_t_load_insights,
              body: _error,
              action: FilledButton.tonal(
                onPressed: _load,
                child: Text(ngL.ng_try_again),
              ),
            )
          else if (data == null)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    ngL.ng_insights_building,
                    textAlign: TextAlign.center,
                    style: NgType.bodySmall.copyWith(color: c.text3),
                  ),
                ],
              ),
            )
          else
            ..._content(c, data),
        ],
      ),
    );
  }

  List<Widget> _content(NgColors c, Map<String, dynamic> data) {
    final totals = data['totals'] is Map
        ? Map<String, dynamic>.from(data['totals'] as Map)
        : <String, dynamic>{};
    final daily = (data['daily'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    Widget stat(String label, String value) => Expanded(
      child: NgCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: NgType.caption.copyWith(color: c.text3)),
            const SizedBox(height: 6),
            Text(value, style: NgType.title.copyWith(color: c.text)),
          ],
        ),
      ),
    );
    final cost = _n(totals['total_estimated_cost']);
    final maxTokens = daily.fold<num>(
      0,
      (m, d) => (_n(d['input_tokens']) + _n(d['output_tokens'])) > m
          ? _n(d['input_tokens']) + _n(d['output_tokens'])
          : m,
    );
    List<Map> ranked(Object? rows) =>
        (rows is List ? rows : const []).whereType<Map>().take(6).toList();
    final skills = data['skills'];
    Widget rankCard(
      String title,
      List<Map> rows,
      String nameKey,
      String valueKey,
    ) {
      if (rows.isEmpty) return const SizedBox.shrink();
      final top = rows
          .map((r) => _n(r[valueKey]))
          .fold<num>(0, (a, b) => b > a ? b : a);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NgSectionLabel(title),
          NgCard(
            child: Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${r[nameKey] ?? r['name'] ?? '—'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NgType.label.copyWith(color: c.text),
                              ),
                            ),
                            Text(
                              ngCompactNumber(_n(r[valueKey])),
                              style: NgType.caption.copyWith(color: c.text3),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: top == 0 ? 0 : _n(r[valueKey]) / top,
                            backgroundColor: c.well,
                            color: c.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return [
      Row(
        children: [
          stat(ngL.ng_sessions, ngCompactNumber(_n(totals['total_sessions']))),
          const SizedBox(width: 10),
          stat(
            ngL.ng_api_calls,
            ngCompactNumber(_n(totals['total_api_calls'])),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          stat(
            ngL.ng_tokens,
            ngCompactNumber(
              _n(totals['total_input']) + _n(totals['total_output']),
            ),
          ),
          const SizedBox(width: 10),
          stat(
            ngL.ng_est_cost,
            cost == 0 ? '—' : '\$${cost.toStringAsFixed(2)}',
          ),
        ],
      ),
      if (daily.isNotEmpty) ...[
        NgSectionLabel(ngL.ng_daily_tokens),
        NgCard(
          child: SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in daily)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${d['day']}: ${ngCompactNumber(_n(d['input_tokens']) + _n(d['output_tokens']))}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          height: maxTokens == 0
                              ? 2
                              : 2 +
                                    138 *
                                        (_n(d['input_tokens']) +
                                            _n(d['output_tokens'])) /
                                        maxTokens,
                          decoration: BoxDecoration(
                            color: c.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      rankCard(ngL.ng_models, ranked(data['by_model']), 'model', 'sessions'),
      rankCard(
        ngL.ng_skills,
        ranked(skills is Map ? skills['top_skills'] : skills),
        'skill',
        'total_count',
      ),
      rankCard(ngL.ng_tools, ranked(data['tools']), 'tool', 'count'),
    ];
  }
}
