import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  const source = 'https://www.loveandlemons.com/appetizers/';

  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[source],
      csvPath: 'tmp/snacks_appetizers_loveandlemons_review.csv',
      apiPrefix: 'snacks_appetizers_loveandlemons',
      sourceName: 'loveandlemons',
      mealType: 'snack',
      cuisineTags: <String>['Appetizers & Snacks'],
      includeKeywords: <String>[
        'appetizer',
        'snack',
        'dip',
        'hummus',
        'guacamole',
        'salsa',
        'board',
        'platter',
        'bites',
        'skewers',
        'poppers',
        'wings',
        'fries',
        'chips',
      ],
      trustExtractedFromSourceUrls: <String>[source],
      restrictRecipeHosts: <String>[
        'loveandlemons.com',
        'www.loveandlemons.com',
      ],
      fallbackRecipeUrls: <String>[
        'https://www.loveandlemons.com/guacamole-recipe/',
        'https://www.loveandlemons.com/spinach-artichoke-dip/',
        'https://www.loveandlemons.com/deviled-eggs-recipe/',
        'https://www.loveandlemons.com/stuffed-mushrooms/',
        'https://www.loveandlemons.com/baked-jalapeno-poppers/',
        'https://www.loveandlemons.com/caprese-skewers/',
        'https://www.loveandlemons.com/taquitos-recipe/',
        'https://www.loveandlemons.com/fresh-spring-rolls/',
        'https://www.loveandlemons.com/cheese-board/',
        'https://www.loveandlemons.com/mezze-platter/',
        'https://www.loveandlemons.com/loaded-nachos/',
        'https://www.loveandlemons.com/crudite-platter/',
        'https://www.loveandlemons.com/baked-brie/',
        'https://www.loveandlemons.com/salsa-recipe/',
        'https://www.loveandlemons.com/mango-salsa/',
        'https://www.loveandlemons.com/cowboy-caviar/',
        'https://www.loveandlemons.com/french-onion-dip/',
        'https://www.loveandlemons.com/whipped-feta/',
        'https://www.loveandlemons.com/muhammara/',
        'https://www.loveandlemons.com/tzatziki-sauce/',
        'https://www.loveandlemons.com/hummus-recipe/',
        'https://www.loveandlemons.com/baba-ganoush/',
        'https://www.loveandlemons.com/air-fryer-french-fries/',
        'https://www.loveandlemons.com/air-fryer-onion-rings/',
        'https://www.loveandlemons.com/air-fryer-fried-pickles/',
      ],
    ),
  );
}

