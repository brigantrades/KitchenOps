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
}
