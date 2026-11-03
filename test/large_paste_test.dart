import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/utils/large_paste.dart';

TextEditingValue _value(
  String text, {
  TextSelection? selection,
  TextRange? composing,
}) => TextEditingValue(
  text: text,
  selection: selection ?? TextSelection.collapsed(offset: text.length),
  composing: composing ?? TextRange.empty,
);

void main() {
  final large = 'x' * 3001;

  test('only a single insertion beyond 3000 UTF-16 code units qualifies', () {
    for (final length in [0, 1, 2999, 3000, 3001]) {
      final edit = LargePasteEdit.detect(_value(''), _value('x' * length));
      expect(edit != null, length > 3000, reason: 'length=$length');
    }
    expect(LargePasteEdit.detect(_value(''), _value('😀' * 1501)), isNotNull);
    expect(LargePasteEdit.detect(_value(''), _value('a\n' * 20)), isNull);
  });

  test('preserves whitespace, CRLF, Unicode and surrounding instructions', () {
    final pasted = '  \r\n${'日本語😀\n' * 600}\r\n  ';
    final old = _value(
      'Explain  please',
      selection: const TextSelection.collapsed(offset: 8),
    );
    final next = _value(
      'Explain $pasted please',
      selection: TextSelection.collapsed(offset: 8 + pasted.length),
    );
    final edit = LargePasteEdit.detect(old, next)!;
    expect(edit.text, pasted);
    expect(edit.withoutPaste.text, 'Explain  please');
    expect(
      edit.withoutPaste.selection,
      const TextSelection.collapsed(offset: 8),
    );
  });

  test('replacing a reversed selection removes the selected text as well', () {
    final old = _value(
      'before replace after',
      selection: const TextSelection(baseOffset: 14, extentOffset: 7),
    );
    final next = _value(
      'before $large after',
      selection: TextSelection.collapsed(offset: 7 + large.length),
    );
    final edit = LargePasteEdit.detect(old, next)!;
    expect(edit.text, large);
    expect(edit.withoutPaste.text, 'before  after');
  });

  test(
    'typing, deletion and selection-only changes do not convert a large draft',
    () {
      expect(LargePasteEdit.detect(_value(large), _value('${large}a')), isNull);
      expect(
        LargePasteEdit.detect(_value(large), _value(large.substring(1))),
        isNull,
      );
      expect(
        LargePasteEdit.detect(
          _value(large),
          _value(large, selection: const TextSelection.collapsed(offset: 0)),
        ),
        isNull,
      );
    },
  );

  test('active IME composition and its commit are not treated as paste', () {
    expect(
      LargePasteEdit.detect(
        _value(''),
        _value(large, composing: TextRange(start: 0, end: large.length)),
      ),
      isNull,
    );
    expect(
      LargePasteEdit.detect(
        _value('a', composing: const TextRange(start: 0, end: 1)),
        _value(large),
      ),
      isNull,
    );
  });

  test('invalid selections and non-selection replacements stay inline', () {
    expect(
      LargePasteEdit.detect(const TextEditingValue(), _value(large)),
      isNull,
    );
    expect(LargePasteEdit.detect(_value('old'), _value(large)), isNull);
    expect(
      LargePasteEdit.detect(
        _value('x', selection: const TextSelection.collapsed(offset: 9)),
        _value(large),
      ),
      isNull,
    );
    expect(
      LargePasteEdit.detect(
        _value(''),
        _value(large, selection: const TextSelection.collapsed(offset: 1)),
      ),
      isNull,
    );
  });

  test(
    'formatter leaves input intact until asynchronous preparation commits',
    () {
      final edits = <LargePasteEdit>[];
      final formatter = LargePasteFormatter(onLargePaste: edits.add);
      final next = _value(large);
      expect(formatter.formatEditUpdate(_value(''), next), same(next));
      expect(edits.single.text, large);
      formatter.formatEditUpdate(next, _value('${large}a'));
      expect(edits, hasLength(1));
    },
  );
}
