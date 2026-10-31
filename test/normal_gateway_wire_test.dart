import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/gateway_turn_application_controller.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/normal_gateway_pending_store.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Gateway gateway;
  HttpOverrides? overrides;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    gateway = _Gateway();
    await gateway.start();
  });
  tearDown(() async {
    await gateway.close();
    HttpOverrides.global = overrides;
  });

  test(
    'restored running guidance preserves the first received assistant activity',
    () async {
      final initialController = GatewayTurnApplicationController();
      final initial = initialController.normalSessionFor(gateway.connection);
      await initial.ready;
      await initial.pendingStore.put(
        NormalGatewayPendingMarker(
          scope: initial.scope,
          localSessionId: 'mobile',
          storedSessionId: 'stored',
          turnId: 'restored-turn',
          rowFloor: 10,
          phase: 'emitted',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await initialController.close();
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.findChat('stored')!;
      await _until(() => chat.canSteer);
      expect(chat.snapshot.displayRows, isEmpty);
      expect(await chat.steer('Continue after restart'), isTrue);
      expect(chat.snapshot.displayRows.single['display_kind'], 'steer');

      gateway.event('reasoning.delta', {'text': 'First reasoning'});
      gateway.event('tool.start', {
        'tool': 'read_file',
        'tool_id': 'early-tool',
      });
      gateway.event('message.delta', {'text': 'After restart'});
      await _until(() => chat.snapshot.tools.isNotEmpty);
      expect(
        chat.snapshot.displayRows.where((row) => row['role'] == 'assistant'),
        hasLength(1),
        reason: 'Acknowledged guidance is not an assistant response scaffold',
      );
      await _until(
        () => chat.snapshot.displayRows.last['content'] == 'After restart',
      );
      expect(
        chat.snapshot.displayRows.last['_gateway_reasoning'],
        'First reasoning',
      );
      expect(
        chat.snapshot.timeline.runs.map(
          (run) => run.activity?.toolId ?? run.text,
        ),
        ['First reasoning', 'early-tool', 'After restart'],
      );
      expect(chat.turnId, 'restored-turn');
      expect(
        (await session.pendingStore.load(session.scope)).single.turnId,
        'restored-turn',
      );
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(
        gateway.requests.where(
          (request) => request['method'] == 'session.steer',
        ),
        hasLength(1),
      );
      expect(
        gateway.requests.where(
          (request) =>
              request['method'] == 'prompt.submit' ||
              request['method'] == 'session.create' ||
              request['method'] == 'session.interrupt',
        ),
        isEmpty,
      );
    },
  );

  test(
    'steering uses the bound runtime once without interrupting or resubmitting',
    () async {
      gateway.holdSteerAck = true;
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'mobile',
        storedSessionId: 'stored',
        title: 'Chat',
      );
      final flight = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'Original',
        localContent: 'Original',
      );
      flight.ignore();
      await gateway.submitted.future;
      final turn = chat.turnId;
      final steer = chat.steer('  Focus on authentication\nKeep the tests  ');
      await _until(() => gateway.releaseSteerAck != null);
      expect(await chat.steer('Duplicate callback'), isFalse);
      expect(chat.snapshot.steering, isTrue);
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(
        gateway.requests
            .where((r) => r['method'] == 'session.steer')
            .single['params'],
        {
          'session_id': gateway.runtime,
          'text': 'Focus on authentication\nKeep the tests',
        },
      );
      expect(
        gateway.requests.where((r) => r['method'] == 'session.interrupt'),
        isEmpty,
      );
      // Stop stays independently usable while the steer acknowledgement waits.
      expect(await chat.interrupt(), isTrue);
      gateway.releaseSteerAck!();
      expect(await steer, isTrue);
      expect(chat.snapshot.steering, isFalse);
      expect(chat.turnId, turn);
      expect(
        (await session.pendingStore.load(session.scope)).single.turnId,
        turn,
      );
      expect(
        chat.snapshot.displayRows
            .where((r) => r['role'] == 'user')
            .map((r) => r['content']),
        ['Original', 'Focus on authentication\nKeep the tests'],
      );
      gateway.event('message.delta', {'text': 'Still the same response'});
      await _until(
        () =>
            chat.snapshot.displayRows.last['content'] ==
            'Still the same response',
      );
      expect(
        gateway.requests.where((r) => r['method'] == 'prompt.submit'),
        hasLength(1),
      );
      expect(
        gateway.requests.where((r) => r['method'] == 'session.create'),
        isEmpty,
      );
    },
  );

  for (final outcome in ['rejected', 'unsupported', 'invalid']) {
    test(
      '$outcome steer acknowledgement never falls back or retries',
      () async {
        gateway.steerStatus = outcome == 'invalid' ? 'steered' : 'rejected';
        if (outcome == 'unsupported') gateway.steerError = -32601;
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final session = controller.normalSessionFor(gateway.connection);
        await session.ready;
        final chat = session.chatFor(
          'mobile',
          storedSessionId: 'stored',
          title: 'Chat',
        );
        final flight = chat.submitPrepared(
          reservation: chat.reserve()!,
          text: 'Original',
          localContent: 'Original',
        );
        flight.ignore();
        await gateway.submitted.future;
        if (outcome == 'rejected') {
          expect(await chat.steer('Guidance'), isFalse);
        } else {
          await expectLater(
            chat.steer('Guidance'),
            throwsA(isA<JsonRpcError>()),
          );
        }
        expect(chat.snapshot.steering, isFalse);
        expect(chat.snapshot.hasActiveTurn, isTrue);
        expect(
          chat.snapshot.displayRows.where((r) => r['role'] == 'user'),
          hasLength(1),
        );
        expect(
          gateway.requests.where((r) => r['method'] == 'session.steer'),
          hasLength(1),
        );
        expect(
          gateway.requests.where((r) => r['method'] == 'prompt.submit'),
          hasLength(1),
        );
        expect(
          gateway.requests.where((r) => r['method'] == 'session.interrupt'),
          isEmpty,
        );
      },
    );
  }

  test(
    'late steering ack cannot append into a settled turn or reopen admission early',
    () async {
      gateway.holdSteerAck = true;
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'mobile',
        storedSessionId: 'stored',
        title: 'Chat',
      );
      final flight = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'Original',
        localContent: 'Original',
      );
      flight.ignore();
      await gateway.submitted.future;
      gateway.event('message.delta', {'text': 'Final'}, turnId: 'turn-A');
      await _until(() => chat.snapshot.displayRows.last['content'] == 'Final');
      final steering = chat.steer('Guidance');
      await _until(() => gateway.releaseSteerAck != null);
      gateway.event('turn.end', {'status': 'completed'}, turnId: 'turn-A');
      await flight;
      await _until(() => !chat.snapshot.hasActiveTurn);
      final settled = chat.snapshot.displayRows;
      expect(
        chat.reserve(),
        isNull,
        reason: 'An unacknowledged steer still owns admission',
      );
      gateway.releaseSteerAck!();
      await expectLater(steering, throwsStateError);
      expect(chat.snapshot.displayRows, settled);
      expect(chat.reserve(), isNotNull);
    },
  );

  test(
    'fresh stock create binds cwd and canonical baseline before the first prompt wire',
    () async {
      gateway.createFresh = true;
      gateway.rows.clear();
      gateway.historyEntered = Completer<void>();
      gateway.releaseHistory = Completer<void>();
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'mob-fresh',
        title: 'Fresh stock chat',
        workingDirectory: '/project',
      );
      final flight = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'First prompt',
        localContent: 'First prompt',
      );
      flight.ignore();
      await gateway.historyEntered!.future;
      expect(chat.storedSessionId, 'stored');
      expect(gateway.historyPaths, ['/api/sessions/stored/messages']);
      expect(
        gateway.requests
            .map((r) => r['method'])
            .where((method) => method != 'client.capabilities'),
        ['session.resume', 'session.create'],
      );
      expect(
        gateway.requests.singleWhere(
          (r) => r['method'] == 'session.create',
        )['params'],
        {'source': 'desktop', 'cwd': '/project'},
      );
      expect(await session.pendingStore.load(session.scope), isEmpty);
      gateway.releaseHistory!.complete();
      await gateway.submitted.future;
      expect(chat.snapshot.rowFloor, 0);
      expect(
        (await session.pendingStore.load(session.scope)).single.rowFloor,
        0,
      );
      gateway.rows.addAll([
        {'id': 1, 'role': 'user', 'content': 'First prompt'},
        {'id': 2, 'role': 'assistant', 'content': 'First final'},
      ]);
      gateway.event('message.complete', {'text': 'First final'});
      await flight;
      expect(chat.snapshot.hasActiveTurn, isTrue);
      gateway.running = false; // stock completes its lifecycle after the frame
      chat.requestRecovery();
      await _until(() => !chat.snapshot.hasActiveTurn);
      expect(chat.phase, NormalGatewayTurnPhase.completed);
      expect(chat.snapshot.historyRows.last['content'], 'First final');
      expect(await session.pendingStore.load(session.scope), isEmpty);
      expect(
        gateway.requests.where((r) => r['method'] == 'prompt.submit'),
        hasLength(1),
      );
      expect(
        gateway.requests.where((r) => r['method'] == 'session.create'),
        hasLength(1),
      );
    },
  );

  test(
    'production ingress delivers tokens once, resumes continued tools/deltas without resending',
    () async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'Wire chat',
      );
      chat.observeHistory([
        {'id': 10, 'role': 'assistant', 'content': 'Before'},
      ]);
      final flight = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'Run',
        localContent: 'Run',
      );
      flight.ignore();
      await gateway.submitted.future;
      expect(
        gateway.requests
            .where((request) => request['method'] == 'session.resume')
            .map((request) => request['params']['source']),
        everyElement('desktop'),
        reason: 'Android must not inherit the server launch surface (TUI).',
      );
      gateway.event('message.delta', {'text': 'Exactly once. '});
      await _until(
        () => chat.snapshot.displayRows.last['content'] == 'Exactly once. ',
      );
      await gateway.socket!.close();
      await flight;
      expect(controller.hasActiveTurn, isTrue);
      final resumed = gateway.nextResume = Completer<void>();
      chat.requestRecovery();
      await resumed.future;
      gateway.event('message.delta', {'text': 'After reconnect.'});
      gateway.event('tool.start', {
        'tool': 'read_file',
        'tool_id': 'tool-after',
      });
      await _until(() => chat.snapshot.tools.isNotEmpty);
      expect(
        chat.snapshot.displayRows.last['content'],
        'Exactly once. After reconnect.',
      );
      expect(
        gateway.requests.where((row) => row['method'] == 'prompt.submit'),
        hasLength(1),
      );
      expect(
        gateway.requests.where((row) => row['method'] == 'session.create'),
        isEmpty,
      );
      gateway.event('turn.end', {
        'status': 'failed',
        'error': 'Retained failure',
      });
      gateway.running = false;
      gateway.inflight = {'status': 'error', 'error': 'Retained failure'};
      chat.requestRecovery();
      await _until(() => !controller.hasActiveTurn);
      expect(chat.phase, NormalGatewayTurnPhase.failed);
      expect(chat.snapshot.error, 'Retained failure');
    },
  );

  test(
    'emitted stale-runtime RPC error cannot automatically retry prompt.submit',
    () async {
      gateway.rejectSubmit = true;
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'Wire chat',
      );
      chat.observeHistory([]);
      await chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'Once',
        localContent: 'Once',
      );
      expect(chat.snapshot.wireEmitted, isTrue);
      expect(chat.phase, NormalGatewayTurnPhase.reconciling);
      expect(
        gateway.requests.where((row) => row['method'] == 'prompt.submit'),
        hasLength(1),
      );
      expect(
        gateway.requests.where((row) => row['method'] == 'session.create'),
        isEmpty,
      );
    },
  );

  test(
    'resume-only missing durable id never creates, even during recovery',
    () async {
      gateway.rejectResume = true;
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      await expectLater(
        session.client!.resumeSubmittedSession(
          localSessionId: 'local',
          storedSessionId: 'missing',
        ),
        throwsA(isA<JsonRpcError>()),
      );
      expect(
        gateway.requests.where((row) => row['method'] == 'session.create'),
        isEmpty,
      );
      expect(
        gateway.requests.where((row) => row['method'] == 'prompt.submit'),
        isEmpty,
      );
    },
  );

  test(
    'absent-route approval remains socket owned; reused wire id cannot approve new socket request',
    () async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'Wire chat',
      );
      await session.client!.ensureSession('local');
      gateway.approval();
      await _until(() => chat.snapshot.pendingInput.isNotEmpty);
      final oldId =
          chat.snapshot.pendingInput.single.data['server_request_id'] as String;
      expect(
        session.ownsApprovalRequest(sessionId: 'stored', requestId: oldId),
        isTrue,
      );
      // No route is subscribed, so nothing may reject the retained request.
      expect(gateway.responses, isEmpty);
      await gateway.socket!.close();
      await _until(() => chat.snapshot.pendingInput.isEmpty);
      await session.client!.resumeSubmittedSession(
        localSessionId: 'local',
        storedSessionId: 'stored',
      );
      gateway.approval();
      await _until(() => chat.snapshot.pendingInput.isNotEmpty);
      final newId =
          chat.snapshot.pendingInput.single.data['server_request_id'] as String;
      expect(newId, isNot(oldId));
      expect(
        await session.tryRespondToApproval(
          sessionId: 'stored',
          requestId: oldId,
          choice: 'approve',
        ),
        isFalse,
      );
      expect(
        await session.tryRespondToApproval(
          sessionId: 'stored',
          requestId: newId,
          choice: 'approve',
        ),
        isTrue,
      );
      await _until(() => gateway.responses.isNotEmpty);
      expect(gateway.responses.single['id'], 'approval-reused');
      expect(gateway.responses.single['result'], {'choice': 'approve'});
      // Reusing a wire id AFTER settlement on the SAME socket is a new
      // authority too; a saved notification action must not answer it.
      gateway.approval();
      await _until(() => chat.snapshot.pendingInput.isNotEmpty);
      final thirdId =
          chat.snapshot.pendingInput.single.data['server_request_id'] as String;
      expect(thirdId, isNot(newId));
      expect(
        await session.tryRespondToApproval(
          sessionId: 'stored',
          requestId: newId,
          choice: 'approve',
        ),
        isFalse,
      );
      expect(
        await session.tryRespondToApproval(
          sessionId: 'stored',
          requestId: thirdId,
          choice: 'reject',
        ),
        isTrue,
      );
      await _until(() => gateway.responses.length == 2);
    },
  );
  for (final terminal in ['turn.end', 'turn.error', 'error']) {
    for (final identified in [false, true]) {
      test(
        'real wire: trailing A $terminal identified=$identified cannot clear emitted B',
        () async {
          final controller = GatewayTurnApplicationController();
          addTearDown(controller.close);
          final session = controller.normalSessionFor(gateway.connection);
          await session.ready;
          final chat = session.chatFor(
            'local',
            storedSessionId: 'stored',
            title: 'Wire chat',
          );
          chat.observeHistory(gateway.rows);
          final first = chat.submitPrepared(
            reservation: chat.reserve()!,
            text: 'First',
            localContent: 'First',
          );
          first.ignore();
          await gateway.submitted.future;
          gateway.event('message.start', {}, turnId: identified ? 'A' : null);
          gateway.rows.add({
            'id': 12,
            'role': 'assistant',
            'content': 'First final',
          });
          gateway.event('message.complete', {'text': 'First final'});
          await first;
          await session.client!.getSessionReasoning(
            'local',
          ); // ordered wire barrier
          expect(
            chat.reserve(),
            isNull,
            reason: 'stock post-complete hooks still running',
          );
          gateway.running = false;
          chat.requestRecovery();
          await _until(() => !chat.snapshot.hasActiveTurn);
          expect(await session.pendingStore.load(session.scope), isEmpty);

          final second = chat.submitPrepared(
            reservation: chat.reserve()!,
            text: 'Second',
            localContent: 'Second',
          );
          second.ignore();
          await _until(
            () =>
                gateway.requests
                    .where((r) => r['method'] == 'prompt.submit')
                    .length ==
                2,
          );
          final b = chat.turnId;
          expect(chat.snapshot.rowFloor, 12);
          gateway.event(
            terminal,
            terminal == 'turn.end'
                ? {'status': 'completed'}
                : {'status': 'failed', 'error': 'Old A failure'},
            turnId: identified ? 'A' : null,
          );
          // This actually completes WsClient's B watcher. It must not complete B.
          await second;
          await session.client!.getSessionReasoning('local');
          expect(chat.snapshot.hasActiveTurn, isTrue);
          expect(chat.snapshot.error, isNull);
          expect(
            (await NormalGatewayPendingStore().load(
              session.scope,
            )).single.turnId,
            b,
          );
          expect(chat.reserve(), isNull);
          expect(
            gateway.requests.where((r) => r['method'] == 'prompt.submit'),
            hasLength(2),
          );

          gateway.rows.add({
            'id': 14,
            'role': 'assistant',
            'content': 'Second final',
          });
          gateway.running = false;
          // Message-complete-only gateways remain supported, without turn.end.
          gateway.event('message.complete', {'text': 'Second final'});
          chat.requestRecovery();
          await _until(() => !chat.snapshot.hasActiveTurn);
          expect(chat.phase, NormalGatewayTurnPhase.completed);
          expect(await session.pendingStore.load(session.scope), isEmpty);
        },
      );
    }
  }

  for (final freshFails in [false, true]) {
    test(
      'real wire: epoch rejects stale runtime and drains fresh resume; failure=$freshFails',
      () async {
        gateway.holdSubmitAck = true;
        final controller = GatewayTurnApplicationController();
        addTearDown(controller.close);
        final session = controller.normalSessionFor(gateway.connection);
        await session.ready;
        final chat = session.chatFor(
          'local',
          storedSessionId: 'stored',
          title: 'B',
        );
        chat.observeHistory(gateway.rows);
        final submission = chat.submitPrepared(
          reservation: chat.reserve()!,
          text: 'B',
          localContent: 'B',
        );
        submission.ignore();
        await gateway.submitted.future;
        final turnId = chat.turnId;
        final initialRuntime = gateway.runtime;
        gateway.holdResumeReply = true;
        gateway.resumeRuntime = 'pre-ack-runtime';
        gateway.running = false;
        gateway.inflight = {'status': 'error', 'error': 'Old A retained error'};
        final oldRead = gateway.nextResume = Completer<void>();
        gateway.event('turn.error', {'message': 'Old A wire error'});
        await oldRead.future;
        final releaseOld = gateway.releaseResumeReply!;
        gateway.resumeRuntime = 'post-ack-runtime';
        gateway.running = !freshFails;
        gateway.inflight = freshFails
            ? {'status': 'error', 'error': 'B fresh authoritative failure'}
            : null;
        gateway.releaseSubmitAck!();
        await submission;
        final freshRead = gateway.nextResume = Completer<void>();
        releaseOld();
        await freshRead.future;
        final releaseFresh = gateway.releaseResumeReply!;
        expect(
          gateway.requests.where((r) => r['method'] == 'session.resume'),
          hasLength(3),
        );
        expect(chat.snapshot.hasActiveTurn, isTrue);
        expect(chat.snapshot.error, isNull);
        expect(
          (await session.pendingStore.load(session.scope)).single.turnId,
          turnId,
        );
        expect(gateway.historyPaths, isEmpty);
        gateway.event('message.delta', {
          'text': 'STALE',
        }, sessionId: 'pre-ack-runtime');
        gateway.event('message.delta', {
          'text': 'Current',
        }, sessionId: initialRuntime);
        await session.client!.getSessionReasoning('local');
        expect(gateway.requests.last['params']['session_id'], initialRuntime);
        expect(chat.snapshot.displayRows.last['content'], 'Current');
        releaseFresh();
        if (freshFails) {
          await _until(() => !chat.snapshot.hasActiveTurn);
          expect(chat.phase, NormalGatewayTurnPhase.failed);
          expect(chat.snapshot.error, 'B fresh authoritative failure');
          expect(await session.pendingStore.load(session.scope), isEmpty);
        } else {
          await _until(() => gateway.historyPaths.isNotEmpty);
          await session.client!.getSessionReasoning('local');
          gateway.event('message.delta', {
            'text': 'STALE',
          }, sessionId: initialRuntime);
          gateway.event('message.delta', {
            'text': '+fresh',
          }, sessionId: 'post-ack-runtime');
          await session.client!.getSessionReasoning('local');
          expect(chat.snapshot.displayRows.last['content'], 'Current+fresh');
          expect(chat.snapshot.hasActiveTurn, isTrue);
          expect(
            (await session.pendingStore.load(session.scope)).single.turnId,
            turnId,
          );
        }
        await session.client!.getSessionReasoning('local');
        expect(
          gateway.requests.last['params']['session_id'],
          'post-ack-runtime',
        );
        expect(
          gateway.requests.where((r) => r['method'] == 'prompt.submit'),
          hasLength(1),
        );
      },
    );
  }

  test(
    'real wire: pre-ACK resume failure delivered after ACK cannot retire B',
    () async {
      gateway.holdSubmitAck = true;
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'B',
      );
      chat.observeHistory(gateway.rows);
      final submission = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'B',
        localContent: 'B',
      );
      submission.ignore();
      await gateway.submitted.future;
      final turnId = chat.turnId;
      gateway.holdResumeReply = true;
      gateway.running = false;
      gateway.inflight = {'status': 'error', 'error': 'Old A retained error'};
      final readStarted = gateway.nextResume = Completer<void>();
      gateway.event('turn.error', {'message': 'Old A wire error'});
      await readStarted.future;
      expect(gateway.releaseResumeReply, isNotNull);
      gateway.running = true;
      gateway.inflight = null;
      gateway.holdResumeReply = false;
      gateway.releaseSubmitAck!();
      await submission;
      expect(chat.snapshot.hasActiveTurn, isTrue);
      // The response was encoded before the ACK, not when it is released.
      gateway.releaseResumeReply!();
      await _until(
        () =>
            !chat.snapshot.hasActiveTurn ||
            gateway.requests
                    .where((r) => r['method'] == 'session.resume')
                    .length >=
                3,
      );
      final receipts = await session.pendingStore.load(session.scope);
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(chat.snapshot.error, isNull);
      expect(receipts.single.turnId, turnId);
      expect(
        gateway.requests.where((r) => r['method'] == 'prompt.submit'),
        hasLength(1),
      );
    },
  );

  test(
    'real wire: old idle error before B ACK cannot retire its receipt',
    () async {
      gateway.holdSubmitAck = true;
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'Wire chat',
      );
      chat.observeHistory(gateway.rows);
      final flight = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'B',
        localContent: 'B',
      );
      flight.ignore();
      await gateway.submitted.future;
      gateway.running = false;
      gateway.inflight = {'status': 'error', 'error': 'Old A retained error'};
      final resumed = gateway.nextResume = Completer<void>();
      gateway.event('turn.error', {'message': 'Old A error'});
      await resumed.future;
      await session.client!.getSessionReasoning('local');
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(
        (await session.pendingStore.load(session.scope)).single.turnId,
        chat.turnId,
      );
      gateway.running = true;
      gateway.inflight = null;
      gateway.releaseSubmitAck!();
      await flight;
      await session.client!.getSessionReasoning('local');
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(chat.snapshot.error, isNull);
      expect(
        gateway.requests.where((r) => r['method'] == 'prompt.submit'),
        hasLength(1),
      );
    },
  );

  test(
    'real wire: disconnected old-socket terminals cannot settle resumed B',
    () async {
      final controller = GatewayTurnApplicationController();
      addTearDown(controller.close);
      final session = controller.normalSessionFor(gateway.connection);
      await session.ready;
      final chat = session.chatFor(
        'local',
        storedSessionId: 'stored',
        title: 'Wire chat',
      );
      chat.observeHistory(gateway.rows);
      final flight = chat.submitPrepared(
        reservation: chat.reserve()!,
        text: 'B',
        localContent: 'B',
      );
      flight.ignore();
      await gateway.submitted.future;
      final old = gateway.socket!;
      final oldRuntime = gateway.runtime;
      await old.close();
      await flight;
      final resumed = gateway.nextResume = Completer<void>();
      chat.requestRecovery();
      await resumed.future;
      // Exercise the old server peer explicitly after the replacement bound.
      // It may accept a buffered send or reject it locally; neither may dispatch.
      try {
        old.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {
              'type': 'turn.end',
              'session_id': oldRuntime,
              'payload': {'status': 'completed'},
            },
          }),
        );
      } on StateError {
        // dart:io rejects writes after its close handshake on this platform.
      }
      // Also deliver an old-runtime frame on the new peer: no alias owns it.
      gateway.event('turn.error', {
        'message': 'old socket',
      }, sessionId: oldRuntime);
      gateway.event('message.delta', {'text': 'Resumed B'});
      await _until(
        () => chat.snapshot.displayRows.last['content'] == 'Resumed B',
      );
      expect(chat.snapshot.hasActiveTurn, isTrue);
      expect(
        (await session.pendingStore.load(session.scope)).single.turnId,
        chat.turnId,
      );
      expect(
        gateway.requests.where((r) => r['method'] == 'prompt.submit'),
        hasLength(1),
      );
    },
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Wire fixture condition did not arrive');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

class _Gateway {
  late HttpServer server;
  WebSocket? socket;
  String runtime = '';
  final sockets = <WebSocket>[];
  final requests = <Map<String, dynamic>>[];
  final responses = <Map<String, dynamic>>[];
  final submitted = Completer<void>();
  Completer<void>? nextResume;
  bool rejectSubmit = false;
  bool rejectResume = false;
  bool createFresh = false;
  bool created = false;
  Completer<void>? historyEntered;
  Completer<void>? releaseHistory;
  final historyPaths = <String>[];
  bool holdSubmitAck = false;
  bool holdSteerAck = false;
  void Function()? releaseSteerAck;
  String steerStatus = 'queued';
  int? steerError;
  void Function()? releaseSubmitAck;
  bool holdResumeReply = false;
  void Function()? releaseResumeReply;
  String? resumeRuntime;
  bool running = true;
  Map<String, dynamic>? inflight;
  final rows = <Map<String, dynamic>>[
    {'id': 10, 'role': 'assistant', 'content': 'Before'},
  ];
  SavedConnection get connection => SavedConnection(
    id: 'real-wire',
    label: 'Wire fixture',
    host: '127.0.0.1',
    port: server.port,
    apiKey: 'fixture',
    dashboardPortOverride: server.port,
    dashboardProxied: true,
  );

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/api/auth/ws-ticket') {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ticket":"fixture-ticket"}');
        await request.response.close();
      } else if (request.uri.path.endsWith('/messages')) {
        historyPaths.add(request.uri.path);
        if (historyEntered != null && !historyEntered!.isCompleted) {
          historyEntered!.complete();
        }
        await releaseHistory?.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': rows}));
        await request.response.close();
      } else if (request.uri.path == '/api/ws') {
        final ws = await WebSocketTransformer.upgrade(request);
        socket = ws;
        sockets.add(ws);
        runtime = 'runtime-${sockets.length}';
        ws.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'event',
            'params': {
              'type': 'gateway.ready',
              'payload': {'server_requests': true},
            },
          }),
        );
        ws.listen((raw) {
          final frame = Map<String, dynamic>.from(
            jsonDecode(raw as String) as Map,
          );
          if (frame['method'] == null) {
            responses.add(frame);
            return;
          }
          requests.add(frame);
          final method = frame['method'];
          if (method == 'prompt.submit') running = true;
          if (method == 'session.create') created = true;
          final rejected =
              method == 'prompt.submit' && rejectSubmit ||
              method == 'session.steer' && steerError != null ||
              method == 'session.resume' &&
                  (rejectResume || createFresh && !created);
          try {
            final encodedReply = jsonEncode({
              'jsonrpc': '2.0',
              'id': frame['id'],
              if (rejected)
                'error': {
                  'code': method == 'session.steer'
                      ? steerError
                      : method == 'prompt.submit'
                      ? 4001
                      : 4007,
                  'message': 'session not found',
                }
              else
                'result': method == 'session.resume'
                    ? {
                        'session_id': resumeRuntime ?? runtime,
                        'running': running,
                        if (!running && inflight == null) 'status': 'completed',
                        if (inflight != null) 'inflight': inflight,
                      }
                    : method == 'session.create'
                    ? {'session_id': runtime, 'stored_session_id': 'stored'}
                    : method == 'session.steer'
                    ? {
                        'status': steerStatus,
                        'text': (frame['params'] as Map)['text'],
                      }
                    : {'ok': true},
            });
            void reply() => ws.add(encodedReply);
            if (method == 'prompt.submit' && holdSubmitAck) {
              releaseSubmitAck = reply;
            } else if (method == 'session.steer' && holdSteerAck) {
              releaseSteerAck = reply;
            } else if (method == 'session.resume' && holdResumeReply) {
              releaseResumeReply = reply;
            } else {
              reply();
            }
          } on StateError {
            // An already accepted request may reach the fixture while the
            // test closes the owner; a closed peer cannot receive the reply.
          }
          if (method == 'session.resume') {
            if (nextResume != null && !nextResume!.isCompleted) {
              nextResume!.complete();
            }
          }
          if (method == 'prompt.submit' && !submitted.isCompleted) {
            submitted.complete();
          }
        }, onDone: () {});
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
  }

  void event(
    String type,
    Map<String, dynamic> payload, {
    String? sessionId,
    String? turnId,
  }) => socket!.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'event',
      'params': {
        'type': type,
        'session_id': sessionId ?? runtime,
        'turn_id': ?turnId,
        'payload': payload,
      },
    }),
  );
  void approval() => socket!.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 'approval-reused',
      'method': 'approval',
      'params': {
        'session_id': runtime,
        'command': 'test',
        'description': 'Fixture action',
      },
    }),
  );
  Future<void> close() async {
    for (final ws in sockets) {
      await ws.close();
    }
    await server.close(force: true);
  }
}
