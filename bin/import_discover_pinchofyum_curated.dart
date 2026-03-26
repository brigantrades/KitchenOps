import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class CuratedRecipe {
  const CuratedRecipe({
    required this.url,
    required this.cuisineTags,
  });

  final String url;
  final List<String> cuisineTags;
}

const curatedQuickEasyDinners = <CuratedRecipe>[
  CuratedRecipe(
    url: 'https://pinchofyum.com/salmon-tacos',
    cuisineTags: <String>['Mexican Fiesta'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/lo-mein',
    cuisineTags: <String>['Asian'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/black-pepper-stir-fried-noodles',
    cuisineTags: <String>['Asian'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/sheet-pan-chicken-pitas',
    cuisineTags: <String>['Mediterranean'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/greek-baked-orzo',
    cuisineTags: <String>['Mediterranean', 'Pasta'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/creamy-garlic-sun-dried-tomato-pasta',
    cuisineTags: <String>['Pasta', 'Comfort Classics'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/coconut-curry-salmon',
    cuisineTags: <String>['Asian'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/butter-chicken-meatballs',
    cuisineTags: <String>['Comfort Classics'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/garlic-butter-baked-penne',
    cuisineTags: <String>['Pasta', 'Comfort Classics'],
  ),
  CuratedRecipe(
    url: 'https://pinchofyum.com/vegan-sheet-pan-fajitas-with-chipotle-queso',
    cuisineTags: <String>[
      'Vegan Delights',
      'Mexican Fiesta',
      'Plant-Based Power'
    ],
  ),
];

Future<void> main(List<String> args) async {
  final supabaseUrl = _env('SUPABASE_URL');
  final serviceRole = _env('SUPABASE_SERVICE_ROLE_KEY');
  final seedUserId = _env('SEED_USER_ID');
  final execute = args.contains('--execute');
  final importPasta = args.contains('--pasta');
  final requestedLimit = _parseLimit(args) ?? 50;

  if (supabaseUrl == null || serviceRole == null || seedUserId == null) {
    stderr.writeln(
      'Missing env vars. Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SEED_USER_ID',
    );
    exitCode = 64;
    return;
  }

  final client = http.Client();
  try {
    var success = 0;
    var failed = 0;

    final items = importPasta
        ? await _discoverPastaRecipes(client, limit: requestedLimit)
        : curatedQuickEasyDinners;

    stdout.writeln('Import target count: ${items.length}');
    for (final item in items) {
      stdout.writeln('\n== Processing ${item.url} ==');
      try {
        final jsonLd = await _fetchRecipeJsonLd(client, item.url);
        final payload = _toPayload(
          jsonLd: jsonLd,
          sourceUrl: item.url,
          seedUserId: seedUserId,
          cuisineTags: item.cuisineTags,
        );

        _validatePayload(payload);
        stdout.writeln('Parsed: ${payload['title']}');

        if (execute) {
          final ok = await _upsertRecipe(
            client: client,
            supabaseUrl: supabaseUrl,
            serviceRole: serviceRole,
            payload: payload,
          );
          if (ok) {
            success += 1;
            stdout.writeln('Upserted successfully.');
          } else {
            failed += 1;
          }
        }
      } catch (error) {
        failed += 1;
        stderr.writeln('Failed for ${item.url}: $error');
      }
    }

    stdout.writeln('');
    if (!execute) {
      stdout.writeln(
        'Dry run complete. Re-run with --execute to import recipes.',
      );
    }
    stdout.writeln('Success: $success, Failed: $failed');
  } finally {
    client.close();
  }
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

Future<List<CuratedRecipe>> _discoverPastaRecipes(
  http.Client client, {
  required int limit,
}) async {
  final discovered = <String>{};
  final listPages = <String>[
    'https://pinchofyum.com/category/recipes/pasta',
    'https://pinchofyum.com/recipes/pasta',
  ];

  // Fetch several paginated pages to accumulate enough links.
  for (final base in listPages) {
    for (var page = 1; page <= 8; page++) {
      if (discovered.length >= limit) break;
      final pageUrl = page == 1 ? base : '$base/page/$page';
      try {
        final response = await client.get(Uri.parse(pageUrl));
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        final urls = _extractPinchPostUrls(response.body);
        discovered.addAll(urls);
      } catch (_) {
        continue;
      }
    }
    if (discovered.length >= limit) break;
  }

  final selected = discovered.take(limit).toList();
  return selected
      .map(
        (url) => const CuratedRecipe(
          url: '',
          cuisineTags: <String>['Pasta'],
        ),
      )
      .toList()
      .asMap()
      .entries
      .map((entry) => CuratedRecipe(
            url: selected[entry.key],
            cuisineTags: entry.value.cuisineTags,
          ))
      .toList();
}

Set<String> _extractPinchPostUrls(String html) {
  final urls = <String>{};
  final regex = RegExp(
    r'href="(https://pinchofyum\.com/[^"#?]+)"',
    caseSensitive: false,
  );
  final blockedPrefixes = <String>[
    '/recipes',
    '/category',
    '/about',
    '/blog',
    '/contact',
    '/privacy-policy',
    '/terms',
    '/resources',
    '/sponsored-content',
    '/media-mentions',
  ];
  const blockedSlugs = <String>{
    'start-here',
    'xmlrpc.php',
    'wp-json',
  };

  for (final m in regex.allMatches(html)) {
    final raw = m.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;
    final uri = Uri.tryParse(raw);
    if (uri == null) continue;
    final path = uri.path;
    if (path.isEmpty || path == '/') continue;
    if (path.split('/').where((s) => s.isNotEmpty).length != 1) continue;
    if (blockedPrefixes.any((prefix) => path.startsWith(prefix))) continue;
    final slug = path.split('/').where((s) => s.isNotEmpty).first;
    if (blockedSlugs.contains(slug)) continue;
    urls.add('https://pinchofyum.com${uri.path}');
  }
  return urls;
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

Map<String, dynamic> _toPayload({
  required Map<String, dynamic> jsonLd,
  required String sourceUrl,
  required String seedUserId,
  required List<String> cuisineTags,
}) {
  final title = _decodeHtmlEntities((jsonLd['name']?.toString() ?? '').trim());
  final description =
      _decodeHtmlEntities((jsonLd['description']?.toString() ?? '').trim());
  final imageUrl = _extractImageUrl(jsonLd['image']);
  final prepMinutes = _durationToMinutes(jsonLd['prepTime']?.toString());
  final cookMinutes = _durationToMinutes(jsonLd['cookTime']?.toString());
  final totalMinutes = _durationToMinutes(jsonLd['totalTime']?.toString());
  final servingInfo = _extractServingInfo(jsonLd['recipeYield']);
  final servings = servingInfo.servings;
  final ingredients = _extractIngredients(jsonLd['recipeIngredient']);
  final instructions = _extractInstructions(jsonLd['recipeInstructions']);
  var nutrition = _extractNutrition(jsonLd['nutrition']);
  final apiId = 'pinch_of_yum:${_slugFromUrl(sourceUrl)}';

  var resolvedPrep = prepMinutes;
  var resolvedCook = cookMinutes;
  if ((resolvedPrep + resolvedCook) == 0 && totalMinutes > 0) {
    resolvedPrep = (totalMinutes * 0.4).round();
    resolvedCook = totalMinutes - resolvedPrep;
  }

  // Some pages expose nutrition in JSON-LD against the upper bound of a yield range
  // (e.g. yield "4-6"), while UI defaults to the lower bound. Normalize to displayed servings.
  if (servingInfo.hadRange &&
      servingInfo.maxServings > servings &&
      servings > 0) {
    final scale = servingInfo.maxServings / servings;
    nutrition = _scaleNutrition(nutrition, scale);
  }

  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title,
    'description': description,
    'servings': servings > 0 ? servings : 2,
    'prep_time': resolvedPrep,
    'cook_time': resolvedCook,
    // DB constraint expects app enum values, not human labels.
    'meal_type': 'sauce',
    'cuisine_tags': cuisineTags,
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url': imageUrl,
    'nutrition': nutrition,
    'nutrition_source': 'source_page_jsonld',
    'visibility': 'public',
    'is_public': true,
    'source': 'pinch_of_yum',
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
  if (instructions.length < 2) throw Exception('instructions too short');
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

typedef ServingInfo = ({int servings, int maxServings, bool hadRange});

ServingInfo _extractServingInfo(dynamic recipeYield) {
  final values = <int>{};
  var hadRange = false;

  void readValue(dynamic v) {
    if (v is num) {
      final n = v.toInt();
      if (n > 0) values.add(n);
      return;
    }
    final text = v?.toString() ?? '';
    final all = RegExp(r'\d+').allMatches(text);
    if (all.isEmpty) return;
    if (all.length >= 2) hadRange = true;
    for (final m in all) {
      final n = int.tryParse(m.group(0) ?? '');
      if (n != null && n > 0) values.add(n);
    }
  }

  if (recipeYield is List) {
    for (final v in recipeYield) {
      readValue(v);
    }
  } else {
    readValue(recipeYield);
  }

  if (values.isEmpty) {
    return (servings: 0, maxServings: 0, hadRange: false);
  }
  final sorted = values.toList()..sort();
  return (
    servings: sorted.first,
    maxServings: sorted.last,
    hadRange: hadRange || (sorted.first != sorted.last),
  );
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

  // Remove leading bullets and normalize spacing.
  line = line
      .replaceFirst(RegExp(r'^[\-•\*\s]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  // Common case: "8 ounces whole wheat penne pasta"
  final m = RegExp(r'^([\d\s.,/\-–—½¼¾⅓⅔⅛⅜⅝⅞]+)\s+(.+)$').firstMatch(line);
  if (m != null) {
    final amountToken = m.group(1)!.trim();
    final rest = m.group(2)!.trim();
    final amount = _parseAmountToken(amountToken);
    if (amount != null) {
      final split = _splitUnitAndName(rest);
      return <String, dynamic>{
        'name': split.name,
        'amount': amount,
        'unit': split.unit,
        'category': 'other',
      };
    }
  }

  // Fallback: keep full phrase as qualitative amount text.
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
    'lbs',
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
    'pinch',
    'dash',
    'head',
    'bunch',
    'sprig',
    'sprigs',
    'stalk',
    'stalks',
  };

  final tokens = cleaned.split(' ');
  if (tokens.isEmpty) return (unit: '', name: cleaned);
  final first = tokens.first.toLowerCase();
  if (knownUnits.contains(first)) {
    final name = tokens.skip(1).join(' ').trim();
    if (name.isNotEmpty) return (unit: _shortUnit(tokens.first), name: name);
  }

  // Handle "16-ounce package pasta" style unit token.
  final hyphenUnit =
      RegExp(r'^(\d+)?-?(ounce|oz|gram|g|pound|lb)s?$', caseSensitive: false)
          .firstMatch(tokens.first);
  if (hyphenUnit != null) {
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
    'kilograms': 'kg',
    'kilogram': 'kg',
    'milliliters': 'ml',
    'milliliter': 'ml',
    'liters': 'l',
    'liter': 'l',
    'cups': 'cup',
    'cloves': 'clove',
    'cans': 'can',
    'packages': 'package',
    'slices': 'slice',
    'pieces': 'piece',
    'sprigs': 'sprig',
    'stalks': 'stalk',
  };
  return map[u] ?? u;
}

double? _parseAmountToken(String token) {
  var normalized = token.trim();
  if (normalized.isEmpty) return null;

  const unicodeFractions = <String, String>{
    '½': ' 1/2',
    '¼': ' 1/4',
    '¾': ' 3/4',
    '⅓': ' 1/3',
    '⅔': ' 2/3',
    '⅛': ' 1/8',
    '⅜': ' 3/8',
    '⅝': ' 5/8',
    '⅞': ' 7/8',
  };
  unicodeFractions.forEach((k, v) {
    normalized = normalized.replaceAll(k, v);
  });
  normalized = normalized
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (normalized.contains('-')) {
    final parts = normalized.split('-').map((e) => e.trim()).toList();
    for (final p in parts) {
      final parsed = _parseSingleAmountToken(p);
      if (parsed != null) return parsed;
    }
  }
  return _parseSingleAmountToken(normalized);
}

double? _parseSingleAmountToken(String token) {
  final t = token.trim();
  if (t.isEmpty) return null;

  final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (mixed != null) {
    final whole = double.tryParse(mixed.group(1)!);
    final a = double.tryParse(mixed.group(2)!);
    final b = double.tryParse(mixed.group(3)!);
    if (whole != null && a != null && b != null && b != 0) {
      return whole + (a / b);
    }
  }

  final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(t);
  if (frac != null) {
    final a = double.tryParse(frac.group(1)!);
    final b = double.tryParse(frac.group(2)!);
    if (a != null && b != null && b != 0) return a / b;
  }

  final commaDecimal = t.contains(',') && !t.contains('.');
  final numeric = commaDecimal ? t.replaceAll(',', '.') : t.replaceAll(',', '');
  return double.tryParse(numeric);
}

List<String> _extractInstructions(dynamic instructionsNode) {
  final out = <String>[];
  if (instructionsNode is String) {
    final cleaned = _decodeHtmlEntities(instructionsNode.trim());
    if (cleaned.isNotEmpty) out.add(cleaned);
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

Map<String, dynamic> _scaleNutrition(Map<String, dynamic> n, double factor) {
  if (factor <= 1) return n;
  final calories = (n['calories'] as num?)?.toDouble() ?? 0;
  final protein = (n['protein'] as num?)?.toDouble() ?? 0;
  final fat = (n['fat'] as num?)?.toDouble() ?? 0;
  final carbs = (n['carbs'] as num?)?.toDouble() ?? 0;
  final fiber = (n['fiber'] as num?)?.toDouble() ?? 0;
  final sugar = (n['sugar'] as num?)?.toDouble() ?? 0;
  return <String, dynamic>{
    'calories': (calories * factor).round(),
    'protein': protein * factor,
    'fat': fat * factor,
    'carbs': carbs * factor,
    'fiber': fiber * factor,
    'sugar': sugar * factor,
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

String? _env(String key) {
  final value = Platform.environment[key]?.trim();
  if (value == null || value.isEmpty || value.startsWith('YOUR_')) return null;
  return value;
}
