import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_week_mapping.dart';

void main() {
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
