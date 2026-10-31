// Cron job browser — list and manage Hermes scheduled cron jobs.
//
// API: GET /api/cron/jobs — returns JSON array of job objects
//      POST /api/cron/jobs/{id}/pause | resume | trigger
//      DELETE /api/cron/jobs/{id}
//      POST /api/cron/jobs — create new job
//      PUT /api/cron/jobs/{id} — update existing job
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connection_manager.dart';
import '../services/gateway_turn_application_controller.dart';
import '../theme/hermes_theme.dart';
import '../widgets/hermes_components.dart';
import '../utils/relative_time.dart';
import 'chat_screen.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class CronScreen extends StatefulWidget {
  final SavedConnection connection;

  /// Threaded to run-transcript chats so follow-up sends there earn the
  /// turn-bounded keep-alive like every other route (a cron run is an
  /// ordinary session; its sends go through the stock transport).
  final GatewayTurnApplicationController? turnApplicationController;
  const CronScreen({
    required this.connection,
    this.turnApplicationController,
    super.key,
  });

  @override
  State<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends State<CronScreen> {
  late DashboardClient _client;
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String? _error;

  /// Desktop-parity run drill-down: expanding a job loads its run sessions
  /// (`GET /api/cron/jobs/{id}/runs`) and each run opens as a resumable
  /// chat transcript. The chat list no longer shows cron rows, so this is
  /// the home for cron output on mobile.
  final Set<String> _expandedJobs = {};
  final Map<String, List<Session>> _runsByJob = {};
  final Set<String> _runsLoading = {};
  final Map<String, String> _runsErrorByJob = {};

  @override
  void initState() {
    super.initState();
    _client = DashboardClient(
      host: widget.connection.host,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? "",
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
      gatewayProfile: widget.connection.gatewayProfile,
      clientCertificate: widget.connection.clientCertificate,
    );
    _loadJobs();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _client.getCronJobs();

      if (!mounted) return;
      setState(() {
        _jobs = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _isPaused(Map<String, dynamic> job) {
    return job['paused_at'] != null ||
        job['state'] == 'paused' ||
        job['enabled'] == false;
  }

  String _scheduleDisplay(Map<String, dynamic> job) {
    final display = job['schedule_display'] as String?;
    if (display != null && display.isNotEmpty) return display;

    final schedule = job['schedule'];
    if (schedule is String) return schedule;
    if (schedule is Map) {
      return schedule['display'] as String? ??
          schedule['run_at'] as String? ??
          schedule.toString();
    }
    return '';
  }

  String _jobName(Map<String, dynamic> job) {
    return job['name'] as String? ?? job['id'] as String? ?? 'Untitled';
  }

  String _jobPrompt(Map<String, dynamic> job) {
    final prompt = job['prompt'] as String? ?? '';
    if (prompt.length > 120) return '${prompt.substring(0, 120)}…';
    return prompt;
  }

  Future<void> _togglePause(Map<String, dynamic> job) async {
    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;
    final paused = _isPaused(job);

    try {
      await _client.setJobPaused(jobId, paused: !paused);
      if (paused) {
        job.remove('paused_at');
        job['state'] = 'active';
        job['enabled'] = true;
      } else {
        job['paused_at'] = DateTime.now().toIso8601String();
        job['state'] = 'paused';
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              paused ? context.l10n.job_resumed : context.l10n.job_paused,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          hermesStatusSnackBar(
            context,
            message: context.l10n.failed(e),
            status: HermesStatus.failed,
          ),
        );
      }
    }
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;
    final name = _jobName(job);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.delete_cron_job),
        content: Text(context.l10n.delete_2(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: HermesTokens.of(ctx).danger,
              foregroundColor: foregroundFor(HermesTokens.of(ctx).danger),
            ),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _client.deleteJob(jobId);
      if (mounted) {
        setState(() => _jobs.removeWhere((j) => j['id'] == jobId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.deleted(name))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          hermesStatusSnackBar(
            context,
            message: context.l10n.delete_failed(e),
            status: HermesStatus.failed,
          ),
        );
      }
    }
  }

  Future<void> _triggerJob(Map<String, dynamic> job) async {
    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;
    try {
      await _client.triggerJob(jobId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.job_triggered)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          hermesStatusSnackBar(
            context,
            message: context.l10n.failed(e),
            status: HermesStatus.failed,
          ),
        );
      }
    }
  }

  void _toggleRuns(String jobId) {
    if (jobId.isEmpty) return;
    setState(() {
      if (_expandedJobs.remove(jobId)) {
        _runsErrorByJob.remove(jobId);
      } else {
        _expandedJobs.add(jobId);
      }
    });
    if (_expandedJobs.contains(jobId)) unawaited(_loadRuns(jobId));
  }

  Future<void> _loadRuns(String jobId) async {
    if (_runsLoading.contains(jobId)) return;
    setState(() {
      _runsLoading.add(jobId);
      _runsErrorByJob.remove(jobId);
    });
    try {
      final runs = await _client.getCronJobRuns(jobId);
      if (!mounted) return;
      setState(() {
        _runsByJob[jobId] = runs;
        _runsLoading.remove(jobId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runsLoading.remove(jobId);
        _runsErrorByJob[jobId] = e.toString();
      });
    }
  }

  /// Opens one cron run's transcript. A run is an ordinary session row
  /// (`cron_{job_id}_{timestamp}`), so the regular ChatScreen resume path
  /// shows the full transcript — same as the desktop's run-pill click.
  void _openRun(Session run) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          connection: widget.connection,
          session: run,
          turnApplicationController: widget.turnApplicationController,
        ),
      ),
    );
  }

  Widget _buildRunsSection(String jobId) {
    final tokens = HermesTokens.of(context);
    if (_runsLoading.contains(jobId)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final error = _runsErrorByJob[jobId];
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: tokens.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.couldn_t_load_runs(error),
                style: TextStyle(fontSize: 12, color: tokens.warning),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_loadRuns(jobId)),
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
    }
    final runs = _runsByJob[jobId] ?? const <Session>[];
    if (runs.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          context.l10n.no_runs_yet,
          style: TextStyle(fontSize: 12, color: tokens.muted),
        ),
      );
    }
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final run in runs)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 24, right: 8),
            leading: Icon(
              run.isActive
                  ? Icons.play_circle_outline
                  : Icons.check_circle_outline,
              size: 18,
              color: run.isActive ? tokens.running : tokens.success,
            ),
            title: Text(
              run.title.isEmpty ? context.l10n.cron_run : run.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: run.preview.isEmpty
                ? null
                : Text(
                    run.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: tokens.muted),
                  ),
            trailing: Text(
              formatRelativeTime(now, run.lastActive),
              style: TextStyle(fontSize: 11, color: tokens.muted),
            ),
            onTap: () => _openRun(run),
          ),
      ],
    );
  }

  Future<void> _showAddJobDialog() async {
    final result = await _showJobDialog(
      title: context.l10n.add_cron_job,
      actionLabel: context.l10n.add,
    );
    if (result == null || !mounted) return;

    try {
      final created = await _client.createJob(
        name: result['name']?.toString() ?? '',
        prompt: result['prompt']?.toString() ?? '',
        schedule: result['schedule']?.toString() ?? '',
      );
      if (result['no_agent'] == true) {
        final jobId =
            created['id']?.toString() ?? created['job_id']?.toString() ?? '';
        if (jobId.isNotEmpty) {
          await _client.updateJob(jobId, {'no_agent': true});
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.cron_job_added)));
      await _loadJobs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          hermesStatusSnackBar(
            context,
            message: context.l10n.failed_to_add_job(e),
            status: HermesStatus.failed,
          ),
        );
      }
    }
  }

  Future<void> _showEditJobDialog(Map<String, dynamic> job) async {
    final result = await _showJobDialog(
      title: context.l10n.edit_cron_job,
      actionLabel: context.l10n.save,
      initialName: _jobName(job),
      initialPrompt: job['prompt'] as String? ?? '',
      initialSchedule: _scheduleDisplay(job),
      initialNoAgent: job['no_agent'] == true,
    );
    if (result == null || !mounted) return;

    final jobId = job['id'] as String? ?? '';
    if (jobId.isEmpty) return;

    try {
      await _client.updateJob(jobId, result);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.cron_job_updated)));
      await _loadJobs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          hermesStatusSnackBar(
            context,
            message: context.l10n.failed_to_update_job(e),
            status: HermesStatus.failed,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showJobDialog({
    required String title,
    required String actionLabel,
    String initialName = '',
    String initialPrompt = '',
    String initialSchedule = '',
    bool initialNoAgent = false,
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final promptCtrl = TextEditingController(text: initialPrompt);
    final scheduleCtrl = TextEditingController(text: initialSchedule);
    var noAgent = initialNoAgent;

    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.name,
                      hintText: context.l10n.e_g_daily_backup,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: promptCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.prompt,
                      hintText: context.l10n.what_should_the_agent_do,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: scheduleCtrl,
                    decoration: InputDecoration(
                      labelText: context.l10n.schedule,
                      hintText: context.l10n.e_g_0_9_or_every_2h,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: noAgent,
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.script_only_no_agent),
                    subtitle: Text(
                      context.l10n.use_for_cron_jobs_backed_by_scripts,
                    ),
                    onChanged: (value) => setDialogState(() => noAgent = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final prompt = promptCtrl.text.trim();
                  final schedule = scheduleCtrl.text.trim();

                  if (name.isEmpty || prompt.isEmpty || schedule.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.l10n.name_prompt_and_schedule_are_required,
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(ctx, {
                    'name': name,
                    'prompt': prompt,
                    'schedule': schedule,
                    'no_agent': noAgent,
                  });
                },
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
    } finally {
      nameCtrl.dispose();
      promptCtrl.dispose();
      scheduleCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.cron_jobs),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadJobs,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        tooltip: context.l10n.add_new_cron_job,
        onPressed: _loading ? null : _showAddJobDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    final tokens = HermesTokens.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: tokens.warning),
              const SizedBox(height: 16),
              Text(
                context.l10n.failed_to_load_cron_jobs,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadJobs,
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 48, color: tokens.muted),
            const SizedBox(height: 16),
            Text(
              context.l10n.no_cron_jobs,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadJobs,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _jobs.length,
        itemBuilder: (context, index) {
          final job = _jobs[index];
          final name = _jobName(job);
          final prompt = _jobPrompt(job);
          final schedule = _scheduleDisplay(job);
          final paused = _isPaused(job);
          final lastRun = job['last_run_at'] as String?;
          final nextRun = job['next_run_at'] as String?;
          final isNoAgent = job['no_agent'] == true;
          final jobId = job['id'] as String? ?? '';
          final expanded = _expandedJobs.contains(jobId);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              // Tap expands the run drill-down (desktop parity: cron output
              // lives under the job, not in the chat list). Editing stays
              // available from the overflow menu.
              onTap: () => _toggleRuns(jobId),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          paused ? Icons.pause_circle : Icons.play_circle,
                          color: paused ? tokens.warning : tokens.success,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: tokens.muted,
                        ),
                        if (isNoAgent)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: tokens.accentContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'script',
                              style: TextStyle(
                                fontSize: 10,
                                color: tokens.onAccentContainer,
                              ),
                            ),
                          ),
                        PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'trigger') _triggerJob(job);
                            if (action == 'edit') _showEditJobDialog(job);
                            if (action == 'toggle') _togglePause(job);
                            if (action == 'delete') _deleteJob(job);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'trigger',
                              child: Row(
                                children: [
                                  Icon(Icons.play_arrow, size: 18),
                                  SizedBox(width: 8),
                                  Text(context.l10n.trigger_now),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text(context.l10n.edit),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Row(
                                children: [
                                  Icon(
                                    paused ? Icons.play_arrow : Icons.pause,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(paused ? 'Resume' : 'Pause'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: tokens.danger,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    context.l10n.delete,
                                    style: TextStyle(color: tokens.danger),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (prompt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        prompt,
                        style: TextStyle(fontSize: 12, color: tokens.muted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (schedule.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 14, color: tokens.muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              schedule,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: tokens.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (lastRun != null && lastRun.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.last(lastRun),
                        style: TextStyle(fontSize: 11, color: tokens.muted),
                      ),
                    ],
                    if (nextRun != null && nextRun.isNotEmpty)
                      Text(
                        context.l10n.next(nextRun),
                        style: TextStyle(fontSize: 11, color: tokens.muted),
                      ),
                    if (expanded) ...[
                      const Divider(height: 16),
                      _buildRunsSection(jobId),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
