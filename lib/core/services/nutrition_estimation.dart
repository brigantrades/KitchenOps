import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/services/api_services.dart';
import 'package:plateplan/core/services/fdc_nutrition_scaling.dart';
import 'package:plateplan/core/services/food_data_central_service.dart';
import 'package:plateplan/features/recipes/data/ingredient_nutrition_cache_repository.dart';

/// One row in the per-ingredient estimate (diagnostics / testing).
///
/// For batched Gemini calls, [nutrition] is an equal split of the batch total
/// across lines (the API does not return per-line macros).
class IngredientNutritionBreakdownLine {
  const IngredientNutritionBreakdownLine({
    required this.label,
    required this.nutrition,
    required this.sourceTag,
  });

  final String label;
  final Nutrition nutrition;

  /// e.g. [usda_cache], [usda_live], [gemini_estimated], [gemini_full_recipe].
  final String sourceTag;
}

Nutrition _splitNutritionEqually(Nutrition n, int parts) {
  if (parts <= 0) return const Nutrition();
  return scaleNutritionProportional(n, 1.0 / parts);
}

bool _nameImpliesEgg(String name) {
  final lower = name.trim().toLowerCase();
  if (lower.contains('eggplant')) return false;
  return RegExp(r'\begg\b|\beggs\b').hasMatch(lower);
}

/// Maps UI shorthands (e.g. `egg: to taste`, bare `egg`) to gram-estimate lines.
String _expandNutritionShorthand(String line) {
  final t = line.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return t;
  final bare = t.toLowerCase();
  if (bare == 'egg' || bare == 'eggs') return '1 egg';

  final colon = t.indexOf(':');
  if (colon <= 0) return t;
  final left = t.substring(0, colon).trim();
  final right = t.substring(colon + 1).trim().toLowerCase();
  if (!_nameImpliesEgg(left)) return t;
  if (right == 'to taste' || right == 'as needed') {
    return '$left: 1 egg';
  }
  return t;
}

/// Prefer a query that surfaces Foundation / whole-food eggs (not prepared dishes).
String _fdcSearchQueryForIngredient(String ingredientName) {
  final lower = ingredientName.trim().toLowerCase();
  if (lower.contains('eggplant')) return ingredientName.trim();
  if (RegExp(r'\begg\b|\beggs\b').hasMatch(lower)) {
    return 'egg whole raw';
  }
  return ingredientName.trim();
}

Future<({
  Nutrition nutrition,
  String source,
  List<IngredientNutritionBreakdownLine> breakdown,
})> estimateNutritionWithFallback({
  required FoodDataCentralService foodDataCentral,
  required IngredientNutritionCacheRepository cacheRepository,
  required GeminiService gemini,
  required List<String> ingredientLines,
  int? servings,
}) async {
  if (ingredientLines.isEmpty) {
    return (
      nutrition: const Nutrition(),
      source: 'gemini_ai_estimated',
      breakdown: const <IngredientNutritionBreakdownLine>[],
    );
  }

  final gramLines = <_Line>[];
  final geminiOnlyLines = <String>[];
  for (final raw in ingredientLines) {
    final trimmed =
        _expandNutritionShorthand(raw.trim()).replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) continue;
    // Before generic [amount unit name] (g/kg/tbsp/ml/…) so `2 piece bell peppers`
    // and `1 piece eggs` map to grams.
    final pieceLine = _tryParsePieceAsGramLine(trimmed);
    if (pieceLine != null) {
      gramLines.add(pieceLine);
      continue;
    }
    final weight = _tryParseWeightLine(trimmed);
    if (weight != null) {
      gramLines.add(weight);
      continue;
    }
    final eggDirect = _tryParseDirectEggCountAsGramLine(trimmed);
    if (eggDirect != null) {
      gramLines.add(eggDirect);
      continue;
    }
    final eggQualitative = _tryParseQualitativeEggLine(trimmed);
    if (eggQualitative != null) {
      gramLines.add(eggQualitative);
      continue;
    }
    geminiOnlyLines.add(trimmed);
  }

  if (gramLines.isEmpty && geminiOnlyLines.isEmpty) {
    return (
      nutrition: const Nutrition(),
      source: 'gemini_ai_estimated',
      breakdown: const <IngredientNutritionBreakdownLine>[],
    );
  }

  if (gramLines.isEmpty) {
    try {
      final gem = await gemini.estimateNutritionFromIngredients(
        geminiOnlyLines,
        servings: servings,
      );
      final part = _splitNutritionEqually(gem, geminiOnlyLines.length);
      final breakdown = <IngredientNutritionBreakdownLine>[
        for (final line in geminiOnlyLines)
          IngredientNutritionBreakdownLine(
            label: line,
            nutrition: part,
            sourceTag: 'gemini_estimated',
          ),
      ];
      return (
        nutrition: gem,
        source: 'gemini_ai_estimated',
        breakdown: breakdown,
      );
    } catch (_) {
      return (
        nutrition: const Nutrition(),
        source: 'gemini_ai_estimated',
        breakdown: const <IngredientNutritionBreakdownLine>[],
      );
    }
  }

  var total = const Nutrition();
  var hitsFromCache = 0;
  var hitsFromUsda = 0;
  final unresolved = <String>[];
  final localMemo = <String, IngredientNutritionCacheEntry?>{};
  final breakdown = <IngredientNutritionBreakdownLine>[];

  for (final line in gramLines) {
    final norm = _normalizeIngredientKey(line.ingredientName);
    if (norm.isEmpty) {
      unresolved.add(line.originalLine);
      continue;
    }
    final cached = localMemo.containsKey(norm)
        ? localMemo[norm]
        : await cacheRepository.getByNormalizedName(norm);
    localMemo[norm] = cached;
    if (cached != null) {
      final lineNutrition = _scalePer100(cached.nutritionPer100g, line.grams);
      total += lineNutrition;
      hitsFromCache += 1;
      breakdown.add(
        IngredientNutritionBreakdownLine(
          label: line.originalLine,
          nutrition: lineNutrition,
          sourceTag: 'usda_cache',
        ),
      );
      continue;
    }

    final resolved = await _resolveFromUsda(foodDataCentral, line);
    if (resolved == null) {
      unresolved.add(line.originalLine);
      continue;
    }
    localMemo[norm] = resolved.entry;
    await cacheRepository.upsertFromUsda(resolved.entry);
    total += resolved.lineNutrition;
    hitsFromUsda += 1;
    breakdown.add(
      IngredientNutritionBreakdownLine(
        label: line.originalLine,
        nutrition: resolved.lineNutrition,
        sourceTag: 'usda_live',
      ),
    );
  }

  final geminiFragments = <String>[...unresolved, ...geminiOnlyLines];
  if (geminiFragments.isNotEmpty) {
    try {
      final gem = await gemini.estimateNutritionFromIngredients(
        geminiFragments,
        servings: servings,
      );
      total += gem;
      final part = _splitNutritionEqually(gem, geminiFragments.length);
      for (final frag in geminiFragments) {
        breakdown.add(
          IngredientNutritionBreakdownLine(
            label: frag,
            nutrition: part,
            sourceTag: 'gemini_estimated',
          ),
        );
      }
    } catch (_) {
      for (final frag in geminiFragments) {
        breakdown.add(
          IngredientNutritionBreakdownLine(
            label: frag,
            nutrition: const Nutrition(),
            sourceTag: 'gemini_failed',
          ),
        );
      }
    }
  }

  final hasNutrition = _hasNutritionData(total);
  if (!hasNutrition) {
    try {
      final gem = await gemini.estimateNutritionFromIngredients(
        ingredientLines,
        servings: servings,
      );
      final nonEmpty = ingredientLines.where((s) => s.trim().isNotEmpty).toList();
      return (
        nutrition: gem,
        source: 'gemini_ai_estimated',
        breakdown: [
          IngredientNutritionBreakdownLine(
            label: nonEmpty.join('\n'),
            nutrition: gem,
            sourceTag: 'gemini_full_recipe',
          ),
        ],
      );
    } catch (_) {
      return (
        nutrition: const Nutrition(),
        source: 'gemini_ai_estimated',
        breakdown: const <IngredientNutritionBreakdownLine>[],
      );
    }
  }

  if (geminiFragments.isNotEmpty) {
    return (
      nutrition: total,
      source: 'usda_partial_gemini_fallback',
      breakdown: breakdown,
    );
  }
  if (hitsFromUsda > 0 && hitsFromCache > 0) {
    return (
      nutrition: total,
      source: 'usda_live_cached',
      breakdown: breakdown,
    );
  }
  if (hitsFromUsda > 0) {
    return (
      nutrition: total,
      source: 'usda_live',
      breakdown: breakdown,
    );
  }
  return (
    nutrition: total,
    source: 'usda_cache',
    breakdown: breakdown,
  );
}

typedef _ResolveFromUsda = ({
  IngredientNutritionCacheEntry entry,
  Nutrition lineNutrition,
});

Future<_ResolveFromUsda?> _resolveFromUsda(
  FoodDataCentralService foodDataCentral,
  _Line line,
) async {
  final query = _fdcSearchQueryForIngredient(line.ingredientName);
  try {
    final hits = await foodDataCentral.searchFoods(query, pageSize: 15);
    if (hits.isEmpty) return null;
    for (final hit in hits.take(8)) {
      try {
        final detail = await foodDataCentral.getFoodDetail(hit.fdcId);
        final per100 = _nutritionPer100FromFdcDetail(detail);
        if (!_hasNutritionData(per100)) continue;
        final entry = IngredientNutritionCacheEntry(
          normalizedName: _normalizeIngredientKey(line.ingredientName),
          displayName: line.ingredientName,
          nutritionPer100g: per100,
          fdcId: hit.fdcId,
          dataType: hit.dataType,
          source: 'usda_fdc',
        );
        final lineNutrition = _scalePer100(per100, line.grams);
        return (entry: entry, lineNutrition: lineNutrition);
      } catch (_) {
        continue;
      }
    }
    return null;
  } catch (_) {
    // Network / rate limit / malformed payload — fall back to Gemini for this line.
    return null;
  }
}

Nutrition _nutritionPer100FromFdcDetail(Map<String, dynamic> detail) {
  final raw = detail['foodNutrients'] as List<dynamic>? ?? const [];
  final base = nutritionFromFdcFoodNutrients(raw);
  final dataType = detail['dataType']?.toString();
  final Nutrition out;
  if (fdcFoodUsesPer100g(dataType)) {
    out = base;
  } else {
    final serveG = brandedServingGrams(detail);
    if (serveG != null && serveG > 0) {
      out = scaleNutritionProportional(base, 100 / serveG);
    } else {
      out = base;
    }
  }
  return ensureCaloriesFromMacrosIfMissing(out);
}

Nutrition _scalePer100(Nutrition per100g, double grams) {
  return scaleNutritionPer100g(
    ensureCaloriesFromMacrosIfMissing(per100g),
    grams,
  );
}

class _Line {
  const _Line({
    required this.originalLine,
    required this.ingredientName,
    required this.grams,
  });

  final String originalLine;
  final String ingredientName;
  final double grams;
}

const double _gramsPerLargeEgg = 50;

/// Rough grams per whole item when the user enters `N piece …` (not weight).
double _gramsPerPieceProduce(String nameLower) {
  if (nameLower.contains('bell pepper') ||
      nameLower.contains('capsicum') ||
      nameLower.contains('sweet pepper')) {
    return 119;
  }
  if (nameLower.contains('eggplant') || nameLower.contains('aubergine')) {
    return 458;
  }
  if (nameLower.contains('zucchini')) {
    return 196;
  }
  return 100;
}

/// `2 piece bell peppers`, `1 piece egg` — map [piece] to an approximate mass for FDC.
_Line? _tryParsePieceAsGramLine(String line) {
  final match = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s+(piece|pieces|pc|pcs|whole)\s+(.+?)\s*$',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!);
  final name = match.group(3)!.trim();
  if (amount == null || amount <= 0 || name.isEmpty) return null;
  final lower = name.toLowerCase();
  if (lower.contains('eggplant')) {
    return _Line(
      originalLine: line,
      ingredientName: name,
      grams: amount * _gramsPerPieceProduce(lower),
    );
  }
  if (RegExp(r'\begg\b|\beggs\b').hasMatch(lower)) {
    return _Line(
      originalLine: line,
      ingredientName: name,
      grams: amount * _gramsPerLargeEgg,
    );
  }
  return _Line(
    originalLine: line,
    ingredientName: name,
    grams: amount * _gramsPerPieceProduce(lower),
  );
}

_Line? _tryParseWeightLine(String line) {
  final match = RegExp(r'^\s*(\d+(?:\.\d+)?)\s+([a-zA-Z]+)\s+(.+?)\s*$').firstMatch(line);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!);
  if (amount == null || amount <= 0) return null;
  final unit = match.group(2)!.trim().toLowerCase();
  final name = match.group(3)!.trim();
  if (name.isEmpty) return null;
  final grams = _toGrams(amount, unit);
  if (grams == null || grams <= 0) return null;
  return _Line(originalLine: line, ingredientName: name, grams: grams);
}

/// `1 egg` / `2 eggs` / `1.5 egg` -> assumes large egg weight.
_Line? _tryParseDirectEggCountAsGramLine(String line) {
  final match = RegExp(
    r'^\s*(\d+(?:\.\d+)?)\s+(egg|eggs)\b.*$',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null) return null;
  final amount = double.tryParse(match.group(1)!);
  if (amount == null || amount <= 0) return null;
  return _Line(
    originalLine: line,
    ingredientName: 'egg',
    grams: amount * _gramsPerLargeEgg,
  );
}

/// `egg: 1 piece` / `eggs: 2` -> supports qualitative builder format.
_Line? _tryParseQualitativeEggLine(String line) {
  final match = RegExp(
    r'^\s*(.+?)\s*:\s*(\d+(?:\.\d+)?)\s*(piece|pieces|pc|pcs|whole|egg|eggs)?\s*$',
    caseSensitive: false,
  ).firstMatch(line);
  if (match == null) return null;
  final name = match.group(1)?.trim() ?? '';
  if (!name.toLowerCase().contains('egg')) return null;
  final amount = double.tryParse(match.group(2)!);
  if (amount == null || amount <= 0) return null;
  return _Line(
    originalLine: line,
    ingredientName: name,
    grams: amount * _gramsPerLargeEgg,
  );
}

double? _toGrams(double amount, String unit) {
  // Volume → approximate mass: ml treated as g (water-like); US tsp/tbsp/cup.
  switch (unit) {
    case 'g':
    case 'gram':
    case 'grams':
      return amount;
    case 'kg':
    case 'kilogram':
    case 'kilograms':
      return amount * 1000;
    case 'oz':
    case 'ounce':
    case 'ounces':
      return amount * 28.349523125;
    case 'mg':
    case 'milligram':
    case 'milligrams':
      return amount / 1000;
    case 'ml':
    case 'milliliter':
    case 'milliliters':
    case 'millilitre':
    case 'millilitres':
    case 'cc':
      return amount;
    case 'l':
    case 'liter':
    case 'liters':
    case 'litre':
    case 'litres':
      return amount * 1000;
    case 'tsp':
    case 'teaspoon':
    case 'teaspoons':
      return amount * 4.92892;
    case 'tbsp':
    case 'tablespoon':
    case 'tablespoons':
      return amount * 14.7868;
    case 'cup':
    case 'cups':
      return amount * 236.588;
    default:
      return null;
  }
}

String _normalizeIngredientKey(String value) {
  var s = normalizeGroceryItemName(value);
  if (s.endsWith('es') && s.length > 4) {
    s = s.substring(0, s.length - 2);
  } else if (s.endsWith('s') && s.length > 3) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

bool _hasNutritionData(Nutrition n) {
  return n.calories > 0 ||
      n.protein > 0 ||
      n.fat > 0 ||
      n.carbs > 0 ||
      n.fiber > 0 ||
      n.sugar > 0;
}
