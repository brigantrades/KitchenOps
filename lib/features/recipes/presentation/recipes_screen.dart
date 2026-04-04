import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/ui/discover_shell.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/measurement_system_toggle.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/recipes/recipe_manual_nutrition.dart';
import 'package:plateplan/core/services/nutrition_estimation.dart';
import 'package:plateplan/core/services/recipe_nutrition_lines.dart';
import 'package:plateplan/core/measurement/ingredient_unit_profile.dart';
import 'package:plateplan/core/measurement/measurement_system.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';
import 'package:plateplan/core/strings/recipe_title_case.dart';
import 'package:plateplan/core/ui/recipe_title_input_formatter.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/recipes/presentation/recipe_creation_guard.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/recipes/presentation/recipe_editor_modals.dart';
import 'package:plateplan/features/recipes/presentation/recipe_lists_sharing_sheet.dart';
import 'package:plateplan/features/recipes/presentation/recipe_sheet_confirmations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// #region agent log
String? _agentDebugLogPath;
String get _agentLogPath {
  if (_agentDebugLogPath != null) return _agentDebugLogPath!;
  if (kIsWeb) return '';
  if (Platform.isMacOS) {
    _agentDebugLogPath =
        '/Users/brigan/Personal Development/KitchenOps/.cursor/debug-5a73d6.log';
  } else {
    _agentDebugLogPath = '${Directory.systemTemp.path}/debug-5a73d6.log';
  }
  return _agentDebugLogPath!;
}

void _recipeBuilderSheetDebugLog(
  String hypothesisId,
  String location,
  String message, [
  Map<String, Object?>? data,
]) {
  final line = jsonEncode({
    'sessionId': '5a73d6',
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data ?? <String, Object?>{},
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });
  debugPrint('AGENT_DEBUG_5a73d6 $line');
  if (!kIsWeb) {
    try {
      File(_agentLogPath)
          .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}
// #endregion

/// After [showModalBottomSheet] completes, the route may still be animating out.
/// Wait two frames before [ref.invalidate] so listeners (e.g. [recipesProvider])
/// do not rebuild the tree while the modal subtree is still tearing down.
Future<void> _afterModalRouteFinished() async {
  final completer = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
  });
  return completer.future;
}

/// Recipe create/edit as a **pushed** full-screen route (not [showModalBottomSheet]).
/// Bottom-sheet modals share the overlay with the tab shell; popping them while
/// Riverpod or stream-driven rebuilds touch the shell has repeatedly produced
/// framework `_dependents.isEmpty` asserts. A [MaterialPageRoute] unmounts in
/// normal stack order and avoids that class of failure.
Future<RecipeBuilderSaveResult?> _pushRecipeBuilderRoute(
  BuildContext context, {
  Recipe? initialRecipe,
  Recipe? initialSauceRecipe,
}) async {
  final result = await Navigator.of(context, rootNavigator: true)
      .push<RecipeBuilderSaveResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _RecipeBuilderSheet(
        initialRecipe: initialRecipe,
        initialSauceRecipe: initialSauceRecipe,
      ),
    ),
  );
  // #region agent log
  _recipeBuilderSheetDebugLog(
    'ROUTE',
    'recipes_screen.dart:_pushRecipeBuilderRoute',
    'push_completed',
    {'hasResult': result != null},
  );
  // #endregion
  return result;
}

/// When true, Step 5 shows per-ingredient USDA/Gemini breakdown (dev / diagnostics).
const bool _kShowNutritionIngredientBreakdown = false;

/// When true, Step 7 shows "Make public" (Discover). Hidden until the flow is defined.
const bool _kShowMakePublicRecipeOption = false;

enum _NutritionEditMode { auto, manual }

enum _RecipeIngredientSection { main, sauce }

/// Result of saving from [_RecipeBuilderSheet] (create or edit).
class RecipeBuilderSaveResult {
  const RecipeBuilderSaveResult({
    required this.recipe,
    this.copyToHousehold = false,
    this.householdFavorite = false,
    this.householdToTry = false,
  });

  final Recipe recipe;

  final bool copyToHousehold;
  final bool householdFavorite;
  final bool householdToTry;
}

/// Create / Edit Recipe wizard header gradient & saved ingredient chips (step 3).
const Color _kCreateRecipeBlueLight = Color(0xFFD7EEFF);
const Color _kCreateRecipeBlueMid = Color(0xFFB4DEFF);
const Color _kCreateRecipeBlueDeep = Color(0xFF8BCBFF);

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

  Future<void> _showAddRecipeOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Add recipe manually'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('Scan from book'),
              subtitle: const Text('Photo of a cookbook page'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Import from link'),
              subtitle: const Text('Paste a recipe URL from the web'),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'manual') {
      await _createRecipeManually();
    } else if (choice == 'scan') {
      context.push('/scan-recipe-book');
    } else if (choice == 'url') {
      context.push('/import-recipe-url');
    }
  }

  Future<void> _createRecipeManually() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sign in required.')));
      return;
    }

    final result = await _pushRecipeBuilderRoute(context);

    if (result == null) return;
    final recipe = result.recipe;

    await _afterModalRouteFinished();
    if (!mounted) return;

    try {
      final repo = ref.read(recipesRepositoryProvider);
      if (result.copyToHousehold) {
        final personalId = await repo.saveRecipeWithOptionalDefaultSauce(
          userId: user.id,
          mainFields: recipe,
          shareWithHousehold: false,
          visibilityOverride: RecipeVisibility.personal,
        );
        await repo.copyPersonalRecipeToHousehold(
          userId: user.id,
          recipeId: personalId,
          householdFavorite: result.householdFavorite,
          householdToTry: result.householdToTry,
        );
      } else {
        await repo.saveRecipeWithOptionalDefaultSauce(
          userId: user.id,
          mainFields: recipe,
          shareWithHousehold: false,
          visibilityOverride: recipe.visibility,
        );
      }
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      final dest = result.copyToHousehold
          ? 'My Recipes and Household Recipes'
          : switch (recipe.visibility) {
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
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    Recipe? initialSauce;
    final sid = recipe.defaultSauceRecipeId?.trim();
    if (recipe.embeddedSauce == null && sid != null && sid.isNotEmpty) {
      final list = ref.read(recipesProvider).valueOrNull;
      initialSauce = list?.firstWhereOrNull((r) => r.id == sid);
    }
    final result = await _pushRecipeBuilderRoute(
      context,
      initialRecipe: recipe,
      initialSauceRecipe: initialSauce,
    );
    if (result == null) return;
    final updated = result.recipe;

    await _afterModalRouteFinished();
    if (!mounted) return;

    try {
      await ref
          .read(recipesRepositoryProvider)
          .saveRecipeWithOptionalDefaultSauce(
            userId: user.id,
            mainFields: updated,
            existingMainId: recipe.id,
            existingDefaultSauceId: recipe.defaultSauceRecipeId,
            visibilityOverride: updated.visibility,
          );
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

  void _openRecipeFiltersSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final scheme = Theme.of(context).colorScheme;
            final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                );
            final mealChips = Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: BrandedSheetScaffold(
                title: 'Filters',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Sort', style: titleStyle),
                    const SizedBox(height: 8),
                    SegmentedButton<_RecipeSortOption>(
                      segments: [
                        ButtonSegment<_RecipeSortOption>(
                          value: _RecipeSortOption.dateAdded,
                          label: Text(_recipeSortOptionLabel(
                            _RecipeSortOption.dateAdded,
                          )),
                        ),
                        ButtonSegment<_RecipeSortOption>(
                          value: _RecipeSortOption.name,
                          label: Text(_recipeSortOptionLabel(
                            _RecipeSortOption.name,
                          )),
                        ),
                      ],
                      selected: {_sortOption},
                      onSelectionChanged: (next) {
                        if (next.isEmpty) return;
                        setState(() => _sortOption = next.first);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 20),
                    Text('Meal type', style: titleStyle),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final type in MealType.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(_mealTypeLabel(type)),
                                selected: _mealTypeFilters.contains(type),
                                showCheckmark: true,
                                selectedColor: scheme.secondaryContainer,
                                checkmarkColor: scheme.onSecondaryContainer,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onSelected: (value) {
                                  _toggleMealTypeFilter(type, value);
                                  setModalState(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_mealTypeFilters.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _mealTypeFilters.clear();
                            });
                            setModalState(() {});
                          },
                          child: const Text('Clear meal filters'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
            return mealChips;
          },
        );
      },
    );
  }

  bool get _recipeFiltersActive {
    return _mealTypeFilters.isNotEmpty &&
        _mealTypeFilters.length < MealType.values.length;
  }

  void _showInstagramImportHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.paddingOf(ctx).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: scheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Import from Instagram',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Save a recipe from Instagram using your phone\'s Share menu. '
                  'We read the post\'s caption and link, then open a preview you can edit before saving to your library.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'How to import',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _instagramImportHelpStep(
                  ctx,
                  '1',
                  'Open Instagram and go to the post or Reel that has the recipe.',
                ),
                _instagramImportHelpStep(
                  ctx,
                  '2',
                  'Tap Share (paper airplane on Android, or the standard share icon on iOS).',
                ),
                _instagramImportHelpStep(
                  ctx,
                  '3',
                  'Pick this app from the list. If it\'s not there, tap More, Edit actions, or similar on your device and add it.',
                ),
                _instagramImportHelpStep(
                  ctx,
                  '4',
                  'We\'ll open an import preview—check ingredients and steps, then save the recipe.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Tip: Captions that spell out the recipe usually import more reliably than video-only posts.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Got it'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.push('/instagram-import-test');
                  },
                  child: const Text('Paste an Instagram link instead'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecipesFilterHeader({
    required BuildContext context,
    required bool hasSharedHousehold,
    required int effectiveLibraryIndex,
    required List<String> libraryLabels,
  }) {
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
        if (hasSharedHousehold) ...[
          const SizedBox(height: 6),
          SegmentedPills(
            labels: libraryLabels,
            selectedIndex: effectiveLibraryIndex,
            onSelect: (idx) => setState(() {
              _libraryIndex = idx;
              _segmentIndex = 0;
            }),
          ),
        ],
        const SizedBox(height: 6),
        SegmentedPills(
          labels: const ['All', 'Favorites', 'To Try'],
          selectedIndex: _segmentIndex,
          onSelect: (idx) => setState(() => _segmentIndex = idx),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Badge(
            isLabelVisible: _recipeFiltersActive,
            label: Text('${_mealTypeFilters.length}'),
            child: IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip:
                  'Filters & sort · ${_recipeSortOptionLabel(_sortOption)}',
              onPressed: _openRecipeFiltersSheet,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSharedHousehold =
        ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;
    final query = _searchCtrl.text.trim().toLowerCase();
    final effectiveLibraryIndex = hasSharedHousehold ? _libraryIndex : 0;
    final libraryLabels = hasSharedHousehold
        ? const ['Household Recipes', 'My Recipes']
        : const ['My Recipes'];

    return DiscoverShellScaffold(
      title: hasSharedHousehold ? 'Recipes' : 'My Recipes',
      onNotificationsTap: () => showDiscoverNotificationsDropdown(context, ref),
      trailingActions: [
        IconButton(
          icon: const Icon(Icons.auto_awesome_outlined),
          tooltip: 'Import from Instagram',
          onPressed: () => _showInstagramImportHelp(context),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRecipeOptions,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Recipe'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // [recipesProvider] must not be watched here: stream updates would rebuild
      // the whole shell while a recipe modal can still be tearing down (framework
      // `_dependents.isEmpty` asserts). Scope the watch to the list subtree only.
      body: Consumer(
        builder: (context, ref, _) {
          final recipesAsync = ref.watch(recipesProvider);
          return recipesAsync.when(
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
                    return a.title
                        .toLowerCase()
                        .compareTo(b.title.toLowerCase());
                  case _RecipeSortOption.dateAdded:
                    final aTime =
                        a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bTime =
                        b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return bTime.compareTo(aTime);
                }
              });

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
                            child: Text(emptyListMessage),
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
                                allRecipes: recipes,
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
          );
        },
      ),
    );
  }
}

void _showRecipeCollectionsSheet({
  required BuildContext anchorContext,
  required String recipeId,
  required bool hasSharedHousehold,
}) {
  showRecipeListsSharingSheet(
    context: anchorContext,
    anchorContext: anchorContext,
    recipeId: recipeId,
    hasSharedHousehold: hasSharedHousehold,
  );
}

class _RecipeRow extends ConsumerWidget {
  const _RecipeRow({
    required this.recipe,
    required this.allRecipes,
    required this.hasSharedHousehold,
    required this.isHouseholdLibrary,
    required this.onEditRecipe,
  });

  final Recipe recipe;
  final List<Recipe> allRecipes;
  final bool hasSharedHousehold;
  final bool isHouseholdLibrary;
  final Future<void> Function(Recipe recipe) onEditRecipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(
      !isHouseholdLibrary || recipe.visibility == RecipeVisibility.household,
      'Household library lists only household recipes.',
    );
    final cuisineTags = recipe.cuisineTags.take(2).toList();

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
      if (value == 'delete_recipe') {
        await confirmAndDeleteRecipeWithOptions(
          context,
          recipe: recipe,
          allRecipes: allRecipes,
        );
        return;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RecipeListCard(
        title: recipe.title,
        meta:
            '${_mealTypeLabel(recipe.mealType)} · Serves ${recipe.servings} · '
            '${recipe.ingredients.length} ingredients · '
            '${recipe.instructions.length} steps',
        tags: cuisineTags,
        summaryStyle: RecipeListSummaryStyle.plain,
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
            const PopupMenuItem<String>(
              value: 'delete_recipe',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Delete'),
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

Widget _instagramImportHelpStep(
  BuildContext context,
  String number,
  String body,
) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 26,
          child: Text(
            '$number.',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _RecipeBuilderSheet extends ConsumerStatefulWidget {
  const _RecipeBuilderSheet({
    this.initialRecipe,
    this.initialSauceRecipe,
  });

  final Recipe? initialRecipe;

  /// Legacy linked sauce row when editing a recipe that still uses
  /// [Recipe.defaultSauceRecipeId] (no [Recipe.embeddedSauce]).
  final Recipe? initialSauceRecipe;

  @override
  ConsumerState<_RecipeBuilderSheet> createState() =>
      _RecipeBuilderSheetState();
}

class _RecipeBuilderSheetState extends ConsumerState<_RecipeBuilderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _stepCtrl = PageController();
  final _titleCtrl = TextEditingController();
  final _servingsCtrl = TextEditingController(text: '2');
  final _titleFocusNode = FocusNode();
  final GlobalKey _ingredientExpandedCardKey = GlobalKey();
  String? _lastAddedIngredientReorderId;
  final List<String> _cuisineTags = [];
  final List<RecipeIngredientFormRow> _ingredients = [];
  final List<RecipeDirectionDraft> _directionDrafts = [RecipeDirectionDraft()];
  MealType _mealType = MealType.entree;
  bool _markFavorite = false;
  bool _markToTry = false;
  bool _makePublic = false;
  bool _saveToHousehold = false;
  bool _householdFavorite = false;
  bool _householdToTry = false;
  bool _sauceEnabled = false;
  final _sauceTitleCtrl = TextEditingController();
  final List<RecipeIngredientFormRow> _sauceIngredients = [];
  final List<RecipeDirectionDraft> _sauceDirectionDrafts = [
    RecipeDirectionDraft(),
  ];
  String? _lastAddedSauceIngredientReorderId;
  int? _selectedSauceIngredientIndex;
  int _step = 0;
  String? _validationMessage;
  bool _isSubmitting = false;
  int? _selectedIngredientIndex;

  /// New recipe only: when true, title field does not auto-format per-word caps.
  bool _recipeTitleLowercaseTyping = false;

  /// With sauce: 7 pages (sauce at index 4). Without: 6 (nutrition at 4, final at 5).
  int get _pageCount => _sauceEnabled ? 7 : 6;

  int get _nutritionPageIndex => _sauceEnabled ? 5 : 4;

  int get _finalPageIndex => _sauceEnabled ? 6 : 5;

  /// Short label for optional sauce block: dessert uses "Sauce or Icing", else "Sauce".
  String get _sauceOrIcingLabel =>
      _mealType == MealType.dessert ? 'Sauce or Icing' : 'Sauce';

  /// [RecipeIngredientFormRow] owns [FocusNode]s. Disposing rows inside
  /// [setState] — before the matching [TextField]s unmount — triggers
  /// "FocusNode was used after being disposed" (see recipe_editor_modals
  /// ingredient [TextField]s). Defer disposal to after the frame.
  void _disposeIngredientRowsAfterFrame(List<RecipeIngredientFormRow> rows) {
    if (rows.isEmpty) return;
    // Two frames: one is not always enough for [TextField] / gesture state to
    // release [FocusNode]s after the row is removed from the list in [setState].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in rows) {
          r.dispose();
        }
      });
    });
  }

  void _disposeDirectionDraftsAfterFrame(List<RecipeDirectionDraft> drafts) {
    if (drafts.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final d in drafts) {
          d.dispose();
        }
      });
    });
  }

  void _clearSauceDraft() {
    _sauceTitleCtrl.clear();
    final oldIngredientRows = List<RecipeIngredientFormRow>.from(
      _sauceIngredients,
    );
    _sauceIngredients.clear();
    final oldDirectionDrafts = List<RecipeDirectionDraft>.from(
      _sauceDirectionDrafts,
    );
    _sauceDirectionDrafts
      ..clear()
      ..add(RecipeDirectionDraft());
    _lastAddedSauceIngredientReorderId = null;
    _selectedSauceIngredientIndex = null;
    _disposeIngredientRowsAfterFrame(oldIngredientRows);
    _disposeDirectionDraftsAfterFrame(oldDirectionDrafts);
  }

  /// After [PageView] child count changes (sauce on/off), sync the controller, then
  /// update the nav guard on the *next* frame so the shell [ref.watch] does not
  /// rebuild during the same layout pass as the page list (avoids
  /// `_dependents.isEmpty` framework asserts).
  void _scheduleStepPageSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stepCtrl.jumpToPage(_step);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
      });
    });
  }

  /// Same as choosing No on Step 2: no linked sauce recipe.
  void _skipSauceStep() {
    FocusScope.of(context).unfocus();
    setState(() {
      _sauceEnabled = false;
      _clearSauceDraft();
    });
    _scheduleStepPageSync();
  }

  String _headerStepTitle() {
    switch (_step) {
      case 0:
        return 'Step 1: Name your recipe';
      case 1:
        return 'Step 2: Serving + labels';
      case 2:
        return 'Step 3: Ingredients';
      case 3:
        return 'Step 4: Directions (optional)';
      case 4:
        if (_sauceEnabled) {
          return _mealType == MealType.dessert
              ? 'Step 5: Sauce or Icing'
              : 'Step 5: Sauce';
        }
        return 'Step 5: Nutrition';
      case 5:
        if (_sauceEnabled) {
          return 'Step 6: Nutrition';
        }
        return 'Step 6: Final touches';
      case 6:
        return 'Step 7: Final touches';
      default:
        return 'Step 7: Final touches';
    }
  }

  Nutrition _estimatedNutrition = const Nutrition();
  String? _nutritionEstimateSource;
  bool _nutritionLoading = false;
  String? _nutritionError;
  String? _loadedNutritionFingerprint;
  List<IngredientNutritionBreakdownLine> _nutritionBreakdown = const [];
  bool _nutritionShowPerServing = false;

  /// When true, the nutrition step shows a prompt and [Calculate] only (no auto-sync).
  bool _nutritionAwaitingManualCalculate = true;

  _NutritionEditMode _nutritionEditMode = _NutritionEditMode.auto;
  final _manualCaloriesCtrl = TextEditingController();
  final _manualProteinCtrl = TextEditingController();
  final _manualFatCtrl = TextEditingController();
  final _manualCarbsCtrl = TextEditingController();
  final _manualFiberCtrl = TextEditingController();
  final _manualSugarCtrl = TextEditingController();

  void _onEditFormControllerChanged() {
    if (!mounted) return;
    if (widget.initialRecipe != null) setState(() {});
  }

  // #region agent log
  void Function(FlutterErrorDetails)? _previousErrorHandler;

  void _interceptFlutterErrors() {
    _previousErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final summary = details.exceptionAsString();
      if (summary.contains('FocusNode') ||
          summary.contains('_dependents') ||
          summary.contains('disposed')) {
        final trace = details.stack?.toString() ?? '(no stack)';
        final msg = 'AGENT_DEBUG_5a73d6 CAUGHT_ERROR summary=$summary\n$trace';
        debugPrint(msg);
        _recipeBuilderSheetDebugLog(
          'CAUGHT_ERROR',
          'recipes_screen.dart:FlutterError.onError',
          summary,
          {'stack': trace},
        );
      }
      _previousErrorHandler?.call(details);
    };
  }

  void _restoreFlutterErrors() {
    if (_previousErrorHandler != null) {
      FlutterError.onError = _previousErrorHandler;
      _previousErrorHandler = null;
    }
  }
  // #endregion

  @override
  void initState() {
    super.initState();
    // #region agent log
    _interceptFlutterErrors();
    // #endregion
    _hydrateFromInitialRecipe();
    if (widget.initialRecipe != null) {
      _titleCtrl.addListener(_onEditFormControllerChanged);
      _servingsCtrl.addListener(_onEditFormControllerChanged);
    }
    unawaited(ref.read(groceryRepositoryProvider).ensureCatalogLoaded());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // #region agent log
      _recipeBuilderSheetDebugLog(
        'H1',
        'recipes_screen.dart:initState:pfb',
        'post-frame start',
        {'mounted': mounted, 'titleHasFocus': _titleFocusNode.hasFocus},
      );
      // #endregion
      if (!mounted) return;
      ref.read(recipeCreationGuardProvider.notifier).open();
      ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
      // #region agent log
      _recipeBuilderSheetDebugLog(
        'H1',
        'recipes_screen.dart:initState:pfb',
        'before requestFocus',
        {'mounted': mounted},
      );
      // #endregion
      try {
        _titleFocusNode.requestFocus();
      } on Object {
        // Route popped before first frame (rare); node must not crash the app.
      }
      // #region agent log
      _recipeBuilderSheetDebugLog(
        'H1',
        'recipes_screen.dart:initState:pfb',
        'after requestFocus',
        {'mounted': mounted, 'titleHasFocus': _titleFocusNode.hasFocus},
      );
      // #endregion
    });
  }

  @override
  void dispose() {
    // #region agent log
    _restoreFlutterErrors();
    _recipeBuilderSheetDebugLog(
      'H3',
      'recipes_screen.dart:dispose:entry',
      'dispose start',
      {'titleHasFocus': _titleFocusNode.hasFocus},
    );
    // #endregion
    if (widget.initialRecipe != null) {
      _titleCtrl.removeListener(_onEditFormControllerChanged);
      _servingsCtrl.removeListener(_onEditFormControllerChanged);
    }
    // FocusNode / TextEditingController disposal is deferred to after the
    // current unmount cycle completes. Descendant TextField widgets may still
    // reference these objects during their own dispose (unmount order is
    // depth-first but post-frame callbacks from focus changes can schedule
    // rebuilds that race with teardown). Deferring guarantees every descendant
    // has released its attachment before we call dispose().
    final ingredients = List<RecipeIngredientFormRow>.of(_ingredients);
    final sauceIngredients =
        List<RecipeIngredientFormRow>.of(_sauceIngredients);
    final directionDrafts = List<RecipeDirectionDraft>.of(_directionDrafts);
    final sauceDirectionDrafts =
        List<RecipeDirectionDraft>.of(_sauceDirectionDrafts);
    final stepCtrl = _stepCtrl;
    final titleCtrl = _titleCtrl;
    final servingsCtrl = _servingsCtrl;
    final manualCaloriesCtrl = _manualCaloriesCtrl;
    final manualProteinCtrl = _manualProteinCtrl;
    final manualFatCtrl = _manualFatCtrl;
    final manualCarbsCtrl = _manualCarbsCtrl;
    final manualFiberCtrl = _manualFiberCtrl;
    final manualSugarCtrl = _manualSugarCtrl;
    final titleFocusNode = _titleFocusNode;
    final sauceTitleCtrl = _sauceTitleCtrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // #region agent log
      _recipeBuilderSheetDebugLog(
        'DEFERRED_DISPOSE',
        'recipes_screen.dart:dispose:deferred',
        'deferred dispose running',
        {
          'ingredientCount': ingredients.length,
          'sauceIngredientCount': sauceIngredients.length,
        },
      );
      // #endregion
      for (final r in ingredients) {
        r.dispose();
      }
      for (final r in sauceIngredients) {
        r.dispose();
      }
      for (final d in directionDrafts) {
        d.dispose();
      }
      for (final d in sauceDirectionDrafts) {
        d.dispose();
      }
      stepCtrl.dispose();
      titleCtrl.dispose();
      servingsCtrl.dispose();
      manualCaloriesCtrl.dispose();
      manualProteinCtrl.dispose();
      manualFatCtrl.dispose();
      manualCarbsCtrl.dispose();
      manualFiberCtrl.dispose();
      manualSugarCtrl.dispose();
      titleFocusNode.dispose();
      sauceTitleCtrl.dispose();
    });
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
        final profile = detectUnitProfile(ingredient.name, system);
        _ingredients.add(
          RecipeIngredientFormRow(
            name: ingredient.name,
            unitOptions: profile.options,
            selectedUnit: profile.defaultUnit,
            qualitative: true,
            qualitativePhrase: ingredient.unit,
          ),
        );
        continue;
      }
      final profile = detectUnitProfile(ingredient.name, system);
      final normalizedUnit = ingredient.unit.trim().toLowerCase();
      final isCustom = !profile.options.contains(normalizedUnit);
      // profile.options already ends with 'custom'; do not append again or the
      // unit dropdown gets duplicate values and DropdownButtonFormField asserts.
      final units = [...profile.options];
      final row = RecipeIngredientFormRow(
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
    _nutritionEditMode = initial.nutritionSource == 'manual'
        ? _NutritionEditMode.manual
        : _NutritionEditMode.auto;
    final serv = initial.servings.clamp(1, 999999);
    if (_nutritionEditMode == _NutritionEditMode.manual) {
      final ps = perServingNutritionFromRecipeTotals(initial.nutrition, serv);
      _manualCaloriesCtrl.text = '${ps.calories}';
      _manualProteinCtrl.text = ps.protein.toStringAsFixed(1);
      _manualFatCtrl.text = ps.fat.toStringAsFixed(1);
      _manualCarbsCtrl.text = ps.carbs.toStringAsFixed(1);
      _manualFiberCtrl.text = ps.fiber.toStringAsFixed(1);
      _manualSugarCtrl.text = ps.sugar.toStringAsFixed(1);
    } else {
      _nutritionAwaitingManualCalculate =
          !nutritionHasAnyTotals(initial.nutrition);
    }
    for (final draft in _directionDrafts) {
      draft.dispose();
    }
    _directionDrafts
      ..clear()
      ..addAll(
        initial.instructions.isEmpty
            ? [RecipeDirectionDraft()]
            : initial.instructions
                .map((step) => RecipeDirectionDraft(text: step)),
      );
    _loadedNutritionFingerprint = _computeNutritionFingerprint();
    _hydrateSauceFromInitial();
  }

  void _hydrateSauceFromInitial() {
    final initial = widget.initialRecipe;
    final embedded = initial?.embeddedSauce;
    if (embedded != null && embedded.ingredients.isNotEmpty) {
      _hydrateSauceRows(
        title: embedded.title ?? '',
        ingredients: embedded.ingredients,
        instructions: embedded.instructions,
      );
      return;
    }
    final sauce = widget.initialSauceRecipe;
    if (sauce == null) {
      _sauceEnabled = initial?.defaultSauceRecipeId != null &&
          initial!.defaultSauceRecipeId!.trim().isNotEmpty;
      return;
    }
    _hydrateSauceRows(
      title: sauce.title,
      ingredients: sauce.ingredients,
      instructions: sauce.instructions,
    );
  }

  void _hydrateSauceRows({
    required String title,
    required List<Ingredient> ingredients,
    required List<String> instructions,
  }) {
    _sauceEnabled = true;
    _sauceTitleCtrl.text = title;
    final system = ref.read(measurementSystemProvider);
    for (final row in _sauceIngredients) {
      row.dispose();
    }
    _sauceIngredients.clear();
    for (final ingredient in ingredients) {
      if (ingredient.qualitative) {
        final profile = detectUnitProfile(ingredient.name, system);
        _sauceIngredients.add(
          RecipeIngredientFormRow(
            name: ingredient.name,
            unitOptions: profile.options,
            selectedUnit: profile.defaultUnit,
            qualitative: true,
            qualitativePhrase: ingredient.unit,
          ),
        );
        continue;
      }
      final profile = detectUnitProfile(ingredient.name, system);
      final normalizedUnit = ingredient.unit.trim().toLowerCase();
      final isCustom = !profile.options.contains(normalizedUnit);
      final units = [...profile.options];
      final row = RecipeIngredientFormRow(
        name: ingredient.name,
        unitOptions: units,
        selectedUnit: isCustom ? 'custom' : normalizedUnit,
        customUnit: isCustom ? ingredient.unit : null,
      );
      row.amountCtrl.text = formatIngredientAmount(ingredient.amount);
      _sauceIngredients.add(row);
    }
    _selectedSauceIngredientIndex = _sauceIngredients.isEmpty ? null : 0;
    _lastAddedSauceIngredientReorderId = null;
    for (final draft in _sauceDirectionDrafts) {
      draft.dispose();
    }
    _sauceDirectionDrafts
      ..clear()
      ..addAll(
        instructions.isEmpty
            ? [RecipeDirectionDraft()]
            : instructions.map((step) => RecipeDirectionDraft(text: step)),
      );
  }

  void _closeWizard([RecipeBuilderSaveResult? result]) {
    // #region agent log
    _recipeBuilderSheetDebugLog(
      'H4',
      'recipes_screen.dart:_closeWizard',
      'entry',
      {'mounted': mounted, 'hasResult': result != null},
    );
    // #endregion
    final container = ProviderScope.containerOf(context, listen: false);
    Navigator.of(context).pop(result);
    container.read(recipeCreationGuardProvider.notifier).close();
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

  void _applyMeasurementSystem(MeasurementSystem next) {
    ref.read(measurementSystemProvider.notifier).setSystem(next);
    setState(() {
      for (final row in _ingredients) {
        applyMeasurementSystemToRow(row, next);
      }
      for (final row in _sauceIngredients) {
        applyMeasurementSystemToRow(row, next);
      }
    });
  }

  /// Rebuilds the recipe sheet and, when open, the ingredients dialog overlay.
  void _notifyIngredientUi(StateSetter? dialogSetState, VoidCallback fn) {
    setState(fn);
    dialogSetState?.call(() {});
  }

  bool _isIngredientRowComplete(RecipeIngredientFormRow row) {
    return isRecipeIngredientRowComplete(row);
  }

  void _removeIngredientAt(int idx, [StateSetter? dialogSetState]) {
    RecipeIngredientFormRow? removed;
    setState(() {
      removed = _ingredients.removeAt(idx);
      if (_lastAddedIngredientReorderId == removed!.reorderId) {
        _lastAddedIngredientReorderId = null;
      }
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
    if (removed != null) {
      _disposeIngredientRowsAfterFrame([removed!]);
    }
  }

  void _removeSauceIngredientAt(int idx, [StateSetter? dialogSetState]) {
    RecipeIngredientFormRow? removed;
    setState(() {
      removed = _sauceIngredients.removeAt(idx);
      if (_lastAddedSauceIngredientReorderId == removed!.reorderId) {
        _lastAddedSauceIngredientReorderId = null;
      }
      _validationMessage = null;
      if (_sauceIngredients.isEmpty) {
        _selectedSauceIngredientIndex = null;
      } else if (_selectedSauceIngredientIndex != null) {
        final sel = _selectedSauceIngredientIndex!;
        if (idx < sel) {
          _selectedSauceIngredientIndex = sel - 1;
        } else if (idx == sel) {
          _selectedSauceIngredientIndex =
              idx.clamp(0, _sauceIngredients.length - 1);
        }
      }
    });
    dialogSetState?.call(() {});
    if (removed != null) {
      _disposeIngredientRowsAfterFrame([removed!]);
    }
  }

  void _onIngredientsReorder(int oldIndex, int newIndex) {
    setState(() {
      final selectedId = _selectedIngredientIndex != null
          ? _ingredients[_selectedIngredientIndex!].reorderId
          : null;
      if (newIndex > oldIndex) newIndex--;
      final item = _ingredients.removeAt(oldIndex);
      _ingredients.insert(newIndex, item);
      if (selectedId != null) {
        final i = _ingredients.indexWhere((e) => e.reorderId == selectedId);
        _selectedIngredientIndex = i >= 0 ? i : null;
      }
      _validationMessage = null;
    });
  }

  void _onSauceIngredientsReorder(int oldIndex, int newIndex) {
    setState(() {
      final selectedId = _selectedSauceIngredientIndex != null
          ? _sauceIngredients[_selectedSauceIngredientIndex!].reorderId
          : null;
      if (newIndex > oldIndex) newIndex--;
      final item = _sauceIngredients.removeAt(oldIndex);
      _sauceIngredients.insert(newIndex, item);
      if (selectedId != null) {
        final i =
            _sauceIngredients.indexWhere((e) => e.reorderId == selectedId);
        _selectedSauceIngredientIndex = i >= 0 ? i : null;
      }
      _validationMessage = null;
    });
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

  bool get _canAddAnotherSauceIngredient {
    if (_sauceIngredients.isEmpty) return true;
    final rid = _lastAddedSauceIngredientReorderId;
    if (rid != null) {
      final idx = _sauceIngredients.indexWhere((e) => e.reorderId == rid);
      if (idx >= 0) {
        return _isIngredientRowComplete(_sauceIngredients[idx]);
      }
    }
    return _sauceIngredients.every(_isIngredientRowComplete);
  }

  String _ingredientSummary(RecipeIngredientFormRow row) {
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

  /// Pill chip for saved ingredients; fill/border match Create Recipe header blues.
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
              color: _kCreateRecipeBlueLight,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _kCreateRecipeBlueMid,
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 10, right: 4, top: 8, bottom: 8),
              child: Row(
                children: [
                  row.namePickedFromSuggestions && row.name.isNotEmpty
                      ? ingredientPickedFoodIcon(context, ref, row, size: 22)
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

  Widget _buildSauceIngredientSavedChip(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final row = _sauceIngredients[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _editSauceIngredientAt(i),
          child: Ink(
            decoration: BoxDecoration(
              color: _kCreateRecipeBlueLight,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _kCreateRecipeBlueMid,
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 10, right: 4, top: 8, bottom: 8),
              child: Row(
                children: [
                  row.namePickedFromSuggestions && row.name.isNotEmpty
                      ? ingredientPickedFoodIcon(context, ref, row, size: 22)
                      : Icon(
                          Icons.water_drop_outlined,
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
                    onPressed: () => _removeSauceIngredientAt(i),
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
    RecipeIngredientFormRow row, {
    StateSetter? dialogSetState,
    VoidCallback? onRemovePressed,
    EdgeInsetsGeometry cardMargin =
        const EdgeInsets.only(bottom: AppSpacing.sm),
    void Function(int, [StateSetter?])? onRemoveIngredientAt,
  }) {
    return buildRecipeIngredientEditorBody(
      context,
      ref,
      row: row,
      index: idx,
      ingredientCardKey: _ingredientExpandedCardKey,
      notifyUi: (fn) => _notifyIngredientUi(dialogSetState, fn),
      onMeasurementSystemChanged: (s) {
        _applyMeasurementSystem(s);
        dialogSetState?.call(() {});
      },
      onRemovePressed: onRemovePressed,
      onRemoveIngredientAt: onRemoveIngredientAt ?? _removeIngredientAt,
      dialogSetState: dialogSetState,
      cardMargin: cardMargin,
    );
  }

  void _removeDirectionAt(int idx, {bool sauce = false}) {
    final drafts = sauce ? _sauceDirectionDrafts : _directionDrafts;
    if (drafts.length <= 1) return;
    RecipeDirectionDraft? removed;
    setState(() {
      removed = drafts.removeAt(idx);
      _validationMessage = null;
    });
    if (removed != null) {
      _disposeDirectionDraftsAfterFrame([removed!]);
    }
  }

  void _onDirectionsReorder(int oldIndex, int newIndex, {bool sauce = false}) {
    setState(() {
      final drafts = sauce ? _sauceDirectionDrafts : _directionDrafts;
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = drafts.removeAt(oldIndex);
      drafts.insert(newIndex, moved);
      _validationMessage = null;
    });
  }

  bool _isDirectionStepComplete(RecipeDirectionDraft draft) {
    return isRecipeDirectionStepComplete(draft);
  }

  Future<void> _addDirectionAndOpenModal() async {
    await _addDirectionAndOpenModalFor(sauce: false);
  }

  Future<void> _addSauceDirectionAndOpenModal() async {
    await _addDirectionAndOpenModalFor(sauce: true);
  }

  Future<void> _addDirectionAndOpenModalFor({required bool sauce}) async {
    if (!_canAddAnotherDirectionFor(sauce)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      final drafts = sauce ? _sauceDirectionDrafts : _directionDrafts;
      drafts.add(RecipeDirectionDraft());
      _validationMessage = null;
    });
    final drafts = sauce ? _sauceDirectionDrafts : _directionDrafts;
    final newIndex = drafts.length - 1;
    await _showDirectionEditorModal(
      index: newIndex,
      isNewDraft: true,
      sauce: sauce,
    );
  }

  Future<void> _editDirectionAt(int i) async {
    if (i < 0 || i >= _directionDrafts.length) return;
    FocusScope.of(context).unfocus();
    await _showDirectionEditorModal(
      index: i,
      isNewDraft: false,
      sauce: false,
    );
  }

  Future<void> _editSauceDirectionAt(int i) async {
    if (i < 0 || i >= _sauceDirectionDrafts.length) return;
    FocusScope.of(context).unfocus();
    await _showDirectionEditorModal(
      index: i,
      isNewDraft: false,
      sauce: true,
    );
  }

  Future<void> _showDirectionEditorModal({
    required int index,
    required bool isNewDraft,
    bool sauce = false,
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
            final drafts = sauce ? _sauceDirectionDrafts : _directionDrafts;
            if (index < 0 || index >= drafts.length) {
              return const SizedBox.shrink();
            }
            final draft = drafts[index];
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
              if (!_isDirectionStepComplete(draft)) return;
              popDialog();
            }

            void removeThenClose() {
              popDialog();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                if (index >= 0 && index < drafts.length) {
                  _removeDirectionAt(index, sauce: sauce);
                }
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
                        data: themeForRecipeEditorModal(dialogCtx),
                        child: Scaffold(
                          resizeToAvoidBottomInset: false,
                          appBar: AppBar(
                            title: Text(
                              isNewDraft
                                  ? (sauce
                                      ? 'Add ${_sauceOrIcingLabel.toLowerCase()} step'
                                      : 'Add step')
                                  : (sauce
                                      ? '$_sauceOrIcingLabel step ${index + 1}'
                                      : 'Step ${index + 1}'),
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
                              16 + MediaQuery.viewInsetsOf(dialogCtx).bottom,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildExpandedDirectionRow(
                                  dialogCtx,
                                  index,
                                  draft,
                                  dialogSetState: setModalState,
                                  onRemovePressed: removeThenClose,
                                  cardMargin: EdgeInsets.zero,
                                  sauce: sauce,
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
                                            _isDirectionStepComplete(draft)
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
    final draftsAfter = sauce ? _sauceDirectionDrafts : _directionDrafts;
    if (isNewDraft &&
        index >= 0 &&
        index < draftsAfter.length &&
        !_isDirectionStepComplete(draftsAfter[index])) {
      _removeDirectionAt(index, sauce: sauce);
    }
    setState(() {});
  }

  bool _canAddAnotherDirectionFor(bool sauce) {
    final drafts = sauce ? _sauceDirectionDrafts : _directionDrafts;
    if (drafts.isEmpty) return true;
    final last = drafts.last;
    return last.textCtrl.text.trim().isNotEmpty;
  }

  bool get _canAddAnotherDirection {
    return _canAddAnotherDirectionFor(false);
  }

  String _directionSummary(RecipeDirectionDraft draft) {
    final t = draft.textCtrl.text.trim();
    if (t.isEmpty) return 'New step';
    return t;
  }

  Widget _buildCondensedDirectionRow(
    BuildContext context,
    int idx,
    RecipeDirectionDraft draft, {
    bool wrapWithBottomPadding = true,
    bool sauce = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => unawaited(
          sauce ? _editSauceDirectionAt(idx) : _editDirectionAt(idx),
        ),
        child: Ink(
          decoration: BoxDecoration(
            color: _kCreateRecipeBlueLight,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _kCreateRecipeBlueMid),
          ),
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
                  onPressed: () => _removeDirectionAt(idx, sauce: sauce),
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
    if (!wrapWithBottomPadding) return chip;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: chip,
    );
  }

  Widget _buildExpandedDirectionRow(
    BuildContext context,
    int idx,
    RecipeDirectionDraft draft, {
    StateSetter? dialogSetState,
    VoidCallback? onRemovePressed,
    EdgeInsetsGeometry cardMargin =
        const EdgeInsets.only(bottom: AppSpacing.sm),
    bool sauce = false,
  }) {
    final drafts = sauce ? _sauceDirectionDrafts : _directionDrafts;
    return buildRecipeDirectionStepBody(
      context,
      draft: draft,
      stepIndex: idx,
      showRemoveButton: drafts.length > 1,
      notifyUi: (fn) {
        fn();
        dialogSetState?.call(() {});
        if (dialogSetState == null) setState(() {});
      },
      onRemovePressed: onRemovePressed,
      cardMargin: cardMargin,
    );
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
      final amt = parseRecipeIngredientAmount(row.amountCtrl.text);
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
        _nutritionEditMode = _NutritionEditMode.auto;
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

  void _syncManualFieldsFromEstimatedTotals() {
    final servings =
        (_parseIntOrNull(_servingsCtrl.text) ?? 2).clamp(1, 999999);
    final n = _estimatedNutrition;
    if (nutritionHasAnyTotals(n) && servings > 0) {
      final ps = perServingNutritionFromRecipeTotals(n, servings);
      _manualCaloriesCtrl.text = '${ps.calories}';
      _manualProteinCtrl.text = ps.protein.toStringAsFixed(1);
      _manualFatCtrl.text = ps.fat.toStringAsFixed(1);
      _manualCarbsCtrl.text = ps.carbs.toStringAsFixed(1);
      _manualFiberCtrl.text = ps.fiber.toStringAsFixed(1);
      _manualSugarCtrl.text = ps.sugar.toStringAsFixed(1);
    }
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
            parseRecipeIngredientAmount(row.amountCtrl.text) == null ||
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

    if (_step == 4 && _sauceEnabled) {
      if (_sauceIngredients.isEmpty) {
        setState(() => _validationMessage =
            'Add at least one ${_sauceOrIcingLabel.toLowerCase()} ingredient.');
        return false;
      }
      final hasSauceIssue = _sauceIngredients.any((row) {
        if (row.nameCtrl.text.trim().isEmpty) return true;
        if (row.qualitative) {
          return row.resolvedQualitativePhrase().isEmpty;
        }
        return row.amountCtrl.text.trim().isEmpty ||
            parseRecipeIngredientAmount(row.amountCtrl.text) == null ||
            row.selectedUnit.trim().isEmpty ||
            (row.selectedUnit == 'custom' &&
                row.customUnitCtrl.text.trim().isEmpty);
      });
      if (hasSauceIssue) {
        setState(() => _validationMessage =
            'Each ${_sauceOrIcingLabel.toLowerCase()} ingredient needs a name and a valid amount (or To taste).');
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
          parseRecipeIngredientAmount(row.amountCtrl.text) == null ||
          row.selectedUnit.trim().isEmpty ||
          (row.selectedUnit == 'custom' &&
              row.customUnitCtrl.text.trim().isEmpty);
    });
    if (hasIssue) {
      setState(() => _validationMessage =
          'Each ingredient needs a name and a valid amount (or To taste).');
      return false;
    }
    if (_sauceEnabled) {
      if (_sauceIngredients.isEmpty) {
        setState(() => _validationMessage =
            'Add at least one ${_sauceOrIcingLabel.toLowerCase()} ingredient.');
        return false;
      }
      final hasSauceIssue = _sauceIngredients.any((row) {
        if (row.nameCtrl.text.trim().isEmpty) return true;
        if (row.qualitative) {
          return row.resolvedQualitativePhrase().isEmpty;
        }
        return row.amountCtrl.text.trim().isEmpty ||
            parseRecipeIngredientAmount(row.amountCtrl.text) == null ||
            row.selectedUnit.trim().isEmpty ||
            (row.selectedUnit == 'custom' &&
                row.customUnitCtrl.text.trim().isEmpty);
      });
      if (hasSauceIssue) {
        setState(() => _validationMessage =
            'Each ${_sauceOrIcingLabel.toLowerCase()} ingredient needs a name and a valid amount (or To taste).');
        return false;
      }
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
    if ((a.amount - b.amount).abs() > kRecipeIngredientAmountEpsilon) {
      return false;
    }
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
    final de = draft.embeddedSauce;
    final be = baseline.embeddedSauce;
    if (de == null && be == null) return true;
    if (de == null || be == null) return false;
    return _embeddedSaucePersistedEquals(de, be);
  }

  bool _embeddedSaucePersistedEquals(
    RecipeEmbeddedSauce a,
    RecipeEmbeddedSauce b,
  ) {
    if ((a.title ?? '').trim() != (b.title ?? '').trim()) return false;
    if (a.ingredients.length != b.ingredients.length) return false;
    for (var i = 0; i < a.ingredients.length; i++) {
      if (!_ingredientPersistedEquals(a.ingredients[i], b.ingredients[i])) {
        return false;
      }
    }
    if (!const ListEquality<String>().equals(a.instructions, b.instructions)) {
      return false;
    }
    return true;
  }

  bool get _hasUnsavedEdits {
    final initial = widget.initialRecipe;
    if (initial == null) return false;
    return !_persistedRecipesEqual(_recipeFromForm(), initial);
  }

  List<Ingredient> _ingredientsFromRows(List<RecipeIngredientFormRow> rows) {
    return rows.map((row) {
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
        amount: parseRecipeIngredientAmount(row.amountCtrl.text) ?? 0,
        unit: unit,
        category: GroceryCategory.other,
      );
    }).toList();
  }

  RecipeEmbeddedSauce? _embeddedSauceFromForm() {
    if (!_sauceEnabled) return null;
    final ingredients = _ingredientsFromRows(_sauceIngredients);
    if (ingredients.isEmpty) return null;
    final directions = _sauceDirectionDrafts
        .map((d) => d.textCtrl.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final rawMain = _titleCtrl.text.trim();
    final formattedMain = formatRecipeTitlePerWord(rawMain);
    final mainTitle = widget.initialRecipe != null ? rawMain : formattedMain;
    final rawSauce = _sauceTitleCtrl.text.trim();
    final defaultSingle =
        _mealType == MealType.dessert ? 'Sauce or Icing' : 'Sauce';
    final suffix = _mealType == MealType.dessert ? 'sauce or icing' : 'sauce';
    final sauceTitle = rawSauce.isEmpty
        ? (mainTitle.isEmpty ? defaultSingle : '$mainTitle — $suffix')
        : (widget.initialRecipe != null
            ? rawSauce
            : formatRecipeTitlePerWord(rawSauce));
    return RecipeEmbeddedSauce(
      title: sauceTitle,
      ingredients: ingredients,
      instructions: directions,
    );
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
          amount: parseRecipeIngredientAmount(row.amountCtrl.text) ?? 0,
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
    if (_nutritionEditMode == _NutritionEditMode.manual) {
      final s = (_parseIntOrNull(_servingsCtrl.text) ?? 2).clamp(1, 999999);
      recipeNutrition = recipeNutritionTotalsFromPerServing(
        caloriesPerServing: int.tryParse(_manualCaloriesCtrl.text.trim()) ?? 0,
        proteinPerServing: double.tryParse(_manualProteinCtrl.text.trim()) ?? 0,
        fatPerServing: double.tryParse(_manualFatCtrl.text.trim()) ?? 0,
        carbsPerServing: double.tryParse(_manualCarbsCtrl.text.trim()) ?? 0,
        fiberPerServing: double.tryParse(_manualFiberCtrl.text.trim()) ?? 0,
        sugarPerServing: double.tryParse(_manualSugarCtrl.text.trim()) ?? 0,
        servings: s,
      );
      recipeNutritionSource = 'manual';
    } else if (_nutritionError != null) {
      recipeNutrition = initial?.nutrition ?? const Nutrition();
      recipeNutritionSource = initial?.nutritionSource;
    } else {
      recipeNutrition = _estimatedNutrition;
      recipeNutritionSource = _nutritionEstimateSource;
    }

    final rawTitle = _titleCtrl.text.trim();
    final formattedTitle = formatRecipeTitlePerWord(rawTitle);
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
          : (initial != null &&
                  initial.visibility == RecipeVisibility.household)
              ? RecipeVisibility.household
              : RecipeVisibility.personal,
      source: initial?.source ?? 'user_created',
      userId: initial?.userId,
      householdId: initial?.householdId,
      apiId: initial?.apiId,
      nutritionSource: recipeNutritionSource,
      embeddedSauce: _embeddedSauceFromForm(),
      defaultSauceRecipeId: null,
    );
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    FocusScope.of(context).unfocus();
    if (_step >= _finalPageIndex) {
      _submit();
      return;
    }
    setState(() {
      _step += 1;
      if (widget.initialRecipe == null &&
          _step == _nutritionPageIndex &&
          _nutritionEditMode == _NutritionEditMode.auto &&
          !nutritionHasAnyTotals(_estimatedNutrition)) {
        _nutritionAwaitingManualCalculate = true;
      }
    });
    ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
    _stepCtrl.animateToPage(
      _step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _prevStep() {
    if (_step == 0) return;
    setState(() {
      _step -= 1;
    });
    ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
    _stepCtrl.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _submit() {
    if (_isSubmitting) return;
    if (!_validateAllStepsForSave()) return;

    final recipe = _recipeFromForm();
    if (recipe.ingredients.isEmpty) {
      setState(() {
        _validationMessage = 'Add at least one ingredient.';
      });
      return;
    }

    setState(() {
      _validationMessage = null;
      _isSubmitting = true;
    });

    final hasShared = ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
    final isCreate = widget.initialRecipe == null;
    final copyToHousehold =
        isCreate && hasShared && _saveToHousehold && !_makePublic;
    final saveResult = RecipeBuilderSaveResult(
      recipe: recipe,
      copyToHousehold: copyToHousehold,
      householdFavorite: _householdFavorite,
      householdToTry: _householdToTry,
    );
    // Pop on the next frame so this [setState] build finishes before the route is
    // removed (same-frame setState + pop can trigger `_dependents.isEmpty` asserts).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // #region agent log
      _recipeBuilderSheetDebugLog(
        'H2',
        'recipes_screen.dart:_submit:pfb',
        'post-frame before closeWizard',
        {'mounted': mounted},
      );
      // #endregion
      if (!mounted) return;
      _closeWizard(saveResult);
    });
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

    final manualTotalsPreview = recipeNutritionTotalsFromPerServing(
      caloriesPerServing: int.tryParse(_manualCaloriesCtrl.text.trim()) ?? 0,
      proteinPerServing: double.tryParse(_manualProteinCtrl.text.trim()) ?? 0,
      fatPerServing: double.tryParse(_manualFatCtrl.text.trim()) ?? 0,
      carbsPerServing: double.tryParse(_manualCarbsCtrl.text.trim()) ?? 0,
      fiberPerServing: double.tryParse(_manualFiberCtrl.text.trim()) ?? 0,
      sugarPerServing: double.tryParse(_manualSugarCtrl.text.trim()) ?? 0,
      servings: servings,
    );

    Widget manualField({
      required String label,
      required TextEditingController controller,
      TextInputType? keyboardType,
    }) {
      return TextField(
        controller: controller,
        keyboardType: keyboardType ??
            const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SectionCard(
              title: 'Nutrition',
              subtitle: _nutritionEditMode == _NutritionEditMode.manual
                  ? 'Enter per-serving values. Stored totals scale with servings ($servings). Not medical advice.'
                  : 'Approximate totals for the full recipe (all servings). Tap '
                      'Calculate to estimate, or Next to skip. Not medical advice.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<_NutritionEditMode>(
                    emptySelectionAllowed: false,
                    segments: const [
                      ButtonSegment(
                        value: _NutritionEditMode.auto,
                        label: Text('Auto'),
                        icon: Icon(Icons.calculate_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _NutritionEditMode.manual,
                        label: Text('Manual'),
                        icon: Icon(Icons.edit_note_rounded, size: 18),
                      ),
                    ],
                    selected: {_nutritionEditMode},
                    onSelectionChanged: (Set<_NutritionEditMode> next) {
                      setState(() {
                        _nutritionEditMode = next.first;
                        if (_nutritionEditMode == _NutritionEditMode.manual) {
                          _nutritionError = null;
                          _syncManualFieldsFromEstimatedTotals();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_nutritionEditMode == _NutritionEditMode.manual) ...[
                    Text(
                      'Per serving',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    manualField(
                      label: 'Calories (kcal)',
                      controller: _manualCaloriesCtrl,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    manualField(
                      label: 'Protein (g)',
                      controller: _manualProteinCtrl,
                    ),
                    const SizedBox(height: 8),
                    manualField(
                      label: 'Fat (g)',
                      controller: _manualFatCtrl,
                    ),
                    const SizedBox(height: 8),
                    manualField(
                      label: 'Carbs (g)',
                      controller: _manualCarbsCtrl,
                    ),
                    const SizedBox(height: 8),
                    manualField(
                      label: 'Fiber (g)',
                      controller: _manualFiberCtrl,
                    ),
                    const SizedBox(height: 8),
                    manualField(
                      label: 'Sugar (g)',
                      controller: _manualSugarCtrl,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Recipe totals (all servings)',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Calories (total)',
                      value: '${manualTotalsPreview.calories}',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.fitness_center_rounded,
                      label: 'Protein (total)',
                      value:
                          '${manualTotalsPreview.protein.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.opacity_rounded,
                      label: 'Fat (total)',
                      value: '${manualTotalsPreview.fat.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.grain_rounded,
                      label: 'Carbs (total)',
                      value:
                          '${manualTotalsPreview.carbs.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.grass_rounded,
                      label: 'Fiber (total)',
                      value:
                          '${manualTotalsPreview.fiber.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 8),
                    tile(
                      icon: Icons.cake_rounded,
                      label: 'Sugar (total)',
                      value:
                          '${manualTotalsPreview.sugar.toStringAsFixed(1)} g',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _nutritionLoading
                          ? null
                          : () {
                              setState(() {
                                _nutritionAwaitingManualCalculate = false;
                              });
                              unawaited(_syncNutritionEstimate());
                            },
                      icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                      label: const Text('Estimate from ingredients'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Replaces manual values with an automated estimate.',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (_nutritionAwaitingManualCalculate) ...[
                    Text(
                      'We can estimate calories and macros from your '
                      'ingredient list. This is optional—use Next to continue '
                      'without estimating.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _nutritionAwaitingManualCalculate = false;
                        });
                        unawaited(_syncNutritionEstimate());
                      },
                      icon: const Icon(Icons.calculate_rounded, size: 20),
                      label: const Text('Calculate'),
                    ),
                  ] else if (_nutritionLoading)
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
                      _nutritionEditMode == _NutritionEditMode.auto &&
                      !_nutritionAwaitingManualCalculate &&
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

  Future<void> _addIngredientAndOpenModal() async {
    await _addIngredientAndOpenModalFor(_RecipeIngredientSection.main);
  }

  Future<void> _addSauceIngredientAndOpenModal() async {
    await _addIngredientAndOpenModalFor(_RecipeIngredientSection.sauce);
  }

  Future<void> _addIngredientAndOpenModalFor(
    _RecipeIngredientSection section,
  ) async {
    final canAdd = section == _RecipeIngredientSection.main
        ? _canAddAnotherIngredient
        : _canAddAnotherSauceIngredient;
    if (!canAdd) return;
    FocusScope.of(context).unfocus();
    final profile = detectUnitProfile(
      '',
      ref.read(measurementSystemProvider),
    );
    final row = RecipeIngredientFormRow(
      name: '',
      unitOptions: profile.options,
      selectedUnit: profile.defaultUnit,
    );
    final draftRid = row.reorderId;
    setState(() {
      if (section == _RecipeIngredientSection.main) {
        _ingredients.add(row);
        _lastAddedIngredientReorderId = draftRid;
        _selectedIngredientIndex = _ingredients.length - 1;
      } else {
        _sauceIngredients.add(row);
        _lastAddedSauceIngredientReorderId = draftRid;
        _selectedSauceIngredientIndex = _sauceIngredients.length - 1;
      }
      _validationMessage = null;
    });
    final listLen = section == _RecipeIngredientSection.main
        ? _ingredients.length
        : _sauceIngredients.length;
    await _showIngredientEditorModal(
      section: section,
      index: listLen - 1,
      isNewDraft: true,
      draftReorderId: draftRid,
    );
  }

  Future<void> _editIngredientAt(int i) async {
    if (i < 0 || i >= _ingredients.length) return;
    FocusScope.of(context).unfocus();
    setState(() => _selectedIngredientIndex = i);
    await _showIngredientEditorModal(
      section: _RecipeIngredientSection.main,
      index: i,
      isNewDraft: false,
    );
  }

  Future<void> _editSauceIngredientAt(int i) async {
    if (i < 0 || i >= _sauceIngredients.length) return;
    FocusScope.of(context).unfocus();
    setState(() => _selectedSauceIngredientIndex = i);
    await _showIngredientEditorModal(
      section: _RecipeIngredientSection.sauce,
      index: i,
      isNewDraft: false,
    );
  }

  Future<void> _showIngredientEditorModal({
    required _RecipeIngredientSection section,
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
            final list = section == _RecipeIngredientSection.main
                ? _ingredients
                : _sauceIngredients;
            final onRemoveAt = section == _RecipeIngredientSection.main
                ? _removeIngredientAt
                : _removeSauceIngredientAt;
            if (index < 0 || index >= list.length) {
              return const SizedBox.shrink();
            }
            final row = list[index];
            final rid = row.reorderId;
            final topPad = MediaQuery.paddingOf(dialogCtx).top + 8;
            final maxH = MediaQuery.sizeOf(dialogCtx).height - topPad - 16;
            final width = MediaQuery.sizeOf(dialogCtx).width;
            void popDialog() {
              // #region agent log
              _recipeBuilderSheetDebugLog(
                'DIALOG_POP',
                'recipes_screen.dart:popDialog',
                'popping ingredient dialog',
                {'rowName': row.nameCtrl.text, 'section': section.name},
              );
              // #endregion
              Navigator.of(dialogCtx).pop();
            }

            void onCancel() {
              popDialog();
            }

            void onSave() {
              if (!_isIngredientRowComplete(row)) return;
              popDialog();
            }

            void removeThenClose() {
              popDialog();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final i = list.indexWhere((e) => e.reorderId == rid);
                if (i >= 0) onRemoveAt(i);
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
                        data: themeForRecipeEditorModal(dialogCtx),
                        child: Scaffold(
                          resizeToAvoidBottomInset: false,
                          appBar: AppBar(
                            title: Text(
                              isNewDraft
                                  ? 'Add ingredient'
                                  : (section == _RecipeIngredientSection.sauce
                                      ? '$_sauceOrIcingLabel ingredient'
                                      : 'Ingredient'),
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
                              16 + MediaQuery.viewInsetsOf(dialogCtx).bottom,
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
                                  onRemoveIngredientAt: onRemoveAt,
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
                                        onPressed: _isIngredientRowComplete(row)
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
    // #region agent log
    _recipeBuilderSheetDebugLog(
      'POST_DIALOG',
      'recipes_screen.dart:_showIngredientEditorModal:afterDialog',
      'showDialog returned',
      {'mounted': mounted, 'isNewDraft': isNewDraft, 'section': section.name},
    );
    // #endregion
    if (!mounted) return;
    if (isNewDraft && draftReorderId != null) {
      final list = section == _RecipeIngredientSection.main
          ? _ingredients
          : _sauceIngredients;
      final onRemove = section == _RecipeIngredientSection.main
          ? _removeIngredientAt
          : _removeSauceIngredientAt;
      final i = list.indexWhere((e) => e.reorderId == draftReorderId);
      if (i >= 0 && !_isIngredientRowComplete(list[i])) {
        onRemove(i);
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
            'Tap a chip to edit, or Add ingredient. Drag the handle on the left '
            'to reorder. Use Save in the editor when you are finished. '
            'Switching Metric / US converts amounts and updates unit choices.',
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
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: _onIngredientsReorder,
                itemCount: _ingredients.length,
                itemBuilder: (context, i) {
                  return KeyedSubtree(
                    key: ValueKey(_ingredients[i].reorderId),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Tooltip(
                          message: 'Drag to reorder',
                          child: ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 22,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _buildIngredientSavedChip(context, i),
                        ),
                      ],
                    ),
                  );
                },
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

  /// Sauce/icing step (index 4); only included in [PageView] when [_sauceEnabled].
  Widget _buildSauceStepPage() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final label = _sauceOrIcingLabel;
    return SingleChildScrollView(
      child: SectionCard(
        title: label,
        subtitle:
            'Name, ingredients, and steps. Same servings as the main recipe.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _skipSauceStep,
                child: Text(
                  'Skip — don\'t add ${label.toLowerCase()}',
                ),
              ),
            ),
            TextField(
              controller: _sauceTitleCtrl,
              textCapitalization: TextCapitalization.sentences,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: InputDecoration(
                labelText: '$label name (optional)',
                hintText: _mealType == MealType.dessert
                    ? 'e.g., Cream cheese frosting'
                    : 'e.g., Lemon pan sauce',
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$label ingredients',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_sauceIngredients.isEmpty)
              Text(
                'No ${label.toLowerCase()} ingredients yet.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorder: _onSauceIngredientsReorder,
                itemCount: _sauceIngredients.length,
                itemBuilder: (context, i) {
                  return KeyedSubtree(
                    key: ValueKey(_sauceIngredients[i].reorderId),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Tooltip(
                          message: 'Drag to reorder',
                          child: ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 22,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _buildSauceIngredientSavedChip(context, i),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _canAddAnotherSauceIngredient
                  ? _addSauceIngredientAndOpenModal
                  : null,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: Text('Add ${label.toLowerCase()} ingredient'),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$label directions (optional)',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (o, n) => _onDirectionsReorder(o, n, sauce: true),
              itemCount: _sauceDirectionDrafts.length,
              itemBuilder: (context, i) {
                final draft = _sauceDirectionDrafts[i];
                return KeyedSubtree(
                  key: ObjectKey(draft),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Tooltip(
                          message: 'Drag to reorder',
                          child: ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 22,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _buildCondensedDirectionRow(
                            context,
                            i,
                            draft,
                            wrapWithBottomPadding: false,
                            sauce: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _canAddAnotherDirectionFor(true)
                    ? _addSauceDirectionAndOpenModal
                    : null,
                icon: const Icon(Icons.add),
                label: Text('Add ${label.toLowerCase()} step'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepTitle = _headerStepTitle();

    final topObstruction = MediaQuery.viewPaddingOf(context).top;
    return Material(
      color: scheme.surface,
      child: WillPopScope(
        onWillPop: () async => false,
        child: SafeArea(
          minimum: EdgeInsets.only(top: topObstruction),
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
                            _kCreateRecipeBlueLight,
                            _kCreateRecipeBlueMid,
                            _kCreateRecipeBlueDeep,
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
                              value: (_step + 1) / _pageCount,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: List.generate(
                              _pageCount,
                              (index) => Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(
                                      right: index == _pageCount - 1 ? 0 : 6),
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
                              textCapitalization: widget.initialRecipe != null
                                  ? TextCapitalization.sentences
                                  : (_recipeTitleLowercaseTyping
                                      ? TextCapitalization.none
                                      : TextCapitalization.words),
                              inputFormatters: widget.initialRecipe == null
                                  ? [
                                      RecipeTitlePerWordInputFormatter(
                                        lowercaseTyping:
                                            _recipeTitleLowercaseTyping,
                                      ),
                                    ]
                                  : null,
                              onTapOutside: (_) =>
                                  FocusScope.of(context).unfocus(),
                              decoration: InputDecoration(
                                labelText: 'Recipe name',
                                hintText: 'e.g., Spicy Garlic Chicken Pasta',
                                suffixIcon: widget.initialRecipe == null
                                    ? IconButton(
                                        icon: Icon(
                                          _recipeTitleLowercaseTyping
                                              ? Icons.title_rounded
                                              : Icons.text_fields_rounded,
                                        ),
                                        tooltip: _recipeTitleLowercaseTyping
                                            ? 'Title case while typing'
                                            : 'Lowercase while typing',
                                        onPressed: () {
                                          setState(() {
                                            if (_recipeTitleLowercaseTyping) {
                                              _recipeTitleLowercaseTyping =
                                                  false;
                                              _titleCtrl.text =
                                                  formatRecipeTitlePerWord(
                                                _titleCtrl.text,
                                              );
                                              _titleCtrl.selection =
                                                  TextSelection.collapsed(
                                                offset: _titleCtrl.text.length,
                                              );
                                            } else {
                                              _recipeTitleLowercaseTyping =
                                                  true;
                                            }
                                          });
                                        },
                                      )
                                    : null,
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
                                              onSelected: (_) {
                                                setState(() {
                                                  final prev = _mealType;
                                                  _mealType = type;
                                                  if (type == MealType.sauce &&
                                                      prev != MealType.sauce) {
                                                    final wasEnabled =
                                                        _sauceEnabled;
                                                    _sauceEnabled = false;
                                                    _clearSauceDraft();
                                                    if (wasEnabled &&
                                                        _step > 4) {
                                                      _step--;
                                                    }
                                                  }
                                                });
                                                if (type == MealType.sauce) {
                                                  _scheduleStepPageSync();
                                                }
                                              },
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_mealType != MealType.sauce)
                                  SectionCard(
                                    title: _mealType == MealType.dessert
                                        ? 'Sauce or Icing'
                                        : 'Sauce',
                                    subtitle: _mealType == MealType.dessert
                                        ? 'Does this recipe have a sauce or icing?'
                                        : 'Does this recipe have a sauce?',
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: SegmentedButton<bool>(
                                        showSelectedIcon: false,
                                        segments: const [
                                          ButtonSegment<bool>(
                                            value: false,
                                            label: Text('No'),
                                            icon: Icon(Icons.close_rounded,
                                                size: 18),
                                          ),
                                          ButtonSegment<bool>(
                                            value: true,
                                            label: Text('Yes'),
                                            icon: Icon(Icons.check_rounded,
                                                size: 18),
                                          ),
                                        ],
                                        selected: {_sauceEnabled},
                                        onSelectionChanged: (Set<bool> next) {
                                          final v = next.first;
                                          final wasEnabled = _sauceEnabled;
                                          setState(() {
                                            _sauceEnabled = v;
                                            if (!v) {
                                              _clearSauceDraft();
                                              if (wasEnabled && _step > 4) {
                                                _step--;
                                              }
                                            } else {
                                              if (_sauceTitleCtrl.text
                                                      .trim()
                                                      .isEmpty &&
                                                  _titleCtrl.text
                                                      .trim()
                                                      .isNotEmpty) {
                                                final m =
                                                    _titleCtrl.text.trim();
                                                _sauceTitleCtrl.text =
                                                    _mealType ==
                                                            MealType.dessert
                                                        ? '$m — sauce or icing'
                                                        : '$m — sauce';
                                              }
                                              if (!wasEnabled && _step >= 4) {
                                                _step++;
                                              }
                                            }
                                          });
                                          _scheduleStepPageSync();
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _buildIngredientStepPage(),
                          _StepCard(
                            title: 'Directions (optional)',
                            subtitle:
                                'Tap a step to edit, or Add step. Drag the handle on '
                                'the left to reorder steps. Use Save in the editor '
                                'when you are finished.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  onReorder: _onDirectionsReorder,
                                  itemCount: _directionDrafts.length,
                                  itemBuilder: (context, i) {
                                    final draft = _directionDrafts[i];
                                    return KeyedSubtree(
                                      key: ObjectKey(draft),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: AppSpacing.xs,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Tooltip(
                                              message: 'Drag to reorder',
                                              child:
                                                  ReorderableDragStartListener(
                                                index: i,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    right: 6,
                                                  ),
                                                  child: Icon(
                                                    Icons.drag_handle_rounded,
                                                    size: 22,
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Expanded(
                                              child:
                                                  _buildCondensedDirectionRow(
                                                context,
                                                i,
                                                draft,
                                                wrapWithBottomPadding: false,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _canAddAnotherDirection
                                        ? _addDirectionAndOpenModal
                                        : null,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add step'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_sauceEnabled) _buildSauceStepPage(),
                          _buildNutritionStepPage(),
                          _StepCard(
                            title: 'Final touches',
                            child: Builder(
                              builder: (context) {
                                final isCreate = widget.initialRecipe == null;
                                final hasShared = ref
                                        .watch(hasSharedHouseholdProvider)
                                        .valueOrNull ??
                                    false;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'My Recipes',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
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
                                        'Show under Favorites on My Recipes.',
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
                                        'Show under To Try on My Recipes.',
                                      ),
                                      value: _markToTry,
                                      onChanged: (value) =>
                                          setState(() => _markToTry = value),
                                    ),
                                    if (hasShared && isCreate) ...[
                                      const Divider(height: 1),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Household',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      SwitchListTile.adaptive(
                                        contentPadding: EdgeInsets.zero,
                                        secondary: Icon(
                                          Icons.groups_2_outlined,
                                          color:
                                              _saveToHousehold && !_makePublic
                                                  ? scheme.primary
                                                  : scheme.onSurfaceVariant,
                                        ),
                                        title: const Text('Save to Household'),
                                        subtitle: Text(
                                          _makePublic
                                              ? 'Public recipes cannot be saved to household from this screen.'
                                              : 'Creates your recipe in My Recipes and a shared copy for your household.',
                                        ),
                                        value: _saveToHousehold,
                                        onChanged: _makePublic
                                            ? null
                                            : (value) => setState(() {
                                                  _saveToHousehold = value;
                                                  if (value) {
                                                    _householdFavorite =
                                                        _markFavorite;
                                                    _householdToTry =
                                                        _markToTry;
                                                  }
                                                }),
                                      ),
                                      if (_saveToHousehold && !_makePublic) ...[
                                        SwitchListTile.adaptive(
                                          contentPadding: EdgeInsets.zero,
                                          secondary: Icon(
                                            _householdFavorite
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            color: _householdFavorite
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                          ),
                                          title: const Text(
                                            'Favorite on Household Recipes',
                                          ),
                                          subtitle: const Text(
                                            'Applies to the shared household copy.',
                                          ),
                                          value: _householdFavorite,
                                          onChanged: (value) => setState(
                                              () => _householdFavorite = value),
                                        ),
                                        const Divider(height: 1),
                                        SwitchListTile.adaptive(
                                          contentPadding: EdgeInsets.zero,
                                          secondary: Icon(
                                            _householdToTry
                                                ? Icons.flag_rounded
                                                : Icons.outlined_flag_rounded,
                                            color: _householdToTry
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                          ),
                                          title: const Text(
                                            'To Try on Household Recipes',
                                          ),
                                          subtitle: const Text(
                                            'Applies to the shared household copy.',
                                          ),
                                          value: _householdToTry,
                                          onChanged: (value) => setState(
                                              () => _householdToTry = value),
                                        ),
                                      ],
                                    ],
                                    if (_kShowMakePublicRecipeOption) ...[
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
                                        onChanged: (value) => setState(() {
                                          _makePublic = value;
                                          if (value) {
                                            _saveToHousehold = false;
                                          }
                                        }),
                                      ),
                                    ],
                                  ],
                                );
                              },
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
                            icon: Icon(_step == _finalPageIndex
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded),
                            label: Text(_step == _finalPageIndex
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
