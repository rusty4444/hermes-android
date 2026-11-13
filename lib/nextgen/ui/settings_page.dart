// NextGen settings: the gateway you're signed in to (with Kyllene's staged
// connection check), saved gateways, appearance, and the NextGen switch.
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/models/connection.dart';
import '../../core/screens/settings_screen.dart';
import '../../core/services/app_licenses.dart';
import '../../core/services/hermes_sign_in.dart';
import '../data/connection_check.dart';
import '../nextgen_preferences.dart';
import '../theme/nextgen_theme.dart';
import 'nextgen_scope.dart';
import 'widgets.dart';

class NgSettingsPage extends StatefulWidget {
  const NgSettingsPage({super.key});

  @override
  State<NgSettingsPage> createState() => _NgSettingsPageState();
}

class _NgSettingsPageState extends State<NgSettingsPage> {
  ConnectionReport? _report;
  bool _checking = false;
  String? _signedInAs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMe());
  }

  Future<void> _loadMe() async {
    final gateway = NgScope.of(context).gateway;
    try {
      final res = await gateway.dashboard.apiRequest('GET', 'auth/me');
      if (res.statusCode == 200 && mounted) {
        final user = AuthUser.fromJson(
          Map<String, dynamic>.from(jsonDecode(res.body) as Map),
        );
        setState(() => _signedInAs = user.label);
      }
    } catch (_) {
      // Shown as unknown.
    }
  }

  Future<void> _check() async {
    final conn = NgScope.of(context).connection;
    setState(() {
      _checking = true;
      _report = null;
    });
    final report = await runConnectionCheck(
      conn,
      onProgress: (r) {
        if (mounted) setState(() => _report = r);
      },
    );
    if (!mounted) return;
    setState(() {
      _checking = false;
      _report = report;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final scope = NgScope.of(context);
    final conn = scope.connection;
    final look = NextGenLook.instance;
    final brightness = Theme.of(context).brightness;
    return NgPage(
      title: 'Settings',
      body: ListenableBuilder(
        listenable: look,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const NgSectionLabel('Gateway'),
            NgCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns_outlined, color: c.accentText),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conn.label,
                              style: NgType.heading.copyWith(color: c.text),
                            ),
                            Text(
                              scope.gateway.url.display,
                              style: NgType.caption.copyWith(color: c.text3),
                            ),
                          ],
                        ),
                      ),
                      ListenableBuilder(
                        listenable: scope.gateway,
                        builder: (context, _) => NgPill(
                          scope.gateway.state.label,
                          tone: scope.gateway.state.isConnected
                              ? NgTone.success
                              : NgTone.warning,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _kv(c, 'Signed in', switch (conn) {
                    _ when !conn.singleLogin => 'Classic connection',
                    _ when conn.usesBrowserSignIn =>
                      'In the browser${_signedInAs == null ? '' : ' as $_signedInAs'}',
                    _ when conn.signInMethod == 'none' => 'Not required',
                    _ => _signedInAs ?? conn.dashboardUsername ?? 'Password',
                  }),
                  if (conn.gatewayProfile != null)
                    _kv(c, 'Profile', conn.gatewayProfile!),
                  if (_report != null) ...[
                    const Divider(height: 24),
                    for (final stage in CheckStage.values)
                      _stage(c, stage, _report!.results[stage]!),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _checking ? null : _check,
                        icon: const Icon(Icons.network_check, size: 18),
                        label: Text(_checking ? 'Testing…' : 'Test connection'),
                      ),
                      TextButton.icon(
                        onPressed: scope.signInAgain,
                        icon: const Icon(Icons.login, size: 18),
                        label: const Text('Sign in again'),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        onPressed: () => _signOut(conn),
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Sign out'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ...[
              const NgSectionLabel('Saved gateways'),
              NgCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    for (final other in scope.connections)
                      NgRow(
                        icon: other.id == conn.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        title: other.label,
                        subtitle: other.singleLogin
                            ? (other.singleLoginUrl ?? other.baseUrl)
                            : '${other.baseUrl} · classic connection',
                        trailing: other.id == conn.id
                            ? NgPill('In use', tone: NgTone.accent)
                            : null,
                        onTap: other.id == conn.id
                            ? null
                            : () => scope.switchTo(other.id),
                      ),
                    NgRow(
                      icon: Icons.add,
                      title: 'Add a gateway',
                      onTap: scope.addGateway,
                    ),
                  ],
                ),
              ),
            ],
            const NgSectionLabel('Appearance'),
            NgCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: NgType.label.copyWith(color: c.text2)),
                  const SizedBox(height: 8),
                  NgSegmented<ThemeMode>(
                    values: const [
                      ThemeMode.system,
                      ThemeMode.light,
                      ThemeMode.dark,
                    ],
                    selected: look.themeMode,
                    labelOf: (m) => switch (m) {
                      ThemeMode.system => 'System',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    },
                    onChanged: (m) =>
                        NextGenPreferences.setThemeMode(scope.prefs, m),
                  ),
                  const SizedBox(height: 18),
                  Text('Accent', style: NgType.label.copyWith(color: c.text2)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final a in NgAccent.values)
                        GestureDetector(
                          onTap: () =>
                              NextGenPreferences.setAccent(scope.prefs, a),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: ngAccentSwatch(a, brightness),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: a == look.accent
                                    ? c.text
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: a == look.accent
                                ? Icon(Icons.check, size: 18, color: c.onAccent)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pure black'),
                    subtitle: const Text('Dark theme uses true black (OLED)'),
                    value: look.pureBlack,
                    onChanged: (v) =>
                        NextGenPreferences.setPureBlack(scope.prefs, v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Glow'),
                    subtitle: const Text(
                      'Soft accent light behind each screen',
                    ),
                    value: look.glow,
                    onChanged: (v) =>
                        NextGenPreferences.setGlow(scope.prefs, v),
                  ),
                ],
              ),
            ),
            const NgSectionLabel('Interface'),
            NgCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('NextGen'),
                    subtitle: const Text(
                      'The new interface. Turn off to go back to the classic '
                      'one; your gateways and chats are shared.',
                    ),
                    value: true,
                    onChanged: (v) =>
                        NextGenPreferences.setEnabled(scope.prefs, v),
                  ),
                  NgRow(
                    icon: Icons.tune,
                    title: 'More settings',
                    subtitle:
                        'Voice, notifications, language, backups and the '
                        'gateway\'s config',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(connection: conn),
                      ),
                    ),
                  ),
                  NgRow(
                    icon: Icons.description_outlined,
                    title: 'Licences',
                    onTap: () {
                      registerAppLicenses();
                      showLicensePage(
                        context: context,
                        applicationName: 'Hermes',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut(SavedConnection conn) async {
    final ok = await ngConfirm(
      context,
      title: 'Sign out of ${conn.label}?',
      body:
          'This gateway and its saved sign-in are removed from this phone, '
          'in both interfaces. Your chats stay on the gateway.',
      confirm: 'Sign out',
    );
    if (!ok || !mounted) return;
    await NgScope.of(context).signOut(conn);
  }

  Widget _kv(NgColors c, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(k, style: NgType.label.copyWith(color: c.text3)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: NgType.label.copyWith(color: c.text),
          ),
        ),
      ],
    ),
  );

  Widget _stage(NgColors c, CheckStage stage, StageResult r) {
    final (icon, color) = switch (r.outcome) {
      CheckOutcome.passed => (Icons.check_circle, c.success),
      CheckOutcome.failed => (Icons.cancel, c.danger),
      CheckOutcome.checking => (Icons.more_horiz, c.accent),
      CheckOutcome.skipped => (Icons.remove_circle_outline, c.text3),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stage.label, style: NgType.label.copyWith(color: c.text)),
                Text(r.detail, style: NgType.caption.copyWith(color: c.text2)),
                if (r.fix != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      r.fix!,
                      style: NgType.caption.copyWith(color: c.accentText),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
