/// Host-managed device authorization; no provider tokens enter device storage.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/provider_oauth.dart';
import '../l10n/l10n.dart';
import '../services/connection_manager.dart';
import '../services/desktop_gateway_client.dart';

enum _OAuthNotice {
  transportInitFailed,
  httpsRequired,
  authRequired,
  catalogFailed,
  expired,
  startFailed,
  refreshing,
  refreshed,
  refreshFailed,
  denied,
  cancelled,
  hostFailed,
  pollFailed,
  browserFailed,
}

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
  _OAuthNotice? _unavailable;
  _OAuthNotice? _message;
  bool _cancellationUnconfirmed = false;

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
      _unavailable = switch (_client!.providerOAuthUnavailableReason) {
        OAuthTransportUnavailableReason.httpsRequired =>
          _OAuthNotice.httpsRequired,
        OAuthTransportUnavailableReason.authenticationRequired =>
          _OAuthNotice.authRequired,
        null => null,
      };
    } catch (_) {
      _unavailable = _OAuthNotice.transportInitFailed;
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
      _cancellationUnconfirmed = false;
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
        _unavailable = _OAuthNotice.catalogFailed;
      });
    }
  }

  void _start(OAuthProvider provider) {
    if (_busy || _session != null || provider.disabledReason != null) return;
    setState(() {
      _busy = true;
      _message = null;
      _cancellationUnconfirmed = false;
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
          unawaited(_finish(_OAuthNotice.expired, cancel: true));
        }
      });
      _schedulePoll(generation);
    } catch (_) {
      if (sessionId != null) await _cancelHost(client, sessionId);
      if (!_current(generation)) return;
      setState(() {
        _busy = false;
        _message = _OAuthNotice.startFailed;
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
          await _finish(_OAuthNotice.refreshing, keepBusy: true);
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
                ? _OAuthNotice.refreshed
                : _OAuthNotice.refreshFailed;
          });
          await _loadCatalog();
          if (_current(generation)) {
            setState(() {
              _busy = false;
            });
          }
        case OAuthLoginStatus.denied:
          await _finish(_OAuthNotice.denied, cancel: true);
        case OAuthLoginStatus.expired:
          await _finish(_OAuthNotice.expired, cancel: true);
        case OAuthLoginStatus.cancelled:
          await _finish(_OAuthNotice.cancelled);
        case OAuthLoginStatus.error:
          await _finish(_OAuthNotice.hostFailed, cancel: true);
      }
    } catch (_) {
      if (_current(generation) && identical(_session, session)) {
        await _finish(_OAuthNotice.pollFailed, cancel: true);
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
    _OAuthNotice message, {
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
      _cancellationUnconfirmed = false;
    });
    if (cancel && session != null && client != null) {
      try {
        await client.cancelProviderOAuth(session.id);
      } catch (_) {
        if (_current(generation)) {
          setState(() {
            _cancellationUnconfirmed = true;
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
          _message = _OAuthNotice.browserFailed;
          _cancellationUnconfirmed = false;
        });
      }
    }
  }

  String _notice(_OAuthNotice notice) => switch (notice) {
    _OAuthNotice.transportInitFailed =>
      context.l10n.provider_oauth_transport_init_failed,
    _OAuthNotice.httpsRequired => context.l10n.provider_oauth_https_required,
    _OAuthNotice.authRequired => context.l10n.provider_oauth_auth_required,
    _OAuthNotice.catalogFailed => context.l10n.provider_oauth_catalog_failed,
    _OAuthNotice.expired => context.l10n.provider_oauth_expired,
    _OAuthNotice.startFailed => context.l10n.provider_oauth_start_failed,
    _OAuthNotice.refreshing => context.l10n.provider_oauth_refreshing,
    _OAuthNotice.refreshed => context.l10n.provider_oauth_refreshed,
    _OAuthNotice.refreshFailed => context.l10n.provider_oauth_refresh_failed,
    _OAuthNotice.denied => context.l10n.provider_oauth_denied,
    _OAuthNotice.cancelled => context.l10n.provider_oauth_cancelled,
    _OAuthNotice.hostFailed => context.l10n.provider_oauth_host_failed,
    _OAuthNotice.pollFailed => context.l10n.provider_oauth_poll_failed,
    _OAuthNotice.browserFailed => context.l10n.provider_oauth_browser_failed,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.provider_oauth_title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(context.l10n.provider_oauth_intro),
        Text(context.l10n.provider_oauth_defaults_notice),
        if (_loading) const LinearProgressIndicator(),
        if (_unavailable case final reason?) ...[
          Text(_notice(reason)),
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
            child: Text(context.l10n.provider_oauth_retry),
          ),
        ],
        if (_message case final message?)
          Text(
            _cancellationUnconfirmed
                ? context.l10n.provider_oauth_cancellation_unconfirmed(
                    _notice(message),
                  )
                : _notice(message),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_session case final session?)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.provider_oauth_complete(_provider!.name)),
                  Text(context.l10n.provider_oauth_code_instruction),
                  Text(session.userCode),
                  Text(session.verificationUrl.host),
                  Text(context.l10n.provider_oauth_waiting),
                  TextButton(
                    onPressed: _openBrowser,
                    child: Text(context.l10n.provider_oauth_open_browser),
                  ),
                  TextButton(
                    onPressed: () => unawaited(
                      _finish(_OAuthNotice.cancelled, cancel: true),
                    ),
                    child: Text(context.l10n.provider_oauth_cancel),
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
                        ? context.l10n.provider_oauth_signed_in
                        : context.l10n.provider_oauth_signed_out,
                  ),
                  if (provider.disabledReason case final reason?)
                    Text(switch (reason) {
                      OAuthProviderDisabledReason.hostCliRequired =>
                        context.l10n.provider_oauth_cli_required,
                    }),
                  FilledButton(
                    onPressed:
                        _unavailable != null ||
                            _busy ||
                            _session != null ||
                            provider.disabledReason != null
                        ? null
                        : () => _start(provider),
                    child: Text(
                      provider.loggedIn
                          ? context.l10n.provider_oauth_sign_in_again
                          : context.l10n.provider_oauth_sign_in,
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
