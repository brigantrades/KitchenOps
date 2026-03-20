import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  int _libraryIndex = 0;
  int _segmentIndex = 0;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.surfaceBase, colors.surfaceAlt, colors.surfaceBase],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                children: [
                  SectionCard(
                    title: 'Recipe Library',
                    subtitle: hasSharedHousehold
                        ? 'Search and manage household and personal recipes.'
                        : 'Search and manage your personal recipes.',
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
                  const SizedBox(height: 10),
                  SegmentedPills(
                    labels: libraryLabels,
                    selectedIndex: effectiveLibraryIndex,
                    onSelect: (idx) => setState(() {
                      _libraryIndex = idx;
                      _segmentIndex = 0;
                    }),
                  ),
                  if (!(hasSharedHousehold &&
                      effectiveLibraryIndex == 0)) ...[
                    const SizedBox(height: 10),
                    SegmentedPills(
                      labels: const ['Favorites', 'To Try'],
                      selectedIndex: _segmentIndex,
                      onSelect: (idx) =>
                          setState(() => _segmentIndex = idx),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
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
                        .where((r) =>
                            r.visibility != RecipeVisibility.household)
                        .toList();
                    final allFavorites = filtered
                        .where((r) => r.isFavorite)
                        .toList();
                    final toTry =
                        personal.where((r) => r.isToTry).toList();
                    visible = switch (_segmentIndex) {
                      1 => toTry,
                      _ => allFavorites,
                    };
                  }
                  return _RecipeList(
                    recipes: visible,
                    hasSharedHousehold: hasSharedHousehold,
                    onEditRecipe: _editRecipe,
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(child: Text('Error: $error')),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRecipeManually,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create New'),
      ),
    );
  }
}

class _RecipeList extends ConsumerWidget {
  const _RecipeList({
    required this.recipes,
    required this.hasSharedHousehold,
    required this.onEditRecipe,
  });

  final List<Recipe> recipes;
  final bool hasSharedHousehold;
  final Future<void> Function(Recipe recipe) onEditRecipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (recipes.isEmpty) {
      return const Center(
          child: Text('No recipes yet. Add one in Discover or Planner.'));
    }
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(currentUserProvider);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      itemCount: recipes.length,
      itemBuilder: (context, index) {
        final recipe = recipes[index];
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
            padding: const EdgeInsets.only(bottom: 12),
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
                            await ref
                                .read(recipesRepositoryProvider)
                                .toggleFavorite(
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
      },
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
  final _ingredientSearchCtrl = TextEditingController();
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
  final List<String> _ingredientCatalog = const [
    'Chicken breast',
    'Ground beef',
    'Salmon',
    'Eggs',
    'Milk',
    'Greek yogurt',
    'Cheddar cheese',
    'Tomato',
    'Onion',
    'Garlic',
    'Bell pepper',
    'Spinach',
    'Broccoli',
    'Carrot',
    'Mushroom',
    'Potato',
    'Sweet potato',
    'Rice',
    'Pasta',
    'Quinoa',
    'Black beans',
    'Chickpeas',
    'Olive oil',
    'Soy sauce',
    'Flour',
    'Butter',
    'Bread',
    'Lemon',
    'Cilantro',
    'Basil',
  ];
  MealType _mealType = MealType.entree;
  bool _markFavorite = false;
  bool _markToTry = false;
  bool _makePublic = false;
  bool _saveToHousehold = false;
  bool _showCustomTag = false;
  int _step = 0;
  String? _validationMessage;
  bool _isSubmitting = false;

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
    _ingredientSearchCtrl.dispose();
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

  void _addIngredient(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) return;
    if (_ingredients.any((i) => i.name.toLowerCase() == name.toLowerCase())) {
      _ingredientSearchCtrl.clear();
      return;
    }
    setState(() {
      final profile = _detectUnitProfile(name);
      final row = _IngredientInput(
        name: name,
        unitOptions: profile.options,
        selectedUnit: profile.defaultUnit,
      );
      _ingredients.add(row);
      _ingredientSearchCtrl.clear();
      _validationMessage = null;
    });
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
            double.tryParse(row.amountCtrl.text.trim()) == null ||
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

  List<String> get _ingredientMatches {
    final q = _ingredientSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _ingredientCatalog
        .where((item) => item.toLowerCase().contains(q))
        .where((item) => !_ingredients
            .any((i) => i.name.toLowerCase() == item.toLowerCase()))
        .take(8)
        .toList();
  }

  List<String> get _contextIngredientSuggestions {
    final title = _titleCtrl.text.toLowerCase();
    final selectedCuisine = _cuisineTags.map((e) => e.toLowerCase()).toList();
    final suggestions = <String>[];

    if (title.contains('pasta')) {
      suggestions
          .addAll(['Pasta', 'Garlic', 'Parmesan', 'Olive oil', 'Tomato']);
    }
    if (title.contains('salad')) {
      suggestions
          .addAll(['Lettuce', 'Cucumber', 'Tomato', 'Olive oil', 'Lemon']);
    }
    if (title.contains('soup')) {
      suggestions.addAll(['Onion', 'Garlic', 'Carrot', 'Broth', 'Celery']);
    }
    if (title.contains('rice')) {
      suggestions.addAll(['Rice', 'Onion', 'Garlic', 'Bell pepper']);
    }
    if (title.contains('chicken')) {
      suggestions.addAll(['Chicken breast', 'Garlic', 'Olive oil']);
    }

    if (selectedCuisine.contains('italian')) {
      suggestions
          .addAll(['Basil', 'Tomato', 'Parmesan', 'Olive oil', 'Garlic']);
    }
    if (selectedCuisine.contains('chinese')) {
      suggestions
          .addAll(['Soy sauce', 'Ginger', 'Garlic', 'Scallion', 'Sesame oil']);
    }
    if (selectedCuisine.contains('american')) {
      suggestions.addAll(['Butter', 'Potato', 'Cheddar cheese', 'Onion']);
    }
    if (selectedCuisine.contains('mexican')) {
      suggestions.addAll(['Cilantro', 'Lime', 'Black beans', 'Chili powder']);
    }
    if (selectedCuisine.contains('indian')) {
      suggestions
          .addAll(['Cumin', 'Turmeric', 'Garam masala', 'Onion', 'Garlic']);
    }
    if (selectedCuisine.contains('japanese')) {
      suggestions.addAll(['Soy sauce', 'Rice', 'Sesame oil', 'Mushroom']);
    }
    if (selectedCuisine.contains('thai')) {
      suggestions.addAll(['Fish sauce', 'Lime', 'Coconut milk', 'Basil']);
    }
    if (selectedCuisine.contains('mediterranean')) {
      suggestions
          .addAll(['Olive oil', 'Lemon', 'Cucumber', 'Tomato', 'Parsley']);
    }

    final existing = _ingredients.map((e) => e.name.toLowerCase()).toSet();
    final unique = <String>[];
    for (final item in suggestions) {
      if (!unique.any((e) => e.toLowerCase() == item.toLowerCase()) &&
          !existing.contains(item.toLowerCase())) {
        unique.add(item);
      }
    }
    return unique.take(10).toList();
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
          amount: double.tryParse(row.amountCtrl.text.trim()) ?? 0,
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

    final recipe = Recipe(
      id: '',
      title: _titleCtrl.text.trim(),
      description: null,
      servings: _parseIntOrNull(_servingsCtrl.text) ?? 2,
      prepTime: null,
      cookTime: null,
      mealType: _mealType,
      cuisineTags: _cuisineTags,
      ingredients: ingredients,
      instructions: directions,
      isFavorite: _markFavorite,
      isToTry: _markToTry,
      visibility: _makePublic
          ? RecipeVisibility.public
          : _saveToHousehold
              ? RecipeVisibility.household
              : RecipeVisibility.personal,
      source: 'user_created',
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
                            child: Column(
                              children: [
                                if (_contextIngredientSuggestions
                                    .isNotEmpty) ...[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Suggested for this recipe',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _contextIngredientSuggestions
                                          .map(
                                            (item) => ActionChip(
                                              label: Text(item),
                                              avatar: const Icon(
                                                  Icons.auto_awesome_rounded,
                                                  size: 16),
                                              onPressed: () =>
                                                  _addIngredient(item),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextField(
                                  controller: _ingredientSearchCtrl,
                                  decoration: const InputDecoration(
                                    hintText:
                                        'Search ingredient (e.g., chicken, tomato)',
                                    prefixIcon: Icon(Icons.search),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  onSubmitted: (value) => _addIngredient(value),
                                ),
                                const SizedBox(height: 8),
                                if (_ingredientSearchCtrl.text
                                    .trim()
                                    .isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ..._ingredientMatches.map(
                                          (item) => ActionChip(
                                            label: Text(item),
                                            onPressed: () =>
                                                _addIngredient(item),
                                          ),
                                        ),
                                        ActionChip(
                                          label: Text(
                                              'Add "${_ingredientSearchCtrl.text.trim()}"'),
                                          onPressed: () => _addIngredient(
                                              _ingredientSearchCtrl.text),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                if (_ingredients.isEmpty)
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        'No ingredients yet. Search and add at least one.'),
                                  ),
                                ..._ingredients.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final row = entry.value;
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: row.nameCtrl,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText:
                                                        'Ingredient name',
                                                  ),
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: () => setState(() {
                                                  final removed = _ingredients
                                                      .removeAt(idx);
                                                  removed.dispose();
                                                }),
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: row.amountCtrl,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText: 'Amount'),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: DropdownButtonFormField<
                                                    String>(
                                                  value: row.unitOptions
                                                          .contains(
                                                              row.selectedUnit)
                                                      ? row.selectedUnit
                                                      : row.unitOptions.first,
                                                  isExpanded: true,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText: 'Unit'),
                                                  items: row.unitOptions
                                                      .map((unit) =>
                                                          DropdownMenuItem(
                                                              value: unit,
                                                              child:
                                                                  Text(unit)))
                                                      .toList(),
                                                  onChanged: (value) {
                                                    if (value == null) return;
                                                    setState(() => row
                                                        .selectedUnit = value);
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (row.selectedUnit == 'custom') ...[
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: row.customUnitCtrl,
                                              decoration: const InputDecoration(
                                                labelText: 'Custom unit',
                                                hintText:
                                                    'e.g., clove, pinch, can',
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        final profile =
                                            _detectUnitProfile('');
                                        _ingredients.add(_IngredientInput(
                                          name: '',
                                          unitOptions: profile.options,
                                          selectedUnit: profile.defaultUnit,
                                        ));
                                        _validationMessage = null;
                                      });
                                    },
                                    icon: const Icon(
                                        Icons.add_circle_outline_rounded),
                                    label: const Text('Add ingredient'),
                                  ),
                                ),
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
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SectionCard(
        title: title,
        child: child,
      ),
    );
  }
}
