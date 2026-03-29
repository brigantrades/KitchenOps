// Parses free-text ingredient lines into name / amount / unit for `recipes.ingredients`.
library;

/// Returns null unless the line is: leading quantity + known unit + ingredient name.
ParsedMeasuredLine? tryParseMeasuredIngredientLine(String input) {
  var line = input.trim();
  if (line.isEmpty) return null;
  line = line
      .replaceFirst(RegExp(r'^[\-•\*\s]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  final m = RegExp(r'^([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s+(.+)$').firstMatch(line);
  if (m == null) return null;
  final amount = parseAmountToken(m.group(1)!.trim());
  if (amount == null || amount <= 0) return null;
  final split = splitUnitAndName(m.group(2)!.trim());
  if (split.unit.isEmpty || split.name.isEmpty) return null;
  return ParsedMeasuredLine(
    name: split.name,
    amount: amount,
    unit: shortUnit(split.unitRaw),
  );
}

class ParsedMeasuredLine {
  const ParsedMeasuredLine({
    required this.name,
    required this.amount,
    required this.unit,
  });

  final String name;
  final double amount;
  final String unit;
}

({String unit, String name, String unitRaw}) splitUnitAndName(String rest) {
  final cleaned = rest.trim();
  if (cleaned.isEmpty) {
    return (unit: '', name: '', unitRaw: '');
  }
  const knownUnits = <String>{
    'tsp',
    'teaspoon',
    'teaspoons',
    'tbsp',
    'tablespoon',
    'tablespoons',
    'cup',
    'cups',
    'oz',
    'ounce',
    'ounces',
    'lb',
    'pound',
    'pounds',
    'g',
    'gram',
    'grams',
    'kg',
    'ml',
    'l',
    'clove',
    'cloves',
    'can',
    'cans',
    'package',
    'packages',
    'slice',
    'slices',
    'piece',
    'pieces',
    'stick',
    'sticks',
    'pinch',
    'pinches',
    'dash',
    'dashes',
  };
  final tokens = cleaned.split(' ');
  if (tokens.isEmpty) {
    return (unit: '', name: cleaned, unitRaw: '');
  }
  final first = tokens.first.toLowerCase();
  if (knownUnits.contains(first)) {
    final name = tokens.skip(1).join(' ').trim();
    if (name.isNotEmpty) {
      return (unit: shortUnit(tokens.first), name: name, unitRaw: tokens.first);
    }
  }
  return (unit: '', name: cleaned, unitRaw: '');
}

String shortUnit(String raw) {
  final u = raw.trim().toLowerCase();
  const map = <String, String>{
    'teaspoon': 'tsp',
    'teaspoons': 'tsp',
    'tablespoon': 'tbsp',
    'tablespoons': 'tbsp',
    'ounce': 'oz',
    'ounces': 'oz',
    'pound': 'lb',
    'pounds': 'lb',
    'grams': 'g',
    'gram': 'g',
    'cups': 'cup',
    'cloves': 'clove',
    'cans': 'can',
    'packages': 'package',
    'slices': 'slice',
    'pieces': 'piece',
    'sticks': 'stick',
    'pinches': 'pinch',
    'dashes': 'dash',
  };
  return map[u] ?? u;
}

double? parseAmountToken(String token) {
  var normalized = token.trim();
  if (normalized.isEmpty) return null;

  const unicodeFractions = <String, String>{
    '½': ' 1/2',
    '¼': ' 1/4',
    '¾': ' 3/4',
    '⅓': ' 1/3',
    '⅔': ' 2/3',
    '⅛': ' 1/8',
    '⅜': ' 3/8',
    '⅝': ' 5/8',
    '⅞': ' 7/8',
  };
  for (final e in unicodeFractions.entries) {
    normalized = normalized.replaceAll(e.key, e.value);
  }
  normalized = normalized
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (normalized.contains('-')) {
    final parts = normalized.split('-').map((e) => e.trim()).toList();
    for (final p in parts) {
      final parsed = parseSingleAmountToken(p);
      if (parsed != null) return parsed;
    }
  }

  return parseSingleAmountToken(normalized);
}

double? parseSingleAmountToken(String token) {
  final t = token.trim();
  if (t.isEmpty) return null;

  final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (mixed != null) {
    final whole = double.tryParse(mixed.group(1)!);
    final a = double.tryParse(mixed.group(2)!);
    final b = double.tryParse(mixed.group(3)!);
    if (whole != null && a != null && b != null && b != 0) {
      return whole + (a / b);
    }
  }

  final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (frac != null) {
    final a = double.tryParse(frac.group(1)!);
    final b = double.tryParse(frac.group(2)!);
    if (a != null && b != null && b != 0) return a / b;
  }

  final commaDecimal = t.contains(',') && !t.contains('.');
  final numeric = commaDecimal ? t.replaceAll(',', '.') : t.replaceAll(',', '');
  return double.tryParse(numeric);
}
