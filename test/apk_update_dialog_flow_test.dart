import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/apk_update_installer.dart';
import 'package:hermes_android/core/services/app_update_service.dart';
import 'package:hermes_android/core/widgets/update_available_dialog.dart';

import 'support/l10n_test_utils.dart';

final _release = AppReleaseInfo(
  version: '3.2.6',
  tagName: 'v3.2.6',
  releaseUrl: 'https://github.com/rusty4444/hermes-android/releases/tag/v3.2.6',
  apkAssets: [
    AppReleaseApk(
      abi: 'arm64-v8a',
      name: 'app-arm64-v8a-release.apk',
      url: Uri.parse(
        'https://github.com/rusty4444/hermes-android/releases/download/v3.2.6/app-arm64-v8a-release.apk',
      ),
      sha256:
          '0037e440f19dad89318902f90a6b8ef29cfe0289304e62fde6b9d4896a6fbff4',
      size: 123,
    ),
  ],
);

class FakeInstaller extends ApkUpdateInstaller {
  final downloadFinished = Completer<void>();
  int downloads = 0;
  int installations = 0;
  int cancellations = 0;
  bool fail = false;
  bool failInstall = false;
  bool prepared = false;
  String installResult = 'launched';
  void Function(int, int)? progress;

  @override
  Future<List<String>> supportedAbis() async => ['arm64-v8a'];

  @override
  Future<bool> hasPreparedUpdate(AppReleaseApk apk, String tag) async =>
      prepared;

  @override
  Future<void> download({
    required AppReleaseApk apk,
    required String tag,
    required void Function(int, int) onProgress,
  }) async {
    downloads++;
    progress = onProgress;
    await downloadFinished.future;
    if (fail) throw PlatformException(code: 'failed');
  }

  @override
  Future<String> install() async {
    installations++;
    if (failInstall) throw PlatformException(code: 'not_ready');
    return installResult;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

Future<void> _show(WidgetTester tester, FakeInstaller installer) async {
  await tester.pumpWidget(
    testAppWithL10n(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateAvailableDialog(
              context,
              release: _release,
              installer: installer,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'download is user initiated, shows progress and opens installer',
    (tester) async {
      final installer = FakeInstaller();
      await _show(tester, installer);
      expect(installer.downloads, 0);
      expect(find.text('Update now'), findsOneWidget);
      await tester.tap(find.text('Update now'));
      await tester.pump();
      expect(installer.downloads, 1);
      expect(find.text('Downloading and verifying update…'), findsOneWidget);
      installer.progress!(50, 100);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      expect(installer.installations, 0);
      installer.downloadFinished.complete();
      await tester.pumpAndSettle();
      expect(installer.installations, 1);
      expect(find.text('Install update'), findsOneWidget);
    },
  );

  testWidgets(
    'permission is explicit and install can be retried without download',
    (tester) async {
      final installer = FakeInstaller()..installResult = 'permission_required';
      await _show(tester, installer);
      await tester.tap(find.text('Update now'));
      await tester.pump();
      installer.downloadFinished.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow Hermes to install'), findsOneWidget);
      installer.installResult = 'launched';
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(installer.downloads, 1);
      expect(installer.installations, 2);
    },
  );

  testWidgets('verification failure leaves browser and retry available', (
    tester,
  ) async {
    final installer = FakeInstaller()..fail = true;
    await _show(tester, installer);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    installer.downloadFinished.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be downloaded'), findsOneWidget);
    expect(find.text('View release'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
    expect(installer.installations, 0);
  });

  testWidgets('a retained verified update resumes without another download', (
    tester,
  ) async {
    final installer = FakeInstaller()..prepared = true;
    await _show(tester, installer);
    expect(find.text('Install update'), findsOneWidget);
    await tester.tap(find.text('Install update'));
    await tester.pumpAndSettle();
    expect(installer.downloads, 0);
    expect(installer.installations, 1);
  });

  testWidgets('cancelling download dismisses and asks native side to cancel', (
    tester,
  ) async {
    final installer = FakeInstaller();
    await _show(tester, installer);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(installer.cancellations, 1);
    expect(find.text('Update available'), findsNothing);
    installer.downloadFinished.complete();
    await tester.pump();
    expect(installer.installations, 0);
  });

  testWidgets(
    'install failure after permission prompt clears ready state and re-downloads on retry',
    (tester) async {
      final installer = FakeInstaller()..installResult = 'permission_required';
      await _show(tester, installer);
      await tester.tap(find.text('Update now'));
      await tester.pump();
      installer.downloadFinished.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow Hermes to install'), findsOneWidget);
      expect(find.text('Install update'), findsOneWidget);

      installer.failInstall = true;
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Allow Hermes to install'), findsNothing);
      expect(find.textContaining('could not be downloaded'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Skip this version'), findsOneWidget);

      installer.failInstall = false;
      installer.installResult = 'launched';
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(installer.downloads, 2);
      expect(installer.installations, 3);
    },
  );
}
