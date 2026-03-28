import 'import_discover_lunch_common.dart';

Future<void> main(List<String> args) {
  return runLunchImport(
    args,
    const LunchImportConfig(
      sourcePages: <String>[
        'https://downshiftology.com/spring-salads-perfect-for-warmer-days/',
        'https://downshiftology.com/best-high-protein-salad-recipes/',
      ],
      csvPath: 'tmp/downshiftology_lunch_salads_review.csv',
      apiPrefix: 'downshiftology_lunch_salads',
      sourceName: 'downshiftology',
      cuisineTags: <String>['Salads'],
      includeKeywords: <String>[
        'salad',
        'greens',
        'vinaigrette',
        'protein salad',
      ],
    ),
  );
}
