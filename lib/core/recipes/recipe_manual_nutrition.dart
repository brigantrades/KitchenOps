import 'package:plateplan/core/models/app_models.dart';

/// Converts per-serving nutrition inputs to stored [Recipe.nutrition] (full recipe totals).
Nutrition recipeNutritionTotalsFromPerServing({
  required int caloriesPerServing,
  required double proteinPerServing,
  required double fatPerServing,
  required double carbsPerServing,
  required double fiberPerServing,
  required double sugarPerServing,
  required int servings,
}) {
  final s = servings.clamp(1, 999999);
  return Nutrition(
    calories: caloriesPerServing * s,
    protein: proteinPerServing * s,
    fat: fatPerServing * s,
    carbs: carbsPerServing * s,
    fiber: fiberPerServing * s,
    sugar: sugarPerServing * s,
  );
}

/// Derives per-serving display values from stored full-recipe totals.
Nutrition perServingNutritionFromRecipeTotals(Nutrition total, int servings) {
  final s = servings.clamp(1, 999999).toDouble();
  return Nutrition(
    calories: (total.calories / s).round(),
    protein: total.protein / s,
    fat: total.fat / s,
    carbs: total.carbs / s,
    fiber: total.fiber / s,
    sugar: total.sugar / s,
  );
}

bool nutritionHasAnyTotals(Nutrition n) {
  return n.calories > 0 ||
      n.protein > 0 ||
      n.fat > 0 ||
      n.carbs > 0 ||
      n.fiber > 0 ||
      n.sugar > 0;
}
