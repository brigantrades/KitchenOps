import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/planner/presentation/planner_screen.dart';

void main() {
  testWidgets('recipe-backed slot tap opens cooking route', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => _PlannerCardHarness(
            slot: MealPlanSlot(
              id: 'slot-1',
              weekStart: DateTime(2026, 3, 23),
              dayOfWeek: 1,
              mealLabel: 'Dinner',
              recipeId: 'recipe-1',
              slotOrder: 0,
              assignedUserIds: ['user-1'],
            ),
            recipes: [
              Recipe(
                id: 'recipe-1',
                title: 'Lemon Pasta',
                mealType: MealType.entree,
              ),
            ],
          ),
        ),
        GoRoute(
          path: '/cooking/:recipeId',
          builder: (context, state) => Text(
            'Cooking ${state.pathParameters['recipeId']}',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lemon Pasta'));
    await tester.pumpAndSettle();

    expect(find.text('Cooking recipe-1'), findsOneWidget);
  });

  testWidgets('non-recipe slot shows hint and edit action in menu', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => _PlannerCardHarness(
            slot: MealPlanSlot(
              id: 'slot-2',
              weekStart: DateTime(2026, 3, 23),
              dayOfWeek: 1,
              mealLabel: 'Lunch',
              mealText: 'Leftovers',
              slotOrder: 0,
              assignedUserIds: ['user-1'],
            ),
            recipes: [],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No recipe linked. Use edit to choose one.'), findsOneWidget);
    expect(find.byTooltip('Slot options'), findsOneWidget);
    await tester.tap(find.byTooltip('Slot options'));
    await tester.pumpAndSettle();
    expect(find.text('Change selected meal'), findsOneWidget);

    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });
}

class _PlannerCardHarness extends ConsumerWidget {
  const _PlannerCardHarness({
    required this.slot,
    required this.recipes,
  });

  final MealPlanSlot slot;
  final List<Recipe> recipes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: buildPlannerDaySlotCard(
        context: context,
        ref: ref,
        index: 0,
        slot: slot,
        displaySlots: [slot],
        recipes: recipes,
        groceryItems: const <GroceryItem>[],
        activeMembers: const <HouseholdMember>[
          HouseholdMember(
            householdId: 'h1',
            userId: 'user-1',
            role: HouseholdRole.owner,
            status: HouseholdMemberStatus.active,
            name: 'Test User',
          ),
        ],
        memberNameById: const {'user-1': 'Test User'},
        storageWeek: DateTime(2026, 3, 23),
        storageDow: 1,
        onEditSlotPlan: (context, {required slot, required slotDisplayLabel}) async => null,
        onEditSlotGroceryItems: (context,
                {required slot, recipe, required groceryItems}) async =>
            null,
        onInvalidatePlanner: () {},
        onRemoveMealSlot: (slot, slotsForLabel) async {},
        openRecipeOnTap: true,
      ),
    );
  }
}
