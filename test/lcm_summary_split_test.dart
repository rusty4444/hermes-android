import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/legacy_lcm_summary.dart';

void main() {
  const header = '[Session Arc Summary (d1, node 1090)]';
  const footer = '[Expand for details: some references]';
  const envelope = '$header\nSome summary content here.\n$footer';

  group('LegacyLcmSummary.splitEnvelope', () {
    test('pure envelope returns null (matches handles it)', () {
      expect(LegacyLcmSummary.matches(envelope), isTrue);
      expect(LegacyLcmSummary.splitEnvelope(envelope), isNull);
    });

    test('envelope + assistant tail splits correctly', () {
      final body = '$envelope\n\nThe actual assistant answer follows.';
      expect(LegacyLcmSummary.matches(body), isFalse);
      final split = LegacyLcmSummary.splitEnvelope(body);
      expect(split, isNotNull);
      expect(split!.$1, envelope);
      expect(split.$2, 'The actual assistant answer follows.');
    });

    test('envelope + tail with tool-looking content', () {
      final body =
          '$envelope\n[ASSISTANT]:\n[Tool calls:\n  terminal({"command": "ls"})\n]\nDone.';
      final split = LegacyLcmSummary.splitEnvelope(body);
      expect(split, isNotNull);
      expect(split!.$1, envelope);
      expect(split.$2, contains('[ASSISTANT]:'));
      expect(split.$2, contains('Done.'));
    });

    test('non-summary body returns null', () {
      expect(LegacyLcmSummary.splitEnvelope('Hello world'), isNull);
      expect(LegacyLcmSummary.splitEnvelope('[Recent Summary (d0, node 1)]'), isNull);
    });

    test('header without footer returns null', () {
      const body = '$header\nContent without a footer line.';
      expect(LegacyLcmSummary.splitEnvelope(body), isNull);
    });

    test('multi-frame envelope + tail splits at last frame', () {
      const frame2Header = '[Recent Summary (d0, node 1091)]';
      const body =
          '$envelope\n\n---\n\n$frame2Header\nMore content.\n$footer\n\nReal tail.';
      // matches() should fail because of the tail
      expect(LegacyLcmSummary.matches(body), isFalse);
      final split = LegacyLcmSummary.splitEnvelope(body);
      expect(split, isNotNull);
      expect(split!.$1, contains(frame2Header));
      expect(split.$1, endsWith(footer));
      expect(split.$2, 'Real tail.');
    });

    test('Recent Summary variant works', () {
      const recentHeader = '[Recent Summary (d0, node 1009)]';
      final body =
          '$recentHeader\nRecent content.\n$footer\n\nAssistant tail here.';
      final split = LegacyLcmSummary.splitEnvelope(body);
      expect(split, isNotNull);
      expect(split!.$1, startsWith(recentHeader));
      expect(split.$2, 'Assistant tail here.');
    });

    test('Durable Summary variant works', () {
      const durableHeader = '[Durable Summary (d2, node 500)]';
      final body = '$durableHeader\nDurable content.\n$footer\n\nTail.';
      final split = LegacyLcmSummary.splitEnvelope(body);
      expect(split, isNotNull);
      expect(split!.$1, startsWith(durableHeader));
      expect(split.$2, 'Tail.');
    });

    test('CRLF normalisation', () {
      final body =
          '$header\r\nContent.\r\n$footer\r\n\r\nTail after CRLF.';
      final split = LegacyLcmSummary.splitEnvelope(body);
      expect(split, isNotNull);
      expect(split!.$2, 'Tail after CRLF.');
    });

    test('empty tail returns null', () {
      final body = '$envelope\n\n   \n';
      expect(LegacyLcmSummary.splitEnvelope(body), isNull);
    });

    test('objective prefix + envelope + tail', () {
      const objective =
          '[Current user objective preserved from compacted history]';
      final body =
          '$objective\nKeep the objective.\n\n---\n\n$envelope\n\nThe real answer.';
      final split = LegacyLcmSummary.splitEnvelope(body);
      expect(split, isNotNull);
      expect(split!.$1, contains(objective));
      expect(split.$1, contains(header));
      expect(split.$2, 'The real answer.');
    });
  });
}