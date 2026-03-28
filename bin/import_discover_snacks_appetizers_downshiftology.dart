import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  const source = 'https://downshiftology.com/courses/appetizers-snacks/';

  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[source],
      csvPath: 'tmp/snacks_appetizers_downshiftology_review.csv',
      apiPrefix: 'snacks_appetizers_downshiftology',
      sourceName: 'downshiftology',
      mealType: 'snack',
      cuisineTags: <String>['Appetizers & Snacks'],
      includeKeywords: <String>[
        'appetizer',
        'snack',
        'dip',
        'hummus',
        'guacamole',
        'eggs',
        'mushrooms',
        'skewers',
        'shrimp',
        'cheese',
        'wings',
        'buffalo',
        'potato skins',
        'charcuterie',
        'salsa',
        'poppers',
      ],
      trustExtractedFromSourceUrls: <String>[source],
      restrictRecipeHosts: <String>[
        'downshiftology.com',
        'www.downshiftology.com',
      ],
      fallbackRecipeUrls: <String>[
        'https://downshiftology.com/recipes/best-ever-guacamole/',
        'https://downshiftology.com/recipes/cowboy-caviar/',
        'https://downshiftology.com/recipes/3-minute-hummus/',
        'https://downshiftology.com/recipes/7-layer-dip/',
        'https://downshiftology.com/recipes/french-onion-dip/',
        'https://downshiftology.com/recipes/deviled-eggs/',
        'https://downshiftology.com/recipes/stuffed-mushrooms/',
        'https://downshiftology.com/recipes/antipasto-skewers/',
        'https://downshiftology.com/recipes/shrimp-cocktail/',
        'https://downshiftology.com/recipes/smoked-salmon-cheese-ball/',
        'https://downshiftology.com/recipes/buffalo-cauliflower/',
        'https://downshiftology.com/recipes/spinach-and-artichoke-dip-dairy-free-paleo/',
        'https://downshiftology.com/recipes/tzatziki/',
        'https://downshiftology.com/recipes/potato-skins/',
        'https://downshiftology.com/recipes/air-fryer-chicken-wings/',
        'https://downshiftology.com/recipes/charcuterie-board/',
        'https://downshiftology.com/recipes/baked-brie-with-cranberry-sauce/',
        'https://downshiftology.com/recipes/candied-pecans/',
        'https://downshiftology.com/recipes/mango-salsa/',
        'https://downshiftology.com/recipes/zucchini-fries/',
        'https://downshiftology.com/recipes/ceviche/',
        'https://downshiftology.com/recipes/black-bean-dip/',
        'https://downshiftology.com/recipes/jalapeno-poppers/',
      ],
    ),
  );
}

