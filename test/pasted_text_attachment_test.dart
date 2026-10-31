import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/attachment_draft.dart';
import 'package:hermes_android/core/services/attachment_draft_service.dart';

void main() {
  late Directory sandbox;
  late Directory cache;
  late AttachmentDraftService service;

  setUp(() async {
    final root = await Directory('build/paste-tests').create(recursive: true);
    sandbox = await root.createTemp('paste-');
    cache = Directory('${sandbox.path}/cache');
    service = AttachmentDraftService(cacheDirectoryProvider: () async => cache);
  });
  tearDown(() => sandbox.delete(recursive: true));

  AttachmentDraft fixture(String name, int size) => AttachmentDraft(
    id: name,
    cachedPath: '${sandbox.path}/$name',
    name: name,
    byteLength: size,
    mediaType: 'text/plain',
    kind: AttachmentDraftKind.genericFile,
  );

  test(
    'preserves exact UTF-8 bytes including whitespace, Unicode and CRLF',
    () async {
      const text = '  \r\n日本語 😀\r\nlast line\n  ';
      final draft = await service.preparePastedText(
        text: text,
        existingDrafts: [],
      );
      expect(draft.name, 'paste.txt');
      expect(draft.kind, AttachmentDraftKind.genericFile);
      expect(draft.mediaType, 'text/plain');
      expect(draft.byteLength, utf8.encode(text).length);
      expect(await File(draft.cachedPath).readAsBytes(), utf8.encode(text));
      expect(
        await service.readDataUrl(draft),
        'data:text/plain;base64,${base64Encode(utf8.encode(text))}',
      );
      await service.removeCachedFile(draft);
      expect(await File(draft.cachedPath).exists(), isFalse);
    },
  );

  test(
    'multiple pastes have unique cache paths and collision-safe display names',
    () async {
      final first = await service.preparePastedText(
        text: 'first',
        existingDrafts: [],
      );
      final second = await service.preparePastedText(
        text: 'second',
        existingDrafts: [first, fixture('paste-2.txt', 1)],
      );
      expect(second.name, 'paste-3.txt');
      expect(second.cachedPath, isNot(first.cachedPath));
      expect(await File(first.cachedPath).readAsString(), 'first');
      expect(await File(second.cachedPath).readAsString(), 'second');
    },
  );

  test(
    'accepts exactly 16 MiB and rejects oversized ASCII and multibyte UTF-8',
    () async {
      final exact = await service.preparePastedText(
        text: 'x' * maxGenericAttachmentBytes,
        existingDrafts: [],
      );
      expect(exact.byteLength, maxGenericAttachmentBytes);
      for (final text in [
        'x' * (maxGenericAttachmentBytes + 1),
        'é' * (maxGenericAttachmentBytes ~/ 2 + 1),
      ]) {
        await expectLater(
          service.preparePastedText(text: text, existingDrafts: []),
          throwsA(isA<AttachmentDraftException>()),
        );
      }
      expect(await cache.list().length, 1);
    },
  );

  test(
    'rejects empty pastes, item 11 and aggregate overflow before writing',
    () async {
      final cases = <(String, List<AttachmentDraft>)>[
        ('', []),
        (
          'paste',
          List.generate(maxRemoteAttachmentDrafts, (i) => fixture('$i.txt', 1)),
        ),
        ('é', [fixture('full.txt', maxRemoteAttachmentDraftBytes - 1)]),
      ];
      for (final (text, existing) in cases) {
        await expectLater(
          service.preparePastedText(text: text, existingDrafts: existing),
          throwsA(isA<AttachmentDraftException>()),
        );
      }
      expect(await cache.exists(), isFalse);
    },
  );

  for (final throwsAfterWrite in [false, true]) {
    test('cleans a partial cache write (throws=$throwsAfterWrite)', () async {
      final broken = AttachmentDraftService(
        cacheDirectoryProvider: () async => cache,
        cacheFileWriter: (file, bytes) async {
          await file.writeAsBytes(bytes.take(2).toList());
          if (throwsAfterWrite) {
            throw const FileSystemException('test write failed');
          }
        },
      );
      await expectLater(
        broken.preparePastedText(text: 'complete paste', existingDrafts: []),
        throwsA(anything),
      );
      expect(await cache.list().length, 0);
    });
  }
}
