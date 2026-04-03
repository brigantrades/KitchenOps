import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:plateplan/core/strings/html_entities.dart';

/// Prefix for stored web-import payloads (Re-parse and retry).
const String kWebRecipeImportPayloadPrefix = '__LECKERLY_WEB_RECIPE_V1__';

const int _kMaxPageChars = 100000;

/// Result of [parseRecipePageUrl].
class RecipePageUrlParseResult {
  const RecipePageUrlParseResult.ok(this.uri) : errorMessage = null;
  const RecipePageUrlParseResult.error(this.errorMessage) : uri = null;

  final Uri? uri;
  final String? errorMessage;

  bool get isOk => uri != null;
}

/// Normalizes and validates a user-pasted URL for recipe import.
RecipePageUrlParseResult parseRecipePageUrl(String raw) {
  final t = raw.trim();
  if (t.isEmpty) {
    return const RecipePageUrlParseResult.error('Enter a recipe URL.');
  }
  var toParse = t;
  if (!toParse.contains('://')) {
    toParse = 'https://$toParse';
  }
  final uri = Uri.tryParse(toParse);
  if (uri == null || uri.host.isEmpty) {
    return const RecipePageUrlParseResult.error('That doesn’t look like a valid URL.');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return const RecipePageUrlParseResult.error('Only http and https links are supported.');
  }
  if (uri.scheme == 'http') {
    return RecipePageUrlParseResult.ok(
      uri.replace(scheme: 'https'),
    );
  }
  return RecipePageUrlParseResult.ok(uri);
}

/// Fetches HTML and returns plain text for Gemini (capped).
Future<RecipePageFetchResult> fetchRecipePagePlainText(Uri uri) async {
  final client = http.Client();
  try {
    final response = await client
        .get(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (compatible; Leckerly/1.0; +https://leckerly.app) AppleWebKit/537.36',
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return RecipePageFetchResult.error(
        'Could not load the page (HTTP ${response.statusCode}).',
      );
    }
    final body = response.body;
    if (body.trim().isEmpty) {
      return const RecipePageFetchResult.error(
        'The page returned no text. Some sites need JavaScript; try copying the recipe text manually.',
      );
    }
    var plain = htmlToPlainRecipeText(body);
    if (plain.length > _kMaxPageChars) {
      plain = plain.substring(0, _kMaxPageChars);
    }
    if (plain.trim().length < 80) {
      return const RecipePageFetchResult.error(
        'Not enough text on the page. The recipe may load only in a browser, or the page may be paywalled.',
      );
    }
    final resolved = response.request?.url ?? uri;
    final heroImageUrl = extractRecipeImageUrlFromHtml(body);
    return RecipePageFetchResult.ok(
      canonicalUrl: resolved.toString(),
      plainText: plain,
      heroImageUrl: heroImageUrl,
    );
  } catch (_) {
    return const RecipePageFetchResult.error(
      'Could not load the page. Check your connection and try again.',
    );
  } finally {
    client.close();
  }
}

/// Strip tags and boilerplate noise from HTML.
///
/// Inserts newlines at block boundaries so recipe import can find sections like
/// "Ingredients", "Instructions", and "Orange Sauce" on separate lines (required
/// by [supplementWebImportJsonWithEmbeddedSauceFromPlainText]).
String htmlToPlainRecipeText(String html) {
  var s = html
      .replaceAll(
        RegExp(
          r'<script\b[^<]*(?:(?!</script>)<[^<]*)*</script>',
          caseSensitive: false,
          dotAll: true,
        ),
        '\n',
      )
      .replaceAll(
        RegExp(
          r'<style\b[^<]*(?:(?!</style>)<[^<]*)*</style>',
          caseSensitive: false,
          dotAll: true,
        ),
        '\n',
      );
  // Block boundaries → line breaks before stripping remaining tags.
  s = s
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(
          r'</\s*(p|div|h[1-6]|li|tr|section|article|header|footer|ul|ol)\s*>',
          caseSensitive: false,
        ),
        '\n',
      )
      .replaceAll(
        RegExp(
          r'<\s*(p|div|h[1-6]|li|tr|section|article)\b[^>]*>',
          caseSensitive: false,
        ),
        '\n',
      );
  s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
  s = decodeHtmlEntities(s);
  // Collapse horizontal space per line; keep newlines.
  final lines = s.split(RegExp(r'\r?\n'));
  final buf = StringBuffer();
  for (final raw in lines) {
    final line = raw.replaceAll(RegExp(r'[ \t\f\v]+'), ' ').trim();
    if (line.isEmpty) continue;
    if (buf.isNotEmpty) buf.writeln();
    buf.write(line);
  }
  return buf.toString().trim();
}

class RecipePageFetchResult {
  const RecipePageFetchResult.ok({
    required this.canonicalUrl,
    required this.plainText,
    this.heroImageUrl,
  }) : errorMessage = null;

  const RecipePageFetchResult.error(this.errorMessage)
      : canonicalUrl = null,
        plainText = null,
        heroImageUrl = null;

  final String? canonicalUrl;
  final String? plainText;
  /// From JSON-LD [Recipe.image] or `og:image` in raw HTML (Gemini never sees this).
  final String? heroImageUrl;
  final String? errorMessage;

  bool get isOk => canonicalUrl != null && plainText != null;
}

/// Best-effort hero image from page HTML before scripts are stripped for Gemini.
///
/// Tries `application/ld+json` [Recipe] nodes first, then Open Graph `og:image`.
String? extractRecipeImageUrlFromHtml(String html) {
  final fromLd = _recipeImageUrlFromAllJsonLd(html);
  if (fromLd != null && fromLd.isNotEmpty) return fromLd;
  return _ogImageFromHtml(html);
}

String? _recipeImageUrlFromAllJsonLd(String html) {
  // Match common variants (Food.com uses type="application/ld+json").
  final scripts = RegExp(
    r'<script[^>]*type\s*=\s*"application/ld\+json"[^>]*>([\s\S]*?)</script>',
    caseSensitive: false,
  ).allMatches(html);
  for (final match in scripts) {
    final raw = match.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;
    try {
      final decoded = jsonDecode(raw);
      final url = _recipeImageUrlFromLdNode(decoded);
      if (url != null && url.isNotEmpty) return url;
    } catch (_) {}
  }
  return null;
}

String? _recipeImageUrlFromLdNode(dynamic node) {
  if (node is Map<String, dynamic>) {
    final type = node['@type'];
    final isRecipe = type == 'Recipe' ||
        (type is List && type.any((t) => t.toString() == 'Recipe'));
    if (isRecipe) {
      return _coerceSchemaImageToUrl(node['image']);
    }
    if (node['@graph'] is List) {
      for (final child in node['@graph'] as List) {
        final url = _recipeImageUrlFromLdNode(child);
        if (url != null && url.isNotEmpty) return url;
      }
    }
  } else if (node is List) {
    for (final child in node) {
      final url = _recipeImageUrlFromLdNode(child);
      if (url != null && url.isNotEmpty) return url;
    }
  }
  return null;
}

String? _coerceSchemaImageToUrl(dynamic imageNode) {
  if (imageNode == null) return null;
  if (imageNode is String) {
    final s = imageNode.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http')) return s;
    return null;
  }
  if (imageNode is List && imageNode.isNotEmpty) {
    for (final item in imageNode) {
      final u = _coerceSchemaImageToUrl(item);
      if (u != null) return u;
    }
    return null;
  }
  if (imageNode is Map) {
    final m = Map<String, dynamic>.from(imageNode);
    for (final key in <String>['url', 'contentUrl', 'thumbnailUrl']) {
      final v = m[key]?.toString().trim();
      if (v != null && v.startsWith('http')) return v;
    }
  }
  return null;
}

String? _ogImageFromHtml(String html) {
  final patterns = <RegExp>[
    RegExp(
      r'<meta\s+property="og:image"\s+content="([^"]+)"',
      caseSensitive: false,
    ),
    RegExp(
      r"<meta\s+property='og:image'\s+content='([^']+)'",
      caseSensitive: false,
    ),
    RegExp(
      r'<meta\s+content="([^"]+)"\s+property="og:image"',
      caseSensitive: false,
    ),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(html);
    if (m != null) {
      final raw = m.group(1)?.trim();
      if (raw != null &&
          raw.isNotEmpty &&
          (raw.startsWith('http://') || raw.startsWith('https://'))) {
        return decodeHtmlEntities(raw);
      }
    }
  }
  return null;
}

/// Decoded payload for web import (Re-parse / retry).
class WebRecipeImportPayload {
  const WebRecipeImportPayload({
    required this.canonicalUrl,
    required this.pageText,
    this.notes,
  });

  final String canonicalUrl;
  final String pageText;
  final String? notes;
}

/// Encodes URL + page text (+ optional user notes) for [ImportRecipePreviewArgs.sourcePayload].
String encodeWebRecipeImportPayload({
  required String canonicalUrl,
  required String pageText,
  String? notes,
}) {
  final buf = StringBuffer()
    ..writeln(kWebRecipeImportPayloadPrefix)
    ..writeln('URL: $canonicalUrl')
    ..writeln('BODY:')
    ..write(pageText);
  final n = notes?.trim();
  if (n != null && n.isNotEmpty) {
    buf.writeln('\nNOTES:');
    buf.write(n);
  }
  return buf.toString();
}

/// Returns null if [raw] is not a web-import payload.
WebRecipeImportPayload? decodeWebRecipeImportPayload(String raw) {
  final lines = raw.split(RegExp(r'\r?\n'));
  if (lines.isEmpty) return null;
  if (lines.first.trim() != kWebRecipeImportPayloadPrefix) return null;
  String? url;
  var bodyStart = -1;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('URL:')) {
      url = line.substring('URL:'.length).trim();
    } else if (line.trim() == 'BODY:') {
      bodyStart = i + 1;
      break;
    }
  }
  if (url == null || url.isEmpty || bodyStart < 0) return null;
  final bodyLines = lines.sublist(bodyStart);
  var notesIdx = -1;
  for (var j = 0; j < bodyLines.length; j++) {
    if (bodyLines[j].trim() == 'NOTES:') {
      notesIdx = j;
      break;
    }
  }
  String? notes;
  final bodyOnly = notesIdx >= 0
      ? bodyLines.sublist(0, notesIdx)
      : bodyLines;
  if (notesIdx >= 0 && notesIdx + 1 < bodyLines.length) {
    notes = bodyLines.sublist(notesIdx + 1).join('\n').trim();
    if (notes.isEmpty) notes = null;
  }
  final pageText = bodyOnly.join('\n').trim();
  if (pageText.isEmpty) return null;
  return WebRecipeImportPayload(
    canonicalUrl: url,
    pageText: pageText,
    notes: notes,
  );
}
