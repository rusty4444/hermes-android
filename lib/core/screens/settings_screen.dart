// Device settings, appearance, connection information and app info.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_licenses.dart';
import 'provider_oauth_screen.dart';
import '../services/config_backup_io.dart';
import '../services/config_backup_service.dart';
import '../services/connection_manager.dart';
import '../services/hands_free_preference.dart';
import '../services/notification_prefs.dart';
import '../widgets/background_work_settings.dart';
import '../services/turn_notification_service.dart';
import '../widgets/config_backup_card.dart';
import '../widgets/mobile_push_settings.dart';
import '../widgets/chat_density_settings_card.dart';
import '../widgets/text_size_settings_card.dart';
import '../widgets/theme_palette_picker.dart';
import '../theme/hermes_theme.dart';
import '../../main.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/app_update_service.dart';
import '../widgets/update_available_dialog.dart';

import 'package:hermes_android/core/l10n/l10n.dart';

class SettingsScreen extends StatefulWidget {
  final SavedConnection connection;
  final DashboardClient? dashboardClient;
  const SettingsScreen({
    required this.connection,
    this.dashboardClient,
    super.key,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.settings)),
    body: _buildBody(),
  );

  Widget _buildChatDensityCard() => ChatDensitySettingsCard(
    preferences: context
        .findAncestorStateOfType<HermesAppState>()!
        .widget
        .connManager
        .prefs,
  );

  Widget _buildBody() {
    final app = context.findAncestorStateOfType<HermesAppState>()!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.login),
          title: Text(context.l10n.provider_oauth_title),
          subtitle: Text(context.l10n.provider_oauth_settings_subtitle),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ProviderOAuthScreen(connection: widget.connection),
            ),
          ),
        ),
        // ---- Section: Theme ----
        _buildSectionHeader(context.l10n.appearance),
        ThemeAppearanceSettings(
          preferences: app.widget.connManager.prefs,
          onChanged: app.refreshAppearancePreferences,
        ),
        const SizedBox(height: 8),
        TextSizeSettingsCard(
          preferences: context
              .findAncestorStateOfType<HermesAppState>()!
              .widget
              .connManager
              .prefs,
          onChanged: (preference) => context
              .findAncestorStateOfType<HermesAppState>()!
              .setTextSizePreference(preference),
        ),
        const SizedBox(height: 8),
        _buildChatDensityCard(),
        const SizedBox(height: 8),
        _VerboseToggle(),
        const SizedBox(height: 16),

        // ---- Section: Notifications ----
        _buildSectionHeader(context.l10n.notifications),
        const _NotificationSettings(),
        MobilePushSettings(
          connection: widget.connection,
          connectionManager: context
              .findAncestorStateOfType<HermesAppState>()!
              .widget
              .connManager,
        ),
        const SizedBox(height: 16),
        _buildSectionHeader(context.l10n.background_work),
        const BackgroundWorkSettings(),
        const SizedBox(height: 16),

        // ---- Section: Voice ----
        _buildSectionHeader(context.l10n.voice),
        _VoicePicker(),
        const SizedBox(height: 8),
        const _HandsFreeToggle(),
        const SizedBox(height: 16),

        // ---- Section: Session Sources ----
        _buildSectionHeader(context.l10n.session_sources),
        _SessionSourcesFilter(connectionId: widget.connection.id),
        const SizedBox(height: 16),

        // ---- Section: Connection ----
        _buildSectionHeader(context.l10n.connection_section),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(context.l10n.label, widget.connection.label),
                const SizedBox(height: 4),
                _infoRow(context.l10n.host, widget.connection.host),
                const SizedBox(height: 4),
                _infoRow(context.l10n.port, '${widget.connection.port}'),
                const SizedBox(height: 4),
                _infoRow(context.l10n.base_url, widget.connection.baseUrl),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---- Section: Backup ----
        _buildSectionHeader(context.l10n.backup_restore),
        ConfigBackupCard(
          onExport: _exportConfig,
          onDeliverExport: _deliverExport,
          onPickBackupFile: _pickBackupFile,
          onImport: _importConfig,
        ),
        const SizedBox(height: 16),

        // ---- Section: About ----
        _buildSectionHeader(context.l10n.about),
        _AboutCard(),
      ],
    );
  }

  ConfigBackupIo _backupIo() {
    final app = context.findAncestorStateOfType<HermesAppState>()!;
    return ConfigBackupIo(connectionManager: app.widget.connManager);
  }

  Future<String> _exportConfig(String passphrase) {
    return _backupIo().exportEncrypted(passphrase);
  }

  Future<String?> _deliverExport(String contents) {
    return _backupIo().deliverExport(contents);
  }

  Future<String?> _pickBackupFile() {
    return _backupIo().pickBackupFile();
  }

  Future<ConfigImportResult> _importConfig(
    String contents,
    String passphrase,
    ConfigImportMode mode,
  ) async {
    final result = await _backupIo().importEncrypted(
      contents,
      passphrase,
      mode,
    );
    if (mounted) {
      // Re-read palette, brightness and text size without replacing any routes.
      context
          .findAncestorStateOfType<HermesAppState>()
          ?.refreshAppearancePreferences();
    }
    return result;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: HermesTokens.of(context).muted,
            ),
          ),
        ),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// About card that reads the real version from package_info_plus.
class _AboutCard extends StatefulWidget {
  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  String _version = '';
  bool _checking = false;
  bool _checkOnLaunch = true;
  String? _updateStatus;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadUpdatePreference();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'unknown');
    }
  }

  Future<void> _loadUpdatePreference() async {
    final enabled = await AppUpdateService().checkOnLaunchEnabled();
    if (!mounted) return;
    setState(() => _checkOnLaunch = enabled);
  }

  Future<void> _setCheckOnLaunch(bool enabled) async {
    setState(() => _checkOnLaunch = enabled);
    await AppUpdateService().setCheckOnLaunchEnabled(enabled);
  }

  /// The manual path: always a real check, and always an answer — the
  /// launch-time prompt is the one that stays quiet when GitHub cannot be
  /// reached, because there the user did not ask.
  Future<void> _checkForUpdates() async {
    setState(() {
      _checking = true;
      _updateStatus = null;
    });
    final service = AppUpdateService();
    AppUpdateResult result;
    try {
      final current = await installedAppVersion() ?? _version;
      result = await service.checkForUpdate(
        currentVersion: current,
        force: true,
      );
    } catch (_) {
      result = const AppUpdateResult(AppUpdateOutcome.failed);
    }
    if (!mounted) return;
    setState(() => _checking = false);
    final l10n = context.l10n;
    switch (result.outcome) {
      case AppUpdateOutcome.updateAvailable:
        final release = result.release!;
        final action = await showUpdateAvailableDialog(
          context,
          release: release,
        );
        if (action == UpdatePromptAction.skipVersion) {
          await service.skipVersion(release.version);
        }
      case AppUpdateOutcome.upToDate:
        setState(() => _updateStatus = l10n.you_re_on_the_latest_version);
      case AppUpdateOutcome.throttled:
      case AppUpdateOutcome.failed:
        setState(() => _updateStatus = l10n.couldn_t_check_for_updates);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.hermes_agent_for_android,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.version_label(_version.isNotEmpty ? _version : '…'),
            ),
            const SizedBox(height: 8),
            Text(
              context
                  .l10n
                  .browse_and_manage_your_hermes_agent_sessions_from_your_phone,
              style: TextStyle(color: HermesTokens.of(context).muted),
            ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(MaterialLocalizations.of(context).licensesPageTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                registerAppLicenses();
                showLicensePage(
                  context: context,
                  applicationName: context.l10n.hermes_agent_for_android,
                  applicationVersion: _version,
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.check_for_updates),
              subtitle: _updateStatus == null ? null : Text(_updateStatus!),
              trailing: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onTap: _checking ? null : _checkForUpdates,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.check_for_updates_on_launch),
              value: _checkOnLaunch,
              onChanged: _setCheckOnLaunch,
            ),
          ],
        ),
      ),
    );
  }
}

/// Toggle for verbose mode — shows tool calls, thinking, and message metadata in chat.
class _VerboseToggle extends StatefulWidget {
  @override
  State<_VerboseToggle> createState() => _VerboseToggleState();
}

class _VerboseToggleState extends State<_VerboseToggle> {
  bool _verbose = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _verbose = prefs.getBool('verbose_mode') ?? false);
  }

  Future<void> _set(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('verbose_mode', value);
    setState(() => _verbose = value);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: Text(context.l10n.verbose_mode),
        subtitle: Text(
          context.l10n.show_tool_calls_thinking_and_message_metadata,
        ),
        secondary: const Icon(Icons.terminal),
        value: _verbose,
        onChanged: _set,
      ),
    );
  }
}

class _HandsFreeToggle extends StatelessWidget {
  const _HandsFreeToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: handsFreeEnabled,
      builder: (context, enabled, _) => Card(
        child: SwitchListTile(
          secondary: const Icon(Icons.record_voice_over_outlined),
          title: Text(context.l10n.hands_free_settings_title),
          subtitle: Text(context.l10n.hands_free_settings_subtitle),
          value: enabled,
          onChanged: (on) => unawaited(HandsFreePreferenceStore.setEnabled(on)),
        ),
      ),
    );
  }
}

class _VoicePicker extends StatefulWidget {
  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  final FlutterTts _tts = FlutterTts();
  final List<Map<String, String>> _voices = [];
  String? _selectedVoiceName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedVoiceName = prefs.getString('voice_name');

    try {
      final raw = await _tts.getVoices;
      if (raw is List && raw.isNotEmpty) {
        for (final item in raw) {
          if (item is Map) {
            final m = <String, String>{};
            m['name'] = (item['name'] ?? '').toString();
            m['locale'] = (item['locale'] ?? '').toString();
            if (m['name']!.isNotEmpty) _voices.add(m);
          }
        }
      }
    } catch (_) {}

    if (_voices.isEmpty) {
      try {
        final raw = await _tts.getLanguages;
        final seen = <String>{};
        if (raw is List) {
          for (final item in raw) {
            final lang = item.toString();
            if (lang.isNotEmpty && seen.add(lang)) {
              _voices.add({'name': lang, 'locale': lang});
            }
          }
        }
      } catch (_) {}
    }

    _voices.sort((a, b) => (a['locale'] ?? '').compareTo(b['locale'] ?? ''));

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _set(Map<String, String>? voice) async {
    final prefs = await SharedPreferences.getInstance();
    if (voice == null) {
      await prefs.remove('voice_name');
      await prefs.remove('voice_locale');
      // Check immediately before setState: the awaits above can outlive the
      // widget, and a mounted check before them does not cover the gap.
      if (!mounted) return;
      setState(() => _selectedVoiceName = null);
    } else {
      final name = voice['name'] ?? '';
      final locale = voice['locale'] ?? '';
      await prefs.setString('voice_name', name);
      await prefs.setString('voice_locale', locale);
      if (!mounted) return;
      setState(() => _selectedVoiceName = name);
    }
  }

  String _voiceLabel(Map<String, String> voice) {
    final name = voice['name'] ?? '';
    final locale = voice['locale'] ?? '';
    if (name == locale) return locale;
    final gender = name.contains('male')
        ? '(male)'
        : name.contains('female')
        ? '(female)'
        : '';
    return '$locale $gender  [$name]';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_voices.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            context.l10n.no_tts_voices_found_ninstall_google_text_to_speech_and,
            style: TextStyle(color: HermesTokens.of(context).muted),
          ),
        ),
      );
    }

    final items = <DropdownMenuItem<Map<String, String>?>>[
      DropdownMenuItem(
        value: null,
        child: Text(context.l10n.auto_device_default),
      ),
      ..._voices.map(
        (v) => DropdownMenuItem(
          value: v,
          child: Text(
            _voiceLabel(v),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];

    final current = _selectedVoiceName != null
        ? _voices.where((v) => v['name'] == _selectedVoiceName).firstOrNull
        : null;

    return DropdownButtonFormField<Map<String, String>?>(
      initialValue: current,
      decoration: InputDecoration(
        labelText: context.l10n.voice,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items,
      onChanged: _set,
    );
  }
}

/// Checkbox list of session sources. Unchecked sources are filtered
/// client-side from the fetched session list by `Session.source`.
class _SessionSourcesFilter extends StatefulWidget {
  final String connectionId;
  const _SessionSourcesFilter({required this.connectionId});

  @override
  State<_SessionSourcesFilter> createState() => _SessionSourcesFilterState();
}

class _SessionSourcesFilterState extends State<_SessionSourcesFilter> {
  /// Known session source types. Hermes Gateway persists `session.source` for
  /// every session. Sources not in this list are always shown (whitelisted).
  Map<String, String> get _knownSources => {
    'acp': context.l10n.autonomous_agents,
    'api_server': context.l10n.external_api_clients,
    'cli': context.l10n.command_line_chats,
    'cron': context.l10n.scheduled_tasks,
    'desktop': context.l10n.desktop_app,
    'discord': context.l10n.discord_chats,
    'gateway': context.l10n.gateway_api_access,
    'mobile': context.l10n.phone_or_tablet,
    'signal': context.l10n.signal_messages,
    'slack': context.l10n.slack_chats,
    'telegram': context.l10n.telegram_messages,
    'tool': context.l10n.developer_tool_calls,
    'tui': context.l10n.terminal_sessions,
    'whatsapp': context.l10n.whatsapp_messages,
  };

  Set<String> _excluded = {};

  String get _prefsKey => 'excluded_session_sources_${widget.connectionId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _excluded = prefs.getStringList(_prefsKey)?.toSet() ?? {};
    });
  }

  Future<void> _toggle(String source, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (enabled) {
        _excluded.remove(source);
      } else {
        _excluded.add(source);
      }
    });
    await prefs.setStringList(_prefsKey, _excluded.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: _knownSources.entries.map((entry) {
          final source = entry.key;
          final label = entry.value;
          final isVisible = !_excluded.contains(source);
          return CheckboxListTile(
            title: Text(label),
            subtitle: Text(
              source,
              style: TextStyle(
                fontSize: 12,
                color: HermesTokens.of(context).muted,
              ),
            ),
            value: isVisible,
            onChanged: (val) => _toggle(source, val ?? true),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          );
        }).toList(),
      ),
    );
  }
}

/// Desktop-parity notification settings: one master switch, a toggle per kind,
/// and the same "send test" affordance so a silent OS-level block is visible
/// instead of looking like a dead feature.
class _NotificationSettings extends StatefulWidget {
  const _NotificationSettings();

  @override
  State<_NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<_NotificationSettings>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission(requestPermission: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  void _refreshPermission({bool requestPermission = false}) {
    // Keep the visible hint in sync after returning from OS Settings without
    // asking again. Only the initial foreground visit may request permission.
    unawaited(
      TurnNotificationService.shared
          .ensureInitialized(requestPermission: requestPermission)
          .then((_) {
            if (mounted) setState(() {});
          }),
    );
  }

  static String _kindLabel(BuildContext context, HermesNotificationKind kind) =>
      switch (kind) {
        HermesNotificationKind.approval => context.l10n.approval_needed,
        HermesNotificationKind.input => context.l10n.input_needed,
        HermesNotificationKind.turnDone => context.l10n.response_complete,
        HermesNotificationKind.turnError => context.l10n.turn_failed,
        HermesNotificationKind.backgroundDone =>
          context.l10n.background_task_completed,
        HermesNotificationKind.credits => context.l10n.credit_notifications,
        HermesNotificationKind.plugin => context.l10n.plugin_notifications,
      };

  static String _kindDescription(
    BuildContext context,
    HermesNotificationKind kind,
  ) => switch (kind) {
    HermesNotificationKind.approval => context.l10n.approval_needed_description,
    HermesNotificationKind.input => context.l10n.input_needed_description,
    HermesNotificationKind.turnDone =>
      context.l10n.response_complete_description,
    HermesNotificationKind.turnError => context.l10n.turn_failed_description,
    HermesNotificationKind.backgroundDone =>
      context.l10n.background_task_completed_description,
    HermesNotificationKind.credits =>
      context.l10n.credit_notifications_description,
    HermesNotificationKind.plugin =>
      context.l10n.plugin_notifications_description,
  };

  Future<void> _sendTest() async {
    final ok = await TurnNotificationService.shared.sendTestNotification(
      title: context.l10n.test_notification_title,
      body: context.l10n.test_notification_body,
    );
    if (!mounted) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? context.l10n.test_notification_sent
                : context.l10n.test_notification_unsupported,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NotificationPrefs>(
      valueListenable: notificationPrefs,
      builder: (context, prefs, _) => Card(
        child: Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: Text(context.l10n.enable_notifications),
              subtitle: Text(context.l10n.enable_notifications_description),
              value: prefs.enabled,
              onChanged: (on) async {
                await NotificationPrefsStore.setEnabled(on);
                if (!on) {
                  await TurnNotificationService.shared.cancelAllOngoingChats();
                }
              },
            ),
            for (final kind in HermesNotificationKind.values) ...[
              const Divider(height: 1),
              SwitchListTile(
                title: Text(_kindLabel(context, kind)),
                subtitle: Text(_kindDescription(context, kind)),
                value: prefs.enabled && prefs.kinds[kind] == true,
                onChanged: prefs.enabled
                    ? (on) =>
                          unawaited(NotificationPrefsStore.setKind(kind, on))
                    : null,
              ),
            ],
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: Text(context.l10n.send_test_notification),
              onTap: () => unawaited(_sendTest()),
            ),
            if (!TurnNotificationService.shared.permissionGranted) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.warning_amber_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(context.l10n.notifications_permission_denied),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
