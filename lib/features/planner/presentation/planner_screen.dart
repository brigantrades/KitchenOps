import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/services/meal_reminder_notification_service.dart';
import 'package:plateplan/core/ui/action_pill.dart';
import 'package:plateplan/core/ui/hero_panel.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final plannerEditModeProvider = StateProvider<bool>((ref) => false);

class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({super.key});
  Future<_SlotPlanDraft?> _editSlotPlan(
    BuildContext context, {
    required MealPlanSlot slot,
    required List<Recipe> recipes,
  }) async {
    return showDialog<_SlotPlanDraft>(
      context: context,
      builder: (context) => _SlotPlanEditorDialog(
        slot: slot,
        recipes: recipes,
        pickRecipeForMeal: _pickRecipeForMeal,
      ),
    );
  }

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
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
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

  Future<_GroceryPickResult?> _openGrocerySheet(
    BuildContext context, {
    Recipe? recipe,
    required String mealName,
    int servingsUsed = 1,
  }) {
    final drafts = recipe?.ingredients
            .map(
              (ingredient) => _IngredientSelectionDraft(
                ingredient: ingredient,
                selected: true,
                quantity: 1,
              ),
            )
            .toList() ??
        <_IngredientSelectionDraft>[];
    final customItems = <TextEditingController>[];

    return showModalBottomSheet<_GroceryPickResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Add to grocery list',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (recipe != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Ingredients from ${recipe.title}',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        ...drafts.map((draft) {
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
                        }),
                        if (drafts.isNotEmpty && customItems.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Additional items',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ...customItems.asMap().entries.map((entry) {
                          final index = entry.key;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: entry.value,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    decoration: InputDecoration(
                                      hintText: 'Item ${index + 1}',
                                      prefixIcon: const Icon(
                                          Icons.shopping_bag_outlined,
                                          size: 20),
                                    ),
                                    onSubmitted: (_) {
                                      setModalState(() {
                                        customItems
                                            .add(TextEditingController());
                                      });
                                    },
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setModalState(() {
                                      customItems[index].dispose();
                                      customItems.removeAt(index);
                                    });
                                  },
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 20),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          customItems.add(TextEditingController());
                        });
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add additional item'),
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
                            final picks =
                                drafts.where((d) => d.selected).toList();
                            final custom = customItems
                                .map((c) => c.text.trim())
                                .where((t) => t.isNotEmpty)
                                .toList();
                            Navigator.of(context).pop(_GroceryPickResult(
                              ingredientPicks: picks,
                              customItems: custom,
                            ));
                          },
                          child: const Text('Add to list'),
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
                        'Edit List Items',
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
    final isEditMode = ref.watch(plannerEditModeProvider);
    final groceryRecipeIds = groceryItems
        .where((item) => item.fromRecipeId != null)
        .map((item) => item.fromRecipeId!)
        .toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Planner'),
      ),
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
              if (slot.hasPlannedContent) {
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => ref
                        .read(plannerEditModeProvider.notifier)
                        .state = !isEditMode,
                    icon: Icon(
                      isEditMode ? Icons.check_rounded : Icons.edit_rounded,
                      size: 18,
                    ),
                    label: Text(isEditMode ? 'Done' : 'Edit meal slots'),
                  ),
                ),
                const SizedBox(height: 4),
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
                            if (!isEditMode) return;
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
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () async {
                                      final draft = await _editSlotPlan(
                                        context,
                                        slot: slot,
                                        recipes: recipes,
                                      );
                                      if (draft == null) return;
                                      final user =
                                          ref.read(currentUserProvider);
                                      if (user == null) return;
                                      try {
                                        if (draft.clearAll) {
                                          await ref
                                              .read(plannerRepositoryProvider)
                                              .unassignSlot(slotId: slot.id);
                                          ref.invalidate(plannerSlotsProvider);
                                          return;
                                        }
                                        await ref
                                            .read(plannerRepositoryProvider)
                                            .assignSlot(
                                              userId: user.id,
                                              weekStart: weekStart,
                                              dayOfWeek: selectedDay,
                                              mealLabel: slot.mealLabel,
                                              slotOrder: slot.slotOrder,
                                              slotId: slot.id,
                                              recipeId: draft.mealRecipeId,
                                              mealText: draft.mealText,
                                              sauceRecipeId:
                                                  draft.sauceRecipeId,
                                              sauceText: draft.sauceText,
                                            );
                                        ref.invalidate(plannerSlotsProvider);
                                      } on PostgrestException catch (error) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
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
                                          isEditMode
                                              ? ReorderableDragStartListener(
                                                  index: i,
                                                  child: const Icon(
                                                    Icons
                                                        .drag_indicator_rounded,
                                                  ),
                                                )
                                              : Icon(
                                                  Icons.drag_indicator_rounded,
                                                  color: scheme.outlineVariant,
                                                ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _mealLabelDisplay(
                                                      slot.mealLabel),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelLarge
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                                Text(
                                                  slot.mealText
                                                              ?.trim()
                                                              .isNotEmpty ==
                                                          true
                                                      ? slot.mealText!
                                                      : (recipe?.title ??
                                                          'Tap to plan meal'),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                                if (slot.sauceText
                                                            ?.trim()
                                                            .isNotEmpty ==
                                                        true ||
                                                    slot.sauceRecipeId != null)
                                                  Text(
                                                    'Sauce: ${slot.sauceText?.trim().isNotEmpty == true ? slot.sauceText : recipes.firstWhereOrNull((r) => r.id == slot.sauceRecipeId)?.title ?? ''}',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isEditMode && recipe == null)
                                                IconButton(
                                                  tooltip: 'Remove meal slot',
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                  ),
                                                  onPressed: () =>
                                                      removeMealSlot(slot),
                                                ),
                                              if (isEditMode && recipe != null)
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
                                              if (recipe != null &&
                                                  isAlreadyAdded)
                                                IconButton(
                                                  tooltip: 'Edit list items',
                                                  icon: const Icon(
                                                    Icons.check_circle_rounded,
                                                    color: Color(0xFF4ECDC4),
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
                                                        if (edit.removed) {
                                                          await ref
                                                              .read(
                                                                  groceryRepositoryProvider)
                                                              .removeItem(
                                                                  edit.item.id);
                                                        } else {
                                                          await ref
                                                              .read(
                                                                  groceryRepositoryProvider)
                                                              .updateItemQuantity(
                                                                edit.item.id,
                                                                edit.quantity
                                                                    .toString(),
                                                              );
                                                        }
                                                      }
                                                      ref.invalidate(
                                                          groceryItemsProvider);
                                                    } on PostgrestException catch (error) {
                                                      if (!context.mounted)
                                                        return;
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Could not update grocery items: ${error.message}',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  },
                                                ),
                                              if (recipe != null ||
                                                  (slot.mealText
                                                          ?.trim()
                                                          .isNotEmpty ==
                                                      true))
                                                if (!(recipe != null &&
                                                    isAlreadyAdded))
                                                  IconButton(
                                                    tooltip:
                                                        'Add to grocery list',
                                                    icon: const Icon(Icons
                                                        .add_shopping_cart_rounded),
                                                    onPressed: () async {
                                                      final user = ref.read(
                                                          currentUserProvider);
                                                      if (user == null) return;
                                                      final selectedListId =
                                                          ref.read(
                                                              selectedListIdProvider);
                                                      final mealName =
                                                          recipe?.title ??
                                                              slot.mealText
                                                                  ?.trim() ??
                                                              'meal';
                                                      final result =
                                                          await _openGrocerySheet(
                                                        context,
                                                        recipe: recipe,
                                                        mealName: mealName,
                                                        servingsUsed:
                                                            slot.servingsUsed,
                                                      );
                                                      if (result == null ||
                                                          result.isEmpty) {
                                                        return;
                                                      }
                                                      try {
                                                        for (final pick in result
                                                            .ingredientPicks) {
                                                          await ref
                                                              .read(
                                                                  groceryRepositoryProvider)
                                                              .addItem(
                                                                userId: user.id,
                                                                listId:
                                                                    selectedListId,
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
                                                                    recipe?.id,
                                                              );
                                                        }
                                                        for (final name
                                                            in result
                                                                .customItems) {
                                                          await ref
                                                              .read(
                                                                  groceryRepositoryProvider)
                                                              .addItem(
                                                                userId: user.id,
                                                                listId:
                                                                    selectedListId,
                                                                name: name,
                                                                quantity: '1',
                                                                unit: null,
                                                              );
                                                        }
                                                        final sauceRecipe =
                                                            slot.sauceRecipeId ==
                                                                    null
                                                                ? null
                                                                : recipes
                                                                    .firstWhereOrNull(
                                                                    (r) =>
                                                                        r.id ==
                                                                        slot.sauceRecipeId,
                                                                  );
                                                        if (sauceRecipe !=
                                                            null) {
                                                          await ref
                                                              .read(
                                                                  groceryRepositoryProvider)
                                                              .addIngredientsFromRecipe(
                                                                sauceRecipe,
                                                                userId: user.id,
                                                                servingsUsed: slot
                                                                    .servingsUsed,
                                                                listId:
                                                                    selectedListId,
                                                                sourceSlotId:
                                                                    slot.id,
                                                              );
                                                        }
                                                        ref.invalidate(
                                                            groceryItemsProvider);
                                                        ref.invalidate(
                                                            groceryRecentsProvider);
                                                      } on PostgrestException catch (error) {
                                                        if (!context.mounted) {
                                                          return;
                                                        }
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                                'Could not add to list: ${error.message}'),
                                                          ),
                                                        );
                                                      }
                                                    },
                                                  ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (slot.hasPlannedContent)
                                    _PlannerSlotReminderRow(
                                      slot: slot,
                                      slotDate: weekStart.add(
                                          Duration(days: slot.dayOfWeek)),
                                    ),
                                ],
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

enum _MealReminderPermissionDialogAction { granted, openedSettings, cancelled }

Future<_MealReminderPermissionDialogAction>
    _showMealReminderPermissionDialog(
  BuildContext context,
  MealReminderPermissionState state,
  MealReminderNotificationService reminderSvc,
) async {
  final isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final lines = <String>[
    'Leckerly needs permission to remind you about this meal.',
  ];
  if (!state.notificationsEnabled) {
    lines.add('Turn on notifications for this app.');
  }
  if (isAndroid && !state.exactAlarmsAllowed) {
    lines.add(
      'On Android, also allow Leckerly to set alarms and reminders (under '
      'App info for Leckerly, or Special app access on some phones) so the '
      'alert arrives on time.',
    );
  }
  if (!isAndroid && !state.notificationsEnabled) {
    lines.add('You can enable them in Settings → Leckerly → Notifications.');
  }

  final result = await showDialog<_MealReminderPermissionDialogAction>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Turn on reminders'),
        content: SingleChildScrollView(
          child: Text(lines.join('\n\n')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              ctx,
              _MealReminderPermissionDialogAction.cancelled,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await AppSettings.openAppSettings();
              if (ctx.mounted) {
                Navigator.pop(
                  ctx,
                  _MealReminderPermissionDialogAction.openedSettings,
                );
              }
            },
            child: const Text('Open Settings'),
          ),
          FilledButton(
            onPressed: () async {
              await reminderSvc.requestReminderPermissions();
              final s = await reminderSvc.getReminderPermissionState();
              if (!ctx.mounted) return;
              if (s.isSufficient) {
                Navigator.pop(
                  ctx,
                  _MealReminderPermissionDialogAction.granted,
                );
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Permissions are still off. Use Open Settings or try again.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Try again'),
          ),
        ],
      );
    },
  );
  return result ?? _MealReminderPermissionDialogAction.cancelled;
}

class _PlannerSlotReminderRow extends ConsumerStatefulWidget {
  const _PlannerSlotReminderRow({
    required this.slot,
    required this.slotDate,
  });

  final MealPlanSlot slot;
  final DateTime slotDate;

  @override
  ConsumerState<_PlannerSlotReminderRow> createState() =>
      _PlannerSlotReminderRowState();
}

class _PlannerSlotReminderRowState
    extends ConsumerState<_PlannerSlotReminderRow> {
  bool _expanded = false;
  late TextEditingController _messageCtrl;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    _messageCtrl =
        TextEditingController(text: widget.slot.reminderMessage?.trim() ?? '');
    _applyTimeFromSlot();
  }

  void _applyTimeFromSlot() {
    final at = widget.slot.reminderAt;
    if (at != null) {
      final local = at.toLocal();
      _time = TimeOfDay(hour: local.hour, minute: local.minute);
    } else {
      _time = null;
    }
  }

  @override
  void didUpdateWidget(covariant _PlannerSlotReminderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.slot.id != oldWidget.slot.id) {
      _messageCtrl.text = widget.slot.reminderMessage?.trim() ?? '';
      _applyTimeFromSlot();
      _expanded = false;
      return;
    }
    if (!_expanded &&
        (widget.slot.reminderAt != oldWidget.slot.reminderAt ||
            widget.slot.reminderMessage != oldWidget.slot.reminderMessage)) {
      _messageCtrl.text = widget.slot.reminderMessage?.trim() ?? '';
      _applyTimeFromSlot();
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  bool get _hasReminder {
    final m = widget.slot.reminderMessage?.trim() ?? '';
    return m.isNotEmpty && widget.slot.reminderAt != null;
  }

  String _truncate(String s, [int max = 48]) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  Future<void> _pickTime() async {
    final scheme = Theme.of(context).colorScheme;
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 12, minute: 30),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(colorScheme: scheme),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a reminder message')),
      );
      return;
    }
    if (_time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a time')),
      );
      return;
    }
    final local = DateTime(
      widget.slotDate.year,
      widget.slotDate.month,
      widget.slotDate.day,
      _time!.hour,
      _time!.minute,
    );
    if (!local.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a time in the future')),
      );
      return;
    }

    final reminderSvc = ref.read(mealReminderNotificationServiceProvider);
    await reminderSvc.init();
    if (reminderSvc.isPermissionCheckAvailable) {
      await reminderSvc.requestReminderPermissions();
      while (mounted) {
        final perm = await reminderSvc.getReminderPermissionState();
        if (perm.isSufficient) break;
        if (!mounted) return;
        final action = await _showMealReminderPermissionDialog(
          context,
          perm,
          reminderSvc,
        );
        if (action == _MealReminderPermissionDialogAction.granted) break;
        if (action == _MealReminderPermissionDialogAction.openedSettings ||
            action == _MealReminderPermissionDialogAction.cancelled) {
          return;
        }
      }
    }

    if (!mounted) return;

    try {
      await ref.read(plannerRepositoryProvider).updateSlotReminder(
            slotId: widget.slot.id,
            reminderAt: local.toUtc(),
            message: msg,
          );
      ref.invalidate(plannerSlotsProvider);
      if (mounted) setState(() => _expanded = false);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save reminder: ${e.message}')),
      );
    }
  }

  Future<void> _clear() async {
    try {
      await ref.read(plannerRepositoryProvider).updateSlotReminder(
            slotId: widget.slot.id,
            reminderAt: null,
            message: null,
          );
      ref.invalidate(plannerSlotsProvider);
      if (mounted) {
        _messageCtrl.clear();
        setState(() {
          _time = null;
          _expanded = false;
        });
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear reminder: ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeFmt = DateFormat.jm();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                tooltip: _expanded ? 'Close reminder' : 'Reminder',
                icon: Icon(
                  _hasReminder
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  color: _hasReminder ? scheme.primary : scheme.outline,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              Expanded(
                child: _hasReminder && !_expanded
                    ? Text(
                        '${timeFmt.format(widget.slot.reminderAt!.toLocal())} · ${_truncate(widget.slot.reminderMessage!)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextField(
                controller: _messageCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reminder',
                  hintText: 'e.g. Lay out chicken',
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  FilledButton.tonal(
                    onPressed: _pickTime,
                    child: Text(
                      _time == null ? 'Pick time' : _time!.format(context),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _clear,
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _mealTypeLabel(MealType mealType) => switch (mealType) {
      MealType.entree => 'Entree',
      MealType.side => 'Side',
      MealType.sauce => 'Sauce',
      MealType.snack => 'Snack',
      MealType.dessert => 'Dessert',
    };

String _mealLabelDisplay(String mealLabel) {
  if (mealLabel.isEmpty) return 'Meal';
  final lower = mealLabel.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

typedef _PickRecipeForMeal = Future<Recipe?> Function(
  BuildContext context, {
  required String mealLabel,
  required List<Recipe> recipes,
});

class _SlotPlanEditorDialog extends StatefulWidget {
  const _SlotPlanEditorDialog({
    required this.slot,
    required this.recipes,
    required this.pickRecipeForMeal,
  });

  final MealPlanSlot slot;
  final List<Recipe> recipes;
  final _PickRecipeForMeal pickRecipeForMeal;

  @override
  State<_SlotPlanEditorDialog> createState() => _SlotPlanEditorDialogState();
}

class _SlotPlanEditorDialogState extends State<_SlotPlanEditorDialog> {
  late final TextEditingController _mealTextCtrl;
  late final TextEditingController _sauceTextCtrl;
  late final FocusNode _mealFocus;
  late final FocusNode _sauceFocus;
  Recipe? _mealRecipe;
  Recipe? _sauceRecipe;
  bool _showSauce = false;
  int _mealMode = 0; // 0 = pick a recipe, 1 = type a meal
  int _sauceMode = 0; // 0 = pick a recipe, 1 = type a sauce

  @override
  void initState() {
    super.initState();
    _mealTextCtrl = TextEditingController(text: widget.slot.mealText ?? '');
    _sauceTextCtrl = TextEditingController(text: widget.slot.sauceText ?? '');
    _mealFocus = FocusNode();
    _sauceFocus = FocusNode();
    _mealRecipe = widget.slot.recipeId == null
        ? null
        : widget.recipes.firstWhereOrNull((r) => r.id == widget.slot.recipeId);
    _sauceRecipe = widget.slot.sauceRecipeId == null
        ? null
        : widget.recipes
            .firstWhereOrNull((r) => r.id == widget.slot.sauceRecipeId);
    _showSauce = _sauceTextCtrl.text.trim().isNotEmpty || _sauceRecipe != null;
    if (_mealTextCtrl.text.trim().isNotEmpty && _mealRecipe == null) {
      _mealMode = 1;
    }
    if (_sauceTextCtrl.text.trim().isNotEmpty && _sauceRecipe == null) {
      _sauceMode = 1;
    }
  }

  @override
  void dispose() {
    _mealTextCtrl.dispose();
    _sauceTextCtrl.dispose();
    _mealFocus.dispose();
    _sauceFocus.dispose();
    super.dispose();
  }

  Widget _buildRecipeRow({
    required Recipe? recipe,
    required String emptyLabel,
    required VoidCallback onSelect,
    VoidCallback? onRemove,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      child: Row(
        children: [
          Icon(
            recipe != null
                ? Icons.restaurant_rounded
                : Icons.restaurant_menu_rounded,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              recipe?.title ?? emptyLabel,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: recipe != null ? null : scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (recipe != null && onRemove != null) ...[
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.close_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
              tooltip: 'Remove',
            ),
            const SizedBox(width: 4),
          ],
          FilledButton.tonal(
            onPressed: onSelect,
            child: Text(recipe != null ? 'Change' : 'Select'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit ${_mealLabelDisplay(widget.slot.mealLabel)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedPills(
                labels: const ['Pick a recipe', 'Type a meal'],
                selectedIndex: _mealMode,
                onSelect: (idx) => setState(() => _mealMode = idx),
              ),
              const SizedBox(height: 16),
              if (_mealMode == 0)
                _buildRecipeRow(
                  recipe: _mealRecipe,
                  emptyLabel: 'No recipe selected',
                  onSelect: () async {
                    final picked = await widget.pickRecipeForMeal(
                      context,
                      mealLabel: widget.slot.mealLabel,
                      recipes: widget.recipes,
                    );
                    if (picked == null) return;
                    setState(() => _mealRecipe = picked);
                  },
                  onRemove: () => setState(() => _mealRecipe = null),
                )
              else
                TextFormField(
                  controller: _mealTextCtrl,
                  focusNode: _mealFocus,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Meal name',
                    hintText: 'e.g., Canned Soup',
                  ),
                ),
              const SizedBox(height: 12),
              const Divider(),
              if (!_showSauce)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _showSauce = true),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Add sauce'),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sauce',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Remove sauce',
                      onPressed: () => setState(() {
                        _showSauce = false;
                        _sauceMode = 0;
                        _sauceTextCtrl.clear();
                        _sauceRecipe = null;
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedPills(
                  labels: const ['Pick a recipe', 'Type a sauce'],
                  selectedIndex: _sauceMode,
                  onSelect: (idx) => setState(() => _sauceMode = idx),
                ),
                const SizedBox(height: 12),
                if (_sauceMode == 0)
                  _buildRecipeRow(
                    recipe: _sauceRecipe,
                    emptyLabel: 'No sauce recipe selected',
                    onSelect: () async {
                      final picked = await widget.pickRecipeForMeal(
                        context,
                        mealLabel: 'sauce',
                        recipes: widget.recipes,
                      );
                      if (picked == null) return;
                      setState(() => _sauceRecipe = picked);
                    },
                    onRemove: () => setState(() => _sauceRecipe = null),
                  )
                else
                  TextFormField(
                    controller: _sauceTextCtrl,
                    focusNode: _sauceFocus,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Sauce name',
                      hintText: 'e.g., Chili crisp',
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(
                        const _SlotPlanDraft(clearAll: true),
                      ),
                      child: const Text('Clear slot'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        _SlotPlanDraft(
                          mealRecipeId: _mealMode == 0 ? _mealRecipe?.id : null,
                          mealText:
                              _mealMode == 1 ? _mealTextCtrl.text.trim() : null,
                          sauceRecipeId:
                              _sauceMode == 0 ? _sauceRecipe?.id : null,
                          sauceText: _sauceMode == 1
                              ? _sauceTextCtrl.text.trim()
                              : null,
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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

class _GroceryPickResult {
  const _GroceryPickResult({
    this.ingredientPicks = const [],
    this.customItems = const [],
  });

  final List<_IngredientSelectionDraft> ingredientPicks;
  final List<String> customItems;

  bool get isEmpty => ingredientPicks.isEmpty && customItems.isEmpty;
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

class _SlotPlanDraft {
  const _SlotPlanDraft({
    this.mealRecipeId,
    this.mealText,
    this.sauceRecipeId,
    this.sauceText,
    this.clearAll = false,
  });

  final String? mealRecipeId;
  final String? mealText;
  final String? sauceRecipeId;
  final String? sauceText;
  final bool clearAll;
}
