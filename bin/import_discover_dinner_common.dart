// Shared helpers for curated dinner discover imports (meal_type: sauce).
//
// Run from repo root with env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SEED_USER_ID.
// Dry run (default): parses recipes and writes tmp/dinner_curated_review.csv — no DB writes.
// Add --execute to upsert. Use --per-category=N and --limit=N as needed.
//
// Featured "Quick & Easy Dinners" uses a fixed api_id allowlist in discover_repository.dart;
// new recipes appear in Discover but not that strip unless that list is updated.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

enum DinnerUrlDiscoveryKind {
  /// Generic link harvest + [dinnerLooksLikeRecipeUrl].
  generic,

  /// Downshiftology /recipes/ URLs only.
  downshiftology,

  /// Love and Lemons single-segment recipe slugs (hub pages excluded).
  loveAndLemons,
}

class DinnerImportConfig {
  const DinnerImportConfig({
    required this.sourcePages,
    required this.apiPrefix,
    required this.sourceName,
    required this.cuisineTags,
    required this.includeKeywords,
    required this.discoveryKind,
    this.fallbackRecipeUrls = const <String>[],
  });

  final List<String> sourcePages;
  final String apiPrefix;
  final String sourceName;
  final List<String> cuisineTags;
  final List<String> includeKeywords;
  final DinnerUrlDiscoveryKind discoveryKind;
  final List<String> fallbackRecipeUrls;
}

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

class DinnerImportResult {
  const DinnerImportResult({
    required this.rows,
    required this.successCount,
    required this.failedCount,
  });

  final List<ReviewRow> rows;
  final int successCount;
  final int failedCount;
}

Future<DinnerImportResult> runDinnerBucketImport(
  http.Client client, {
  required List<String> args,
  required DinnerImportConfig config,
  required int limit,
  required String supabaseUrl,
  required String serviceRole,
  required String seedUserId,
}) async {
  final execute = args.contains('--execute');
  final reviewRows = <ReviewRow>[];
  var success = 0;
  var failed = 0;

  final urls = await _discoverUrls(
    client,
    config: config,
    limit: limit,
  );
  stdout.writeln('  URLs to process (${config.apiPrefix}): ${urls.length}');

  for (final url in urls) {
    stdout.writeln('\n  == $url ==');
    try {
      final warnings = <String>[];
      Map<String, dynamic>? jsonLd;
      try {
        jsonLd = await _fetchRecipeJsonLd(client, url);
      } catch (_) {
        final md = await _fetchRecipeMarkdownViaJina(client, url);
        warnings.add('used_jina_markdown_fallback');
        final payload = _toPayloadFromJinaMarkdown(
          markdown: md,
          sourceUrl: url,
          seedUserId: seedUserId,
          warnings: warnings,
          config: config,
        );
        _validatePayload(payload);
        stdout.writeln('  Parsed (Jina): ${payload['title']}');
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
          } else {
            failed += 1;
          }
        }
        continue;
      }

      final payload = _toPayload(
        jsonLd: jsonLd,
        sourceUrl: url,
        seedUserId: seedUserId,
        warnings: warnings,
        config: config,
      );
      _validatePayload(payload);
      stdout.writeln('  Parsed: ${payload['title']}');
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
        } else {
          failed += 1;
        }
      }
    } catch (error) {
      failed += 1;
      stderr.writeln('  Failed: $error');
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

  return DinnerImportResult(
    rows: reviewRows,
    successCount: success,
    failedCount: failed,
  );
}

Future<List<String>> _discoverUrls(
  http.Client client, {
  required DinnerImportConfig config,
  required int limit,
}) async {
  final keywordSet = config.includeKeywords.map((k) => k.toLowerCase()).toSet();
  final candidates = <String>{...config.fallbackRecipeUrls};

  for (final sourceUrl in config.sourcePages) {
    try {
      final response = await _getWithRetry(client, sourceUrl);
      if (response.statusCode < 200 || response.statusCode >= 300) continue;
      switch (config.discoveryKind) {
        case DinnerUrlDiscoveryKind.downshiftology:
          candidates.addAll(
            _extractDownshiftologyRecipeUrls(response.body),
          );
          break;
        case DinnerUrlDiscoveryKind.loveAndLemons:
          candidates.addAll(
            _extractLoveAndLemonsRecipeUrls(response.body),
          );
          break;
        case DinnerUrlDiscoveryKind.generic:
          candidates.addAll(_extractUrls(response.body, sourceUrl));
          break;
      }
    } catch (_) {
      continue;
    }
  }

  final sorted = candidates.toList()..sort();
  final discovered = <String>[];
  for (final url in sorted) {
    if (discovered.length >= limit) break;
    try {
      Map<String, dynamic> jsonLd;
      try {
        jsonLd = await _fetchRecipeJsonLd(client, url);
      } catch (_) {
        await _fetchRecipeMarkdownViaJina(client, url);
        jsonLd = <String, dynamic>{
          'name': _titleGuessFromUrl(url),
          'description': '',
        };
      }
      final haystack =
          '${jsonLd['name'] ?? ''} ${jsonLd['description'] ?? ''} '
                  '${jsonLd['keywords'] ?? ''} ${jsonLd['recipeCuisine'] ?? ''} '
                  '${url.toLowerCase()}'
              .toLowerCase();
      if (keywordSet.isNotEmpty && !keywordSet.any(haystack.contains)) {
        continue;
      }
      discovered.add(url);
    } catch (_) {
      continue;
    }
  }

  if (discovered.isEmpty) {
    throw Exception(
      'No recipe URLs discovered for ${config.apiPrefix}. Check source pages or keywords.',
    );
  }
  return discovered.take(limit).toList();
}

List<String> _extractDownshiftologyRecipeUrls(String html) {
  final out = <String>{};
  final abs = RegExp(
    r'https://downshiftology\.com/recipes/[a-z0-9\-/]+/?',
    caseSensitive: false,
  );
  for (final m in abs.allMatches(html)) {
    var url = (m.group(0) ?? '').trim().toLowerCase();
    if (url.isEmpty) continue;
    if (!_isDownshiftologyRecipeUrl(url)) continue;
    out.add(url.endsWith('/') ? url : '$url/');
  }
  final sorted = out.toList()..sort();
  return sorted;
}

bool _isDownshiftologyRecipeUrl(String url) {
  final uri = Uri.parse(url);
  final path = uri.path.toLowerCase();
  if (!path.startsWith('/recipes/')) return false;
  if (path.contains('/category/')) return false;
  return true;
}

List<String> _extractLoveAndLemonsRecipeUrls(String html) {
  final out = <String>{};
  final abs = RegExp(
    r'https://www\.loveandlemons\.com/[a-z0-9\-]+/?',
    caseSensitive: false,
  );
  for (final m in abs.allMatches(html)) {
    final url = m.group(0)?.trim().toLowerCase();
    if (url == null || url.isEmpty) continue;
    if (!_isLoveAndLemonsRecipePath(url)) continue;
    out.add(url.endsWith('/') ? url : '$url/');
  }
  final rel = RegExp(r'href="(/[^"#? ]+)"', caseSensitive: false);
  for (final m in rel.allMatches(html)) {
    final path = (m.group(1) ?? '').trim().toLowerCase();
    if (!path.startsWith('/')) continue;
    final url = 'https://www.loveandlemons.com$path';
    if (!_isLoveAndLemonsRecipePath(url)) continue;
    out.add(url.endsWith('/') ? url : '$url/');
  }
  final sorted = out.toList()..sort();
  return sorted;
}

bool _isLoveAndLemonsRecipePath(String url) {
  final uri = Uri.parse(url);
  final path = uri.path.toLowerCase();
  if (path.isEmpty || path == '/') return false;
  const blocked = <String>{
    '/vegan-recipes',
    '/soup-recipes',
    '/about',
    '/recipes',
    '/contact',
    '/cookbook',
    '/privacy-policy',
    '/subscribe',
    '/shop',
    '/newsletters',
  };
  if (blocked.contains(path.replaceAll('/', '')) || blocked.contains(path)) {
    return false;
  }
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length != 1) return false;
  final slug = segments.first;
  return slug.length > 3 && !slug.contains('.');
}

Set<String> _extractUrls(String html, String sourceUrl) {
  final out = <String>{};
  final abs = RegExp(r'https?://[^\s)"<>]+', caseSensitive: false);
  for (final m in abs.allMatches(html)) {
    final url = (m.group(0) ?? '').replaceAll('&amp;', '&').trim();
    if (url.isEmpty) continue;
    if (dinnerLooksLikeRecipeUrl(url)) out.add(url);
  }
  final href = RegExp(r'href\s*=\s*"([^"]+)"', caseSensitive: false);
  for (final m in href.allMatches(html)) {
    final raw = (m.group(1) ?? '').trim();
    if (raw.isEmpty) continue;
    final resolved = Uri.parse(sourceUrl).resolve(raw).toString();
    if (dinnerLooksLikeRecipeUrl(resolved)) out.add(resolved);
  }
  return out;
}

bool dinnerLooksLikeRecipeUrl(String url) {
  final lowered = url.toLowerCase();
  if (lowered.contains('facebook.com') ||
      lowered.contains('pinterest.com') ||
      lowered.contains('twitter.com') ||
      lowered.contains('instagram.com') ||
      lowered.contains('tiktok.com')) {
    return false;
  }
  if (lowered.contains('javascript:')) return false;
  if (lowered.contains('downshiftology.com/recipes/')) {
    return _isDownshiftologyRecipeUrl(lowered);
  }
  if (lowered.contains('food52.com/recipes/')) return true;
  if (lowered.contains('177milkstreet.com/recipes/')) return true;
  if (lowered.contains('halfbakedharvest.com/')) {
    final uri = Uri.parse(lowered);
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return false;
    if (segs.first == 'wp-json' || segs.first == 'category') return false;
    return true;
  }
  if (lowered.contains('delish.com/')) {
    return lowered.contains('/recipe') ||
        lowered.contains('/cooking/recipe') ||
        RegExp(r'delish\.com/cooking/[a-z0-9\-]+/[a-z0-9\-]+').hasMatch(lowered);
  }
  if (lowered.contains('loveandlemons.com/')) {
    return _isLoveAndLemonsRecipePath(lowered);
  }
  if (lowered.contains('/recipes/')) return true;
  if (lowered.contains('recipe') && !lowered.contains('/story/')) return true;
  return false;
}

Future<String> _fetchRecipeMarkdownViaJina(http.Client client, String url) async {
  final uri = Uri.parse(url);
  final scheme = uri.scheme == 'https' ? 'https' : 'http';
  final jinaPath = uri.hasQuery
      ? '${uri.path}?${uri.query}'
      : uri.path;
  final jinaUrl = 'https://r.jina.ai/$scheme://${uri.host}$jinaPath';
  final response = await _getWithRetry(client, jinaUrl);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Jina fetch failed (${response.statusCode})');
  }
  return response.body;
}

Map<String, dynamic> _toPayloadFromJinaMarkdown({
  required String markdown,
  required String sourceUrl,
  required String seedUserId,
  required List<String> warnings,
  required DinnerImportConfig config,
}) {
  var title = _firstHeading(markdown) ?? _titleGuessFromUrl(sourceUrl);
  title = _decodeHtmlEntities(title.trim());
  if (title.isEmpty) {
    title = _titleGuessFromUrl(sourceUrl);
    warnings.add('defaulted_title_from_url');
  }

  var ingredients = _ingredientsFromJinaMarkdown(markdown);
  var instructions = _instructionsFromJinaMarkdown(markdown);
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

  final slug = _slugFromUrl(sourceUrl);
  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title,
    'description': '',
    'servings': 4,
    'prep_time': 15,
    'cook_time': 25,
    'meal_type': 'sauce',
    'cuisine_tags': config.cuisineTags,
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url':
        'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=1200&q=80',
    'nutrition': const <String, dynamic>{
      'calories': 0,
      'protein': 0,
      'fat': 0,
      'carbs': 0,
      'fiber': 0,
      'sugar': 0,
    },
    'nutrition_source': 'source_page_jsonld',
    'visibility': 'public',
    'is_public': true,
    'source': config.sourceName,
    'source_url': sourceUrl,
    'api_id': '${config.apiPrefix}:$slug',
  };
}

String? _firstHeading(String markdown) {
  final m = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(markdown);
  return m?.group(1)?.trim();
}

String _titleGuessFromUrl(String url) {
  final slug = _slugFromUrl(url);
  return _titleFromSlug(slug);
}

List<Map<String, dynamic>> _ingredientsFromJinaMarkdown(String markdown) {
  final out = <Map<String, dynamic>>[];
  final lower = markdown.toLowerCase();
  var start = lower.indexOf('ingredients');
  if (start < 0) return out;
  final slice = markdown.substring(start);
  final lines = slice.split('\n');
  var collecting = false;
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('## ') && collecting) break;
    if (t.startsWith('# ') && collecting) break;
    if (t.toLowerCase().contains('ingredient')) {
      collecting = true;
      continue;
    }
    if (!collecting) continue;
    if (t.isEmpty) continue;
    if (t.startsWith('-') || t.startsWith('*') || RegExp(r'^\d+\.').hasMatch(t)) {
      final cleaned = t.replaceFirst(RegExp(r'^[-*]\s*'), '').replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
      if (cleaned.length > 2) {
        out.add(<String, dynamic>{
          'name': cleaned,
          'amount': 0,
          'unit': '',
          'category': 'other',
          'qualitative': true,
        });
      }
    }
  }
  return out;
}

List<String> _instructionsFromJinaMarkdown(String markdown) {
  final out = <String>[];
  final lower = markdown.toLowerCase();
  for (final header in <String>['instructions', 'directions', 'method', 'preparation']) {
    var start = lower.indexOf(header);
    if (start < 0) continue;
    final slice = markdown.substring(start);
    final lines = slice.split('\n');
    var i = 1;
    for (final line in lines.skip(1)) {
      final t = line.trim();
      if (t.startsWith('## ') || (t.startsWith('# ') && out.isNotEmpty)) break;
      if (t.isEmpty) continue;
      final step = t.replaceFirst(RegExp(r'^\d+\.\s*'), '').trim();
      if (step.length > 5) {
        out.add('$i. $step');
        i++;
      }
      if (out.length >= 20) break;
    }
    if (out.isNotEmpty) return out;
  }
  return out;
}

Future<Map<String, dynamic>> _fetchRecipeJsonLd(http.Client client, String url) async {
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
    if (node['@graph'] is List) {
      for (final child in node['@graph'] as List) {
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
  required DinnerImportConfig config,
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

  final slug = _slugFromUrl(sourceUrl);
  return <String, dynamic>{
    'user_id': seedUserId,
    'title': title.isNotEmpty ? title : _titleFromSlug(slug),
    'description': description,
    'servings': servings > 0 ? servings : 4,
    'prep_time': resolvedPrep,
    'cook_time': resolvedCook,
    'meal_type': 'sauce',
    'cuisine_tags': config.cuisineTags,
    'ingredients': ingredients,
    'instructions': instructions,
    'image_url': imageUrl,
    'nutrition': nutrition,
    'nutrition_source': 'source_page_jsonld',
    'visibility': 'public',
    'is_public': true,
    'source': config.sourceName,
    'source_url': sourceUrl,
    'api_id': '${config.apiPrefix}:$slug',
  };
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

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

Future<String> writeDinnerReviewCsv(String path, List<ReviewRow> rows) async {
  final file = File(path);
  file.parent.createSync(recursive: true);
  final b = StringBuffer()..writeln('url,title,api_id,warnings');
  for (final row in rows) {
    b.writeln(
      '${_csv(row.url)},${_csv(row.title)},${_csv(row.apiId)},${_csv(row.warnings.join(';'))}',
    );
  }
  file.writeAsStringSync(b.toString());
  return path;
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
    final line = _decodeHtmlEntities(raw.toString()).trim();
    if (line.isEmpty) continue;
    out.add(<String, dynamic>{
      'name': line,
      'amount': 0,
      'unit': '',
      'category': 'other',
      'qualitative': true,
    });
  }
  return out;
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
      final text = step is String
          ? _decodeHtmlEntities(step.trim())
          : _decodeHtmlEntities((step as Map<String, dynamic>)['text']?.toString() ?? '');
      if (text.trim().isEmpty) continue;
      out.add('$i. ${text.trim()}');
      i++;
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
  return (int.tryParse(match.group(1) ?? '0') ?? 0) * 60 +
      (int.tryParse(match.group(2) ?? '0') ?? 0);
}

String _slugFromUrl(String url) {
  final path = Uri.parse(url).path;
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  return segs.isEmpty ? url : segs.last;
}

String _titleFromSlug(String slug) => slug
    .split('-')
    .where((s) => s.isNotEmpty)
    .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
    .join(' ');

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll('&#215;', '×')
      .replaceAll('&#8217;', "'")
      .replaceAll('&#8216;', "'")
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

int? parsePerCategoryArg(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--per-category' && i + 1 < args.length) {
      return int.tryParse(args[i + 1]);
    }
    if (args[i].startsWith('--per-category=')) {
      return int.tryParse(args[i].split('=').last);
    }
    if (args[i] == '--limit' && i + 1 < args.length) {
      return int.tryParse(args[i + 1]);
    }
    if (args[i].startsWith('--limit=')) {
      return int.tryParse(args[i].split('=').last);
    }
  }
  return null;
}

String? envOrNull(String key) => _env(key);
