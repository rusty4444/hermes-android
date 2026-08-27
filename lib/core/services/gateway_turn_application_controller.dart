import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/connection.dart';
import 'desktop_gateway_client.dart';
import 'gateway_turn_coordinator.dart';
import 'gateway_turn_recovery.dart';

typedef GatewayTurnApplicationSessionFactory =
    GatewayTurnApplicationSession Function(SavedConnection connection);

/// Connection-scoped recovery surface retained by the application owner.
abstract interface class GatewayTurnApplicationSession {
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  });

  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  });

  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  });

  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  });

  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  });

  Future<void> close();

  set onTurnSettled(GatewayTurnSettledCallback? callback);
}

/// Owns recovery registries above screen and Navigator lifetimes.
///
/// A screen may detach its callbacks when disposed, but this owner keeps the
/// coordinator, socket, and process-local recovery authority alive until the
/// whole application is disposed. A changed connection configuration receives
/// a distinct scope without retaining plaintext credentials in the key.
class GatewayTurnApplicationController {
  final GatewayTurnApplicationSessionFactory _sessionFactory;
  final Map<String, GatewayTurnApplicationSession> _sessions = {};
  bool _closed = false;

  GatewayTurnApplicationController({
    GatewayTurnApplicationSessionFactory? sessionFactory,
  }) : _sessionFactory =
           sessionFactory ??
           ((connection) => _CoordinatorGatewayTurnApplicationSession(
             DesktopGatewayClient.fromConnection(connection),
           ));

  GatewayTurnApplicationSession sessionFor(SavedConnection connection) {
    if (_closed) throw StateError('Gateway turn application owner is closed.');
    final key = _connectionScopeKey(connection);
    return _sessions.putIfAbsent(key, () => _sessionFactory(connection));
  }

  int get retainedSessionCount => _sessions.length;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final sessions = _sessions.values.toList(growable: false);
    _sessions.clear();
    Object? firstError;
    StackTrace? firstStack;
    for (final session in sessions) {
      try {
        await session.close();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}

class _CoordinatorGatewayTurnApplicationSession
    implements GatewayTurnApplicationSession {
  final DesktopGatewayClient _client;
  late final GatewayTurnCoordinatorRegistry _registry = _client
      .enableTurnRecoveryCoordinator();
  bool _closed = false;

  _CoordinatorGatewayTurnApplicationSession(this._client);

  void _requireOpen() {
    if (_closed) {
      throw StateError('Gateway turn application session is closed.');
    }
  }

  @override
  Future<GatewayTurnAttachmentReceipt> stageAttachment({
    required String localSessionId,
    required String clientAttachmentId,
    required String name,
    required String dataUrl,
    required int byteLength,
    required String mediaType,
    required GatewayTurnAttachmentKind kind,
  }) {
    _requireOpen();
    return _registry.stageAttachment(
      localSessionId: localSessionId,
      clientAttachmentId: clientAttachmentId,
      name: name,
      dataUrl: dataUrl,
      byteLength: byteLength,
      mediaType: mediaType,
      kind: kind,
    );
  }

  @override
  Future<void> detachAttachments({
    required String localSessionId,
    required Iterable<GatewayTurnAttachmentReceipt> attachments,
  }) {
    _requireOpen();
    return _registry.detachAttachments(
      localSessionId: localSessionId,
      attachments: attachments,
    );
  }

  @override
  Future<GatewayTurnRecoveryState> submit({
    required String localSessionId,
    required String text,
    List<GatewayTurnAttachmentReceipt> attachments = const [],
    GatewayTurnStateCallback? onState,
  }) {
    _requireOpen();
    return _registry.submit(
      localSessionId: localSessionId,
      text: text,
      attachments: attachments,
      onState: onState,
    );
  }

  @override
  Future<List<GatewayTurnRecoveryState>> recoverPending(
    String localSessionId, {
    GatewayTurnStateCallback? onState,
  }) {
    _requireOpen();
    return _registry.recoverPending(localSessionId, onState: onState);
  }

  @override
  Future<GatewayTurnRecoveryState> interrupt({
    required String localSessionId,
    required String clientTurnId,
  }) {
    _requireOpen();
    return _registry.interrupt(
      localSessionId: localSessionId,
      clientTurnId: clientTurnId,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _registry.closeAll();
    } finally {
      _client.close();
    }
  }

  @override
  set onTurnSettled(GatewayTurnSettledCallback? callback) {
    _registry.onTurnSettled = callback;
  }
}

String _connectionScopeKey(SavedConnection connection) {
  final credentialDigest = sha256
      .convert(
        utf8.encode(
          '${connection.apiKey}\u0000'
          '${connection.dashboardPassword ?? ''}\u0000'
          '${connection.mtlsCertificateAlias ?? ''}',
        ),
      )
      .toString();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'id': connection.id,
            'desktop_gateway_url': connection.desktopGatewayUrl,
            'dashboard_username': connection.dashboardUsername,
            'dashboard_prefix': connection.dashboardPrefix,
            'dashboard_port': connection.dashboardPort,
            'dashboard_proxied': connection.dashboardProxied,
            'mtls_enabled': connection.mtlsEnabled,
            'credential_digest': credentialDigest,
          }),
        ),
      )
      .toString();
}
