import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodCall;
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_pdf_service.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () =>
        messenger.setMockMethodCallHandler(AttachmentPdfDocument.channel, null),
  );

  test('oversize and empty PDFs never cross the native channel', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(AttachmentPdfDocument.channel, (
      _,
    ) async {
      calls++;
      return null;
    });
    await expectLater(
      AttachmentPdfDocument.open(Uint8List(0)),
      throwsFormatException,
    );
    await expectLater(
      AttachmentPdfDocument.open(Uint8List(maxAttachmentDownloadBytes + 1)),
      throwsFormatException,
    );
    expect(calls, 0);
  });

  test('invalid native page count closes the exact acquired handle', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(AttachmentPdfDocument.channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'open'
          ? {'id': 'owned', 'pageCount': AttachmentPdfDocument.maxPages + 1}
          : null;
    });
    await expectLater(
      AttachmentPdfDocument.open(Uint8List.fromList([1])),
      throwsFormatException,
    );
    expect(calls.map((call) => call.method), ['open', 'close']);
    expect(calls.last.arguments, {'id': 'owned'});
  });

  test(
    'native dimensions and PNG byte count are validated before decode',
    () async {
      var width = 99999;
      var height = 1;
      var bytes = Uint8List.fromList([1]);
      messenger.setMockMethodCallHandler(
        AttachmentPdfDocument.channel,
        (call) async => switch (call.method) {
          'open' => {'id': 'owned', 'pageCount': 1},
          'render' => {'bytes': bytes, 'width': width, 'height': height},
          _ => null,
        },
      );
      final document = await AttachmentPdfDocument.open(
        Uint8List.fromList([1]),
      );
      await expectLater(document.render(0), throwsFormatException);
      width = 1;
      height = 0;
      await expectLater(document.render(0), throwsFormatException);
      height = 1;
      bytes = Uint8List(16 * 1024 * 1024 + 1);
      await expectLater(document.render(0), throwsFormatException);
      await document.close();
    },
  );

  test(
    'closing during render fences the late result and closes only once',
    () async {
      final render = Completer<Map<String, dynamic>>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AttachmentPdfDocument.channel, (
        call,
      ) async {
        calls.add(call);
        return switch (call.method) {
          'open' => {'id': 'owned', 'pageCount': 1},
          'render' => render.future,
          _ => null,
        };
      });
      final document = await AttachmentPdfDocument.open(
        Uint8List.fromList([1]),
      );
      final page = document.render(0);
      final rejected = expectLater(page, throwsStateError);
      await document.close();
      await document.close();
      render.complete({
        'bytes': Uint8List.fromList([1]),
        'width': 1,
        'height': 1,
      });
      await rejected;
      expect(calls.where((call) => call.method == 'close').length, 1);
      await expectLater(document.render(0), throwsStateError);
    },
  );

  test('page bounds are rejected without invoking render', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(AttachmentPdfDocument.channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'open' ? {'id': 'owned', 'pageCount': 2} : null;
    });
    final document = await AttachmentPdfDocument.open(Uint8List.fromList([1]));
    await expectLater(document.render(-1), throwsStateError);
    await expectLater(document.render(2), throwsStateError);
    expect(calls.where((call) => call.method == 'render'), isEmpty);
    await document.close();
  });
}
