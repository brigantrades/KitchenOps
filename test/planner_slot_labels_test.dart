import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_slot_labels.dart';

void main() {
  group('plannerSlotKind', () {
    test('trims meal_type so padded values count as meal kind', () {
      expect(plannerSlotKind('meal'), PlannerSlotKind.meal);
      expect(plannerSlotKind(' meal '), PlannerSlotKind.meal);
      expect(plannerSlotKind('snack\n'), PlannerSlotKind.snack);
    });

    test('normalizes quotes, ZWSP, nbsp, and null string literals', () {
      expect(plannerSlotKind('"meal"'), PlannerSlotKind.meal);
      expect(plannerSlotKind("'meal'"), PlannerSlotKind.meal);
      expect(plannerSlotKind('meal\u200b'), PlannerSlotKind.meal);
      expect(plannerSlotKind('meal\u00a0'), PlannerSlotKind.meal);
      expect(plannerSlotKind('null'), PlannerSlotKind.meal);
      expect(plannerSlotKind('undefined'), PlannerSlotKind.meal);
    });

    test('legacy numbered meal_type strings are meal/snack kinds for ordinals', () {
      expect(plannerSlotKind('Meal 1'), PlannerSlotKind.meal);
      expect(plannerSlotKind('meal 2'), PlannerSlotKind.meal);
      expect(plannerSlotKind('Snack 3'), PlannerSlotKind.snack);
      expect(plannerSlotKind('Picnic'), PlannerSlotKind.custom);
      expect(plannerSlotKind('meal prep'), PlannerSlotKind.custom);
    });
  });

  group('dedupeMealPlanSlotsByIdPreferPlanned', () {
    test('merges duplicate ids and prefers planned content', () {
      final mon = DateTime(2026, 3, 30);
      final filled = MealPlanSlot(
        id: 'same',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 0,
        mealText: 'Leftover',
      );
      final emptyDup = MealPlanSlot(
        id: 'same',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      final out = dedupeMealPlanSlotsByIdPreferPlanned([emptyDup, filled]);
      expect(out.length, 1);
      expect(out.single.mealText, 'Leftover');
    });
  });

  group('nextNewSlotDisplayOrdinal / plannerNewSlotRecipePickerDisplayLabel', () {
    test('meal ordinal follows existing meal rows on the day', () {
      final mon = DateTime(2026, 3, 30);
      final m1 = MealPlanSlot(
        id: 'a',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      final m2 = MealPlanSlot(
        id: 'b',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 1,
      );
      expect(nextNewSlotDisplayOrdinal([m1, m2], 'meal'), 3);
      expect(
        plannerNewSlotRecipePickerDisplayLabel('meal', 3),
        'Meal 3',
      );
    });

    test('snack ordinal ignores meal rows', () {
      final mon = DateTime(2026, 3, 30);
      final meal = MealPlanSlot(
        id: 'a',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      expect(nextNewSlotDisplayOrdinal([meal], 'snack'), 1);
      expect(
        plannerNewSlotRecipePickerDisplayLabel('snack', 1),
        'Snack 1',
      );
    });

    test('custom label returns ordinal 0 and title is capitalized', () {
      final mon = DateTime(2026, 3, 30);
      final m = MealPlanSlot(
        id: 'a',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      expect(nextNewSlotDisplayOrdinal([m], 'Picnic'), 0);
      expect(
        plannerNewSlotRecipePickerDisplayLabel('Picnic', 0),
        'Picnic',
      );
    });
  });

  group('plannerSlotDisplayLabel', () {
    test('duplicate same id in list does not yield two Meal 1 labels', () {
      final mon = DateTime(2026, 3, 30);
      final a = MealPlanSlot(
        id: 'dup',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 0,
        mealText: 'One',
      );
      final aAgain = MealPlanSlot(
        id: 'dup',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      final b = MealPlanSlot(
        id: 'other',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 1,
        mealText: 'Two',
      );
      final c = MealPlanSlot(
        id: 'third',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'meal',
        slotOrder: 2,
      );
      final messy = [a, b, aAgain, c];
      expect(plannerSlotDisplayLabel(messy, a), 'Meal 1');
      expect(plannerSlotDisplayLabel(messy, b), 'Meal 2');
      expect(plannerSlotDisplayLabel(messy, c), 'Meal 3');
    });

    test('legacy Meal 1 / Meal 2 labels renumber when slot order changes', () {
      final mon = DateTime(2026, 3, 30);
      final formerSecond = MealPlanSlot(
        id: 'b',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'Meal 2',
        slotOrder: 0,
      );
      final formerFirst = MealPlanSlot(
        id: 'a',
        weekStart: mon,
        dayOfWeek: 0,
        mealLabel: 'Meal 1',
        slotOrder: 1,
      );
      final day = [formerSecond, formerFirst];
      expect(plannerSlotDisplayLabel(day, formerSecond), 'Meal 1');
      expect(plannerSlotDisplayLabel(day, formerFirst), 'Meal 2');
    });
  });
}
