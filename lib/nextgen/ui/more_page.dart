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
import '../nextgen_l10n.dart';

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
      title: ngL.ng_more,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          NgSectionLabel(ngL.ng_chats),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                NgRow(
                  icon: Icons.archive_outlined,
                  title: ngL.ng_archived_chats,
                  onTap: () =>
                      push(NgArchivedPage(onOpenSession: onOpenSession)),
                ),
                NgRow(
                  icon: Icons.folder_outlined,
                  title: ngL.ng_projects,
                  subtitle: ngL.ng_chats_grouped_by_project_and_workspace,
                  onTap: () => push(ProjectsRootScreen(connection: conn)),
                ),
              ],
            ),
          ),
          NgSectionLabel(ngL.ng_agent),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                NgRow(
                  icon: Icons.memory,
                  title: ngL.ng_memory,
                  subtitle: ngL.ng_what_hermes_remembers_about_you,
                  onTap: () => push(MemoryScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.auto_fix_high_outlined,
                  title: ngL.ng_skills_library,
                  subtitle: ngL.ng_browse_and_read_installed_skills,
                  onTap: () => push(SkillsScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.event_repeat,
                  title: ngL.ng_cron_editor,
                  subtitle: ngL.ng_edit_schedules_prompts_and_delivery,
                  onTap: () => push(CronScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.code,
                  title: ngL.ng_config_file,
                  subtitle: ngL.ng_edit_config_yaml_on_the_gateway,
                  onTap: () => push(const NgConfigPage()),
                ),
              ],
            ),
          ),
          NgSectionLabel(ngL.ng_models_and_providers),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                NgRow(
                  icon: Icons.tune,
                  title: ngL.ng_model_management,
                  subtitle: ngL.ng_default_fallback_and_auxiliary_models,
                  onTap: () => push(ModelManagementScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.key_outlined,
                  title: ngL.ng_provider_sign_in,
                  subtitle: ngL.ng_connect_provider_accounts_with_oauth,
                  onTap: () => push(ProviderOAuthScreen(connection: conn)),
                ),
                NgRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: ngL.ng_nous_portal,
                  subtitle: ngL.ng_subscription_credits_and_usage,
                  onTap: () => push(NousPortalScreen(connection: conn)),
                ),
              ],
            ),
          ),
          NgSectionLabel(ngL.ng_interface),
          NgCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: NgRow(
              icon: Icons.history_toggle_off,
              title: ngL.ng_switch_to_the_classic_interface,
              subtitle: ngL.ng_turns_nextgen_off_you_can_turn,
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
      ngToast(context, ngL.ng_restored);
    } catch (e) {
      if (mounted) ngToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final rows = _sessions;
    return NgPage(
      title: ngL.ng_archived,
      body: _error != null
          ? NgEmpty(
              icon: Icons.cloud_off,
              title: ngL.ng_couldn_t_load_archived_chats,
              body: _error,
            )
          : rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? NgEmpty(
              icon: Icons.archive_outlined,
              title: ngL.ng_nothing_archived,
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
                      ngL.ng_restore,
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
      if (mounted) ngToast(context, ngL.ng_saved_new_chats_use_it);
    } catch (e) {
      if (mounted) ngToast(context, ngL.ng_couldn_t_save(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return NgPage(
      title: ngL.ng_config_file,
      actions: [
        TextButton(
          onPressed: _loading || _saving || _error != null ? null : _save,
          child: Text(_saving ? ngL.ng_saving : ngL.ng_save),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? NgEmpty(
              icon: Icons.code_off,
              title: ngL.ng_couldn_t_load,
              body: _error,
            )
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
