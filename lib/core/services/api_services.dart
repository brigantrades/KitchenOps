import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:plateplan/core/config/env.dart';
import 'package:plateplan/core/debug/share_import_debug_log.dart';
import 'package:plateplan/core/models/app_models.dart';
import 'package:plateplan/core/models/instagram_recipe_import.dart';
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
  /// Shared recipe-import guidance so Gemini can split sauce/icing into `embedded_sauce`.
  static const String _kRecipeImportEmbeddedSauceSchema = r'''
Optional top-level key "embedded_sauce": use null or omit when there is no separate sauce block; otherwise an object with:
- "title" (string, optional): e.g. "Lemon butter sauce", "Vanilla icing"
- "ingredients": same array shape as root [{ "name", "amount", "unit" }]
- "instructions": array of strings (steps only for the sauce, dressing, glaze, icing, frosting, aioli, or similar sub-recipe)

Sauce rules:
- If the source clearly separates Sauce, Dressing, Glaze, Icing, Frosting, or Aioli (or similar) with its own ingredient list and/or steps, put that content in "embedded_sauce" and keep the main dish in root "ingredients" and "instructions".
- Do not duplicate the same lines in both places.
- Food blogs often use subheadings such as "For the air fryer tofu" vs "For the orange sauce", or "#### Orange Sauce:" under Ingredients, and separate instruction sections (e.g. "Orange Sauce" then "Air Fryer Tofu"). In those cases root "ingredients" must be ONLY the main component (e.g. tofu and its coating), and ALL sauce-related ingredients and sauce-only steps belong in "embedded_sauce" (use a clear title like "Orange sauce").
''';

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

  /// Models tried for cookbook photo import (multimodal); order matches text fallbacks.
  static const List<String> _visionFallbackModels = <String>[
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];

  /// Structured output for Instagram import — avoids prose refusals that break JSON parsing.
  static final Schema _kInstagramRecipeImportSchema = Schema.object(
    properties: {
      'title': Schema.string(
        description:
            'Recipe title: first non-empty caption line naming the dish, as written.',
      ),
      'description': Schema.string(
        description: 'Short summary; omit or empty if none.',
        nullable: true,
      ),
      'ingredients': Schema.array(
        items: Schema.object(
          properties: {
            'name': Schema.string(),
            'amount': Schema.string(
              nullable: true,
              description: 'Quantity text or empty',
            ),
            'unit': Schema.string(nullable: true),
          },
          requiredProperties: ['name'],
        ),
      ),
      'instructions': Schema.array(items: Schema.string()),
      'servings': Schema.number(description: 'Servings (whole number)'),
      'prep_time': Schema.integer(nullable: true),
      'cook_time': Schema.integer(nullable: true),
      'meal_type': Schema.string(
        description: 'e.g. breakfast, lunch, dinner, snack, dessert',
      ),
      'cuisine_tags': Schema.array(items: Schema.string()),
    },
    requiredProperties: [
      'title',
      'ingredients',
      'instructions',
      'servings',
      'meal_type',
      'cuisine_tags',
    ],
  );

  /// Instagram-only: prefer JSON MIME type + schema so the model cannot return refusal prose.
  Future<GenerateContentResponse?> _generateInstagramRecipeImportWithFallback(
      String prompt) async {
    if (_model == null) return null;

    Future<GenerateContentResponse?> tryOnce(
      GenerativeModel model,
      GenerationConfig config,
      String modeLabel,
    ) async {
      try {
        final r = await model.generateContent(
          [Content.text(prompt)],
          generationConfig: config,
        );
        _lastGenerateFailure = null;
        // #region agent log
        agentDebugLogShareImport(
          hypothesisId: 'H5',
          location: 'GeminiService._generateInstagramRecipeImportWithFallback',
          message: 'instagram_json_generation_ok',
          data: {'mode': modeLabel},
        );
        // #endregion
        return r;
      } catch (e) {
        final err = e.toString();
        // #region agent log
        agentDebugLogShareImport(
          hypothesisId: 'H1',
          location: 'GeminiService._generateInstagramRecipeImportWithFallback',
          message: 'instagram_generate_attempt_failed',
          data: {
            'mode': modeLabel,
            'errSnippet': err.length > 300 ? err.substring(0, 300) : err,
          },
        );
        // #endregion
        return null;
      }
    }

    final withSchema = GenerationConfig(
      temperature: 0.2,
      responseMimeType: 'application/json',
      responseSchema: _kInstagramRecipeImportSchema,
    );
    final jsonOnly = GenerationConfig(
      temperature: 0.2,
      responseMimeType: 'application/json',
    );

    GenerateContentResponse? r;

    r = await tryOnce(_model, withSchema, 'json_schema_primary');
    if (r != null) return r;
    r = await tryOnce(_model, jsonOnly, 'json_mime_primary');
    if (r != null) return r;

    for (final modelName in _fallbackModels) {
      final model = GenerativeModel(model: modelName, apiKey: _apiKey);
      r = await tryOnce(model, withSchema, 'json_schema_$modelName');
      if (r != null) return r;
      r = await tryOnce(model, jsonOnly, 'json_mime_$modelName');
      if (r != null) return r;
    }

    // #region agent log
    agentDebugLogShareImport(
      hypothesisId: 'H3',
      location: 'GeminiService._generateInstagramRecipeImportWithFallback',
      message: 'instagram_falling_back_plain_text',
      data: const {},
    );
    // #endregion
    return _generateWithFallback(prompt);
  }

  /// Instagram-only (image): prefer JSON MIME type + schema for multimodal caption screenshots.
  Future<GenerateContentResponse?>
      _generateInstagramRecipeImportMultimodalWithFallback({
    required String prompt,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    if (_model == null) return null;

    Future<GenerateContentResponse?> tryOnce(
      GenerativeModel model,
      GenerationConfig config,
      String modeLabel,
    ) async {
      try {
        final userContent = Content.multi([
          TextPart(prompt),
          DataPart(mimeType, imageBytes),
        ]);
        final r = await model.generateContent(
          [userContent],
          generationConfig: config,
        );
        _lastGenerateFailure = null;
        agentDebugLogShareImport(
          hypothesisId: 'H5',
          location:
              'GeminiService._generateInstagramRecipeImportMultimodalWithFallback',
          message: 'instagram_multimodal_json_generation_ok',
          data: {'mode': modeLabel},
        );
        return r;
      } catch (e) {
        final err = e.toString();
        agentDebugLogShareImport(
          hypothesisId: 'H1',
          location:
              'GeminiService._generateInstagramRecipeImportMultimodalWithFallback',
          message: 'instagram_multimodal_generate_attempt_failed',
          data: {
            'mode': modeLabel,
            'errSnippet': err.length > 300 ? err.substring(0, 300) : err,
          },
        );
        return null;
      }
    }

    final withSchema = GenerationConfig(
      temperature: 0.2,
      responseMimeType: 'application/json',
      responseSchema: _kInstagramRecipeImportSchema,
    );
    final jsonOnly = GenerationConfig(
      temperature: 0.2,
      responseMimeType: 'application/json',
    );

    GenerateContentResponse? r;

    r = await tryOnce(_model, withSchema, 'json_schema_primary');
    if (r != null) return r;
    r = await tryOnce(_model, jsonOnly, 'json_mime_primary');
    if (r != null) return r;

    for (final modelName in _visionFallbackModels) {
      final model = GenerativeModel(model: modelName, apiKey: _apiKey);
      r = await tryOnce(model, withSchema, 'json_schema_$modelName');
      if (r != null) return r;
      r = await tryOnce(model, jsonOnly, 'json_mime_$modelName');
      if (r != null) return r;
    }

    agentDebugLogShareImport(
      hypothesisId: 'H3',
      location:
          'GeminiService._generateInstagramRecipeImportMultimodalWithFallback',
      message: 'instagram_multimodal_falling_back_plain_text',
      data: const {},
    );
    return _generateMultimodalWithFallback(
      prompt: prompt,
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
  }

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

  Future<GenerateContentResponse?> _generateMultimodalWithFallback({
    required String prompt,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    if (_model == null) return null;
    final userContent = Content.multi([
      TextPart(prompt),
      DataPart(mimeType, imageBytes),
    ]);
    Future<GenerateContentResponse> callModel(GenerativeModel model) {
      return model.generateContent([userContent]);
    }
    try {
      final r = await callModel(_model);
      _lastGenerateFailure = null;
      return r;
    } catch (e) {
      final err = e.toString();
      for (final modelName in _visionFallbackModels) {
        try {
          final model = GenerativeModel(model: modelName, apiKey: _apiKey);
          final r = await callModel(model);
          _lastGenerateFailure = null;
          return r;
        } catch (_) {
          continue;
        }
      }
      _lastGenerateFailure = err;
      return null;
    }
  }

  bool _looksValidRecipeImportJson(Map<String, dynamic> m) {
    final ingredients = m['ingredients'];
    final instructions = m['instructions'];
    final hasIngredients = ingredients is List && ingredients.isNotEmpty;
    final hasInstructions = instructions is List && instructions.isNotEmpty;
    return hasIngredients || hasInstructions;
  }

  /// Reads model text without throwing when output is blocked (recitation/safety).
  String? _safeResponseText(GenerateContentResponse response) {
    if (response.candidates.isEmpty) {
      final pf = response.promptFeedback;
      if (pf != null) {
        final br = pf.blockReason;
        final msg = pf.blockReasonMessage;
        _lastGenerateFailure = br != null
            ? 'Prompt blocked: $br${msg != null && msg.isNotEmpty ? ' — $msg' : ''}'
            : 'Prompt blocked.';
      }
      return null;
    }
    final c = response.candidates.first;
    if (c.finishReason == FinishReason.recitation ||
        c.finishReason == FinishReason.safety) {
      _lastGenerateFailure = c.finishReason == FinishReason.recitation
          ? 'First pass looked too close to published text (recitation). Trying a paraphrased extraction…'
          : 'Output blocked for safety.';
      return null;
    }
    try {
      return c.text;
    } on GenerativeAIException catch (e) {
      _lastGenerateFailure = e.message;
      return null;
    }
  }

  /// Decodes Gemini output and returns a recipe map if ingredients or steps exist.
  Map<String, dynamic>? _parseRecipeImportJsonFromModelText(String raw) {
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
    if (asMap != null && _looksValidRecipeImportJson(asMap)) {
      return asMap;
    }
    return null;
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
    final caption = captionForInstagramGemini(sharedContent);
    if (caption.trim().isEmpty) return null;
    final prompt = '''
Extract a recipe from the Instagram caption below. Link URLs were removed where possible; if the text is only a link, treat that as the full input.
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
  "cuisine_tags": array of strings,
  "embedded_sauce": null or { "title": string (optional), "ingredients": same as root, "instructions": array of strings }
}
$_kRecipeImportEmbeddedSauceSchema
Title:
- Set "title" to the first non-empty line of the caption (the dish name as written there). If that line is only hashtags or not a dish name, use the next line that names the dish.
- Never invent a different recipe name: words in "title" must appear in the caption (e.g. do not use "pesto", "chicken", or "creamy" in the title if those words do not appear in the caption).

Output rules (critical — must follow):
- Return ONLY a single JSON object. No markdown code fences, no commentary, no text before or after the JSON.
- Do NOT refuse, apologize, or say you cannot access websites or URLs. You are not fetching the web; you only see the caption text below as provided by the user's device.
- If the caption is only an Instagram URL with no recipe lines, still return valid JSON: set "title" to a short placeholder like "Instagram reel" or infer from path tokens; "ingredients": []; "instructions": ["Open the post in Instagram, tap … → Copy the full caption, then paste it into the app and import again."].

Verbatim rules (when the caption contains recipe text):
- Use ONLY the caption text below. Every ingredient and instruction must appear in that text. Do not add ingredients not written in the caption. Do not substitute proteins or rename the dish.
- Do not invent viral or generic titles that are not in the caption.
- If the caption is incomplete, extract what is present; omit missing parts rather than guessing.
- Split each ingredient into name / amount / unit when the caption allows; if a line is messy, keep the wording in "name".

Caption:
$caption

Serving size guidance:
- Infer servings from ingredient quantities and yield language (e.g. "serves 4", tray size, pan size, portions).
- Return an integer servings estimate even if not explicit.
- If uncertain, choose the most plausible household size from {2, 3, 4, 6}.
''';
    final response = await _generateInstagramRecipeImportWithFallback(prompt);
    if (response == null) {
      debugPrint(
        'Gemini Instagram import: generateContent returned null (API key, '
        'network, quota, or all fallback models failed). Check GEMINI_API_KEY '
        'and device network.',
      );
      return null;
    }
    final raw = (response.text ?? '').trim();
    final asMap = _parseRecipeImportJsonFromModelText(raw);
    if (asMap != null) {
      // #region agent log
      final ings = asMap['ingredients'];
      var jsonChicken = false;
      var jsonFish = false;
      var ingCount = 0;
      if (ings is List) {
        ingCount = ings.length;
        for (final e in ings) {
          if (e is! Map) continue;
          final n = (e['name'] ?? '').toString().toLowerCase();
          if (n.contains('chicken')) jsonChicken = true;
          if (n.contains('fish') ||
              n.contains('cod') ||
              n.contains('tilapia') ||
              n.contains('haddock') ||
              n.contains('salmon')) {
            jsonFish = true;
          }
        }
      }
      agentDebugLogShareImport(
        hypothesisId: 'H2',
        location: 'GeminiService.extractRecipeFromInstagramContent',
        message: 'gemini_parsed_json_protein_flags',
        data: {
          'ingredientCount': ingCount,
          'jsonHasChicken': jsonChicken,
          'jsonHasFish': jsonFish,
          'titleLen': (asMap['title'] ?? '').toString().length,
        },
      );
      // #endregion
      return asMap;
    }

    final decoded = _decodeJsonSafe(raw.isEmpty ? '{}' : raw);
    // Truncated raw response (refusals, markdown, empty JSON, wrong shape).
    final snippet = raw.isEmpty
        ? '<empty response.text>'
        : (raw.length <= 800 ? raw : raw.substring(0, 800));
    debugPrint('Gemini Instagram import: invalid or empty recipe JSON.');
    debugPrint('Gemini raw (first 800 chars): $snippet');
    final fallbackMap = decoded is Map<String, dynamic> ? decoded : null;
    if (fallbackMap != null) {
      debugPrint(
        'Gemini decoded keys: ${fallbackMap.keys.toList()} '
        '(ingredients/instructions missing or empty?)',
      );
    } else {
      debugPrint(
        'Gemini decode result type: ${decoded.runtimeType} (expected object or array of object)',
      );
    }
    // #region agent log
    agentDebugLogShareImport(
      hypothesisId: 'H4',
      location: 'GeminiService.extractRecipeFromInstagramContent',
      message: 'gemini_map_null_or_unparsed',
      data: {
        'rawLen': raw.length,
        'trimmedSharedLen': trimmed.length,
        'captionLen': caption.length,
      },
    );
    // #endregion
    return null;
  }

  /// Recipe website: plain text from fetched HTML (same JSON shape as Instagram import).
  Future<Map<String, dynamic>?> extractRecipeFromWebPageText({
    required String canonicalUrl,
    required String pagePlainText,
    String? userNotes,
  }) async {
    if (_model == null) return null;
    final url = canonicalUrl.trim();
    final body = pagePlainText.trim();
    if (url.isEmpty || body.isEmpty) return null;
    final notes = userNotes?.trim();
    final notesBlock = (notes != null && notes.isNotEmpty)
        ? '\nUser-added notes (may clarify missing details):\n$notes\n'
        : '';
    final prompt = '''
Extract a recipe from the plain text below, taken from this web page:
$url
$notesBlock
The text is from an HTML page (navigation, ads, and chrome may be mixed in). Ignore site navigation, "jump to recipe", newsletter prompts, comments, and unrelated sections. Focus on ingredients and cooking steps for one dish.

When the page splits ingredients or instructions into a main item and a separate sauce, glaze, or dressing (common on recipe blogs), you MUST populate "embedded_sauce" with the sauce part and keep the primary dish in the root arrays. Never put sauce ingredients only in root "ingredients" when the source labeled them as a distinct block.

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
  "cuisine_tags": array of strings,
  "embedded_sauce": null or { "title": string (optional), "ingredients": same as root, "instructions": array of strings }
}
$_kRecipeImportEmbeddedSauceSchema

Rules (critical):
- Return ONLY a single JSON object. No markdown code fences, no commentary.
- Use ONLY information supported by the plain text below. Do not invent ingredients or steps.
- If the text does not contain a real recipe (e.g. only navigation or paywall), return valid JSON with "title": "Could not read recipe", "ingredients": [], "instructions": ["Open the page in a browser, copy the full recipe text, then use Add recipe manually or try again."].

Plain text:
$body
''';
    final response = await _generateInstagramRecipeImportWithFallback(prompt);
    if (response == null) {
      debugPrint(
        'Gemini web import: generateContent returned null (API key, network, quota).',
      );
      return null;
    }
    final raw = (response.text ?? '').trim();
    final asMap = _parseRecipeImportJsonFromModelText(raw);
    if (asMap != null) {
      agentDebugLogShareImport(
        hypothesisId: 'H2',
        location: 'GeminiService.extractRecipeFromWebPageText',
        message: 'web_import_json_ok',
        data: {
          'titleLen': (asMap['title'] ?? '').toString().length,
          'ingCount': (asMap['ingredients'] is List)
              ? (asMap['ingredients'] as List).length
              : 0,
        },
      );
      return asMap;
    }
    debugPrint('Gemini web import: invalid or empty recipe JSON.');
    return null;
  }

  /// Instagram share import (image-only): extract recipe from a shared screenshot/preview image.
  Future<Map<String, dynamic>?> extractRecipeFromInstagramShareImage({
    required Uint8List imageBytes,
    required String mimeType,
    String? sharedTextHint,
  }) async {
    if (_model == null) return null;
    if (imageBytes.isEmpty) return null;
    final hint = (sharedTextHint ?? '').trim();
    final prompt = '''
Extract a recipe from the attached Instagram share image. The image may contain the caption,
ingredients, and/or directions overlaid or in the post description UI.

Return ONLY valid JSON with these keys:
{
  "title": string,
  "description": string (short summary),
  "ingredients": array of objects [{ "name": string, "amount": string, "unit": string }],
  "instructions": array of strings (each step as one string),
  "servings": number (default 2 if missing),
  "prep_time": number (minutes, null if missing),
  "cook_time": number (minutes, null if missing),
  "meal_type": string (best guess),
  "cuisine_tags": array of strings,
  "embedded_sauce": null or { "title": string (optional), "ingredients": same as root, "instructions": array of strings }
}
$_kRecipeImportEmbeddedSauceSchema

Rules:
- Use ONLY text visible in the image. Do not invent ingredients or steps.
- If the image does not include recipe content (just a photo), return valid JSON with:
  "ingredients": [], "instructions": ["Open the post in Instagram, tap … → Copy the full caption, then paste it into the app and import again."].

Optional hint text from the share sheet (may be empty / noisy):
$hint
''';

    final response = await _generateInstagramRecipeImportMultimodalWithFallback(
      prompt: prompt,
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
    if (response == null) return null;
    final raw = (response.text ?? '').trim();
    final asMap = _parseRecipeImportJsonFromModelText(raw);
    if (asMap != null) return asMap;

    agentDebugLogShareImport(
      hypothesisId: 'H4',
      location: 'GeminiService.extractRecipeFromInstagramShareImage',
      message: 'gemini_multimodal_map_null_or_unparsed',
      data: {
        'rawLen': raw.length,
        'hintLen': hint.length,
        'imageBytesLen': imageBytes.length,
      },
    );
    return null;
  }

  static const String _kBookScanPromptPrimary = '''
You are an expert chef and recipe extractor.
Extract a complete, clean recipe from the attached photo of a cookbook page.
Return ONLY valid JSON (no extra text) with these exact keys:
{
  "title": string,
  "description": string (short summary if present),
  "ingredients": array of objects [ { "name": string, "amount": string, "unit": string } ],
  "instructions": array of strings (each step as one clean string),
  "servings": number (default 2 if missing),
  "prep_time": number (minutes, null if missing),
  "cook_time": number (minutes, null if missing),
  "meal_type": string (best guess: breakfast, lunch, dinner, snack, dessert),
  "cuisine_tags": array of strings,
  "embedded_sauce": null or { "title": string (optional), "ingredients": same as root, "instructions": array of strings }
}
$_kRecipeImportEmbeddedSauceSchema
Ingredient rules (strict):
- "name": ingredient name only — no leading quantities or units.
- "amount": numeric quantity only (a number or numeric string) — no unit words in this field.
- "unit": one canonical token when possible from: g, kg, mg, ml, l, cup, tbsp, tsp, oz, lb, fl oz, pt, qt, gal, piece. Use "" for qualitative lines or when unclear.
Handle messy text, columns, handwriting, or poor lighting. Fix any OCR-like errors.
Infer servings from yield language when visible; if uncertain, choose from {2, 3, 4, 6}.
''';

  /// Second pass when the API blocks verbatim transcription (recitation).
  static const String _kBookScanPromptParaphrase = '''
You help a home cook digitize their own recipe notes for personal use.
Read the recipe in the photo and express it in your own words: paraphrase ingredient lines
and cooking steps (do not reproduce long copyrighted passages verbatim).
Return ONLY valid JSON (no extra text) with these exact keys:
{
  "title": string,
  "description": string (short summary if present),
  "ingredients": array of objects [ { "name": string, "amount": string, "unit": string } ],
  "instructions": array of strings (each step as one clean string),
  "servings": number (default 2 if missing),
  "prep_time": number (minutes, null if missing),
  "cook_time": number (minutes, null if missing),
  "meal_type": string (best guess: breakfast, lunch, dinner, snack, dessert),
  "cuisine_tags": array of strings,
  "embedded_sauce": null or { "title": string (optional), "ingredients": same as root, "instructions": array of strings }
}
$_kRecipeImportEmbeddedSauceSchema
Ingredient rules (strict):
- "name": ingredient name only — no leading quantities or units.
- "amount": numeric quantity only — no unit words in this field.
- "unit": one canonical token when possible from: g, kg, mg, ml, l, cup, tbsp, tsp, oz, lb, fl oz, pt, qt, gal, piece. Use "" for qualitative lines or when unclear.
Infer servings from yield language when visible; if uncertain, choose from {2, 3, 4, 6}.
''';

  /// Cookbook page photo: returns decoded JSON map or null if Gemini is disabled or parsing fails.
  Future<Map<String, dynamic>?> extractRecipeFromBookPhoto({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    if (_model == null) return null;
    if (imageBytes.isEmpty) return null;

    const prompts = <String>[
      _kBookScanPromptPrimary,
      _kBookScanPromptParaphrase,
    ];

    for (var attempt = 0; attempt < prompts.length; attempt++) {
      final response = await _generateMultimodalWithFallback(
        prompt: prompts[attempt],
        imageBytes: imageBytes,
        mimeType: mimeType,
      );
      if (response == null) {
        debugPrint(
          'Gemini book scan: attempt ${attempt + 1} generateContent returned null.',
        );
        continue;
      }
      final raw = _safeResponseText(response)?.trim();
      if (raw == null || raw.isEmpty) {
        debugPrint(
          'Gemini book scan: attempt ${attempt + 1} blocked or empty text.',
        );
        continue;
      }
      final asMap = _parseRecipeImportJsonFromModelText(raw);
      if (asMap != null) {
        return asMap;
      }
      final snippet =
          raw.length <= 800 ? raw : raw.substring(0, 800);
      debugPrint('Gemini book scan: attempt ${attempt + 1} invalid JSON.');
      debugPrint('Gemini raw (first 800 chars): $snippet');
      _lastGenerateFailure = 'Could not parse recipe from model output.';
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
