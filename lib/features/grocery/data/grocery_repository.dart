import 'package:collection/collection.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroceryRepository {
  GroceryRepository(this._cache);

  final SupabaseClient _client = Supabase.instance.client;
  final LocalCache _cache;
  List<String> _usdaCatalog = const [];
  Map<String, List<String>> _usdaPrefixIndex = const {};
  bool _catalogLoadAttempted = false;
  static const int _maxAutocompleteCatalogItems = 7500;

  Future<void> _ensureProfileRow(String userId) async {
    await _client.from('profiles').upsert({
      'id': userId,
      'name': 'KitchenOps User',
    });
  }

  Future<String?> _householdForUser(String userId) async {
    await _ensureProfileRow(userId);
    final profile = await _client
        .from('profiles')
        .select('household_id')
        .eq('id', userId)
        .maybeSingle();
    final profileHouseholdId = profile?['household_id']?.toString();
    if (profileHouseholdId != null && profileHouseholdId.isNotEmpty) {
      return profileHouseholdId;
    }

    // Recovery path for users whose profile row does not currently point to the
    // active household but who are still an active household member.
    final membership = await _client
        .from('household_members')
        .select('household_id')
        .eq('user_id', userId)
        .eq('status', HouseholdMemberStatus.active.name)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final membershipHouseholdId = membership?['household_id']?.toString();
    if (membershipHouseholdId == null || membershipHouseholdId.isEmpty) {
      final pendingInvite = await _client
          .from('household_members')
          .select('household_id')
          .eq('user_id', userId)
          .eq('status', HouseholdMemberStatus.invited.name)
          .limit(1)
          .maybeSingle();
      if (pendingInvite != null) {
        return null;
      }
      try {
        final created = await _client.rpc(
          'create_household_with_member',
          params: {'name': 'My Household'},
        );
        final createdHouseholdId = created?.toString();
        if (createdHouseholdId != null && createdHouseholdId.isNotEmpty) {
          return createdHouseholdId;
        }
      } catch (_) {
        // Fall through and return null so callers can handle gracefully.
      }
      return null;
    }

    // Best effort sync so future reads/writes use the profile shortcut.
    try {
      await _client
          .from('profiles')
          .update({'household_id': membershipHouseholdId})
          .eq('id', userId)
          .isFilter('household_id', null);
    } catch (_) {
      // Ignore profile sync failures; we can still proceed with the recovered id.
    }
    return membershipHouseholdId;
  }

  static const Map<String, GroceryCategory> _categoryMap = {
    'tomato': GroceryCategory.produce,
    'onion': GroceryCategory.produce,
    'spinach': GroceryCategory.produce,
    'chicken': GroceryCategory.meatFish,
    'salmon': GroceryCategory.meatFish,
    'egg': GroceryCategory.dairyEggs,
    'milk': GroceryCategory.dairyEggs,
    'rice': GroceryCategory.pantryGrains,
    'pasta': GroceryCategory.pantryGrains,
    'bread': GroceryCategory.bakery,
  };

  static const List<String> _localCatalog = [
    'Milk',
    'Bananas',
    'Strawberries',
    'Bread',
    'Eggs',
    'Chicken Breast',
    'Salmon',
    'Rice',
    'Pasta',
    'Tomatoes',
    'Onions',
    'Potatoes',
    'Carrots',
    'Spinach',
    'Apples',
    'Yogurt',
    'Cheese',
    'Butter',
    'Olive Oil',
    'Garlic',
    'Bell Peppers',
    'Lettuce',
    'Cucumber',
    'Avocado',
    'Ground Beef',
    'Turkey',
    'Tuna',
    'Oats',
    'Flour',
    'Sugar',
    'Salt',
    'Black Pepper',
    'Coffee',
    'Tea',
    'Orange Juice',
    'Jam',
    'Peanut Butter',
  ];

  GroceryCategory categorize(String ingredient) {
    final lower = ingredient.toLowerCase();
    for (final entry in _categoryMap.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return GroceryCategory.other;
  }

  Future<void> ensureCatalogLoaded() async {
    if (_catalogLoadAttempted) return;
    _catalogLoadAttempted = true;
    try {
      final raw =
          await rootBundle.loadString('assets/data/usda_food_catalog.txt');
      final loaded = _firstNonEmptyLines(raw, _maxAutocompleteCatalogItems);
      final index = <String, List<String>>{};
      for (final item in loaded) {
        final normalized = _normalizedForSearch(item);
        if (normalized.isEmpty) continue;
        final key1 = normalized.substring(0, 1);
        final key2 =
            normalized.length > 1 ? normalized.substring(0, 2) : '${key1}_';
        (index[key1] ??= <String>[]).add(item);
        (index[key2] ??= <String>[]).add(item);
      }
      _usdaCatalog = loaded;
      _usdaPrefixIndex = index;
    } catch (_) {
      _usdaCatalog = const [];
      _usdaPrefixIndex = const {};
    }
  }

  List<String> suggestItems({
    required String query,
    required List<GroceryItem> recentItems,
    int limit = 24,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final recentNames = recentItems
        .map((e) => e.name.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final normalizedSearch = _normalizedForSearch(normalizedQuery);
    final candidates = _candidatesByQuery(normalizedSearch);
    final merged = <String>{
      ..._localCatalog,
      ...recentNames,
      ...candidates,
    }.where((item) => !_isNoisyCatalogItem(item)).toList();

    if (normalizedQuery.isEmpty) {
      final recentFirst = [
        ...recentNames,
        ..._localCatalog.where((name) => !recentNames.contains(name)),
      ];
      return recentFirst.take(limit).toList();
    }

    final matched = merged
        .where((item) => item.toLowerCase().contains(normalizedQuery))
        .toList();
    matched.sort((a, b) {
      final scoreA = _matchScore(
        item: a,
        query: normalizedQuery,
        recentNames: recentNames,
      );
      final scoreB = _matchScore(
        item: b,
        query: normalizedQuery,
        recentNames: recentNames,
      );
      if (scoreA != scoreB) return scoreA.compareTo(scoreB);
      if (a.length != b.length) return a.length.compareTo(b.length);
      return a.compareTo(b);
    });
    return matched.take(limit).toList();
  }

  List<String> _candidatesByQuery(String normalizedQuery) {
    if (_usdaCatalog.isEmpty) return _localCatalog;
    if (normalizedQuery.isEmpty) {
      return _usdaCatalog.take(300).toList();
    }
    if (normalizedQuery.length == 1) {
      return _usdaPrefixIndex[normalizedQuery.substring(0, 1)] ?? _usdaCatalog;
    }
    final prefixKey = normalizedQuery.substring(0, 2);
    return _usdaPrefixIndex[prefixKey] ?? _usdaCatalog;
  }

  String _normalizedForSearch(String value) {
    final lower = value.toLowerCase();
    final buffer = StringBuffer();
    for (final code in lower.codeUnits) {
      final isNumber = code >= 48 && code <= 57;
      final isLetter = code >= 97 && code <= 122;
      if (isNumber || isLetter) {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  List<String> _firstNonEmptyLines(String raw, int maxItems) {
    final items = <String>[];
    var start = 0;
    while (start < raw.length && items.length < maxItems) {
      final end = raw.indexOf('\n', start);
      final line =
          (end == -1 ? raw.substring(start) : raw.substring(start, end)).trim();
      if (line.isNotEmpty) {
        items.add(line);
      }
      if (end == -1) break;
      start = end + 1;
    }
    return items;
  }

  bool _isNoisyCatalogItem(String item) {
    final trimmed = item.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'^\d').hasMatch(trimmed)) return true;
    if (trimmed.contains('#')) return true;
    if (RegExp(r'\b(oz|lb|pk|ct|count|pack|pkg)\b', caseSensitive: false)
        .hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  int _matchScore({
    required String item,
    required String query,
    required Set<String> recentNames,
  }) {
    final lower = item.toLowerCase();
    var score = 100;
    if (lower == query) score -= 90;
    if (lower.startsWith(query)) score -= 60;
    if (RegExp(r'\b' + RegExp.escape(query)).hasMatch(lower)) score -= 40;
    if (recentNames.contains(item)) score -= 20;
    if (RegExp(r'[^a-z0-9\s]').hasMatch(lower)) score += 8;
    return score;
  }

  Future<List<GroceryItem>> listItems(String userId) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return [];
    try {
      final rows = await _client
          .from('grocery_items')
          .select()
          .eq('household_id', householdId)
          .order('created_at');
      final items = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map(GroceryItem.fromJson)
          .toList();
      await _cache.saveGrocery(items.map((e) => e.toJson()).toList());
      return items;
    } catch (_) {
      return _cache.loadGrocery().map(GroceryItem.fromJson).toList();
    }
  }

  Stream<List<GroceryItem>> streamItems(String userId) async* {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) {
      yield const [];
      return;
    }

    final initial = await listItems(userId);
    yield initial;

    yield* _client
        .from('grocery_items')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .order('created_at')
        .map((rows) {
          final items = rows
              .whereType<Map<String, dynamic>>()
              .map(GroceryItem.fromJson)
              .toList();
          unawaited(_cache.saveGrocery(items.map((e) => e.toJson()).toList()));
          return items;
        });
  }

  Future<void> addItem({
    required String userId,
    required String name,
    String? quantity,
    String? unit,
    GroceryCategory? category,
    String? fromRecipeId,
  }) {
    return _insertItem(
      userId: userId,
      name: name,
      quantity: quantity,
      unit: unit,
      category: category ?? categorize(name),
      fromRecipeId: fromRecipeId,
    );
  }

  Future<void> removeItem(String itemId) {
    return _client.from('grocery_items').delete().eq('id', itemId);
  }

  Future<void> updateItemQuantity(String itemId, String quantity) {
    return _client
        .from('grocery_items')
        .update({'quantity': quantity}).eq('id', itemId);
  }

  Future<void> removeItemsByRecipe(String recipeId) {
    return _client
        .from('grocery_items')
        .delete()
        .eq('from_recipe_id', recipeId);
  }

  Future<void> clear(String userId) {
    return _clearHouseholdItems(userId);
  }

  Future<void> shareText(List<GroceryItem> items) {
    final text = items
        .map((e) => '- ${e.name} ${e.quantity ?? ''}${e.unit ?? ''}'.trim())
        .join('\n');
    return Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> addIngredientsFromRecipe(Recipe recipe,
      {required String userId, required int servingsUsed}) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return;
    final ratio = servingsUsed / recipe.servings;
    final existing = await listItems(userId);

    for (final ingredient in recipe.ingredients) {
      final current = existing.firstWhereOrNull(
          (e) => e.name.toLowerCase() == ingredient.name.toLowerCase());
      if (current != null) continue;

      await _client.from('grocery_items').insert({
        'user_id': userId,
        'household_id': householdId,
        'name': ingredient.name,
        'category': ingredient.category.dbValue,
        'quantity': (ingredient.amount * ratio).toStringAsFixed(1),
        'unit': ingredient.unit,
        'from_recipe_id': recipe.id,
      });
    }
  }

  Future<void> _insertItem({
    required String userId,
    required String name,
    String? quantity,
    String? unit,
    required GroceryCategory category,
    String? fromRecipeId,
  }) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) {
      throw StateError('Could not initialize your personal grocery list.');
    }
    await _client.from('grocery_items').insert({
      'user_id': userId,
      'household_id': householdId,
      'name': name,
      'category': category.dbValue,
      'quantity': quantity,
      'unit': unit,
      'from_recipe_id': fromRecipeId,
    });
  }

  Future<void> _clearHouseholdItems(String userId) async {
    final householdId = await _householdForUser(userId);
    if (householdId == null || householdId.isEmpty) return;
    await _client.from('grocery_items').delete().eq('household_id', householdId);
  }
}

final groceryRepositoryProvider = Provider<GroceryRepository>((ref) {
  return GroceryRepository(ref.watch(localCacheProvider));
});

final groceryItemsProvider = StreamProvider<List<GroceryItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream<List<GroceryItem>>.value(const []);
  return ref.watch(groceryRepositoryProvider).streamItems(user.id);
});
