import 'import_discover_downshiftology_breakfast_common.dart';

Future<void> main(List<String> args) {
  return runDownshiftologyImport(
    args,
    const DownshiftologyImportConfig(
      sourceUrl: 'https://downshiftology.com/15-best-high-protein-breakfast-ideas/',
      csvPath: 'tmp/downshiftology_high_protein_breakfast_review.csv',
      apiPrefix: 'downshiftology_high_protein_breakfast',
      sourceName: 'downshiftology',
      cuisineTags: <String>['High-Protein'],
      mealType: 'entree',
      focusStartRegex: r'Best High-Protein Breakfast Ideas',
      focusEndRegex: r'More Recipe Ideas',
    ),
  );
}
