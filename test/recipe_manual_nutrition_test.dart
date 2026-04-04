import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/recipes/recipe_manual_nutrition.dart';

void main() {
  group('recipeNutritionTotalsFromPerServing', () {
    test('scales per-serving values by servings', () {
      final t = recipeNutritionTotalsFromPerServing(
        caloriesPerServing: 200,
        proteinPerServing: 10,
        fatPerServing: 5,
        carbsPerServing: 20,
        fiberPerServing: 2,
        sugarPerServing: 3,
        servings: 4,
      );
      expect(t.calories, 800);
      expect(t.protein, 40);
      expect(t.fat, 20);
      expect(t.carbs, 80);
      expect(t.fiber, 8);
      expect(t.sugar, 12);
    });

    test('clamps servings to at least 1', () {
      final t = recipeNutritionTotalsFromPerServing(
        caloriesPerServing: 100,
        proteinPerServing: 1,
        fatPerServing: 1,
        carbsPerServing: 1,
        fiberPerServing: 1,
        sugarPerServing: 1,
        servings: 0,
      );
      expect(t.calories, 100);
    });
  });

  group('perServingNutritionFromRecipeTotals', () {
    test('divides totals by servings', () {
      const total = Nutrition(
        calories: 800,
        protein: 40,
        fat: 20,
        carbs: 80,
        fiber: 8,
        sugar: 12,
      );
      final ps = perServingNutritionFromRecipeTotals(total, 4);
      expect(ps.calories, 200);
      expect(ps.protein, 10);
      expect(ps.fat, 5);
      expect(ps.carbs, 20);
      expect(ps.fiber, 2);
      expect(ps.sugar, 3);
    });
  });

  group('nutritionHasAnyTotals', () {
    test('false for empty', () {
      expect(nutritionHasAnyTotals(const Nutrition()), isFalse);
    });

    test('true when calories positive', () {
      expect(
        nutritionHasAnyTotals(const Nutrition(calories: 1)),
        isTrue,
      );
    });
  });
}
