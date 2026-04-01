import 'package:flutter/services.dart';
import 'package:plateplan/core/strings/recipe_title_case.dart';

/// While [lowercaseTyping] is false, reformats the full field with
/// [formatRecipeTitlePerWord] on each edit. When true, passes input through.
class RecipeTitlePerWordInputFormatter extends TextInputFormatter {
  RecipeTitlePerWordInputFormatter({required this.lowercaseTyping});

  final bool lowercaseTyping;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (lowercaseTyping) return newValue;

    final newText = newValue.text;
    final formatted = formatRecipeTitlePerWord(newText);
    if (formatted == newText) return newValue;

    final selection = newValue.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final oldText = oldValue.text;
    final oldCursor = selection.baseOffset;
    var newCursor = oldCursor + formatted.length - newText.length;
    if (oldCursor == newText.length && newText.length > oldText.length) {
      newCursor = formatted.length;
    } else {
      newCursor = newCursor.clamp(0, formatted.length);
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}
