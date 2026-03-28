import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[
        'https://downshiftology.com/bento-box-lunch-ideas/',
      ],
      csvPath: 'tmp/downshiftology_bento_lunch_review.csv',
      apiPrefix: 'downshiftology_bento_lunch',
      sourceName: 'downshiftology',
      cuisineTags: <String>['Bento Box Lunch'],
      includeKeywords: <String>[
        'bento',
        'lunch',
        'meal prep',
      ],
    ),
  );
}
