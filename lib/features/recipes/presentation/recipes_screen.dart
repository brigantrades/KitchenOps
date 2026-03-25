import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';
import 'package:plateplan/core/ui/food_icon_resolver.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/measurement_system_toggle.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/services/nutrition_estimation.dart';
import 'package:plateplan/core/services/recipe_nutrition_lines.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';
import 'package:plateplan/core/strings/recipe_title_case.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/grocery/presentation/grocery_item_suggestions_grid.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/recipes/presentation/recipe_creation_guard.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// When true, Step 5 shows per-ingredient USDA/Gemini breakdown (dev / diagnostics).
const bool _kShowNutritionIngredientBreakdown = false;

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

enum _RecipeSortOption { dateAdded, name }

String _recipeSortOptionLabel(_RecipeSortOption o) {
  return switch (o) {
    _RecipeSortOption.dateAdded => 'Date added',
    _RecipeSortOption.name => 'Name',
  };
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  final _searchCtrl = TextEditingController();
  int _libraryIndex = 0;
  int _segmentIndex = 0;
  final Set<MealType> _mealTypeFilters = {};
  _RecipeSortOption _sortOption = _RecipeSortOption.dateAdded;

  Future<void> _createRecipeManually() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sign in required.')));
      return;
    }

    final recipe = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => const _RecipeBuilderSheet(),
    );

    if (recipe == null) return;

    try {
      final isHousehold = recipe.visibility == RecipeVisibility.household;
      final repo = ref.read(recipesRepositoryProvider);
      if (isHousehold) {
        // Household-only insert would skip a personal row; My Recipes → Favorites
        // lists personal recipes only. Match the Share flow: personal first, then copy.
        final personalDraft = Recipe(
          id: recipe.id,
          title: recipe.title,
          description: recipe.description,
          servings: recipe.servings,
          prepTime: recipe.prepTime,
          cookTime: recipe.cookTime,
          mealType: recipe.mealType,
          cuisineTags: recipe.cuisineTags,
          ingredients: recipe.ingredients,
          instructions: recipe.instructions,
          imageUrl: recipe.imageUrl,
          nutrition: recipe.nutrition,
          isFavorite: recipe.isFavorite,
          isToTry: recipe.isToTry,
          source: recipe.source,
          userId: recipe.userId,
          householdId: null,
          visibility: RecipeVisibility.personal,
          apiId: recipe.apiId,
          nutritionSource: recipe.nutritionSource,
        );
        final personalId = await repo.create(
          user.id,
          personalDraft,
          shareWithHousehold: false,
          visibilityOverride: RecipeVisibility.personal,
        );
        await repo.copyPersonalRecipeToHousehold(
          userId: user.id,
          recipeId: personalId,
        );
      } else {
        await repo.create(
          user.id,
          recipe,
          shareWithHousehold: false,
          visibilityOverride: recipe.visibility,
        );
      }
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      final dest = switch (recipe.visibility) {
        RecipeVisibility.household => 'My Recipes and Household Recipes',
        RecipeVisibility.public => 'My Recipes (public)',
        _ => 'My Recipes',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recipe "${recipe.title}" saved to $dest.')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create recipe: ${error.message}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create recipe. Try again.')),
      );
    }
  }

  Future<void> _editRecipe(Recipe recipe) async {
    final updated = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _RecipeBuilderSheet(initialRecipe: recipe),
    );
    if (updated == null) return;
    try {
      await ref
          .read(recipesRepositoryProvider)
          .updateRecipe(recipe.id, updated);
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated "${updated.title}".')),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update recipe: ${error.message}')),
      );
    }
  }

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

  Widget _buildRecipesFilterHeader({
    required BuildContext context,
    required bool hasSharedHousehold,
    required int effectiveLibraryIndex,
    required List<String> libraryLabels,
  }) {
    final colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBar(
          controller: _searchCtrl,
          hintText: hasSharedHousehold
              ? (effectiveLibraryIndex == 0
                  ? 'Search household recipes'
                  : 'Search my recipes')
              : 'Search my recipes',
          onChanged: (_) => setState(() {}),
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
        if (!(hasSharedHousehold && effectiveLibraryIndex == 0)) ...[
          const SizedBox(height: 4),
          SegmentedPills(
            labels: const ['All', 'Favorites', 'To Try'],
            selectedIndex: _segmentIndex,
            onSelect: (idx) => setState(() => _segmentIndex = idx),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Meal type',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FilterChip(
                  label: Text(_mealTypeLabel(MealType.dessert)),
                  selected: _mealTypeFilters.contains(MealType.dessert),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (value) =>
                      _toggleMealTypeFilter(MealType.dessert, value),
                  selectedColor: const Color(0xFFD6EBFF),
                ),
                const Spacer(),
                PopupMenuButton<_RecipeSortOption>(
                  padding: EdgeInsets.zero,
                  offset: const Offset(0, 10),
                  initialValue: _sortOption,
                  color: colors.panel,
                  surfaceTintColor: Colors.transparent,
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.sm,
                    side: BorderSide(color: colors.pillBorder),
                  ),
                  tooltip: 'Sort · ${_recipeSortOptionLabel(_sortOption)}',
                  onSelected: (value) => setState(() => _sortOption = value),
                  itemBuilder: (context) => [
                    PopupMenuItem<_RecipeSortOption>(
                      value: _RecipeSortOption.dateAdded,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_recipeSortOptionLabel(
                                _RecipeSortOption.dateAdded)),
                          ),
                          if (_sortOption == _RecipeSortOption.dateAdded)
                            Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: scheme.primary,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuItem<_RecipeSortOption>(
                      value: _RecipeSortOption.name,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                _recipeSortOptionLabel(_RecipeSortOption.name)),
                          ),
                          if (_sortOption == _RecipeSortOption.name)
                            Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: scheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.sort_rounded,
                      size: 22,
                      color: scheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(recipesProvider);
    final hasSharedHousehold =
        ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;
    final query = _searchCtrl.text.trim().toLowerCase();
    final colors =
        Theme.of(context).extension<AppThemeColors>() ?? AppThemeColors.light;
    final effectiveLibraryIndex = hasSharedHousehold ? _libraryIndex : 0;
    final libraryLabels = hasSharedHousehold
        ? const ['Household Recipes', 'My Recipes']
        : const ['My Recipes'];

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [colors.surfaceBase, colors.surfaceAlt, colors.surfaceBase],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.black26,
        surfaceTintColor: Colors.transparent,
        backgroundColor: colors.surfaceBase,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Test Instagram import',
            onPressed: () => context.push('/instagram-import-test'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRecipeManually,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Recipe'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: recipesAsync.when(
          data: (recipes) {
            bool matches(Recipe recipe) {
              if (query.isEmpty) return true;
              final title = recipe.title.toLowerCase();
              final cuisines = recipe.cuisineTags.join(' ').toLowerCase();
              final meal = _mealTypeLabel(recipe.mealType).toLowerCase();
              return title.contains(query) ||
                  cuisines.contains(query) ||
                  meal.contains(query);
            }

            final filtered = recipes.where(matches).toList();
            final isHouseholdLibrary =
                hasSharedHousehold && effectiveLibraryIndex == 0;
            final List<Recipe> visible;
            if (isHouseholdLibrary) {
              // All shared household rows — not only favorites. New "Save to Household"
              // copies often have is_favorite false until the user favorites them.
              visible = filtered
                  .where((r) => r.visibility == RecipeVisibility.household)
                  .toList();
            } else {
              final personal = filtered
                  .where((r) => r.visibility != RecipeVisibility.household)
                  .toList();
              final favorites = personal.where((r) => r.isFavorite).toList();
              final toTry = personal.where((r) => r.isToTry).toList();
              // My Recipes lists personal copies only. Favorites / To Try are your
              // personal rows; household copies live under Household Recipes.
              visible = switch (_segmentIndex) {
                1 => favorites,
                2 => toTry,
                _ => personal,
              };
            }
            final displayed = visible.where(_recipePassesMealFilter).toList();
            displayed.sort((a, b) {
              switch (_sortOption) {
                case _RecipeSortOption.name:
                  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
                case _RecipeSortOption.dateAdded:
                  final aTime =
                      a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final bTime =
                      b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return bTime.compareTo(aTime);
              }
            });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: _buildRecipesFilterHeader(
                    context: context,
                    hasSharedHousehold: hasSharedHousehold,
                    effectiveLibraryIndex: effectiveLibraryIndex,
                    libraryLabels: libraryLabels,
                  ),
                ),
                Expanded(
                  child: displayed.isEmpty
                      ? Center(
                          child: Text(
                            isHouseholdLibrary
                                ? 'No recipes yet. Add one in Discover or Planner.'
                                : switch (_segmentIndex) {
                                    1 =>
                                      'No favorites yet. Open a personal recipe and turn on My Favorites.',
                                    2 =>
                                      'Nothing in To Try. Mark a personal recipe from Lists & Sharing.',
                                    _ =>
                                      'No recipes yet. Add one in Discover or Planner.',
                                  },
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            10,
                            0,
                            10,
                            88,
                          ),
                          itemCount: displayed.length,
                          itemBuilder: (context, index) {
                            return _RecipeRow(
                              recipe: displayed[index],
                              hasSharedHousehold: hasSharedHousehold,
                              isHouseholdLibrary: isHouseholdLibrary,
                              onEditRecipe: _editRecipe,
                            );
                          },
                        ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(child: Text('Error: $error')),
        ),
      ),
    );
  }
}

Future<void> _confirmAndDeleteRecipe(
  BuildContext context,
  Recipe recipe,
) async {
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final repo = container.read(recipesRepositoryProvider);
  final removesForHousehold = recipe.visibility == RecipeVisibility.household;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Text('Remove recipe permanently?'),
        content: Text(
          removesForHousehold
              ? 'This will permanently remove "${recipe.title}" '
                  'from Household Recipes for everyone in your household.'
              : 'This will permanently delete "${recipe.title}" '
                  'from your recipes only. If you shared a copy to '
                  'Household Recipes, that copy stays until you remove '
                  'it from the Household tab.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  try {
    await repo.deleteRecipe(recipe.id);
    if (!context.mounted) return;
    container.invalidate(recipesProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removesForHousehold
              ? '"${recipe.title}" removed for your household.'
              : '"${recipe.title}" deleted from your recipes.',
        ),
      ),
    );
  } on PostgrestException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not remove recipe: ${error.message}'),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not remove recipe: $error')),
    );
  }
}

Future<void> _confirmAndRemoveHouseholdCopyOnly(
  BuildContext context,
  Recipe personalRecipe,
) async {
  if (!context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: const Text('Remove from household?'),
        content: Text(
          'Remove the shared household copy of "${personalRecipe.title}"? '
          'Everyone in your household will lose access to that copy. '
          'Your personal recipe stays in My Recipes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  final user = container.read(currentUserProvider);
  if (user == null) return;
  try {
    final repo = container.read(recipesRepositoryProvider);
    final deleted = await repo.deleteHouseholdCopyMatchingPersonal(
      userId: user.id,
      personalRecipeId: personalRecipe.id,
    );
    if (!context.mounted) return;
    container.invalidate(recipesProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Removed "${personalRecipe.title}" from Household Recipes.'
              : 'No matching household copy found. It may already be removed, or the title changed after sharing.',
        ),
      ),
    );
  } on PostgrestException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not remove household copy: ${error.message}'),
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not remove household copy: $error')),
    );
  }
}

bool _hasLikelyHouseholdCopyForPersonal({
  required Recipe personal,
  required List<Recipe> allRecipes,
  required String currentUserId,
}) {
  final t = personal.title.trim().toLowerCase();
  return allRecipes.any(
    (r) =>
        r.id != personal.id &&
        r.visibility == RecipeVisibility.household &&
        (r.userId ?? '') == currentUserId &&
        r.title.trim().toLowerCase() == t,
  );
}

void _showRecipeCollectionsSheet({
  required BuildContext anchorContext,
  required String recipeId,
  required bool hasSharedHousehold,
}) {
  showModalBottomSheet<void>(
    context: anchorContext,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _RecipeCollectionsSheet(
      anchorContext: anchorContext,
      recipeId: recipeId,
      hasSharedHousehold: hasSharedHousehold,
    ),
  );
}

class _RecipeCollectionsSheet extends ConsumerStatefulWidget {
  const _RecipeCollectionsSheet({
    required this.anchorContext,
    required this.recipeId,
    required this.hasSharedHousehold,
  });

  final BuildContext anchorContext;
  final String recipeId;
  final bool hasSharedHousehold;

  @override
  ConsumerState<_RecipeCollectionsSheet> createState() =>
      _RecipeCollectionsSheetState();
}

class _RecipeCollectionsSheetState
    extends ConsumerState<_RecipeCollectionsSheet> {
  bool _sharing = false;
  bool _removingHouseholdCopy = false;

  Future<void> _shareToHousehold(Recipe recipe) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _sharing = true);
    try {
      await ref.read(recipesRepositoryProvider).copyPersonalRecipeToHousehold(
            userId: user.id,
            recipeId: recipe.id,
          );
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Shared "${recipe.title}" to Household Recipes.'),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share recipe: ${error.message}'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share recipe: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _removeHouseholdCopyOnly(Recipe personalRecipe) async {
    if (_removingHouseholdCopy) return;
    setState(() => _removingHouseholdCopy = true);
    try {
      await _confirmAndRemoveHouseholdCopyOnly(
        widget.anchorContext,
        personalRecipe,
      );
    } finally {
      if (mounted) setState(() => _removingHouseholdCopy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final recipesAsync = ref.watch(recipesProvider);

    return recipesAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottom),
        child: Text('Could not load recipe: $e'),
      ),
      data: (recipes) {
        final recipe = recipes.firstWhereOrNull((r) => r.id == widget.recipeId);
        if (recipe == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }

        final canSharePersonal = widget.hasSharedHousehold &&
            recipe.visibility == RecipeVisibility.personal;
        final user = ref.watch(currentUserProvider);
        final hasLikelyHouseholdCopy = user != null &&
            recipe.visibility == RecipeVisibility.personal &&
            _hasLikelyHouseholdCopyForPersonal(
              personal: recipe,
              allRecipes: recipes,
              currentUserId: user.id,
            );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 16 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  'Lists & Sharing',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Turn each option on or off to choose where "${recipe.title}" '
                  'shows up. The recipe stays saved until you remove it permanently below.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              // 1. Household
              if (recipe.visibility == RecipeVisibility.household) ...[
                ListTile(
                  leading: Icon(Icons.home_outlined, color: scheme.primary),
                  title: const Text('Household'),
                  subtitle: const Text(
                    'This copy is shared with everyone in your household.',
                  ),
                ),
                SwitchListTile(
                  secondary:
                      Icon(Icons.favorite_outline, color: scheme.outline),
                  title: const Text('My Favorites'),
                  subtitle: const Text(
                    'When on, this recipe appears on Household Recipes. '
                    'Favorites on My Recipes lists only personal recipes — '
                    'keep a personal copy favorited if you want it there after removing the household copy.',
                  ),
                  value: recipe.isFavorite,
                  onChanged: (v) async {
                    await ref.read(recipesRepositoryProvider).toggleFavorite(
                          recipe.id,
                          v,
                        );
                    ref.invalidate(recipesProvider);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: Icon(Icons.home_outlined, color: scheme.primary),
                  title: const Text('Household'),
                  subtitle: Text(
                    canSharePersonal
                        ? 'Add a copy everyone in your household can open and cook from.'
                        : 'Create or join a household in Settings to share recipes.',
                  ),
                  trailing: canSharePersonal
                      ? (_sharing
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : FilledButton.tonal(
                              onPressed: () => _shareToHousehold(recipe),
                              child: const Text('Share'),
                            ))
                      : null,
                ),
                if (canSharePersonal && hasLikelyHouseholdCopy)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _removingHouseholdCopy
                          ? const SizedBox(
                              height: 36,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : TextButton(
                              onPressed: () => _removeHouseholdCopyOnly(recipe),
                              child: Text(
                                'Remove from household',
                                style: TextStyle(color: scheme.error),
                              ),
                            ),
                    ),
                  ),
                SwitchListTile(
                  secondary:
                      Icon(Icons.favorite_outline, color: scheme.outline),
                  title: const Text('My Favorites'),
                  subtitle: const Text(
                    'Show under Favorites on My Recipes.',
                  ),
                  value: recipe.isFavorite,
                  onChanged: (v) async {
                    await ref.read(recipesRepositoryProvider).toggleFavorite(
                          recipe.id,
                          v,
                        );
                    ref.invalidate(recipesProvider);
                  },
                ),
              ],
              // 3. To try (both personal and household rows can carry the flag)
              SwitchListTile(
                secondary: Icon(Icons.bookmark_outline, color: scheme.outline),
                title: const Text('To Try'),
                subtitle: Text(
                  recipe.visibility == RecipeVisibility.personal
                      ? 'Show under To Try on My Recipes.'
                      : 'Used in Planner and Discover. To Try on My Recipes lists only personal recipes.',
                ),
                value: recipe.isToTry,
                onChanged: (v) async {
                  await ref.read(recipesRepositoryProvider).toggleToTry(
                        recipe.id,
                        v,
                      );
                  ref.invalidate(recipesProvider);
                },
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  recipe.visibility == RecipeVisibility.household
                      ? 'Remove from household'
                      : 'Delete recipe',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  recipe.visibility == RecipeVisibility.household
                      ? 'This removes the shared recipe for every household member.'
                      : 'This deletes only this recipe row (your personal copy).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await Future<void>.delayed(Duration.zero);
                    if (!widget.anchorContext.mounted) return;
                    await _confirmAndDeleteRecipe(
                      widget.anchorContext,
                      recipe,
                    );
                  },
                  child: Text(
                    recipe.visibility == RecipeVisibility.household
                        ? 'Remove for everyone…'
                        : 'Delete my recipe permanently…',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecipeRow extends ConsumerWidget {
  const _RecipeRow({
    required this.recipe,
    required this.hasSharedHousehold,
    required this.isHouseholdLibrary,
    required this.onEditRecipe,
  });

  final Recipe recipe;
  final bool hasSharedHousehold;
  final bool isHouseholdLibrary;
  final Future<void> Function(Recipe recipe) onEditRecipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      !isHouseholdLibrary || recipe.visibility == RecipeVisibility.household,
      'Household library lists only household recipes.',
    );
    final tags = <String>[
      _mealTypeLabel(recipe.mealType),
      '${recipe.ingredients.length} ingredients',
      '${recipe.instructions.length} steps',
    ];

    Future<void> onMenuSelected(String value) async {
      if (value == 'manage_collections') {
        _showRecipeCollectionsSheet(
          anchorContext: context,
          recipeId: recipe.id,
          hasSharedHousehold: hasSharedHousehold,
        );
        return;
      }
      if (value == 'edit_recipe') {
        await onEditRecipe(recipe);
        return;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RecipeListCard(
        title: recipe.title,
        meta: '${_mealTypeLabel(recipe.mealType)} • Serves ${recipe.servings}',
        tags: recipe.cuisineTags.isEmpty
            ? tags
            : [recipe.cuisineTags.first, ...tags],
        onTap: () => context.push('/cooking/${recipe.id}'),
        trailing: PopupMenuButton<String>(
          tooltip: 'Recipe actions',
          onSelected: onMenuSelected,
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: 'edit_recipe',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined),
                  SizedBox(width: 8),
                  Text('Edit recipe'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'manage_collections',
              child: Row(
                children: [
                  Icon(Icons.library_books_outlined),
                  SizedBox(width: 8),
                  Text('Lists & Sharing'),
                ],
              ),
            ),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.more_vert_rounded),
          ),
        ),
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

const double _kAmountEpsilon = 1e-9;

class _PresetAmountChip {
  const _PresetAmountChip({required this.label, required this.canonicalText});
  final String label;
  final String canonicalText;
}

const _presetAmountChips = [
  _PresetAmountChip(label: '¼', canonicalText: '1/4'),
  _PresetAmountChip(label: '⅓', canonicalText: '1/3'),
  _PresetAmountChip(label: '½', canonicalText: '1/2'),
  _PresetAmountChip(label: '1', canonicalText: '1'),
];

const _kQualitativePresets = [
  'to taste',
  'as needed',
  'pinch',
  '1 tsp',
  '1 tbsp',
  '½ tsp',
];

class _IngredientInput {
  _IngredientInput({
    required String name,
    required List<String> unitOptions,
    required this.selectedUnit,
    String? customUnit,
    String? reorderId,
    bool qualitative = false,
    String qualitativePhrase = '',
  })  : unitOptions = List<String>.from(unitOptions),
        reorderId = reorderId ?? 'ing_${_nextReorderId++}' {
    nameCtrl.text = name;
    if (customUnit != null) {
      customUnitCtrl.text = customUnit;
    }
    this.qualitative = qualitative;
    if (qualitative) {
      final t = qualitativePhrase.trim();
      if (t.isEmpty) {
        qualitativePreset = 'to taste';
      } else if (_kQualitativePresets.contains(t)) {
        qualitativePreset = t;
      } else {
        qualitativePreset = 'custom';
        qualitativeCustomCtrl.text = t;
      }
    }
  }

  static int _nextReorderId = 0;

  final String reorderId;
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController customUnitCtrl = TextEditingController();
  final TextEditingController qualitativeCustomCtrl = TextEditingController();
  List<String> unitOptions;
  String selectedUnit;

  bool qualitative = false;
  String qualitativePreset = 'to taste';

  final FocusNode nameFocusNode = FocusNode();
  final FocusNode amountFocusNode = FocusNode();
  final FocusNode qualitativeCustomFocusNode = FocusNode();
  final FocusNode customUnitFocusNode = FocusNode();

  /// True after the user chose a name from the grocery suggestion grid.
  bool namePickedFromSuggestions = false;

  String get name => nameCtrl.text.trim();

  String resolvedQualitativePhrase() {
    if (!qualitative) return '';
    if (qualitativePreset == 'custom') {
      return qualitativeCustomCtrl.text.trim();
    }
    return qualitativePreset;
  }

  void dispose() {
    nameFocusNode.dispose();
    amountFocusNode.dispose();
    qualitativeCustomFocusNode.dispose();
    customUnitFocusNode.dispose();
    nameCtrl.dispose();
    amountCtrl.dispose();
    customUnitCtrl.dispose();
    qualitativeCustomCtrl.dispose();
  }
}

class _UnitProfile {
  const _UnitProfile({required this.options, required this.defaultUnit});

  final List<String> options;
  final String defaultUnit;
}

class _DirectionDraft {
  _DirectionDraft({String? text}) {
    if (text != null) textCtrl.text = text;
  }

  final TextEditingController textCtrl = TextEditingController();

  void dispose() {
    textCtrl.dispose();
  }
}

/// Scrolls the expanded ingredient card into view when any of its fields focus
/// so the full card stays above the keyboard.
class _IngredientCardScrollIntoView extends StatefulWidget {
  const _IngredientCardScrollIntoView({
    required this.focusNodes,
    required this.cardKey,
    required this.child,
  });

  final List<FocusNode> focusNodes;
  final GlobalKey cardKey;
  final Widget child;

  @override
  State<_IngredientCardScrollIntoView> createState() =>
      _IngredientCardScrollIntoViewState();
}

class _IngredientCardScrollIntoViewState
    extends State<_IngredientCardScrollIntoView> {
  void _onAnyFocusNodeChanged() {
    if (!widget.focusNodes.any((n) => n.hasFocus)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.focusNodes.any((n) => n.hasFocus)) return;
      final ctx = widget.cardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.08,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    for (final n in widget.focusNodes) {
      n.addListener(_onAnyFocusNodeChanged);
    }
  }

  @override
  void dispose() {
    for (final n in widget.focusNodes) {
      n.removeListener(_onAnyFocusNodeChanged);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _IngredientCardScrollIntoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.focusNodes, widget.focusNodes)) return;
    for (final n in oldWidget.focusNodes) {
      n.removeListener(_onAnyFocusNodeChanged);
    }
    for (final n in widget.focusNodes) {
      n.addListener(_onAnyFocusNodeChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: widget.cardKey,
      child: widget.child,
    );
  }
}

class _RecipeBuilderSheet extends ConsumerStatefulWidget {
  const _RecipeBuilderSheet({this.initialRecipe});

  final Recipe? initialRecipe;

  @override
  ConsumerState<_RecipeBuilderSheet> createState() =>
      _RecipeBuilderSheetState();
}

class _RecipeBuilderSheetState extends ConsumerState<_RecipeBuilderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _stepCtrl = PageController();
  final _titleCtrl = TextEditingController();
  final _servingsCtrl = TextEditingController(text: '2');
  final _tagCtrl = TextEditingController();
  final _titleFocusNode = FocusNode();
  final GlobalKey _ingredientExpandedCardKey = GlobalKey();
  String? _lastAddedIngredientReorderId;
  final List<String> _cuisineTags = [];
  final List<String> _presetCuisines = const [
    'Italian',
    'Chinese',
    'American',
    'Mexican',
    'Indian',
    'Mediterranean',
    'Japanese',
    'Thai',
  ];
  final List<_IngredientInput> _ingredients = [];
  final List<_DirectionDraft> _directionDrafts = [_DirectionDraft()];
  MealType _mealType = MealType.entree;
  bool _markFavorite = false;
  bool _markToTry = false;
  bool _makePublic = false;
  bool _saveToHousehold = false;
  bool _showCustomTag = false;
  int _step = 0;
  String? _validationMessage;
  bool _isSubmitting = false;
  int? _selectedIngredientIndex;
  int? _selectedDirectionIndex = 0;

  static const int _kNutritionStepIndex = 4;

  Nutrition _estimatedNutrition = const Nutrition();
  String? _nutritionEstimateSource;
  bool _nutritionLoading = false;
  String? _nutritionError;
  String? _loadedNutritionFingerprint;
  List<IngredientNutritionBreakdownLine> _nutritionBreakdown = const [];
  bool _nutritionShowPerServing = false;

  void _onEditFormControllerChanged() {
    if (!mounted) return;
    if (widget.initialRecipe != null) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _hydrateFromInitialRecipe();
    if (widget.initialRecipe != null) {
      _titleCtrl.addListener(_onEditFormControllerChanged);
      _servingsCtrl.addListener(_onEditFormControllerChanged);
      _tagCtrl.addListener(_onEditFormControllerChanged);
    }
    unawaited(ref.read(groceryRepositoryProvider).ensureCatalogLoaded());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recipeCreationGuardProvider.notifier).open();
      ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
      _titleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    if (widget.initialRecipe != null) {
      _titleCtrl.removeListener(_onEditFormControllerChanged);
      _servingsCtrl.removeListener(_onEditFormControllerChanged);
      _tagCtrl.removeListener(_onEditFormControllerChanged);
    }
    _stepCtrl.dispose();
    _titleCtrl.dispose();
    _servingsCtrl.dispose();
    _tagCtrl.dispose();
    _titleFocusNode.dispose();
    for (final ingredient in _ingredients) {
      ingredient.dispose();
    }
    for (final direction in _directionDrafts) {
      direction.dispose();
    }
    super.dispose();
  }

  void _hydrateFromInitialRecipe() {
    final initial = widget.initialRecipe;
    if (initial == null) return;
    final system = ref.read(measurementSystemProvider);
    _titleCtrl.text = initial.title;
    _servingsCtrl.text = '${initial.servings}';
    _mealType = initial.mealType;
    _cuisineTags
      ..clear()
      ..addAll(initial.cuisineTags);
    _markFavorite = initial.isFavorite;
    _markToTry = initial.isToTry;
    _makePublic = initial.visibility == RecipeVisibility.public;
    // Must match initial visibility or saves use defaults (e.g. _saveToHousehold
    // false → personal) while user_id stays the owner, which violates RLS for
    // non-owners updating household recipes.
    _saveToHousehold = initial.visibility == RecipeVisibility.household;
    _ingredients.clear();
    for (final ingredient in initial.ingredients) {
      if (ingredient.qualitative) {
        final profile = _detectUnitProfile(ingredient.name, system);
        _ingredients.add(
          _IngredientInput(
            name: ingredient.name,
            unitOptions: profile.options,
            selectedUnit: profile.defaultUnit,
            qualitative: true,
            qualitativePhrase: ingredient.unit,
          ),
        );
        continue;
      }
      final profile = _detectUnitProfile(ingredient.name, system);
      final normalizedUnit = ingredient.unit.trim().toLowerCase();
      final isCustom = !profile.options.contains(normalizedUnit);
      // profile.options already ends with 'custom'; do not append again or the
      // unit dropdown gets duplicate values and DropdownButtonFormField asserts.
      final units = [...profile.options];
      final row = _IngredientInput(
        name: ingredient.name,
        unitOptions: units,
        selectedUnit: isCustom ? 'custom' : normalizedUnit,
        customUnit: isCustom ? ingredient.unit : null,
      );
      row.amountCtrl.text = formatIngredientAmount(ingredient.amount);
      _ingredients.add(row);
    }
    _selectedIngredientIndex = _ingredients.isEmpty ? null : 0;
    _lastAddedIngredientReorderId = null;
    _estimatedNutrition = initial.nutrition;
    _nutritionEstimateSource = initial.nutritionSource;
    _nutritionBreakdown = const [];
    for (final draft in _directionDrafts) {
      draft.dispose();
    }
    _directionDrafts
      ..clear()
      ..addAll(
        initial.instructions.isEmpty
            ? [_DirectionDraft()]
            : initial.instructions.map((step) => _DirectionDraft(text: step)),
      );
    _selectedDirectionIndex = _directionDrafts.isEmpty ? null : 0;
  }

  void _closeWizard([Recipe? recipe]) {
    ref.read(recipeCreationGuardProvider.notifier).close();
    Navigator.of(context).pop(recipe);
  }

  Future<void> _confirmClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard recipe?'),
        content: const Text(
          'Your changes have not been saved and will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) _closeWizard();
  }

  int? _parseIntOrNull(String value) {
    if (value.trim().isEmpty) return null;
    return int.tryParse(value.trim());
  }

  void _addCuisineTag() {
    final raw = _tagCtrl.text.trim();
    if (raw.isEmpty) return;
    if (_cuisineTags.any((e) => e.toLowerCase() == raw.toLowerCase())) {
      _tagCtrl.clear();
      return;
    }
    setState(() {
      _cuisineTags.add(raw);
      _tagCtrl.clear();
    });
  }

  void _toggleCuisinePreset(String cuisine) {
    setState(() {
      if (_cuisineTags.contains(cuisine)) {
        _cuisineTags.remove(cuisine);
      } else {
        _cuisineTags.add(cuisine);
      }
      _validationMessage = null;
    });
  }

  void _incrementServings() {
    final current = int.tryParse(_servingsCtrl.text.trim()) ?? 1;
    _servingsCtrl.text = '${current + 1}';
    setState(() {});
  }

  void _decrementServings() {
    final current = int.tryParse(_servingsCtrl.text.trim()) ?? 1;
    final next = current <= 1 ? 1 : current - 1;
    _servingsCtrl.text = '$next';
    setState(() {});
  }

  _UnitProfile _detectUnitProfile(String ingredientName, MeasurementSystem system) {
    final lower = ingredientName.toLowerCase();
    const liquidWords = [
      'milk',
      'oil',
      'broth',
      'sauce',
      'water',
      'juice',
      'vinegar',
      'stock'
    ];
    const powderWords = [
      'flour',
      'sugar',
      'salt',
      'pepper',
      'paprika',
      'cumin',
      'spice'
    ];
    if (liquidWords.any(lower.contains)) {
      return switch (system) {
        MeasurementSystem.metric => const _UnitProfile(
            options: ['ml', 'l', 'tsp', 'tbsp', 'custom'],
            defaultUnit: 'ml',
          ),
        MeasurementSystem.imperial => const _UnitProfile(
            options: [
              'fl oz',
              'cup',
              'tbsp',
              'tsp',
              'pt',
              'qt',
              'gal',
              'custom',
            ],
            defaultUnit: 'fl oz',
          ),
      };
    }
    if (powderWords.any(lower.contains)) {
      return switch (system) {
        MeasurementSystem.metric => const _UnitProfile(
            options: ['tsp', 'tbsp', 'g', 'kg', 'mg', 'custom'],
            defaultUnit: 'tsp',
          ),
        MeasurementSystem.imperial => const _UnitProfile(
            options: ['tsp', 'tbsp', 'oz', 'cup', 'custom'],
            defaultUnit: 'tsp',
          ),
      };
    }
    return switch (system) {
      MeasurementSystem.metric => const _UnitProfile(
          options: ['g', 'kg', 'mg', 'ml', 'l', 'tsp', 'tbsp', 'piece', 'custom'],
          defaultUnit: 'g',
        ),
      MeasurementSystem.imperial => const _UnitProfile(
          options: [
            'oz',
            'lb',
            'fl oz',
            'cup',
            'tbsp',
            'tsp',
            'pt',
            'qt',
            'gal',
            'piece',
            'custom',
          ],
          defaultUnit: 'oz',
        ),
    };
  }

  String? _matchUnitOption(List<String> options, String unit) {
    final t = unit.trim().toLowerCase();
    for (final o in options) {
      if (o.toLowerCase() == t) return o;
    }
    return null;
  }

  void _applyMeasurementSystem(MeasurementSystem next) {
    ref.read(measurementSystemProvider.notifier).setSystem(next);
    setState(() {
      for (final row in _ingredients) {
        final profile = _detectUnitProfile(row.nameCtrl.text, next);
        row.unitOptions
          ..clear()
          ..addAll(profile.options);
        if (row.qualitative) continue;
        final amt = _parseIngredientAmount(row.amountCtrl.text);
        final unit = row.selectedUnit == 'custom'
            ? row.customUnitCtrl.text.trim()
            : row.selectedUnit;
        if (amt == null || unit.isEmpty) continue;
        final conv = convertAmountAndUnitForMeasurementSystem(
          amount: amt,
          unitRaw: unit,
          target: next,
        );
        if (conv != null) {
          final matched = _matchUnitOption(row.unitOptions, conv.unit);
          if (matched != null) {
            row.selectedUnit = matched;
            row.customUnitCtrl.clear();
          } else {
            row.selectedUnit = 'custom';
            row.customUnitCtrl.text = conv.unit;
          }
          row.amountCtrl.text = formatIngredientAmount(conv.amount);
        } else {
          final matched = _matchUnitOption(row.unitOptions, unit);
          if (matched != null) {
            row.selectedUnit = matched;
            row.customUnitCtrl.clear();
          } else {
            row.selectedUnit = 'custom';
            row.customUnitCtrl.text = unit;
          }
        }
      }
    });
  }

  /// Rebuilds the recipe sheet and, when open, the ingredients dialog overlay.
  void _notifyIngredientUi(StateSetter? dialogSetState, VoidCallback fn) {
    setState(fn);
    dialogSetState?.call(() {});
  }

  bool _isIngredientRowComplete(_IngredientInput row) {
    if (row.nameCtrl.text.trim().isEmpty) return false;
    if (row.qualitative) {
      return row.resolvedQualitativePhrase().isNotEmpty;
    }
    if (row.amountCtrl.text.trim().isEmpty) return false;
    if (_parseIngredientAmount(row.amountCtrl.text) == null) return false;
    if (row.selectedUnit.trim().isEmpty) return false;
    if (row.selectedUnit == 'custom' &&
        row.customUnitCtrl.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  void _removeIngredientAt(int idx, [StateSetter? dialogSetState]) {
    setState(() {
      final removed = _ingredients.removeAt(idx);
      if (_lastAddedIngredientReorderId == removed.reorderId) {
        _lastAddedIngredientReorderId = null;
      }
      removed.dispose();
      _validationMessage = null;
      if (_ingredients.isEmpty) {
        _selectedIngredientIndex = null;
      } else if (_selectedIngredientIndex != null) {
        final sel = _selectedIngredientIndex!;
        if (idx < sel) {
          _selectedIngredientIndex = sel - 1;
        } else if (idx == sel) {
          _selectedIngredientIndex = idx.clamp(0, _ingredients.length - 1);
        }
      }
    });
    dialogSetState?.call(() {});
  }

  /// First ingredient can always be added; further rows require the row last
  /// added (or every row when editing an existing recipe) to be complete.
  bool get _canAddAnotherIngredient {
    if (_ingredients.isEmpty) return true;
    final rid = _lastAddedIngredientReorderId;
    if (rid != null) {
      final idx = _ingredients.indexWhere((e) => e.reorderId == rid);
      if (idx >= 0) {
        return _isIngredientRowComplete(_ingredients[idx]);
      }
    }
    return _ingredients.every(_isIngredientRowComplete);
  }

  String _ingredientSummary(_IngredientInput row) {
    final name = row.nameCtrl.text.trim().isEmpty
        ? 'New ingredient'
        : row.nameCtrl.text.trim();
    if (row.qualitative) {
      final q = row.resolvedQualitativePhrase();
      return q.isEmpty ? name : '$name · $q';
    }
    final amt = row.amountCtrl.text.trim();
    final unitStr = row.selectedUnit == 'custom'
        ? row.customUnitCtrl.text.trim()
        : row.selectedUnit;
    if (amt.isEmpty) return name;
    if (unitStr.isEmpty) return '$name · $amt';
    return '$name · $amt $unitStr';
  }

  /// Pill-shaped rose chip for saved ingredients on the wizard step (matches prior condensed style).
  Widget _buildIngredientSavedChip(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final row = _ingredients[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _editIngredientAt(i),
          child: Ink(
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8EE),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFFE8A8B8),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 4, top: 8, bottom: 8),
              child: Row(
                children: [
                  row.namePickedFromSuggestions && row.name.isNotEmpty
                      ? _ingredientPickedFoodIcon(context, row, size: 22)
                      : Icon(
                          Icons.restaurant_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _ingredientSummary(row),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  IconButton(
                    onPressed: () => _removeIngredientAt(i),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedIngredientRow(
    BuildContext context,
    int idx,
    _IngredientInput row, {
    StateSetter? dialogSetState,
    VoidCallback? onRemovePressed,
    EdgeInsetsGeometry cardMargin =
        const EdgeInsets.only(bottom: AppSpacing.sm),
  }) {
    final scheme = Theme.of(context).colorScheme;
    final qualitativeDropdownValue =
        _kQualitativePresets.contains(row.qualitativePreset)
            ? row.qualitativePreset
            : 'custom';
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final suggestionGridMaxHeight = keyboardBottom > 0 ? 130.0 : 230.0;
    final fieldScrollPadding = EdgeInsets.fromLTRB(
      20,
      20,
      20,
      keyboardBottom + 80,
    );
    return _IngredientCardScrollIntoView(
      focusNodes: [
        row.nameFocusNode,
        row.amountFocusNode,
        row.qualitativeCustomFocusNode,
        row.customUnitFocusNode,
      ],
      cardKey: _ingredientExpandedCardKey,
      child: Container(
        margin: cardMargin,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.primary,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: row.nameCtrl,
                        focusNode: row.nameFocusNode,
                        textCapitalization: TextCapitalization.sentences,
                        scrollPadding: fieldScrollPadding,
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: _ingredientInputDecoration(
                          context,
                          hintText: 'Ingredient name',
                          hintStyle:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                          borderOpacity: 0.2,
                          prefixIcon: row.namePickedFromSuggestions &&
                                  row.name.isNotEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: 1,
                                    child: _ingredientPickedFoodIcon(
                                      context,
                                      row,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        onChanged: (_) => _notifyIngredientUi(dialogSetState, () {
                          row.namePickedFromSuggestions = false;
                        }),
                      ),
                      if (!row.qualitative)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: GroceryItemSuggestionsGrid(
                            repo: ref.read(groceryRepositoryProvider),
                            typedValue: row.nameCtrl.text,
                            recentItems: const [],
                            maxHeight: suggestionGridMaxHeight,
                            onPick: (suggestion) {
                              _notifyIngredientUi(dialogSetState, () {
                                row.nameCtrl.text = suggestion;
                                row.namePickedFromSuggestions = true;
                              });
                              row.nameFocusNode.unfocus();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    if (onRemovePressed != null) {
                      onRemovePressed();
                    } else {
                      _removeIngredientAt(idx, dialogSetState);
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Remove ingredient',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<bool>(
              emptySelectionAllowed: false,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Measure'),
                  icon: Icon(Icons.scale_outlined, size: 18),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('To taste'),
                  icon: Icon(Icons.spa_outlined, size: 18),
                ),
              ],
              selected: {row.qualitative},
              onSelectionChanged: (next) {
                _notifyIngredientUi(dialogSetState, () {
                  row.qualitative = next.first;
                });
              },
            ),
            if (row.qualitative) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: qualitativeDropdownValue,
                isExpanded: true,
                decoration: _ingredientInputDecoration(
                  context,
                  labelText: 'Amount',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  borderOpacity: 0.2,
                ),
                items: [
                  ..._kQualitativePresets.map(
                    (p) => DropdownMenuItem<String>(
                      value: p,
                      child: Text(p),
                    ),
                  ),
                  const DropdownMenuItem<String>(
                    value: 'custom',
                    child: Text('Custom…'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _notifyIngredientUi(dialogSetState, () {
                    row.qualitativePreset = value;
                  });
                },
              ),
              if (row.qualitativePreset == 'custom') ...[
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: row.qualitativeCustomCtrl,
                  focusNode: row.qualitativeCustomFocusNode,
                  textCapitalization: TextCapitalization.sentences,
                  scrollPadding: fieldScrollPadding,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: _ingredientInputDecoration(
                    context,
                    hintText: 'e.g. 1½ tsp',
                    borderOpacity: 0.2,
                  ),
                  onChanged: (_) =>
                      _notifyIngredientUi(dialogSetState, () {}),
                ),
              ],
            ] else ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Amount',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final preset in _presetAmountChips)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            preset.label,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.1,
                            ),
                          ),
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          selected: _isPresetAmountSelected(
                            row,
                            preset.canonicalText,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          onSelected: (selected) {
                            _notifyIngredientUi(dialogSetState, () {
                              if (selected) {
                                row.amountCtrl.text = preset.canonicalText;
                              }
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: TextField(
                      controller: row.amountCtrl,
                      focusNode: row.amountFocusNode,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      scrollPadding: fieldScrollPadding,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      decoration: _ingredientInputDecoration(
                        context,
                        hintText: 'Enter amount',
                        hintStyle:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w400,
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.5),
                                ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        borderOpacity: 0.2,
                      ),
                      onChanged: (_) =>
                          _notifyIngredientUi(dialogSetState, () {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: row.unitOptions.contains(row.selectedUnit)
                          ? row.selectedUnit
                          : row.unitOptions.first,
                      isDense: true,
                      isExpanded: true,
                      decoration: _ingredientInputDecoration(
                        context,
                        labelText: 'Unit',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        borderOpacity: 0.2,
                      ),
                      items: row.unitOptions
                          .map(
                            (unit) => DropdownMenuItem(
                              value: unit,
                              child: Text(unit),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        _notifyIngredientUi(dialogSetState, () {
                          row.selectedUnit = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (row.selectedUnit == 'custom') ...[
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: row.customUnitCtrl,
                  focusNode: row.customUnitFocusNode,
                  textCapitalization: TextCapitalization.sentences,
                  scrollPadding: fieldScrollPadding,
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  decoration: _ingredientInputDecoration(
                    context,
                    labelText: 'Custom unit',
                    hintText: 'e.g. clove, pinch, can',
                    borderOpacity: 0.2,
                  ),
                  onChanged: (_) =>
                      _notifyIngredientUi(dialogSetState, () {}),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _removeDirectionAt(int idx) {
    if (_directionDrafts.length <= 1) return;
    setState(() {
      final removed = _directionDrafts.removeAt(idx);
      removed.dispose();
      _validationMessage = null;
      if (_selectedDirectionIndex != null) {
        final sel = _selectedDirectionIndex!;
        if (idx < sel) {
          _selectedDirectionIndex = sel - 1;
        } else if (idx == sel) {
          _selectedDirectionIndex = idx.clamp(0, _directionDrafts.length - 1);
        }
      }
    });
  }

  void _addDirectionStep() {
    if (!_canAddAnotherDirection) return;
    setState(() {
      _directionDrafts.add(_DirectionDraft());
      _selectedDirectionIndex = _directionDrafts.length - 1;
      _validationMessage = null;
    });
  }

  bool get _canAddAnotherDirection {
    if (_directionDrafts.isEmpty) return true;
    final last = _directionDrafts.last;
    return last.textCtrl.text.trim().isNotEmpty;
  }

  String _directionSummary(_DirectionDraft draft) {
    final t = draft.textCtrl.text.trim();
    if (t.isEmpty) return 'New step';
    return t;
  }

  static const double _kDirectionFieldBorderRadius = 14;
  static const double _kIngredientFieldBorderRadius = 14;

  InputDecoration _ingredientInputDecoration(
    BuildContext context, {
    String? labelText,
    String? hintText,
    TextStyle? hintStyle,
    EdgeInsetsGeometry contentPadding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    double borderOpacity = 1.0,
    Widget? prefixIcon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = scheme.primary.withValues(alpha: borderOpacity);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kIngredientFieldBorderRadius),
      borderSide: BorderSide(color: borderColor, width: 1.2),
    );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      labelText: labelText,
      hintText: hintText,
      hintStyle: hintStyle,
      isDense: true,
      contentPadding: contentPadding,
      prefixIcon: prefixIcon,
      prefixIconConstraints: prefixIcon == null
          ? null
          : const BoxConstraints(minWidth: 40, minHeight: 32),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
    );
  }

  IconData _groceryCategoryIcon(GroceryCategory category) {
    return switch (category) {
      GroceryCategory.produce => Icons.eco_rounded,
      GroceryCategory.meatFish => Icons.set_meal_rounded,
      GroceryCategory.dairyEggs => Icons.egg_alt_rounded,
      GroceryCategory.pantryGrains => Icons.rice_bowl_rounded,
      GroceryCategory.bakery => Icons.bakery_dining_rounded,
      GroceryCategory.other => Icons.shopping_bag_rounded,
    };
  }

  Widget _ingredientPickedFoodIcon(
    BuildContext context,
    _IngredientInput row, {
    double size = 24,
  }) {
    final repo = ref.read(groceryRepositoryProvider);
    final name = row.nameCtrl.text.trim();
    if (name.isEmpty) {
      return SizedBox(width: size, height: size);
    }
    final category = repo.categorize(name);
    final asset = foodIconAssetForName(name, category: category);
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    if (asset != null) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Icon(
          _groceryCategoryIcon(category),
          size: size,
          color: color,
        ),
      );
    }
    return Icon(
      _groceryCategoryIcon(category),
      size: size,
      color: color,
    );
  }

  InputDecoration _directionInstructionDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kDirectionFieldBorderRadius),
      borderSide: BorderSide(color: primary, width: 1.2),
    );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      labelText: 'Instruction',
      hintText: 'Describe what to do for this step',
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
    );
  }

  Widget _buildCondensedDirectionRow(
    BuildContext context,
    int idx,
    _DirectionDraft draft,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => setState(() => _selectedDirectionIndex = idx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.format_list_numbered_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Step ${idx + 1}: ${_directionSummary(draft)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                IconButton(
                  onPressed: () => _removeDirectionAt(idx),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDirectionRow(
    BuildContext context,
    int idx,
    _DirectionDraft draft,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Step ${idx + 1}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const Spacer(),
              if (_directionDrafts.length > 1)
                IconButton(
                  onPressed: () => _removeDirectionAt(idx),
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Remove step',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: draft.textCtrl,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            decoration: _directionInstructionDecoration(context),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  double? _parseIngredientAmount(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    final slash = RegExp(r'^\s*(\d+)\s*/\s*(\d+)\s*$').firstMatch(s);
    if (slash != null) {
      final n = int.tryParse(slash.group(1)!);
      final d = int.tryParse(slash.group(2)!);
      if (n != null && d != null && d != 0) return n / d;
    }
    return null;
  }

  List<String> _ingredientLinesForNutrition() {
    final ingredients = <Ingredient>[];
    for (final row in _ingredients) {
      if (row.name.trim().isEmpty) continue;
      if (row.qualitative) {
        final q = row.resolvedQualitativePhrase();
        if (q.isEmpty) continue;
        ingredients.add(
          Ingredient(
            name: row.name,
            amount: 0,
            unit: q,
            category: GroceryCategory.other,
            qualitative: true,
          ),
        );
        continue;
      }
      final amt = _parseIngredientAmount(row.amountCtrl.text);
      final unit = row.selectedUnit == 'custom'
          ? row.customUnitCtrl.text.trim()
          : row.selectedUnit;
      if (amt == null || unit.trim().isEmpty) continue;
      ingredients.add(
        Ingredient(
          name: row.name,
          amount: amt,
          unit: unit,
          category: GroceryCategory.other,
        ),
      );
    }
    return ingredientLinesFromIngredients(ingredients);
  }

  String _computeNutritionFingerprint() {
    final servings = _parseIntOrNull(_servingsCtrl.text) ?? 2;
    final lines = _ingredientLinesForNutrition();
    return '$servings|\u001e${lines.join('\u001e')}';
  }

  void _scheduleNutritionSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _step != _kNutritionStepIndex) return;
      unawaited(_syncNutritionEstimate());
    });
  }

  Future<void> _syncNutritionEstimate() async {
    final fp = _computeNutritionFingerprint();
    if (fp == _loadedNutritionFingerprint && _nutritionError == null) {
      return;
    }
    final lines = _ingredientLinesForNutrition();
    if (lines.isEmpty) {
      setState(() {
        _nutritionLoading = false;
        _nutritionError =
            'Add ingredients with amounts on the ingredients step.';
        _estimatedNutrition = const Nutrition();
        _nutritionEstimateSource = null;
        _nutritionBreakdown = const [];
      });
      return;
    }
    if (!Env.hasFdc && !Env.hasGemini) {
      setState(() {
        _nutritionLoading = false;
        _nutritionError = null;
        _estimatedNutrition = const Nutrition();
        _nutritionEstimateSource = null;
        _loadedNutritionFingerprint = fp;
        _nutritionBreakdown = const [];
      });
      return;
    }
    setState(() {
      _nutritionLoading = true;
      _nutritionError = null;
      _nutritionBreakdown = const [];
    });
    try {
      final result = await estimateNutritionWithFallback(
        foodDataCentral: ref.read(foodDataCentralServiceProvider),
        cacheRepository: ref.read(ingredientNutritionCacheRepositoryProvider),
        gemini: ref.read(geminiServiceProvider),
        ingredientLines: lines,
        servings: _parseIntOrNull(_servingsCtrl.text) ?? 2,
      );
      if (!mounted) return;
      setState(() {
        _estimatedNutrition = result.nutrition;
        _nutritionEstimateSource = result.source;
        _nutritionLoading = false;
        _nutritionError = null;
        _loadedNutritionFingerprint = fp;
        _nutritionBreakdown = result.breakdown;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nutritionLoading = false;
        _nutritionError =
            'Could not estimate nutrition. Check your connection and try again.';
        _nutritionBreakdown = const [];
      });
    }
  }

  bool _isPresetAmountSelected(_IngredientInput row, String canonical) {
    final a = _parseIngredientAmount(row.amountCtrl.text);
    final b = _parseIngredientAmount(canonical);
    if (a == null || b == null) return false;
    return (a - b).abs() < _kAmountEpsilon;
  }

  bool _validateCurrentStep() {
    if (_step == 0) {
      if ((_formKey.currentState?.validate() ?? false) == false) {
        return false;
      }
      if (_titleCtrl.text.trim().isEmpty) {
        setState(() => _validationMessage = 'Recipe name is required.');
        return false;
      }
    }

    if (_step == 1) {
      final servings = int.tryParse(_servingsCtrl.text.trim());
      if (servings == null || servings < 1) {
        setState(() => _validationMessage = 'Serving size must be at least 1.');
        return false;
      }
    }

    if (_step == 2) {
      if (_ingredients.isEmpty) {
        setState(() => _validationMessage = 'Add at least one ingredient.');
        return false;
      }
      final hasIssue = _ingredients.any((row) {
        if (row.nameCtrl.text.trim().isEmpty) return true;
        if (row.qualitative) {
          return row.resolvedQualitativePhrase().isEmpty;
        }
        return row.amountCtrl.text.trim().isEmpty ||
            _parseIngredientAmount(row.amountCtrl.text) == null ||
            row.selectedUnit.trim().isEmpty ||
            (row.selectedUnit == 'custom' &&
                row.customUnitCtrl.text.trim().isEmpty);
      });
      if (hasIssue) {
        setState(() => _validationMessage =
            'Each ingredient needs a name and a valid amount (or To taste).');
        return false;
      }
    }

    if (_step == 3) {
      final stepCount = _directionDrafts
          .map((d) => d.textCtrl.text.trim())
          .where((text) => text.isNotEmpty)
          .length;
      if (stepCount == 0) {
        setState(() => _validationMessage = 'Add at least one direction step.');
        return false;
      }
    }

    setState(() => _validationMessage = null);
    return true;
  }

  /// Full validation for persisted recipe (steps 0–3). Used when saving an edit
  /// from any step, including early Save.
  bool _validateAllStepsForSave() {
    if ((_formKey.currentState?.validate() ?? false) == false) {
      return false;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _validationMessage = 'Recipe name is required.');
      return false;
    }
    final servings = int.tryParse(_servingsCtrl.text.trim());
    if (servings == null || servings < 1) {
      setState(() => _validationMessage = 'Serving size must be at least 1.');
      return false;
    }
    if (_ingredients.isEmpty) {
      setState(() => _validationMessage = 'Add at least one ingredient.');
      return false;
    }
    final hasIssue = _ingredients.any((row) {
      if (row.nameCtrl.text.trim().isEmpty) return true;
      if (row.qualitative) {
        return row.resolvedQualitativePhrase().isEmpty;
      }
      return row.amountCtrl.text.trim().isEmpty ||
          _parseIngredientAmount(row.amountCtrl.text) == null ||
          row.selectedUnit.trim().isEmpty ||
          (row.selectedUnit == 'custom' &&
              row.customUnitCtrl.text.trim().isEmpty);
    });
    if (hasIssue) {
      setState(() => _validationMessage =
          'Each ingredient needs a name and a valid amount (or To taste).');
      return false;
    }
    final stepCount = _directionDrafts
        .map((d) => d.textCtrl.text.trim())
        .where((text) => text.isNotEmpty)
        .length;
    if (stepCount == 0) {
      setState(() => _validationMessage = 'Add at least one direction step.');
      return false;
    }
    setState(() => _validationMessage = null);
    return true;
  }

  static const double _kNutritionEpsilon = 1e-6;

  bool _nutritionPersistedEquals(Nutrition a, Nutrition b) {
    if (a.calories != b.calories) return false;
    return (a.protein - b.protein).abs() < _kNutritionEpsilon &&
        (a.fat - b.fat).abs() < _kNutritionEpsilon &&
        (a.carbs - b.carbs).abs() < _kNutritionEpsilon &&
        (a.fiber - b.fiber).abs() < _kNutritionEpsilon &&
        (a.sugar - b.sugar).abs() < _kNutritionEpsilon;
  }

  bool _ingredientPersistedEquals(Ingredient a, Ingredient b) {
    if (a.name != b.name) return false;
    if (a.qualitative != b.qualitative) return false;
    if (a.unit != b.unit) return false;
    if (a.category != b.category) return false;
    if ((a.amount - b.amount).abs() > _kAmountEpsilon) return false;
    if (a.fdcId != b.fdcId) return false;
    if ((a.fdcDescription ?? '') != (b.fdcDescription ?? '')) return false;
    if (a.fdcNutritionEstimated != b.fdcNutritionEstimated) return false;
    if (a.fdcTypicalAverage != b.fdcTypicalAverage) return false;
    final lnA = a.lineNutrition;
    final lnB = b.lineNutrition;
    if (lnA == null && lnB == null) return true;
    if (lnA == null || lnB == null) return false;
    return _nutritionPersistedEquals(lnA, lnB);
  }

  bool _persistedRecipesEqual(Recipe draft, Recipe baseline) {
    if (draft.title != baseline.title) return false;
    if (draft.servings != baseline.servings) return false;
    if (draft.mealType != baseline.mealType) return false;
    final da = [...draft.cuisineTags]..sort();
    final db = [...baseline.cuisineTags]..sort();
    if (!const ListEquality<String>().equals(da, db)) return false;
    if (!const ListEquality<String>()
        .equals(draft.instructions, baseline.instructions)) {
      return false;
    }
    if (draft.ingredients.length != baseline.ingredients.length) return false;
    for (var i = 0; i < draft.ingredients.length; i++) {
      if (!_ingredientPersistedEquals(
          draft.ingredients[i], baseline.ingredients[i])) {
        return false;
      }
    }
    if (draft.isFavorite != baseline.isFavorite) return false;
    if (draft.isToTry != baseline.isToTry) return false;
    if (draft.visibility != baseline.visibility) return false;
    if (!_nutritionPersistedEquals(draft.nutrition, baseline.nutrition)) {
      return false;
    }
    if ((draft.nutritionSource ?? '') != (baseline.nutritionSource ?? '')) {
      return false;
    }
    return true;
  }

  bool get _hasUnsavedEdits {
    final initial = widget.initialRecipe;
    if (initial == null) return false;
    return !_persistedRecipesEqual(_recipeFromForm(), initial);
  }

  Recipe _recipeFromForm() {
    final initial = widget.initialRecipe;
    final ingredients = _ingredients.map(
      (row) {
        if (row.qualitative) {
          return Ingredient(
            name: row.name.trim(),
            amount: 0,
            unit: row.resolvedQualitativePhrase(),
            category: GroceryCategory.other,
            qualitative: true,
          );
        }
        final unit = row.selectedUnit == 'custom'
            ? row.customUnitCtrl.text.trim()
            : row.selectedUnit;
        return Ingredient(
          name: row.name.trim(),
          amount: _parseIngredientAmount(row.amountCtrl.text) ?? 0,
          unit: unit,
          category: GroceryCategory.other,
        );
      },
    ).toList();

    final directions = _directionDrafts
        .map((d) => d.textCtrl.text.trim())
        .where((step) => step.isNotEmpty)
        .toList();

    final Nutrition recipeNutrition;
    final String? recipeNutritionSource;
    if (_nutritionError != null) {
      recipeNutrition = initial?.nutrition ?? const Nutrition();
      recipeNutritionSource = initial?.nutritionSource;
    } else {
      recipeNutrition = _estimatedNutrition;
      recipeNutritionSource = _nutritionEstimateSource;
    }

    final rawTitle = _titleCtrl.text.trim();
    final formattedTitle = formatRecipeTitleCase(rawTitle);
    final savedTitle = initial != null ? rawTitle : formattedTitle;

    return Recipe(
      id: initial?.id ?? '',
      title: savedTitle,
      description: initial?.description,
      servings: _parseIntOrNull(_servingsCtrl.text) ?? 2,
      prepTime: initial?.prepTime,
      cookTime: initial?.cookTime,
      mealType: _mealType,
      cuisineTags: _cuisineTags,
      ingredients: ingredients,
      instructions: directions,
      imageUrl: initial?.imageUrl,
      nutrition: recipeNutrition,
      isFavorite: _markFavorite,
      isToTry: _markToTry,
      visibility: _makePublic
          ? RecipeVisibility.public
          : _saveToHousehold
              ? RecipeVisibility.household
              : RecipeVisibility.personal,
      source: initial?.source ?? 'user_created',
      userId: initial?.userId,
      householdId: initial?.householdId,
      apiId: initial?.apiId,
      nutritionSource: recipeNutritionSource,
    );
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    FocusScope.of(context).unfocus();
    if (_step >= 5) {
      _submit();
      return;
    }
    setState(() => _step += 1);
    ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
    _stepCtrl.animateToPage(
      _step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
    if (_step == _kNutritionStepIndex) {
      _scheduleNutritionSync();
    }
  }

  void _prevStep() {
    if (_step == 0) return;
    setState(() => _step -= 1);
    ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
    _stepCtrl.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (_step == _kNutritionStepIndex) {
      _scheduleNutritionSync();
    }
  }

  void _submit() {
    if (_isSubmitting) return;
    if (!_validateAllStepsForSave()) return;

    final recipe = _recipeFromForm();
    if (recipe.ingredients.isEmpty || recipe.instructions.isEmpty) {
      setState(() {
        _validationMessage =
            'Add at least one ingredient and one direction step.';
      });
      return;
    }

    setState(() {
      _validationMessage = null;
      _isSubmitting = true;
    });

    _closeWizard(recipe);
  }

  Widget _buildNutritionStepPage() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final servings =
        (_parseIntOrNull(_servingsCtrl.text) ?? 2).clamp(1, 999999);
    final n = _estimatedNutrition;
    final showPerServing = _nutritionShowPerServing && servings > 0;
    final shownNutrition = showPerServing
        ? Nutrition(
            calories: (n.calories / servings).round(),
            protein: n.protein / servings,
            fat: n.fat / servings,
            carbs: n.carbs / servings,
            fiber: n.fiber / servings,
            sugar: n.sugar / servings,
          )
        : n;

    Widget tile({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    final hasTotals = n.calories > 0 ||
        n.protein > 0 ||
        n.fat > 0 ||
        n.carbs > 0 ||
        n.fiber > 0 ||
        n.sugar > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SectionCard(
              title: 'Nutrition estimate',
              subtitle:
                  'Approximate totals for the full recipe (all servings). Not medical advice.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_nutritionLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_nutritionError != null) ...[
                    Text(
                      _nutritionError!,
                      style:
                          textTheme.bodyMedium?.copyWith(color: scheme.error),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() => _loadedNutritionFingerprint = null);
                          unawaited(_syncNutritionEstimate());
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('Try again'),
                      ),
                    ),
                  ] else if (!hasTotals) ...[
                    if (!Env.hasFdc && !Env.hasGemini)
                      Text(
                        'Configure USDA FDC or Gemini API keys in your environment to estimate nutrition.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else ...[
                      Text(
                        'No nutrition totals were returned. You can retry or continue; values may stay at zero.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() => _loadedNutritionFingerprint = null);
                            unawaited(_syncNutritionEstimate());
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('Retry'),
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      'Nutritional values',
                      style: textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    ToggleButtons(
                      isSelected: [!showPerServing, showPerServing],
                      onPressed: (index) {
                        setState(() {
                          _nutritionShowPerServing = index == 1;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      constraints:
                          const BoxConstraints(minHeight: 36, minWidth: 118),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Total'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Per Serving'),
                        ),
                      ],
                    ),
                    if (servings <= 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Serving size is 1, so total and per serving are the same.',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.local_fire_department_rounded,
                      label: showPerServing
                          ? 'Calories (per serving)'
                          : 'Calories (total)',
                      value: '${shownNutrition.calories}',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.fitness_center_rounded,
                      label: 'Protein',
                      value: '${shownNutrition.protein.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.opacity_rounded,
                      label: 'Fat',
                      value: '${shownNutrition.fat.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.grain_rounded,
                      label: 'Carbs',
                      value: '${shownNutrition.carbs.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.grass_rounded,
                      label: 'Fiber',
                      value: '${shownNutrition.fiber.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.cake_rounded,
                      label: 'Sugar',
                      value: '${shownNutrition.sugar.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _nutritionLoading
                            ? null
                            : () {
                                setState(
                                    () => _loadedNutritionFingerprint = null);
                                unawaited(_syncNutritionEstimate());
                              },
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text('Recalculate'),
                      ),
                    ),
                  ],
                  if (_kShowNutritionIngredientBreakdown &&
                      !_nutritionLoading &&
                      _nutritionError == null &&
                      _nutritionBreakdown.isNotEmpty)
                    _buildNutritionBreakdownSection(scheme, textTheme),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _breakdownSourceLabel(String tag) {
    return switch (tag) {
      'usda_cache' => 'USDA (cached per 100g)',
      'usda_live' => 'USDA (live lookup)',
      'gemini_estimated' => 'Gemini (batch total split evenly across lines)',
      'gemini_full_recipe' => 'Gemini (full recipe)',
      'gemini_failed' => 'Gemini failed (0 allocated)',
      _ => tag,
    };
  }

  /// Shown only when [_kShowNutritionIngredientBreakdown] is true.
  Widget _buildNutritionBreakdownSection(
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Per-ingredient breakdown (testing)',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'USDA rows are per line. Gemini batch rows share one API total, split evenly for display.',
            style:
                textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ..._nutritionBreakdown.map(
            (row) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _breakdownSourceLabel(row.sourceTag),
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${row.nutrition.calories} cal · '
                      'P ${row.nutrition.protein.toStringAsFixed(1)} · '
                      'F ${row.nutrition.fat.toStringAsFixed(1)} · '
                      'C ${row.nutrition.carbs.toStringAsFixed(1)} g · '
                      'fiber ${row.nutrition.fiber.toStringAsFixed(1)} · '
                      'sugar ${row.nutrition.sugar.toStringAsFixed(1)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ThemeData _themeForIngredientModal(BuildContext sheetContext) {
    return Theme.of(sheetContext).copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEFF6FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Theme.of(sheetContext).colorScheme.primary,
            width: 1.2,
          ),
        ),
      ),
    );
  }

  Future<void> _addIngredientAndOpenModal() async {
    if (!_canAddAnotherIngredient) return;
    FocusScope.of(context).unfocus();
    final profile = _detectUnitProfile(
      '',
      ref.read(measurementSystemProvider),
    );
    final row = _IngredientInput(
      name: '',
      unitOptions: profile.options,
      selectedUnit: profile.defaultUnit,
    );
    final draftRid = row.reorderId;
    setState(() {
      _ingredients.add(row);
      _lastAddedIngredientReorderId = draftRid;
      _selectedIngredientIndex = _ingredients.length - 1;
      _validationMessage = null;
    });
    await _showIngredientEditorModal(
      index: _ingredients.length - 1,
      isNewDraft: true,
      draftReorderId: draftRid,
    );
  }

  Future<void> _editIngredientAt(int i) async {
    if (i < 0 || i >= _ingredients.length) return;
    FocusScope.of(context).unfocus();
    setState(() => _selectedIngredientIndex = i);
    await _showIngredientEditorModal(
      index: i,
      isNewDraft: false,
    );
  }

  Future<void> _showIngredientEditorModal({
    required int index,
    required bool isNewDraft,
    String? draftReorderId,
  }) async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (index < 0 || index >= _ingredients.length) {
              return const SizedBox.shrink();
            }
            final row = _ingredients[index];
            final rid = row.reorderId;
            final topPad = MediaQuery.paddingOf(dialogCtx).top + 8;
            final maxH = MediaQuery.sizeOf(dialogCtx).height - topPad - 16;
            final width = MediaQuery.sizeOf(dialogCtx).width;
            void popDialog() {
              FocusScope.of(dialogCtx).unfocus();
              Navigator.of(dialogCtx).pop();
            }

            void onCancel() {
              popDialog();
            }

            void onSave() {
              FocusScope.of(dialogCtx).unfocus();
              if (!_isIngredientRowComplete(row)) return;
              popDialog();
            }

            void removeThenClose() {
              popDialog();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final i = _ingredients.indexWhere((e) => e.reorderId == rid);
                if (i >= 0) _removeIngredientAt(i);
              });
            }

            return Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: topPad, left: 12, right: 12),
                child: Material(
                  elevation: 8,
                  shadowColor: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  color: Theme.of(dialogCtx).colorScheme.surface,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 560, maxHeight: maxH),
                    child: SizedBox(
                      width: width - 24,
                      child: Theme(
                        data: _themeForIngredientModal(this.context),
                        child: Scaffold(
                          resizeToAvoidBottomInset: false,
                          appBar: AppBar(
                            title: Text(
                              isNewDraft ? 'Add ingredient' : 'Ingredient',
                            ),
                            leading: IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Cancel',
                              onPressed: onCancel,
                            ),
                          ),
                          body: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              16 +
                                  MediaQuery.viewInsetsOf(dialogCtx).bottom,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildExpandedIngredientRow(
                                  dialogCtx,
                                  index,
                                  row,
                                  dialogSetState: setModalState,
                                  onRemovePressed: removeThenClose,
                                  cardMargin: EdgeInsets.zero,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: onCancel,
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed:
                                            _isIngredientRowComplete(row)
                                                ? onSave
                                                : null,
                                        child: const Text('Save'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    if (!mounted) return;
    if (isNewDraft && draftReorderId != null) {
      final i =
          _ingredients.indexWhere((e) => e.reorderId == draftReorderId);
      if (i >= 0 && !_isIngredientRowComplete(_ingredients[i])) {
        _removeIngredientAt(i);
      }
    }
    setState(() {});
  }

  /// Summary on the wizard step; one ingredient at a time in a top modal.
  Widget _buildIngredientStepPage() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: SectionCard(
        title: 'Ingredients',
        titleTrailing: MeasurementSystemToggle(
          onChanged: _applyMeasurementSystem,
        ),
        subtitle:
            'Tap a chip to edit, or Add ingredient. Use Save in the editor '
            'when you are finished. Switching Metric / US converts amounts '
            'and updates unit choices.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_ingredients.isEmpty)
              Text(
                'No ingredients yet.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              ...List.generate(
                _ingredients.length,
                (i) => _buildIngredientSavedChip(context, i),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed:
                  _canAddAnotherIngredient ? _addIngredientAndOpenModal : null,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text('Add ingredient'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepTitle = switch (_step) {
      0 => 'Step 1: Name your recipe',
      1 => 'Step 2: Serving + labels',
      2 => 'Step 3: Ingredients',
      3 => 'Step 4: Directions',
      4 => 'Step 5: Nutrition',
      _ => 'Step 6: Final touches',
    };

    return WillPopScope(
      onWillPop: () async => false,
      child: SafeArea(
        child: Form(
            key: _formKey,
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xFFEFF6FF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: scheme.primary, width: 1.2),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFD7EEFF),
                            Color(0xFFB4DEFF),
                            Color(0xFF8BCBFF)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.initialRecipe == null
                                ? 'Create Recipe'
                                : 'Edit Recipe',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(stepTitle),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: (_step + 1) / 6,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: List.generate(
                              6,
                              (index) => Expanded(
                                child: Container(
                                  margin:
                                      EdgeInsets.only(right: index == 5 ? 0 : 6),
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: index <= _step
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.45),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.initialRecipe != null && _hasUnsavedEdits)
                          TextButton.icon(
                            onPressed: _isSubmitting ? null : _submit,
                            icon: Icon(
                              _isSubmitting
                                  ? Icons.hourglass_empty
                                  : Icons.save_rounded,
                              size: 18,
                            ),
                            label: Text(_isSubmitting ? 'Saving…' : 'Save'),
                          ),
                        if (widget.initialRecipe != null && _hasUnsavedEdits)
                          const SizedBox(width: 4),
                        TextButton.icon(
                          onPressed: _confirmClose,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Cancel'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: PageView(
                        controller: _stepCtrl,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _StepCard(
                            title: 'Name your recipe',
                            child: TextFormField(
                              controller: _titleCtrl,
                              focusNode: _titleFocusNode,
                              textCapitalization: TextCapitalization.sentences,
                              onTapOutside: (_) =>
                                  FocusScope.of(context).unfocus(),
                              decoration: const InputDecoration(
                                labelText: 'Recipe name',
                                hintText: 'e.g., Spicy Garlic Chicken Pasta',
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'Recipe name is required.'
                                      : null,
                            ),
                          ),
                          SingleChildScrollView(
                            child: Column(
                              children: [
                                SectionCard(
                                  title: 'Serving size',
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: _decrementServings,
                                          icon: const Icon(
                                              Icons.remove_circle_outline),
                                        ),
                                        SizedBox(
                                          width: 64,
                                          child: TextFormField(
                                            controller: _servingsCtrl,
                                            textAlign: TextAlign.center,
                                            keyboardType: TextInputType.number,
                                            onTapOutside: (_) =>
                                                FocusScope.of(context)
                                                    .unfocus(),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              contentPadding: EdgeInsets.zero,
                                              isDense: true,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.w700),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: _incrementServings,
                                          icon: const Icon(
                                              Icons.add_circle_outline),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SectionCard(
                                  title: 'Meal type',
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: MealType.values
                                          .map(
                                            (type) => ChoiceChip(
                                              label: Text(_mealTypeLabel(type)),
                                              selected: _mealType == type,
                                              onSelected: (_) => setState(
                                                  () => _mealType = type),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SectionCard(
                                  title: 'Cuisine',
                                  child: Column(
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ..._presetCuisines.map(
                                              (cuisine) => FilterChip(
                                                label: Text(cuisine),
                                                selected: _cuisineTags
                                                    .contains(cuisine),
                                                onSelected: (_) =>
                                                    _toggleCuisinePreset(
                                                        cuisine),
                                                selectedColor:
                                                    const Color(0xFFD6EBFF),
                                              ),
                                            ),
                                            ActionChip(
                                              avatar: const Icon(Icons.add,
                                                  size: 18),
                                              label: const Text('Custom'),
                                              onPressed: () => setState(
                                                  () => _showCustomTag = true),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_showCustomTag) ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _tagCtrl,
                                                autofocus: true,
                                                textCapitalization:
                                                    TextCapitalization
                                                        .sentences,
                                                onTapOutside: (_) =>
                                                    FocusScope.of(context)
                                                        .unfocus(),
                                                decoration:
                                                    const InputDecoration(
                                                  hintText:
                                                      'Add custom cuisine tag',
                                                ),
                                                onSubmitted: (_) =>
                                                    _addCuisineTag(),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: _addCuisineTag,
                                              icon:
                                                  const Icon(Icons.add_circle),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (_cuisineTags
                                          .where((tag) =>
                                              !_presetCuisines.contains(tag))
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Wrap(
                                            spacing: 8,
                                            children: _cuisineTags
                                                .where((tag) => !_presetCuisines
                                                    .contains(tag))
                                                .map(
                                                  (tag) => Chip(
                                                    label: Text(tag),
                                                    onDeleted: () => setState(
                                                        () => _cuisineTags
                                                            .remove(tag)),
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildIngredientStepPage(),
                          _StepCard(
                            title: 'Directions',
                            child: Column(
                              children: [
                                for (var i = 0;
                                    i < _directionDrafts.length;
                                    i++)
                                  if (_selectedDirectionIndex == i)
                                    _buildExpandedDirectionRow(
                                      context,
                                      i,
                                      _directionDrafts[i],
                                    )
                                  else
                                    _buildCondensedDirectionRow(
                                      context,
                                      i,
                                      _directionDrafts[i],
                                    ),
                                const SizedBox(height: AppSpacing.xs),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _canAddAnotherDirection
                                        ? _addDirectionStep
                                        : null,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add step'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildNutritionStepPage(),
                          _StepCard(
                            title: 'Final touches',
                            child: Column(
                              children: [
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  secondary: Icon(
                                    _markFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    color: _markFavorite
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  title: const Text('Add to Favorites'),
                                  subtitle: const Text(
                                    'Quick access from your Favorites list.',
                                  ),
                                  value: _markFavorite,
                                  onChanged: (value) =>
                                      setState(() => _markFavorite = value),
                                ),
                                const Divider(height: 1),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  secondary: Icon(
                                    _markToTry
                                        ? Icons.flag_rounded
                                        : Icons.outlined_flag_rounded,
                                    color: _markToTry
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  title: const Text('Add to To Try'),
                                  subtitle: const Text(
                                    'Save to your To Try list for later.',
                                  ),
                                  value: _markToTry,
                                  onChanged: (value) =>
                                      setState(() => _markToTry = value),
                                ),
                                const Divider(height: 1),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  secondary: Icon(
                                    _makePublic
                                        ? Icons.public_rounded
                                        : Icons.public_off_rounded,
                                    color: _makePublic
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  title: const Text('Make public'),
                                  subtitle: const Text(
                                    'Public recipes appear in Discover for all users.',
                                  ),
                                  value: _makePublic,
                                  onChanged: (value) =>
                                      setState(() => _makePublic = value),
                                ),
                                if (ref
                                        .watch(hasSharedHouseholdProvider)
                                        .valueOrNull ??
                                    false) ...[
                                  const Divider(height: 1),
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: Icon(
                                      Icons.groups_2_outlined,
                                      color: _saveToHousehold
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    title: const Text('Save to Household'),
                                    subtitle: const Text(
                                      'Share this recipe with your household members.',
                                    ),
                                    value: _saveToHousehold,
                                    onChanged: (value) => setState(
                                        () => _saveToHousehold = value),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_validationMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _validationMessage!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _isSubmitting
                                ? null
                                : (_step == 0 ? _confirmClose : _prevStep),
                            icon: Icon(_step == 0
                                ? Icons.close_rounded
                                : Icons.arrow_back_rounded),
                            label: Text(_step == 0 ? 'Cancel' : 'Back'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSubmitting ? null : _nextStep,
                            icon: Icon(_step == 5
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded),
                            label: Text(_step == 5
                                ? (_isSubmitting ? 'Saving...' : 'Save Recipe')
                                : 'Next'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4CA9F5),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SectionCard(
        title: title,
        subtitle: subtitle,
        child: child,
      ),
    );
  }
}
