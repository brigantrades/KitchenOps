import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plateplan/features/planner/presentation/planner_magazine_day_card.dart';

void main() {
  testWidgets(
    'empty planner day card wrapped in opaque GestureDetector receives taps',
    (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 200,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => tapped = true,
                  child: Material(
                    color: Colors.transparent,
                    child: PlannerMagazineDayCard(
                      date: DateTime(2026, 3, 31),
                      isToday: false,
                      daySlots: const [],
                      recipes: const [],
                      maxVisibleSlots: 5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Tap the lower area where only the empty-slot region draws little ink;
      // the parent must still hit-test the full tile (regression for Planner grid).
      await tester.tapAt(const Offset(150, 160));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    },
  );
}
