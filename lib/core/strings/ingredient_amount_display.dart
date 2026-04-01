String formatIngredientAmount(double amount) {
  const epsilon = 1e-6;

  bool near(double target) => (amount - target).abs() < epsilon;

  final whole = amount.roundToDouble();
  if ((amount - whole).abs() < epsilon) {
    return whole.toInt().toString();
  }

  if (near(0.25)) return '1/4';
  if (near(1 / 3)) return '1/3';
  if (near(0.5)) return '1/2';

  final fixed = amount.toStringAsFixed(3);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

// --- US kitchen measures: round-up + fraction labels (display / editor) ---

const _kitchenFracTol = 0.015;

/// Ascending standard recipe fractions in (0, 1].
const _kitchenFractionSteps = <double>[0.25, 1 / 3, 0.5, 2 / 3, 0.75, 1.0];

/// Smallest standard fraction ≥ [fractionalPart] (for fractionalPart ∈ (0, 1]).
double ceilKitchenFraction(double fractionalPart) {
  var f = fractionalPart;
  if (f <= 0) return 0;
  for (final s in _kitchenFractionSteps) {
    if (f <= s + 1e-9) {
      return s;
    }
  }
  return 1.0;
}

/// Rounds [amount] up to the next common US recipe fraction (for cup, tbsp, tsp).
double roundUpToKitchenStep(double amount) {
  if (amount <= 0) return amount;
  final w = amount.floor();
  var f = amount - w;
  // If conversion lands just off a whole number, keep the whole number.
  const nearWholeTol = 0.03;
  if (f <= nearWholeTol) {
    return w.toDouble();
  }
  if ((1 - f) <= nearWholeTol) {
    return (w + 1).toDouble();
  }
  if (f < 1e-9) {
    return w.toDouble();
  }
  final u = ceilKitchenFraction(f);
  if ((u - 1.0).abs() < 1e-9) {
    return (w + 1).toDouble();
  }
  return w + u;
}

String _kitchenFractionalPartToString(double f) {
  if ((f - 0.25).abs() < _kitchenFracTol) return '1/4';
  if ((f - 1 / 3).abs() < _kitchenFracTol) return '1/3';
  if ((f - 0.5).abs() < _kitchenFracTol) return '1/2';
  if ((f - 2 / 3).abs() < _kitchenFracTol) return '2/3';
  if ((f - 0.75).abs() < _kitchenFracTol) return '3/4';
  return formatIngredientAmount(f);
}

/// Formats amounts after [roundUpToKitchenStep] (plain fractions and mixed numbers).
String formatKitchenMeasureAmount(double amount) {
  if (amount <= 0) {
    return formatIngredientAmount(amount);
  }
  final w = amount.floor();
  var f = amount - w;
  const eps = 1e-5;
  if (f < eps) {
    return w.toString();
  }
  if ((f - 1.0).abs() < eps) {
    return '${w + 1}';
  }
  final fracStr = _kitchenFractionalPartToString(f);
  if (w == 0) {
    return fracStr;
  }
  return '$w $fracStr';
}

/// Readable grams for metric display (e.g. ~1 lb → 500 g).
double snapMetricGramsForDisplay(double grams) {
  if (grams < 100) {
    return grams.roundToDouble();
  }
  if (grams < 400) {
    return (grams / 10).round() * 10.0;
  }
  return (grams / 100).round() * 100.0;
}

/// After unit conversion: kitchen fractions for US cup/tbsp/tsp; otherwise [formatIngredientAmount].
String formatConvertedIngredientAmount(double amount, String unit) {
  switch (unit) {
    case 'cup':
    case 'tbsp':
    case 'tsp':
      return formatKitchenMeasureAmount(amount);
    case 'oz':
      return formatQuarterMeasureAmount(amount);
    default:
      return formatIngredientAmount(amount);
  }
}

// --- Imperial mass: ounces as quarters ---

double snapToNearestQuarter(double amount) {
  return (amount * 4).round() / 4.0;
}

String formatQuarterMeasureAmount(double amount) {
  if (amount <= 0) {
    return formatIngredientAmount(amount);
  }
  final snapped = snapToNearestQuarter(amount);
  final w = snapped.floor();
  final f = snapped - w;
  const eps = 1e-6;
  if (f < eps) {
    return w.toString();
  }
  if ((f - 1.0).abs() < eps) {
    return '${w + 1}';
  }
  String frac;
  if ((f - 0.25).abs() < 1e-3) {
    frac = '1/4';
  } else if ((f - 0.5).abs() < 1e-3) {
    frac = '1/2';
  } else if ((f - 0.75).abs() < 1e-3) {
    frac = '3/4';
  } else {
    frac = formatIngredientAmount(f);
  }
  if (w == 0) return frac;
  return '$w $frac';
}
