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

/// Strips invisible chars and wrapping quotes so API/DB values classify consistently.
String _normalizePlannerMealLabelForKind(String mealLabel) {
  var s = mealLabel.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  s = s.replaceAll('\u00a0', ' ').trim();
  if (s.length >= 2) {
    final first = s.codeUnitAt(0);
    final last = s.codeUnitAt(s.length - 1);
    if ((first == 0x22 && last == 0x22) || (first == 0x27 && last == 0x27)) {
      s = s.substring(1, s.length - 1).trim();
    }
  }
  return s;
}

/// Classifies [meal_type] from the database.
///
/// Trims/normalizes so values like `'meal '` or quoted literals match [PlannerSlotKind.meal].
PlannerSlotKind plannerSlotKind(String mealLabel) {
  final lower = _normalizePlannerMealLabelForKind(mealLabel).toLowerCase();
  if (lower.isEmpty) return PlannerSlotKind.meal;
  if (lower == 'null' || lower == 'undefined') return PlannerSlotKind.meal;
  if (lower == 'snack') return PlannerSlotKind.snack;
  // Legacy rows where meal_type was stored as "Meal 1" / "Snack 2"; UI ordinals are by slot.
  if (RegExp(r'^meal\s*\d+$').hasMatch(lower)) return PlannerSlotKind.meal;
  if (RegExp(r'^snack\s*\d+$').hasMatch(lower)) return PlannerSlotKind.snack;
  if (_isMealKind(lower)) return PlannerSlotKind.meal;
  return PlannerSlotKind.custom;
}

bool _sameCalendarDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Title segment for [showPlannerRecipePicker] when creating a new slot (no row
/// index yet). For generic meal/snack rows prefer [plannerNewSlotRecipePickerDisplayLabel]
/// so the picker matches post-create labels (`Meal 1`, `Snack 2`, etc.).
String plannerNewSlotRecipePickerTitleLabel(String mealLabel) {
  final lower = mealLabel.trim().toLowerCase();
  if (lower == 'meal') return 'Meal';
  if (lower == 'snack') return 'Snack';
  final raw = mealLabel.trim();
  if (raw.isEmpty) return 'Meal';
  final l = raw.toLowerCase();
  return l[0].toUpperCase() + l.substring(1);
}

/// Ordinal for the next `Meal N` / `Snack N` for [mealLabelChosen], using the same
/// kind rules as [plannerSlotDisplayLabel]. Returns `0` for custom labels.
int nextNewSlotDisplayOrdinal(
  List<MealPlanSlot> daySlotsSorted,
  String mealLabelChosen,
) {
  final day = dedupeMealPlanSlotsByIdPreferPlanned(daySlotsSorted);
  final k = plannerSlotKind(mealLabelChosen);
  if (k == PlannerSlotKind.custom) return 0;
  if (k == PlannerSlotKind.snack) {
    return day
            .where((s) => plannerSlotKind(s.mealLabel) == PlannerSlotKind.snack)
            .length +
        1;
  }
  return day
          .where((s) => plannerSlotKind(s.mealLabel) == PlannerSlotKind.meal)
          .length +
      1;
}

/// Picker title when adding a slot: `Meal 3` / `Snack 2` aligned with existing day rows.
String plannerNewSlotRecipePickerDisplayLabel(String mealLabel, int ordinal) {
  final lower = mealLabel.trim().toLowerCase();
  if (lower == 'meal' && ordinal > 0) return 'Meal $ordinal';
  if (lower == 'snack' && ordinal > 0) return 'Snack $ordinal';
  return plannerNewSlotRecipePickerTitleLabel(mealLabel);
}

/// Collapses duplicate [MealPlanSlot.id] entries (stale cache / merge quirks).
/// Prefers the row with planned content, then recipe-backed, then stable id.
List<MealPlanSlot> dedupeMealPlanSlotsByIdPreferPlanned(
  List<MealPlanSlot> slots,
) {
  final byId = <String, MealPlanSlot>{};
  for (final s in slots) {
    final existing = byId[s.id];
    if (existing == null) {
      byId[s.id] = s;
    } else {
      byId[s.id] = _preferMealPlanSlotByPlannedContent(existing, s);
    }
  }
  final out = byId.values.toList();
  out.sort((a, b) => a.slotOrder.compareTo(b.slotOrder));
  return out;
}

MealPlanSlot _preferMealPlanSlotByPlannedContent(MealPlanSlot a, MealPlanSlot b) {
  if (a.hasPlannedContent != b.hasPlannedContent) {
    return a.hasPlannedContent ? a : b;
  }
  final aRecipe = (a.recipeId?.trim().isNotEmpty ?? false);
  final bRecipe = (b.recipeId?.trim().isNotEmpty ?? false);
  if (aRecipe != bRecipe) {
    return aRecipe ? a : b;
  }
  return a.id.compareTo(b.id) <= 0 ? a : b;
}

/// Slots for one calendar day of the plan, sorted by [MealPlanSlot.slotOrder].
///
/// [daySlotsSorted] may contain duplicate ids; numbering uses id-deduped list so
/// two rows with the same id never both read as "Meal 1".
String plannerSlotDisplayLabel(
  List<MealPlanSlot> daySlotsSorted,
  MealPlanSlot slot,
) {
  final day = dedupeMealPlanSlotsByIdPreferPlanned(daySlotsSorted);
  final kind = plannerSlotKind(slot.mealLabel);
  if (kind == PlannerSlotKind.custom) {
    final raw = slot.mealLabel.trim();
    if (raw.isEmpty) return 'Meal';
    final lower = raw.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  var mealIndex = 0;
  var snackIndex = 0;
  for (final s in day) {
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
  final sameDay = dedupeMealPlanSlotsByIdPreferPlanned(
    allWeekSlots
        .where((s) =>
            s.dayOfWeek == slot.dayOfWeek &&
            _sameCalendarDay(s.weekStart, slot.weekStart))
        .toList()
      ..sort((a, b) => a.slotOrder.compareTo(b.slotOrder)),
  );
  return plannerSlotDisplayLabel(sameDay, slot);
}
