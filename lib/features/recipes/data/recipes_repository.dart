import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/network/http_client.dart';
import 'package:plateplan/core/services/api_services.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecipesRepository {
  RecipesRepository(this._cache, this._spoonacular);

  final LocalCache _cache;
  final SpoonacularService _spoonacular;
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> _ensureProfileRow(String userId) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'name': 'Leckerly User',
    });
  }

  Future<String?> _householdForUser(String userId) async {
    final profile = await _client
        .from('profiles')
        .select('household_id')
        .eq('id', userId)
        .maybeSingle();
    return profile?['household_id']?.toString();
  }

  Future<List<Recipe>> listPersonalForUser(String userId) async {
    try {
      final rows = await _client
          .from('recipes')
          .select()
          .eq('user_id', userId)
          .eq('visibility', 'personal')
          .order('created_at', ascending: false);
      final recipes = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .toList();
      return _sortByCreatedFallback(recipes);
    } catch (_) {
      return [];
    }
  }

  Future<List<Recipe>> listHouseholdForUser(String userId) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return [];
    try {
      final rows = await _client
          .from('recipes')
          .select()
          .eq('household_id', householdId)
          .eq('visibility', 'household')
          .order('created_at', ascending: false);
      final recipes = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .toList();
      return _sortByCreatedFallback(recipes);
    } catch (_) {
      return [];
    }
  }

  Future<List<Recipe>> listForUser(String userId) async {
    try {
      final personal = await listPersonalForUser(userId);
      final household = await listHouseholdForUser(userId);
      final combined = <String, Recipe>{};
      for (final recipe in [...household, ...personal]) {
        combined[recipe.id] = recipe;
      }
      final all = combined.values.toList();
      await _cache.saveRecipes(all.map((r) => r.toJson()).toList());
      return all;
    } catch (_) {
      final cached = _cache.loadRecipes();
      return cached.map(Recipe.fromJson).toList();
    }
  }

  List<Recipe> _sortByCreatedFallback(List<Recipe> recipes) {
    return recipes;
  }

  Future<void> create(
    String userId,
    Recipe recipe, {
    bool shareWithHousehold = false,
    RecipeVisibility? visibilityOverride,
  }) async {
    final payload = recipe.toJson()
      ..remove('id')
      ..remove('user_id')
      ..remove('household_id')
      ..remove('visibility');
    await _ensureProfileRow(userId);
    final householdId = await _householdForUser(userId);
    final visibility = (visibilityOverride ??
            (shareWithHousehold
                ? RecipeVisibility.household
                : RecipeVisibility.personal))
        .name;
    await _client.from('recipes').insert({
      ...payload,
      'user_id': userId,
      'household_id':
          visibility == RecipeVisibility.household.name ? householdId : null,
      'visibility': visibility,
      'is_public': visibility == RecipeVisibility.public.name,
    });
  }

  Future<void> updateRecipe(String recipeId, Recipe recipe) async {
    final payload = recipe.toJson()
      ..remove('id')
      ..remove('user_id');
    payload['is_public'] = recipe.visibility == RecipeVisibility.public;
    await _client.from('recipes').update(payload).eq('id', recipeId);
  }

  Future<void> toggleFavorite(String recipeId, bool value) {
    return _client
        .from('recipes')
        .update({'is_favorite': value}).eq('id', recipeId);
  }

  Future<void> toggleToTry(String recipeId, bool value) {
    return _client
        .from('recipes')
        .update({'is_to_try': value}).eq('id', recipeId);
  }

  Future<void> copyPersonalRecipeToHousehold({
    required String userId,
    required String recipeId,
  }) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) {
      throw StateError('No active household found.');
    }

    final source = await _client
        .from('recipes')
        .select()
        .eq('id', recipeId)
        .eq('user_id', userId)
        .eq('visibility', RecipeVisibility.personal.name)
        .maybeSingle();

    if (source == null) {
      throw StateError('Could not find personal recipe to copy.');
    }

    final payload = Map<String, dynamic>.from(source)
      ..remove('id')
      ..remove('created_at')
      ..remove('user_id')
      ..remove('household_id')
      ..remove('visibility')
      // recipes.api_id is globally unique; household copies should not reuse it.
      ..remove('api_id');

    await _client.from('recipes').insert({
      ...payload,
      'user_id': userId,
      'household_id': householdId,
      'visibility': RecipeVisibility.household.name,
    });
  }

  Future<List<Recipe>> searchSpoonacular(String query) async {
    final items = await _spoonacular.searchRecipes(query);
    return items.map((raw) {
      final nutrients = (raw['nutrition']?['nutrients'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [];
      final caloriesEntry = nutrients
          .where((n) => n['name'] == 'Calories')
          .cast<Map<String, dynamic>>()
          .toList();
      final calories = caloriesEntry.isEmpty
          ? 0
          : ((caloriesEntry.first['amount'] as num?)?.round() ?? 0);

      return Recipe(
        id: 'spoon-${raw['id'] ?? Random().nextInt(999999)}',
        title: raw['title']?.toString() ?? 'Recipe',
        mealType: MealType.entree,
        cuisineTags: const ['Spoonacular'],
        source: 'spoonacular',
        imageUrl: raw['image']?.toString(),
        nutrition: Nutrition(calories: calories),
      );
    }).toList();
  }
}

final spoonacularServiceProvider = Provider<SpoonacularService>((ref) {
  return SpoonacularService(const HttpClient());
});

final recipesRepositoryProvider = Provider<RecipesRepository>((ref) {
  return RecipesRepository(
      ref.watch(localCacheProvider), ref.watch(spoonacularServiceProvider));
});

final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(recipesRepositoryProvider).listForUser(user.id);
});
