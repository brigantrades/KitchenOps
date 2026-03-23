import 'package:app_settings/app_settings.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/planner_week_mapping.dart';
import 'package:plateplan/core/planner_slot_labels.dart';
import 'package:plateplan/core/services/meal_reminder_notification_service.dart';
import 'package:plateplan/core/ui/action_pill.dart';
import 'package:plateplan/core/ui/hero_panel.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/planner/data/planner_repository.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/planner/presentation/planner_optimistic_day_reorder_list.dart';
import 'package:plateplan/features/planner/presentation/planner_recipe_picker_sheet.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> showPlannerWindowSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final household = ref.read(activeHouseholdProvider).valueOrNull;
  final user = ref.read(currentUserProvider);
  final members = ref.read(householdMembersProvider).valueOrNull ?? const [];
  final currentMember =
      user == null ? null : members.firstWhereOrNull((m) => m.userId == user.id);
  final isOwner = currentMember?.role == HouseholdRole.owner;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      if (household == null) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Planner window',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'The weekly planner uses the app default (Monday through Sunday) until you join or create a household. '
                'Everyone in a household shares the same planner window.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      if (!isOwner) {
        final range = plannerWindowRangeLabel(
          household.plannerStartDay.clamp(0, 6),
          household.plannerDayCount.clamp(1, 14),
        );
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Planner window',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (range.isNotEmpty)
                Text(
                  'Shown as: $range',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                ),
              const SizedBox(height: 8),
              Text(
                'Only the household owner can change the planner window.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/household');
                },
                child: const Text('Open Household'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }

      var startDay = household.plannerStartDay;
      var dayCount = household.plannerDayCount;
      return StatefulBuilder(
        builder: (ctx, setModal) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
              left: 16,
              right: 16,
              top: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Planner window',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose start day and how many days to show '
                  '(e.g. Mon + 8 days is Mon through the following Mon). '
                  'This applies to everyone in your household.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: startDay.clamp(0, 6),
                  decoration: const InputDecoration(
                    labelText: 'Start day',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Monday')),
                    DropdownMenuItem(value: 1, child: Text('Tuesday')),
                    DropdownMenuItem(value: 2, child: Text('Wednesday')),
                    DropdownMenuItem(value: 3, child: Text('Thursday')),
                    DropdownMenuItem(value: 4, child: Text('Friday')),
                    DropdownMenuItem(value: 5, child: Text('Saturday')),
                    DropdownMenuItem(value: 6, child: Text('Sunday')),
                  ],
                  onChanged: (v) {
                    if (v != null) setModal(() => startDay = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: dayCount.clamp(1, 14),
                  decoration: const InputDecoration(
                    labelText: 'Number of days',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var n = 1; n <= 14; n++)
                      DropdownMenuItem(
                        value: n,
                        child: Text('$n day${n == 1 ? '' : 's'}'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setModal(() => dayCount = v);
                  },
                ),
                const SizedBox(height: 12),
                Builder(
                  builder: (ctx) {
                    final range = plannerWindowRangeLabel(
                      startDay.clamp(0, 6),
                      dayCount.clamp(1, 14),
                    );
                    if (range.isEmpty) return const SizedBox.shrink();
                    return Text(
                      'Shown as: $range',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    try {
                      await ref.read(householdRepositoryProvider).updateHouseholdPlannerWindow(
                            householdId: household.id,
                            plannerStartDay: startDay,
                            plannerDayCount: dayCount,
                          );
                      ref.invalidate(activeHouseholdProvider);
                      ref.invalidate(profileProvider);
                      ref.invalidate(plannerSlotsProvider);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Could not save: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

enum _SlotCardAction { clearMeal, deleteSlot }

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
    required this.targetListId,
    this.ingredientPicks = const [],
    this.customLines = const [],
  });

  final String targetListId;
  final List<_IngredientSelectionDraft> ingredientPicks;
  final List<PlannerGroceryDraftLine> customLines;

  bool get isEmpty => ingredientPicks.isEmpty && customLines.isEmpty;
}

/// Subtitle when the destination list already has matching item name(s).
String? basketSubtitleForPlannerIngredient(
  String ingredientName,
  List<GroceryItem> cartItems,
  List<Recipe> recipes,
) {
  final norm = normalizeGroceryItemName(ingredientName);
  final matches =
      cartItems.where((i) => normalizeGroceryItemName(i.name) == norm).toList();
  if (matches.isEmpty) return null;
  final qtyParts = <String>[];
  for (final m in matches) {
    final q = (m.quantity ?? '').trim();
    final u = (m.unit ?? '').trim();
    final part = [q, u].where((s) => s.isNotEmpty).join(' ').trim();
    qtyParts.add(part.isEmpty ? '1' : part);
  }
  final recipeTitles = <String>[];
  for (final m in matches) {
    final rid = m.fromRecipeId;
    if (rid == null) {
      if (!recipeTitles.contains('Added manually')) {
        recipeTitles.add('Added manually');
      }
      continue;
    }
    final title = recipes.firstWhereOrNull((r) => r.id == rid)?.title;
    if (title != null && !recipeTitles.contains(title)) {
      recipeTitles.add(title);
    }
  }
  var line = 'On list: ${qtyParts.join(', ')}';
  if (recipeTitles.isNotEmpty) {
    final show = recipeTitles.take(2).join(', ');
    final more = recipeTitles.length > 2 ? ' +${recipeTitles.length - 2}' : '';
    line += ' · from $show$more';
  }
  return line;
}

List<GroceryItem> basketMatchesForPlannerIngredient(
  String ingredientName,
  List<GroceryItem> cartItems,
) {
  final norm = normalizeGroceryItemName(ingredientName);
  return cartItems
      .where((i) => normalizeGroceryItemName(i.name) == norm)
      .toList();
}

Future<_GroceryPickResult?> _showPlannerGrocerySheet(
  BuildContext context,
  WidgetRef ref, {
  required MealPlanSlot slot,
  Recipe? recipe,
  required List<Recipe> recipes,
  required int servingsUsed,
}) {
  return showModalBottomSheet<_GroceryPickResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _PlannerGroceryAddSheet(
      slot: slot,
      recipe: recipe,
      recipes: recipes,
      servingsUsed: servingsUsed,
    ),
  );
}

class _PlannerGroceryAddSheet extends ConsumerStatefulWidget {
  const _PlannerGroceryAddSheet({
    required this.slot,
    required this.recipes,
    required this.servingsUsed,
    this.recipe,
  });

  final MealPlanSlot slot;
  final Recipe? recipe;
  final List<Recipe> recipes;
  final int servingsUsed;

  @override
  ConsumerState<_PlannerGroceryAddSheet> createState() =>
      _PlannerGroceryAddSheetState();
}

class _CustomLineDraft {
  _CustomLineDraft({required this.name, required this.quantity});

  final TextEditingController name;
  int quantity;
}

class _PlannerGroceryAddSheetState
    extends ConsumerState<_PlannerGroceryAddSheet> {
  late List<_IngredientSelectionDraft> _drafts;
  final List<_CustomLineDraft> _customLines = [];
  int _listScopeIndex = 0;
  String? _selectedListId;

  @override
  void initState() {
    super.initState();
    _drafts = widget.recipe?.ingredients
            .map(
              (ingredient) => _IngredientSelectionDraft(
                ingredient: ingredient,
                selected: true,
                quantity: 1,
              ),
            )
            .toList() ??
        <_IngredientSelectionDraft>[];
    if (widget.recipe == null) {
      final saved = widget.slot.groceryDraftLines;
      if (saved.isEmpty) {
        _customLines.add(_CustomLineDraft(
          name: TextEditingController(),
          quantity: 1,
        ));
      } else {
        for (final line in saved) {
          _customLines.add(_CustomLineDraft(
            name: TextEditingController(text: line.name),
            quantity: line.quantity.clamp(1, 999),
          ));
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _customLines) {
      c.name.dispose();
    }
    super.dispose();
  }

  Future<void> _persistDraftIfNeeded() async {
    if (widget.recipe != null) return;
    final lines = <PlannerGroceryDraftLine>[];
    for (final c in _customLines) {
      final n = c.name.text.trim();
      if (n.isEmpty) continue;
      lines.add(PlannerGroceryDraftLine(name: n, quantity: c.quantity));
    }
    await ref.read(plannerRepositoryProvider).updateSlotGroceryDraft(
          widget.slot.id,
          lines,
        );
    ref.invalidate(plannerSlotsProvider);
  }

  List<AppList> _orderedListsForScope(
    List<AppList> lists,
    ListScope scope,
    GroceryListOrder order,
  ) {
    return applyGroceryListOrder(lists, scope, order);
  }

  Future<void> _editExistingBasketItems(
    BuildContext context,
    List<GroceryItem> matches,
  ) async {
    if (matches.isEmpty) return;
    final drafts = matches
        .map(
          (item) => _GroceryEditDraft(
            item: item,
            quantity: int.tryParse(item.quantity ?? '') ?? 1,
            removed: false,
          ),
        )
        .toList();

    final edits = await showModalBottomSheet<List<_GroceryEditDraft>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit basket items',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: drafts.length,
                    itemBuilder: (ctx, index) {
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
                                        style: Theme.of(ctx)
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
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(drafts),
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
    if (edits == null || edits.isEmpty) {
      return;
    }
    try {
      final groceryRepo = ref.read(groceryRepositoryProvider);
      for (final edit in edits) {
        if (edit.removed) {
          await groceryRepo.removeItem(edit.item.id);
        } else {
          await groceryRepo.updateItemQuantity(
            edit.item.id,
            edit.quantity.toString(),
          );
        }
      }
      invalidateActiveGroceryStreams(ref);
    } on PostgrestException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update grocery items: ${error.message}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final listsAsync = ref.watch(listsProvider);
    final profileAsync = ref.watch(profileProvider);
    final hasSharedHousehold =
        ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;
    final profileOrder =
        profileAsync.valueOrNull?.groceryListOrder ?? GroceryListOrder.empty;

    return listsAsync.when(
      loading: () => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
          child: Text('Error: $e'),
        ),
      ),
      data: (lists) {
        final effectiveScopeIndex = hasSharedHousehold ? _listScopeIndex : 0;
        final scopeFilter = !hasSharedHousehold
            ? ListScope.private
            : (effectiveScopeIndex == 0
                ? ListScope.household
                : ListScope.private);
        final orderedFilteredLists =
            _orderedListsForScope(lists, scopeFilter, profileOrder);

        if (orderedFilteredLists.isNotEmpty) {
          final hasValid = _selectedListId != null &&
              orderedFilteredLists.any((l) => l.id == _selectedListId);
          if (!hasValid) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _selectedListId = orderedFilteredLists.first.id;
              });
            });
          }
        }

        final targetListId =
            _selectedListId ?? orderedFilteredLists.firstOrNull?.id ?? '';
        final itemsAsync = targetListId.isEmpty
            ? const AsyncValue<List<GroceryItem>>.data([])
            : ref.watch(groceryListItemsFamily(targetListId));

        final cartItems = itemsAsync.valueOrNull ?? const <GroceryItem>[];

        final dropdownValue = _selectedListId != null &&
                orderedFilteredLists.any((l) => l.id == _selectedListId)
            ? _selectedListId
            : orderedFilteredLists.firstOrNull?.id;

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
                      onPressed: () async {
                        await _persistDraftIfNeeded();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (hasSharedHousehold) ...[
                  const SizedBox(height: 8),
                  SegmentedPills(
                    labels: const ['Shared', 'Private'],
                    selectedIndex: effectiveScopeIndex,
                    onSelect: (idx) {
                      setState(() {
                        _listScopeIndex = idx;
                        final newScope =
                            idx == 0 ? ListScope.household : ListScope.private;
                        final newScopeLists = _orderedListsForScope(
                            lists, newScope, profileOrder);
                        if (newScopeLists.isEmpty) {
                          _selectedListId = null;
                        } else {
                          final still =
                              newScopeLists.any((l) => l.id == _selectedListId);
                          _selectedListId =
                              still ? _selectedListId : newScopeLists.first.id;
                        }
                      });
                    },
                  ),
                ],
                if (orderedFilteredLists.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'List',
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: dropdownValue,
                        items: orderedFilteredLists
                            .map(
                              (l) => DropdownMenuItem<String>(
                                value: l.id,
                                child: Text(l.name),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id == null) return;
                          setState(() => _selectedListId = id);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Basket hints use the list selected above.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                if (widget.recipe != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                        'Ingredients from ${widget.recipe!.title}',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                if (widget.recipe == null &&
                    (widget.slot.mealText?.trim().isNotEmpty ?? false))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, top: 4),
                      child: Text(
                        'Ingredients for ${widget.slot.mealText!.trim()}',
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
                      ..._drafts.map((draft) {
                        final matches = basketMatchesForPlannerIngredient(
                          draft.ingredient.name,
                          cartItems,
                        );
                        final subtitle = basketSubtitleForPlannerIngredient(
                          draft.ingredient.name,
                          cartItems,
                          widget.recipes,
                        );
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: subtitle != null
                              ? const Color(0xFFE8F7EE)
                              : const Color(0xFFF8FCFF),
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: draft.selected,
                                      onChanged: (value) => setState(() =>
                                          draft.selected = value ?? false),
                                    ),
                                    Expanded(
                                      child: Text(
                                        draft.ingredient.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () {
                                              setState(() {
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
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () {
                                              setState(() {
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
                                if (subtitle != null)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(left: 48, top: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            subtitle,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      const Color(0xFF1D5E39),
                                                ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _editExistingBasketItems(
                                            context,
                                            matches,
                                          ),
                                          child: const Text('Edit'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                      if (_drafts.isNotEmpty && _customLines.isNotEmpty)
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
                      ..._customLines.asMap().entries.map((entry) {
                        final index = entry.key;
                        final line = entry.value;
                        final matches = basketMatchesForPlannerIngredient(
                          line.name.text,
                          cartItems,
                        );
                        final subtitle = basketSubtitleForPlannerIngredient(
                          line.name.text,
                          cartItems,
                          widget.recipes,
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            color: subtitle != null
                                ? const Color(0xFFE8F7EE)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: line.name,
                                          textCapitalization:
                                              TextCapitalization.sentences,
                                          decoration: InputDecoration(
                                            hintText: 'Item ${index + 1}',
                                            prefixIcon: const Icon(
                                              Icons.shopping_bag_outlined,
                                              size: 20,
                                            ),
                                          ),
                                          onChanged: (_) => setState(() {}),
                                          onSubmitted: (_) {
                                            setState(() {
                                              _customLines.add(
                                                _CustomLineDraft(
                                                  name: TextEditingController(),
                                                  quantity: 1,
                                                ),
                                              );
                                            });
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () {
                                          setState(() {
                                            if (_customLines.length == 1) {
                                              line.name.clear();
                                              line.quantity = 1;
                                            } else {
                                              line.name.dispose();
                                              _customLines.removeAt(index);
                                            }
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 20),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(() {
                                            if (line.quantity > 1) {
                                              line.quantity -= 1;
                                            }
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                      ),
                                      Text(
                                        '${line.quantity}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(() {
                                            line.quantity += 1;
                                          });
                                        },
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                      ),
                                    ],
                                  ),
                                  if (subtitle != null)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 4, top: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              subtitle,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        const Color(0xFF1D5E39),
                                                  ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                _editExistingBasketItems(
                                              context,
                                              matches,
                                            ),
                                            child: const Text('Edit'),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                if (widget.recipe != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _customLines.add(
                            _CustomLineDraft(
                              name: TextEditingController(),
                              quantity: 1,
                            ),
                          );
                        });
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add additional item'),
                    ),
                  ),
                if (widget.recipe == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _customLines.add(
                            _CustomLineDraft(
                              name: TextEditingController(),
                              quantity: 1,
                            ),
                          );
                        });
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add item'),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await _persistDraftIfNeeded();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: targetListId.isEmpty
                            ? null
                            : () async {
                                final picks =
                                    _drafts.where((d) => d.selected).toList();
                                final custom = <PlannerGroceryDraftLine>[];
                                for (final c in _customLines) {
                                  final n = c.name.text.trim();
                                  if (n.isEmpty) continue;
                                  custom.add(PlannerGroceryDraftLine(
                                    name: n,
                                    quantity: c.quantity,
                                  ));
                                }
                                await _persistDraftIfNeeded();
                                if (!context.mounted) return;
                                Navigator.of(context).pop(_GroceryPickResult(
                                  targetListId: targetListId,
                                  ingredientPicks: picks,
                                  customLines: custom,
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
    );
  }
}

class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({super.key});
  Future<_SlotPlanDraft?> _editSlotPlan(
    BuildContext context, {
    required MealPlanSlot slot,
    required List<Recipe> recipes,
    required String slotDisplayLabel,
    required List<HouseholdMember> activeMembers,
    required String currentUserId,
  }) async {
    return showDialog<_SlotPlanDraft>(
      context: context,
      builder: (context) => _SlotPlanEditorDialog(
        slot: slot,
        slotDisplayLabel: slotDisplayLabel,
        recipes: recipes,
        activeMembers: activeMembers,
        currentUserId: currentUserId,
        pickRecipeForMeal: _pickRecipeForMeal,
      ),
    );
  }

  String _weekLabel(DateTime weekStart, int dayCount) {
    final weekEnd = weekStart.add(Duration(days: dayCount - 1));
    final sameMonth = weekStart.month == weekEnd.month;
    if (sameMonth) {
      return '${DateFormat('MMM').format(weekStart)} ${weekStart.day} - ${weekEnd.day}';
    }
    return '${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d').format(weekEnd)}';
  }

  Future<Recipe?> _pickRecipeForMeal(
    BuildContext context, {
    required String slotDisplayLabel,
    required List<Recipe> recipes,
  }) {
    if (recipes.isEmpty) return Future.value(null);
    return showPlannerRecipePicker(
      context,
      slotDisplayLabel: slotDisplayLabel,
      allRecipes: recipes,
    );
  }

  Future<String?> _pickNewMealLabel(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _AddMealOrSnackSheet(),
    );
  }

  Future<List<_GroceryEditDraft>?> _editPlannerSlotGroceryItems(
    BuildContext context, {
    required MealPlanSlot slot,
    Recipe? recipe,
    required List<GroceryItem> groceryItems,
  }) {
    final related = groceryItems.where((i) {
      if (i.sourceSlotId == slot.id) return true;
      if (recipe != null && i.fromRecipeId == recipe.id) return true;
      return false;
    }).toList();
    return _editGroceryItemDrafts(context, related);
  }

  Future<List<_GroceryEditDraft>?> _editGroceryItemDrafts(
    BuildContext context,
    List<GroceryItem> related,
  ) async {
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
    final pref = ref.watch(effectivePlannerWindowProvider);
    ref.listen<PlannerWindowPreference>(effectivePlannerWindowProvider,
        (prev, next) {
      final max = next.dayCount - 1;
      final current = ref.read(selectedPlannerDayProvider);
      if (current > max) {
        ref.read(selectedPlannerDayProvider.notifier).state = max;
      }
      if (prev != null &&
          (prev.startDay != next.startDay || prev.dayCount != next.dayCount)) {
        final now = DateTime.now();
        ref.read(weekStartProvider.notifier).state =
            anchorDateForWindowContaining(now, next);
      }
    });
    final weekStart = ref.watch(weekStartProvider);
    final dayCount = pref.dayCount;
    final stepDays = pref.navigationStepDays;
    final selectedDay = ref.watch(selectedPlannerDayProvider);
    final effectiveDay = selectedDay.clamp(0, dayCount - 1);
    final slotsAsync = ref.watch(plannerSlotsProvider);
    final recipesAsync = ref.watch(recipesProvider);
    final members = ref.watch(householdMembersProvider).valueOrNull ?? const [];
    final activeMembers =
        members.where((m) => m.status == HouseholdMemberStatus.active).toList();
    final currentUser = ref.watch(currentUserProvider);
    final groceryItems =
        ref.watch(groceryItemsProvider).valueOrNull ?? const [];
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
            final memberNameById = <String, String>{
              for (final member in activeMembers)
                member.userId: member.displayName,
            };
            final nutrition = slots.fold<Nutrition>(
              const Nutrition(),
              (sum, slot) =>
                  sum +
                  (recipes
                          .firstWhereOrNull((r) => r.id == slot.recipeId)
                          ?.nutrition ??
                      const Nutrition()),
            );
            final selectedDate = calendarDateForPlannerUiDay(
              weekStart,
              effectiveDay,
              pref,
            );
            final daySlots = slots
                .where((s) =>
                    plannerUiDayIndexForSlot(s, weekStart, pref) ==
                    effectiveDay)
                .sorted((a, b) => a.slotOrder.compareTo(b.slotOrder))
                .toList();
            final dayTotals = <int, int>{
              for (var day = 0; day < dayCount; day++) day: 0,
            };
            final dayAssigned = <int, int>{
              for (var day = 0; day < dayCount; day++) day: 0,
            };
            for (final slot in slots) {
              final ui = plannerUiDayIndexForSlot(slot, weekStart, pref);
              if (ui == null) continue;
              dayTotals[ui] = (dayTotals[ui] ?? 0) + 1;
              if (slot.hasPlannedContent) {
                dayAssigned[ui] = (dayAssigned[ui] ?? 0) + 1;
              }
            }
            final storageWeek =
                slotStorageWeekStartFromUiDay(weekStart, effectiveDay, pref);
            final storageDow =
                slotStorageDayOfWeekFromUiDay(weekStart, effectiveDay, pref);

            Future<void> removeMealSlot(
              MealPlanSlot slot,
              List<MealPlanSlot> slotsForLabel,
            ) async {
              final confirmed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (context) => AlertDialog(
                  title: const Text('Delete meal slot?'),
                  content: Text(
                    'Delete ${plannerSlotDisplayLabel(slotsForLabel, slot)} from ${DateFormat('EEEE').format(selectedDate)}? This cannot be undone.',
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
                              'Week of ${_weekLabel(weekStart, dayCount)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Planner window',
                            onPressed: () =>
                                showPlannerWindowSettingsSheet(context, ref),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                          IconButton(
                            tooltip: 'Previous week',
                            onPressed: () {
                              ref.read(weekStartProvider.notifier).state =
                                  weekStart.subtract(
                                      Duration(days: stepDays));
                              ref.invalidate(plannerSlotsProvider);
                            },
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          IconButton(
                            tooltip: 'Next week',
                            onPressed: () {
                              ref.read(weekStartProvider.notifier).state =
                                  weekStart.add(Duration(days: stepDays));
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
                    children: List.generate(dayCount, (dayIndex) {
                      final day = calendarDateForPlannerUiDay(
                        weekStart,
                        dayIndex,
                        pref,
                      );
                      final total = dayTotals[dayIndex] ?? 0;
                      final assigned = dayAssigned[dayIndex] ?? 0;
                      return ActionPill(
                        label:
                            '${DateFormat('EEE d').format(day)}  $assigned/$total',
                        selected: effectiveDay == dayIndex,
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
                        PlannerOptimisticDayReorderList(
                          syncKey:
                              '${weekStart.toIso8601String()}-$effectiveDay-${pref.startDay}-${pref.dayCount}',
                          providerDaySlots: daySlots,
                          itemBuilder: (context, i, slot, displaySlots) {
                            final recipe = slot.recipeId == null
                                ? null
                                : recipes.firstWhereOrNull(
                                    (r) => r.id == slot.recipeId);
                            final sideItems = slot.sideItems.isNotEmpty
                                ? slot.sideItems
                                : [
                                    PlannerSlotSideItem(
                                      recipeId: slot.sideRecipeId,
                                      text: slot.sideText,
                                    ),
                                  ].where((e) => !e.isEmpty).toList();
                            final mealSource =
                                slot.mealText?.trim().isNotEmpty == true
                                    ? 'Typed'
                                    : (recipe != null ? 'Recipe' : null);
                            final slotNutrition =
                                recipe?.nutrition ?? const Nutrition();
                            final hasSlotNutrition = recipe != null &&
                                (slotNutrition.calories > 0 ||
                                    slotNutrition.protein > 0 ||
                                    slotNutrition.fat > 0 ||
                                    slotNutrition.carbs > 0 ||
                                    slotNutrition.fiber > 0 ||
                                    slotNutrition.sugar > 0);
                            final slotNutritionLabel =
                                '${slotNutrition.calories} kcal • ${slotNutrition.protein.toStringAsFixed(0)}g protein';
                            final sauceRecipe = slot.sauceRecipeId == null
                                ? null
                                : recipes.firstWhereOrNull(
                                    (r) => r.id == slot.sauceRecipeId);
                            final sauceLabel =
                                slot.sauceText?.trim().isNotEmpty == true
                                    ? slot.sauceText!.trim()
                                    : sauceRecipe?.title;
                            final sauceSource =
                                slot.sauceText?.trim().isNotEmpty == true
                                    ? 'Typed'
                                    : (sauceRecipe != null ? 'Recipe' : null);
                            final hasTypedSource = mealSource == 'Typed' ||
                                sideItems.any(
                                  (side) =>
                                      side.text?.trim().isNotEmpty == true,
                                ) ||
                                sauceSource == 'Typed';
                            final hasRecipeSource = mealSource == 'Recipe' ||
                                sideItems.any(
                                  (side) =>
                                      side.text?.trim().isNotEmpty != true &&
                                      (side.recipeId?.isNotEmpty ?? false),
                                ) ||
                                sauceSource == 'Recipe';
                            final relatedGroceryForSlot =
                                groceryItems.where((i) {
                              if (i.sourceSlotId == slot.id) return true;
                              if (recipe != null &&
                                  i.fromRecipeId == recipe.id) {
                                return true;
                              }
                              return false;
                            }).toList();
                            final hasPlannerGroceryItems =
                                relatedGroceryForSlot.isNotEmpty;
                            final assignedIds = slot.assignedUserIds.isNotEmpty
                                ? slot.assignedUserIds
                                : activeMembers.map((m) => m.userId).toList();
                            final assignedNames = assignedIds
                                .map((id) => memberNameById[id])
                                .whereType<String>()
                                .toList();
                            final activeMemberIds =
                                activeMembers.map((m) => m.userId).toSet();
                            final assignedIdSet = assignedIds.toSet();
                            final allSelected = activeMemberIds.isNotEmpty &&
                                assignedIdSet.length ==
                                    activeMemberIds.length &&
                                activeMemberIds.every(assignedIdSet.contains);
                            final canAddToGrocery = recipe != null ||
                                (slot.mealText?.trim().isNotEmpty == true);
                            final assignmentLabel = allSelected
                                ? 'Assigned: All'
                                : (assignedNames.isEmpty
                                    ? 'Assigned: Unknown'
                                    : 'Assigned: ${assignedNames.join(', ')}');
                            final scheme = Theme.of(context).colorScheme;
                            Future<void> addToGrocery() async {
                              final user = ref.read(currentUserProvider);
                              if (user == null) return;
                              final groceryRepo =
                                  ref.read(groceryRepositoryProvider);
                              final result = await _showPlannerGrocerySheet(
                                context,
                                ref,
                                slot: slot,
                                recipe: recipe,
                                recipes: recipes,
                                servingsUsed: slot.servingsUsed,
                              );
                              if (result == null || result.isEmpty) return;
                              try {
                                ref
                                    .read(selectedListIdProvider.notifier)
                                    .state = result.targetListId;
                                for (final pick in result.ingredientPicks) {
                                  await groceryRepo.addItem(
                                    userId: user.id,
                                    listId: result.targetListId,
                                    name: pick.ingredient.name,
                                    quantity: pick.quantity.toString(),
                                    unit: null,
                                    category: pick.ingredient.category,
                                    fromRecipeId: recipe?.id,
                                    sourceSlotId: slot.id,
                                  );
                                }
                                for (final line in result.customLines) {
                                  await groceryRepo.addItem(
                                    userId: user.id,
                                    listId: result.targetListId,
                                    name: line.name,
                                    quantity: line.quantity.toString(),
                                    unit: null,
                                    category: groceryRepo.categorize(line.name),
                                    sourceSlotId: slot.id,
                                  );
                                }
                                final sauceRecipe = slot.sauceRecipeId == null
                                    ? null
                                    : recipes.firstWhereOrNull(
                                        (r) => r.id == slot.sauceRecipeId,
                                      );
                                if (sauceRecipe != null) {
                                  await groceryRepo.addIngredientsFromRecipe(
                                    sauceRecipe,
                                    userId: user.id,
                                    servingsUsed: slot.servingsUsed,
                                    listId: result.targetListId,
                                    sourceSlotId: slot.id,
                                  );
                                }
                                invalidateActiveGroceryStreams(ref);
                                ref.invalidate(groceryRecentsProvider);
                              } on PostgrestException catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not add to list: ${error.message}',
                                    ),
                                  ),
                                );
                              }
                            }

                            Future<void> editGroceryItems() async {
                              final edits = await _editPlannerSlotGroceryItems(
                                context,
                                slot: slot,
                                recipe: recipe,
                                groceryItems: groceryItems,
                              );
                              if (edits == null || edits.isEmpty) return;
                              try {
                                for (final edit in edits) {
                                  if (edit.removed) {
                                    await ref
                                        .read(groceryRepositoryProvider)
                                        .removeItem(edit.item.id);
                                  } else {
                                    await ref
                                        .read(groceryRepositoryProvider)
                                        .updateItemQuantity(
                                          edit.item.id,
                                          edit.quantity.toString(),
                                        );
                                  }
                                }
                                invalidateActiveGroceryStreams(ref);
                              } on PostgrestException catch (error) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not update grocery items: ${error.message}',
                                    ),
                                  ),
                                );
                              }
                            }

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
                                        slotDisplayLabel:
                                            plannerSlotDisplayLabel(
                                                displaySlots, slot),
                                        activeMembers: activeMembers,
                                        currentUserId: currentUser?.id ?? '',
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
                                              weekStart: storageWeek,
                                              dayOfWeek: storageDow,
                                              mealLabel: slot.mealLabel,
                                              slotOrder: slot.slotOrder,
                                              slotId: slot.id,
                                              recipeId: draft.mealRecipeId,
                                              mealText: draft.mealText,
                                              sideItems: draft.sideItems,
                                              sauceRecipeId:
                                                  draft.sauceRecipeId,
                                              sauceText: draft.sauceText,
                                              assignedUserIds:
                                                  draft.assignedUserIds,
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
                                    child: Stack(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 10),
                                          child: Row(
                                            children: [
                                              ReorderableDragStartListener(
                                                index: i,
                                                child: Icon(
                                                  Icons.drag_indicator_rounded,
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            plannerSlotDisplayLabel(
                                                                displaySlots,
                                                                slot),
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .labelLarge
                                                                ?.copyWith(
                                                                  color: scheme
                                                                      .onSurfaceVariant,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
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
                                                    if (mealSource == 'Recipe')
                                                      Text(
                                                        hasSlotNutrition
                                                            ? slotNutritionLabel
                                                            : 'Nutrition unavailable for this recipe.',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: scheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                    if (mealSource == 'Typed')
                                                      Text(
                                                        'Nutrition unavailable for typed meal.',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: scheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                    if (slot.hasPlannedContent)
                                                      Text(
                                                        assignmentLabel,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: scheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                    for (final side
                                                        in sideItems) ...[
                                                      Text(
                                                        'Side: ${side.text?.trim().isNotEmpty == true ? side.text!.trim() : recipes.firstWhereOrNull((r) => r.id == side.recipeId)?.title ?? ''}',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                    ],
                                                    if (sauceLabel != null &&
                                                        sauceLabel.isNotEmpty)
                                                      Text(
                                                        'Sauce: $sauceLabel',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox.shrink(),
                                            ],
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child:
                                              PopupMenuButton<_SlotCardAction>(
                                            tooltip: 'Slot options',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            splashRadius: 18,
                                            icon: const Icon(
                                              Icons.more_vert_rounded,
                                            ),
                                            onSelected: (action) async {
                                              if (action ==
                                                  _SlotCardAction.clearMeal) {
                                                try {
                                                  await ref
                                                      .read(
                                                          plannerRepositoryProvider)
                                                      .unassignSlot(
                                                        slotId: slot.id,
                                                      );
                                                  ref.invalidate(
                                                      plannerSlotsProvider);
                                                } on PostgrestException catch (error) {
                                                  if (!context.mounted) {
                                                    return;
                                                  }
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Could not clear meal: ${error.message}',
                                                      ),
                                                    ),
                                                  );
                                                }
                                                return;
                                              }
                                              await removeMealSlot(
                                                  slot, displaySlots);
                                            },
                                            itemBuilder: (context) => [
                                              if (slot.hasPlannedContent)
                                                const PopupMenuItem(
                                                  value:
                                                      _SlotCardAction.clearMeal,
                                                  child: Text('Clear meal'),
                                                ),
                                              const PopupMenuItem(
                                                value:
                                                    _SlotCardAction.deleteSlot,
                                                child: Text('Delete slot'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (slot.hasPlannedContent)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        if (canAddToGrocery)
                                          IconButton(
                                            tooltip: hasPlannerGroceryItems
                                                ? 'Items already on grocery list'
                                                : 'Add to grocery list',
                                            icon: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                const Icon(Icons
                                                    .add_shopping_cart_rounded),
                                                if (hasPlannerGroceryItems)
                                                  const Positioned(
                                                    right: -2,
                                                    bottom: -2,
                                                    child: Icon(
                                                      Icons
                                                          .check_circle_rounded,
                                                      size: 14,
                                                      color: Color(0xFF4ECDC4),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            onPressed: hasPlannerGroceryItems
                                                ? editGroceryItems
                                                : addToGrocery,
                                          ),
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: _PlannerSlotReminderRow(
                                            slot: slot,
                                            slotDate: plannerDateOnly(
                                                    slot.weekStart)
                                                .add(Duration(
                                                    days: slot.dayOfWeek)),
                                          ),
                                        ),
                                        const Spacer(),
                                        if (hasTypedSource || hasRecipeSource)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                right: 10),
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                if (hasTypedSource)
                                                  _sourceChip(context, 'Typed'),
                                                if (hasRecipeSource)
                                                  _sourceChip(
                                                      context, 'Recipe'),
                                              ],
                                            ),
                                          ),
                                      ],
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
                                    weekStart: storageWeek,
                                    dayOfWeek: storageDow,
                                  );
                              await ref.read(plannerRepositoryProvider).addSlot(
                                    userId: user.id,
                                    weekStart: storageWeek,
                                    dayOfWeek: storageDow,
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
                          label: const Text('Add meal or snack'),
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

/// Bottom sheet for adding a slot; owns [TextEditingController] so disposal
/// happens after the route is removed (avoids framework assertions when
/// canceling after opening the custom field + keyboard).
class _AddMealOrSnackSheet extends StatefulWidget {
  const _AddMealOrSnackSheet();

  @override
  State<_AddMealOrSnackSheet> createState() => _AddMealOrSnackSheetState();
}

class _AddMealOrSnackSheetState extends State<_AddMealOrSnackSheet> {
  late final TextEditingController _customCtrl;
  String _picked = 'meal';

  @override
  void initState() {
    super.initState();
    _customCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_picked == 'custom') {
      final raw = _customCtrl.text.trim();
      if (raw.isEmpty) return;
      Navigator.of(context).pop(raw.toLowerCase());
      return;
    }
    Navigator.of(context).pop(_picked);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add meal or snack',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionPill(
                  label: 'Meal',
                  selected: _picked == 'meal',
                  onTap: () => setState(() => _picked = 'meal'),
                ),
                ActionPill(
                  label: 'Snack',
                  selected: _picked == 'snack',
                  onTap: () => setState(() => _picked = 'snack'),
                ),
                ActionPill(
                  label: 'Custom',
                  selected: _picked == 'custom',
                  onTap: () => setState(() => _picked = 'custom'),
                ),
              ],
            ),
            if (_picked == 'custom') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _customCtrl,
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
                    onPressed: _submit,
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _MealReminderPermissionDialogAction { granted, openedSettings, cancelled }

Future<_MealReminderPermissionDialogAction> _showMealReminderPermissionDialog(
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
      return;
    }
    if (widget.slot.reminderAt != oldWidget.slot.reminderAt ||
        widget.slot.reminderMessage != oldWidget.slot.reminderMessage) {
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
        });
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear reminder: ${e.message}')),
      );
    }
  }

  Future<void> _openReminderDialog() async {
    final draftCtrl = TextEditingController(text: _messageCtrl.text);
    var draftTime = _time;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Meal reminder'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: draftCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reminder',
                  hintText: 'e.g. Lay out chicken',
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: dialogContext,
                      initialTime:
                          draftTime ?? const TimeOfDay(hour: 12, minute: 30),
                    );
                    if (picked == null) return;
                    setDialogState(() => draftTime = picked);
                  },
                  child: Text(
                    draftTime == null
                        ? 'Pick time'
                        : draftTime!.format(context),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                _messageCtrl.text = '';
                _time = null;
                await _clear();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Delete'),
            ),
            FilledButton(
              onPressed: () async {
                _messageCtrl.text = draftCtrl.text;
                _time = draftTime;
                await _save();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    draftCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeFmt = DateFormat.jm();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Reminder',
            icon: Icon(
              _hasReminder
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: _hasReminder ? scheme.primary : scheme.outline,
            ),
            onPressed: _openReminderDialog,
          ),
          if (_hasReminder)
            Text(
              timeFmt.format(widget.slot.reminderAt!.toLocal()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

typedef _PickRecipeForMeal = Future<Recipe?> Function(
  BuildContext context, {
  required String slotDisplayLabel,
  required List<Recipe> recipes,
});

Widget _sourceChip(BuildContext context, String label) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
    ),
  );
}

class _SlotPlanEditorDialog extends StatefulWidget {
  const _SlotPlanEditorDialog({
    required this.slot,
    required this.slotDisplayLabel,
    required this.recipes,
    required this.activeMembers,
    required this.currentUserId,
    required this.pickRecipeForMeal,
  });

  final MealPlanSlot slot;
  final String slotDisplayLabel;
  final List<Recipe> recipes;
  final List<HouseholdMember> activeMembers;
  final String currentUserId;
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
  final List<_SideDraft> _sideDrafts = [];
  int _sauceMode = 0; // 0 = pick a recipe, 1 = type a sauce
  late final Set<String> _assignedUserIds;

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
    final existingSides = widget.slot.sideItems.isNotEmpty
        ? widget.slot.sideItems
        : [
            PlannerSlotSideItem(
              recipeId: widget.slot.sideRecipeId,
              text: widget.slot.sideText,
            ),
          ].where((e) => !e.isEmpty).toList();
    for (final side in existingSides) {
      final ctrl = TextEditingController(text: side.text ?? '');
      final focus = FocusNode();
      final recipe = side.recipeId == null
          ? null
          : widget.recipes.firstWhereOrNull((r) => r.id == side.recipeId);
      final mode =
          side.text?.trim().isNotEmpty == true && recipe == null ? 1 : 0;
      _sideDrafts.add(
        _SideDraft(
          textCtrl: ctrl,
          focusNode: focus,
          recipe: recipe,
          mode: mode,
        ),
      );
    }
    _sauceRecipe = widget.slot.sauceRecipeId == null
        ? null
        : widget.recipes
            .firstWhereOrNull((r) => r.id == widget.slot.sauceRecipeId);
    _showSauce = _sauceTextCtrl.text.trim().isNotEmpty || _sauceRecipe != null;
    _assignedUserIds = widget.slot.assignedUserIds.isNotEmpty
        ? widget.slot.assignedUserIds.toSet()
        : widget.activeMembers.map((m) => m.userId).toSet();
    if (_assignedUserIds.isEmpty && widget.currentUserId.isNotEmpty) {
      _assignedUserIds.add(widget.currentUserId);
    }
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
    for (final side in _sideDrafts) {
      side.textCtrl.dispose();
      side.focusNode.dispose();
    }
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

  bool _hasNutritionData(Nutrition nutrition) {
    return nutrition.calories > 0 ||
        nutrition.protein > 0 ||
        nutrition.fat > 0 ||
        nutrition.carbs > 0 ||
        nutrition.fiber > 0 ||
        nutrition.sugar > 0;
  }

  Widget _buildMealNutritionInfoSection(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typedMealSelected =
        _mealMode == 1 && _mealTextCtrl.text.trim().isNotEmpty;
    final nutrition = _mealRecipe?.nutrition ?? const Nutrition();
    final hasNutrition = _mealRecipe != null && _hasNutritionData(nutrition);
    final servings = (_mealRecipe?.servings ?? 1).clamp(1, 999999);
    Nutrition perServingNutrition(Nutrition n) {
      final s = servings.toDouble();
      return Nutrition(
        calories: (n.calories / s).round(),
        protein: n.protein / s,
        fat: n.fat / s,
        carbs: n.carbs / s,
        fiber: n.fiber / s,
        sugar: n.sugar / s,
      );
    }

    final per = perServingNutrition(nutrition);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (typedMealSelected)
            Text(
              'Nutritional info is only available for recipe-linked meals with ingredients.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            )
          else if (_mealRecipe == null)
            Text(
              'Select a recipe to view nutrition for this slot.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            )
          else if (hasNutrition)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Nutritional value (per serving)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                subtitle: Text(
                  '${per.calories} kcal • ${per.protein.toStringAsFixed(1)} g protein',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.4),
                        1: FlexColumnWidth(1),
                      },
                      children: [
                        _nutritionTableRow(
                            context, 'Calories', '${per.calories} kcal'),
                        _nutritionTableRow(context, 'Protein',
                            '${per.protein.toStringAsFixed(1)} g'),
                        _nutritionTableRow(
                            context, 'Fat', '${per.fat.toStringAsFixed(1)} g'),
                        _nutritionTableRow(context, 'Carbs',
                            '${per.carbs.toStringAsFixed(1)} g'),
                        _nutritionTableRow(context, 'Fiber',
                            '${per.fiber.toStringAsFixed(1)} g'),
                        _nutritionTableRow(context, 'Sugar',
                            '${per.sugar.toStringAsFixed(1)} g'),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              'No nutrition totals found for this recipe yet.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }

  TableRow _nutritionTableRow(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
                      'Edit ${widget.slotDisplayLabel}',
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
              Text(
                'Main meal',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
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
                      slotDisplayLabel: widget.slotDisplayLabel,
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
              const SizedBox(height: 10),
              _buildMealNutritionInfoSection(context),
              const SizedBox(height: 12),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _sideDrafts.add(
                          _SideDraft(
                            textCtrl: TextEditingController(),
                            focusNode: FocusNode(),
                          ),
                        );
                      }),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add side'),
                    ),
                    if (!_showSauce)
                      TextButton.icon(
                        onPressed: () => setState(() => _showSauce = true),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Add sauce'),
                      ),
                  ],
                ),
              ),
              for (var sideIndex = 0;
                  sideIndex < _sideDrafts.length;
                  sideIndex++) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Side ${sideIndex + 1}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Remove side',
                      onPressed: () => setState(() {
                        final removed = _sideDrafts.removeAt(sideIndex);
                        removed.textCtrl.dispose();
                        removed.focusNode.dispose();
                      }),
                    ),
                  ],
                ),
                SegmentedPills(
                  labels: const ['Pick a recipe', 'Type a side'],
                  selectedIndex: _sideDrafts[sideIndex].mode,
                  onSelect: (idx) =>
                      setState(() => _sideDrafts[sideIndex].mode = idx),
                ),
                const SizedBox(height: 12),
                if (_sideDrafts[sideIndex].mode == 0)
                  _buildRecipeRow(
                    recipe: _sideDrafts[sideIndex].recipe,
                    emptyLabel: 'No side recipe selected',
                    onSelect: () async {
                      final picked = await widget.pickRecipeForMeal(
                        context,
                        slotDisplayLabel: 'Side',
                        recipes: widget.recipes,
                      );
                      if (picked == null) return;
                      setState(() => _sideDrafts[sideIndex].recipe = picked);
                    },
                    onRemove: () =>
                        setState(() => _sideDrafts[sideIndex].recipe = null),
                  )
                else
                  TextFormField(
                    controller: _sideDrafts[sideIndex].textCtrl,
                    focusNode: _sideDrafts[sideIndex].focusNode,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Side name',
                      hintText: 'e.g., Roasted carrots',
                    ),
                  ),
              ],
              if (_sideDrafts.isNotEmpty) const SizedBox(height: 12),
              if (_showSauce) ...[
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
                        slotDisplayLabel: 'Sauce',
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
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Who is this for?',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final member in widget.activeMembers)
                    FilterChip(
                      label: Text(member.displayName),
                      selected: _assignedUserIds.contains(member.userId),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _assignedUserIds.add(member.userId);
                          } else if (_assignedUserIds.length > 1) {
                            _assignedUserIds.remove(member.userId);
                          }
                        });
                      },
                    ),
                ],
              ),
              if (_assignedUserIds.length <= 1)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Tip: select both people for shared meals.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
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
                      onPressed: () {
                        final sideItems = <PlannerSlotSideItem>[
                          for (final side in _sideDrafts)
                            PlannerSlotSideItem(
                              recipeId: side.mode == 0 ? side.recipe?.id : null,
                              text: side.mode == 1
                                  ? side.textCtrl.text.trim()
                                  : null,
                            ),
                        ].where((e) => !e.isEmpty).toList();
                        Navigator.of(context).pop(
                          _SlotPlanDraft(
                            mealRecipeId:
                                _mealMode == 0 ? _mealRecipe?.id : null,
                            mealText: _mealMode == 1
                                ? _mealTextCtrl.text.trim()
                                : null,
                            sideItems: sideItems,
                            sauceRecipeId:
                                _sauceMode == 0 ? _sauceRecipe?.id : null,
                            sauceText: _sauceMode == 1
                                ? _sauceTextCtrl.text.trim()
                                : null,
                            assignedUserIds: _assignedUserIds.toList(),
                          ),
                        );
                      },
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

class _SideDraft {
  _SideDraft({
    required this.textCtrl,
    required this.focusNode,
    this.recipe,
    this.mode = 0,
  });

  final TextEditingController textCtrl;
  final FocusNode focusNode;
  Recipe? recipe;
  int mode; // 0 = recipe, 1 = typed
}

class _SlotPlanDraft {
  const _SlotPlanDraft({
    this.mealRecipeId,
    this.mealText,
    this.sideItems = const [],
    this.sauceRecipeId,
    this.sauceText,
    this.assignedUserIds = const [],
    this.clearAll = false,
  });

  final String? mealRecipeId;
  final String? mealText;
  final List<PlannerSlotSideItem> sideItems;
  final String? sauceRecipeId;
  final String? sauceText;
  final List<String> assignedUserIds;
  final bool clearAll;
}
