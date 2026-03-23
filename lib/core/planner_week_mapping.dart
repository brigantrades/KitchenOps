import 'package:plateplan/core/models/app_models.dart';

DateTime plannerDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday (local) of the ISO week containing [date]; time cleared.
DateTime weekStartMondayForDate(DateTime date) {
  final d = plannerDateOnly(date);
  return d.subtract(Duration(days: date.weekday - DateTime.monday));
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

/// Calendar date of a slot row (`week_start` Monday + `day_of_week` 0..6).
DateTime calendarDateForSlot(MealPlanSlot slot) {
  return plannerDateOnly(slot.weekStart).add(Duration(days: slot.dayOfWeek));
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
    final end = s.add(Duration(days: pref.dayCount - 1));
    if (!t.isBefore(s) && !t.isAfter(end)) return s;
  }
  for (var i = 0; i < 400; i++) {
    final s = t.subtract(Duration(days: i));
    if (s.weekday != dartW) continue;
    final end = s.add(Duration(days: pref.dayCount - 1));
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
    (i) => a.add(Duration(days: i)),
  );
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

DateTime calendarDateForPlannerUiDay(
  DateTime anchor,
  int uiDayIndex,
  PlannerWindowPreference pref,
) {
  return plannerDateOnly(anchor).add(Duration(days: uiDayIndex));
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
