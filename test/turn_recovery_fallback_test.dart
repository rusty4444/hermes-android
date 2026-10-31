import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:hermes_android/core/utils/turn_recovery_fallback.dart';

void main() {
  group('classifyTurnRecoveryFailure', () {
    test('only an explicit unsupported capability may enable legacy', () {
      expect(
        classifyTurnRecoveryFailure(
          const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.unsupportedCapability,
          ),
          allowLegacyFallback: true,
        ),
        TurnRecoveryFallback.legacyTransport,
      );
    });

    test('a gateway that already recovered never degrades to legacy', () {
      // The init pass sets allowLegacyFallback; every later resume must not.
      // Degrading after a working v2 pass would re-open double-submit.
      expect(
        classifyTurnRecoveryFailure(
          const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.unsupportedCapability,
          ),
          allowLegacyFallback: false,
        ),
        TurnRecoveryFallback.reportUnavailable,
      );
    });

    test('unsupported capability with pending turns never enables legacy', () {
      // Pending durable turns exist server-side; a legacy submit would
      // duplicate them, so this failure stays fail-closed even on init.
      expect(
        classifyTurnRecoveryFailure(
          const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.unsupportedCapabilityWithPendingTurns,
          ),
          allowLegacyFallback: true,
        ),
        TurnRecoveryFallback.reportUnavailable,
      );
    });

    test('every other coordinator failure reports unavailable', () {
      final ambiguous = GatewayTurnCoordinatorFailure.values
          .where(
            (failure) =>
                failure != GatewayTurnCoordinatorFailure.unsupportedCapability,
          )
          .toList(growable: false);
      expect(ambiguous, isNotEmpty);
      for (final failure in ambiguous) {
        expect(
          classifyTurnRecoveryFailure(
            GatewayTurnCoordinatorException(failure),
            allowLegacyFallback: true,
          ),
          TurnRecoveryFallback.reportUnavailable,
          reason: '${failure.name} must not enable legacy transport',
        );
      }
    });

    test('transport, auth, and arbitrary errors report unavailable', () {
      final errors = <Object>[
        JsonRpcError('gateway.ready', 'Unauthorized', reason: 'unauthorized'),
        StateError('socket closed'),
        'plain string failure',
      ];
      for (final error in errors) {
        expect(
          classifyTurnRecoveryFailure(error, allowLegacyFallback: true),
          TurnRecoveryFallback.reportUnavailable,
          reason: '$error must not enable legacy transport',
        );
      }
    });
  });

  group('turnRecoveryFailureIsStockGateway', () {
    test('a clean stock-gateway absence is recognised', () {
      expect(
        turnRecoveryFailureIsStockGateway(
          const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.unsupportedCapability,
            stockGateway: true,
          ),
        ),
        isTrue,
      );
    });

    test('a v2-gateway rejection is not a stock gateway', () {
      expect(
        turnRecoveryFailureIsStockGateway(
          const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure.unsupportedCapability,
          ),
        ),
        isFalse,
      );
    });

    test('pending turns and every other failure are never a stock gateway', () {
      for (final failure in GatewayTurnCoordinatorFailure.values) {
        if (failure == GatewayTurnCoordinatorFailure.unsupportedCapability) {
          continue;
        }
        expect(
          turnRecoveryFailureIsStockGateway(
            GatewayTurnCoordinatorException(failure, stockGateway: true),
          ),
          isFalse,
          reason: '${failure.name} must not read as a stock gateway',
        );
      }
      expect(
        turnRecoveryFailureIsStockGateway(
          const GatewayTurnCoordinatorException(
            GatewayTurnCoordinatorFailure
                .unsupportedCapabilityWithPendingTurns,
            stockGateway: true,
          ),
        ),
        isFalse,
      );
    });
  });
}
