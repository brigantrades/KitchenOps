import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_week_mapping.dart';

void main() {
  group('PlannerWindowPreference.navigationStepDays', () {
    test('is always one calendar week so anchor weekday does not drift', () {
      const pref7 =
          PlannerWindowPreference(startDay: 1, dayCount: 7); // Tue–Mon
      const pref8 =
          PlannerWindowPreference(startDay: 1, dayCount: 8); // Tue–Tue span
      expect(pref7.navigationStepDays, 7);
      expect(pref8.navigationStepDays, 7);
    });
  });

  group('plannerShiftAnchorByCalendarWeeks', () {
    test('from Tuesday advances to next Tuesday', () {
      final tue = DateTime(2026, 3, 24);
      expect(tue.weekday, DateTime.tuesday);
      final next = plannerShiftAnchorByCalendarWeeks(tue, 1);
      expect(next.weekday, DateTime.tuesday);
      expect(next.day, 31);
    });
  });

  group('plannerDateOnly', () {
    test('uses local calendar components for UTC instants', () {
      final utc = DateTime.utc(2026, 6, 15, 14, 30);
      final p = plannerDateOnly(utc);
      final l = utc.toLocal();
      expect(p.year, l.year);
      expect(p.month, l.month);
      expect(p.day, l.day);
      expect(p.isUtc, isFalse);
    });
  });

  group('MealPlanSlot week_start JSON', () {
    test('calendarDateForSlot matches local day when API sends UTC midnight', () {
      final slot = MealPlanSlot.fromJson({
        'id': 'test-slot',
        'week_start': '2026-03-30T00:00:00+00:00',
        'day_of_week': 1,
        'meal_type': 'meal',
        'slot_order': 0,
      });
      expect(plannerDateOnly(calendarDateForSlot(slot)), DateTime(2026, 3, 31));
    });

    test('calendarDateForSlot uses calendar days (Mar 30 week Tue/Fri)', () {
      final mon = DateTime(2026, 3, 30);
      final tue = MealPlanSlot(
        id: 'a',
        weekStart: mon,
        dayOfWeek: 1,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      final fri = MealPlanSlot(
        id: 'b',
        weekStart: mon,
        dayOfWeek: 4,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      expect(plannerDateOnly(calendarDateForSlot(tue)), DateTime(2026, 3, 31));
      expect(plannerDateOnly(calendarDateForSlot(fri)), DateTime(2026, 4, 3));
    });

    test('mealPlanSlotMatchesCalendarDay aligns with tapped day', () {
      final mon = DateTime(2026, 3, 30);
      final tue = MealPlanSlot(
        id: 'a',
        weekStart: mon,
        dayOfWeek: 1,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      expect(mealPlanSlotMatchesCalendarDay(tue, DateTime(2026, 3, 31)), isTrue);
      expect(mealPlanSlotMatchesCalendarDay(tue, DateTime(2026, 4, 3)), isFalse);
    });
  });

  group('plannerAnchorMatchesPreference', () {
    test('returns false when anchor weekday does not match preference', () {
      const pref = PlannerWindowPreference(startDay: 1, dayCount: 7); // Tuesday
      final mondayAnchor = DateTime(2026, 3, 23); // Monday

      expect(plannerAnchorMatchesPreference(mondayAnchor, pref), isFalse);
    });

    test('returns true when anchor weekday matches preference', () {
      const pref = PlannerWindowPreference(startDay: 1, dayCount: 7); // Tuesday
      final tuesdayAnchor = DateTime(2026, 3, 24); // Tuesday

      expect(plannerAnchorMatchesPreference(tuesdayAnchor, pref), isTrue);
    });
  });

  group('plannerUiDayIndexForDate', () {
    test('returns index for date inside window', () {
      const pref = PlannerWindowPreference(startDay: 0, dayCount: 5);
      final anchor = DateTime(2026, 4, 6); // Monday
      expect(
        plannerUiDayIndexForDate(anchor, pref, DateTime(2026, 4, 8)),
        2,
      );
    });

    test('returns null when date outside window', () {
      const pref = PlannerWindowPreference(startDay: 0, dayCount: 5);
      final anchor = DateTime(2026, 4, 6);
      expect(
        plannerUiDayIndexForDate(anchor, pref, DateTime(2026, 4, 5)),
        isNull,
      );
    });
  });

  group('dedupeMealPlannerSlotsByCalendarDayAndSlotOrder', () {
    test('merges duplicate slot positions and prefers planned content', () {
      final mon = DateTime(2026, 3, 30);
      final withText = MealPlanSlot(
        id: 'a',
        weekStart: mon,
        dayOfWeek: 1,
        mealLabel: 'meal',
        slotOrder: 0,
        mealText: 'Leftover Roast',
      );
      final empty = MealPlanSlot(
        id: 'b',
        weekStart: mon,
        dayOfWeek: 1,
        mealLabel: 'meal',
        slotOrder: 0,
      );
      final out = dedupeMealPlannerSlotsByCalendarDayAndSlotOrder([
        withText,
        empty,
      ]);
      expect(out.length, 1);
      expect(out.single.id, 'a');
    });
  });
}
