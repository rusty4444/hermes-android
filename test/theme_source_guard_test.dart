import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UI colours come from active tokens, not fixed branding or brightness', () {
    // Palette seeds and semantic ramps belong in the single design-system root.
    const themeRoot = 'lib/core/theme/hermes_theme.dart';
    const mediaViewer = 'lib/core/widgets/attachment_preview_dialog.dart';
    // Exact image-only cinema exceptions, not a blanket preview exemption.
    // Documents continue to use the active application's ColorScheme.
    const mediaExceptions = {
      'final foreground = image ? Colors.white : scheme.onSurface;',
      'backgroundColor: image ? Colors.black : scheme.surface,',
    };
    final literalColor = RegExp(
      r'\b(?:Color|MaterialColor|MaterialAccentColor)\s*\('
      r'|\bColor\.(?:fromARGB|fromRGBO)\s*\('
      r'|\bColors\.(?!transparent\b)\w+'
      r'|#[0-9a-fA-F]{6}\b',
    );
    final packedColor = RegExp(r'\b0x[0-9a-fA-F]{8}\b');
    final bypassedTheme = RegExp(
      r'\bHermesTokens\.(?:hermesGold|dark|light|forBrightness)\b',
    );
    final violations = <String>[];
    final exceptionsSeen = <String, int>{};
    final sources =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(sources, isNotEmpty);
    for (final file in sources) {
      final path = file.path.replaceAll('\\', '/');
      if (path == themeRoot) continue;
      // Integers in services also encode non-colour bitmasks and file headers.
      final presentation =
          path == 'lib/main.dart' ||
          path.contains('/screens/') ||
          path.contains('/widgets/');
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index].trim();
        if (line.startsWith('//')) continue;
        if (path == mediaViewer && mediaExceptions.contains(line)) {
          exceptionsSeen.update(line, (count) => count + 1, ifAbsent: () => 1);
          continue;
        }
        if (literalColor.hasMatch(line) ||
            bypassedTheme.hasMatch(line) ||
            (presentation && packedColor.hasMatch(line))) {
          violations.add('$path:${index + 1}: $line');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Use HermesTokens.of(context) or the active ColorScheme; '
          'keep media-only exceptions narrow and documented.\n${violations.join('\n')}',
    );
    expect(exceptionsSeen, {for (final line in mediaExceptions) line: 1});
  });
}
