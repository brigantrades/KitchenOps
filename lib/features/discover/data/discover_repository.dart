import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/services/api_services.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/discover/data/discover_selected_dietary_tags_notifier.dart';
import 'package:plateplan/features/discover/domain/discover_browse_categories.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/recipes/data/recipes_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DiscoverMealType {
  entree('Breakfast'),
  side('Lunch'),
  sauce('Dinner'),
  snack('Appetizers & Snacks'),
  dessert('Desserts');

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

enum DiscoverPrepTimeBucket {
  any('Any'),
  under15('Under 15 min'),
  from15To30('15-30 min'),
  over30('30+ min');

  const DiscoverPrepTimeBucket(this.label);
  final String label;
}

enum DiscoverRatingBucket {
  any('Any'),
  threePlus('3 Stars +'),
  fourPlus('4 Stars +');

  const DiscoverRatingBucket(this.label);
  final String label;
}

class DiscoverCuisineTile {
  const DiscoverCuisineTile({
    required this.id,
    required this.label,
    required this.recipeCount,
  });

  final String id;
  final String label;
  final int recipeCount;
}

class DiscoverFilters {
  const DiscoverFilters({
    this.query = '',
    this.cuisineIds = const <String>{},
    this.dietaryIds = const <String>{},
    this.prepTime = DiscoverPrepTimeBucket.any,
    this.rating = DiscoverRatingBucket.any,
    this.mealTypes = const <DiscoverMealType>{},
  });

  final String query;
  final Set<String> cuisineIds;
  final Set<String> dietaryIds;
  final DiscoverPrepTimeBucket prepTime;
  final DiscoverRatingBucket rating;
  final Set<DiscoverMealType> mealTypes;

  bool get isDefault =>
      query.trim().isEmpty &&
      cuisineIds.isEmpty &&
      dietaryIds.isEmpty &&
      prepTime == DiscoverPrepTimeBucket.any &&
      rating == DiscoverRatingBucket.any &&
      mealTypes.isEmpty;

  DiscoverFilters copyWith({
    String? query,
    Set<String>? cuisineIds,
    Set<String>? dietaryIds,
    DiscoverPrepTimeBucket? prepTime,
    DiscoverRatingBucket? rating,
    Set<DiscoverMealType>? mealTypes,
  }) {
    return DiscoverFilters(
      query: query ?? this.query,
      cuisineIds: cuisineIds ?? this.cuisineIds,
      dietaryIds: dietaryIds ?? this.dietaryIds,
      prepTime: prepTime ?? this.prepTime,
      rating: rating ?? this.rating,
      mealTypes: mealTypes ?? this.mealTypes,
    );
  }
}

extension DiscoverMealTypeX on DiscoverMealType {
  MealType get recipeMealType {
    switch (this) {
      case DiscoverMealType.entree:
        return MealType.entree;
      case DiscoverMealType.side:
        return MealType.side;
      case DiscoverMealType.sauce:
        return MealType.sauce;
      case DiscoverMealType.snack:
        return MealType.snack;
      case DiscoverMealType.dessert:
        return MealType.dessert;
    }
  }
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
    keywords: <String>['vegetarian', 'plant-based'],
  ),
  DiscoverFilterChip(id: 'pasta', label: 'Pasta', keywords: <String>['pasta']),
  DiscoverFilterChip(id: 'pork', label: 'Pork', keywords: <String>['pork']),
  DiscoverFilterChip(
    id: 'seafood',
    label: 'Seafood',
    keywords: <String>['seafood', 'salmon', 'shrimp', 'fish'],
  ),
  DiscoverFilterChip(
    id: 'one-pan',
    label: 'One-Pan',
    keywords: <String>['one-pan', 'one pan', 'sheet pan', 'sheet-pan'],
  ),
  DiscoverFilterChip(
    id: 'southern',
    label: 'Southern',
    keywords: <String>['southern', 'comfort'],
  ),
  DiscoverFilterChip(
    id: 'crockpot',
    label: 'Crockpot',
    keywords: <String>['crockpot', 'slow cooker', 'slow-cooker'],
  ),
  DiscoverFilterChip(
    id: 'instant-pot',
    label: 'Instant Pot',
    keywords: <String>['instant pot', 'instant-pot', 'pressure cooker'],
  ),
  DiscoverFilterChip(
    id: 'grill',
    label: 'Grill',
    keywords: <String>['grill', 'grilled', 'bbq'],
  ),
  DiscoverFilterChip(
    id: 'soup',
    label: 'Soup',
    keywords: <String>['soup', 'stew', 'chowder', 'bisque'],
  ),
];

const _dessertChips = <DiscoverFilterChip>[
  DiscoverFilterChip(id: 'all', label: 'All', keywords: <String>[]),
  DiscoverFilterChip(
    id: 'dessert-chocolate',
    label: 'Chocolate',
    keywords: <String>['chocolate', 'brownie', 'mousse', 'cacao', 'fudge'],
  ),
  DiscoverFilterChip(
    id: 'dessert-cookies-bars',
    label: 'Cookies & Bars',
    keywords: <String>[
      'cookie',
      'bars',
      'shortbread',
      'snickerdoodle',
      'thumbprint',
    ],
  ),
  DiscoverFilterChip(
    id: 'dessert-cakes-cupcakes',
    label: 'Cakes & Cupcakes',
    keywords: <String>['cake', 'cupcake', 'layer cake', 'pound cake'],
  ),
  DiscoverFilterChip(
    id: 'dessert-muffins-breads',
    label: 'Muffins & Quick Breads',
    keywords: <String>['muffin', 'banana bread', 'zucchini bread', 'quick bread'],
  ),
  DiscoverFilterChip(
    id: 'dessert-pies-cobblers-crisps',
    label: 'Pies, Cobblers & Crisps',
    keywords: <String>['pie', 'cobbler', 'crisp', 'crumble', 'tart'],
  ),
  DiscoverFilterChip(
    id: 'dessert-fruit',
    label: 'Fruit Desserts',
    keywords: <String>['fruit', 'berries', 'strawberry', 'peach', 'apple', 'cherry'],
  ),
  DiscoverFilterChip(
    id: 'dessert-no-bake',
    label: 'No-Bake',
    keywords: <String>['no-bake', 'energy balls', 'protein balls', 'truffles'],
  ),
  DiscoverFilterChip(
    id: 'dessert-frozen-creamy',
    label: 'Frozen & Creamy',
    keywords: <String>['ice cream', 'pudding', 'panna cotta', 'affogato', 'custard'],
  ),
];

List<DiscoverFilterChip> discoverChipsForMeal(DiscoverMealType meal) {
  switch (meal) {
    case DiscoverMealType.entree:
      return _breakfastChips;
    case DiscoverMealType.side:
      return _lunchChips;
    case DiscoverMealType.sauce:
      return _dinnerChips;
    case DiscoverMealType.snack:
      return const <DiscoverFilterChip>[
        DiscoverFilterChip(id: 'all', label: 'All', keywords: <String>[]),
        DiscoverFilterChip(
          id: 'dips-spreads',
          label: 'Dips & Spreads',
          keywords: <String>[
            'dip',
            'hummus',
            'guacamole',
            'salsa',
            'tapenade',
            'tzatziki',
          ],
        ),
        DiscoverFilterChip(
          id: 'finger-foods',
          label: 'Finger Foods',
          keywords: <String>[
            'finger food',
            'bites',
            'skewer',
            'roll',
            'taquito',
            'dumpling',
            'poppers',
            'deviled',
          ],
        ),
        DiscoverFilterChip(
          id: 'boards-platters',
          label: 'Boards & Platters',
          keywords: <String>[
            'board',
            'platter',
            'charcuterie',
            'crudite',
            'mezze',
            'nachos',
          ],
        ),
        DiscoverFilterChip(
          id: 'cheesy-bakes',
          label: 'Cheesy Bakes',
          keywords: <String>[
            'baked brie',
            'cheese log',
            'potato skins',
            'spinach artichoke',
            'cheese',
          ],
        ),
        DiscoverFilterChip(
          id: 'wings-meaty-bites',
          label: 'Wings & Meaty Bites',
          keywords: <String>[
            'wings',
            'meatballs',
            'sausage',
            'buffalo',
            'chicken',
            'bacon',
          ],
        ),
        DiscoverFilterChip(
          id: 'seafood-appetizers',
          label: 'Seafood Appetizers',
          keywords: <String>[
            'shrimp',
            'prawns',
            'smoked salmon',
            'ceviche',
            'fish',
          ],
        ),
        DiscoverFilterChip(
          id: 'crispy-snacks',
          label: 'Crispy Snacks',
          keywords: <String>[
            'fries',
            'onion rings',
            'fried pickles',
            'zucchini fries',
            'chips',
            'popcorn',
          ],
        ),
        DiscoverFilterChip(
          id: 'healthy-veggie-snacks',
          label: 'Healthy & Veggie',
          keywords: <String>[
            'cauliflower',
            'mushroom',
            'vegetarian',
            'vegan',
            'veggie',
            'nuts',
            'seeds',
          ],
        ),
      ];
    case DiscoverMealType.dessert:
      return _dessertChips;
  }
}

class DiscoverRepository {
  DiscoverRepository(this._gemini, this._spoonacular, this._cache);

  final GeminiService _gemini;
  final SpoonacularService _spoonacular;
  final LocalCache _cache;
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> _ensureProfileRow(String userId) async {
    try {
      await _client.from('profiles').insert({'id': userId});
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
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
              orElse: () => MealType.entree,
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
        orElse: () => MealType.entree,
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
            orElse: () => MealType.entree,
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
      orElse: () => MealType.entree,
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
        .eq('visibility', RecipeVisibility.public.name)
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

  Future<void> saveDiscoverRecipeForUser({
    required String userId,
    required Recipe recipe,
    bool? favorite,
    bool? toTry,
  }) async {
    await _ensureProfileRow(userId);

    final existing = await _client
        .from('recipes')
        .select('id,is_favorite,is_to_try')
        .eq('user_id', userId)
        .eq('visibility', 'personal')
        .eq('source', 'saved_from_discover')
        .eq('title', recipe.title)
        .eq('meal_type', recipe.mealType.name)
        .maybeSingle();

    if (existing != null) {
      final currentFavorite = existing['is_favorite'] == true;
      final currentToTry = existing['is_to_try'] == true;
      await _client.from('recipes').update({
        'is_favorite': favorite ?? currentFavorite,
        'is_to_try': toTry ?? currentToTry,
      }).eq('id', existing['id']);
      return;
    }

    final payload = recipe.toJson()
      ..remove('id')
      ..remove('user_id')
      ..remove('household_id')
      ..remove('visibility')
      ..remove('api_id')
      ..remove('is_favorite')
      ..remove('is_to_try')
      ..remove('source');

    await _client.from('recipes').insert({
      'user_id': userId,
      'visibility': 'personal',
      'source': 'saved_from_discover',
      'is_favorite': favorite ?? false,
      'is_to_try': toTry ?? false,
      ...payload,
    });
  }

  Future<String> saveDiscoverRecipeForUserAndReturnId({
    required String userId,
    required Recipe recipe,
    bool? favorite,
    bool? toTry,
  }) async {
    await _ensureProfileRow(userId);

    final existing = await _client
        .from('recipes')
        .select('id,is_favorite,is_to_try')
        .eq('user_id', userId)
        .eq('visibility', 'personal')
        .eq('source', 'saved_from_discover')
        .eq('title', recipe.title)
        .eq('meal_type', recipe.mealType.name)
        .maybeSingle();

    if (existing != null) {
      final currentFavorite = existing['is_favorite'] == true;
      final currentToTry = existing['is_to_try'] == true;
      await _client.from('recipes').update({
        'is_favorite': favorite ?? currentFavorite,
        'is_to_try': toTry ?? currentToTry,
      }).eq('id', existing['id']);
      return existing['id'].toString();
    }

    final payload = recipe.toJson()
      ..remove('id')
      ..remove('user_id')
      ..remove('household_id')
      ..remove('visibility')
      ..remove('api_id')
      ..remove('is_favorite')
      ..remove('is_to_try')
      ..remove('source');

    final inserted = await _client
        .from('recipes')
        .insert({
          'user_id': userId,
          'visibility': 'personal',
          'source': 'saved_from_discover',
          'is_favorite': favorite ?? false,
          'is_to_try': toTry ?? false,
          ...payload,
        })
        .select('id')
        .single();
    return inserted['id'].toString();
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
    StateProvider<DiscoverMealType>((ref) => DiscoverMealType.entree);

/// Drives shuffle order for [discoverLazyBreakfastRecipesProvider]. Rolled when
/// Discover opens or when the user switches to Breakfast.
final discoverBreakfastFeaturedShuffleSeedProvider =
    StateProvider<int>((ref) => 0);

/// Drives shuffle order for [discoverQuickLunchRecipesProvider]. Rolled when
/// Discover opens or when the user switches to Lunch.
final discoverLunchFeaturedShuffleSeedProvider =
    StateProvider<int>((ref) => 0);

/// Drives shuffle order for [discoverQuickEasyRecipesProvider]. Rolled when
/// Discover opens or when the user switches to Dinner.
final discoverDinnerFeaturedShuffleSeedProvider =
    StateProvider<int>((ref) => 0);

final discoverChipIdProvider = StateProvider<String>((ref) => 'all');

final discoverSearchQueryProvider = StateProvider<String>((ref) => '');

final discoverSelectedCuisineIdsProvider =
    StateProvider<Set<String>>((ref) => <String>{});

final discoverSelectedDietaryTagsProvider =
    NotifierProvider<DiscoverSelectedDietaryTagsNotifier, Set<String>>(
  DiscoverSelectedDietaryTagsNotifier.new,
);

/// Public catalog filtered by active dietary tags.
///
/// Exclusion-based diets (vegetarian, vegan, pescatarian) use ingredient
/// categories so recipes like "Greek Scrambled Eggs" are correctly kept for
/// vegetarians even when the title/tags don't contain "vegetarian".
/// Label-based diets (gluten-free, keto, etc.) still use substring matching
/// on title + cuisine tags because those are opt-in labels.
final discoverDietaryFilteredPublicRecipesProvider =
    Provider<AsyncValue<List<Recipe>>>((ref) {
  final dietary = ref.watch(discoverSelectedDietaryTagsProvider);
  final recipesAsync = ref.watch(discoverAllPublicRecipesProvider);
  if (dietary.isEmpty) return recipesAsync;
  return recipesAsync.whenData(
    (recipes) => recipes
        .where((r) => _recipeMatchesDiscoverDietaryTags(r, dietary))
        .toList(),
  );
});

const _meatKeywords = <String>[
  'chicken', 'beef', 'pork', 'lamb', 'turkey', 'duck', 'veal', 'venison',
  'bison', 'bacon', 'sausage', 'ham', 'prosciutto', 'salami', 'pepperoni',
  'chorizo', 'steak', 'ground meat', 'meatball', 'ribs', 'roast',
  'braised', 'pulled pork', 'ground turkey', 'ground beef',
];

const _fishKeywords = <String>[
  'salmon', 'tuna', 'shrimp', 'prawn', 'cod', 'tilapia', 'halibut', 'trout',
  'bass', 'anchovy', 'sardine', 'crab', 'lobster', 'scallop', 'mussel',
  'clam', 'oyster', 'squid', 'calamari', 'octopus', 'fish', 'seafood',
  'mahi', 'swordfish', 'snapper',
];

const _dairyEggKeywords = <String>[
  'egg', 'cheese', 'butter', 'cream', 'milk', 'yogurt', 'whey',
  'ghee', 'sour cream', 'cream cheese', 'parmesan', 'mozzarella',
  'cheddar', 'feta', 'ricotta', 'brie', 'gouda',
];

/// Build a searchable string from the recipe title, tags, and ingredient names.
String _recipeHaystack(Recipe recipe) {
  final parts = StringBuffer()
    ..write(recipe.title.toLowerCase())
    ..write(' ')
    ..write(recipe.cuisineTags.join(' ').toLowerCase());
  for (final i in recipe.ingredients) {
    parts
      ..write(' ')
      ..write(i.name.toLowerCase());
  }
  return parts.toString();
}

bool _hasMeatOrFishCategory(Recipe recipe) =>
    recipe.ingredients.any((i) => i.category == GroceryCategory.meatFish);

bool _hasDairyEggCategory(Recipe recipe) =>
    recipe.ingredients.any((i) => i.category == GroceryCategory.dairyEggs);

bool _recipeMatchesDiscoverDietaryTags(Recipe recipe, Set<String> dietary) {
  if (dietary.isEmpty) return true;

  final haystack = _recipeHaystack(recipe);

  for (final tag in dietary) {
    switch (tag) {
      case 'vegetarian':
        if (_hasMeatOrFishCategory(recipe)) return false;
        if (_meatKeywords.any(haystack.contains)) return false;
        if (_fishKeywords.any(haystack.contains)) return false;
      case 'vegan':
        if (_hasMeatOrFishCategory(recipe)) return false;
        if (_hasDairyEggCategory(recipe)) return false;
        if (_meatKeywords.any(haystack.contains)) return false;
        if (_fishKeywords.any(haystack.contains)) return false;
        if (_dairyEggKeywords.any(haystack.contains)) return false;
      case 'pescatarian':
        if (_meatKeywords.any(haystack.contains)) return false;
        if (recipe.ingredients
            .where((i) => i.category == GroceryCategory.meatFish)
            .any((i) => _meatKeywords.any(i.name.toLowerCase().contains))) {
          return false;
        }
      default:
        if (!haystack.contains(tag)) return false;
    }
  }

  return true;
}

final discoverPrepTimeBucketProvider =
    StateProvider<DiscoverPrepTimeBucket>((ref) => DiscoverPrepTimeBucket.any);

final discoverRatingBucketProvider =
    StateProvider<DiscoverRatingBucket>((ref) => DiscoverRatingBucket.any);

final discoverSelectedMealTypesProvider =
    StateProvider<Set<DiscoverMealType>>(
      (ref) => <DiscoverMealType>{DiscoverMealType.entree},
    );

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

final discoverAllPublicRecipesProvider =
    FutureProvider<List<Recipe>>((ref) async {
  final repository = ref.watch(discoverRepositoryProvider);
  final rows = await repository._client
      .from('recipes')
      .select()
      .eq('visibility', RecipeVisibility.public.name)
      .order('created_at', ascending: false);
  return (rows as List)
      .whereType<Map<String, dynamic>>()
      .map(Recipe.fromJson)
      .toList();
});

final discoverFiltersProvider = Provider<DiscoverFilters>((ref) {
  return DiscoverFilters(
    query: ref.watch(discoverSearchQueryProvider),
    cuisineIds: ref.watch(discoverSelectedCuisineIdsProvider),
    dietaryIds: ref.watch(discoverSelectedDietaryTagsProvider),
    prepTime: ref.watch(discoverPrepTimeBucketProvider),
    rating: ref.watch(discoverRatingBucketProvider),
    mealTypes: ref.watch(discoverSelectedMealTypesProvider),
  );
});

final discoverActiveFilterCountProvider = Provider<int>((ref) {
  final dietary = ref.watch(discoverSelectedDietaryTagsProvider);
  return dietary.length;
});

final discoverCuisineTilesProvider =
    Provider<AsyncValue<List<DiscoverCuisineTile>>>(
  (ref) {
    final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
    final mealTab = ref.watch(discoverMealTypeProvider);
    final activeDiets = ref.watch(discoverSelectedDietaryTagsProvider);

    return recipesAsync.whenData((recipes) {
      final mealType = mealTab.recipeMealType;
      final mealRecipes = recipes
          .where((r) => r.mealType == mealType)
          .toList();

      final candidates = browseCategoriesForMeal(mealTab, activeDiets);

      final tiles = <DiscoverCuisineTile>[];
      for (final cat in candidates) {
        var count = 0;
        for (final recipe in mealRecipes) {
          final haystack =
              '${recipe.title} ${recipe.cuisineTags.join(' ')}'.toLowerCase();
          if (cat.keywords.any(haystack.contains)) count++;
        }
        tiles.add(DiscoverCuisineTile(
          id: cat.id,
          label: cat.label,
          recipeCount: count,
        ));
      }

      tiles.sort((a, b) => b.recipeCount.compareTo(a.recipeCount));
      return tiles;
    });
  },
);

final discoverTrendingRecipesProvider =
    Provider<AsyncValue<List<Recipe>>>((ref) {
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  return recipesAsync.whenData((recipes) => recipes.take(8).toList());
});

const _discoverQuickEasyApiIds = <String>{
  'pinch_of_yum:salmon-tacos',
  'pinch_of_yum:lo-mein',
  'pinch_of_yum:black-pepper-stir-fried-noodles',
  'pinch_of_yum:sheet-pan-chicken-pitas',
  'pinch_of_yum:greek-baked-orzo',
  'pinch_of_yum:creamy-garlic-sun-dried-tomato-pasta',
  'pinch_of_yum:coconut-curry-salmon',
  'pinch_of_yum:butter-chicken-meatballs',
  'pinch_of_yum:garlic-butter-baked-penne',
  'pinch_of_yum:vegan-sheet-pan-fajitas-with-chipotle-queso',
};

final discoverQuickEasyRecipesProvider = Provider<AsyncValue<List<Recipe>>>((ref) {
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  final shuffleSeed = ref.watch(discoverDinnerFeaturedShuffleSeedProvider);
  return recipesAsync.whenData((recipes) {
    final allowlisted = recipes
        .where((recipe) => _discoverQuickEasyApiIds.contains(recipe.apiId))
        .toList();
    // Curated Pinch of Yum ids; if none are present (slug drift, different DB),
    // fall back to all public dinner recipes so the strip isn't empty.
    final pool = allowlisted.isNotEmpty
        ? allowlisted
        : recipes.where((r) => r.mealType == MealType.sauce).toList();
    if (pool.isEmpty) return const <Recipe>[];
    final shuffled = [...pool]..shuffle(Random(shuffleSeed));
    return shuffled;
  });
});

final discoverLazyBreakfastRecipesProvider = Provider<AsyncValue<List<Recipe>>>((ref) {
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  final shuffleSeed = ref.watch(discoverBreakfastFeaturedShuffleSeedProvider);
  return recipesAsync.whenData((recipes) {
    final filtered = recipes.where((recipe) {
      final haystack =
          '${recipe.title} ${recipe.cuisineTags.join(' ')}'.toLowerCase();
      final isBreakfastMeal = recipe.mealType == MealType.entree;
      final isLazyBreakfast = haystack.contains('breakfast') ||
          haystack.contains('egg') ||
          haystack.contains('overnight oats') ||
          haystack.contains('pancake') ||
          haystack.contains('frittata') ||
          haystack.contains('casserole') ||
          haystack.contains('whole30');
      return isBreakfastMeal && isLazyBreakfast;
    }).toList();
    if (filtered.isEmpty) return const <Recipe>[];
    final shuffled = [...filtered]..shuffle(Random(shuffleSeed));
    return shuffled.take(12).toList();
  });
});

final discoverQuickLunchRecipesProvider = Provider<AsyncValue<List<Recipe>>>((ref) {
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  final shuffleSeed = ref.watch(discoverLunchFeaturedShuffleSeedProvider);
  return recipesAsync.whenData((recipes) {
    final filtered = recipes.where((recipe) {
      final haystack =
          '${recipe.title} ${recipe.cuisineTags.join(' ')}'.toLowerCase();
      final isLunchMeal = recipe.mealType == MealType.side;
      final isQuickLunch = haystack.contains('lunch') ||
          haystack.contains('salad') ||
          haystack.contains('sandwich') ||
          haystack.contains('wrap') ||
          haystack.contains('bento') ||
          haystack.contains('whole30');
      return isLunchMeal && isQuickLunch;
    }).toList();
    if (filtered.isEmpty) return const <Recipe>[];
    final shuffled = [...filtered]..shuffle(Random(shuffleSeed));
    return shuffled.take(12).toList();
  });
});

final discoverSnackIdeasRecipesProvider = Provider<AsyncValue<List<Recipe>>>((ref) {
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  return recipesAsync.whenData((recipes) {
    final snackRecipes = recipes
        .where((recipe) => recipe.mealType == MealType.snack)
        .toList();
    if (snackRecipes.isEmpty) return const <Recipe>[];

    // Keep "random" picks stable between rebuilds for a smoother UI.
    final shuffled = <Recipe>[...snackRecipes]..shuffle(Random(73));
    return shuffled.take(7).toList();
  });
});

final discoverDessertIdeasRecipesProvider = Provider<AsyncValue<List<Recipe>>>((ref) {
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  return recipesAsync.whenData((recipes) {
    final dessertRecipes = recipes
        .where((recipe) => recipe.mealType == MealType.dessert)
        .toList();
    if (dessertRecipes.isEmpty) return const <Recipe>[];

    final shuffled = <Recipe>[...dessertRecipes]..shuffle(Random(79));
    return shuffled.take(7).toList();
  });
});

final discoverFilteredRecipesProvider =
    Provider<AsyncValue<List<Recipe>>>((ref) {
  final selectedChip = ref.watch(discoverSelectedChipProvider);
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  final filters = ref.watch(discoverFiltersProvider);
  final repository = ref.watch(discoverRepositoryProvider);
  return recipesAsync.whenData((recipes) {
    var output = recipes;
    output = repository.filterRecipesByChip(output, selectedChip);
    output = _applyFilters(output, filters);
    return output;
  });
});

/// Public-catalog search: token AND across title, cuisine tags, and ingredient names.
final discoverPublicSearchResultsProvider =
    Provider<AsyncValue<List<Recipe>>>((ref) {
  final query = ref.watch(discoverSearchQueryProvider).trim();
  final recipesAsync = ref.watch(discoverDietaryFilteredPublicRecipesProvider);
  if (query.isEmpty) {
    return const AsyncValue.data(<Recipe>[]);
  }
  final tokens = _discoverSearchTokens(query);
  if (tokens.isEmpty) {
    return const AsyncValue.data(<Recipe>[]);
  }
  return recipesAsync.whenData((recipes) {
    return recipes
        .where((r) => _recipeMatchesDiscoverSearch(r, tokens))
        .toList();
  });
});

List<String> _discoverSearchTokens(String query) {
  return query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();
}

bool _recipeMatchesDiscoverSearch(Recipe recipe, List<String> tokens) {
  if (tokens.isEmpty) return true;
  final title = recipe.title.toLowerCase();
  final tagHaystack = recipe.cuisineTags.map((t) => t.toLowerCase()).join(' ');
  final ingredientHaystack =
      recipe.ingredients.map((i) => i.name.toLowerCase()).join(' ');
  final combined = '$title $tagHaystack $ingredientHaystack';
  for (final token in tokens) {
    if (!combined.contains(token)) return false;
  }
  return true;
}

List<Recipe> _applyFilters(List<Recipe> recipes, DiscoverFilters filters) {
  final query = filters.query.trim().toLowerCase();
  return recipes.where((recipe) {
    if (query.isNotEmpty) {
      final inTitle = recipe.title.toLowerCase().contains(query);
      final inTags = recipe.cuisineTags.any(
        (tag) => tag.toLowerCase().contains(query),
      );
      if (!inTitle && !inTags) return false;
    }

    if (filters.cuisineIds.isNotEmpty) {
      final recipeTags = recipe.cuisineTags.map((tag) => tag.toLowerCase());
      final hasCuisine = recipeTags.any(filters.cuisineIds.contains);
      if (!hasCuisine) return false;
    }

    if (filters.dietaryIds.isNotEmpty) {
      final haystack =
          '${recipe.title.toLowerCase()} ${recipe.cuisineTags.join(' ').toLowerCase()}';
      final hasAllDietary = filters.dietaryIds.every(haystack.contains);
      if (!hasAllDietary) return false;
    }

    if (!_matchesPrepTime(recipe, filters.prepTime)) return false;
    if (!_matchesRating(recipe, filters.rating)) return false;

    if (filters.mealTypes.isNotEmpty &&
        !filters.mealTypes
            .map((meal) => meal.recipeMealType)
            .contains(recipe.mealType)) {
      return false;
    }

    return true;
  }).toList();
}

bool _matchesPrepTime(Recipe recipe, DiscoverPrepTimeBucket bucket) {
  if (bucket == DiscoverPrepTimeBucket.any) return true;
  final totalTime = (recipe.prepTime ?? 0) + (recipe.cookTime ?? 0);
  if (totalTime <= 0) return false;
  switch (bucket) {
    case DiscoverPrepTimeBucket.any:
      return true;
    case DiscoverPrepTimeBucket.under15:
      return totalTime < 15;
    case DiscoverPrepTimeBucket.from15To30:
      return totalTime >= 15 && totalTime <= 30;
    case DiscoverPrepTimeBucket.over30:
      return totalTime > 30;
  }
}

bool _matchesRating(Recipe recipe, DiscoverRatingBucket rating) {
  if (rating == DiscoverRatingBucket.any) return true;
  final value = _derivedRating(recipe);
  switch (rating) {
    case DiscoverRatingBucket.any:
      return true;
    case DiscoverRatingBucket.threePlus:
      return value >= 3.0;
    case DiscoverRatingBucket.fourPlus:
      return value >= 4.0;
  }
}

double _derivedRating(Recipe recipe) {
  final base = recipe.nutrition.protein > 20 ? 4.2 : 3.6;
  final totalTime = (recipe.prepTime ?? 0) + (recipe.cookTime ?? 0);
  final timeBonus = totalTime > 0 && totalTime <= 30 ? 0.3 : 0.0;
  final varietyBonus = recipe.cuisineTags.length >= 2 ? 0.2 : 0.0;
  final jitter = (recipe.title.length % 5) * 0.1;
  final score = base + timeBonus + varietyBonus + jitter;
  return score.clamp(2.8, 4.9);
}

