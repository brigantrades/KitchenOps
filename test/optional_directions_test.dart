import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/models/app_models.dart';

void main() {
  test('Recipe can be serialized with empty instructions', () {
    const recipe = Recipe(
      id: 'r1',
      title: 'Test',
      mealType: MealType.entree,
      ingredients: [
        Ingredient(
          name: 'Flour',
          amount: 1,
          unit: 'cup',
          category: GroceryCategory.pantryGrains,
        ),
      ],
      instructions: [],
    );

    final json = recipe.toJson();
    expect(json['instructions'], isA<List>());
    expect((json['instructions'] as List).isEmpty, isTrue);

    final decoded = Recipe.fromJson(Map<String, dynamic>.from(json));
    expect(decoded.instructions, isEmpty);
    expect(decoded.ingredients, isNotEmpty);
  });
}

