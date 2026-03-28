import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class LunchImportConfig {
  const LunchImportConfig({
    required this.sourcePages,
    required this.csvPath,
    required this.apiPrefix,
    required this.sourceName,
    required this.cuisineTags,
    required this.includeKeywords,
    this.mealType = 'side',
    this.fallbackRecipeUrls = const <String>[],
    this.trustExtractedFromSourceUrls = const <String>[],
    this.restrictRecipeHosts = const <String>[],
  });

  final List<String> sourcePages;
  final String csvPath;
  final String apiPrefix;
  final String sourceName;
  final List<String> cuisineTags;
  final List<String> includeKeywords;
  final String mealType;
  final List<String> fallbackRecipeUrls;

  /// URLs extracted from these list pages are accepted without [includeKeywords]
  /// matching JSON-LD (titles like "BLT" often omit "sandwich").
  final List<String> trustExtractedFromSourceUrls;

  /// If non-empty, only keep discovered URLs whose [Uri.host] matches one of
  /// these (exact or subdomain, e.g. `cookedandloved.com` matches `www.`).
  final List<String> restrictRecipeHosts;
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

Future<void> runLunchImport(List<String> args, LunchImportConfig config) async {
  final supabaseUrl = _env('SUPABASE_URL');
  final serviceRole = _env('SUPABASE_SERVICE_ROLE_KEY');
  final seedUserId = _env('SEED_USER_ID');
  final execute = args.contains('--execute');
  final limit = _parseLimit(args) ?? 25;

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
    final urls = await _discoverUrls(client, config: config, limit: limit);
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
          config: config,
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

    final reviewPath = await _writeReviewCsv(config.csvPath, reviewRows);
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

bool _recipeHostAllowed(String url, List<String> hosts) {
  if (hosts.isEmpty) return true;
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) return false;
  final h = parsed.host.toLowerCase();
  for (final allowed in hosts) {
    final a = allowed.toLowerCase().trim();
    if (a.isEmpty) continue;
    if (h == a) return true;
    if (h.endsWith('.$a')) return true;
  }
  return false;
}

Future<List<String>> _discoverUrls(
  http.Client client, {
  required LunchImportConfig config,
  required int limit,
}) async {
  final keywordSet = config.includeKeywords.map((k) => k.toLowerCase()).toSet();
  final trustSet = config.trustExtractedFromSourceUrls.toSet();
  final trustedFromListPages = <String>{};
  final fromPages = <String>{};

  for (final sourceUrl in config.sourcePages) {
    String? body;
    try {
      final response = await _getWithRetry(client, sourceUrl);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        body = response.body;
      }
    } catch (e) {
      stderr.writeln('Warning: could not fetch listing $sourceUrl: $e');
    }
    var extracted = body != null ? _extractUrls(body, sourceUrl) : <String>{};
    if (extracted.isEmpty) {
      try {
        body = await _fetchPageBodyViaJina(client, sourceUrl);
        extracted = _extractUrls(body, sourceUrl);
        if (extracted.isNotEmpty) {
          stderr.writeln('Listing links resolved via Jina Reader fallback.');
        }
      } catch (e) {
        stderr.writeln('Warning: Jina listing fallback failed for $sourceUrl: $e');
      }
    }
    fromPages.addAll(extracted);
    if (trustSet.contains(sourceUrl)) {
      trustedFromListPages.addAll(extracted);
    }
  }

  if (config.restrictRecipeHosts.isNotEmpty) {
    fromPages.removeWhere((u) => !_recipeHostAllowed(u, config.restrictRecipeHosts));
    trustedFromListPages
        .removeWhere((u) => !_recipeHostAllowed(u, config.restrictRecipeHosts));
  }

  final candidates = <String>{
    ...fromPages,
    ...config.fallbackRecipeUrls,
  };

  // Prefer listicle URLs first (stable order), then fallbacks, then other links.
  final orderedRaw = <String>[
    ...trustedFromListPages.toList()..sort(),
    ...config.fallbackRecipeUrls,
    ...candidates
        .where(
          (u) =>
              !trustedFromListPages.contains(u) &&
              !config.fallbackRecipeUrls.contains(u),
        )
        .toList()
      ..sort(),
  ];
  final ordered = <String>[];
  final seenOrder = <String>{};
  for (final u in orderedRaw) {
    if (seenOrder.add(u)) ordered.add(u);
  }

  final discovered = <String>[];
  for (final url in ordered) {
    if (discovered.length >= limit) break;
    if (config.restrictRecipeHosts.isNotEmpty &&
        !_recipeHostAllowed(url, config.restrictRecipeHosts)) {
      continue;
    }
    final skipKeyword = trustedFromListPages.contains(url);
    try {
      final jsonLd = await _fetchRecipeJsonLd(client, url);
      final haystack = '${jsonLd['name'] ?? ''} ${jsonLd['description'] ?? ''} '
              '${jsonLd['keywords'] ?? ''} ${jsonLd['recipeCuisine'] ?? ''}'
          .toLowerCase();
      if (keywordSet.isNotEmpty &&
          !skipKeyword &&
          !keywordSet.any(haystack.contains)) {
        continue;
      }
      discovered.add(url);
    } catch (_) {
      continue;
    }
  }
  if (discovered.isEmpty) {
    throw Exception(
      'No recipe URLs discovered from source pages. '
      'Listing had ${fromPages.length} candidate links; '
      'none returned usable Recipe JSON-LD. '
      'Ensure curl works for delish.com or network allows https://r.jina.ai.',
    );
  }
  return discovered.take(limit).toList();
}

Set<String> _extractUrls(String html, String sourceUrl) {
  final out = <String>{};
  final abs = RegExp(r'https?://[^\s)]+', caseSensitive: false);
  for (final m in abs.allMatches(html)) {
    final url = (m.group(0) ?? '').replaceAll('&amp;', '&').trim();
    final normalized = _normalizeCandidateUrl(url);
    if (normalized == null) continue;
    if (_looksLikeRecipeUrl(normalized)) out.add(normalized);
  }
  final href = RegExp(r'href\s*=\s*"([^"]+)"', caseSensitive: false);
  for (final m in href.allMatches(html)) {
    final raw = (m.group(1) ?? '').trim();
    if (raw.isEmpty) continue;
    final resolved = Uri.parse(sourceUrl).resolve(raw).toString();
    final normalized = _normalizeCandidateUrl(resolved);
    if (normalized == null) continue;
    if (_looksLikeRecipeUrl(normalized)) out.add(normalized);
  }
  return out;
}

String? _normalizeCandidateUrl(String raw) {
  if (raw.isEmpty) return null;
  var v = raw.trim();
  // Strip common trailing punctuation/leakage from inline scripts/JSON blobs.
  while (v.isNotEmpty &&
      (v.endsWith(',') ||
          v.endsWith(';') ||
          v.endsWith('"') ||
          v.endsWith("'") ||
          v.endsWith('}') ||
          v.endsWith(']'))) {
    v = v.substring(0, v.length - 1);
  }
  final u = Uri.tryParse(v);
  if (u == null || !u.hasScheme || (u.scheme != 'http' && u.scheme != 'https')) {
    return null;
  }
  if (u.host.isEmpty) return null;
  return u.toString();
}

bool _looksLikeRecipeUrl(String url) {
  final lowered = url.toLowerCase();
  if (lowered.contains('/recipes/')) return true;
  if (lowered.contains('recipe')) return true;
  if (lowered.contains('/story/')) return false;
  return false;
}

/// Reader API returns Markdown (and plain URLs) that [_extractUrls] can scan.
/// Works when direct Delish HTML fetch fails (curl missing) or returns no links.
Future<String> _fetchPageBodyViaJina(http.Client client, String url) async {
  final uri = Uri.parse(url);
  final scheme = uri.scheme == 'https' ? 'https' : 'http';
  final jinaPath = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  final jinaUrl = 'https://r.jina.ai/$scheme://${uri.host}$jinaPath';
  final response = await client.get(Uri.parse(jinaUrl));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('Jina Reader failed (${response.statusCode})');
  }
  if (response.body.isEmpty) {
    throw Exception('Jina Reader empty body');
  }
  return response.body;
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
  required LunchImportConfig config,
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
    'servings': servings > 0 ? servings : 2,
    'prep_time': resolvedPrep,
    'cook_time': resolvedCook,
    'meal_type': config.mealType,
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

Future<String> _writeReviewCsv(String path, List<ReviewRow> rows) async {
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

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

String _extractImageUrl(dynamic imageNode) {
  if (imageNode is String) return imageNode;
  if (imageNode is List && imageNode.isNotEmpty) {
    final first = imageNode.first;
    if (first is String) return first;
    if (first is Map<String, dynamic>) return (first['url']?.toString() ?? '').trim();
  }
  if (imageNode is Map<String, dynamic>) return (imageNode['url']?.toString() ?? '').trim();
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

const _browserUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36';

/// Delish (Hearst/Fastly) responses often trigger
/// `ClientException: Failed to parse HTTP, … does not match …` in Dart's
/// HTTP parser; `curl` handles the same responses reliably.
bool _hostNeedsCurlFallback(String url) {
  final h = Uri.parse(url).host.toLowerCase();
  return h == 'www.delish.com' || h == 'delish.com';
}

Future<String> _curlGetBody(String url) async {
  final binaries = <String>['curl'];
  if (Platform.isMacOS || Platform.isLinux) {
    binaries.add('/usr/bin/curl');
  }
  if (Platform.isWindows) {
    binaries.add(r'C:\Windows\System32\curl.exe');
  }
  final tried = <String>{};
  Object? lastErr;
  for (final bin in binaries) {
    if (!tried.add(bin)) continue;
    try {
      final result = await Process.run(
        bin,
        <String>[
          '-sL',
          '--compressed',
          '-A',
          _browserUserAgent,
          url,
        ],
      );
      if (result.exitCode != 0) {
        lastErr = 'curl exit ${result.exitCode}: ${result.stderr}';
        continue;
      }
      final raw = result.stdout;
      if (raw is! List<int>) {
        lastErr = 'curl: unexpected stdout type';
        continue;
      }
      final text = utf8.decode(raw);
      if (text.isEmpty) {
        lastErr = 'curl: empty body';
        continue;
      }
      return text;
    } catch (e) {
      lastErr = e;
    }
  }
  throw Exception('curl failed (tried ${tried.join(", ")}): $lastErr');
}

Future<http.Response> _getWithRetry(http.Client client, String url) async {
  const maxAttempts = 7;
  var backoffMs = 900;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    late http.Response response;
    try {
      if (_hostNeedsCurlFallback(url)) {
        final body = await _curlGetBody(url);
        response = http.Response(body, 200);
      } else {
        response = await client.get(
          Uri.parse(url),
          headers: const <String, String>{'User-Agent': _browserUserAgent},
        );
      }
    } on http.ClientException catch (_) {
      if (!_hostNeedsCurlFallback(url)) rethrow;
      final body = await _curlGetBody(url);
      response = http.Response(body, 200);
    }
    if (response.statusCode != 429) return response;
    if (attempt < maxAttempts) {
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
      backoffMs *= 2;
      continue;
    }
    return response;
  }
  return client.get(
    Uri.parse(url),
    headers: const <String, String>{'User-Agent': _browserUserAgent},
  );
}

String? _env(String key) {
  final value = Platform.environment[key]?.trim();
  if (value == null || value.isEmpty || value.startsWith('YOUR_')) return null;
  return value;
}
