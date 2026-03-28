import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  const wrapsRoundup =
      'https://www.cookedandloved.com/best-wraps-recipes/';
  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[wrapsRoundup],
      csvPath: 'tmp/lunch_sandwiches_wraps_review.csv',
      apiPrefix: 'lunch_sandwiches_wraps',
      sourceName: 'cookedandloved',
      cuisineTags: <String>['Sandwiches & Wraps'],
      includeKeywords: <String>[
        'sandwich',
        'wrap',
        'panini',
        'melt',
      ],
      trustExtractedFromSourceUrls: <String>[wrapsRoundup],
      restrictRecipeHosts: <String>[
        'cookedandloved.com',
        'www.cookedandloved.com',
      ],
    ),
  );
}
