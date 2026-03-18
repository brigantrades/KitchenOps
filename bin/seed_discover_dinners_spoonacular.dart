import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const spoonacularApiKey = 'YOUR_KEY';
const supabaseUrl = 'YOUR_SUPABASE_URL';
const supabaseServiceRoleKey = 'YOUR_SUPABASE_SERVICE_ROLE_KEY';
const seedUserId = 'YOUR_SEED_USER_ID';

const discoverCategoriesByMeal = <String, List<String>>{
  'breakfast': <String>[
    'eggs',
    'oatmeal',
    'pancakes',
    'toast',
    'smoothie',
  ],
  'lunch': <String>[
    'salad',
    'sandwich',
    'wrap',
    'bowl',
    'soup',
  ],
  'dinner': <String>[
    'chicken',
    'beef',
    'vegetarian',
    'pasta',
    'pork',
  ],
};

class QuotaHitException implements Exception {
  const QuotaHitException(this.message);
  final String message;

  @override
  String toString() => message;
}

Future<void> main() async {
  final resolvedSpoonKey = _resolveSecret(
    explicit: spoonacularApiKey,
    envNames: const ['SPOONACULAR_API_KEY'],
  );
  final resolvedSupabaseUrl = _resolveSecret(
    explicit: supabaseUrl,
    envNames: const ['SUPABASE_URL'],
  );
  final resolvedServiceRole = _resolveSecret(
    explicit: supabaseServiceRoleKey,
    envNames: const ['SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ANON_KEY'],
  );
  final resolvedSeedUserId = _resolveSecret(
    explicit: seedUserId,
    envNames: const ['SEED_USER_ID'],
  );

  final missing = <String>[];
  if (_isPlaceholder(resolvedSpoonKey)) missing.add('SPOONACULAR_API_KEY');
  if (_isPlaceholder(resolvedSupabaseUrl)) missing.add('SUPABASE_URL');
  if (_isPlaceholder(resolvedServiceRole)) {
    missing.add('SUPABASE_SERVICE_ROLE_KEY');
  }
  if (_isPlaceholder(resolvedSeedUserId)) missing.add('SEED_USER_ID');

  if (missing.isNotEmpty) {
    stderr.writeln(
      'Missing required values: ${missing.join(', ')}.\n'
      'Set them as environment variables or update placeholders in this file.',
    );
    exitCode = 64;
    return;
  }

  var totalUpserted = 0;
  var nutritionFallbackCalls = 0;
  const maxNutritionFallbackCalls = 3;
  final client = http.Client();
  try {
    for (final entry in discoverCategoriesByMeal.entries) {
      final mealType = entry.key;
      for (final category in entry.value) {
        stdout.writeln('\n== [$mealType] Category: $category ==');
        final recipes = await _fetchCategoryRecipes(
          client: client,
          apiKey: resolvedSpoonKey,
          mealType: mealType,
          category: category,
        );
        stdout.writeln('Fetched ${recipes.length} recipes from Spoonacular.');

        var categoryUpserted = 0;
        for (final raw in recipes) {
          final payload = await _toSupabasePayload(
            client: client,
            spoonacularApiKey: resolvedSpoonKey,
            seedUserId: resolvedSeedUserId,
            mealType: mealType,
            category: category,
            raw: raw,
            canFetchNutritionFallback:
                nutritionFallbackCalls < maxNutritionFallbackCalls,
          );
          if (payload['used_nutrition_fallback'] == true) {
            nutritionFallbackCalls += 1;
          }
          payload.remove('used_nutrition_fallback');

          final ok = await _upsertRecipe(
            client: client,
            supabaseUrl: resolvedSupabaseUrl,
            serviceRoleKey: resolvedServiceRole,
            payload: payload,
          );
          if (ok) {
            categoryUpserted += 1;
            totalUpserted += 1;
            stdout.writeln(
              'Upserted [$mealType] [${payload['api_id']}] ${payload['title']}',
            );
          }
        }

        stdout.writeln(
          'Category complete: [$mealType] $category (upserted $categoryUpserted recipes).',
        );

        await Future<void>.delayed(const Duration(milliseconds: 1000));
      }
    }
  } on QuotaHitException catch (error) {
    stderr.writeln('Quota hit, stopping seed: $error');
  } catch (error, stackTrace) {
    stderr.writeln('Seed failed: $error');
    stderr.writeln(stackTrace);
    rethrow;
  } finally {
    client.close();
  }

  stdout.writeln('\nSeed done. Total upserted: $totalUpserted');
}

String _resolveSecret({
  required String explicit,
  required List<String> envNames,
}) {
  if (!_isPlaceholder(explicit) && explicit.trim().isNotEmpty) {
    return explicit.trim();
  }
  for (final key in envNames) {
    final value = Platform.environment[key];
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return explicit.trim();
}

bool _isPlaceholder(String value) => value.startsWith('YOUR_') || value.isEmpty;

Future<List<Map<String, dynamic>>> _fetchCategoryRecipes({
  required http.Client client,
  required String apiKey,
  required String mealType,
  required String category,
}) async {
  final spoonType = _spoonTypeForMeal(mealType);
  final uri = Uri.https(
    'api.spoonacular.com',
    '/recipes/complexSearch',
    <String, String>{
      'apiKey': apiKey,
      'query': category,
      'type': spoonType,
      'number': '10',
      'addRecipeInformation': 'true',
      'fillIngredients': 'true',
      'instructionsRequired': 'true',
      'addRecipeNutrition': 'true',
    },
  );

  final response = await client.get(uri);
  if (response.statusCode == 402 || response.statusCode == 429) {
    throw QuotaHitException(
      'Spoonacular responded with ${response.statusCode}: ${response.body}',
    );
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Spoonacular request failed (${response.statusCode}): ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final results = decoded['results'] as List<dynamic>? ?? const [];
  return results.whereType<Map<String, dynamic>>().toList();
}

Future<Map<String, dynamic>> _toSupabasePayload({
  required http.Client client,
  required String spoonacularApiKey,
  required String seedUserId,
  required String mealType,
  required String category,
  required Map<String, dynamic> raw,
  required bool canFetchNutritionFallback,
}) async {
  final recipeId = (raw['id'] as num?)?.toInt() ?? 0;
  final title = raw['title']?.toString().trim().isNotEmpty == true
      ? raw['title'].toString().trim()
      : 'Untitled recipe';
  final summary = _stripHtml(raw['summary']?.toString() ?? '');
  final readyInMinutes = (raw['readyInMinutes'] as num?)?.toInt() ?? 30;
  final prepTime = readyInMinutes >= 10 ? (readyInMinutes * 0.4).round() : 5;
  final cookTime =
      readyInMinutes - prepTime > 0 ? readyInMinutes - prepTime : 5;
  final servings = (raw['servings'] as num?)?.toInt() ?? 2;

  final cuisinesRaw = (raw['cuisines'] as List<dynamic>? ?? const [])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final cuisines =
      cuisinesRaw.isEmpty ? <String>[_capitalize(category)] : cuisinesRaw;

  final ingredients = _parseIngredients(raw);
  final instructions = _parseInstructions(raw);

  var nutrition = _parseNutrition(raw['nutrition']);
  var usedNutritionFallback = false;
  if (_nutritionEmpty(nutrition) && canFetchNutritionFallback && recipeId > 0) {
    final fallback = await _fetchNutritionFallback(
      client: client,
      apiKey: spoonacularApiKey,
      recipeId: recipeId,
    );
    if (fallback != null) {
      nutrition = fallback;
      usedNutritionFallback = true;
    }
  }

  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title,
    'description': summary,
    'servings': servings,
    'prep_time': prepTime,
    'cook_time': cookTime,
    'meal_type': mealType,
    'cuisine_tags': cuisines,
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url': raw['image']?.toString(),
    'nutrition': nutrition,
    'nutrition_source': 'spoonacular',
    'is_public': true,
    'source': 'spoonacular',
    'api_id': recipeId.toString(),
    'used_nutrition_fallback': usedNutritionFallback,
  };
}

String _spoonTypeForMeal(String mealType) {
  switch (mealType) {
    case 'breakfast':
      return 'breakfast';
    case 'lunch':
      return 'main course';
    case 'dinner':
      return 'main course';
    default:
      return 'main course';
  }
}

List<Map<String, dynamic>> _parseIngredients(Map<String, dynamic> raw) {
  final source = raw['extendedIngredients'] as List<dynamic>? ?? const [];
  return source
      .whereType<Map<String, dynamic>>()
      .map((item) {
        final name = item['nameClean']?.toString().trim().isNotEmpty == true
            ? item['nameClean'].toString().trim()
            : item['name']?.toString().trim() ?? '';
        return <String, dynamic>{
          'name': name,
          'amount': (item['amount'] as num?)?.toDouble() ?? 0,
          'unit': item['unit']?.toString() ?? '',
          'category': 'other',
        };
      })
      .where((item) => (item['name'] as String).isNotEmpty)
      .toList();
}

List<String> _parseInstructions(Map<String, dynamic> raw) {
  final analyzed = raw['analyzedInstructions'] as List<dynamic>? ?? const [];
  if (analyzed.isNotEmpty) {
    final first = analyzed.first;
    if (first is Map<String, dynamic>) {
      final steps = first['steps'] as List<dynamic>? ?? const [];
      final parsed = steps
          .whereType<Map<String, dynamic>>()
          .map((step) {
            final number = (step['number'] as num?)?.toInt() ?? 0;
            final text = step['step']?.toString().trim() ?? '';
            if (text.isEmpty) return '';
            return number > 0 ? '$number. $text' : text;
          })
          .where((s) => s.isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) return parsed;
    }
  }

  final plain = raw['instructions']?.toString() ?? '';
  if (plain.trim().isEmpty) return const [];
  return plain
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

Map<String, dynamic> _parseNutrition(dynamic nutritionRaw) {
  final nutrients = (nutritionRaw is Map<String, dynamic>
          ? nutritionRaw['nutrients']
          : null) as List<dynamic>? ??
      const [];

  double lookup(String name) {
    for (final n in nutrients.whereType<Map<String, dynamic>>()) {
      final nName = n['name']?.toString().toLowerCase();
      if (nName == name.toLowerCase()) {
        return (n['amount'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }

  return <String, dynamic>{
    'calories': lookup('Calories').round(),
    'protein': lookup('Protein'),
    'fat': lookup('Fat'),
    'carbs': lookup('Carbohydrates'),
    'fiber': lookup('Fiber'),
    'sugar': lookup('Sugar'),
  };
}

Future<Map<String, dynamic>?> _fetchNutritionFallback({
  required http.Client client,
  required String apiKey,
  required int recipeId,
}) async {
  final uri = Uri.https(
    'api.spoonacular.com',
    '/recipes/$recipeId/nutritionWidget.json',
    <String, String>{'apiKey': apiKey},
  );
  final response = await client.get(uri);

  if (response.statusCode == 402 || response.statusCode == 429) {
    throw QuotaHitException(
      'Spoonacular nutrition quota issue (${response.statusCode}).',
    );
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    return null;
  }
  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final caloriesRaw = decoded['calories']?.toString() ?? '0';
  final proteinRaw = decoded['protein']?.toString() ?? '0';
  final fatRaw = decoded['fat']?.toString() ?? '0';
  final carbsRaw = decoded['carbs']?.toString() ?? '0';

  return <String, dynamic>{
    'calories': _parseNumberFromLabel(caloriesRaw).round(),
    'protein': _parseNumberFromLabel(proteinRaw),
    'fat': _parseNumberFromLabel(fatRaw),
    'carbs': _parseNumberFromLabel(carbsRaw),
    'fiber': 0,
    'sugar': 0,
  };
}

double _parseNumberFromLabel(String value) {
  final match = RegExp(r'[-+]?[0-9]*\.?[0-9]+').firstMatch(value);
  if (match == null) return 0;
  return double.tryParse(match.group(0) ?? '') ?? 0;
}

bool _nutritionEmpty(Map<String, dynamic> nutrition) {
  final calories = (nutrition['calories'] as num?)?.toDouble() ?? 0;
  final protein = (nutrition['protein'] as num?)?.toDouble() ?? 0;
  final fat = (nutrition['fat'] as num?)?.toDouble() ?? 0;
  final carbs = (nutrition['carbs'] as num?)?.toDouble() ?? 0;
  return calories <= 0 && protein <= 0 && fat <= 0 && carbs <= 0;
}

Future<bool> _upsertRecipe({
  required http.Client client,
  required String supabaseUrl,
  required String serviceRoleKey,
  required Map<String, dynamic> payload,
}) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/recipes').replace(
    queryParameters: <String, String>{
      'on_conflict': 'api_id',
      'select': 'id,api_id,title',
    },
  );
  final response = await client.post(
    uri,
    headers: <String, String>{
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=representation',
    },
    body: jsonEncode(payload),
  );

  if (response.statusCode >= 200 && response.statusCode < 300) {
    return true;
  }
  stderr.writeln(
    'Supabase upsert failed (${response.statusCode}) for ${payload['title']}: ${response.body}',
  );
  return false;
}

String _stripHtml(String input) {
  final noTags = input.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return noTags.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
