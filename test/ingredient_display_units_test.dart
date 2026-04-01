import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/models/app_models.dart';

void main() {
  test('normalizeIngredientUnitKey strips trailing punctuation from OCR', () {
    expect(normalizeIngredientUnitKey('Tbsp.'), 'tbsp');
    expect(normalizeIngredientUnitKey('tsp,'), 'tsp');
    expect(normalizeIngredientUnitKey('ml.'), 'ml');
  });

  test('normalizeIngredientUnitKey tolerates zero-width and parentheses', () {
    expect(normalizeIngredientUnitKey('tbsp\u200B'), 'tbsp');
    expect(normalizeIngredientUnitKey('(ml)'), 'ml');
    expect(normalizeIngredientUnitKey('tsp)'), 'tsp');
    expect(normalizeIngredientUnitKey('fl. oz'), 'fl oz');
  });

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

  test('grams to oz formats as quarters in US display', () {
    final ing = Ingredient(
      name: 'nuts',
      amount: 100,
      unit: 'g',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.imperial);
    expect(c.unit, 'oz');
    expect(c.amount, '3 1/2');
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

  test('metric display rounds tsp/tbsp to kitchen fractions', () {
    final tsp = Ingredient(
      name: 'salt',
      amount: 0.406,
      unit: 'tsp',
      category: GroceryCategory.other,
    );
    final tspCols = ingredientDisplayColumns(tsp, MeasurementSystem.metric);
    expect(tspCols.amount, '1/2');
    expect(tspCols.unit, 'tsp');

    final tbsp = Ingredient(
      name: 'paprika',
      amount: 0.676,
      unit: 'tbsp',
      category: GroceryCategory.other,
    );
    final tbspCols = ingredientDisplayColumns(tbsp, MeasurementSystem.metric);
    expect(tbspCols.amount, '3/4');
    expect(tbspCols.unit, 'tbsp');
  });

  test('30 ml converts to 1 fl oz in US display (snap near-whole)', () {
    final ing = Ingredient(
      name: 'extract',
      amount: 30,
      unit: 'ml',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.imperial);
    expect(c.amount, '1');
    expect(c.unit, 'fl oz');
  });

  test('10 ml converts to 3/4 tbsp in US display (kitchen fraction round-up)', () {
    final ing = Ingredient(
      name: 'paprika',
      amount: 10,
      unit: 'ml',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.imperial);
    expect(c.amount, '3/4');
    expect(c.unit, 'tbsp');
  });

  test('5 ml converts to 1 tsp in US display (snap near whole)', () {
    final ing = Ingredient(
      name: 'pepper',
      amount: 5,
      unit: 'ml',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.imperial);
    expect(c.amount, '1');
    expect(c.unit, 'tsp');
  });

  test('453 g displays as 500 g in metric', () {
    final ing = Ingredient(
      name: 'beef',
      amount: 453,
      unit: 'g',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.metric);
    expect(c.amount, '500');
    expect(c.unit, 'g');
  });

  test('ml to fl oz does not snap when not near a whole fl oz', () {
    // ~1.18 fl oz from 35 ml — outside 0.03 tolerance from 1
    final ing = Ingredient(
      name: 'juice',
      amount: 35,
      unit: 'ml',
      category: GroceryCategory.other,
    );
    final c = ingredientDisplayColumns(ing, MeasurementSystem.imperial);
    expect(c.unit, 'fl oz');
    final fl = double.parse(c.amount);
    expect(fl, closeTo(35 / 29.5735295625, 0.001));
    expect(fl, greaterThan(1.03));
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
