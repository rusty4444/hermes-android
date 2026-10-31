import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';
import 'package:hermes_android/core/utils/media_tags.dart';
import 'package:hermes_android/core/widgets/media_artifact_card.dart';
import 'package:hermes_android/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;

/// Closing this transport aborts its body, as production IOClient.close does.
class _DownloadClient extends http.BaseClient {
  late final StreamController<List<int>> body;
  var closeCalls = 0;
  var cancelled = false;
  var requested = false;

  _DownloadClient() {
    body = StreamController<List<int>>(onCancel: () => cancelled = true);
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested = true;
    return http.StreamedResponse(body.stream, 200);
  }

  @override
  void close() {
    closeCalls++;
    if (!body.isClosed) {
      if (body.hasListener) {
        body.addError(http.ClientException('fixture closed'));
      }
      unawaited(body.close());
    }
  }
}

Future<void> _pump(
  WidgetTester tester,
  String path,
  _DownloadClient client,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaArtifactCard(
          ref: MediaTagRef(path: path),
          filesClient: () => RemoteFilesClient(
            dashboard: DashboardClient(
              host: 'fixture.test',
              proxied: true,
              httpClient: client,
            ),
            maxDownloadBytes: 25 * 1024 * 1024,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('disposing a media card aborts its active download', (
    tester,
  ) async {
    final client = _DownloadClient();
    await _pump(tester, '/out/held.png', client);
    await tester.tap(find.text('held.png'));
    await tester.pump();
    expect(client.requested, isTrue);
    expect(client.body.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(client.closeCalls, 1);
    expect(client.cancelled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing a media path aborts the old download without stale error',
    (tester) async {
      final old = _DownloadClient();
      await _pump(tester, '/out/old.png', old);
      await tester.tap(find.text('old.png'));
      await tester.pump();
      final replacement = _DownloadClient();
      await _pump(tester, '/out/new.png', replacement);
      await tester.pumpAndSettle();
      expect(old.closeCalls, 1);
      expect(old.cancelled, isTrue);
      expect(replacement.requested, isFalse);
      expect(find.text('new.png'), findsOneWidget);
      expect(find.textContaining('fixture closed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      replacement.close();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
