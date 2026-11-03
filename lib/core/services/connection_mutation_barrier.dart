/// Process-local ownership of saved-account transactions, shared by every
/// manager/controller. Metadata fingerprints alone cannot see a secure write
/// that has started but not committed. Native consent is separately revoked
/// before those writes and native enable tickets fence already-dispatched IPC.
class ConnectionMutationBarrier {
  ConnectionMutationBarrier._();

  static final _epochs = <String, Object>{};
  static final _pending = <String, int>{};
  static final _listeners = <void Function()>{};

  static void addListener(void Function() listener) => _listeners.add(listener);
  static void removeListener(void Function() listener) =>
      _listeners.remove(listener);

  static Object? capture(String id) => _epochs[id];
  static bool isPending(String id) => _pending.containsKey(id);

  static bool isCurrent(String id, Object? epoch) =>
      !isPending(id) && identical(_epochs[id], epoch);

  static ConnectionMutationLease begin(Iterable<String> connections) {
    final ids = connections.toSet();
    for (final id in ids) {
      _epochs[id] = Object();
      _pending[id] = (_pending[id] ?? 0) + 1;
    }
    for (final listener in _listeners.toList()) {
      try {
        listener();
      } catch (_) {
        // Observers are best-effort: a failed authority read is not revocation.
        // Keep delivering without blocking the caller's storage/recovery path
        // or losing its release lease. Do not surface sensitive observer errors.
      }
    }
    return ConnectionMutationLease._(ids);
  }
}

/// Held through credential verification, metadata commit and attempted rollback.
/// Reference counts keep overlapping mutations from releasing a sibling's gate.
class ConnectionMutationLease {
  ConnectionMutationLease._(this.connections);
  final Set<String> connections;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    for (final id in connections) {
      final remaining = ConnectionMutationBarrier._pending[id]! - 1;
      if (remaining == 0) {
        ConnectionMutationBarrier._pending.remove(id);
      } else {
        ConnectionMutationBarrier._pending[id] = remaining;
      }
    }
  }
}
