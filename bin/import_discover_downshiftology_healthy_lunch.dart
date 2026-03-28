import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[
        'https://downshiftology.com/healthy-lunch-ideas/',
      ],
      csvPath: 'tmp/downshiftology_healthy_lunch_review.csv',
      apiPrefix: 'downshiftology_healthy_lunch',
      sourceName: 'downshiftology',
      cuisineTags: <String>['Healthy Lunch Ideas'],
      includeKeywords: <String>[
        'healthy',
        'lunch',
        'meal prep',
        'salad',
      ],
    ),
  );
}
