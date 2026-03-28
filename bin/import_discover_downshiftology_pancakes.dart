import 'import_discover_downshiftology_breakfast_common.dart';

Future<void> main(List<String> args) {
  return runDownshiftologyImport(
    args,
    const DownshiftologyImportConfig(
      sourceUrl: 'https://downshiftology.com/?s=pancakes',
      csvPath: 'tmp/downshiftology_pancakes_review.csv',
      apiPrefix: 'downshiftology_pancakes',
      sourceName: 'downshiftology',
      cuisineTags: <String>['Pancakes'],
      mealType: 'entree',
    ),
  );
}
