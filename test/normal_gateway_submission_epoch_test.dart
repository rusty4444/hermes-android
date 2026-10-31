import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final currentTurnFails in [false, true]) {
    test(
      'pre-wait resume cannot gain authority after ACK; fresh failure $currentTurnFails',
      () async {
        SharedPreferences.setMockInitialValues({});
        final sent = Completer<void>();
        final rpc = Completer<void>();
        final resumeStarted = Completer<void>();
        final staleResume = Completer<ResumedGatewaySession>();
        final store = NormalGatewayPendingStore();
        var resumes = 0;
        var submissions = 0;
        final session = NormalGatewayApplicationSession(
          connection: SavedConnection(
            id: 'submission-epoch',
            label: 'Fixture',
            host: 'fixture.invalid',
            port: 8642,
            apiKey: 'fixture-only',
          ),
          scope: 'submission-epoch',
          pendingStore: store,
          history: (_) async => [],
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) {
                submissions++;
                onSent();
                sent.complete();
                return rpc.future;
              },
          resume: ({required localSessionId, required storedSessionId}) {
            resumes++;
            if (resumes == 1) {
              resumeStarted.complete();
              return staleResume.future;
            }
            return Future.value(
              ResumedGatewaySession(
                runtimeSessionId: 'runtime',
                running: !currentTurnFails,
                status: currentTurnFails ? 'error' : 'running',
                inflight: currentTurnFails
                    ? {'status': 'error', 'error': 'B authoritative failure'}
                    : null,
              ),
            );
          },
        );
        addTearDown(session.close);
        await session.ready;
        final chat = session.chatFor(
          'local',
          storedSessionId: 'stored',
          title: 'Fixture',
        );
        chat.observeHistory([]);
        final submission = chat.submitPrepared(
          reservation: chat.reserve()!,
          text: 'B',
          localContent: 'B',
        );
        await sent.future;
        final turnId = chat.turnId;
        session.receiveEvent(
          'local',
          StreamEvent(
            type: 'turn.error',
            data: const {'message': 'Old A wire error'},
          ),
        );
        await resumeStarted.future;
        rpc.complete();
        await submission;
        expect(chat.snapshot.hasActiveTurn, isTrue);
        staleResume.complete(
          const ResumedGatewaySession(
            runtimeSessionId: 'old-runtime',
            running: false,
            status: 'error',
            inflight: {'status': 'error', 'error': 'Old A retained failure'},
          ),
        );
        await pumpEventQueue();
        final receipts = await store.load('submission-epoch');
        expect(
          resumes,
          2,
          reason: 'A fresh post-wait observation is required.',
        );
        expect(submissions, 1);
        if (currentTurnFails) {
          expect(chat.phase, NormalGatewayTurnPhase.failed);
          expect(chat.snapshot.error, contains('B authoritative failure'));
          expect(receipts, isEmpty);
        } else {
          expect(chat.snapshot.hasActiveTurn, isTrue);
          expect(chat.snapshot.error, isNull);
          expect(receipts.single.turnId, turnId);
        }
      },
    );
  }
}
