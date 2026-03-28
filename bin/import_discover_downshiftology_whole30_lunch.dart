import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[
        'https://downshiftology.com/whole30-lunch-ideas/',
      ],
      csvPath: 'tmp/downshiftology_whole30_lunch_review.csv',
      apiPrefix: 'downshiftology_whole30_lunch',
      sourceName: 'downshiftology',
      cuisineTags: <String>['Whole30'],
      includeKeywords: <String>[
        'whole30',
        'whole 30',
        'paleo',
        'salad',
        'chicken',
        'beef',
        'pork',
        'turkey',
        'salmon',
        'shrimp',
        'cod',
        'tuna',
        'shakshuka',
        'zucchini',
        'cauliflower',
        'cabbage',
        'sweet potato',
        'soup',
        'stew',
        'fajitas',
        'kabobs',
        'meatballs',
        'burger',
      ],
      restrictRecipeHosts: <String>[
        'downshiftology.com',
        'www.downshiftology.com',
      ],
    ),
  );
}
