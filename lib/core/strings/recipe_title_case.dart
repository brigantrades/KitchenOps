/// English-style title case for recipe names: main words capitalized,
/// minor words (articles, short prepositions) lowercase except first/last.
String formatRecipeTitleCase(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  const minorWords = {
    'a',
    'an',
    'the',
    'and',
    'but',
    'or',
    'nor',
    'for',
    'on',
    'at',
    'to',
    'from',
    'by',
    'with',
    'in',
    'of',
    'as',
    'vs',
    'per',
    'into',
    'onto',
    'over',
  };

  final words = trimmed.split(RegExp(r'\s+'));
  final out = <String>[];

  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (w.isEmpty) continue;

    final lower = w.toLowerCase();
    final isFirst = out.isEmpty;
    final isLast = i == words.length - 1;

    if (!isFirst && !isLast && minorWords.contains(lower)) {
      out.add(lower);
    } else {
      out.add(_titleCaseToken(w));
    }
  }

  return out.join(' ');
}

String _titleCaseToken(String w) {
  if (w.isEmpty) return w;
  final first = w[0].toUpperCase();
  if (w.length == 1) return first;
  return '$first${w.substring(1).toLowerCase()}';
}
