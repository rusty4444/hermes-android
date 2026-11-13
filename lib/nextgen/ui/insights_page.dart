// Insights (`/api/analytics/usage`): totals, daily tokens and the busiest
// models, skills and tools over 7, 30 or 90 days.
import 'package:flutter/material.dart';

import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';

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

  Future<void> _load() async {
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final data = await NgScope.of(
        context,
      ).gateway.dashboard.getAnalytics(days: _days);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  static num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final data = _data;
    return NgPage(
      title: 'Insights',
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
              title: 'Couldn\'t load insights',
              body: _error,
            )
          else if (data == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
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
          stat('Sessions', ngCompactNumber(_n(totals['total_sessions']))),
          const SizedBox(width: 10),
          stat('API calls', ngCompactNumber(_n(totals['total_api_calls']))),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          stat(
            'Tokens',
            ngCompactNumber(
              _n(totals['total_input']) + _n(totals['total_output']),
            ),
          ),
          const SizedBox(width: 10),
          stat('Est. cost', cost == 0 ? '—' : '\$${cost.toStringAsFixed(2)}'),
        ],
      ),
      if (daily.isNotEmpty) ...[
        const NgSectionLabel('Daily tokens'),
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
      rankCard('Models', ranked(data['by_model']), 'model', 'sessions'),
      rankCard(
        'Skills',
        ranked(skills is Map ? skills['top_skills'] : skills),
        'skill',
        'total_count',
      ),
      rankCard('Tools', ranked(data['tools']), 'tool', 'count'),
    ];
  }
}
