import 'import_discover_downshiftology_breakfast_common.dart';

Future<void> main(List<String> args) {
  return runDownshiftologyImport(
    args,
    const DownshiftologyImportConfig(
      sourceUrl: 'https://downshiftology.com/best-healthy-breakfast-ideas/',
      csvPath: 'tmp/downshiftology_healthy_breakfast_review.csv',
      apiPrefix: 'downshiftology_healthy_breakfast',
      sourceName: 'downshiftology',
      cuisineTags: <String>['Healthy'],
      mealType: 'entree',
      focusStartRegex: r'Staple Breakfast Ideas',
      focusEndRegex: r'More Recipe Roundup Ideas',
    ),
  );
}
