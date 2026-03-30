import 'package:plateplan/core/models/app_models.dart';

/// How a numeric quantity is interpreted for pantry vs recipe comparison.
enum PantryPhysicalKind {
  /// Grams (mass).
  mass,

  /// Milliliters (volume).
  volume,

  /// Discrete count (each, whole numbers).
  count,
}

/// A quantity normalized to a single physical kind for subtraction.
class NormalizedQuantity {
  const NormalizedQuantity({
    required this.kind,
    required this.value,
    required this.displayUnit,
  });

  final PantryPhysicalKind kind;
  final double value;

  /// Short label for UI, e.g. `g`, `ml`, `each`.
  final String displayUnit;
}

NormalizedQuantity? normalizePantryAmount(
  double amount,
  String rawUnit, {
  bool qualitative = false,
}) {
  if (qualitative) return null;
  final u = rawUnit.trim().toLowerCase();
  if (u.isEmpty) {
    if (amount > 0) {
      return NormalizedQuantity(
        kind: PantryPhysicalKind.count,
        value: amount,
        displayUnit: 'each',
      );
    }
    return null;
  }

  if (u == 'g' || u == 'gram' || u == 'grams') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.mass,
      value: amount,
      displayUnit: 'g',
    );
  }
  if (u == 'kg' || u == 'kilogram' || u == 'kilograms') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.mass,
      value: amount * 1000,
      displayUnit: 'g',
    );
  }
  if (u == 'mg' || u == 'milligram' || u == 'milligrams') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.mass,
      value: amount / 1000,
      displayUnit: 'g',
    );
  }
  if (u == 'lb' || u == 'lbs' || u == 'pound' || u == 'pounds') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.mass,
      value: amount * 453.592,
      displayUnit: 'g',
    );
  }
  if (u == 'oz' || u == 'ounce' || u == 'ounces') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.mass,
      value: amount * 28.3495,
      displayUnit: 'g',
    );
  }

  if (u == 'ml' || u == 'milliliter' || u == 'milliliters') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.volume,
      value: amount,
      displayUnit: 'ml',
    );
  }
  if (u == 'l' || u == 'liter' || u == 'liters' || u == 'litre' || u == 'litres') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.volume,
      value: amount * 1000,
      displayUnit: 'ml',
    );
  }
  if (u == 'cup' || u == 'cups') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.volume,
      value: amount * 240,
      displayUnit: 'ml',
    );
  }
  if (u == 'tbsp' || u == 'tablespoon' || u == 'tablespoons') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.volume,
      value: amount * 15,
      displayUnit: 'ml',
    );
  }
  if (u == 'tsp' || u == 'teaspoon' || u == 'teaspoons') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.volume,
      value: amount * 5,
      displayUnit: 'ml',
    );
  }
  if (u == 'fl oz' || u == 'floz' || u == 'fluid oz' || u == 'fluid ounce') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.volume,
      value: amount * 29.5735,
      displayUnit: 'ml',
    );
  }

  if (u == 'each' ||
      u == 'whole' ||
      u == 'clove' ||
      u == 'cloves' ||
      u == 'pinch' ||
      u == 'slice' ||
      u == 'slices') {
    return NormalizedQuantity(
      kind: PantryPhysicalKind.count,
      value: amount,
      displayUnit: u == 'each' ? 'each' : u,
    );
  }

  return null;
}

NormalizedQuantity? normalizePantryIngredientFromIngredient(Ingredient ing) {
  return normalizePantryAmount(
    ing.amount,
    ing.unit,
    qualitative: ing.qualitative,
  );
}

String formatNormalizedForDisplay(NormalizedQuantity n) {
  final v = n.value;
  if (n.kind == PantryPhysicalKind.count) {
    if (v == v.roundToDouble()) {
      return '${v.round()} ${n.displayUnit}';
    }
    return '${v.toStringAsFixed(1)} ${n.displayUnit}';
  }
  if (v >= 1000 && (n.kind == PantryPhysicalKind.mass)) {
    return '${(v / 1000).toStringAsFixed(2)} kg';
  }
  if (v >= 1000 && (n.kind == PantryPhysicalKind.volume)) {
    return '${(v / 1000).toStringAsFixed(2)} L';
  }
  return '${v.toStringAsFixed(1)} ${n.displayUnit}';
}

String demandMapKey(String nameKey, PantryPhysicalKind kind) =>
    '$nameKey|${kind.name}';
