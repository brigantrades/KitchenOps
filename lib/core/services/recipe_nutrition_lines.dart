import 'package:plateplan/core/models/app_models.dart';

/// True for chicken eggs, false for e.g. eggplant.
bool nameImpliesEggForNutrition(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('eggplant')) return false;
  return RegExp(r'\begg\b|\beggs\b').hasMatch(lower);
}

/// Non-numeric presets like "to taste" would skip USDA; assume one large egg.
String qualitativePhraseForNutritionEstimate(String name, String phrase) {
  final p = phrase.trim().toLowerCase();
  if (!nameImpliesEggForNutrition(name)) return phrase;
  if (p == 'to taste' || p == 'as needed') return '1 egg';
  return phrase;
}

/// String lines for [estimateNutritionWithFallback], aligned with the recipe wizard.
List<String> ingredientLinesFromIngredients(List<Ingredient> ingredients) {
  final out = <String>[];
  for (final ing in ingredients) {
    final name = ing.name.trim();
    if (name.isEmpty) continue;
    if (ing.qualitative) {
      final q = ing.unit.trim();
      if (q.isEmpty) continue;
      final qForNutrition = qualitativePhraseForNutritionEstimate(name, q);
      out.add('$name: $qForNutrition');
    } else {
      final unit = ing.unit.trim();
      if (unit.isEmpty) continue;
      final amt = ing.amount;
      final amtStr = amt % 1 == 0 ? '${amt.toInt()}' : amt.toStringAsFixed(1);
      out.add('$amtStr $unit $name');
    }
  }
  return out;
}

/// Convenience for saved [Recipe] rows (e.g. Cooking Mode).
List<String> ingredientLinesForNutritionEstimate(Recipe recipe) =>
    ingredientLinesFromIngredients(recipe.ingredients);
