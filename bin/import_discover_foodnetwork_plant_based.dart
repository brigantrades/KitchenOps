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

    final urls = await _discoverPlantBasedUrls(client, limit: limit);
    stdout.writeln('Import target count: ${urls.length}');

    for (final url in urls) {
      stdout.writeln('\n== Processing $url ==');
      try {
        final warnings = <String>[];
        Map<String, dynamic>? jsonLd;
        String? jinaMarkdown;
        try {
          jsonLd = await _fetchRecipeJsonLd(client, url);
        } catch (_) {
          jinaMarkdown = await _fetchRecipeMarkdownViaJina(client, url);
          warnings.add('used_jina_markdown_fallback');
        }
        final payload = jsonLd != null
            ? _toPayload(
                jsonLd: jsonLd,
                sourceUrl: url,
                seedUserId: seedUserId,
                warnings: warnings,
              )
            : _toPayloadFromJinaMarkdown(
                markdown: jinaMarkdown!,
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

Future<List<String>> _discoverPlantBasedUrls(
  http.Client client, {
  required int limit,
}) async {
  const sourcePage =
      'https://www.foodnetwork.com/recipes/photos/plant-based-recipes';
  final urls = <String>{};
  try {
    final res = await _get(client, sourcePage);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      urls.addAll(_extractRecipeUrlsFromPage(res.body));
    }
  } catch (_) {
    // Fall through to curated list.
  }
  if (urls.isEmpty) {
    stdout.writeln(
      'Source page blocked in this environment; using curated URL list fallback.',
    );
    urls.addAll(_curatedPlantBasedRecipeUrls);
  }

  final sorted = urls.toList()..sort();
  final uniqueById = <String, String>{};
  for (final url in sorted) {
    final id = _recipeIdFromUrl(url) ?? _slugFromUrl(url);
    uniqueById.putIfAbsent(id, () => url);
  }

  final selected = uniqueById.values.take(limit).toList();
  if (selected.isEmpty) {
    throw Exception('No Food Network recipe URLs discovered on source page.');
  }
  return selected;
}

const _curatedPlantBasedRecipeUrls = <String>[
  'https://www.foodnetwork.com/recipes/food-network-kitchen/15-minute-tofu-and-vegetable-stir-fry-3676440',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/bbq-pulled-jackfruit-sandwiches-3686824',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/almond-cherry-pepita-bars-3532755',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-cauliflower-mac-and-cheese-3362375',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-black-bean-and-sweet-potato-soup-9424811',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-chickpea-crab-cakes-3364958',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/grilled-bbq-tempeh-steaks-12741409',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/instant-pot-hummus-7997567',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-cream-of-broccoli-soup-3362563',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/baked-chickpea-patties-with-cucumber-and-tahini-4621832',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-wild-rice-stuffed-butternut-squash-3362734',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-lentil-burgers-3362403',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/the-best-gazpacho-8849862',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/healthy-seed-and-oat-crackers-9488558',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/simple-broccoli-stir-fry-3362921',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-cheddar-wheel-7089848',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/moroccan-harissa-roast-cauliflower-3626547',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/chickpea-salad-sandwiches-8811083',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/the-best-lentil-soup-7192365',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-blueberry-muffins-3362193',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-scalloped-potatoes-3362839',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-lentil-chili-9483281',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/the-best-crispy-tofu-8317073',
  'https://www.foodnetwork.com/recipes/green-smoothie-bowl-3414403',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-pulled-pork-sliders-3364735',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-curried-vegetable-chowder-9430495',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/the-best-tempeh-marinade-13019015',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/healthy-cauliflower-rice-3363582',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/spicy-vegan-sloppy-joes-recipe-2120219',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-tofu-and-spinach-scramble-3362219',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-banana-bread-3362239',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-queso-5568072',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/dal-5568066',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/shaved-brussels-sprouts-salad-with-pecans-5455769',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/mushroom-bacon-3364696',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/ratatouille-5658876',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/marinated-white-beans-8649917',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/falafel-6543276',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/kale-pesto-and-white-bean-dip-3538883',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/roasted-cauliflower-steaks-with-raisin-relish-recipe-2112219',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/lentil-mushroom-meatballs-3364782',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-basil-pesto-3362418',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-roasted-garlic-mashed-potatoes-3362287',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-green-bean-casserole-8899263',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/instant-pot-eggplant-masala-with-peas-5471342',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-pinto-bean-breakfast-sausage-3364983',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-spinach-and-mushroom-lasagna-3362768',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/quinoa-with-roasted-butternut-squash-3362573',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-sunflower-seed-tuna-salad-3364563',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-quinoa-cranberry-stuffed-acorn-squash-3363289',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/vegan-stuffing-3363062',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/roasted-okra-and-chickpeas-3362601',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/chickpeas-and-dumplings-12701430',
  'https://www.foodnetwork.com/recipes/food-network-kitchen/ultimate-tempeh-bacon-12741404',
];

Set<String> _extractRecipeUrlsFromPage(String html) {
  final out = <String>{};
  final abs = RegExp(
    r'https://www\.foodnetwork\.com/recipes/[a-z0-9\-/]+-\d+',
    caseSensitive: false,
  );
  for (final m in abs.allMatches(html)) {
    final url = m.group(0)?.trim();
    if (url == null || url.isEmpty) continue;
    out.add(url.toLowerCase());
  }
  return out;
}

Future<Map<String, dynamic>> _fetchRecipeJsonLd(
  http.Client client,
  String url,
) async {
  final response = await _get(client, url);
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

Future<String> _fetchRecipeMarkdownViaJina(http.Client client, String url) async {
  final jinaUrl = 'https://r.jina.ai/http://${Uri.parse(url).host}${Uri.parse(url).path}';
  final response = await _get(client, jinaUrl);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Jina fetch failed (${response.statusCode})');
  }
  return response.body;
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

  final recipeId = _recipeIdFromUrl(sourceUrl);
  final apiId = recipeId != null
      ? 'food_network:$recipeId'
      : 'food_network:${_slugFromUrl(sourceUrl)}';

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
        'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1200&q=80';
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

  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title.isNotEmpty ? title : _titleFromSlug(_slugFromUrl(sourceUrl)),
    'description': description,
    'servings': servings > 0 ? servings : 2,
    'prep_time': resolvedPrep,
    'cook_time': resolvedCook,
    'meal_type': 'sauce',
    'cuisine_tags': const <String>['Plant-Based Power'],
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url': imageUrl,
    'nutrition': nutrition,
    'nutrition_source': 'source_page_jsonld',
    'visibility': 'public',
    'is_public': true,
    'source': 'food_network',
    'source_url': sourceUrl,
    'api_id': apiId,
  };
}

Map<String, dynamic> _toPayloadFromJinaMarkdown({
  required String markdown,
  required String sourceUrl,
  required String seedUserId,
  required List<String> warnings,
}) {
  final title =
      _decodeHtmlEntities(_firstMatch(markdown, r'^Title:\s*(.+)$') ?? '');
  final prepText = _firstMatch(markdown, r'^\*\s+Prep:\s*([^\n]+)$') ?? '';
  final cookText = _firstMatch(markdown, r'^\*\s+Cook:\s*([^\n]+)$') ?? '';
  final totalText = _firstMatch(markdown, r'^\*\s+Total:\s*([^\n]+)$') ?? '';
  final yieldText = _firstMatch(markdown, r'^\*\s+Yield:\s*([^\n]+)$') ?? '';
  final desc = _firstMatch(
        markdown,
        r'Nutrition Info[\s\S]*?\n\n(.*?)\n\n\*\s+\[Pinterest',
        dotAll: true,
      ) ??
      '';
  final ingredients = _extractIngredientsFromJina(markdown, warnings);
  final instructions = _extractDirectionsFromJina(markdown, warnings);
  final nutrition = _extractNutritionFromJina(markdown);
  var imageUrl = _extractImageUrlFromJina(markdown);
  final recipeId = _recipeIdFromUrl(sourceUrl);
  final apiId = recipeId != null
      ? 'food_network:$recipeId'
      : 'food_network:${_slugFromUrl(sourceUrl)}';

  var prep = _humanDurationToMinutes(prepText);
  var cook = _humanDurationToMinutes(cookText);
  final total = _humanDurationToMinutes(totalText);
  if ((prep + cook) == 0 && total > 0) {
    prep = (total * 0.4).round();
    cook = total - prep;
    warnings.add('defaulted_time_from_total');
  } else if ((prep + cook) == 0) {
    cook = 25;
    warnings.add('defaulted_time_constant');
  }

  if (imageUrl.isEmpty) {
    imageUrl =
        'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1200&q=80';
    warnings.add('defaulted_image');
  }

  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title.isNotEmpty ? title : _titleFromSlug(_slugFromUrl(sourceUrl)),
    'description': _decodeHtmlEntities(desc.trim()),
    'servings': _extractServings(yieldText),
    'prep_time': prep,
    'cook_time': cook,
    'meal_type': 'sauce',
    'cuisine_tags': const <String>['Plant-Based Power'],
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url': imageUrl,
    'nutrition': nutrition,
    'nutrition_source': 'source_page_jsonld',
    'visibility': 'public',
    'is_public': true,
    'source': 'food_network',
    'source_url': sourceUrl,
    'api_id': apiId,
  };
}

String _extractImageUrlFromJina(String markdown) {
  // Prefer fullset/staged food photography, ignore nav/editorial avatar assets.
  final candidates = RegExp(
    r'https?://[^)\s]+(?:jpe?g|png|webp)',
    caseSensitive: false,
  ).allMatches(markdown);

  String? fallback;
  for (final m in candidates) {
    final url = (m.group(0) ?? '').trim();
    if (url.isEmpty) continue;
    final lowered = url.toLowerCase();
    if (!lowered.contains('food.fnr.sndimg.com')) continue;
    if (lowered.contains('/editorial/') ||
        lowered.contains('/shows/') ||
        lowered.contains('/talent/') ||
        lowered.contains('/products/') ||
        lowered.contains('/avatars/') ||
        lowered.contains('/plus/profiles/')) {
      continue;
    }
    if (lowered.contains('/fullset/') || lowered.contains('/content/dam/images/food/')) {
      return url;
    }
    fallback ??= url;
  }
  return fallback ?? '';
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
  final path = '${dir.path}/foodnetwork_plant_based_review.csv';
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
  return int.tryParse(match?.group(0) ?? '') ?? 2;
}

List<Map<String, dynamic>> _extractIngredientsFromJina(
  String markdown,
  List<String> warnings,
) {
  final block = _firstMatch(
    markdown,
    r'## Ingredients\n([\s\S]*?)\nGet Ingredients',
    dotAll: true,
  );
  if (block == null || block.trim().isEmpty) {
    warnings.add('defaulted_ingredients_placeholder');
    return <Map<String, dynamic>>[
      const <String, dynamic>{
        'name': 'Ingredients listed on source page',
        'amount': 0,
        'unit': '',
        'category': 'other',
        'qualitative': true,
      }
    ];
  }
  final lines = block
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.startsWith('- [x] '))
      .map((e) => e.replaceFirst('- [x] ', '').trim())
      .where((e) => e.isNotEmpty)
      .toList();
  return lines.map(_parseIngredientLine).toList();
}

List<String> _extractDirectionsFromJina(String markdown, List<String> warnings) {
  final block =
      _firstMatch(markdown, r'## Directions\n([\s\S]*?)\n## Categories:', dotAll: true);
  if (block == null || block.trim().isEmpty) {
    warnings.add('defaulted_instructions_placeholder');
    return <String>[
      '1. Gather ingredients and prep your workspace.',
      '2. Follow source recipe directions and serve.',
    ];
  }
  final out = <String>[];
  for (final line in block.split('\n')) {
    final m = RegExp(r'^\s*(\d+)\.\s+(.*)$').firstMatch(line.trim());
    if (m == null) continue;
    final stepNum = m.group(1)!;
    final text = _decodeHtmlEntities(m.group(2)!.trim());
    if (text.isEmpty) continue;
    out.add('$stepNum. $text');
  }
  if (out.isEmpty) {
    warnings.add('defaulted_instructions_placeholder');
    return <String>[
      '1. Gather ingredients and prep your workspace.',
      '2. Follow source recipe directions and serve.',
    ];
  }
  return out;
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

Map<String, dynamic> _extractNutritionFromJina(String markdown) {
  final line =
      _firstMatch(markdown, r'^\*\s+Nutrition Info\s+(.*)$') ?? '';
  final calories = _numberFromAny(_firstMatch(line, r'Calories\s+(\d+)'));
  final fat = _numberFromAny(_firstMatch(line, r'Total Fat\s+(\d+)'));
  final carbs = _numberFromAny(_firstMatch(line, r'Carbohydrates\s+(\d+)'));
  final fiber = _numberFromAny(_firstMatch(line, r'Dietary Fiber\s+(\d+)'));
  final protein = _numberFromAny(_firstMatch(line, r'Protein\s+(\d+)'));
  final sugar = _numberFromAny(_firstMatch(line, r'Sugar\s+(\d+)'));
  return <String, dynamic>{
    'calories': calories.round(),
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
    'fiber': fiber,
    'sugar': sugar,
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

int _humanDurationToMinutes(String? input) {
  if (input == null || input.trim().isEmpty) return 0;
  final text = input.toLowerCase();
  final h = RegExp(r'(\d+)\s*hr').firstMatch(text);
  final m = RegExp(r'(\d+)\s*min').firstMatch(text);
  final hours = int.tryParse(h?.group(1) ?? '0') ?? 0;
  final mins = int.tryParse(m?.group(1) ?? '0') ?? 0;
  return (hours * 60) + mins;
}

String? _firstMatch(String text, String pattern, {bool dotAll = false}) {
  final m = RegExp(pattern, multiLine: true, dotAll: dotAll).firstMatch(text);
  return m?.group(m.groupCount >= 1 ? 1 : 0);
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
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&rsquo;', "'")
      .replaceAll('&lsquo;', "'")
      .replaceAll('&ldquo;', '"')
      .replaceAll('&rdquo;', '"')
      .replaceAll('&mdash;', '-')
      .replaceAll('&ndash;', '-');
}

Future<http.Response> _get(http.Client client, String url) {
  return client.get(
    Uri.parse(url),
    headers: const <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    },
  );
}

String? _env(String key) {
  final value = Platform.environment[key]?.trim();
  if (value == null || value.isEmpty || value.startsWith('YOUR_')) return null;
  return value;
}
