import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';

/// Local calendar date at midnight. Converts [d] with [DateTime.toLocal] first so UTC
/// instants from the network map to the user's weekday/calendar day correctly.
DateTime plannerDateOnly(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Monday (local) of the ISO week containing [date]; time cleared.
DateTime weekStartMondayForDate(DateTime date) {
  final d = plannerDateOnly(date);
  // Use [d.weekday] (the normalized calendar day), not [date.weekday], so the
  // offset matches the same local date as [d] when [date] is a UTC instant.
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

/// Dart `DateTime.weekday` (1=Mon..7=Sun) to planner index 0..6 (Mon..Sun).
int dartWeekdayToStartDay(int weekday) =>
    weekday == DateTime.sunday ? 6 : weekday - 1;

/// Planner [startDay] (0=Mon..6=Sun) to Dart weekday.
int startDayToDartWeekday(int startDay) {
  if (startDay < 0 || startDay > 6) return DateTime.monday;
  if (startDay == 6) return DateTime.sunday;
  return startDay + 1;
}

/// True when [anchor] starts on the weekday required by [pref.startDay].
bool plannerAnchorMatchesPreference(
  DateTime anchor,
  PlannerWindowPreference pref,
) {
  final normalizedAnchor = plannerDateOnly(anchor);
  final expectedWeekday = startDayToDartWeekday(pref.startDay);
  return normalizedAnchor.weekday == expectedWeekday;
}

/// Calendar date of a slot row (`week_start` Monday + `day_of_week` 0..6).
///
/// Uses calendar day rollover ([DateTime] y/m/d arithmetic) instead of
/// [Duration] so adding days cannot cross a DST transition and land on the
/// wrong **date** (e.g. Tuesday Mar 31 mistaken for Apr 1). That bug removed
/// slots from [listPlannerMonthSlots] for March while they still appeared in
/// April, and hid rows for the Mar 31 day sheet.
DateTime calendarDateForSlot(MealPlanSlot slot) {
  final monday = plannerDateOnly(slot.weekStart);
  return DateTime(monday.year, monday.month, monday.day + slot.dayOfWeek);
}

/// True when [slot] belongs to [dayOnly] using DB storage keys (ISO Monday
/// [MealPlanSlot.weekStart] + [MealPlanSlot.dayOfWeek]). Prefer over comparing
/// [calendarDateForSlot] when filtering rows for a tapped day.
bool mealPlanSlotMatchesCalendarDay(MealPlanSlot slot, DateTime dayOnly) {
  final d = plannerDateOnly(dayOnly);
  final storageWeek = weekStartMondayForDate(d);
  final storageDow = dartWeekdayToStartDay(d.weekday);
  return plannerDateOnly(slot.weekStart) == plannerDateOnly(storageWeek) &&
      slot.dayOfWeek == storageDow;
}

/// Anchor = first calendar day of the visible window. Picks the window that
/// contains [today], or if [today] falls outside (e.g. weekend for Mon–Fri),
/// the most recent window that has already ended (so the last work week).
DateTime anchorDateForWindowContaining(
  DateTime today,
  PlannerWindowPreference pref,
) {
  final t = plannerDateOnly(today);
  final dartW = startDayToDartWeekday(pref.startDay);
  for (var i = 0; i <= pref.dayCount + 6; i++) {
    final s = t.subtract(Duration(days: i));
    if (s.weekday != dartW) continue;
    final end = DateTime(s.year, s.month, s.day + pref.dayCount - 1);
    if (!t.isBefore(s) && !t.isAfter(end)) return s;
  }
  for (var i = 0; i < 400; i++) {
    final s = t.subtract(Duration(days: i));
    if (s.weekday != dartW) continue;
    final end = DateTime(s.year, s.month, s.day + pref.dayCount - 1);
    if (t.isAfter(end)) return s;
  }
  return t;
}

/// Each calendar day in the window starting at [anchor] (inclusive).
List<DateTime> calendarDatesForPlannerWindow(
  DateTime anchor,
  PlannerWindowPreference pref,
) {
  final a = plannerDateOnly(anchor);
  return List.generate(
    pref.dayCount,
    (i) => DateTime(a.year, a.month, a.day + i),
  );
}

/// UI index of [dateOnly] in the planner window, or null if outside the range.
int? plannerUiDayIndexForDate(
  DateTime anchor,
  PlannerWindowPreference pref,
  DateTime dateOnly,
) {
  final target = plannerDateOnly(dateOnly);
  final dates = calendarDatesForPlannerWindow(anchor, pref);
  for (var i = 0; i < dates.length; i++) {
    if (plannerDateOnly(dates[i]) == target) return i;
  }
  return null;
}

/// Unique Monday `week_start` buckets needed for DB queries for this window.
Set<DateTime> weekStartMondaysForWindow(
  DateTime anchor,
  PlannerWindowPreference pref,
) {
  final set = <DateTime>{};
  for (final d in calendarDatesForPlannerWindow(anchor, pref)) {
    set.add(weekStartMondayForDate(d));
  }
  return set;
}

/// Local date-only: today, tomorrow, and the day after (for home outlook).
List<DateTime> plannerOutlookDates(DateTime now) {
  final t = plannerDateOnly(now);
  return [t, t.add(const Duration(days: 1)), t.add(const Duration(days: 2))];
}

/// Unique ISO Mondays for `week_start` rows covering [dateOnlyDays].
Set<DateTime> weekStartMondaysForDates(Iterable<DateTime> dateOnlyDays) {
  return dateOnlyDays.map(weekStartMondayForDate).toSet();
}

DateTime calendarDateForPlannerUiDay(
  DateTime anchor,
  int uiDayIndex,
  PlannerWindowPreference pref,
) {
  final a = plannerDateOnly(anchor);
  return DateTime(a.year, a.month, a.day + uiDayIndex);
}

/// Moves the planner anchor by [weekDelta] calendar weeks (±7 days per step). Uses
/// calendar date math (not [Duration]) so the start weekday stays aligned across DST.
DateTime plannerShiftAnchorByCalendarWeeks(DateTime anchor, int weekDelta) {
  final a = plannerDateOnly(anchor);
  return DateTime(a.year, a.month, a.day + weekDelta * 7);
}

DateTime slotStorageWeekStartFromUiDay(
  DateTime anchor,
  int uiDayIndex,
  PlannerWindowPreference pref,
) {
  final cal = calendarDateForPlannerUiDay(anchor, uiDayIndex, pref);
  return weekStartMondayForDate(cal);
}

int slotStorageDayOfWeekFromUiDay(
  DateTime anchor,
  int uiDayIndex,
  PlannerWindowPreference pref,
) {
  final cal = calendarDateForPlannerUiDay(anchor, uiDayIndex, pref);
  return dartWeekdayToStartDay(cal.weekday);
}

int? plannerUiDayIndexForSlot(
  MealPlanSlot slot,
  DateTime anchor,
  PlannerWindowPreference pref,
) {
  final slotDate = plannerDateOnly(calendarDateForSlot(slot));
  final dates = calendarDatesForPlannerWindow(anchor, pref);
  for (var i = 0; i < dates.length; i++) {
    if (plannerDateOnly(dates[i]) == slotDate) return i;
  }
  return null;
}

bool slotBelongsToPlannerWindow(
  MealPlanSlot slot,
  DateTime anchor,
  PlannerWindowPreference pref,
) {
  return plannerUiDayIndexForSlot(slot, anchor, pref) != null;
}

/// Short weekday range for settings preview, e.g. `Mon–Fri`, `Mon–Mon` (Mon + 8 days).
String plannerWindowRangeLabel(int startDay, int dayCount) {
  const abbrev = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (dayCount < 1 || startDay < 0 || startDay > 6) return '';
  if (dayCount == 1) return abbrev[startDay];
  final endIdx = (startDay + dayCount - 1) % 7;
  return '${abbrev[startDay]}–${abbrev[endIdx]}';
}

/// Normalized first day of the calendar month containing [anyDateInMonth].
DateTime firstDayOfPlannerMonth(DateTime anyDateInMonth) {
  final d = plannerDateOnly(anyDateInMonth);
  return DateTime(d.year, d.month, 1);
}

/// Unique ISO Mondays for `week_start` rows that can cover any day in that month.
Set<DateTime> weekStartMondaysForCalendarMonth(DateTime monthStart) {
  final first = firstDayOfPlannerMonth(monthStart);
  final last = DateTime(first.year, first.month + 1, 0);
  final set = <DateTime>{};
  for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
    set.add(weekStartMondayForDate(d));
  }
  return set;
}

/// Each calendar date in the month (local), date-only.
Set<DateTime> plannerCalendarDatesInMonth(DateTime monthStart) {
  final first = firstDayOfPlannerMonth(monthStart);
  final last = DateTime(first.year, first.month + 1, 0);
  final set = <DateTime>{};
  for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
    set.add(plannerDateOnly(d));
  }
  return set;
}

/// Uppercase magazine-style range, e.g. `OCTOBER 14 — 20` or `OCT 31 — NOV 2`.
String plannerMagazineWindowTitle(
  DateTime anchor,
  PlannerWindowPreference pref,
) {
  final dates = calendarDatesForPlannerWindow(anchor, pref);
  if (dates.isEmpty) return '';
  final first = dates.first;
  final last = dates.last;
  if (first.year == last.year && first.month == last.month) {
    final month = DateFormat('MMMM').format(first).toUpperCase();
    return '$month ${first.day} — ${last.day}';
  }
  final a = DateFormat('MMM d').format(first).toUpperCase();
  final b = DateFormat('MMM d').format(last).toUpperCase();
  return '$a — $b';
}

/// Collapses duplicate [MealPlanSlot] rows for the same logical slot
/// `(week_start local date, day_of_week, slot_order)` — the same key as
/// `meal_plan_slots_household_week_day_order_uidx` (different ids).
///
/// Uses storage keys instead of [calendarDateForSlot] so two rows that
/// disagree on derived calendar math still merge.
///
/// Prefers the row with planned content, then a recipe-backed row, then stable id order.
List<MealPlanSlot> dedupeMealPlannerSlotsByCalendarDayAndSlotOrder(
  Iterable<MealPlanSlot> slots,
) {
  final byKey = <String, MealPlanSlot>{};
  for (final s in slots) {
    final key = _mealPlanSlotDedupeKey(s);
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = s;
    } else {
      byKey[key] = _preferMealPlanSlotWhenDuplicate(existing, s);
    }
  }
  final out = byKey.values.toList();
  out.sort((a, b) {
    final da = plannerDateOnly(calendarDateForSlot(a));
    final db = plannerDateOnly(calendarDateForSlot(b));
    final c = da.compareTo(db);
    if (c != 0) return c;
    return a.slotOrder.compareTo(b.slotOrder);
  });
  return out;
}

String _mealPlanSlotDedupeKey(MealPlanSlot s) {
  final ws = plannerDateOnly(s.weekStart);
  return '${ws.year}|${ws.month}|${ws.day}|${s.dayOfWeek}|${s.slotOrder}';
}

MealPlanSlot _preferMealPlanSlotWhenDuplicate(MealPlanSlot a, MealPlanSlot b) {
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
