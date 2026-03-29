import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/features/household/data/household_providers.dart';

/// Recipe picker aligned with [RecipesScreen] library and filters.
Future<Recipe?> showPlannerRecipePicker(
  BuildContext context, {
  required String slotDisplayLabel,
  required List<Recipe> allRecipes,
}) {
  return showModalBottomSheet<Recipe>(
    context: context,
    isScrollControlled: true,
    builder: (context) => PlannerRecipePickerSheet(
      slotDisplayLabel: slotDisplayLabel,
      allRecipes: allRecipes,
    ),
  );
}

class PlannerRecipePickerSheet extends ConsumerStatefulWidget {
  const PlannerRecipePickerSheet({
    super.key,
    required this.slotDisplayLabel,
    required this.allRecipes,
  });

  final String slotDisplayLabel;
  final List<Recipe> allRecipes;

  @override
  ConsumerState<PlannerRecipePickerSheet> createState() =>
      _PlannerRecipePickerSheetState();
}

class _PlannerRecipePickerSheetState
    extends ConsumerState<PlannerRecipePickerSheet> {
  final _searchCtrl = TextEditingController();
  int _libraryIndex = 0;
  int _segmentIndex = 0;
  final Set<MealType> _mealTypeFilters = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _mealFilterShowsAllRecipes() {
    if (_mealTypeFilters.isEmpty) return true;
    if (_mealTypeFilters.length == MealType.values.length) return true;
    return false;
  }

  bool _recipePassesMealFilter(Recipe recipe) {
    if (_mealFilterShowsAllRecipes()) return true;
    return _mealTypeFilters.contains(recipe.mealType);
  }

  void _toggleMealTypeFilter(MealType type, bool selected) {
    setState(() {
      if (selected) {
        _mealTypeFilters.add(type);
      } else {
        _mealTypeFilters.remove(type);
      }
    });
  }

  String _mealTypeLabel(MealType mealType) => switch (mealType) {
        MealType.entree => 'Entree',
        MealType.side => 'Side',
        MealType.sauce => 'Sauce',
        MealType.snack => 'Snack',
        MealType.dessert => 'Dessert',
      };

  @override
  Widget build(BuildContext context) {
    final hasSharedHousehold =
        ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;
    final query = _searchCtrl.text.trim().toLowerCase();
    final effectiveLibraryIndex = hasSharedHousehold ? _libraryIndex : 0;
    final libraryLabels = hasSharedHousehold
        ? const ['Household Recipes', 'My Recipes']
        : const ['My Recipes'];

    bool matches(Recipe recipe) {
      if (query.isEmpty) return true;
      final title = recipe.title.toLowerCase();
      final cuisines = recipe.cuisineTags.join(' ').toLowerCase();
      final meal = _mealTypeLabel(recipe.mealType).toLowerCase();
      return title.contains(query) ||
          cuisines.contains(query) ||
          meal.contains(query);
    }

    final filtered = widget.allRecipes.where(matches).toList();
    final isHouseholdLibrary =
        hasSharedHousehold && effectiveLibraryIndex == 0;
    final List<Recipe> visible;
    if (isHouseholdLibrary) {
      final householdBase = filtered
          .where((r) => r.visibility == RecipeVisibility.household)
          .toList();
      final hhFavorites =
          householdBase.where((r) => r.isFavorite).toList();
      final hhToTry = householdBase.where((r) => r.isToTry).toList();
      visible = switch (_segmentIndex) {
        1 => hhFavorites,
        2 => hhToTry,
        _ => householdBase,
      };
    } else {
      final personal =
          filtered.where((r) => r.visibility != RecipeVisibility.household).toList();
      final favorites = personal.where((r) => r.isFavorite).toList();
      final toTry = personal.where((r) => r.isToTry).toList();
      visible = switch (_segmentIndex) {
        1 => favorites,
        2 => toTry,
        _ => personal,
      };
    }
    final displayed = visible.where(_recipePassesMealFilter).toList();

    final emptyListMessage = isHouseholdLibrary
        ? switch (_segmentIndex) {
            1 =>
              'No household favorites yet. Open a household recipe and turn on My Favorites in Lists & Sharing.',
            2 =>
              'Nothing in To Try for household recipes. Mark one from Lists & Sharing.',
            _ => 'No recipes yet. Add one in Discover or Planner.',
          }
        : switch (_segmentIndex) {
            1 =>
              'No favorites yet. Open a personal recipe and turn on My Favorites.',
            2 =>
              'Nothing in To Try. Mark a personal recipe from Lists & Sharing.',
            _ => 'No recipes yet. Add one in Discover or Planner.',
          };

    final sheetBodyHeight =
        (MediaQuery.of(context).size.height * 0.62).clamp(340.0, 560.0);

    return BrandedSheetScaffold(
      title: 'Select ${widget.slotDisplayLabel} recipe',
      child: SizedBox(
        height: sheetBodyHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SearchBar(
                    controller: _searchCtrl,
                    hintText: hasSharedHousehold
                        ? (effectiveLibraryIndex == 0
                            ? 'Search household recipes'
                            : 'Search my recipes')
                        : 'Search my recipes',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SegmentedPills(
              labels: libraryLabels,
              selectedIndex: effectiveLibraryIndex,
              onSelect: (idx) => setState(() {
                _libraryIndex = idx;
                _segmentIndex = 0;
              }),
            ),
            const SizedBox(height: 4),
            SegmentedPills(
              labels: const ['All', 'Favorites', 'To Try'],
              selectedIndex: _segmentIndex,
              onSelect: (idx) => setState(() => _segmentIndex = idx),
            ),
            const SizedBox(height: 4),
            Text(
              'Meal type',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final type in [
                  MealType.entree,
                  MealType.side,
                  MealType.sauce,
                  MealType.snack,
                ])
                  FilterChip(
                    label: Text(_mealTypeLabel(type)),
                    selected: _mealTypeFilters.contains(type),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (value) => _toggleMealTypeFilter(type, value),
                    selectedColor: const Color(0xFFD6EBFF),
                  ),
                FilterChip(
                  label: Text(_mealTypeLabel(MealType.dessert)),
                  selected: _mealTypeFilters.contains(MealType.dessert),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (value) =>
                      _toggleMealTypeFilter(MealType.dessert, value),
                  selectedColor: const Color(0xFFD6EBFF),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: displayed.isEmpty
                    ? null
                    : () {
                        final picked =
                            displayed[Random().nextInt(displayed.length)];
                        Navigator.of(context).pop(picked);
                      },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Select for me'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: displayed.isEmpty
                  ? Center(
                      child: Text(emptyListMessage),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      itemCount: displayed.length,
                      itemBuilder: (context, index) {
                        final recipe = displayed[index];
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
      ),
    );
  }
}
