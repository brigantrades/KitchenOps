import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalCache {
  static const _recipesBox = 'recipes_cache';
  static const _groceryBox = 'grocery_cache';
  static const _groceryRecentsKey = 'grocery_recents';
  static const _discoverBox = 'discover_cache';
  static const _homePinnedListIdKey = 'home_pinned_list_id';
  static const _householdCtaHiddenUntilKey = 'home_household_cta_hidden_until';
  static const _plannerLayoutModeKey = 'planner_layout_mode';
  static const _plannerSlotsKeyPrefix = 'planner_slots_json_';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(_recipesBox);
    await Hive.openBox<String>(_groceryBox);
    await Hive.openBox<String>(_discoverBox);
  }

  Future<void> saveRecipes(List<Map<String, dynamic>> recipes) async {
    final box = Hive.box<String>(_recipesBox);
    await box.put('items', jsonEncode(recipes));
  }

  List<Map<String, dynamic>> loadRecipes() {
    final box = Hive.box<String>(_recipesBox);
    final raw = box.get('items');
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> saveGrocery(List<Map<String, dynamic>> items) async {
    final box = Hive.box<String>(_groceryBox);
    await box.put('items', jsonEncode(items));
  }

  List<Map<String, dynamic>> loadGrocery() {
    final box = Hive.box<String>(_groceryBox);
    final raw = box.get('items');
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().toList();
  }

  Future<void> saveGroceryRecents(List<Map<String, dynamic>> entries) async {
    final box = Hive.box<String>(_groceryBox);
    await box.put(_groceryRecentsKey, jsonEncode(entries));
  }

  List<Map<String, dynamic>> loadGroceryRecents() {
    final box = Hive.box<String>(_groceryBox);
    final raw = box.get(_groceryRecentsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> saveGeneratedRecipe(
      String key, Map<String, dynamic> recipe) async {
    final box = Hive.box<String>(_discoverBox);
    await box.put(key, jsonEncode(recipe));
  }

  Map<String, dynamic>? loadGeneratedRecipe(String key) {
    final box = Hive.box<String>(_discoverBox);
    final raw = box.get(key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<void> saveHomePinnedListId(String? listId) async {
    final box = Hive.box<String>(_discoverBox);
    if (listId == null || listId.isEmpty) {
      await box.delete(_homePinnedListIdKey);
      return;
    }
    await box.put(_homePinnedListIdKey, listId);
  }

  String? loadHomePinnedListId() {
    final box = Hive.box<String>(_discoverBox);
    final raw = box.get(_homePinnedListIdKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<void> saveHouseholdCtaHiddenUntil(DateTime? hiddenUntil) async {
    final box = Hive.box<String>(_discoverBox);
    if (hiddenUntil == null) {
      await box.delete(_householdCtaHiddenUntilKey);
      return;
    }
    await box.put(_householdCtaHiddenUntilKey, hiddenUntil.toIso8601String());
  }

  DateTime? loadHouseholdCtaHiddenUntil() {
    final box = Hive.box<String>(_discoverBox);
    final raw = box.get(_householdCtaHiddenUntilKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// Stored enum name: `list` or `calendar`.
  Future<void> savePlannerLayoutMode(String modeName) async {
    final box = Hive.box<String>(_discoverBox);
    await box.put(_plannerLayoutModeKey, modeName);
  }

  String? loadPlannerLayoutMode() {
    final box = Hive.box<String>(_discoverBox);
    final raw = box.get(_plannerLayoutModeKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  /// Last known planner slot rows for a cache key (see [planner_repository] keys).
  Future<void> savePlannerSlotList(
    String cacheKey,
    List<Map<String, dynamic>> rows,
  ) async {
    final box = Hive.box<String>(_discoverBox);
    await box.put('$_plannerSlotsKeyPrefix$cacheKey', jsonEncode(rows));
  }

  List<Map<String, dynamic>>? loadPlannerSlotList(String cacheKey) {
    final box = Hive.box<String>(_discoverBox);
    final raw = box.get('$_plannerSlotsKeyPrefix$cacheKey');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;
    return decoded.whereType<Map<String, dynamic>>().toList();
  }
}

final localCacheProvider = Provider<LocalCache>((ref) => LocalCache());
