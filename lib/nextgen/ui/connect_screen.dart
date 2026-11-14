// Kyllene-style onboarding: one dashboard address, one sign-in.
//
// Step 1 tests the address (`/api/status`) and shows what the gateway offers;
// it can find dashboards on the local network and store a Cloudflare Access
// service token. Step 2 signs in with a username/password or in the browser,
// picks a profile when the dashboard hosts several, and saves the connection.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/connection_manager.dart';
import '../../core/services/hermes_sign_in.dart';
import '../../core/services/lan_discovery_service.dart';
import '../theme/nextgen_theme.dart';
import 'certificate_picker.dart';
import 'widgets.dart';
import '../nextgen_l10n.dart';

class NgConnectScreen extends StatefulWidget {
  const NgConnectScreen({
    super.key,
    required this.connManager,
    required this.onConnected,
    this.existing,
    this.firstRun = true,
    this.onCancel,
    this.onUseClassic,
  });

  final ConnectionManager connManager;
  final ValueChanged<SavedConnection> onConnected;

  /// A saved connection to sign in to again (address pre-filled).
  final SavedConnection? existing;
  final bool firstRun;
  final VoidCallback? onCancel;

  /// Leaves NextGen for the classic interface (first run only).
  final VoidCallback? onUseClassic;

  @override
  State<NgConnectScreen> createState() => _NgConnectScreenState();
}

class _NgConnectScreenState extends State<NgConnectScreen> {
  final _address = TextEditingController();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _testing = false;
  ProbeResult? _probe;
  String? _addressError;
  bool _showAccess = false;
  bool _showCertificate = false;
  late final NgCertificateController _certificate = NgCertificateController(
    initial: widget.existing?.clientCertificate,
  );
  bool _signInStep = false;
  bool _signingIn = false;
  bool _waitingForBrowser = false;
  String? _signInError;
  bool _obscure = true;
  String? _profile;

  @override
  void initState() {
    super.initState();
    _certificate.addListener(_onCertificate);
    final existing = widget.existing;
    if (existing != null) {
      _address.text =
          existing.singleLoginUrl ??
          existing.desktopGatewayUrl ??
          existing.baseUrl;
      _username.text = existing.dashboardUsername ?? '';
      _showCertificate = existing.clientCertificate != null;
      _profile = existing.gatewayProfile;
      WidgetsBinding.instance.addPostFrameCallback((_) => _test());
    }
  }

  void _onCertificate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _certificate.removeListener(_onCertificate);
    for (final c in [
      _address,
      _clientId,
      _clientSecret,
      _username,
      _password,
    ]) {
      c.dispose();
    }
    _certificate.dispose();
    super.dispose();
  }

  GatewayUrl? get _url => switch (_probe) {
    final ProbeResult p => p.url,
    null => null,
  };

  GatewayStatus? get _status => switch (_probe) {
    ProbeReachable(:final status) => status,
    _ => null,
  };

  Future<void> _test() async {
    FocusScope.of(context).unfocus();
    final GatewayUrl url;
    try {
      url = GatewayUrl.parse(_address.text);
    } on InvalidGatewayUrlException catch (e) {
      setState(() => _addressError = e.toString());
      return;
    }
    final id = _clientId.text.trim();
    final secret = _clientSecret.text.trim();
    if (id.isEmpty != secret.isEmpty) {
      setState(() => _addressError = ngL.ng_enter_both_the_client_id_and);
      return;
    }
    if (id.isNotEmpty) {
      await HermesSignInVault.instance.setAccessToken(
        url.host,
        AccessToken(id, secret),
      );
      _clientId.clear();
      _clientSecret.clear();
    }
    setState(() {
      _addressError = null;
      _testing = true;
      _probe = null;
    });
    final result = await GatewayProbe().probe(
      url,
      certificate: _certificate.config,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
      if (result is ProbeAccessBlocked) _showAccess = true;
      if (result is ProbeClientCertRequired) _showCertificate = true;
      final profiles = _status?.profiles ?? const [];
      if (_profile != null && !profiles.contains(_profile)) _profile = null;
    });
  }

  Future<void> _findOnNetwork() async {
    final picked = await showNgSheet<DiscoveredHermesServer>(
      context,
      builder: (_) => _DiscoverySheet(
        known: knownDiscoveryTargets(widget.connManager.getConnections()),
      ),
    );
    if (picked == null || !mounted) return;
    _address.text = picked.connectionUrl;
    await _test();
  }

  Future<void> _save(String method) async {
    final url = _url!;
    final certificate = await _certificate.commit();
    final saved = await widget.connManager.saveSingleLoginConnection(
      url: url,
      signInMethod: method,
      label: widget.existing?.label,
      username: method == 'password' ? _username.text : null,
      password: method == 'password' ? _password.text : null,
      profile: _profile,
      clientCertificate: certificate,
      clearClientCertificate: _certificate.cleared,
    );
    // A replaced or removed identity is no longer referenced.
    unawaited(widget.connManager.cleanupUnreferencedCertificates());
    if (!mounted) return;
    widget.onConnected(saved);
  }

  Future<void> _passwordSignIn() async {
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _signInError = ngL.ng_enter_your_username_and_password);
      return;
    }
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    final result = await HermesSignIn().passwordSignIn(
      _url!,
      username: user,
      password: pass,
      certificate: _certificate.config,
    );
    if (!mounted) return;
    await _handle(result, 'password');
  }

  Future<void> _browserSignIn() async {
    setState(() {
      _signingIn = true;
      _waitingForBrowser = true;
      _signInError = null;
    });
    final result = await HermesSignIn().browserSignIn(
      _url!,
      certificate: _certificate.config,
      openBrowser: (uri) =>
          launchUrl(uri, mode: LaunchMode.externalApplication),
    );
    if (!mounted) return;
    await _handle(result, 'browser');
  }

  Future<void> _handle(SignInResult result, String method) async {
    switch (result) {
      case SignInOk():
        try {
          await _save(method);
        } catch (e) {
          if (mounted) {
            setState(() => _signInError = ngL.ng_couldn_t_save_the_sign_in(e));
          }
        }
      case SignInInvalidCredentials():
        _signInError = ngL.ng_wrong_username_or_password;
      case SignInRateLimited():
        _signInError = ngL.ng_too_many_attempts_wait_a_moment;
      case SignInFailed(:final message):
        _signInError = message;
    }
    if (mounted) {
      setState(() {
        _signingIn = false;
        _waitingForBrowser = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    return PopScope(
      canPop: !_signInStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _signInStep) setState(() => _signInStep = false);
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          leading: _signInStep
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _signInStep = false),
                )
              : widget.onCancel == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onCancel,
                ),
        ),
        body: NgGlow(
          child: SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _signInStep ? _signInView(c) : _addressView(c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _addressView(NgColors c) {
    final status = _status;
    final url = _url;
    return ListView(
      key: const ValueKey('address'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Text(
          widget.firstRun ? ngL.ng_welcome_to_hermes : ngL.ng_add_a_gateway,
          style: NgType.display.copyWith(color: c.text),
        ),
        const SizedBox(height: 10),
        Text(
          widget.firstRun
              ? ngL.ng_connect_to_your_hermes_agent_dashboard
              : ngL.ng_connect_to_another_hermes_agent_dashboard,
          style: NgType.body.copyWith(color: c.text2),
        ),
        const SizedBox(height: 28),
        NgField(
          controller: _address,
          label: ngL.ng_dashboard_address,
          hint: '192.168.1.20:9119',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _test(),
          errorText: _addressError,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextButton(
              onPressed: _testing ? null : _test,
              child: Text(_testing ? ngL.ng_testing : ngL.ng_test),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            ngL.ng_where_your_hermes_dashboard_runs_lan,
            style: NgType.caption.copyWith(color: c.text3),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NgPill(
              ngL.ng_find_on_my_network,
              icon: Icons.wifi_find,
              tone: NgTone.accent,
              onTap: _findOnNetwork,
            ),
            NgPill(
              ngL.ng_which_address_do_i_use,
              icon: Icons.help_outline,
              onTap: () => showNgSheet<void>(
                context,
                builder: (_) => const _AddressGuide(),
              ),
            ),
            NgPill(
              ngL.ng_behind_cloudflare_access,
              icon: Icons.shield_outlined,
              onTap: () => setState(() => _showAccess = !_showAccess),
            ),
            NgPill(
              ngL.ng_need_a_client_certificate,
              icon: Icons.badge_outlined,
              tone: _certificate.config != null
                  ? NgTone.success
                  : NgTone.neutral,
              onTap: () => setState(() => _showCertificate = !_showCertificate),
            ),
          ],
        ),
        if (_showAccess) ...[const SizedBox(height: 16), _accessCard(c)],
        if (_showCertificate) ...[
          const SizedBox(height: 16),
          NgCertificateCard(
            controller: _certificate,
            isHttps: GatewayUrl.tryParse(_address.text)?.isHttps ?? true,
          ),
        ],
        if (url != null && url.isExposed) ...[
          const SizedBox(height: 16),
          NgCard(
            color: c.warningSoft,
            borderColor: c.warning.withValues(alpha: 0.4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: c.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ngL.ng_this_address_isn_t_private_and,
                    style: NgType.bodySmall.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_probe != null) ...[const SizedBox(height: 16), _probeCard(c)],
        const SizedBox(height: 24),
        NgPrimaryButton(
          label: ngL.ng_continue_to_sign_in,
          busy: _testing,
          onPressed: status == null || !status.canSignIn
              ? null
              : () => setState(() {
                  _signInStep = true;
                  _signInError = null;
                }),
        ),
        if (widget.onUseClassic != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.onUseClassic,
            child: Text(ngL.ng_use_the_classic_interface_instead),
          ),
        ],
      ],
    );
  }

  Widget _accessCard(NgColors c) {
    final url = GatewayUrl.tryParse(_address.text);
    final saved = url == null
        ? null
        : HermesSignInVault.instance.accessTokenFor(url.host);
    return NgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ngL.ng_if_cloudflare_access_protects_this_address,
            style: NgType.bodySmall.copyWith(color: c.text2),
          ),
          if (saved != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: c.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ngL.ng_a_service_token_is_saved_for,
                    style: NgType.label.copyWith(color: c.text),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await HermesSignInVault.instance.setAccessToken(
                      url!.host,
                      null,
                    );
                    if (mounted) setState(() {});
                  },
                  child: Text(ngL.ng_forget),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          NgField(controller: _clientId, label: ngL.ng_client_id),
          const SizedBox(height: 10),
          NgField(
            controller: _clientSecret,
            label: ngL.ng_client_secret,
            obscure: true,
          ),
          const SizedBox(height: 6),
          Text(
            ngL.ng_stored_encrypted_on_this_phone_and,
            style: NgType.caption.copyWith(color: c.text3),
          ),
        ],
      ),
    );
  }

  Widget _probeCard(NgColors c) {
    final probe = _probe!;
    if (probe case ProbeReachable(:final status)) {
      return NgCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: c.success, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status.version == null
                        ? ngL.ng_hermes_is_reachable
                        : ngL.ng_hermes_is_reachable_2(status.version ?? ''),
                    style: NgType.heading.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                ngL.ng_sign_in_is_tested_next_then,
                style: NgType.caption.copyWith(color: c.text3),
              ),
            ),
            const Divider(height: 24),
            _kv(
              c,
              ngL.ng_agent_gateway,
              status.gatewayRunning ? ngL.ng_running : ngL.ng_stopped,
              status.gatewayRunning ? c.success : c.warning,
            ),
            _kv(c, ngL.ng_sign_in, switch (status.signInSummary) {
              'Password' => ngL.ng_username_password,
              'Browser' => ngL.ng_in_the_browser_sso,
              'Not required' => ngL.ng_not_required,
              'Password or browser' => ngL.ng_password_or_browser,
              'Unsupported' => ngL.ng_unsupported,
              final other => other,
            }, status.canSignIn ? c.text2 : c.danger),
            if (status.profiles.isNotEmpty)
              _kv(c, ngL.ng_profiles, status.profiles.join(', '), c.text2),
            if (!status.canSignIn) ...[
              const SizedBox(height: 10),
              Text(
                ngL.ng_this_dashboard_offers_neither_a_username,
                style: NgType.bodySmall.copyWith(color: c.danger),
              ),
            ] else if (!status.authRequired &&
                !isPrivateHost(probe.url.host)) ...[
              const SizedBox(height: 10),
              Text(
                ngL.ng_the_auth_gate_is_off_on,
                style: NgType.bodySmall.copyWith(color: c.warning),
              ),
            ],
          ],
        ),
      );
    }
    final (title, body) = switch (probe) {
      ProbeUnreachable(:final reason) => (
        ngL.ng_couldn_t_reach_the_dashboard,
        ngL.ng_check_the_address_and_port_9119(reason),
      ),
      ProbeNotHermes(:final httpStatus) => (
        ngL.ng_that_isn_t_a_hermes_dashboard,
        httpStatus == null
            ? ngL.ng_something_answered_but_not_a_hermes_2
            : ngL.ng_something_answered_http_but_not_a_2(httpStatus),
      ),
      ProbeAccessBlocked(:final tokenSent, :final httpStatus) => (
        ngL.ng_cloudflare_access_stopped_the_request,
        tokenSent
            ? ngL.ng_cloudflare_access_turned_down_the_service(httpStatus)
            : ngL.ng_add_a_cloudflare_access_service_token_2,
      ),
      ProbeClientCertRequired() => (
        ngL.ng_a_client_certificate_is_needed,
        ngL.ng_this_server_asks_for_a_client,
      ),
      ProbeReachable() => ('', ''),
    };
    return NgCard(
      color: c.dangerSoft,
      borderColor: c.danger.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: c.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: NgType.heading.copyWith(color: c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            body,
            style: NgType.bodySmall.copyWith(color: c.text2),
          ),
        ],
      ),
    );
  }

  Widget _kv(NgColors c, String k, String v, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(k, style: NgType.label.copyWith(color: c.text2)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            v,
            textAlign: TextAlign.end,
            style: NgType.label.copyWith(color: color),
          ),
        ),
      ],
    ),
  );

  Widget _signInView(NgColors c) {
    final status = _status!;
    final url = _url!;
    final password = status.supportsPasswordLogin;
    final browser = status.supportsNativeSignIn;
    final detail = !status.authRequired
        ? ngL.ng_this_dashboard_doesn_t_ask_for
        : password && browser
        ? ngL.ng_use_the_dashboard_username_and_password(url.display)
        : password
        ? ngL.ng_use_the_dashboard_username_and_password_2(url.display)
        : ngL.ng_sign_in_to_in_your_browser(url.display);
    return ListView(
      key: const ValueKey('signin'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: NgPill(
            ngL.ng_gateway(url.display),
            icon: Icons.dns_outlined,
            onTap: () => setState(() => _signInStep = false),
          ),
        ),
        const SizedBox(height: 18),
        Text(ngL.ng_sign_in_2, style: NgType.display.copyWith(color: c.text)),
        const SizedBox(height: 10),
        Text(detail, style: NgType.body.copyWith(color: c.text2)),
        if (status.profiles.length > 1) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              ngL.ng_profile,
              style: NgType.label.copyWith(color: c.text2),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(ngL.ng_server_default),
                selected: _profile == null,
                onSelected: (_) => setState(() => _profile = null),
              ),
              for (final p in status.profiles)
                ChoiceChip(
                  label: Text(p),
                  selected: _profile == p,
                  onSelected: (_) => setState(() => _profile = p),
                ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        if (!status.authRequired)
          NgPrimaryButton(
            label: ngL.ng_continue,
            busy: _signingIn,
            onPressed: () async {
              setState(() => _signingIn = true);
              try {
                await _save('none');
              } finally {
                if (mounted) setState(() => _signingIn = false);
              }
            },
          )
        else ...[
          if (password) ...[
            AutofillGroup(
              child: Column(
                children: [
                  NgField(
                    controller: _username,
                    label: ngL.ng_username,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  NgField(
                    controller: _password,
                    label: ngL.ng_password,
                    obscure: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _passwordSignIn(),
                    suffix: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            NgPrimaryButton(
              label: _signingIn && !_waitingForBrowser
                  ? ngL.ng_signing_in
                  : ngL.ng_sign_in_2,
              busy: _signingIn && !_waitingForBrowser,
              onPressed: _signingIn ? null : _passwordSignIn,
            ),
          ],
          if (password && browser)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(child: Divider(color: c.stroke)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or',
                      style: NgType.caption.copyWith(color: c.text3),
                    ),
                  ),
                  Expanded(child: Divider(color: c.stroke)),
                ],
              ),
            ),
          if (browser && password)
            NgSecondaryButton(
              label: _waitingForBrowser
                  ? ngL.ng_waiting_for_the_browser
                  : ngL.ng_sign_in_with_browser,
              icon: Icons.open_in_browser,
              onPressed: _signingIn ? null : _browserSignIn,
            )
          else if (browser)
            NgPrimaryButton(
              label: _waitingForBrowser
                  ? ngL.ng_waiting_for_the_browser
                  : ngL.ng_sign_in_with_browser,
              icon: Icons.open_in_browser,
              busy: _waitingForBrowser,
              onPressed: _signingIn ? null : _browserSignIn,
            ),
          if (_waitingForBrowser) ...[
            const SizedBox(height: 12),
            Text(
              ngL.ng_finish_signing_in_on_the_page,
              textAlign: TextAlign.center,
              style: NgType.caption.copyWith(color: c.text3),
            ),
          ],
        ],
        if (_signInError != null) ...[
          const SizedBox(height: 16),
          Text(
            _signInError!,
            textAlign: TextAlign.center,
            style: NgType.bodySmall.copyWith(color: c.danger),
          ),
        ],
        const SizedBox(height: 18),
        TextButton(
          onPressed: () => setState(() => _signInStep = false),
          child: Text(ngL.ng_use_a_different_gateway),
        ),
      ],
    );
  }
}

class _AddressGuide extends StatelessWidget {
  const _AddressGuide();

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    Widget item(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.accentText),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: NgType.heading.copyWith(color: c.text)),
                const SizedBox(height: 4),
                Text(body, style: NgType.bodySmall.copyWith(color: c.text2)),
              ],
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ngL.ng_which_address_do_i_use,
              style: NgType.title.copyWith(color: c.text),
            ),
            const SizedBox(height: 18),
            item(
              Icons.wifi,
              ngL.ng_same_wi_fi_or_local_network,
              ngL.ng_use_the_server_s_local_address,
            ),
            item(
              Icons.hub_outlined,
              ngL.ng_tailscale,
              ngL.ng_turn_on_tailscale_on_this_phone,
            ),
            item(
              Icons.lock_outline,
              'HTTPS',
              ngL.ng_use_your_https_address_when_the,
            ),
            const SizedBox(height: 4),
            Text(
              ngL.ng_start_the_dashboard_on_the_server,
              style: NgType.label.copyWith(color: c.text2),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                Clipboard.setData(
                  const ClipboardData(text: 'hermes dashboard --host 0.0.0.0'),
                );
                ngToast(context, ngL.ng_copied);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.well,
                  borderRadius: BorderRadius.circular(NgRadii.md),
                ),
                child: Text(
                  'hermes dashboard --host 0.0.0.0',
                  style: NgType.code.copyWith(color: c.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Addresses the phone already knows from saved connections, probed for a
/// dashboard before the local sweep. A tailnet (100.x / *.ts.net) or a host
/// on another subnet cannot be swept, but a saved one can still be checked.
List<DiscoveryTarget> knownDiscoveryTargets(
  Iterable<SavedConnection> connections,
) {
  final out = <DiscoveryTarget>{};
  for (final c in connections) {
    final gateway = Uri.tryParse(c.desktopGatewayUrl ?? '');
    if (gateway != null && gateway.host.isNotEmpty) {
      out.add(DiscoveryTarget(gateway.host, gateway.port));
      out.add(DiscoveryTarget(gateway.host, 9119));
    }
    if (c.host.trim().isNotEmpty) {
      final host = c.host.trim();
      out.add(DiscoveryTarget(host, c.dashboardPortOverride ?? 9119));
      out.add(DiscoveryTarget(host, 9119));
    }
    if (out.length >= 32) break;
  }
  return out.take(32).toList();
}

class _DiscoverySheet extends StatefulWidget {
  const _DiscoverySheet({this.known = const []});

  final List<DiscoveryTarget> known;

  @override
  State<_DiscoverySheet> createState() => _DiscoverySheetState();
}

class _DiscoverySheetState extends State<_DiscoverySheet> {
  LanDiscoveryService? _service;
  final _port = TextEditingController();
  List<DiscoveredHermesServer>? _found;
  String? _error;
  String? _portError;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final raw = _port.text.trim();
    final custom = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && (custom == null || custom < 1 || custom > 65535)) {
      setState(() => _portError = ngL.ng_enter_a_port_from_1_to);
      return;
    }
    _service?.cancel();
    final service = LanDiscoveryService.dashboards(
      extraPorts: [?custom],
      extraTargets: <DiscoveryTarget>{
        ...widget.known,
        if (custom != null)
          for (final t in widget.known) DiscoveryTarget(t.host, custom),
      }.take(32).toList(),
    );
    _service = service;
    setState(() {
      _found = null;
      _error = null;
      _portError = null;
    });
    try {
      final found = await service.discover();
      if (mounted && _service == service) setState(() => _found = found);
    } catch (e) {
      if (mounted && _service == service) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _service?.cancel();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final found = _found;
    final port = _port.text.trim();
    return SafeArea(
      child: Padding(
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
              Text(
                ngL.ng_find_on_my_network,
                style: NgType.title.copyWith(color: c.text),
              ),
              const SizedBox(height: 6),
              Text(
                port.isEmpty
                    ? ngL.ng_looks_for_hermes_dashboards_on_port
                    : ngL.ng_looks_for_hermes_dashboards_on_ports(port),
                style: NgType.bodySmall.copyWith(color: c.text3),
              ),
              const SizedBox(height: 14),
              NgField(
                controller: _port,
                label: ngL.ng_other_port_optional,
                hint: '9119',
                keyboardType: TextInputType.number,
                errorText: _portError,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _run(),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Text(_error!, style: NgType.bodySmall.copyWith(color: c.danger))
              else if (found == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (found.isEmpty)
                Text(
                  ngL.ng_no_dashboards_answered_start_one_with,
                  style: NgType.bodySmall.copyWith(color: c.text2),
                )
              else
                for (final s in found)
                  NgRow(
                    icon: Icons.dns_outlined,
                    title: s.label,
                    subtitle: s.displayName,
                    onTap: () => Navigator.pop(context, s),
                  ),
              const SizedBox(height: 12),
              Text(
                ngL.ng_using_tailscale_or_a_vpn_those,
                style: NgType.bodySmall.copyWith(color: c.text3),
              ),
              if (found != null || _error != null) ...[
                const SizedBox(height: 12),
                NgSecondaryButton(label: ngL.ng_search_again, onPressed: _run),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
