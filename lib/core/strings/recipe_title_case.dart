/// Each whitespace-separated word: first character uppercased, rest lowercased.
/// Collapses internal runs of whitespace to single spaces.
///
/// **Trailing spaces are preserved** so live typing in a [TextField] with an
/// input formatter is not blocked (plain `trim()` would eat the space key).
/// Leading whitespace-only input is returned as-is until there is a word.
String formatRecipeTitlePerWord(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return raw.isEmpty ? '' : raw;
  }
  final hasTrailingSpace = raw.isNotEmpty && RegExp(r'\s$').hasMatch(raw);
  final words = trimmed.split(RegExp(r'\s+'));
  final result = words.map(_titleCaseToken).join(' ');
  return hasTrailingSpace ? '$result ' : result;
}

String _titleCaseToken(String w) {
  if (w.isEmpty) return w;
  final first = w[0].toUpperCase();
  if (w.length == 1) return first;
  return '$first${w.substring(1).toLowerCase()}';
}
