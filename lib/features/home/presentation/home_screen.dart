import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:plateplan/core/ui/action_pill.dart';
import 'package:plateplan/core/ui/app_surface.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/core/models/app_models.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planner = ref.watch(plannerSlotsProvider);
    final grocery = ref.watch(groceryItemsProvider);
    final recipes = ref.watch(recipesProvider);
    final pendingInvites = ref.watch(pendingHouseholdInvitesProvider);
    final pendingInviteCount = pendingInvites.valueOrNull?.length ?? 0;
    final plannedCount = planner.valueOrNull
            ?.where((slot) => slot.dayOfWeek == DateTime.now().weekday - 1)
            .length ??
        0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leckerly'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
            icon: pendingInviteCount > 0
                ? Badge(
                    label: Text('$pendingInviteCount'),
                    child: const Icon(Icons.person_outline),
                  )
                : const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: AppSurface(
        child: Column(
          children: [
            _HomeHeader(plannedCount: plannedCount),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Today',
                    icon: Icons.calendar_today_rounded,
                    value: planner.when(
                      data: (slots) =>
                          '${slots.where((s) => s.dayOfWeek == DateTime.now().weekday - 1).length} meals',
                      loading: () => '...',
                      error: (e, _) => 'Error',
                    ),
                    onTap: () {
                      final slots = planner.valueOrNull;
                      if (slots == null) return;
                      final todaySlots = slots
                          .where(
                              (s) => s.dayOfWeek == DateTime.now().weekday - 1)
                          .toList();
                      if (todaySlots.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No meals planned for today yet.'),
                          ),
                        );
                        return;
                      }
                      final allRecipes =
                          recipes.valueOrNull ?? const <Recipe>[];
                      _showTodayMealsPreview(
                        context,
                        slots: todaySlots,
                        recipes: allRecipes,
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    title: 'Grocery',
                    icon: Icons.shopping_basket_rounded,
                    value: grocery.when(
                      data: (items) => '${items.length} items',
                      loading: () => '...',
                      error: (e, _) => 'Error',
                    ),
                    onTap: () => context.go('/grocery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Quick jump',
              subtitle: 'Everything from planning to discovery in one tap.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionPill(
                    label: 'Recipes',
                    icon: Icons.menu_book_rounded,
                    onTap: () => context.go('/recipes'),
                  ),
                  ActionPill(
                    label: 'Planner',
                    icon: Icons.calendar_month_rounded,
                    onTap: () => context.go('/planner'),
                  ),
                  ActionPill(
                    label: 'Grocery',
                    icon: Icons.shopping_cart_checkout_rounded,
                    onTap: () => context.go('/grocery'),
                  ),
                  ActionPill(
                    label: 'Discover',
                    icon: Icons.auto_awesome_rounded,
                    onTap: () => context.go('/discover'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTodayMealsPreview(
    BuildContext context, {
    required List<MealPlanSlot> slots,
    required List<Recipe> recipes,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return BrandedSheetScaffold(
          title: 'Today\'s Meals',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              ...slots.map((slot) {
                final recipe = recipes.firstWhereOrNull(
                  (r) => r.id == slot.recipeId,
                );
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.45),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant_menu_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_mealLabelDisplay(slot.mealLabel)),
                            Text(
                              recipe?.title ?? 'No recipe assigned yet',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => context.go('/planner'),
                  child: const Text('Open Planner'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.plannedCount});

  final int plannedCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final weekday = switch (now.weekday) {
      DateTime.monday => 'Monday',
      DateTime.tuesday => 'Tuesday',
      DateTime.wednesday => 'Wednesday',
      DateTime.thursday => 'Thursday',
      DateTime.friday => 'Friday',
      DateTime.saturday => 'Saturday',
      DateTime.sunday => 'Sunday',
      _ => 'Today',
    };
    final statusLine = plannedCount == 0
        ? 'No meals planned yet. Start one for tonight.'
        : '$plannedCount meal slots already planned.';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: AppRadius.md,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.tertiaryContainer,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$weekday focus',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Home',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            statusLine,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.icon,
    required this.value,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

String _mealLabelDisplay(String mealLabel) {
  if (mealLabel.isEmpty) return 'Meal';
  final lower = mealLabel.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}
