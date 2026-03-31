import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/network/http_client.dart';
import 'package:plateplan/core/services/api_services.dart';
import 'package:plateplan/core/services/food_data_central_service.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/recipes/data/ingredient_nutrition_cache_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecipesRepository {
  RecipesRepository(this._cache, this._spoonacular);

  final LocalCache _cache;
  final SpoonacularService _spoonacular;
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> _ensureProfileRow(String userId) async {
    try {
      await _client.from('profiles').insert({'id': userId});
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
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
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .toList();
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
      return (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(Recipe.fromJson)
          .toList();
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

  /// Live updates via Realtime; refetches merged personal + household list on
  /// each change. No column filter on the subscription (same pattern as
  /// [GroceryRepository.streamItemsForList]); RLS scopes which events apply.
  Stream<List<Recipe>> streamRecipesForUser(String userId) {
    return Stream<List<Recipe>>.multi((multi) {
      RealtimeChannel? channel;
      Timer? debounce;
      final topic =
          'public:recipes:nofilter=$userId:${DateTime.now().microsecondsSinceEpoch}';

      Future<void> pushFresh() async {
        if (multi.isClosed) return;
        final items = await listForUser(userId);
        if (!multi.isClosed) {
          multi.add(items);
        }
      }

      void scheduleRefetch() {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 350), () {
          unawaited(pushFresh());
        });
      }

      var sawSubscribedOnce = false;

      Future<void> setup() async {
        await pushFresh();
        if (multi.isClosed) return;
        channel = _client.channel(topic);
        void onChange(PostgresChangePayload _) {
          scheduleRefetch();
        }

        channel!
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'recipes',
              callback: onChange,
            )
            .subscribe((RealtimeSubscribeStatus status, Object? error) {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              if (sawSubscribedOnce) {
                unawaited(pushFresh());
              }
              sawSubscribedOnce = true;
              break;
            case RealtimeSubscribeStatus.timedOut:
            case RealtimeSubscribeStatus.channelError:
              unawaited(pushFresh());
              break;
            case RealtimeSubscribeStatus.closed:
              break;
          }
        });
      }

      unawaited(setup());

      multi.onCancel = () {
        debounce?.cancel();
        unawaited(channel?.unsubscribe());
      };
    });
  }

  /// Inserts a recipe row and returns the new row id.
  Future<String> create(
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
    final inserted = await _client
        .from('recipes')
        .insert({
          ...payload,
          'user_id': userId,
          'household_id':
              visibility == RecipeVisibility.household.name ? householdId : null,
          'visibility': visibility,
          'is_public': visibility == RecipeVisibility.public.name,
        })
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  Future<void> updateRecipe(String recipeId, Recipe recipe) async {
    final payload = recipe.toJson()..remove('id')..remove('user_id');
    payload['is_public'] = recipe.visibility == RecipeVisibility.public;
    // Omit null fields so we do not overwrite DB-only columns (api_id, household_id,
    // image_url, …) with NULL — that caused unique constraint errors on save.
    payload.removeWhere((_, value) => value == null);
    final updated = await _client
        .from('recipes')
        .update(payload)
        .eq('id', recipeId)
        .select('id')
        .maybeSingle();
    if (updated == null) {
      throw StateError('Recipe update was not permitted.');
    }
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

  Future<void> deleteRecipe(String recipeId) {
    return _client.from('recipes').delete().eq('id', recipeId);
  }

  Future<void> copyPersonalRecipeToHousehold({
    required String userId,
    required String recipeId,
    bool? householdFavorite,
    bool? householdToTry,
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

    final existingCopy = await _client
        .from('recipes')
        .select('id')
        .eq('user_id', userId)
        .eq('household_id', householdId)
        .eq('visibility', RecipeVisibility.household.name)
        .eq('copied_from_personal_recipe_id', recipeId)
        .maybeSingle();
    if (existingCopy != null) {
      return;
    }

    final payload = Map<String, dynamic>.from(source)
      ..remove('id')
      ..remove('created_at')
      ..remove('user_id')
      ..remove('household_id')
      ..remove('visibility')
      // recipes.api_id is globally unique; household copies should not reuse it.
      ..remove('api_id')
      ..remove('copied_from_personal_recipe_id');

    final sourceFavorite = source['is_favorite'] == true;
    final sourceToTry = source['is_to_try'] == true;

    await _client.from('recipes').insert({
      ...payload,
      'user_id': userId,
      'household_id': householdId,
      'visibility': RecipeVisibility.household.name,
      'copied_from_personal_recipe_id': recipeId,
      'is_favorite': householdFavorite ?? sourceFavorite,
      'is_to_try': householdToTry ?? sourceToTry,
    });
  }

  /// Linked household copy row for this personal recipe, if any.
  Future<String?> householdCopyIdForPersonalRecipe({
    required String userId,
    required String personalRecipeId,
  }) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return null;
    final row = await _client
        .from('recipes')
        .select('id')
        .eq('user_id', userId)
        .eq('household_id', householdId)
        .eq('visibility', RecipeVisibility.household.name)
        .eq('copied_from_personal_recipe_id', personalRecipeId)
        .maybeSingle();
    return row?['id']?.toString();
  }

  /// Deletes the most recent household recipe row you created whose title matches
  /// this personal recipe (same pairing as [copyPersonalRecipeToHousehold]).
  /// Returns true if a row was deleted. No DB link between copies — matching is by title.
  Future<bool> deleteHouseholdCopyMatchingPersonal({
    required String userId,
    required String personalRecipeId,
  }) async {
    final personalRow = await _client
        .from('recipes')
        .select()
        .eq('id', personalRecipeId)
        .eq('user_id', userId)
        .eq('visibility', RecipeVisibility.personal.name)
        .maybeSingle();
    if (personalRow == null) return false;
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return false;

    final byLink = await _client
        .from('recipes')
        .select('id')
        .eq('user_id', userId)
        .eq('household_id', householdId)
        .eq('visibility', RecipeVisibility.household.name)
        .eq('copied_from_personal_recipe_id', personalRecipeId)
        .maybeSingle();
    if (byLink != null) {
      await _client.from('recipes').delete().eq('id', byLink['id']);
      return true;
    }

    final title = personalRow['title']?.toString().trim() ?? '';
    if (title.isEmpty) return false;

    final match = await _client
        .from('recipes')
        .select('id')
        .eq('user_id', userId)
        .eq('household_id', householdId)
        .eq('visibility', RecipeVisibility.household.name)
        .eq('title', title)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (match == null) return false;
    final copyId = match['id'].toString();
    await _client.from('recipes').delete().eq('id', copyId);
    return true;
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

  Future<String> createRecipeShare({
    required String userId,
    required Recipe recipe,
  }) async {
    final payload = Map<String, dynamic>.from(recipe.toJson())
      ..remove('id')
      ..remove('user_id')
      ..remove('household_id')
      ..remove('visibility');
    final inserted = await _client
        .from('recipe_shares')
        .insert({
          'created_by': userId,
          'source_recipe_id': recipe.id,
          'payload': payload,
        })
        .select('id')
        .single();
    return inserted['id'].toString();
  }

  String recipeShareUrl(String shareId) => 'https://leckerly.app/r/$shareId';

  Future<Recipe?> fetchSharedRecipePayload({
    required String shareId,
  }) async {
    final row = await _client
        .from('recipe_shares')
        .select('payload')
        .eq('id', shareId)
        .maybeSingle();
    final payload = row?['payload'];
    if (payload is! Map) return null;
    final map = Map<String, dynamic>.from(payload);
    // Provide a placeholder id; recipients will create a new row on save.
    map['id'] = 'share:$shareId';
    map['visibility'] = RecipeVisibility.personal.name;
    return Recipe.fromJson(map);
  }
}

final spoonacularServiceProvider = Provider<SpoonacularService>((ref) {
  return SpoonacularService(const HttpClient());
});

final foodDataCentralServiceProvider = Provider<FoodDataCentralService>((ref) {
  return FoodDataCentralService(const HttpClient());
});

final ingredientNutritionCacheRepositoryProvider =
    Provider<IngredientNutritionCacheRepository>((ref) {
  return IngredientNutritionCacheRepository();
});

final recipesRepositoryProvider = Provider<RecipesRepository>((ref) {
  return RecipesRepository(
      ref.watch(localCacheProvider), ref.watch(spoonacularServiceProvider));
});

final recipesProvider = StreamProvider<List<Recipe>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.read(recipesRepositoryProvider).streamRecipesForUser(user.id);
});
