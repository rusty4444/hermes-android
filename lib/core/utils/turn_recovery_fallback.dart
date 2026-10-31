import '../services/gateway_turn_coordinator.dart';

/// What the chat surface may do after `recoverPending` failed.
///
/// Recovery failure handling is the last guard against submitting the same
/// prompt twice: an ambiguous failure must never be answered by falling back
/// to the legacy transport, because the durable turn may already exist on the
/// server. Only a gateway that explicitly reports the recovery capability as
/// absent — and reports no pending durable turn — may be answered that way.
enum TurnRecoveryFallback {
  /// The gateway proved it cannot host durable turns and holds none, so the
  /// chat may switch to the clearly-labelled legacy transport.
  legacyTransport,

  /// Everything else: keep the durable transport, surface the error, and keep
  /// the composer blocked rather than risking a duplicate submit.
  reportUnavailable,
}

/// Pure classification of a `recoverPending` failure.
///
/// [allowLegacyFallback] is only true for the first recovery pass of a chat.
/// A later resume that fails must not degrade a gateway that already worked.
TurnRecoveryFallback classifyTurnRecoveryFailure(
  Object error, {
  required bool allowLegacyFallback,
}) {
  if (allowLegacyFallback &&
      error is GatewayTurnCoordinatorException &&
      error.failure == GatewayTurnCoordinatorFailure.unsupportedCapability) {
    return TurnRecoveryFallback.legacyTransport;
  }
  return TurnRecoveryFallback.reportUnavailable;
}

/// Whether a legacy-fallback-eligible failure came from a gateway that
/// cleanly does not offer the durable recovery contract (a stock Hermes
/// server), rather than a v2 gateway that broke mid-negotiation.
///
/// The UI uses this to draw an accurate "this server doesn't offer
/// background recovery" notice instead of the failure-toned banner, so a
/// stock-gateway user is not shown a permanent error for a state that is
/// working exactly as designed.
bool turnRecoveryFailureIsStockGateway(Object error) =>
    error is GatewayTurnCoordinatorException &&
    error.failure == GatewayTurnCoordinatorFailure.unsupportedCapability &&
    error.stockGateway;
