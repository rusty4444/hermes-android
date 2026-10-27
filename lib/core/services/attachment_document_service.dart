import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:flutter/foundation.dart'
    show compute, immutable, visibleForTesting;
import 'package:xml/xml.dart' show XmlDefaultEntityMapping;
import 'package:xml/xml_events.dart';

/// Only the ZIP/XML Office formats are supported, not legacy binary or macro
/// enabled documents. The preview never follows links or evaluates formulas.
bool attachmentIsDocument(String extension) =>
    const {'docx', 'xlsx', 'pptx'}.contains(extension.toLowerCase());

@immutable
class AttachmentDocumentLimits {
  const AttachmentDocumentLimits({
    this.maxCompressedBytes = 25 * 1024 * 1024,
    this.maxEntries = 1024,
    this.maxEntryBytes = 4 * 1024 * 1024,
    this.maxInflatedBytes = 16 * 1024 * 1024,
    this.maxTextCharacters = 64 * 1024,
    this.maxXmlEvents = 200000,
    this.maxXmlDepth = 64,
    this.maxSharedStrings = 20000,
    this.maxSections = 256,
  });

  final int maxCompressedBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final int maxInflatedBytes;
  final int maxTextCharacters;
  final int maxXmlEvents;
  final int maxXmlDepth;
  final int maxSharedStrings;
  final int maxSections;

  bool get _valid =>
      maxCompressedBytes > 0 &&
      maxEntries > 0 &&
      maxEntryBytes > 0 &&
      maxInflatedBytes > 0 &&
      maxTextCharacters > 0 &&
      maxXmlEvents > 0 &&
      maxXmlDepth > 0 &&
      maxSharedStrings > 0 &&
      maxSections > 0;
}

@immutable
class AttachmentDocumentPreviewData {
  const AttachmentDocumentPreviewData({
    this.text = '',
    this.truncated = false,
    this.failed = false,
  });

  const AttachmentDocumentPreviewData.failed()
    : text = '',
      truncated = false,
      failed = true;

  final String text;
  final bool truncated;
  final bool failed;
  bool get isEmpty => !failed && text.trim().isEmpty;
}

/// No filesystem, network, external viewer, WebView, or active-content reads.
/// Each native preview parses in a worker isolate and returns only inert text.
class AttachmentDocumentService {
  static Future<AttachmentDocumentPreviewData> preview(
    Uint8List bytes,
    String extension, {
    AttachmentDocumentLimits limits = const AttachmentDocumentLimits(),
  }) async {
    if (!_validInput(bytes, extension, limits)) {
      return const AttachmentDocumentPreviewData.failed();
    }
    // Snapshot before the async boundary. Neither caller mutations nor worker
    // mutations can change the input associated with a displayed preview.
    final request = _DocumentRequest(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      extension.toLowerCase(),
      limits,
    );
    try {
      return await compute(
        _parseDocument,
        request,
        debugLabel: 'office-preview',
      );
    } catch (_) {
      return const AttachmentDocumentPreviewData.failed();
    }
  }

  /// Synchronous seam for malicious-container/budget tests. UI code uses
  /// [preview], never this method, so decompression/XML stay off its isolate.
  @visibleForTesting
  static AttachmentDocumentPreviewData parse(
    Uint8List bytes,
    String extension, {
    AttachmentDocumentLimits limits = const AttachmentDocumentLimits(),
  }) =>
      _parseDocument(_DocumentRequest(bytes, extension.toLowerCase(), limits));
}

bool _validInput(
  Uint8List bytes,
  String extension,
  AttachmentDocumentLimits limits,
) =>
    limits._valid &&
    attachmentIsDocument(extension) &&
    bytes.isNotEmpty &&
    bytes.length <= limits.maxCompressedBytes;

@immutable
class _DocumentRequest {
  const _DocumentRequest(this.bytes, this.extension, this.limits);
  final Uint8List bytes;
  final String extension;
  final AttachmentDocumentLimits limits;
}

AttachmentDocumentPreviewData _parseDocument(_DocumentRequest request) {
  final output = _LimitedText(request.limits.maxTextCharacters);
  try {
    if (!_validInput(request.bytes, request.extension, request.limits)) {
      return const AttachmentDocumentPreviewData.failed();
    }
    final package = _OfficePackage(request.bytes, request.limits);
    switch (request.extension) {
      case 'docx':
        _readWord(package, output);
      case 'xlsx':
        _readWorkbook(package, output);
      case 'pptx':
        _readPresentation(package, output);
    }
    return AttachmentDocumentPreviewData(text: output.text);
  } on _TextLimitReached {
    return AttachmentDocumentPreviewData(text: output.text, truncated: true);
  } catch (_) {
    // No parser details or untrusted XML are exposed to the user on failure.
    return const AttachmentDocumentPreviewData.failed();
  }
}

class _TextLimitReached implements Exception {
  const _TextLimitReached();
}

class _LimitedText {
  _LimitedText(this.limit);
  final int limit;
  final _buffer = StringBuffer();
  String get text => _buffer.toString();

  void add(String value) {
    final remaining = limit - _buffer.length;
    if (value.length <= remaining) {
      _buffer.write(value);
      return;
    }
    var end = remaining;
    // Do not split an emoji/non-BMP character at the preview boundary.
    if (end > 0 &&
        value.codeUnitAt(end - 1) >= 0xd800 &&
        value.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    _buffer.write(value.substring(0, end));
    throw const _TextLimitReached();
  }
}

const _wordNamespaces = {
  'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  'http://purl.oclc.org/ooxml/wordprocessingml/main',
};
const _sheetNamespaces = {
  'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
  'http://purl.oclc.org/ooxml/spreadsheetml/main',
};
const _presentationNamespaces = {
  'http://schemas.openxmlformats.org/presentationml/2006/main',
  'http://purl.oclc.org/ooxml/presentationml/main',
};
const _drawingNamespaces = {
  'http://schemas.openxmlformats.org/drawingml/2006/main',
  'http://purl.oclc.org/ooxml/drawingml/main',
};
const _officeRelationshipNamespaces = {
  'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
  'http://purl.oclc.org/ooxml/officeDocument/relationships',
};
const _packageRelationshipNamespaces = {
  'http://schemas.openxmlformats.org/package/2006/relationships',
  'http://purl.oclc.org/ooxml/package/relationships',
};

bool _is(XmlStartElementEvent element, Set<String> namespaces, String name) =>
    element.localName == name && namespaces.contains(element.namespaceUri);

String? _attribute(XmlStartElementEvent element, String name) {
  for (final attribute in element.attributes) {
    if (attribute.name == name) return attribute.value;
  }
  return null;
}

String _relationshipId(XmlStartElementEvent element) {
  for (final attribute in element.attributes) {
    if (attribute.localName == 'id' &&
        _officeRelationshipNamespaces.contains(attribute.namespaceUri)) {
      return attribute.value;
    }
  }
  throw const FormatException('Missing relationship');
}

bool _hasAncestor(
  XmlStartElementEvent element,
  Set<String> namespaces,
  String name,
) {
  for (var parent = element.parent; parent != null; parent = parent.parent) {
    if (_is(parent, namespaces, name)) return true;
  }
  return false;
}

void _readWord(_OfficePackage package, _LimitedText output) {
  final rowCells = <int>[];
  var cellParagraphs = 0;
  package.walk(
    'word/document.xml',
    _wordNamespaces,
    'document',
    onStart: (element) {
      if (_is(element, _wordNamespaces, 'tr')) rowCells.add(0);
      if (_is(element, _wordNamespaces, 'tc')) {
        if (rowCells.isNotEmpty) {
          if (rowCells.last > 0) output.add('\t');
          rowCells[rowCells.length - 1]++;
        }
        cellParagraphs = 0;
      }
      if (_is(element, _wordNamespaces, 'p') &&
          _hasAncestor(element, _wordNamespaces, 'tc')) {
        if (cellParagraphs++ > 0) output.add('\n');
      }
      final inRun = _hasAncestor(element, _wordNamespaces, 'r');
      if (inRun && _is(element, _wordNamespaces, 'tab')) output.add('\t');
      if (inRun &&
          (_is(element, _wordNamespaces, 'br') ||
              _is(element, _wordNamespaces, 'cr'))) {
        output.add('\n');
      }
    },
    onText: (text, parent) {
      if (parent != null && _is(parent, _wordNamespaces, 't')) output.add(text);
    },
    onEnd: (element) {
      if (_is(element, _wordNamespaces, 'p') &&
          !_hasAncestor(element, _wordNamespaces, 'tc')) {
        output.add('\n');
      }
      if (_is(element, _wordNamespaces, 'tr')) {
        output.add('\n');
        rowCells.removeLast();
      }
    },
  );
}

class _Relationship {
  const _Relationship(this.type, this.part);
  final String type;
  final String part;
  bool isType(String name) => _officeRelationshipNamespaces.any(
    (namespace) => type == '$namespace/$name',
  );
}

Map<String, _Relationship> _relationships(
  _OfficePackage package,
  String source,
) {
  final slash = source.lastIndexOf('/');
  final path =
      '${source.substring(0, slash + 1)}_rels/${source.substring(slash + 1)}.rels';
  final result = <String, _Relationship>{};
  final ids = <String>{};
  package.walk(
    path,
    _packageRelationshipNamespaces,
    'Relationships',
    onStart: (element) {
      if (!_is(element, _packageRelationshipNamespaces, 'Relationship')) return;
      final id = _attribute(element, 'Id');
      final type = _attribute(element, 'Type');
      final target = _attribute(element, 'Target');
      if (id == null ||
          id.isEmpty ||
          !ids.add(id) ||
          type == null ||
          target == null) {
        throw const FormatException('Invalid relationship');
      }
      final mode = _attribute(element, 'TargetMode');
      // External hyperlinks, images, etc. are never read, resolved or fetched.
      if (mode == 'External') return;
      if (mode != null && mode != 'Internal') {
        throw const FormatException('Invalid relationship mode');
      }
      // Unused image/chart/macro relationships are intentionally not read.
      final relationship = _Relationship(type, '');
      if (relationship.isType('chartsheet') ||
          relationship.isType('dialogsheet') ||
          relationship.isType('macrosheet') ||
          relationship.isType('intlMacrosheet')) {
        // Retain the type without resolving or reading unsupported sheet data.
        result[id] = relationship;
      } else if (relationship.isType('worksheet') ||
          relationship.isType('sharedStrings') ||
          relationship.isType('slide')) {
        result[id] = _Relationship(type, _resolvePart(source, target));
      }
    },
  );
  return result;
}

String _resolvePart(String source, String target) {
  final uri = Uri.parse(target);
  if (uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      target.contains('\\')) {
    throw const FormatException('Not an internal part');
  }
  final segments = target.startsWith('/')
      ? <String>[]
      : (source.split('/')..removeLast());
  for (final segment in uri.pathSegments) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isEmpty) throw const FormatException('Part escapes package');
      segments.removeLast();
    } else {
      if (segment.contains('/') ||
          segment.contains('\\') ||
          segment.contains(':') ||
          segment.codeUnits.any((unit) => unit < 32 || unit == 127)) {
        throw const FormatException('Invalid part name');
      }
      segments.add(segment);
    }
  }
  return segments.join('/');
}

String _relatedPart(
  Map<String, _Relationship> relationships,
  String id,
  String type,
  String prefix,
) {
  final relationship = relationships[id];
  if (relationship == null ||
      !relationship.isType(type) ||
      !relationship.part.startsWith(prefix) ||
      !relationship.part.endsWith('.xml')) {
    throw const FormatException('Missing internal document part');
  }
  return relationship.part;
}

void _readWorkbook(_OfficePackage package, _LimitedText output) {
  final relationships = _relationships(package, 'xl/workbook.xml');
  final sheets = <({String name, String id})>[];
  package.walk(
    'xl/workbook.xml',
    _sheetNamespaces,
    'workbook',
    onStart: (element) {
      if (!_is(element, _sheetNamespaces, 'sheet')) return;
      if (sheets.length >= package.limits.maxSections) {
        throw const FormatException('Too many sheets');
      }
      final name = _attribute(element, 'name');
      if (name == null) throw const FormatException('Missing sheet name');
      sheets.add((name: name, id: _relationshipId(element)));
    },
  );
  final sharedParts = relationships.values
      .where((relationship) => relationship.isType('sharedStrings'))
      .toList();
  if (sharedParts.length > 1) {
    throw const FormatException('Ambiguous shared strings');
  }
  final shared = sharedParts.isEmpty
      ? const <String>[]
      : _readSharedStrings(package, sharedParts.single.part);
  final seen = <String>{};
  for (final sheet in sheets) {
    final relationship = relationships[sheet.id];
    if (relationship != null &&
        (relationship.isType('chartsheet') ||
            relationship.isType('dialogsheet') ||
            relationship.isType('macrosheet') ||
            relationship.isType('intlMacrosheet'))) {
      continue;
    }
    final path = _relatedPart(
      relationships,
      sheet.id,
      'worksheet',
      'xl/worksheets/',
    );
    if (!seen.add(path)) throw const FormatException('Duplicate sheet');
    _readSheet(package, path, sheet.name, shared, output);
  }
}

List<String> _readSharedStrings(_OfficePackage package, String path) {
  if (!path.startsWith('xl/') || !path.endsWith('.xml')) {
    throw const FormatException('Invalid shared strings part');
  }
  final result = <String>[];
  StringBuffer? current;
  package.walk(
    path,
    _sheetNamespaces,
    'sst',
    onStart: (element) {
      if (_is(element, _sheetNamespaces, 'si')) {
        if (current != null ||
            result.length >= package.limits.maxSharedStrings) {
          throw const FormatException('Too many shared strings');
        }
        current = StringBuffer();
      }
    },
    onText: (text, parent) {
      if (parent != null &&
          _is(parent, _sheetNamespaces, 't') &&
          !_hasAncestor(parent, _sheetNamespaces, 'rPh')) {
        current?.write(text);
      }
    },
    onEnd: (element) {
      if (_is(element, _sheetNamespaces, 'si')) {
        result.add(current!.toString());
        current = null;
      }
    },
  );
  return result;
}

class _Cell {
  _Cell(this.coordinate, this.type);
  final String coordinate;
  final String? type;
  final value = StringBuffer();
  final inline = StringBuffer();

  String text(List<String> shared) {
    if (type == 'inlineStr') return inline.toString();
    final raw = value.toString();
    if (type != 's') return raw;
    final index = int.tryParse(raw.trim());
    if (index == null || index < 0 || index >= shared.length) {
      throw const FormatException('Invalid shared string index');
    }
    return shared[index];
  }
}

void _readSheet(
  _OfficePackage package,
  String path,
  String name,
  List<String> shared,
  _LimitedText output,
) {
  var row = 0;
  var column = 0;
  var inRow = false;
  var titled = false;
  _Cell? cell;
  package.walk(
    path,
    _sheetNamespaces,
    'worksheet',
    onStart: (element) {
      if (_is(element, _sheetNamespaces, 'row')) {
        if (inRow) throw const FormatException('Nested row');
        final next = _attribute(element, 'r');
        final number = next == null ? row + 1 : int.tryParse(next);
        if (number == null || number <= row || number > 1048576) {
          throw const FormatException('Invalid row coordinate');
        }
        row = number;
        column = 0;
        inRow = true;
      }
      if (_is(element, _sheetNamespaces, 'c')) {
        if (!inRow || cell != null) {
          throw const FormatException('Cell outside row');
        }
        final coordinate = _attribute(element, 'r');
        final next = coordinate == null ? column + 1 : _column(coordinate, row);
        if (next <= column || next > 16384) {
          throw const FormatException('Invalid cell coordinate');
        }
        column = next;
        cell = _Cell(
          coordinate ?? '${_columnName(column)}$row',
          _attribute(element, 't'),
        );
      }
    },
    onText: (text, parent) {
      if (parent == null || cell == null) return;
      if (_is(parent, _sheetNamespaces, 'v')) cell!.value.write(text);
      if (_is(parent, _sheetNamespaces, 't') &&
          _hasAncestor(parent, _sheetNamespaces, 'is') &&
          !_hasAncestor(parent, _sheetNamespaces, 'rPh')) {
        cell!.inline.write(text);
      }
    },
    onEnd: (element) {
      if (_is(element, _sheetNamespaces, 'c')) {
        if (!titled) {
          if (output.text.isNotEmpty) output.add('\n');
          output.add('[$name]\n');
          titled = true;
        }
        // Sparse coordinate/value lines preserve explicit blanks and missing
        // columns/rows without expanding a hostile XFD1048576-sized grid.
        output.add('${cell!.coordinate}\t');
        output.add(cell!.text(shared));
        output.add('\n');
        cell = null;
      }
      if (_is(element, _sheetNamespaces, 'row')) inRow = false;
    },
  );
}

int _column(String coordinate, int row) {
  final match = RegExp(
    r'^([A-Z]{1,3})([1-9][0-9]{0,6})$',
  ).firstMatch(coordinate);
  if (match == null || int.tryParse(match[2]!) != row) {
    throw const FormatException('Invalid cell coordinate');
  }
  var result = 0;
  for (final unit in match[1]!.codeUnits) {
    result = result * 26 + unit - 64;
  }
  return result;
}

String _columnName(int column) {
  var result = '';
  while (column > 0) {
    column--;
    result = String.fromCharCode(65 + column % 26) + result;
    column ~/= 26;
  }
  return result;
}

void _readPresentation(_OfficePackage package, _LimitedText output) {
  final relationships = _relationships(package, 'ppt/presentation.xml');
  final ids = <String>[];
  package.walk(
    'ppt/presentation.xml',
    _presentationNamespaces,
    'presentation',
    onStart: (element) {
      if (!_is(element, _presentationNamespaces, 'sldId')) return;
      if (ids.length >= package.limits.maxSections) {
        throw const FormatException('Too many slides');
      }
      ids.add(_relationshipId(element));
    },
  );
  final seen = <String>{};
  for (final id in ids) {
    final path = _relatedPart(relationships, id, 'slide', 'ppt/slides/');
    if (!seen.add(path)) throw const FormatException('Duplicate slide');
    if (output.text.isNotEmpty) output.add('\n');
    package.walk(
      path,
      _presentationNamespaces,
      'sld',
      onStart: (element) {
        if (_is(element, _drawingNamespaces, 'br')) output.add('\n');
        if (_is(element, _drawingNamespaces, 'tab')) output.add('\t');
      },
      onText: (text, parent) {
        if (parent != null && _is(parent, _drawingNamespaces, 't')) {
          output.add(text);
        }
      },
      onEnd: (element) {
        if (_is(element, _drawingNamespaces, 'p')) output.add('\n');
      },
    );
  }
}

const _compatibilityNamespaces = {
  'http://schemas.openxmlformats.org/markup-compatibility/2006',
};

class _OfficeAlternative {
  _OfficeAlternative(this.element);
  final XmlStartElementEvent element;
  var selected = false;
}

/// Office often stores the same textbox twice for newer and older consumers.
/// Select the first Choice whose text vocabularies we recognise, or Fallback;
/// never combine mutually exclusive branches. Skipped XML is still validated.
class _OfficeCompatibility {
  final _alternatives = <_OfficeAlternative>[];
  XmlStartElementEvent? _suppressed;
  bool get acceptsText => _suppressed == null;

  bool start(XmlStartElementEvent element) {
    if (_suppressed != null) return false;
    if (_is(element, _compatibilityNamespaces, 'AlternateContent')) {
      _alternatives.add(_OfficeAlternative(element));
    } else if (_alternatives.isNotEmpty &&
        identical(element.parent, _alternatives.last.element) &&
        (_is(element, _compatibilityNamespaces, 'Choice') ||
            _is(element, _compatibilityNamespaces, 'Fallback'))) {
      final alternative = _alternatives.last;
      final supported =
          _is(element, _compatibilityNamespaces, 'Fallback') ||
          _supportsChoice(element);
      if (alternative.selected || !supported) {
        _suppressed = element;
        return false;
      }
      alternative.selected = true;
    }
    return true;
  }

  bool end(XmlStartElementEvent element) {
    if (_suppressed != null) {
      if (identical(element, _suppressed)) _suppressed = null;
      return false;
    }
    if (_alternatives.isNotEmpty &&
        identical(element, _alternatives.last.element)) {
      _alternatives.removeLast();
    }
    return true;
  }

  bool _supportsChoice(XmlStartElementEvent element) {
    final requires = _attribute(element, 'Requires')?.trim();
    if (requires == null || requires.isEmpty) return false;
    for (final prefix in requires.split(RegExp(r'\s+'))) {
      String? namespace;
      for (
        XmlStartElementEvent? parent = element;
        parent != null && namespace == null;
        parent = parent.parent
      ) {
        namespace = _attribute(parent, 'xmlns:$prefix');
      }
      if (!_wordNamespaces.contains(namespace) &&
          !_sheetNamespaces.contains(namespace) &&
          !_presentationNamespaces.contains(namespace) &&
          !_drawingNamespaces.contains(namespace) &&
          !const {
            'http://schemas.microsoft.com/office/word/2010/wordprocessingShape',
            'http://schemas.microsoft.com/office/word/2010/wordprocessingGroup',
            'urn:schemas-microsoft-com:vml',
          }.contains(namespace)) {
        return false;
      }
    }
    return true;
  }
}

class _ZipPart {
  const _ZipPart(
    this.offset,
    this.compressed,
    this.size,
    this.method,
    this.crc,
  );
  final int offset;
  final int compressed;
  final int size;
  final int method;
  final int crc;
}

/// A deliberately restricted ZIP reader: validate the entire central directory
/// and all local ranges BEFORE inflating any entry. No Archive/ZipDecoder is
/// instantiated (its symlink handling can eagerly inflate untrusted content).
class _OfficePackage {
  _OfficePackage(this.bytes, this.limits) {
    _index();
  }
  final Uint8List bytes;
  final AttachmentDocumentLimits limits;
  final _parts = <String, _ZipPart>{};
  var _inflated = 0;
  var _events = 0;

  void _index() {
    final data = ByteData.sublistView(bytes);
    void range(int start, int length, [int? end]) {
      if (start < 0 || length < 0 || start + length > (end ?? bytes.length)) {
        throw const FormatException('Invalid ZIP range');
      }
    }

    int u16(int offset) => data.getUint16(offset, Endian.little);
    int u32(int offset) => data.getUint32(offset, Endian.little);
    var end = bytes.length - 22;
    final earliest = bytes.length - 65557;
    for (; end >= 0 && end >= earliest; end--) {
      if (u32(end) == 0x06054b50 && end + 22 + u16(end + 20) == bytes.length) {
        break;
      }
    }
    if (end < 0 || end < earliest) {
      throw const FormatException('Missing ZIP directory');
    }
    final count = u16(end + 10);
    final directorySize = u32(end + 12);
    final directory = u32(end + 16);
    if (u16(end + 4) != 0 ||
        u16(end + 6) != 0 ||
        u16(end + 8) != count ||
        count == 0xffff ||
        count > limits.maxEntries ||
        directorySize == 0xffffffff ||
        directory == 0xffffffff ||
        directory + directorySize != end) {
      throw const FormatException('Unsupported or oversized ZIP directory');
    }
    range(directory, directorySize, end);
    var position = directory;
    var declaredTotal = 0;
    final ranges = <({int start, int end})>[];
    for (var index = 0; index < count; index++) {
      range(position, 46, end);
      if (u32(position) != 0x02014b50) {
        throw const FormatException('Invalid ZIP entry');
      }
      final flags = u16(position + 8);
      final method = u16(position + 10);
      final crc = u32(position + 16);
      final compressed = u32(position + 20);
      final size = u32(position + 24);
      final nameLength = u16(position + 28);
      final extraLength = u16(position + 30);
      final commentLength = u16(position + 32);
      final local = u32(position + 42);
      if (flags & ~0x080e != 0 ||
          (method != 0 && method != 8) ||
          u16(position + 34) != 0 ||
          (u32(position + 38) >> 16) & 0xf000 == 0xa000 ||
          size > limits.maxEntryBytes ||
          compressed > limits.maxCompressedBytes ||
          (method == 0 && compressed != size) ||
          nameLength < 1 ||
          nameLength > 1024) {
        throw const FormatException('Unsupported or oversized ZIP entry');
      }
      declaredTotal += size;
      if (declaredTotal > limits.maxInflatedBytes) {
        throw const FormatException('ZIP exceeds inflation budget');
      }
      range(position + 46, nameLength + extraLength + commentLength, end);
      final nameBytes = Uint8List.sublistView(
        bytes,
        position + 46,
        position + 46 + nameLength,
      );
      final name = utf8.decode(nameBytes);
      final components = name.endsWith('/')
          ? name.substring(0, name.length - 1).split('/')
          : name.split('/');
      if (name.startsWith('/') ||
          name.contains('\\') ||
          name.contains(':') ||
          name.codeUnits.any((unit) => unit < 32 || unit == 127) ||
          components.any(
            (part) => part.isEmpty || part == '.' || part == '..',
          ) ||
          _parts.containsKey(name)) {
        throw const FormatException('Invalid or duplicate ZIP name');
      }
      range(local, 30, directory);
      if (u32(local) != 0x04034b50 ||
          u16(local + 6) != flags ||
          u16(local + 8) != method ||
          u16(local + 26) != nameLength) {
        throw const FormatException('Inconsistent ZIP local header');
      }
      final content = local + 30 + nameLength + u16(local + 28);
      range(local + 30, content - local - 30, directory);
      range(content, compressed, directory);
      for (var i = 0; i < nameLength; i++) {
        if (bytes[local + 30 + i] != nameBytes[i]) {
          throw const FormatException('Inconsistent ZIP filename');
        }
      }
      if (flags & 8 == 0 &&
          (u32(local + 14) != crc ||
              u32(local + 18) != compressed ||
              u32(local + 22) != size)) {
        throw const FormatException('Inconsistent ZIP sizes');
      }
      _parts[name] = _ZipPart(content, compressed, size, method, crc);
      ranges.add((start: local, end: content + compressed));
      position += 46 + nameLength + extraLength + commentLength;
    }
    if (position != end) throw const FormatException('Invalid ZIP entry count');
    ranges.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].start < ranges[i - 1].end) {
        throw const FormatException('Overlapping ZIP entries');
      }
    }
  }

  Uint8List _read(String path) {
    final part = _parts[path];
    if (part == null || path.endsWith('/')) {
      throw const FormatException('Missing document part');
    }
    final sink = AttachmentDocumentInflationSink(
      part.size,
      limits.maxInflatedBytes - _inflated,
    );
    final compressed = Uint8List.sublistView(
      bytes,
      part.offset,
      part.offset + part.compressed,
    );
    if (part.method == 0) {
      sink.add(compressed);
      sink.close();
    } else {
      // archive 4.0.9's native decodeStream buffers all output in a callback.
      // A direct chunked sink checks every emitted chunk BEFORE retaining it;
      // dishonest metadata cannot cause unbounded decompression allocation.
      final decoder = ZLibDecoder(raw: true).startChunkedConversion(sink);
      for (var offset = 0; offset < compressed.length; offset += 1024) {
        final stop = offset + 1024 < compressed.length
            ? offset + 1024
            : compressed.length;
        decoder.add(Uint8List.sublistView(compressed, offset, stop));
      }
      // Do not close/retry the decoder after an add throws a budget error: it
      // could produce more output. Its native filter is garbage collected.
      decoder.close();
    }
    if (sink.length != part.size || sink.crc != part.crc) {
      throw const FormatException('ZIP integrity check failed');
    }
    _inflated += sink.length;
    return sink.takeBytes();
  }

  void walk(
    String path,
    Set<String> namespaces,
    String root, {
    void Function(XmlStartElementEvent)? onStart,
    void Function(String, XmlStartElementEvent?)? onText,
    void Function(XmlStartElementEvent)? onEnd,
  }) {
    final text = _decodeXml(_read(path));
    // Reject declarations before the XML parser even considers an internal
    // subset. Custom entities, external DTDs and stylesheet PIs are not needed.
    if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
      throw const FormatException('Document declarations are not supported');
    }
    _checkXmlMarkup(text);
    final stack = <XmlStartElementEvent>[];
    final compatibility = _OfficeCompatibility();
    var rooted = false;
    for (final event in parseEvents(
      text,
      entityMapping: const _OfficeEntities(),
      validateNesting: true,
      validateDocument: true,
      withParent: true,
    )) {
      if (++_events > limits.maxXmlEvents) {
        throw const FormatException('XML event budget exceeded');
      }
      if (event is XmlDoctypeEvent || event is XmlProcessingEvent) {
        throw const FormatException('Active XML is not supported');
      }
      if (event is XmlStartElementEvent) {
        if (stack.length >= limits.maxXmlDepth ||
            event.attributes.length > 128 ||
            event.attributes
                    .map((attribute) => attribute.name)
                    .toSet()
                    .length !=
                event.attributes.length) {
          throw const FormatException('XML complexity budget exceeded');
        }
        if (!rooted) {
          if (!_is(event, namespaces, root)) {
            throw const FormatException('Incorrect document root');
          }
          rooted = true;
        }
        if (compatibility.start(event)) onStart?.call(event);
        if (event.isSelfClosing) {
          if (compatibility.end(event)) onEnd?.call(event);
        } else {
          stack.add(event);
        }
      } else if (event is XmlEndElementEvent) {
        final element = stack.removeLast();
        if (compatibility.end(element)) onEnd?.call(element);
      } else if (event is XmlTextEvent) {
        final decoded = event.value;
        if (stack.isEmpty && decoded.trim().isNotEmpty) {
          throw const FormatException('Text outside document root');
        }
        if (compatibility.acceptsText) {
          onText?.call(decoded, stack.isEmpty ? null : stack.last);
        }
      } else if (event is XmlCDATAEvent) {
        if (stack.isEmpty) throw const FormatException('CDATA outside root');
        if (compatibility.acceptsText) onText?.call(event.value, stack.last);
      }
    }
    if (!rooted || stack.isNotEmpty) {
      throw const FormatException('Incomplete document XML');
    }
  }
}

/// Bound a start tag before the XML library allocates its attribute list.
/// Text/CDATA/comments remain bounded by the entry budget, not this tag cap.
void _checkXmlMarkup(String text) {
  for (final rune in text.runes) {
    if (!_xmlCharacter(rune)) {
      throw const FormatException('Invalid XML character');
    }
  }
  var start = text.indexOf('<');
  while (start >= 0) {
    String? terminator;
    if (text.startsWith('<!--', start)) terminator = '-->';
    if (text.startsWith('<![CDATA[', start)) terminator = ']]>';
    if (terminator != null) {
      final end = text.indexOf(terminator, start + 4);
      if (end < 0) throw const FormatException('Incomplete XML section');
      start = text.indexOf('<', end + terminator.length);
      continue;
    }
    var quote = 0;
    var end = start + 1;
    for (; end < text.length; end++) {
      if (end - start > 16 * 1024) {
        throw const FormatException('XML tag exceeds complexity budget');
      }
      final unit = text.codeUnitAt(end);
      if (unit == 60) throw const FormatException('Invalid XML markup');
      if (quote != 0) {
        if (unit == quote) quote = 0;
      } else if (unit == 34 || unit == 39) {
        quote = unit;
      } else if (unit == 62) {
        break;
      }
    }
    if (end == text.length) throw const FormatException('Incomplete XML tag');
    start = text.indexOf('<', end + 1);
  }
}

bool _xmlCharacter(int rune) =>
    rune == 9 ||
    rune == 10 ||
    rune == 13 ||
    (rune >= 0x20 && rune <= 0xd7ff) ||
    (rune >= 0xe000 && rune <= 0xfffd) ||
    (rune >= 0x10000 && rune <= 0x10ffff);

/// The package's default mapping tolerates unknown/bare ampersands and can
/// repeatedly search an entire text node for a missing semicolon. Restrict
/// references to built-ins/numeric characters with a linear, bounded scan.
class _OfficeEntities extends XmlDefaultEntityMapping {
  const _OfficeEntities() : super.xml();

  @override
  String decode(String input) {
    var start = input.indexOf('&');
    if (start < 0) return input;
    final output = StringBuffer(input.substring(0, start));
    while (start >= 0) {
      var end = start + 1;
      while (end < input.length &&
          end - start <= 16 &&
          input.codeUnitAt(end) != 59) {
        end++;
      }
      if (end >= input.length || end - start > 16) {
        throw const FormatException('Invalid XML reference');
      }
      output.write(decodeEntity(input.substring(start + 1, end)));
      final next = input.indexOf('&', end + 1);
      output.write(input.substring(end + 1, next < 0 ? input.length : next));
      start = next;
    }
    return output.toString();
  }

  @override
  String decodeEntity(String input) {
    final decoded = super.decodeEntity(input);
    if (decoded == null || decoded.runes.any((rune) => !_xmlCharacter(rune))) {
      throw const FormatException('Invalid XML reference');
    }
    return decoded;
  }
}

String _decodeXml(Uint8List bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    if (bytes.length.isOdd) throw const FormatException('Invalid UTF-16 XML');
    final endian = bytes[0] == 0xff ? Endian.little : Endian.big;
    final data = ByteData.sublistView(bytes);
    return String.fromCharCodes([
      for (var i = 2; i < bytes.length; i += 2) data.getUint16(i, endian),
    ]);
  }
  return utf8.decode(bytes);
}

/// Retains no bytes beyond either the declared entry size or aggregate cap.
/// The native inflater emits bounded chunks; this is not a collect-then-check
/// converter, and no allocation is based on an untrusted declared size.
@visibleForTesting
class AttachmentDocumentInflationSink implements Sink<List<int>> {
  AttachmentDocumentInflationSink(this.entryLimit, this.aggregateLimit);
  final int entryLimit;
  final int aggregateLimit;
  final _bytes = BytesBuilder(copy: false);

  /// Directly observes retention, so collect-then-check cannot pass a failure-
  /// only parser test merely because CRC/declared-size validation also fails.
  int get bufferedBytes => _bytes.length;
  var length = 0;
  var crc = 0;

  @override
  void add(List<int> data) {
    if (data.length > entryLimit - length ||
        data.length > aggregateLimit - length) {
      throw const FormatException('Inflated data exceeds budget');
    }
    length += data.length;
    crc = getCrc32(data, crc);
    _bytes.add(data);
  }

  @override
  void close() {}
  Uint8List takeBytes() => _bytes.takeBytes();
}
