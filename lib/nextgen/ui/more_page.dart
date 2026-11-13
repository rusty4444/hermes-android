// "More": archived chats, the raw config editor and every classic Hermes
// Android feature Kyllene doesn't have (memory, projects, model management,
// provider sign-in, Nous Portal, the full cron editor...), opened in place.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models/session.dart';
import '../../core/screens/cron_screen.dart';
import '../../core/screens/memory_screen.dart';
import '../../core/screens/model_management_screen.dart';
import '../../core/screens/nous_portal_screen.dart';
import '../../core/screens/projects_root_screen.dart';
import '../../core/screens/provider_oauth_screen.dart';
import '../../core/screens/skills_screen.dart';
import '../../core/services/dashboard_api_client.dart';
import '../nextgen_preferences.dart';
import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'scheduled_page.dart';
import 'sessions_sidebar.dart';
import 'widgets.dart';

class NgMorePage extends StatelessWidget {
  const NgMorePage({super.key, required this.onOpenSession});
  final ValueChanged<Session> onOpenSession;

  @override
  Widget build(BuildContext context) {
    final scope = NgScope.of(context);
    final conn = scope.connection;
    void push(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    return NgPage(
      title: 'More',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const NgSectionLabel('Chats'),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                NgRow(
                  icon: Icons.archive_outlined,
                  title: 'Archived chats',
                  onTap: () =>
                      push(NgArchivedPage(onOpenSession: onOpenSession)),
                ),
                NgRow(
                  icon: Icons.folder_outlined,
                  title: 'Projects',
                  subtitle: 'Chats grouped by project and workspace',
                  onTap: () => push(ProjectsRootScreen(connection: conn)),
                ),
              ],
            ),
          ),
          const NgSectionLabel('Agent'),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                NgRow(
                  icon: Icons.memory,
                  title: 'Memory',
                  subtitle: 'What Hermes remembers about you',
                  onTap: () => push(MemoryScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'Skills library',
                  subtitle: 'Browse and read installed skills',
                  onTap: () => push(SkillsScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.event_repeat,
                  title: 'Cron editor',
                  subtitle: 'Edit schedules, prompts and delivery',
                  onTap: () => push(CronScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.code,
                  title: 'Config file',
                  subtitle: 'Edit config.yaml on the gateway',
                  onTap: () => push(const NgConfigPage()),
                ),
              ],
            ),
          ),
          const NgSectionLabel('Models and providers'),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                NgRow(
                  icon: Icons.tune,
                  title: 'Model management',
                  subtitle: 'Default, fallback and auxiliary models',
                  onTap: () => push(ModelManagementScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.key_outlined,
                  title: 'Provider sign-in',
                  subtitle: 'Connect provider accounts with OAuth',
                  onTap: () => push(ProviderOAuthScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Nous Portal',
                  subtitle: 'Subscription, credits and usage',
                  onTap: () => push(NousPortalScreen(connection: conn)),
                ),
              ],
            ),
          ),
          const NgSectionLabel('Interface'),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: NgRow(
              icon: Icons.history_toggle_off,
              title: 'Switch to the classic interface',
              subtitle:
                  'Turns NextGen off. You can turn it back on in Settings.',
              onTap: () => NextGenPreferences.setEnabled(scope.prefs, false),
            ),
          ),
        ],
      ),
    );
  }
}

class NgArchivedPage extends StatefulWidget {
  const NgArchivedPage({super.key, required this.onOpenSession});
  final ValueChanged<Session> onOpenSession;

  @override
  State<NgArchivedPage> createState() => _NgArchivedPageState();
}

class _NgArchivedPageState extends State<NgArchivedPage> {
  List<Session>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final g = NgScope.of(context).gateway;
    try {
      final rows = await g.dashboard.getArchivedSessions(
        maxPages: 5,
        gatewayProfile: g.profile,
      );
      if (mounted) setState(() => _sessions = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _restore(Session s) async {
    try {
      await NgScope.of(
        context,
      ).gateway.api.setSessionArchived(sessionId: s.id, archived: false);
      if (!mounted) return;
      setState(() => _sessions?.removeWhere((x) => x.id == s.id));
      ngToast(context, 'Restored');
    } catch (e) {
      if (mounted) ngToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final rows = _sessions;
    return NgPage(
      title: 'Archived',
      body: _error != null
          ? NgEmpty(
              icon: Icons.cloud_off,
              title: 'Couldn\'t load archived chats',
              body: _error,
            )
          : rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? const NgEmpty(
              icon: Icons.archive_outlined,
              title: 'Nothing archived',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final s = rows[i];
                return NgRow(
                  icon: Icons.chat_bubble_outline,
                  title: ngSessionTitle(s),
                  subtitle: ngWhen(ngSessionTime(s)),
                  trailing: TextButton(
                    onPressed: () => _restore(s),
                    child: Text(
                      'Restore',
                      style: TextStyle(color: c.accentText),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    widget.onOpenSession(s);
                  },
                );
              },
            ),
    );
  }
}

class NgConfigPage extends StatefulWidget {
  const NgConfigPage({super.key});

  @override
  State<NgConfigPage> createState() => _NgConfigPageState();
}

class _NgConfigPageState extends State<NgConfigPage> {
  final _text = TextEditingController();
  String? _path;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  String _original = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Map<String, String>? _query() {
    final p = NgScope.of(context).gateway.profile;
    return p == null ? null : {'profile': p};
  }

  Future<void> _load() async {
    try {
      final res = await NgScope.of(context).gateway.dashboard.apiRequest(
        'GET',
        'config/raw',
        queryParameters: _query(),
      );
      if (res.statusCode != 200) {
        throw DashboardRequestException(
          res.statusCode,
          dashboardErrorMessage(res),
        );
      }
      final data = jsonDecode(res.body) as Map;
      _original = '${data['yaml'] ?? ''}';
      _text.text = _original;
      _path = data['path']?.toString();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final res = await NgScope.of(context).gateway.dashboard.apiRequest(
        'PUT',
        'config/raw',
        queryParameters: _query(),
        body: {'yaml_text': _text.text},
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw DashboardRequestException(
          res.statusCode,
          dashboardErrorMessage(res),
        );
      }
      _original = _text.text;
      if (mounted) ngToast(context, 'Saved. New chats use it.');
    } catch (e) {
      if (mounted) ngToast(context, 'Couldn\'t save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return NgPage(
      title: 'Config file',
      actions: [
        TextButton(
          onPressed: _loading || _saving || _error != null ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? NgEmpty(icon: Icons.code_off, title: 'Couldn\'t load', body: _error)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_path != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _path!,
                      style: NgType.caption.copyWith(color: c.text3),
                    ),
                  ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    decoration: BoxDecoration(
                      color: c.well,
                      borderRadius: BorderRadius.circular(NgRadii.md),
                      border: Border.all(color: c.stroke),
                    ),
                    child: TextField(
                      controller: _text,
                      expands: true,
                      maxLines: null,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.multiline,
                      style: NgType.code.copyWith(color: c.text),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
