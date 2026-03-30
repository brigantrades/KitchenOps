import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/models/instagram_recipe_import.dart';

void main() {
  group('inferInstagramRecipeTitle', () {
    test('skips URL-only first line and uses next line', () {
      final t = inferInstagramRecipeTitle(
        'https://www.instagram.com/p/AbCdE/\n\n'
        'Lemon Garlic Salmon\n'
        'So good!',
      );
      expect(t, 'Lemon Garlic Salmon');
    });

    test('uses first caption line when it is the title', () {
      expect(
        inferInstagramRecipeTitle(
          'Chocolate Chip Cookies 🍪\n\nIngredients:\n2 cups flour',
        ),
        'Chocolate Chip Cookies 🍪',
      );
    });

    test('skips hashtag-only line then uses real title', () {
      expect(
        inferInstagramRecipeTitle(
          '#vegan #healthy\n'
          'Creamy Tomato Soup',
        ),
        'Creamy Tomato Soup',
      );
    });

    test('returns null when first block is Ingredients section', () {
      expect(
        inferInstagramRecipeTitle(
          'Ingredients:\n2 cups flour\n1 egg',
        ),
        isNull,
      );
    });

    test('returns null for ingredient-like first line', () {
      expect(
        inferInstagramRecipeTitle(
          '2 cups all-purpose flour\nMore text here',
        ),
        isNull,
      );
    });

    test('strips trailing hashtags from title line', () {
      expect(
        inferInstagramRecipeTitle(
          'Sheet Pan Fajitas  #dinner #easy',
        ),
        'Sheet Pan Fajitas',
      );
    });
  });

  group('recipeFromInstagramGeminiMap', () {
    const minimalJson = <String, dynamic>{
      'title': 'Gemini Chosen Title',
      'ingredients': [
        {'name': 'salt', 'amount': '1', 'unit': 'pinch'},
      ],
      'instructions': ['Mix.'],
    };

    test('prefers inferred caption title over Gemini title', () {
      final r = recipeFromInstagramGeminiMap(
        minimalJson,
        sharedContent:
            'https://instagram.com/p/xyz/\n\nCaption Headline\n\nIngredients:\n…',
      );
      expect(r.title, 'Caption Headline');
    });

    test('falls back to Gemini title when inference yields null', () {
      final r = recipeFromInstagramGeminiMap(
        minimalJson,
        sharedContent: 'Ingredients:\n2 cups flour',
      );
      expect(r.title, 'Gemini Chosen Title');
    });

    test('without sharedContent uses Gemini title only', () {
      final r = recipeFromInstagramGeminiMap(minimalJson);
      expect(r.title, 'Gemini Chosen Title');
    });

    test('normalizes units with trailing punctuation from models', () {
      final r = recipeFromInstagramGeminiMap({
        'title': 'T',
        'ingredients': [
          {'name': 'vinegar', 'amount': 2, 'unit': 'Tbsp.'},
        ],
        'instructions': ['Mix.'],
      });
      expect(r.ingredients.first.unit, 'tbsp');
    });

    test('splits quantity at end of name when merged into name field', () {
      final r = recipeFromInstagramGeminiMap({
        'title': 'T',
        'ingredients': [
          {'name': 'Vinegar 2 Tbsp.', 'amount': '', 'unit': ''},
        ],
        'instructions': ['Mix.'],
      });
      expect(r.ingredients.first.name, 'Vinegar');
      expect(r.ingredients.first.amount, 2);
      expect(r.ingredients.first.unit, 'tbsp');
    });

    test('normalizes unit synonyms to canonical keys', () {
      final r = recipeFromInstagramGeminiMap({
        'title': 'T',
        'ingredients': [
          {'name': 'flour', 'amount': 2, 'unit': 'Tablespoons'},
        ],
        'instructions': ['Mix.'],
      });
      expect(r.ingredients, hasLength(1));
      expect(r.ingredients.first.unit, 'tbsp');
      expect(r.ingredients.first.amount, 2);
    });

    test('recovers amount when unit words are merged into amount string', () {
      final r = recipeFromInstagramGeminiMap({
        'title': 'T',
        'ingredients': [
          {'name': 'all-purpose flour', 'amount': '2 tbsp', 'unit': ''},
        ],
        'instructions': ['Mix.'],
      });
      expect(r.ingredients.first.amount, 2);
      expect(r.ingredients.first.unit, 'tbsp');
      expect(r.ingredients.first.name, 'all-purpose flour');
    });

    test('splits extra unit text into ingredient name', () {
      final r = recipeFromInstagramGeminiMap({
        'title': 'T',
        'ingredients': [
          {'name': 'oil', 'amount': 1, 'unit': 'tbsp extra virgin'},
        ],
        'instructions': ['Mix.'],
      });
      expect(r.ingredients.first.unit, 'tbsp');
      expect(r.ingredients.first.name, 'extra virgin oil');
    });

    test('converts qualitative full line to measured when parseable', () {
      final r = recipeFromInstagramGeminiMap({
        'title': 'T',
        'ingredients': [
          {'name': '', 'amount': '', 'unit': '1 tsp kosher salt'},
        ],
        'instructions': ['Mix.'],
      });
      expect(r.ingredients, hasLength(1));
      expect(r.ingredients.first.name, 'kosher salt');
      expect(r.ingredients.first.unit, 'tsp');
      expect(r.ingredients.first.amount, 1);
      expect(r.ingredients.first.qualitative, false);
    });
  });

  group('normalizeImportedIngredient', () {
    test('parses qualitative combined unit+name into measured row', () {
      final i = normalizeImportedIngredient(
        const Ingredient(
          name: '',
          amount: 0,
          unit: '2 cups sugar',
          category: GroceryCategory.other,
          qualitative: true,
        ),
      );
      expect(i.qualitative, false);
      expect(i.amount, 2);
      expect(i.unit, 'cup');
      expect(i.name, 'sugar');
    });
  });
}
