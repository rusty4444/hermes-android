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
import '../nextgen_l10n.dart';

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
      title: ngL.ng_settings,
      body: ListenableBuilder(
        listenable: look,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            NgSectionLabel(ngL.ng_gateway_2),
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
                  _kv(c, ngL.ng_signed_in, switch (conn) {
                    _ when !conn.singleLogin => ngL.ng_classic_connection_2,
                    _ when conn.usesBrowserSignIn =>
                      _signedInAs == null
                          ? ngL.ng_in_the_browser
                          : ngL.ng_in_the_browser_as(_signedInAs!),
                    _ when conn.signInMethod == 'none' => ngL.ng_not_required,
                    _ =>
                      _signedInAs ?? conn.dashboardUsername ?? ngL.ng_password,
                  }),
                  if (conn.gatewayProfile != null)
                    _kv(c, ngL.ng_profile, conn.gatewayProfile!),
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
                        label: Text(
                          _checking ? ngL.ng_testing : ngL.ng_test_connection,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: scope.signInAgain,
                        icon: const Icon(Icons.login, size: 18),
                        label: Text(ngL.ng_sign_in_again_2),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: c.danger),
                        onPressed: () => _signOut(conn),
                        icon: const Icon(Icons.logout, size: 18),
                        label: Text(ngL.ng_sign_out),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ...[
              NgSectionLabel(ngL.ng_saved_gateways),
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
                            : ngL.ng_classic_connection(other.baseUrl),
                        trailing: other.id == conn.id
                            ? NgPill(ngL.ng_in_use, tone: NgTone.accent)
                            : null,
                        onTap: other.id == conn.id
                            ? null
                            : () => scope.switchTo(other.id),
                      ),
                    NgRow(
                      icon: Icons.add,
                      title: ngL.ng_add_a_gateway,
                      onTap: scope.addGateway,
                    ),
                  ],
                ),
              ),
            ],
            NgSectionLabel(ngL.ng_appearance),
            NgCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ngL.ng_theme,
                    style: NgType.label.copyWith(color: c.text2),
                  ),
                  const SizedBox(height: 8),
                  NgSegmented<ThemeMode>(
                    values: const [
                      ThemeMode.system,
                      ThemeMode.light,
                      ThemeMode.dark,
                    ],
                    selected: look.themeMode,
                    labelOf: (m) => switch (m) {
                      ThemeMode.system => ngL.ng_system,
                      ThemeMode.light => ngL.ng_light,
                      ThemeMode.dark => ngL.ng_dark,
                    },
                    onChanged: (m) =>
                        NextGenPreferences.setThemeMode(scope.prefs, m),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    ngL.ng_accent,
                    style: NgType.label.copyWith(color: c.text2),
                  ),
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
                    title: Text(ngL.ng_pure_black),
                    subtitle: Text(ngL.ng_dark_theme_uses_true_black_oled),
                    value: look.pureBlack,
                    onChanged: (v) =>
                        NextGenPreferences.setPureBlack(scope.prefs, v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(ngL.ng_glow),
                    subtitle: Text(ngL.ng_soft_accent_light_behind_each_screen),
                    value: look.glow,
                    onChanged: (v) =>
                        NextGenPreferences.setGlow(scope.prefs, v),
                  ),
                ],
              ),
            ),
            NgSectionLabel(ngL.ng_interface),
            NgCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: const Text('NextGen'),
                    subtitle: Text(ngL.ng_the_new_interface_turn_off_to),
                    value: true,
                    onChanged: (v) =>
                        NextGenPreferences.setEnabled(scope.prefs, v),
                  ),
                  NgRow(
                    icon: Icons.tune,
                    title: ngL.ng_more_settings,
                    subtitle:
                        ngL.ng_voice_notifications_language_backups_and_the,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(connection: conn),
                      ),
                    ),
                  ),
                  NgRow(
                    icon: Icons.description_outlined,
                    title: ngL.ng_licences,
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
      title: ngL.ng_sign_out_of(conn.label),
      body: ngL.ng_this_gateway_and_its_saved_sign,
      confirm: ngL.ng_sign_out,
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
