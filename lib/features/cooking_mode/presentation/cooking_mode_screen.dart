import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/services/nutrition_estimation.dart';
import 'package:plateplan/core/services/recipe_nutrition_lines.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';

class CookingModeScreen extends ConsumerStatefulWidget {
  const CookingModeScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  ConsumerState<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends ConsumerState<CookingModeScreen> {
  final FlutterTts _tts = FlutterTts();
  int _stepIndex = 0;
  final Set<int> _checkedIngredients = {};
  bool _nutritionShowPerServing = false;
  bool _nutritionBusy = false;
  DateTime? _recipeMissingSince;
  Nutrition? _nutritionOverride;
  List<IngredientNutritionBreakdownLine> _nutritionBreakdownOverride = const [];

  bool _hasNutritionData(Nutrition n) {
    return n.calories > 0 ||
        n.protein > 0 ||
        n.fat > 0 ||
        n.carbs > 0 ||
        n.fiber > 0 ||
        n.sugar > 0;
  }

  Nutrition _displayNutrition(Recipe recipe) {
    final n = _nutritionOverride ?? recipe.nutrition;
    final s = recipe.servings.clamp(1, 999999);
    if (!_nutritionShowPerServing) return n;
    return Nutrition(
      calories: (n.calories / s).round(),
      protein: n.protein / s,
      fat: n.fat / s,
      carbs: n.carbs / s,
      fiber: n.fiber / s,
      sugar: n.sugar / s,
    );
  }

  List<IngredientNutritionBreakdownLine> _displayBreakdown(Recipe recipe) {
    if (_nutritionBreakdownOverride.isNotEmpty) {
      return _nutritionBreakdownOverride;
    }
    return recipe.ingredients.map((ingredient) {
      final label = ingredient.qualitative
          ? '${ingredient.name}: ${ingredient.unit}'
          : '${ingredient.quantityLabel} ${ingredient.name}'.trim();
      final lineNutrition = ingredient.lineNutrition;
      if (lineNutrition != null && _hasNutritionData(lineNutrition)) {
        return IngredientNutritionBreakdownLine(
          label: label,
          nutrition: lineNutrition,
          sourceTag: 'saved_line',
        );
      }
      return IngredientNutritionBreakdownLine(
        label: label,
        nutrition: const Nutrition(),
        sourceTag: 'missing',
      );
    }).toList();
  }

  Future<void> _estimateNutrition(Recipe recipe) async {
    if (!Env.hasFdc && !Env.hasGemini) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configure USDA FDC or Gemini API keys in your environment to estimate nutrition.',
          ),
        ),
      );
      return;
    }
    final lines = ingredientLinesForNutritionEstimate(recipe);
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No usable ingredient lines for nutrition. Edit the recipe and add amounts.',
          ),
        ),
      );
      return;
    }
    setState(() => _nutritionBusy = true);
    try {
      final result = await estimateNutritionWithFallback(
        foodDataCentral: ref.read(foodDataCentralServiceProvider),
        cacheRepository: ref.read(ingredientNutritionCacheRepositoryProvider),
        gemini: ref.read(geminiServiceProvider),
        ingredientLines: lines,
        servings: recipe.servings,
      );
      final updated = recipe.copyWith(
        nutrition: result.nutrition,
        nutritionSource: result.source,
      );
      await ref.read(recipesRepositoryProvider).updateRecipe(recipe.id, updated);
      ref.invalidate(recipesProvider);
      if (mounted) {
        setState(() {
          _nutritionOverride = result.nutrition;
          _nutritionBreakdownOverride = result.breakdown;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nutrition updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not estimate nutrition. Check your connection and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _nutritionBusy = false);
    }
  }

  Widget _macroTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
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

  Widget _buildNutritionSection(BuildContext context, Recipe recipe) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final servings = recipe.servings.clamp(1, 999999);
    final showPerServing = _nutritionShowPerServing;
    final n = _displayNutrition(recipe);
    final hasTotals = _hasNutritionData(n);
    final breakdown = _displayBreakdown(recipe);

    String subtitle;
    if (!hasTotals) {
      subtitle = 'Not calculated — use Estimate below';
    } else if (showPerServing) {
      subtitle =
          '${(n.calories / servings).round()} cal per serving (approx.)';
    } else {
      subtitle =
          '${n.calories} cal total (approx.)';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        title: const Text('Nutrition'),
        subtitle: Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Nutritional values', style: textTheme.labelLarge),
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
                if (breakdown.isNotEmpty) ...[
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      initiallyExpanded: false,
                      title: Text(
                        'Ingredient breakdown (for testing purposes)',
                        style: textTheme.labelLarge,
                      ),
                      children: [
                        ...breakdown.map((row) {
                          final missing = row.sourceTag == 'missing';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          row.label,
                                          style: textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${row.nutrition.calories} cal',
                                        style: textTheme.labelLarge?.copyWith(
                                          color: missing
                                              ? scheme.error
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    missing
                                        ? 'Missing nutrition for this ingredient.'
                                        : '${row.nutrition.protein.toStringAsFixed(1)}g protein · ${row.nutrition.fat.toStringAsFixed(1)}g fat · ${row.nutrition.carbs.toStringAsFixed(1)}g carbs · ${row.nutrition.fiber.toStringAsFixed(1)}g fiber · ${row.nutrition.sugar.toStringAsFixed(1)}g sugar',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
                if (!hasTotals && (Env.hasFdc || Env.hasGemini))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No nutrition totals yet. Use Estimate to calculate from ingredients.',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (!hasTotals && !Env.hasFdc && !Env.hasGemini)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Configure USDA FDC or Gemini API keys to estimate nutrition.',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (hasTotals) ...[
                  const SizedBox(height: 8),
                  _macroTile(
                    context: context,
                    icon: Icons.local_fire_department_rounded,
                    label: showPerServing
                        ? 'Calories (per serving)'
                        : 'Calories (total)',
                    value: '${n.calories}',
                  ),
                  const SizedBox(height: 8),
                  _macroTile(
                    context: context,
                    icon: Icons.fitness_center_rounded,
                    label: 'Protein',
                    value: '${n.protein.toStringAsFixed(1)} g',
                  ),
                  const SizedBox(height: 8),
                  _macroTile(
                    context: context,
                    icon: Icons.opacity_rounded,
                    label: 'Fat',
                    value: '${n.fat.toStringAsFixed(1)} g',
                  ),
                  const SizedBox(height: 8),
                  _macroTile(
                    context: context,
                    icon: Icons.grain_rounded,
                    label: 'Carbs',
                    value: '${n.carbs.toStringAsFixed(1)} g',
                  ),
                  const SizedBox(height: 8),
                  _macroTile(
                    context: context,
                    icon: Icons.grass_rounded,
                    label: 'Fiber',
                    value: '${n.fiber.toStringAsFixed(1)} g',
                  ),
                  const SizedBox(height: 8),
                  _macroTile(
                    context: context,
                    icon: Icons.cake_rounded,
                    label: 'Sugar',
                    value: '${n.sugar.toStringAsFixed(1)} g',
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _nutritionBusy
                      ? null
                      : () => _estimateNutrition(recipe),
                  icon: _nutritionBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.calculate_outlined),
                  label: Text(
                    hasTotals ? 'Recalculate nutrition' : 'Estimate nutrition',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(recipesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Recipes',
          onPressed: () => context.go('/recipes'),
        ),
      ),
      body: recipesAsync.when(
        data: (recipes) {
          final recipe =
              recipes.firstWhereOrNull((r) => r.id == widget.recipeId);
          if (recipe == null) {
            _recipeMissingSince ??= DateTime.now();
            final waiting = DateTime.now().difference(_recipeMissingSince!) <
                const Duration(seconds: 2);
            if (waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Opening recipe...'),
                  ],
                ),
              );
            }
            return const Center(child: Text('Recipe not found'));
          }
          _recipeMissingSince = null;

          final steps = recipe.instructions.isEmpty
              ? const ['Follow your recipe details.']
              : recipe.instructions;
          final step = steps[_stepIndex.clamp(0, steps.length - 1)];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(recipe.title,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('${recipe.ingredients.length} ingredients')),
                  Chip(label: Text('${steps.length} steps')),
                  Chip(
                    label: const Text('Cook mode'),
                    backgroundColor: scheme.secondary,
                    labelStyle: TextStyle(color: scheme.onSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildNutritionSection(context, recipe),
              const SizedBox(height: 16),
              Text('Ingredients',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              ...recipe.ingredients.asMap().entries.map(
                    (entry) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: _checkedIngredients.contains(entry.key),
                        title: Text(
                          entry.value.qualitative
                              ? '${entry.value.name} · ${entry.value.unit}'
                              : '${entry.value.quantityLabel} ${entry.value.name}',
                        ),
                        onChanged: (_) {
                          setState(() {
                            if (_checkedIngredients.contains(entry.key)) {
                              _checkedIngredients.remove(entry.key);
                            } else {
                              _checkedIngredients.add(entry.key);
                            }
                          });
                        },
                      ),
                    ),
                  ),
              const Divider(),
              Text('Step ${_stepIndex + 1}/${steps.length}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(step, style: Theme.of(context).textTheme.bodyLarge),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _stepIndex == 0
                          ? null
                          : () => setState(() => _stepIndex--),
                      child: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _stepIndex >= steps.length - 1
                          ? null
                          : () => setState(() => _stepIndex++),
                      child: const Text('Next Step'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _tts.speak(step),
                    child: const Text('Voice'),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                    },
                    child: const Text('Timer'),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}
