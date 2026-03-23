import 'package:collection/collection.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/strings/ingredient_amount_display.dart';
import 'package:plateplan/core/storage/local_cache.dart';
import 'package:plateplan/features/auth/data/auth_providers.dart';
import 'package:plateplan/features/household/data/household_providers.dart';
import 'package:plateplan/features/profile/data/profile_providers.dart';
import 'package:plateplan/features/profile/data/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Applies saved [order] for [scope]; unknown ids sort by [AppList.createdAt].
List<AppList> applyGroceryListOrder(
  List<AppList> lists,
  ListScope scope,
  GroceryListOrder order,
) {
  final filtered = lists.where((l) => l.scope == scope).toList();
  if (filtered.isEmpty) return filtered;
  final preferred = order.idsFor(scope);
  final index = {for (var i = 0; i < preferred.length; i++) preferred[i]: i};
  int rank(AppList l) => index[l.id] ?? (1 << 30);
  filtered.sort((a, b) {
    final ra = rank(a);
    final rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return da.compareTo(db);
  });
  return filtered;
}

/// Resolves which grocery list to show when [selectedListId] is null or stale.
/// Matches the default used on the Lists screen (Shared tab first when
/// [hasSharedHousehold] is true, else private lists).
String? effectiveGroceryListId({
  required List<AppList> lists,
  required String? selectedListId,
  required bool hasSharedHousehold,
  required GroceryListOrder profileOrder,
}) {
  if (lists.isEmpty) return null;
  if (selectedListId != null &&
      selectedListId.isNotEmpty &&
      lists.any((l) => l.id == selectedListId)) {
    return selectedListId;
  }
  final scopeFilter = !hasSharedHousehold
      ? ListScope.private
      : ListScope.household;
  final ordered = applyGroceryListOrder(lists, scopeFilter, profileOrder);
  return ordered.firstOrNull?.id;
}

class GroceryRepository {
  GroceryRepository(this._cache, this._profileRepo);

  final SupabaseClient _client = Supabase.instance.client;
  final LocalCache _cache;
  final ProfileRepository _profileRepo;

  static const int _maxGroceryRecentsStored = 32;
  List<String> _usdaCatalog = const [];
  Map<String, List<String>> _usdaPrefixIndex = const {};
  bool _catalogLoadAttempted = false;
  static const int _maxAutocompleteCatalogItems = 7500;

  Future<void> _ensureProfileRow(String userId) async {
    try {
      await _client.from('profiles').insert({'id': userId});
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
    }
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

  /// Keyword hints for categorization (longer/specific keys should appear before
  /// broader substrings where order matters).
  static const Map<String, GroceryCategory> _categoryMap = {
    'blueberr': GroceryCategory.produce,
    'blackberr': GroceryCategory.produce,
    'raspberr': GroceryCategory.produce,
    'strawberr': GroceryCategory.produce,
    'lettuce': GroceryCategory.produce,
    'cucumber': GroceryCategory.produce,
    'avocado': GroceryCategory.produce,
    'broccoli': GroceryCategory.produce,
    'cauliflower': GroceryCategory.produce,
    'celery': GroceryCategory.produce,
    'mushroom': GroceryCategory.produce,
    'zucchini': GroceryCategory.produce,
    'squash': GroceryCategory.produce,
    'asparagus': GroceryCategory.produce,
    'kale': GroceryCategory.produce,
    'cilantro': GroceryCategory.produce,
    'parsley': GroceryCategory.produce,
    'basil': GroceryCategory.produce,
    'lime': GroceryCategory.produce,
    'lemon': GroceryCategory.produce,
    'grape': GroceryCategory.produce,
    'watermelon': GroceryCategory.produce,
    'pineapple': GroceryCategory.produce,
    'mango': GroceryCategory.produce,
    'peach': GroceryCategory.produce,
    'pear': GroceryCategory.produce,
    'cherry': GroceryCategory.produce,
    'green bean': GroceryCategory.produce,
    'corn': GroceryCategory.produce,
    'tomato': GroceryCategory.produce,
    'onion': GroceryCategory.produce,
    'spinach': GroceryCategory.produce,
    'potato': GroceryCategory.produce,
    'carrot': GroceryCategory.produce,
    'garlic': GroceryCategory.produce,
    'apple': GroceryCategory.produce,
    'banana': GroceryCategory.produce,
    'bell pepper': GroceryCategory.produce,
    'jalapeno': GroceryCategory.produce,
    'chicken': GroceryCategory.meatFish,
    'salmon': GroceryCategory.meatFish,
    'shrimp': GroceryCategory.meatFish,
    'bacon': GroceryCategory.meatFish,
    'sausage': GroceryCategory.meatFish,
    'pork': GroceryCategory.meatFish,
    'steak': GroceryCategory.meatFish,
    'ground beef': GroceryCategory.meatFish,
    'turkey': GroceryCategory.meatFish,
    'tuna': GroceryCategory.meatFish,
    'fish': GroceryCategory.meatFish,
    'egg': GroceryCategory.dairyEggs,
    'milk': GroceryCategory.dairyEggs,
    'cream cheese': GroceryCategory.dairyEggs,
    'sour cream': GroceryCategory.dairyEggs,
    'yogurt': GroceryCategory.dairyEggs,
    'butter': GroceryCategory.dairyEggs,
    'cheddar': GroceryCategory.dairyEggs,
    'mozzarella': GroceryCategory.dairyEggs,
    'parmesan': GroceryCategory.dairyEggs,
    'feta': GroceryCategory.dairyEggs,
    'cheese': GroceryCategory.dairyEggs,
    'granola': GroceryCategory.pantryGrains,
    'cereal': GroceryCategory.pantryGrains,
    'oat': GroceryCategory.pantryGrains,
    'quinoa': GroceryCategory.pantryGrains,
    'bean': GroceryCategory.pantryGrains,
    'lentil': GroceryCategory.pantryGrains,
    'rice': GroceryCategory.pantryGrains,
    'pasta': GroceryCategory.pantryGrains,
    'flour': GroceryCategory.pantryGrains,
    'sugar': GroceryCategory.pantryGrains,
    'honey': GroceryCategory.pantryGrains,
    'maple syrup': GroceryCategory.pantryGrains,
    'oil': GroceryCategory.pantryGrains,
    'vinegar': GroceryCategory.pantryGrains,
    'salsa': GroceryCategory.pantryGrains,
    'tortilla': GroceryCategory.pantryGrains,
    'mayo': GroceryCategory.pantryGrains,
    'mustard': GroceryCategory.pantryGrains,
    'ketchup': GroceryCategory.pantryGrains,
    'soy sauce': GroceryCategory.pantryGrains,
    'bread': GroceryCategory.bakery,
    'bagel': GroceryCategory.bakery,
    'croissant': GroceryCategory.bakery,
    'muffin': GroceryCategory.bakery,
  };

  /// Common grocery staples shown first in search; USDA catalog fills only when needed.
  static const List<String> _localCatalog = [
    // Produce
    'Apples',
    'Bananas',
    'Blueberries',
    'Blackberries',
    'Raspberries',
    'Strawberries',
    'Grapes',
    'Pears',
    'Peaches',
    'Cherries',
    'Oranges',
    'Lemons',
    'Limes',
    'Avocado',
    'Pineapple',
    'Mango',
    'Watermelon',
    'Cantaloupe',
    'Kiwi',
    'Tomatoes',
    'Cherry Tomatoes',
    'Onions',
    'Red Onions',
    'Green Onions',
    'Garlic',
    'Potatoes',
    'Sweet Potatoes',
    'Carrots',
    'Broccoli',
    'Cauliflower',
    'Spinach',
    'Lettuce',
    'Romaine',
    'Kale',
    'Arugula',
    'Cucumber',
    'Bell Peppers',
    'Jalapenos',
    'Zucchini',
    'Mushrooms',
    'Asparagus',
    'Celery',
    'Cabbage',
    'Green Beans',
    'Corn',
    'Peas',
    'Brussels Sprouts',
    'Cilantro',
    'Parsley',
    'Basil',
    'Ginger',

    // Meat, fish, eggs
    'Chicken Breast',
    'Chicken Thighs',
    'Chicken Drumsticks',
    'Chicken Wings',
    'Ground Chicken',
    'Ground Turkey',
    'Turkey',
    'Ground Beef',
    'Beef Stew Meat',
    'Steak',
    'Pork Chops',
    'Ground Pork',
    'Sausage',
    'Bacon',
    'Ham',
    'Salmon',
    'Tuna',
    'Tilapia',
    'Cod',
    'Shrimp',
    'Scallops',
    'Crab',
    'Eggs',

    // Dairy and refrigerated
    'Milk',
    'Half and Half',
    'Heavy Cream',
    'Butter',
    'Cheese',
    'Cheddar Cheese',
    'Mozzarella',
    'Parmesan',
    'Feta',
    'Cream Cheese',
    'Sour Cream',
    'Cottage Cheese',
    'Yogurt',
    'Greek Yogurt',
    'Almond Milk',
    'Oat Milk',

    // Bakery
    'Bread',
    'Whole Wheat Bread',
    'Sourdough Bread',
    'Bagels',
    'Hamburger Buns',
    'Hot Dog Buns',
    'English Muffins',
    'Tortillas',
    'Pita Bread',
    'Croissants',

    // Pantry staples
    'Rice',
    'Brown Rice',
    'Jasmine Rice',
    'Basmati Rice',
    'Quinoa',
    'Pasta',
    'Spaghetti',
    'Macaroni',
    'Penne',
    'Oats',
    'Rolled Oats',
    'Granola',
    'Cereal',
    'Flour',
    'Sugar',
    'Brown Sugar',
    'Powdered Sugar',
    'Salt',
    'Black Pepper',
    'Paprika',
    'Chili Powder',
    'Cumin',
    'Garlic Powder',
    'Onion Powder',
    'Cinnamon',
    'Vanilla Extract',
    'Baking Soda',
    'Baking Powder',
    'Yeast',
    'Cornstarch',
    'Olive Oil',
    'Vegetable Oil',
    'Sesame Oil',
    'Vinegar',
    'Apple Cider Vinegar',
    'Soy Sauce',
    'Hot Sauce',
    'Mustard',
    'Mayonnaise',
    'Ketchup',
    'BBQ Sauce',
    'Salsa',
    'Pasta Sauce',
    'Tomato Sauce',
    'Tomato Paste',
    'Broth',
    'Chicken Broth',
    'Beef Broth',
    'Peanut Butter',
    'Jam',
    'Honey',
    'Maple Syrup',

    // Canned and dry goods
    'Black Beans',
    'Pinto Beans',
    'Chickpeas',
    'Lentils',
    'Kidney Beans',
    'Canned Corn',
    'Canned Tomatoes',
    'Diced Tomatoes',
    'Coconut Milk',
    'Tuna Cans',
    'Crackers',
    'Breadcrumbs',

    // Frozen
    'Frozen Berries',
    'Frozen Broccoli',
    'Frozen Peas',
    'Frozen Corn',
    'Frozen Pizza',
    'Ice Cream',

    // Snacks
    'Chips',
    'Tortilla Chips',
    'Pretzels',
    'Popcorn',
    'Nuts',
    'Almonds',
    'Walnuts',
    'Trail Mix',
    'Protein Bars',
    'Chocolate',
    'Cookies',

    // Drinks
    'Coffee',
    'Tea',
    'Orange Juice',
    'Apple Juice',
    'Sparkling Water',
    'Soda',
  ];

  static final Set<String> _stapleCatalogLower =
      _localCatalog.map((e) => e.toLowerCase()).toSet();

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

    if (normalizedQuery.isEmpty) {
      final recentFirst = [
        ...recentNames,
        ..._localCatalog.where((name) => !recentNames.contains(name)),
      ];
      return recentFirst.take(limit).toList();
    }

    bool matchesQuery(String item) =>
        item.toLowerCase().contains(normalizedQuery);

    // Phase 1: curated staples + names already on this list (never USDA noise).
    final primaryMatches = <String>[
      ...recentNames.where(matchesQuery),
      ..._localCatalog.where(
        (n) => matchesQuery(n) && !recentNames.contains(n),
      ),
    ];
    primaryMatches.sort(
      (a, b) => _compareSuggestionRank(
        a,
        b,
        query: normalizedQuery,
        recentNames: recentNames,
        isUsdaFallback: false,
      ),
    );

    final out = <String>[...primaryMatches];
    final seen = out.toSet();

    // Phase 2: USDA catalog only to fill remaining slots; deprioritized vs staples.
    if (out.length < limit && _usdaCatalog.isNotEmpty) {
      final normalizedSearch = _normalizedForSearch(normalizedQuery);
      final usdaPool = _candidatesByQuery(normalizedSearch)
          .where((item) => !seen.contains(item))
          .where(matchesQuery)
          .where((item) => !_isNoisyCatalogItem(item))
          .where((item) => !_isHeavyBrandedUsdaLine(item))
          .toList();
      usdaPool.sort(
        (a, b) => _compareSuggestionRank(
          a,
          b,
          query: normalizedQuery,
          recentNames: recentNames,
          isUsdaFallback: true,
        ),
      );
      for (final item in usdaPool) {
        if (out.length >= limit) break;
        out.add(item);
        seen.add(item);
      }
    }

    return out.take(limit).toList();
  }

  int _compareSuggestionRank(
    String a,
    String b, {
    required String query,
    required Set<String> recentNames,
    required bool isUsdaFallback,
  }) {
    final scoreA = _matchScore(
      item: a,
      query: query,
      recentNames: recentNames,
      isUsdaFallback: isUsdaFallback,
    );
    final scoreB = _matchScore(
      item: b,
      query: query,
      recentNames: recentNames,
      isUsdaFallback: isUsdaFallback,
    );
    if (scoreA != scoreB) return scoreA.compareTo(scoreB);
    if (a.length != b.length) return a.length.compareTo(b.length);
    return a.compareTo(b);
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

  /// Filters branded / industrial USDA descriptions so autocomplete stays grocery-like.
  bool _isHeavyBrandedUsdaLine(String item) {
    final t = item.trim();
    if (t.isEmpty) return true;
    if (t.length > 90) return true;
    if (t.startsWith('!') || t.startsWith('"')) return true;
    if (t.contains('""')) return true;
    final commaCount = ','.allMatches(t).length;
    if (commaCount >= 4) return true;
    final wordCount = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    if (wordCount > 12) return true;
    if (RegExp(r'#\d').hasMatch(t)) return true;
    return false;
  }

  int _matchScore({
    required String item,
    required String query,
    required Set<String> recentNames,
    bool isUsdaFallback = false,
  }) {
    final lower = item.toLowerCase();
    var score = 100;
    final isStaple = _stapleCatalogLower.contains(lower);
    if (isStaple) score -= 28;
    if (isUsdaFallback &&
        !isStaple &&
        !recentNames.contains(item)) {
      score += 32;
    }
    if (lower == query) score -= 90;
    if (lower.startsWith(query)) score -= 60;
    if (RegExp(r'\b' + RegExp.escape(query)).hasMatch(lower)) score -= 40;
    if (recentNames.contains(item)) score -= 20;
    if (RegExp(r'[^a-z0-9\s]').hasMatch(lower)) score += 8;
    return score;
  }

  Future<List<GroceryItem>> _fetchListItemsForList(String listId) async {
    try {
      final rows = await _client
          .from('list_items')
          .select()
          .eq('list_id', listId)
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

  Future<List<GroceryItem>> listItems(String userId) async {
    final listId = await _defaultListIdForUser(userId);
    if (listId == null || listId.isEmpty) return [];
    return _fetchListItemsForList(listId);
  }

  Stream<List<GroceryItem>> streamItems(String userId) async* {
    final listId = await _defaultListIdForUser(userId);
    if (listId == null || listId.isEmpty) {
      yield const [];
      return;
    }
    yield* streamItemsForList(listId);
  }

  /// Live updates via Realtime; refetches on each change. No column filter on
  /// the subscription: without a filter, DELETE old rows still reach the
  /// client; RLS scopes events. DB uses `REPLICA IDENTITY FULL` on `list_items`
  /// so DELETE payloads include columns needed for RLS.
  Stream<List<GroceryItem>> streamItemsForList(String listId) {
    return Stream<List<GroceryItem>>.multi((multi) {
      RealtimeChannel? channel;
      final topic =
          'public:list_items:list=$listId:${DateTime.now().microsecondsSinceEpoch}';

      Future<void> pushFresh() async {
        if (multi.isClosed) return;
        final items = await _fetchListItemsForList(listId);
        if (!multi.isClosed) {
          multi.add(items);
        }
      }

      var sawSubscribedOnce = false;

      Future<void> setup() async {
        await pushFresh();
        if (multi.isClosed) return;
        channel = _client.channel(topic);
        channel!
            .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'list_items',
          callback: (_) {
            unawaited(pushFresh());
          },
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
        unawaited(channel?.unsubscribe());
      };
    });
  }

  Future<void> addItem({
    required String userId,
    String? listId,
    required String name,
    String? quantity,
    String? unit,
    GroceryCategory? category,
    String? fromRecipeId,
    String? sourceSlotId,
  }) {
    return _insertItem(
      userId: userId,
      listId: listId,
      name: name,
      quantity: quantity,
      unit: unit,
      category: category ?? categorize(name),
      fromRecipeId: fromRecipeId,
      sourceSlotId: sourceSlotId,
    );
  }

  Future<void> removeItem(String itemId) {
    return _client.from('list_items').delete().eq('id', itemId);
  }

  Future<void> updateItemQuantity(String itemId, String quantity) {
    return _client
        .from('list_items')
        .update({'quantity': quantity}).eq('id', itemId);
  }

  Future<void> removeItemsByRecipe(String recipeId) {
    return _client.from('list_items').delete().eq('from_recipe_id', recipeId);
  }

  Future<void> clear(String userId, {String? listId}) {
    return _clearHouseholdItems(userId, listId: listId);
  }

  Future<void> shareText(List<GroceryItem> items) {
    final text = items
        .map((e) => '- ${e.name} ${e.quantity ?? ''}${e.unit ?? ''}'.trim())
        .join('\n');
    return Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> addIngredientsFromRecipe(Recipe recipe,
      {required String userId,
      required int servingsUsed,
      String? listId,
      String? sourceSlotId}) async {
    final targetListId = listId ?? await _defaultListIdForUser(userId);
    if (targetListId == null || targetListId.isEmpty) return;
    final ratio = servingsUsed / recipe.servings;
    final existing = await listItems(userId);

    for (final ingredient in recipe.ingredients) {
      final current = existing.firstWhereOrNull(
          (e) => e.name.toLowerCase() == ingredient.name.toLowerCase());
      if (current != null) continue;

      if (ingredient.qualitative) {
        await _client.from('list_items').insert({
          'list_id': targetListId,
          'user_id': userId,
          'name': ingredient.name,
          'category': ingredient.category.dbValue,
          'quantity': null,
          'unit': ingredient.unit,
          'from_recipe_id': recipe.id,
          'source_type': 'planner_recipe',
          'source_slot_id': sourceSlotId,
        });
        await touchRecent(
          name: ingredient.name,
          category: ingredient.category,
          quantity: null,
          unit: ingredient.unit,
        );
        continue;
      }

      final qty = formatIngredientAmount(ingredient.amount * ratio);
      await _client.from('list_items').insert({
        'list_id': targetListId,
        'user_id': userId,
        'name': ingredient.name,
        'category': ingredient.category.dbValue,
        'quantity': qty,
        'unit': ingredient.unit,
        'from_recipe_id': recipe.id,
        'source_type': 'planner_recipe',
        'source_slot_id': sourceSlotId,
      });
      await touchRecent(
        name: ingredient.name,
        category: ingredient.category,
        quantity: qty,
        unit: ingredient.unit,
      );
    }
  }

  Future<void> _insertItem({
    required String userId,
    String? listId,
    required String name,
    String? quantity,
    String? unit,
    required GroceryCategory category,
    String? fromRecipeId,
    String? sourceSlotId,
  }) async {
    final targetListId = listId ?? await _defaultListIdForUser(userId);
    if (targetListId == null || targetListId.isEmpty) {
      throw StateError('Could not initialize your list.');
    }
    final String sourceType;
    if (sourceSlotId != null && sourceSlotId.isNotEmpty) {
      sourceType = fromRecipeId != null ? 'planner_recipe' : 'planner_slot';
    } else {
      sourceType = fromRecipeId == null ? 'manual' : 'planner_recipe';
    }
    final row = <String, dynamic>{
      'list_id': targetListId,
      'user_id': userId,
      'name': name,
      'category': category.dbValue,
      'quantity': quantity,
      'unit': unit,
      'from_recipe_id': fromRecipeId,
      'source_type': sourceType,
    };
    if (sourceSlotId != null && sourceSlotId.isNotEmpty) {
      row['source_slot_id'] = sourceSlotId;
    }
    await _client.from('list_items').insert(row);
    await touchRecent(
      name: name,
      category: category,
      quantity: quantity,
      unit: unit,
    );
  }

  List<RecentGroceryEntry> readRecentsFromCache() {
    return _cache
        .loadGroceryRecents()
        .map(RecentGroceryEntry.fromJson)
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
  }

  Future<void> touchRecent({
    required String name,
    required GroceryCategory category,
    String? quantity,
    String? unit,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final norm = normalizeGroceryItemName(trimmed);
    final existing = readRecentsFromCache();
    final filtered = existing
        .where((e) => normalizeGroceryItemName(e.name) != norm)
        .toList();
    final entry = RecentGroceryEntry(
      name: trimmed,
      category: category,
      quantity: quantity,
      unit: unit,
      lastUsedAt: DateTime.now().toUtc(),
    );
    final next = [entry, ...filtered].take(_maxGroceryRecentsStored).toList();
    await _cache.saveGroceryRecents(next.map((e) => e.toJson()).toList());
  }

  Future<void> _clearHouseholdItems(String userId, {String? listId}) async {
    final targetListId = listId ?? await _defaultListIdForUser(userId);
    if (targetListId == null || targetListId.isEmpty) return;
    await _client.from('list_items').delete().eq('list_id', targetListId);
  }

  Future<List<AppList>> listLists(String userId) async {
    final rows = await _client.from('lists').select().order('created_at');
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(AppList.fromJson)
        .toList();
  }

  Future<AppList> createList({
    required String userId,
    required String name,
    required ListScope scope,
  }) async {
    String? householdId;
    if (scope == ListScope.household) {
      householdId = await _householdForUser(userId);
      if (householdId == null || householdId.isEmpty) {
        throw StateError('No household found for a shared list.');
      }
    }
    final row = await _client
        .from('lists')
        .insert({
          'owner_user_id': userId,
          'household_id': householdId,
          'name': name.trim(),
          'kind': 'general',
          'scope': scope.name,
        })
        .select()
        .single();
    final list = AppList.fromJson(row);
    await _profileRepo.appendGroceryListId(userId, scope, list.id);
    return list;
  }

  /// Updates the display name of a list. RLS: owner for private lists; any household
  /// member for household lists.
  Future<void> renameList({
    required String listId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('List name cannot be empty.');
    }
    await _client.from('lists').update({'name': trimmed}).eq('id', listId);
  }

  /// Deletes the list and its items (DB cascade). Updates saved list order for [userId].
  Future<void> deleteList({
    required String userId,
    required AppList list,
  }) async {
    await _client.from('lists').delete().eq('id', list.id);
    await _profileRepo.removeGroceryListId(userId, list.scope, list.id);
  }

  Future<String?> _defaultListIdForUser(String userId) async {
    final householdId = await _householdForUser(userId);
    if (householdId != null && householdId.isNotEmpty) {
      final existingHousehold = await _client
          .from('lists')
          .select('id')
          .eq('household_id', householdId)
          .eq('scope', ListScope.household.name)
          .eq('kind', 'grocery')
          .limit(1)
          .maybeSingle();
      if (existingHousehold != null) {
        return existingHousehold['id']?.toString();
      }
      final inserted = await _client
          .from('lists')
          .insert({
            'owner_user_id': userId,
            'household_id': householdId,
            'name': 'Household Grocery',
            'kind': 'grocery',
            'scope': ListScope.household.name,
          })
          .select('id')
          .single();
      return inserted['id']?.toString();
    }

    final existingPrivate = await _client
        .from('lists')
        .select('id')
        .eq('owner_user_id', userId)
        .eq('scope', ListScope.private.name)
        .eq('kind', 'grocery')
        .limit(1)
        .maybeSingle();
    if (existingPrivate != null) {
      return existingPrivate['id']?.toString();
    }
    final inserted = await _client
        .from('lists')
        .insert({
          'owner_user_id': userId,
          'name': 'My List',
          'kind': 'grocery',
          'scope': ListScope.private.name,
        })
        .select('id')
        .single();
    return inserted['id']?.toString();
  }

  Future<void> upsertDeviceToken(String userId, String token) async {
    final platform = Platform.operatingSystem;
    await _client.from('user_device_tokens').upsert(
      {
        'user_id': userId,
        'platform': platform,
        'token': token,
        'last_seen_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'token',
    );
  }
}

final groceryRepositoryProvider = Provider<GroceryRepository>((ref) {
  return GroceryRepository(
    ref.watch(localCacheProvider),
    ref.watch(profileRepositoryProvider),
  );
});

class GroceryRecentsNotifier extends Notifier<List<RecentGroceryEntry>> {
  @override
  List<RecentGroceryEntry> build() {
    return ref.read(groceryRepositoryProvider).readRecentsFromCache();
  }

  Future<void> recordRemovedItem(GroceryItem item) async {
    await ref.read(groceryRepositoryProvider).touchRecent(
          name: item.name,
          category: item.category,
          quantity: item.quantity,
          unit: item.unit,
        );
    state = ref.read(groceryRepositoryProvider).readRecentsFromCache();
  }
}

final groceryRecentsProvider =
    NotifierProvider<GroceryRecentsNotifier, List<RecentGroceryEntry>>(
  GroceryRecentsNotifier.new,
);

final listsProvider = FutureProvider<List<AppList>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(groceryRepositoryProvider).listLists(user.id);
});

final selectedListIdProvider = StateProvider<String?>((ref) => null);

/// Realtime + fetch per list id. [keepAlive] retains the subscription when you
/// switch Private/Shared so the UI can show cached data instead of a cold reload.
final groceryListItemsFamily =
    StreamProvider.autoDispose.family<List<GroceryItem>, String>(
  (ref, listId) {
    ref.keepAlive();
    return ref.watch(groceryRepositoryProvider).streamItemsForList(listId);
  },
);

/// When no list is selected yet, follow the user's default grocery list.
final groceryItemsDefaultListStreamProvider =
    StreamProvider<List<GroceryItem>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(groceryRepositoryProvider).streamItems(user.id);
});

/// Resolves to the active list's [AsyncValue] without tearing down the stream on
/// every [selectedListId] change (see [groceryListItemsFamily]).
final groceryItemsProvider = Provider<AsyncValue<List<GroceryItem>>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const AsyncData([]);
  final selectedListId = ref.watch(selectedListIdProvider);
  final lists = ref.watch(listsProvider).valueOrNull ?? const <AppList>[];
  final hasSharedHousehold =
      ref.watch(hasSharedHouseholdProvider).valueOrNull ?? false;
  final profileOrder =
      ref.watch(profileProvider).valueOrNull?.groceryListOrder ??
          GroceryListOrder.empty;

  final effectiveId = effectiveGroceryListId(
    lists: lists,
    selectedListId: selectedListId,
    hasSharedHousehold: hasSharedHousehold,
    profileOrder: profileOrder,
  );

  if (effectiveId != null && effectiveId.isNotEmpty) {
    return ref.watch(groceryListItemsFamily(effectiveId));
  }
  return ref.watch(groceryItemsDefaultListStreamProvider);
});

/// Recreates the Realtime channel and refetches items for the active list
/// (or default list when none is selected).
void invalidateActiveGroceryStreams(WidgetRef ref) {
  ref.invalidate(groceryItemsDefaultListStreamProvider);
  final selectedListId = ref.read(selectedListIdProvider);
  final lists = ref.read(listsProvider).valueOrNull ?? const <AppList>[];
  final hasSharedHousehold =
      ref.read(hasSharedHouseholdProvider).valueOrNull ?? false;
  final profileOrder =
      ref.read(profileProvider).valueOrNull?.groceryListOrder ??
          GroceryListOrder.empty;
  final effectiveId = effectiveGroceryListId(
    lists: lists,
    selectedListId: selectedListId,
    hasSharedHousehold: hasSharedHousehold,
    profileOrder: profileOrder,
  );
  if (effectiveId != null && effectiveId.isNotEmpty) {
    ref.invalidate(groceryListItemsFamily(effectiveId));
  }
  if (selectedListId != null &&
      selectedListId.isNotEmpty &&
      selectedListId != effectiveId) {
    ref.invalidate(groceryListItemsFamily(selectedListId));
  }
  ref.invalidate(groceryItemsProvider);
}
