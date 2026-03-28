import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  const source = 'https://downshiftology.com/courses/desserts/';

  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[source],
      csvPath: 'tmp/desserts_downshiftology_review.csv',
      apiPrefix: 'desserts_downshiftology',
      sourceName: 'downshiftology',
      mealType: 'dessert',
      cuisineTags: <String>['Desserts'],
      includeKeywords: <String>[
        'dessert',
        'chocolate',
        'cookie',
        'cake',
        'muffin',
        'bread',
        'pie',
        'cobbler',
        'crisp',
        'fruit',
        'no-bake',
        'ice cream',
        'pudding',
        'affogato',
        'mousse',
      ],
      trustExtractedFromSourceUrls: <String>[source],
      restrictRecipeHosts: <String>[
        'downshiftology.com',
        'www.downshiftology.com',
      ],
      fallbackRecipeUrls: <String>[
        'https://downshiftology.com/recipes/paleo-chocolate-cake/',
        'https://downshiftology.com/recipes/almond-cake/',
        'https://downshiftology.com/recipes/flourless-chocolate-cake/',
        'https://downshiftology.com/recipes/paleo-lemon-blueberry-cake/',
        'https://downshiftology.com/recipes/gluten-free-carrot-cake/',
        'https://downshiftology.com/recipes/gluten-free-chocolate-chip-cookies/',
        'https://downshiftology.com/recipes/no-bake-cookies/',
        'https://downshiftology.com/recipes/chocolate-chip-tahini-cookies/',
        'https://downshiftology.com/recipes/banana-oatmeal-cookies/',
        'https://downshiftology.com/recipes/super-moist-banana-bread/',
        'https://downshiftology.com/recipes/paleo-blueberry-muffins/',
        'https://downshiftology.com/recipes/paleo-chocolate-zucchini-bread/',
        'https://downshiftology.com/recipes/healthy-zucchini-muffins/',
        'https://downshiftology.com/recipes/cranberry-orange-muffins/',
        'https://downshiftology.com/recipes/chocolate-covered-strawberries/',
        'https://downshiftology.com/recipes/chocolate-mousse/',
        'https://downshiftology.com/recipes/mint-chocolate-mousse-cake/',
        'https://downshiftology.com/recipes/panna-cotta/',
        'https://downshiftology.com/recipes/affogato/',
        'https://downshiftology.com/recipes/vegan-cacao-nib-ice-cream/',
        'https://downshiftology.com/recipes/chocolate-crunch-bars/',
        'https://downshiftology.com/recipes/peach-crisp/',
        'https://downshiftology.com/recipes/chocolate-avocado-pudding/',
        'https://downshiftology.com/recipes/rice-pudding/',
      ],
    ),
  );
}

