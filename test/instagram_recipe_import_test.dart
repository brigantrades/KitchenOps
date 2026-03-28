import 'package:flutter_test/flutter_test.dart';
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
  });
}
