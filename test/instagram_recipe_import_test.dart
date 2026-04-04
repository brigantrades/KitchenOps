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

    test('returns null when caption is only section headers and measured ingredients', () {
      expect(
        inferInstagramRecipeTitle(
          'Ingredients:\n2 cups flour\n1 egg\n1 tbsp salt',
        ),
        isNull,
      );
    });

    test('uses second line when first line is a measured ingredient', () {
      expect(
        inferInstagramRecipeTitle(
          '2 cups all-purpose flour\nBeef Stroganoff',
        ),
        'Beef Stroganoff',
      );
    });

    test('infers title when URL and dish name are on the same line', () {
      expect(
        inferInstagramRecipeTitle(
          'https://www.instagram.com/reel/AbCdEfGhIjK Bok Choy and Mushroom stir-fry\n\n'
          'Ingredients:\n1 lb bok choy',
        ),
        'Bok Choy and Mushroom stir-fry',
      );
    });

    test('uses headline before first Ingredients block (fish caption shape)', () {
      final caption = 'Lemon Butter Fish Bites with Garlic Aioli (Full Recipe)\n'
          'For the Fish Bites\n\n'
          'Ingredients:\n'
          '500g white fish fillets';
      expect(
        inferInstagramRecipeTitle(caption),
        'Lemon Butter Fish Bites with Garlic Aioli (Full Recipe)',
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

    test('replaces hallucinated Gemini title when caption names a different dish', () {
      final r = recipeFromInstagramGeminiMap(
        {
          'title': 'Creamy Pesto Chicken',
          'ingredients': [
            {'name': 'bok choy', 'amount': '1', 'unit': 'lb'},
          ],
          'instructions': ['Stir-fry.'],
        },
        sharedContent:
            'https://www.instagram.com/reel/AbCdEfGhIjK Bok Choy and Mushroom stir-fry\n\n'
            'Ingredients:\n1 lb bok choy',
      );
      expect(r.title, 'Bok Choy and Mushroom stir-fry');
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

    test('drops carb ingredient when name token not in shared caption', () {
      final r = recipeFromInstagramGeminiMap(
        {
          'title': 'Wrong',
          'ingredients': [
            {'name': 'salmon fillet', 'amount': 1, 'unit': 'lb'},
            {'name': 'penne pasta', 'amount': 8, 'unit': 'oz'},
          ],
          'instructions': ['Cook.'],
        },
        sharedContent:
            'Salmon bowl\n\nIngredients:\n1 lb salmon fillet\nlemon',
      );
      expect(r.ingredients, hasLength(1));
      expect(r.ingredients.first.name, 'salmon fillet');
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

  group('captionForInstagramGemini', () {
    test('returns stripped text when URL and caption are present', () {
      expect(
        captionForInstagramGemini(
          'https://www.instagram.com/reel/AbCdEfGhIjK/\n\n'
          'Bok choy stir fry\n\nIngredients:\n1 tsp oil',
        ),
        'Bok choy stir fry\nIngredients:\n1 tsp oil',
      );
    });

    test('falls back to raw share when strip is empty but text looks like a recipe', () {
      // Simulates over-aggressive strip edge case: long letter-only payload with ingredient + digit.
      final raw = '${'x' * 30} Ingredients: 2 cups flour';
      expect(stripInstagramUrlsForCaption(raw), raw);
      expect(captionForInstagramGemini(raw), raw);
    });

    test('URL-only reel share from device still yields text for Gemini (regression: no empty caption)', () {
      const u =
          'https://www.instagram.com/reel/DVl0Os5DEUz/?igsh=MTd6anpna200eW93Yg==';
      expect(stripInstagramUrlsForCaption(u), '');
      expect(captionForInstagramGemini(u), u);
    });
  });

  group('stripInstagramUrlsForCaption', () {
    test('removes reel URL with trailing slash without leaving a lone slash before caption', () {
      expect(
        stripInstagramUrlsForCaption(
          'https://www.instagram.com/reel/AbCdEfGhIjK/\n\nBok choy',
        ),
        'Bok choy',
      );
    });

    test('preserves caption fused to reel URL without space after shortcode', () {
      expect(
        stripInstagramUrlsForCaption(
          'https://www.instagram.com/reel/AbCdEfGhIjKSalmon bites',
        ),
        'Salmon bites',
      );
    });

    test('returns empty when text is reel URL only', () {
      expect(
        stripInstagramUrlsForCaption(
          'https://www.instagram.com/reel/AbCdEfGhIjK',
        ),
        '',
      );
    });
  });

  group('supplementWebImportJsonWithEmbeddedSauceFromPlainText', () {
    test('splits #### Orange Sauce from #### Air Fryer Tofu blog layout', () {
      const plain = '''
### Ingredients

#### Air Fryer Tofu:

* 1 block tofu
* 1 tsp salt

#### Orange Sauce:

* 1/4 cup water
* 1 tbsp orange juice

### Instructions

#### Orange Sauce

* Boil and thicken the sauce.

#### Air Fryer Tofu

* Air fry tofu until crisp.
''';
      final base = {
        'title': 'Orange Tofu',
        'ingredients': [
          {'name': 'merged', 'amount': '1', 'unit': 'item'},
        ],
        'instructions': ['Do everything'],
      };
      final out =
          supplementWebImportJsonWithEmbeddedSauceFromPlainText(base, plain);
      final recipe = recipeFromInstagramGeminiMap(
        out,
        source: 'web_import',
      );
      expect(recipe.embeddedSauce, isNotNull);
      expect(
        recipe.embeddedSauce!.ingredients.length,
        greaterThanOrEqualTo(2),
      );
      expect(recipe.embeddedSauce!.instructions, isNotEmpty);
      expect(recipe.ingredients.length, greaterThanOrEqualTo(2));
      expect(
        recipe.ingredients.any((i) => i.name.toLowerCase().contains('tofu')),
        isTrue,
      );
      expect(
        recipe.ingredients.every(
          (i) => !i.name.toLowerCase().contains('orange juice'),
        ),
        isTrue,
      );
    });

    test('splits WP-style plain Ingredients / For the … headings (no #)', () {
      const plain = '''
Ingredients

For the air fryer tofu

1 block firm tofu
1 tsp salt

For the orange sauce

1/4 cup water
1 tbsp orange juice concentrate

Instructions

For the orange sauce

Boil and thicken the sauce.

For the air fryer tofu

Air fry tofu until crisp.
''';
      final base = {
        'title': 'Orange Tofu',
        'ingredients': [
          {'name': 'merged', 'amount': '1', 'unit': 'item'},
        ],
        'instructions': ['Do everything'],
      };
      final out =
          supplementWebImportJsonWithEmbeddedSauceFromPlainText(base, plain);
      final recipe = recipeFromInstagramGeminiMap(
        out,
        source: 'web_import',
      );
      expect(recipe.embeddedSauce, isNotNull);
      expect(
        recipe.embeddedSauce!.ingredients.length,
        greaterThanOrEqualTo(2),
      );
      expect(recipe.embeddedSauce!.instructions, isNotEmpty);
      expect(recipe.ingredients.length, greaterThanOrEqualTo(2));
      expect(
        recipe.ingredients.any((i) => i.name.toLowerCase().contains('tofu')),
        isTrue,
      );
      expect(
        recipe.ingredients.every(
          (i) => !i.name.toLowerCase().contains('orange juice'),
        ),
        isTrue,
      );
    });
  });

  group('recipeFromInstagramGeminiMap embedded_sauce', () {
    test('parses embedded_sauce ingredients and instructions', () {
      final r = recipeFromInstagramGeminiMap(
        {
          'title': 'Fish',
          'ingredients': [
            {'name': 'fish', 'amount': '1', 'unit': 'lb'},
          ],
          'instructions': ['Bake fish'],
          'embedded_sauce': {
            'title': 'Lemon butter',
            'ingredients': [
              {'name': 'butter', 'amount': '2', 'unit': 'tbsp'},
            ],
            'instructions': ['Melt and drizzle'],
          },
        },
        source: 'web_import',
      );
      expect(r.embeddedSauce, isNotNull);
      expect(r.embeddedSauce!.title, 'Lemon butter');
      expect(r.embeddedSauce!.ingredients, hasLength(1));
      expect(
        r.embeddedSauce!.ingredients.first.name.toLowerCase(),
        contains('butter'),
      );
      expect(r.embeddedSauce!.instructions, ['Melt and drizzle']);
    });

    test('omitted embedded_sauce yields null', () {
      final r = recipeFromInstagramGeminiMap(
        {
          'title': 'Plain',
          'ingredients': [
            {'name': 'flour', 'amount': '1', 'unit': 'cup'},
          ],
          'instructions': ['Mix'],
        },
        source: 'web_import',
      );
      expect(r.embeddedSauce, isNull);
    });

    test('accepts sauce as alias key', () {
      final r = recipeFromInstagramGeminiMap(
        {
          'title': 'Pasta',
          'ingredients': [],
          'instructions': [],
          'sauce': {
            'ingredients': [
              {'name': 'cream', 'amount': '1', 'unit': 'cup'},
            ],
            'instructions': [],
          },
        },
        source: 'web_import',
      );
      expect(r.embeddedSauce, isNotNull);
      expect(r.embeddedSauce!.ingredients, hasLength(1));
      expect(
        r.embeddedSauce!.ingredients.first.name.toLowerCase(),
        contains('cream'),
      );
    });
  });
}
