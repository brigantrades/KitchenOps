import 'package:plateplan/core/measurement/measurement_system.dart';

/// Unit dropdown options for an ingredient row, keyed by ingredient name heuristics.
class UnitProfile {
  const UnitProfile({required this.options, required this.defaultUnit});

  final List<String> options;
  final String defaultUnit;
}

/// Picks volume vs mass vs general unit lists for the recipe ingredient editor.
UnitProfile detectUnitProfile(String ingredientName, MeasurementSystem system) {
  final lower = ingredientName.toLowerCase();
  const liquidWords = [
    'milk',
    'oil',
    'broth',
    'sauce',
    'water',
    'juice',
    'vinegar',
    'stock'
  ];
  const powderWords = [
    'flour',
    'sugar',
    'salt',
    'pepper',
    'paprika',
    'cumin',
    'spice'
  ];
  if (liquidWords.any(lower.contains)) {
    return switch (system) {
      MeasurementSystem.metric => const UnitProfile(
          options: ['ml', 'l', 'tsp', 'tbsp', 'custom'],
          defaultUnit: 'ml',
        ),
      MeasurementSystem.imperial => const UnitProfile(
          options: [
            'fl oz',
            'cup',
            'tbsp',
            'tsp',
            'pt',
            'qt',
            'gal',
            'custom',
          ],
          defaultUnit: 'fl oz',
        ),
    };
  }
  if (powderWords.any(lower.contains)) {
    return switch (system) {
      MeasurementSystem.metric => const UnitProfile(
          options: ['tsp', 'tbsp', 'g', 'kg', 'mg', 'custom'],
          defaultUnit: 'tsp',
        ),
      MeasurementSystem.imperial => const UnitProfile(
          options: ['tsp', 'tbsp', 'oz', 'cup', 'custom'],
          defaultUnit: 'tsp',
        ),
    };
  }
  return switch (system) {
    MeasurementSystem.metric => const UnitProfile(
        options: ['g', 'kg', 'mg', 'ml', 'l', 'tsp', 'tbsp', 'piece', 'custom'],
        defaultUnit: 'g',
      ),
    MeasurementSystem.imperial => const UnitProfile(
        options: [
          'oz',
          'lb',
          'fl oz',
          'cup',
          'tbsp',
          'tsp',
          'pt',
          'qt',
          'gal',
          'piece',
          'custom',
        ],
        defaultUnit: 'oz',
      ),
  };
}

/// Case-insensitive match of [unit] to an entry in [options] (returns canonical casing from options).
String? matchUnitOption(List<String> options, String unit) {
  final t = unit.trim().toLowerCase();
  for (final o in options) {
    if (o.toLowerCase() == t) return o;
  }
  return null;
}
