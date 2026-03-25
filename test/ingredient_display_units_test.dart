import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/models/app_models.dart';

void main() {
  test('1 kg converts to lb in US customary display', () {
    final ing = Ingredient(
      name: 'flour',
      amount: 1,
      unit: 'kg',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.imperial);
    expect(c.unit, 'lb');
    final lb = double.parse(c.amount);
    expect(lb, closeTo(2.20462, 0.02));
  });

  test('1 cup converts to whole ml in metric display', () {
    final ing = Ingredient(
      name: 'water',
      amount: 1,
      unit: 'cup',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.metric);
    expect(c.unit, 'ml');
    final ml = double.parse(c.amount);
    expect(ml, 237);
  });

  test('tbsp stays tbsp in metric display', () {
    final ing = Ingredient(
      name: 'mint',
      amount: 1,
      unit: 'tbsp',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.metric);
    expect(c.amount, '1');
    expect(c.unit, 'tbsp');
  });

  test('qualitative ingredient passes through display columns', () {
    final ing = Ingredient(
      name: 'salt',
      amount: 0,
      unit: 'to taste',
      category: GroceryCategory.other,
      qualitative: true,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.metric);
    expect(c.amount, '—');
    expect(c.unit, 'to taste');
  });

  test('piece is not converted', () {
    final ing = Ingredient(
      name: 'egg',
      amount: 2,
      unit: 'piece',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.imperial);
    expect(c.amount, '2');
    expect(c.unit, 'piece');
  });

  test('convertAmountAndUnitForMeasurementSystem kg to lb', () {
    final out = convertAmountAndUnitForMeasurementSystem(
      amount: 1,
      unitRaw: 'kg',
      target: MeasurementSystem.imperial,
    );
    expect(out, isNotNull);
    expect(out!.unit, 'lb');
    expect(out.amount, closeTo(2.20462, 0.02));
  });

  test('convertAmountAndUnitForMeasurementSystem tbsp to metric ml is rounded', () {
    final out = convertAmountAndUnitForMeasurementSystem(
      amount: 1,
      unitRaw: 'tbsp',
      target: MeasurementSystem.metric,
    );
    expect(out, isNotNull);
    expect(out!.unit, 'ml');
    expect(out.amount, 15);
  });
}
