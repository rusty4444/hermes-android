import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';

void main() {
  for (final fault in [
    StateError('synthetic observer error'),
    Exception('synthetic observer exception'),
  ]) {
    test(
      'observer ${fault.runtimeType} cannot interrupt all-ID invalidation or later observers',
      () {
        const a = 'observer-unit-all-a';
        const b = 'observer-unit-all-b';
        final beforeA = ConnectionMutationBarrier.capture(a);
        final beforeB = ConnectionMutationBarrier.capture(b);
        final observations = <(bool, bool, bool, bool)>[];
        void observe() => observations.add((
          ConnectionMutationBarrier.isPending(a),
          ConnectionMutationBarrier.isPending(b),
          ConnectionMutationBarrier.isCurrent(a, beforeA),
          ConnectionMutationBarrier.isCurrent(b, beforeB),
        ));
        void failing() {
          observe();
          throw fault;
        }

        void healthy() => observe();
        ConnectionMutationBarrier.addListener(failing);
        ConnectionMutationBarrier.addListener(healthy);
        addTearDown(() {
          ConnectionMutationBarrier.removeListener(failing);
          ConnectionMutationBarrier.removeListener(healthy);
        });
        final lease = ConnectionMutationBarrier.begin([a, b, a]);
        addTearDown(lease.release);
        expect(observations, [
          (true, true, false, false),
          (true, true, false, false),
        ]);
        expect(lease.connections, {a, b});
        final epochA = ConnectionMutationBarrier.capture(a);
        lease.release();
        lease.release();
        expect(ConnectionMutationBarrier.isPending(a), isFalse);
        expect(ConnectionMutationBarrier.isPending(b), isFalse);
        expect(ConnectionMutationBarrier.isCurrent(a, beforeA), isFalse);
        expect(ConnectionMutationBarrier.isCurrent(a, epochA), isTrue);
      },
    );
  }

  test(
    'faulted observer cannot release an overlapped sibling or roll epochs back',
    () {
      const a = 'observer-unit-overlap-a';
      const b = 'observer-unit-overlap-b';
      final sibling = ConnectionMutationBarrier.begin([a]);
      addTearDown(sibling.release);
      final old = ConnectionMutationBarrier.capture(a);
      var delivered = 0;
      void failing() => throw StateError('synthetic');
      void healthy() => delivered++;
      ConnectionMutationBarrier.addListener(failing);
      ConnectionMutationBarrier.addListener(healthy);
      addTearDown(() {
        ConnectionMutationBarrier.removeListener(failing);
        ConnectionMutationBarrier.removeListener(healthy);
      });
      final lease = ConnectionMutationBarrier.begin([a, b]);
      addTearDown(lease.release);
      final latest = ConnectionMutationBarrier.capture(a);
      expect(latest, isNot(same(old)));
      lease.release();
      lease.release();
      expect(delivered, 1);
      expect(ConnectionMutationBarrier.isPending(a), isTrue);
      expect(ConnectionMutationBarrier.isPending(b), isFalse);
      expect(ConnectionMutationBarrier.isCurrent(a, latest), isFalse);
      sibling.release();
      expect(ConnectionMutationBarrier.isCurrent(a, latest), isTrue);
      expect(ConnectionMutationBarrier.isCurrent(a, old), isFalse);
    },
  );

  test(
    'reentrant begin retains nested ownership and synchronous snapshot delivery after a fault',
    () {
      const a = 'observer-unit-reentrant-a';
      const b = 'observer-unit-reentrant-b';
      final deliveries = <String>[];
      ConnectionMutationLease? nested;
      Object? nestedEpoch;
      var nesting = false;
      void failing() => throw StateError('synthetic');
      void healthy() => deliveries.add(nesting ? 'nested' : 'outer');
      void added() => deliveries.add('added');
      void reenter() {
        if (nesting) return;
        nesting = true;
        // Snapshot semantics: removal/addition affects the next delivery only.
        ConnectionMutationBarrier.removeListener(healthy);
        ConnectionMutationBarrier.addListener(added);
        nested = ConnectionMutationBarrier.begin([a, b]);
        nestedEpoch = ConnectionMutationBarrier.capture(a);
        nesting = false;
      }

      ConnectionMutationBarrier.addListener(failing);
      ConnectionMutationBarrier.addListener(reenter);
      ConnectionMutationBarrier.addListener(healthy);
      addTearDown(() {
        for (final listener in [failing, reenter, healthy, added]) {
          ConnectionMutationBarrier.removeListener(listener);
        }
        nested?.release();
      });
      final outer = ConnectionMutationBarrier.begin([a]);
      addTearDown(outer.release);
      expect(deliveries, ['added', 'outer']);
      expect(ConnectionMutationBarrier.capture(a), same(nestedEpoch));
      nested!.release();
      nested!.release();
      expect(ConnectionMutationBarrier.isPending(b), isFalse);
      expect(ConnectionMutationBarrier.isPending(a), isTrue);
      outer.release();
      expect(ConnectionMutationBarrier.isCurrent(a, nestedEpoch), isTrue);
    },
  );

  test(
    'empty-ID recovery still delivers all observers synchronously despite a fault',
    () {
      var delivered = 0;
      void failing() => throw StateError('synthetic');
      void healthy() => delivered++;
      ConnectionMutationBarrier.addListener(failing);
      ConnectionMutationBarrier.addListener(healthy);
      addTearDown(() {
        ConnectionMutationBarrier.removeListener(failing);
        ConnectionMutationBarrier.removeListener(healthy);
      });
      final lease = ConnectionMutationBarrier.begin([]);
      expect(delivered, 1);
      expect(lease.connections, isEmpty);
      lease.release();
      lease.release();
    },
  );
}
