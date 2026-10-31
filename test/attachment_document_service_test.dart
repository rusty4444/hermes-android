import 'dart:convert';
import 'dart:io' as io show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/attachment_document_service.dart';

const _word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _sheet = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _presentation =
    'http://schemas.openxmlformats.org/presentationml/2006/main';
const _drawing = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _officeRels =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _packageRels =
    'http://schemas.openxmlformats.org/package/2006/relationships';

Uint8List _zip(Map<String, String> parts, {bool stored = false}) {
  final archive = Archive();
  for (final part in parts.entries) {
    final file = ArchiveFile.string(part.key, part.value);
    if (stored) file.compression = CompressionType.none;
    archive.add(file);
  }
  return ZipEncoder().encodeBytes(archive);
}

String _doc(String body) =>
    '<w:document xmlns:w="$_word"><w:body>$body</w:body></w:document>';

Uint8List _docx(String body, {bool stored = false}) =>
    _zip({'word/document.xml': _doc(body)}, stored: stored);

String _rels(String body) =>
    '<Relationships xmlns="$_packageRels">$body</Relationships>';
String _rel(String id, String type, String target, {bool external = false}) =>
    '<Relationship Id="$id" Type="$_officeRels/$type" Target="$target"'
    '${external ? ' TargetMode="External"' : ''}/>';
String _worksheet(String body) =>
    '<worksheet xmlns="$_sheet"><sheetData>$body</sheetData></worksheet>';
String _workbook(String body) =>
    '<workbook xmlns="$_sheet" xmlns:r="$_officeRels"><sheets>$body</sheets></workbook>';
String _slide(String body) =>
    '<p:sld xmlns:p="$_presentation" xmlns:a="$_drawing">'
    '<p:cSld><p:spTree><p:sp><p:txBody>$body</p:txBody></p:sp>'
    '</p:spTree></p:cSld></p:sld>';
String _presentationXml(String body) =>
    '<p:presentation xmlns:p="$_presentation" xmlns:r="$_officeRels">'
    '<p:sldIdLst>$body</p:sldIdLst></p:presentation>';

Uint8List _xlsx(String rows, {String? shared, String? target}) => _zip({
  'xl/workbook.xml': _workbook('<sheet name="Budget" sheetId="1" r:id="r1"/>'),
  'xl/_rels/workbook.xml.rels': _rels(
    _rel('r1', 'worksheet', target ?? 'worksheets/sheet1.xml') +
        (shared == null
            ? ''
            : _rel('strings', 'sharedStrings', 'sharedStrings.xml')),
  ),
  'xl/worksheets/sheet1.xml': _worksheet(rows),
  if (shared != null)
    'xl/sharedStrings.xml': '<sst xmlns="$_sheet">$shared</sst>',
});

/// Locate real generated ZIP records so security cases can lie consistently in
/// both directories, rather than relying on fabricated decoder responses.
({int central, int local, int content}) _entry(Uint8List bytes, String name) {
  final data = ByteData.sublistView(bytes);
  final end = bytes.length - 22;
  var offset = data.getUint32(end + 16, Endian.little);
  final count = data.getUint16(end + 10, Endian.little);
  for (var i = 0; i < count; i++) {
    final length = data.getUint16(offset + 28, Endian.little);
    final actual = utf8.decode(
      bytes.sublist(offset + 46, offset + 46 + length),
    );
    if (actual == name) {
      final local = data.getUint32(offset + 42, Endian.little);
      final content =
          local +
          30 +
          data.getUint16(local + 26, Endian.little) +
          data.getUint16(local + 28, Endian.little);
      return (central: offset, local: local, content: content);
    }
    offset +=
        46 +
        length +
        data.getUint16(offset + 30, Endian.little) +
        data.getUint16(offset + 32, Endian.little);
  }
  throw StateError('Fixture does not contain $name');
}

/// A valid, unused outer stored entry embeds another valid local header. Add
/// its central record without changing either name, CRC, size or content. Only
/// the overlap guard can distinguish it from an ordinary readable package.
Uint8List _overlappingZip() {
  final inner = _zip({'inner.xml': '<unused/>'}, stored: true);
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'word/document.xml',
        _doc('<w:p><w:r><w:t>safe</w:t></w:r></w:p>'),
      ),
    )
    ..add(
      ArchiveFile.bytes('outer.bin', inner)..compression = CompressionType.none,
    );
  final outer = ZipEncoder().encodeBytes(archive);
  expect(AttachmentDocumentService.parse(outer, 'docx').text, 'safe\n');
  final innerEntry = _entry(inner, 'inner.xml');
  final outerEntry = _entry(outer, 'outer.bin');
  final oldEnd = outer.length - 22;
  final central = Uint8List.fromList(
    inner.sublist(innerEntry.central, inner.length - 22),
  );
  ByteData.sublistView(
    central,
  ).setUint32(42, outerEntry.content + innerEntry.local, Endian.little);
  final result = Uint8List.fromList([
    ...outer.sublist(0, oldEnd),
    ...central,
    ...outer.sublist(oldEnd),
  ]);
  final data = ByteData.sublistView(result);
  final end = result.length - 22;
  data.setUint16(end + 8, 3, Endian.little);
  data.setUint16(end + 10, 3, Endian.little);
  data.setUint32(
    end + 12,
    data.getUint32(end + 12, Endian.little) + central.length,
    Endian.little,
  );
  return result;
}

void main() {
  test('only modern non-macro Office extensions are previewable', () {
    for (final extension in ['docx', 'xlsx', 'pptx', 'DOCX']) {
      expect(attachmentIsDocument(extension), isTrue);
    }
    for (final extension in [
      'doc',
      'xls',
      'ppt',
      'docm',
      'xlsm',
      'pptm',
      'zip',
    ]) {
      expect(attachmentIsDocument(extension), isFalse);
    }
  });

  test('DOCX preserves paragraphs, tabs, breaks, tables and Unicode', () {
    final result = AttachmentDocumentService.parse(
      _docx(
        '<w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/>'
        '</w:tabs></w:pPr><w:r><w:t>Hello &amp; </w:t></w:r>'
        '<w:r><w:t>世界😀</w:t><w:tab/><w:t>next</w:t>'
        '<w:br/><w:t>line</w:t><w:cr/><w:t>end</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>second paragraph</w:t></w:r></w:p></w:tc>'
        '</w:tr></w:tbl>',
      ),
      'docx',
    );
    expect(result.failed, isFalse);
    expect(
      result.text,
      'Hello & 世界😀\tnext\nline\nend\nA\tB\nsecond paragraph\n',
    );
  });

  test('stored ZIP entries and strict namespaces/nonstandard prefixes work', () {
    final result = AttachmentDocumentService.parse(
      _zip({
        'word/document.xml':
            '<x:document xmlns:x="http://purl.oclc.org/ooxml/wordprocessingml/main">'
            '<x:body><x:p><x:r><x:t>Strict</x:t></x:r></x:p></x:body></x:document>',
      }, stored: true),
      'docx',
    );
    expect(result.failed, isFalse);
    expect(result.text, 'Strict\n');
  });

  test('UTF-16 BOM XML is decoded without network or entity resolution', () {
    final xml = _doc('<w:p><w:r><w:t>Résumé 世界</w:t></w:r></w:p>');
    final encoded = BytesBuilder()..add([0xff, 0xfe]);
    for (final unit in xml.codeUnits) {
      encoded.add([unit & 255, unit >> 8]);
    }
    final archive = Archive()
      ..add(ArchiveFile.bytes('word/document.xml', encoded.takeBytes()));
    final result = AttachmentDocumentService.parse(
      ZipEncoder().encodeBytes(archive),
      'docx',
    );
    expect(result.failed, isFalse);
    expect(result.text, 'Résumé 世界\n');
  });

  test(
    'UTF-8 BOM and XML declaration work on selected DOCX/XLSX/PPTX parts',
    () {
      final fixtures = {
        'docx': {
          'word/document.xml': _doc(
            '<w:p><w:r><w:t>Résumé 世界</w:t></w:r></w:p>',
          ),
        },
        'xlsx': {
          'xl/workbook.xml': _workbook('<sheet name="Budget" r:id="r1"/>'),
          'xl/_rels/workbook.xml.rels': _rels(
            _rel('r1', 'worksheet', 'worksheets/sheet1.xml'),
          ),
          'xl/worksheets/sheet1.xml': _worksheet(
            '<row><c t="inlineStr"><is><t>Résumé 世界</t></is></c></row>',
          ),
        },
        'pptx': {
          'ppt/presentation.xml': _presentationXml(
            '<p:sldId id="1" r:id="r1"/>',
          ),
          'ppt/_rels/presentation.xml.rels': _rels(
            _rel('r1', 'slide', 'slides/slide1.xml'),
          ),
          'ppt/slides/slide1.xml': _slide(
            '<a:p><a:r><a:t>Résumé 世界</a:t></a:r></a:p>',
          ),
        },
      };
      for (final fixture in fixtures.entries) {
        final original = AttachmentDocumentService.parse(
          _zip(fixture.value),
          fixture.key,
        );
        expect(original.failed, isFalse);
        final bytes = _zip(
          fixture.value.map(
            (name, xml) => MapEntry(
              name,
              '\ufeff<?xml version="1.0" encoding="UTF-8"?>$xml',
            ),
          ),
        );
        final result = AttachmentDocumentService.parse(bytes, fixture.key);
        expect(result.failed, isFalse, reason: fixture.key);
        expect(result.text, original.text, reason: fixture.key);
        expect(result.text, contains('Résumé 世界'));
      }
    },
  );

  for (final cap in ['entry', 'aggregate']) {
    test(
      'streaming $cap cap rejects native output BEFORE retaining a chunk',
      () {
        // Keep the other limit above the entire native output, not merely
        // above the target limit. Otherwise it masks removal of this guard.
        final sink = AttachmentDocumentInflationSink(
          cap == 'entry' ? 64 : 256 * 1024,
          cap == 'aggregate' ? 64 : 256 * 1024,
        );
        sink.add(List<int>.filled(16, 7));
        final crc = sink.crc;
        final compressed = io.ZLibEncoder(
          raw: true,
        ).convert(Uint8List(128 * 1024));
        final decoder = io.ZLibDecoder(raw: true).startChunkedConversion(sink);
        expect(() {
          decoder.add(compressed);
          decoder.close();
        }, throwsFormatException);
        expect(sink.length, 16);
        expect(sink.bufferedBytes, 16);
        expect(sink.crc, crc);
        expect(sink.takeBytes(), List<int>.filled(16, 7));
      },
    );
  }

  test('streaming sink accepts the exact entry and aggregate boundary', () {
    final sink = AttachmentDocumentInflationSink(64, 64);
    sink.add(List<int>.filled(32, 1));
    sink.add(List<int>.filled(32, 2));
    expect(sink.length, 64);
    expect(sink.bufferedBytes, 64);
    expect(() => sink.add([3]), throwsFormatException);
    expect(sink.bufferedBytes, 64);
  });

  test('DOCX hyperlinks and escaped scripts remain ordinary inert text', () {
    final result = AttachmentDocumentService.parse(
      _zip({
        'word/document.xml': _doc(
          '<w:p><w:hyperlink><w:r><w:t>https://example.invalid/secret</w:t>'
          '</w:r></w:hyperlink><w:r>'
          '<w:t>&lt;script&gt;fetch("remote")&lt;/script&gt;</w:t>'
          '<w:instrText>DO NOT EVALUATE</w:instrText></w:r></w:p>',
        ),
        'word/_rels/document.xml.rels': _rels(
          _rel('link', 'hyperlink', 'https://example.invalid', external: true),
        ),
        'word/vbaProject.bin': 'this is ignored, not executed',
      }),
      'docx',
    );
    expect(result.failed, isFalse);
    expect(result.text, contains('https://example.invalid/secret'));
    expect(result.text, contains('<script>fetch("remote")</script>'));
    expect(result.text, isNot(contains('DO NOT EVALUATE')));
  });

  test(
    'XLSX shared/inline strings, blank and missing cells keep coordinates',
    () {
      final result = AttachmentDocumentService.parse(
        _xlsx(
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"/>'
          '<c r="D1" t="inlineStr"><is><r><t>In</t></r><r><t>line</t></r>'
          '</is></c></row>'
          '<row r="3"><c r="C3"><v>42.5</v></c>'
          '<c><f>HYPERLINK("https://example.invalid")</f><v>7</v></c>'
          '<c r="F3" t="b"><v>1</v></c></row>',
          shared:
              '<si><r><t>Shared </t></r><r><t>世界</t></r>'
              '<rPh sb="0" eb="1"><t>phonetic-not-visible</t></rPh></si>',
        ),
        'xlsx',
      );
      expect(result.failed, isFalse);
      expect(
        result.text,
        '[Budget]\nA1\tShared 世界\nB1\t\nD1\tInline\nC3\t42.5\nD3\t7\nF3\t1\n',
      );
      expect(result.text, isNot(contains('HYPERLINK')));
      expect(result.text, isNot(contains('phonetic')));
    },
  );

  for (final requires in ['wps', 'unknown']) {
    for (final fallback in ['Textbox', 'Legacy alternative']) {
      test('DOCX alternate textbox selects one branch: $requires / $fallback', () {
        String textbox(String text) =>
            '<w:txbxContent><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:txbxContent>';
        final bytes = _zip({
          'word/document.xml':
              '<w:document xmlns:w="$_word" '
              'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
              'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" '
              'xmlns:unknown="urn:unsupported-textbox" xmlns:v="urn:schemas-microsoft-com:vml">'
              '<w:body><mc:AlternateContent><mc:Choice Requires="$requires">'
              '<wps:wsp>${textbox('Textbox')}</wps:wsp></mc:Choice>'
              '<mc:Fallback><v:shape>${textbox(fallback)}</v:shape></mc:Fallback>'
              '</mc:AlternateContent><w:p><w:r><w:t>After</w:t></w:r></w:p>'
              '</w:body></w:document>',
        });
        final result = AttachmentDocumentService.parse(bytes, 'docx');
        expect(result.failed, isFalse);
        final selected = requires == 'wps' ? 'Textbox' : fallback;
        expect(result.text, '$selected\nAfter\n');
      });
    }
  }

  test(
    'XLSX chart tabs do not discard readable worksheets or read chart data',
    () {
      final result = AttachmentDocumentService.parse(
        _zip({
          'xl/workbook.xml': _workbook(
            '<sheet name="Chart" sheetId="1" r:id="chart"/>'
            '<sheet name="Data" sheetId="2" r:id="data"/>',
          ),
          'xl/_rels/workbook.xml.rels': _rels(
            _rel('chart', 'chartsheet', 'chartsheets/sheet1.xml') +
                _rel('data', 'worksheet', 'worksheets/sheet1.xml'),
          ),
          'xl/chartsheets/sheet1.xml': 'not parsed: chart data is unsupported',
          'xl/worksheets/sheet1.xml': _worksheet(
            '<row><c t="inlineStr"><is><t>visible</t></is></c></row>',
          ),
        }),
        'xlsx',
      );
      expect(result.failed, isFalse);
      expect(result.text, '[Data]\nA1\tvisible\n');
    },
  );

  test('XLSX missing worksheet relationships still fail closed', () {
    final result = AttachmentDocumentService.parse(
      _zip({
        'xl/workbook.xml': _workbook(
          '<sheet name="Data" sheetId="1" r:id="missing"/>',
        ),
        'xl/_rels/workbook.xml.rels': _rels(''),
      }),
      'xlsx',
    );
    expect(result.failed, isTrue);
  });

  test(
    'XLSX sheet cap has valid exact-boundary and over-boundary controls',
    () {
      final bytes = _zip({
        'xl/workbook.xml': _workbook(
          '<sheet name="One" r:id="a"/><sheet name="Two" r:id="b"/>',
        ),
        'xl/_rels/workbook.xml.rels': _rels(
          _rel('a', 'worksheet', 'worksheets/a.xml') +
              _rel('b', 'worksheet', 'worksheets/b.xml'),
        ),
        'xl/worksheets/a.xml': _worksheet('<row><c><v>1</v></c></row>'),
        'xl/worksheets/b.xml': _worksheet('<row><c><v>2</v></c></row>'),
      });
      final exact = AttachmentDocumentService.parse(
        bytes,
        'xlsx',
        limits: const AttachmentDocumentLimits(maxSections: 2),
      );
      expect(exact.failed, isFalse);
      expect(exact.text, '[One]\nA1\t1\n\n[Two]\nA1\t2\n');
      final rejected = AttachmentDocumentService.parse(
        bytes,
        'xlsx',
        limits: const AttachmentDocumentLimits(maxSections: 1),
      );
      expect(rejected.failed, isTrue);
      expect(rejected.text, isEmpty);
    },
  );

  test('XLSX uses workbook relationship order and actual sheet titles', () {
    final result = AttachmentDocumentService.parse(
      _zip({
        'xl/workbook.xml': _workbook(
          '<sheet name="Second file first" sheetId="9" r:id="second"/>'
          '<sheet name="First file last" sheetId="2" r:id="first"/>',
        ),
        'xl/_rels/workbook.xml.rels': _rels(
          _rel('first', 'worksheet', '/xl/worksheets/sheet1.xml') +
              _rel('second', 'worksheet', 'worksheets/sheet9.xml'),
        ),
        'xl/worksheets/sheet1.xml': _worksheet('<row><c><v>1</v></c></row>'),
        'xl/worksheets/sheet9.xml': _worksheet('<row><c><v>9</v></c></row>'),
      }),
      'xlsx',
    );
    expect(result.failed, isFalse);
    expect(
      result.text,
      '[Second file first]\nA1\t9\n\n[First file last]\nA1\t1\n',
    );
  });

  test(
    'sparse XLSX does not allocate rows/columns for a distant coordinate',
    () {
      final result = AttachmentDocumentService.parse(
        _xlsx('<row r="1048576"><c r="XFD1048576"><v>9</v></c></row>'),
        'xlsx',
      );
      expect(result.failed, isFalse);
      expect(result.text, '[Budget]\nXFD1048576\t9\n');
    },
  );

  for (final rows in [
    '<row r="1"><c r="A2"><v>1</v></c></row>',
    '<row r="1"><c r="XFE1"><v>1</v></c></row>',
    '<row r="1048577"><c><v>1</v></c></row>',
    '<row><c r="B1"/><c r="A1"/></row>',
    '<row><c t="s"><v>9</v></c></row>',
    '<row><c t="s"><v>-1</v></c></row>',
  ]) {
    test(
      'invalid XLSX coordinate/shared-string reference fails safely: $rows',
      () {
        expect(
          AttachmentDocumentService.parse(_xlsx(rows), 'xlsx').failed,
          isTrue,
        );
      },
    );
  }

  test('PPTX follows presentation IDs, not ZIP/relationship/lexical order', () {
    final result = AttachmentDocumentService.parse(
      _zip({
        'ppt/slides/slide1.xml': _slide(
          '<a:p><a:r><a:t>unlisted</a:t></a:r></a:p>',
        ),
        'ppt/slides/slide2.xml': _slide(
          '<a:p><a:r><a:t>last</a:t></a:r></a:p>',
        ),
        'ppt/slides/slide10.xml': _slide(
          '<a:p><a:r><a:t>first</a:t></a:r><a:br/>'
          '<a:r><a:t>line two</a:t></a:r></a:p>'
          '<a:p><a:r><a:t>second paragraph</a:t></a:r></a:p>',
        ),
        'ppt/presentation.xml': _presentationXml(
          '<p:sldId id="400" r:id="ten"/><p:sldId id="300" r:id="two"/>',
        ),
        'ppt/_rels/presentation.xml.rels': _rels(
          _rel('two', 'slide', 'slides/slide2.xml') +
              _rel('ten', 'slide', 'slides/slide10.xml') +
              _rel(
                'web',
                'hyperlink',
                'https://example.invalid',
                external: true,
              ),
        ),
      }),
      'pptx',
    );
    expect(result.failed, isFalse);
    expect(result.text, 'first\nline two\nsecond paragraph\n\nlast\n');
  });

  test('valid empty DOCX, XLSX and PPTX have a distinct empty result', () {
    final fixtures = {
      'docx': _docx(''),
      'xlsx': _xlsx(''),
      'pptx': _zip({
        'ppt/presentation.xml': _presentationXml(''),
        'ppt/_rels/presentation.xml.rels': _rels(''),
      }),
    };
    for (final fixture in fixtures.entries) {
      final result = AttachmentDocumentService.parse(
        fixture.value,
        fixture.key,
      );
      expect(result.failed, isFalse, reason: fixture.key);
      expect(result.isEmpty, isTrue, reason: fixture.key);
    }
  });

  test('malformed containers, XML, wrong roots and binary extensions fail', () {
    final fixtures = [
      Uint8List(0),
      Uint8List.fromList([1, 2, 3]),
      _zip({'word/document.xml': '<broken>'}),
      _zip({'word/document.xml': _doc('<w:p><w:r><w:t>prefix</w:t></w:p>')}),
      _zip({
        'word/document.xml': '<document xmlns="untrusted"><t>no</t></document>',
      }),
      _zip({'word/document.xml': '${_doc('')}<another/>'}),
      _zip({'unrelated.xml': '<root/>'}),
    ];
    for (final fixture in fixtures) {
      final result = AttachmentDocumentService.parse(fixture, 'docx');
      expect(result.failed, isTrue);
      expect(result.text, isEmpty);
      expect(result.truncated, isFalse);
    }
    expect(AttachmentDocumentService.parse(_docx(''), 'doc').failed, isTrue);
  });

  test('rejects external DTD, custom entities and stylesheet instructions', () {
    for (final prefix in [
      '<!DOCTYPE w:document SYSTEM "https://example.invalid/private.dtd">',
      '<!DOCTYPE w:document [<!ENTITY a "text"><!ENTITY b "&a;&a;&a;">]>',
      '<?xml-stylesheet href="https://example.invalid/style.xsl"?>',
    ]) {
      final result = AttachmentDocumentService.parse(
        _zip({
          'word/document.xml':
              prefix + _doc('<w:p><w:r><w:t>safe</w:t></w:r></w:p>'),
        }),
        'docx',
      );
      expect(result.failed, isTrue);
      expect(result.text, isEmpty);
    }
  });

  test(
    'malformed XML references, duplicate attributes and oversized tags fail',
    () {
      for (final xml in [
        _doc('<w:p><w:r><w:t>&unknown;</w:t></w:r></w:p>'),
        _doc('<w:p><w:r><w:t>${'&' * 2048}</w:t></w:r></w:p>'),
        _doc('<w:p><w:r><w:t>&#0;</w:t></w:r></w:p>'),
        _doc('<w:p w:rsidR="1" w:rsidR="2"/>'),
        'outside${_doc('')}',
        '${_doc('')}outside',
        _doc('<w:p attribute="${'x' * (17 * 1024)}"/>'),
        _doc('<w:p>\u0000</w:p>'),
      ]) {
        final result = AttachmentDocumentService.parse(
          _zip({'word/document.xml': xml}),
          'docx',
        );
        expect(result.failed, isTrue);
        expect(result.text, isEmpty);
      }
      final cdata = AttachmentDocumentService.parse(
        _docx('<w:p><w:r><w:t><![CDATA[bare & <inert>]]></w:t></w:r></w:p>'),
        'docx',
      );
      expect(cdata.failed, isFalse);
      expect(cdata.text, 'bare & <inert>\n');
    },
  );

  test('selected external and escaping relationship targets are not read', () {
    for (final target in [
      'https://example.invalid/sheet.xml',
      '//example.invalid/sheet.xml',
      '../../../secret.xml',
      'worksheets/%2e%2e/%2e%2e/%2e%2e/secret.xml',
      'worksheets/sheet1.xml?secret=1',
      'worksheets/sheet1.xml#fragment',
      r'worksheets\sheet1.xml',
    ]) {
      expect(
        AttachmentDocumentService.parse(
          _xlsx('', target: target),
          'xlsx',
        ).failed,
        isTrue,
        reason: target,
      );
    }
    final external = _zip({
      'xl/workbook.xml': _workbook('<sheet name="Remote" r:id="r1"/>'),
      'xl/_rels/workbook.xml.rels': _rels(
        _rel(
          'r1',
          'worksheet',
          'https://example.invalid/x.xml',
          external: true,
        ),
      ),
    });
    expect(AttachmentDocumentService.parse(external, 'xlsx').failed, isTrue);
  });

  test(
    'relative leading dot segments survive Uri normalization and remain guarded',
    () {
      expect(Uri.parse('../../../secret.xml').pathSegments, [
        '..',
        '..',
        '..',
        'secret.xml',
      ]);
      expect(
        Uri.parse('worksheets/%2e%2e/%2e%2e/%2e%2e/secret.xml').pathSegments,
        ['..', '..', 'secret.xml'],
      );
      for (final target in [
        '../xl/worksheets/sheet1.xml',
        '%2e%2e/xl/worksheets/sheet1.xml',
        'worksheets/../worksheets/sheet1.xml',
      ]) {
        final result = AttachmentDocumentService.parse(
          _xlsx('<row><c><v>7</v></c></row>', target: target),
          'xlsx',
        );
        expect(result.failed, isFalse, reason: target);
        expect(result.text, '[Budget]\nA1\t7\n');
      }
      // A valid selected part exists: this rejection cannot be explained by a
      // missing worksheet. Relative over-root traversal must still fail closed.
      for (final target in [
        '../../xl/worksheets/sheet1.xml',
        '%2e%2e/%2e%2e/xl/worksheets/sheet1.xml',
      ]) {
        expect(
          AttachmentDocumentService.parse(
            _xlsx('', target: target),
            'xlsx',
          ).failed,
          isTrue,
          reason: target,
        );
      }
    },
  );

  for (final invalid in [
    '../unused.xml',
    '/unused.xml',
    r'bad\name.xml',
    'bad:name.xml',
    'a//unused.xml',
    'a/./unused.xml',
    'a/../unused.xml',
    'bad\u0000name.xml',
    'bad\u007fname.xml',
  ]) {
    test(
      'invalid unused ZIP name rejects an otherwise valid DOCX: ${jsonEncode(invalid)}',
      () {
        // ArchiveFile can normalize names, so rename both local/central records
        // explicitly. All other metadata/integrity and the selected part remain valid.
        final placeholder = 'x' * utf8.encode(invalid).length;
        final bytes = _zip({
          'word/document.xml': _doc('<w:p><w:r><w:t>safe</w:t></w:r></w:p>'),
          placeholder: '<unused/>',
        });
        expect(AttachmentDocumentService.parse(bytes, 'docx').text, 'safe\n');
        final entry = _entry(bytes, placeholder);
        final name = utf8.encode(invalid);
        bytes.setRange(
          entry.central + 46,
          entry.central + 46 + name.length,
          name,
        );
        bytes.setRange(entry.local + 30, entry.local + 30 + name.length, name);
        expect(AttachmentDocumentService.parse(bytes, 'docx').failed, isTrue);
      },
    );
  }

  test(
    'valid local entries nested in an unused stored entry are rejected as overlapping',
    () {
      final bytes = _overlappingZip();
      expect(AttachmentDocumentService.parse(bytes, 'docx').failed, isTrue);
    },
  );

  test('fixed memory-related default budgets remain unchanged', () {
    const limits = AttachmentDocumentLimits();
    expect(limits.maxCompressedBytes, 25 * 1024 * 1024);
    expect(limits.maxEntryBytes, 4 * 1024 * 1024);
    expect(limits.maxInflatedBytes, 16 * 1024 * 1024);
    expect(limits.maxEntries, 1024);
    expect(limits.maxTextCharacters, 64 * 1024);
    expect(limits.maxXmlDepth, 64);
    expect(limits.maxXmlEvents, 200000);
  });

  test('unused corrupt compressed image data is never eagerly inflated', () {
    final bytes = _zip({
      'word/document.xml': _doc('<w:p><w:r><w:t>readable</w:t></w:r></w:p>'),
      'word/media/image.bin': 'not an actual image; never decoded',
    });
    final entry = _entry(bytes, 'word/media/image.bin');
    bytes[entry.content] ^= 0xff;
    final result = AttachmentDocumentService.parse(bytes, 'docx');
    expect(result.failed, isFalse);
    expect(result.text, 'readable\n');
  });

  test(
    'entry size, aggregate inflation, count and input caps are enforced',
    () {
      final xml = _doc('<w:p><w:r><w:t>hello</w:t></w:r></w:p>');
      final bytes = _zip({'word/document.xml': xml, 'unused.xml': xml});
      for (final limits in [
        AttachmentDocumentLimits(maxEntryBytes: utf8.encode(xml).length - 1),
        AttachmentDocumentLimits(
          maxInflatedBytes: utf8.encode(xml).length * 2 - 1,
        ),
        const AttachmentDocumentLimits(maxEntries: 1),
        AttachmentDocumentLimits(maxCompressedBytes: bytes.length - 1),
      ]) {
        expect(
          AttachmentDocumentService.parse(bytes, 'docx', limits: limits).failed,
          isTrue,
        );
      }
    },
  );

  test(
    'dishonest small size metadata cannot bypass streaming output limits',
    () {
      final bytes = _docx(
        '<w:p><w:r><w:t>${'x' * (128 * 1024)}</w:t></w:r></w:p>',
      );
      final entry = _entry(bytes, 'word/document.xml');
      final data = ByteData.sublistView(bytes)
        ..setUint32(entry.central + 24, 32, Endian.little)
        ..setUint32(entry.local + 22, 32, Endian.little);
      expect(data.lengthInBytes, bytes.length);
      final result = AttachmentDocumentService.parse(
        bytes,
        'docx',
        limits: const AttachmentDocumentLimits(
          maxEntryBytes: 256,
          maxInflatedBytes: 512,
        ),
      );
      expect(result.failed, isTrue);
      expect(result.text, isEmpty);
    },
  );

  test('text truncates at its cap and never leaves an unmatched surrogate', () {
    final result = AttachmentDocumentService.parse(
      _docx('<w:p><w:r><w:t>123456789😀rest</w:t></w:r></w:p>'),
      'docx',
      limits: const AttachmentDocumentLimits(maxTextCharacters: 10),
    );
    expect(result.failed, isFalse);
    expect(result.truncated, isTrue);
    expect(result.text, '123456789');
    expect(result.text.length, lessThanOrEqualTo(10));
    final exact = AttachmentDocumentService.parse(
      _docx('<w:p><w:r><w:t>123456789</w:t></w:r></w:p>'),
      'docx',
      limits: const AttachmentDocumentLimits(maxTextCharacters: 10),
    );
    expect(exact.text, '123456789\n');
    expect(exact.truncated, isFalse);
  });

  test('XML event/depth and shared-string/section budgets are enforced', () {
    final doc = _docx('<w:p><w:r><w:t>hello</w:t></w:r></w:p>');
    for (final limits in [
      const AttachmentDocumentLimits(maxXmlEvents: 3),
      const AttachmentDocumentLimits(maxXmlDepth: 3),
    ]) {
      expect(
        AttachmentDocumentService.parse(doc, 'docx', limits: limits).failed,
        isTrue,
      );
    }
    expect(
      AttachmentDocumentService.parse(
        _xlsx('', shared: '<si><t>one</t></si><si><t>two</t></si>'),
        'xlsx',
        limits: const AttachmentDocumentLimits(maxSharedStrings: 1),
      ).failed,
      isTrue,
    );
    expect(
      AttachmentDocumentService.parse(
        _zip({
          'ppt/presentation.xml': _presentationXml(
            '<p:sldId id="1" r:id="a"/><p:sldId id="2" r:id="b"/>',
          ),
          'ppt/_rels/presentation.xml.rels': _rels(''),
        }),
        'pptx',
        limits: const AttachmentDocumentLimits(maxSections: 1),
      ).failed,
      isTrue,
    );
  });

  test('ZIP CRC mismatch and local/directory disagreements fail closed', () {
    for (final corrupt
        in <void Function(Uint8List, ({int central, int local, int content}))>[
          (bytes, entry) => bytes[entry.content] ^= 1,
          (bytes, entry) => ByteData.sublistView(
            bytes,
          ).setUint32(entry.central + 16, 0, Endian.little),
          (bytes, entry) => bytes[entry.local + 30] ^= 1,
          (bytes, entry) => ByteData.sublistView(
            bytes,
          ).setUint32(entry.central + 42, 0xffffff00, Endian.little),
        ]) {
      final bytes = _docx(
        '<w:p><w:r><w:t>safe</w:t></w:r></w:p>',
        stored: true,
      );
      corrupt(bytes, _entry(bytes, 'word/document.xml'));
      expect(AttachmentDocumentService.parse(bytes, 'docx').failed, isTrue);
    }
  });

  test(
    'encrypted, symlink and unsupported compression entries are rejected',
    () {
      for (final kind in ['encrypted', 'symlink', 'compression']) {
        final bytes = _docx('<w:p/>');
        final entry = _entry(bytes, 'word/document.xml');
        final data = ByteData.sublistView(bytes);
        if (kind == 'encrypted') {
          data.setUint16(entry.central + 8, 1, Endian.little);
          data.setUint16(entry.local + 6, 1, Endian.little);
        } else if (kind == 'symlink') {
          data.setUint32(entry.central + 38, 0xa1ff0000, Endian.little);
        } else {
          data.setUint16(entry.central + 10, 12, Endian.little);
          data.setUint16(entry.local + 8, 12, Endian.little);
        }
        expect(
          AttachmentDocumentService.parse(bytes, 'docx').failed,
          isTrue,
          reason: kind,
        );
      }
    },
  );

  test('path traversal, duplicate names and multipart/ZIP64 metadata fail', () {
    expect(
      AttachmentDocumentService.parse(
        _zip({'../word/document.xml': _doc('')}),
        'docx',
      ).failed,
      isTrue,
    );
    final duplicate = _zip({
      'word/document.xml': _doc(''),
      'word/documenx.xml': _doc(''),
    });
    final entry = _entry(duplicate, 'word/documenx.xml');
    final replacement = utf8.encode('word/document.xml');
    duplicate.setRange(
      entry.central + 46,
      entry.central + 46 + replacement.length,
      replacement,
    );
    duplicate.setRange(
      entry.local + 30,
      entry.local + 30 + replacement.length,
      replacement,
    );
    expect(AttachmentDocumentService.parse(duplicate, 'docx').failed, isTrue);
    for (final zip64 in [false, true]) {
      final bytes = _docx('');
      final data = ByteData.sublistView(bytes);
      final end = bytes.length - 22;
      data.setUint16(end + (zip64 ? 10 : 4), zip64 ? 0xffff : 1, Endian.little);
      expect(AttachmentDocumentService.parse(bytes, 'docx').failed, isTrue);
    }
  });

  test(
    'worker parses a snapshot even when caller mutates its original input',
    () async {
      final bytes = _docx('<w:p><w:r><w:t>snapshot</w:t></w:r></w:p>');
      final pending = AttachmentDocumentService.preview(bytes, 'DOCX');
      bytes.fillRange(0, bytes.length, 0);
      final result = await pending;
      expect(result.failed, isFalse);
      expect(result.text, 'snapshot\n');
    },
  );
}
