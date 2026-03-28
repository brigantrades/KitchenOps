import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  const source = 'https://www.recipetineats.com/party-food-recipe-round-up/';

  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[source],
      csvPath: 'tmp/snacks_appetizers_recipetineats_review.csv',
      apiPrefix: 'snacks_appetizers_recipetineats',
      sourceName: 'recipetineats',
      mealType: 'snack',
      cuisineTags: <String>['Appetizers & Snacks'],
      includeKeywords: <String>[
        'party',
        'appetizer',
        'snack',
        'dip',
        'wings',
        'meatballs',
        'bites',
        'cheese',
        'brie',
        'hummus',
        'salsa',
        'guacamole',
        'popcorn',
        'potato skins',
      ],
      trustExtractedFromSourceUrls: <String>[source],
      restrictRecipeHosts: <String>[
        'recipetineats.com',
        'www.recipetineats.com',
      ],
      fallbackRecipeUrls: <String>[
        'https://www.recipetineats.com/vietnamese-rice-paper-rolls-spring-rolls/',
        'https://www.recipetineats.com/cocktail-meatballs-with-sweet-sour-dipping-sauce/',
        'https://www.recipetineats.com/cheese-garlic-crack-bread-pull-apart-bread/',
        'https://www.recipetineats.com/salami-cream-cheese-roll-ups/',
        'https://www.recipetineats.com/smoked-salmon-appetizer/',
        'https://www.recipetineats.com/cheese-and-bacon-potato-skins/',
        'https://www.recipetineats.com/special-pork-fennel-sausage-rolls/',
        'https://www.recipetineats.com/homemade-movie-popcorn/',
        'https://www.recipetineats.com/coconut-shrimp-prawns-with-spicy-thai-mango-sauce/',
        'https://www.recipetineats.com/queso-dip-mexican-cheese-dip/',
        'https://www.recipetineats.com/best-ever-authentic-guacamole/',
        'https://www.recipetineats.com/hot-corn-dip/',
        'https://www.recipetineats.com/cheese-bacon-dip/',
        'https://www.recipetineats.com/hummus/',
        'https://www.recipetineats.com/chorizo-black-bean-and-corn-salsa/',
        'https://www.recipetineats.com/homemade-french-onion-dip/',
        'https://www.recipetineats.com/christmas-appetiser-italian-cheese-log/',
        'https://www.recipetineats.com/spinach-and-artichoke-dip/',
        'https://www.recipetineats.com/smoked-salmon-dip/',
        'https://www.recipetineats.com/salsa-super-easy-restaurant-style/',
        'https://www.recipetineats.com/festive-baked-brie/',
        'https://www.recipetineats.com/herb-chilli-feta/',
        'https://www.recipetineats.com/cheese-truffles-mini-cheese-balls/',
        'https://www.recipetineats.com/truly-crispy-oven-baked-buffalo-wings-my-wings-cookbook/',
        'https://www.recipetineats.com/sticky-chinese-chicken-wings/',
      ],
    ),
  );
}

