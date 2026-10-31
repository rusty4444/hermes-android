import 'package:uuid/uuid.dart';

import '../models/connection.dart';
import 'connection_mutation_barrier.dart';
import 'mobile_push_service.dart';

/// Client-local provenance, not server authorization. Provenance stores only
/// the application's complete, secret-hashed binding; dispatch owners retain
/// their existing credentials, never copies in payloads or approval metadata.
class NotificationApprovalAuthority {
  NotificationApprovalAuthority._(
    this.connectionId,
    this.accountBinding,
    this.mutation,
    this.owner,
    this._ownerIsCurrent,
    this._refresh,
  );

  static final _process = const Uuid().v4();
  static final _mutations = Expando<String>();
  static final _originPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:(?:initial|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
  );
  static String _originMutation(String id) {
    final epoch = ConnectionMutationBarrier.capture(id);
    return '$_process:${epoch == null ? 'initial' : (_mutations[epoch] ??= const Uuid().v4())}';
  }

  static Map<String, String> origin(SavedConnection connection) => {
    'approvalAccount': MobilePushService.binding(connection),
    'approvalMutation': _originMutation(connection.id),
  };

  static NotificationApprovalAuthority? capture({
    required SavedConnection connection,
    required String? accountBinding,
    required String? originMutation,
    required Object owner,
    required bool Function() ownerIsCurrent,
    required Future<bool> Function() refresh,
  }) {
    final mutation = ConnectionMutationBarrier.capture(connection.id);
    if (!ConnectionMutationBarrier.isCurrent(connection.id, mutation) ||
        accountBinding != MobilePushService.binding(connection) ||
        originMutation == null ||
        !_originPattern.hasMatch(originMutation) ||
        (originMutation.startsWith('$_process:') &&
            originMutation != _originMutation(connection.id))) {
      return null;
    }
    return NotificationApprovalAuthority._(
      connection.id,
      accountBinding!,
      mutation,
      owner,
      ownerIsCurrent,
      refresh,
    );
  }

  final String connectionId;
  final String accountBinding;
  final Object? mutation;
  final Object owner;
  final bool Function() _ownerIsCurrent;
  final Future<bool> Function() _refresh;

  bool get isCurrent =>
      ConnectionMutationBarrier.isCurrent(connectionId, mutation) &&
      _ownerIsCurrent();

  bool isCurrentFor(SavedConnection connection) =>
      isCurrent &&
      connection.id == connectionId &&
      MobilePushService.binding(connection) == accountBinding;

  Future<bool> validate() async => isCurrent && await _refresh() && isCurrent;

  bool sameCapture(NotificationApprovalAuthority other) =>
      connectionId == other.connectionId &&
      accountBinding == other.accountBinding &&
      identical(mutation, other.mutation) &&
      identical(owner, other.owner);
}
