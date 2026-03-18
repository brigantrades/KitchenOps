import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/services/api_services.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DiscoverMealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner');

  const DiscoverMealType(this.label);
  final String label;
}

class DiscoverFilterChip {
  const DiscoverFilterChip({
    required this.id,
    required this.label,
    required this.keywords,
  });

  final String id;
  final String label;
  final List<String> keywords;

  bool get isAll => id == 'all';
}

const _breakfastChips = <DiscoverFilterChip>[
  DiscoverFilterChip(id: 'all', label: 'All', keywords: <String>[]),
  DiscoverFilterChip(id: 'quick', label: 'Quick', keywords: <String>['quick']),
  DiscoverFilterChip(
    id: 'high-protein',
    label: 'High Protein',
    keywords: <String>['protein', 'high protein'],
  ),
  DiscoverFilterChip(id: 'eggs', label: 'Eggs', keywords: <String>['egg']),
  DiscoverFilterChip(id: 'oats', label: 'Oats', keywords: <String>['oat']),
  DiscoverFilterChip(
    id: 'sweet',
    label: 'Sweet',
    keywords: <String>['sweet', 'pancake', 'waffle', 'smoothie'],
  ),
  DiscoverFilterChip(
    id: 'savory',
    label: 'Savory',
    keywords: <String>['savory', 'toast', 'omelet'],
  ),
];

const _lunchChips = <DiscoverFilterChip>[
  DiscoverFilterChip(id: 'all', label: 'All', keywords: <String>[]),
  DiscoverFilterChip(id: 'quick', label: 'Quick', keywords: <String>['quick']),
  DiscoverFilterChip(id: 'salad', label: 'Salad', keywords: <String>['salad']),
  DiscoverFilterChip(
    id: 'sandwich',
    label: 'Sandwich',
    keywords: <String>['sandwich'],
  ),
  DiscoverFilterChip(id: 'wrap', label: 'Wrap', keywords: <String>['wrap']),
  DiscoverFilterChip(id: 'bowl', label: 'Bowl', keywords: <String>['bowl']),
  DiscoverFilterChip(id: 'soup', label: 'Soup', keywords: <String>['soup']),
];

const _dinnerChips = <DiscoverFilterChip>[
  DiscoverFilterChip(id: 'all', label: 'All', keywords: <String>[]),
  DiscoverFilterChip(
    id: 'chicken',
    label: 'Chicken',
    keywords: <String>['chicken'],
  ),
  DiscoverFilterChip(id: 'beef', label: 'Beef', keywords: <String>['beef']),
  DiscoverFilterChip(
    id: 'vegetarian',
    label: 'Vegetarian',
    keywords: <String>['vegetarian'],
  ),
  DiscoverFilterChip(id: 'pasta', label: 'Pasta', keywords: <String>['pasta']),
  DiscoverFilterChip(id: 'pork', label: 'Pork', keywords: <String>['pork']),
];

List<DiscoverFilterChip> discoverChipsForMeal(DiscoverMealType meal) {
  switch (meal) {
    case DiscoverMealType.breakfast:
      return _breakfastChips;
    case DiscoverMealType.lunch:
      return _lunchChips;
    case DiscoverMealType.dinner:
      return _dinnerChips;
  }
}

class DiscoverRepository {
  DiscoverRepository(this._gemini, this._spoonacular, this._cache);

  final GeminiService _gemini;
  final SpoonacularService _spoonacular;
  final LocalCache _cache;
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> _ensureProfileRow(String userId) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'name': 'PlatePlanner',
    });
  }

  Future<List<Recipe>> generateWeekly(Profile profile) async {
    final generated = await _gemini.generateWeeklyPlan(profile: profile);
    return generated
        .map(
          (entry) => Recipe(
            id: 'ai-${Random().nextInt(99999999)}',
            title: entry['title']?.toString() ?? 'AI Recipe',
            mealType: MealType.values.firstWhere(
              (m) => m.name == entry['meal_type'],
              orElse: () => MealType.dinner,
            ),
            cuisineTags: (entry['cuisine_tags'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const ['AI'],
            ingredients: (entry['ingredients'] as List?)
                    ?.whereType<Map<String, dynamic>>()
                    .map(Ingredient.fromJson)
                    .toList() ??
                const [],
            instructions: (entry['instructions'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ??
                const [],
            source: 'gemini',
          ),
        )
        .toList();
  }

  Future<Recipe?> createFromIngredients(List<String> ingredients) async {
    return createFromCriteria(
      ingredients: ingredients,
      dietTags: const [],
      mealType: null,
      maxCookTimeMinutes: null,
      servings: null,
      prompt: null,
    );
  }

  Future<Recipe?> createFromCriteria({
    required List<String> ingredients,
    required List<String> dietTags,
    String? mealType,
    int? maxCookTimeMinutes,
    int? servings,
    String? prompt,
  }) async {
    final normalizedIngredients = ingredients
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    final normalizedTags = dietTags
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    final normalizedPrompt = (prompt ?? '').trim().toLowerCase();
    final cacheKey =
        'recipe:v2:${normalizedIngredients.join('|')}|${normalizedTags.join('|')}|${mealType ?? ''}|${maxCookTimeMinutes ?? ''}|${servings ?? ''}|$normalizedPrompt';
    final cached = _cache.loadGeneratedRecipe(cacheKey);
    if (cached != null) {
      return Recipe.fromJson(cached);
    }

    Map<String, dynamic> generated = await _gemini.generateRecipeWithCriteria(
      ingredients: ingredients,
      dietTags: dietTags,
      mealType: mealType,
      maxCookTimeMinutes: maxCookTimeMinutes,
      servings: servings,
      prompt: prompt,
    );
    if (generated.isEmpty) {
      final fallbackPrompt = _buildFallbackPrompt(
        ingredients: ingredients,
        dietTags: dietTags,
        mealType: mealType,
        maxCookTimeMinutes: maxCookTimeMinutes,
        servings: servings,
        prompt: prompt,
      );
      generated = await _gemini.generateRecipeWithCriteria(
        ingredients: ingredients,
        dietTags: dietTags,
        mealType: mealType,
        maxCookTimeMinutes: maxCookTimeMinutes,
        servings: servings,
        prompt: fallbackPrompt,
      );
    }
    if (generated.isEmpty) {
      generated = _buildLocalFallbackRecipeJson(
        ingredients: ingredients,
        dietTags: dietTags,
        mealType: mealType,
        prompt: prompt,
      );
    }

    Nutrition nutrition = const Nutrition();
    var source = 'gemini';

    try {
      nutrition =
          await _spoonacular.estimateNutritionFromIngredients(ingredients);
      final hasSpoonData = nutrition.calories > 0 ||
          nutrition.protein > 0 ||
          nutrition.fat > 0 ||
          nutrition.carbs > 0;
      if (hasSpoonData) {
        source = 'gemini_spoonacular_verified';
      } else {
        nutrition = await _gemini.estimateNutritionFromIngredients(ingredients);
        source = 'gemini_ai_estimated';
      }
    } catch (_) {
      nutrition = await _gemini.estimateNutritionFromIngredients(ingredients);
      source = 'gemini_ai_estimated';
    }
    if (source == 'gemini') {
      source = 'gemini_ai_estimated';
    }

    final recipe = Recipe(
      id: 'ai-${Random().nextInt(99999999)}',
      title: generated['title']?.toString() ?? 'Fridge Recipe',
      mealType: MealType.values.firstWhere(
        (m) => m.name == generated['meal_type'],
        orElse: () => MealType.dinner,
      ),
      cuisineTags: (generated['cuisine_tags'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['AI'],
      ingredients: (generated['ingredients'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(Ingredient.fromJson)
              .toList() ??
          const [],
      instructions: (generated['instructions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      nutrition: nutrition,
      source: source,
    );
    await _cache.saveGeneratedRecipe(cacheKey, recipe.toJson());
    return recipe;
  }

  Future<List<Recipe>> createOptionsFromCriteria({
    required List<String> ingredients,
    required List<String> dietTags,
    String? mealType,
    int? maxCookTimeMinutes,
    int? servings,
    String? prompt,
    int count = 3,
  }) async {
    final generated = await _gemini.generateRecipeOptionsWithCriteria(
      ingredients: ingredients,
      dietTags: dietTags,
      mealType: mealType,
      maxCookTimeMinutes: maxCookTimeMinutes,
      servings: servings,
      prompt: prompt,
      count: count,
    );

    if (generated.isEmpty) {
      final single = await createFromCriteria(
        ingredients: ingredients,
        dietTags: dietTags,
        mealType: mealType,
        maxCookTimeMinutes: maxCookTimeMinutes,
        servings: servings,
        prompt: prompt,
      );
      return single == null ? const [] : [single];
    }

    final options = <Recipe>[];
    for (final entry in generated.take(count)) {
      options.add(
        Recipe(
          id: 'ai-${Random().nextInt(99999999)}',
          title: entry['title']?.toString() ?? 'AI Recipe',
          mealType: MealType.values.firstWhere(
            (m) => m.name == entry['meal_type'],
            orElse: () => MealType.dinner,
          ),
          prepTime: (entry['prep_time'] as num?)?.toInt(),
          cookTime: (entry['cook_time'] as num?)?.toInt(),
          cuisineTags: (entry['cuisine_tags'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const ['AI'],
          ingredients: (entry['ingredients'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(Ingredient.fromJson)
                  .toList() ??
              const [],
          instructions: (entry['instructions'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          source: 'gemini',
        ),
      );
    }
    return options;
  }

  String _buildFallbackPrompt({
    required List<String> ingredients,
    required List<String> dietTags,
    String? mealType,
    int? maxCookTimeMinutes,
    int? servings,
    String? prompt,
  }) {
    final parts = <String>[
      if (prompt != null && prompt.trim().isNotEmpty) prompt.trim(),
      if (ingredients.isNotEmpty)
        'Use these ingredients: ${ingredients.join(', ')}.',
      if (dietTags.isNotEmpty) 'Diet style: ${dietTags.join(', ')}.',
      if (mealType != null) 'Meal type should be $mealType.',
      if (maxCookTimeMinutes != null)
        'Cook time under $maxCookTimeMinutes minutes.',
      if (servings != null) 'Make $servings servings.',
    ];
    if (parts.isEmpty) {
      return 'Create a simple healthy dinner recipe with clear ingredients and steps.';
    }
    return parts.join(' ');
  }

  Map<String, dynamic> _buildLocalFallbackRecipeJson({
    required List<String> ingredients,
    required List<String> dietTags,
    String? mealType,
    String? prompt,
  }) {
    final resolvedMealType = MealType.values.firstWhere(
      (m) => m.name == mealType,
      orElse: () => MealType.dinner,
    );
    final ingredientNames = ingredients.isEmpty
        ? <String>['Olive oil', 'Garlic', 'Salt']
        : ingredients;
    final ingredientJson = ingredientNames
        .map(
          (name) => <String, dynamic>{
            'name': name,
            'amount': 1,
            'unit': 'piece',
            'category': 'other',
          },
        )
        .toList();
    final instructions = <String>[
      'Prep all ingredients and gather your pan and utensils.',
      'Cook the main ingredients over medium heat until tender and flavorful.',
      'Taste, adjust seasoning, and serve warm.',
    ];
    final title = (prompt != null && prompt.trim().isNotEmpty)
        ? 'AI ${prompt.trim().split(' ').take(3).join(' ')}'
        : 'AI Quick ${resolvedMealType.name[0].toUpperCase()}${resolvedMealType.name.substring(1)}';
    return <String, dynamic>{
      'title': title,
      'meal_type': resolvedMealType.name,
      'cuisine_tags': dietTags.isEmpty ? <String>['AI'] : dietTags,
      'ingredients': ingredientJson,
      'instructions': instructions,
    };
  }

  Future<void> saveRecipe(
      {required String userId, required Recipe recipe}) async {
    final payload = recipe.toJson()..remove('id');
    await _ensureProfileRow(userId);
    await _client.from('recipes').insert({'user_id': userId, ...payload});
  }

  Future<List<Recipe>> listPublicRecipesForMeal(DiscoverMealType meal) async {
    final rows = await _client
        .from('recipes')
        .select()
        .eq('is_public', true)
        .eq('meal_type', meal.name)
        .order('created_at', ascending: false);
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(Recipe.fromJson)
        .toList();
  }

  List<Recipe> filterRecipesByChip(
    List<Recipe> recipes,
    DiscoverFilterChip chip,
  ) {
    if (chip.isAll) return recipes;
    if (chip.id == 'quick') {
      return recipes.where((recipe) {
        final totalTime = (recipe.prepTime ?? 0) + (recipe.cookTime ?? 0);
        return totalTime > 0 && totalTime <= 30;
      }).toList();
    }
    return recipes.where((recipe) {
      final title = recipe.title.toLowerCase();
      final tags = recipe.cuisineTags.map((tag) => tag.toLowerCase()).toList();
      for (final keyword in chip.keywords) {
        if (title.contains(keyword) ||
            tags.any((tag) => tag.contains(keyword))) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  Future<void> setFavorite(String recipeId, bool value) async {
    await _client
        .from('recipes')
        .update({'is_favorite': value}).eq('id', recipeId);
  }

  Future<void> setToTry(String recipeId, bool value) async {
    await _client
        .from('recipes')
        .update({'is_to_try': value}).eq('id', recipeId);
  }
}

final geminiServiceProvider = Provider<GeminiService>((ref) => GeminiService());

final discoverRepositoryProvider = Provider<DiscoverRepository>((ref) {
  return DiscoverRepository(
    ref.watch(geminiServiceProvider),
    ref.watch(spoonacularServiceProvider),
    ref.watch(localCacheProvider),
  );
});

final generatedWeeklyProvider = FutureProvider<List<Recipe>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return [];
  return ref.watch(discoverRepositoryProvider).generateWeekly(profile);
});

final discoverMealTypeProvider =
    StateProvider<DiscoverMealType>((ref) => DiscoverMealType.dinner);

final discoverChipIdProvider = StateProvider<String>((ref) => 'all');

final discoverAvailableChipsProvider =
    Provider<List<DiscoverFilterChip>>((ref) {
  final meal = ref.watch(discoverMealTypeProvider);
  return discoverChipsForMeal(meal);
});

final discoverSelectedChipProvider = Provider<DiscoverFilterChip>((ref) {
  final chipId = ref.watch(discoverChipIdProvider);
  final chips = ref.watch(discoverAvailableChipsProvider);
  return chips.firstWhere(
    (chip) => chip.id == chipId,
    orElse: () => chips.first,
  );
});

final discoverPublicRecipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final meal = ref.watch(discoverMealTypeProvider);
  return ref.watch(discoverRepositoryProvider).listPublicRecipesForMeal(meal);
});

final discoverFilteredRecipesProvider =
    Provider<AsyncValue<List<Recipe>>>((ref) {
  final selectedChip = ref.watch(discoverSelectedChipProvider);
  final recipesAsync = ref.watch(discoverPublicRecipesProvider);
  return recipesAsync.whenData((recipes) {
    return ref
        .watch(discoverRepositoryProvider)
        .filterRecipesByChip(recipes, selectedChip);
  });
});
