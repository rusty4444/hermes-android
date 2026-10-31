/// Host-managed device authorization; no provider tokens enter device storage.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/provider_oauth.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';

class ProviderOAuthScreen extends StatefulWidget {
  final SavedConnection connection;
  final DashboardClient? dashboardClient;
  final Future<bool> Function(Uri)? openBrowser;
  const ProviderOAuthScreen({
    required this.connection,
    this.dashboardClient,
    this.openBrowser,
    super.key,
  });
  @override
  State<ProviderOAuthScreen> createState() => _ProviderOAuthScreenState();
}

class _ProviderOAuthScreenState extends State<ProviderOAuthScreen>
    with WidgetsBindingObserver {
  DashboardClient? _client;
  List<OAuthProvider> _providers = const [];
  OAuthDeviceSession? _session;
  OAuthProvider? _provider;
  Future<void>? _starting;
  OAuthDeviceSession? _polling;
  Timer? _pollTimer;
  Timer? _expiryTimer;
  int _generation = 0;
  bool _loading = true;
  bool _busy = false;
  bool _foreground = true;
  String? _unavailable;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  void _connect() {
    try {
      final origin = Uri.parse(
        DesktopGatewayClient.normalizedGatewayBaseUrl(widget.connection),
      );
      _client =
          widget.dashboardClient ??
          DashboardClient(
            host: origin.host,
            port: origin.port,
            useHttps: origin.scheme == 'https',
            pathPrefix: origin.path == '/' ? '' : origin.path,
            proxied: widget.connection.dashboardProxied,
            username: widget.connection.dashboardUsername,
            password: widget.connection.dashboardPassword,
            gatewayProfile: widget.connection.gatewayProfile,
            clientCertificate: widget.connection.clientCertificate,
          );
      _unavailable = _client!.providerOAuthUnavailableReason;
    } catch (_) {
      _unavailable =
          'The selected secure dashboard transport could not be initialized. Check its TLS identity and connection settings.';
    }
    if (_unavailable != null) {
      _loading = false;
    } else {
      unawaited(_loadCatalog());
    }
  }

  @override
  void didUpdateWidget(covariant ProviderOAuthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connection != widget.connection ||
        oldWidget.dashboardClient != widget.dashboardClient) {
      _retire(close: oldWidget.dashboardClient == null);
      _providers = const [];
      _provider = null;
      _message = null;
      _unavailable = null;
      _loading = true;
      _busy = false;
      _connect();
    }
  }

  // Capture the OLD authority. A late start is cancelled before closing its
  // owned client, never via the replacement connection/profile.
  void _retire({required bool close}) {
    _generation++;
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    final client = _client;
    final session = _session;
    final starting = _starting;
    _session = null;
    _starting = null;
    _client = null;
    unawaited(() async {
      if (session != null && client != null) {
        await _cancelHost(client, session.id);
      }
      await starting;
      if (close) client?.close();
    }());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retire(close: widget.dashboardClient == null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _pollTimer?.cancel();
    // Opening the external browser pauses the app: retain the bounded session,
    // but never poll in background or restart authorization on resume.
    if (_foreground && _session != null) _schedulePoll(_generation);
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _loadCatalog() async {
    final generation = _generation;
    try {
      final data = await _client!.getProviderOAuthCatalog();
      final rows = data['providers'];
      if (rows is! List) throw const FormatException('Missing catalog');
      final providers = rows
          .map(
            (row) =>
                OAuthProvider.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      if (!_current(generation)) return;
      setState(() {
        _providers = providers;
        _loading = false;
      });
    } catch (_) {
      if (!_current(generation)) return;
      setState(() {
        _loading = false;
        _unavailable =
            'Provider sign-in is unavailable on this host. Check dashboard authentication and update the host if it does not support provider OAuth.';
      });
    }
  }

  void _start(OAuthProvider provider) {
    if (_busy || _session != null || provider.disabledReason != null) return;
    setState(() {
      _busy = true;
      _message = null;
      _provider = provider;
    });
    final generation = _generation;
    final client = _client!;
    final flight = _startSession(provider, client, generation);
    _starting = flight;
    unawaited(
      flight.whenComplete(() {
        if (identical(_starting, flight)) _starting = null;
      }),
    );
  }

  Future<void> _startSession(
    OAuthProvider provider,
    DashboardClient client,
    int generation,
  ) async {
    String? sessionId;
    try {
      final data = await client.startProviderOAuth(provider.id);
      final rawId = data['session_id'];
      if (rawId is String && OAuthDeviceSession.validSessionId(rawId)) {
        sessionId = rawId;
      }
      if (!_current(generation)) {
        if (sessionId != null) await _cancelHost(client, sessionId);
        return;
      }
      final session = OAuthDeviceSession.fromJson(data);
      setState(() {
        _session = session;
        _busy = false;
      });
      _expiryTimer = Timer(session.lifetime, () {
        if (_current(generation)) {
          unawaited(_finish('Sign-in expired. Start again.', cancel: true));
        }
      });
      _schedulePoll(generation);
    } catch (_) {
      if (sessionId != null) await _cancelHost(client, sessionId);
      if (!_current(generation)) return;
      setState(() {
        _busy = false;
        _message = 'Could not start secure provider sign-in. Please try again.';
      });
    }
  }

  void _schedulePoll(int generation) {
    _pollTimer?.cancel();
    final session = _session;
    if (session == null || !_foreground || identical(_polling, session)) return;
    _pollTimer = Timer(
      session.pollInterval,
      () => unawaited(_poll(generation, session)),
    );
  }

  Future<void> _poll(int generation, OAuthDeviceSession session) async {
    if (!_current(generation) || !identical(_session, session)) return;
    if (identical(_polling, session)) return;
    _polling = session;
    try {
      final data = await _client!.pollProviderOAuth(_provider!.id, session.id);
      if (identical(_polling, session)) _polling = null;
      if (!_current(generation) || !identical(_session, session)) return;
      final status = parseOAuthStatus(data, session.id);
      switch (status) {
        case OAuthLoginStatus.pending:
          _schedulePoll(generation);
        case OAuthLoginStatus.approved:
          await _finish(
            'Signed in on the Hermes host. Refreshing account usage…',
            keepBusy: true,
          );
          if (!_current(generation)) return;
          // Read only: never select a provider/model or change config on login.
          final client = _client!;
          final refreshed = await Future.wait(
            [client.getModelOptions(), client.getModelsAnalytics()].map(
              (read) => read.then((_) => true).catchError((Object _) => false),
            ),
          );
          if (!_current(generation)) return;
          setState(() {
            _message = refreshed.every((ok) => ok)
                ? 'Signed in on the Hermes host. Usage and model inventory refreshed.'
                : 'Signed in on the Hermes host. Usage or inventory refresh failed; refresh it again from Usage.';
          });
          await _loadCatalog();
          if (_current(generation)) {
            setState(() {
              _busy = false;
            });
          }
        case OAuthLoginStatus.denied:
          await _finish('Sign-in was denied. Start again.', cancel: true);
        case OAuthLoginStatus.expired:
          await _finish('Sign-in expired. Start again.', cancel: true);
        case OAuthLoginStatus.cancelled:
          await _finish('Sign-in cancelled.');
        case OAuthLoginStatus.error:
          await _finish(
            'The host could not complete sign-in. Start again.',
            cancel: true,
          );
      }
    } catch (_) {
      if (_current(generation) && identical(_session, session)) {
        await _finish(
          'Could not check sign-in status. Start again.',
          cancel: true,
        );
      }
    } finally {
      if (identical(_polling, session)) _polling = null;
    }
  }

  Future<void> _cancelHost(DashboardClient client, String id) async {
    try {
      await client.cancelProviderOAuth(id);
    } catch (_) {
      // Best effort on a lost transport; host expiry remains authoritative.
    }
  }

  Future<void> _finish(
    String message, {
    bool cancel = false,
    bool keepBusy = false,
  }) async {
    final session = _session;
    final client = _client;
    final generation = _generation;
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    setState(() {
      _session = null;
      _busy = cancel || keepBusy;
      _message = message;
    });
    if (cancel && session != null && client != null) {
      try {
        await client.cancelProviderOAuth(session.id);
      } catch (_) {
        if (_current(generation)) {
          setState(() {
            _message =
                '$message Cancellation could not be confirmed; the host session may continue until it expires.';
          });
        }
      }
    }
    if (_current(generation)) {
      setState(() {
        _busy = keepBusy;
      });
    }
  }

  Future<void> _openBrowser() async {
    final session = _session;
    final generation = _generation;
    if (session == null) return;
    try {
      // Only the provider HTTPS URL goes to the OS browser. No cookie, gateway
      // password, bearer token, client certificate or custom headers are sent.
      final opened =
          await (widget.openBrowser?.call(session.verificationUrl) ??
              launchUrl(
                session.verificationUrl,
                mode: LaunchMode.externalApplication,
              ));
      if (!opened) throw StateError('Browser unavailable');
    } catch (_) {
      if (_current(generation) && identical(_session, session)) {
        setState(() {
          _message =
              'Could not open the external browser. Try again or cancel sign-in.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Provider sign-in')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Sign in with your provider in an external browser. Tokens are stored only on your Hermes host, not this device. Signing in does not select a chat model in this app.',
        ),
        const Text(
          'Some host flows, including Nous free-tier account replacement, may update host defaults. Review your host settings after signing in.',
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_unavailable case final reason?) ...[
          Text(reason),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _loading = true;
                      _unavailable = null;
                    });
                    if (_client == null) {
                      _connect();
                    } else {
                      unawaited(_loadCatalog());
                    }
                  },
            child: const Text('Retry'),
          ),
        ],
        if (_message case final message?) Text(message),
        if (_busy) const LinearProgressIndicator(),
        if (_session case final session?)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Complete sign-in for ${_provider!.name}'),
                  const Text('Enter this temporary code on the provider page:'),
                  Text(session.userCode),
                  Text(session.verificationUrl.host),
                  const Text(
                    'Waiting for approval. This session expires automatically.',
                  ),
                  TextButton(
                    onPressed: _openBrowser,
                    child: const Text('Open provider in browser'),
                  ),
                  TextButton(
                    onPressed: () =>
                        unawaited(_finish('Sign-in cancelled.', cancel: true)),
                    child: const Text('Cancel sign-in'),
                  ),
                ],
              ),
            ),
          ),
        for (final provider in _providers)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    provider.loggedIn
                        ? 'Signed in on host'
                        : 'Not signed in on host',
                  ),
                  if (provider.disabledReason case final reason?) Text(reason),
                  FilledButton(
                    onPressed:
                        _unavailable != null ||
                            _busy ||
                            _session != null ||
                            provider.disabledReason != null
                        ? null
                        : () => _start(provider),
                    child: Text(
                      provider.loggedIn ? 'Sign in again' : 'Sign in',
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
