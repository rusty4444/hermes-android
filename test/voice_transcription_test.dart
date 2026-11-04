import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/voice_transcription.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('voice-upload-fixture-');
    file = File('${directory.path}/fixture.m4a');
    await file.writeAsBytes([1, 2, 3, 4]);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'uses the existing authenticated Dashboard route and selected profile',
    () async {
      final requests = <http.Request>[];
      final dashboard = DashboardClient(
        host: 'hermes.invalid',
        port: 443,
        useHttps: true,
        pathPrefix: '/dashboard',
        gatewayProfile: 'work',
        proxied: true,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"ok":true,"transcript":"  Recognized words  ","provider":"fixture"}',
            200,
          );
        }),
      );
      expect(
        await transcribeVoiceRecording(dashboard, file.path),
        'Recognized words',
      );
      expect(requests, hasLength(1));
      expect(
        requests.single.url.toString(),
        'https://hermes.invalid/dashboard/api/audio/transcribe?profile=work',
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body.keys.toSet(), {'data_url', 'mime_type'});
      expect(body['mime_type'], 'audio/mp4');
      expect(base64Decode((body['data_url'] as String).split(',').last), [
        1,
        2,
        3,
        4,
      ]);
      expect(
        await file.readAsBytes(),
        [1, 2, 3, 4],
        reason: 'Transcription alone never deletes the recording',
      );
      dashboard.close();
    },
  );

  for (final payload in [
    '{"ok":true,"transcript":""}',
    '{"ok":false,"transcript":"Do not send"}',
    '{"ok":true}',
    '{"ok":true,"transcript":42}',
  ]) {
    test(
      'invalid or silent recognition never becomes a prompt: $payload',
      () async {
        final dashboard = DashboardClient(
          host: 'fixture.invalid',
          proxied: true,
          httpClient: MockClient((_) async => http.Response(payload, 200)),
        );
        await expectLater(
          transcribeVoiceRecording(dashboard, file.path),
          throwsA(isA<VoiceTranscriptionException>()),
        );
        expect(await file.exists(), isTrue);
        dashboard.close();
      },
    );
  }

  for (final status in [404, 413, 503]) {
    test(
      'HTTP$status retains recording with no fallback or automatic retry',
      () async {
        var requests = 0;
        final dashboard = DashboardClient(
          host: 'fixture.invalid',
          proxied: true,
          httpClient: MockClient((_) async {
            requests++;
            return http.Response(
              '{"private_provider_details":"do not display"}',
              status,
            );
          }),
        );
        await expectLater(
          transcribeVoiceRecording(dashboard, file.path),
          throwsA(isA<VoiceTranscriptionException>()),
        );
        expect(requests, 1);
        expect(await file.exists(), isTrue);
        dashboard.close();
      },
    );
  }

  test('empty and oversized recordings never leave the phone', () async {
    var requests = 0;
    final dashboard = DashboardClient(
      host: 'fixture.invalid',
      proxied: true,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    await file.writeAsBytes([]);
    await expectLater(
      transcribeVoiceRecording(dashboard, file.path),
      throwsA(isA<VoiceTranscriptionException>()),
    );
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(6 * 1024 * 1024 + 1);
    await handle.close();
    await expectLater(
      transcribeVoiceRecording(dashboard, file.path),
      throwsA(isA<VoiceTranscriptionException>()),
    );
    expect(requests, 0);
    expect(await file.exists(), isTrue);
    dashboard.close();
  });
}
