import 'import_discover_downshiftology_breakfast_common.dart';

Future<void> main(List<String> args) {
  return runDownshiftologyImport(
    args,
    const DownshiftologyImportConfig(
      sourceUrl: 'https://downshiftology.com/whole30-breakfast-recipes/',
      csvPath: 'tmp/downshiftology_whole30_breakfast_review.csv',
      apiPrefix: 'downshiftology_whole30_breakfast',
      sourceName: 'downshiftology',
      cuisineTags: <String>['Whole30'],
      mealType: 'entree',
      focusStartRegex: r'Whole30 Breakfast Recipes with Eggs',
      focusEndRegex: r'More Whole30 Recipes',
    ),
  );
}
