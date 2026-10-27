/// Compatibility recognition for unannotated LCM context-assembly rows.
/// This is a display heuristic, not proof of authorship. Match the complete
/// producer envelope, never an arbitrary summary-looking prefix or long reply.
abstract final class LegacyLcmSummary {
  static const _objective =
      '[Current user objective preserved from compacted history]';
  static final _header = RegExp(
    r'^\[(Recent|Session Arc|Durable|Depth-[0-9]+) Summary '
    r'\(d(0|[1-9][0-9]*), node [1-9][0-9]*\)\]$',
  );

  static bool _isHeader(String line) {
    final match = _header.firstMatch(line);
    if (match == null) return false;
    final depth = match.group(2)!;
    final label = switch (depth) {
      '0' => 'Recent',
      '1' => 'Session Arc',
      '2' => 'Durable',
      _ => 'Depth-$depth',
    };
    return match.group(1) == label;
  }

  static bool _isSeparator(List<String> lines, int index) =>
      index + 2 < lines.length &&
      lines[index].isEmpty &&
      lines[index + 1] == '---' &&
      lines[index + 2].isEmpty;

  static bool matches(String body) {
    // Avoid splitting ordinary large messages. Line-ending normalisation is
    // local to recognition; BackgroundReport retains the exact original body.
    if (!body.startsWith('[Recent Summary (') &&
        !body.startsWith('[Session Arc Summary (') &&
        !body.startsWith('[Durable Summary (') &&
        !body.startsWith('[Depth-') &&
        !body.startsWith('$_objective\n') &&
        !body.startsWith('$_objective\r\n')) {
      return false;
    }
    final lines = body.replaceAll('\r\n', '\n').split('\n');
    var index = 0;
    if (lines.first == _objective) {
      // LCM may prepend the omitted user objective to its summary group. It is
      // scaffolding only when followed by a complete summary envelope.
      index = 2;
      while (index + 3 < lines.length &&
          !(_isSeparator(lines, index) && _isHeader(lines[index + 3]))) {
        index++;
      }
      index += 3;
    }
    if (index >= lines.length || !_isHeader(lines[index])) return false;
    var hasContent = false;
    for (index++; index < lines.length; index++) {
      final line = lines[index];
      if (line.startsWith('[Expand for details: ') && line.endsWith(']')) {
        if (!hasContent) return false;
        if (index == lines.length - 1) return true;
        // Stop at the complete frame: a real human tail must not be swallowed.
        if (!_isSeparator(lines, index + 1) ||
            index + 4 >= lines.length ||
            !_isHeader(lines[index + 4])) {
          return false;
        }
        index += 4;
        hasContent = false;
      } else if (line.trim().isNotEmpty) {
        hasContent = true;
      }
    }
    return false;
  }
}
