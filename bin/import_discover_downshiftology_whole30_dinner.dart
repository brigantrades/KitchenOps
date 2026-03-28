import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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

Future<void> main(List<String> args) async {
  final supabaseUrl = _env('SUPABASE_URL');
  final serviceRole = _env('SUPABASE_SERVICE_ROLE_KEY');
  final seedUserId = _env('SEED_USER_ID');
  final execute = args.contains('--execute');
  final limit = _parseLimit(args) ?? 50;

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

    final urls = await _discoverWhole30DinnerUrls(client, limit: limit);
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
            stdout.writeln('Upserted successfully.');
          } else {
            failed += 1;
          }
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
      stdout.writeln('Dry run complete. Re-run with --execute to import recipes.');
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

Future<List<String>> _discoverWhole30DinnerUrls(
  http.Client client, {
  required int limit,
}) async {
  const roundup = 'https://downshiftology.com/whole30-dinner-recipes/';
  final response = await _getWithRetry(client, roundup);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Could not fetch source page: ${response.statusCode}');
  }

  final urls = _extractDownshiftologyRecipeUrls(response.body);
  final recipeUrls = <String>[];
  for (final url in urls) {
    if (recipeUrls.length >= limit) break;
    try {
      await _fetchRecipeJsonLd(client, url);
      recipeUrls.add(url);
    } catch (_) {
      continue;
    }
  }

  if (recipeUrls.isEmpty) {
    throw Exception('No recipe URLs discovered from source page.');
  }
  return recipeUrls.take(limit).toList();
}

List<String> _extractDownshiftologyRecipeUrls(String html) {
  final out = <String>{};
  final focusBlockMatch = RegExp(
    r'Light and Filling Whole30 Salad Recipes([\s\S]*?)Leave a comment',
    caseSensitive: false,
  ).firstMatch(html);
  final source = focusBlockMatch?.group(1) ?? html;

  final abs = RegExp(
    r'https://downshiftology\.com/recipes/[a-z0-9\-/]+/?',
    caseSensitive: false,
  );
  for (final m in abs.allMatches(source)) {
    final url = (m.group(0) ?? '').trim().toLowerCase();
    if (url.isEmpty) continue;
    if (!_isLikelyRecipeUrl(url)) continue;
    out.add(url.endsWith('/') ? url : '$url/');
  }

  final sorted = out.toList()..sort();
  return sorted;
}

bool _isLikelyRecipeUrl(String url) {
  final uri = Uri.parse(url);
  final path = uri.path.toLowerCase();
  if (!path.startsWith('/recipes/')) return false;
  if (path.contains('/category/')) return false;
  return true;
}

Future<Map<String, dynamic>> _fetchRecipeJsonLd(
  http.Client client,
  String url,
) async {
  final response = await _getWithRetry(client, url);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Fetch failed (${response.statusCode})');
  }
  final html = response.body;
  final scripts = RegExp(
    r'<script[^>]*type\s*=\s*"?application/ld\+json"?[^>]*>([\s\S]*?)</script>',
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

  var resolvedPrep = prepMinutes;
  var resolvedCook = cookMinutes;
  if ((resolvedPrep + resolvedCook) == 0 && totalMinutes > 0) {
    resolvedPrep = (totalMinutes * 0.4).round();
    resolvedCook = totalMinutes - resolvedPrep;
    warnings.add('defaulted_time_from_total');
  } else if ((resolvedPrep + resolvedCook) == 0) {
    resolvedCook = 25;
    warnings.add('defaulted_time_constant');
  }

  if (imageUrl.isEmpty) {
    imageUrl =
        'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=1200&q=80';
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
      },
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

  final slug = _slugFromUrl(sourceUrl);
  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title.isNotEmpty ? title : _titleFromSlug(slug),
    'description': description,
    'servings': servings > 0 ? servings : 2,
    'prep_time': resolvedPrep,
    'cook_time': resolvedCook,
    'meal_type': 'sauce',
    'cuisine_tags': const <String>['Whole30'],
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url': imageUrl,
    'nutrition': nutrition,
    'nutrition_source': 'source_page_jsonld',
    'visibility': 'public',
    'is_public': true,
    'source': 'downshiftology',
    'source_url': sourceUrl,
    'api_id': 'downshiftology_whole30:$slug',
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
  final path = '${dir.path}/downshiftology_whole30_dinner_review.csv';
  final buffer = StringBuffer()..writeln('url,title,api_id,warnings');
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

String _titleFromSlug(String slug) {
  return slug
      .split('-')
      .where((s) => s.isNotEmpty)
      .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
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

Future<http.Response> _getWithRetry(http.Client client, String url) async {
  const maxAttempts = 7;
  var backoffMs = 900;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final response = await client.get(
      Uri.parse(url),
      headers: const <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );
    if (response.statusCode != 429) return response;
    if (attempt < maxAttempts) {
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
      backoffMs *= 2;
      continue;
    }
    return response;
  }
  return client.get(Uri.parse(url));
}

String? _env(String key) {
  final value = Platform.environment[key]?.trim();
  if (value == null || value.isEmpty || value.startsWith('YOUR_')) return null;
  return value;
}
