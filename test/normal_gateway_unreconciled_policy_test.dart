import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/normal_gateway_application_session.dart';
import 'package:hermes_android/core/services/ws_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final successful in [true, false]) {
    test(
      'uncorrelated $successful output survives later full saved history',
      () async {
        final rows = <Map<String, dynamic>>[
          {'id': 37, 'role': 'assistant', 'content': 'Old'},
        ];
        var submissions = 0;
        final session = NormalGatewayApplicationSession(
          connection: SavedConnection(
            id: 'policy',
            label: 'Policy',
            host: 'localhost',
            port: 8642,
            apiKey: '',
          ),
          scope: 'policy',
          history: (_) async => rows,
          resume: ({required localSessionId, required storedSessionId}) async =>
              ResumedGatewaySession(runtimeSessionId: 'runtime', running: true),
          submit:
              ({
                required sessionId,
                required text,
                required onEvent,
                required onSent,
              }) async {
                submissions++;
                onSent();
              },
        );
        addTearDown(session.close);
        await session.ready;
        final owner = session.chatFor(
          'local',
          storedSessionId: 'stored',
          title: 'Policy',
        );
        owner.observeHistory(rows);
        await owner.submitPrepared(
          reservation: owner.reserve()!,
          text: 'Prompt',
          localContent: 'Prompt',
        );
        void emit(String type, Map<String, dynamic> data) =>
            session.receiveEvent(
              'local',
              StreamEvent(type: type, data: data, turnId: 'wire'),
            );
        emit('reasoning.delta', {'text': 'Reasoning'});
        emit('message.delta', {'text': 'Received'});
        emit('tool.start', {'tool': 'read_file', 'tool_id': 'raw-tool'});
        emit(
          successful ? 'turn.end' : 'turn.error',
          successful ? {} : {'error': 'Failure'},
        );
        for (var i = 0; i < 50 && owner.snapshot.hasActiveTurn; i++) {
          await pumpEventQueue();
        }
        expect(owner.snapshot.hasActiveTurn, isFalse);
        final retained = owner.snapshot;
        rows.addAll([
          {'id': 98, 'role': 'user', 'content': 'Prompt'},
          {'id': 99, 'role': 'assistant', 'content': 'Received'},
          {'id': 100, 'role': 'user', 'content': 'Other prompt'},
          {'id': 101, 'role': 'assistant', 'content': 'Other answer'},
        ]);
        owner.observeHistory(rows);
        expect(owner.snapshot.historyRows, rows);
        expect(owner.snapshot.displayRows, retained.displayRows);
        expect(owner.snapshot.timeline, same(retained.timeline));
        expect(owner.snapshot.tools.single.toolId, 'raw-tool');
        expect(owner.snapshot.rowFloor, 37);
        expect(submissions, 1);
        final token = owner.beginHistoryRead('stored');
        await session.close();
        expect(token.isAttached, isFalse);
        expect(owner.snapshot.displayRows, isEmpty);
        expect(owner.snapshot.timeline.runs, isEmpty);
        expect(owner.snapshot.tools, isEmpty);
        expect(
          retained.displayRows,
          isNotEmpty,
          reason: 'close releases owned buffers, not external snapshots',
        );
      },
    );
  }
}
