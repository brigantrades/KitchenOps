import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/features/discover/domain/discover_browse_categories.dart';

void main() {
  test(
      'lunch-five-ingredients matches representative title and cuisine tags',
      () {
    final cat = browseCategoryById('lunch-five-ingredients');
    expect(cat, isNotNull);
    final match = discoverRecipeMatchesBrowseCategoryKeywords(
      title: 'Easy 5-Ingredient Chili',
      cuisineTags: const [
        '5 ingredients or less',
        '5-ingredient',
        'Lunch',
        'five ingredients',
        'quick lunch',
      ],
      category: cat!,
    );
    expect(match, isTrue);
  });

  test('lunch-five-ingredients does not match unrelated tags', () {
    final cat = browseCategoryById('lunch-five-ingredients');
    expect(cat, isNotNull);
    final match = discoverRecipeMatchesBrowseCategoryKeywords(
      title: 'Garden Salad',
      cuisineTags: const ['Lunch', 'salad', 'vinaigrette'],
      category: cat!,
    );
    expect(match, isFalse);
  });
}
