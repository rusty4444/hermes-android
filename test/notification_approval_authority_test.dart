import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/notification_approval_authority.dart';
import 'package:hermes_android/core/services/turn_notification_service.dart';

import 'helpers/notification_approval_fixture.dart';

void main() {
  setUp(() => pendingNotificationApprovals.value = []);
  tearDown(() => pendingNotificationApprovals.value = []);

  PendingNotificationApproval action(
    SavedConnection c, {
    String request = 'same',
  }) => PendingNotificationApproval(
    connectionId: c.id,
    sessionId: 'session',
    requestId: request,
    choice: 'once',
    authority: fixtureApprovalAuthority(c),
  );

  test('legacy unscoped automatic approval fails closed', () {
    addPendingNotificationApproval(
      const PendingNotificationApproval(
        connectionId: 'legacy',
        sessionId: 'session',
        requestId: 'same',
        choice: 'once',
      ),
    );
    expect(pendingNotificationApprovals.value, isEmpty);
  });

  test(
    'pending credential mutation revokes old and rejects new admission through ABA',
    () {
      final c = fixtureApprovalConnection('aba');
      final old = action(c);
      addPendingNotificationApproval(old);
      final lease = ConnectionMutationBarrier.begin([c.id]);
      expect(old.authority!.isCurrent, false);
      final origin = NotificationApprovalAuthority.origin(c);
      expect(
        NotificationApprovalAuthority.capture(
          connection: c,
          accountBinding: origin['approvalAccount'],
          originMutation: origin['approvalMutation'],
          owner: c,
          ownerIsCurrent: () => true,
          refresh: () async => true,
        ),
        isNull,
      );
      lease.release();
      prunePendingNotificationApprovals();
      expect(pendingNotificationApprovals.value, isEmpty);
      expect(old.authority!.isCurrentFor(c), false);
      final fresh = action(c);
      addPendingNotificationApproval(fresh);
      expect(pendingNotificationApprovals.value.single, same(fresh));
    },
  );

  test(
    'creation provenance cannot revive after same-process ABA before tap',
    () {
      final c = fixtureApprovalConnection('created-before-aba');
      final origin = NotificationApprovalAuthority.origin(c);
      ConnectionMutationBarrier.begin([c.id]).release();
      expect(
        NotificationApprovalAuthority.capture(
          connection: c,
          accountBinding: origin['approvalAccount'],
          originMutation: origin['approvalMutation'],
          owner: c,
          ownerIsCurrent: () => true,
          refresh: () async => true,
        ),
        isNull,
      );
    },
  );

  test(
    'late success and release own exact entry; fresh same IDs and sibling survive',
    () {
      final c = fixtureApprovalConnection('cleanup');
      final sibling = action(fixtureApprovalConnection('sibling'));
      final old = action(c);
      addPendingNotificationApproval(old);
      addPendingNotificationApproval(sibling);
      expect(claimNotificationApproval(old), true);
      ConnectionMutationBarrier.begin([c.id]).release();
      final fresh = action(c);
      addPendingNotificationApproval(fresh);
      expect(claimNotificationApproval(fresh), true);
      removePendingNotificationApproval(old);
      releaseNotificationApproval(old);
      expect(pendingNotificationApprovals.value, [sibling, fresh]);
      expect(claimNotificationApproval(fresh), false);
      releaseNotificationApproval(fresh);
      expect(claimNotificationApproval(fresh), true);
      releaseNotificationApproval(fresh);
    },
  );

  test(
    'same authority deduplicates and singleflights, unrelated requests remain independent',
    () {
      final c = fixtureApprovalConnection('dedup');
      final first = action(c);
      final duplicate = action(c);
      final other = action(c, request: 'other');
      addPendingNotificationApproval(first);
      addPendingNotificationApproval(duplicate);
      addPendingNotificationApproval(other);
      expect(pendingNotificationApprovals.value, [first, other]);
      expect(claimNotificationApproval(first), true);
      expect(claimNotificationApproval(duplicate), false);
      expect(claimNotificationApproval(other), true);
      releaseNotificationApproval(first);
      releaseNotificationApproval(other);
    },
  );

  test(
    'physical refresh completion cannot regain revoked mutation or owner authority',
    () async {
      final c = fixtureApprovalConnection('held-refresh');
      final held = Completer<bool>();
      var alive = true;
      final origin = NotificationApprovalAuthority.origin(c);
      final authority = NotificationApprovalAuthority.capture(
        connection: c,
        accountBinding: origin['approvalAccount'],
        originMutation: origin['approvalMutation'],
        owner: c,
        ownerIsCurrent: () => alive,
        refresh: () => held.future,
      )!;
      final validating = authority.validate();
      ConnectionMutationBarrier.begin([c.id]).release();
      alive = false;
      held.complete(true);
      expect(await validating, false);
    },
  );

  final replacements = <String, SavedConnection Function(SavedConnection)>{
    'credential': (c) => c.copyWith(apiKey: 'replacement'),
    'dashboard credential': (c) => c.copyWith(dashboardPassword: 'replacement'),
    'profile': (c) => c.copyWith(gatewayProfile: 'replacement'),
    'host': (c) => c.copyWith(host: 'replacement.fixture'),
    'prefix': (c) => c.copyWith(gatewayPrefix: '/replacement'),
  };
  for (final entry in replacements.entries) {
    test(
      'complete binding rejects ${entry.key} replacement with identical IDs',
      () {
        final c = fixtureApprovalConnection('binding-${entry.key}');
        expect(action(c).authority!.isCurrentFor(entry.value(c)), false);
      },
    );
  }

  test(
    'local origin contains hashes and opaque process epoch, no plaintext credential',
    () {
      final c = fixtureApprovalConnection('payload').copyWith(
        apiKey: 'private-fixture-key',
        dashboardPassword: 'private-fixture-password',
      );
      final payload = jsonEncode(NotificationApprovalAuthority.origin(c));
      expect(payload, isNot(contains(c.apiKey)));
      expect(payload, isNot(contains(c.dashboardPassword!)));
      expect(
        jsonDecode(payload)['approvalAccount'],
        matches(RegExp(r'^[a-f0-9]{64}$')),
      );
    },
  );
}
