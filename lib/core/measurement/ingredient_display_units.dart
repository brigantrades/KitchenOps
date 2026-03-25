import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/measurement/us_customary_units.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';

/// Normalizes free-text units to internal keys. Returns null if unrecognized.
String? normalizeIngredientUnitKey(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  if (s == 'fl oz' ||
      s == 'floz' ||
      s == 'fluid oz' ||
      s.startsWith('fluid ounce')) {
    return 'fl oz';
  }
  const map = <String, String>{
    'g': 'g',
    'gram': 'g',
    'grams': 'g',
    'kg': 'kg',
    'kilogram': 'kg',
    'kilograms': 'kg',
    'mg': 'mg',
    'milligram': 'mg',
    'milligrams': 'mg',
    'oz': 'oz',
    'ounce': 'oz',
    'ounces': 'oz',
    'lb': 'lb',
    'lbs': 'lb',
    'pound': 'lb',
    'pounds': 'lb',
    'ml': 'ml',
    'milliliter': 'ml',
    'milliliters': 'ml',
    'millilitre': 'ml',
    'millilitres': 'ml',
    'l': 'l',
    'liter': 'l',
    'liters': 'l',
    'litre': 'l',
    'litres': 'l',
    'cup': 'cup',
    'cups': 'cup',
    'tbsp': 'tbsp',
    'tablespoon': 'tbsp',
    'tablespoons': 'tbsp',
    'tbl': 'tbsp',
    'tsp': 'tsp',
    'teaspoon': 'tsp',
    'teaspoons': 'tsp',
    'pt': 'pt',
    'pint': 'pt',
    'pints': 'pt',
    'qt': 'qt',
    'quart': 'qt',
    'quarts': 'qt',
    'gal': 'gal',
    'gallon': 'gal',
    'gallons': 'gal',
    'piece': 'piece',
    'pieces': 'piece',
  };
  return map[s];
}

double? _volumeKeyToMl(double amount, String key) {
  switch (key) {
    case 'ml':
      return amount;
    case 'l':
      return amount * 1000;
    case 'cup':
      return amount * UsCustomaryUnits.mlPerCup;
    case 'tbsp':
      return amount * UsCustomaryUnits.mlPerTbsp;
    case 'tsp':
      return amount * UsCustomaryUnits.mlPerTsp;
    case 'fl oz':
      return amount * UsCustomaryUnits.mlPerUsFlOz;
    case 'pt':
      return amount * UsCustomaryUnits.mlPerUsPt;
    case 'qt':
      return amount * UsCustomaryUnits.mlPerUsQt;
    case 'gal':
      return amount * UsCustomaryUnits.mlPerUsGal;
    default:
      return null;
  }
}

double? _massKeyToGrams(double amount, String key) {
  switch (key) {
    case 'g':
      return amount;
    case 'kg':
      return amount * 1000;
    case 'mg':
      return amount / 1000;
    case 'oz':
      return amount * UsCustomaryUnits.gPerAvoirdupoisOz;
    case 'lb':
      return amount * UsCustomaryUnits.gPerLb;
    default:
      return null;
  }
}

sealed class CanonicalIngredientMeasure {
  const CanonicalIngredientMeasure();
}

final class CanonicalMass extends CanonicalIngredientMeasure {
  const CanonicalMass(this.grams);
  final double grams;
}

final class CanonicalVolume extends CanonicalIngredientMeasure {
  const CanonicalVolume(this.ml);
  final double ml;
}

/// Parses a measured ingredient line to grams (mass) or ml (volume).
CanonicalIngredientMeasure? canonicalIngredientMeasure(
  double amount,
  String unitRaw,
) {
  if (amount <= 0) return null;
  final key = normalizeIngredientUnitKey(unitRaw);
  if (key == null) return null;
  if (key == 'piece') return null;

  final g = _massKeyToGrams(amount, key);
  if (g != null) return CanonicalMass(g);

  final ml = _volumeKeyToMl(amount, key);
  if (ml != null) return CanonicalVolume(ml);

  return null;
}

({double amount, String unit}) _massValuesForSystem(double grams, MeasurementSystem s) {
  switch (s) {
    case MeasurementSystem.metric:
      if (grams >= 1000) {
        return (amount: grams / 1000, unit: 'kg');
      }
      if (grams >= 1) {
        return (amount: grams, unit: 'g');
      }
      return (amount: grams * 1000, unit: 'mg');
    case MeasurementSystem.imperial:
      final lb = grams / UsCustomaryUnits.gPerLb;
      if (lb >= 1) {
        return (amount: lb, unit: 'lb');
      }
      final oz = grams / UsCustomaryUnits.gPerAvoirdupoisOz;
      return (amount: oz, unit: 'oz');
  }
}

({double amount, String unit}) _volumeValuesForSystem(double ml, MeasurementSystem s) {
  switch (s) {
    case MeasurementSystem.metric:
      if (ml >= 1000) {
        return (amount: ml / 1000, unit: 'l');
      }
      // Whole millilitres — avoids "14.787 ml" for 1 tbsp etc. when converting.
      return (amount: ml.roundToDouble(), unit: 'ml');
    case MeasurementSystem.imperial:
      if (ml >= UsCustomaryUnits.mlPerUsGal) {
        return (amount: ml / UsCustomaryUnits.mlPerUsGal, unit: 'gal');
      }
      if (ml >= UsCustomaryUnits.mlPerUsQt) {
        return (amount: ml / UsCustomaryUnits.mlPerUsQt, unit: 'qt');
      }
      if (ml >= UsCustomaryUnits.mlPerUsPt) {
        return (amount: ml / UsCustomaryUnits.mlPerUsPt, unit: 'pt');
      }
      final cups = ml / UsCustomaryUnits.mlPerCup;
      if (cups >= 0.25) {
        return (amount: cups, unit: 'cup');
      }
      final flOz = ml / UsCustomaryUnits.mlPerUsFlOz;
      if (flOz >= 0.5) {
        return (amount: flOz, unit: 'fl oz');
      }
      final tbsp = ml / UsCustomaryUnits.mlPerTbsp;
      if (tbsp >= 0.5) {
        return (amount: tbsp, unit: 'tbsp');
      }
      final tsp = ml / UsCustomaryUnits.mlPerTsp;
      return (amount: tsp, unit: 'tsp');
  }
}

({String amount, String unit}) _formatMass(double grams, MeasurementSystem s) {
  final v = _massValuesForSystem(grams, s);
  return (amount: formatIngredientAmount(v.amount), unit: v.unit);
}

({String amount, String unit}) _formatVolume(double ml, MeasurementSystem s) {
  final v = _volumeValuesForSystem(ml, s);
  return (amount: formatIngredientAmount(v.amount), unit: v.unit);
}

/// Kitchen spoon measures: keep as written in metric view (no "14.787 ml" for 1 tbsp).
bool _isKitchenSpoonUnitKey(String? key) => key == 'tsp' || key == 'tbsp';

/// Table columns: amount and unit text for [system] (display only).
({String amount, String unit}) ingredientDisplayColumns(
  Ingredient ing,
  MeasurementSystem system,
) {
  if (ing.qualitative) {
    return (amount: '—', unit: ing.unit.trim());
  }
  final c = canonicalIngredientMeasure(ing.amount, ing.unit);
  if (c == null) {
    return (
      amount: formatIngredientAmount(ing.amount),
      unit: ing.unit.trim(),
    );
  }
  if (c case CanonicalVolume()) {
    final key = normalizeIngredientUnitKey(ing.unit);
    if (system == MeasurementSystem.metric && _isKitchenSpoonUnitKey(key)) {
      return (
        amount: formatIngredientAmount(ing.amount),
        unit: ing.unit.trim(),
      );
    }
  }
  return switch (c) {
    CanonicalMass(:final grams) => _formatMass(grams, system),
    CanonicalVolume(:final ml) => _formatVolume(ml, system),
  };
}

/// Single-line quantity for lists (non-qualitative: amount + unit).
String ingredientDisplayQuantityLabel(Ingredient ing, MeasurementSystem system) {
  if (ing.qualitative) {
    return ing.unit.trim();
  }
  final cols = ingredientDisplayColumns(ing, system);
  if (cols.unit.isEmpty) return cols.amount;
  return '${cols.amount} ${cols.unit}'.trim();
}

/// Converts a measured line to [target] units for the recipe editor.
/// Returns null if the line is not convertible (qualitative, piece, unknown unit).
({double amount, String unit})? convertAmountAndUnitForMeasurementSystem({
  required double amount,
  required String unitRaw,
  required MeasurementSystem target,
}) {
  if (normalizeIngredientUnitKey(unitRaw) == 'piece') return null;

  final c = canonicalIngredientMeasure(amount, unitRaw);
  if (c == null) return null;

  return switch (c) {
    CanonicalMass(:final grams) => _massValuesForSystem(grams, target),
    CanonicalVolume(:final ml) => _volumeValuesForSystem(ml, target),
  };
}
