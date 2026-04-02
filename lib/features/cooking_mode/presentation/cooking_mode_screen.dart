import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/measurement/ingredient_display_units.dart';
import 'package:plateplan/core/measurement/measurement_system_provider.dart';
import 'package:plateplan/core/ui/measurement_system_toggle.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/services/nutrition_estimation.dart';
import 'package:plateplan/core/services/recipe_nutrition_lines.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/discover/data/discover_repository.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/grocery/data/grocery_repository.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:plateplan/features/recipes/presentation/recipe_editor_modals.dart';
import 'package:plateplan/features/recipes/presentation/recipe_direction_edit_chip.dart';
import 'package:plateplan/features/recipes/presentation/recipe_ingredient_edit_chip.dart';
import 'package:plateplan/features/recipes/presentation/recipe_lists_sharing_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _ingredientsEditMode = false;
  bool _directionsEditMode = false;
  bool _nutritionShowPerServing = false;
  bool _nutritionBusy = false;
  DateTime? _recipeMissingSince;
  Nutrition? _nutritionOverride;
  List<IngredientNutritionBreakdownLine> _nutritionBreakdownOverride = const [];

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(localCacheProvider).recordViewedRecipeId(widget.recipeId));
    unawaited(ref.read(groceryRepositoryProvider).ensureCatalogLoaded());
  }

  bool _isInstagramSourceUrl(String? raw) {
    final parsed = Uri.tryParse(raw?.trim() ?? '');
    if (parsed == null || parsed.host.isEmpty) return false;
    final host = parsed.host.toLowerCase();
    return host == 'instagram.com' ||
        host == 'www.instagram.com' ||
        host.endsWith('.instagram.com');
  }

  Future<void> _openSourcePost(String? raw) async {
    final text = raw?.trim() ?? '';
    final uri = Uri.tryParse(text);
    if (uri == null || !_isInstagramSourceUrl(text)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid Instagram post link available.')),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Instagram post.')),
      );
    }
  }

  Future<void> _openListsAndSharingSheet() async {
    final hasSharedHousehold =
        ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
    showRecipeListsSharingSheet(
      context: context,
      anchorContext: context,
      recipeId: widget.recipeId,
      hasSharedHousehold: hasSharedHousehold,
    );
  }

  Future<String?> _pickTargetListId({
    required List<AppList> lists,
    String? initialListId,
    required int itemCount,
  }) {
    if (lists.isEmpty) return Future.value(null);
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final sharedLists =
            lists.where((l) => l.scope == ListScope.household).toList();
        final privateLists =
            lists.where((l) => l.scope == ListScope.private).toList();
        final hasShared = sharedLists.isNotEmpty;
        final hasPrivate = privateLists.isNotEmpty;

        final initialTabIndex = hasShared ? 0 : 1;
        final preferredInitialId = initialListId ??
            (hasShared ? sharedLists.first.id : privateLists.first.id);
        var selectedId = preferredInitialId;

        return SafeArea(
          child: DefaultTabController(
            length: 2,
            initialIndex: initialTabIndex,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  Widget listRadio(List<AppList> visible) {
                    if (visible.isEmpty) {
                      return Center(
                        child: Text(
                          'No lists in this section.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final list = visible[idx];
                        return RadioListTile<String>(
                          value: list.id,
                          groupValue: selectedId,
                          onChanged: (v) => setModalState(() {
                            selectedId = v ?? selectedId;
                          }),
                          title: Text(list.name),
                        );
                      },
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Add $itemCount item${itemCount == 1 ? '' : 's'} to list',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      TabBar(
                        tabs: const [
                          Tab(text: 'Shared'),
                          Tab(text: 'Private'),
                        ],
                        onTap: (index) {
                          final next = index == 0 ? sharedLists : privateLists;
                          if (next.isEmpty) return;
                          // If the current selection isn't in the active tab, move
                          // selection to the first list in that tab.
                          final stillVisible = next.any((l) => l.id == selectedId);
                          if (!stillVisible) {
                            setModalState(() => selectedId = next.first.id);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: TabBarView(
                          children: [
                            listRadio(sharedLists),
                            listRadio(privateLists),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: (!hasShared && !hasPrivate)
                            ? null
                            : () => Navigator.of(sheetCtx).pop(selectedId),
                        child: const Text('Add to this list'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addCheckedIngredientsToList(Recipe recipe) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final checked = _checkedIngredients.toList()..sort();
    if (checked.isEmpty) return;

    final lists = await ref.read(listsProvider.future);
    if (!mounted) return;
    if (lists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No lists available right now.')),
      );
      return;
    }

    final currentSelected = ref.read(selectedListIdProvider);
    final targetListId = await _pickTargetListId(
      lists: lists,
      initialListId: currentSelected,
      itemCount: checked.length,
    );
    if (!mounted || targetListId == null || targetListId.isEmpty) return;

    final repo = ref.read(groceryRepositoryProvider);
    var added = 0;
    for (final idx in checked) {
      if (idx < 0 || idx >= recipe.ingredients.length) continue;
      final ing = recipe.ingredients[idx];
      final name = ing.name.trim();
      if (name.isEmpty) continue;
      try {
        final measurementSystem = ref.read(measurementSystemProvider);
        final cols = ing.qualitative
            ? null
            : ingredientDisplayColumns(ing, measurementSystem);
        await repo.addItem(
          userId: user.id,
          listId: targetListId,
          name: name,
          quantity: ing.qualitative
              ? ing.unit
              : cols!.amount,
          unit: ing.qualitative ? null : (cols!.unit.isEmpty ? null : cols.unit),
          fromRecipeId: recipe.id,
        );
        added++;
      } catch (_) {
        // Ignore individual failures (e.g. duplicates); keep going.
      }
    }

    ref.read(selectedListIdProvider.notifier).state = targetListId;
    invalidateActiveGroceryStreams(ref);

    if (!mounted) return;
    setState(() => _checkedIngredients.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added $added item${added == 1 ? '' : 's'} to list.')),
    );
  }

  Recipe? _recipeSnapshot(String id) {
    final recipes = ref.read(recipesProvider).valueOrNull;
    return recipes?.firstWhereOrNull((r) => r.id == id);
  }

  Future<void> _persistRecipeIngredients(
    Recipe base,
    List<Ingredient> ingredients,
  ) async {
    final updated = base.copyWith(ingredients: ingredients);
    try {
      await ref.read(recipesRepositoryProvider).updateRecipe(base.id, updated);
      ref.invalidate(recipesProvider);
      if (mounted) {
        setState(() => _checkedIngredients.clear());
      }
    } on StateError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save ingredients. Try again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save ingredients. Check your connection.'),
        ),
      );
    }
  }

  Future<void> _editIngredientLine(Recipe recipe, int index) async {
    if (index < 0 || index >= recipe.ingredients.length) return;
    final initial = recipe.ingredients[index];
    final outcome =
        await showImportIngredientEditorDialog(context, ref, initial: initial);
    if (!mounted || outcome == null) return;
    final fresh = _recipeSnapshot(recipe.id);
    if (fresh == null) return;
    final list = [...fresh.ingredients];
    if (index < 0 || index >= list.length) return;
    if (outcome is ImportIngredientEditorSaved) {
      list[index] = outcome.ingredient;
      await _persistRecipeIngredients(fresh, list);
    } else if (outcome is ImportIngredientEditorDeleted) {
      list.removeAt(index);
      await _persistRecipeIngredients(fresh, list);
    }
  }

  Future<void> _removeIngredientLine(Recipe recipe, int index) async {
    final fresh = _recipeSnapshot(recipe.id);
    if (fresh == null) return;
    final list = [...fresh.ingredients];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await _persistRecipeIngredients(fresh, list);
  }

  Future<void> _addIngredientLine(Recipe recipe) async {
    final outcome =
        await showImportIngredientEditorDialog(context, ref, initial: null);
    if (!mounted || outcome == null) return;
    if (outcome is! ImportIngredientEditorSaved) return;
    final fresh = _recipeSnapshot(recipe.id);
    if (fresh == null) return;
    await _persistRecipeIngredients(
      fresh,
      [...fresh.ingredients, outcome.ingredient],
    );
  }

  Future<void> _persistRecipeInstructions(
    Recipe base,
    List<String> instructions,
  ) async {
    final updated = base.copyWith(instructions: instructions);
    try {
      await ref.read(recipesRepositoryProvider).updateRecipe(base.id, updated);
      ref.invalidate(recipesProvider);
      if (mounted) {
        setState(() {
          if (instructions.isEmpty) {
            _stepIndex = 0;
          } else if (_stepIndex >= instructions.length) {
            _stepIndex = instructions.length - 1;
          }
        });
      }
    } on StateError {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save directions. Try again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save directions. Check your connection.'),
        ),
      );
    }
  }

  Future<void> _editDirectionLine(Recipe recipe, int index) async {
    if (index < 0 || index >= recipe.instructions.length) return;
    final initialText = recipe.instructions[index];
    final outcome = await showImportDirectionStepDialog(
      context,
      stepIndex: index,
      initialText: initialText,
      isNewStep: false,
      showRemoveButton: recipe.instructions.length > 1,
    );
    if (!mounted || outcome == null) return;
    final fresh = _recipeSnapshot(recipe.id);
    if (fresh == null) return;
    final list = [...fresh.instructions];
    if (index < 0 || index >= list.length) return;
    if (outcome is ImportDirectionEditorSaved) {
      list[index] = outcome.text;
      await _persistRecipeInstructions(fresh, list);
    } else if (outcome is ImportDirectionEditorDeleted) {
      if (list.length <= 1) {
        await _persistRecipeInstructions(fresh, const []);
      } else {
        list.removeAt(index);
        await _persistRecipeInstructions(fresh, list);
      }
    }
  }

  Future<void> _removeDirectionLine(Recipe recipe, int index) async {
    final fresh = _recipeSnapshot(recipe.id);
    if (fresh == null) return;
    final list = [...fresh.instructions];
    if (index < 0 || index >= list.length) return;
    if (list.length <= 1) {
      await _persistRecipeInstructions(fresh, const []);
    } else {
      list.removeAt(index);
      await _persistRecipeInstructions(fresh, list);
    }
  }

  Future<void> _addDirectionLine(Recipe recipe) async {
    final fresh = _recipeSnapshot(recipe.id);
    if (fresh == null) return;
    final list = [...fresh.instructions];
    final isReplacingEmptyOnly =
        list.length == 1 && list.first.trim().isEmpty;
    final isEmpty = list.isEmpty;
    final newIndex = isReplacingEmptyOnly ? 0 : (isEmpty ? 0 : list.length);
    final outcome = await showImportDirectionStepDialog(
      context,
      stepIndex: newIndex,
      initialText: '',
      isNewStep: true,
      showRemoveButton: !isEmpty && !isReplacingEmptyOnly,
    );
    if (!mounted || outcome == null) return;
    if (outcome is ImportDirectionEditorDeleted) return;
    if (outcome is! ImportDirectionEditorSaved) return;
    final text = outcome.text.trim();
    if (text.isEmpty) return;
    final fresh2 = _recipeSnapshot(recipe.id);
    if (fresh2 == null) return;
    var next = [...fresh2.instructions];
    if (isReplacingEmptyOnly) {
      next = [text];
    } else if (isEmpty) {
      next = [text];
    } else {
      next.add(text);
    }
    await _persistRecipeInstructions(fresh2, next);
  }

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
    final measurementSystem = ref.watch(measurementSystemProvider);
    return recipe.ingredients.map((ingredient) {
      final label = ingredient.qualitative
          ? '${ingredient.name}: ${ingredient.unit}'
          : '${ingredientDisplayQuantityLabel(ingredient, measurementSystem)} ${ingredient.name}'
              .trim();
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
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/recipes');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Lists & Sharing',
            onPressed: () {
              final recipes = ref.read(recipesProvider).valueOrNull;
              final recipe = recipes?.firstWhereOrNull(
                (r) => r.id == widget.recipeId,
              );
              if (recipe == null) return;
              _openListsAndSharingSheet();
            },
            icon: const Icon(Icons.library_books_outlined),
          ),
        ],
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

          final measurementSystem = ref.watch(measurementSystemProvider);

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
                  Chip(
                    avatar: const Icon(Icons.shopping_basket_rounded, size: 16),
                    label: Text('${recipe.ingredients.length} ingredients'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.format_list_numbered_rounded, size: 16),
                    label: Text(
                      recipe.instructions.isEmpty
                          ? 'No directions'
                          : '${recipe.instructions.length} steps',
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.people_alt_rounded, size: 16),
                    label: Text('${recipe.servings} servings'),
                  ),
                  if (recipe.source == 'instagram_import')
                    ActionChip(
                      avatar: const Icon(Icons.camera_alt_rounded, size: 16),
                      label: const Text('Instagram'),
                      side: BorderSide(
                        color: scheme.error.withValues(alpha: 0.35),
                      ),
                      onPressed: _isInstagramSourceUrl(recipe.sourceUrl)
                          ? () => _openSourcePost(recipe.sourceUrl)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _buildNutritionSection(context, recipe),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Ingredients',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 36,
                        ),
                        tooltip: _ingredientsEditMode
                            ? 'Done editing ingredients'
                            : 'Edit ingredients',
                        icon: Icon(
                          _ingredientsEditMode
                              ? Icons.check_rounded
                              : Icons.edit_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            _ingredientsEditMode = !_ingredientsEditMode;
                          });
                        },
                      ),
                      const MeasurementSystemToggle(),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (!_ingredientsEditMode)
                ...recipe.ingredients.asMap().entries.map(
                      (entry) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          value: _checkedIngredients.contains(entry.key),
                          title: Text(
                            entry.value.qualitative
                                ? '${entry.value.name} · ${entry.value.unit}'
                                : '${ingredientDisplayQuantityLabel(entry.value, measurementSystem)} ${entry.value.name}',
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
                    )
              else ...[
                ...recipe.ingredients.asMap().entries.map(
                      (entry) => RecipeIngredientEditChip(
                        label:
                            RecipeIngredientEditChip.labelForIngredientWithSystem(
                          entry.value,
                          measurementSystem,
                        ),
                        onTap: () => unawaited(
                          _editIngredientLine(recipe, entry.key),
                        ),
                        onDelete: () => unawaited(
                          _removeIngredientLine(recipe, entry.key),
                        ),
                      ),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_addIngredientLine(recipe)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add ingredient'),
                  ),
                ),
              ],
              if (_checkedIngredients.isNotEmpty) ...[
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: () => _addCheckedIngredientsToList(recipe),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: Text(
                    'Add ${_checkedIngredients.length} item${_checkedIngredients.length == 1 ? '' : 's'} to List',
                  ),
                ),
              ],
              const Divider(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Directions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 36,
                    ),
                    tooltip: _directionsEditMode
                        ? 'Done editing directions'
                        : 'Edit directions',
                    icon: Icon(
                      _directionsEditMode
                          ? Icons.check_rounded
                          : Icons.edit_outlined,
                    ),
                    onPressed: () {
                      setState(() {
                        _directionsEditMode = !_directionsEditMode;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (!_directionsEditMode) ...[
                if (recipe.instructions.isEmpty) ...[
                  Text(
                    'No directions for this recipe. Tap Edit to add steps, or add them when editing the recipe.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      onPressed: () async {
                        await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                      },
                      child: const Text('Timer'),
                    ),
                  ),
                ] else ...[
                  Builder(
                    builder: (context) {
                      final instr = recipe.instructions;
                      final idx = _stepIndex.clamp(0, instr.length - 1);
                      final stepText = instr[idx];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Step ${idx + 1}/${instr.length}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Text(
                              stepText,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: idx == 0
                                      ? null
                                      : () => setState(() => _stepIndex--),
                                  child: const Text('Previous'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed: idx >= instr.length - 1
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
                                onPressed: () => _tts.speak(stepText),
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
                  ),
                ],
              ] else ...[
                if (recipe.instructions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No steps yet. Add one below.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  )
                else
                  ...recipe.instructions.asMap().entries.map(
                        (e) => RecipeDirectionEditChip(
                          label: RecipeDirectionEditChip.labelForStep(
                            e.key + 1,
                            e.value,
                          ),
                          onTap: () => unawaited(
                            _editDirectionLine(recipe, e.key),
                          ),
                          onDelete: () => unawaited(
                            _removeDirectionLine(recipe, e.key),
                          ),
                        ),
                      ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_addDirectionLine(recipe)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add step'),
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}
