import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/ui/action_pill.dart';
import 'package:plateplan/core/ui/hero_panel.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final selectedPlannerDayProvider = StateProvider<int>((ref) {
  final current = DateTime.now().weekday - 1;
  if (current < 0) return 0;
  if (current > 6) return 6;
  return current;
});

class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({super.key});

  String _weekLabel(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final sameMonth = weekStart.month == weekEnd.month;
    if (sameMonth) {
      return '${DateFormat('MMM').format(weekStart)} ${weekStart.day} - ${weekEnd.day}';
    }
    return '${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d').format(weekEnd)}';
  }

  Future<Recipe?> _pickRecipeForMeal(
    BuildContext context, {
    required String mealLabel,
    required List<Recipe> recipes,
  }) {
    final normalized = mealLabel.toLowerCase();
    final matching =
        recipes.where((r) => r.mealType.name == normalized).toList();
    final options = matching.isNotEmpty ? matching : recipes;
    if (options.isEmpty) return Future.value(null);
    var segmentIndex = 0;

    return showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final resultsHeight =
              (MediaQuery.of(context).size.height * 0.42).clamp(240.0, 420.0);
          final visible = switch (segmentIndex) {
            1 => options.where((r) => r.isToTry).toList(),
            _ => options.where((r) => r.isFavorite).toList(),
          };
          return BrandedSheetScaffold(
            title: 'Select ${_mealLabelDisplay(mealLabel)} Recipe',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (matching.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'No exact meal-tag matches, showing all recipes.',
                      ),
                    ),
                  ),
                SegmentedPills(
                  labels: const ['Favorites', 'To Try'],
                  selectedIndex: segmentIndex,
                  onSelect: (idx) => setModalState(() => segmentIndex = idx),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: visible.isEmpty
                        ? null
                        : () {
                            final picked =
                                visible[Random().nextInt(visible.length)];
                            Navigator.of(context).pop(picked);
                          },
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Select for me'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: resultsHeight.toDouble(),
                  child: visible.isEmpty
                      ? const Center(
                          child: Text('No recipes in this tab yet.'),
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final recipe = visible[index];
                            return InkWell(
                              onTap: () => Navigator.of(context).pop(recipe),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.4),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.restaurant_rounded),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(recipe.title),
                                          Text(
                                            '${_mealTypeLabel(recipe.mealType)} • Serves ${recipe.servings}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<String?> _pickNewMealLabel(BuildContext context) async {
    final customCtrl = TextEditingController();
    String picked = 'snack';
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add Meal Slot',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionPill(
                      label: 'Snack',
                      selected: picked == 'snack',
                      onTap: () => setModalState(() => picked = 'snack'),
                    ),
                    ActionPill(
                      label: 'Custom',
                      selected: picked == 'custom',
                      onTap: () => setModalState(() => picked = 'custom'),
                    ),
                  ],
                ),
                if (picked == 'custom') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: customCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Custom meal label'),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          if (picked == 'custom') {
                            final raw = customCtrl.text.trim();
                            if (raw.isEmpty) return;
                            Navigator.of(context).pop(raw.toLowerCase());
                            return;
                          }
                          Navigator.of(context).pop('snack');
                        },
                        child: const Text('Add'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    customCtrl.dispose();
    return result;
  }

  Future<List<_IngredientSelectionDraft>?> _pickIngredientsForGrocery(
    BuildContext context, {
    required Recipe recipe,
    required int servingsUsed,
  }) {
    final drafts = recipe.ingredients
        .map(
          (ingredient) => _IngredientSelectionDraft(
            ingredient: ingredient,
            selected: true,
            quantity: 1,
          ),
        )
        .toList();

    if (drafts.isEmpty) return Future.value(const []);

    return showModalBottomSheet<List<_IngredientSelectionDraft>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Add ingredients to Grocery',
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: drafts.length,
                      itemBuilder: (context, index) {
                        final draft = drafts[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: const Color(0xFFF8FCFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.12),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: draft.selected,
                                  onChanged: (value) => setModalState(
                                      () => draft.selected = value ?? false),
                                ),
                                Expanded(
                                  child: Text(
                                    draft.ingredient.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF5FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setModalState(() {
                                            if (draft.quantity > 1) {
                                              draft.quantity -= 1;
                                            }
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                      ),
                                      Text(
                                        '${draft.quantity}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setModalState(() {
                                            draft.quantity += 1;
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final selected =
                                drafts.where((d) => d.selected).toList();
                            Navigator.of(context).pop(selected);
                          },
                          child: const Text('Add selected'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<List<_GroceryEditDraft>?> _editRecipeGroceryItems(
    BuildContext context, {
    required Recipe recipe,
    required List<GroceryItem> groceryItems,
  }) {
    final related =
        groceryItems.where((item) => item.fromRecipeId == recipe.id).toList();
    if (related.isEmpty) return Future.value(const []);

    final drafts = related
        .map(
          (item) => _GroceryEditDraft(
            item: item,
            quantity: int.tryParse(item.quantity ?? '') ?? 1,
            removed: false,
          ),
        )
        .toList();

    return showModalBottomSheet<List<_GroceryEditDraft>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit Grocery Items',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: drafts.length,
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Opacity(
                          opacity: draft.removed ? 0.45 : 1,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    draft.item.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF5FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: draft.removed
                                            ? null
                                            : () {
                                                setModalState(() {
                                                  if (draft.quantity > 1) {
                                                    draft.quantity -= 1;
                                                  }
                                                });
                                              },
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                      ),
                                      Text(
                                        '${draft.quantity}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: draft.removed
                                            ? null
                                            : () {
                                                setModalState(() {
                                                  draft.quantity += 1;
                                                });
                                              },
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: draft.removed
                                      ? 'Undo remove'
                                      : 'Remove item',
                                  onPressed: () => setModalState(
                                      () => draft.removed = !draft.removed),
                                  icon: Icon(
                                    draft.removed
                                        ? Icons.undo_rounded
                                        : Icons.delete_outline,
                                    color: draft.removed
                                        ? Colors.blueGrey
                                        : Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(drafts),
                        child: const Text('Save changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(weekStartProvider);
    final selectedDay = ref.watch(selectedPlannerDayProvider);
    final slotsAsync = ref.watch(plannerSlotsProvider);
    final recipesAsync = ref.watch(recipesProvider);
    final groceryItems =
        ref.watch(groceryItemsProvider).valueOrNull ?? const [];
    final groceryRecipeIds = groceryItems
        .where((item) => item.fromRecipeId != null)
        .map((item) => item.fromRecipeId!)
        .toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Planner')),
      body: slotsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (slots) => recipesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading recipes: $e')),
          data: (recipes) {
            final nutrition = slots.fold<Nutrition>(
              const Nutrition(),
              (sum, slot) =>
                  sum +
                  (recipes
                          .firstWhereOrNull((r) => r.id == slot.recipeId)
                          ?.nutrition ??
                      const Nutrition()),
            );
            final selectedDate = weekStart.add(Duration(days: selectedDay));
            final daySlots = slots
                .where((s) => s.dayOfWeek == selectedDay)
                .sorted((a, b) => a.slotOrder.compareTo(b.slotOrder))
                .toList();
            final dayTotals = <int, int>{
              for (var day = 0; day < 7; day++) day: 0,
            };
            final dayAssigned = <int, int>{
              for (var day = 0; day < 7; day++) day: 0,
            };
            for (final slot in slots) {
              dayTotals[slot.dayOfWeek] = (dayTotals[slot.dayOfWeek] ?? 0) + 1;
              if (slot.recipeId != null) {
                dayAssigned[slot.dayOfWeek] =
                    (dayAssigned[slot.dayOfWeek] ?? 0) + 1;
              }
            }

            Future<void> removeMealSlot(MealPlanSlot slot) async {
              final confirmed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text('Delete meal slot?'),
                  content: Text(
                    'Delete ${_mealLabelDisplay(slot.mealLabel)} from ${DateFormat('EEEE').format(selectedDate)}? This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) {
                return;
              }
              try {
                await ref.read(plannerRepositoryProvider).removeSlot(
                      slotId: slot.id,
                    );
                ref.invalidate(plannerSlotsProvider);
              } on PostgrestException catch (error) {
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('Could not remove meal slot: ${error.message}'),
                  ),
                );
              }
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
              children: [
                HeroPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Week of ${_weekLabel(weekStart)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Previous week',
                            onPressed: () {
                              ref.read(weekStartProvider.notifier).state =
                                  weekStart.subtract(const Duration(days: 7));
                              ref.invalidate(plannerSlotsProvider);
                            },
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          IconButton(
                            tooltip: 'Next week',
                            onPressed: () {
                              ref.read(weekStartProvider.notifier).state =
                                  weekStart.add(const Duration(days: 7));
                              ref.invalidate(plannerSlotsProvider);
                            },
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                          'Pick a day, drag to reorder meals, and tap a meal to assign a recipe.'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Weekly cadence',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (dayIndex) {
                      final day = weekStart.add(Duration(days: dayIndex));
                      final total = dayTotals[dayIndex] ?? 0;
                      final assigned = dayAssigned[dayIndex] ?? 0;
                      return ActionPill(
                        label:
                            '${DateFormat('EEE d').format(day)}  $assigned/$total',
                        selected: selectedDay == dayIndex,
                        onTap: () => ref
                            .read(selectedPlannerDayProvider.notifier)
                            .state = dayIndex,
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SectionCard(
                        child: Row(
                          children: [
                            const Icon(Icons.local_fire_department_rounded),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Calories'),
                                Text('${nutrition.calories} kcal'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SectionCard(
                        child: Row(
                          children: [
                            const Icon(Icons.fitness_center_rounded),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Protein'),
                                Text(
                                    '${nutrition.protein.toStringAsFixed(0)}g'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEEE, MMM d').format(selectedDate),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ReorderableListView.builder(
                          key: ValueKey('selected-day-$selectedDay'),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          buildDefaultDragHandles: false,
                          itemCount: daySlots.length,
                          onReorder: (oldIndex, newIndex) async {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final reordered = [...daySlots];
                            final moved = reordered.removeAt(oldIndex);
                            reordered.insert(newIndex, moved);
                            final repo = ref.read(plannerRepositoryProvider);
                            try {
                              await repo.reorderSlots(reordered);
                              ref.invalidate(plannerSlotsProvider);
                            } on PostgrestException catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Could not reorder slots: ${error.message}')),
                              );
                            }
                          },
                          itemBuilder: (context, i) {
                            final slot = daySlots[i];
                            final recipe = slot.recipeId == null
                                ? null
                                : recipes.firstWhereOrNull(
                                    (r) => r.id == slot.recipeId);
                            final isAlreadyAdded = recipe != null &&
                                groceryRecipeIds.contains(recipe.id);
                            final scheme = Theme.of(context).colorScheme;

                            return Container(
                              key: ValueKey(slot.id),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1A000000),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(24),
                                onTap: () async {
                                  if (recipes.isEmpty) return;
                                  final selected = await _pickRecipeForMeal(
                                    context,
                                    mealLabel: slot.mealLabel,
                                    recipes: recipes,
                                  );
                                  if (selected == null) return;
                                  final user = ref.read(currentUserProvider);
                                  if (user == null) return;
                                  try {
                                    await ref
                                        .read(plannerRepositoryProvider)
                                        .assignSlot(
                                          userId: user.id,
                                          weekStart: weekStart,
                                          dayOfWeek: selectedDay,
                                          mealLabel: slot.mealLabel,
                                          slotOrder: slot.slotOrder,
                                          slotId: slot.id,
                                          recipeId: selected.id,
                                        );
                                    ref.invalidate(plannerSlotsProvider);
                                  } on PostgrestException catch (error) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Could not assign recipe: ${error.message}')),
                                    );
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: i,
                                        child: const Icon(
                                            Icons.drag_indicator_rounded),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _mealLabelDisplay(slot.mealLabel),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                            Text(
                                              recipe?.title ??
                                                  'Tap to assign recipe',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                      recipe == null
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Remove meal slot',
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                  ),
                                                  onPressed: () =>
                                                      removeMealSlot(slot),
                                                ),
                                              ],
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Unassign recipe',
                                                  icon: const Icon(Icons
                                                      .remove_circle_outline),
                                                  onPressed: () async {
                                                    try {
                                                      await ref
                                                          .read(
                                                              plannerRepositoryProvider)
                                                          .unassignSlot(
                                                              slotId: slot.id);
                                                      ref.invalidate(
                                                          plannerSlotsProvider);
                                                    } on PostgrestException catch (error) {
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Could not unassign recipe: ${error.message}'),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                ),
                                                isAlreadyAdded
                                                    ? IconButton(
                                                        tooltip:
                                                            'Edit grocery items',
                                                        icon: const Icon(
                                                          Icons
                                                              .check_circle_rounded,
                                                          color:
                                                              Color(0xFF4ECDC4),
                                                        ),
                                                        onPressed: () async {
                                                          final edits =
                                                              await _editRecipeGroceryItems(
                                                            context,
                                                            recipe: recipe,
                                                            groceryItems:
                                                                groceryItems,
                                                          );
                                                          if (edits == null ||
                                                              edits.isEmpty) {
                                                            return;
                                                          }
                                                          try {
                                                            for (final edit
                                                                in edits) {
                                                              if (edit
                                                                  .removed) {
                                                                await ref
                                                                    .read(
                                                                        groceryRepositoryProvider)
                                                                    .removeItem(
                                                                        edit.item
                                                                            .id);
                                                              } else {
                                                                await ref
                                                                    .read(
                                                                        groceryRepositoryProvider)
                                                                    .updateItemQuantity(
                                                                      edit.item
                                                                          .id,
                                                                      edit.quantity
                                                                          .toString(),
                                                                    );
                                                              }
                                                            }
                                                            ref.invalidate(
                                                                groceryItemsProvider);
                                                          } on PostgrestException catch (error) {
                                                            if (!context
                                                                .mounted) {
                                                              return;
                                                            }
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              SnackBar(
                                                                content: Text(
                                                                  'Could not update grocery items: ${error.message}',
                                                                ),
                                                              ),
                                                            );
                                                          }
                                                        },
                                                      )
                                                    : IconButton(
                                                        tooltip:
                                                            'Add ingredients to Grocery',
                                                        icon: const Icon(Icons
                                                            .add_shopping_cart_rounded),
                                                        onPressed: () async {
                                                          final user = ref.read(
                                                              currentUserProvider);
                                                          if (user == null) {
                                                            return;
                                                          }
                                                          final picks =
                                                              await _pickIngredientsForGrocery(
                                                            context,
                                                            recipe: recipe,
                                                            servingsUsed: slot
                                                                .servingsUsed,
                                                          );
                                                          if (picks == null ||
                                                              picks.isEmpty) {
                                                            return;
                                                          }
                                                          try {
                                                            for (final pick
                                                                in picks) {
                                                              await ref
                                                                  .read(
                                                                      groceryRepositoryProvider)
                                                                  .addItem(
                                                                    userId:
                                                                        user.id,
                                                                    name: pick
                                                                        .ingredient
                                                                        .name,
                                                                    quantity: pick
                                                                        .quantity
                                                                        .toString(),
                                                                    unit: null,
                                                                    category: pick
                                                                        .ingredient
                                                                        .category,
                                                                    fromRecipeId:
                                                                        recipe
                                                                            .id,
                                                                  );
                                                            }
                                                            ref.invalidate(
                                                                groceryItemsProvider);
                                                          } on PostgrestException catch (error) {
                                                            if (!context
                                                                .mounted) {
                                                              return;
                                                            }
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              SnackBar(
                                                                content: Text(
                                                                    'Could not add to grocery: ${error.message}'),
                                                              ),
                                                            );
                                                          }
                                                        },
                                                      ),
                                                IconButton(
                                                  tooltip: 'Remove meal slot',
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                  ),
                                                  onPressed: () =>
                                                      removeMealSlot(slot),
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final label = await _pickNewMealLabel(context);
                            if (label == null || label.trim().isEmpty) return;
                            final user = ref.read(currentUserProvider);
                            if (user == null) return;
                            try {
                              final nextOrder = await ref
                                  .read(plannerRepositoryProvider)
                                  .nextSlotOrder(
                                    userId: user.id,
                                    weekStart: weekStart,
                                    dayOfWeek: selectedDay,
                                  );
                              await ref.read(plannerRepositoryProvider).addSlot(
                                    userId: user.id,
                                    weekStart: weekStart,
                                    dayOfWeek: selectedDay,
                                    mealLabel: label,
                                    slotOrder: nextOrder,
                                  );
                              ref.invalidate(plannerSlotsProvider);
                            } on PostgrestException catch (error) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Could not add meal slot: ${error.message}')),
                              );
                            }
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Add meal'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _mealTypeLabel(MealType mealType) => switch (mealType) {
      MealType.breakfast => 'Breakfast',
      MealType.lunch => 'Lunch',
      MealType.dinner => 'Dinner',
      MealType.snack => 'Snack',
      MealType.dessert => 'Dessert',
    };

String _mealLabelDisplay(String mealLabel) {
  if (mealLabel.isEmpty) return 'Meal';
  final lower = mealLabel.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

class _IngredientSelectionDraft {
  _IngredientSelectionDraft({
    required this.ingredient,
    required this.selected,
    required this.quantity,
  });

  final Ingredient ingredient;
  bool selected;
  int quantity;
}

class _GroceryEditDraft {
  _GroceryEditDraft({
    required this.item,
    required this.quantity,
    required this.removed,
  });

  final GroceryItem item;
  int quantity;
  bool removed;
}
