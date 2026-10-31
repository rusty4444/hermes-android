/// Immutable UI-only lifecycle fact. Persistence correspondence is independent.
/// Its anchors are existing receipt scopes; it owns no body or server identity.
enum ReceivedLifecycleOutcome { completed, failed, unknown }

class ReceivedScopeOutcome {
  ReceivedScopeOutcome({
    required this.id,
    required Iterable<String> scopes,
    required this.outcome,
  }) : scopes = Set<String>.unmodifiable(scopes);

  final String id;
  final Set<String> scopes;
  final ReceivedLifecycleOutcome outcome;
}
