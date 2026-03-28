import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  const wrapsRoundup = 'https://www.cookedandloved.com/best-wraps-recipes/';

  // Curated links from the roundup so imports remain stable
  // even when source page markup changes.
  const curatedWrapUrls = <String>[
    'https://www.cookedandloved.com/recipes/cheesy-garlic-chicken-wraps/',
    'https://www.cookedandloved.com/recipes/chicken-salad-wraps/',
    'https://www.cookedandloved.com/recipes/big-mac-wraps/',
    'https://www.cookedandloved.com/recipes/protein-veggie-wrap/',
    'https://www.cookedandloved.com/recipes/beef-burritos/',
    'https://www.cookedandloved.com/recipes/bang-bang-chicken-wraps/',
    'https://dishingouthealth.com/miso-chicken-caesar-wrap/',
    'https://www.feastingathome.com/turkish-lamb-wraps/',
    'https://www.halfbakedharvest.com/poblano-avocado-burrito/',
    'https://www.chelseasmessyapron.com/mediterranean-wrap/',
    'https://hungryhealthyhappy.com/salmon-wrap/',
    'https://www.cookedandloved.com/recipes/healthy-breakfast-burritos/',
    'https://www.tamingtwins.com/halloumi-wraps/',
    'https://www.kitchensanctuary.com/chicken-souvlaki-with-homemade-tzatziki/',
    'https://healthyfitnessmeals.com/easy-southwest-chicken-wrap/',
    'https://fitfoodiefinds.com/breakfast-crunchwrap-recipe/',
    'https://www.skinnytaste.com/cheeseburger-crunch-wrap/',
    'https://thecheaplazyvegan.com/rainbow-wrap/',
    'https://lifemadesweeter.com/low-carb-wraps/',
    'https://thebestketorecipes.com/easy-keto-italian-lettuce-wrap/',
    'https://www.cottercrunch.com/chicken-salad-wrap/',
  ];

  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[wrapsRoundup],
      csvPath: 'tmp/lunch_wraps_cookedandloved_roundup_review.csv',
      apiPrefix: 'lunch_wraps_cookedandloved_roundup',
      sourceName: 'cookedandloved_roundup',
      cuisineTags: <String>['Sandwiches & Wraps', 'Lunch'],
      includeKeywords: <String>[
        'wrap',
        'wraps',
        'burrito',
        'crunchwrap',
        'sandwich',
        'lunch',
      ],
      fallbackRecipeUrls: curatedWrapUrls,
      trustExtractedFromSourceUrls: <String>[wrapsRoundup],
      // Intentionally no restrictRecipeHosts:
      // this roundup includes multiple external recipe domains.
    ),
  );
}

