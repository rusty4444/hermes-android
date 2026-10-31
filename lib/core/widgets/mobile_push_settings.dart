import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connection_manager.dart';
import '../services/mobile_push_service.dart';
import '../services/notification_prefs.dart';
import 'markdown_link_handler.dart';

/// Explicit opt-in, deliberately separate from local notification preferences.
class MobilePushSettings extends StatefulWidget {
  const MobilePushSettings({
    required this.connection,
    required this.connectionManager,
    this.service,
    super.key,
  });
  final SavedConnection connection;
  final ConnectionManager connectionManager;
  final MobilePushService? service;
  @override
  State<MobilePushSettings> createState() => _MobilePushSettingsState();
}

class _MobilePushSettingsState extends State<MobilePushSettings> {
  static const _serverSetupGuide =
      'https://github.com/rusty4444/hermes-android/blob/main/docs/mobile-push-server.md'
      '#operator-installation-not-performed-by-this-implementation';
  late final MobilePushService service =
      widget.service ?? MobilePushService.shared;
  List<Map<String, dynamic>> transports = [];
  String? distributor;
  bool ready = false;
  bool busy = false;
  int operation = 0;
  String? message;
  MobilePushAvailability? availability;
  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() => availability = null);
  }

  @override
  void didUpdateWidget(covariant MobilePushSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (MobilePushService.binding(oldWidget.connection) !=
        MobilePushService.binding(widget.connection)) {
      ++operation;
      busy = false;
      message = null;
      availability = null;
    }
  }

  Future<void> _load() async {
    try {
      await service.initialize(widget.connectionManager);
      if (!mounted) return;
      final options = await service.transportOptions();
      if (!mounted) return;
      setState(() {
        transports = options;
        ready = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          ready = true;
          message = 'Unable to read Android push availability. Retry below.';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final ticket = ++operation;
    setState(() {
      busy = true;
      message = null;
      availability = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && ticket == operation) {
        setState(
          () => message =
              service.error ??
              'Push setup failed. Check Android permission, server authorization and transport, then retry.',
        );
      }
    } finally {
      if (mounted && ticket == operation) setState(() => busy = false);
    }
  }

  Future<void> _refresh() async {
    final ticket = operation;
    final connection = widget.connection;
    final fingerprint = MobilePushService.binding(connection);
    bool current() =>
        mounted &&
        ticket == operation &&
        MobilePushService.binding(widget.connection) == fingerprint;
    await _load();
    if (!current()) return;
    if (service.enabled) {
      await service.retry();
    } else {
      await service.refresh();
      if (!current()) return;
      final result = await service.checkAvailability(connection);
      if (!current()) return;
      setState(() => availability = result);
    }
  }

  String? _boundConnectionLabel(String boundId) {
    if (boundId.isEmpty) return null;
    final raw = widget.connectionManager
        .getConnections()
        .where((c) => c.id == boundId)
        .firstOrNull
        ?.label
        .trim();
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  @override
  void dispose() {
    ++operation;
    service.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!service.supported) return const SizedBox.shrink();
    final on = service.enabled || service.enabling;
    final boundId = service.enabling
        ? service.pendingConnectionId
        : service.connectionId;
    final another = on && boundId != widget.connection.id;
    final boundLabel = another ? _boundConnectionLabel(boundId) : null;
    final rawStatus = availability?.status ?? service.status;
    final statusText = another
        ? 'Status: Bound to ${boundLabel ?? 'another saved connection'} '
              '(not active for ${widget.connection.label}; handshake: $rawStatus)'
        : 'Status: $rawStatus';
    return ValueListenableBuilder<NotificationPrefs>(
      valueListenable: notificationPrefs,
      builder: (context, prefs, _) => Card(
        key: const Key('mobile-push-card'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                identifier: 'mobile-push-switch',
                child: SwitchListTile(
                  key: const Key('mobile-push-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Background notifications'),
                  subtitle: Text(
                    another
                        ? 'Bound to ${boundLabel ?? 'another saved connection'} '
                              '— revoke that binding below before enabling for ${widget.connection.label}'
                        : 'Private server activity for ${widget.connection.label}',
                  ),
                  value: on && !another,
                  // Opt-out stays actionable through capabilities, permission, native
                  // registration and HTTP. It must never wait for _run's old future.
                  onChanged: another || (!on && (!ready || busy))
                      ? null
                      : (value) => _run(
                          value
                              ? () => service.enableAutomatic(
                                  widget.connection,
                                  distributor: distributor,
                                )
                              : service.disable,
                        ),
                ),
              ),
              Text(statusText, key: const Key('mobile-push-status')),
              if (busy) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (another) ...[
                const SizedBox(height: 8),
                Text(
                  boundLabel != null
                      ? 'Bound to another saved connection ($boundLabel). Disable and revoke that binding before enabling for this connection.'
                      : 'Bound to another saved connection. Disable and revoke that binding before enabling for this connection.',
                  key: const Key('mobile-push-another-warning'),
                ),
              ],
              if (service.enabled && !another && !prefs.enabled) ...[
                const SizedBox(height: 8),
                const Text(
                  'Local notifications are turned off above. Background notification consent is unchanged, but ordinary background activity hints are muted until "Enable notifications" is turned on.',
                  key: Key('mobile-push-local-mute-warning'),
                ),
              ],
              if (service.enabled &&
                  !another &&
                  service.sessionScope == 'explicit') ...[
                const SizedBox(height: 8),
                Text(
                  'Legacy subscription: ${service.sessionIds.length} selected session(s) only. It will not expand automatically. Turn off, then on to opt in to server-authorized sessions.',
                ),
              ],
              if (service.enabled &&
                  !another &&
                  service.sessionScope == 'authorized') ...[
                const SizedBox(height: 8),
                const Text(
                  'Bound only to this saved connection and profile. Session access follows current server authorization.',
                ),
              ],
              if (service.pendingRevocations > 0) ...[
                const SizedBox(height: 8),
                const Text(
                  'Server revocation pending. Local delivery is off; retry while the original saved login is available.',
                  key: Key('mobile-push-revocation-pending'),
                ),
              ],
              if (message ?? availability?.error ?? service.error
                  case final String text) ...[
                const SizedBox(height: 8),
                Text(
                  text,
                  key: const Key('mobile-push-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    key: const Key('mobile-push-refresh-retry'),
                    onPressed: busy || !ready ? null : () => _run(_refresh),
                    child: const Text('Refresh / retry'),
                  ),
                  if (on)
                    TextButton(
                      key: const Key('mobile-push-disable-revoke'),
                      onPressed: () => _run(service.disable),
                      child: Text(
                        another
                            ? 'Disable and revoke ${boundLabel ?? 'other connection'}'
                            : 'Disable and revoke',
                      ),
                    ),
                ],
              ),
              const Text(
                'Refresh / retry rechecks availability after server setup; it cannot install the companion. Enabling notifications remains a separate choice.',
              ),
              const Text(
                'Background notifications require a separately installed and enabled server-side mobile-push companion. Android cannot install it. Updating the APK alone does not set up the server.',
              ),
              TextButton.icon(
                onPressed: () => openMarkdownWebLink(context, _serverSetupGuide),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Server setup guide'),
              ),
              const Text(
                'Enable to request Android notification permission and share this installation’s endpoint and encryption keys with this server. Encrypted activity hints contain no chat content. Only sessions authorized by your server login are included.',
              ),
              const Text(
                'Built-in delivery uses Google’s push transport and needs Google Play Services, but includes no Firebase SDK. An optional UnifiedPush distributor can be used instead. Delivery is best-effort; reopen Hermes to reconcile.',
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Advanced transport'),
                children: [
                  const Text(
                    'Automatic preserves an existing distributor choice, otherwise uses built-in Google delivery when available. Disable before changing transport.',
                  ),
                  DropdownButtonFormField<String>(
                    key: ValueKey(distributor),
                    initialValue: distributor ?? 'automatic',
                    decoration: const InputDecoration(
                      labelText: 'Push transport',
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: 'automatic',
                        child: Text('Automatic (recommended)'),
                      ),
                      if (distributor != null &&
                          !transports.any(
                            (option) => option['id'] == distributor,
                          ))
                        DropdownMenuItem(
                          value: distributor,
                          enabled: false,
                          child: const Text(
                            'Selected distributor (unavailable)',
                          ),
                        ),
                      for (final option in transports)
                        DropdownMenuItem(
                          value: option['id'] as String,
                          child: Text(
                            option['label'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: on || busy
                        ? null
                        : (value) => setState(
                            () => distributor = value == 'automatic'
                                ? null
                                : value,
                          ),
                  ),
                  if (transports.isEmpty)
                    const Text(
                      'No available transport detected. Built-in delivery needs Google Play Services; without it, install and configure a UnifiedPush distributor, then refresh.',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
