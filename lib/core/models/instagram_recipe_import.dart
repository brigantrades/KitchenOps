import 'dart:math';

import 'package:plateplan/core/models/app_models.dart';

/// Maps Gemini / Instagram labels like "dinner" to [MealType] without using [_mealTypeFromDb].
MealType mealTypeFromInstagramLabel(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  const mains = <String>{
    'breakfast',
    'brunch',
    'lunch',
    'dinner',
    'supper',
    'entree',
    'main',
    'main course',
  };
  const sides = <String>{'side', 'side dish', 'salad'};
  const sauces = <String>{'sauce', 'condiment'};
  const snacks = <String>{'snack', 'appetizer', 'starter'};
  const desserts = <String>{'dessert', 'sweet'};
  if (mains.contains(s)) return MealType.entree;
  if (sides.contains(s)) return MealType.side;
  if (sauces.contains(s)) return MealType.sauce;
  if (snacks.contains(s)) return MealType.snack;
  if (desserts.contains(s)) return MealType.dessert;
  return MealType.entree;
}

Ingredient _ingredientFromInstagramJson(Map<String, dynamic> json) {
  final name = json['name']?.toString().trim() ?? '';
  final amountRaw = json['amount'];
  final unitRaw = json['unit']?.toString().trim() ?? '';

  if (amountRaw is num) {
    return Ingredient(
      name: name,
      amount: amountRaw.toDouble(),
      unit: unitRaw,
      category: GroceryCategory.other,
    );
  }

  final str = amountRaw?.toString().trim() ?? '';
  if (str.isEmpty && unitRaw.isEmpty) {
    return Ingredient(
      name: name,
      amount: 0,
      unit: '',
      category: GroceryCategory.other,
      qualitative: false,
    );
  }

  if (str.isEmpty) {
    return Ingredient(
      name: name,
      amount: 0,
      unit: unitRaw,
      category: GroceryCategory.other,
      qualitative: true,
    );
  }

  final leading = RegExp(r'^([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s*(.*)$')
      .firstMatch(str);
  if (leading != null) {
    final numPart = leading.group(1)!;
    final restFromAmount = leading.group(2)?.trim() ?? '';
    final parsed = _parseAmountToken(numPart);
    if (parsed != null) {
      final unitCombined = [unitRaw, restFromAmount]
          .where((e) => e.isNotEmpty)
          .join(' ')
          .trim();
      return Ingredient(
        name: name,
        amount: parsed,
        unit: unitCombined,
        category: GroceryCategory.other,
      );
    }
  }

  return Ingredient(
    name: name,
    amount: 0,
    unit: [str, unitRaw].where((e) => e.isNotEmpty).join(' ').trim(),
    category: GroceryCategory.other,
    qualitative: true,
  );
}

double? _parseAmountToken(String token) {
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
  unicodeFractions.forEach((k, v) {
    normalized = normalized.replaceAll(k, v);
  });
  normalized = normalized
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Handle ranges (e.g. "1-2", "1 1/2-2").
  if (normalized.contains('-')) {
    final parts = normalized.split('-').map((e) => e.trim()).toList();
    for (final p in parts) {
      final parsed = _parseSingleAmountToken(p);
      if (parsed != null) return parsed;
    }
  }

  return _parseSingleAmountToken(normalized);
}

double? _parseSingleAmountToken(String token) {
  final t = token.trim();
  if (t.isEmpty) return null;

  // Mixed number: "1 1/2"
  final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (mixed != null) {
    final whole = double.tryParse(mixed.group(1)!);
    final a = double.tryParse(mixed.group(2)!);
    final b = double.tryParse(mixed.group(3)!);
    if (whole != null && a != null && b != null && b != 0) {
      return whole + (a / b);
    }
  }

  // Fraction: "1/2"
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

/// Max length for a caption line we treat as a recipe title (longer lines look like paragraphs).
const int kInstagramInferredTitleMaxLength = 120;

final RegExp _urlToken = RegExp(r'^https?://\S+$', caseSensitive: false);

bool _isUrlOnlyLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  for (final tok in t.split(RegExp(r'\s+'))) {
    if (!_urlToken.hasMatch(tok)) return false;
  }
  return true;
}

bool _isIngredientsSectionHeader(String line) {
  return RegExp(r'^\s*ingredients?\s*:?\s*$', caseSensitive: false)
      .hasMatch(line);
}

bool _isSectionHeaderLine(String line) {
  return RegExp(
    r'^\s*(ingredients?|instructions?|method|directions|steps|prep|cook\s*time|notes|tips)\s*:?\s*$',
    caseSensitive: false,
  ).hasMatch(line);
}

bool _isHashtagOnlyLine(String line) {
  final t = line.trim();
  if (t.isEmpty) return true;
  for (final tok in t.split(RegExp(r'\s+'))) {
    if (RegExp(r'^#\w').hasMatch(tok)) continue;
    if (RegExp(r'[a-zA-Z]').hasMatch(tok)) return false;
  }
  return true;
}

/// Line starts like a quantity + common cooking unit (not a dish name like "1-Pot Pasta").
final RegExp _ingredientLineLead = RegExp(
  r'^\s*([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s+'
  r'(cups?|tbsp|tsp|oz|ounce|ounces|g|kg|grams?|ml|l|lb|lbs|tablespoons?|teaspoons?|pinch|cloves?|large|medium|small|stalks?|sticks?|slices?|packets?|cans?|bunch|bunches)\b',
  caseSensitive: false,
);

bool _looksLikeIngredientLine(String line) {
  return _ingredientLineLead.hasMatch(line);
}

String _normalizeInstagramTitle(String line) {
  var s = line.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceAll(RegExp(r'(\s+#\w+)+$'), '');
  return s.trim();
}

/// Picks a title from shared Instagram text (URL + caption) when the caption has a clear headline.
///
/// Uses the **first** substantive line after skipping leading URL-only and hashtag-only lines.
/// If that line is not a plausible title (section header, ingredient-like, too long), returns null
/// so callers can fall back to Gemini's [title] in JSON.
String? inferInstagramRecipeTitle(String sharedContent) {
  final raw = sharedContent.trim();
  if (raw.isEmpty) return null;
  final lines = raw.split(RegExp(r'\r?\n')).map((e) => e.trim()).toList();
  var i = 0;
  while (i < lines.length) {
    final lineTrim = lines[i];
    if (lineTrim.isEmpty) {
      i++;
      continue;
    }
    if (_isUrlOnlyLine(lineTrim)) {
      i++;
      continue;
    }
    if (_isHashtagOnlyLine(lineTrim)) {
      i++;
      continue;
    }
    break;
  }
  if (i >= lines.length) return null;

  final lineTrim = lines[i];
  if (_isIngredientsSectionHeader(lineTrim)) return null;
  if (lineTrim.length > kInstagramInferredTitleMaxLength) return null;
  if (_isSectionHeaderLine(lineTrim)) return null;
  if (_looksLikeIngredientLine(lineTrim)) return null;

  final normalized = _normalizeInstagramTitle(lineTrim);
  if (normalized.isEmpty) return null;
  if (normalized.length > kInstagramInferredTitleMaxLength) return null;
  return normalized;
}

/// Builds a [Recipe] from Gemini JSON for Instagram import (see prompt in [GeminiService]).
Recipe recipeFromInstagramGeminiMap(
  Map<String, dynamic> json, {
  String? id,
  String? imageUrl,
  String? sourceUrl,
  String? sharedContent,
}) {
  final tempId =
      id ?? 'import-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999999)}';
  final ingredients = (json['ingredients'] as List?)
          ?.whereType<Map>()
          .map((e) => _ingredientFromInstagramJson(Map<String, dynamic>.from(e)))
          .where((i) => i.name.isNotEmpty)
          .toList() ??
      const <Ingredient>[];

  final instructions = (json['instructions'] as List?)
          ?.map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList() ??
      const <String>[];

  final servings = (json['servings'] as num?)?.toInt().clamp(1, 99) ?? 2;

  final geminiTitle = json['title']?.toString().trim();
  final inferredTitle =
      sharedContent != null ? inferInstagramRecipeTitle(sharedContent) : null;
  final title =
      (inferredTitle != null && inferredTitle.isNotEmpty)
          ? inferredTitle
          : (geminiTitle ?? 'Imported recipe');

  return Recipe(
    id: tempId,
    title: title,
    description: json['description']?.toString().trim(),
    servings: servings,
    prepTime: (json['prep_time'] as num?)?.toInt(),
    cookTime: (json['cook_time'] as num?)?.toInt(),
    mealType: mealTypeFromInstagramLabel(json['meal_type']?.toString()),
    cuisineTags: (json['cuisine_tags'] as List?)
            ?.map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [],
    ingredients: ingredients,
    instructions: instructions,
    imageUrl: imageUrl,
    nutrition: const Nutrition(),
    isFavorite: false,
    isToTry: false,
    source: 'instagram_import',
    sourceUrl: sourceUrl,
    visibility: RecipeVisibility.personal,
  );
}
