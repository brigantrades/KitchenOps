/// Each whitespace-separated word: first character uppercased, rest lowercased.
/// Collapses internal runs of whitespace to single spaces; trims ends.
String formatRecipeTitlePerWord(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;
  final words = trimmed.split(RegExp(r'\s+'));
  return words.map(_titleCaseToken).join(' ');
}

String _titleCaseToken(String w) {
  if (w.isEmpty) return w;
  final first = w[0].toUpperCase();
  if (w.length == 1) return first;
  return '$first${w.substring(1).toLowerCase()}';
}
