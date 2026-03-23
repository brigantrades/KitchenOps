import 'package:plateplan/core/models/app_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IngredientNutritionCacheEntry {
  const IngredientNutritionCacheEntry({
    required this.normalizedName,
    required this.displayName,
    required this.nutritionPer100g,
    this.fdcId,
    this.dataType,
    this.source = 'usda_fdc',
  });

  final String normalizedName;
  final String displayName;
  final Nutrition nutritionPer100g;
  final int? fdcId;
  final String? dataType;
  final String source;

  Map<String, dynamic> toUpsertJson() => {
        'normalized_name': normalizedName,
        'display_name': displayName,
        'fdc_id': fdcId,
        'data_type': dataType,
        'calories_per_100g': nutritionPer100g.calories,
        'protein_per_100g': nutritionPer100g.protein,
        'fat_per_100g': nutritionPer100g.fat,
        'carbs_per_100g': nutritionPer100g.carbs,
        'fiber_per_100g': nutritionPer100g.fiber,
        'sugar_per_100g': nutritionPer100g.sugar,
        'source': source,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory IngredientNutritionCacheEntry.fromJson(Map<String, dynamic> json) {
    return IngredientNutritionCacheEntry(
      normalizedName: json['normalized_name']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      fdcId: (json['fdc_id'] as num?)?.toInt(),
      dataType: json['data_type']?.toString(),
      source: json['source']?.toString() ?? 'usda_fdc',
      nutritionPer100g: Nutrition(
        calories: (json['calories_per_100g'] as num?)?.round() ?? 0,
        protein: (json['protein_per_100g'] as num?)?.toDouble() ?? 0,
        fat: (json['fat_per_100g'] as num?)?.toDouble() ?? 0,
        carbs: (json['carbs_per_100g'] as num?)?.toDouble() ?? 0,
        fiber: (json['fiber_per_100g'] as num?)?.toDouble() ?? 0,
        sugar: (json['sugar_per_100g'] as num?)?.toDouble() ?? 0,
      ),
    );
  }
}

class IngredientNutritionCacheRepository {
  IngredientNutritionCacheRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<IngredientNutritionCacheEntry?> getByNormalizedName(
    String normalizedName,
  ) async {
    if (normalizedName.trim().isEmpty) return null;
    try {
      final row = await _client
          .from('ingredient_nutrition_cache')
          .select(
            'normalized_name,display_name,fdc_id,data_type,source,'
            'calories_per_100g,protein_per_100g,fat_per_100g,'
            'carbs_per_100g,fiber_per_100g,sugar_per_100g',
          )
          .eq('normalized_name', normalizedName)
          .maybeSingle();
      if (row == null) return null;
      return IngredientNutritionCacheEntry.fromJson(row);
    } on PostgrestException {
      // Table missing, RLS, or project not migrated — estimation can still use USDA.
      return null;
    }
  }

  Future<void> upsertFromUsda(IngredientNutritionCacheEntry entry) async {
    try {
      await _client.from('ingredient_nutrition_cache').upsert(
            entry.toUpsertJson(),
            onConflict: 'normalized_name',
          );
    } on PostgrestException {
      // Ignore cache write failures; USDA totals are still returned.
    }
  }
}
