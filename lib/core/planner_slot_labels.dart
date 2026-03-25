import 'package:plateplan/core/models/app_models.dart';

/// Kind of planner row for display numbering.
enum PlannerSlotKind { meal, snack, custom }

/// Canonical meal-like labels (including legacy meal times from older app versions).
bool _isMealKind(String lower) {
  return lower == 'meal' ||
      lower == 'entree' ||
      lower == 'side' ||
      lower == 'sauce' ||
      lower == 'breakfast' ||
      lower == 'brunch' ||
      lower == 'lunch' ||
      lower == 'dinner' ||
      lower == 'supper' ||
      lower == 'dessert';
}

/// Classifies [meal_type] from the database.
PlannerSlotKind plannerSlotKind(String mealLabel) {
  final lower = mealLabel.toLowerCase();
  if (lower == 'snack') return PlannerSlotKind.snack;
  if (_isMealKind(lower)) return PlannerSlotKind.meal;
  return PlannerSlotKind.custom;
}

bool _sameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Slots for one calendar day of the plan, sorted by [MealPlanSlot.slotOrder].
String plannerSlotDisplayLabel(
  List<MealPlanSlot> daySlotsSorted,
  MealPlanSlot slot,
) {
  final kind = plannerSlotKind(slot.mealLabel);
  if (kind == PlannerSlotKind.custom) {
    final raw = slot.mealLabel.trim();
    if (raw.isEmpty) return 'Meal';
    final lower = raw.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  var mealIndex = 0;
  var snackIndex = 0;
  for (final s in daySlotsSorted) {
    final k = plannerSlotKind(s.mealLabel);
    if (k == PlannerSlotKind.meal) {
      mealIndex++;
      if (s.id == slot.id) return 'Meal $mealIndex';
    } else if (k == PlannerSlotKind.snack) {
      snackIndex++;
      if (s.id == slot.id) return 'Snack $snackIndex';
    }
  }
  return 'Meal';
}

/// Short tag for condensed planner UI, e.g. `Meal 1` → `M1`, `Snack 2` → `S2`.
String plannerSlotShortLabel(String displayLabel) {
  final t = displayLabel.trim();
  final meal = RegExp(r'^Meal\s+(\d+)$', caseSensitive: false).firstMatch(t);
  if (meal != null) return 'M${meal.group(1)}';
  final snack = RegExp(r'^Snack\s+(\d+)$', caseSensitive: false).firstMatch(t);
  if (snack != null) return 'S${snack.group(1)}';
  if (t.length <= 5) return t;
  return '${t.substring(0, 4)}…';
}

/// Groups by same week row and weekday, then applies [plannerSlotDisplayLabel].
String plannerSlotDisplayLabelForWeek(
  List<MealPlanSlot> allWeekSlots,
  MealPlanSlot slot,
) {
  final sameDay = allWeekSlots
      .where((s) =>
          s.dayOfWeek == slot.dayOfWeek &&
          _sameCalendarDay(s.weekStart, slot.weekStart))
      .toList()
    ..sort((a, b) => a.slotOrder.compareTo(b.slotOrder));
  return plannerSlotDisplayLabel(sameDay, slot);
}
