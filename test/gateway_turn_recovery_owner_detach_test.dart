import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_mutation_barrier.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/gateway_turn_journal.dart';
import 'package:hermes_android/core/services/gateway_turn_coordinator.dart';

import 'support/memory_turn_journal_store.dart';
import 'normal_gateway_alias_handoff_wire_test.dart' show BindingServer;

void main() {
  for (final replace in [false, true]) {
    test(
      'default recovery owner late detach during held close; replacement=$replace',
      () async {
        final server = await BindingServer.start();
        addTearDown(server.close);
        final store = _HeldReadStore();
        var journals = 0;
        final controller = GatewayTurnApplicationController(
          journalFactory: () => GatewayTurnJournal(
            store: journals++ == 0 ? store : MemoryTurnJournalStore(),
          ),
        );
        final connection = server.connection;
        final owner = controller.sessionFor(connection);
        final asyncToken = owner.setAsyncEventListener('local', (_, _) {});
        final settledToken = owner.setTurnSettledListener('local', (_) {});
        final boundToken = owner.setSessionBoundListener('local', (_, _) {});
        final activityToken = owner.addTurnActivityListener(() {});
        final opening = owner.recoverPending('local');
        // Attach the pending operation's error observer before releasing its
        // read. The stock fixture lacks v2; this pins close's held cleanup, not
        // successful recovery or a particular operation-failure classification.
        final openingFailed = expectLater(
          opening,
          throwsA(isA<GatewayTurnCoordinatorException>()),
        );
        await store.entered.future;
        var closeFinished = false;
        final closing = owner.close().then((_) => closeFinished = true);
        try {
          if (replace) {
            final mutation = ConnectionMutationBarrier.begin([connection.id]);
            mutation.release();
            final replacement = controller.sessionFor(connection);
            expect(replacement, isNot(same(owner)));
            final token = replacement.setAsyncEventListener('local', (_, _) {});
            // Cross-owner tokens cannot unregister a same-ID replacement.
            replacement.removeAsyncEventListener('local', asyncToken);
            replacement.removeAsyncEventListener('local', token);
          }
          await Future<void>.value();
          expect(closeFinished, isFalse);
          for (var i = 0; i < 2; i++) {
            owner.removeAsyncEventListener('local', asyncToken);
            owner.removeAsyncEventListener('other-local', asyncToken);
            owner.removeAsyncEventListener('local', Object());
            owner.removeTurnSettledListener('local', settledToken);
            owner.removeSessionBoundListener('local', boundToken);
            owner.removeTurnActivityListener(activityToken);
          }
          await _expectClosedAdmissions(owner);
          expect(closeFinished, isFalse);
        } finally {
          store.release.complete();
          await openingFailed;
          await closing;
          await controller.close();
        }
        expect(closeFinished, isTrue);
        owner.removeAsyncEventListener('local', asyncToken);
        await owner.close();
        await _expectClosedAdmissions(owner);
      },
    );
  }
}

Future<void> _expectClosedAdmissions(
  GatewayTurnApplicationSession owner,
) async {
  final operations = <FutureOr<Object?> Function()>[
    () => owner.setAsyncEventListener('local', (_, _) {}),
    () => owner.setTurnSettledListener('local', (_) {}),
    () => owner.setSessionBoundListener('local', (_, _) {}),
    () => owner.addTurnActivityListener(() {}),
    () => owner.ownsApprovalRequest(sessionId: 'local', requestId: 'request'),
    () => owner.tryRespondToApproval(
      sessionId: 'local',
      requestId: 'request',
      choice: 'deny',
    ),
    () => owner.tryRespondToClarify(requestId: 'request', answer: 'fixture'),
    () => owner.tryRespondToSudo(requestId: 'request', password: 'fixture'),
    () => owner.tryRespondToSecret(requestId: 'request', value: 'fixture'),
    () => owner.submit(localSessionId: 'local', text: 'must not send'),
    () => owner.recoverPending('local'),
    () => owner.interrupt(localSessionId: 'local', clientTurnId: 'turn'),
    () => owner.stageAttachment(
      localSessionId: 'local',
      clientAttachmentId: 'attachment',
      name: 'fixture',
      dataUrl: 'data:text/plain;base64,eA==',
      byteLength: 1,
      mediaType: 'text/plain',
      kind: GatewayTurnAttachmentKind.file,
    ),
    () =>
        owner.detachAttachments(localSessionId: 'local', attachments: const []),
  ];
  for (final operation in operations) {
    await expectLater(Future<Object?>.sync(operation), throwsStateError);
  }
}

class _HeldReadStore extends MemoryTurnJournalStore {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> read() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.read();
  }
}
