import 'package:flutter/services.dart';

/// Match the Desktop composer's strict UTF-16 character threshold.
const largePasteAttachmentThreshold = 3000;

/// A committed bulk insertion at the editor's current selection. Android IME
/// clipboard buttons deliver editing updates rather than a separate paste event.
/// Programmatic controller changes do not pass through input formatters.
class LargePasteEdit {
  final String text;
  final TextEditingValue insertedValue;
  final TextEditingValue withoutPaste;

  const LargePasteEdit._(this.text, this.insertedValue, this.withoutPaste);

  static LargePasteEdit? detect(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.composing.isCollapsed || !newValue.composing.isCollapsed) {
      return null;
    }
    final selection = oldValue.selection;
    if (!selection.isValid || selection.end > oldValue.text.length) return null;
    final prefix = oldValue.text.substring(0, selection.start);
    final suffix = oldValue.text.substring(selection.end);
    final length = newValue.text.length - prefix.length - suffix.length;
    if (length <= largePasteAttachmentThreshold ||
        !newValue.text.startsWith(prefix) ||
        !newValue.text.endsWith(suffix) ||
        !newValue.selection.isCollapsed ||
        newValue.selection.extentOffset != prefix.length + length) {
      return null;
    }
    return LargePasteEdit._(
      newValue.text.substring(prefix.length, prefix.length + length),
      newValue,
      TextEditingValue(
        text: '$prefix$suffix',
        selection: TextSelection.collapsed(offset: prefix.length),
      ),
    );
  }
}

/// Observe paste-sized edits without discarding any text before cache I/O has
/// succeeded. The consumer owns async preparation and edit-revision fencing.
class LargePasteFormatter extends TextInputFormatter {
  final void Function(LargePasteEdit) onLargePaste;

  LargePasteFormatter({required this.onLargePaste});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final edit = LargePasteEdit.detect(oldValue, newValue);
    if (edit != null) onLargePaste(edit);
    return newValue;
  }
}
