import 'package:http/http.dart' as http;

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
    return RecipePageFetchResult.ok(
      canonicalUrl: resolved.toString(),
      plainText: plain,
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
String htmlToPlainRecipeText(String html) {
  var s = html
      .replaceAll(
        RegExp(
          r'<script\b[^<]*(?:(?!</script>)<[^<]*)*</script>',
          caseSensitive: false,
          dotAll: true,
        ),
        ' ',
      )
      .replaceAll(
        RegExp(
          r'<style\b[^<]*(?:(?!</style>)<[^<]*)*</style>',
          caseSensitive: false,
          dotAll: true,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s;
}

class RecipePageFetchResult {
  const RecipePageFetchResult.ok({
    required this.canonicalUrl,
    required this.plainText,
  }) : errorMessage = null;

  const RecipePageFetchResult.error(this.errorMessage)
      : canonicalUrl = null,
        plainText = null;

  final String? canonicalUrl;
  final String? plainText;
  final String? errorMessage;

  bool get isOk => canonicalUrl != null && plainText != null;
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
