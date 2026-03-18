import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LocalCache {
  static const _recipesBox = 'recipes_cache';
  static const _groceryBox = 'grocery_cache';
  static const _discoverBox = 'discover_cache';

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

  Future<void> saveGeneratedRecipe(String key, Map<String, dynamic> recipe) async {
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
}

final localCacheProvider = Provider<LocalCache>((ref) => LocalCache());
