import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'connection_manager.dart';
import 'connection_mutation_barrier.dart';
import 'mobile_push_api.dart';
import 'notification_prefs.dart';

/// A verified event route, not a URL or approval. Recheck [isRouteCurrent] after
/// any asynchronous session lookup, immediately before navigating.
class MobilePushRoute {
  const MobilePushRoute(
    this.connection,
    this.sessionId,
    this.eventId,
    this.authority,
  );
  final SavedConnection connection;
  final String sessionId;
  final String eventId;
  final Map<String, dynamic> authority;
}

/// A read-only diagnosis, owned by its caller rather than shared consent state.
class MobilePushAvailability {
  const MobilePushAvailability._(this.status, this.error);
  final String status;
  final String? error;
}

/// Optional, one explicitly selected saved connection per Android installation.
/// Native encrypted storage is the source of truth. Startup never requests
/// permission, registers a distributor, or blocks credential hydration.
class MobilePushService extends ChangeNotifier with WidgetsBindingObserver {
  MobilePushService({
    MethodChannel? channel,
    DashboardClient Function(SavedConnection)? clientFactory,
    bool? supported,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _clientFactory = clientFactory ?? _dashboard,
       supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  static const channelName = 'com.hermesagent.hermes_android/mobile_push';
  static final shared = MobilePushService();
  final MethodChannel _channel;
  final DashboardClient Function(SavedConnection) _clientFactory;
  final bool supported;
  ConnectionManager? _manager;
  Future<void>? _initialization;
  Map<String, dynamic> _state = {};
  Map<String, dynamic>? _tap;
  Future<void>? _flight;
  bool _dirty = false;
  bool _closed = false;
  int _epoch = 0;
  String? _enablingConnection;
  bool get enabling => _enablingConnection != null;
  String get pendingConnectionId => _enablingConnection ?? '';
  String status = 'Off';
  String? error;
  List<Map<String, dynamic>> events = [];
  String get connectionId => _state['connection'] as String? ?? '';
  bool get enabled => _state['enabled'] == true;
  bool get active => enabled && _state['active'] == true;
  String get sessionScope => _state['session_scope'] as String? ?? 'explicit';
  List<String> get sessionIds =>
      List<String>.from(_state['sessions'] as List? ?? []);
  bool get hasPendingTap => _tap != null;
  int get pendingRevocations => (_state['revocations'] as List? ?? []).length;

  static DashboardClient _dashboard(SavedConnection c) =>
      DashboardClient.fromConnection(c);
  static String binding(SavedConnection c) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            ...c.toMap(),
            'api_key': c.apiKey,
            'dashboard_password': c.dashboardPassword,
            if (c.clientCertificate != null)
              'client_key_password': c.clientCertificate!.privateKeyPassword,
          }),
        ),
      )
      .toString();
  SavedConnection? _connection(String id) =>
      _manager?.getConnections().where((c) => c.id == id).firstOrNull;

  Future<bool> _refreshCredentialCache(String id) async {
    final manager = _manager;
    final mutation = ConnectionMutationBarrier.capture(id);
    if (!ConnectionMutationBarrier.isCurrent(id, mutation)) return false;
    await manager?.refreshConnectionCredentials(id);
    return !_closed &&
        identical(manager, _manager) &&
        ConnectionMutationBarrier.isCurrent(id, mutation);
  }

  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic>? args,
  ]) async => Map<String, dynamic>.from(
    await _channel.invokeMapMethod<String, dynamic>(method, args) ?? {},
  );

  Future<void> initialize(ConnectionManager manager) {
    _manager = manager;
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (!supported) {
      status = 'Android only';
      return;
    }
    // Do not briefly overwrite a persisted disabled native preference with
    // Dart's startup defaults while the root's preference hydration is pending.
    await NotificationPrefsStore.load();
    if (_closed) return;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await refresh();
    });
    notificationPrefs.addListener(_preferencesChanged);
    await syncPreferences(notificationPrefs.value);
    await refresh();
  }

  void _preferencesChanged() {
    unawaited(syncPreferences(notificationPrefs.value));
  }

  /// Explicit parity hook for the app's current master/per-kind preferences.
  /// Await this when settings change so headless delivery uses the same policy.
  /// Consent is separately revoked immediately by [disable], not by a toggle
  /// that only suppresses local notifications.
  Future<void> syncPreferences(NotificationPrefs prefs) async {
    if (!supported || _closed) return;
    try {
      await _call('preferences', {
        'master': prefs.enabled,
        'kinds': [
          if (prefs.kindEnabled(HermesNotificationKind.turnDone)) 'turn_done',
          if (prefs.kindEnabled(HermesNotificationKind.turnError)) 'turn_error',
          if (prefs.kindEnabled(HermesNotificationKind.input)) ...[
            'input',
            'input_resolved',
          ],
        ],
      });
    } catch (_) {
      error = 'Native notification preferences could not be synchronized.';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<List<String>> distributors() async {
    if (!supported) return [];
    return List<String>.from(
      await _channel.invokeListMethod<String>('distributors') ?? [],
    );
  }

  Future<List<Map<String, dynamic>>> transportOptions() async {
    if (!supported) return [];
    final options =
        await _channel.invokeListMethod<dynamic>('transportOptions') ?? [];
    return options
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  /// Explicit consent to the server's continuously authorized sessions. Never
  /// broadens persisted legacy allowlists or enrolls on startup.
  Future<void> enableAutomatic(
    SavedConnection connection, {
    String? distributor,
  }) => _enable(connection, distributor ?? 'automatic', const [], 'authorized');

  Future<void> enable(
    SavedConnection connection,
    String distributor,
    List<String> sessions,
  ) async {
    final List<String> ids;
    try {
      ids = MobilePushApi.validateSessionIds(sessions);
    } on StateError catch (e) {
      // The settings surface reads this safe, local validation message rather
      // than exposing platform/server exception bodies that may contain secrets.
      error = e.message;
      if (!_closed) notifyListeners();
      rethrow;
    }
    return _enable(connection, distributor, ids, 'explicit');
  }

  Future<void> _enable(
    SavedConnection connection,
    String distributor,
    List<String> ids,
    String scope,
  ) async {
    if (!supported || _manager == null) {
      throw StateError('Choose a saved connection on Android first.');
    }
    final epoch = ++_epoch;
    final mutationEpoch = ConnectionMutationBarrier.capture(connection.id);
    final fingerprint = binding(connection);
    bool current() =>
        !_closed &&
        epoch == _epoch &&
        ConnectionMutationBarrier.isCurrent(connection.id, mutationEpoch) &&
        _connection(connection.id) != null &&
        binding(_connection(connection.id)!) == fingerprint;
    // A new opt-in started during an edit must not queue old consent to run
    // after that edit, even if the saved metadata still looks unchanged.
    if (_closed ||
        !ConnectionMutationBarrier.isCurrent(connection.id, mutationEpoch)) {
      return;
    }
    _enablingConnection = connection.id;
    final client = _clientFactory(connection);
    error = null;
    status = 'Checking server authorization';
    notifyListeners();
    try {
      if (!await _refreshCredentialCache(connection.id) || !current()) return;
      await _manager!.finishPendingMobilePushChanges();
      if (!current()) return;
      final ticket = await _call('connectionFence', {
        'connection': connection.id,
      });
      // A replacement engine may hydrate before abandoned native writes drain.
      // This ticket is unavailable until the engine-owned drain completes. Now
      // refresh metadata/secrets without waiting behind an unrelated live list
      // owner. A subsequent BEGIN still invalidates this exact enable ticket.
      await _manager!.refreshMobilePushBinding(connection.id);
      if (!current()) return;
      final caps = await MobilePushApi(
        client,
      ).capabilities(authorized: scope == 'authorized');
      if (!current()) return;
      final permission =
          await _channel.invokeMethod<bool>('permission') == true;
      if (!current()) return;
      if (!permission) {
        throw StateError(
          'Allow Android notifications before enabling mobile push.',
        );
      }
      final prefs = notificationPrefs.value;
      final state = await _call('enable', {
        'connection_fence': ticket['connection_fence'],
        'connection': connection.id,
        'connection_metadata': _manager!.mobilePushConsentMetadata(
          connection.id,
        ),
        'binding': fingerprint,
        'distributor': distributor,
        'sessions': ids,
        'session_scope': scope,
        'vapid': caps['vapid_public_key'],
        'master': prefs.enabled,
        'kinds': [
          if (prefs.kindEnabled(HermesNotificationKind.turnDone)) 'turn_done',
          if (prefs.kindEnabled(HermesNotificationKind.turnError)) 'turn_error',
          if (prefs.kindEnabled(HermesNotificationKind.input)) ...[
            'input',
            'input_resolved',
          ],
        ],
      });
      if (!current()) return;
      _state = state;
    } catch (e) {
      if (current()) {
        // A connector error can occur after native consent was durably stored.
        // Reflect that authority so Disable is still visible and effective.
        try {
          final live = await _call('snapshot');
          if (current()) _state = live;
        } catch (_) {
          /* preserve original, non-secret error below */
        }
      }
      if (current()) {
        status = 'Error';
        error = _message(e);
        notifyListeners();
      }
      rethrow;
    } finally {
      client.close();
      if (epoch == _epoch) {
        _enablingConnection = null;
        if (!_closed) notifyListeners();
      }
    }
    if (current()) await refresh();
  }

  /// Invalidates in-flight Dart callbacks synchronously; native consent, queued
  /// hints and notifications are revoked before attempting authenticated DELETE.
  Future<void> disable() async {
    ++_epoch;
    _enablingConnection = null;
    _tap = null;
    events = [];
    status = 'Off';
    error = null;
    notifyListeners();
    if (!supported || _closed) return;
    try {
      _state = await _call('disable');
    } catch (_) {
      error =
          'Could not persist revocation. Retry disabling before leaving the app.';
      notifyListeners();
      rethrow;
    }
    await refresh();
  }

  /// Read-only server check while off: never requests permission or registers.
  /// Results must be fenced by the caller's lifetime/operation/connection. They
  /// never change shared consent status/errors or invalidate its epoch.
  Future<MobilePushAvailability?> checkAvailability(
    SavedConnection connection,
  ) async {
    if (!supported || _closed || enabled || enabling) return null;
    final epoch = _epoch;
    final fingerprint = binding(connection);
    final mutation = ConnectionMutationBarrier.capture(connection.id);
    bool current() =>
        !_closed &&
        epoch == _epoch &&
        !enabled &&
        !enabling &&
        ConnectionMutationBarrier.isCurrent(connection.id, mutation) &&
        _connection(connection.id) != null &&
        binding(_connection(connection.id)!) == fingerprint;
    final client = _clientFactory(connection);
    try {
      if (!await _refreshCredentialCache(connection.id) || !current()) {
        return null;
      }
      await MobilePushApi(client).capabilities(authorized: true);
      return current()
          ? const MobilePushAvailability._('Off; server API ready', null)
          : null;
    } catch (e) {
      return current() ? MobilePushAvailability._('Error', _message(e)) : null;
    } finally {
      client.close();
    }
  }

  Future<void> retry() async {
    if (!supported || _closed) return;
    final epoch = _epoch;
    try {
      if (enabled && (_state['endpoint'] == null || _state['error'] != null)) {
        await _call('retryDistributor');
      }
      await refresh();
    } catch (e) {
      if (!_closed && epoch == _epoch) {
        error = _message(e);
        status = 'Error';
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Single flight with a dirty tail: a challenge arriving during PUT is not
  /// lost, and disable/renewal invalidates every subsequent async continuation.
  Future<void> refresh() {
    if (!supported || _closed) return Future.value();
    _dirty = true;
    if (_flight != null) return _flight!;
    final flight = _drain();
    _flight = flight;
    flight.whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
      if (_dirty && !_closed) unawaited(refresh());
    }).ignore();
    return flight;
  }

  Future<void> _drain() async {
    while (_dirty && !_closed) {
      _dirty = false;
      final epoch = _epoch;
      try {
        await _refresh();
      } catch (e) {
        // An uncertain handshake is journalled natively. Do not let callbacks
        // queued by its challenge cause a tight rotate/PUT/fail loop. A later
        // foreground/manual refresh recovers it; a newer consent epoch still
        // gets its queued pass (e.g. disable while the old request failed).
        if (epoch != _epoch) continue;
        if (_dirty && !_closed) {
          try {
            final live = await _call('snapshot');
            // Do hand off to a newer native authority (endpoint renewal or
            // revocation), rather than suppressing its queued foreground pass.
            if (epoch != _epoch ||
                live['nonce'] != _state['nonce'] ||
                live['revision'] != _state['revision'] ||
                live['enabled'] != _state['enabled']) {
              continue;
            }
          } catch (_) {
            /* Keep the durable intent for a later explicit retry. */
          }
        }
        _dirty = false;
        if (!_closed && epoch == _epoch) {
          error = _message(e);
          status = 'Error';
          notifyListeners();
        }
      }
    }
  }

  Future<bool> _current(Map<String, dynamic> expected, int epoch) async {
    if (_closed || epoch != _epoch) return false;
    final live = await _call('snapshot');
    if (_closed || epoch != _epoch) return false;
    if (!await _refreshCredentialCache(
          expected['connection'] as String? ?? '',
        ) ||
        _closed ||
        epoch != _epoch) {
      return false;
    }
    if (live['enabled'] != true) return false;
    try {
      MobilePushApi.sessionScope(live);
    } on FormatException {
      return false;
    }
    final c = _connection(expected['connection'] as String? ?? '');
    return c != null &&
        !ConnectionMutationBarrier.isPending(c.id) &&
        binding(c) == expected['binding'] &&
        live['enabled'] == true &&
        live['installation'] == expected['installation'] &&
        live['nonce'] == expected['nonce'] &&
        live['generation'] == expected['generation'] &&
        (live['session_scope'] ?? 'explicit') ==
            (expected['session_scope'] ?? 'explicit') &&
        live['revision'] == expected['revision'];
  }

  Future<void> _refresh() async {
    final epoch = _epoch;
    final snapshot = await _call('snapshot');
    if (_closed || epoch != _epoch) return;
    _state = snapshot;
    // Retry recorded failed revokes, but never against changed credentials or a
    // different origin/profile. Such records remain visibly pending.
    for (final raw in snapshot['revocations'] as List? ?? []) {
      final item = Map<String, dynamic>.from(raw as Map);
      if (!await _refreshCredentialCache(item['connection'] as String)) {
        continue;
      }
      if (_closed || epoch != _epoch) return;
      final c = _connection(item['connection'] as String);
      if (c == null ||
          ConnectionMutationBarrier.isPending(c.id) ||
          binding(c) != item['binding']) {
        continue;
      }
      final client = _clientFactory(c);
      try {
        await MobilePushApi(client).revoke(item['installation'] as String);
        if (_closed || epoch != _epoch) return;
        final revoked = await _call('revoked', {
          'revokedInstallation': item['installation'],
        });
        if (_closed || epoch != _epoch) return;
        _state = revoked;
      } catch (_) {
        /* durable record retained for next foreground retry */
      } finally {
        client.close();
      }
    }
    if (!enabled) {
      status = pendingRevocations > 0
          ? 'Off; server revocation pending'
          : 'Off';
      notifyListeners();
      return;
    }
    if (!await _refreshCredentialCache(connectionId)) return;
    if (_closed || epoch != _epoch) return;
    final connection = _connection(connectionId);
    if (connection != null &&
        ConnectionMutationBarrier.isPending(connection.id)) {
      return;
    }
    if (connection == null || binding(connection) != snapshot['binding']) {
      // A removed/edited account cannot retain authority from a former login.
      ++_epoch;
      _tap = null;
      _state = await _call('disable');
      status = 'Off; saved connection changed';
      notifyListeners();
      return;
    }
    final client = _clientFactory(connection);
    final api = MobilePushApi(client);
    var state = snapshot;
    try {
      MobilePushApi.sessionScope(state);
      if (state['error'] != null) throw StateError(state['error'] as String);
      if (state['endpoint'] == null) {
        status = 'Pending distributor endpoint';
        notifyListeners();
        return;
      }
      if (state['active'] != true && _needsRegistrationRecovery(state)) {
        if (!await _current(state, epoch)) return;
        // Atomic native rotation retains ONLY already-consented account/scope
        // and endpoint keys. It invalidates old proofs/taps before any new PUT.
        state = await _call('recoverRegistration', state);
        if (!await _current(state, epoch)) return;
        _state = state;
        _tap = null;
        events = [];
      }
      if (state['generation'] == 0) {
        status = 'Registering';
        notifyListeners();
        if (!await _current(state, epoch)) return;
        // The durable native revision travels in this PUT. The server compares
        // it inside its write transaction, not at request/DNS admission, so a
        // superseded pre-commit handler cannot replace a recovered authority.
        // Write-ahead intent must survive process death after server commit but
        // before the response/generation can reach native encrypted storage.
        state = await _call('beginRegistration', state);
        if (!await _current(state, epoch)) return;
        final response = await api.register(state);
        if (!await _current(state, epoch)) return;
        final generation = response['generation'];
        if (generation is! int ||
            generation <= 0 ||
            response['status'] != 'pending' ||
            response['registration_nonce'] != state['nonce'] ||
            response['registration_revision'] != state['revision']) {
          throw const FormatException('Invalid registration response.');
        }
        state = await _call('generation', {...state, 'generation': generation});
        if (!await _current(state, epoch)) return;
        _state = state;
      }
      if (state['active'] != true) {
        final live = await _call('snapshot');
        if (!await _current(state, epoch)) return;
        final challenges = live['challenges'] as List? ?? [];
        for (final raw in challenges) {
          final hint = Map<String, dynamic>.from(raw as Map);
          if (hint['generation'] != state['generation'] ||
              hint['registration_nonce'] != state['nonce'] ||
              hint['expires_at'] is! int ||
              (hint['expires_at'] as int) <=
                  DateTime.now().millisecondsSinceEpoch ~/ 1000) {
            continue;
          }
          state = await _call('beginConfirmation', state);
          if (!await _current(state, epoch)) return;
          final response = await api.confirm(
            state['installation'] as String,
            state['generation'] as int,
            hint['challenge'] as String,
          );
          if (!await _current(state, epoch)) return;
          if (response['status'] != 'active' ||
              response['generation'] is! int ||
              response['generation'] != state['generation']) {
            throw const FormatException('Server did not confirm activation.');
          }
          state = await _call('activate', state);
          if (!await _current(state, epoch)) return;
          _state = state;
          break;
        }
      }
      status = state['active'] == true
          ? 'Active'
          : 'Pending encrypted challenge (waiting for silent server verification push)';
      error = null;
      if (state['active'] == true) {
        // Discard old routable data before fetching; a bad later page must not
        // leave a previous authenticated reconciliation usable for stale taps.
        events = [];
        final List<Map<String, dynamic>> reconciled;
        try {
          reconciled = await _events(api, state, epoch);
        } catch (_) {
          _tap = null;
          rethrow;
        }
        if (!await _current(state, epoch)) return;
        events = reconciled;
        final rawTap = await _channel.invokeMapMethod<String, dynamic>(
          'takeTap',
        );
        if (!await _current(state, epoch)) return;
        if (rawTap != null) _tap = Map<String, dynamic>.from(rawTap);
      }
      notifyListeners();
    } finally {
      client.close();
    }
  }

  bool _needsRegistrationRecovery(Map<String, dynamic> state) {
    if (state['registration_attempt'] == true ||
        state['confirmation_attempt'] == true) {
      return true;
    }
    if (state['generation'] == 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var hasLiveProof = false;
    for (final raw in state['challenges'] as List? ?? []) {
      final hint = Map<String, dynamic>.from(raw as Map);
      if (hint['generation'] != state['generation'] ||
          hint['registration_nonce'] != state['nonce'] ||
          hint['expires_at'] is! int) {
        continue;
      }
      if ((hint['expires_at'] as int) <= now) return true;
      hasLiveProof = true;
    }
    // A proof may never arrive (or native may discard an already-expired one).
    // The local wait ceiling is durable, not a timer reset by every app launch.
    final until = state['pending_until'];
    if (until is int) return until <= now;
    // Migrate pre-journal pending registrations without discarding a usable
    // encrypted proof. No proof and no deadline otherwise means infinite Pending.
    return !hasLiveProof;
  }

  Future<List<Map<String, dynamic>>> _events(
    MobilePushApi api,
    Map<String, dynamic> state,
    int epoch,
  ) async {
    var cursor = '0';
    final result = <String, Map<String, dynamic>>{};
    final visited = <String>{};
    // Cursor paging, never a latest-100 window used as deletion/completion proof.
    for (var page = 0; page < 100; page++) {
      if (!visited.add(cursor)) {
        throw const FormatException('Event cursor did not advance.');
      }
      final response = await api.events(cursor, state: state);
      if (!await _current(state, epoch)) return [];
      if (response['events'] is! List || response['has_more'] is! bool) {
        throw const FormatException('Invalid events response.');
      }
      for (final raw in response['events'] as List) {
        if (raw is! Map) continue;
        final event = Map<String, dynamic>.from(raw);
        if (!MobilePushApi.validIdentifier(event['event_id'], maxLength: 256) ||
            !MobilePushApi.validIdentifier(event['session_id']) ||
            (MobilePushApi.sessionScope(state) == 'explicit' &&
                !(state['sessions'] as List).contains(event['session_id'])) ||
            !const [
              'turn_done',
              'turn_error',
              'input',
              'input_resolved',
            ].contains(event['kind']) ||
            event['expires_at'] is! num ||
            (event['expires_at'] as num) <=
                DateTime.now().millisecondsSinceEpoch / 1000) {
          continue;
        }
        result[event['event_id'] as String] = event;
      }
      if (response['has_more'] == false) return result.values.toList();
      cursor = '${response['next_cursor']}';
    }
    throw StateError(
      'Event reconciliation incomplete; retry after the server backlog is reduced.',
    );
  }

  /// Called by root on service changes/resume. Resolves only through the
  /// authenticated event feed; no arbitrary URL, message body, or auto-approval.
  Future<MobilePushRoute?> takePendingNotificationRoute() async {
    final tap = _tap;
    _tap = null;
    if (tap == null) return null;
    final state = Map<String, dynamic>.from(_state);
    final epoch = _epoch;
    if (tap['nonce'] != state['nonce'] ||
        tap['revision'] != state['revision'] ||
        tap['generation'] != state['generation'] ||
        tap['expires_at'] is! num ||
        (tap['expires_at'] as num) <=
            DateTime.now().millisecondsSinceEpoch / 1000 ||
        !await _current(state, epoch)) {
      return null;
    }
    final event = events
        .where((e) => e['event_id'] == tap['event_id'])
        .firstOrNull;
    final connection = _connection(state['connection'] as String);
    if (event == null ||
        connection == null ||
        !notificationPrefs.value.enabled ||
        !_kindEnabled(event['kind'])) {
      return null;
    }
    return MobilePushRoute(
      connection,
      event['session_id'] as String,
      event['event_id'] as String,
      {
        for (final key in [
          'connection',
          'binding',
          'installation',
          'nonce',
          'generation',
          'revision',
          'session_scope',
        ])
          key: state[key],
        'route_kind': event['kind'],
        'route_expires_at': event['expires_at'],
      },
    );
  }

  bool _kindEnabled(Object? kind) => switch (kind) {
    'turn_done' => notificationPrefs.value.kindEnabled(
      HermesNotificationKind.turnDone,
    ),
    'turn_error' => notificationPrefs.value.kindEnabled(
      HermesNotificationKind.turnError,
    ),
    'input' || 'input_resolved' => notificationPrefs.value.kindEnabled(
      HermesNotificationKind.input,
    ),
    _ => false,
  };
  Future<bool> isRouteCurrent(MobilePushRoute route) async {
    final current = await _current(route.authority, _epoch);
    return current &&
        notificationPrefs.value.enabled &&
        _kindEnabled(route.authority['route_kind']) &&
        (route.authority['route_expires_at'] as num) >
            DateTime.now().millisecondsSinceEpoch / 1000;
  }

  static String _message(Object error) {
    if (error is StateError &&
        error.message ==
            'Allow Android notifications before enabling mobile push.') {
      return 'Allow Android notifications in system settings, then retry.';
    }
    if (error is FormatException) {
      return 'The server mobile-push plugin is unavailable, outdated, or returned an invalid subscription response. Ask the operator to update it, then retry.';
    }
    if (error is PlatformException) {
      if (error.code == 'push_transport_unavailable') {
        return 'No push transport is available. Built-in delivery needs working Google Play Services; alternatively install a UnifiedPush distributor and retry.';
      }
      if (error.code == 'push_transport_choice') {
        return 'Several UnifiedPush distributors are available. Choose one in Advanced transport, then retry.';
      }
      if (error.code == 'push_transport_missing') {
        return 'The selected UnifiedPush distributor is unavailable. Restore it or choose another in Advanced transport.';
      }
    }
    if (error is DashboardHttpException) {
      if (error.statusCode == 404) {
        return 'The server mobile-push companion is unavailable. It may be missing or disabled, or this connection may point to the wrong dashboard. Install or enable the companion on the server, check the dashboard connection, then refresh. See Server setup guide above.';
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Server denied mobile push. Ask the operator to authorize this principal and these sessions.';
      }
    }
    // Never surface server/platform exception bodies (endpoint/auth secrets).
    return 'Mobile push is not ready. Check server plugin authorization, distributor and network, then retry.';
  }

  @override
  void dispose() {
    _closed = true;
    ++_epoch;
    notificationPrefs.removeListener(_preferencesChanged);
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
