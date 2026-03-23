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
