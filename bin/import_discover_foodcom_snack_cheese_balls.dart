import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Imports public Appetizer (meal_type snack) recipes from Food.com's
/// cheese ball ideas page — aligns with Discover "Cheese Balls"
/// (`snack-cheese-balls`).
///
/// Source: https://www.food.com/ideas/cheese-ball-recipes-6797
///
/// Hub pages embed extra `/recipe/` links; JSON-LD is filtered to cheese-ball picks.
///
/// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SEED_USER_ID
/// Args: [--execute] [--limit=N]  (default limit 32 — hub lists ~30)
///
/// Dry run writes tmp/foodcom_snack_cheese_balls_review.csv.

class ReviewRow {
  const ReviewRow({
    required this.url,
    required this.title,
    required this.apiId,
    required this.warnings,
  });

  final String url;
  final String title;
  final String apiId;
  final List<String> warnings;
}

const _ideasPageUrl =
    'https://www.food.com/ideas/cheese-ball-recipes-6797';

/// Substrings for JSON-LD gating (Food.com hub is curated; list errs on inclusive).
const _cheeseBallSignals = <String>[
  'cheese ball',
  'cheeseball',
  'cheese balls',
  'cream cheese',
  'neufchatel',
  'port wine cheese',
  'braunschweiger ball',
  'pinecone cheese',
  'goat cheese',
  'havarti',
  'cheddar',
];

/// Subset aligned with discover_repository meat/fish checks for vegetarian tagging.
const _meatKeywords = <String>[
  'chicken', 'beef', 'pork', 'lamb', 'turkey', 'duck', 'veal', 'venison',
  'bison', 'bacon', 'sausage', 'ham', 'prosciutto', 'salami', 'pepperoni',
  'chorizo', 'steak', 'ground meat', 'meatball', 'ribs', 'roast',
  'braised', 'pulled pork', 'ground turkey', 'ground beef', 'lox',
  'nova lox', 'belly lox', 'smoked salmon', 'pastrami',
  'brisket', 'andouille', 'kielbasa',
];

const _fishKeywords = <String>[
  'salmon', 'tuna', 'shrimp', 'prawn', 'cod', 'tilapia', 'halibut', 'trout',
  'bass', 'anchovy', 'sardine', 'crab', 'lobster', 'scallop', 'mussel',
  'clam', 'oyster', 'squid', 'calamari', 'seafood', 'mahi', 'swordfish',
];

const _dairyEggKeywords = <String>[
  'egg', 'cheese', 'butter', 'cream', 'milk', 'yogurt', 'whey',
  'crème', 'creme fraiche', 'sour cream', 'mayo', 'mayonnaise',
];

Future<void> main(List<String> args) async {
  final supabaseUrl = _env('SUPABASE_URL');
  final serviceRole = _env('SUPABASE_SERVICE_ROLE_KEY');
  final seedUserId = _env('SEED_USER_ID');
  final execute = args.contains('--execute');
  final limit = _parseLimit(args) ?? 32;

  if (supabaseUrl == null || serviceRole == null || seedUserId == null) {
    stderr.writeln(
      'Missing env vars. Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SEED_USER_ID',
    );
    exitCode = 64;
    return;
  }

  final client = http.Client();
  final reviewRows = <ReviewRow>[];
  try {
    var success = 0;
    var failed = 0;
    var skipped = 0;

    Set<String> existingTitles;
    try {
      existingTitles = await _fetchExistingPublicTitles(
        client: client,
        supabaseUrl: supabaseUrl,
        serviceRole: serviceRole,
      );
      stdout.writeln('Existing public catalog titles loaded: ${existingTitles.length}');
    } catch (e) {
      stderr.writeln('Warning: could not prefetch public titles: $e');
      existingTitles = <String>{};
    }

    final urls = await _discoverRegionalCheeseBallUrls(client, limit: limit);
    stdout.writeln('Import target count: ${urls.length}');

    for (final url in urls) {
      stdout.writeln('\n== Processing $url ==');
      try {
        final jsonLd = await _fetchRecipeJsonLd(client, url);
        final warnings = <String>[];
        final payload = _toPayload(
          jsonLd: jsonLd,
          sourceUrl: url,
          seedUserId: seedUserId,
          warnings: warnings,
        );

        _validatePayload(payload);
        final titleNorm = _normalizeTitle(payload['title']?.toString() ?? '');
        if (existingTitles.contains(titleNorm)) {
          warnings.add('duplicate_title_skip');
          skipped += 1;
          stdout.writeln('Skip (duplicate title): ${payload['title']}');
          reviewRows.add(
            ReviewRow(
              url: url,
              title: payload['title']?.toString() ?? '',
              apiId: payload['api_id']?.toString() ?? '',
              warnings: warnings,
            ),
          );
          continue;
        }

        stdout.writeln('Parsed: ${payload['title']}');
        reviewRows.add(
          ReviewRow(
            url: url,
            title: payload['title']?.toString() ?? '',
            apiId: payload['api_id']?.toString() ?? '',
            warnings: warnings,
          ),
        );

        if (execute) {
          final ok = await _upsertRecipe(
            client: client,
            supabaseUrl: supabaseUrl,
            serviceRole: serviceRole,
            payload: payload,
          );
          if (ok) {
            success += 1;
            existingTitles.add(titleNorm);
            stdout.writeln('Upserted successfully.');
          } else {
            failed += 1;
          }
        } else {
          existingTitles.add(titleNorm);
        }
      } catch (error) {
        failed += 1;
        stderr.writeln('Failed for $url: $error');
        reviewRows.add(
          ReviewRow(
            url: url,
            title: '',
            apiId: '',
            warnings: <String>['parse_failed:$error'],
          ),
        );
      }
    }

    final reviewPath = await _writeReviewCsv(reviewRows);
    stdout.writeln('\nReview CSV: $reviewPath');
    if (!execute) {
      stdout.writeln(
        'Dry run complete. Re-run with --execute to import recipes.',
      );
    }
    stdout.writeln('Success: $success, Skipped: $skipped, Failed: $failed');
  } finally {
    client.close();
  }
}

String _normalizeTitle(String title) => title.trim().toLowerCase();

Future<Set<String>> _fetchExistingPublicTitles({
  required http.Client client,
  required String supabaseUrl,
  required String serviceRole,
}) async {
  final out = <String>{};
  var offset = 0;
  const page = 1000;
  while (true) {
    final uri = Uri.parse('$supabaseUrl/rest/v1/recipes').replace(
      queryParameters: <String, String>{
        'select': 'title',
        'visibility': 'eq.public',
      },
    );
    final response = await client.get(
      uri,
      headers: <String, String>{
        'apikey': serviceRole,
        'Authorization': 'Bearer $serviceRole',
        'Range': '$offset-${offset + page - 1}',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Title fetch failed (${response.statusCode}): ${response.body}',
      );
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        final t = row['title']?.toString() ?? '';
        if (t.isNotEmpty) out.add(_normalizeTitle(t));
      }
    }
    if (rows.length < page) break;
    offset += page;
  }
  return out;
}

int? _parseLimit(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--limit' && i + 1 < args.length) {
      return int.tryParse(args[i + 1]);
    }
    if (args[i].startsWith('--limit=')) {
      return int.tryParse(args[i].split('=').last);
    }
  }
  return null;
}

Future<List<String>> _discoverRegionalCheeseBallUrls(
  http.Client client, {
  required int limit,
}) async {
  final response = await client.get(Uri.parse(_ideasPageUrl));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Ideas page fetch failed (${response.statusCode})');
  }
  final orderedUrls = _extractFoodComRecipeUrlsInDocumentOrder(response.body);
  final reviewed = <String>{};
  final seenRecipeKeys = <String>{};
  final discovered = <String>[];

  for (final candidate in orderedUrls) {
    if (discovered.length >= limit) break;
    if (reviewed.contains(candidate)) continue;
    reviewed.add(candidate);
    final key = _recipeIdFromUrl(candidate) ?? candidate;
    if (seenRecipeKeys.contains(key)) continue;
    try {
      final jsonLd = await _fetchRecipeJsonLd(client, candidate);
      if (!_isLikelyRegionalCheeseBallRecipe(jsonLd)) continue;
      discovered.add(candidate);
      seenRecipeKeys.add(key);
    } catch (_) {
      continue;
    }
  }

  if (discovered.isEmpty) {
    throw Exception(
      'No Food.com recipe URLs discovered. The ideas page may require '
      'different scraping or a manual URL list.',
    );
  }
  return discovered;
}

/// First occurrence order (hub main list before footer “related” when DOM allows).
List<String> _extractFoodComRecipeUrlsInDocumentOrder(String html) {
  final hits = <MapEntry<int, String>>[];
  final abs = RegExp(
    r'https://www\.food\.com/recipe/[a-z0-9\-]+',
    caseSensitive: false,
  );
  for (final m in abs.allMatches(html)) {
    final raw = m.group(0)?.trim();
    if (raw == null || raw.isEmpty) continue;
    hits.add(MapEntry(m.start, raw.toLowerCase()));
  }
  final rel = RegExp(
    r'href="(/recipe/[a-z0-9\-]+)"',
    caseSensitive: false,
  );
  for (final m in rel.allMatches(html)) {
    final path = m.group(1)?.trim();
    if (path == null || path.isEmpty) continue;
    hits.add(MapEntry(m.start, 'https://www.food.com$path'.toLowerCase()));
  }
  hits.sort((a, b) => a.key.compareTo(b.key));
  final out = <String>[];
  final seen = <String>{};
  for (final e in hits) {
    if (seen.add(e.value)) out.add(e.value);
  }
  return out;
}

Future<Map<String, dynamic>> _fetchRecipeJsonLd(
  http.Client client,
  String url,
) async {
  final response = await client.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Fetch failed (${response.statusCode})');
  }
  final html = response.body;
  final scripts = RegExp(
    r'<script[^>]*type="application/ld\+json"[^>]*>([\s\S]*?)</script>',
    caseSensitive: false,
  ).allMatches(html);

  for (final match in scripts) {
    final raw = match.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      continue;
    }
    final recipe = _findRecipeNode(decoded);
    if (recipe != null) return recipe;
  }
  throw Exception('No Recipe JSON-LD found');
}

Map<String, dynamic>? _findRecipeNode(dynamic node) {
  if (node is Map<String, dynamic>) {
    final type = node['@type'];
    if ((type is String && type.toLowerCase() == 'recipe') ||
        (type is List &&
            type.any((t) => t.toString().toLowerCase() == 'recipe'))) {
      return node;
    }
    if (node.containsKey('@graph') && node['@graph'] is List) {
      for (final child in (node['@graph'] as List)) {
        final found = _findRecipeNode(child);
        if (found != null) return found;
      }
    }
  } else if (node is List) {
    for (final child in node) {
      final found = _findRecipeNode(child);
      if (found != null) return found;
    }
  }
  return null;
}

/// Ideas pages include unrelated `/recipe/` links; keep cheese-ball picks.
bool _isLikelyRegionalCheeseBallRecipe(Map<String, dynamic> jsonLd) {
  final title = (jsonLd['name']?.toString() ?? '').toLowerCase();
  final desc = (jsonLd['description']?.toString() ?? '').toLowerCase();
  final keywords = (jsonLd['keywords']?.toString() ?? '').toLowerCase();
  final cat = (jsonLd['recipeCategory']?.toString() ?? '').toLowerCase();
  final cuisine = (jsonLd['recipeCuisine']?.toString() ?? '').toLowerCase();
  final haystack = '$title $desc $keywords $cat $cuisine';

  for (final s in _cheeseBallSignals) {
    if (haystack.contains(s)) return true;
  }

  return false;
}

/// Tags tuned for [kBrowseCategories] `snack-cheese-balls` plus dietary filters.
List<String> _buildCuisineTags({
  required Map<String, dynamic> jsonLd,
  required List<Map<String, dynamic>> ingredients,
  required String title,
}) {
  final tags = <String>{};

  final t = title.toLowerCase();
  final desc = (jsonLd['description']?.toString() ?? '').toLowerCase();
  final cuisine = (jsonLd['recipeCuisine']?.toString() ?? '').toLowerCase();
  final keywords = (jsonLd['keywords']?.toString() ?? '').toLowerCase();
  final ingHaystack = ingredients
      .map((m) => m['name']?.toString() ?? '')
      .join(' ')
      .toLowerCase();
  final haystack = '$t $desc $cuisine $keywords $ingHaystack';

  if (haystack.contains('cheese ball') || haystack.contains('cheeseball')) {
    tags.add('cheese ball');
    tags.add('cheeseball');
  }
  if (haystack.contains('cream cheese') || haystack.contains('neufchatel')) {
    tags.add('cream cheese');
  }
  if (haystack.contains('cheddar')) tags.add('cheddar');
  if (haystack.contains('goat cheese') || haystack.contains("goat's cheese")) {
    tags.add('goat cheese');
  }
  if (haystack.contains('pecan')) tags.add('pecan');

  if (tags.isEmpty) {
    tags.add('cheese ball');
  }

  final hasMeat = _meatKeywords.any(haystack.contains);
  final hasFish = _fishKeywords.any(haystack.contains);
  if (!hasMeat && !hasFish) {
    tags.add('vegetarian');
  }

  final hasAnimalProducts = _dairyEggKeywords.any(haystack.contains) ||
      haystack.contains('honey') ||
      haystack.contains('gelatin');
  if (!hasMeat && !hasFish && !hasAnimalProducts) {
    tags.add('vegan');
  }

  return tags.toList()..sort();
}

Map<String, dynamic> _toPayload({
  required Map<String, dynamic> jsonLd,
  required String sourceUrl,
  required String seedUserId,
  required List<String> warnings,
}) {
  final title = _decodeHtmlEntities((jsonLd['name']?.toString() ?? '').trim());
  final description =
      _decodeHtmlEntities((jsonLd['description']?.toString() ?? '').trim());
  var imageUrl = _extractImageUrl(jsonLd['image']);
  final prepMinutes = _durationToMinutes(jsonLd['prepTime']?.toString());
  final cookMinutes = _durationToMinutes(jsonLd['cookTime']?.toString());
  final totalMinutes = _durationToMinutes(jsonLd['totalTime']?.toString());
  final servings = _extractServings(jsonLd['recipeYield']);
  var ingredients = _extractIngredients(jsonLd['recipeIngredient']);
  var instructions = _extractInstructions(jsonLd['recipeInstructions']);
  final nutrition = _extractNutrition(jsonLd['nutrition']);
  final recipeId = _recipeIdFromUrl(sourceUrl);
  final apiId = recipeId != null
      ? 'food_com:$recipeId'
      : 'food_com:${_slugFromUrl(sourceUrl)}';

  var resolvedPrep = prepMinutes;
  var resolvedCook = cookMinutes;
  if ((resolvedPrep + resolvedCook) == 0 && totalMinutes > 0) {
    resolvedPrep = (totalMinutes * 0.4).round();
    resolvedCook = totalMinutes - resolvedPrep;
    warnings.add('defaulted_time_from_total');
  } else if ((resolvedPrep + resolvedCook) == 0) {
    resolvedCook = 15;
    warnings.add('defaulted_time_constant');
  }

  if (imageUrl.isEmpty) {
    imageUrl =
        'https://images.unsplash.com/photo-1574484284002-952d92456975?auto=format&fit=crop&w=1200&q=80';
    warnings.add('defaulted_image');
  }

  if (ingredients.isEmpty) {
    ingredients = <Map<String, dynamic>>[
      const <String, dynamic>{
        'name': 'Ingredients listed on source page',
        'amount': 0,
        'unit': '',
        'category': 'other',
        'qualitative': true,
      }
    ];
    warnings.add('defaulted_ingredients_placeholder');
  }
  if (instructions.length < 2) {
    instructions = <String>[
      '1. Gather ingredients and prep your workspace.',
      '2. Follow source recipe directions and serve.',
    ];
    warnings.add('defaulted_instructions_placeholder');
  }
  if ((nutrition['calories'] as num?) == 0) {
    warnings.add('defaulted_nutrition_missing');
  }

  final cuisineTags = _buildCuisineTags(
    jsonLd: jsonLd,
    ingredients: ingredients,
    title: title.isNotEmpty ? title : _titleFromSlug(_slugFromUrl(sourceUrl)),
  );

  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title.isNotEmpty ? title : _titleFromSlug(_slugFromUrl(sourceUrl)),
    'description': description,
    'servings': servings > 0 ? servings : 2,
    'prep_time': resolvedPrep,
    'cook_time': resolvedCook,
    'meal_type': 'snack',
    'cuisine_tags': cuisineTags,
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url': imageUrl,
    'nutrition': nutrition,
    'nutrition_source': 'source_page_jsonld',
    'visibility': 'public',
    'is_public': true,
    'source': 'food_com',
    'source_url': sourceUrl,
    'api_id': apiId,
  };
}

void _validatePayload(Map<String, dynamic> payload) {
  final title = payload['title']?.toString().trim() ?? '';
  final imageUrl = payload['image_url']?.toString().trim() ?? '';
  final instructions = (payload['instructions'] as List?) ?? const [];
  final ingredients = (payload['ingredients'] as List?) ?? const [];

  if (title.isEmpty) throw Exception('title is empty');
  if (instructions.isEmpty) throw Exception('instructions empty');
  if (ingredients.isEmpty) throw Exception('ingredients empty');
  if (imageUrl.isEmpty) throw Exception('image missing');
}

Future<bool> _upsertRecipe({
  required http.Client client,
  required String supabaseUrl,
  required String serviceRole,
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
      'apikey': serviceRole,
      'Authorization': 'Bearer $serviceRole',
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=representation',
    },
    body: jsonEncode(payload),
  );

  if (response.statusCode >= 200 && response.statusCode < 300) return true;
  stderr.writeln(
    'Upsert failed (${response.statusCode}) for ${payload['title']}: ${response.body}',
  );
  return false;
}

Future<String> _writeReviewCsv(List<ReviewRow> rows) async {
  final dir = Directory('tmp');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  const path = 'tmp/foodcom_snack_cheese_balls_review.csv';
  final buffer = StringBuffer()
    ..writeln('url,title,api_id,warnings');
  for (final row in rows) {
    buffer.writeln(
      '${_csv(row.url)},${_csv(row.title)},${_csv(row.apiId)},${_csv(row.warnings.join(';'))}',
    );
  }
  File(path).writeAsStringSync(buffer.toString());
  return path;
}

String _csv(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String _extractImageUrl(dynamic imageNode) {
  if (imageNode is String) return imageNode;
  if (imageNode is List && imageNode.isNotEmpty) {
    final first = imageNode.first;
    if (first is String) return first;
    if (first is Map<String, dynamic>) {
      return (first['url']?.toString() ?? '').trim();
    }
  }
  if (imageNode is Map<String, dynamic>) {
    return (imageNode['url']?.toString() ?? '').trim();
  }
  return '';
}

int _extractServings(dynamic recipeYield) {
  if (recipeYield == null) return 0;
  final text = recipeYield is List
      ? recipeYield.map((e) => e.toString()).join(' ')
      : recipeYield.toString();
  final match = RegExp(r'\d+').firstMatch(text);
  return int.tryParse(match?.group(0) ?? '') ?? 0;
}

List<Map<String, dynamic>> _extractIngredients(dynamic ingredientNode) {
  final out = <Map<String, dynamic>>[];
  if (ingredientNode is! List) return out;
  for (final raw in ingredientNode) {
    final parsed = _parseIngredientLine(_decodeHtmlEntities(raw.toString()));
    if ((parsed['name']?.toString().trim().isEmpty ?? true)) continue;
    out.add(parsed);
  }
  return out;
}

Map<String, dynamic> _parseIngredientLine(String input) {
  var line = input.trim();
  if (line.isEmpty) {
    return const <String, dynamic>{
      'name': '',
      'amount': 0,
      'unit': '',
      'category': 'other',
      'qualitative': true,
    };
  }
  line = line
      .replaceFirst(RegExp(r'^[\-•\*\s]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ');
  final m = RegExp(r'^([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s+(.+)$').firstMatch(line);
  if (m != null) {
    final amount = _parseAmountToken(m.group(1)!.trim());
    if (amount != null) {
      final split = _splitUnitAndName(m.group(2)!.trim());
      return <String, dynamic>{
        'name': split.name,
        'amount': amount,
        'unit': split.unit,
        'category': 'other',
      };
    }
  }
  return <String, dynamic>{
    'name': line,
    'amount': 0,
    'unit': '',
    'category': 'other',
    'qualitative': true,
  };
}

({String unit, String name}) _splitUnitAndName(String rest) {
  final cleaned = rest.trim();
  if (cleaned.isEmpty) return (unit: '', name: '');
  const knownUnits = <String>{
    'tsp',
    'teaspoon',
    'teaspoons',
    'tbsp',
    'tablespoon',
    'tablespoons',
    'cup',
    'cups',
    'oz',
    'ounce',
    'ounces',
    'lb',
    'pound',
    'pounds',
    'g',
    'gram',
    'grams',
    'kg',
    'ml',
    'l',
    'clove',
    'cloves',
    'can',
    'cans',
    'package',
    'packages',
    'slice',
    'slices',
    'piece',
    'pieces',
  };
  final tokens = cleaned.split(' ');
  if (tokens.isEmpty) return (unit: '', name: cleaned);
  final first = tokens.first.toLowerCase();
  if (knownUnits.contains(first)) {
    final name = tokens.skip(1).join(' ').trim();
    if (name.isNotEmpty) return (unit: _shortUnit(tokens.first), name: name);
  }
  return (unit: '', name: cleaned);
}

String _shortUnit(String raw) {
  final u = raw.trim().toLowerCase();
  const map = <String, String>{
    'teaspoon': 'tsp',
    'teaspoons': 'tsp',
    'tablespoon': 'tbsp',
    'tablespoons': 'tbsp',
    'ounce': 'oz',
    'ounces': 'oz',
    'pound': 'lb',
    'pounds': 'lb',
    'grams': 'g',
    'gram': 'g',
    'cups': 'cup',
    'cloves': 'clove',
    'cans': 'can',
    'packages': 'package',
    'slices': 'slice',
    'pieces': 'piece',
  };
  return map[u] ?? u;
}

double? _parseAmountToken(String token) {
  var normalized = token.trim();
  if (normalized.isEmpty) return null;
  normalized = normalized
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.contains('-')) {
    final parts = normalized.split('-').map((e) => e.trim()).toList();
    for (final p in parts) {
      final parsed = double.tryParse(p);
      if (parsed != null) return parsed;
    }
  }
  final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(normalized);
  if (frac != null) {
    final a = double.tryParse(frac.group(1)!);
    final b = double.tryParse(frac.group(2)!);
    if (a != null && b != null && b != 0) return a / b;
  }
  return double.tryParse(normalized.replaceAll(',', ''));
}

List<String> _extractInstructions(dynamic instructionsNode) {
  final out = <String>[];
  if (instructionsNode is String) {
    final text = _decodeHtmlEntities(instructionsNode.trim());
    if (text.isNotEmpty) out.add(text);
    return out;
  }
  if (instructionsNode is List) {
    var i = 1;
    for (final step in instructionsNode) {
      if (step is String) {
        final text = _decodeHtmlEntities(step.trim());
        if (text.isEmpty) continue;
        out.add('$i. $text');
        i++;
      } else if (step is Map<String, dynamic>) {
        final text = _decodeHtmlEntities((step['text']?.toString() ?? '').trim());
        if (text.isEmpty) continue;
        out.add('$i. $text');
        i++;
      }
    }
  }
  return out;
}

Map<String, dynamic> _extractNutrition(dynamic nutritionNode) {
  if (nutritionNode is! Map<String, dynamic>) {
    return const <String, dynamic>{
      'calories': 0,
      'protein': 0,
      'fat': 0,
      'carbs': 0,
      'fiber': 0,
      'sugar': 0,
    };
  }
  return <String, dynamic>{
    'calories': _numberFromAny(nutritionNode['calories']).round(),
    'protein': _numberFromAny(nutritionNode['proteinContent']),
    'fat': _numberFromAny(nutritionNode['fatContent']),
    'carbs': _numberFromAny(nutritionNode['carbohydrateContent']),
    'fiber': _numberFromAny(nutritionNode['fiberContent']),
    'sugar': _numberFromAny(nutritionNode['sugarContent']),
  };
}

double _numberFromAny(dynamic raw) {
  final text = raw?.toString() ?? '';
  final match = RegExp(r'[-+]?[0-9]*\.?[0-9]+').firstMatch(text);
  if (match == null) return 0;
  return double.tryParse(match.group(0) ?? '') ?? 0;
}

int _durationToMinutes(String? duration) {
  if (duration == null || duration.isEmpty) return 0;
  final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?$').firstMatch(duration);
  if (match == null) return 0;
  final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
  final mins = int.tryParse(match.group(2) ?? '0') ?? 0;
  return (hours * 60) + mins;
}

String _slugFromUrl(String url) {
  final path = Uri.parse(url).path;
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  return segs.isEmpty ? url : segs.last;
}

String? _recipeIdFromUrl(String url) {
  final slug = _slugFromUrl(url);
  final m = RegExp(r'-(\d+)$').firstMatch(slug);
  return m?.group(1);
}

String _titleFromSlug(String slug) {
  return slug
      .split('-')
      .where((s) => s.isNotEmpty)
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join(' ');
}

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll('&#215;', '×')
      .replaceAll('&times;', '×')
      .replaceAll('&#8217;', "'")
      .replaceAll('&#8216;', "'")
      .replaceAll('&#8220;', '"')
      .replaceAll('&#8221;', '"')
      .replaceAll('&#8211;', '-')
      .replaceAll('&#8212;', '-')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}

String? _env(String key) {
  final value = Platform.environment[key]?.trim();
  if (value == null || value.isEmpty || value.startsWith('YOUR_')) return null;
  return value;
}
