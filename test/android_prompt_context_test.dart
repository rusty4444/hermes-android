import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/android_prompt_context.dart';

void main() {
  test(
    'guidance identifies the frontend, delivery contract and host paths',
    () {
      final wire = AndroidPromptContext.forModel('Create a PDF');
      expect(wire, startsWith('Create a PDF\n\n'));
      expect(wire, contains('native Hermes Android app, not a terminal'));
      expect(wire, contains('`MEDIA:/absolute/host/path`'));
      expect(wire, contains('previews, Download and Share'));
      expect(wire, contains('Hermes host, not the phone'));
      expect(utf8.encode(AndroidPromptContext.suffix).length, lessThan(1024));
    },
  );

  test(
    'one exact note round-trips whitespace, Unicode and literal escapes',
    () {
      for (final text in [
        'Create a PDF',
        '  keep both ends  \r\n',
        '你好 — café 🦘\nsecond line',
        r'literal \n and \r are not line endings',
        'A literal example${AndroidPromptContext.suffix}',
      ]) {
        expect(
          AndroidPromptContext.userText(AndroidPromptContext.forModel(text)),
          text,
        );
      }
    },
  );

  test('only one complete known note is removed', () {
    const suffix = AndroidPromptContext.suffix;
    expect(AndroidPromptContext.userText('body$suffix$suffix'), 'body$suffix');
    for (final text in [
      'body${suffix.replaceAll('context v1', 'context v2')}',
      'body${suffix.substring(0, suffix.length - 1)}',
      'body$suffix\nnot a trailer',
      suffix.split('\n').map((line) => '> $line').join('\n'),
      '```text\n$suffix\n```',
      r'body\n\n[Hermes Android client context v1]',
    ]) {
      expect(AndroidPromptContext.userText(text), text);
    }
  });

  test(
    'empty input, slash commands and bare stock stop controls are verbatim',
    () {
      for (final text in [
        '',
        '  \n',
        '/model exact-provider/model-id',
        ' \n/custom-skill preserve arguments\nsecond line',
        '/srv/a file.pdf',
        'stop',
        ' STOP! ',
        '"stop."',
        'stop talking',
        'cancel',
      ]) {
        expect(AndroidPromptContext.forModel(text), text);
      }
      expect(
        AndroidPromptContext.forModel('stop doing that and try again'),
        endsWith(AndroidPromptContext.suffix),
      );
    },
  );

  test(
    'attachment-only context retains the exact empty or whitespace text',
    () {
      for (final text in ['', '  \n']) {
        final wire = AndroidPromptContext.forAttachment(text);
        expect(wire, endsWith(AndroidPromptContext.suffix));
        expect(AndroidPromptContext.userText(wire), text);
      }
      expect(AndroidPromptContext.forAttachment('/model keep'), '/model keep');
    },
  );

  test('custom stop phrases use the stock whole-utterance normalisation', () {
    for (final text in [' "BONNE NUIT!" ', 'bonne nuit', 'Bonne nuit.']) {
      expect(
        AndroidPromptContext.forModel(text, stopPhrases: [' Bonne nuit ']),
        text,
      );
    }
    expect(
      AndroidPromptContext.forModel(
        'bonne nuit and make a report',
        stopPhrases: ['bonne nuit'],
      ),
      endsWith(AndroidPromptContext.suffix),
    );
  });

  test('multimodal decoding never mutates the raw history or image part', () {
    final image = {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,Zml4dHVyZQ=='},
    };
    final raw = [
      {'type': 'text', 'text': AndroidPromptContext.forModel('Look at this')},
      image,
      {'type': 'unknown', 'text': 'keep${AndroidPromptContext.suffix}'},
    ];
    final before = jsonEncode(raw);
    final decoded = AndroidPromptContext.userContent(raw) as List;
    expect(decoded.first, {'type': 'text', 'text': 'Look at this'});
    expect(decoded[1], same(image));
    expect(decoded.last, same(raw.last));
    expect(jsonEncode(raw), before);
    expect(AndroidPromptContext.userContent(null), isNull);
  });

  test(
    'presentation decodes only remote user rows, not local text or output',
    () {
      final raw = AndroidPromptContext.forModel('Create a file');
      expect(
        AndroidPromptContext.displayContent({'role': 'user'}, raw),
        'Create a file',
      );
      for (final role in ['assistant', 'agent', 'tool', 'system']) {
        expect(AndroidPromptContext.displayContent({'role': role}, raw), raw);
      }
      expect(
        AndroidPromptContext.displayContent({
          'role': 'user',
          AndroidPromptContext.localUserTextKey: true,
        }, raw),
        raw,
      );
      expect(
        AndroidPromptContext.displayContent({'role': 'user'}, null),
        isNull,
      );
      expect(AndroidPromptContext.displayContent({'role': 'user'}, ''), '');
    },
  );

  test(
    'session previews hide only recognised complete or clipped app notes',
    () {
      final raw = AndroidPromptContext.forModel('Create a report');
      expect(AndroidPromptContext.sessionPreview(raw), 'Create a report');
      final clipped = raw.substring(0, 110);
      expect(AndroidPromptContext.sessionPreview(clipped), 'Create a report');
      expect(
        AndroidPromptContext.sessionPreview(clipped.replaceAll('\n', ' ')),
        'Create a report',
      );
      final unknown = raw.replaceAll('context v1', 'context v2');
      expect(AndroidPromptContext.sessionPreview(unknown), unknown);
      const changed = 'Report [Hermes Android client context v1]\nnot our note';
      expect(AndroidPromptContext.sessionPreview(changed), changed);
      expect(
        AndroidPromptContext.sessionPreview('ordinary preview'),
        'ordinary preview',
      );
    },
  );
}
