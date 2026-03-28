import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/network/http_client.dart';

class SpoonacularService {
  SpoonacularService(this._client);

  final HttpClient _client;

  Future<List<Map<String, dynamic>>> searchRecipes(String query) async {
    if (!Env.hasSpoonacular) return [];
    final uri = Uri.https('api.spoonacular.com', '/recipes/complexSearch', {
      'apiKey': Env.spoonacularApiKey,
      'query': query,
      'number': '10',
      'addRecipeNutrition': 'true',
    });
    final json = await _client.getJson(uri);
    return (json['results'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
  }

  Future<Nutrition> estimateNutritionFromIngredients(
      List<String> ingredients) async {
    if (!Env.hasSpoonacular || ingredients.isEmpty) return const Nutrition();
    final uri = Uri.https('api.spoonacular.com', '/recipes/parseIngredients', {
      'apiKey': Env.spoonacularApiKey,
      'includeNutrition': 'true',
    });
    final json = await _client.getJson(uri.replace(queryParameters: {
      ...uri.queryParameters,
      'ingredientList': ingredients.join('\n'),
      'servings': '1',
    }));

    int calories = 0;
    double protein = 0;
    double fat = 0;
    double carbs = 0;
    double fiber = 0;
    double sugar = 0;

    if (json['results'] is List) {
      for (final entry
          in (json['results'] as List).whereType<Map<String, dynamic>>()) {
        final nutrients =
            (entry['nutrition']?['nutrients'] as List?) ?? const [];
        for (final nutrient in nutrients.whereType<Map<String, dynamic>>()) {
          final name = nutrient['name']?.toString().toLowerCase();
          final amount = (nutrient['amount'] as num?)?.toDouble() ?? 0;
          if (name == 'calories') calories += amount.round();
          if (name == 'protein') protein += amount;
          if (name == 'fat') fat += amount;
          if (name == 'carbohydrates') carbs += amount;
          if (name == 'fiber') fiber += amount;
          if (name == 'sugar') sugar += amount;
        }
      }
    }

    return Nutrition(
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      fiber: fiber,
      sugar: sugar,
    );
  }
}

class GeminiService {
  GeminiService()
      : _apiKey = Env.geminiApiKey,
        _model = Env.hasGemini
            ? GenerativeModel(
                model: 'gemini-2.5-flash-lite',
                apiKey: Env.geminiApiKey,
              )
            : null;

  final String _apiKey;
  final GenerativeModel? _model;
  String? _lastGenerateFailure;
  String? get lastGenerateFailure => _lastGenerateFailure;
  static const List<String> _fallbackModels = <String>[
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];

  Future<GenerateContentResponse?> _generateWithFallback(String prompt) async {
    if (_model == null) return null;

    Future<GenerateContentResponse> callModel(GenerativeModel model) {
      return model.generateContent([Content.text(prompt)]);
    }

    try {
      final r = await callModel(_model);
      _lastGenerateFailure = null;
      return r;
    } catch (e) {
      final err = e.toString();
      for (final modelName in _fallbackModels) {
        try {
          final model = GenerativeModel(model: modelName, apiKey: _apiKey);
          final r = await callModel(model);
          _lastGenerateFailure = null;
          return r;
        } catch (e2, _) {
          continue;
        }
      }
      _lastGenerateFailure = err;
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> generateWeeklyPlan({
    required Profile profile,
  }) async {
    if (_model == null) return [];
    final prompt = '''
Generate 7 diverse meal recipes in strict JSON array format.
Each item keys: title, meal_type, cuisine_tags, ingredients[{name,amount,unit,category}], instructions.
Respect dietary restrictions: ${profile.dietaryRestrictions.join(', ')}
Goals: ${profile.goals.join(', ')}
Preferred cuisines: ${profile.preferredCuisines.join(', ')}
''';

    final response = await _generateWithFallback(prompt);
    if (response == null) return [];
    final decoded = _decodeJsonSafe(response.text ?? '[]');
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> generateRecipeFromIngredients(
      List<String> ingredients) async {
    if (_model == null) return {};
    final prompt = '''
Create one recipe from these ingredients: ${ingredients.join(', ')}.
Return strict JSON object with keys: title, meal_type, cuisine_tags, ingredients, instructions.
''';
    final response = await _generateWithFallback(prompt);
    if (response == null) return {};
    final decoded = _decodeJsonSafe(response.text ?? '{}');
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> generateRecipeWithCriteria({
    required List<String> ingredients,
    required List<String> dietTags,
    String? mealType,
    int? maxCookTimeMinutes,
    int? servings,
    String? prompt,
  }) async {
    if (_model == null) return {};
    final promptText = '''
Create one recipe and return strict JSON object with keys:
title, meal_type, cuisine_tags, ingredients, instructions.

Constraints:
- Diet preferences: ${dietTags.isEmpty ? 'none' : dietTags.join(', ')}
- Target meal type: ${mealType ?? 'any'}
- Max cook time minutes: ${maxCookTimeMinutes?.toString() ?? 'not specified'}
- Servings: ${servings?.toString() ?? 'not specified'}
- Ingredients available (optional): ${ingredients.isEmpty ? 'none provided' : ingredients.join(', ')}

User prompt (optional): ${prompt?.trim().isEmpty ?? true ? 'none' : prompt!.trim()}

Rules:
- Keep instructions concise and practical.
- Respect dietary constraints first.
- If ingredients are provided, prioritize using them.
''';
    final response = await _generateWithFallback(promptText);
    if (response == null) return {};
    final decoded = _decodeJsonSafe(response.text ?? '{}');
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> generateRecipeOptionsWithCriteria({
    required List<String> ingredients,
    required List<String> dietTags,
    String? mealType,
    int? maxCookTimeMinutes,
    int? servings,
    String? prompt,
    int count = 3,
  }) async {
    if (_model == null) return const [];
    final safeCount = count < 2 ? 2 : (count > 5 ? 5 : count);
    final promptText = '''
Create $safeCount different recipe options and return strict JSON array.

Each array item must be an object with keys:
title, meal_type, cuisine_tags, ingredients, instructions, prep_time, cook_time.

Constraints:
- Diet preferences: ${dietTags.isEmpty ? 'none' : dietTags.join(', ')}
- Target meal type: ${mealType ?? 'any'}
- Max cook time minutes: ${maxCookTimeMinutes?.toString() ?? 'not specified'}
- Servings: ${servings?.toString() ?? 'not specified'}
- Ingredients available (optional): ${ingredients.isEmpty ? 'none provided' : ingredients.join(', ')}
- User prompt (optional): ${prompt?.trim().isEmpty ?? true ? 'none' : prompt!.trim()}

Rules:
- Keep recipes realistic and distinct from each other.
- Include concise instructions.
- Use common pantry items when possible.
''';
    final response = await _generateWithFallback(promptText);
    if (response == null) return const [];
    final decoded = _decodeJsonSafe(response.text ?? '[]');
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) {
      return [decoded];
    }
    return const [];
  }

  /// Instagram share import: returns decoded JSON map or null if Gemini is disabled or parsing fails.
  Future<Map<String, dynamic>?> extractRecipeFromInstagramContent(
      String sharedContent) async {
    if (_model == null) return null;
    final trimmed = sharedContent.trim();
    if (trimmed.isEmpty) return null;
    final prompt = '''
Extract a complete recipe from the following Instagram post content.
Return ONLY valid JSON with these keys:
{
  "title": string,
  "description": string (short summary),
  "ingredients": array of objects [{ "name": string, "amount": string, "unit": string }],
  "instructions": array of strings (each step as one string),
  "servings": number (default 2 if missing),
  "prep_time": number (minutes, null if missing),
  "cook_time": number (minutes, null if missing),
  "meal_type": "dinner" or "lunch" etc (best guess),
  "cuisine_tags": array of strings
}
Title guidance:
- The app may use the first line of the caption as the recipe name when it is clear.
- For "title", provide a short fallback dish name only when the caption does not clearly name the recipe (otherwise a simple descriptive name is fine).

Here is the shared content: $trimmed

Serving size guidance:
- Infer servings from ingredient quantities and yield language (e.g. "serves 4", tray size, pan size, portions).
- Return an integer servings estimate even if not explicit.
- If uncertain, choose the most plausible household size from {2, 3, 4, 6}.
''';
    final response = await _generateWithFallback(prompt);
    if (response == null) {
      debugPrint(
        'Gemini Instagram import: generateContent returned null (API key, '
        'network, quota, or all fallback models failed). Check GEMINI_API_KEY '
        'and device network.',
      );
      return null;
    }
    final raw = (response.text ?? '').trim();
    final decoded = _decodeJsonSafe(raw.isEmpty ? '{}' : raw);
    Map<String, dynamic>? asMap;
    if (decoded is Map<String, dynamic>) {
      asMap = decoded;
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          asMap = item;
          break;
        }
        if (item is Map) {
          asMap = Map<String, dynamic>.from(item);
          break;
        }
      }
    }

    bool looksValidRecipeJson(Map<String, dynamic> m) {
      final ingredients = m['ingredients'];
      final instructions = m['instructions'];
      final hasIngredients = ingredients is List && ingredients.isNotEmpty;
      final hasInstructions = instructions is List && instructions.isNotEmpty;
      return hasIngredients || hasInstructions;
    }

    if (asMap != null && looksValidRecipeJson(asMap)) {
      return asMap;
    }

    // Truncated raw response (refusals, markdown, empty JSON, wrong shape).
    final snippet = raw.isEmpty
        ? '<empty response.text>'
        : (raw.length <= 800 ? raw : raw.substring(0, 800));
    debugPrint('Gemini Instagram import: invalid or empty recipe JSON.');
    debugPrint('Gemini raw (first 800 chars): $snippet');
    if (asMap != null) {
      debugPrint(
        'Gemini decoded keys: ${asMap.keys.toList()} '
        '(ingredients/instructions missing or empty?)',
      );
    } else {
      debugPrint(
        'Gemini decode result type: ${decoded.runtimeType} (expected object or array of object)',
      );
    }
    return null;
  }

  Future<Nutrition> estimateNutritionFromIngredients(
      List<String> ingredients, {
    int? servings,
  }) async {
    if (_model == null || ingredients.isEmpty) return const Nutrition();
    final servingsClause = servings != null && servings > 0
        ? 'The recipe makes $servings servings; totals are for the full batch (all servings combined).'
        : '';
    final prompt = '''
Estimate nutrition for one recipe made from these ingredients (with amounts):
${ingredients.join('\n')}
$servingsClause
Return strict JSON object with numeric keys: calories, protein, fat, carbs, fiber, sugar.
Keep values realistic for one full recipe (entire batch), not per 100g.
''';
    final response = await _generateWithFallback(prompt);
    if (response == null) return const Nutrition();
    final decoded = _decodeJsonSafe(response.text ?? '{}');
    if (decoded is! Map<String, dynamic>) return const Nutrition();
    return Nutrition.fromJson(decoded);
  }

  dynamic _decodeJsonSafe(String raw) {
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    try {
      return jsonDecode(cleaned);
    } catch (_) {
      final objStart = cleaned.indexOf('{');
      final objEnd = cleaned.lastIndexOf('}');
      if (objStart != -1 && objEnd > objStart) {
        final slice = cleaned.substring(objStart, objEnd + 1);
        try {
          return jsonDecode(slice);
        } catch (_) {}
      }
      final arrStart = cleaned.indexOf('[');
      final arrEnd = cleaned.lastIndexOf(']');
      if (arrStart != -1 && arrEnd > arrStart) {
        final slice = cleaned.substring(arrStart, arrEnd + 1);
        try {
          return jsonDecode(slice);
        } catch (_) {}
      }
      return null;
    }
  }
}
