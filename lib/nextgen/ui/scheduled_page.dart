// Scheduled jobs (`/api/cron/jobs`): list, create, run now, pause/resume,
// delete, and each job's past runs (opening a run opens its chat).
import 'package:flutter/material.dart';

import '../../core/models/session.dart';
import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'sessions_sidebar.dart';
import 'widgets.dart';
import '../nextgen_l10n.dart';

DateTime? ngParseTime(Object? v) {
  if (v == null) return null;
  if (v is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      (v > 1e12 ? v : v * 1000).round(),
    );
  }
  return DateTime.tryParse('$v')?.toLocal();
}

String ngWhen(DateTime? t) {
  if (t == null) return '—';
  final now = DateTime.now();
  final diff = t.difference(now);
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return ngL.ng_today(hm);
  }
  if (diff.inDays.abs() < 7) {
    final days = [
      ngL.ng_mon,
      ngL.ng_tue,
      ngL.ng_wed,
      ngL.ng_thu,
      ngL.ng_fri,
      ngL.ng_sat,
      ngL.ng_sun,
    ];
    return '${days[t.weekday - 1]} $hm';
  }
  return '${t.day}/${t.month}/${t.year} $hm';
}

class NgScheduledPage extends StatefulWidget {
  const NgScheduledPage({super.key, required this.onOpenSession});
  final ValueChanged<Session> onOpenSession;

  @override
  State<NgScheduledPage> createState() => _NgScheduledPageState();
}

class _NgScheduledPageState extends State<NgScheduledPage> {
  List<Map<String, dynamic>>? _jobs;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final jobs = await NgScope.of(context).gateway.dashboard.getCronJobs();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _create() async {
    final created = await showNgSheet<bool>(
      context,
      builder: (_) => _NewJobSheet(scope: NgScope.of(context)),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final jobs = _jobs;
    return NgPage(
      title: ngL.ng_scheduled,
      floating: FloatingActionButton.extended(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(ngL.ng_new_job),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _error != null
            ? ListView(
                children: [
                  NgEmpty(
                    icon: Icons.cloud_off,
                    title: ngL.ng_couldn_t_load_scheduled_jobs,
                    body: _error,
                  ),
                ],
              )
            : jobs == null
            ? const Center(child: CircularProgressIndicator())
            : jobs.isEmpty
            ? ListView(
                children: [
                  NgEmpty(
                    icon: Icons.schedule,
                    title: ngL.ng_nothing_scheduled,
                    body: ngL.ng_ask_hermes_to_do_something_on,
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: jobs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final job = jobs[i];
                  final enabled =
                      job['enabled'] != false &&
                      job['state']?.toString() != 'paused';
                  final last = job['last_status']?.toString();
                  return NgCard(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _JobPage(
                            job: job,
                            onOpenSession: widget.onOpenSession,
                          ),
                        ),
                      );
                      await _load();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _jobName(job),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NgType.heading.copyWith(color: c.text),
                              ),
                            ),
                            NgPill(
                              enabled ? ngL.ng_active : ngL.ng_paused,
                              tone: enabled ? NgTone.success : NgTone.neutral,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          job['schedule_display']?.toString() ??
                              job['schedule']?.toString() ??
                              '',
                          style: NgType.bodySmall.copyWith(color: c.text2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (enabled)
                              ngL.ng_next(
                                ngWhen(ngParseTime(job['next_run_at'])),
                              ),
                            if (job['last_run_at'] != null)
                              last == null
                                  ? ngL.ng_last(
                                      ngWhen(ngParseTime(job['last_run_at'])),
                                    )
                                  : ngL.ng_last_2(
                                      ngWhen(ngParseTime(job['last_run_at'])),
                                      last,
                                    ),
                          ].join('   '),
                          style: NgType.caption.copyWith(
                            color: last == 'error' || last == 'failed'
                                ? c.danger
                                : c.text3,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

String _jobName(Map<String, dynamic> job) {
  final name = job['name']?.toString().trim() ?? '';
  if (name.isNotEmpty) return name;
  final prompt = job['prompt']?.toString().trim() ?? '';
  return prompt.isEmpty ? ngL.ng_job(job['id']) : prompt.split('\n').first;
}

class _JobPage extends StatefulWidget {
  const _JobPage({required this.job, required this.onOpenSession});
  final Map<String, dynamic> job;
  final ValueChanged<Session> onOpenSession;

  @override
  State<_JobPage> createState() => _JobPageState();
}

class _JobPageState extends State<_JobPage> {
  late Map<String, dynamic> _job = widget.job;
  List<Session>? _runs;
  bool _busy = false;

  String get _id => '${_job['id']}';
  bool get _enabled =>
      _job['enabled'] != false && _job['state']?.toString() != 'paused';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final d = NgScope.of(context).gateway.dashboard;
    try {
      final results = await Future.wait([
        d.getCronJob(_id),
        d.getCronJobRuns(_id),
      ]);
      if (!mounted) return;
      setState(() {
        final job = results[0] as Map<String, dynamic>;
        _job = job['job'] is Map
            ? Map<String, dynamic>.from(job['job'] as Map)
            : job;
        _runs = results[1] as List<Session>;
      });
    } catch (e) {
      if (mounted) setState(() => _runs ??= const []);
    }
  }

  Future<void> _do(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ngToast(context, done);
      await _load();
    } catch (e) {
      if (mounted) ngToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final d = NgScope.of(context).gateway.dashboard;
    final runs = _runs;
    return NgPage(
      title: _jobName(_job),
      actions: [
        IconButton(
          tooltip: ngL.ng_delete,
          icon: Icon(Icons.delete_outline, color: c.danger),
          onPressed: _busy
              ? null
              : () async {
                  final ok = await ngConfirm(
                    context,
                    title: ngL.ng_delete_this_job,
                    body: ngL.ng_it_stops_running_past_runs_stay,
                  );
                  if (!ok || !context.mounted) return;
                  try {
                    await d.deleteJob(_id);
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) ngToast(context, '$e');
                  }
                },
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          NgCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _job['schedule_display']?.toString() ??
                      _job['schedule']?.toString() ??
                      '',
                  style: NgType.heading.copyWith(color: c.text),
                ),
                const SizedBox(height: 6),
                Text(
                  _enabled
                      ? ngL.ng_next_run(
                          ngWhen(ngParseTime(_job['next_run_at'])),
                        )
                      : ngL.ng_paused,
                  style: NgType.bodySmall.copyWith(color: c.text3),
                ),
                if ((_job['deliver']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    ngL.ng_delivers_to(_job['deliver']),
                    style: NgType.bodySmall.copyWith(color: c.text3),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: NgPrimaryButton(
                        label: ngL.ng_run_now,
                        icon: Icons.play_arrow_rounded,
                        busy: _busy,
                        onPressed: () =>
                            _do(() => d.triggerJob(_id), ngL.ng_started),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: NgSecondaryButton(
                        label: _enabled ? ngL.ng_pause : ngL.ng_resume,
                        icon: _enabled
                            ? Icons.pause
                            : Icons.play_circle_outline,
                        onPressed: _busy
                            ? null
                            : () => _do(
                                () => d.setJobPaused(_id, paused: _enabled),
                                _enabled ? ngL.ng_paused : ngL.ng_resumed,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          NgSectionLabel(ngL.ng_prompt),
          NgCard(
            child: SelectableText(
              _job['prompt']?.toString() ?? '',
              style: NgType.bodySmall.copyWith(color: c.text),
            ),
          ),
          NgSectionLabel(ngL.ng_runs),
          if (runs == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (runs.isEmpty)
            Text(
              ngL.ng_no_runs_yet,
              style: NgType.bodySmall.copyWith(color: c.text3),
            )
          else
            NgCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final run in runs)
                    NgRow(
                      icon: Icons.chat_bubble_outline,
                      title: ngSessionTitle(run),
                      subtitle: ngWhen(ngSessionTime(run)),
                      onTap: () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        widget.onOpenSession(run);
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NewJobSheet extends StatefulWidget {
  const _NewJobSheet({required this.scope});
  final NgScope scope;

  @override
  State<_NewJobSheet> createState() => _NewJobSheetState();
}

class _NewJobSheetState extends State<_NewJobSheet> {
  final _name = TextEditingController();
  final _schedule = TextEditingController();
  final _prompt = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _schedule.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_schedule.text.trim().isEmpty || _prompt.text.trim().isEmpty) {
      setState(() => _error = ngL.ng_enter_a_schedule_and_a_prompt);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.scope.gateway.dashboard.createJob(
        prompt: _prompt.text.trim(),
        schedule: _schedule.text.trim(),
        name: _name.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ngL.ng_new_job, style: NgType.title.copyWith(color: c.text)),
            const SizedBox(height: 16),
            NgField(controller: _name, label: ngL.ng_name_optional),
            const SizedBox(height: 12),
            NgField(
              controller: _schedule,
              label: ngL.ng_schedule,
              hint: ngL.ng_every_1h_0_9_or_30m,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prompt,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: ngL.ng_prompt,
                filled: true,
                fillColor: c.input,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NgRadii.md),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: NgType.bodySmall.copyWith(color: c.danger)),
            ],
            const SizedBox(height: 18),
            NgPrimaryButton(
              label: ngL.ng_create,
              busy: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
