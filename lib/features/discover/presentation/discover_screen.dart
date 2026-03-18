import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/ui/app_surface.dart';
import 'package:plateplan/core/ui/recipo_kit.dart';
import 'package:plateplan/core/ui/section_card.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMeal = ref.watch(discoverMealTypeProvider);
    final availableChips = ref.watch(discoverAvailableChipsProvider);
    final selectedChip = ref.watch(discoverSelectedChipProvider);
    final recipesAsync = ref.watch(discoverFilteredRecipesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: AppSurface(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          children: [
            _buildDiscoverHero(),
            const SizedBox(height: 12),
            _buildMealSelector(ref, selectedMeal),
            const SizedBox(height: 10),
            _buildMealFilters(ref, availableChips, selectedChip),
            const SizedBox(height: 12),
            recipesAsync.when(
              data: (recipes) =>
                  _buildRecipeList(context, ref, selectedMeal, recipes),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SectionCard(
                title: 'Could not load discover recipes',
                subtitle: 'Please retry in a moment.',
                child: Text(error.toString()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealSelector(WidgetRef ref, DiscoverMealType selectedMeal) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: DiscoverMealType.values
            .map(
              (meal) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(meal.label),
                  selected: selectedMeal == meal,
                  onSelected: (_) {
                    ref.read(discoverMealTypeProvider.notifier).state = meal;
                    ref.read(discoverChipIdProvider.notifier).state = 'all';
                  },
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDiscoverHero() {
    return Builder(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.restaurant_menu_rounded,
                      color: scheme.onPrimaryContainer,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Discover',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Browse recipes with nutrition insights and save favorites for later.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMealFilters(
    WidgetRef ref,
    List<DiscoverFilterChip> chips,
    DiscoverFilterChip selected,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chips
            .map(
              (chip) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(chip.label),
                  selected: selected.id == chip.id,
                  onSelected: (_) {
                    ref.read(discoverChipIdProvider.notifier).state = chip.id;
                  },
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildRecipeList(
    BuildContext context,
    WidgetRef ref,
    DiscoverMealType meal,
    List<Recipe> recipes,
  ) {
    if (recipes.isEmpty) {
      return SectionCard(
        title: 'No ${meal.label.toLowerCase()} recipes yet',
        subtitle: 'Run the Spoonacular seeding script to populate this meal.',
        child:
            const Text('Try another filter or seed new recipes to continue.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: recipes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final recipe = recipes[index];
        return MediaRecipeCard(
          title: recipe.title,
          meta: _recipeMeta(recipe),
          imageUrl: recipe.imageUrl ?? '',
          tags: recipe.cuisineTags,
          trailing: _nutritionChip(recipe),
          onTap: () => _showPublicRecipeDetail(context, ref, recipe),
        );
      },
    );
  }

  String _recipeMeta(Recipe recipe) {
    final totalTime = (recipe.prepTime ?? 0) + (recipe.cookTime ?? 0);
    final timeText = totalTime > 0 ? '${totalTime}m' : 'Time n/a';
    final calories = recipe.nutrition.calories;
    final protein = recipe.nutrition.protein;
    final nutritionText = calories > 0 || protein > 0
        ? '${calories > 0 ? '$calories cal' : ''}${calories > 0 && protein > 0 ? ' • ' : ''}${protein > 0 ? '${protein.toStringAsFixed(0)}g protein' : ''}'
        : 'Data loading soon';
    return '${_mealLabel(recipe.mealType)} • $timeText • Serves ${recipe.servings} • $nutritionText';
  }

  String _mealLabel(MealType mealType) {
    final raw = mealType.name;
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  Widget _nutritionChip(Recipe recipe) {
    final hasNutrition =
        recipe.nutrition.calories > 0 || recipe.nutrition.protein > 0;
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        hasNutrition
            ? recipe.nutrition.calories > 0
                ? '${recipe.nutrition.calories} cal'
                : '${recipe.nutrition.protein.toStringAsFixed(0)}g P'
            : 'Data loading soon',
      ),
    );
  }

  Future<void> _showPublicRecipeDetail(
    BuildContext context,
    WidgetRef ref,
    Recipe recipe,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DiscoverRecipeDetailPage(recipe: recipe),
      ),
    );
  }
}

class _DiscoverRecipeDetailPage extends ConsumerStatefulWidget {
  const _DiscoverRecipeDetailPage({required this.recipe});

  final Recipe recipe;

  @override
  ConsumerState<_DiscoverRecipeDetailPage> createState() =>
      _DiscoverRecipeDetailPageState();
}

class _DiscoverRecipeDetailPageState
    extends ConsumerState<_DiscoverRecipeDetailPage> {
  _DiscoverDetailSection _selectedSection = _DiscoverDetailSection.ingredients;
  late bool _isFavorite = widget.recipe.isFavorite;
  late bool _isToTry = widget.recipe.isToTry;

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    return Scaffold(
      appBar: AppBar(title: const Text('Recipe')),
      body: AppSurface(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recipe.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FoodMedia(imageUrl: recipe.imageUrl, height: 220),
            ),
            const SizedBox(height: 12),
            _buildDetailSectionChips(),
            const SizedBox(height: 12),
            _buildDetailSectionContent(context, recipe),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _setRecipeFlag(favorite: !_isFavorite),
                icon: Icon(
                  _isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                label: Text(_isFavorite ? 'Favorited' : 'Add to Favorites'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _setRecipeFlag(toTry: !_isToTry),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(_isToTry ? 'In To Try' : 'To Try'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSectionChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _DiscoverDetailSection.values
            .map(
              (section) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(section.label),
                  selected: _selectedSection == section,
                  onSelected: (_) => setState(() => _selectedSection = section),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDetailSectionContent(BuildContext context, Recipe recipe) {
    switch (_selectedSection) {
      case _DiscoverDetailSection.ingredients:
        return SectionCard(
          title: 'Ingredients',
          child: _buildIngredientsTable(context, recipe),
        );
      case _DiscoverDetailSection.directions:
        return SectionCard(
          title: 'Directions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: recipe.instructions.isEmpty
                ? const [Text('No instructions available yet.')]
                : recipe.instructions
                    .map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(step),
                      ),
                    )
                    .toList(),
          ),
        );
      case _DiscoverDetailSection.nutritionalInfo:
        return SectionCard(
          title: 'Nutritional Info',
          child: _nutritionGrid(context, recipe),
        );
    }
  }

  Widget _nutritionGrid(BuildContext context, Recipe recipe) {
    final nutrition = recipe.nutrition;
    final hasNutrition = nutrition.calories > 0 ||
        nutrition.protein > 0 ||
        nutrition.fat > 0 ||
        nutrition.carbs > 0;
    if (!hasNutrition) {
      return const Text('Data loading soon');
    }

    Widget tile({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

    return Column(
      children: [
        tile(
          icon: Icons.local_fire_department_rounded,
          label: 'Calories',
          value: '${nutrition.calories}',
        ),
        const SizedBox(height: 8),
        tile(
          icon: Icons.fitness_center_rounded,
          label: 'Protein',
          value: '${nutrition.protein.toStringAsFixed(1)}g',
        ),
        const SizedBox(height: 8),
        tile(
          icon: Icons.opacity_rounded,
          label: 'Fat',
          value: '${nutrition.fat.toStringAsFixed(1)}g',
        ),
        const SizedBox(height: 8),
        tile(
          icon: Icons.grain_rounded,
          label: 'Carbs',
          value: '${nutrition.carbs.toStringAsFixed(1)}g',
        ),
      ],
    );
  }

  Widget _buildIngredientsTable(BuildContext context, Recipe recipe) {
    if (recipe.ingredients.isEmpty) {
      return const Text('No ingredients available yet.');
    }

    final scheme = Theme.of(context).colorScheme;
    final amountHeader =
        MediaQuery.sizeOf(context).width < 380 ? 'Amt.' : 'Amount';

    TableRow headerRow() {
      return TableRow(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
        ),
        children: [
          const _IngredientTableCell(
            text: 'Ingredient',
            isHeader: true,
            noWrap: true,
          ),
          _IngredientTableCell(
            text: amountHeader,
            isHeader: true,
            noWrap: true,
          ),
          const _IngredientTableCell(
            text: 'Unit',
            isHeader: true,
            noWrap: true,
          ),
        ],
      );
    }

    final ingredientRows = recipe.ingredients.asMap().entries.map((entry) {
      final index = entry.key;
      final ingredient = entry.value;
      final amount = ingredient.amount.toStringAsFixed(
        ingredient.amount % 1 == 0 ? 0 : 1,
      );
      final evenRow = index.isEven;
      final unit = _shortUnit(ingredient.unit);
      return TableRow(
        decoration: BoxDecoration(
          color: evenRow
              ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
              : scheme.surface,
        ),
        children: [
          _IngredientTableCell(text: ingredient.name),
          _IngredientTableCell(text: amount, noWrap: true),
          _IngredientTableCell(
            text: unit.isEmpty ? '-' : unit,
            noWrap: true,
          ),
        ],
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Table(
        border: TableBorder(
          horizontalInside: BorderSide(color: scheme.outlineVariant),
          verticalInside: BorderSide(color: scheme.outlineVariant),
          top: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
          left: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
        ),
        columnWidths: const <int, TableColumnWidth>{
          0: FlexColumnWidth(2.1),
          1: FlexColumnWidth(1.35),
          2: FlexColumnWidth(1.0),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          headerRow(),
          ...ingredientRows,
        ],
      ),
    );
  }

  String _shortUnit(String rawUnit) {
    final unit = rawUnit.trim().toLowerCase();
    if (unit.isEmpty) return '';

    const shorthand = <String, String>{
      'tablespoon': 'tbsp',
      'tablespoons': 'tbsp',
      'tbsp': 'tbsp',
      'tbl': 'tbsp',
      'teaspoon': 'tsp',
      'teaspoons': 'tsp',
      'tsp': 'tsp',
      'ounce': 'oz',
      'ounces': 'oz',
      'oz': 'oz',
      'fluid ounce': 'fl oz',
      'fluid ounces': 'fl oz',
      'cup': 'cup',
      'cups': 'cups',
      'pint': 'pt',
      'pints': 'pt',
      'quart': 'qt',
      'quarts': 'qt',
      'gallon': 'gal',
      'gallons': 'gal',
      'pound': 'lb',
      'pounds': 'lb',
      'lb': 'lb',
      'lbs': 'lb',
      'gram': 'g',
      'grams': 'g',
      'g': 'g',
      'kilogram': 'kg',
      'kilograms': 'kg',
      'kg': 'kg',
      'milligram': 'mg',
      'milligrams': 'mg',
      'mg': 'mg',
      'liter': 'l',
      'liters': 'l',
      'litre': 'l',
      'litres': 'l',
      'l': 'l',
      'milliliter': 'ml',
      'milliliters': 'ml',
      'millilitre': 'ml',
      'millilitres': 'ml',
      'ml': 'ml',
    };

    return shorthand[unit] ?? unit;
  }

  Future<void> _setRecipeFlag({bool? favorite, bool? toTry}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(discoverRepositoryProvider);
      if (favorite != null) {
        await repository.setFavorite(widget.recipe.id, favorite);
        setState(() => _isFavorite = favorite);
      }
      if (toTry != null) {
        await repository.setToTry(widget.recipe.id, toTry);
        setState(() => _isToTry = toTry);
      }
      ref.invalidate(discoverPublicRecipesProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update recipe: $error')),
      );
    }
  }
}

enum _DiscoverDetailSection {
  ingredients('Ingredients'),
  directions('Directions'),
  nutritionalInfo('Nutritional Info');

  const _DiscoverDetailSection(this.label);
  final String label;
}

class _IngredientTableCell extends StatelessWidget {
  const _IngredientTableCell({
    required this.text,
    this.isHeader = false,
    this.noWrap = false,
  });

  final String text;
  final bool isHeader;
  final bool noWrap;

  @override
  Widget build(BuildContext context) {
    final style = isHeader
        ? Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            )
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: style,
        softWrap: !noWrap,
        overflow: noWrap ? TextOverflow.fade : TextOverflow.visible,
        maxLines: noWrap ? 1 : null,
      ),
    );
  }
}
