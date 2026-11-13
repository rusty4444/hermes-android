// Kyllene-style onboarding: one dashboard address, one sign-in.
//
// Step 1 tests the address (`/api/status`) and shows what the gateway offers;
// it can find dashboards on the local network and store a Cloudflare Access
// service token. Step 2 signs in with a username/password or in the browser,
// picks a profile when the dashboard hosts several, and saves the connection.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/connection_manager.dart';
import '../../core/services/hermes_sign_in.dart';
import '../../core/services/lan_discovery_service.dart';
import '../theme/nextgen_theme.dart';
import 'widgets.dart';

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
  bool _signInStep = false;
  bool _signingIn = false;
  bool _waitingForBrowser = false;
  String? _signInError;
  bool _obscure = true;
  String? _profile;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _address.text =
          existing.singleLoginUrl ??
          existing.desktopGatewayUrl ??
          existing.baseUrl;
      _username.text = existing.dashboardUsername ?? '';
      _profile = existing.gatewayProfile;
      WidgetsBinding.instance.addPostFrameCallback((_) => _test());
    }
  }

  @override
  void dispose() {
    for (final c in [
      _address,
      _clientId,
      _clientSecret,
      _username,
      _password,
    ]) {
      c.dispose();
    }
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
      setState(
        () => _addressError =
            'Enter both the Client ID and the Client Secret, or neither.',
      );
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
      certificate: widget.existing?.clientCertificate,
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
      if (result is ProbeAccessBlocked) _showAccess = true;
      final profiles = _status?.profiles ?? const [];
      if (_profile != null && !profiles.contains(_profile)) _profile = null;
    });
  }

  Future<void> _findOnNetwork() async {
    final picked = await showNgSheet<DiscoveredHermesServer>(
      context,
      builder: (_) => const _DiscoverySheet(),
    );
    if (picked == null || !mounted) return;
    _address.text = picked.connectionUrl;
    await _test();
  }

  Future<void> _save(String method) async {
    final url = _url!;
    final saved = await widget.connManager.saveSingleLoginConnection(
      url: url,
      signInMethod: method,
      label: widget.existing?.label,
      username: method == 'password' ? _username.text : null,
      password: method == 'password' ? _password.text : null,
      profile: _profile,
      clientCertificate: widget.existing?.clientCertificate,
    );
    if (!mounted) return;
    widget.onConnected(saved);
  }

  Future<void> _passwordSignIn() async {
    final user = _username.text.trim();
    final pass = _password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => _signInError = 'Enter your username and password.');
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
      certificate: widget.existing?.clientCertificate,
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
      certificate: widget.existing?.clientCertificate,
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
            setState(() => _signInError = 'Couldn\'t save the sign-in: $e');
          }
        }
      case SignInInvalidCredentials():
        _signInError = 'Wrong username or password.';
      case SignInRateLimited():
        _signInError = 'Too many attempts. Wait a moment and try again.';
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
          widget.firstRun ? 'Welcome to Hermes' : 'Add a gateway',
          style: NgType.display.copyWith(color: c.text),
        ),
        const SizedBox(height: 10),
        Text(
          widget.firstRun
              ? 'Connect to your Hermes Agent dashboard. One address and one '
                    'sign-in reach your chats, tools and settings. Nothing is '
                    'sent until you sign in.'
              : 'Connect to another Hermes Agent dashboard. You stay signed in '
                    'to the ones you saved.',
          style: NgType.body.copyWith(color: c.text2),
        ),
        const SizedBox(height: 28),
        NgField(
          controller: _address,
          label: 'Dashboard address',
          hint: '192.168.1.20:9119',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _test(),
          errorText: _addressError,
          suffix: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextButton(
              onPressed: _testing ? null : _test,
              child: Text(_testing ? 'Testing…' : 'Test'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'Where your hermes dashboard runs: LAN, Tailscale or HTTPS.',
            style: NgType.caption.copyWith(color: c.text3),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NgPill(
              'Find on my network',
              icon: Icons.wifi_find,
              tone: NgTone.accent,
              onTap: _findOnNetwork,
            ),
            NgPill(
              'Which address do I use?',
              icon: Icons.help_outline,
              onTap: () => showNgSheet<void>(
                context,
                builder: (_) => const _AddressGuide(),
              ),
            ),
            NgPill(
              'Behind Cloudflare Access?',
              icon: Icons.shield_outlined,
              onTap: () => setState(() => _showAccess = !_showAccess),
            ),
          ],
        ),
        if (_showAccess) ...[const SizedBox(height: 16), _accessCard(c)],
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
                    'This address isn\'t private and doesn\'t use https://, so '
                    'your password and chats would cross the internet '
                    'unencrypted. Use https://, Tailscale or your own network '
                    'instead.',
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
          label: 'Continue to sign in',
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
            child: const Text('Use the classic interface instead'),
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
            'If Cloudflare Access protects this address, create a service '
            'token in Cloudflare Zero Trust (Access, Service credentials) and '
            'add a Service Auth policy for it to the Access application.',
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
                    'A service token is saved for this address',
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
                  child: const Text('Forget'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          NgField(controller: _clientId, label: 'Client ID'),
          const SizedBox(height: 10),
          NgField(
            controller: _clientSecret,
            label: 'Client Secret',
            obscure: true,
          ),
          const SizedBox(height: 6),
          Text(
            'Stored encrypted on this phone, and sent only to this address.',
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
                        ? 'Hermes is reachable'
                        : 'Hermes ${status.version} is reachable',
                    style: NgType.heading.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                'Sign-in is tested next, then the chat',
                style: NgType.caption.copyWith(color: c.text3),
              ),
            ),
            const Divider(height: 24),
            _kv(
              c,
              'Agent gateway',
              status.gatewayRunning ? 'Running' : 'Stopped',
              status.gatewayRunning ? c.success : c.warning,
            ),
            _kv(c, 'Sign-in', switch (status.signInSummary) {
              'Password' => 'Username & password',
              'Browser' => 'In the browser (SSO)',
              final other => other,
            }, status.canSignIn ? c.text2 : c.danger),
            if (status.profiles.isNotEmpty)
              _kv(c, 'Profiles', status.profiles.join(', '), c.text2),
            if (!status.canSignIn) ...[
              const SizedBox(height: 10),
              Text(
                'This dashboard offers neither a username/password provider '
                'nor browser sign-in. Update Hermes, or configure the '
                'username/password provider on the server.',
                style: NgType.bodySmall.copyWith(color: c.danger),
              ),
            ] else if (!status.authRequired &&
                !isPrivateHost(probe.url.host)) ...[
              const SizedBox(height: 10),
              Text(
                'The auth gate is off on this dashboard. Anyone who can reach '
                'it can use your agent.',
                style: NgType.bodySmall.copyWith(color: c.warning),
              ),
            ],
          ],
        ),
      );
    }
    final (title, body) = switch (probe) {
      ProbeUnreachable(:final reason) => (
        'Couldn\'t reach the dashboard',
        '$reason\n\nCheck the address and port (9119 by default). If the '
            'dashboard isn\'t running yet, run this on the server:\n'
            'hermes dashboard --host 0.0.0.0',
      ),
      ProbeNotHermes(:final httpStatus) => (
        'That isn\'t a Hermes dashboard',
        'Something answered${httpStatus == null ? '' : ' (HTTP $httpStatus)'}, '
            'but not a Hermes dashboard. Use the dashboard\'s address, not the '
            'API server\'s (port 8642).',
      ),
      ProbeAccessBlocked(:final tokenSent, :final httpStatus) => (
        'Cloudflare Access stopped the request',
        tokenSent
            ? 'Cloudflare Access turned down the service token (HTTP '
                  '$httpStatus). Check the Client ID and Secret, and the '
                  'Service Auth policy.'
            : 'Add a Cloudflare Access service token below, then test again.',
      ),
      ProbeClientCertRequired() => (
        'A client certificate is needed',
        'This server asks for a client certificate before it talks. Add the '
            'connection in the classic interface to import the certificate, '
            'then sign in here.',
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
        ? 'This dashboard doesn\'t ask for a sign-in.'
        : password && browser
        ? 'Use the dashboard username and password configured on '
              '${url.display}, or sign in in your browser.'
        : password
        ? 'Use the dashboard username and password configured on '
              '${url.display}.'
        : 'Sign in to ${url.display} in your browser, with the account its '
              'dashboard uses.';
    return ListView(
      key: const ValueKey('signin'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: NgPill(
            'Gateway ${url.display}',
            icon: Icons.dns_outlined,
            onTap: () => setState(() => _signInStep = false),
          ),
        ),
        const SizedBox(height: 18),
        Text('Sign in', style: NgType.display.copyWith(color: c.text)),
        const SizedBox(height: 10),
        Text(detail, style: NgType.body.copyWith(color: c.text2)),
        if (status.profiles.length > 1) ...[
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'Profile',
              style: NgType.label.copyWith(color: c.text2),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Server default'),
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
            label: 'Continue',
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
                    label: 'Username',
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  NgField(
                    controller: _password,
                    label: 'Password',
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
                  ? 'Signing in…'
                  : 'Sign in',
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
                  ? 'Waiting for the browser…'
                  : 'Sign in with browser',
              icon: Icons.open_in_browser,
              onPressed: _signingIn ? null : _browserSignIn,
            )
          else if (browser)
            NgPrimaryButton(
              label: _waitingForBrowser
                  ? 'Waiting for the browser…'
                  : 'Sign in with browser',
              icon: Icons.open_in_browser,
              busy: _waitingForBrowser,
              onPressed: _signingIn ? null : _browserSignIn,
            ),
          if (_waitingForBrowser) ...[
            const SizedBox(height: 12),
            Text(
              'Finish signing in on the page that opened. Hermes comes back by '
              'itself when you\'re done.',
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
          child: const Text('Use a different gateway'),
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
              'Which address do I use?',
              style: NgType.title.copyWith(color: c.text),
            ),
            const SizedBox(height: 18),
            item(
              Icons.wifi,
              'Same Wi-Fi or local network',
              'Use the server\'s local address and port, like '
                  '192.168.1.20:9119. Start the dashboard with --host 0.0.0.0 '
                  'so other devices can reach it.',
            ),
            item(
              Icons.hub_outlined,
              'Tailscale',
              'Turn on Tailscale on this phone and use the server\'s Tailscale '
                  'address, like 100.64.0.1:9119 or its .ts.net name. Works '
                  'away from home too.',
            ),
            item(
              Icons.lock_outline,
              'HTTPS',
              'Use your https:// address when the dashboard sits behind a '
                  'proxy with a certificate. The proxy must also pass '
                  'WebSocket upgrades on /api/ws.',
            ),
            const SizedBox(height: 4),
            Text(
              'Start the dashboard on the server:',
              style: NgType.label.copyWith(color: c.text2),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                Clipboard.setData(
                  const ClipboardData(text: 'hermes dashboard --host 0.0.0.0'),
                );
                ngToast(context, 'Copied');
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

class _DiscoverySheet extends StatefulWidget {
  const _DiscoverySheet();

  @override
  State<_DiscoverySheet> createState() => _DiscoverySheetState();
}

class _DiscoverySheetState extends State<_DiscoverySheet> {
  final _service = LanDiscoveryService.dashboards();
  List<DiscoveredHermesServer>? _found;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _found = null;
      _error = null;
    });
    try {
      final found = await _service.discover();
      if (mounted) setState(() => _found = found);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _service.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NgColors.of(context);
    final found = _found;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Find on my network',
              style: NgType.title.copyWith(color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              'Looks for Hermes dashboards on port 9119 on this Wi-Fi network.',
              style: NgType.bodySmall.copyWith(color: c.text3),
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
                'No dashboards answered. Start one with hermes dashboard '
                '--host 0.0.0.0, or type its address.',
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
            if (found != null) ...[
              const SizedBox(height: 12),
              NgSecondaryButton(label: 'Search again', onPressed: _run),
            ],
          ],
        ),
      ),
    );
  }
}
