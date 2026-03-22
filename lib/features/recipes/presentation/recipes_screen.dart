import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/theme/design_tokens.dart';
import 'package:plateplan/core/theme/theme_extensions.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/recipes/presentation/recipe_creation_guard.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  final _searchCtrl = TextEditingController();
  final GlobalKey _filterChromeKey = GlobalKey();
  double? _measuredFilterChromeHeight;
  ({bool secondPills, int libraryTab})? _filterLayoutKey;
  int _libraryIndex = 0;
  int _segmentIndex = 0;
  final Set<MealType> _mealTypeFilters = {};

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
      await ref.read(recipesRepositoryProvider).create(
            user.id,
            recipe,
            shareWithHousehold: isHousehold,
            visibilityOverride: recipe.visibility,
          );
      ref.invalidate(recipesProvider);
      if (!mounted) return;
      final dest = switch (recipe.visibility) {
        RecipeVisibility.household => 'Household Recipes',
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

  /// Conservative fallback before the first layout measurement.
  double _estimateFilterChromeHeight(bool hasSecondPillRow) {
    const searchRow = 48.0;
    const gap = 4.0;
    const pills = 46.0;
    const mealBlock = 70.0;
    var h = searchRow + gap + pills;
    if (hasSecondPillRow) {
      h += gap + pills;
    }
    h += gap + mealBlock;
    return h;
  }

  void _measureFilterChromeAfterLayout() {
    if (!mounted) return;
    final box =
        _filterChromeKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if (_measuredFilterChromeHeight == null ||
        (h - _measuredFilterChromeHeight!).abs() > 0.5) {
      setState(() => _measuredFilterChromeHeight = h);
    }
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
            const SizedBox(width: 2),
            IconButton.filledTonal(
              tooltip: 'Create new recipe',
              onPressed: _createRecipeManually,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.all(6),
              ),
              icon: const Icon(Icons.add_rounded, size: 22),
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
        if (!(hasSharedHousehold && effectiveLibraryIndex == 0)) ...[
          const SizedBox(height: 4),
          SegmentedPills(
            labels: const ['Favorites', 'To Try'],
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
            Wrap(
              spacing: 5,
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
    final hasSecondPillRow =
        !(hasSharedHousehold && effectiveLibraryIndex == 0);

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [colors.surfaceBase, colors.surfaceAlt, colors.surfaceBase],
    );

    return Scaffold(
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
              visible = filtered
                  .where((r) =>
                      r.visibility == RecipeVisibility.household &&
                      r.isFavorite)
                  .toList();
            } else {
              final personal = filtered
                  .where((r) => r.visibility != RecipeVisibility.household)
                  .toList();
              final allFavorites =
                  filtered.where((r) => r.isFavorite).toList();
              final toTry = personal.where((r) => r.isToTry).toList();
              visible = switch (_segmentIndex) {
                1 => toTry,
                _ => allFavorites,
              };
            }
            final displayed =
                visible.where(_recipePassesMealFilter).toList();

            final layoutKey = (
              secondPills: hasSecondPillRow,
              libraryTab: effectiveLibraryIndex,
            );
            if (_filterLayoutKey != layoutKey) {
              _filterLayoutKey = layoutKey;
              _measuredFilterChromeHeight = null;
            }

            final headerTopPad =
                MediaQuery.paddingOf(context).top + kToolbarHeight + 2;
            final chromeHeight = _measuredFilterChromeHeight ??
                _estimateFilterChromeHeight(hasSecondPillRow);
            final minExpanded =
                MediaQuery.paddingOf(context).top + kToolbarHeight;
            final expandedHeight = math.max(
              minExpanded,
              headerTopPad + chromeHeight - 20,
            );

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _measureFilterChromeAfterLayout();
            });

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  stretch: false,
                  elevation: 0,
                  scrolledUnderElevation: 0.5,
                  shadowColor: Colors.black26,
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: colors.surfaceBase,
                  expandedHeight: expandedHeight,
                  title: const Text('Recipes'),
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.parallax,
                    stretchModes: const [],
                    background: Padding(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        headerTopPad,
                        10,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: KeyedSubtree(
                          key: _filterChromeKey,
                          child: _buildRecipesFilterHeader(
                            context: context,
                            hasSharedHousehold: hasSharedHousehold,
                            effectiveLibraryIndex: effectiveLibraryIndex,
                            libraryLabels: libraryLabels,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (displayed.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.zero,
                    sliver: SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No recipes yet. Add one in Discover or Planner.',
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _RecipeRow(
                            recipe: displayed[index],
                            hasSharedHousehold: hasSharedHousehold,
                            onEditRecipe: _editRecipe,
                          );
                        },
                        childCount: displayed.length,
                      ),
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

class _RecipeRow extends ConsumerWidget {
  const _RecipeRow({
    required this.recipe,
    required this.hasSharedHousehold,
    required this.onEditRecipe,
  });

  final Recipe recipe;
  final bool hasSharedHousehold;
  final Future<void> Function(Recipe recipe) onEditRecipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider);
    final canCopyToHousehold = user != null &&
        hasSharedHousehold &&
        recipe.visibility == RecipeVisibility.personal;
    final tags = <String>[
      _mealTypeLabel(recipe.mealType),
      '${recipe.ingredients.length} ingredients',
      '${recipe.instructions.length} steps',
    ];
    return Dismissible(
      key: ValueKey(recipe.id),
      background: Container(color: scheme.primary.withValues(alpha: 0.14)),
      secondaryBackground:
          Container(color: scheme.secondary.withValues(alpha: 0.2)),
      confirmDismiss: (dir) async {
        final repo = ref.read(recipesRepositoryProvider);
        if (dir == DismissDirection.startToEnd) {
          await repo.toggleFavorite(recipe.id, !recipe.isFavorite);
        } else {
          await repo.toggleToTry(recipe.id, !recipe.isToTry);
        }
        ref.invalidate(recipesProvider);
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RecipeListCard(
          title: recipe.title,
          meta:
              '${_mealTypeLabel(recipe.mealType)} • Serves ${recipe.servings}',
          tags: recipe.cuisineTags.isEmpty
              ? tags
              : [recipe.cuisineTags.first, ...tags],
          onTap: () => context.push('/cooking/${recipe.id}'),
          trailing: canCopyToHousehold
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () async {
                        await ref.read(recipesRepositoryProvider).toggleFavorite(
                              recipe.id,
                              !recipe.isFavorite,
                            );
                        ref.invalidate(recipesProvider);
                      },
                      icon: Icon(
                        recipe.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: recipe.isFavorite
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Recipe actions',
                      onSelected: (value) async {
                        if (value == 'edit_recipe') {
                          await onEditRecipe(recipe);
                          return;
                        }
                        if (value != 'copy_to_household') {
                          return;
                        }
                        try {
                          await ref
                              .read(recipesRepositoryProvider)
                              .copyPersonalRecipeToHousehold(
                                userId: user.id,
                                recipeId: recipe.id,
                              );
                          ref.invalidate(recipesProvider);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Shared "${recipe.title}" to Household Recipes.',
                              ),
                            ),
                          );
                        } on PostgrestException catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not copy recipe: ${error.message}',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not copy recipe: $error',
                              ),
                            ),
                          );
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem<String>(
                          value: 'edit_recipe',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined),
                              SizedBox(width: 8),
                              Text('Edit recipe'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'copy_to_household',
                          child: Row(
                            children: [
                              Icon(Icons.content_copy_rounded),
                              SizedBox(width: 8),
                              Text('Share to Household'),
                            ],
                          ),
                        ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.more_vert_rounded),
                      ),
                    ),
                  ],
                )
              : IconButton.filledTonal(
                  onPressed: () => onEditRecipe(recipe),
                  icon: Icon(Icons.edit_outlined,
                      color: scheme.onSurfaceVariant),
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

class _IngredientInput {
  _IngredientInput({
    required String name,
    required this.unitOptions,
    required this.selectedUnit,
    String? customUnit,
  }) {
    nameCtrl.text = name;
    if (customUnit != null) {
      customUnitCtrl.text = customUnit;
    }
  }

  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController customUnitCtrl = TextEditingController();
  final List<String> unitOptions;
  String selectedUnit;

  String get name => nameCtrl.text.trim();

  void dispose() {
    nameCtrl.dispose();
    amountCtrl.dispose();
    customUnitCtrl.dispose();
  }
}

class _UnitProfile {
  const _UnitProfile({required this.options, required this.defaultUnit});

  final List<String> options;
  final String defaultUnit;
}

class _DirectionDraft {
  _DirectionDraft({String? text, String? timeMinutes}) {
    if (text != null) textCtrl.text = text;
    if (timeMinutes != null) timeCtrl.text = timeMinutes;
  }

  final TextEditingController textCtrl = TextEditingController();
  final TextEditingController timeCtrl = TextEditingController();

  void dispose() {
    textCtrl.dispose();
    timeCtrl.dispose();
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

  @override
  void initState() {
    super.initState();
    _hydrateFromInitialRecipe();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(recipeCreationGuardProvider.notifier).open();
      ref.read(recipeCreationGuardProvider.notifier).setStep(_step);
      _titleFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
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
    _titleCtrl.text = initial.title;
    _servingsCtrl.text = '${initial.servings}';
    _mealType = initial.mealType;
    _cuisineTags
      ..clear()
      ..addAll(initial.cuisineTags);
    _markFavorite = initial.isFavorite;
    _markToTry = initial.isToTry;
    _makePublic = initial.visibility == RecipeVisibility.public;
    _ingredients.clear();
    for (final ingredient in initial.ingredients) {
      final profile = _detectUnitProfile(ingredient.name);
      final normalizedUnit = ingredient.unit.trim().toLowerCase();
      final isCustom = !profile.options.contains(normalizedUnit);
      final units = [...profile.options, 'custom'];
      final row = _IngredientInput(
        name: ingredient.name,
        unitOptions: units,
        selectedUnit: isCustom ? 'custom' : normalizedUnit,
        customUnit: isCustom ? ingredient.unit : null,
      );
      row.amountCtrl.text = ingredient.amount.toString();
      _ingredients.add(row);
    }
    _selectedIngredientIndex =
        _ingredients.isEmpty ? null : 0;
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

  _UnitProfile _detectUnitProfile(String ingredientName) {
    final lower = ingredientName.toLowerCase();
    final liquidWords = [
      'milk',
      'oil',
      'broth',
      'sauce',
      'water',
      'juice',
      'vinegar',
      'stock'
    ];
    final powderWords = [
      'flour',
      'sugar',
      'salt',
      'pepper',
      'paprika',
      'cumin',
      'spice'
    ];
    if (liquidWords.any(lower.contains)) {
      return const _UnitProfile(
        options: ['ml', 'l', 'cup', 'tbsp', 'tsp', 'custom'],
        defaultUnit: 'ml',
      );
    }
    if (powderWords.any(lower.contains)) {
      return const _UnitProfile(
        options: ['tsp', 'tbsp', 'g', 'cup', 'custom'],
        defaultUnit: 'tsp',
      );
    }
    return const _UnitProfile(
      options: ['g', 'kg', 'piece', 'cup', 'tbsp', 'tsp', 'custom'],
      defaultUnit: 'g',
    );
  }

  void _removeIngredientAt(int idx) {
    setState(() {
      final removed = _ingredients.removeAt(idx);
      removed.dispose();
      _validationMessage = null;
      if (_ingredients.isEmpty) {
        _selectedIngredientIndex = null;
      } else if (_selectedIngredientIndex != null) {
        final sel = _selectedIngredientIndex!;
        if (idx < sel) {
          _selectedIngredientIndex = sel - 1;
        } else if (idx == sel) {
          _selectedIngredientIndex =
              idx.clamp(0, _ingredients.length - 1);
        }
      }
    });
  }

  void _addBlankIngredient() {
    if (!_canAddAnotherIngredient) return;
    setState(() {
      final profile = _detectUnitProfile('');
      _ingredients.add(_IngredientInput(
        name: '',
        unitOptions: profile.options,
        selectedUnit: profile.defaultUnit,
      ));
      _selectedIngredientIndex = _ingredients.length - 1;
      _validationMessage = null;
    });
  }

  /// First ingredient can always be added; further rows require the last row
  /// to have a name and a valid amount (same rules as step validation).
  bool get _canAddAnotherIngredient {
    if (_ingredients.isEmpty) return true;
    final last = _ingredients.last;
    if (last.nameCtrl.text.trim().isEmpty) return false;
    if (_parseIngredientAmount(last.amountCtrl.text) == null) return false;
    return true;
  }

  String _ingredientSummary(_IngredientInput row) {
    final name = row.nameCtrl.text.trim().isEmpty
        ? 'New ingredient'
        : row.nameCtrl.text.trim();
    final amt = row.amountCtrl.text.trim();
    final unitStr = row.selectedUnit == 'custom'
        ? row.customUnitCtrl.text.trim()
        : row.selectedUnit;
    if (amt.isEmpty) return name;
    if (unitStr.isEmpty) return '$name · $amt';
    return '$name · $amt $unitStr';
  }

  Widget _buildCondensedIngredientRow(
    BuildContext context,
    int idx,
    _IngredientInput row,
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
          onTap: () => setState(() => _selectedIngredientIndex = idx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.restaurant_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _ingredientSummary(row),
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
                  onPressed: () => _removeIngredientAt(idx),
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

  Widget _buildExpandedIngredientRow(
    BuildContext context,
    int idx,
    _IngredientInput row,
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
              Expanded(
                child: TextField(
                  controller: row.nameCtrl,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'Ingredient name',
                    hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                onPressed: () => _removeIngredientAt(idx),
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Remove ingredient',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
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
                      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                      selected: _isPresetAmountSelected(
                        row,
                        preset.canonicalText,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (selected) {
                        setState(() {
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
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  decoration: InputDecoration(
                    hintText: 'Enter amount',
                    hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: row.unitOptions.contains(row.selectedUnit)
                      ? row.selectedUnit
                      : row.unitOptions.first,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                    setState(() => row.selectedUnit = value);
                  },
                ),
              ),
            ],
          ),
          if (row.selectedUnit == 'custom') ...[
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: row.customUnitCtrl,
              decoration: const InputDecoration(
                labelText: 'Custom unit',
                hintText: 'e.g. clove, pinch, can',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
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
      final hasAmountIssue = _ingredients.any(
        (row) =>
            row.amountCtrl.text.trim().isEmpty ||
            _parseIngredientAmount(row.amountCtrl.text) == null ||
            row.selectedUnit.trim().isEmpty ||
            (row.selectedUnit == 'custom' &&
                row.customUnitCtrl.text.trim().isEmpty),
      );
      if (hasAmountIssue) {
        setState(() =>
            _validationMessage = 'Each ingredient needs amount and unit.');
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
      final invalidTime = _directionDrafts.any((d) {
        final raw = d.timeCtrl.text.trim();
        if (raw.isEmpty) return false;
        final parsed = int.tryParse(raw);
        return parsed == null || parsed < 0;
      });
      if (invalidTime) {
        setState(() =>
            _validationMessage = 'Step time must be a non-negative number.');
        return false;
      }
    }

    setState(() => _validationMessage = null);
    return true;
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_step >= 4) {
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
  }

  List<String> _suggestionsForStep(int stepIndex) {
    final title = _titleCtrl.text.toLowerCase();
    final names = _ingredients.map((e) => e.name.toLowerCase()).join(' ');
    final cuisines = _cuisineTags.map((e) => e.toLowerCase()).toSet();
    final byStep = <int, List<String>>{
      0: [
        'Prep all ingredients and tools before turning on heat.',
        if (title.contains('pasta') || names.contains('pasta'))
          'Bring a large pot of salted water to a boil.',
        if (title.contains('salad')) 'Wash and dry vegetables thoroughly.',
        if (title.contains('soup'))
          'Set a pot over medium heat and prep aromatics.',
      ],
      1: [
        if (title.contains('pasta') || names.contains('pasta'))
          'At the same time, chop vegetables and mince garlic.',
        if (title.contains('stir') || names.contains('soy sauce'))
          'Heat oil in a wok/pan and get it very hot before adding ingredients.',
        if (title.contains('soup')) 'Saute onion and garlic until fragrant.',
        if (title.contains('salad'))
          'Whisk the dressing ingredients in a bowl.',
      ],
      2: [
        if (title.contains('pasta') || names.contains('pasta'))
          'Cook pasta until al dente, then reserve some pasta water.',
        if (names.contains('chicken'))
          'Cook chicken until browned and fully cooked through.',
        if (names.contains('rice'))
          'Cook rice according to package directions until tender.',
        'Add vegetables and cook until just tender.',
      ],
      3: [
        'Combine all cooked components and adjust seasoning.',
        if (cuisines.contains('italian'))
          'Finish with olive oil, herbs, and parmesan.',
        if (cuisines.contains('chinese'))
          'Add soy-based sauce and toss over high heat.',
        if (cuisines.contains('mexican'))
          'Finish with lime juice and chopped cilantro.',
      ],
    };

    final fallback = <String>[
      'Continue cooking and combine ingredients as needed.',
      'Taste and adjust seasoning before serving.',
      'Plate and garnish, then serve warm.',
    ];

    final suggestions =
        byStep[stepIndex]?.where((e) => e.trim().isNotEmpty).toList() ??
            fallback;
    if (suggestions.isEmpty) return fallback;
    return suggestions.take(5).toList();
  }

  void _applySuggestionToStep(int stepIndex, String suggestion) {
    setState(() {
      final draft = _directionDrafts[stepIndex];
      if (draft.textCtrl.text.trim().isEmpty) {
        draft.textCtrl.text = suggestion;
      } else if (!draft.textCtrl.text.contains(suggestion)) {
        draft.textCtrl.text = '${draft.textCtrl.text.trim()} $suggestion';
      }
    });
  }

  void _applyQuickTime(int stepIndex, int minutes) {
    setState(() {
      _directionDrafts[stepIndex].timeCtrl.text = '$minutes';
    });
  }

  void _submit() {
    if (_isSubmitting) return;
    if (!_validateCurrentStep()) return;

    final ingredients = _ingredients.map(
      (row) {
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
        .map((d) {
          final text = d.textCtrl.text.trim();
          final minutes = int.tryParse(d.timeCtrl.text.trim());
          if (text.isEmpty) return '';
          if (minutes == null) return text;
          return '$text (~$minutes min)';
        })
        .where((step) => step.isNotEmpty)
        .toList();

    if (ingredients.isEmpty || directions.isEmpty) {
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

    final initial = widget.initialRecipe;
    final recipe = Recipe(
      id: initial?.id ?? '',
      title: _titleCtrl.text.trim(),
      description: initial?.description,
      servings: _parseIntOrNull(_servingsCtrl.text) ?? 2,
      prepTime: initial?.prepTime,
      cookTime: initial?.cookTime,
      mealType: _mealType,
      cuisineTags: _cuisineTags,
      ingredients: ingredients,
      instructions: directions,
      imageUrl: initial?.imageUrl,
      nutrition: initial?.nutrition ?? const Nutrition(),
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
    );
    _closeWizard(recipe);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final scheme = Theme.of(context).colorScheme;
    final stepTitle = switch (_step) {
      0 => 'Step 1: Name your recipe',
      1 => 'Step 2: Serving + labels',
      2 => 'Step 3: Ingredients',
      3 => 'Step 4: Directions',
      _ => 'Step 5: Final touches',
    };

    return WillPopScope(
      onWillPop: () async => false,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
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
                          Text('Create Recipe',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text(stepTitle),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: (_step + 1) / 5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: List.generate(
                              5,
                              (index) => Expanded(
                                child: Container(
                                  margin: EdgeInsets.only(
                                      right: index == 4 ? 0 : 6),
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
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _confirmClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Cancel'),
                      ),
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
                                              label:
                                                  Text(_mealTypeLabel(type)),
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
                                              onPressed: () => setState(() =>
                                                  _showCustomTag = true),
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
                                              icon: const Icon(
                                                  Icons.add_circle),
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
                                                .where((tag) =>
                                                    !_presetCuisines
                                                        .contains(tag))
                                                .map(
                                                  (tag) => Chip(
                                                    label: Text(tag),
                                                    onDeleted: () =>
                                                        setState(() =>
                                                            _cuisineTags
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
                          _StepCard(
                            title: 'Add ingredients',
                            subtitle:
                                'Type each ingredient name, amount, and unit. Add more rows as needed.',
                            child: Column(
                              children: [
                                if (_ingredients.isEmpty) ...[
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        'No ingredients yet. Tap Add ingredient to start.'),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: _canAddAnotherIngredient
                                          ? _addBlankIngredient
                                          : null,
                                      icon: const Icon(
                                          Icons.add_circle_outline_rounded),
                                      label: const Text('Add ingredient'),
                                    ),
                                  ),
                                ],
                                if (_ingredients.isNotEmpty) ...[
                                  for (var i = 0; i < _ingredients.length; i++)
                                    if (_selectedIngredientIndex == i)
                                      _buildExpandedIngredientRow(
                                        context,
                                        i,
                                        _ingredients[i],
                                      )
                                    else
                                      _buildCondensedIngredientRow(
                                        context,
                                        i,
                                        _ingredients[i],
                                      ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      onPressed: _canAddAnotherIngredient
                                          ? _addBlankIngredient
                                          : null,
                                      icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                          size: 20),
                                      label: const Text('Add ingredient'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _StepCard(
                            title: 'Directions',
                            child: Column(
                              children: [
                                ..._directionDrafts
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                  final idx = entry.key;
                                  final draft = entry.value;
                                  final stepSuggestions =
                                      _suggestionsForStep(idx);
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    color: const Color(0xFFF3FAFF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      side: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(0.15),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDDEFFF),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              'Step ${idx + 1}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: draft.textCtrl,
                                            maxLines: 3,
                                            decoration: const InputDecoration(
                                              labelText: 'Instruction',
                                              hintText:
                                                  'Describe what to do for this step',
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: draft.timeCtrl,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText:
                                                        'Estimated time (min)',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Wrap(
                                                spacing: 6,
                                                children: [5, 10, 15]
                                                    .map(
                                                      (mins) => ActionChip(
                                                        label: Text('${mins}m'),
                                                        onPressed: () =>
                                                            _applyQuickTime(
                                                                idx, mins),
                                                      ),
                                                    )
                                                    .toList(),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: stepSuggestions
                                                .map(
                                                  (suggestion) => ActionChip(
                                                    label: Text(suggestion),
                                                    onPressed: () =>
                                                        _applySuggestionToStep(
                                                            idx, suggestion),
                                                  ),
                                                )
                                                .toList(),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Spacer(),
                                              if (_directionDrafts.length > 1)
                                                IconButton(
                                                  onPressed: () => setState(() {
                                                    final removed =
                                                        _directionDrafts
                                                            .removeAt(idx);
                                                    removed.dispose();
                                                  }),
                                                  icon: const Icon(Icons
                                                      .remove_circle_outline),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => setState(() =>
                                        _directionDrafts
                                            .add(_DirectionDraft())),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add step'),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                    title:
                                        const Text('Save to Household'),
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
                                : (_step == 0
                                    ? _confirmClose
                                    : _prevStep),
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
                            icon: Icon(_step == 4
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded),
                            label: Text(_step == 4
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
